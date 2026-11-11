#!/usr/bin/env python3
"""键盘选择：数字键按钟表顺序数、方向键移动高亮、回车确认；轮盘上不显示数字。

前半部分是行为测试：把 WheelKeyboardNavigation 这段纯计算从源码里取出来，配上断言真正编译运行。
后半部分是接线契约：按键只在轮盘显示期间被接管，一开始收起就交还。
"""
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
INTERACTION = (ROOT / "Sources" / "dok" / "WheelInteraction.swift").read_text()
WINDOW = (ROOT / "Sources" / "dok" / "DokWheelWindow.swift").read_text()
APP = (ROOT / "Sources" / "dok" / "DokApp.swift").read_text()
VIEW = (ROOT / "Sources" / "dok" / "DokWheelView.swift").read_text()

CHECKS = r"""
func check(_ condition: Bool, _ message: String) {
    if !condition { print("FAILED: \(message)"); exit(1) }
}
typealias Nav = WheelKeyboardNavigation

// 8 个槽位：0 在正下方，逆时针排开，4 在正上方。
check(Nav.clockOrder(count: 8) == [4, 3, 2, 1, 0, 7, 6, 5], "8 slots count clockwise from the top slot")
check(Nav.slot(forDigit: 1, count: 8) == 4, "1 is the top slot when there is one")
check(Nav.slot(forDigit: 5, count: 8) == 0, "5 is the bottom slot of eight")
check(Nav.slot(forDigit: 9, count: 8) == nil, "no ninth slot on an eight-slot wheel")

// 9 个槽位：正上方是空的，右边紧挨着的那个是 1。
check(Nav.clockOrder(count: 9) == [4, 3, 2, 1, 0, 8, 7, 6, 5], "9 slots start just right of the empty top")
check(abs(Nav.clockDegrees(4, count: 9) - 20) < 1e-6, "the first slot of nine sits 20° clockwise of 12 o'clock")
check(Nav.slot(forDigit: 1, count: 9) == 4, "1 is the slot just right of the top")
check(Nav.slot(forDigit: 9, count: 9) == 5, "9 is the slot just left of the top")
check(Nav.slot(forDigit: 0, count: 9) == nil, "0 means the tenth slot")

// 12 个槽位：0 是第十个，第十一、十二个没有数字键。
check(Nav.slot(forDigit: 1, count: 12) == 6, "1 is the top slot of twelve")
check(Nav.slot(forDigit: 0, count: 12) == Nav.clockOrder(count: 12)[9], "0 is the tenth slot")
check(Nav.slot(forDigit: 1, count: 1) == 0 && Nav.slot(forDigit: 2, count: 1) == nil, "one slot")
check(Nav.slot(forDigit: 1, count: 0) == nil && Nav.clockOrder(count: 0).isEmpty, "empty wheel")
for count in 1...12 {
    check(Set(Nav.clockOrder(count: count)) == Set(0..<count), "every slot is counted exactly once (\(count))")
}

// 方向键第一次按下：跳到那个方向最近的槽位；一样近时取顺时针一侧。
check(Nav.nearestSlot(toward: .up, count: 8) == 4, "up reaches the top slot")
check(Nav.nearestSlot(toward: .down, count: 8) == 0, "down reaches the bottom slot")
check(Nav.nearestSlot(toward: .right, count: 8) == 2 && Nav.nearestSlot(toward: .left, count: 8) == 6, "sides")
check(Nav.nearestSlot(toward: .up, count: 9) == 4, "a tie around the empty top goes clockwise, matching digit 1")
check(Nav.nearestSlot(toward: .down, count: 9) == 0, "nine slots still have a bottom slot")
check(Nav.nearestSlot(toward: .right, count: 9) == 2 && Nav.nearestSlot(toward: .left, count: 9) == 7, "nine: sides")
check(Nav.nearestSlot(toward: .up, count: 0) == nil, "nothing to select on an empty wheel")

// 已有选中项时：挪到更靠那个方向的相邻项；相邻两项一样就跳过去；都不在那个方向就不动。
check(Nav.step(from: 4, arrow: .right, count: 8) == 3, "right from the top moves clockwise")
check(Nav.step(from: 4, arrow: .left, count: 8) == 5, "left from the top moves counterclockwise")
check(Nav.step(from: 4, arrow: .down, count: 8) == 0, "down from the top jumps to the bottom")
check(Nav.step(from: 4, arrow: .up, count: 8) == 4, "up from the top stays")
check(Nav.step(from: 2, arrow: .down, count: 8) == 1, "down from the right side moves toward the bottom")
check(Nav.step(from: 2, arrow: .left, count: 8) == 6, "left from the right side jumps across")
check(Nav.step(from: 2, arrow: .right, count: 8) == 2, "right from the right side stays")
check(Nav.step(from: 0, arrow: .up, count: 2) == 1 && Nav.step(from: 1, arrow: .down, count: 2) == 0, "two slots")
check(Nav.step(from: 0, arrow: .up, count: 1) == 0, "one slot never moves")
print("ok")
"""


def run_behaviour() -> None:
    start = INTERACTION.index("enum WheelKey: Equatable")
    end = INTERACTION.index("/// 把鼠标位置换算成轮盘上的命中目标")
    source = "import Foundation\n" + INTERACTION[start:end] + CHECKS
    with tempfile.TemporaryDirectory() as tmp:
        path = Path(tmp) / "main.swift"
        path.write_text(source)
        binary = Path(tmp) / "nav"
        build = subprocess.run(["swiftc", "-O", str(path), "-o", str(binary)], capture_output=True, text=True)
        assert build.returncode == 0, build.stderr[-2000:]
        result = subprocess.run([str(binary)], capture_output=True, text=True)
    assert result.returncode == 0 and result.stdout.strip() == "ok", result.stdout + result.stderr


def main() -> None:
    run_behaviour()

    # 槽位摆法是键盘数法的前提：第 0 个在正下方，逆时针。
    assert "let angle = (2 * Double.pi / Double(total)) * Double(index) - .pi / 2" in VIEW
    assert "let y = center - iconOrbitRadius * sin(angle)" in VIEW

    handle = WINDOW.split("func handleKey(_ key: WheelKey)", 1)[1].split("func updateSelection()", 1)[0]
    assert "guard isPresented, !isContextMenuOpen" in handle, "keys act only on a presented wheel"
    assert "WheelKeyboardNavigation.slot(forDigit: digit, count: count)" in handle
    assert "activateSelectionAndDismiss()" in handle, "a digit opens the slot directly"
    assert "applySelection(index: index, recentIndex: nil)" in handle, "keyboard reuses the hover highlight"

    update = WINDOW.split("func updateSelection()", 1)[1][:500]
    assert "keyboardMouseAnchor" in update and ">= 8" in update, (
        "the mouse takes over only after moving 8pt, so a nudge does not clear the keyboard highlight"
    )
    for label in ("Text(\"1\")", "digitLabel", "slotNumber"):
        assert label not in VIEW, "the wheel never draws slot numbers"

    register = APP.split("func updateWheelKeyHotKeys()", 1)[1].split("func handleWheelKeyHotKey", 1)[0]
    assert "let needed = isMenuOpen" in register, "keys are held only while the wheel is presented"
    assert "RegisterEventHotKey(entry.keyCode, 0, id" in register, "bare keys, no modifiers"
    assert "UnregisterEventHotKey(ref)" in register
    assert "created.onPresentationChanged" in APP and "self?.updateWheelKeyHotKeys()" in APP
    presentation = WINDOW.split("private func setPresentation", 1)[1][:500]
    assert "onPresentationChanged?()" in presentation, "keys are returned the moment dismissal begins"
    keys = APP.split("private static let wheelKeys", 1)[1].split("]\n", 1)[0]
    assert keys.count(".digit(") == 20 and keys.count(".arrow(") == 4 and keys.count(".confirm") == 2

    print("dok wheel keyboard contract passed.")


if __name__ == "__main__":
    main()
