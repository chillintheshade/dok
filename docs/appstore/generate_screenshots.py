#!/usr/bin/env python3
"""Generate App Store marketing screenshots (2880x1800) from raw screenshots."""

from PIL import Image, ImageDraw, ImageFont, ImageFilter
import os

# Paths
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
RAW_DIR = os.path.join(SCRIPT_DIR, "screenshots-raw")
OUT_DIR = os.path.join(SCRIPT_DIR, "screenshots-final")
os.makedirs(OUT_DIR, exist_ok=True)

# Target size
W, H = 2880, 1800

# Color palette (deep ocean blue gradient to match the app's aesthetic)
BG_TOP = (15, 30, 80)
BG_BOTTOM = (30, 60, 120)

# Screenshot configs: (filename, headline, subline)
CONFIGS = [
    ("01-arcly-wheel.png", "环形启动器", "应用切换 · 音乐控制 · 一触即达"),
    ("02-settings-apps.png", "轮盘按你习惯排列", "应用 · 文件夹 · 拖动排序"),
    ("03-settings-options.png", "为 macOS 设计", "快捷键 · 外观 · 播放控制"),
]


def make_gradient(w, h, top, bottom):
    """Create a vertical linear gradient."""
    img = Image.new("RGB", (w, h))
    draw = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        r = int(top[0] + (bottom[0] - top[0]) * t)
        g = int(top[1] + (bottom[1] - top[1]) * t)
        b = int(top[2] + (bottom[2] - top[2]) * t)
        draw.line([(0, y), (w, y)], fill=(r, g, b))
    return img


def add_rounded_corners(img, radius):
    """Add rounded corners with transparency."""
    mask = Image.new("L", img.size, 0)
    draw = ImageDraw.Draw(mask)
    draw.rounded_rectangle([(0, 0), img.size], radius=radius, fill=255)
    result = img.copy()
    result.putalpha(mask)
    return result


def add_shadow(img, offset=15, blur_radius=30, opacity=120):
    """Add drop shadow to an RGBA image."""
    # Create shadow
    shadow = Image.new("RGBA", (img.width + blur_radius * 2 + abs(offset),
                                 img.height + blur_radius * 2 + abs(offset)), (0, 0, 0, 0))
    shadow_base = Image.new("RGBA", img.size, (0, 0, 0, opacity))
    # Use alpha channel of original image as shadow shape
    if img.mode == "RGBA":
        shadow_base.putalpha(img.split()[3])
    shadow.paste(shadow_base, (blur_radius + offset, blur_radius + offset))
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur_radius))
    # Composite original on top of shadow
    sx = blur_radius
    sy = blur_radius
    shadow.paste(img, (sx, sy), img)
    return shadow, sx, sy


def load_font(size):
    """Load a nice CJK font."""
    candidates = [
        "/System/Library/Fonts/PingFang.ttc",
        "/System/Library/Fonts/STHeiti Medium.ttc",
        "/System/Library/Fonts/Helvetica.ttc",
    ]
    for path in candidates:
        if os.path.exists(path):
            try:
                return ImageFont.truetype(path, size, index=0)
            except Exception:
                continue
    return ImageFont.load_default()


def generate_screenshot(raw_filename, headline, subline, output_filename):
    """Generate one marketing screenshot."""
    raw_path = os.path.join(RAW_DIR, raw_filename)
    if not os.path.exists(raw_path):
        print(f"  ⚠️  跳过：{raw_filename} 不存在")
        return

    # 1. Background gradient
    canvas = make_gradient(W, H, BG_TOP, BG_BOTTOM)
    canvas = canvas.convert("RGBA")

    # 2. Load and resize screenshot
    screenshot = Image.open(raw_path).convert("RGBA")

    # Scale screenshot to fit ~70% of canvas width
    target_w = int(W * 0.65)
    scale = target_w / screenshot.width
    target_h = int(screenshot.height * scale)
    screenshot = screenshot.resize((target_w, target_h), Image.LANCZOS)

    # Round corners
    screenshot = add_rounded_corners(screenshot, radius=24)

    # Add shadow
    shadowed, sx, sy = add_shadow(screenshot, offset=12, blur_radius=40, opacity=100)

    # Position: center horizontally, lower 60% vertically
    scr_x = (W - shadowed.width) // 2
    scr_y = H - shadowed.height - 60  # 60px from bottom

    canvas.paste(shadowed, (scr_x, scr_y), shadowed)

    # 3. Text
    font_big = load_font(120)
    font_small = load_font(52)

    draw = ImageDraw.Draw(canvas)

    # Headline — centered, above screenshot
    text_y = 100
    bbox = draw.textbbox((0, 0), headline, font=font_big)
    text_w = bbox[2] - bbox[0]
    draw.text(((W - text_w) // 2, text_y), headline, font=font_big, fill=(255, 255, 255, 255))

    # Subline
    sub_y = text_y + 150
    bbox2 = draw.textbbox((0, 0), subline, font=font_small)
    sub_w = bbox2[2] - bbox2[0]
    draw.text(((W - sub_w) // 2, sub_y), subline, font=font_small, fill=(200, 220, 255, 200))

    # 4. Save as PNG (RGB for App Store)
    out_path = os.path.join(OUT_DIR, output_filename)
    canvas.convert("RGB").save(out_path, "PNG", optimize=True)
    print(f"  ✅ {output_filename} ({W}x{H})")


if __name__ == "__main__":
    print("生成 App Store 营销截图...")
    for i, (raw, headline, subline) in enumerate(CONFIGS):
        output = f"arcly_screenshot_{i+1}.png"
        generate_screenshot(raw, headline, subline, output)
    print(f"\n完成！输出目录：{OUT_DIR}")
