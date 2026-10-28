#!/usr/bin/env python3
"""按需推送契约：唤出时启动 stream、收起即停；切歌等待态；常驻兜底自愈。"""
from pathlib import Path
import re


ROOT = Path(__file__).resolve().parents[1]
SERVICE = (ROOT / "Sources" / "dok" / "NowPlayingService.swift").read_text()
WINDOW = (ROOT / "Sources" / "dok" / "DokWheelWindow.swift").read_text()
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()


def body(signature: str) -> str:
    match = re.search(re.escape(signature) + r" \{(?P<body>.*?)\n    \}\n", SERVICE, re.S)
    assert match, f"{signature} not found"
    return match.group("body")


def main() -> None:
    present = body("func refreshForMenuPresentation()")
    for needle in ["isMenuPresented = true", "updateAdapterStream()", "healResidentHelperOnPresentation()"]:
        assert needle in present, f"summon must run: {needle}"

    dismiss = body("func menuDidDismiss()")
    assert "isMenuPresented = false" in dismiss and "updateAdapterStream()" in dismiss
    hide = WINDOW.split("private func finishHiding() {", 1)[1].split("override func order(", 1)[0]
    assert "appState.nowPlaying.menuDidDismiss()" in hide, "hidden wheel ends its stream"

    start = body("private func startAdapterStream()")
    assert "guard adapterStreamProcess == nil" in start, "never more than one stream"
    assert "readabilityHandler" in start and "buffer.append(chunk)" in start, "stream is read line by line"
    stop = body("private func stopAdapterStream()")
    assert "process.terminate()" in stop and "process.terminationHandler = nil" in stop

    exited = body("private func adapterStreamDidTerminate(status: Int32, wasSignal: Bool, observationID: UUID)")
    assert "if uptime < 1 { recordAdapterFailure() }" in exited, "an instantly dying stream counts as failure"
    assert "asyncAfter" in exited, "an unexpected exit while still needed restarts after a delay"

    failure = body("private func recordAdapterFailure()")
    assert "startHelper()" in failure, "repeated failures enable the fallback"
    accept = body("private func acceptAdapterSnapshot(_ snapshot: NowPlayingSnapshot)")
    assert "if helperProcess != nil { stopHelper() }" in accept, "a recovered adapter retires the fallback"

    # 切歌锁：播放器切歌期间丢弃命令，按钮显示不可点；被拒的点击不发命令、不排队。
    for command, direction in [("func nextTrack()", ".forward"), ("func previousTrack()", ".backward")]:
        assert f"performSkip({direction})" in body(command)
    skip = body("private func performSkip(_ direction: SkipDirection)")
    assert skip.index("guard !isSkipLocked else {") < skip.index("sendSkipCommand("), \
        "a locked press never reaches the player"
    assert "SkipEvent(direction: direction, accepted: false)" in skip, "rejected press gets feedback"
    assert "lockSkips(for: delay + Self.skipConfirmTimeout)" in skip
    # 按钮随新曲目恢复；播放器余下的忙碌期里按下的那一次延后发送，而不是被丢弃。
    assert "let delay = max(0, skipCommandReadyAt.timeIntervalSinceNow)" in skip
    assert "deferredSkipWorkItem = work" in skip
    assert "skipQueue" not in SERVICE and "pendingSkips" not in SERVICE, "presses are never queued"
    assert "noteTrackChange(from: trackName)" in SERVICE.split("let trackChanged = trackName != snapshot.title", 1)[1][:800]

    # 切歌后：新曲目快照的播放状态不受冻结；冻结中收到的状态在结束时补上。
    assert "if trackChanged || Date() > playingFrozenUntil {" in SERVICE
    assert "schedulePlayingReapply()" in SERVICE and "lastReportedPlaying = snapshot.playing" in SERVICE

    # QQ 播放栏只用来尽早确认命令已被接收（取消补发），不再提前改显示。
    send = body("private func sendSkipCommand(_ direction: SkipDirection, isRetry: Bool)")
    assert "startEarlyTitleWatch()" in send
    assert "sendSkipCommand(direction, isRetry: false)" in body("private func performSkip(_ direction: SkipDirection)")
    watch = body("private func startEarlyTitleWatch()")
    assert "self.skipRetryWorkItem?.cancel()" in watch
    assert "trackName =" not in watch and "applyEarlyTitle" not in SERVICE, "play bar never drives the display"
    reader = (ROOT / "Sources" / "dok" / "QQMusicTitleReader.swift").read_text()
    assert 'titlePrefix = "歌曲名："' in reader and 'artistSeparator = " - 歌手名："' in reader
    assert "AXIsProcessTrusted()" in reader and "queue.async" in reader, "tree search stays off the main thread"

    # 播放器偶尔无故丢命令：没确认就补发，且只补一次，避免多切。
    assert "scheduleSkipRetry(direction)" in send
    assert "diagnostics" not in SERVICE, "the diagnostics feature was removed"
    retry = body("private func scheduleSkipRetry(_ direction: SkipDirection)")
    assert "self.sendSkipCommand(direction, isRetry: true)" in retry
    assert "self.trackName == shownTitle" in retry, "a confirmed skip is never resent"
    assert "skipRetryWorkItem?.cancel()" in body("private func noteTrackChange(from previousTitle: String)")
    assert "private static let skipRetryDelayWithTitle: TimeInterval = 0.8" in SERVICE

    # 曲目卡片：曲名、歌手、封面一起切换；封面到齐（或等待 0.6s 无果）才提交。
    update = body("private func updateTrackCard()")
    assert "if let art = albumArt, card.artwork !== art {" in update, "late artwork updates the card in place"
    assert "if albumArt != nil {\n            commitTrackCard()" in update, "a new track commits once its cover is here"
    assert "Self.cardArtworkWait" in update and "private static let cardArtworkWait: TimeInterval = 0.6" in SERVICE
    assert "didSet { updateTrackCard() }" in SERVICE and "applyArtwork(snapshot, trackChanged: trackChanged)\n        updateTrackCard()" in SERVICE
    assert "if albumArt == nil || fingerprint != lastAppliedArtworkFingerprint {" in SERVICE, \
        "identical artwork bytes must keep the same image object, or the cover crossfades for nothing"

    # 按钮与卡片推入同时恢复；方向在推入结束后才复位。
    commit = body("private func commitTrackCard()")
    assert commit.index("trackCard = TrackCard(") < commit.index("unlockSkips()")
    assert "resetSkipDirection(after: Self.skipSettleDelay)" in commit
    note = body("private func noteTrackChange(from previousTitle: String)")
    assert "skipCommandReadyAt = Date().addingTimeInterval(Self.skipSettleDelay)" in note
    assert "unlockSkips()" not in note, "buttons wait for the card, not the bare title"
    assert "skipDirection = .forward" not in body("private func unlockSkips()")
    assert "private static let skipSettleDelay: TimeInterval = 0.6" in SERVICE
    assert "private static let skipConfirmTimeout: TimeInterval = 2" in SERVICE
    assert "isArtworkPending" not in SERVICE and "isArtworkPending" not in VIEW

    # 视图：不可点态、轻缩/轻晃反馈、整张卡片左右紧挨着推入，边缘渐隐。
    assert "isAwaitingTrackChange" not in SERVICE and "isAwaitingTrackChange" not in VIEW
    assert "hovered && !locked" in VIEW and "MenuMotion.skipLockedOpacity" in VIEW
    assert "locked ? .easeOut(duration: 0.15) : MenuMotion.trackPushAnimation" in VIEW, \
        "unlock shares the push curve so both settle together"
    assert "private struct ShakeEffect: GeometryEffect" in VIEW
    assert ".id(trackInfoIdentity)" in VIEW and ".transition(trackInfoTransition)" in VIEW
    assert "nowPlaying.trackCard?.id.uuidString" in VIEW, "the card, not the raw title, drives the push"
    assert "insertion: .offset(x: width * sign)" in VIEW and "removal: .offset(x: -width * sign)" in VIEW, \
        "old and new cards stay edge to edge: the push distance equals the card width"
    assert ".mask(trackPushMask)" in VIEW
    artwork = VIEW.split("private func musicArtwork(_ artwork: NSImage?) -> some View {", 1)[1].split("\n    }\n", 1)[0]
    assert ".blur(" not in artwork and ".blur(" not in VIEW.split("private var trackPushMask", 1)[1][:600], \
        "blur flickers in the transparent wheel window"
    assert "nowPlaying.skipDirection == .forward ? 1 : -1" in VIEW
    assert "guard !reduceMotion else { return .opacity }" in VIEW, "reduce motion keeps only the fade"

    # 长曲名：向左滑到末尾完整露出，停一下再滑回开头，然后停住；不循环。
    title = VIEW.split("private struct OverflowTitle: View {", 1)[1].split("/// 每增加 1 晃动两个来回", 1)[0]
    assert "if overflow > 0 && !reduceMotion {" in title
    assert "(Self.startDelay, -overflow)" in title and "(travel + Self.endPause, 0)" in title
    assert "while" not in title and "label\n                    label" not in title, "plays once, never loops"
    assert "guard isActive, overflow > 0, !reduceMotion else { return }" in title
    assert "isActive: appState.isMenuVisible" in VIEW, "the reveal plays only while the wheel is visible"
    assert ".truncationMode(.tail)" in title
    # 宽度同步算出，新卡片首帧就是最终排版，歌名随封面一起推入，不会中途跳一下。
    assert "NSFont.systemFont(ofSize: fontSize, weight: .medium)" in title
    assert "onPreferenceChange" not in title and "TitleWidthKey" not in VIEW

    # 收起期间换的歌：打开时直接显示，不推入；只有看着轮盘时换歌（或自己切歌）才推入。
    assert "hasSnapshotSincePresentation = false" in present and "hasSnapshotSincePresentation = false" in dismiss
    assert "nextCardAnimated = isSkipLocked || (isMenuPresented && hasSnapshotSincePresentation)" in SERVICE
    assert "if isMenuPresented { hasSnapshotSincePresentation = true }" in SERVICE
    assert "animated: nextCardAnimated" in body("private func commitTrackCard()")
    assert "nowPlaying.trackCard?.animated == false ? nil : trackInfoAnimation" in VIEW

    heal = body("private func healResidentHelperOnPresentation()")
    assert "trackName.isEmpty, runningMusicApp != nil" in heal, "no data on summon restarts the fallback"
    wake = body("private func handleSystemWake()")
    assert "stopHelper()" in wake and "startHelper()" in wake and "readAdapterOnce()" in wake
    assert "NSWorkspace.didWakeNotification" in SERVICE

    print("Now-playing on-demand contract passed.")


if __name__ == "__main__":
    main()
