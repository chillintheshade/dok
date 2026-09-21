#!/usr/bin/env python3
"""Exercise the actual Swift service across disabled, enabled, and resumed states.

A disposable sleep process occupies the helper slot so the test never launches
a metadata helper or modifies the user's playback. All temporary files and child
processes are removed after the test.
"""
from pathlib import Path
import subprocess
import tempfile


ROOT = Path(__file__).resolve().parents[1]
SERVICE = ROOT / "Sources/dok/NowPlayingService.swift"
SWIFTC = Path("/Library/Developer/CommandLineTools/usr/bin/swiftc")

HARNESS = r'''

extension NowPlayingService {
    static func verifyObservationToggle() throws {
        let service = NowPlayingService()
        var children: [Process] = []
        defer {
            service.stopObserving()
            for child in children where child.isRunning {
                child.terminate()
            }
        }

        func placeholderHelper() throws -> Process {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/bin/sleep")
            process.arguments = ["20"]
            try process.run()
            children.append(process)
            return process
        }

        service.setObservationEnabled(false)
        service.refreshForMenuPresentation()
        service.backendQueue = [.swiftToolchain]
        service.startHelper()
        precondition(!service.isObserving && service.helperProcess == nil)
        precondition(service.upkeepTimer == nil)
        precondition(!Self.mrRegistered, "disabled startup must not subscribe to MediaRemote")

        let originalHelper = try placeholderHelper()
        service.helperProcess = originalHelper
        service.trackName = "Existing track"
        service.artistName = "Existing artist"
        let originalArtwork = NSImage(size: NSSize(width: 1, height: 1))
        service.albumArt = originalArtwork
        service.setObservationEnabled(true)
        precondition(service.isObserving && service.upkeepTimer?.isValid == true)
        precondition(service.helperProcess === originalHelper)
        let originalObservationID = service.observationID
        let originalTimer = service.upkeepTimer
        service.setObservationEnabled(true)
        precondition(service.observationID == originalObservationID)
        precondition(service.upkeepTimer === originalTimer, "enabling twice must not duplicate timers")

        service.scheduleClear()
        precondition(service.pendingClearWorkItem != nil)
        service.scheduleArtworkSettle(trackKey: "Existing track|Existing artist", data: Data())
        precondition(service.artworkSettleWorkItem != nil)
        service.setObservationEnabled(false)
        precondition(!service.isObserving && service.helperProcess == nil)
        precondition(service.upkeepTimer == nil && originalTimer?.isValid == false)
        precondition(service.pendingClearWorkItem == nil && service.artworkSettleWorkItem == nil)
        precondition(service.helperRestartWorkItem == nil)
        precondition(service.observationID != originalObservationID)
        precondition(service.trackName == "Existing track" && service.albumArt === originalArtwork,
                     "disabling must preserve cached metadata without a visual reset")

        let disabledTrack = service.trackName
        service.apply(NowPlayingSnapshot(pid: 0, title: "Late old track", artist: "",
                                         playing: true, artworkData: nil))
        service.refreshForMenuPresentation()
        service.upkeep()
        service.startHelper()
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(!originalHelper.isRunning, "disabling must terminate the helper")
        precondition(service.trackName == disabledTrack && service.helperProcess == nil,
                     "queued reads must not update or resurrect a disabled service")

        let resumedHelper = try placeholderHelper()
        service.helperProcess = resumedHelper
        service.playingFrozenUntil = Date().addingTimeInterval(60)
        service.progressFrozenUntil = Date().addingTimeInterval(60)
        service.setObservationEnabled(true)
        precondition(service.isObserving && service.upkeepTimer?.isValid == true)
        precondition(service.observationID != originalObservationID)
        precondition(service.trackName == disabledTrack && service.albumArt === originalArtwork)

        service.apply(NowPlayingSnapshot(pid: 0, title: "Existing track", artist: "Existing artist",
                                         playing: true, artworkData: nil, duration: 180,
                                         elapsedTime: 42, timestamp: Date(), playbackRate: 1))
        precondition(service.trackName == "Existing track" && service.isPlaying)
        precondition(service.duration == 180 && service.elapsedTime == 42,
                     "fresh progress must replace a same-track value after re-enabling")
        service.setObservationEnabled(false)
        RunLoop.main.run(until: Date().addingTimeInterval(0.2))
        precondition(!resumedHelper.isRunning)
        precondition(service.trackName == "Existing track" && service.elapsedTime == 42)
    }
}

try NowPlayingService.verifyObservationToggle()
print("Now-playing observation toggle behavior passed.")
'''


def main() -> None:
    compiler = SWIFTC
    if not compiler.is_file():
        compiler = Path("/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin/swiftc")
    with tempfile.TemporaryDirectory(prefix="now-playing-toggle-", dir=ROOT / "work") as temporary:
        directory = Path(temporary)
        source = directory / "main.swift"
        executable = directory / "observation-toggle-test"
        source.write_text("import Combine\n" + SERVICE.read_text() + HARNESS)
        subprocess.run([str(compiler), "-swift-version", "5", str(source), "-o", str(executable)], check=True)
        subprocess.run([str(executable)], check=True, timeout=20)


if __name__ == "__main__":
    main()
