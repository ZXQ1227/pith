#!/usr/bin/env python3
"""Generate Pith's macOS app icon and Resources/AppIcon.icns.

The artwork is drawn in code so the icon can be regenerated or tweaked
without committing binary art beyond the final .icns.

Layout follows Apple's macOS icon grid: an 824/1024 rounded square centred on
a transparent canvas, corner radius 824 * 0.225.

Usage:
    python3 tools/make-icon.py [--preview out.png]

Requires Pillow.
"""

from __future__ import annotations

import argparse
import os
import shutil
import subprocess
import sys

from PIL import Image, ImageChops, ImageDraw

# --- geometry, in 1024pt design space -------------------------------------

CANVAS = 1024
SUPERSAMPLE = 4                       # draw at 4x, then downsample
SQUARE = 824                          # Apple's macOS icon square
MARGIN = (CANVAS - SQUARE) // 2
CORNER = int(SQUARE * 0.225)          # ~185

# --- palette --------------------------------------------------------------

TOP = (88, 86, 232)                   # indigo
BOTTOM = (139, 62, 226)               # purple
SHEEN_ALPHA = 58                      # soft top highlight

# Relative bar heights for the voice waveform glyph.
BARS = (0.34, 0.62, 1.00, 0.74, 0.46)
BAR_WIDTH = 0.086                     # of SQUARE
BAR_GAP = 0.052                       # of SQUARE
BAR_MAX_HEIGHT = 0.52                 # of SQUARE
BAR_ALPHA = 242


def _gradient(width: int, height: int) -> Image.Image:
    """Vertical two-stop gradient, interpolated from a 1x2 source."""
    strip = Image.new("RGB", (1, 2))
    strip.putpixel((0, 0), TOP)
    strip.putpixel((0, 1), BOTTOM)
    return strip.resize((width, height), Image.BICUBIC)


def _sheen(scale: int) -> Image.Image:
    """White fade over the upper part of the square."""
    square = SQUARE * scale
    fade_h = int(square * 0.55)

    strip = Image.new("L", (1, fade_h))
    for y in range(fade_h):
        progress = y / max(fade_h - 1, 1)
        strip.putpixel((0, y), int(SHEEN_ALPHA * (1.0 - progress) ** 1.7))

    fade = strip.resize((square, fade_h), Image.BICUBIC)

    layer = Image.new("RGBA", (CANVAS * scale, CANVAS * scale), (0, 0, 0, 0))
    white = Image.new("RGBA", fade.size, (255, 255, 255, 255))
    white.putalpha(fade)
    layer.paste(white, (MARGIN * scale, MARGIN * scale))
    return layer


def render() -> Image.Image:
    scale = SUPERSAMPLE
    size = CANVAS * scale

    margin = MARGIN * scale
    square = SQUARE * scale
    corner = CORNER * scale

    mask = Image.new("L", (size, size), 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        [margin, margin, margin + square - 1, margin + square - 1],
        radius=corner,
        fill=255,
    )

    # Gradient body.
    icon = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    icon.paste(_gradient(size, size), (0, 0), mask)

    # Top sheen, clipped to the square.
    sheen = _sheen(scale)
    sheen.putalpha(ImageChops.multiply(sheen.split()[3], mask))
    icon = Image.alpha_composite(icon, sheen)

    # Waveform glyph.
    glyph = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glyph)

    bar_w = BAR_WIDTH * square
    gap = BAR_GAP * square
    total = len(BARS) * bar_w + (len(BARS) - 1) * gap
    x = margin + (square - total) / 2
    centre_y = margin + square / 2
    max_h = BAR_MAX_HEIGHT * square

    for factor in BARS:
        h = max_h * factor
        draw.rounded_rectangle(
            [x, centre_y - h / 2, x + bar_w, centre_y + h / 2],
            radius=bar_w / 2,
            fill=(255, 255, 255, BAR_ALPHA),
        )
        x += bar_w + gap

    icon = Image.alpha_composite(icon, glyph)
    return icon.resize((CANVAS, CANVAS), Image.LANCZOS)


def write_icns(master: Image.Image, out_path: str) -> None:
    """Build an .iconset and compile it with iconutil."""
    iconset = out_path + ".iconset"
    if os.path.isdir(iconset):
        shutil.rmtree(iconset)
    os.makedirs(iconset)

    specs = [
        (16, "icon_16x16.png"),
        (32, "icon_16x16@2x.png"),
        (32, "icon_32x32.png"),
        (64, "icon_32x32@2x.png"),
        (128, "icon_128x128.png"),
        (256, "icon_128x128@2x.png"),
        (256, "icon_256x256.png"),
        (512, "icon_256x256@2x.png"),
        (512, "icon_512x512.png"),
        (1024, "icon_512x512@2x.png"),
    ]
    for px, name in specs:
        master.resize((px, px), Image.LANCZOS).save(os.path.join(iconset, name))

    subprocess.run(["iconutil", "-c", "icns", iconset, "-o", out_path], check=True)
    shutil.rmtree(iconset)
    print(f"wrote {out_path} ({os.path.getsize(out_path)} bytes)")


def main() -> int:
    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    parser = argparse.ArgumentParser(description="Generate Pith's app icon.")
    parser.add_argument("--out", default=os.path.join(root, "Resources", "AppIcon.icns"))
    parser.add_argument("--preview", help="also write a 1024px PNG preview here")
    args = parser.parse_args()

    master = render()

    if args.preview:
        master.save(args.preview)
        print(f"wrote {args.preview}")

    write_icns(master, args.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
