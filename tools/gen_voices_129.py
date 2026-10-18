#!/usr/bin/env python3
"""1.29: голоса — неразборчивый «бубнёж» людей (формантный синтез, без записей).

Запуск: python3 tools/gen_voices_129.py  (из корня проекта; нужны numpy, scipy и ffmpeg)
Голосовой источник — последовательность импульсов с «живой» высотой тона (дрожание, ударения,
повествовательная интонация падает, вопросительная поднимается); через три резонатора-форманты
со сменой гласных по слогам (а о у э и ы), слоги 4–6 в секунду, между ними шипящие и взрывные шумы.
Всё приглушено (как через шум цеха) и слегка озвучено эхом комнаты, чтобы слов было не разобрать.
v_talk_m*/f* — спокойный разговор, v_talk_mo*/fo* — пожилые, хрипловатые; v_argue_* — ругань
(громче, быстрее, выше); v_laugh_* — смех «ха-ха»; v_crowd — бесшовная петля гомона многих людей.
"""
import os
import sys

import numpy as np
from scipy.signal import lfilter, fftconvolve

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sounds as g  # noqa: E402
from gen_sounds import SR, secs, lowpass, highpass, fade, save  # noqa: E402

rng = np.random.default_rng(1290)
g.rng = rng

# форманты мужского голоса (F1, F2, F3), Гц
VOWELS = {
    "а": (700, 1220, 2500), "о": (520, 860, 2450), "у": (330, 720, 2300),
    "э": (520, 1720, 2480), "и": (290, 2200, 2900), "ы": (340, 1500, 2350),
}
VKEYS = list(VOWELS.keys())
BW = (90.0, 120.0, 170.0)   # ширина формант
BLOCK = 110                 # шаг смены коэффициентов фильтра (5 мс)


def smooth(x, ms):
    """Сгладить огибающую скользящим средним (без щелчков)."""
    k = max(1, int(ms * SR / 1000))
    w = np.hanning(k + 2)[1:-1]
    return np.convolve(x, w / w.sum(), mode="same")


def resonate(src, ftrack, bws):
    """Каскад резонаторов с меняющимися частотами: ftrack[k] — (n,) частота k-й форманты."""
    y = src
    n = len(src)
    for k in range(ftrack.shape[0]):
        out = np.zeros(n)
        zi = np.zeros(2)
        for s in range(0, n, BLOCK):
            e = min(n, s + BLOCK)
            f = float(np.mean(ftrack[k, s:e]))
            r = np.exp(-np.pi * bws[k] / SR)
            c = 2 * r * np.cos(2 * np.pi * f / SR)
            a = [1.0, -c, r * r]
            b = [1.0 - c + r * r]          # единичное усиление на нуле частот
            out[s:e], zi = lfilter(b, a, y[s:e], zi=zi)
        y = out
    return y


def glottal(f0):
    """Источник: производная импульса Розенберга по накопленной фазе."""
    ph = np.cumsum(f0 / SR)
    p = ph - np.floor(ph)
    op, cl = 0.42, 0.16          # открытие плавное, смыкание резкое — отсюда «звонкость» голоса
    pulse = np.where(p < op, 0.5 * (1 - np.cos(np.pi * p / op)),
                     np.where(p < op + cl, np.cos(0.5 * np.pi * (p - op) / cl), 0.0))
    d = np.diff(pulse, prepend=pulse[0])
    return d / (np.max(np.abs(d)) + 1e-9), p


def plan(dur, rate, rasp=0.0):
    """Раскладка фразы на слоги: список (начало, длина, гласная, ударение, согласный перед ней)."""
    syl = []
    t = rng.uniform(0.04, 0.12)
    word_left = rng.integers(1, 5)
    while t < dur - 0.25:
        ln = rng.uniform(0.75, 1.3) / rate
        cons = rng.choice(["", "s", "sh", "p", "t", "k", "m", "n", "r", "v"], p=[.18, .1, .06, .09, .12, .08, .1, .11, .08, .08])
        syl.append((t, ln, VKEYS[rng.integers(0, len(VKEYS))], rng.uniform() < 0.3, cons))
        t += ln
        word_left -= 1
        if word_left <= 0:
            word_left = rng.integers(1, 5)
            t += rng.uniform(0.03, 0.14) if rng.uniform() < 0.8 else rng.uniform(0.25, 0.45)
    return syl


def phrase(dur, f0, fem=False, rate=5.0, rasp=0.0, question=None, energy=1.0, rangek=1.0):
    """Одна фраза «бубнежа». Возвращает сухой сигнал длины dur."""
    n = secs(dur)
    tt = np.arange(n) / SR
    syl = plan(dur, rate, rasp)
    if question is None:
        question = rng.uniform() < 0.3
    fs = 1.17 if fem else 1.0
    # --- высота тона: склонение, ударения, вопрос в конце, дрожание
    last = syl[-1][0] + syl[-1][1] if syl else dur
    rel = np.clip(tt / max(0.3, last), 0, 1)
    contour = 1.0 + 0.12 * rangek - 0.24 * rangek * rel     # повествование: вниз
    if question:
        contour += 0.45 * rangek * np.clip((rel - 0.8) / 0.2, 0, 1) ** 1.5
    acc = np.zeros(n)
    for (s0, ln, _v, stress, _c) in syl:
        if stress:
            c = s0 + ln * 0.4
            acc += 0.13 * rangek * np.exp(-((tt - c) / (ln * 0.45)) ** 2)
    drift = smooth(rng.standard_normal(n), 120) * 0.9
    jit = smooth(rng.standard_normal(n), 3) * (0.25 + rasp * 1.6)
    f0t = f0 * (contour + acc) * (1 + 0.04 * drift + 0.012 * jit)
    src, gph = glottal(f0t)
    # --- огибающая голоса и шумов, форманты
    venv = np.zeros(n)
    nenv = np.zeros(n)
    nband = np.zeros(n)
    ftr = np.zeros((3, n))
    targets = []
    for (s0, ln, v, stress, cons) in syl:
        a = int(s0 * SR)
        m = int(ln * SR)
        e = min(n, a + m)
        if e - a < 40:
            continue
        loc = np.arange(e - a) / (e - a)
        cl = 0.22 if cons else 0.08          # доля слога на согласный
        on = np.clip((loc - cl) / 0.18, 0, 1)
        off = np.clip((1 - loc) / 0.3, 0, 1)
        lvl = (1.25 if stress else 1.0) * rng.uniform(0.8, 1.05)
        venv[a:e] = np.maximum(venv[a:e], lvl * np.sin(0.5 * np.pi * on) * np.sin(0.5 * np.pi * off))
        if cons in ("m", "n", "v", "r"):    # звонкие согласные — тихий голос под гласной
            venv[a:e] = np.maximum(venv[a:e], 0.35 * lvl * np.clip(loc / 0.05, 0, 1) * (loc < cl + 0.1))
        if cons in ("s", "sh", "p", "t", "k"):
            if cons in ("s", "sh"):
                w = np.sin(np.pi * np.clip(loc / cl, 0, 1)) * (loc < cl)
                nenv[a:e] = np.maximum(nenv[a:e], (0.35 if cons == "s" else 0.3) * w)
                nband[a:e] = 1.0 if cons == "s" else 0.5
            else:
                bp = cl * 0.75
                w = np.exp(-np.clip(loc - bp, 0, None) * ln / 0.012) * (loc >= bp) * (loc < cl + 0.08)
                nenv[a:e] = np.maximum(nenv[a:e], 0.45 * w)
                nband[a:e] = {"p": 0.0, "t": 0.8, "k": 0.3}[cons]
        fv = np.array(VOWELS[v]) * fs * rng.uniform(0.95, 1.05, 3)
        targets.append((a, e, fv, cl))
    # дорожки формант: от гласной к гласной с плавными переходами, у согласных — «локус» пониже
    base = np.array(VOWELS["ы"]) * fs
    for k in range(3):
        ftr[k, :] = base[k]
    prev = base
    for (a, e, fv, cl) in targets:
        loc = np.arange(e - a) / (e - a)
        mid = 0.7 * prev + 0.3 * fv * np.array([0.7, 1.0, 1.0])
        w = np.clip((loc - cl * 0.5) / 0.35, 0, 1)
        w = w * w * (3 - 2 * w)
        for k in range(3):
            ftr[k, a:e] = mid[k] + (fv[k] - mid[k]) * w
        ftr[:, e:] = fv[:, None]
        prev = fv
    for k in range(3):
        ftr[k] = smooth(ftr[k], 25)
    venv = smooth(venv, 18) * energy
    nenv = smooth(nenv, 6) * energy
    # голос: импульсы + придыхание (у пожилых сильнее), через форманты
    breath = rng.standard_normal(n) * (0.08 + 0.5 * rasp) * (0.6 + 0.4 * np.cos(2 * np.pi * gph))
    exc = (src + breath) * venv
    if rasp > 0:   # хрипотца: неровная амплитуда от периода к периоду
        exc *= 1.0 + rasp * 0.6 * smooth(rng.standard_normal(n), 4)
    voiced = resonate(exc, ftr, BW)
    voiced = lfilter([1.0, -0.94], [1.0], voiced)          # предыскажение: верх формант не тонет в основном тоне
    voiced = voiced + 0.05 * lowpass(exc, 700)            # немного «грудного» гула
    # согласные: полосовой шум (с — выше, ш — ниже, взрывные — короткие широкие)
    nz = rng.standard_normal(n)
    hi = highpass(lowpass(nz, 4200), 2400)
    mid = highpass(lowpass(nz, 2600), 1300)
    lo = lowpass(nz, 1200)
    noise = (hi * np.clip(nband, 0, 1) + mid * np.clip(1 - abs(nband - 0.5) * 2, 0, 1) + lo * np.clip(1 - nband * 2, 0, 1)) * nenv
    sv = np.std(voiced[venv > 0.2]) if np.any(venv > 0.2) else 1.0
    sn = np.std(noise[nenv > 0.1]) if np.any(nenv > 0.1) else 1.0
    x = voiced / (sv + 1e-9) + 0.55 * noise / (sn + 1e-9)
    return x


def muffle(x, cut=2600.0):
    """Приглушить: убрать гул ниже 120 Гц и верх выше cut — слов не разобрать."""
    return lowpass(highpass(x, 120), cut)


def room(x, wet=0.16, rt=0.32, circular=False):
    """Лёгкое эхо комнаты: свёртка с затухающим шумом."""
    m = secs(rt)
    ir = rng.standard_normal(m) * np.exp(-np.arange(m) / (rt * SR / 6.9))
    ir = lowpass(ir, 2200)
    ir[: secs(0.012)] = 0
    ir /= np.sqrt(np.sum(ir ** 2)) + 1e-9
    if circular:
        n = len(x)
        h = np.zeros(n)
        h[:m] = ir
        rev = np.fft.irfft(np.fft.rfft(x) * np.fft.rfft(h), n)
    else:
        rev = fftconvolve(x, ir)[: len(x)]
    return x + wet * rev * (np.std(x) / (np.std(rev) + 1e-9))


def finish(x, cut=2600.0, wet=0.16):
    y = room(muffle(x, cut), wet)
    return fade(y, 0.03, 0.12)


def talk(name, dur, f0, fem=False, rate=5.0, rasp=0.0, phrases=2, cut=2600.0):
    """Реплика из одной-двух фраз с паузой между ними."""
    parts = []
    left = dur
    for i in range(phrases):
        d = left / (phrases - i) * rng.uniform(0.85, 1.1) if i < phrases - 1 else left
        d = max(0.7, d)
        parts.append(phrase(d, f0 * rng.uniform(0.96, 1.04), fem, rate * rng.uniform(0.9, 1.1), rasp,
                            question=(rng.uniform() < 0.45) if i == phrases - 1 else False))
        left -= d
        if i < phrases - 1:
            gap = rng.uniform(0.15, 0.3)
            parts.append(np.zeros(secs(gap)))
            left -= gap
    x = np.concatenate(parts)
    save(name, finish(x, cut), 0.8)
    return x


def argue(name, dur, f0, fem=False):
    """Ругань: выше, быстрее, громче, размах интонации больше, резкие ударения."""
    parts = []
    left = dur
    while left > 0.6:
        d = min(left, rng.uniform(0.9, 1.5))
        parts.append(phrase(d, f0 * rng.uniform(1.25, 1.45), fem, rng.uniform(6.0, 7.0), 0.05,
                            question=rng.uniform() < 0.35, energy=1.0, rangek=1.8))
        left -= d
        gp = rng.uniform(0.06, 0.15)
        parts.append(np.zeros(secs(gp)))
        left -= gp
    x = np.concatenate(parts)
    x = np.tanh(1.6 * x / (np.max(np.abs(x)) + 1e-9))     # голос «на крике» — чуть жёстче
    save(name, finish(x, 3000.0, 0.2), 0.92)


def laugh(name, f0, fem=False, bursts=6):
    """Смех: «ха» — выдох-шум и короткая «а», высота и громкость спадают."""
    rate = rng.uniform(4.6, 5.6)
    n = secs(bursts / rate + 0.9)
    tt = np.arange(n) / SR
    f0t = np.full(n, f0)
    venv = np.zeros(n)
    henv = np.zeros(n)
    t = 0.05
    for i in range(bursts):
        ln = 1.0 / rate * rng.uniform(0.85, 1.15)
        a = int(t * SR)
        e = min(n, a + int(ln * SR))
        loc = np.arange(e - a) / (e - a)
        k = (1.0 - 0.5 * i / bursts) * rng.uniform(0.85, 1.05)
        henv[a:e] = np.maximum(henv[a:e], 0.7 * k * np.sin(np.pi * np.clip(loc / 0.3, 0, 1)) * (loc < 0.3))
        on = np.clip((loc - 0.18) / 0.12, 0, 1)
        off = np.clip((0.85 - loc) / 0.25, 0, 1)
        venv[a:e] = np.maximum(venv[a:e], k * np.sin(0.5 * np.pi * on) * np.sin(0.5 * np.pi * off) * (loc < 0.85))
        f0t[a:e] = f0 * (1.35 - 0.35 * i / bursts) * (1.08 - 0.12 * loc)
        t += ln
        if i == bursts // 2 and rng.uniform() < 0.5:
            t += rng.uniform(0.15, 0.25)          # вдох посреди смеха
    f0t = smooth(f0t, 15) * (1 + 0.01 * smooth(rng.standard_normal(n), 3))
    src, gph = glottal(f0t)
    venv = smooth(venv, 10)
    henv = smooth(henv, 8)
    fs = 1.17 if fem else 1.0
    fa = np.array(VOWELS["а"]) * fs
    ftr = np.vstack([np.full(n, fa[0]), np.full(n, fa[1]), np.full(n, fa[2])])
    breath = rng.standard_normal(n)
    exc = src * venv + 0.12 * breath * venv + breath * henv * 0.9
    y = lfilter([1.0, -0.94], [1.0], resonate(exc, ftr, (140.0, 170.0, 220.0))) + 0.05 * lowpass(src * venv, 700)
    save(name, finish(y, 2900.0, 0.2), 0.8)


def crowd(name, dur=6.0, voices=11):
    """Гомон: много голосов внахлёст, приглушённо; бесшовная петля (всё кладётся по кругу)."""
    n = secs(dur)
    buf = np.zeros(n)
    for i in range(voices):
        fem = i % 3 == 1
        f0 = rng.uniform(180, 240) if fem else rng.uniform(95, 140)
        pos = rng.integers(0, n)
        total = 0
        while total < n * rng.uniform(0.6, 0.85):
            d = rng.uniform(1.0, 2.2)
            x = phrase(d, f0, fem, rng.uniform(4.2, 5.8), 0.1 if i % 4 == 3 else 0.0)
            x = x / (np.std(x) + 1e-9) * rng.uniform(0.5, 1.0) * (0.6 if i > 6 else 1.0)
            idx = (pos + total + np.arange(len(x))) % n
            buf[idx] += fade(x, 0.02, 0.05)
            total += len(x) + secs(rng.uniform(0.3, 1.2))
    # приглушить по кругу (частотная область — тоже бесшовно), эхо по кругу
    f = np.fft.rfftfreq(n, 1 / SR)
    X = np.fft.rfft(buf)
    X *= 1.0 / np.sqrt(1.0 + (f / 1900.0) ** 4) * (f / np.sqrt(f ** 2 + 110.0 ** 2))
    y = np.fft.irfft(X, n)
    y = room(y, 0.35, 0.45, circular=True)
    save(name, y, 0.7)


def main():
    # спокойный разговор: четыре мужских, четыре женских голоса, двое пожилых
    talk("v_talk_m1", 2.4, 110, rate=4.8)
    talk("v_talk_m2", 3.2, 125, rate=5.2, phrases=2)
    talk("v_talk_m3", 1.8, 98, rate=4.4, phrases=1)
    talk("v_talk_m4", 3.6, 135, rate=5.6, phrases=2)
    talk("v_talk_f1", 2.2, 205, fem=True, rate=5.2, phrases=1)
    talk("v_talk_f2", 3.0, 225, fem=True, rate=5.6, phrases=2)
    talk("v_talk_f3", 2.6, 188, fem=True, rate=4.8, phrases=2)
    talk("v_talk_f4", 1.7, 240, fem=True, rate=5.8, phrases=1)
    talk("v_talk_mo1", 3.0, 92, rate=4.2, rasp=0.35, phrases=2, cut=2300.0)
    talk("v_talk_fo1", 2.6, 172, fem=True, rate=4.4, rasp=0.3, phrases=2, cut=2400.0)
    # ругань
    argue("v_argue_m1", 2.6, 120)
    argue("v_argue_m2", 3.2, 105)
    argue("v_argue_f1", 2.4, 210, fem=True)
    # смех
    laugh("v_laugh_m1", 120, bursts=6)
    laugh("v_laugh_f1", 220, fem=True, bursts=7)
    # гомон
    crowd("v_crowd")


if __name__ == "__main__":
    main()
