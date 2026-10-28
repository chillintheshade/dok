import Foundation
import AppKit
import ApplicationServices
import IOKit.hidsystem

// MARK: - Now Playing Service

/// 读取系统「正在播放」信息。
///
/// macOS 只向 Apple 签名的进程开放 MediaRemote 元数据，因此本机进程内直读通常拿不到数据。
/// 主路径是借系统 perl（Apple 签名）运行打包的 MediaRemoteAdapter，**按需**运行：
/// 唤出轮盘时先显示缓存，同时启动 `stream`（首帧实测约 20ms），系统一宣布变化就推送，
/// 与播放器切歌同步；轮盘收起即结束。没有常驻进程，也就没有"进程活着却不再推数据"
/// 的失效方式。启动和系统唤醒时各用一次性 `get` 预热缓存。
///
/// 只有 perl 路不可用时，才退回常驻的 Swift 工具链 helper（解释器启动要 1～3 秒，
/// 无法按需），并为它提供自愈：快速失败退避重试、唤醒后重启、唤出时无数据则重启。
class NowPlayingService: ObservableObject {
    @Published var trackName: String = ""
    @Published var artistName: String = ""
    @Published var albumArt: NSImage? = nil {
        didSet { updateTrackCard() }
    }
    /// 轮盘中心显示的曲目卡片：曲名、歌手与封面作为一个整体切换。新曲目要等封面到齐
    /// （或确认没有封面）才提交，轮盘据此整张推入，不会出现空的封面位。
    @Published private(set) var trackCard: TrackCard?

    struct TrackCard: Equatable {
        let id = UUID()
        let title: String
        let artist: String
        var artwork: NSImage?
        /// 用户正看着轮盘时换歌才推入；轮盘收起期间换的歌，打开时直接显示。
        var animated: Bool = true

        var key: String { "\(title)|\(artist)" }

        static func == (lhs: TrackCard, rhs: TrackCard) -> Bool {
            lhs.id == rhs.id && lhs.artwork === rhs.artwork
        }
    }
    @Published var isPlaying: Bool = false
    @Published var hasNowPlaying: Bool = false
    @Published private(set) var duration: TimeInterval? = nil
    @Published private(set) var elapsedTime: TimeInterval? = nil
    @Published private(set) var progressTimestamp: Date? = nil
    @Published private(set) var playbackRate: Double? = nil
    @Published private(set) var canSeek: Bool = false
    /// 播放器切歌期间为真。此时它会静默丢弃新的切歌命令（QQ 音乐实测：
    /// 从命令发出到报告新曲目后约 0.5s），轮盘据此把上一首/下一首显示为不可点。
    @Published private(set) var isSkipLocked = false
    /// 最近一次切歌的方向，决定新曲目滑入的方向。
    @Published private(set) var skipDirection: SkipDirection = .forward
    /// 每次按下上一首/下一首都会更新：被接受时按钮轻缩，被拒绝时按钮轻晃。
    @Published private(set) var skipEvent: SkipEvent?

    enum SkipDirection: Equatable {
        case forward, backward
    }

    struct SkipEvent: Equatable {
        let id = UUID()
        let direction: SkipDirection
        let accepted: Bool
    }
    var recentMusicAppBundleIdentifiers: (() -> [String])?

    private var isObserving = false
    private var observationID = UUID()
    private var helperProcess: Process?
    private var seekProcesses: [Process] = []
    private var playbackCommandProcesses: [Process] = []
    private var helperRestartWorkItem: DispatchWorkItem?
    private var helperStartDate: Date = .distantPast
    private var upkeepTimer: Timer?
    private var pendingClearWorkItem: DispatchWorkItem?

    /// perl adapter 按需读取。同一时刻最多一个 `get` 在跑。
    private var adapterReadProcess: Process?
    private var adapterStreamProcess: Process?
    private var adapterStreamStartDate: Date = .distantPast
    private var adapterStreamRestartWorkItem: DispatchWorkItem?
    private var skipUnlockWorkItem: DispatchWorkItem?
    /// 播放器在此时刻之前仍会丢弃切歌命令；按钮已恢复，此前的按下延后到这里再发送。
    private var skipCommandReadyAt: Date = .distantPast
    private var deferredSkipWorkItem: DispatchWorkItem?
    private var skipRetryWorkItem: DispatchWorkItem?
    private var skipDirectionResetWorkItem: DispatchWorkItem?

    /// QQ 音乐播放栏比 MediaRemote 早约 0.4s 更新曲名，切歌期间短暂轮询它。
    private let qqTitleReader = QQMusicTitleReader()
    private var earlyTitleTimer: Timer?
    private var cardCommitWorkItem: DispatchWorkItem?
    /// 冻结期内收到的最新播放状态，冻结结束时补上，不因 stream 不重发而丢失。
    private var lastReportedPlaying: Bool?
    private var playingReapplyWorkItem: DispatchWorkItem?
    private var adapterFailures = 0
    private var isMenuPresented = false
    /// 本次打开后是否已收到过快照：在此之前到达的新曲目是收起期间换的，不推入。
    private var hasSnapshotSincePresentation = false
    private var nextCardAnimated = true
    /// 常驻兜底 helper 连续快速失败时的退避间隔；稳定运行后归零。
    private var helperRetryDelay: TimeInterval = 0
    private var wakeObserver: NSObjectProtocol?
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

    private static func unregisterMRNotifications() {
        guard mrRegistered, let h = mrHandle,
              let sym = dlsym(h, "MRMediaRemoteUnregisterForNowPlayingNotifications") else { return }
        typealias Unregister = @convention(c) () -> Void
        unsafeBitCast(sym, to: Unregister.self)()
        mrRegistered = false
    }

    // MARK: - 数据来源

    /// 读取"正在播放"信息的两条路，按优先级排列：
    ///
    /// 1. perl adapter —— 打包在 App 里的 MediaRemoteAdapter.framework（BSD-3，
    ///    见 Vendor/），由系统自带的 `/usr/bin/perl`（Apple 签名，被系统视作
    ///    `com.apple.perl`）加载运行。所有 Mac 都可用，按需一次性读取。
    /// 2. Swift 工具链常驻 helper —— 旧方案：把脚本交给 Swift 工具链解释执行。
    ///    仅在装有 Xcode/CLT 的机器上可用，作为 perl 路不通时的兜底。
    private static let adapterFailureLimit = 3
    /// 切歌后等待新曲目的上限（QQ 音乐实测约 0.7s 才报告）。
    private static let skipConfirmTimeout: TimeInterval = 2
    /// 报告新曲目后播放器仍会丢弃命令的时长（实测 0.24s 丢弃、0.54s 接受）。
    private static let skipSettleDelay: TimeInterval = 0.6
    /// 新曲目快照里没有封面时，最多再等这么久；仍没有就以无封面卡片提交。
    /// 实测封面通常与曲名同时或紧随其后（0ms）到达。
    private static let cardArtworkWait: TimeInterval = 0.6
    private static let earlyTitlePollInterval: TimeInterval = 0.025
    /// 播放器偶尔无故丢弃命令（实测空闲数分钟后的首次切歌也会被丢）。超过这个时间
    /// 仍没有新曲目，就补发一次。播放栏约 0.28s 就有反应；只有系统报告时约 0.7s。
    private static let skipRetryDelayWithTitle: TimeInterval = 0.8
    private static let skipRetryDelayWithoutTitle: TimeInterval = 1.4
    private static let adapterReadTimeout: TimeInterval = 3
    private static let helperMaxRetryDelay: TimeInterval = 300

    private static var adapterAvailable: Bool {
        perlURL != nil && adapterScriptURL != nil && adapterFrameworkURL != nil
    }

    private static var residentHelperAvailable: Bool {
        helperSwiftURL != nil && helperScriptURL != nil
    }

    /// 连续失败达到上限后，播放命令退回媒体键，并启动常驻兜底；
    /// 之后每次唤出仍会尝试读取，一旦成功就切回来。
    private var adapterUsable: Bool {
        Self.adapterAvailable && adapterFailures < Self.adapterFailureLimit
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

    func setObservationEnabled(_ enabled: Bool) {
        if enabled {
            startObserving()
        } else {
            stopObserving()
        }
    }

    func startObserving() {
        guard !isObserving else { return }
        isObserving = true
        observationID = UUID()
        playingFrozenUntil = .distantPast
        progressFrozenUntil = .distantPast
        resetDisplayedProgressTracking()
        Self.ensureMRRegistered()

        // 进程内直读。在未被系统限制的机器上这一步即可拿到数据。
        directRead()

        adapterFailures = 0
        helperRetryDelay = 0
        readAdapterOnce()
        startHelper()

        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            self?.handleSystemWake()
        }

        // 轻量巡检：维持 hasNowPlaying（播放器开关），并在直读可用时保持同步。
        // helper 不可用时，这是唯一的更新来源。
        upkeepTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.upkeep()
        }
    }

    func stopObserving() {
        guard isObserving else { return }
        isObserving = false
        observationID = UUID()
        upkeepTimer?.invalidate()
        upkeepTimer = nil
        pendingClearWorkItem?.cancel()
        pendingClearWorkItem = nil
        artworkSettleWorkItem?.cancel()
        artworkSettleWorkItem = nil
        cancelPendingPlaybackIntent()
        stopAdapterStream()
        deferredSkipWorkItem?.cancel()
        deferredSkipWorkItem = nil
        stopEarlyTitleWatch()
        cardCommitWorkItem?.cancel()
        cardCommitWorkItem = nil
        skipRetryWorkItem?.cancel()
        skipRetryWorkItem = nil
        playingReapplyWorkItem?.cancel()
        playingReapplyWorkItem = nil
        unlockSkips()
        if let process = adapterReadProcess, process.isRunning { process.terminate() }
        adapterReadProcess = nil
        canSeek = false
        stopHelper()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        wakeObserver = nil
        Self.unregisterMRNotifications()
    }

    deinit {
        pendingPlaybackIntentExpirationWorkItem?.cancel()
        pendingClearWorkItem?.cancel()
        artworkSettleWorkItem?.cancel()
        stopHelper()
        skipUnlockWorkItem?.cancel()
        deferredSkipWorkItem?.cancel()
        skipDirectionResetWorkItem?.cancel()
        playingReapplyWorkItem?.cancel()
        skipRetryWorkItem?.cancel()
        cardCommitWorkItem?.cancel()
        earlyTitleTimer?.invalidate()
        adapterStreamRestartWorkItem?.cancel()
        if let process = adapterStreamProcess, process.isRunning { process.terminate() }
        if let process = adapterReadProcess, process.isRunning { process.terminate() }
        upkeepTimer?.invalidate()
        if let wakeObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver)
        }
        if isObserving { Self.unregisterMRNotifications() }
    }

    // MARK: - 媒体控制

    func togglePlayPause() {
        guard isObserving else { return }
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
        guard isObserving else { return }
        cancelPendingPlaybackIntent()
        guard !trackName.isEmpty else { return }
        performSkip(.forward)
    }

    func previousTrack() {
        guard isObserving else { return }
        cancelPendingPlaybackIntent()
        guard !trackName.isEmpty else { return }
        performSkip(.backward)
    }

    /// 切歌期间的点击不发命令，只给"现在不行"的反馈；不排队，免得用户连点后被动连跳。
    private func performSkip(_ direction: SkipDirection) {
        guard !isSkipLocked else {
            skipEvent = SkipEvent(direction: direction, accepted: false)
            return
        }
        skipDirectionResetWorkItem?.cancel()
        skipDirection = direction
        skipEvent = SkipEvent(direction: direction, accepted: true)

        let send: () -> Void = { [weak self] in
            self?.sendSkipCommand(direction, isRetry: false)
        }
        // 按钮随新曲目滑入就已恢复，播放器却还要忙一小会儿：这一下仍算数，
        // 等它能接收时再发。之后立即上锁，所以最多只延后这一次，不会排队。
        let delay = max(0, skipCommandReadyAt.timeIntervalSinceNow)
        if delay > 0 {
            let work = DispatchWorkItem(block: send)
            deferredSkipWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
        } else {
            send()
        }
        lockSkips(for: delay + Self.skipConfirmTimeout)
    }

    private func routePlaybackCommand(adapterCommand: Int, fallbackMediaKey: Int32) {
        if !sendAdapterPlaybackCommand(adapterCommand) {
            postSystemMediaKey(fallbackMediaKey)
        }
    }

    private func sendAdapterPlaybackCommand(_ command: Int) -> Bool {
        guard adapterUsable,
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
        // 等待播放器暴露可控会话期间保持推送，才能及时兑现这次播放意图。
        updateAdapterStream()

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
        updateAdapterStream()
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
        guard isObserving else { return }
        cancelPendingPlaybackIntent()
        guard adapterUsable,
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

    /// 轮盘弹出时调用：界面先显示缓存，同时启动推送（首帧约 20ms）。
    func refreshForMenuPresentation() {
        guard isObserving else { return }
        isMenuPresented = true
        hasSnapshotSincePresentation = false
        directRead()
        updateAdapterStream()
        if currentSessionBundleIdentifier == QQMusicTitleReader.bundleIdentifier {
            qqTitleReader.prepare()
        }
        healResidentHelperOnPresentation()
    }

    /// 轮盘收起后结束推送（播放意图仍在等待时除外）。
    func menuDidDismiss() {
        isMenuPresented = false
        hasSnapshotSincePresentation = false
        updateAdapterStream()
    }

    private func sendSkipCommand(_ direction: SkipDirection, isRetry: Bool) {
        guard isObserving else { return }
        deferredSkipWorkItem = nil
        switch direction {
        case .forward:
            routePlaybackCommand(adapterCommand: 4, fallbackMediaKey: NX_KEYTYPE_NEXT)
        case .backward:
            routePlaybackCommand(adapterCommand: 5, fallbackMediaKey: NX_KEYTYPE_PREVIOUS)
        }
        playingFrozenUntil = Date().addingTimeInterval(1.5)
        startEarlyTitleWatch()
        if isRetry {
            // 只补发一次：再没反应就让锁超时解开，不会多切一首。
            lockSkips(for: Self.skipConfirmTimeout)
        } else {
            scheduleSkipRetry(direction)
        }
    }

    private func scheduleSkipRetry(_ direction: SkipDirection) {
        skipRetryWorkItem?.cancel()
        let shownTitle = trackName
        let readsPlayBar = currentSessionBundleIdentifier == QQMusicTitleReader.bundleIdentifier
            && qqTitleReader.read() != nil
        let wait = readsPlayBar ? Self.skipRetryDelayWithTitle : Self.skipRetryDelayWithoutTitle
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving, self.isSkipLocked,
                  self.trackName == shownTitle else { return }
            self.skipRetryWorkItem = nil
            NSLog("dok.nowPlaying: skip not confirmed in %.1fs; resending once", wait)
            self.sendSkipCommand(direction, isRetry: true)
        }
        skipRetryWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + wait, execute: work)
    }

    // MARK: - 切歌锁

    /// 锁定上一首/下一首，到期自动解锁；再次调用会以新的时长覆盖。
    private func lockSkips(for duration: TimeInterval) {
        isSkipLocked = true
        skipUnlockWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            // 超时没等到新曲目：没有滑入动画在进行，方向可以立即复位。
            self?.unlockSkips()
            self?.resetSkipDirection(after: 0)
        }
        skipUnlockWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    private func unlockSkips() {
        skipUnlockWorkItem?.cancel()
        skipUnlockWorkItem = nil
        if isSkipLocked { isSkipLocked = false }
    }

    /// 之后播放器自行换歌（自动连播、在播放器里点）时按"前进"方向滑入。
    /// 不能与新曲目同一刻复位，否则后退切歌的新曲目会从错误的一侧滑入。
    private func resetSkipDirection(after delay: TimeInterval) {
        skipDirectionResetWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.skipDirectionResetWorkItem = nil
            if self.skipDirection != .forward { self.skipDirection = .forward }
        }
        skipDirectionResetWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    /// 新曲目到达：按钮与滑入动画同时恢复。播放器在之后约 0.6s 内仍会丢弃命令
    /// （轮盘打开期间它自己换歌时也一样），这段由 skipCommandReadyAt 延后发送吸收。
    /// 唤出时首帧追上缓存不算换歌。
    private func noteTrackChange(from previousTitle: String) {
        skipRetryWorkItem?.cancel()
        skipRetryWorkItem = nil
        let changedWhileOpen = adapterStreamProcess != nil
            && Date().timeIntervalSince(adapterStreamStartDate) > 0.3
        guard isSkipLocked || (!previousTitle.isEmpty && changedWhileOpen) else { return }
        skipCommandReadyAt = Date().addingTimeInterval(Self.skipSettleDelay)
    }

    // MARK: - 曲目卡片

    /// 每次曲名、歌手或封面变化后调用。同一曲目只原地更新封面；新曲目等封面到齐再提交。
    private func updateTrackCard() {
        guard !trackName.isEmpty else {
            cardCommitWorkItem?.cancel()
            cardCommitWorkItem = nil
            if trackCard != nil { trackCard = nil }
            return
        }
        let key = "\(trackName)|\(artistName)"
        if var card = trackCard, card.key == key {
            // 封面晚到或更换：原地替换，不推入。为防闪烁暂时隐藏的封面不覆盖已显示的。
            if let art = albumArt, card.artwork !== art {
                card.artwork = art
                trackCard = card
            }
            return
        }
        if albumArt != nil {
            commitTrackCard()
        } else if cardCommitWorkItem == nil {
            let work = DispatchWorkItem { [weak self] in
                guard let self, "\(self.trackName)|\(self.artistName)" == key else { return }
                self.commitTrackCard()
            }
            cardCommitWorkItem = work
            DispatchQueue.main.asyncAfter(deadline: .now() + Self.cardArtworkWait, execute: work)
        }
    }

    /// 卡片推入的同一刻恢复切歌按钮；方向在推入动画结束后才复位，免得滑向错误一侧。
    private func commitTrackCard() {
        cardCommitWorkItem?.cancel()
        cardCommitWorkItem = nil
        trackCard = TrackCard(title: trackName, artist: artistName, artwork: albumArt,
                              animated: nextCardAnimated)
        nextCardAnimated = true
        unlockSkips()
        resetSkipDirection(after: Self.skipSettleDelay)
    }

    // MARK: - QQ 音乐播放栏曲名

    /// 切歌命令发出后短暂轮询播放栏（单次约 0.1ms），用来尽早确认播放器收到了命令：
    /// 播放栏约 0.3s 就换歌，MediaRemote 要约 0.7s。确认后就不再补发。
    /// 显示仍以 MediaRemote 为准，卡片要等封面一起到齐。
    private func startEarlyTitleWatch() {
        stopEarlyTitleWatch()
        guard currentSessionBundleIdentifier == QQMusicTitleReader.bundleIdentifier,
              let baseline = qqTitleReader.read() else { return }
        let startedAt = Date()
        let timer = Timer(timeInterval: Self.earlyTitlePollInterval, repeats: true) { [weak self] _ in
            guard let self else { return }
            guard self.isSkipLocked,
                  Date().timeIntervalSince(startedAt) < Self.skipConfirmTimeout else {
                self.stopEarlyTitleWatch()
                return
            }
            guard let current = self.qqTitleReader.read(),
                  current.title != baseline.title || current.artist != baseline.artist else { return }
            self.stopEarlyTitleWatch()
            self.skipRetryWorkItem?.cancel()
            self.skipRetryWorkItem = nil
        }
        RunLoop.main.add(timer, forMode: .common)
        earlyTitleTimer = timer
    }

    private func stopEarlyTitleWatch() {
        earlyTitleTimer?.invalidate()
        earlyTitleTimer = nil
    }

    // MARK: - perl adapter 按需推送

    /// 轮盘打开或播放意图等待期间运行 `stream --no-diff`，其余时间不留进程。
    private func updateAdapterStream() {
        let needed = isObserving && Self.adapterAvailable
            && (isMenuPresented || pendingPlaybackIntent != nil)
        if needed {
            startAdapterStream()
        } else {
            stopAdapterStream()
        }
    }

    private func startAdapterStream() {
        guard adapterStreamProcess == nil,
              let perl = Self.perlURL,
              let script = Self.adapterScriptURL,
              let framework = Self.adapterFrameworkURL else { return }
        adapterStreamRestartWorkItem?.cancel()
        adapterStreamRestartWorkItem = nil

        let observationID = observationID
        let buffer = LineBuffer()
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = perl
        // --no-diff：每行都是完整快照，解析无需维护增量合并状态。
        process.arguments = [script.path, framework.path, "stream", "--no-diff"]
        process.standardOutput = output
        process.standardError = errorOutput

        errorOutput.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
        }

        output.fileHandleForReading.readabilityHandler = { [weak self, weak process] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let lines = buffer.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, let process,
                      self.isObserving, self.observationID == observationID,
                      self.adapterStreamProcess === process else { return }
                for line in lines {
                    self.handleAdapterStreamLine(line)
                }
            }
        }

        process.terminationHandler = { [weak self] finished in
            output.fileHandleForReading.readabilityHandler = nil
            let status = finished.terminationStatus
            let wasSignal = finished.terminationReason == .uncaughtSignal
            DispatchQueue.main.async {
                guard let self, self.adapterStreamProcess === finished else { return }
                self.adapterStreamDidTerminate(status: status, wasSignal: wasSignal,
                                               observationID: observationID)
            }
        }

        do {
            try process.run()
            adapterStreamProcess = process
            adapterStreamStartDate = Date()
        } catch {
            output.fileHandleForReading.readabilityHandler = nil
            errorOutput.fileHandleForReading.readabilityHandler = nil
            recordAdapterFailure()
        }
    }

    private func stopAdapterStream() {
        adapterStreamRestartWorkItem?.cancel()
        adapterStreamRestartWorkItem = nil
        guard let process = adapterStreamProcess else { return }
        process.terminationHandler = nil
        (process.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
        if process.isRunning { process.terminate() }
        adapterStreamProcess = nil
    }

    private func adapterStreamDidTerminate(status: Int32, wasSignal: Bool, observationID: UUID) {
        adapterStreamProcess = nil
        let uptime = Date().timeIntervalSince(adapterStreamStartDate)
        NSLog("dok.nowPlaying: adapter stream exited %@=%d uptime=%.1fs",
              wasSignal ? "signal" : "code", status, uptime)
        guard isObserving, self.observationID == observationID else { return }

        // 刚启动就退出视为一次失败；仍需要推送时稍后重启，失败累计后交给兜底。
        if uptime < 1 { recordAdapterFailure() }
        guard adapterUsable else { return }
        let restart = DispatchWorkItem { [weak self] in
            guard let self, self.observationID == observationID else { return }
            self.adapterStreamRestartWorkItem = nil
            self.updateAdapterStream()
        }
        adapterStreamRestartWorkItem = restart
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: restart)
    }

    private func handleAdapterStreamLine(_ line: Data) {
        guard let snapshot = Self.parseAdapterStreamLine(line) else { return }
        acceptAdapterSnapshot(snapshot)
    }

    /// 任一 perl 读取成功：它是权威来源，兜底 helper 不再需要。
    private func acceptAdapterSnapshot(_ snapshot: NowPlayingSnapshot) {
        adapterFailures = 0
        canSeek = true
        if helperProcess != nil { stopHelper() }
        fulfillPendingPlaybackIntent(
            using: snapshot,
            reportedBundleIdentifier: reportedBundleIdentifier(for: snapshot)
        )
        apply(snapshot)
    }

    private func recordAdapterFailure() {
        adapterFailures += 1
        NSLog("dok.nowPlaying: adapter failure %d/%d", adapterFailures, Self.adapterFailureLimit)
        if !adapterUsable {
            canSeek = false
            stopAdapterStream()
            startHelper()
        }
    }

    private func readAdapterOnce() {
        guard isObserving, adapterReadProcess == nil,
              let perl = Self.perlURL,
              let script = Self.adapterScriptURL,
              let framework = Self.adapterFrameworkURL else { return }

        let observationID = observationID
        let process = Process()
        let output = Pipe()
        let errorOutput = Pipe()
        process.executableURL = perl
        process.arguments = [script.path, framework.path, "get"]
        process.standardOutput = output
        process.standardError = errorOutput

        let startedAt = Date()
        do {
            try process.run()
        } catch {
            finishAdapterRead(status: -1, wasSignal: false, output: Data(),
                              errorText: "launch failed: \(error.localizedDescription)",
                              startedAt: startedAt, observationID: observationID)
            return
        }
        adapterReadProcess = process

        // Artwork makes the payload larger than a pipe buffer, so drain while it runs.
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            let data = output.fileHandleForReading.readDataToEndOfFile()
            let errorData = errorOutput.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let status = process.terminationStatus
            let wasSignal = process.terminationReason == .uncaughtSignal
            DispatchQueue.main.async {
                self?.finishAdapterRead(status: status, wasSignal: wasSignal, output: data,
                                        errorText: String(decoding: errorData, as: UTF8.self),
                                        startedAt: startedAt, observationID: observationID)
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.adapterReadTimeout) { [weak process] in
            if let process, process.isRunning { process.terminate() }
        }
    }

    private func finishAdapterRead(
        status: Int32,
        wasSignal: Bool,
        output: Data,
        errorText: String,
        startedAt: Date,
        observationID: UUID
    ) {
        adapterReadProcess = nil
        let elapsed = Date().timeIntervalSince(startedAt)
        guard isObserving, self.observationID == observationID else { return }

        guard status == 0, !wasSignal else {
            NSLog("dok.nowPlaying: adapter get failed %@=%d in %.0fms",
                  wasSignal ? "signal" : "code", status, elapsed * 1000)
            recordAdapterFailure()
            return
        }
        acceptAdapterSnapshot(Self.parseAdapterOutput(output))
    }

    private func handleSystemWake() {
        guard isObserving else { return }
        NSLog("dok.nowPlaying: system woke; refreshing sources")
        readAdapterOnce()
        // 睡眠可能让常驻 helper 失联而不退出，唤醒后直接重启。
        if helperProcess != nil {
            stopHelper()
        }
        helperRetryDelay = 0
        startHelper()
    }

    // MARK: - 常驻兜底 helper（Swift 工具链）

    private func startHelper() {
        guard isObserving, !adapterUsable, Self.residentHelperAvailable else { return }
        guard helperProcess == nil else { return }
        helperRestartWorkItem?.cancel()
        helperRestartWorkItem = nil
        launchHelper()
    }

    /// 唤出时常驻 helper 在跑、播放器也在、却没有曲目：视为失联，重启它。
    private func healResidentHelperOnPresentation() {
        guard !adapterUsable, Self.residentHelperAvailable else { return }
        if helperProcess == nil {
            // 跳过退避等待：用户此刻正需要数据。
            startHelper()
            return
        }
        let uptime = Date().timeIntervalSince(helperStartDate)
        guard trackName.isEmpty, runningMusicApp != nil, uptime > 5 else { return }
        NSLog("dok.nowPlaying: resident helper has no data on summon; restarting")
        stopHelper()
        startHelper()
    }

    private func launchHelper() {
        guard isObserving,
              let swiftURL = Self.helperSwiftURL,
              let scriptURL = Self.helperScriptURL else { return }
        let observationID = observationID
        do {
            try Self.helperScript.write(to: scriptURL, atomically: true, encoding: .utf8)
        } catch {
            NSLog("⚠️ 无法写入 now playing helper 脚本: %@", error.localizedDescription)
            return
        }
        // Each process owns its buffer, so an old pipe cannot mix partial JSON
        // into a replacement helper after a quick off/on toggle.
        let helperBuffer = LineBuffer()

        let proc = Process()
        let pipe = Pipe()
        let errorPipe = Pipe()
        proc.executableURL = swiftURL
        proc.arguments = [scriptURL.path]
        proc.standardOutput = pipe
        proc.standardError = errorPipe

        // The handler removes itself at EOF, so output printed while the helper
        // dies is still delivered and nothing blocks on a pipe a child holds open.
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else {
                handle.readabilityHandler = nil
                return
            }
        }

        pipe.fileHandleForReading.readabilityHandler = { [weak self, weak proc] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            let lines = helperBuffer.append(chunk)
            guard !lines.isEmpty else { return }
            DispatchQueue.main.async {
                guard let self, let proc,
                      self.isObserving, self.observationID == observationID,
                      self.helperProcess === proc else { return }
                for line in lines {
                    self.handleHelperLine(line)
                }
            }
        }

        proc.terminationHandler = { [weak self] finishedProcess in
            pipe.fileHandleForReading.readabilityHandler = nil
            let status = finishedProcess.terminationStatus
            let wasSignal = finishedProcess.terminationReason == .uncaughtSignal
            DispatchQueue.main.async {
                guard let self, self.isObserving, self.observationID == observationID,
                      self.helperProcess === finishedProcess else { return }
                self.recordHelperExit(status: status, wasSignal: wasSignal)
                self.helperDidTerminate()
            }
        }

        do {
            try proc.run()
            helperProcess = proc
            helperStartDate = Date()
            NSLog("dok.nowPlaying: resident helper launched pid=%d", proc.processIdentifier)
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            errorPipe.fileHandleForReading.readabilityHandler = nil
            proc.terminationHandler = nil
            NSLog("⚠️ 无法启动 now playing helper: %@", error.localizedDescription)
            helperProcess = nil
            scheduleHelperRestart(quickFailure: true)
        }
    }

    private func stopHelper() {
        helperRestartWorkItem?.cancel()
        helperRestartWorkItem = nil
        if let proc = helperProcess {
            proc.terminationHandler = nil
            (proc.standardOutput as? Pipe)?.fileHandleForReading.readabilityHandler = nil
            if proc.isRunning { proc.terminate() }
        }
        helperProcess = nil
    }

    private func recordHelperExit(status: Int32, wasSignal: Bool) {
        let uptime = Date().timeIntervalSince(helperStartDate)
        NSLog("dok.nowPlaying: resident helper exited %@=%d uptime=%.1fs",
              wasSignal ? "signal" : "code", status, uptime)
    }

    private func helperDidTerminate() {
        helperProcess = nil
        guard isObserving else { return }
        let uptime = Date().timeIntervalSince(helperStartDate)
        scheduleHelperRestart(quickFailure: uptime < 5)
    }

    /// 快速失败按 30s 起翻倍退避（上限 5 分钟），不再永久放弃；
    /// 运行良久后的偶发退出 3 秒后重启并清零退避。
    private func scheduleHelperRestart(quickFailure: Bool) {
        guard isObserving, !adapterUsable, Self.residentHelperAvailable else { return }
        helperRetryDelay = quickFailure
            ? min(max(helperRetryDelay * 2, 30), Self.helperMaxRetryDelay)
            : 0
        let delay = quickFailure ? helperRetryDelay : 3
        NSLog("dok.nowPlaying: resident helper restart in %.0fs", delay)

        helperRestartWorkItem?.cancel()
        let observationID = observationID
        let restart = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving,
                  self.observationID == observationID else { return }
            self.helperRestartWorkItem = nil
            self.startHelper()
        }
        helperRestartWorkItem = restart
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: restart)
    }

    private func handleHelperLine(_ line: Data) {
        guard isObserving, let snapshot = Self.parseSnapshot(line) else { return }
        apply(snapshot)
    }

    // MARK: - 进程内直读

    /// - Parameter applyEmpty: 读到空结果时是否据此清理。
    ///   仅在没有常驻 helper 时为真 —— helper 在运行时它才是权威数据源，
    ///   直读被系统限制返回的空值不能用来覆盖它。
    private func directRead(applyEmpty: Bool = false) {
        guard isObserving else { return }
        let observationID = observationID
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
            guard let self, self.isObserving,
                  self.observationID == observationID else { return }
            getPlaying(.main) { [weak self] playing in
                guard let self, self.isObserving,
                      self.observationID == observationID else { return }
                getInfo(.main) { [weak self] info in
                    guard let self, self.isObserving,
                          self.observationID == observationID else { return }
                    let title = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String ?? ""
                    // 直读被系统限制时会返回空。此时不要覆盖 helper 推来的数据。
                    guard !title.isEmpty else {
                        if applyEmpty { self.scheduleClear() }
                        return
                    }
                    self.apply(NowPlayingSnapshot(
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
        guard isObserving else { return }
        // helper 在跑时它是权威来源，直读的空结果不参与清理。
        directRead(applyEmpty: helperProcess == nil && !Self.adapterAvailable)

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
    /// 解析 perl adapter 一次性 `get` 的输出。没有正在播放的内容时它输出 `null`，
    /// 得到空快照，交给 apply() 走延迟清理。
    private static func parseAdapterOutput(_ data: Data) -> NowPlayingSnapshot {
        let payload = (try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]))
            as? [String: Any]
        return parseAdapterPayload(payload ?? [:])
    }

    /// 解析 `stream --no-diff` 的一行：`{"type":"data","payload":{...}}`。
    /// 启动时的首行 payload 为空，随后约 5ms 内送达完整数据；空快照只会触发可取消的延迟清理。
    private static func parseAdapterStreamLine(_ data: Data) -> NowPlayingSnapshot? {
        guard !data.isEmpty,
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              json["type"] as? String == "data",
              let payload = json["payload"] as? [String: Any] else {
            return nil
        }
        return parseAdapterPayload(payload)
    }

    private static func parseAdapterPayload(_ payload: [String: Any]) -> NowPlayingSnapshot {
        NowPlayingSnapshot(
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
        guard isObserving else { return }
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
            nextCardAnimated = isSkipLocked || (isMenuPresented && hasSnapshotSincePresentation)
            noteTrackChange(from: trackName)
            if !trackName.isEmpty {
                cancelPendingPlaybackIntent()
            }
            clearProgress()
        }
        trackName = snapshot.title
        artistName = snapshot.artist
        hasNowPlaying = true
        currentSessionBundleIdentifier = reportedBundleID

        // 冻结期内不覆盖 isPlaying，防止命令刚发出就被旧状态回弹（切歌途中播放器会
        // 短暂报告暂停）。新曲目的快照不受冻结：它的播放状态就是切歌后的真实状态。
        // 冻结中收到的状态在冻结结束时补上——stream 只在变化时推送，不会再发一次。
        lastReportedPlaying = snapshot.playing
        if trackChanged || Date() > playingFrozenUntil {
            playingReapplyWorkItem?.cancel()
            playingReapplyWorkItem = nil
            setPlaying(snapshot.playing)
        } else {
            schedulePlayingReapply()
        }

        applyProgress(snapshot, trackChanged: trackChanged)
        applyArtwork(snapshot, trackChanged: trackChanged)
        updateTrackCard()
        if isMenuPresented { hasSnapshotSincePresentation = true }
    }

    private func setPlaying(_ playing: Bool) {
        guard isPlaying != playing else { return }
        isPlaying = playing
        resetDisplayedProgressTracking()
    }

    private func schedulePlayingReapply() {
        playingReapplyWorkItem?.cancel()
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving else { return }
            self.playingReapplyWorkItem = nil
            if let reported = self.lastReportedPlaying { self.setPlaying(reported) }
        }
        playingReapplyWorkItem = work
        let delay = max(0, playingFrozenUntil.timeIntervalSinceNow) + 0.01
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
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
            // --no-diff 每份快照都带完整封面（播放/暂停变化也会重发同一份）。
            // 字节没变就保留原图片对象：换成新对象会让轮盘把它当成新封面，重播显影动画。
            if albumArt == nil || fingerprint != lastAppliedArtworkFingerprint {
                albumArt = NSImage(data: artData)
            }
        } else if trackChanged {
            albumArt = nil
        }
    }

    private func scheduleArtworkSettle(trackKey: String, data: Data) {
        artworkSettleWorkItem?.cancel()
        let observationID = observationID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving,
                  self.observationID == observationID else { return }
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
        guard isObserving else { return }
        guard !trackName.isEmpty else {
            if runningMusicApp == nil {
                clearNowPlaying()
            } else {
                hasNowPlaying = true
            }
            return
        }
        guard pendingClearWorkItem == nil else { return }

        let observationID = observationID
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.isObserving,
                  self.observationID == observationID else { return }
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
        updateTrackCard()
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
