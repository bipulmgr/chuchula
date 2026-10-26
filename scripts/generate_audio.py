#!/usr/bin/env python3
"""Synthesizes Chuchula's original sound effects and background music.

Everything here is generated from scratch (no samples), so the output is
original work licensed with the project. Requires numpy and ffmpeg.

    python3 scripts/generate_audio.py

Writes OGG Vorbis files to assets/audio/.
"""
import os
import subprocess
import tempfile
import wave

import numpy as np

SR = 44100
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
rng = np.random.default_rng(2026)


def t(seconds):
    return np.arange(int(SR * seconds)) / SR


def env(n, attack=0.005, decay=0.2):
    x = np.arange(n) / SR
    a = np.clip(x / max(attack, 1e-4), 0, 1)
    return a * np.exp(-x / max(decay, 1e-4))


def lowpass(x, cutoff):
    # Simple one-pole low-pass filter.
    alpha = 1 - np.exp(-2 * np.pi * cutoff / SR)
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def highpass(x, cutoff):
    return x - lowpass(x, cutoff)


def bell(freq, dur, decay=0.8, gain=0.5):
    """Singing-bowl / bell tone with inharmonic partials."""
    x = t(dur)
    partials = [(1.0, 1.0), (2.76, 0.45), (5.4, 0.25), (8.93, 0.12)]
    y = sum(g * np.sin(2 * np.pi * freq * r * x) * np.exp(-x * (1 + r) / (decay * 3))
            for r, g in partials)
    return gain * y * env(len(x), 0.002, decay)


def pluck(freq, dur, decay=0.35, gain=0.5, bright=0.6):
    """Karplus-Strong plucked string (sitar-ish with a buzz)."""
    n = int(SR * dur)
    period = int(SR / freq)
    buf = rng.uniform(-1, 1, period)
    out = np.zeros(n)
    for i in range(n):
        out[i] = buf[i % period]
        nxt = buf[(i + 1) % period]
        buf[i % period] = 0.5 * (buf[i % period] + nxt) * (0.994 + 0.005 * bright)
    # Jawari-like buzz: soft clipping of the bright component.
    out = np.tanh(out * 1.8) * 0.7 + out * 0.3
    return gain * out * env(n, 0.001, decay * 2)


def drum(freq, dur, bend=1.6, decay=0.12, gain=0.8, noise=0.15):
    """Hand drum (madal-like) with a falling pitch."""
    x = t(dur)
    f = freq * (1 + (bend - 1) * np.exp(-x / 0.03))
    phase = 2 * np.pi * np.cumsum(f) / SR
    body = np.sin(phase) * env(len(x), 0.001, decay)
    slap = lowpass(rng.uniform(-1, 1, len(x)), 3000) * env(len(x), 0.0005, 0.02)
    return gain * (body + noise * slap)


def noise_burst(dur, cutoff_lo, cutoff_hi, decay, gain):
    x = rng.uniform(-1, 1, int(SR * dur))
    y = highpass(lowpass(x, cutoff_hi), cutoff_lo)
    return gain * y * env(len(x), 0.001, decay)


def mix(length, *parts):
    out = np.zeros(int(SR * length))
    for start, sig in parts:
        s = int(SR * start)
        e = min(len(out), s + len(sig))
        out[s:e] += sig[: e - s]
    return out


def save(name, y, quality=4):
    peak = np.max(np.abs(y)) or 1.0
    y = (y / peak * 0.89 * 32767).astype(np.int16)
    os.makedirs(OUT, exist_ok=True)
    with tempfile.NamedTemporaryFile(suffix='.wav', delete=False) as tmp:
        path = tmp.name
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(y.tobytes())
    dst = os.path.join(OUT, name + '.ogg')
    subprocess.run(['ffmpeg', '-y', '-loglevel', 'error', '-i', path,
                    '-c:a', 'libvorbis', '-q:a', str(quality), dst], check=True)
    os.remove(path)
    print('wrote', dst, os.path.getsize(dst), 'bytes')


# Bhupali-like pentatonic scale (Sa Re Ga Pa Dha) on D.
SA = 146.83
SCALE = [1, 9 / 8, 5 / 4, 3 / 2, 5 / 3]


def note(degree, octave=0):
    return SA * SCALE[degree % 5] * (2 ** (octave + degree // 5))


def sfx():
    save('deal', noise_burst(0.07, 1800, 7000, 0.018, 0.6))
    save('drag', noise_burst(0.05, 2500, 9000, 0.012, 0.35))
    save('snap', mix(0.12, (0, drum(420, 0.1, 1.3, 0.03, 0.6, 0.6)),
                     (0, noise_burst(0.04, 3000, 9000, 0.008, 0.4))))
    save('play', mix(0.35, (0, noise_burst(0.25, 400, 4000, 0.08, 0.35)),
                     (0.12, drum(180, 0.2, 1.4, 0.05, 0.8, 0.5))))
    save('turn', bell(note(4, 2), 0.9, 0.35, 0.5))
    save('button', mix(0.08, (0, drum(900, 0.06, 1.2, 0.015, 0.5, 0.3))))
    win = [(i * 0.13, bell(note(d, 2), 1.2, 0.6, 0.45))
           for i, d in enumerate([0, 1, 2, 3, 4, 5, 7])]
    win += [(0, drum(90, 0.4, 1.8, 0.15, 0.9)), (0.52, drum(90, 0.4, 1.8, 0.15, 0.9)),
            (0.78, drum(140, 0.3, 1.5, 0.08, 0.7))]
    save('win', mix(2.2, *win))
    lose = [(i * 0.22, pluck(note(d, 1), 0.9, 0.3, 0.4))
            for i, d in enumerate([4, 3, 2, 0])]
    save('lose', mix(1.8, *lose))
    chord = [(i * 0.04, bell(note(d, 2), 1.6, 0.9, 0.35)) for i, d in enumerate([0, 2, 4, 5])]
    shimmer = [(0.1 + i * 0.05, bell(note(d, 3), 0.5, 0.2, 0.15))
               for i, d in enumerate([0, 1, 2, 3, 4, 3, 2, 4])]
    save('achievement', mix(1.9, *chord, *shimmer))
    save('group_win', mix(0.9, (0, bell(note(2, 2), 0.8, 0.4, 0.4)),
                          (0.09, bell(note(4, 2), 0.8, 0.4, 0.4))))


def music():
    bpm = 84
    beat = 60 / bpm
    bars = 16
    length = bars * 4 * beat
    parts = []
    # Tanpura-like drone: Pa Sa Sa Sa(low), repeating.
    drone_notes = [note(3, -1), note(0), note(0), note(0, -1)]
    for i in range(int(length / (beat))):
        f = drone_notes[i % 4]
        parts.append((i * beat, pluck(f, beat * 2.2, 0.9, 0.18, 0.2)))
    # Madal pattern (dha .. tin dha | tin .. dha ..) per bar.
    pattern = [(0, 'lo'), (1.5, 'hi'), (2, 'lo'), (2.5, 'hi'), (3, 'hi'), (3.5, 'lo')]
    for bar in range(bars):
        for pos, kind in pattern:
            s = (bar * 4 + pos) * beat
            if kind == 'lo':
                parts.append((s, drum(95, 0.35, 1.7, 0.14, 0.55, 0.1)))
            else:
                parts.append((s, drum(330, 0.15, 1.2, 0.04, 0.35, 0.4)))
    # Melody: a gentle phrase in the pentatonic scale, played on plucks
    # and answered on bells.
    phrase_a = [(0, 2, 1), (1, 3, 0.5), (1.5, 4, 0.5), (2, 5, 1.5), (3.5, 4, 0.5),
                (4, 3, 1), (5, 2, 1), (6, 1, 1), (7, 2, 1)]
    phrase_b = [(0, 4, 1), (1, 5, 0.5), (1.5, 7, 0.5), (2, 6, 1), (3, 5, 1),
                (4, 4, 0.5), (4.5, 3, 0.5), (5, 2, 1), (6, 1, 1), (7, 0, 1)]
    form = [phrase_a, phrase_b, phrase_a, phrase_b]
    for k, phrase in enumerate(form):
        base = k * 8 * beat
        for pos, deg, durb in phrase:
            voice = pluck if k % 2 == 0 else (lambda f, d, dec, g: bell(f, d, dec, g * 0.8))
            parts.append((base + pos * beat, voice(note(deg, 1), durb * beat * 2.5, 0.5, 0.33)))
    y = mix(length + 1.0, *parts)
    # Seamless loop: fold the tail back onto the head.
    n = int(SR * length)
    tail = y[n:]
    y = y[:n]
    y[: len(tail)] += tail
    save('music_loop', lowpass(y, 9000), quality=3)


if __name__ == '__main__':
    sfx()
    music()
