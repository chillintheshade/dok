#!/usr/bin/env python3
"""Run the production close/reopen lifecycle with an inert application/window."""
from pathlib import Path
import subprocess
import tempfile

root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/dok/DokApp.swift').read_text()
start = source.index('    func windowWillClose(')
end = source.index('\n    @objc func quitApp()', start)
close = source[start:end]
start = source.index('    @objc func openSettings() {')
end = source.index('        setupMainMenu()', start)
reopen = source[start:end].replace('@objc ', '') + '    }\n'
harness = r'''
import Foundation
final class NSWindow: NSObject {}
enum Policy { case regular, accessory }
final class Application {
    var policy: Policy = .regular
    func setActivationPolicy(_ policy: Policy) { self.policy = policy }
}
let NSApp = Application()
enum NSEvent { static func removeMonitor(_ monitor: Any) {} }
final class Lifecycle {
    var settingsWindow: NSWindow?
    var settingsHostingController: Any?
    var settingsKeyMonitor: Any?
    var settingsDeactivationWorkItem: DispatchWorkItem?
    var settingsActivationGeneration = 0
'''
harness += close + reopen + r'''
}
let lifecycle = Lifecycle()
let first = NSWindow()
lifecycle.settingsWindow = first
lifecycle.windowWillClose(Notification(name: Notification.Name("close"), object: NSWindow()))
precondition(lifecycle.settingsWindow === first, "An unrelated close must not clear settings")
lifecycle.windowWillClose(Notification(name: Notification.Name("close"), object: first))
let second = NSWindow()
lifecycle.openSettings()
lifecycle.settingsWindow = second
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
precondition(NSApp.policy == .regular, "An old close must not demote reopened settings")
precondition(lifecycle.settingsWindow === second)
lifecycle.windowWillClose(Notification(name: Notification.Name("close"), object: second))
RunLoop.main.run(until: Date().addingTimeInterval(0.4))
precondition(NSApp.policy == .accessory, "A final close must still hide the Dock presence")
print("Settings lifecycle: unrelated close, rapid reopen and final close passed.")
'''
with tempfile.TemporaryDirectory(prefix='settings-lifecycle-', dir=root/'work') as tmp:
    main = Path(tmp)/'main.swift'
    main.write_text(harness)
    executable = Path(tmp)/'check'
    subprocess.run(['xcrun', 'swiftc', str(main), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
