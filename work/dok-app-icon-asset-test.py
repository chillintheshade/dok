#!/usr/bin/env python3
"""App icon contract: the ripple mark (one droplet, one ring) on a deep ink tile."""
import json
from pathlib import Path
from PIL import Image


ROOT = Path(__file__).resolve().parents[1]
APPICON_SET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
COMPOSER_ICON = ROOT / "Resources" / "AppIcon.icon"
COMPOSER_MANIFEST = COMPOSER_ICON / "icon.json"
COMPOSER_ARTWORK = COMPOSER_ICON / "Assets" / "dok-ripple.png"
GENERATOR = ROOT / "work" / "generate-dok-app-icon.py"
SOURCE_ART = ROOT / "work" / "dok-icon-source.webp"
PROJECT_YML = ROOT / "project.yml"


def pixel(image: Image.Image, x: float, y: float) -> tuple[int, int, int, int]:
    px = min(image.width - 1, max(0, round((image.width - 1) * x)))
    py = min(image.height - 1, max(0, round((image.height - 1) * y)))
    return image.getpixel((px, py))


def main() -> None:
    assert GENERATOR.exists() and SOURCE_ART.exists(), "every icon is rebuilt from the ripple source by the generator"

    manifest = json.loads(COMPOSER_MANIFEST.read_text())
    layer = manifest["groups"][0]["layers"][0]
    assert layer["image-name"] == "dok-ripple.png" and layer["glass"] is False
    assert manifest["supported-platforms"]["squares"] == ["macOS"]
    assert sorted(p.name for p in (COMPOSER_ICON / "Assets").iterdir()) == ["dok-ripple.png"]
    assert "Resources/AppIcon.icon" in PROJECT_YML.read_text()
    with Image.open(COMPOSER_ARTWORK) as art:
        assert art.size == (1024, 1024)
        corner = art.convert("RGBA").getpixel((0, 0))
        assert corner[3] == 255 and max(corner[:3]) < 80, "Composer art is full bleed; macOS 26 applies the shape"

    assert ICNS.exists() and ICNS.stat().st_size > 0

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        path = APPICON_SET / f"icon_{size}x{size}.png"
        with Image.open(path) as source:
            image = source.convert("RGBA")
        assert image.size == (size, size), f"{path.name} should be {size}x{size}"
        assert pixel(image, 0, 0)[3] == 0, f"{path.name} is pre-shaped with transparent template margins"
        tile = pixel(image, 0.2, 0.2)
        assert tile[3] > 240 and max(tile[:3]) < 110 and tile[2] > tile[0], f"{path.name} has a deep ink tile"

    for size in [16, 32]:
        with Image.open(APPICON_SET / f"icon_{size}x{size}.png") as source:
            center = source.convert("RGBA").getpixel((size // 2, size // 2))
        assert min(center[:3]) > 200, f"the {size}px mark keeps a bright centre dot"

    print("dok app icon asset contract passed.")


if __name__ == "__main__":
    main()
