"""设置页拆成了几个文件，契约测试统一从这里读取它们的合并文本。

按页面顺序拼接：共用控件、窗口外壳、轮盘页、按键动作编辑器、通用页。
"""
from pathlib import Path

SOURCES = Path(__file__).resolve().parents[1] / "Sources" / "dok"
FILES = [
    "SettingsComponents.swift",
    "SettingsView.swift",
    "WheelSettingsView.swift",
    "KeyActionEditor.swift",
    "GeneralSettingsView.swift",
]


def settings_source() -> str:
    return "\n".join((SOURCES / name).read_text() for name in FILES)


class _SettingsSource:
    """给原来按 Path 使用的测试：只需要 read_text()。"""

    def read_text(self) -> str:
        return settings_source()


SETTINGS_SOURCE = _SettingsSource()
