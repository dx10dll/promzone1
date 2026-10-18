#!/usr/bin/env python3
"""1.27: звуки литья и штамповки.

Запуск: python3 tools/gen_sounds_127.py  (из корня проекта; нужны numpy, scipy и ffmpeg)
m_casting — петля: гул индукционной печи (высокий тон и 50 Гц), бульканье расплава, шипение опок.
m_stamp — петля: удары пресса раз в ~0,9 с — стук ползуна, звон штампа, щелчок муфты.
pour — короткий: металл льётся в опоку, шипит и потрескивает.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sounds as g  # noqa: E402
from gen_sounds import SR, secs, loop_noise, band, tone, lfo, harmonics, env_decay, lowpass, highpass, clicks, fade, save, bell  # noqa: E402

rng = np.random.default_rng(1270)
g.rng = rng


def put(buf, x, pos, circular=True):
    n = len(buf)
    idx = (pos + np.arange(len(x)))
    if circular:
        buf[idx % n] += x
    else:
        idx = idx[idx < n]
        buf[idx] += x[:len(idx)]


def bubbles(n, rate):
    """Бульканье: короткие тоны с падающей частотой в случайные моменты."""
    x = np.zeros(n)
    for _ in range(int(rate * n / SR)):
        k = secs(rng.uniform(0.03, 0.08))
        f0 = rng.uniform(180, 420)
        t = np.arange(k) / SR
        f = f0 * (1.0 - 0.5 * t / t[-1])
        b = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t / 0.025)
        put(x, b * rng.uniform(0.3, 1.0), rng.integers(0, n))
    return x


def casting():
    n = secs(3.0)
    hum = 0.22 * tone(1000, n) * lfo(0.5, n, 0.2, 0.8) + 0.3 * harmonics(50, n, [0.6, 0.4, 0.25, 0.15])
    roar = lowpass(loop_noise(n, lambda f: 1 / f), 500) * 0.5
    hiss = 0.18 * loop_noise(n, band(2500, 7000)) * lfo(0.33, n, 0.6, 0.4)
    save("m_casting", hum + roar + hiss + 0.35 * bubbles(n, 9), 0.7)


def stamp():
    n = secs(2.7)   # три удара по 0,9 с — петля без шва
    x = 0.04 * loop_noise(n, band(150, 1200)) + 0.12 * harmonics(50, n, [0.5, 0.3])
    for k in range(3):
        p = secs(0.9 * k + 0.1)
        m = secs(0.5)
        t = np.arange(m) / SR
        thud = lowpass(rng.standard_normal(m), 260) * np.exp(-t / 0.06) * 2.2
        ring = bell(rng.uniform(1650, 1900), 0.5, ((1, 1.0), (2.76, 0.45), (5.4, 0.2)), tau=0.09)[:m] * 0.35
        clack = highpass(rng.standard_normal(m), 3000) * np.exp(-t / 0.008) * 0.6
        put(x, thud + ring + clack, p)
        put(x, highpass(rng.standard_normal(secs(0.03)), 1500) * 0.25, p - secs(0.25))   # щелчок муфты перед ударом
    save("m_stamp", x, 0.8)


def pour():
    n = secs(1.6)
    t = np.arange(n) / SR
    env = np.minimum(1.0, t / 0.08) * np.exp(-np.maximum(0.0, t - 0.9) / 0.25)
    sizzle = loop_noise(n, band(2000, 9000)) * env * 0.6
    crackle = clicks(n, 70, 0.003, 2600, circular=False, amp_var=0.9) * env * 0.5
    low = lowpass(rng.standard_normal(n), 300) * env * 0.4
    save("pour", fade(sizzle + crackle + low, 0.01, 0.2), 0.75)


if __name__ == "__main__":
    casting()
    stamp()
    pour()
    print("ok")
