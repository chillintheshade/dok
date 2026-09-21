#!/usr/bin/env python3
import re
import subprocess
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "Sources" / "dok"


def read(relative_path: str) -> str:
    return (ROOT / relative_path).read_text()


def require(text: str, needle: str, reason: str) -> None:
    assert needle in text, f"Missing {reason}: {needle}"


def forbid(text: str, needle: str, reason: str) -> None:
    assert needle not in text, f"Forbidden {reason}: {needle}"


def main() -> None:
    project_yml = read("project.yml")
    package = read("Package.swift")
    pbxproj = read("dok.xcodeproj/project.pbxproj")
    app = read("Sources/dok/DokApp.swift")
    readme = read("README.md")
    public_docs = "\n".join(
        [
            read("docs/appstore/store-copy.md"),
            read("docs/appstore/privacy-policy.html"),
            read("Resources/en.lproj/Localizable.strings"),
            read("Resources/zh-Hans.lproj/Localizable.strings"),
        ]
    )

    for needle in [
        "name: dok",
        "  dok:",
        "PRODUCT_NAME: Dok",
        "INFOPLIST_KEY_CFBundleName: Dok",
        "INFOPLIST_KEY_CFBundleDisplayName: Dok",
        "PRODUCT_BUNDLE_IDENTIFIER: com.qingshan.orbis",
        "path: Sources/dok",
        "CODE_SIGN_ENTITLEMENTS: dok.entitlements",
    ]:
        require(project_yml, needle, "dok XcodeGen configuration")

    require(package, 'name: "dok"', "Swift package name")
    require(package, 'path: "Sources/dok"', "Swift package source path")
    require(pbxproj, "PRODUCT_NAME = Dok;", "generated Xcode product name")
    require(pbxproj, "PRODUCT_BUNDLE_IDENTIFIER = com.qingshan.orbis;", "stable bundle identifier")

    expected_sources = {
        "DokApp.swift": "enum DokEntry",
        "DokWheelView.swift": "struct DokWheelView",
        "DokWheelWindow.swift": "class DokWheelWindow",
    }
    for filename, symbol in expected_sources.items():
        path = SOURCE / filename
        assert path.exists(), f"Missing renamed source file: {path.relative_to(ROOT)}"
        require(path.read_text(), symbol, f"renamed Swift symbol in {filename}")

    for needle in [
        "private func statusBarBrandImage() -> NSImage",
        "let imageSize = NSSize(width: 18, height: 18)",
        "let orbitRadius: CGFloat = 6.2",
        "let satelliteRadius: CGFloat = 1.4",
        "let centerRadius: CGFloat = 2",
        "for index in 0..<8",
        "NSImage(size: imageSize, flipped: false)",
        "image.isTemplate = true",
        'image.accessibilityDescription = "Dok"',
    ]:
        require(app, needle, "menu bar brand icon contract")
    forbid(app, 'systemSymbolName: "circle.grid.cross"', "legacy SF Symbol menu bar icon")
    require(app, 'button.toolTip = "Dok"', "menu bar tooltip")
    require(readme, "# Dok", "README title")
    require(readme, "github.com/chillintheshade/dok", "README repository URL")
    require(public_docs, "Show Dok", "English user-facing name")
    require(public_docs, "Dok 设置", "Chinese user-facing name")

    assert not (ROOT / "Sources" / "Arcly").exists(), "old source directory remains"
    assert not (ROOT / "Arcly.xcodeproj").exists(), "old Xcode project remains"
    assert not (ROOT / "Arcly.entitlements").exists(), "old release entitlements remain"
    assert not (ROOT / "Arcly.debug.entitlements").exists(), "old debug entitlements remain"
    assert all(path.name.startswith("dok-") for path in (ROOT / "work").glob("*-test.py")), "contract tests must use the dok- prefix"

    for relative_path in [
        "docs/appstore/screenshots-raw/01-dok-wheel.png",
        "docs/appstore/screenshots-final/dok_screenshot_1.png",
        "docs/appstore/screenshots-final/dok_screenshot_2.png",
        "docs/appstore/screenshots-final/dok_screenshot_3.png",
    ]:
        assert (ROOT / relative_path).exists(), f"Missing renamed App Store asset: {relative_path}"

    for text, label in [(readme, "README"), (public_docs, "public copy"), (project_yml, "project.yml"), (package, "Package.swift")]:
        for old_name in ["Arcly", "PieMenu", "Orbis"]:
            forbid(text, old_name, f"legacy product name in {label}")

    source_legacy_hits: list[tuple[str, str]] = []
    for path in SOURCE.glob("*.swift"):
        for line in path.read_text().splitlines():
            if re.search(r"Arcly|PieMenu|Orbis", line):
                source_legacy_hits.append((path.name, line.strip()))
    expected_legacy_hits = [
        ("AppState.swift", 'let dir = appSupport.appendingPathComponent("Arcly")'),
        ("NowPlayingService.swift", '.appendingPathComponent("Arcly") else {'),
    ]
    assert source_legacy_hits == expected_legacy_hits, f"Unexpected legacy source references: {source_legacy_hits}"

    vendor_diff = subprocess.run(
        ["git", "diff", "--quiet", "--", "Vendor"], cwd=ROOT, check=False
    )
    assert vendor_diff.returncode == 0, "Vendor must remain byte-for-byte unchanged"

    assert (ROOT / "dist" / "dok-1.1.0.dmg").exists(), "current dok DMG must remain available"
    print("dok rename contract passed.")


if __name__ == "__main__":
    main()
