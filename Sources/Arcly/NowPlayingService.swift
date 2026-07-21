import Foundation
import AppKit
import IOKit.hidsystem

// MARK: - Now Playing Service

class NowPlayingService: ObservableObject {
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage? = nil
    @Published var isPlaying: Bool = false
    @Published var hasNowPlaying: Bool = false

    private var pollTimer: Timer?
    private var isObserving = false
    private var notificationObservers: [Any] = []
    private var refreshInFlight = false
    private var refreshQueuedAfterInFlight = false
    private var activeRefreshID = 0
    private var refreshProcess: Process?
    private let refreshTimeout: TimeInterval = 3.2
    private var emptyRefreshCount = 0
    private let maxEmptyRefreshesBeforeClear = 4
    /// 发送播放命令后短暂冻结，防止文件旧状态覆盖乐观更新
    private var playingFrozenUntil: Date = .distantPast

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

    private static let helperSwiftURL: URL? = {
        let candidates = [
            "/Library/Developer/CommandLineTools/usr/bin/swift",
            "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swift",
        ]
        return candidates.first(where: FileManager.default.isExecutableFile(atPath:)).map {
            URL(fileURLWithPath: $0)
        }
    }()

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

    private static func sendCommandDirect(_ cmd: UInt32) -> Bool {
        guard let h = mrHandle,
              let sym = dlsym(h, "MRMediaRemoteSendCommand") else { return false }
        ensureMRRegistered()
        typealias S = @convention(c) (UInt32, UnsafeRawPointer?) -> Bool
        return unsafeBitCast(sym, to: S.self)(cmd, nil)
    }

    // MARK: - 生命周期

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        Self.ensureMRRegistered()

        // 监听 MediaRemote 通知 → 立即刷新播放状态
        let nc = NotificationCenter.default
        let names = [
            "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
            "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        ]
        for name in names {
            let obs1 = nc.addObserver(forName: Notification.Name(name), object: nil, queue: .main) { [weak self] _ in
                self?.refreshNowPlaying()
            }
            notificationObservers.append(obs1)

            let obs2 = DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(name), object: nil, queue: .main
            ) { [weak self] _ in
                self?.refreshNowPlaying()
            }
            notificationObservers.append(obs2)
        }

        // 兜底轮询：部分播放器不稳定发送 MediaRemote 通知
        pollTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.refreshNowPlaying()
        }

        refreshNowPlaying()
    }

    func stopObserving() {
        isObserving = false
        pollTimer?.invalidate()
        pollTimer = nil

        // Bug fix: 移除所有通知观察者，防止 start/stop 循环后回调累积
        for observer in notificationObservers {
            NotificationCenter.default.removeObserver(observer)
            DistributedNotificationCenter.default().removeObserver(observer)
        }
        notificationObservers.removeAll()
    }

    // MARK: - 媒体控制

    func togglePlayPause() {
        sendMediaCommand(2, keyType: NX_KEYTYPE_PLAY)
        isPlaying.toggle()
        playingFrozenUntil = Date().addingTimeInterval(1.5)
        refreshAfterMediaCommand()
    }

    func nextTrack() {
        sendMediaCommand(4, keyType: NX_KEYTYPE_NEXT)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
        refreshAfterMediaCommand()
    }

    func previousTrack() {
        sendMediaCommand(5, keyType: NX_KEYTYPE_PREVIOUS)
        playingFrozenUntil = Date().addingTimeInterval(1.5)
        refreshAfterMediaCommand()
    }

    private func sendMediaCommand(_ command: UInt32, keyType: Int32) {
        _ = command
        postSystemMediaKey(keyType)
    }

    private func postSystemMediaKey(_ keyType: Int32) {
        let flags = NSEvent.ModifierFlags(rawValue: 0xA00)
        let keyDownData = (Int(keyType) << 16) | (0xA << 8)
        let keyUpData = (Int(keyType) << 16) | (0xB << 8)
        let keyDown = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyDownData,
            data2: -1
        )
        let keyUp = NSEvent.otherEvent(
            with: .systemDefined,
            location: .zero,
            modifierFlags: flags,
            timestamp: 0,
            windowNumber: 0,
            context: nil,
            subtype: 8,
            data1: keyUpData,
            data2: -1
        )
        keyDown?.cgEvent?.post(tap: .cghidEventTap)
        keyUp?.cgEvent?.post(tap: .cghidEventTap)
    }

    private func refreshAfterMediaCommand() {
        for delay in [0.35, 0.9, 1.7, 3.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshNowPlaying()
            }
        }
    }

    func refreshForMenuPresentation() {
        refreshNowPlaying()

        for delay in [0.2, 0.7, 1.4] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                self?.refreshNowPlaying()
            }
        }
    }

    // MARK: - 读取当前播放

    private struct NowPlayingSnapshot {
        let pid: Int32
        let title: String
        let artist: String
        let playing: Bool
        let artworkData: Data?
    }

    private final class HelperOutputBuffer {
        private let lock = NSLock()
        private var data = Data()

        func append(_ chunk: Data) {
            guard !chunk.isEmpty else { return }
            lock.lock()
            data.append(chunk)
            lock.unlock()
        }

        func snapshot() -> Data {
            lock.lock()
            defer { lock.unlock() }
            return data
        }
    }

    private static let helperScriptURL: URL? = {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("Arcly") else {
            return nil
        }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("mr_info.swift")
    }()

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
    getPID(.main) { pid in
        getPlaying(.main) { playing in
            getInfo(.main) { info in
                var output: [String: Any] = ["playing": playing, "pid": pid]
                output["title"] = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                output["artist"] = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                if let data = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                    output["artwork"] = data.base64EncodedString()
                }
                if let json = try? JSONSerialization.data(withJSONObject: output),
                   let str = String(data: json, encoding: .utf8) {
                    print(str)
                }
                exit(0)
            }
        }
    }
    RunLoop.main.run(until: Date().addingTimeInterval(3))
    """

    private static func readNowPlayingDirect(_ completion: @escaping (NowPlayingSnapshot?) -> Void) -> Bool {
        guard let h = mrHandle,
              let infoSym = dlsym(h, "MRMediaRemoteGetNowPlayingInfo"),
              let playingSym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationIsPlaying"),
              let pidSym = dlsym(h, "MRMediaRemoteGetNowPlayingApplicationPID") else {
            return false
        }

        ensureMRRegistered()

        typealias GetInfo = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
        typealias GetPlaying = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
        typealias GetPID = @convention(c) (DispatchQueue, @escaping (Int32) -> Void) -> Void

        let getInfo = unsafeBitCast(infoSym, to: GetInfo.self)
        let getPlaying = unsafeBitCast(playingSym, to: GetPlaying.self)
        let getPID = unsafeBitCast(pidSym, to: GetPID.self)

        getPID(.main) { pid in
            getPlaying(.main) { playing in
                getInfo(.main) { info in
                    let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                    let artist = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String ?? ""
                    let artworkData = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data
                    completion(NowPlayingSnapshot(
                        pid: pid,
                        title: title,
                        artist: artist,
                        playing: playing,
                        artworkData: artworkData
                    ))
                }
            }
        }

        return true
    }

    private func refreshNowPlaying() {
        let musicApp = runningMusicApp
        let expectedBID = musicApp?.bundleIdentifier

        if refreshInFlight {
            refreshQueuedAfterInFlight = true
            return
        }

        refreshProcess?.terminate()
        refreshProcess = nil
        refreshInFlight = true
        refreshQueuedAfterInFlight = false
        activeRefreshID += 1
        let refreshID = activeRefreshID

        scheduleRefreshTimeout(refreshID: refreshID, expectedBID: expectedBID)

        if Self.readNowPlayingDirect({ [weak self] snapshot in
            DispatchQueue.main.async {
                guard let self = self,
                      self.refreshInFlight,
                      self.activeRefreshID == refreshID else {
                    return
                }

                if let snapshot = snapshot, !snapshot.title.isEmpty {
                    self.completeRefresh(snapshot, expectedBID: expectedBID, refreshID: refreshID)
                } else {
                    self.startHelperRefresh(expectedBID: expectedBID, refreshID: refreshID)
                }
            }
        }) {
            return
        }

        startHelperRefresh(expectedBID: expectedBID, refreshID: refreshID)
    }

    private func scheduleRefreshTimeout(refreshID: Int, expectedBID: String?) {
        DispatchQueue.main.asyncAfter(deadline: .now() + refreshTimeout) { [weak self] in
            guard let self = self,
                  self.refreshInFlight,
                  self.activeRefreshID == refreshID else {
                return
            }
            self.refreshProcess?.terminate()
            self.completeRefresh(nil, expectedBID: expectedBID, refreshID: refreshID)
        }
    }

    private func startHelperRefresh(expectedBID: String?, refreshID: Int) {
        guard let swiftURL = Self.helperSwiftURL,
              let helperScriptURL = Self.helperScriptURL else {
            completeRefresh(nil, expectedBID: expectedBID, refreshID: refreshID)
            return
        }
        do {
            try Self.helperScript.write(to: helperScriptURL, atomically: true, encoding: .utf8)
        } catch {
            completeRefresh(nil, expectedBID: expectedBID, refreshID: refreshID)
            return
        }

        let proc = Process()
        let output = Pipe()
        let outputBuffer = HelperOutputBuffer()
        proc.executableURL = swiftURL
        proc.arguments = [helperScriptURL.path]
        proc.standardOutput = output
        proc.standardError = FileHandle.nullDevice
        refreshProcess = proc

        output.fileHandleForReading.readabilityHandler = { handle in
            outputBuffer.append(handle.availableData)
        }

        proc.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            outputBuffer.append(output.fileHandleForReading.readDataToEndOfFile())
            let data = outputBuffer.snapshot()
            let snapshot = Self.parseHelperOutput(data)
            DispatchQueue.main.async {
                self?.completeRefresh(snapshot, expectedBID: expectedBID, refreshID: refreshID)
            }
        }

        do {
            try proc.run()
        } catch {
            refreshProcess = nil
            completeRefresh(nil, expectedBID: expectedBID, refreshID: refreshID)
        }
    }

    private func completeRefresh(_ snapshot: NowPlayingSnapshot?, expectedBID: String?, refreshID: Int) {
        guard refreshInFlight, refreshID == activeRefreshID else { return }
        refreshInFlight = false
        refreshProcess = nil

        if let snapshot = snapshot {
            applyNowPlaying(snapshot, expectedBID: expectedBID)
        } else {
            handleEmptyNowPlaying()
        }

        if refreshQueuedAfterInFlight {
            refreshQueuedAfterInFlight = false
            refreshNowPlaying()
        }
    }

    private static func parseHelperOutput(_ data: Data) -> NowPlayingSnapshot? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }

        let pid = Int32(json["pid"] as? Int ?? -1)
        let title = json["title"] as? String ?? ""
        let artist = json["artist"] as? String ?? ""
        let playing = json["playing"] as? Bool ?? false
        let artworkData = (json["artwork"] as? String).flatMap { Data(base64Encoded: $0) }

        return NowPlayingSnapshot(
            pid: pid,
            title: title,
            artist: artist,
            playing: playing,
            artworkData: artworkData
        )
    }

    private func applyNowPlaying(_ snapshot: NowPlayingSnapshot, expectedBID: String?) {
        if snapshot.title.isEmpty && snapshot.pid <= 0 {
            handleEmptyNowPlaying()
            return
        }

        if snapshot.pid > 0,
           let app = NSRunningApplication(processIdentifier: snapshot.pid),
           let bundleID = app.bundleIdentifier,
           let expectedBID = expectedBID,
           bundleID != expectedBID,
           !Self.musicBundleIDs.contains(bundleID) {
            clearStaleNowPlaying()
            return
        }

        let title = snapshot.title
        let trackChanged = self.trackName != title

        emptyRefreshCount = 0
        self.trackName = title
        self.artistName = snapshot.artist
        // 冻结期内不覆盖 isPlaying（防止命令后旧状态回弹）
        if Date() > playingFrozenUntil {
            self.isPlaying = snapshot.playing
        }
        self.hasNowPlaying = !title.isEmpty || runningMusicApp != nil

        if let artData = snapshot.artworkData {
            self.albumArt = NSImage(data: artData)
        } else if trackChanged && !title.isEmpty {
            // 封面可能延迟到达，短暂后重读
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.refreshNowPlaying()
            }
        } else if title.isEmpty {
            self.albumArt = nil
        }
    }

    private func handleEmptyNowPlaying() {
        emptyRefreshCount += 1

        if runningMusicApp != nil && !trackName.isEmpty && emptyRefreshCount <= maxEmptyRefreshesBeforeClear {
            hasNowPlaying = true
            if Date() > playingFrozenUntil {
                isPlaying = false
            }
            return
        }

        clearStaleNowPlaying()
    }

    private func clearStaleNowPlaying() {
        emptyRefreshCount = 0
        hasNowPlaying = false
        trackName = ""
        artistName = ""
        isPlaying = false
        albumArt = nil
        if refreshInFlight {
            refreshInFlight = false
        }
    }
}
