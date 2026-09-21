import AppKit
import ApplicationServices
import Carbon.HIToolbox

/// Sends a balanced key sequence only after the wheel and physical modifiers are released.
enum KeyActionService {
    static var isRecording = false {
        didSet { NotificationCenter.default.post(name: .hotkeyChanged, object: nil) }
    }
    static func recordedCombination(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> HotkeyConfig? {
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        guard keyCode < 128, ![54,55,56,57,58,59,60,61,62,63].contains(keyCode),
              !flags.intersection([.command, .control, .option]).isEmpty else { return nil }
        return HotkeyConfig(keyCode: keyCode, modifiers: flags)
    }
    private static var executing = false

    static func hasHeldModifiers(_ flags: CGEventFlags) -> Bool {
        !flags.intersection([.maskCommand, .maskControl, .maskAlternate, .maskShift]).isEmpty
    }

    static func events(keyCode: UInt16, modifiers: NSEvent.ModifierFlags) -> [CGEvent] {
        guard keyCode < 128, ![54,55,56,57,58,59,60,61,62,63].contains(keyCode),
              !modifiers.intersection([.command, .control, .option]).isEmpty,
              let source = CGEventSource(stateID: .privateState) else { return [] }
        let keys: [(NSEvent.ModifierFlags, UInt16, CGEventFlags)] = [
            (.control, 59, .maskControl), (.option, 58, .maskAlternate),
            (.shift, 56, .maskShift), (.command, 55, .maskCommand),
        ]
        var sequence: [(UInt16, Bool, CGEventFlags)] = []
        var flags: CGEventFlags = []
        for (modifier, code, flag) in keys where modifiers.contains(modifier) {
            flags.insert(flag)
            sequence.append((code, true, flags))
        }
        sequence.append((keyCode, true, flags))
        sequence.append((keyCode, false, flags))
        for (modifier, code, flag) in keys.reversed() where modifiers.contains(modifier) {
            flags.remove(flag)
            sequence.append((code, false, flags))
        }
        let events = sequence.compactMap { code, down, flags -> CGEvent? in
            guard let event = CGEvent(keyboardEventSource: source, virtualKey: code, keyDown: down) else { return nil }
            event.flags = flags
            event.setIntegerValueField(.keyboardEventAutorepeat, value: 0)
            return event
        }
        return events.count == sequence.count ? events : []
    }

    static func openAccessibility() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    static func run(keyCode: UInt16, modifiers: NSEvent.ModifierFlags,
                    bundleIdentifier: String,
                    ready: @escaping () -> Bool = { true }) {
        guard !executing, !isRecording else { return }
        guard AXIsProcessTrusted() else { showError("keyAction.permission"); return }
        let sequence = events(keyCode: keyCode, modifiers: modifiers)
        guard !sequence.isEmpty else { return }
        executing = true
        if bundleIdentifier.isEmpty {
            // An unassigned slot sends a system shortcut without an app switch.
            // In particular, summoning from dok settings has no previous app.
            waitAndSend(sequence, target: nil, deadline: Date().addingTimeInterval(3), ready: ready)
        } else if let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first {
            prepare(sequence, target: running, ready: ready)
        } else if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { app, error in
                DispatchQueue.main.async {
                    guard error == nil, let app else { fail("keyAction.targetError"); return }
                    prepare(sequence, target: app, ready: ready)
                }
            }
        } else { fail("keyAction.targetError") }
    }

    private static func prepare(_ events: [CGEvent], target: NSRunningApplication?, ready: @escaping () -> Bool) {
        guard let target, !target.isTerminated,
              target.processIdentifier != ProcessInfo.processInfo.processIdentifier else {
            fail("keyAction.targetError"); return
        }
        if NSWorkspace.shared.frontmostApplication?.processIdentifier != target.processIdentifier {
            target.activate(options: [.activateIgnoringOtherApps])
        }
        waitAndSend(events, target: target, deadline: Date().addingTimeInterval(3), ready: ready)
    }

    static func executionError(held: Bool, mouseHeld: Bool, wheelReady: Bool, focused: Bool, terminated: Bool) -> String? {
        if held || mouseHeld { return "keyAction.releaseError" }
        if !wheelReady { return "keyAction.wheelError" }
        if !focused || terminated { return "keyAction.targetError" }
        return nil
    }

    private static func waitAndSend(_ events: [CGEvent], target: NSRunningApplication?, deadline: Date, ready: @escaping () -> Bool) {
        let physical = CGEventSource.flagsState(.hidSystemState)
        // The destination key is not the wheel trigger. Its cached keyState can
        // also remain down after intercepted recording events. Only modifiers
        // can contaminate the explicit, balanced shortcut we are about to send.
        let held = hasHeldModifiers(physical)
        let focused = target.map { NSWorkspace.shared.frontmostApplication?.processIdentifier == $0.processIdentifier } ?? true
        let mouseHeld = CGEventSource.buttonState(.hidSystemState, button: .left)
            || CGEventSource.buttonState(.hidSystemState, button: .right)
        let terminated = target?.isTerminated == true
        let error = executionError(held: held, mouseHeld: mouseHeld, wheelReady: ready(), focused: focused, terminated: terminated)
        if error == nil {
            events.forEach { $0.post(tap: .cghidEventTap) }
            executing = false
        } else if Date() >= deadline || terminated {
            fail(error!)
        } else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                waitAndSend(events, target: target, deadline: deadline, ready: ready)
            }
        }
    }

    private static func fail(_ key: String) { executing = false; showError(key) }
    static func showError(_ key: String) {
        let alert = NSAlert()
        alert.messageText = Loc.string("keyAction.error")
        alert.informativeText = Loc.string(key)
        if key == "keyAction.permission" { alert.addButton(withTitle: Loc.string("keyAction.openAccessibility")) }
        alert.addButton(withTitle: Loc.string("link.cancel"))
        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn, key == "keyAction.permission" { openAccessibility() }
    }
}


/// The native control owns focus, event sources and lifetime; SwiftUI only binds its value.
final class KeyActionRecorderControl: NSButton {
    var value: HotkeyConfig? { didSet { if !recording { refreshTitle() } } }
    var onChange: ((HotkeyConfig) -> Void)?
    var onRecordingChanged: ((Bool) -> Void)?
    private(set) var recording = false
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var monitor: Any?
    private var deactivateObserver: NSObjectProtocol?
    private var mode: UnsafeMutableRawPointer?
    private var capturedKey: UInt16?
    private var generation = UUID()
    override var acceptsFirstResponder: Bool { true }

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        bezelStyle = .rounded
        target = self
        action = #selector(toggleRecording)
        refreshTitle()
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func refreshTitle() { title = value?.displayString ?? Loc.string("keyAction.record") }

    @objc private func toggleRecording() {
        if recording { stop(reason: "cancel"); return }
        guard let window else { return }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKey()
        guard window.makeFirstResponder(self) else { return }
        guard AXIsProcessTrusted() else { KeyActionService.showError("keyAction.permission"); return }
        generation = UUID()
        capturedKey = nil
        let mask = (CGEventMask(1) << CGEventType.keyDown.rawValue) | (CGEventMask(1) << CGEventType.keyUp.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return Unmanaged<KeyActionRecorderControl>.fromOpaque(context).takeUnretainedValue().intercept(type: type, event: event)
        }
        // Prefer the earliest available position, ahead of third-party screenshot listeners.
        for location in [CGEventTapLocation.cghidEventTap, .cgSessionEventTap] {
            tap = CGEvent.tapCreate(tap: location, place: .headInsertEventTap, options: .defaultTap,
                eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque())
            if tap != nil { break }
        }
        guard let tap, let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            stop(reason: "tap-unavailable")
            KeyActionService.showError("keyAction.captureError")
            return
        }
        self.source = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        mode = PushSymbolicHotKeyMode(OptionBits(kHIHotKeyModeAllDisabled))
        recording = true
        KeyActionService.isRecording = true
        title = Loc.string("keyAction.recording")
        onRecordingChanged?(true)
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            guard let self, self.recording else { return event }
            guard event.window == nil || event.window === self.window || event.window === self.window?.sheetParent else { return event }
            self.receive(code: event.keyCode, modifiers: event.modifierFlags,
                         down: event.type == .keyDown, repeatKey: event.isARepeat)
            return nil
        }
        deactivateObserver = NotificationCenter.default.addObserver(forName: NSApplication.didResignActiveNotification, object: NSApp, queue: .main) { [weak self] _ in
            self?.stop(reason: "application-deactivated")
        }
        NSLog("dok.keyRecorder: started")
    }

    private func intercept(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard recording else { return Unmanaged.passUnretained(event) }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            stop(reason: "tap-disabled")
            return Unmanaged.passUnretained(event)
        }
        receive(code: UInt16(event.getIntegerValueField(.keyboardEventKeycode)),
                modifiers: NSEvent.ModifierFlags(rawValue: UInt(event.flags.rawValue)),
                down: type == .keyDown, repeatKey: event.getIntegerValueField(.keyboardEventAutorepeat) != 0)
        return nil
    }

    private func receive(code: UInt16, modifiers: NSEvent.ModifierFlags, down: Bool, repeatKey: Bool) {
        guard recording else { return }
        if !down {
            if capturedKey == code {
                // The actual release is authoritative; an intercepted key-up
                // need not be reflected in Quartz's accumulated state table.
                let expected = generation
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.generation == expected else { return }
                    self.stop(reason: "key-released")
                }
            }
            return
        }
        guard !repeatKey, capturedKey == nil else { return }
        let flags = modifiers.intersection([.command, .control, .option, .shift])
        if code == 53 && flags.isEmpty { stop(reason: "escape"); return }
        guard let result = KeyActionService.recordedCombination(keyCode: code, modifiers: flags) else {
            title = Loc.string("keyAction.needModifier")
            return
        }
        // Publish on key-down; never depend on receiving a matching key-up to save the value.
        capturedKey = code
        value = result
        title = result.displayString
        onChange?(result)
        NSLog("dok.keyRecorder: captured")
        finishAfterRelease()
    }

    private func finishAfterRelease() {
        let expected = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.02) { [weak self] in
            guard let self, self.recording, self.generation == expected, let code = self.capturedKey else { return }
            if CGEventSource.keyState(.hidSystemState, key: code) {
                self.finishAfterRelease()
            } else {
                self.stop(reason: "completed")
            }
        }
    }
    override func keyDown(with event: NSEvent) {
        if recording { receive(code: event.keyCode, modifiers: event.modifierFlags, down: true, repeatKey: event.isARepeat) }
        else { super.keyDown(with: event) }
    }
    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        guard recording else { return super.performKeyEquivalent(with: event) }
        receive(code: event.keyCode, modifiers: event.modifierFlags, down: true, repeatKey: event.isARepeat)
        return true
    }
    override func resignFirstResponder() -> Bool {
        stop(reason: "focus-left-control")
        return super.resignFirstResponder()
    }
    override func viewWillMove(toWindow newWindow: NSWindow?) {
        if newWindow == nil { stop(reason: "window-closed") }
        super.viewWillMove(toWindow: newWindow)
    }
    func stop(reason: String) {
        let wasRecording = recording
        recording = false
        generation = UUID()
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        if let deactivateObserver { NotificationCenter.default.removeObserver(deactivateObserver) }
        deactivateObserver = nil
        if let mode { PopSymbolicHotKeyMode(mode) }
        mode = nil
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        tap = nil
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        source = nil
        if wasRecording {
            KeyActionService.isRecording = false
            refreshTitle()
            onRecordingChanged?(false)
            NSLog("dok.keyRecorder: stopped (%@)", reason)
        }
    }
    deinit { stop(reason: "released") }
}
