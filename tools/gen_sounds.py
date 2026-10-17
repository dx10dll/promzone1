#!/usr/bin/env python3
"""Генератор звуков и музыки «Промзоны» (всё синтезируется, без сторонних записей).

Запуск: python3 tools/gen_sounds.py  (из корня проекта; нужны numpy и ffmpeg)
Создаёт assets/sound/*.ogg: циклы станков и фона, короткие эффекты интерфейса и событий, две мелодии.
Циклы бесшовные: шум строится в частотной области, у тонов целое число периодов на длину цикла.
"""
import math
import os
import subprocess
import tempfile

import numpy as np
from scipy.io import wavfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sound")
SR = 22050
rng = np.random.default_rng(1977)


# ------------------------------------------------------------------ примитивы

def secs(n):
    return int(n * SR)


def t_axis(n):
    return np.arange(n) / SR


def loop_noise(n, shape):
    """Бесшовный шум с заданной АЧХ: shape(freq) -> амплитуда."""
    f = np.fft.rfftfreq(n, 1 / SR)
    amp = shape(np.maximum(f, 1.0))
    ph = rng.uniform(0, 2 * np.pi, len(f))
    x = np.fft.irfft(amp * np.exp(1j * ph), n)
    return x / (np.max(np.abs(x)) + 1e-9)


def band(lo, hi, slope=1.0):
    def s(f):
        a = np.where((f >= lo) & (f <= hi), 1.0, 0.0)
        a += np.where(f < lo, np.exp(-(lo - f) / (lo * 0.3 + 1)), 0) + np.where(f > hi, np.exp(-(f - hi) / (hi * 0.3 + 1)), 0)
        return a / np.power(f, slope * 0.5)
    return s


def tone(freq, n, phase=0.0):
    """Синус с целым числом периодов на длину n (для бесшовных циклов)."""
    k = max(1, round(freq * n / SR))
    return np.sin(2 * np.pi * k * np.arange(n) / n + phase)


def lfo(rate, n, depth=1.0, base=0.0):
    k = max(1, round(rate * n / SR))
    return base + depth * (0.5 + 0.5 * np.sin(2 * np.pi * k * np.arange(n) / n))


def harmonics(f0, n, amps):
    x = np.zeros(n)
    for i, a in enumerate(amps):
        x += a * tone(f0 * (i + 1), n, rng.uniform(0, 6.28))
    return x


def env_decay(n, tau):
    return np.exp(-np.arange(n) / (tau * SR))


def lowpass(x, cutoff):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X = np.fft.rfft(x)
    X *= 1.0 / np.sqrt(1.0 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def highpass(x, cutoff):
    f = np.fft.rfftfreq(len(x), 1 / SR)
    X = np.fft.rfft(x)
    X *= 1.0 - 1.0 / np.sqrt(1.0 + (f / cutoff) ** 4)
    return np.fft.irfft(X, len(x))


def clicks(n, rate, decay, freq=2000.0, circular=True, amp_var=0.6):
    """Случайные щелчки/удары с затуханием (для треска сварки, огня, храповика)."""
    x = np.zeros(n)
    count = int(rate * n / SR)
    k = int(decay * SR * 6)
    tail = env_decay(k, decay) * np.sin(2 * np.pi * freq * np.arange(k) / SR + rng.uniform(0, 6.28))
    for _ in range(count):
        p = rng.integers(0, n)
        a = 1.0 - amp_var * rng.random()
        idx = (p + np.arange(k)) % n if circular else np.clip(p + np.arange(k), 0, n - 1)
        x[idx] += a * tail
    return x


def norm(x, peak=0.9):
    return x * (peak / (np.max(np.abs(x)) + 1e-9))


def fade(x, a=0.01, b=0.05):
    n = len(x)
    ia = max(1, int(a * SR))
    ib = max(1, int(b * SR))
    x = x.copy()
    x[:ia] *= np.linspace(0, 1, ia)
    x[-ib:] *= np.linspace(1, 0, ib)
    return x


def save(name, x, peak=0.9, sr=SR, q=3):
    os.makedirs(OUT, exist_ok=True)
    x = norm(np.asarray(x, dtype=np.float64), peak)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wavfile.write(tf.name, sr, (x * 32767).astype(np.int16))
        tmp = tf.name
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), out], check=True)
    os.unlink(tmp)


# ------------------------------------------------------------------ станки (циклы ~2–3 с)

def machines():
    n = secs(2.4)
    # токарный: гул двигателя 50 Гц, шпиндель, шорох резца с биением
    hum = harmonics(50, n, [0.6, 0.35, 0.2, 0.12, 0.08])
    spindle = 0.25 * tone(266, n) * lfo(4, n, 0.3, 0.7)
    cut = loop_noise(n, band(1800, 5000)) * lfo(3, n, 0.6, 0.4) * 0.35
    save("m_lathe", hum + spindle + cut, 0.7)
    # фрезерный: вой и удары зубьев
    whine = 0.3 * tone(420, n) + 0.15 * tone(840, n)
    teeth = clicks(n, 14, 0.012, 900) * 0.6
    save("m_mill", harmonics(50, n, [0.5, 0.3, 0.15]) + whine + teeth + 0.2 * loop_noise(n, band(1500, 4500)), 0.7)
    # сверлильный: высокий вой
    save("m_drill", 0.4 * tone(310, n) + 0.2 * tone(620, n) * lfo(2, n, 0.5, 0.5) + 0.25 * loop_noise(n, band(2500, 6000)) + harmonics(50, n, [0.3, 0.2]), 0.6)
    # сварка: треск и гудение 100 Гц
    save("m_weld", 0.25 * harmonics(100, n, [0.6, 0.4, 0.25, 0.1]) + clicks(n, 220, 0.004, 3200, amp_var=0.9) + 0.3 * loop_noise(n, band(2000, 8000)) * lfo(7, n, 0.6, 0.4), 0.75)
    # печь: низкий рёв горелки и вентилятор
    roar = lowpass(loop_noise(n, lambda f: 1 / f), 400) * lfo(0.8, n, 0.3, 0.7)
    save("m_furnace", roar + 0.2 * harmonics(25, n, [0.5, 0.4, 0.3, 0.2]) + 0.1 * loop_noise(n, band(600, 1500)), 0.7)
    # покраска: шипение краскопульта, компрессор
    save("m_paint", 0.6 * loop_noise(n, band(3000, 9000, 0.3)) * lfo(0.8, n, 0.4, 0.6) + 0.25 * harmonics(30, n, [0.6, 0.4, 0.2]), 0.6)
    # сборка: гайковёрт очередями
    burst = np.zeros(n)
    for start in (0.2, 1.3):
        s0 = secs(start)
        k = secs(0.45)
        seg = clicks(k, 60, 0.01, 1400, circular=False) + 0.4 * np.sin(2 * np.pi * 180 * np.arange(k) / SR)
        burst[s0:s0 + k] += seg * np.hanning(k)
    save("m_assembly", burst + 0.05 * loop_noise(n, band(200, 2000)), 0.6)
    # испытательный стенд: гидронасос и шипение давления
    save("m_test", 0.35 * harmonics(48, n, [0.6, 0.5, 0.3, 0.2]) + 0.3 * tone(196, n) * lfo(1, n, 0.4, 0.6) + 0.25 * loop_noise(n, band(1200, 3500)) * lfo(0.4, n, 0.8, 0.2), 0.6)
    # ЧПУ: плавный вой сервоприводов и СОЖ
    save("m_cnc", 0.3 * tone(520, n) * lfo(0.6, n, 0.5, 0.5) + 0.2 * tone(1040, n) + 0.35 * loop_noise(n, band(800, 2500)) + harmonics(50, n, [0.25, 0.15]), 0.6)


# ------------------------------------------------------------------ фон

def ambience():
    n = secs(8.0)
    # день: далёкий гул трассы, редкие птицы
    traffic = lowpass(loop_noise(n, lambda f: 1 / f), 250) * lfo(0.25, n, 0.5, 0.5)
    birds = np.zeros(n)
    for _ in range(5):
        p = rng.integers(0, n - secs(0.4))
        k = secs(rng.uniform(0.08, 0.16))
        f0 = rng.uniform(2800, 4200)
        tt = np.arange(k) / SR
        chirp = np.sin(2 * np.pi * (f0 * tt + rng.uniform(-3000, 3000) * tt * tt)) * np.hanning(k)
        for r in range(rng.integers(1, 4)):
            q = p + r * secs(0.14)
            if q + k < n:
                birds[q:q + k] += chirp * 0.25
    save("amb_day", traffic + birds, 0.45)
    # ночь: тихий ветер и сверчки
    wind = lowpass(loop_noise(n, lambda f: 1 / f), 600) * lfo(0.15, n, 0.6, 0.4)
    cr = tone(4300, n) * (tone(30, n) > 0.6) * lfo(0.5, n, 0.8, 0.2) * 0.15
    save("amb_night", wind * 0.6 + cr, 0.35)
    # зимний ветер
    save("amb_wind", lowpass(loop_noise(n, band(150, 1200, 0.5)), 900) * lfo(0.2, n, 0.7, 0.3) + 0.3 * highpass(loop_noise(n, lambda f: 1 / f), 2500) * lfo(0.33, n, 0.8, 0.2), 0.5)
    # дождь
    save("amb_rain", 0.6 * loop_noise(n, band(1500, 9000, 0.2)) + clicks(n, 90, 0.006, 5000) * 0.35, 0.5)
    # огонь
    save("amb_fire", lowpass(loop_noise(n, lambda f: 1 / f), 300) + clicks(n, 40, 0.01, 2500) * 0.7, 0.6)
    # гул толпы (забастовка)
    crowd = np.zeros(n)
    for _ in range(14):
        f0 = rng.uniform(110, 240)
        crowd += loop_noise(n, band(f0 * 2, f0 * 6, 0.5)) * lfo(rng.uniform(0.5, 2.0), n, 1.0, 0.0)
    save("amb_crowd", lowpass(crowd, 1800), 0.4)


# ------------------------------------------------------------------ короткие эффекты

def bell(f, dur, partials=((1, 1.0), (2.0, 0.5), (3.01, 0.25), (4.2, 0.15)), tau=0.25):
    n = secs(dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for r, a in partials:
        x += a * np.sin(2 * np.pi * f * r * tt) * np.exp(-tt / (tau / r ** 0.5))
    return x


def oneshots():
    # интерфейс
    k = secs(0.05)
    save("ui_click", fade(np.sin(2 * np.pi * 1600 * np.arange(k) / SR) * env_decay(k, 0.008) + 0.3 * rng.standard_normal(k) * env_decay(k, 0.003), 0.001, 0.01), 0.5)
    k = secs(0.18)
    sweep = np.sin(2 * np.pi * np.cumsum(np.linspace(300, 900, k)) / SR) * np.hanning(k)
    save("ui_open", sweep * 0.5 + 0.2 * highpass(rng.standard_normal(k), 3000) * np.hanning(k), 0.35)
    sweep2 = np.sin(2 * np.pi * np.cumsum(np.linspace(800, 350, k)) / SR) * np.hanning(k)
    save("ui_close", sweep2 * 0.5, 0.3)
    # уведомления
    save("n_info", fade(bell(1320, 0.5, tau=0.18)), 0.45)
    good = np.concatenate([bell(988, 0.14, tau=0.12)[:secs(0.12)], bell(1318, 0.5, tau=0.2)])
    save("n_good", fade(good), 0.5)
    warn = np.concatenate([bell(880, 0.16, tau=0.12)[:secs(0.15)], bell(698, 0.45, tau=0.18)])
    save("n_warn", fade(warn), 0.5)
    k = secs(0.6)
    tt = np.arange(k) / SR
    buzz = np.sign(np.sin(2 * np.pi * 330 * tt)) * 0.4 + np.sin(2 * np.pi * 440 * tt) * 0.4
    buzz *= (np.sin(2 * np.pi * 6 * tt) > -0.2) * np.hanning(k)
    save("n_bad", lowpass(buzz, 2500), 0.5)
    # касса: звон и щелчок
    cash = bell(2093, 0.7, tau=0.3) + 0.6 * bell(2637, 0.7, tau=0.25)
    cash[:secs(0.03)] += rng.standard_normal(secs(0.03)) * 0.5
    save("cash", fade(cash), 0.55)
    # письмо: шелест бумаги + колокольчик
    k = secs(0.35)
    rustle = highpass(rng.standard_normal(k), 2500) * np.hanning(k) * 0.5
    save("letter", np.concatenate([rustle, bell(1568, 0.6, tau=0.2)]), 0.5)
    # стройка: удары молотка
    hit = np.zeros(secs(0.3))
    kk = secs(0.25)
    hit[:kk] = (np.sin(2 * np.pi * 220 * np.arange(kk) / SR) * 0.6 + rng.standard_normal(kk) * 0.5) * env_decay(kk, 0.03)
    save("hammer", lowpass(hit, 3500), 0.6)
    k = secs(0.4)
    thunk = np.sin(2 * np.pi * 90 * np.arange(k) / SR) * env_decay(k, 0.08) + lowpass(rng.standard_normal(k), 800) * env_decay(k, 0.05)
    save("place", thunk, 0.6)
    k = secs(0.9)
    crash = lowpass(rng.standard_normal(k), 2500) * env_decay(k, 0.25) + clicks(k, 30, 0.02, 1200, circular=False) * env_decay(k, 0.3)
    save("demolish", crash, 0.6)
    # автомат выбило: искра и щелчок
    k = secs(0.5)
    zap = highpass(rng.standard_normal(k), 3000) * env_decay(k, 0.06) + np.sin(2 * np.pi * 60 * np.arange(k) / SR) * env_decay(k, 0.15) * 0.5
    save("breaker", zap, 0.6)
    # поломка станка: лязг
    clang = bell(410, 1.0, ((1, 1.0), (2.76, 0.6), (5.4, 0.4), (8.9, 0.2)), tau=0.35)
    clang += lowpass(rng.standard_normal(len(clang)), 1500) * env_decay(len(clang), 0.1) * 0.6
    save("breakdown", clang, 0.6)
    # травма: глухой удар
    k = secs(0.4)
    save("injury", np.sin(2 * np.pi * 70 * np.arange(k) / SR) * env_decay(k, 0.07) + lowpass(rng.standard_normal(k), 600) * env_decay(k, 0.04), 0.6)
    # гудок фургона
    k = secs(0.9)
    tt = np.arange(k) / SR
    horn = (np.sign(np.sin(2 * np.pi * 415 * tt)) + np.sign(np.sin(2 * np.pi * 523 * tt))) * 0.3
    gate = ((tt > 0.0) & (tt < 0.25)) | ((tt > 0.4) & (tt < 0.75))
    save("van_horn", lowpass(horn * gate, 2200) * np.minimum(1, tt * 60), 0.45)
    # заводской гудок: начало и конец смены
    k = secs(2.6)
    tt = np.arange(k) / SR
    f = 196 * (1 + 0.01 * np.minimum(1, tt * 2))
    ph = 2 * np.pi * np.cumsum(f) / SR
    horn2 = sum(a * np.sin(ph * (i + 1)) for i, a in enumerate([1, 0.7, 0.5, 0.35, 0.2, 0.1]))
    envh = np.minimum(1, tt * 3) * np.minimum(1, (2.6 - tt) * 2)
    save("factory_horn", lowpass(horn2 * envh, 1400), 0.5)
    # новый этап: фанфара (арпеджио)
    notes = [523, 659, 784, 1047]
    fan = np.concatenate([bell(f, 0.22, tau=0.3)[:secs(0.16)] for f in notes[:-1]] + [bell(notes[-1], 1.2, tau=0.5)])
    save("fanfare", fade(fan), 0.55)
    # звонок у проходной (инспектор)
    save("doorbell", np.concatenate([bell(1046, 0.4, tau=0.3)[:secs(0.35)], bell(830, 0.9, tau=0.35)]), 0.5)
    # лай собаки
    k = secs(0.22)
    tt = np.arange(k) / SR
    bark = lowpass(np.sign(np.sin(2 * np.pi * 380 * tt * (1 - tt))) * 0.5 + rng.standard_normal(k) * 0.3, 1800) * np.hanning(k)
    save("bark", np.concatenate([bark, np.zeros(secs(0.12)), bark * 0.8]), 0.45)
    # огнетушитель
    k = secs(1.2)
    save("extinguish", highpass(rng.standard_normal(k), 1500) * np.minimum(1, np.arange(k) / (0.05 * SR)) * env_decay(k, 0.9), 0.5)


# ------------------------------------------------------------------ музыка

NOTE = {"C": -9, "C#": -8, "D": -7, "D#": -6, "E": -5, "F": -4, "F#": -3, "G": -2, "G#": -1, "A": 0, "A#": 1, "B": 2}


def hz(name, octave):
    return 440.0 * 2 ** ((NOTE[name] + 12 * (octave - 4)) / 12)


def accordion(f, dur, vol=1.0):
    """Баян/аккордеон: два «голоса» с расстройкой (мюзет), нечётные и чётные гармоники, мягкая атака."""
    n = secs(dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for det in (-0.0025, 0.0025):
        ff = f * (1 + det)
        for i, a in enumerate([1.0, 0.6, 0.45, 0.3, 0.22, 0.14, 0.1, 0.06]):
            x += a * np.sin(2 * np.pi * ff * (i + 1) * tt + i)
    env = np.minimum(1, tt / 0.04) * np.minimum(1, (dur - tt) / 0.08)
    return x * env * vol * (1 + 0.04 * np.sin(2 * np.pi * 5.2 * tt))


def piano(f, dur, vol=1.0):
    n = secs(dur)
    tt = np.arange(n) / SR
    x = np.zeros(n)
    for i, a in enumerate([1.0, 0.45, 0.25, 0.15, 0.08, 0.05]):
        x += a * np.sin(2 * np.pi * f * (i + 1) * (1 + 0.0004 * i * i) * tt) * np.exp(-tt * (1.6 + i * 0.9))
    x[:secs(0.006)] += rng.standard_normal(secs(0.006)) * 0.15
    return x * vol * np.minimum(1, (dur - tt) / 0.05)


def mix_at(buf, x, pos):
    p = int(pos * SR)
    if p >= len(buf):
        return
    m = min(len(x), len(buf) - p)
    buf[p:p + m] += x[:m]


def music_waltz():
    """«Заводской вальс»: ля минор, 3/4 — бас на раз, аккорд на два-три, мелодия баяна."""
    bpm = 88
    beat = 60 / bpm
    prog = [("A", "m"), ("A", "m"), ("D", "m"), ("D", "m"), ("G", ""), ("G", ""), ("C", ""), ("E", "7"),
            ("A", "m"), ("A", "m"), ("D", "m"), ("D", "m"), ("E", ""), ("E", "7"), ("A", "m"), ("A", "m")]
    chords = {"m": [0, 3, 7], "": [0, 4, 7], "7": [0, 4, 7, 10]}
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    mel = [("E", 5, 2), ("A", 4, 1), ("C", 5, 2), ("B", 4, 1), ("A", 4, 3), ("F", 5, 2), ("E", 5, 1), ("D", 5, 3), ("A", 4, 3),
           ("D", 5, 2), ("B", 4, 1), ("G", 4, 3), ("E", 5, 2), ("D", 5, 1), ("C", 5, 3), ("B", 4, 2), ("G#", 4, 1),
           ("E", 5, 2), ("A", 4, 1), ("C", 5, 2), ("E", 5, 1), ("A", 5, 3), ("F", 5, 2), ("E", 5, 1), ("D", 5, 3), ("F", 5, 3),
           ("E", 5, 2), ("D", 5, 1), ("B", 4, 2), ("G#", 4, 1), ("A", 4, 3), ("A", 4, 3)]
    total = len(prog) * 3 * beat * 2
    buf = np.zeros(secs(total) + secs(1.0))
    for rep in range(2):
        base = rep * len(prog) * 3 * beat
        for i, (root, kind) in enumerate(prog):
            t0 = base + i * 3 * beat
            ri = names.index(root)
            bass_f = hz(root, 2)
            mix_at(buf, accordion(bass_f, beat * 0.9, 0.5), t0)
            for b in (1, 2):
                for iv in chords[kind]:
                    nm = names[(ri + iv) % 12]
                    mix_at(buf, accordion(hz(nm, 3 if (ri + iv) % 12 > 4 else 4), beat * 0.6, 0.16), t0 + b * beat)
        t = base
        for (nm, octv, dur) in mel:
            mix_at(buf, accordion(hz(nm, octv), dur * beat * 0.95, 0.42 if rep == 0 else 0.36), t)
            t += dur * beat
    buf = lowpass(buf, 4200)
    # «хвост» в начало для бесшовного повтора
    tail = secs(1.0)
    buf[:tail] += buf[-tail:]
    buf = buf[:-tail]
    save("music_waltz", buf, 0.6, q=4)


def music_calm():
    """Спокойная тема для игры: фортепиано-арпеджио, 72 уд/мин, ля минор — до мажор."""
    bpm = 72
    beat = 60 / bpm
    prog = [("A", "m"), ("F", ""), ("C", ""), ("G", ""), ("A", "m"), ("F", ""), ("D", "m"), ("E", "")] * 2 + \
           [("F", ""), ("G", ""), ("E", "m"), ("A", "m"), ("D", "m"), ("G", ""), ("C", ""), ("E", "")]
    chords = {"m": [0, 3, 7], "": [0, 4, 7]}
    names = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    total = len(prog) * 4 * beat
    buf = np.zeros(secs(total) + secs(3.0))
    for i, (root, kind) in enumerate(prog):
        t0 = i * 4 * beat
        ri = names.index(root)
        mix_at(buf, piano(hz(root, 2), 4 * beat, 0.45), t0)
        arp = [0, 1, 2, 1, 2, 1, 0, 1]
        for k, a in enumerate(arp):
            iv = chords[kind][a]
            nm = names[(ri + iv) % 12]
            octv = 4 if (ri + iv) % 12 < 9 else 3
            mix_at(buf, piano(hz(nm, octv), 1.6, 0.22), t0 + k * beat / 2)
        if i % 2 == 0:
            top = names[(ri + chords[kind][2]) % 12]
            mix_at(buf, piano(hz(top, 5), 2.5, 0.2), t0 + beat * 2)
    tail = secs(3.0)
    buf[:tail] += buf[-tail:]
    buf = buf[:-tail]
    save("music_calm", lowpass(buf, 5000), 0.55, q=4)


def main():
    machines()
    ambience()
    oneshots()
    music_waltz()
    music_calm()
    files = sorted(os.listdir(OUT))
    size = sum(os.path.getsize(os.path.join(OUT, f)) for f in files)
    print("Готово: %d файлов, %.1f КБ" % (len(files), size / 1024))


if __name__ == "__main__":
    main()
