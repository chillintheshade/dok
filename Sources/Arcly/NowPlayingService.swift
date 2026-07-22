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
    @Published private(set) var duration: TimeInterval? = nil
    @Published private(set) var elapsedTime: TimeInterval? = nil
    @Published private(set) var progressTimestamp: Date? = nil
    @Published private(set) var playbackRate: Double? = nil
    @Published private(set) var canSeek: Bool = false
    var recentMusicAppBundleIdentifiers: (() -> [String])?

    private var isObserving = false
    private var helperProcess: Process?
    private var seekProcesses: [Process] = []
    private var playbackCommandProcesses: [Process] = []
    private var helperRestartWorkItem: DispatchWorkItem?
    private var helperStartDate: Date = .distantPast
    private let helperBuffer = LineBuffer()
    private var upkeepTimer: Timer?
    private var pendingClearWorkItem: DispatchWorkItem?

    /// 可用的 helper 后端，按优先级排列；快速失败的后端会被移出队列。
    private var backendQueue: [HelperBackend] = []
    private var activeBackend: HelperBackend?
    private var currentSessionBundleIdentifier: String?
    private var pendingPlaybackIntent: PendingPlaybackIntent?
    private var pendingPlaybackIntentExpirationWorkItem: DispatchWorkItem?
    private let playbackIntentLifetime: TimeInterval = 12

    /// 封面归属追踪：检测"曲目换了、封面还是上一首的"这种滞后。
    private var lastAppliedTrackKey: String = ""
    private var lastAppliedArtworkFingerprint: String?
    private var artworkSettleWorkItem: DispatchWorkItem?

    /// 发送播放命令后短暂冻结，防止旧状态覆盖乐观更新
    private var playingFrozenUntil: Date = .distantPast
    /// seek 后短暂保留乐观进度，避免 helper 尚未更新的旧采样点把进度拉回去。
    private var progressFrozenUntil: Date = .distantPast
    /// 视图实际显示过的播放位置。helper 的轻微滞后采样不得让它向后跳。
    private var lastDisplayedElapsed: TimeInterval?
    private var lastDisplayedAt: Date?
    private let minorProgressRegressionTolerance: TimeInterval = 1.5
    /// 元数据短暂读空时不立刻清空，避免切歌瞬间闪烁
    private let staleClearDelay: TimeInterval = 2.5

    private struct PendingPlaybackIntent {
        let id = UUID()
        let targetBundleIdentifier: String
        let expiresAt: Date
    }

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

    private var runningMusicApps: [NSRunningApplication] {
        NSWorkspace.shared.runningApplications.filter { app in
            guard let bid = app.bundleIdentifier else { return false }
            return Self.musicBundleIDs.contains(bid) && !app.isTerminated
        }
    }

    private var runningMusicApp: NSRunningApplication? {
        let musicApps = runningMusicApps
        return musicApps.first { $0.bundleIdentifier != "com.apple.Music" } ?? musicApps.first
    }

    private var preferredRunningMusicApp: NSRunningApplication? {
        let musicApps = runningMusicApps
        if let currentSessionBundleIdentifier,
           let owner = musicApps.first(where: {
               $0.bundleIdentifier == currentSessionBundleIdentifier
           }) {
            return owner
        }
        for bundleIdentifier in recentMusicAppBundleIdentifiers?() ?? [] {
            if let recent = musicApps.first(where: { $0.bundleIdentifier == bundleIdentifier }) {
                return recent
            }
        }
        return runningMusicApp
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

    // MARK: - Helper 后端

    /// 读取"正在播放"信息的两条路，按优先级排列：
    ///
    /// 1. `perlAdapter` —— 打包在 App 里的 MediaRemoteAdapter.framework（BSD-3，
    ///    见 Vendor/），由系统自带的 `/usr/bin/perl`（Apple 签名，被系统视作
    ///    `com.apple.perl`）加载运行。所有 Mac 都可用，无需任何开发工具。
    /// 2. `swiftToolchain` —— 旧方案：把脚本交给 Swift 工具链解释执行。
    ///    仅在装有 Xcode/CLT 的机器上可用，作为 perl 路不通时的兜底。
    private enum HelperBackend: Equatable {
        case perlAdapter
        case swiftToolchain
    }

    private static let perlURL: URL? = {
        let path = "/usr/bin/perl"
        return FileManager.default.isExecutableFile(atPath: path)
            ? URL(fileURLWithPath: path) : nil
    }()

    private static let adapterScriptURL: URL? =
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")

    private static let adapterFrameworkURL: URL? = {
        guard let url = Bundle.main.privateFrameworksURL?
            .appendingPathComponent("MediaRemoteAdapter.framework"),
            FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        return url
    }()

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

    private static func availableBackends() -> [HelperBackend] {
        var result: [HelperBackend] = []
        if perlURL != nil, adapterScriptURL != nil, adapterFrameworkURL != nil {
            result.append(.perlAdapter)
        }
        if helperSwiftURL != nil, helperScriptURL != nil {
            result.append(.swiftToolchain)
        }
        return result
    }

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

        backendQueue = Self.availableBackends()
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
        artworkSettleWorkItem?.cancel()
        artworkSettleWorkItem = nil
        cancelPendingPlaybackIntent()
        stopHelper()
    }

    deinit {
        pendingPlaybackIntentExpirationWorkItem?.cancel()
        stopHelper()
        upkeepTimer?.invalidate()
    }

    // MARK: - 媒体控制

    func togglePlayPause() {
        guard !trackName.isEmpty else {
            armPendingPlaybackIntent()
            activatePreferredRunningMusicApp()
            return
        }
        cancelPendingPlaybackIntent()
        routePlaybackCommand(adapterCommand: 2, fallbackMediaKey: NX_KEYTYPE_PLAY)
        isPlaying.toggle()
        resetDisplayedProgressTracking()
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    func nextTrack() {
        cancelPendingPlaybackIntent()
        guard !trackName.isEmpty else { return }
        routePlaybackCommand(adapterCommand: 4, fallbackMediaKey: NX_KEYTYPE_NEXT)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    func previousTrack() {
        cancelPendingPlaybackIntent()
        guard !trackName.isEmpty else { return }
        routePlaybackCommand(adapterCommand: 5, fallbackMediaKey: NX_KEYTYPE_PREVIOUS)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
    }

    private func routePlaybackCommand(adapterCommand: Int, fallbackMediaKey: Int32) {
        if !sendAdapterPlaybackCommand(adapterCommand) {
            postSystemMediaKey(fallbackMediaKey)
        }
    }

    private func sendAdapterPlaybackCommand(_ command: Int) -> Bool {
        guard activeBackend == .perlAdapter,
              let perl = Self.perlURL,
              let script = Self.adapterScriptURL,
              let framework = Self.adapterFrameworkURL else { return false }

        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "send", String(command)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                self?.playbackCommandProcesses.removeAll { $0 === finishedProcess }
            }
        }

        do {
            try process.run()
            playbackCommandProcesses.append(process)
            return true
        } catch {
            NSLog("⚠️ 无法发送 MediaRemote 播放命令: %@", error.localizedDescription)
            return false
        }
    }

    private func activatePreferredRunningMusicApp() {
        guard let application = preferredRunningMusicApp else { return }
        if application.activate(options: [.activateAllWindows]) { return }
        guard let bundleURL = application.bundleURL else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.openApplication(
            at: bundleURL,
            configuration: configuration,
            completionHandler: nil
        )
    }

    private func armPendingPlaybackIntent() {
        cancelPendingPlaybackIntent()
        guard let targetBundleIdentifier = preferredRunningMusicApp?.bundleIdentifier else { return }

        let intent = PendingPlaybackIntent(
            targetBundleIdentifier: targetBundleIdentifier,
            expiresAt: Date().addingTimeInterval(playbackIntentLifetime)
        )
        pendingPlaybackIntent = intent

        let expiration = DispatchWorkItem { [weak self] in
            guard let self,
                  self.pendingPlaybackIntent?.id == intent.id else { return }
            self.cancelPendingPlaybackIntent()
        }
        pendingPlaybackIntentExpirationWorkItem = expiration
        DispatchQueue.main.asyncAfter(
            deadline: .now() + playbackIntentLifetime,
            execute: expiration
        )
    }

    private func cancelPendingPlaybackIntent() {
        pendingPlaybackIntentExpirationWorkItem?.cancel()
        pendingPlaybackIntentExpirationWorkItem = nil
        pendingPlaybackIntent = nil
    }

    private func fulfillPendingPlaybackIntent(
        using snapshot: NowPlayingSnapshot,
        reportedBundleIdentifier: String?
    ) {
        guard let intent = pendingPlaybackIntent else { return }
        guard intent.expiresAt > Date() else {
            cancelPendingPlaybackIntent()
            return
        }
        guard trackName.isEmpty || trackName == snapshot.title else {
            cancelPendingPlaybackIntent()
            return
        }
        guard reportedBundleIdentifier == intent.targetBundleIdentifier else { return }
        guard !snapshot.title.isEmpty || snapshot.pid > 0 else { return }

        // Consume before sending. Consecutive helper payloads can never send twice.
        cancelPendingPlaybackIntent()
        guard !snapshot.playing else { return }
        _ = sendAdapterPlaybackCommand(2)
    }

    /// 使用 perl adapter 的一次性命令跳转播放位置。Swift 兜底后端没有命令通道。
    func seek(to seconds: TimeInterval) {
        cancelPendingPlaybackIntent()
        guard activeBackend == .perlAdapter,
              canSeek,
              let duration, duration > 0,
              let perl = Self.perlURL,
              let script = Self.adapterScriptURL,
              let framework = Self.adapterFrameworkURL else { return }

        let target = min(max(seconds, 0), duration)
        let microseconds = Int64((target * 1_000_000).rounded())
        let process = Process()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "seek", String(microseconds)]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.terminationHandler = { [weak self] finishedProcess in
            DispatchQueue.main.async {
                self?.seekProcesses.removeAll { $0 === finishedProcess }
            }
        }

        do {
            try process.run()
            seekProcesses.append(process)
            let optimisticTimestamp = Date()
            elapsedTime = target
            progressTimestamp = optimisticTimestamp
            if playbackRate == nil {
                playbackRate = isPlaying ? 1 : 0
            }
            resetDisplayedProgress(to: target, at: optimisticTimestamp)
            progressFrozenUntil = Date().addingTimeInterval(1.2)
        } catch {
            NSLog("⚠️ 无法发送 seek 命令: %@", error.localizedDescription)
        }
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
        guard helperProcess == nil else { return }
        guard let backend = backendQueue.first else {
            // 没有可用后端：保留播放控制，仅无法显示曲目信息。
            return
        }
        launchHelper(backend)
    }

    private func launchHelper(_ backend: HelperBackend) {
        let executable: URL
        let arguments: [String]

        switch backend {
        case .perlAdapter:
            guard let perl = Self.perlURL,
                  let script = Self.adapterScriptURL,
                  let framework = Self.adapterFrameworkURL else { return }
            executable = perl
            // --no-diff：每行都是完整快照，解析无需维护增量合并状态。
            arguments = [script.path, framework.path, "stream", "--no-diff"]

        case .swiftToolchain:
            guard let swiftURL = Self.helperSwiftURL,
                  let scriptURL = Self.helperScriptURL else { return }
            do {
                try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
            } catch {
                NSLog("⚠️ 无法写入 now playing helper 脚本: %@", error.localizedDescription)
                return
            }
            executable = swiftURL
            arguments = [scriptURL.path]
        }

        helperBuffer.reset()

        let proc = Process()
        let pipe = Pipe()
        proc.executableURL = executable
        proc.arguments = arguments
        proc.standardOutput = pipe
        proc.standardError = FileHandle.nullDevice

        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            let lines = self.helperBuffer.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                for line in lines {
                    self.handleHelperLine(line, backend: backend)
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
            helperStartDate = Date()
            activeBackend = backend
            canSeek = backend == .perlAdapter
        } catch {
            NSLog("⚠️ 无法启动 now playing helper: %@", error.localizedDescription)
            helperProcess = nil
            activeBackend = nil
            canSeek = false
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
        activeBackend = nil
        canSeek = false
    }

    private func helperDidTerminate() {
        helperProcess = nil
        activeBackend = nil
        canSeek = false
        guard isObserving else { return }

        // 启动后很快就退出说明这个后端在当前机器上跑不通，换下一个；
        // 运行良久后的意外退出则视为偶发，同一后端延迟重启。
        let uptime = Date().timeIntervalSince(helperStartDate)
        if uptime < 5, !backendQueue.isEmpty {
            backendQueue.removeFirst()
        }
        guard !backendQueue.isEmpty else { return }

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

    private func handleHelperLine(_ line: Data, backend: HelperBackend) {
        let snapshot: NowPlayingSnapshot?
        switch backend {
        case .perlAdapter:
            snapshot = Self.parseAdapterLine(line)
        case .swiftToolchain:
            snapshot = Self.parseSnapshot(line)
        }
        guard let snapshot else { return }
        if backend == .perlAdapter {
            fulfillPendingPlaybackIntent(
                using: snapshot,
                reportedBundleIdentifier: reportedBundleIdentifier(for: snapshot)
            )
        }
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
        var duration: TimeInterval? = nil
        var elapsedTime: TimeInterval? = nil
        var timestamp: Date? = nil
        var playbackRate: Double? = nil
        /// 封面仍属于上一首曲目，尚不可信（swift 工具链 helper 会主动标记）
        var artworkStale: Bool = false
        /// 播放器 bundle ID（perl adapter 后端直接提供）
        var bundleIdentifier: String? = nil
    }

    /// 解析 swift 工具链 helper 的输出行。
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

    /// 解析 perl adapter 的输出行：{"type":"data","diff":false,"payload":{...}}。
    /// 使用 --no-diff，payload 始终是完整快照；无音乐时 payload 为空字典。
    private static func parseAdapterLine(_ data: Data) -> NowPlayingSnapshot? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "data",
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }
        return NowPlayingSnapshot(
            pid: Int32(payload["processIdentifier"] as? Int ?? -1),
            title: payload["title"] as? String ?? "",
            artist: payload["artist"] as? String ?? "",
            playing: payload["playing"] as? Bool ?? false,
            artworkData: (payload["artworkData"] as? String).flatMap { Data(base64Encoded: $0) },
            duration: number(payload["duration"]),
            elapsedTime: number(payload["elapsedTime"]),
            timestamp: (payload["timestamp"] as? String).flatMap(parseISO8601Date),
            playbackRate: number(payload["playbackRate"]),
            bundleIdentifier: payload["bundleIdentifier"] as? String
        )
    }

    private static func number(_ value: Any?) -> Double? {
        (value as? NSNumber)?.doubleValue
    }

    private static func parseISO8601Date(_ value: String) -> Date? {
        ISO8601DateFormatter().date(from: value)
    }

    /// 基于后端提供的采样点外推播放位置。视图层可高频调用，不会触发状态发布。
    func estimatedElapsedTime(at now: Date = Date()) -> TimeInterval? {
        guard let duration, duration > 0,
              let elapsedTime else { return nil }

        var estimated = elapsedTime
        if isPlaying,
           let progressTimestamp,
           let playbackRate,
           playbackRate > 0 {
            estimated += max(0, now.timeIntervalSince(progressTimestamp)) * playbackRate
        }
        return min(max(estimated, 0), duration)
    }

    func playbackProgress(at now: Date = Date()) -> Double? {
        guard let duration, duration > 0,
              let candidate = estimatedElapsedTime(at: now) else { return nil }
        let elapsed = monotonicDisplayedElapsed(candidate: candidate, duration: duration, at: now)
        return min(max(elapsed / duration, 0), 1)
    }

    private func monotonicDisplayedElapsed(
        candidate: TimeInterval,
        duration: TimeInterval,
        at now: Date
    ) -> TimeInterval {
        let clampedCandidate = min(max(candidate, 0), duration)
        guard let lastDisplayedElapsed, let lastDisplayedAt else {
            resetDisplayedProgress(to: clampedCandidate, at: now)
            return clampedCandidate
        }

        let elapsedSinceDisplay = max(0, now.timeIntervalSince(lastDisplayedAt))
        let displayRate = isPlaying ? max(playbackRate ?? 1, 0) : 0
        let continuedDisplayedElapsed = min(
            max(lastDisplayedElapsed + elapsedSinceDisplay * displayRate, 0),
            duration
        )
        let diff = clampedCandidate - continuedDisplayedElapsed
        let displayedElapsed: TimeInterval
        if abs(diff) < minorProgressRegressionTolerance {
            displayedElapsed = continuedDisplayedElapsed + diff * 0.08
        } else {
            displayedElapsed = clampedCandidate
        }

        resetDisplayedProgress(to: displayedElapsed, at: now)
        return displayedElapsed
    }

    private func resetDisplayedProgress(
        to elapsed: TimeInterval? = nil,
        at date: Date? = nil
    ) {
        lastDisplayedElapsed = elapsed
        lastDisplayedAt = elapsed == nil ? nil : (date ?? Date())
    }

    private func resetDisplayedProgressTracking() {
        resetDisplayedProgress()
    }

    private func apply(_ snapshot: NowPlayingSnapshot) {
        // 报告方不是已知播放器时，说明是系统里其他发声来源，不予采信。
        let reportedBundleID = reportedBundleIdentifier(for: snapshot)
        if let bundleID = reportedBundleID,
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
        if trackChanged {
            if !trackName.isEmpty {
                cancelPendingPlaybackIntent()
            }
            clearProgress()
        }
        trackName = snapshot.title
        artistName = snapshot.artist
        hasNowPlaying = true
        currentSessionBundleIdentifier = reportedBundleID

        // 冻结期内不覆盖 isPlaying，防止命令刚发出就被旧状态回弹
        if Date() > playingFrozenUntil {
            let playbackStateChanged = isPlaying != snapshot.playing
            isPlaying = snapshot.playing
            if playbackStateChanged {
                resetDisplayedProgressTracking()
            }
        }

        applyProgress(snapshot, trackChanged: trackChanged)
        applyArtwork(snapshot, trackChanged: trackChanged)
    }

    private func reportedBundleIdentifier(for snapshot: NowPlayingSnapshot) -> String? {
        snapshot.bundleIdentifier
            ?? (snapshot.pid > 0
                ? NSRunningApplication(processIdentifier: snapshot.pid)?.bundleIdentifier
                : nil)
    }

    private func applyProgress(_ snapshot: NowPlayingSnapshot, trackChanged: Bool) {
        guard trackChanged || Date() >= progressFrozenUntil else { return }

        guard let duration = snapshot.duration, duration > 0,
              let elapsedTime = snapshot.elapsedTime else {
            clearProgress()
            return
        }

        self.duration = duration
        self.elapsedTime = min(max(elapsedTime, 0), duration)
        progressTimestamp = snapshot.timestamp
        playbackRate = snapshot.playbackRate
    }

    private func clearProgress() {
        duration = nil
        elapsedTime = nil
        progressTimestamp = nil
        playbackRate = nil
        resetDisplayedProgressTracking()
    }

    /// 封面归属判定。MediaRemote 常常先更新曲目、封面稍后才到：
    /// 曲目刚换而封面字节与上一首完全相同时，先按"过期"处理不显示，
    /// 1.5 秒后仍无新封面则认可它（同专辑连播、封面本来就一样的场景）。
    private func applyArtwork(_ snapshot: NowPlayingSnapshot, trackChanged: Bool) {
        let trackKey = "\(snapshot.title)|\(snapshot.artist)"
        let fingerprint = snapshot.artworkData.map { "\($0.count)-\($0.hashValue)" }
        defer {
            lastAppliedTrackKey = trackKey
            if fingerprint != nil {
                lastAppliedArtworkFingerprint = fingerprint
            }
        }

        var artworkStale = snapshot.artworkStale
        if !artworkStale,
           trackKey != lastAppliedTrackKey,
           let fingerprint,
           fingerprint == lastAppliedArtworkFingerprint {
            artworkStale = true
        }

        if artworkStale, let artData = snapshot.artworkData {
            albumArt = nil
            scheduleArtworkSettle(trackKey: trackKey, data: artData)
        } else if let artData = snapshot.artworkData {
            artworkSettleWorkItem?.cancel()
            artworkSettleWorkItem = nil
            albumArt = NSImage(data: artData)
        } else if trackChanged {
            albumArt = nil
        }
    }

    private func scheduleArtworkSettle(trackKey: String, data: Data) {
        artworkSettleWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.artworkSettleWorkItem = nil
            // 曲目没再变、也没有新封面顶掉它 → 这张封面确实属于当前曲目
            guard "\(self.trackName)|\(self.artistName)" == trackKey,
                  self.albumArt == nil else { return }
            self.albumArt = NSImage(data: data)
        }
        artworkSettleWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5, execute: work)
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
        artworkSettleWorkItem?.cancel()
        artworkSettleWorkItem = nil
        lastAppliedTrackKey = ""
        lastAppliedArtworkFingerprint = nil
        trackName = ""
        artistName = ""
        albumArt = nil
        currentSessionBundleIdentifier = nil
        clearProgress()
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
