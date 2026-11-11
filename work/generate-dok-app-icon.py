#!/usr/bin/env python3
"""Builds every Dok app icon from code: the glass "d" on a graphite tile.

The mark: a standing Dock (the stem) and the wheel (the ring with its centre lens) fused into one
piece of glass that reads as the lowercase d of Dok. Drawn as SVG here, rasterised by the system
(qlmanage), then shaped with Pillow.

- work/dok-icon-source.svg / dok-icon-source-small.svg: the generated full-bleed artwork, kept for reference.
- Resources/AppIcon.icon (macOS 26+): full-bleed artwork; the system applies the shape, rim and shadow.
- AppIcon.appiconset (macOS 13–15): pre-shaped squircle on the 1024 template (824 body, 100 margins),
  with a faint top rim so the dark tile separates from a dark Dock, and a soft shadow.
- 64px and below use the simplified mark (denser glass, no fine rim): the edge light vanishes there.
- Resources/AppIcon.icns from the icon set.
"""
import shutil
import subprocess
import tempfile
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageFilter

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "work" / "dok-icon-source.svg"
SOURCE_SMALL = ROOT / "work" / "dok-icon-source-small.svg"
ICONSET = ROOT / "Resources" / "Assets.xcassets" / "AppIcon.appiconset"
COMPOSER = ROOT / "Resources" / "AppIcon.icon"
ARTWORK_NAME = "dok-d.png"
ICNS = ROOT / "Resources" / "AppIcon.icns"

TILE_TOP, TILE_BOTTOM = "#4D5159", "#1B1D21"

# Glyph geometry on the 1024 template (tile body 100…924). The stem overlaps the ring's right edge
# by 14 and the glyph's bounding box is centred on the tile.
R_OUT, R_IN = 216, 116
BAR_W = 104
RING_CX, RING_CY = 505, 582
BAR_X = RING_CX + R_OUT - BAR_W + 14
BAR_TOP, BAR_BOTTOM = 226, RING_CY + R_OUT


def circle_path(r: float) -> str:
    return f"M{RING_CX - r},{RING_CY} a{r},{r} 0 1 0 {2 * r},0 a{r},{r} 0 1 0 {-2 * r},0 Z"


def artwork_svg(small: bool) -> str:
    """Full-bleed square artwork: the tile gradient edge to edge, the glass d on top.

    The viewBox is the 824 tile body, so the glyph keeps its template proportions once the system
    (macOS 26) or shaped() (macOS 13–15) fits the art to the icon body.
    """
    hi, lo = (0.88, 0.60) if small else (0.34, 0.12)
    ring = circle_path(R_OUT) + " " + circle_path(R_IN)
    r = BAR_W / 2
    bar_d = f"M{BAR_X},{BAR_TOP + r} a{r},{r} 0 0 1 {BAR_W},0 V{BAR_BOTTOM - r} a{r},{r} 0 0 1 {-BAR_W},0 Z"
    glyph = f'<path d="{ring}" fill-rule="evenodd"/><path d="{bar_d}"/>'
    full = "M0,0 H1024 V1024 H0 Z"
    left, width, height = RING_CX - R_OUT, BAR_X + BAR_W - (RING_CX - R_OUT), BAR_BOTTOM - BAR_TOP

    s = f"""<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="100 100 824 824">
  <defs>
    <linearGradient id="tile" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOTTOM}"/>
    </linearGradient>
    <linearGradient id="body" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="{hi}"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="{lo}"/>
    </linearGradient>
    <!-- Outer rim: lit from the top left. -->
    <linearGradient id="rim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.95"/>
      <stop offset="0.55" stop-color="#FFF" stop-opacity="0.14"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.45"/>
    </linearGradient>
    <!-- Lens: the tile's light and dark swapped, the way a lens flips what is behind it. -->
    <linearGradient id="lens" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{TILE_BOTTOM}" stop-opacity="0.92"/>
      <stop offset="1" stop-color="#6A6F78" stop-opacity="0.92"/>
    </linearGradient>
    <!-- Lens rim: opposite the outer rim (bright bottom right), which reads as thickness. -->
    <linearGradient id="lensrim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity="0.38"/>
      <stop offset="0.5" stop-color="#FFF" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.85"/>
    </linearGradient>
    <filter id="shadow" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="12"/></filter>
    <filter id="erode" x="-10%" y="-10%" width="120%" height="120%">
      <feMorphology operator="erode" radius="13"/><feGaussianBlur stdDeviation="11"/>
    </filter>
    <!-- One piece of glass: the union of ring and stem, with no inner edges. -->
    <mask id="glyph" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024"><g fill="#FFF">{glyph}</g></mask>
    <!-- Edge light: the glyph minus a shrunken, blurred copy — a soft falloff, never a line. -->
    <mask id="edge" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">
      <g fill="#FFF">{glyph}</g><g fill="#000" filter="url(#erode)">{glyph}</g>
    </mask>
    <clipPath id="outside-disc"><path d="{full} {circle_path(R_OUT)}" clip-rule="evenodd"/></clipPath>
    <clipPath id="outside-bar"><path d="{full} {bar_d}" clip-rule="evenodd"/></clipPath>
  </defs>
  <rect x="100" y="100" width="824" height="824" fill="url(#tile)"/>
  <g transform="translate(0,16)" opacity="{0.38 if small else 0.52}" filter="url(#shadow)" fill="#000">{glyph}</g>
  <rect x="{left}" y="{BAR_TOP}" width="{width}" height="{height}" fill="url(#body)" mask="url(#glyph)"/>
"""
    if not small:
        s += f"""  <rect x="0" y="0" width="1024" height="1024" fill="#FFF" opacity="0.42" mask="url(#edge)"/>
  <path d="{bar_d}" fill="none" stroke="url(#rim)" stroke-width="4" clip-path="url(#outside-disc)"/>
  <circle cx="{RING_CX}" cy="{RING_CY}" r="{R_OUT}" fill="none" stroke="url(#rim)" stroke-width="4" clip-path="url(#outside-bar)"/>
"""
    s += f'  <circle cx="{RING_CX}" cy="{RING_CY}" r="{R_IN}" fill="url(#lens)"/>\n'
    if not small:
        s += (f'  <circle cx="{RING_CX}" cy="{RING_CY}" r="{R_IN}" fill="none" stroke="url(#lensrim)" '
              f'stroke-width="4"/>\n')
    return s + "</svg>\n"


def rasterise(svg_path: Path) -> Image.Image:
    """Renders the SVG at 1024 with the system's Quick Look renderer (no third-party tools)."""
    with tempfile.TemporaryDirectory() as tmp:
        subprocess.run(["qlmanage", "-t", "-s", "1024", "-o", tmp, str(svg_path)], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        with Image.open(Path(tmp) / f"{svg_path.name}.png") as rendered:
            art = rendered.convert("RGB")
    assert art.size == (1024, 1024), f"qlmanage returned {art.size}"
    return art


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


def main() -> None:
    SOURCE.write_text(artwork_svg(small=False))
    SOURCE_SMALL.write_text(artwork_svg(small=True))
    art = rasterise(SOURCE)
    master = shaped(art)
    master_small = shaped(rasterise(SOURCE_SMALL))
    for size in [16, 32, 64, 128, 256, 512, 1024]:
        source = master_small if size <= 64 else master
        source.resize((size, size), Image.LANCZOS).save(ICONSET / f"icon_{size}x{size}.png")

    assets = COMPOSER / "Assets"
    for old in assets.iterdir():
        old.unlink()
    art.save(assets / ARTWORK_NAME)

    with tempfile.TemporaryDirectory() as tmp:
        iconset = Path(tmp) / "AppIcon.iconset"
        iconset.mkdir()
        for size in [16, 32, 128, 256, 512]:
            shutil.copy(ICONSET / f"icon_{size}x{size}.png", iconset / f"icon_{size}x{size}.png")
            shutil.copy(ICONSET / f"icon_{size * 2}x{size * 2}.png", iconset / f"icon_{size}x{size}@2x.png")
        subprocess.run(["iconutil", "-c", "icns", str(iconset), "-o", str(ICNS)], check=True)


if __name__ == "__main__":
    main()
