#!/usr/bin/env python3
"""Exercise the native search field's composition/commit and focus lifetime."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
s = (root/'Sources/dok/SettingsView.swift').read_text()
block = s[s.index('private final class AppPickerSearchField'):s.index('// MARK: - 交互模式')]
harness = r'''
let app = NSApplication.shared
var value = ""
let input = SearchField(text: Binding(get: { value }, set: { value = $0 }), placeholder: "Search")
let coordinator = input.makeCoordinator()
let window = NSWindow(contentRect: NSRect(x:0,y:0,width:400,height:100), styleMask:.titled, backing:.buffered, defer:false)
private let field = AppPickerSearchField(frame:NSRect(x:10,y:10,width:300,height:30))
field.delegate = coordinator
window.contentView?.addSubview(field)
field.selectText(nil)
guard let editor = field.currentEditor() as? NSTextView else { fatalError("Missing native field editor") }
coordinator.controlTextDidBeginEditing(Notification(name:NSText.didBeginEditingNotification, object:field))
editor.setMarkedText("weixin", selectedRange:NSRange(location:6,length:0), replacementRange:NSRange(location:NSNotFound,length:0))
coordinator.controlTextDidChange(Notification(name:NSText.didChangeNotification, object:field))
precondition(editor.hasMarkedText() && value.isEmpty, "Preedit must not trigger SwiftUI search updates")
let responder = window.firstResponder
NotificationCenter.default.post(name:NSTextInputContext.keyboardSelectionDidChangeNotification, object:nil)
NotificationCenter.default.post(name:NSApplication.didBecomeActiveNotification, object:app)
NotificationCenter.default.post(name:NSWindow.didBecomeKeyNotification, object:window)
RunLoop.main.run(until:Date().addingTimeInterval(0.3))
precondition(window.firstResponder === responder && editor.hasMarkedText(), "Notifications must not reclaim focus during composition")
editor.insertText("微信", replacementRange:NSRange(location:NSNotFound,length:0))
coordinator.controlTextDidChange(Notification(name:NSText.didChangeNotification, object:field))
precondition(value == "微信", "Search must receive committed Chinese")
SearchField.dismantleNSView(field, coordinator:coordinator)
precondition(field.delegate == nil && field.onAttachedToWindow == nil)
print("Search IME composition, commit, notification isolation and teardown passed.")
'''
with tempfile.TemporaryDirectory(prefix='search-ime-', dir=root/'work') as tmp:
    p=Path(tmp); (p/'main.swift').write_text('import AppKit\nimport SwiftUI\n'+block+harness)
    subprocess.run(['xcrun','swiftc','-swift-version','5',str(p/'main.swift'),'-o',str(p/'check')],check=True)
    subprocess.run([str(p/'check')],check=True,timeout=10)
