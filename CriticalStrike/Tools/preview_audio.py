#!/usr/bin/env python3
"""Renders the synthesised sounds as waveform and spectrum sheets.

The audio counterpart of preview_textures.py, and it exists for the same reason: the Swift
is the shipping implementation, and this mirror lets the recipes be judged without a Mac.
Nobody here can hear the output, but a waveform picture catches everything that actually
goes wrong in synthesis — a filter blowing up, a sound that is silent, one that clips flat,
a transient that is not a transient, a tail three times longer than intended — and a
spectrum catches a rifle that is brighter than a pistol when it should be darker.

    python3 Tools/preview_audio.py        # writes Docs/previews/audio_*.png
    python3 Tools/preview_audio.py --wav  # also writes playable .wav files
"""
import math
import os
import struct
import sys
import zlib

RATE = 44100.0
MASK64 = (1 << 64) - 1


# ── PNG ────────────────────────────────────────────────────────────────────────

def write_png(path, width, height, pixels):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    raw = bytearray()
    stride = width * 4
    for y in range(height):
        raw.append(0)
        raw.extend(pixels[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        out = struct.pack('>I', len(data)) + tag + data
        return out + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)

    header = struct.pack('>IIBBBBB', width, height, 8, 6, 0, 0, 0)
    with open(path, 'wb') as handle:
        handle.write(b'\x89PNG\r\n\x1a\n')
        handle.write(chunk(b'IHDR', header))
        handle.write(chunk(b'IDAT', zlib.compress(bytes(raw), 6)))
        handle.write(chunk(b'IEND', b''))


def write_wav(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    frames = b''.join(struct.pack('<h', int(max(-1.0, min(1.0, s)) * 32767)) for s in samples)
    with open(path, 'wb') as handle:
        handle.write(b'RIFF' + struct.pack('<I', 36 + len(frames)) + b'WAVE')
        handle.write(b'fmt ' + struct.pack('<IHHIIHH', 16, 1, 1, int(RATE), int(RATE) * 2, 2, 16))
        handle.write(b'data' + struct.pack('<I', len(frames)) + frames)


# ── Mirror of DeterministicRandom ──────────────────────────────────────────────

class Random:
    """xoshiro-free mirror: only the distribution matters for a preview, not the bits."""
    def __init__(self, seed):
        self.state = (seed ^ 0x9E3779B97F4A7C15) & MASK64

    def next(self):
        self.state = (self.state * 6364136223846793005 + 1442695040888963407) & MASK64
        return self.state

    def unit(self):
        return ((self.next() >> 11) & ((1 << 24) - 1)) / float(1 << 24)

    def signed_unit(self):
        return self.unit() * 2 - 1

    def float_in(self, lo, hi):
        return lo + self.unit() * (hi - lo)


# ── Mirror of Synth ────────────────────────────────────────────────────────────

def clamp(v, lo, hi):
    return lo if v < lo else (hi if v > hi else v)


def noise(seconds, seed):
    r = Random(seed)
    return [r.signed_unit() for _ in range(int(seconds * RATE))]


def wave_sample(kind, phase):
    w = phase - math.floor(phase)
    if kind == 'sine':
        return math.sin(w * 2 * math.pi)
    if kind == 'triangle':
        return 4 * abs(w - 0.5) - 1
    if kind == 'sawtooth':
        return w * 2 - 1
    return 1.0 if w < 0.5 else -1.0


def sweep(start, end, seconds, kind='sine', curve=2.5):
    n = int(seconds * RATE)
    out = [0.0] * n
    acc = 0.0
    if start == end:
        # Steady tone: no glide maths, same as the Swift fast path.
        step = start / RATE
        for i in range(n):
            acc += step
            out[i] = wave_sample(kind, acc)
        return out
    for i in range(n):
        t = i / float(n) if n else 0.0
        f = end + (start - end) * ((1 - t) ** curve)
        acc += f / RATE
        out[i] = wave_sample(kind, acc)
    return out


def tone(freq, seconds, kind='sine'):
    return sweep(freq, freq, seconds, kind)


def envelope(buf, attack, decay, hold=0.0, curve=3.0):
    a = max(1, int(attack * RATE))
    h = int(hold * RATE)
    d = max(1, int(decay * RATE))
    out = list(buf)
    for i in range(len(out)):
        if i < a:
            g = i / float(a)
        elif i < a + h:
            g = 1.0
        else:
            p = (i - a - h) / float(d)
            g = 0.0 if p >= 1 else (1 - p) ** curve
        out[i] *= g
    return out


def decay_tail(buf, half_life):
    if half_life <= 0:
        return list(buf)
    per = 0.5 ** (1 / (half_life * RATE))
    out = list(buf)
    g = 1.0
    for i in range(len(out)):
        out[i] *= g
        g *= per
    return out


def svf(buf, mode, cutoff, resonance=0.7):
    cutoff = clamp(cutoff, 10, RATE * 0.49)
    f = 2 * math.sin(math.pi * clamp(cutoff / RATE, 0.0001, 0.24))
    q = 1 / clamp(resonance, 0.5, 10)
    low = band = 0.0
    out = [0.0] * len(buf)
    for i, x in enumerate(buf):
        high = x - low - q * band
        band += f * high
        low += f * band
        out[i] = {'low': low, 'band': band, 'high': high}[mode]
    return out


def sweeping_low_pass(buf, start, end, resonance=0.7):
    q = 1 / clamp(resonance, 0.5, 10)
    low = band = 0.0
    out = [0.0] * len(buf)
    n = len(buf) or 1
    for i, x in enumerate(buf):
        cutoff = start + (end - start) * (i / float(n))
        f = 2 * math.sin(math.pi * clamp(cutoff / RATE, 0.0001, 0.24))
        high = x - low - q * band
        band += f * high
        low += f * band
        out[i] = low
    return out


def saturate(buf, drive=3.0):
    norm = math.tanh(drive)
    return [math.tanh(x * drive) / norm for x in buf]


def pad(buf, seconds):
    target = int(seconds * RATE)
    return buf + [0.0] * max(0, target - len(buf))


def delay(buf, seconds, feedback, mix, tail=0.0):
    out = pad(list(buf), len(buf) / RATE + tail)
    step = max(1, int(seconds * RATE))
    if step >= len(out):
        return list(buf)
    fb = clamp(feedback, 0, 0.95)
    for i in range(step, len(out)):
        out[i] += out[i - step] * fb * mix
    return out


def room(buf, size, decay_amount, mix=0.4):
    total = len(buf) / RATE + size * 1.2
    dry = pad(list(buf), total)
    wet = [0.0] * len(dry)
    fb = clamp(decay_amount, 0, 0.92)
    spacings = [0.0297, 0.0371, 0.0411, 0.0437]
    for spacing in spacings:
        step = max(1, int(spacing * size * RATE))
        if step >= len(dry):
            continue
        line = [0.0] * len(dry)
        for i in range(step, len(line)):
            line[i] = (dry[i - step] + line[i - step]) * fb
        for i in range(len(wet)):
            wet[i] += line[i] / len(spacings)
    return [dry[i] + wet[i] * mix for i in range(len(dry))]

def trimmed_silence(buf, threshold=0.002, release=0.05):
    last = -1
    for i in range(len(buf) - 1, -1, -1):
        if abs(buf[i]) > threshold:
            last = i
            break
    if last < 0:
        return list(buf)
    end = min(len(buf), last + int(release * RATE))
    return faded(buf[:end], 0.0, release)


def mix_into(base, other, at=0.0, gain=1.0):
    offset = int(max(0.0, at) * RATE)
    needed = offset + len(other)
    if needed > len(base):
        base.extend([0.0] * (needed - len(base)))
    for i, s in enumerate(other):
        base[offset + i] += s * gain
    return base


def normalized(buf, target=0.9):
    peak = max((abs(s) for s in buf), default=0.0)
    return list(buf) if peak < 1e-6 else [s * target / peak for s in buf]


def faded(buf, fade_in=0.001, fade_out=0.01):
    out = list(buf)
    a = min(int(fade_in * RATE), len(out))
    b = min(int(fade_out * RATE), len(out))
    for i in range(a):
        out[i] *= i / float(max(1, a))
    for i in range(b):
        out[len(out) - 1 - i] *= i / float(max(1, b))
    return out


def loopable(buf, crossfade):
    fade = min(int(crossfade * RATE), len(buf) // 2)
    if fade <= 1:
        return list(buf)
    out = list(buf[:len(buf) - fade])
    for i in range(fade):
        t = i / float(fade)
        out[i] = buf[i] * math.sqrt(t) + buf[len(buf) - fade + i] * math.sqrt(1 - t)
    return out


# ── Mirror of SoundBank ────────────────────────────────────────────────────────

def fnv(text):
    value = 0xcbf29ce484222325
    for byte in text.encode('utf-8'):
        value = ((value ^ byte) * 0x100000001b3) & MASK64
    return value


def gunshot(base_damage, rpm, shotgun=False, seed=1):
    power = clamp(base_damage / 40.0, 0.35, 2.2)
    cadence = clamp(rpm / 600.0, 0.4, 2.0)
    size = clamp(power / cadence, 0.3, 2.4)
    length = clamp(0.16 + size * 0.22, 0.14, 0.62)

    shot = envelope(svf(noise(0.05, seed), 'high', 2600, 1.1), 0.0004, 0.02, curve=4)
    shot = [s * 0.85 for s in shot]

    start_cutoff = 5200 / (0.6 + size)
    body = envelope(sweeping_low_pass(noise(length, seed + 11), start_cutoff,
                                      start_cutoff * 0.28, 1.3),
                    0.0008, length * 0.8, hold=0.004, curve=2.6)
    mix_into(shot, body, 0, 1.0)

    thump = envelope(sweep(400 / (0.6 + size), 90 / (0.4 + size * 0.3), length * 0.9, 'sine', 3),
                     0.001, length * 0.7, curve=2.2)
    mix_into(shot, thump, 0, 0.22 + size * 0.12)

    action = envelope(svf(noise(0.04, seed + 23), 'band', 3200, 2.4), 0.0005, 0.03, curve=3)
    mix_into(shot, action, 0.012, 0.18)

    if shotgun:
        second = envelope(sweeping_low_pass(noise(length, seed + 37), 2400, 500, 1.0),
                          0.001, length, hold=0.006, curve=2.2)
        mix_into(shot, second, 0.003, 0.7)

    tailed = room(saturate(shot, 1.6 + size * 0.5), 0.7 + size * 0.5, 0.34 + size * 0.1, 0.30)
    tailed = svf(tailed, 'high', 62, 0.6)
    return faded(trimmed_silence(normalized(tailed, clamp(0.62 + size * 0.14, 0.6, 0.95))), 0.0002, 0.03)


def footstep_metal(seed):
    hit = envelope(svf(noise(0.22, seed), 'band', 2400, 2.6), 0.0008, 0.1, curve=3)
    mix_into(hit, decay_tail(tone(880, 0.3), 0.07), 0, 0.28)
    mix_into(hit, decay_tail(tone(1470, 0.25), 0.05), 0, 0.16)
    return faded(normalized(hit, 0.45))


def footstep_grass(seed):
    step = envelope(svf(noise(0.2, seed), 'high', 2200, 0.8), 0.006, 0.12, curve=2)
    return faded(normalized(step, 0.45))


def footstep_water(seed):
    step = envelope(sweeping_low_pass(noise(0.3, seed), 700, 6000, 0.9), 0.004, 0.22, curve=1.7)
    return faded(normalized(step, 0.45))


def explosion(seed):
    blast = envelope(sweep(240, 58, 1.1, 'sine', 2.4), 0.002, 0.9, curve=2)
    mix_into(blast, envelope(sweeping_low_pass(noise(1.2, seed), 4200, 260, 1.1),
                             0.001, 1.1, hold=0.01, curve=2.2), 0, 0.9)
    mix_into(blast, envelope(svf(noise(0.7, seed + 3), 'high', 3000), 0.02, 0.6, curve=2),
             0.09, 0.22)
    tailed = svf(room(saturate(blast, 3.5), 1.6, 0.5, 0.42), 'high', 55, 0.6)
    return faded(trimmed_silence(normalized(tailed, 0.95)), 0.0004, 0.15)


def hit_marker(headshot):
    base = 1760.0 if headshot else 1180.0
    tick = envelope(tone(base, 0.07), 0.0006, 0.05, curve=4)
    mix_into(tick, envelope(tone(base * 1.5, 0.06), 0.0006, 0.04, curve=4), 0, 0.5)
    if headshot:
        mix_into(tick, envelope(tone(base * 2, 0.06), 0.0006, 0.04, curve=4), 0.045, 0.55)
    return faded(normalized(tick, 0.6 if headshot else 0.45))


def reload_sound(weight, shells, seed):
    out = [0.0] * int((0.8 if shells else 1.05) * RATE)
    pitch = clamp(1.4 / max(0.4, weight), 0.6, 1.8)

    def clack(at, cutoff, dec, gain, s):
        click = envelope(svf(noise(dec * 2, s), 'band', cutoff * pitch, 3.0), 0.0006, dec, curve=3)
        ring = decay_tail(tone(cutoff * pitch * 1.6, dec * 1.4), dec * 0.35)
        mix_into(out, click, at, gain)
        mix_into(out, ring, at, gain * 0.22)

    if shells:
        clack(0.02, 2100, 0.05, 0.8, seed)
        clack(0.30, 1500, 0.09, 0.9, seed + 5)
    else:
        clack(0.02, 1800, 0.07, 0.75, seed)
        clack(0.34, 1200, 0.10, 0.55, seed + 5)
        clack(0.62, 1600, 0.11, 0.95, seed + 9)
        clack(0.86, 2600, 0.07, 0.8, seed + 13)
    return faded(normalized(out, 0.62))


def ambience_wind(seed, harsh=False):
    bed = svf(noise(8, seed), 'band', 900 if harsh else 520, 1.4 if harsh else 1.0)
    r = Random(seed + 3)
    for _ in range(7):
        gust = envelope(svf(noise(r.float_in(1.2, 2.6), r.next()), 'band',
                            r.float_in(700, 2200), 1.6), 0.5, 1.4, curve=1.6)
        mix_into(bed, gust, r.float_in(0, 5.5), r.float_in(0.25, 0.6))
    return normalized(loopable(bed, 1.2), 0.32)


def music(root, bpm, seed):
    beat = 60.0 / bpm
    seconds = beat * 4 * 8
    track = [0.0] * int(seconds * RATE)
    for ratio, gain in [(1.0, 0.5), (1.5, 0.22), (2.0, 0.16), (1.003, 0.2)]:
        mix_into(track, tone(root * ratio, seconds, 'triangle'), 0, gain)
    r = Random(seed)
    index, time = 0, 0.0
    while time < seconds - beat:
        accent = index % 4 == 0
        pulse = envelope(sweep(root * (4 if accent else 3), root * 2, beat * 0.8, 'triangle', 2),
                         0.004, beat * 0.55, curve=2.6)
        mix_into(track, pulse, time, 0.3 if accent else 0.16)
        if index % 2 == 1:
            mix_into(track, envelope(svf(noise(0.12, r.next()), 'band', 4200, 3),
                                     0.001, 0.08, curve=3), time + beat * 0.5, 0.08)
        index += 1
        time += beat
    return normalized(loopable(svf(track, 'low', 2600, 0.8), beat * 2), 0.42)


# ── Drawing ────────────────────────────────────────────────────────────────────

BG = (16, 17, 20)
GRID = (44, 46, 52)
TRACE = (255, 150, 40)
SPECTRUM = (90, 200, 255)


def blank(width, height):
    buf = bytearray(width * height * 4)
    for i in range(0, len(buf), 4):
        buf[i], buf[i + 1], buf[i + 2], buf[i + 3] = BG[0], BG[1], BG[2], 255
    return buf


def put(buf, width, height, x, y, colour):
    if 0 <= x < width and 0 <= y < height:
        i = (y * width + x) * 4
        buf[i], buf[i + 1], buf[i + 2] = colour


def draw_waveform(buf, width, height, top, rows, samples, colour=TRACE):
    """Min/max envelope per column — the honest way to draw audio at this scale."""
    if not samples:
        return
    mid = top + rows // 2
    for x in range(width):
        put(buf, width, height, x, mid, GRID)
    step = max(1, len(samples) // width)
    for x in range(width):
        chunk = samples[x * step:(x + 1) * step]
        if not chunk:
            continue
        lo, hi = min(chunk), max(chunk)
        y0 = mid - int(hi * rows * 0.48)
        y1 = mid - int(lo * rows * 0.48)
        for y in range(min(y0, y1), max(y0, y1) + 1):
            put(buf, width, height, x, y, colour)


def spectrum(samples, bands=64):
    """Goertzel at log-spaced frequencies. Slow, exact enough, no dependencies."""
    n = min(len(samples), int(0.25 * RATE))
    if n < 64:
        return [0.0] * bands
    window = samples[:n]
    out = []
    for band in range(bands):
        freq = 40.0 * ((16000.0 / 40.0) ** (band / float(bands - 1)))
        k = 2 * math.cos(2 * math.pi * freq / RATE)
        s1 = s2 = 0.0
        for x in window:
            s0 = x + k * s1 - s2
            s2, s1 = s1, s0
        power = s1 * s1 + s2 * s2 - k * s1 * s2
        out.append(math.sqrt(max(0.0, power)) / n)
    peak = max(out) or 1.0
    return [v / peak for v in out]


def draw_spectrum(buf, width, height, top, rows, samples):
    bands = spectrum(samples)
    per = max(1, width // len(bands))
    for index, value in enumerate(bands):
        # dB, because linear magnitude hides everything below the fundamental.
        db = 20 * math.log10(max(value, 1e-4))
        norm = clamp((db + 60) / 60.0, 0.0, 1.0)
        h = int(norm * (rows - 4))
        for x in range(index * per, min(width, (index + 1) * per - 1)):
            for y in range(top + rows - h, top + rows):
                put(buf, width, height, x, y, SPECTRUM)


def sheet(path, entries, width=760):
    """One row per sound: waveform on top, spectrum beneath."""
    row = 96
    height = row * len(entries)
    buf = blank(width, height)
    for index, (_, samples) in enumerate(entries):
        top = index * row
        for x in range(width):
            put(buf, width, height, x, top, GRID)
        draw_waveform(buf, width, height, top + 4, 56, samples)
        draw_spectrum(buf, width, height, top + 62, 32, samples)
    write_png(path, width, height, buf)


def main():
    out_dir = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))),
                           "Docs", "previews")
    want_wav = "--wav" in sys.argv

    weapons = [
        ("sniper  (95 dmg, 45 rpm)", gunshot(95, 45, seed=fnv("snp_longbow") & 0xFFFF)),
        ("rifle   (33 dmg, 640 rpm)", gunshot(33, 640, seed=fnv("ar_vanguard") & 0xFFFF)),
        ("smg     (24 dmg, 900 rpm)", gunshot(24, 900, seed=fnv("smg_falcon") & 0xFFFF)),
        ("pistol  (28 dmg, 420 rpm)", gunshot(28, 420, seed=fnv("pst_sidearm") & 0xFFFF)),
        ("shotgun (16x8, 75 rpm)", gunshot(16, 75, shotgun=True, seed=fnv("sg_breaker") & 0xFFFF)),
    ]
    others = [
        ("explosion", explosion(0xE1)),
        ("reload (rifle)", reload_sound(1.0, False, 0x7A)),
        ("hit marker", hit_marker(False)),
        ("headshot", hit_marker(True)),
        ("step metal", footstep_metal(0x51)),
        ("step grass", footstep_grass(0x52)),
        ("step water", footstep_water(0x53)),
    ]
    beds = [
        ("amb_desert_wind", ambience_wind(fnv("amb_desert_wind") & 0xFFFF)),
        ("amb_blizzard", ambience_wind(fnv("amb_blizzard") & 0xFFFF, harsh=True)),
        ("mus_sandstorm", music(110.0, 96, fnv("mus_sandstorm") & 0xFFFF)),
    ]

    for name, entries in (("audio_weapons", weapons), ("audio_effects", others),
                          ("audio_beds", beds)):
        print(f"rendering {name} …", flush=True)
        sheet(os.path.join(out_dir, f"{name}.png"), entries)

    print("\n%-26s %8s %8s %8s %9s" % ("sound", "seconds", "peak", "rms", "centroid"))
    for _, entries in (("", weapons), ("", others), ("", beds)):
        for name, samples in entries:
            bands = spectrum(samples)
            total = sum(bands) or 1.0
            centroid = sum(v * 40.0 * ((16000.0 / 40.0) ** (i / 63.0))
                           for i, v in enumerate(bands)) / total
            peak = max(abs(s) for s in samples)
            rms = math.sqrt(sum(s * s for s in samples) / len(samples))
            print("%-26s %8.3f %8.3f %8.4f %8.0f Hz" %
                  (name, len(samples) / RATE, peak, rms, centroid))
            if want_wav:
                key = name.split()[0].strip("()")
                write_wav(os.path.join(out_dir, "audio", f"{key}.wav"), samples)

    print(f"\nwrote previews to {out_dir}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
