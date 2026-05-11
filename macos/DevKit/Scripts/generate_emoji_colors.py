#!/usr/bin/env python3
"""
Generate harmonious background colors for each emoji in Emoji.json.

Usage:
    cd macos
    pip install Pillow
    python DevKit/Scripts/generate_emoji_colors.py

Dependencies:
    - Pillow (pip install Pillow)
"""

import json
import colorsys
from pathlib import Path
from collections import Counter
from PIL import Image, ImageDraw, ImageFont


SCRIPT_DIR = Path(__file__).parent
EMOJI_JSON_PATH = SCRIPT_DIR.parent.parent / "OpenBridge" / "Resources" / "Emoji.json"

# Default colors when extraction fails
DEFAULT_LIGHT_BG = "#f0f0f0"
DEFAULT_DARK_BG = "#2a2a2a"


def emoji_to_image(emoji: str, size: int = 64) -> Image.Image:
    """Render an emoji string to an image."""
    try:
        font = ImageFont.truetype("/System/Library/Fonts/Apple Color Emoji.ttc", size)
    except OSError:
        font = ImageFont.load_default()

    img = Image.new("RGBA", (size * 2, size * 2), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)
    draw.text((size // 2, size // 2), emoji, font=font, embedded_color=True)

    bbox = img.getbbox()
    if bbox:
        img = img.crop(bbox)
    return img


def get_dominant_color(img: Image.Image) -> tuple[int, int, int] | None:
    """Extract the dominant color from an image."""
    img = img.convert("RGBA")
    pixels = list(img.get_flattened_data())

    filtered = []
    for r, g, b, a in pixels:
        # Skip transparent pixels
        if a < 128:
            continue
        # Skip near-white pixels
        if r > 240 and g > 240 and b > 240:
            continue
        # Skip near-black pixels (outlines, shadows)
        if r < 30 and g < 30 and b < 30:
            continue
        # Quantize color to reduce noise (keep high 4 bits)
        quantized = ((r >> 4) << 4, (g >> 4) << 4, (b >> 4) << 4)
        filtered.append(quantized)

    if not filtered:
        return None

    counter = Counter(filtered)
    return counter.most_common(1)[0][0]


def rgb_to_hsl(r: int, g: int, b: int) -> tuple[float, float, float]:
    """Convert RGB (0-255) to HSL (H: 0-360, S: 0-1, L: 0-1)."""
    r, g, b = r / 255, g / 255, b / 255
    h, l, s = colorsys.rgb_to_hls(r, g, b)
    return h * 360, s, l


def hsl_to_rgb(h: float, s: float, l: float) -> tuple[int, int, int]:
    """Convert HSL to RGB (0-255)."""
    r, g, b = colorsys.hls_to_rgb(h / 360, l, s)
    return int(r * 255), int(g * 255), int(b * 255)


def generate_light_background(dominant_rgb: tuple[int, int, int]) -> str:
    """
    Generate a harmonious light-mode background color.
    Strategy: Keep hue, moderate saturation, softer lightness.
    """
    h, s, l = rgb_to_hsl(*dominant_rgb)

    new_h = h
    # Saturation: 40-65%, more vibrant but not overwhelming
    new_s = min(max(s * 0.6, 0.40), 0.65)
    # Lightness: 75-85%, softer but still visible color
    new_l = 0.75 + (1 - l) * 0.10

    new_rgb = hsl_to_rgb(new_h, new_s, new_l)
    return f"#{new_rgb[0]:02x}{new_rgb[1]:02x}{new_rgb[2]:02x}"


def generate_dark_background(dominant_rgb: tuple[int, int, int]) -> str:
    """
    Generate a harmonious dark-mode background color.
    Strategy: Keep hue, moderate saturation, dark but visible.
    """
    h, s, l = rgb_to_hsl(*dominant_rgb)

    new_h = h
    # Saturation: 25-45%, more noticeable color hint
    new_s = min(max(s * 0.6, 0.25), 0.45)
    # Lightness: 20-30%, dark but with visible color
    new_l = 0.20 + l * 0.10

    new_rgb = hsl_to_rgb(new_h, new_s, new_l)
    return f"#{new_rgb[0]:02x}{new_rgb[1]:02x}{new_rgb[2]:02x}"


def process_emojis():
    """Process Emoji.json and add background colors."""
    print(f"Reading: {EMOJI_JSON_PATH}")

    with open(EMOJI_JSON_PATH, "r", encoding="utf-8") as f:
        emojis = json.load(f)

    total = len(emojis)
    print(f"Processing {total} emojis...")

    for i, item in enumerate(emojis):
        emoji = item["emoji"]
        try:
            img = emoji_to_image(emoji)
            color = get_dominant_color(img)

            if color:
                item["background_color"] = generate_light_background(color)
                item["background_color_dark"] = generate_dark_background(color)
            else:
                item["background_color"] = DEFAULT_LIGHT_BG
                item["background_color_dark"] = DEFAULT_DARK_BG

        except Exception as e:
            print(f"Error processing {emoji}: {e}")
            item["background_color"] = DEFAULT_LIGHT_BG
            item["background_color_dark"] = DEFAULT_DARK_BG

        if (i + 1) % 200 == 0:
            print(f"Processed {i + 1}/{total}")

    print(f"Writing back to: {EMOJI_JSON_PATH}")
    with open(EMOJI_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(emojis, f, ensure_ascii=False, indent=2)

    print("Done!")


if __name__ == "__main__":
    process_emojis()

