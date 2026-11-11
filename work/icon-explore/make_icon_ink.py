#!/usr/bin/env python3
"""Dok 图标 · 石墨定向稿：「一根 Dock + 一个轮盘 = d」。

输出：
  ink-full.svg   大尺寸：两片玻璃 + 8 个槽位
  ink-plain.svg  大尺寸：纯玻璃
  ink-small.svg  64px 及以下：加实、去细节
  ink-preview.png  与现有图标在 Dock 场景下的对比
只写入本目录，不触碰 Resources/ 里的正式图标。
用法：python3 make_icon_ink.py
"""
import base64
import subprocess
from pathlib import Path

from make_icons import squircle, polar, svg

OUT = Path(__file__).parent
ROOT = OUT.parent.parent
C = 512

TILE_TOP, TILE_BOT = "#4D5159", "#1B1D21"

# 字形几何（1024 画布）。竖条压住圆环右缘 14，整体外框居中。
R_OUT, R_IN = 216, 116
BAR_W = 104
RING_C = (505, 582)
BAR_X = RING_C[0] + R_OUT - BAR_W + 14
BAR_TOP, BAR_BOT = 226, RING_C[1] + R_OUT


def defs(p, small):
    hi, lo = (0.88, 0.60) if small else (0.34, 0.12)
    return f"""
  <defs>
    <linearGradient id="{p}tile" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{TILE_TOP}"/><stop offset="1" stop-color="{TILE_BOT}"/>
    </linearGradient>
    <linearGradient id="{p}tilerim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.38"/>
      <stop offset="0.4" stop-color="#FFF" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="{p}body" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="{hi}"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="{lo}"/>
    </linearGradient>
    <!-- 外沿高光：受光在左上 -->
    <linearGradient id="{p}rim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.95"/>
      <stop offset="0.55" stop-color="#FFF" stop-opacity="0.14"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.45"/>
    </linearGradient>
    <!-- 透镜：把底板的明暗倒过来，像真透镜那样把背景翻转 -->
    <linearGradient id="{p}lens" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{TILE_BOT}" stop-opacity="0.92"/>
      <stop offset="1" stop-color="#6A6F78" stop-opacity="0.92"/>
    </linearGradient>
    <!-- 透镜内沿：与外沿相反，亮在右下，读出玻璃的厚度 -->
    <linearGradient id="{p}lensrim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#000" stop-opacity="0.38"/>
      <stop offset="0.5" stop-color="#FFF" stop-opacity="0.10"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.85"/>
    </linearGradient>
    <!-- 背光侧聚出的一道弱光 -->
    <linearGradient id="{p}caustic" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0.55" stop-color="#FFF" stop-opacity="0"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.42"/>
    </linearGradient>
    <filter id="{p}sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="{p}gsh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="12"/></filter>
    <filter id="{p}ssh" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3"/></filter>
    <filter id="{p}streak" x="-200%" y="-10%" width="500%" height="120%"><feGaussianBlur stdDeviation="4"/></filter>
  </defs>"""


def ring_path():
    cx, cy = RING_C

    def circ(r):
        return f"M{cx - r},{cy} a{r},{r} 0 1 0 {2 * r},0 a{r},{r} 0 1 0 {-2 * r},0 Z"

    return circ(R_OUT) + " " + circ(R_IN)


def bar(extra=""):
    return (f'<rect x="{BAR_X}" y="{BAR_TOP}" width="{BAR_W}" height="{BAR_BOT - BAR_TOP}" '
            f'rx="{BAR_W / 2}" {extra}/>')


def art(p, mode="full"):
    """mode: full（带槽位）/ plain（纯玻璃）/ small（小尺寸简化）"""
    small = mode == "small"
    cx, cy = RING_C
    sq = squircle()
    s = defs(p, small)
    # 底板
    s += f'<path d="{squircle(cy=C + 14)}" fill="#000" opacity="0.24" filter="url(#{p}sh)"/>'
    s += f'<path d="{sq}" fill="url(#{p}tile)"/>'
    s += f'<path d="{sq}" fill="none" stroke="url(#{p}tilerim)" stroke-width="4"/>'
    # 玻璃落影
    s += (f'<g transform="translate(0,16)" opacity="{0.38 if small else 0.52}" filter="url(#{p}gsh)" fill="#000">'
          f'<path d="{ring_path()}" fill-rule="evenodd"/>{bar()}</g>')
    # 竖条（立起来的 Dock）和圆环（轮盘外圈）合成一整片玻璃：
    # 用蒙版取两者的并集，内部不留任何边线，重叠处也不加深。
    full = "M0,0 H1024 V1024 H0 Z"
    r = BAR_W / 2
    bar_d = (f"M{BAR_X},{BAR_TOP + r} a{r},{r} 0 0 1 {BAR_W},0 V{BAR_BOT - r} "
             f"a{r},{r} 0 0 1 {-BAR_W},0 Z")
    disc_d = f"M{cx - R_OUT},{cy} a{R_OUT},{R_OUT} 0 1 0 {2 * R_OUT},0 a{R_OUT},{R_OUT} 0 1 0 {-2 * R_OUT},0 Z"
    s += (f'<defs><mask id="{p}glyph" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
          f'<path d="{ring_path()}" fill-rule="evenodd" fill="#FFF"/>{bar("fill=" + chr(34) + "#FFF" + chr(34))}</mask>'
          f'<clipPath id="{p}outdisc"><path d="{full} {disc_d}" clip-rule="evenodd"/></clipPath>'
          f'<clipPath id="{p}outbar"><path d="{full} {bar_d}" clip-rule="evenodd"/></clipPath></defs>')
    s += (f'<rect x="{cx - R_OUT}" y="{BAR_TOP}" width="{BAR_X + BAR_W - (cx - R_OUT)}" '
          f'height="{BAR_BOT - BAR_TOP}" fill="url(#{p}body)" mask="url(#{p}glyph)"/>')
    if not small:
        # 通透感：玻璃中间更清、靠近边缘更亮（边缘聚光）。用「字形 减去 向内收缩并模糊的字形」
        # 做蒙版，得到的是一圈向内渐隐的柔光，不是线。
        glyph = f'<path d="{ring_path()}" fill-rule="evenodd"/>{bar()}'
        s += (f'<defs><filter id="{p}erode" x="-10%" y="-10%" width="120%" height="120%">'
              f'<feMorphology operator="erode" radius="13"/><feGaussianBlur stdDeviation="11"/></filter>'
              f'<mask id="{p}edge" maskUnits="userSpaceOnUse" x="0" y="0" width="1024" height="1024">'
              f'<g fill="#FFF">{glyph}</g><g fill="#000" filter="url(#{p}erode)">{glyph}</g></mask></defs>')
        s += (f'<rect x="0" y="0" width="1024" height="1024" fill="#FFF" opacity="0.42" '
              f'mask="url(#{p}edge)"/>')
        # 高光只描最外轮廓：竖条的边在圆外才画，圆环的边在竖条外才画
        s += bar(f'fill="none" stroke="url(#{p}rim)" stroke-width="4" clip-path="url(#{p}outdisc)"')
        s += (f'<circle cx="{cx}" cy="{cy}" r="{R_OUT}" fill="none" stroke="url(#{p}rim)" '
              f'stroke-width="4" clip-path="url(#{p}outbar)"/>')
    # 中心透镜
    s += f'<circle cx="{cx}" cy="{cy}" r="{R_IN}" fill="url(#{p}lens)"/>'
    if not small:
        s += (f'<circle cx="{cx}" cy="{cy}" r="{R_IN}" fill="none" stroke="url(#{p}lensrim)" '
              f'stroke-width="4"/>')
    # 8 个槽位
    if mode == "full":
        rm, size = (R_OUT + R_IN) / 2, 42
        for i in range(8):
            x, y = polar(rm, -90 + i * 45, cx, cy)
            box = (f'x="{x - size / 2:.2f}" y="{y - size / 2:.2f}" width="{size}" height="{size}" '
                   f'rx="{size * 0.27:.2f}"')
            s += f'<rect {box} transform="translate(0,4)" fill="#000" opacity="0.26" filter="url(#{p}ssh)"/>'
            s += f'<rect {box} fill="#FFF" fill-opacity="0.97"/>'
    return s


def place(fn, x, y, size, pid):
    return (f'<svg x="{x}" y="{y}" width="{size}" height="{size}" viewBox="0 0 1024 1024">'
            f'{fn(pid)}</svg>')


def old_icon(x, y, size):
    png = ROOT / "Resources/Assets.xcassets/AppIcon.appiconset/icon_512x512.png"
    b64 = base64.b64encode(png.read_bytes()).decode()
    return f'<image x="{x}" y="{y}" width="{size}" height="{size}" href="data:image/png;base64,{b64}"/>'


def label(x, y, text, size=24, fill="#3A3D43", anchor="middle"):
    return (f'<text x="{x}" y="{y}" text-anchor="{anchor}" font-family="PingFang SC, Helvetica" '
            f'font-size="{size}" fill="{fill}">{text}</text>')


def main():
    for mode in ("full", "plain", "small"):
        (OUT / f"ink-{mode}.svg").write_text(svg(art(f"{mode}_", mode)))

    W = H = 1600
    body = f'<rect width="{W}" height="{H}" fill="#EDEEF0"/>'
    # 第一排：大图
    big = 400
    for i, (name, fn) in enumerate([
        ("新 · 带槽位", lambda p: art(p, "full")),
        ("新 · 纯玻璃", lambda p: art(p, "plain")),
    ]):
        x = 80 + i * 500
        body += place(fn, x, 70, big, f"big{i}_") + label(x + big / 2, 70 + big + 44, name)
    body += old_icon(1080, 70, big) + label(1080 + big / 2, 70 + big + 44, "现在的图标")

    # 第二、三排：深色 / 浅色 Dock 条，新旧并排，128 → 16
    sizes = [128, 64, 32, 16]
    for row, (bg0, bg1, txt) in enumerate([("#2A3550", "#6E5A6B", "#FFFFFF"), ("#DCE6F2", "#F4EDE4", "#3A3D43")]):
        y0 = 620 + row * 470
        gid = f"wall{row}"
        body += (f'<defs><linearGradient id="{gid}" x1="0" y1="0" x2="1" y2="1">'
                 f'<stop offset="0" stop-color="{bg0}"/><stop offset="1" stop-color="{bg1}"/></linearGradient></defs>')
        body += f'<rect x="80" y="{y0}" width="1440" height="400" rx="36" fill="url(#{gid})"/>'
        for col, (who, fn) in enumerate([("新", None), ("现在", "old")]):
            x = 150 + col * 720
            body += label(x, y0 + 60, who, 26, txt, "start")
            # 玻璃 Dock 托盘
            body += (f'<rect x="{x - 24}" y="{y0 + 110}" width="560" height="200" rx="44" fill="#FFF" '
                     f'fill-opacity="0.18" stroke="#FFF" stroke-opacity="0.35" stroke-width="1.5"/>')
            cx = x + 10
            for sz in sizes:
                yy = y0 + 110 + (200 - sz) / 2
                if fn == "old":
                    body += old_icon(cx, yy, sz)
                else:
                    mode = "full" if sz >= 128 else "small"
                    body += place(lambda p, m=mode: art(p, m), cx, yy, sz, f"d{row}_{sz}_")
                body += label(cx + sz / 2, y0 + 350, f"{sz}", 20, txt)
                cx += sz + 44
    (OUT / "ink-preview.svg").write_text(svg(body, W, H))
    subprocess.run(["qlmanage", "-t", "-s", str(W), "-o", str(OUT), str(OUT / "ink-preview.svg")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (OUT / "ink-preview.svg.png").replace(OUT / "ink-preview.png")
    print("ok", OUT / "ink-preview.png")


if __name__ == "__main__":
    main()
