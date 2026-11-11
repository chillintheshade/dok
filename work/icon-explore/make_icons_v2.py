#!/usr/bin/env python3
"""Dok 图标 v2：「一根 Dock + 一个轮盘 = d」。

两片玻璃叠成小写 d：竖条是立起来的 Dock，圆环是轮盘（外圈 8 个槽位 + 中心透镜）。
只写入本目录，不触碰 Resources/ 里的正式图标。
用法：python3 make_icons_v2.py   （用系统自带 qlmanage 导出 PNG）
"""
import subprocess
from pathlib import Path

from make_icons import squircle, polar, svg

OUT = Path(__file__).parent
C = 512

# 字形几何（1024 画布）
RING_C = (505, 596)     # 轮盘圆心
R_OUT, R_IN = 232, 124  # 外沿 / 中心透镜
BAR_W = 112
BAR_X = RING_C[0] + R_OUT - BAR_W + 14   # 竖条压住圆环右缘
BAR_TOP, BAR_BOT = 196, RING_C[1] + R_OUT

# 配色：底板上下色、玻璃色、槽位色、落影强度
WAYS = {
    "muse": dict(label="暮橙", top="#FFA466", bot="#EE4B3A", glass="#FFFFFF", slot="#FFFFFF", sh=0.20),
    "lake": dict(label="湖蓝", top="#6AD0F5", bot="#2563DC", glass="#FFFFFF", slot="#FFFFFF", sh=0.20),
    "moss": dict(label="松绿", top="#7ED9A6", bot="#178A62", glass="#FFFFFF", slot="#FFFFFF", sh=0.18),
    "ink": dict(label="石墨", top="#4C5058", bot="#1C1E22", glass="#FFFFFF", slot="#FFFFFF", sh=0.34),
}


def defs(p, w):
    return f"""
  <defs>
    <linearGradient id="{p}tile" x1="0.15" y1="0" x2="0.85" y2="1">
      <stop offset="0" stop-color="{w['top']}"/><stop offset="1" stop-color="{w['bot']}"/>
    </linearGradient>
    <linearGradient id="{p}tilerim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.55"/>
      <stop offset="0.45" stop-color="#FFF" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="{p}body" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="{w['glass']}" stop-opacity="0.60"/>
      <stop offset="1" stop-color="{w['glass']}" stop-opacity="0.26"/>
    </linearGradient>
    <linearGradient id="{p}rim" x1="0.1" y1="0" x2="0.9" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.95"/>
      <stop offset="0.55" stop-color="#FFF" stop-opacity="0.18"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.5"/>
    </linearGradient>
    <linearGradient id="{p}lens" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="#FFF" stop-opacity="0.02"/>
      <stop offset="1" stop-color="#FFF" stop-opacity="0.16"/>
    </linearGradient>
    <filter id="{p}sh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="16"/></filter>
    <filter id="{p}gsh" x="-30%" y="-30%" width="160%" height="160%"><feGaussianBlur stdDeviation="11"/></filter>
    <filter id="{p}ssh" x="-50%" y="-50%" width="200%" height="200%"><feGaussianBlur stdDeviation="3"/></filter>
  </defs>"""


def ring_path():
    cx, cy = RING_C
    def circ(r):
        return (f"M{cx - r},{cy} a{r},{r} 0 1 0 {2 * r},0 a{r},{r} 0 1 0 {-2 * r},0 Z")
    return circ(R_OUT) + " " + circ(R_IN)


def bar_rect(extra=""):
    return (f'<rect x="{BAR_X}" y="{BAR_TOP}" width="{BAR_W}" height="{BAR_BOT - BAR_TOP}" '
            f'rx="{BAR_W / 2}" {extra}/>')


def icon(p, w, slots=True):
    cx, cy = RING_C
    sq = squircle()
    s = defs(p, w)
    # 底板
    s += f'<path d="{squircle(cy=C + 14)}" fill="#000" opacity="0.22" filter="url(#{p}sh)"/>'
    s += f'<path d="{sq}" fill="url(#{p}tile)"/>'
    s += f'<path d="{sq}" fill="none" stroke="url(#{p}tilerim)" stroke-width="4"/>'
    # 玻璃在底板上的落影（两片一起）
    s += (f'<g transform="translate(0,14)" opacity="{w["sh"]}" filter="url(#{p}gsh)" fill="#000">'
          f'<path d="{ring_path()}" fill-rule="evenodd"/>{bar_rect()}</g>')
    # 第一片玻璃：竖条 = 立起来的 Dock
    s += bar_rect(f'fill="url(#{p}body)"')
    s += bar_rect(f'fill="none" stroke="url(#{p}rim)" stroke-width="4"')
    # 第二片玻璃：圆环 = 轮盘外圈，叠在竖条上，重叠处自然更实
    s += f'<path d="{ring_path()}" fill-rule="evenodd" fill="url(#{p}body)"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{R_OUT}" fill="none" stroke="url(#{p}rim)" stroke-width="4"/>'
    # 中心透镜：更通透的一小片玻璃
    s += f'<circle cx="{cx}" cy="{cy}" r="{R_IN}" fill="url(#{p}lens)"/>'
    s += f'<circle cx="{cx}" cy="{cy}" r="{R_IN}" fill="none" stroke="url(#{p}rim)" stroke-width="3.5"/>'
    # 8 个槽位
    if slots:
        rm, size = (R_OUT + R_IN) / 2, 44
        for i in range(8):
            x, y = polar(rm, -90 + i * 45, cx, cy)
            box = (f'x="{x - size / 2:.2f}" y="{y - size / 2:.2f}" width="{size}" height="{size}" '
                   f'rx="{size * 0.27:.2f}"')
            s += f'<rect {box} transform="translate(0,4)" fill="#000" opacity="0.22" filter="url(#{p}ssh)"/>'
            s += f'<rect {box} fill="{w["slot"]}" fill-opacity="0.96"/>'
    return s


def main():
    items = []
    for key, w in WAYS.items():
        (OUT / f"d-{key}.svg").write_text(svg(icon(f"{key}_", w)))
        (OUT / f"d-{key}-plain.svg").write_text(svg(icon(f"{key}p_", w, slots=False)))
        items.append((w["label"], lambda p, w=w: icon(p, w)))
    for key, w in WAYS.items():
        items.append((w["label"] + " · 无槽位", lambda p, w=w: icon(p, w, slots=False)))

    col_w, row_h, pad = 420, 470, 40
    W = H = pad * 2 + col_w * 4
    top = (H - row_h * 2) // 2 + 40
    body = f'<rect width="{W}" height="{H}" fill="#EDEEF0"/>'
    for idx, (label, fn) in enumerate(items):
        col, row = idx % 4, idx // 4
        ox, oy = pad + col * col_w, top + row * row_h
        for size, x, y in ((300, 20, 0), (64, 330, 120), (32, 346, 210)):
            body += (f'<svg x="{ox + x}" y="{oy + y}" width="{size}" height="{size}" '
                     f'viewBox="0 0 1024 1024">{fn(f"v{idx}_{size}_")}</svg>')
        body += (f'<text x="{ox + 170}" y="{oy + 345}" text-anchor="middle" '
                 f'font-family="PingFang SC, Helvetica" font-size="26" fill="#3A3D43">{label}</text>')
    (OUT / "preview2.svg").write_text(svg(body, W, H))
    subprocess.run(["qlmanage", "-t", "-s", str(W), "-o", str(OUT), str(OUT / "preview2.svg")],
                   check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    (OUT / "preview2.svg.png").replace(OUT / "preview2.png")
    print("ok", OUT / "preview2.png")


if __name__ == "__main__":
    main()
