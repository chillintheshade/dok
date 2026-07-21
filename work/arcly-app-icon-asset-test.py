#!/usr/bin/env python3
from pathlib import Path
from PIL import Image, ImageChops, ImageStat


ROOT = Path(__file__).resolve().parents[1]
APPICON_SET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
ICNS = ROOT / "Resources" / "AppIcon.icns"
SOURCE_ICON = APPICON_SET / "icon_1024x1024.png"


def dimensions(path: Path) -> tuple[int, int]:
    with Image.open(path) as image:
        return image.size


def resized_pixel_rms(path: Path, size: int) -> float:
    with Image.open(SOURCE_ICON) as source, Image.open(path) as actual:
        expected = source.convert("RGBA").resize((size, size), Image.Resampling.LANCZOS)
        difference = ImageChops.difference(expected, actual.convert("RGBA"))
        return max(ImageStat.Stat(difference).rms)


def main() -> None:
    assert SOURCE_ICON.exists(), "the repository must contain its canonical 1024px app icon"
    assert ICNS.exists() and ICNS.stat().st_size > 0, "AppIcon.icns should exist and be non-empty"

    for size in [16, 32, 64, 128, 256, 512, 1024]:
        icon = APPICON_SET / f"icon_{size}x{size}.png"
        assert icon.exists(), f"missing app icon asset: {icon}"
        assert dimensions(icon) == (size, size), f"{icon.name} should be {size}x{size}"

    for size in [16, 32, 64, 128, 256, 512]:
        current = APPICON_SET / f"icon_{size}x{size}.png"
        assert resized_pixel_rms(current, size) < 6, (
            f"{current.name} should remain visually derived from the repository source icon"
        )

    print("Arcly app icon asset contract passed.")


if __name__ == "__main__":
    main()
