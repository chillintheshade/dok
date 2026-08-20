#!/usr/bin/env python3
import json
from pathlib import Path
from PIL import Image
from xml.etree import ElementTree


ROOT = Path(__file__).resolve().parents[1]
APPICON_SET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
SOURCE_ICON = APPICON_SET / "icon_1024x1024.png"
COMPOSER_ICON = ROOT / "Resources" / "AppIcon.icon"
COMPOSER_MANIFEST = COMPOSER_ICON / "icon.json"
COMPOSER_ARTWORK = COMPOSER_ICON / "Assets" / "dok-ring.svg"
PROJECT_YML = ROOT / "project.yml"


def dimensions(path: Path) -> tuple[int, int]:
    with Image.open(path) as image:
        return image.size


def pixel(image: Image.Image, x: float, y: float) -> tuple[int, int, int, int]:
    px = min(image.width - 1, max(0, round((image.width - 1) * x)))
    py = min(image.height - 1, max(0, round((image.height - 1) * y)))
    return image.getpixel((px, py))


def assert_brand_geometry(path: Path) -> None:
    with Image.open(path) as source:
        image = source.convert("RGBA")
        corner = pixel(image, 0, 0)
        background = pixel(image, 0.5, 0.28)
        center = pixel(image, 0.5, 0.5)
        orbit = 6.2 / 18
        diagonal = orbit / (2**0.5)
        satellites = [
            (0.5, 0.5 - orbit),
            (0.5 + diagonal, 0.5 - diagonal),
            (0.5 + orbit, 0.5),
            (0.5 + diagonal, 0.5 + diagonal),
            (0.5, 0.5 + orbit),
            (0.5 - diagonal, 0.5 + diagonal),
            (0.5 - orbit, 0.5),
            (0.5 - diagonal, 0.5 - diagonal),
        ]

        assert max(corner[:3]) < 32 and corner[3] > 220, (
            f"{path.name} should use a full-bleed opaque black base; macOS supplies the icon mask"
        )
        assert max(background[:3]) < 32 and background[3] > 220, f"{path.name} should have a black base"
        assert min(center[:3]) > 220 and center[3] > 220, f"{path.name} should have a white center node"
        for coordinate in satellites:
            dot = pixel(image, *coordinate)
            assert min(dot[:3]) > 190 and dot[3] > 220, f"{path.name} should preserve all eight white satellites"


def main() -> None:
    assert COMPOSER_MANIFEST.exists(), "macOS 26 must use an Icon Composer document"
    assert COMPOSER_ARTWORK.exists(), "Icon Composer must contain the dok ring foreground"

    manifest = json.loads(COMPOSER_MANIFEST.read_text())
    assert manifest["fill"]["solid"] == "srgb:0.00000,0.00000,0.00000,1.00000", (
        "Icon Composer background must be opaque black so it fills the system enclosure"
    )
    assert manifest["supported-platforms"]["squares"] == ["macOS"]
    assert manifest["groups"][0]["layers"][0]["image-name"] == "dok-ring.svg"
    assert manifest["groups"][0]["layers"][0]["glass"] is False

    artwork = ElementTree.parse(COMPOSER_ARTWORK)
    circles = artwork.findall(".//{http://www.w3.org/2000/svg}circle")
    assert len(circles) == 9, "the Composer foreground must contain eight satellites and one center node"
    assert "Resources/AppIcon.icon" in PROJECT_YML.read_text(), (
        "the Icon Composer document must belong to the app target"
    )

    assert SOURCE_ICON.exists(), "the repository must contain its canonical 1024px app icon"
    assert ICNS.exists() and ICNS.stat().st_size > 0, "AppIcon.icns should exist and be non-empty"

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        icon = APPICON_SET / f"icon_{size}x{size}.png"
        assert icon.exists(), f"missing app icon asset: {icon}"
        assert dimensions(icon) == (size, size), f"{icon.name} should be {size}x{size}"

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        assert_brand_geometry(APPICON_SET / f"icon_{size}x{size}.png")

    print("dok app icon asset contract passed.")


if __name__ == "__main__":
    main()
