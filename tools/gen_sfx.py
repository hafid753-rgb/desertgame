#!/usr/bin/env python3
"""Generate Hafid's placeholder sound effects procedurally (original, CC0-able).

Usage: python3 tools/gen_sfx.py   -> writes game/audio/*.wav (22.05 kHz, mono, 16-bit)
Each jinn attack has its own sound so it can be read by ear, not only by eye colour.
"""
import os
import wave

import numpy as np

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "game", "audio")
rng = np.random.default_rng(7)


def t(sec):
    return np.linspace(0, sec, int(SR * sec), endpoint=False)


def env(n, attack=0.005, release=0.2, sec=None):
    x = np.ones(n)
    a = max(1, int(attack * SR))
    r = max(1, int(release * SR))
    x[:a] = np.linspace(0, 1, a)
    x[-r:] *= np.linspace(1, 0, r) ** 2
    return x


def lowpass(x, alpha):
    y = np.zeros_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += alpha * (v - acc)
        y[i] = acc
    return y


def noise(sec):
    return rng.uniform(-1, 1, int(SR * sec))


def sweep(f0, f1, sec):
    tt = t(sec)
    f = np.linspace(f0, f1, tt.size)
    return np.sin(2 * np.pi * np.cumsum(f) / SR)


def save(name, x, gain=0.8):
    x = np.asarray(x, dtype=np.float64)
    peak = np.max(np.abs(x)) or 1.0
    x = np.clip(x / peak * gain, -1, 1)
    data = (x * 32767).astype("<i2")
    os.makedirs(OUT, exist_ok=True)
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(data.tobytes())


def whoosh(sec, a0, a1):
    n = noise(sec)
    alphas = np.linspace(a0, a1, n.size)
    y = np.zeros_like(n)
    acc = 0.0
    for i, v in enumerate(n):
        acc += alphas[i] * (v - acc)
        y[i] = acc
    return y * np.sin(np.linspace(0, np.pi, n.size))


def main():
    save("swing", whoosh(0.16, 0.05, 0.35), 0.5)
    hit = sweep(180, 60, 0.18) * env(int(SR * 0.18), 0.001, 0.15) + lowpass(noise(0.18), 0.4) * env(int(SR * 0.18), 0.001, 0.17) * 0.6
    save("hit", hit, 0.9)
    tp = t(0.6)
    parry = sum(np.sin(2 * np.pi * f * tp) * np.exp(-tp * d) for f, d in [(1320, 7), (1980, 9), (2640, 12), (3520, 15)])
    save("parry", parry + lowpass(noise(0.6), 0.6) * np.exp(-tp * 60) * 0.8, 0.8)
    save("block", sweep(140, 90, 0.12) * env(int(SR * 0.12), 0.001, 0.1) + lowpass(noise(0.12), 0.2) * 0.5, 0.7)
    save("dodge", whoosh(0.22, 0.02, 0.12), 0.45)
    tq = t(0.5)
    save("perfect", np.sin(2 * np.pi * np.cumsum(np.linspace(600, 1500, tq.size)) / SR) * np.exp(-tq * 6), 0.6)
    save("hurt", sweep(300, 120, 0.22) * env(int(SR * 0.22), 0.002, 0.18) + lowpass(noise(0.22), 0.3) * 0.4, 0.8)
    for i, f in enumerate([520, 660, 880]):
        tt = t(0.12)
        save("tier%d" % (i + 1), np.sin(2 * np.pi * f * tt) * np.exp(-tt * 30), 0.5)
    tf = t(0.55)
    crackle = noise(0.55) * (rng.uniform(0, 1, tf.size) > 0.97) * 1.5
    save("fire", lowpass(noise(0.55), 0.25) * np.exp(-tf * 4) + crackle * np.exp(-tf * 5) + sweep(90, 50, 0.55) * np.exp(-tf * 6) * 0.6, 0.85)
    save("wind", whoosh(0.5, 0.01, 0.2), 0.6)
    save("jump", sweep(220, 380, 0.1) * env(int(SR * 0.1), 0.002, 0.08) * 0.6 + whoosh(0.1, 0.05, 0.1), 0.4)
    save("land", lowpass(noise(0.1), 0.1) * env(int(SR * 0.1), 0.001, 0.09), 0.5)
    save("glide", whoosh(0.7, 0.01, 0.06), 0.4)
    save("grab", lowpass(noise(0.07), 0.3) * env(int(SR * 0.07), 0.001, 0.06), 0.4)
    # Jinn telegraphs: three clearly different shapes.
    ts = t(0.6)
    save("tel_swipe", sweep(200, 420, 0.6) * np.minimum(1, ts * 3) * 0.7 + lowpass(noise(0.6), 0.05) * 0.4, 0.6)
    tl = t(0.9)
    save("tel_lunge", (np.sign(np.sin(2 * np.pi * 70 * tl)) * 0.3 + np.sin(2 * np.pi * 140 * tl)) * np.minimum(1, tl * 1.5) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tl)), 0.6)
    tb = t(1.2)
    save("tel_burst", sweep(60, 160, 1.2) * np.minimum(1, tb * 1.2) + lowpass(noise(1.2), 0.02) * tb, 0.65)
    tbn = t(1.2)
    save("banish", sweep(400, 1200, 1.2) * np.exp(-tbn * 2.5) * 0.5 + whoosh(1.2, 0.01, 0.1), 0.6)
    print("wrote", len(os.listdir(OUT)), "files to", os.path.abspath(OUT))


if __name__ == "__main__":
    main()
