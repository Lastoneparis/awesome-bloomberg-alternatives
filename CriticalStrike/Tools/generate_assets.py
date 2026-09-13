#!/usr/bin/env python3
"""Generates the app's static image assets.

Everything else in this project draws its textures at runtime, but three things have to
exist as files before the app launches: the App Store icon, the launch background, and the
in-app logo. This script writes them with a pure-Python PNG encoder — no Pillow, no
ImageMagick, nothing to install — using the same shapes and palette as the runtime art so
the icon and the game look like they belong to each other.

    python3 Tools/generate_assets.py
"""
import json
import math
import os
import struct
import sys
import zlib

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ASSETS = os.path.join(ROOT, "Support", "Assets.xcassets")

# Palette, matching Theme.swift.
BACKGROUND = (0x0B, 0x0E, 0x13)
SURFACE = (0x1B, 0x24, 0x30)
ACCENT = (0xFF, 0x6B, 0x35)
ACCENT_HOT = (0xFF, 0xA8, 0x5C)
STEEL = (0x9A, 0xA6, 0xB4)


def write_png(path, width, height, pixels):
    """pixels: bytearray of RGBA, row-major, top to bottom."""
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)                       # filter type 0 (None)
        raw += pixels[y * stride:(y + 1) * stride]
    compressed = zlib.compress(bytes(raw), 9)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    png = (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
           + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(png)
    return len(png)


def smoothstep(edge0, edge1, value):
    if edge1 == edge0:
        return 0.0 if value < edge0 else 1.0
    t = (value - edge0) / (edge1 - edge0)
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return t * t * (3 - 2 * t)


def mix(a, b, t):
    t = 0.0 if t < 0 else (1.0 if t > 1 else t)
    return (a[0] + (b[0] - a[0]) * t,
            a[1] + (b[1] - a[1]) * t,
            a[2] + (b[2] - a[2]) * t)


def hash2(x, y, seed=0):
    h = (x * 0x8DA6B343 + y * 0xD8163841 + seed * 0xCB1AB31F) & 0xFFFFFFFF
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & 0xFFFFFFFF
    h ^= h >> 12
    h = (h * 0x297A2D39) & 0xFFFFFFFF
    h ^= h >> 15
    return (h >> 8) / float(1 << 24)


def render_icon(size):
    """A gunmetal plate with a hot reticle cut into it.

    Designed to survive being shrunk to 40px: one strong silhouette, one accent colour,
    no text, and the negative space in the ring is wide enough to stay open at any size.
    """
    pixels = bytearray(size * size * 4)
    centre = size / 2.0
    unit = size / 1024.0

    ring_radius = 300 * unit
    ring_width = 54 * unit
    tick_inner = 150 * unit
    tick_outer = 250 * unit
    tick_width = 30 * unit
    dot_radius = 46 * unit

    for y in range(size):
        dy = y - centre
        for x in range(size):
            dx = x - centre
            radius = math.hypot(dx, dy)
            angle = math.atan2(dy, dx)

            # ── Plate: a soft vertical gradient with a radial falloff, so the icon has
            # depth rather than sitting on a flat swatch.
            vertical = y / float(size)
            colour = mix(SURFACE, BACKGROUND, vertical * 0.75 + 0.15)
            colour = mix(colour, BACKGROUND, smoothstep(0.35 * size, 0.78 * size, radius))

            # Brushed micro-texture, the same idea as the in-game metal.
            grain = hash2(x // 2, y // 6, 11) * 0.05 - 0.025
            colour = (colour[0] * (1 + grain), colour[1] * (1 + grain), colour[2] * (1 + grain))

            # Faint hex lattice, echoing the weapon finish.
            hex_scale = 46 * unit
            hx = (x / hex_scale) % 1.0
            hy = (y / hex_scale) % 1.0
            lattice = min(abs(hx - 0.5), abs(hy - 0.5))
            colour = mix(colour, SURFACE, smoothstep(0.5, 0.46, lattice) * 0.10)

            # ── Reticle ring with four gaps at the diagonals.
            gap = abs(math.cos(angle * 2))
            ring_band = 1 - smoothstep(ring_width * 0.42, ring_width * 0.55, abs(radius - ring_radius))
            ring = ring_band * smoothstep(0.32, 0.55, gap)

            # ── Cross ticks on the axes.
            along_x = 1 - smoothstep(tick_width * 0.4, tick_width * 0.55, abs(dy))
            along_y = 1 - smoothstep(tick_width * 0.4, tick_width * 0.55, abs(dx))
            within = smoothstep(tick_inner * 0.9, tick_inner, radius) * (1 - smoothstep(tick_outer, tick_outer * 1.06, radius))
            ticks = max(along_x, along_y) * within

            # ── Centre dot.
            dot = 1 - smoothstep(dot_radius * 0.85, dot_radius, radius)

            mark = max(ring, ticks, dot)
            if mark > 0.001:
                # The mark runs hot at the centre and cools toward the ring, which reads
                # as emissive rather than painted on.
                heat = 1 - smoothstep(0, ring_radius, radius)
                accent = mix(ACCENT, ACCENT_HOT, heat * 0.8)
                colour = mix(colour, accent, mark)

            # ── Outer glow, so the mark separates from the plate on a dark home screen.
            glow = (1 - smoothstep(ring_radius, ring_radius + 90 * unit, radius)) * \
                   smoothstep(ring_radius - 40 * unit, ring_radius, radius)
            colour = mix(colour, ACCENT, glow * 0.16)

            # ── Top sheen.
            sheen = (1 - smoothstep(0.0, 0.45, vertical)) * 0.10
            colour = mix(colour, STEEL, sheen)

            index = (y * size + x) * 4
            pixels[index] = int(max(0, min(255, colour[0])))
            pixels[index + 1] = int(max(0, min(255, colour[1])))
            pixels[index + 2] = int(max(0, min(255, colour[2])))
            pixels[index + 3] = 255
    return pixels


def render_wordmark(width, height):
    """A transparent logo lockup for the main menu: the reticle plus a bar motif."""
    pixels = bytearray(width * height * 4)
    centre_y = height / 2.0
    unit = height / 256.0
    reticle_x = height * 0.5
    ring_radius = 88 * unit
    ring_width = 18 * unit

    for y in range(height):
        dy = y - centre_y
        for x in range(width):
            dx = x - reticle_x
            radius = math.hypot(dx, dy)
            angle = math.atan2(dy, dx)

            gap = abs(math.cos(angle * 2))
            ring = (1 - smoothstep(ring_width * 0.4, ring_width * 0.55, abs(radius - ring_radius))) \
                * smoothstep(0.3, 0.55, gap)
            dot = 1 - smoothstep(12 * unit, 15 * unit, radius)

            # Speed bars trailing to the right of the reticle.
            bars = 0.0
            for index in range(3):
                bar_y = centre_y + (index - 1) * 34 * unit
                bar_start = reticle_x + 120 * unit + index * 16 * unit
                bar_end = width - 30 * unit - index * 60 * unit
                if bar_start < x < bar_end:
                    bars = max(bars, 1 - smoothstep(7 * unit, 9 * unit, abs(y - bar_y)))

            alpha = max(ring, dot, bars * 0.85)
            if alpha <= 0.002:
                continue
            heat = 1 - smoothstep(0, ring_radius * 2, radius)
            colour = mix(ACCENT, ACCENT_HOT, heat * 0.7)
            index = (y * width + x) * 4
            pixels[index] = int(colour[0])
            pixels[index + 1] = int(colour[1])
            pixels[index + 2] = int(colour[2])
            pixels[index + 3] = int(max(0, min(255, alpha * 255)))
    return pixels


def write_contents(path, payload):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w") as handle:
        json.dump(payload, handle, indent=2)
        handle.write("\n")


def main():
    info = {"version": 1, "author": "xcode"}

    write_contents(os.path.join(ASSETS, "Contents.json"), {"info": info})

    # ── App icon (single-size modern format) ──
    icon_size = 1024
    print(f"rendering app icon at {icon_size}x{icon_size} …", flush=True)
    icon = render_icon(icon_size)
    icon_path = os.path.join(ASSETS, "AppIcon.appiconset", "AppIcon.png")
    written = write_png(icon_path, icon_size, icon_size, icon)
    write_contents(os.path.join(ASSETS, "AppIcon.appiconset", "Contents.json"), {
        "images": [{"filename": "AppIcon.png", "idiom": "universal",
                    "platform": "ios", "size": "1024x1024"}],
        "info": info,
    })
    print(f"  wrote {icon_path} ({written // 1024} KB)")

    # ── Launch background colour ──
    write_contents(os.path.join(ASSETS, "LaunchBackground.colorset", "Contents.json"), {
        "colors": [{
            "color": {
                "color-space": "srgb",
                "components": {"alpha": "1.000", "blue": "0x13", "green": "0x0E", "red": "0x0B"},
            },
            "idiom": "universal",
        }],
        "info": info,
    })

    # ── Menu wordmark ──
    mark_width, mark_height = 768, 256
    print(f"rendering wordmark at {mark_width}x{mark_height} …", flush=True)
    mark = render_wordmark(mark_width, mark_height)
    mark_path = os.path.join(ASSETS, "Wordmark.imageset", "Wordmark.png")
    written = write_png(mark_path, mark_width, mark_height, mark)
    write_contents(os.path.join(ASSETS, "Wordmark.imageset", "Contents.json"), {
        "images": [
            {"filename": "Wordmark.png", "idiom": "universal", "scale": "1x"},
            {"idiom": "universal", "scale": "2x"},
            {"idiom": "universal", "scale": "3x"},
        ],
        "info": info,
        "properties": {"template-rendering-intent": "original"},
    })
    print(f"  wrote {mark_path} ({written // 1024} KB)")
    print("done")
    return 0


if __name__ == "__main__":
    sys.exit(main())
