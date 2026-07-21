// 常驻 now-playing helper —— 可读副本。
//
// 运行时 Arcly 会把这段代码写到 Application Support 并交给 Swift 工具链执行
// （见 NowPlayingService.helperScript）。此文件不参与构建，仅供阅读和单独调试：
//
//     swift Sources/Helper/mr_info.swift
//
// 之所以要借工具链的壳来跑：macOS 只向 Apple 签名的进程开放 MediaRemote 元数据，
// App 自身进程内直读通常返回空。
//
// 本文件由 work/arcly-now-playing-helper-sync-test.py 校验，
// 必须与 NowPlayingService.helperScript 逐字一致。

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
                let artworkID = artwork.map { "\($0.count)-\($0.hashValue)" } ?? "none"

                let trackKey = "\(pid)|\(title)|\(artist)"
                let identity = "\(trackKey)|\(playing)|\(artworkID)"
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
                    FileHandle.standardOutput.write(Data((str + "\n").utf8))
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
