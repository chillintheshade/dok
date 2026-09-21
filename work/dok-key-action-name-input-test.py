#!/usr/bin/env python3
"""Exercise the production NSTextInputClient's IME preedit/commit path offscreen."""
from pathlib import Path
import subprocess, tempfile
root = Path(__file__).resolve().parents[1]
source = (root / 'Sources/dok/SettingsView.swift').read_text()
block = source[source.index('private final class KeyActionNameTextView'):source.index('private struct KeyActionRecorderInput')]
harness = r'''
let application = NSApplication.shared
var value = ""
private let input = KeyActionNameInput(text: Binding(get: { value }, set: { value = $0 }))
private let coordinator = input.makeCoordinator()
private let view = KeyActionNameTextView(frame: NSRect(x: 0, y: 0, width: 400, height: 30))
view.delegate = coordinator
view.isEditable = true
view.isRichText = false
view.isFieldEditor = true
view.setMarkedText("zhongwen", selectedRange: NSRange(location: 8, length: 0), replacementRange: NSRange(location: NSNotFound, length: 0))
precondition(view.hasMarkedText())
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
precondition(value.isEmpty, "IME preedit must not overwrite the bound name")
view.insertText("中文", replacementRange: NSRange(location: NSNotFound, length: 0))
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
precondition(!view.hasMarkedText())
precondition(view.string == "中文" && value == "中文")
precondition(view.selectedRange().location == 2, "Caret must follow the committed Chinese text")
view.setSelectedRange(NSRange(location: 0, length: 2))
view.insertText("微信截图", replacementRange: NSRange(location: NSNotFound, length: 0))
coordinator.textDidChange(Notification(name: NSText.didChangeNotification, object: view))
precondition(value == "微信截图" && view.selectedRange().location == 4)
print("Native name editor: Chinese marked text, commit, replacement and caret checks passed.")
'''
with tempfile.TemporaryDirectory(prefix='name-ime-test-', dir=root/'work') as tmp:
    directory=Path(tmp)
    main=directory/'main.swift'
    app_state = (root/'Sources/dok/AppState.swift').read_text()
    notifications = app_state[app_state.index('extension Notification.Name {'):app_state.index('// MARK: - Data Models')]
    main.write_text('import AppKit\nimport SwiftUI\nenum KeyActionService { static let isRecording = false }\n'+notifications+block+harness)
    compiler=subprocess.check_output(['xcrun','--find','swiftc'],text=True).strip()
    executable=directory/'check'
    subprocess.run([compiler,'-swift-version','5',str(root/'Sources/dok/Localization.swift'),str(main),'-o',str(executable)],check=True)
    subprocess.run([str(executable)],check=True,timeout=10)
