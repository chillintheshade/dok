from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]

required_localizations = {
    "Resources/en.lproj/Localizable.strings": [
        '"settings.tab.wheel" = "Wheel";',
        '"menu.show" = "Show dok";',
        '"onboarding.title" = "Welcome to dok";',
        '"music.placeholder" = "Music";',
    ],
    "Resources/zh-Hans.lproj/Localizable.strings": [
        '"settings.tab.wheel" = "轮盘";',
        '"menu.show" = "显示 dok";',
        '"onboarding.title" = "欢迎使用 dok！";',
        '"music.placeholder" = "音乐";',
    ],
}

for relative_path, snippets in required_localizations.items():
    path = ROOT / relative_path
    assert path.exists(), f"missing localization file: {relative_path}"
    text = path.read_text()
    for snippet in snippets:
        assert snippet in text, f"{relative_path} missing {snippet}"

readme = (ROOT / "README.md").read_text()
assert "English and Simplified Chinese UI" in readme
assert "支持英文和简体中文界面" in readme
assert "docs/github/dok-wheel-music.jpg" in readme
assert "docs/github/dok-settings-wheel.png" in readme
assert "docs/github/dok-settings-general.png" in readme
assert "GitHub Releases" in readme

package = (ROOT / "Package.swift").read_text()
assert 'name: "dok"' in package
assert "PieMenu" not in package

project_yml = (ROOT / "project.yml").read_text()
assert "name: dok" in project_yml
assert "Sources/dok" in project_yml
assert "Sources/PieMenu" not in project_yml

assert (ROOT / "dok.xcodeproj").exists(), "Xcode project should be named dok.xcodeproj"
assert not (ROOT / "Orbis.xcodeproj").exists(), "old Orbis.xcodeproj should be renamed"
assert (ROOT / "Sources/dok").exists(), "source module should be named dok"
assert not (ROOT / "Sources/PieMenu").exists(), "old PieMenu source folder should be renamed"

for path in (ROOT / "Sources").rglob("*.swift"):
    text = path.read_text()
    assert "PieMenu" not in text, f"old PieMenu name remains in {path.relative_to(ROOT)}"
    assert "饼状菜单" not in text, f"old Chinese pie-menu wording remains in {path.relative_to(ROOT)}"

print("dok localization and naming contract passed.")
