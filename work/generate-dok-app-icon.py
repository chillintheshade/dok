#!/usr/bin/env python3
"""Builds every Dok app icon from the ripple artwork (work/dok-icon-source.webp).

- Resources/AppIcon.icon (macOS 26+): full-bleed artwork; the system applies the shape, rim and shadow.
- AppIcon.appiconset (macOS 13–15): pre-shaped squircle on the 1024 template (824 body, 100 margins),
  with a faint top rim so the dark tile separates from a dark Dock, and a soft shadow.
- 16 and 32px are redrawn as a simplified mark (thicker ring, larger dot): the fine ripple vanishes there.
- Resources/AppIcon.icns from the icon set.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "work" / "dok-icon-source.webp"
ICONSET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
COMPOSER = ROOT / "Resources" / "AppIcon.icon"
ICNS = ROOT / "Resources" / "AppIcon.icns"

TOP = np.array([33, 44, 63], float)
BOTTOM = np.array([8, 10, 16], float)


def gradient(size: int) -> Image.Image:
    t = np.linspace(0, 1, size)[:, None, None]
    rows = TOP * (1 - t) + BOTTOM * t
    return Image.fromarray(np.repeat(rows, size, axis=1).astype(np.uint8))


def full_bleed() -> Image.Image:
    """Square artwork: the source tile's centre, its rounded corners filled with the matching gradient."""
    src = Image.open(SOURCE).convert("RGBA")
    solid = np.asarray(src)[:, :, 3] > 250
    cols = np.where(solid.mean(axis=0) > 0.5)[0]
    rows = np.where(solid.mean(axis=1) > 0.5)[0]
    cx, cy = (cols.min() + cols.max()) / 2, (rows.min() + rows.max()) / 2
    side = min(cols.max() - cols.min(), rows.max() - rows.min())
    box = tuple(round(v) for v in (cx - side / 2, cy - side / 2, cx + side / 2, cy + side / 2))
    crop = src.crop(box).resize((1024, 1024), Image.LANCZOS)
    keep = crop.getchannel("A").point(lambda a: 255 if a > 250 else 0)
    keep = keep.filter(ImageFilter.MinFilter(31)).filter(ImageFilter.GaussianBlur(10))
    out = gradient(1024)
    out.paste(crop.convert("RGB"), (0, 0), keep)
    return out


def squircle_mask(size: int, n: float = 5.0) -> Image.Image:
    s = size * 4
    yy, xx = np.mgrid[0:s, 0:s]
    u = np.abs((xx + 0.5) / s * 2 - 1)
    v = np.abs((yy + 0.5) / s * 2 - 1)
    mask = ((u**n + v**n) <= 1).astype(np.uint8) * 255
    return Image.fromarray(mask).resize((size, size), Image.LANCZOS)


def shaped(art: Image.Image, canvas: int = 1024) -> Image.Image:
    body = round(canvas * 824 / 1024)
    margin = (canvas - body) // 2
    mask = squircle_mask(body)
    tile = art.resize((body, body), Image.LANCZOS).convert("RGBA")

    # 顶部一道极淡的亮边，向下渐隐：深色程序坞上也分得出边界。
    inner = mask.filter(ImageFilter.MinFilter(max(3, body // 256 * 2 + 1)))
    rim = ImageChops.subtract(mask, inner)
    fade = Image.fromarray((np.linspace(0.30, 0.06, body)[:, None] * 255 * np.ones((1, body))).astype(np.uint8))
    rim = ImageChops.multiply(rim, fade)
    tile = Image.composite(Image.new("RGBA", (body, body), (255, 255, 255, 255)), tile, rim)
    tile.putalpha(mask)

    out = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow = Image.new("RGBA", (canvas, canvas), (0, 0, 0, 0))
    shadow.paste(Image.new("RGBA", (body, body), (0, 0, 0, 90)), (margin, margin + canvas // 100), mask)
    shadow = shadow.filter(ImageFilter.GaussianBlur(canvas / 80))
    out.alpha_composite(shadow)
    out.alpha_composite(tile, (margin, margin))
    return out


def simplified(size: int) -> Image.Image:
    """16/32px: one bright ring and a dot, drawn large and reduced."""
    s = 512
    art = gradient(s)
    d = ImageDraw.Draw(art)
    r = s * 0.31
    width = s * (0.085 if size == 16 else 0.06)
    d.ellipse((s / 2 - r, s / 2 - r, s / 2 + r, s / 2 + r), outline=(176, 200, 236), width=round(width))
    dot = s * (0.10 if size == 16 else 0.085)
    d.ellipse((s / 2 - dot, s / 2 - dot, s / 2 + dot, s / 2 + dot), fill=(236, 244, 255))
    return shaped(art, s).resize((size, size), Image.LANCZOS)


def main() -> None:
    art = full_bleed()
    master = shaped(art)
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        icon = simplified(size) if size <= 32 else master.resize((size, size), Image.LANCZOS)
        icon.save(ICONSET / f"icon_{size}x{size}.png")

    assets = COMPOSER / "Assets"
    for old in assets.iterdir():
        old.unlink()
    art.save(assets / "dok-ripple.png")

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            shutil.copy(ICONSET / f"icon_{size}x{size}.png", iconset / f"icon_{size}x{size}.png")
            shutil.copy(ICONSET / f"icon_{size * 2}x{size * 2}.png", iconset / f"icon_{size}x{size}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)


if __name__ == "__main__":
    main()
