#!/usr/bin/env python3
"""1.30: звуки пожарной машины.

Запуск: python3 tools/gen_sounds_130.py  (из корня проекта; нужны numpy, scipy и ffmpeg)
siren — короткий: сирена «вой» (плавный подъём и спад тона, ~3,5 с) с хрипом рупора и гулом мотора.
amb_hose — петля: шум струи из пожарного ствола — шипящий шум, плеск и бульканье.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sounds as g  # noqa: E402
from gen_sounds import SR, secs, loop_noise, band, lfo, lowpass, highpass, clicks, fade, save  # noqa: E402

rng = np.random.default_rng(1300)
g.rng = rng


def siren():
    n = secs(3.6)
    t = np.arange(n) / SR
    # вой: два цикла подъёма-спада 600 → 1350 Гц
    f = 600.0 + 750.0 * (0.5 - 0.5 * np.cos(2 * np.pi * t / 1.8))
    ph = 2 * np.pi * np.cumsum(f) / SR
    x = np.sin(ph) + 0.45 * np.sin(2 * ph) + 0.22 * np.sin(3 * ph) + 0.1 * np.sign(np.sin(ph))
    x = lowpass(x, 3800) * 0.8
    motor = lowpass(loop_noise(n, band(60, 240)), 300) * 0.25
    out = fade(x + motor, 0.25, 0.6)
    save("siren", out, 0.75)


def hose():
    n = secs(3.0)
    hiss = highpass(loop_noise(n, band(1500, 7000, 0.4)), 1200) * 0.55
    rush = loop_noise(n, band(250, 1500)) * 0.45 * lfo(0.66, n, 0.25, 0.75)
    splash = clicks(n, 22, 0.012, 900.0) * 0.25 + clicks(n, 10, 0.03, 420.0) * 0.2
    save("amb_hose", hiss + rush + splash, 0.6)


if __name__ == "__main__":
    siren()
    hose()
    print("1.30: siren, amb_hose")
