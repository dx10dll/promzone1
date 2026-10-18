#!/usr/bin/env python3
"""1.28 «Музыка»: шесть синтезированных композиций для «Промзоны».

Запуск: python3 tools/gen_music_128.py  (из корня проекта; нужны numpy, scipy и ffmpeg)
Всё синтезируется: щипковая гитара (Карплус — Стронг), фортепиано с расстроенными обертонами,
баян, медь (пила с фильтром по огибающей), флейта с дыханием, струнные пэды, бас, ударные.
Стерео, панорама, общий ревербератор (гребёнки + фазовращатели). Каждая петля бесшовная.

  music_menu     — «Проходная»: тема главного меню, романс на фортепиано и струнных, ре минор, 76 уд/мин
  music_morning  — «Первая смена»: гитара-арпеджио и флейта, соль мажор, 96 уд/мин
  music_shop     — «Норма»: рабочий грув — бас, малый, электропиано, ми минор, 108 уд/мин
  music_march    — «Встречный план»: бодрый марш меди и малого барабана, си-бемоль мажор, 116 уд/мин
  music_evening  — «Пересменка»: баян и пэд, вальс, ля минор, 84 уд/мин
  music_night    — «Ночная смена»: пэды, тихий бас и шорох щёток, фа-диез минор, 66 уд/мин
"""
import os
import subprocess
import sys
import tempfile

import numpy as np
from scipy.io import wavfile
from scipy.signal import lfilter, butter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sound")
SR = 32000
NAMES = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
CH = {"": [0, 4, 7], "m": [0, 3, 7], "7": [0, 4, 7, 10], "m7": [0, 3, 7, 10], "maj7": [0, 4, 7, 11], "sus": [0, 5, 7], "dim": [0, 3, 6]}


def midi(name, octave):
    return NAMES.index(name) + 12 * (octave + 1)


def mf(m):
    return 440.0 * 2 ** ((m - 69) / 12)


def n_of(sec):
    return int(sec * SR)


def lp(x, fc, order=2):
    b, a = butter(order, min(0.99, fc / (SR / 2)))
    return lfilter(b, a, x)


def hp(x, fc, order=2):
    b, a = butter(order, min(0.99, fc / (SR / 2)), "high")
    return lfilter(b, a, x)


class Song:
    def __init__(self, seconds, seed):
        self.n = n_of(seconds)
        self.L = np.zeros(self.n + n_of(6))
        self.R = np.zeros(self.n + n_of(6))
        self.send = np.zeros(self.n + n_of(6))
        self.rng = np.random.default_rng(seed)

    def add(self, x, t, pan=0.0, vol=1.0, rev=0.25):
        p = n_of(t)
        if p >= len(self.L):
            return
        m = min(len(x), len(self.L) - p)
        x = x[:m] * vol
        gl = np.sqrt(0.5 * (1 - pan))
        gr = np.sqrt(0.5 * (1 + pan))
        self.L[p:p + m] += x * gl
        self.R[p:p + m] += x * gr
        self.send[p:p + m] += x * rev

    def render(self, room=0.82, damp=3800, wet=0.32):
        rv_l, rv_r = reverb(self.send, room, damp)
        L = self.L + rv_l * wet
        R = self.R + rv_r * wet
        # бесшовная петля: хвост — в начало
        tail = len(L) - self.n
        L[:tail] += L[self.n:]
        R[:tail] += R[self.n:]
        L, R = L[:self.n], R[:self.n]
        pk = max(np.max(np.abs(L)), np.max(np.abs(R))) + 1e-9
        k = 0.89 / pk
        # мягкий лимитер
        return np.tanh(L * k * 1.1) / np.tanh(1.1), np.tanh(R * k * 1.1) / np.tanh(1.1)


def reverb(x, room, damp):
    combs = [1557, 1617, 1491, 1422, 1277, 1356]
    aps = [225, 556, 441]
    outs = []
    for side in (0, 23):
        y = np.zeros_like(x)
        for d in combs:
            d = int((d + side) * SR / 44100)
            a = np.zeros(d + 1)
            a[0] = 1.0
            a[d] = -room
            y += lfilter([1.0], a, lp(x, damp, 1))
        y /= len(combs)
        for d in aps:
            d = int((d + side) * SR / 44100)
            g = 0.5
            b = np.zeros(d + 1)
            a = np.zeros(d + 1)
            b[0], b[d] = -g, 1.0
            a[0], a[d] = 1.0, -g
            y = lfilter(b, a, y)
        outs.append(y)
    return outs[0], outs[1]


# ---------------------------------------------------------------- инструменты

def env_adsr(n, a, d, s, r, dur_n):
    e = np.zeros(n)
    an, dn, rn = max(1, n_of(a)), max(1, n_of(d)), max(1, n_of(r))
    k = min(an, n)
    e[:k] = np.linspace(0, 1, an)[:k]
    if dur_n > an:
        k2 = min(an + dn, n)
        e[an:k2] = np.linspace(1, s, dn)[:k2 - an]
        e[an + dn:dur_n] = s
    end = min(dur_n + rn, n)
    lvl = e[dur_n - 1] if dur_n - 1 < n and dur_n > 0 else s
    if dur_n < n:
        e[dur_n:end] = np.linspace(lvl, 0, rn)[:end - dur_n]
    return e


def guitar(f, dur, rng, bright=0.5):
    """Карплус — Стронг: шумовой импульс в линии задержки с усредняющим фильтром."""
    n = n_of(dur + 1.2)
    d = max(2, int(SR / f))
    buf = rng.uniform(-1, 1, d) * 0.9
    buf = lp(buf, 1500 + 5000 * bright, 1)
    out = np.empty(n)
    # быстрая векторная запись: по блокам длиной d
    prev = buf.copy()
    pos = 0
    while pos < n:
        m = min(d, n - pos)
        out[pos:pos + m] = prev[:m]
        nxt = 0.5 * (prev + np.roll(prev, -1)) * 0.996
        prev = nxt
        pos += m
    out *= np.exp(-np.arange(n) / SR / 1.8)
    return hp(out, 70)


def piano(f, dur, rng, vel=1.0):
    n = n_of(dur + 1.5)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for i, a in enumerate([1.0, 0.55, 0.32, 0.2, 0.12, 0.08, 0.05]):
        h = i + 1
        fi = f * h * np.sqrt(1 + 0.00012 * h * h)
        if fi > SR / 2.2:
            break
        dec = 1.2 + h * 0.7 + f / 900
        x += a * np.sin(2 * np.pi * fi * t + rng.uniform(0, 6)) * np.exp(-t * dec)
    x += 0.4 * np.sin(2 * np.pi * f * 1.002 * t) * np.exp(-t * 1.3)   # второй струна хора
    hammer = rng.standard_normal(n_of(0.01)) * 0.25
    x[:len(hammer)] += lp(hammer, 3000)
    rel = env_adsr(n, 0.002, 0.01, 1.0, 0.25, n_of(dur))
    return x * rel * vel


def epiano(f, dur, rng, vel=1.0):
    """Электропиано: ФМ-колокольчик с быстрым затуханием верха."""
    n = n_of(dur + 0.8)
    t = np.arange(n) / SR
    mod = np.sin(2 * np.pi * f * 7.0 * t) * 1.4 * np.exp(-t * 6)
    x = np.sin(2 * np.pi * f * t + mod) * np.exp(-t * 1.5) + 0.3 * np.sin(2 * np.pi * f * 2 * t) * np.exp(-t * 3)
    return x * env_adsr(n, 0.003, 0.05, 1.0, 0.2, n_of(dur)) * vel


def saw(f, n, rng, det=0.0):
    t = np.arange(n) / SR
    ph = (f * (1 + det) * t + rng.uniform(0, 1)) % 1.0
    return 2 * ph - 1


def pad(fs, dur, rng, bright=1200, vol=1.0):
    """Струнный пэд: несколько расстроенных пил на голос, мягкий фильтр, медленная атака."""
    n = n_of(dur + 1.5)
    x = np.zeros(n)
    for f in fs:
        for det in (-0.004, 0.0, 0.005):
            x += saw(f, n, rng, det)
    x = lp(x, bright, 2) / (3 * len(fs))
    t = np.arange(n) / SR
    x *= 1 + 0.05 * np.sin(2 * np.pi * 0.3 * t + rng.uniform(0, 6))
    return x * env_adsr(n, 0.6, 0.3, 0.85, 1.2, n_of(dur)) * vol


def strings(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.8)
    t = np.arange(n) / SR
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * t) * np.minimum(1, t / 0.4)
    x = np.zeros(n)
    for det in (-0.003, 0.003):
        ph = np.cumsum(f * (1 + det) * vib / SR)
        x += 2 * (ph % 1.0) - 1
    x = lp(x, 2600, 2) * 0.5
    return x * env_adsr(n, 0.12, 0.2, 0.9, 0.5, n_of(dur)) * vol


def brass(f, dur, rng, vol=1.0):
    """Медь: пила, фильтр раскрывается на атаке — характерное «пуа»."""
    n = n_of(dur + 0.4)
    t = np.arange(n) / SR
    vib = 1 + 0.003 * np.sin(2 * np.pi * 5.0 * t) * np.minimum(1, t / 0.3)
    ph = np.cumsum(f * vib / SR)
    x = 2 * (ph % 1.0) - 1 + 0.5 * (2 * ((ph * 1.003) % 1.0) - 1)
    # фильтр по огибающей: блоками
    env = env_adsr(n, 0.04, 0.15, 0.75, 0.12, n_of(dur))
    out = np.zeros(n)
    blk = n_of(0.02)
    zi = None
    for i in range(0, n, blk):
        fc = 600 + 3200 * env[min(i, n - 1)]
        b, a = butter(2, min(0.99, fc / (SR / 2)))
        seg = x[i:i + blk]
        if zi is None:
            zi = np.zeros(max(len(a), len(b)) - 1)
        y, zi = lfilter(b, a, seg, zi=zi)
        out[i:i + blk] = y
    return out * env * vol


def flute(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.4)
    t = np.arange(n) / SR
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * t) * np.minimum(1, t / 0.3)
    ph = np.cumsum(f * vib / SR) * 2 * np.pi
    x = np.sin(ph) + 0.2 * np.sin(2 * ph) + 0.06 * np.sin(3 * ph)
    breath = lp(hp(rng.standard_normal(n), 1500), 5000) * 0.08
    return (x + breath) * env_adsr(n, 0.06, 0.1, 0.85, 0.15, n_of(dur)) * vol


def accordion(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.2)
    t = np.arange(n) / SR
    x = np.zeros(n)
    for det in (-0.0028, 0.0028):
        for i, a in enumerate([1.0, 0.6, 0.45, 0.3, 0.22, 0.14, 0.1]):
            fi = f * (1 + det) * (i + 1)
            if fi < SR / 2.2:
                x += a * np.sin(2 * np.pi * fi * t + i)
    x = lp(x, 3500) * (1 + 0.05 * np.sin(2 * np.pi * 5.0 * t))
    return x * env_adsr(n, 0.03, 0.05, 0.9, 0.08, n_of(dur)) * vol * 0.4


def bass(f, dur, rng, vol=1.0, pick=0.6):
    n = n_of(dur + 0.3)
    t = np.arange(n) / SR
    x = np.sin(2 * np.pi * f * t) + 0.45 * np.sin(4 * np.pi * f * t) * np.exp(-t * 4)
    x += pick * 0.4 * lp(saw(f, n, rng), 900, 2) * np.exp(-t * 6)
    return x * env_adsr(n, 0.005, 0.2, 0.7, 0.08, n_of(dur)) * vol


def kick(rng, vol=1.0):
    n = n_of(0.45)
    t = np.arange(n) / SR
    f = 48 + 90 * np.exp(-t * 30)
    return np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 7) * vol


def snare(rng, vol=1.0, brush=False):
    n = n_of(0.3)
    t = np.arange(n) / SR
    nz = hp(rng.standard_normal(n), 1200 if not brush else 2500)
    if brush:
        return lp(nz, 7000) * np.exp(-t * 14) * vol * 0.5
    body = np.sin(2 * np.pi * 185 * t) * np.exp(-t * 25)
    return (nz * np.exp(-t * 16) * 0.7 + body * 0.5) * vol


def hat(rng, vol=1.0, open_=False):
    n = n_of(0.25 if open_ else 0.06)
    t = np.arange(n) / SR
    return hp(rng.standard_normal(n), 7000) * np.exp(-t * (12 if open_ else 70)) * vol


# ---------------------------------------------------------------- композиция

def chord_notes(root, kind, octave=3):
    r = midi(root, octave)
    return [r + iv for iv in CH[kind]]


def melody_line(rng, prog, scale, beats_per_chord, start=72, motif=None):
    """Мелодия: опирается на тоны аккорда на сильных долях, между ними — шаги по ладу; мотив повторяется."""
    notes = []
    cur = start
    if motif is None:
        motif = [(1.0, 0), (0.5, 1), (0.5, -1), (1.0, 2), (1.0, -2)]
    for ci, (root, kind) in enumerate(prog):
        tones = chord_notes(root, kind, 5)
        t = 0.0
        mi = 0
        while t < beats_per_chord - 0.01:
            d, step = motif[(mi + ci) % len(motif)]
            d = min(d, beats_per_chord - t)
            if t == 0.0:
                # ближайший тон аккорда
                cur = min(tones + [x - 12 for x in tones], key=lambda x: abs(x - cur))
            else:
                cand = [s for s in scale if abs(s - cur) <= 4 and s != cur]
                if step > 0:
                    cand = [s for s in cand if s > cur] or cand
                elif step < 0:
                    cand = [s for s in cand if s < cur] or cand
                cur = cand[rng.integers(0, len(cand))] if cand else cur
            cur = max(start - 7, min(start + 9, cur))
            rest = rng.random() < 0.08 and t > 0
            notes.append((ci * beats_per_chord + t, d, None if rest else cur))
            t += d
            mi += 1
    return notes


def scale_of(root, minor=False):
    base = [0, 2, 3, 5, 7, 8, 10] if minor else [0, 2, 4, 5, 7, 9, 11]
    r = NAMES.index(root)
    return sorted({60 + ((r + s) % 12) + 12 * k for s in base for k in range(-2, 3)})


def save(name, L, R, q=4):
    os.makedirs(OUT, exist_ok=True)
    st = np.stack([L, R], axis=1)
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        wavfile.write(tf.name, SR, (st * 32767).astype(np.int16))
        tmp = tf.name
    out = os.path.join(OUT, name + ".ogg")
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", tmp, "-c:a", "libvorbis", "-q:a", str(q), out], check=True)
    os.unlink(tmp)
    # выравнивание громкости: средний уровень −17 дБ, как у остальных треков
    det = subprocess.run(["ffmpeg", "-i", out, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
    mean = float(det.split("mean_volume:")[1].split("dB")[0])
    tmp2 = out + ".tmp.ogg"
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", out, "-af", "volume=%.2fdB,alimiter=limit=0.95" % (-17.5 - mean),
                    "-c:a", "libvorbis", "-q:a", str(q), tmp2], check=True)
    os.replace(tmp2, out)
    print(name, "%.0f с" % (len(L) / SR), "%d КБ" % (os.path.getsize(out) // 1024))


def music_menu():
    bpm, beats = 76, 4
    b = 60 / bpm
    prog = [("D", "m"), ("A#", ""), ("F", ""), ("C", ""), ("D", "m"), ("G", "m"), ("A", "sus"), ("A", "7")] * 2 + \
           [("G", "m"), ("D", "m"), ("A#", "maj7"), ("A", "7"), ("D", "m"), ("G", "m"), ("A", "7"), ("D", "m")]
    s = Song(len(prog) * beats * b, 128)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        s.add(pad([mf(m) for m in ns[:3]], beats * b, rng, 1500, 0.55), t0, 0.0, 1.0, 0.5)
        s.add(piano(mf(ns[0] - 12), beats * b, rng, 0.5), t0, -0.2, 1.0, 0.3)
        for k, ai in enumerate([0, 1, 2, 1, 2, 1, 0, 2]):
            m = ns[ai % len(ns)] + 12
            s.add(piano(mf(m), b * 0.9, rng, 0.22), t0 + k * b / 2, 0.25, 1.0, 0.35)
    mel = melody_line(rng, prog[8:16], scale_of("D", True), beats, 74, [(1.5, 0), (0.5, 1), (1.0, -1), (1.0, 1), (2.0, -2), (1.0, 1), (1.0, -1)])
    for tb, d, m in mel:
        if m is not None:
            s.add(strings(mf(m), d * b * 0.95, rng, 0.32), 8 * beats * b + tb * b, -0.15, 1.0, 0.5)
    mel2 = melody_line(rng, prog[16:], scale_of("D", True), beats, 77)
    for tb, d, m in mel2:
        if m is not None:
            s.add(piano(mf(m), d * b, rng, 0.42), 16 * beats * b + tb * b, 0.1, 1.0, 0.4)
            s.add(strings(mf(m - 12), d * b * 0.95, rng, 0.18), 16 * beats * b + tb * b, -0.3, 1.0, 0.5)
    L, R = s.render(0.84, 3600, 0.38)
    save("music_menu", L, R)


def music_morning():
    bpm, beats = 96, 4
    b = 60 / bpm
    prog = [("G", ""), ("D", ""), ("E", "m"), ("C", "")] * 4 + [("A", "m"), ("D", ""), ("G", ""), ("E", "m"), ("C", ""), ("A", "m"), ("D", "sus"), ("D", "")]
    s = Song(len(prog) * beats * b, 129)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        pat = [0, 2, 1, 2, 0 + 3, 2, 1, 2]
        for k, ai in enumerate(pat):
            m = ns[ai % 3] + (12 if ai >= 3 else 0)
            s.add(guitar(mf(m), b / 2, rng, 0.45), t0 + k * b / 2 + rng.uniform(0, 0.008), -0.35, 0.55, 0.25)
        s.add(bass(mf(ns[0] - 12), b * 1.8, rng, 0.55, 0.2), t0, 0.0, 1.0, 0.1)
        s.add(bass(mf(ns[2] - 24), b * 1.8, rng, 0.45, 0.2), t0 + 2 * b, 0.0, 1.0, 0.1)
        if i >= 4:
            s.add(pad([mf(m + 12) for m in ns], beats * b, rng, 1800, 0.25), t0, 0.3, 1.0, 0.5)
    mel = melody_line(rng, prog[4:], scale_of("G"), beats, 76, [(1.0, 0), (0.5, 1), (0.5, 1), (1.0, -1), (0.5, -1), (0.5, 1)])
    for tb, d, m in mel:
        if m is not None:
            s.add(flute(mf(m), d * b * 0.92, rng, 0.33), 4 * beats * b + tb * b, 0.3, 1.0, 0.4)
    L, R = s.render(0.8, 4200, 0.3)
    save("music_morning", L, R)


def music_shop():
    bpm, beats = 108, 4
    b = 60 / bpm
    prog = [("E", "m7"), ("E", "m7"), ("C", "maj7"), ("D", "")] * 3 + [("A", "m7"), ("B", "7"), ("E", "m7"), ("C", "maj7"), ("A", "m7"), ("B", "7"), ("E", "m7"), ("E", "m7")]
    s = Song(len(prog) * beats * b, 130)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        for k in range(beats):
            s.add(kick(rng, 0.8), t0 + k * b, 0.0, 1.0, 0.05) if k in (0, 2) else None
            if k in (1, 3):
                s.add(snare(rng, 0.45), t0 + k * b, 0.05, 1.0, 0.2)
            for h in range(2):
                s.add(hat(rng, 0.18 if h else 0.12), t0 + k * b + h * b / 2 + (0.02 if h else 0), 0.35, 1.0, 0.05)
        line = [0, 0, 7, 0, 10, 0, 7, 5] if "m" in kind else [0, 0, 7, 0, 4, 0, 7, 9]
        for k, iv in enumerate(line):
            s.add(bass(mf(ns[0] - 12 + iv), b * 0.45, rng, 0.6, 0.7), t0 + k * b / 2, -0.05, 1.0, 0.05)
        for k in (0.5, 1.5, 2.5, 3.25):
            for m in ns[1:]:
                s.add(epiano(mf(m + 12), b * 0.4, rng, 0.16), t0 + k * b, -0.3, 1.0, 0.3)
    mel = melody_line(rng, prog[4:12], scale_of("E", True), beats, 76, [(0.5, 0), (0.5, 1), (1.0, -1), (0.5, 2), (1.5, -1)])
    for tb, d, m in mel:
        if m is not None:
            s.add(epiano(mf(m), d * b, rng, 0.38), 4 * beats * b + tb * b, 0.25, 1.0, 0.35)
    mel2 = melody_line(rng, prog[12:], scale_of("E", True), beats, 79, [(1.0, 0), (0.5, -1), (0.5, -1), (2.0, 2)])
    for tb, d, m in mel2:
        if m is not None:
            s.add(brass(mf(m), d * b * 0.9, rng, 0.2), 12 * beats * b + tb * b, 0.2, 1.0, 0.3)
    L, R = s.render(0.7, 4500, 0.2)
    save("music_shop", L, R)


def music_march():
    bpm, beats = 116, 4
    b = 60 / bpm
    prog = [("A#", ""), ("F", ""), ("A#", ""), ("D#", ""), ("A#", ""), ("G", "m"), ("C", "7"), ("F", "7")] * 2 + \
           [("D#", ""), ("A#", ""), ("C", "m"), ("F", "7"), ("D#", ""), ("A#", ""), ("F", "7"), ("A#", "")]
    s = Song(len(prog) * beats * b, 131)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        for k in range(beats):
            s.add(bass(mf(ns[0] - 12 if k % 2 == 0 else ns[2] - 24), b * 0.5, rng, 0.6, 0.3), t0 + k * b, 0.0, 1.0, 0.1)
            if k % 2 == 1:
                for m in ns:
                    s.add(brass(mf(m + 12), b * 0.35, rng, 0.08), t0 + k * b, -0.25, 1.0, 0.3)
            s.add(snare(rng, 0.25), t0 + k * b + b / 2, 0.15, 1.0, 0.2)
            if k == 0:
                s.add(kick(rng, 0.7), t0, 0.0, 1.0, 0.2)
                s.add(snare(rng, 0.4), t0, 0.15, 1.0, 0.3)
        if i % 4 == 3:
            for r in range(4):
                s.add(snare(rng, 0.2), t0 + 3 * b + r * b / 4, 0.15, 1.0, 0.2)
    mel = melody_line(rng, prog[:8], scale_of("A#"), beats, 74, [(1.5, 0), (0.5, 1), (1.0, 1), (1.0, -2), (0.5, 1), (0.5, 1), (1.0, 2)])
    for rep, off in ((0, 0), (1, 8)):
        for tb, d, m in mel:
            if m is not None:
                s.add(brass(mf(m), d * b * 0.88, rng, 0.42), off * beats * b + tb * b, 0.1, 1.0, 0.3)
                if rep:
                    s.add(flute(mf(m + 12), d * b * 0.85, rng, 0.18), off * beats * b + tb * b, 0.4, 1.0, 0.3)
    mel2 = melody_line(rng, prog[16:], scale_of("A#"), beats, 72, [(1.0, 0), (1.0, 1), (0.5, -1), (0.5, -1), (1.0, 2)])
    for tb, d, m in mel2:
        if m is not None:
            s.add(brass(mf(m - 12), d * b * 0.9, rng, 0.4), 16 * beats * b + tb * b, -0.2, 1.0, 0.3)
            s.add(brass(mf(m), d * b * 0.9, rng, 0.22), 16 * beats * b + tb * b, 0.25, 1.0, 0.3)
    L, R = s.render(0.78, 4000, 0.28)
    save("music_march", L, R)


def music_evening():
    bpm, beats = 84, 3
    b = 60 / bpm
    prog = [("A", "m"), ("A", "m"), ("D", "m"), ("D", "m"), ("G", ""), ("G", ""), ("C", ""), ("E", "7"),
            ("F", ""), ("F", ""), ("D", "m"), ("E", ""), ("A", "m"), ("D", "m"), ("E", "7"), ("A", "m")] * 2
    s = Song(len(prog) * beats * b, 132)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        s.add(accordion(mf(ns[0] - 12), b * 0.85, rng, 0.9), t0, -0.2, 1.0, 0.2)
        for k in (1, 2):
            for m in ns[:3]:
                s.add(accordion(mf(m), b * 0.5, rng, 0.35), t0 + k * b, -0.1, 1.0, 0.25)
        s.add(pad([mf(m + 12) for m in ns[:3]], beats * b, rng, 1100, 0.18), t0, 0.35, 1.0, 0.5)
    mel = melody_line(rng, prog[:16], scale_of("A", True), beats, 76, [(2.0, 0), (1.0, -1), (1.0, 1), (1.0, 1), (1.0, -2), (3.0, 0)])
    for rep in range(2):
        for tb, d, m in mel:
            if m is not None:
                inst = accordion if rep == 0 else strings
                s.add(inst(mf(m), d * b * 0.95, rng, 0.75 if rep == 0 else 0.3), rep * 16 * beats * b + tb * b, 0.2, 1.0, 0.35)
    L, R = s.render(0.83, 3600, 0.33)
    save("music_evening", L, R)


def music_night():
    bpm, beats = 66, 4
    b = 60 / bpm
    prog = [("F#", "m7"), ("D", "maj7"), ("A", ""), ("E", "sus"), ("F#", "m7"), ("B", "m7"), ("D", "maj7"), ("C#", "7")] * 2
    s = Song(len(prog) * beats * b, 133)
    rng = s.rng
    for i, (root, kind) in enumerate(prog):
        t0 = i * beats * b
        ns = chord_notes(root, kind, 3)
        s.add(pad([mf(m) for m in ns], beats * b, rng, 900, 0.6), t0, 0.0, 1.0, 0.6)
        s.add(bass(mf(ns[0] - 12), b * 3.5, rng, 0.45, 0.1), t0, 0.0, 1.0, 0.1)
        for k in range(beats):
            s.add(snare(rng, 0.12, brush=True), t0 + k * b + b / 2, 0.3, 1.0, 0.3)
            if k == 0 or k == 2:
                s.add(kick(rng, 0.25), t0 + k * b, 0.0, 1.0, 0.1)
        for k, ai in enumerate([2, 1, 3, 1]):
            m = ns[ai % len(ns)] + 12
            s.add(epiano(mf(m), b * 0.9, rng, 0.13), t0 + k * b + b * 0.25, -0.35, 1.0, 0.5)
    mel = melody_line(rng, prog[8:], scale_of("F#", True), beats, 78, [(2.0, 0), (1.0, -1), (1.0, -1), (3.0, 2), (1.0, -1)])
    for tb, d, m in mel:
        if m is not None:
            s.add(piano(mf(m), d * b, rng, 0.3), 8 * beats * b + tb * b, 0.25, 1.0, 0.6)
    L, R = s.render(0.88, 3000, 0.42)
    save("music_night", L, R)


if __name__ == "__main__":
    only = sys.argv[1:]
    for fn in [music_menu, music_morning, music_shop, music_march, music_evening, music_night]:
        if not only or fn.__name__ in only:
            fn()
