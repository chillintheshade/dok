#!/usr/bin/env python3
"""Verify production key sequences and Codable data without sending keyboard events."""
from pathlib import Path
import subprocess
import tempfile
ROOT = Path(__file__).resolve().parents[1]
source = (ROOT / 'Sources/dok/AppState.swift').read_text()
config = source[source.index('struct HotkeyConfig:'):source.index('\nstruct AppSettings:')]
types = source[source.index('enum WheelItemType:'):source.index('\nstruct AppItem:')]
harness = r'''
precondition(KeyActionService.executionError(held: false, mouseHeld: false, wheelReady: true, focused: true, terminated: false) == nil)
precondition(KeyActionService.executionError(held: false, mouseHeld: true, wheelReady: true, focused: true, terminated: false) == "keyAction.releaseError")
precondition(KeyActionService.executionError(held: false, mouseHeld: false, wheelReady: false, focused: true, terminated: false) == "keyAction.wheelError")
precondition(KeyActionService.executionError(held: false, mouseHeld: false, wheelReady: true, focused: false, terminated: false) == "keyAction.targetError")
precondition(KeyActionService.executionError(held: false, mouseHeld: false, wheelReady: true, focused: true, terminated: true) == "keyAction.targetError")
precondition(!KeyActionService.hasHeldModifiers([]))
precondition(!KeyActionService.hasHeldModifiers([.maskAlphaShift, .maskSecondaryFn, .maskNonCoalesced]))
for flag: CGEventFlags in [.maskCommand, .maskControl, .maskAlternate, .maskShift] {
    precondition(KeyActionService.hasHeldModifiers(flag))
}
let captured = KeyActionService.recordedCombination(keyCode: 0, modifiers: [.command, .control, .capsLock, .numericPad])!
precondition(captured.keyCode == 0 && captured.modifiers == [.command, .control])
precondition(KeyActionService.recordedCombination(keyCode: 0, modifiers: []) == nil)
precondition(KeyActionService.recordedCombination(keyCode: 55, modifiers: [.command]) == nil)
precondition(KeyActionService.recordedCombination(keyCode: 65535, modifiers: [.command]) == nil)
let original = HotkeyConfig(keyCode: 18, modifiers: [.command, .shift, .control])
let restored = try JSONDecoder().decode(HotkeyConfig.self, from: JSONEncoder().encode(original))
precondition(original == restored)
precondition(restored.displayString == "⌃⇧⌘1")
precondition(try JSONDecoder().decode(WheelItemType.self, from: Data("\"shortcut\"".utf8)) == .keyAction)
let events = KeyActionService.events(keyCode: 18, modifiers: original.modifiers)
precondition(events.map { $0.getIntegerValueField(.keyboardEventKeycode) } == [59, 56, 55, 18, 18, 55, 56, 59])
precondition(events[3].type == .keyDown && events[4].type == .keyUp)
precondition(events[3].flags == [.maskControl, .maskShift, .maskCommand])
precondition(events[5].flags == [.maskControl, .maskShift])
precondition(events.last!.flags.isEmpty)
precondition(events.allSatisfy { $0.getIntegerValueField(.keyboardEventAutorepeat) == 0 })
precondition(KeyActionService.events(keyCode: 55, modifiers: [.command]).isEmpty)
precondition(KeyActionService.events(keyCode: 65535, modifiers: [.command]).isEmpty)
precondition(KeyActionService.events(keyCode: 0, modifiers: [.shift]).isEmpty)
for flags: NSEvent.ModifierFlags in [[.command], [.control, .option], [.command, .control, .option, .shift]] {
    let keys = KeyActionService.events(keyCode: 0, modifiers: flags)
    precondition(keys.count >= 4 && keys.last!.flags.isEmpty)
    let codes = keys.map { $0.getIntegerValueField(.keyboardEventKeycode) }
    precondition(Array(codes.prefix(codes.count / 2)) == Array(codes.suffix(codes.count / 2).reversed()))
}
print("Keyboard action encoding, legacy decoding, event ordering, flags and rejection checks passed.")
'''
# Throwing decode must be evaluated outside the nonthrowing precondition autoclosure.
harness = harness.replace('precondition(try JSONDecoder().decode(WheelItemType.self, from: Data("\\\"shortcut\\\"".utf8)) == .keyAction)', 'let legacy = try JSONDecoder().decode(WheelItemType.self, from: Data("\\\"shortcut\\\"".utf8))\nprecondition(legacy == .keyAction)')
with tempfile.TemporaryDirectory(prefix='key-action-test-', dir=ROOT / 'work') as temporary:
    directory = Path(temporary)
    (directory / 'models.swift').write_text('import AppKit\nimport Carbon\n' + types + config)
    (directory / 'notification.swift').write_text('import Foundation\nextension Notification.Name { static let hotkeyChanged = Notification.Name("test.hotkey") }')
    (directory / 'main.swift').write_text('import AppKit\n' + harness)
    compiler = subprocess.check_output(['xcrun', '--find', 'swiftc'], text=True).strip()
    executable = directory / 'checks'
    subprocess.run([compiler, '-swift-version', '5', str(ROOT / 'Sources/dok/KeyActionService.swift'), str(ROOT / 'Sources/dok/Localization.swift'), str(directory / 'models.swift'), str(directory / 'notification.swift'), str(directory / 'main.swift'), '-o', str(executable)], check=True)
    subprocess.run([str(executable)], check=True, timeout=10)
