#!/usr/bin/env python3
"""Renders preview sheets of the procedural surfaces.

This mirrors the generators in Sources/CriticalStrikeApp/Render/Textures so the art can be
tuned and reviewed without a Mac. It is a design tool, not a test: the Swift code is the
shipping implementation, and this exists so the parameters can be judged by eye.

    python3 Tools/preview_textures.py [output_dir]

Each sheet is drawn 2x2 tiled, which is the only reliable way to spot a seam.
"""
import math
import os
import struct
import sys
import zlib

# ──────────────────────────── PNG ────────────────────────────

def write_png(path, width, height, pixels):
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw += pixels[y * stride:(y + 1) * stride]
    compressed = zlib.compress(bytes(raw), 6)

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data
                + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    header = struct.pack(">IIBBBBB", width, height, 8, 6, 0, 0, 0)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "wb") as handle:
        handle.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", header)
                     + chunk(b"IDAT", compressed) + chunk(b"IEND", b""))

# ──────────────────────────── Noise (mirrors Noise.swift) ────────────────────────────

MASK = 0xFFFFFFFF

def nhash(x, y, seed):
    h = (x * 0x8DA6B343) & MASK
    h = (h + (y * 0xD8163841)) & MASK
    h = (h + (seed * 0xCB1AB31F)) & MASK
    h ^= h >> 15
    h = (h * 0x2C1B3C6D) & MASK
    h ^= h >> 12
    h = (h * 0x297A2D39) & MASK
    h ^= h >> 15
    return (h >> 8) / float(1 << 24)


def wrap(value, period):
    return value % period if period > 0 else value


def fade(t):
    return t * t * t * (t * (t * 6 - 15) + 10)


def value_noise(x, y, period, seed):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    u, v = fade(xf), fade(yf)
    x0, x1 = wrap(xi, period), wrap(xi + 1, period)
    y0, y1 = wrap(yi, period), wrap(yi + 1, period)
    n00 = nhash(x0, y0, seed)
    n10 = nhash(x1, y0, seed)
    n01 = nhash(x0, y1, seed)
    n11 = nhash(x1, y1, seed)
    top = n00 + (n10 - n00) * u
    bottom = n01 + (n11 - n01) * u
    return top + (bottom - top) * v


def gradient_noise(x, y, period, seed):
    xi, yi = math.floor(x), math.floor(y)
    xf, yf = x - xi, y - yi
    u, v = fade(xf), fade(yf)

    def dot(cx, cy, dx, dy):
        angle = nhash(wrap(cx, period), wrap(cy, period), seed) * 2 * math.pi
        return math.cos(angle) * dx + math.sin(angle) * dy

    n00 = dot(xi, yi, xf, yf)
    n10 = dot(xi + 1, yi, xf - 1, yf)
    n01 = dot(xi, yi + 1, xf, yf - 1)
    n11 = dot(xi + 1, yi + 1, xf - 1, yf - 1)
    top = n00 + (n10 - n00) * u
    bottom = n01 + (n11 - n01) * u
    return clamp((top + (bottom - top) * v) * 0.7071 + 0.5, 0, 1)


def fbm(x, y, period, octaves=4, gain=0.5, lacunarity=2.0, basis="value", seed=0):
    amplitude, total, norm, frequency = 1.0, 0.0, 0.0, 1.0
    current = period
    for octave in range(max(1, octaves)):
        fn = value_noise if basis == "value" else gradient_noise
        total += fn(x * frequency, y * frequency, current, seed + octave * 131) * amplitude
        norm += amplitude
        amplitude *= gain
        frequency *= lacunarity
        current = int(current * lacunarity)
    return total / norm if norm else 0.0


def ridged(x, y, period, octaves=4, gain=0.5, lacunarity=2.0, seed=0):
    amplitude, total, norm, frequency = 1.0, 0.0, 0.0, 1.0
    current = period
    for octave in range(max(1, octaves)):
        sample = value_noise(x * frequency, y * frequency, current, seed + octave * 977)
        ridge = 1 - abs(sample * 2 - 1)
        total += ridge * ridge * amplitude
        norm += amplitude
        amplitude *= gain
        frequency *= lacunarity
        current = int(current * lacunarity)
    return clamp(total / norm, 0, 1) if norm else 0.0


def cellular(x, y, period, jitter=1.0, seed=0):
    xi, yi = math.floor(x), math.floor(y)
    nearest, second, cell_value = 1e9, 1e9, 0.0
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            cx, cy = xi + dx, yi + dy
            jx = nhash(wrap(cx, period), wrap(cy, period), seed)
            jy = nhash(wrap(cx, period), wrap(cy, period), (seed + 0x9E3779B9) & MASK)
            px = cx + 0.5 + (jx - 0.5) * jitter
            py = cy + 0.5 + (jy - 0.5) * jitter
            distance = math.hypot(px - x, py - y)
            if distance < nearest:
                second = nearest
                nearest = distance
                cell_value = nhash(wrap(cx, period), wrap(cy, period), (seed + 7717) & MASK)
            elif distance < second:
                second = distance
    return clamp(nearest, 0, 1.5), clamp(second, 0, 2), cell_value


def warp(x, y, period, strength, octaves=3, seed=0):
    ox = fbm(x, y, period, octaves, seed=(seed + 13) & MASK) - 0.5
    oy = fbm(x, y, period, octaves, seed=(seed + 29) & MASK) - 0.5
    return x + ox * strength, y + oy * strength


def smoothstep(edge0, edge1, value):
    if edge1 == edge0:
        return 0.0 if value < edge0 else 1.0
    t = clamp((value - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def wave(x, y, period, cycles_x, cycles_y, phase=0.0):
    """Mirrors Noise.wave: whole cycles per tile, so the result is seamless."""
    if period <= 0:
        return 0.5
    u, v = x / float(period), y / float(period)
    return (math.sin((u * cycles_x + v * cycles_y) * 2 * math.pi + phase) + 1) * 0.5


def grid_distance(x, y, cells):
    fx, fy = x * cells, y * cells
    dx = min(fx - math.floor(fx), 1 - (fx - math.floor(fx)))
    dy = min(fy - math.floor(fy), 1 - (fy - math.floor(fy)))
    return min(dx, dy)


def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def mix(a, b, t):
    t = clamp(t, 0, 1)
    return (a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t)


def rgb(hexcode):
    return (((hexcode >> 16) & 0xFF) / 255.0, ((hexcode >> 8) & 0xFF) / 255.0,
            (hexcode & 0xFF) / 255.0)


def scale(c, s):
    return (c[0] * s, c[1] * s, c[2] * s)

# ──────────────────────────── Surfaces ────────────────────────────

def surface_concrete(x, y, seed):
    near, _, cell_value = cellular(x * 17, y * 17, 17, 1.0, seed)
    stone_size = 0.22 + cell_value * 0.2
    aggregate = (1 - smoothstep(stone_size * 0.55, stone_size, near)) * (0.35 + cell_value * 0.65)
    pit_near, _, pit_cell = cellular(x * 40, y * 40, 40, 1.0, seed + 29)
    pits = (1 - smoothstep(0.0, 0.22, pit_near)) if pit_cell > 0.7 else 0.0
    grain = fbm(x * 48, y * 48, 48, 4, seed=seed + 3)
    wx, wy = warp(x * 5, y * 5, 5, 1.2, seed=seed + 11)
    m_near, m_second, m_cell = cellular(wx, wy, 5, 1.0, seed + 17)
    major = (1 - smoothstep(0.0, 0.045, m_second - m_near)) * smoothstep(0.62, 0.82, m_cell)
    cx, cy = warp(x * 13, y * 13, 13, 0.8, seed=seed + 31)
    c_near, c_second, c_cell = cellular(cx, cy, 13, 1.0, seed + 37)
    craze = (1 - smoothstep(0.0, 0.025, c_second - c_near)) * smoothstep(0.78, 0.93, c_cell)
    cracks = clamp(major + craze * 0.45, 0, 1)
    mottle = fbm(x * 2, y * 2, 2, 4, basis="gradient", seed=seed + 19)
    stains = fbm(x * 4, y * 4, 4, 5, basis="gradient", seed=seed + 23)

    h = clamp(grain * 0.35 + aggregate * 0.5 - pits * 0.8 - cracks * 0.8, 0, 1)
    colour = mix(rgb(0x8F8B82), rgb(0xA9A59A), mottle)
    colour = mix(colour, rgb(0x8E8A80), aggregate * 0.55)
    colour = scale(colour, 0.86 + h * 0.26)
    colour = mix(colour, rgb(0x55534E), smoothstep(0.58, 0.92, stains) * 0.3)
    colour = mix(colour, scale(rgb(0x55534E), 0.75), pits * 0.8)
    colour = mix(colour, scale(rgb(0x55534E), 0.55), cracks * 0.85)
    return colour


def surface_metal(x, y, seed):
    cells = 2
    brushed = fbm(x * 3, y * 110, 110, 3, seed=seed)
    seams = 1 - smoothstep(0.0, 0.022, grid_distance(x, y, cells))
    spacing = 8
    seam_u, seam_v = x * cells, y * cells
    to_vertical = abs(seam_u - round(seam_u)) / cells
    to_horizontal = abs(seam_v - round(seam_v)) / cells
    step = 1.0 / spacing
    along_y = abs(y / step - round(y / step)) * step
    along_x = abs(x / step - round(x / step)) * step
    rivets = 1 - smoothstep(0.013, 0.021,
                            min(math.hypot(to_vertical, along_y),
                                math.hypot(to_horizontal, along_x)))
    wx, wy = warp(x * 10, y * 10, 10, 2.2, seed=seed + 41)
    scratches = smoothstep(0.88, 0.99, ridged(wx * 1.4, wy * 0.3, 14, 3, seed=seed + 47))
    near_seam = 1 - smoothstep(0.0, 0.12, grid_distance(x, y, cells))
    rust = smoothstep(0.60, 0.82,
                      fbm(x * 4, y * 4, 4, 5, basis="gradient", seed=seed + 59) + near_seam * 0.16)

    colour = scale(rgb(0x7C848D), 0.88 + brushed * 0.3)
    colour = mix(colour, rgb(0x2E3339), seams * 0.65)
    colour = mix(colour, rgb(0xC8CED4), scratches)
    colour = mix(colour, mix(rgb(0x7E5233), rgb(0x6B4028), rust), rust * 0.7)
    colour = mix(colour, scale(rgb(0xC8CED4), 1.02), rivets * 0.8)
    return colour


def surface_wood(x, y, seed):
    planks = 5
    plank = math.floor(y * planks)
    plank_seed = (seed + plank * 313) & MASK
    wx, wy = warp(x * 3, y * 12, 12, 0.9, seed=plank_seed)
    cycles = 34 + int(nhash(plank, 3, plank_seed) * 3) * 6
    drift = fbm(wx, wy, 12, 3, seed=plank_seed) * 4
    rings = wave(wx, wy, 12, 0, cycles, drift)
    grain = fbm(x * 120, y * 8, 120, 3, seed=seed + 71)
    fy = y * planks
    local = fy - math.floor(fy)
    gaps = 1 - smoothstep(0.0, 0.035, min(local, 1 - local))
    near, _, cell_value = cellular(x * 3, y * 3, 3, 1.0, seed + 83)
    knots = (1 - smoothstep(0.0, 0.16, near)) if cell_value > 0.82 else 0.0
    halo = ((1 - smoothstep(0.12, 0.34, near)) * smoothstep(0.1, 0.18, near)) \
        if cell_value > 0.82 else 0.0

    tint = nhash(plank, 0, seed + 97) * 0.22 - 0.11
    colour = mix(rgb(0xA3805A), rgb(0x63472C), rings * 0.75)
    colour = scale(colour, 1 + tint)
    colour = scale(colour, 0.9 + grain * 0.22)
    colour = mix(colour, rgb(0x63472C), halo * 0.5)
    colour = mix(colour, rgb(0x3A2313), knots)
    colour = mix(colour, rgb(0x241608), gaps)
    return colour


def surface_tile(x, y, seed):
    tiles = 6
    grout = 1 - smoothstep(0.012, 0.03, grid_distance(x, y, tiles))
    speckle = fbm(x * 70, y * 70, 70, 3, seed=seed)
    cell_x, cell_y = math.floor(x * tiles), math.floor(y * tiles)
    tint = nhash(cell_x, cell_y, seed + 31) * 0.14 - 0.07
    colour = scale(rgb(0xC2C8CE), 1 + tint)
    colour = scale(colour, 0.95 + speckle * 0.1)
    colour = mix(colour, rgb(0x6C6F73), grout)
    return colour


def surface_sand(x, y, seed):
    wx, wy = warp(x * 4, y * 4, 4, 0.6, seed=seed)
    ripples = wave(wx, wy, 4, 3, 11)
    grains = fbm(x * 150, y * 150, 150, 2, seed=seed + 3)
    drift = fbm(x * 5, y * 5, 5, 4, basis="gradient", seed=seed + 7)
    h = clamp(ripples * 0.5 + grains * 0.12 + drift * 0.35, 0, 1)
    return scale(mix(rgb(0xB0946A), rgb(0xD9C08A), h), 0.94 + grains * 0.12)


def surface_grass(x, y, seed):
    coarse_near, _, coarse_cell = cellular(x * 46, y * 18, 46, 1.0, seed)
    fine_near, _, fine_cell = cellular(x * 24, y * 70, 70, 1.0, seed + 101)
    coarse_blade = (1 - smoothstep(0.0, 0.3 + coarse_cell * 0.4, coarse_near)) \
        * (0.5 + coarse_cell * 0.5)
    fine_blade = (1 - smoothstep(0.0, 0.25 + fine_cell * 0.3, fine_near)) * 0.7
    blades = clamp(max(coarse_blade, fine_blade), 0, 1)
    patches = fbm(x * 6, y * 6, 6, 4, basis="gradient", seed=seed + 9)
    soil = fbm(x * 20, y * 20, 20, 3, seed=seed + 15)

    colour = mix(rgb(0x5C8442), rgb(0x8A8B4A), smoothstep(0.45, 0.8, patches))
    colour = mix(colour, mix(scale(colour, 0.7), rgb(0x8A8B4A), 0.4), coarse_cell * 0.6)
    colour = mix(colour, rgb(0x4A3B28), (1 - blades) * 0.5 * (1 - patches * 0.6))
    return scale(colour, 0.7 + blades * 0.48 + soil * 0.08)


SURFACES = {
    "concrete": (surface_concrete, 0x5EED + 0 * 7919),
    "metal": (surface_metal, 0x5EED + 1 * 7919),
    "wood": (surface_wood, 0x5EED + 2 * 7919),
    "sand": (surface_sand, 0x5EED + 4 * 7919),
    "grass": (surface_grass, 0x5EED + 5 * 7919),
    "tile": (surface_tile, 0x5EED + 11 * 7919),
}

# ──────────────────────────── Sky (mirrors SkyTextures.swift) ────────────────────────────

SKY_PRESETS = {
    "desert_noon": dict(zenith=0x2E6FB5, horizon=0xD9C39A, ground=0x8A7350, sun=0xFFF4D0,
                        sun_size=0.035, sun_glow=0.22, coverage=0.18, sharpness=2.4,
                        cloud=0xFFFBF2, cloud_shadow=0xCBBBA0, stars=0.0, haze=0.55,
                        sun_dir=(0.35, 0.88, 0.32)),
    "night_city": dict(zenith=0x080C18, horizon=0x2A2340, ground=0x0A0A12, sun=0xBFD4FF,
                       sun_size=0.02, sun_glow=0.1, coverage=0.45, sharpness=1.4,
                       cloud=0x3A3350, cloud_shadow=0x15121F, stars=0.55, haze=0.35,
                       sun_dir=(-0.3, 0.9, 0.3)),
    "snow_storm": dict(zenith=0x8FA3B8, horizon=0xD6E2EC, ground=0xBCCBD8, sun=0xF2F7FF,
                       sun_size=0.12, sun_glow=0.6, coverage=0.92, sharpness=0.9,
                       cloud=0xE4EDF5, cloud_shadow=0xA8BAC9, stars=0.0, haze=0.95,
                       sun_dir=(-0.25, 0.8, -0.55)),
}


def normalize(v):
    length = math.sqrt(v[0] * v[0] + v[1] * v[1] + v[2] * v[2]) or 1.0
    return (v[0] / length, v[1] / length, v[2] / length)


def sky_color(direction, preset, seed=0x5C4B):
    elevation = direction[1]
    if elevation >= 0:
        t = pow(clamp(elevation, 0, 1), 0.45)
        colour = mix(rgb(preset["horizon"]), rgb(preset["zenith"]), t)
    else:
        t = pow(clamp(-elevation, 0, 1), 0.6)
        colour = mix(rgb(preset["horizon"]), rgb(preset["ground"]), t)

    if preset["stars"] > 0 and elevation > -0.05:
        scale_factor = 220
        gx = math.floor(direction[0] * scale_factor)
        gy = math.floor(direction[1] * scale_factor)
        gz = math.floor(direction[2] * scale_factor)
        if nhash(gx + gz * 7919, gy, seed + 101) > 1 - preset["stars"] * 0.06:
            brightness = nhash(gx, gy + gz * 31, seed + 211)
            intensity = pow(brightness, 3) * 1.4 + 0.15
            temperature = nhash(gz, gx, seed + 307)
            star = (1.0, 0.92 + temperature * 0.08, 0.85 + temperature * 0.15)
            colour = (colour[0] + star[0] * intensity,
                      colour[1] + star[1] * intensity,
                      colour[2] + star[2] * intensity)

    sun_dir = normalize(preset["sun_dir"])
    if preset["sun_size"] > 0:
        alignment = clamp(direction[0] * sun_dir[0] + direction[1] * sun_dir[1]
                          + direction[2] * sun_dir[2], -1, 1)
        angle = math.acos(alignment)
        disc = 1 - smoothstep(preset["sun_size"] * 0.8, preset["sun_size"], angle)
        glow = pow(clamp(alignment, 0, 1), 64) * preset["sun_glow"] \
            + pow(clamp(alignment, 0, 1), 6) * preset["sun_glow"] * 0.25
        sun = rgb(preset["sun"])
        colour = (colour[0] + sun[0] * glow, colour[1] + sun[1] * glow, colour[2] + sun[2] * glow)
        colour = mix(colour, scale(sun, 1.6), disc)

    if preset["coverage"] > 0 and elevation > 0.02:
        projection = 1 / max(elevation, 0.04)
        px = direction[0] * projection * 2.5
        pz = direction[2] * projection * 2.5
        wx, wy = warp(px, pz, 512, 0.9, seed=seed + 3)
        density = fbm(wx, wy, 512, 5, gain=0.55, basis="gradient", seed=seed + 5)
        threshold = 0.68 - preset["coverage"] * 0.45
        amount = smoothstep(threshold, threshold + 0.22 / preset["sharpness"], density)
        amount *= smoothstep(0.06, 0.34, elevation)
        lit = smoothstep(threshold, threshold + 0.34, density + 0.06)
        colour = mix(colour, mix(rgb(preset["cloud_shadow"]), rgb(preset["cloud"]), lit), amount)

    haze = (1 - smoothstep(0, 0.35, abs(elevation))) * preset["haze"]
    return mix(colour, rgb(preset["horizon"]), haze * 0.5)


def render_sky_panorama(name, width, height):
    """A horizontal panorama, which shows far more of the sky at once than a cube face."""
    preset = SKY_PRESETS[name]
    out = bytearray(width * height * 4)
    for y in range(height):
        # Elevation from +80 degrees at the top to −20 at the bottom.
        elevation = math.radians(80 - (y / float(height)) * 100)
        for x in range(width):
            azimuth = (x / float(width)) * 2 * math.pi
            direction = (math.cos(elevation) * math.sin(azimuth),
                         math.sin(elevation),
                         math.cos(elevation) * math.cos(azimuth))
            colour = sky_color(direction, preset)
            index = (y * width + x) * 4
            out[index] = int(clamp(colour[0], 0, 1) * 255)
            out[index + 1] = int(clamp(colour[1], 0, 1) * 255)
            out[index + 2] = int(clamp(colour[2], 0, 1) * 255)
            out[index + 3] = 255
    return out


# ──────────────────────────── Decals (mirrors SpriteTextures.swift) ────────────────────────────

def radial_cracks(angle, radius, seed, count, reach, width=0.02):
    strongest = 0.0
    for index in range(count):
        spoke_seed = (seed + index * 131) & MASK
        spoke_angle = (nhash(index, 0, spoke_seed) * 2 - 1) * math.pi
        spoke_length = reach * (0.35 + nhash(index, 1, spoke_seed) * 0.65)
        if radius >= spoke_length:
            continue
        difference = abs((angle - spoke_angle + math.pi) % (2 * math.pi) - math.pi)
        difference -= (nhash(index, int(radius * 20), spoke_seed) - 0.5) * 0.08
        taper = 1 - radius / spoke_length
        half_width = (width + taper * width * 2) / max(radius, 0.08)
        strongest = max(strongest, (1 - smoothstep(0, half_width, abs(difference))) * taper)
    return strongest


def concentric_cracks(radius, seed):
    strongest = 0.0
    for index in range(1, 4):
        ring = 0.2 + index * 0.2 + nhash(index, 9, seed) * 0.06
        strongest = max(strongest, (1 - smoothstep(0, 0.012, abs(radius - ring))) * (1 - radius))
    return strongest


def decal_pixel(kind, dx, dy, nx, ny, seed):
    radius = math.hypot(dx, dy)
    angle = math.atan2(dy, dx)
    if kind == "bullet_hole_hard":
        hole = 1 - smoothstep(0.14, 0.2, radius)
        chipped = fbm(nx * 6, ny * 6, 6, 3, seed=seed + 5)
        rim = (1 - smoothstep(0.2 + (chipped - 0.5) * 0.18, 0.46, radius)) \
            * smoothstep(0.12, 0.2, radius)
        cracks = radial_cracks(angle, radius, seed, 11, 0.9, 0.032)
        alpha = clamp(hole + rim * 0.5 + cracks * 0.85, 0, 1)
        colour = mix((0.06, 0.06, 0.07), (0.78, 0.76, 0.72), rim)
    elif kind == "bullet_hole_metal":
        hole = 1 - smoothstep(0.12, 0.17, radius)
        petals = abs(math.cos(angle * 5 + nhash(0, 0, seed) * 6))
        tear = (1 - smoothstep(0.15, 0.15 + petals * 0.22, radius)) * smoothstep(0.1, 0.16, radius)
        alpha = clamp(hole + tear * 0.85, 0, 1)
        colour = mix((0.04, 0.04, 0.05), (0.85, 0.86, 0.9), tear)
    elif kind == "glass_crack":
        hole = 1 - smoothstep(0.05, 0.1, radius)
        radials = radial_cracks(angle, radius, seed, 11, 1.0, 0.012)
        rings = concentric_cracks(radius, seed)
        alpha = clamp(hole + radials * 0.9 + rings * 0.5, 0, 1)
        colour = (0.86, 0.94, 0.98)
    else:  # blood_splat
        wobble = fbm(nx * 7, ny * 7, 7, 4, basis="gradient", seed=seed)
        edge = 0.3 + (wobble - 0.5) * 0.7
        body = 1 - smoothstep(edge, edge + 0.16, radius)
        near, _, cell_value = cellular(nx * 6, ny * 6, 6, 1.0, seed + 3)
        droplet_size = 0.06 + cell_value * 0.14
        spatter = (1 - smoothstep(droplet_size * 0.5, droplet_size, near)) if cell_value > 0.6 else 0.0
        alpha = clamp(body + spatter * 0.85, 0, 1) * (1 - smoothstep(0.82, 1.0, radius))
        colour = mix((0.3, 0.02, 0.03), (0.55, 0.07, 0.07), wobble)
    return colour, alpha


def render_decal_sheet(kinds, cell, seed=0xDEC1):
    """Decals on a checkerboard, so the alpha channel is visible."""
    width = cell * len(kinds)
    out = bytearray(width * cell * 4)
    for y in range(cell):
        for column, kind in enumerate(kinds):
            for x in range(cell):
                nx, ny = x / float(cell), y / float(cell)
                dx, dy = (nx - 0.5) * 2, (ny - 0.5) * 2
                colour, alpha = decal_pixel(kind, dx, dy, nx, ny, seed)
                check = 0.55 if ((x // 12) + (y // 12)) % 2 == 0 else 0.42
                background = (check, check, check)
                final = mix(background, colour, alpha)
                index = (y * width + column * cell + x) * 4
                out[index] = int(clamp(final[0], 0, 1) * 255)
                out[index + 1] = int(clamp(final[1], 0, 1) * 255)
                out[index + 2] = int(clamp(final[2], 0, 1) * 255)
                out[index + 3] = 255
    return width, out


# ──────────────────────────── Rendering ────────────────────────────

def render_sheet(name, size, tiles=2):
    generator, seed = SURFACES[name]
    # Evaluate one tile, then repeat it — which also proves the tile is seamless, because
    # any discontinuity shows up as a hard line at the repeat boundary.
    tile_pixels = []
    for y in range(size):
        ny = y / float(size)
        row = []
        for x in range(size):
            colour = generator(x / float(size), ny, seed)
            row.append((int(clamp(colour[0], 0, 1) * 255),
                        int(clamp(colour[1], 0, 1) * 255),
                        int(clamp(colour[2], 0, 1) * 255)))
        tile_pixels.append(row)

    full = size * tiles
    out = bytearray(full * full * 4)
    for y in range(full):
        for x in range(full):
            r, g, b = tile_pixels[y % size][x % size]
            index = (y * full + x) * 4
            out[index] = r
            out[index + 1] = g
            out[index + 2] = b
            out[index + 3] = 255
    return full, out


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "Docs", "previews")
    size = 160
    for name in SURFACES:
        print(f"rendering {name} …", flush=True)
        full, pixels = render_sheet(name, size)
        write_png(os.path.join(output, f"surface_{name}.png"), full, full, pixels)

    for name in SKY_PRESETS:
        print(f"rendering sky {name} …", flush=True)
        width, height = 480, 160
        write_png(os.path.join(output, f"sky_{name}.png"), width, height,
                  render_sky_panorama(name, width, height))

    print("rendering decals …", flush=True)
    kinds = ["bullet_hole_hard", "bullet_hole_metal", "glass_crack", "blood_splat"]
    width, pixels = render_decal_sheet(kinds, 96)
    write_png(os.path.join(output, "decals.png"), width, 96, pixels)

    print(f"wrote previews to {output}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
