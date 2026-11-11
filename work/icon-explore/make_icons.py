#!/usr/bin/env python3
"""Dok 图标探索：纯代码生成 4 个方向的矢量图标 + 一张对比预览。

只写入本目录，不触碰 Resources/ 里的正式图标。
用法：python3 make_icons.py   （用系统自带 qlmanage 导出 PNG）
"""
import math
import subprocess
from pathlib import Path

OUT = Path(__file__).parent
C = 512  # 画布 1024，中心 512
INK = "#26282C"      # 石墨
MID = "#B9BDC4"      # 中灰
SOFT = "#D9DCE1"     # 浅灰


def squircle(cx=C, cy=C, r=412, n=5.0, steps=240):
    """macOS 风格的连续圆角方形（超椭圆），图标本体 824/1024。"""
    pts = []
    for i in range(steps):
        t = 2 * math.pi * i / steps
        ct, st = math.cos(t), math.sin(t)
        x = cx + r * math.copysign(abs(ct) ** (2 / n), ct)
        y = cy + r * math.copysign(abs(st) ** (2 / n), st)
        pts.append(f"{x:.2f},{y:.2f}")
    return "M" + " L".join(pts) + " Z"


def polar(r, deg, cx=C, cy=C):
    a = math.radians(deg)
    return cx + r * math.cos(a), cy + r * math.sin(a)


def ring_segment(r0, r1, a0, a1, cx=C, cy=C):
    """环形扇段路径，角度为屏幕坐标（0°向右，顺时针为正）。"""
    x0, y0 = polar(r1, a0, cx, cy)
    x1, y1 = polar(r1, a1, cx, cy)
    x2, y2 = polar(r0, a1, cx, cy)
    x3, y3 = polar(r0, a0, cx, cy)
    return (f"M{x0:.2f},{y0:.2f} A{r1},{r1} 0 0 1 {x1:.2f},{y1:.2f} "
            f"L{x2:.2f},{y2:.2f} A{r0},{r0} 0 0 0 {x3:.2f},{y3:.2f} Z")


def tile(p, dark=False):
    """底板：很克制的渐变 + 顶部一道细高光 + 落影。不发光、不加镜头光斑。"""
    top, bot = ("#3A3D43", "#1F2125") if dark else ("#FCFCFD", "#E3E6EA")
    rim = "#FFFFFF" if not dark else "#FFFFFF"
    rim_op = 0.9 if not dark else 0.14
    sq = squircle()
    return f"""
  <defs>
    <linearGradient id="{p}tile" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{top}"/><stop offset="1" stop-color="{bot}"/>
    </linearGradient>
    <linearGradient id="{p}rim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="{rim}" stop-opacity="{rim_op}"/>
      <stop offset="0.5" stop-color="{rim}" stop-opacity="0"/>
    </linearGradient>
    <filter id="{p}sh" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="16"/>
    </filter>
    <filter id="{p}soft" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="10"/>
    </filter>
  </defs>
  <path d="{squircle(cy=C + 14)}" fill="#000" opacity="0.22" filter="url(#{p}sh)"/>
  <path d="{sq}" fill="url(#{p}tile)"/>
  <path d="{sq}" fill="none" stroke="url(#{p}rim)" stroke-width="4"/>
"""


def glass_disc(p, r, dark=False):
    """玻璃盘：半透明白 + 细边 + 底部柔和落影，对应轮盘本体。"""
    fill_op = 0.62 if not dark else 0.10
    stroke = "#FFFFFF" if not dark else "#FFFFFF"
    s_op = 1 if not dark else 0.28
    return f"""
  <circle cx="{C}" cy="{C + 12}" r="{r}" fill="#000" opacity="{0.13 if not dark else 0.35}" filter="url(#{p}soft)"/>
  <circle cx="{C}" cy="{C}" r="{r}" fill="#FFFFFF" fill-opacity="{fill_op}"/>
  <circle cx="{C}" cy="{C}" r="{r}" fill="none" stroke="{stroke}" stroke-opacity="{s_op}" stroke-width="5"/>
  <circle cx="{C}" cy="{C}" r="{r + 2.5}" fill="none" stroke="#000" stroke-opacity="{0.07 if not dark else 0.3}" stroke-width="2"/>
"""


# ---------- A 盘：轮盘俯视，8 个槽位，其中一个被选中 ----------
def icon_a(p="a", dark=False):
    fg = "#F2F3F5" if dark else INK
    rest = "#6B6F77" if dark else MID
    s = tile(p, dark) + glass_disc(p, 300, dark)
    # 中心透镜
    s += (f'<circle cx="{C}" cy="{C}" r="112" fill="none" stroke="{rest}" '
          f'stroke-opacity="0.75" stroke-width="5"/>')
    for i in range(8):
        deg = -90 + i * 45
        x, y = polar(206, deg)
        picked = i == 1
        size = 84 if picked else 66
        col = fg if picked else rest
        s += (f'<rect x="{x - size / 2:.2f}" y="{y - size / 2:.2f}" width="{size}" height="{size}" '
              f'rx="{size * 0.26:.2f}" fill="{col}"/>')
    return s


# ---------- B 扇：环被切成 8 段，一段被推出去 ----------
def icon_b(p="b", dark=False, accent=None):
    fg = accent or ("#F2F3F5" if dark else INK)
    rest = "#5E626A" if dark else "#C4C8CE"
    s = tile(p, dark)
    gap = 5.5
    for i in range(8):
        mid = -90 + i * 45
        a0, a1 = mid - 22.5 + gap / 2, mid + 22.5 - gap / 2
        picked = i == 1
        if picked:
            dx, dy = polar(34, mid, 0, 0)
            s += f'<path d="{ring_segment(148, 304, a0, a1, C + dx, C + dy)}" fill="{fg}"/>'
        else:
            s += f'<path d="{ring_segment(148, 304, a0, a1)}" fill="{rest}"/>'
    s += f'<circle cx="{C}" cy="{C}" r="92" fill="{rest}" fill-opacity="0.55"/>'
    return s


# ---------- C d：轮盘的环 + 一根竖，合成小写 d（Dok） ----------
def icon_c(p="c", dark=False):
    fg = "#F2F3F5" if dark else INK
    rest = "#6B6F77" if dark else MID
    cx, cy, r, w = 470, 590, 186, 70
    stem_x = cx + r
    s = tile(p, dark)
    s += f'<circle cx="{cx}" cy="{cy}" r="{r}" fill="none" stroke="{fg}" stroke-width="{w}"/>'
    s += (f'<line x1="{stem_x}" y1="252" x2="{stem_x}" y2="{cy + r}" stroke="{fg}" '
          f'stroke-width="{w}" stroke-linecap="round"/>')
    # 环里的 8 个槽位点：把字母读成轮盘
    for i in range(8):
        x, y = polar(96, -90 + i * 45, cx, cy)
        s += f'<circle cx="{x:.2f}" cy="{y:.2f}" r="15" fill="{rest}"/>'
    return s


# ---------- D 光标：环在光标尖端展开 ----------
def icon_d(p="d", dark=False):
    fg = "#F2F3F5" if dark else INK
    rest = "#5E626A" if dark else "#C4C8CE"
    s = tile(p, dark)
    gap = 7
    for i in range(8):
        mid = -90 + i * 45
        # 光标身体压住的右下三段留空，让箭头干净
        if i in (3,):
            continue
        s += (f'<path d="{ring_segment(214, 300, mid - 22.5 + gap / 2, mid + 22.5 - gap / 2)}" '
              f'fill="{rest}"/>')
    # 经典箭头光标，尖端落在圆心
    k = 15.5
    pts = [(0, 0), (0, 16.6), (3.9, 13.0), (6.9, 20.0), (9.9, 18.7), (6.9, 11.9), (12.2, 11.9)]
    d = "M" + " L".join(f"{C + x * k:.2f},{C + y * k:.2f}" for x, y in pts) + " Z"
    edge = "#1F2125" if dark else "#FFFFFF"
    s += (f'<path d="{d}" fill="{fg}" stroke="{edge}" stroke-width="13" '
          f'stroke-linejoin="round" paint-order="stroke"/>')
    return s


ICONS = [
    ("A-pan", "A 盘", lambda p: icon_a(p)),
    ("B-shan", "B 扇", lambda p: icon_b(p)),
    ("C-d", "C 字母 d", lambda p: icon_c(p)),
    ("D-cursor", "D 光标", lambda p: icon_d(p)),
    ("A-pan-dark", "A 深色", lambda p: icon_a(p, dark=True)),
    ("B-shan-dark", "B 深色", lambda p: icon_b(p, dark=True)),
    ("C-d-dark", "C 深色", lambda p: icon_c(p, dark=True)),
    ("D-cursor-dark", "D 深色", lambda p: icon_d(p, dark=True)),
]


def svg(body, w=1024, h=1024, vb=None):
    vb = vb or f"0 0 {w} {h}"
    return (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
            f'viewBox="{vb}">{body}</svg>\n')


def main():
    for name, _, fn in ICONS:
        (OUT / f"{name}.svg").write_text(svg(fn(name.replace("-", "") + "_")))

    # 对比预览：每个方向 大(300) / 中(64) / 小(32)，上排浅色，下排深色
    col_w, row_h, pad = 420, 470, 40
    W = pad * 2 + col_w * 4
    H = W  # qlmanage 只出正方形缩略图，画布保持正方
    top = (H - row_h * 2) // 2 + 40
    body = f'<rect width="{W}" height="{H}" fill="#EDEEF0"/>'
    for idx, (name, label, fn) in enumerate(ICONS):
        col, row = idx % 4, idx // 4
        ox, oy = pad + col * col_w, top + row * row_h
        art = fn(f"s{idx}_")
        for size, x, y in ((300, 20, 0), (64, 330, 120), (32, 346, 210)):
            body += (f'<svg x="{ox + x}" y="{oy + y}" width="{size}" height="{size}" '
                     f'viewBox="0 0 1024 1024">{art.replace(f"s{idx}_", f"s{idx}_{size}_")}</svg>')
        body += (f'<text x="{ox + 170}" y="{oy + 345}" text-anchor="middle" '
                 f'font-family="PingFang SC, Helvetica" font-size="26" fill="#3A3D43">{label}</text>')
    (OUT / "preview.svg").write_text(svg(body, W, H))

    subprocess.run(["qlmanage", "-t", "-s", str(W), "-o", str(OUT), str(OUT / "preview.svg")],
                   check=True,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (OUT / "preview.svg.png").replace(OUT / "preview.png")
    print("ok", OUT / "preview.png")


if __name__ == "__main__":
    main()
