#!/usr/bin/env python3
import math
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter, ImageFont

SIZE = 1024
CENTER = SIZE // 2

def draw_hexagon(draw, cx, cy, r, fill=None, outline=None, width=1):
    points = []
    for i in range(6):
        angle = math.radians(60 * i - 30)
        x = cx + r * math.cos(angle)
        y = cy + r * math.sin(angle)
        points.append((x, y))
    if fill:
        draw.polygon(points, fill=fill)
    if outline:
        draw.polygon(points, outline=outline, width=width)

def draw_eye(draw, cx, cy, w, h, pupil_r, iris_r):
    eye_points = []
    steps = 100
    for i in range(steps + 1):
        t = i / steps
        angle = math.pi * t
        x = cx - w * math.cos(angle)
        y_top = cy - h * math.sin(angle) ** 1.5
        eye_points.append((x, y_top))
    for i in range(steps + 1):
        t = 1 - i / steps
        angle = math.pi * t
        x = cx + w * math.cos(angle)
        y_bot = cy + h * math.sin(angle) ** 1.5
        eye_points.append((x, y_bot))

    draw.polygon(eye_points, fill=(20, 30, 60))

    for i in range(iris_r, 0, -1):
        t = i / iris_r
        r_val = int(0 * (1 - t) + 60 * t)
        g_val = int(220 * (1 - t) + 100 * t)
        b_val = int(255 * (1 - t) + 200 * t)
        draw.ellipse([cx - i, cy - i, cx + i, cy + i], fill=(r_val, g_val, b_val))

    pupil_color = (10, 15, 30)
    draw.ellipse([cx - pupil_r, cy - pupil_r, cx + pupil_r, cy + pupil_r], fill=pupil_color)

    highlight_r = pupil_r // 3
    hx = cx - pupil_r // 2
    hy = cy - pupil_r // 2
    draw.ellipse([hx - highlight_r, hy - highlight_r, hx + highlight_r, hy + highlight_r],
                 fill=(180, 230, 255, 200))

def draw_circuit_lines(draw, cx, cy, hex_r):
    line_color = (60, 80, 140, 80)
    for i in range(6):
        angle = math.radians(60 * i - 30)
        x1 = cx + hex_r * 0.55 * math.cos(angle)
        y1 = cy + hex_r * 0.55 * math.sin(angle)
        x2 = cx + hex_r * 0.85 * math.cos(angle)
        y2 = cy + hex_r * 0.85 * math.sin(angle)
        draw.line([(x1, y1), (x2, y2)], fill=line_color, width=3)
        dot_r = 6
        draw.ellipse([x2 - dot_r, y2 - dot_r, x2 + dot_r, y2 + dot_r], fill=(80, 140, 220))

def load_font(size):
    font_paths = [
        '/System/Library/Fonts/HelveticaNeue.ttc',
        '/System/Library/Fonts/SFNSMono.ttf',
        '/System/Library/Fonts/Geneva.ttf',
        '/System/Library/Fonts/Optima.ttc',
    ]
    for fp in font_paths:
        try:
            return ImageFont.truetype(fp, size)
        except Exception:
            continue
    try:
        return ImageFont.truetype('/System/Library/Fonts/HelveticaNeue.ttc', size)
    except Exception:
        pass
    return ImageFont.load_default()

def create_icon():
    img = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    corner_r = SIZE // 4.5
    mask = Image.new('L', (SIZE, SIZE), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle([0, 0, SIZE - 1, SIZE - 1], radius=int(corner_r), fill=255)

    bg = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    bg_draw = ImageDraw.Draw(bg)
    for y in range(SIZE):
        t = y / SIZE
        r = int(15 * (1 - t) + 40 * t)
        g = int(20 * (1 - t) + 15 * t)
        b = int(60 * (1 - t) + 80 * t)
        bg_draw.line([(0, y), (SIZE, y)], fill=(r, g, b, 255))

    img = Image.composite(bg, img, mask)
    draw = ImageDraw.Draw(img)

    symbol_cy = CENTER - 80
    hex_r = SIZE * 0.28
    hex_inner_r = hex_r * 0.92

    for i in range(int(hex_r * 1.1), int(hex_inner_r), -1):
        t = (i - hex_inner_r) / (hex_r * 1.1 - hex_inner_r)
        alpha = int(40 * (1 - t))
        draw_hexagon(draw, CENTER, symbol_cy, i, fill=(40, 60, 120, alpha))

    draw_hexagon(draw, CENTER, symbol_cy, int(hex_r), fill=(25, 35, 70, 230),
                 outline=(80, 130, 220), width=4)
    draw_hexagon(draw, CENTER, symbol_cy, int(hex_inner_r), fill=(20, 28, 55, 200),
                 outline=(60, 100, 180, 150), width=2)

    draw_circuit_lines(draw, CENTER, symbol_cy, hex_r)

    eye_w = SIZE * 0.15
    eye_h = SIZE * 0.085
    iris_r = int(SIZE * 0.054)
    pupil_r = int(SIZE * 0.024)
    draw_eye(draw, CENTER, symbol_cy, int(eye_w), int(eye_h), pupil_r, iris_r)

    glow = Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_r = int(iris_r * 1.8)
    for i in range(glow_r, 0, -1):
        t = i / glow_r
        alpha = int(30 * (1 - t))
        glow_draw.ellipse([CENTER - i, symbol_cy - i, CENTER + i, symbol_cy + i],
                          fill=(0, 200, 255, alpha))
    img = Image.alpha_composite(img, glow)

    draw = ImageDraw.Draw(img)
    for i in range(6):
        angle = math.radians(60 * i + 30)
        x = CENTER + hex_r * 0.78 * math.cos(angle)
        y = symbol_cy + hex_r * 0.78 * math.sin(angle)
        dot_r = 5
        draw.ellipse([x - dot_r, y - dot_r, x + dot_r, y + dot_r], fill=(0, 200, 255, 180))

    text_y = symbol_cy + hex_r + 60
    font = load_font(88)
    text = "AgentGuard"

    bbox = draw.textbbox((0, 0), text, font=font)
    tw = bbox[2] - bbox[0]
    th = bbox[3] - bbox[1]
    tx = (SIZE - tw) // 2

    for dx in [-2, -1, 0, 1, 2]:
        for dy in [-2, -1, 0, 1, 2]:
            if dx == 0 and dy == 0:
                continue
            draw.text((tx + dx, text_y + dy), text, fill=(0, 0, 0, 160), font=font)

    draw.text((tx, text_y), text, fill=(220, 245, 255), font=font)

    img = Image.composite(img, Image.new('RGBA', (SIZE, SIZE), (0, 0, 0, 0)), mask)

    return img

def resize_and_save(img, size, path):
    resized = img.resize((size, size), Image.LANCZOS)
    resized.save(path, 'PNG')

if __name__ == '__main__':
    icon = create_icon()

    base = Path(__file__).resolve().parent / 'AIMacCleaner/Assets.xcassets/AppIcon.appiconset'
    sizes = {
        'icon_16.png': 16,
        'icon_16_2x.png': 32,
        'icon_32.png': 32,
        'icon_32_2x.png': 64,
        'icon_128.png': 128,
        'icon_128_2x.png':  256,
        'icon_256.png': 256,
        'icon_256_2x.png': 512,
        'icon_512.png': 512,
        'icon_512_2x.png': 1024,
    }

    for name, size in sizes.items():
        path = base / name
        resize_and_save(icon, size, path)
        print(f'Saved {name} ({size}x{size})')

    preview_path = '/tmp/AgentGuard_icon_preview.png'
    icon.save(preview_path, 'PNG')
    print(f'Preview saved to: {preview_path}')
    print('All icon sizes generated!')
