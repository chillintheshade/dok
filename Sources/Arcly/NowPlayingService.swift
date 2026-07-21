import Foundation
import AppKit
import IOKit.hidsystem

// MARK: - Now Playing Service

/// 读取系统「正在播放」信息。
///
/// macOS 只向 Apple 签名的进程开放 MediaRemote 元数据，因此本机进程内直读通常拿不到数据。
/// 兜底方案是把一段脚本交给 Swift 工具链（Apple 签名）执行，借它的身份读取。
///
/// 该 helper 是**常驻**的：启动一次后注册 MediaRemote 通知并低成本轮询，
/// 有变化就往 stdout 推一行 JSON。这样切歌是事件驱动的即时更新，
/// 而不是每次刷新都重新启动解释器（那样每次要付 1～3 秒的编译开销）。
class NowPlayingService: ObservableObject {
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool = false
    @Published var hasNowPlaying: Bool = false

    private var isObserving = false
    private var helperProcess: Process?
    private var helperRestartWorkItem: DispatchWorkItem?
    private let helperBuffer = LineBuffer()
    private var upkeepTimer: Timer?
    private var pendingClearWorkItem: DispatchWorkItem?

    /// 发送播放命令后短暂冻结，防止旧状态覆盖乐观更新
    private var playingFrozenUntil: Date = .distantPast
    /// 元数据短暂读空时不立刻清空，避免切歌瞬间闪烁
    private let staleClearDelay: TimeInterval = 2.5

    // MARK: - 音乐 App 配置

    private static let musicBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.tencent.QQMusicMac",
        "com.netease.163music",
        "com.bytedance.music.macos",
        "com.spotify.client",
        "com.apple.QuickTimePlayerX",
        "com.colliderli.iina",
    ]

    private var runningMusicApp: NSRunningApplication? {
        let running = NSWorkspace.shared.runningApplications
        let musicApps = running.filter { app in
            guard let bid = app.bundleIdentifier else { return false }
            return Self.musicBundleIDs.contains(bid)
        }
        return musicApps.first { $0.bundleIdentifier != "com.apple.Music" } ?? musicApps.first
    }

    // MARK: - MediaRemote

    private static let mrHandle: UnsafeMutableRawPointer? = {
        dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)
    }()

    private static var mrRegistered = false

    private static func ensureMRRegistered() {
        guard !mrRegistered, let h = mrHandle,
              let sym = dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications") else { return }
        typealias R = @convention(c) (DispatchQueue) -> Void
        unsafeBitCast(sym, to: R.self)(.main)
        mrRegistered = true
    }

    /// Swift 工具链路径。只认真实存在的安装，不碰 `/usr/bin/swift`
    /// —— 那是个 shim，未安装命令行工具时调用会弹出系统安装对话框。
    private static let helperSwiftURL: URL? = {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/swift",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map {
            URL(fileURLWithPath: $0)
        }
    }()

    private static let helperScriptURL: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Arcly") else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mr_watch.swift")
    }()

    /// 常驻 helper 脚本。与 `Sources/Helper/mr_info.swift` 保持一致。
    private static let helperScript = """
    import Foundation

    let h = dlopen("/System/Library/PrivateFrameworks/MediaRemote.framework/MediaRemote", RTLD_LAZY)!
    typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias GetPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    typealias Register = @convention(c) (DispatchQueue) -> Void
    typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void
    let getInfo = unsafeBitCast(dlsym(h, "MRMediaRemoteGetNowPlayingInfo"), to: GetInfo.self)
    let getPlaying = unsafeBitCast(dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"), to: GetPlaying.self)
    let register = unsafeBitCast(dlsym(h, "MRMediaRemoteRegisterForNowPlayingNotifications"), to: Register.self)
    let getPID = unsafeBitCast(dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID"), to: GetPID.self)

    register(.main)

    // 只在内容真正变化时才输出，避免每秒重复编码封面。
    // 封面必须参与比对：MediaRemote 先更新曲目、封面稍后才到，
    // 只看曲名会导致封面永远慢一首。
    var lastIdentity = "<none>"
    var lastTrackKey = "<none>"
    var lastArtworkID = "none"

    func emit(force: Bool = false) {
        getPID(.main) { pid in
            getPlaying(.main) { playing in
                getInfo(.main) { info in
                    let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                    let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                    let artwork = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                    let artworkID = artwork.map { "\\($0.count)-\\($0.hashValue)" } ?? "none"

                    let trackKey = "\\(pid)|\\(title)|\\(artist)"
                    let identity = "\\(trackKey)|\\(playing)|\\(artworkID)"
                    guard force || identity != lastIdentity else { return }

                    // 曲目刚换而封面数据没动，说明这张封面还属于上一首，先别显示。
                    let trackChanged = trackKey != lastTrackKey
                    let artworkStale = !force && trackChanged && artworkID == lastArtworkID

                    lastIdentity = identity
                    lastTrackKey = trackKey
                    lastArtworkID = artworkID

                    var output: [String: Any] = [
                        "playing": playing,
                        "pid": pid,
                        "title": title,
                        "artist": artist,
                        "artworkStale": artworkStale,
                    ]
                    if let artwork {
                        output["artwork"] = artwork.base64EncodedString()
                    }
                    if let json = try? JSONSerialization.data(withJSONObject: output),
                       let str = String(data: json, encoding: .utf8) {
                        FileHandle.standardOutput.write(Data((str + "\\n").utf8))
                    }

                    if artworkStale {
                        // 封面可能稍后送达；若届时字节仍未变化，
                        // 说明它确实属于当前曲目（例如同专辑连播），补发一次认可它。
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                            emit(force: true)
                        }
                    }
                }
            }
        }
    }

    for name in [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
    ] {
        NotificationCenter.default.addObserver(
            forName: Notification.Name(name), object: nil, queue: .main
        ) { _ in emit() }
    }

    // 部分播放器不稳定发送 MediaRemote 通知。进程常驻后轮询几乎没有成本，
    // 这里作为兜底，保证它们也能在 1 秒内同步。
    Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in emit() }

    emit()
    RunLoop.main.run()
    """

    // MARK: - 生命周期

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        Self.ensureMRRegistered()

        // 进程内直读。在未被系统限制的机器上这一步即可拿到数据。
        directRead()

        startHelper()

        // 轻量巡检：维持 hasNowPlaying（播放器开关），并在直读可用时保持同步。
        // helper 不可用时，这是唯一的更新来源。
        upkeepTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.upkeep()
        }
    }

    func stopObserving() {
        isObserving = false
        upkeepTimer?.invalidate()
        upkeepTimer = nil
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
        stopHelper()
    }

    deinit {
        stopHelper()
        upkeepTimer?.invalidate()
    }

    // MARK: - 媒体控制

    // 通过系统媒体按键发送，不依赖 MediaRemote 命令通道，因此在所有机器上都可用。

    func togglePlayPause() {
        postSystemMediaKey(NX_KEYTYPE_PLAY)
        isPlaying.toggle()
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    func nextTrack() {
        postSystemMediaKey(NX_KEYTYPE_NEXT)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    func previousTrack() {
        postSystemMediaKey(NX_KEYTYPE_PREVIOUS)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    private func postSystemMediaKey(_ keyType: Int32) {
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let keyDownData = (Int(keyType) << 16) | (0xA << 8)
        let keyUpData = (Int(keyType) << 16) | (0xB << 8)
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: keyDownData, data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined, location: .zero, modifierFlags: flags,
            timestamp: 0, windowNumber: 0, context: nil,
            subtype: 8, data1: keyUpData, data2: -1
        )
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }

    /// 轮盘弹出时调用。常驻 helper 已持续同步，这里只补一次直读。
    func refreshForMenuPresentation() {
        directRead()
    }

    // MARK: - 常驻 helper

    private func startHelper() {
        guard helperProcess == nil,
              let swiftURL = Self.helperSwiftURL,
              let scriptURL = Self.helperScriptURL else {
            // 没有可用工具链：保留播放控制，仅无法显示曲目信息。
            return
        }

        do {
            try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("⚠️ 无法写入 now playing helper 脚本: %@", error.localizedDescription)
            return
        }

        helperBuffer.reset()

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = swiftURL
        proc.arguments = [scriptURL.path]
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            let lines = self.helperBuffer.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                for line in lines {
                    self.handleHelperLine(line)
                }
            }
        }

        proc.terminationHandler = { [weak self] _ in
            pipe.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                self?.helperDidTerminate()
            }
        }

        do {
            try proc.run()
            helperProcess = proc
        } catch {
            NSLog("⚠️ 无法启动 now playing helper: %@", error.localizedDescription)
            helperProcess = nil
        }
    }

    private func stopHelper() {
        helperRestartWorkItem?.cancel()
        helperRestartWorkItem = nil
        if let proc = helperProcess, proc.isRunning {
            proc.terminationHandler = nil
            proc.terminate()
        }
        helperProcess = nil
    }

    private func helperDidTerminate() {
        helperProcess = nil
        guard isObserving else { return }

        // helper 意外退出时延迟重启，避免异常情况下反复拉起进程。
        helperRestartWorkItem?.cancel()
        let restart = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving else { return }
            self.helperRestartWorkItem = nil
            self.startHelper()
        }
        helperRestartWorkItem = restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: restart)
    }

    private func handleHelperLine(_ line: Data) {
        guard let snapshot = Self.parseSnapshot(line) else { return }
        apply(snapshot)
    }

    // MARK: - 进程内直读

    /// - Parameter applyEmpty: 读到空结果时是否据此清理。
    ///   仅在没有常驻 helper 时为真 —— helper 在运行时它才是权威数据源，
    ///   直读被系统限制返回的空值不能用来覆盖它。
    private func directRead(applyEmpty: Bool = false) {
        guard let h = Self.mrHandle,
              let infoSym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
              let playingSym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
              let pidSym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID") else {
            return
        }

        Self.ensureMRRegistered()

        typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        typealias GetPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
        typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

        let getInfo = unsafeBitCast(infoSym, to: GetInfo.self)
        let getPlaying = unsafeBitCast(playingSym, to: GetPlaying.self)
        let getPID = unsafeBitCast(pidSym, to: GetPID.self)

        getPID(.main) { [weak self] pid in
            getPlaying(.main) { playing in
                getInfo(.main) { info in
                    let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                    // 直读被系统限制时会返回空。此时不要覆盖 helper 推来的数据。
                    guard !title.isEmpty else {
                        if applyEmpty { self?.scheduleClear() }
                        return
                    }
                    self?.apply(NowPlayingSnapshot(
                        pid: pid,
                        title: title,
                        artist: info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? "",
                        playing: playing,
                        artworkData: info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                    ))
                }
            }
        }
    }

    /// 播放器启停不一定触发 MediaRemote 通知，这里维持占位状态的准确性。
    private func upkeep() {
        // helper 在跑时它是权威来源，直读的空结果不参与清理。
        directRead(applyEmpty: helperProcess == nil)

        // 正在显示曲目时不做任何清理判断。
        // 运行中的播放器只是可选提示：沙箱构建可能枚举不到它，
        // 若据此清空，会在音乐正常播放时误清有效信息。
        guard trackName.isEmpty else { return }

        let playerRunning = runningMusicApp != nil
        if hasNowPlaying != playerRunning {
            hasNowPlaying = playerRunning
        }
    }

    // MARK: - 状态更新

    private struct NowPlayingSnapshot {
        let pid: Int32
        let title: String
        let artist: String
        let playing: Bool
        let artworkData: Data?
        /// 封面仍属于上一首曲目，尚不可信
        var artworkStale: Bool = false
    }

    private static func parseSnapshot(_ data: Data) -> NowPlayingSnapshot? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return NowPlayingSnapshot(
            pid: Int32(json["pid"] as? Int ?? -1),
            title: json["title"] as? String ?? "",
            artist: json["artist"] as? String ?? "",
            playing: json["playing"] as? Bool ?? false,
            artworkData: (json["artwork"] as? String).flatMap { Data(base64Encoded: $0) },
            artworkStale: json["artworkStale"] as? Bool ?? false
        )
    }

    private func apply(_ snapshot: NowPlayingSnapshot) {
        // 报告方不是已知播放器时，说明是系统里其他发声来源，不予采信。
        if snapshot.pid > 0,
           let app = NSRunningApplication(processIdentifier: snapshot.pid),
           let bundleID = app.bundleIdentifier,
           !Self.musicBundleIDs.contains(bundleID),
           let expected = runningMusicApp?.bundleIdentifier,
           bundleID != expected {
            scheduleClear()
            return
        }

        guard !snapshot.title.isEmpty else {
            scheduleClear()
            return
        }

        cancelPendingClear()

        let trackChanged = trackName != snapshot.title
        trackName = snapshot.title
        artistName = snapshot.artist
        hasNowPlaying = true

        // 冻结期内不覆盖 isPlaying，防止命令刚发出就被旧状态回弹
        if Date() > playingFrozenUntil {
            isPlaying = snapshot.playing
        }

        if snapshot.artworkStale {
            // 宁可短暂显示占位图，也不要挂上一首歌的封面。
            // helper 会在封面到达或确认无变化后补发。
            albumArt = nil
        } else if let artData = snapshot.artworkData {
            albumArt = NSImage(data: artData)
        } else if trackChanged {
            albumArt = nil
        }
    }

    /// 元数据读空时延迟清理。切歌瞬间常有短暂空窗，立即清空会导致闪烁。
    private func scheduleClear() {
        guard !trackName.isEmpty else {
            if runningMusicApp == nil {
                clearNowPlaying()
            } else {
                hasNowPlaying = true
            }
            return
        }
        guard pendingClearWorkItem == nil else { return }

        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.pendingClearWorkItem = nil
            self.clearNowPlaying()
        }
        pendingClearWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + staleClearDelay, execute: work)
    }

    private func cancelPendingClear() {
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
    }

    private func clearNowPlaying() {
        cancelPendingClear()
        trackName = ""
        artistName = ""
        albumArt = nil
        if Date() > playingFrozenUntil {
            isPlaying = false
        }
        // 播放器仍在运行时保留占位控制器，让用户仍能操作播放。
        hasNowPlaying = runningMusicApp != nil
    }
}

// MARK: - 行缓冲

/// helper 以「一行一条 JSON」的形式流式输出，管道读到的分片需要按行重组。
private final class LineBuffer {
    private let lock = NSLock()
    private var data = Data()

    func append(_ chunk: Data) -> [Data] {
        lock.lock()
        defer { lock.unlock() }

        data.append(chunk)
        var lines: [Data] = []
        while let newlineIndex = data.firstIndex(of: 0x0A) {
            let line = data.subdata(in: data.startIndex..<newlineIndex)
            data = data.subdata(in: data.index(after: newlineIndex)..<data.endIndex)
            if !line.isEmpty { lines.append(line) }
        }
        return lines
    }

    func reset() {
        lock.lock()
        data.removeAll()
        lock.unlock()
    }
}
