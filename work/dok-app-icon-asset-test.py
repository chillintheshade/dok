#!/usr/bin/env python3
"""App icon contract: the glass d (a standing Dock fused with the wheel) on a graphite tile."""
import json
from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APPICON_SET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
COMPOSER_ICON = ROOT / "Resources" / "AppIcon.icon"
COMPOSER_MANIFEST = COMPOSER_ICON / "icon.json"
COMPOSER_ARTWORK = COMPOSER_ICON / "Assets" / "dok-d.png"
GENERATOR = ROOT / "work" / "generate-dok-app-icon.py"
SOURCE_ART = ROOT / "work" / "dok-icon-source.svg"
PROJECT_YML = ROOT / "project.yml"


def pixel(image: Image.Image, x: float, y: float) -> tuple[int, int, int, int]:
    px = min(image.width - 1, max(0, round((image.width - 1) * x)))
    py = min(image.height - 1, max(0, round((image.height - 1) * y)))
    return image.getpixel((px, py))


def main() -> None:
    assert GENERATOR.exists() and SOURCE_ART.exists(), "every icon is drawn in code by the generator, which writes its SVG source"

    manifest = json.loads(COMPOSER_MANIFEST.read_text())
    layer = manifest["groups"][0]["layers"][0]
    assert layer["image-name"] == "dok-d.png" and layer["glass"] is False
    assert manifest["supported-platforms"]["squares"] == ["macOS"]
    assert sorted(p.name for p in (COMPOSER_ICON / "Assets").iterdir()) == ["dok-d.png"]
    assert "Resources/AppIcon.icon" in PROJECT_YML.read_text()
    with Image.open(COMPOSER_ARTWORK) as art:
        assert art.size == (1024, 1024)
        corner = art.convert("RGBA").getpixel((0, 0))
        assert corner[3] == 255 and max(corner[:3]) < 110, "Composer art is full bleed; macOS 26 applies the shape"

    assert ICNS.exists() and ICNS.stat().st_size > 0

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        path = APPICON_SET / f"icon_{size}x{size}.png"
        with Image.open(path) as source:
            image = source.convert("RGBA")
        assert image.size == (size, size), f"{path.name} should be {size}x{size}"
        assert pixel(image, 0, 0)[3] == 0, f"{path.name} is pre-shaped with transparent template margins"
        tile = pixel(image, 0.2, 0.2)
        assert tile[3] > 240 and max(tile[:3]) < 110 and tile[2] > tile[0], f"{path.name} has a dark graphite tile"

    # The d stays legible at every size: a bright stem, and a lens darker than the glass around it.
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        with Image.open(APPICON_SET / f"icon_{size}x{size}.png") as source:
            image = source.convert("RGBA")
        stem = pixel(image, 0.667, 0.33)
        lens = pixel(image, 0.493, 0.568)
        beside = pixel(image, 0.80, 0.33)
        assert min(stem[:3]) > max(beside[:3]) + 15, f"the {size}px stem stands out from the tile"
        if size <= 64:
            assert min(stem[:3]) > 150, f"the simplified {size}px mark uses dense glass"
        assert max(lens[:3]) < min(stem[:3]), f"the {size}px lens is darker than the glass"

    print("dok app icon asset contract passed.")


if __name__ == "__main__":
    main()
