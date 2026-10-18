#!/usr/bin/env python3
"""1.31 «Музыка»: десять новых композиций для «Промзоны» — разных по темпу, ладу и составу.

Запуск: python3 tools/gen_music_131.py [имя ...]  (из корня проекта; нужны numpy, scipy и ffmpeg)
Всё синтезируется кодом: инструменты из gen_music_128.py плюс новые — полисинтезатор, квадратный «эстрадный»
синтезатор, синт-бас, вибрафон, челеста, колокольчики, металл (трубы, наковальня, пресс), пар, гул цеха,
контрабас, щётки и райд, кларнет, балалаечное тремоло, бубенцы, радиошорох.
У каждой пьесы настоящая форма (вступление — A — A' — B — A'' — кода), гармония по тактам, мелодия
строится мотивом и его «подгонкой» под следующие аккорды (секвенции, ответы, каденции), варьируется
при повторах. Конец — каденция, ритардандо, хвост ревербератора и естественное затухание (не петля).

  music_estrada  — «Огни проспекта»: эстрадный лаунж, синтезаторы и драм-машина, ми-бемоль мажор → ми мажор, 112
  music_accwaltz — «Над заводской рекой»: медленный вальс баяна, ми минор / соль мажор, 3/4, 88
  music_folk     — «Тропинка к проходной»: гитара-перебор, балалайка, флейта, ре мажор, 6/8
  music_foundry  — «Литейный цех»: индустриальный эмбиент — гул, пар, металл, до-диез фригийский, 96
  music_jazz     — «Буфет на втором этаже»: свинг — контрабас, щётки, рояль, кларнет и вибрафон, фа мажор, 132
  music_march2   — «Ударная вахта»: бодрый трудовой марш с трио, ре мажор → соль мажор, 124
  music_rain     — «Дождь над крышей цеха»: рояль, ре-бемоль мажор, 66
  music_radio    — «Ночной эфир»: ночное радио — пэды, вибрафон, шорох эфира, си минор, 60
  music_winter   — «Первый снег»: челеста, пиццикато, струнные и бубенцы, ля мажор, 82
  music_dawn     — «Утренний автобус»: секвенсор, синт-струнные, свист, соль миксолидийский, 104

Ещё выравнивает громкость старых music_calm и music_waltz (−17,5 дБ, как у остальных).
"""
import os
import subprocess
import sys
import tempfile

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_music_128 as g  # noqa: E402
from gen_music_128 import SR, NAMES, mf, n_of, lp, hp, env_adsr, saw, reverb  # noqa: E402
from gen_music_128 import guitar, piano, epiano, pad, strings, brass, flute, accordion, bass, kick, snare, hat  # noqa: E402

CH = dict(g.CH)
CH.update({"5": [0, 7], "6": [0, 4, 7, 9], "m6": [0, 3, 7, 9], "9": [0, 4, 7, 10, 14], "m9": [0, 3, 7, 10, 14],
           "maj9": [0, 4, 7, 11, 14], "add9": [0, 4, 7, 14], "m7b5": [0, 3, 6, 10], "7sus": [0, 5, 7, 10]})
MODES = {"major": [0, 2, 4, 5, 7, 9, 11], "minor": [0, 2, 3, 5, 7, 8, 10], "harm": [0, 2, 3, 5, 7, 8, 11],
         "dorian": [0, 2, 3, 5, 7, 9, 10], "mixo": [0, 2, 4, 5, 7, 9, 10], "phryg": [0, 1, 3, 5, 7, 8, 10]}
STATS = {}


def pc(name):
    return NAMES.index(name)


def tones(root, kind):
    return [(pc(root) + iv) % 12 for iv in CH[kind]]


def voicing(root, kind, lo=55, top=None):
    """Тесное расположение: каждый тон аккорда — в октаве [lo, lo+11]."""
    ivs = CH[kind] if top is None else CH[kind][:top]
    return sorted(lo + ((pc(root) + iv - lo) % 12) for iv in ivs)


def scale(root, mode):
    s = {(pc(root) + iv) % 12 for iv in MODES[mode]}
    return [m for m in range(24, 109) if m % 12 in s]


def nearest(cands, x):
    return min(cands, key=lambda c: (abs(c - x), c))


def trans(root, semis):
    return NAMES[(pc(root) + semis) % 12]


def tr_chords(chords, semis):
    return [(trans(c[0], semis),) + tuple(c[1:]) for c in chords]


# ---------------------------------------------------------------- форма и время

class Arr:
    """Форма пьесы: разделы с аккордами, доли → секунды (свинг, ритардандо в конце)."""

    def __init__(self, bpm, bpb, sections, strong=(0,), swing=0.0, rit=0, rit_amt=0.4):
        self.b = 60.0 / bpm
        self.bpb = bpb
        self.strong = strong
        self.swing = swing
        self.secs = []
        beat = 0
        for name, chords in sections:
            evs = []
            b0 = beat
            for c in chords:
                nb = c[2] if len(c) > 2 else bpb
                evs.append((beat, nb, c[0], c[1]))
                beat += nb
            self.secs.append((name, b0, beat - b0, evs))
        self.total = beat
        durs = np.full(int(np.ceil(beat)) + 16, self.b)
        for i in range(rit):
            k = int(beat) - rit + i
            durs[k] *= 1 + rit_amt * ((i + 1) / rit) ** 2
        durs[int(beat):] = durs[int(beat) - 1] if rit else self.b
        self.cum = np.concatenate([[0.0], np.cumsum(durs)])

    def T(self, beat):
        i = int(np.floor(beat + 1e-9))
        f = beat - i
        if self.swing:
            s = self.swing
            f = f * (0.5 + s) / 0.5 if f < 0.5 else 0.5 + s + (f - 0.5) * (0.5 - s) / 0.5
        return self.cum[i] + f * (self.cum[i + 1] - self.cum[i])

    def D(self, beat, dur):
        return self.T(beat + dur) - self.T(beat)

    def length(self):
        return self.T(self.total)

    def chord_at(self, beat):
        for _, b0, nb, evs in self.secs:
            if b0 <= beat < b0 + nb:
                for e in evs:
                    if e[0] <= beat + 1e-6 < e[0] + e[1]:
                        return e[2], e[3]
        e = self.secs[-1][3][-1]
        return e[2], e[3]

    def is_strong(self, beat):
        rel = beat % self.bpb
        return any(abs(rel - s) < 1e-6 for s in self.strong)

    def sec(self, name, k=0):
        found = [s for s in self.secs if s[0] == name]
        return found[k]

    def chords(self):
        for s in self.secs:
            for e in s[3]:
                yield s[0], e


class Mix:
    """Как Song из 1.28, но без «петли»: хвост ревербератора остаётся, в конце — естественное затухание."""

    def __init__(self, seconds, seed):
        self.n = n_of(seconds + 7.0)
        self.L = np.zeros(self.n)
        self.R = np.zeros(self.n)
        self.send = np.zeros(self.n)
        self.rng = np.random.default_rng(seed)
        self.stats = {}

    def add(self, x, t, pan=0.0, vol=1.0, rev=0.25, tag="?", hum=0.0):
        if hum:
            t += self.rng.normal(0, hum)
            vol *= 1 + self.rng.normal(0, 0.07)
        p = max(0, n_of(t))
        if p >= self.n:
            return
        m = min(len(x), self.n - p)
        x = x[:m] * vol
        gl = np.sqrt(0.5 * (1 - pan))
        gr = np.sqrt(0.5 * (1 + pan))
        self.L[p:p + m] += x * gl
        self.R[p:p + m] += x * gr
        self.send[p:p + m] += x * rev
        if tag not in self.stats:
            self.stats[tag] = np.zeros(self.n, np.float32)
        self.stats[tag][p:p + m] += x

    def render(self, room=0.82, damp=3800, wet=0.32, fade=2.5):
        rv_l, rv_r = reverb(self.send, room, damp)
        L = self.L + rv_l * wet
        R = self.R + rv_r * wet
        env = np.maximum(np.abs(L), np.abs(R))
        pk = float(np.max(env)) + 1e-9
        alive = np.nonzero(env > pk * 0.002)[0]
        end = min(self.n, int(alive[-1]) + n_of(0.3)) if len(alive) else self.n
        L, R = L[:end], R[:end]
        fn = min(end, n_of(fade))
        w = np.cos(np.linspace(0, np.pi / 2, fn)) ** 2
        L[-fn:] *= w
        R[-fn:] *= w
        fi = n_of(0.01)
        L[:fi] *= np.linspace(0, 1, fi)
        R[:fi] *= np.linspace(0, 1, fi)
        k = 0.89 / pk
        def loud(x):   # грубая «слуховая» громкость: без низа, с подъёмом верха
            y = hp(x.astype(np.float64), 120)
            y = y + 0.6 * hp(y, 2000)
            return 10 * np.log10(np.mean(y * y) + 1e-15)
        tot = loud((L + R) * 0.5 / max(1e-9, 1.0))
        rows = sorted(((loud(v[:end]), t) for t, v in self.stats.items()), reverse=True)
        print("   партии (дБ к целому):", ", ".join("%s %+.1f" % (t, d - tot) for d, t in rows))
        return np.tanh(L * k * 1.1) / np.tanh(1.1), np.tanh(R * k * 1.1) / np.tanh(1.1)


# ---------------------------------------------------------------- мелодия

def rh(s):
    """Ритм строкой: w h q e s (целая … шестнадцатая), точка — с точкой, r — пауза, числа — доли как есть, | — для глаз."""
    base = {"w": 4.0, "h": 2.0, "q": 1.0, "e": 0.5, "s": 0.25, "t": 1.0 / 3.0}
    out = []
    for tok in s.split():
        if tok == "|":
            continue
        rest = tok.startswith("r")
        tok = tok[1:] if rest else tok
        dots = tok.count(".") if tok[0] in base else 0
        core = tok.rstrip(".") if dots else tok
        d = base[core] if core in base else float(core)
        d *= 1.5 if dots == 1 else 1.0
        out.append((d, rest))
    return out


def chord_scale(sc, root, kind):
    """Лад под аккорд: убираем «избегаемые» ступени (полутон над тоном аккорда) и альтерации, добавляем тоны аккорда."""
    ct = set(tones(root, kind))
    pcs = {m % 12 for m in sc}
    keep = set()
    for p in pcs:
        if p in ct:
            keep.add(p)
        elif (p - 1) % 12 in ct:
            continue
        elif (p + 1) % 12 in ct and (p + 1) % 12 not in pcs:
            continue
        else:
            keep.add(p)
    keep |= ct
    return [m for m in range(24, 109) if m % 12 in keep]


def gen_phrase(arr, rng, beat0, rhythm, sc, lo, hi, start, end_pc=None, leap=0.25):
    notes = []
    cur = start
    d = 1 if rng.random() < 0.5 else -1
    t = beat0
    idx = [i for i, (_, r) in enumerate(rhythm) if not r]
    last = idx[-1] if idx else -1
    for i, (du, rest) in enumerate(rhythm):
        if rest:
            t += du
            continue
        root, kind = arr.chord_at(t)
        cs = [s for s in chord_scale(sc, root, kind) if lo <= s <= hi]
        if i == last and end_pc is not None:
            cur = nearest([s for s in cs if s % 12 == end_pc] or cs, cur)
        elif arr.is_strong(t) or du >= arr.bpb / 2:
            ct = set(tones(root, kind))
            cands = [s for s in cs if s % 12 in ct]
            cur = nearest(cands, cur + d * int(rng.integers(1, 4)))
        else:
            k = cs.index(nearest(cs, cur))
            k = int(np.clip(k + d * (2 if rng.random() < leap else 1), 0, len(cs) - 1))
            cur = cs[k]
        if cur >= hi - 2:
            d = -1
        elif cur <= lo + 2:
            d = 1
        elif rng.random() < 0.22:
            d = -d
        notes.append((t, du, cur))
        t += du
    return notes


def refit(arr, notes, offset, sc, end_pc=None, shift=0):
    """Тот же мотив на новом месте: сильные доли — к ближайшему тону нового аккорда, остальное — к ладу."""
    out = []
    for i, (t, du, m) in enumerate(notes):
        nt = t + offset
        m2 = m + shift
        root, kind = arr.chord_at(nt)
        cs = chord_scale(sc, root, kind)
        if i == len(notes) - 1 and end_pc is not None:
            m2 = nearest([s for s in cs if s % 12 == end_pc], m2)
        elif arr.is_strong(nt):
            ct = set(tones(root, kind))
            m2 = nearest([s for s in cs if s % 12 in ct], m2)
        else:
            m2 = nearest(cs, m2)
        out.append((nt, du, m2))
    return out


def vary(arr, notes, rng, sc, p=0.25, split=1.0):
    """Вариация при повторе: часть слабых нот сдвинута на ступень, длинные иногда раздроблены."""
    out = []
    for i, (t, du, m) in enumerate(notes):
        if 0 < i < len(notes) - 1 and not arr.is_strong(t):
            r = rng.random()
            root, kind = arr.chord_at(t)
            cs = chord_scale(sc, root, kind)
            if r < p:
                k = cs.index(nearest(cs, m))
                m = cs[int(np.clip(k + (1 if rng.random() < 0.5 else -1), 0, len(cs) - 1))]
            elif r < p * 1.6 and du >= split:
                k = cs.index(nearest(cs, m))
                out.append((t, du / 2, m))
                out.append((t + du / 2, du / 2, cs[int(np.clip(k + (1 if rng.random() < 0.5 else -1), 0, len(cs) - 1))]))
                continue
        out.append((t, du, m))
    return out


def shift_notes(notes, beats=0.0, semis=0):
    return [(t + beats, d, m + semis) for t, d, m in notes]


def put(mix, arr, inst, notes, pan=0.0, vol=1.0, rev=0.3, legato=0.95, tag="мелодия", hum=0.004, **kw):
    for t, d, m in notes:
        if m is None:
            continue
        mix.add(inst(mf(m), arr.D(t, d) * legato, mix.rng, **kw), arr.T(t), pan, vol, rev, tag, hum)


# ---------------------------------------------------------------- новые инструменты

def _t(n):
    return np.arange(n) / SR


def partials(f, n, ratios, amps, decays, rng):
    t = _t(n)
    x = np.zeros(n)
    for r, a, dc in zip(ratios, amps, decays):
        if f * r < SR / 2.2:
            x += a * np.sin(2 * np.pi * f * r * t + rng.uniform(0, 6.28)) * np.exp(-t * dc)
    return x


def vibes(f, dur, rng, vol=1.0):
    n = n_of(dur + 1.8)
    t = _t(n)
    x = partials(f, n, [1, 4.0, 10.0], [1.0, 0.22, 0.05], [0.9, 3.0, 8.0], rng)
    x *= 1 + 0.25 * np.sin(2 * np.pi * 5.3 * t)
    x[:n_of(0.004)] += lp(rng.standard_normal(n_of(0.004)), 2500) * 0.2
    return x * env_adsr(n, 0.002, 0.01, 1.0, 0.35, n_of(dur + 0.4)) * vol


def celesta(f, dur, rng, vol=1.0):
    n = n_of(min(dur, 1.0) + 1.4)
    x = partials(f, n, [1, 3.0, 4.18], [1.0, 0.18, 0.08], [2.0, 5.0, 9.0], rng)
    x[:n_of(0.003)] += hp(rng.standard_normal(n_of(0.003)), 3000) * 0.15
    return x * vol


def glock(f, dur, rng, vol=1.0):
    n = n_of(2.2)
    return partials(f, n, [1, 2.76, 5.40, 8.93], [1.0, 0.35, 0.14, 0.05], [1.3, 3.0, 6.0, 9.0], rng) * vol


def metal(f, rng, vol=1.0, dec=2.5, length=2.5):
    n = n_of(length)
    rs = np.array([1, 1.506, 2.10, 2.74, 3.33, 4.21, 5.02]) * (1 + rng.normal(0, 0.012, 7))
    am = np.array([1.0, 0.7, 0.55, 0.4, 0.3, 0.2, 0.12]) * rng.uniform(0.6, 1.0, 7)
    x = partials(f, n, rs, am, [dec * (1 + 0.6 * k) for k in range(7)], rng)
    nz = n_of(0.02)
    x[:nz] += hp(rng.standard_normal(nz), 1500) * np.exp(-_t(nz) * 200) * 0.6
    return x * vol * 0.5


def press(rng, vol=1.0):
    """Удар пресса: низкий «бух», глухой шум и металлический призвук."""
    x = np.zeros(n_of(1.0))
    k = kick(rng, 1.0)
    x[:len(k)] += k
    nz = n_of(0.3)
    x[:nz] += lp(rng.standard_normal(nz), 350) * np.exp(-_t(nz) * 14) * 1.2
    m = metal(170, rng, 0.35, dec=6, length=1.0)
    x[:len(m)] += m
    return x * vol


def steam(dur, rng, vol=1.0):
    n = n_of(dur)
    x = lp(hp(rng.standard_normal(n), 900), 4500)
    t = _t(n)
    e = np.minimum(1, t / (dur * 0.3)) * np.exp(-np.maximum(0, t - dur * 0.3) * 3.0 / dur)
    return x * e * vol * 0.4


def drone(fs, dur, rng, vol=1.0, rate=0.07):
    n = n_of(dur + 2.5)
    x = np.zeros(n)
    for f in fs:
        for det in (-0.003, 0.0, 0.004):
            x += saw(f, n, rng, det)
    x /= 3 * len(fs)
    a = lp(x, 260, 2)
    b = lp(x, 1300, 2)
    t = _t(n)
    w = 0.5 + 0.5 * np.sin(2 * np.pi * rate * t + rng.uniform(0, 6.28))
    y = a * (1 - w) + b * w * 0.7
    return y * env_adsr(n, 1.8, 0.5, 1.0, 2.2, n_of(dur)) * vol


def spluck(f, dur, rng, vol=1.0, bright=1.0, sus=0.0):
    """Синт-щипок / синт-бас: гармоники пилы, верхние гаснут быстрее — как фильтр, закрывающийся по огибающей."""
    n = n_of(dur + 0.25)
    t = _t(n)
    x = np.zeros(n)
    for k in range(1, 22):
        if f * k > SR / 2.3:
            break
        dc = 1.5 + k * 2.2 / bright
        x += (1.0 / k) * np.sin(2 * np.pi * f * k * t) * (np.exp(-t * dc) * (1 - sus) + sus * (k < 4))
    return x * env_adsr(n, 0.003, 0.05, 1.0, 0.08, n_of(dur)) * vol


def slead(f, dur, rng, vol=1.0, vib=0.006, odd=True):
    """«Эстрадный» синтезатор: квадрат (нечётные гармоники) и второй генератор чуть выше, вибрато с задержкой."""
    n = n_of(dur + 0.3)
    t = _t(n)
    v = 1 + vib * np.sin(2 * np.pi * 5.6 * t) * np.clip((t - 0.25) / 0.4, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * v) / SR
    x = np.zeros(n)
    for k in range(1, 12, 2 if odd else 1):
        if f * k < SR / 2.3:
            x += np.sin(k * ph) / k + 0.4 * np.sin(k * ph * 1.004) / k
    return lp(x, 4200, 1) * env_adsr(n, 0.015, 0.1, 0.8, 0.15, n_of(dur)) * vol * 0.6


def polysynth(fs, dur, rng, vol=1.0, cutoff=2200, a=0.01, r=0.3):
    n = n_of(dur + r + 0.1)
    x = np.zeros(n)
    for f in fs:
        for det in (-0.005, 0.005):
            x += saw(f, n, rng, det)
    x = lp(x, cutoff, 2) / (2 * len(fs))
    return x * env_adsr(n, a, 0.25, 0.65, r, n_of(dur)) * vol


def clap(rng, vol=1.0):
    n = n_of(0.3)
    t = _t(n)
    nz = lp(hp(rng.standard_normal(n), 900), 5200)
    e = np.zeros(n)
    for d in (0.0, 0.011, 0.022):
        e += np.where(t >= d, np.exp(-(t - d) * 160), 0)
    e += np.where(t >= 0.03, np.exp(-(t - 0.03) * 18) * 0.6, 0)
    return nz * e * vol * 0.6


def tom(f, rng, vol=1.0):
    n = n_of(0.6)
    t = _t(n)
    fr = f * (1 + 0.6 * np.exp(-t * 20))
    return np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 6) * vol


def crash(rng, vol=1.0, length=3.0):
    n = n_of(length)
    t = _t(n)
    x = hp(rng.standard_normal(n), 3500) * np.exp(-t * 1.6)
    x += partials(3100, n, [1, 1.37, 1.81, 2.3], [0.3, 0.25, 0.2, 0.15], [2, 2.5, 3, 3.5], rng)
    return x * vol * 0.35


def ride(rng, vol=1.0):
    n = n_of(1.4)
    t = _t(n)
    x = hp(rng.standard_normal(n), 6000) * np.exp(-t * 9) * 0.6
    x += partials(3150, n, [1, 1.41, 1.87], [0.35, 0.3, 0.2], [2.4, 3.0, 3.6], rng)
    return x * vol * 0.3


def swish(dur, rng, vol=1.0):
    n = n_of(dur)
    t = _t(n)
    x = lp(hp(rng.standard_normal(n), 2200), 8000)
    return x * np.sin(np.pi * np.clip(t / dur, 0, 1)) ** 1.5 * vol * 0.25


def upright(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.4)
    t = _t(n)
    x = partials(f, n, [1, 2, 3, 4], [1.0, 0.45, 0.18, 0.06], [1.6, 3.2, 5.5, 8.0], rng)
    th = n_of(0.03)
    x[:th] += lp(rng.standard_normal(th), 500) * np.exp(-_t(th) * 90) * 0.5
    return x * env_adsr(n, 0.004, 0.05, 1.0, 0.09, n_of(dur)) * vol


def clarinet(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.3)
    t = _t(n)
    v = 1 + 0.0035 * np.sin(2 * np.pi * 4.8 * t) * np.clip((t - 0.3) / 0.5, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * v) / SR
    x = np.zeros(n)
    for k, a in enumerate([1.0, 0.04, 0.55, 0.05, 0.3, 0.03, 0.14, 0.02, 0.07], start=1):
        if f * k < SR / 2.3:
            x += a * np.sin(k * ph)
    x += lp(hp(rng.standard_normal(n), 1800), 5000) * 0.03
    return x * env_adsr(n, 0.05, 0.1, 0.85, 0.12, n_of(dur)) * vol


def pizz(f, dur, rng, vol=1.0):
    x = guitar(f, 0.3, rng, 0.2)
    return x * np.exp(-_t(len(x)) * 4.5) * vol


def trem(f, dur, rng, vol=1.0, rate=13.0):
    """Балалаечное тремоло: частые щипки одной струны."""
    one = guitar(f, 0.2, rng, 0.85)[:n_of(0.4)]
    one *= np.exp(-_t(len(one)) * 6)
    n = n_of(dur + 0.4)
    x = np.zeros(n)
    k = 0
    while k / rate < dur:
        p = n_of(k / rate + rng.uniform(0, 0.006))
        m = min(len(one), n - p)
        x[p:p + m] += one[:m] * (1.0 if k % 2 == 0 else 0.72)
        k += 1
    return x * vol * 0.6


def sleigh(rng, vol=1.0):
    n = n_of(0.3)
    x = np.zeros(n)
    for _ in range(5):
        o = n_of(rng.uniform(0, 0.018))
        f = rng.uniform(2600, 6800)
        y = partials(f, n - o, [1, 1.42, 2.3], [1, 0.5, 0.3], [28, 34, 40], rng)
        x[o:] += y
    x += hp(rng.standard_normal(n), 6000) * np.exp(-_t(n) * 35) * 0.5
    return x * vol * 0.25


def crackle(n, rng, vol=1.0):
    x = np.zeros(n)
    k = int(n / SR * 7)
    idx = rng.integers(0, n, k)
    x[idx] = rng.uniform(-1, 1, k) ** 3
    x = lp(x, 3500) * 3.0 + hp(rng.standard_normal(n), 2500) * 0.012
    return x * vol


def radio(x):
    return hp(lp(x, 3400, 2), 280, 2)


def timp(f, rng, vol=1.0):
    n = n_of(1.6)
    t = _t(n)
    fr = f * (1 + 0.03 * np.exp(-t * 8))
    x = np.sin(2 * np.pi * np.cumsum(fr) / SR) * np.exp(-t * 2.2) + 0.3 * np.sin(2 * np.pi * np.cumsum(fr * 1.5) / SR) * np.exp(-t * 4)
    x[:n_of(0.02)] += lp(rng.standard_normal(n_of(0.02)), 900) * 0.4
    return x * vol


def whistle(f, dur, rng, vol=1.0):
    n = n_of(dur + 0.3)
    t = _t(n)
    v = 1 + 0.007 * np.sin(2 * np.pi * 5.0 * t) * np.clip((t - 0.2) / 0.3, 0, 1)
    ph = 2 * np.pi * np.cumsum(f * v) / SR
    x = np.sin(ph) + 0.12 * np.sin(3 * ph)
    x += lp(hp(rng.standard_normal(n), 2000), 6000) * 0.03
    return x * env_adsr(n, 0.04, 0.1, 0.9, 0.12, n_of(dur)) * vol


# ---------------------------------------------------------------- сохранение

def finish(name, mix, room, damp, wet, q=4):
    L, R = mix.render(room, damp, wet)
    g.save(name, L, R, q)


def renorm(name, target=-17.5, q=4):
    out = os.path.join(g.OUT, name + ".ogg")
    det = subprocess.run(["ffmpeg", "-i", out, "-af", "volumedetect", "-f", "null", "-"], capture_output=True, text=True).stderr
    mean = float(det.split("mean_volume:")[1].split("dB")[0])
    if abs(mean - target) < 0.3:
        print(name, "громкость уже %.1f дБ" % mean)
        return
    with tempfile.NamedTemporaryFile(suffix=".ogg", delete=False) as tf:
        tmp = tf.name
    subprocess.run(["ffmpeg", "-loglevel", "error", "-y", "-i", out, "-af", "volume=%.2fdB,alimiter=limit=0.95" % (target - mean),
                    "-c:a", "libvorbis", "-q:a", str(q), tmp], check=True)
    os.replace(tmp, out)
    print(name, "громкость %.1f → %.1f дБ" % (mean, target))


# ---------------------------------------------------------------- общие партии

def bars(arr):
    """Такты: (доля начала, имя раздела, номер такта в разделе, тактов в разделе)."""
    for name, b0, nb, _ in arr.secs:
        k = int(round(nb / arr.bpb))
        for i in range(k):
            yield b0 + i * arr.bpb, name, i, k


def events(arr):
    out = []
    for name, b0, nb, evs in arr.secs:
        for e in evs:
            out.append((name,) + e)
    return out


def low_root(root, lo=36):
    return lo + (pc(root) - lo) % 12


def counter_line(arr, names, lo, hi, start, dur_beats=None, tag="подголосок"):
    """Подголосок: по тону аккорда на такт, плавным голосоведением."""
    out = []
    cur = start
    for name, b, nb, root, kind in events(arr):
        if name not in names:
            continue
        ct = set(tones(root, kind))
        cands = [m for m in range(lo, hi + 1) if m % 12 in ct and m != cur] or [cur]
        cur = nearest(cands, cur)
        out.append((b, dur_beats or nb, cur))
    return out


def third_below(notes, sc):
    out = []
    for t, d, m in notes:
        k = sc.index(nearest(sc, m))
        out.append((t, d, sc[max(0, k - 2)]))
    return out


def part_buf(mix, arr, inst, notes, legato=0.95, **kw):
    buf = np.zeros(mix.n)
    for t, d, m in notes:
        x = inst(mf(m), arr.D(t, d) * legato, mix.rng, **kw)
        p = n_of(arr.T(t))
        k = min(len(x), mix.n - p)
        if k > 0:
            buf[p:p + k] += x[:k]
    return buf


def licks(rng, n, pats, last="h rh"):
    out = []
    for i in range(n):
        out += rh(last if i == n - 1 else pats[int(rng.integers(0, len(pats)))])
    return out


# ---------------------------------------------------------------- 1. «Огни проспекта»

def music_estrada():
    A = [("D#", "maj7"), ("C", "m7"), ("F", "m7"), ("A#", "7"), ("G", "m7"), ("C", "7"), ("F", "m7"), ("A#", "7")]
    AE = A[:6] + [("F", "m7", 2), ("A#", "7", 2), ("D#", "6")]
    B = [("G#", "maj7"), ("A#", "7"), ("G", "m7"), ("C", "m7"), ("G#", "maj7"), ("G", "m7"), ("F", "m7"), ("A#", "7")]
    secs = [("intro", [("G#", "maj7"), ("A#", "7sus"), ("D#", "maj7"), ("A#", "7")]), ("A", A), ("AE", AE), ("B", B), ("AE2", AE),
            ("solo", A), ("pivot", [("B", "7")]), ("Aup", tr_chords(A, 1)), ("AEup", tr_chords(AE, 1)),
            ("outro", [("A", "maj7"), ("B", "7sus"), ("E", "maj9"), ("E", "maj9")])]
    arr = Arr(112, 4, secs, strong=(0, 2), rit=8, rit_amt=0.6)
    mix = Mix(arr.length(), 1311)
    rng = mix.rng
    sc, scu = scale("D#", "major"), scale("E", "major")
    bA, bAE, bB = arr.sec("A")[1], arr.sec("AE")[1], arr.sec("B")[1]
    motif = gen_phrase(arr, rng, bA, rh("q. e q q | h. e e | q. e q e e | w"), sc, 63, 80, 70)
    melA = motif + refit(arr, motif, 16, sc)
    melAE = vary(arr, shift_notes(motif, bAE - bA), rng, sc, 0.2) + refit(arr, motif, bAE - bA + 16, sc, pc("D#"))
    mB = gen_phrase(arr, rng, bB, rh("h q q | q. e h | e e e e q q | w"), sc, 65, 82, 75)
    melB = mB + refit(arr, mB, 16, sc, pc("F"))
    put(mix, arr, slead, melA, 0.15, 0.55, 0.3, 0.9)
    put(mix, arr, slead, melAE, 0.15, 0.55, 0.3, 0.9)
    put(mix, arr, epiano, melB, 0.2, 0.75, 0.35)
    put(mix, arr, brass, shift_notes(melB, 0, -12), -0.25, 0.3, 0.3, 0.9, tag="медь")
    bAE2 = arr.sec("AE2")[1]
    mAE2 = vary(arr, shift_notes(melAE, bAE2 - bAE), rng, sc, 0.25)
    put(mix, arr, slead, mAE2, 0.15, 0.5, 0.3, 0.9)
    put(mix, arr, brass, shift_notes(mAE2, 0, -12), -0.3, 0.3, 0.3, 0.88, tag="медь")
    bS = arr.sec("solo")[1]
    solo = gen_phrase(arr, rng, bS, licks(rng, 8, ["e e e e q e e", "q e e e e q", "e e q e e q", "q. e e e q", "h e e e e", "rq e e e e q"]),
                      sc, 67, 87, 75, leap=0.35)
    put(mix, arr, slead, solo, 0.3, 0.5, 0.35, 0.85, vib=0.011)
    bU, bEU = arr.sec("Aup")[1], arr.sec("AEup")[1]
    mU = vary(arr, shift_notes(melA, bU - bA, 1), rng, scu, 0.2)
    mEU = vary(arr, shift_notes(melAE, bEU - bAE, 1), rng, scu, 0.2)
    for mm in (mU, mEU):
        put(mix, arr, slead, mm, 0.15, 0.55, 0.3, 0.9)
        put(mix, arr, brass, shift_notes(mm, 0, -12), -0.3, 0.32, 0.3, 0.88, tag="медь")
    bO = arr.sec("outro")[1]
    put(mix, arr, slead, refit(arr, motif[:3], bO - bA, scu) + [(bO + 8, 8, 76)], 0.15, 0.5, 0.4, 0.95)
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 56)
        r2 = low_root(root, 33)
        if name in ("intro", "B", "outro", "pivot"):
            mix.add(polysynth([mf(m) for m in vc], arr.D(b, nb), rng, 0.8, 1500, a=0.3, r=0.8), arr.T(b), -0.1, 1.0, 0.5, "аккорды")
        if name not in ("intro", "outro"):
            for o in (0.0, 1.5, 2.5):
                if o < nb:
                    mix.add(polysynth([mf(m) for m in vc], arr.D(b + o, 0.45), rng, 0.8, 2600), arr.T(b + o), 0.3, 1.0, 0.3, "аккорды", 0.003)
        if name in ("intro", "outro"):
            mix.add(spluck(mf(r2), arr.D(b, nb) * 0.95, rng, 0.45, 0.5, sus=0.6), arr.T(b), 0.0, 1.0, 0.05, "бас")
        elif name == "B":
            for k, iv in enumerate([0, 7, 12, 10 if "7" in kind else 11]):
                if k < nb:
                    mix.add(spluck(mf(r2 + iv), arr.D(b + k, 0.9), rng, 0.45, 0.7, sus=0.4), arr.T(b + k), 0.0, 1.0, 0.05, "бас", 0.002)
        else:
            for k in range(int(nb * 2)):
                iv = [0, 12, 7, 12][k % 4]
                mix.add(spluck(mf(r2 + iv), arr.D(b + k / 2, 0.42), rng, 0.32 if k % 2 == 0 else 0.23, 0.9), arr.T(b + k / 2), 0.0, 1.0, 0.05, "бас", 0.002)
    for b, name, i, k in bars(arr):
        T = arr.T
        if name == "intro":
            for h in range(8):
                mix.add(hat(rng, 0.12 if h % 2 else 0.08), T(b + h / 2), 0.35, 1.0, 0.05, "ударные", 0.003)
            if i >= 2:
                mix.add(kick(rng, 0.7), T(b), 0, 1.0, 0.05, "ударные")
                mix.add(kick(rng, 0.7), T(b + 2), 0, 1.0, 0.05, "ударные")
            continue
        if name == "outro":
            if i < 2:
                mix.add(kick(rng, 0.6), T(b), 0, 1.0, 0.05, "ударные")
                mix.add(hat(rng, 0.1, True), T(b + 2.5), 0.35, 1.0, 0.1, "ударные")
            if i == 2:
                mix.add(crash(rng, 0.7, 4.0), T(b), -0.3, 1.0, 0.4, "ударные")
            continue
        if i == 0:
            mix.add(crash(rng, 0.6), T(b), -0.3, 1.0, 0.3, "ударные")
        mix.add(kick(rng, 0.8), T(b), 0, 1.0, 0.05, "ударные")
        mix.add(kick(rng, 0.75), T(b + 2), 0, 1.0, 0.05, "ударные")
        if i % 2 == 1:
            mix.add(kick(rng, 0.5), T(b + 2.5), 0, 1.0, 0.05, "ударные")
        fill = i == k - 1 and name != "outro"
        for q in (1, 3):
            if not (fill and q == 3):
                mix.add(clap(rng, 0.55), T(b + q), 0.05, 1.0, 0.25, "ударные", 0.002)
        step = 0.25 if name == "solo" else 0.5
        for h in range(int(4 / step)):
            tb = h * step
            if fill and tb >= 3:
                break
            mix.add(hat(rng, 0.13 if (tb % 1) else 0.09), T(b + tb), 0.35, 1.0, 0.05, "ударные", 0.002)
        if i % 2 == 1 and not fill:
            mix.add(hat(rng, 0.12, True), T(b + 3.5), 0.35, 1.0, 0.1, "ударные")
        if fill:
            for j, f in enumerate([220, 180, 145, 115]):
                mix.add(tom(f, rng, 0.45), T(b + 3 + j * 0.25), -0.4 + j * 0.25, 1.0, 0.3, "ударные")
    finish("music_estrada", mix, 0.78, 4200, 0.26)


# ---------------------------------------------------------------- 2. «Над заводской рекой»

def music_accwaltz():
    A = [("E", "m"), ("E", "m"), ("A", "m"), ("A", "m"), ("D", "7"), ("D", "7"), ("G", ""), ("G", ""),
         ("C", ""), ("C", ""), ("A", "m"), ("A", "m"), ("F#", "m7b5"), ("B", "7"), ("E", "m"), ("E", "m")]
    B = [("G", ""), ("G", ""), ("B", "m"), ("B", "m"), ("C", ""), ("C", ""), ("G", ""), ("G", ""),
         ("E", "7"), ("E", "7"), ("A", "m"), ("A", "m"), ("F#", "m7b5"), ("B", "7"), ("E", "m"), ("B", "7")]
    secs = [("intro", [("E", "m"), ("A", "m"), ("B", "7"), ("B", "7")]), ("A1", A), ("A2", A), ("B", B), ("A3", A),
            ("outro", [("A", "m"), ("A", "m"), ("E", "m"), ("B", "7"), ("E", "m"), ("E", "m")])]
    arr = Arr(88, 3, secs, strong=(0,), rit=10, rit_amt=0.9)
    mix = Mix(arr.length(), 1312)
    rng = mix.rng
    sc = scale("E", "minor")
    b1 = arr.sec("A1")[1]
    r8 = rh("h q | q q q | h q | h. | h q | q q q | q q q | h.")
    motif = gen_phrase(arr, rng, b1, r8, sc, 62, 81, 71, pc("B"))
    m1 = motif + refit(arr, motif, 24, sc, pc("E"))
    put(mix, arr, accordion, m1, 0.2, 1.1, 0.3, 0.93)
    b2 = arr.sec("A2")[1]
    m2 = vary(arr, shift_notes(m1, b2 - b1), rng, sc, 0.3)
    put(mix, arr, accordion, m2, 0.2, 1.05, 0.3, 0.93)
    put(mix, arr, strings, counter_line(arr, ["A2"], 55, 67, 59), -0.35, 0.4, 0.5, 0.97, tag="подголосок")
    bB = arr.sec("B")[1]
    mb = gen_phrase(arr, rng, bB, rh("q q q | h. | q q q | h q | q q q | h. | h q | h."), sc, 66, 84, 74, pc("D"))
    mB = mb + refit(arr, mb, 24, sc, pc("F#"))
    put(mix, arr, strings, mB, 0.25, 0.75, 0.45, 0.97)
    put(mix, arr, strings, shift_notes(third_below(mB, sc), 0, 0), -0.25, 0.3, 0.45, 0.97, tag="подголосок")
    b3 = arr.sec("A3")[1]
    m3 = vary(arr, shift_notes(m1, b3 - b1), rng, sc, 0.2)
    put(mix, arr, accordion, m3, 0.2, 1.05, 0.3, 0.93)
    put(mix, arr, strings, shift_notes(m3, 0, 12), -0.2, 0.28, 0.5, 0.97, tag="подголосок")
    bo = arr.sec("outro")[1]
    end = refit(arr, motif[:4], bo - b1, sc) + [(bo + 6, 3, 67), (bo + 9, 2, 66), (bo + 11, 1, 63), (bo + 12, 6, 64)]
    put(mix, arr, accordion, end, 0.2, 1.05, 0.35, 0.95)
    for name, b, nb, root, kind in events(arr):
        ns = voicing(root, kind, 55, top=3)
        lowr = low_root(root, 40)
        bassn = lowr if int(b / 3) % 2 == 0 else lowr + 7 - (12 if lowr + 7 > 52 else 0)
        if name == "outro" and b >= bo + 15:
            continue
        if name == "outro" and b >= bo + 12:
            mix.add(accordion(mf(lowr), arr.D(b, 6), rng, 1.0), arr.T(b), -0.2, 1.0, 0.3, "аккомп.")
            for m in ns:
                mix.add(accordion(mf(m), arr.D(b, 6), rng, 0.5), arr.T(b), -0.1, 1.0, 0.3, "аккомп.")
            continue
        mix.add(accordion(mf(bassn), arr.D(b, 0.9), rng, 1.0), arr.T(b), -0.2, 1.0, 0.2, "аккомп.", 0.003)
        mix.add(upright(mf(bassn - 12), arr.D(b, 1.2), rng, 0.9), arr.T(b), 0.0, 1.0, 0.1, "бас", 0.003)
        for k in (1, 2):
            for m in ns:
                mix.add(accordion(mf(m), arr.D(b + k, 0.5), rng, 0.42), arr.T(b + k), -0.1, 1.0, 0.25, "аккомп.", 0.003)
            if name in ("A2", "B", "A3"):
                mix.add(snare(rng, 0.4, brush=True), arr.T(b + k), 0.3, 1.0, 0.3, "щётки", 0.004)
        if name in ("B", "A3", "intro"):
            mix.add(pad([mf(m + 12) for m in ns], arr.D(b, nb), rng, 1000, 0.3), arr.T(b), 0.35, 1.0, 0.5, "пэд")
    finish("music_accwaltz", mix, 0.84, 3500, 0.34)


# ---------------------------------------------------------------- 3. «Тропинка к проходной»

def music_folk():
    A = [("D", ""), ("G", ""), ("D", ""), ("A", ""), ("D", ""), ("G", ""), ("A", ""), ("D", "")]
    B = [("B", "m"), ("B", "m"), ("G", ""), ("D", ""), ("E", "m"), ("G", ""), ("A", ""), ("A", "")]
    brk = [("G", ""), ("A", ""), ("D", ""), ("D", "")]
    secs = [("intro", A[:4]), ("A1", A), ("A2", A), ("B1", B), ("A3", A), ("brk", brk), ("A4", A), ("B2", B), ("A5", A), ("outro", brk)]
    arr = Arr(186, 6, secs, strong=(0, 3), rit=12, rit_amt=0.7)
    mix = Mix(arr.length(), 1313)
    rng = mix.rng
    sc = scale("D", "major")
    b1 = arr.sec("A1")[1]
    motif = gen_phrase(arr, rng, b1, rh("2 1 2 1 | 3 2 1 | 2 1 1 1 1 | 6"), sc, 62, 81, 69)
    mA = motif + refit(arr, motif, 24, sc, pc("D"))
    put(mix, arr, trem, mA, 0.25, 2.25, 0.3, 0.95, tag="балалайка")
    b2 = arr.sec("A2")[1]
    m2 = vary(arr, shift_notes(mA, b2 - b1), rng, sc, 0.3, split=2)
    put(mix, arr, flute, m2, 0.3, 0.5, 0.35, 0.92, tag="флейта")
    bb = arr.sec("B1")[1]
    mb = gen_phrase(arr, rng, bb, rh("3 3 | 2 1 2 1 | 3 2 1 | 6"), sc, 64, 83, 71)
    mB = mb + refit(arr, mb, 24, sc, pc("A"))
    put(mix, arr, flute, mB, 0.3, 0.5, 0.35, 0.92, tag="флейта")
    put(mix, arr, trem, third_below(mB, sc), -0.2, 1.88, 0.3, 0.95, tag="балалайка")
    b3 = arr.sec("A3")[1]
    m3 = vary(arr, shift_notes(mA, b3 - b1), rng, sc, 0.2, split=2)
    put(mix, arr, trem, m3, 0.25, 2.12, 0.3, 0.95, tag="балалайка")
    put(mix, arr, flute, shift_notes(m3, 0, 12), 0.35, 0.28, 0.4, 0.9, tag="флейта")
    b4 = arr.sec("A4")[1]
    m4 = vary(arr, shift_notes(mA, b4 - b1), rng, sc, 0.35, split=2)
    put(mix, arr, whistle, m4, 0.3, 0.32, 0.4, 0.92, tag="свист")
    put(mix, arr, trem, third_below(m4, sc), -0.2, 1.50, 0.3, 0.95, tag="балалайка")
    bb2 = arr.sec("B2")[1]
    mB2 = vary(arr, shift_notes(mB, bb2 - bb), rng, sc, 0.3, split=2)
    put(mix, arr, flute, mB2, 0.3, 0.5, 0.35, 0.92, tag="флейта")
    put(mix, arr, trem, shift_notes(mB2, 0, -12), -0.2, 1.75, 0.3, 0.95, tag="балалайка")
    b5 = arr.sec("A5")[1]
    m5 = vary(arr, shift_notes(mA, b5 - b1), rng, sc, 0.2, split=2)
    put(mix, arr, flute, shift_notes(m5, 0, 12), 0.35, 0.3, 0.4, 0.92, tag="флейта")
    put(mix, arr, trem, m5, 0.2, 2.25, 0.3, 0.95, tag="балалайка")
    bo = arr.sec("outro")[1]
    put(mix, arr, trem, refit(arr, motif[:4], bo - b1, sc) + [(bo + 12, 12, 74)], 0.25, 2.12, 0.35, 0.95, tag="балалайка")
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 52)
        lr = low_root(root, 40)
        last = name == "outro" and b >= bo + 12
        pat = [lr, vc[0], vc[1], vc[2], vc[1], vc[0]]
        for k, m in enumerate(pat if not last else pat[:1] + vc + [vc[0] + 12]):
            mix.add(guitar(mf(m), arr.D(b + k, 1.5), rng, 0.5), arr.T(b + k), -0.35, 0.5 if k else 0.62, 0.25, "гитара", 0.004)
        if name not in ("intro", "A1", "brk"):
            mix.add(bass(mf(lr - 12 if lr > 45 else lr), arr.D(b, 2.6), rng, 0.32, 0.3), arr.T(b), 0, 1.0, 0.1, "бас", 0.003)
            if not last:
                mix.add(bass(mf(lr - 5 if lr > 45 else lr + 7), arr.D(b + 3, 2.4), rng, 0.26, 0.3), arr.T(b + 3), 0, 1.0, 0.1, "бас", 0.003)
        if name in ("A2", "B1", "A3", "A4", "B2", "A5"):
            for k in (0, 2, 3, 5):
                mix.add(hat(rng, 0.18 if k in (0, 3) else 0.12), arr.T(b + k), 0.45, 1.0, 0.1, "бубен", 0.004)
            mix.add(snare(rng, 0.25, brush=True), arr.T(b + 3), 0.2, 1.0, 0.2, "бубен", 0.004)
            mix.add(kick(rng, 0.35), arr.T(b), 0, 1.0, 0.1, "бубен")
        if name in ("B1", "B2", "A5"):
            mix.add(pad([mf(m + 12) for m in vc], arr.D(b, nb), rng, 1300, 0.16), arr.T(b), 0.0, 1.0, 0.5, "пэд")
    finish("music_folk", mix, 0.8, 4000, 0.3)


# ---------------------------------------------------------------- 4. «Литейный цех»

def music_foundry():
    P = [("C#", "5")] * 8
    A = [("C#", "m"), ("C#", "m"), ("D", ""), ("C#", "m"), ("C#", "m"), ("C#", "m"), ("A", ""), ("G#", "7")]
    B = [("F#", "m"), ("F#", "m"), ("D", ""), ("D", ""), ("C#", "m"), ("C#", "m"), ("D", ""), ("G#", "7")]
    secs = [("intro", P), ("A1", A), ("B1", B), ("brk", P), ("A2", A), ("B2", B), ("outro", P)]
    arr = Arr(96, 4, secs, strong=(0, 2), rit=4, rit_amt=0.3)
    mix = Mix(arr.length(), 1314)
    rng = mix.rng
    sc = scale("C#", "phryg")
    T = arr.T
    for name, b0, nb, _ in arr.secs:
        lvl = {"intro": 0.5, "outro": 0.55, "brk": 0.45}.get(name, 0.38)
        mix.add(drone([mf(37), mf(44), mf(49)], arr.D(b0, nb) + 1.0, rng, lvl, 0.05 + 0.03 * rng.random()), T(b0) - 0.5, 0.0, 1.0, 0.4, "гул")
    b1 = arr.sec("A1")[1]
    horn = gen_phrase(arr, rng, b1, rh("rw | q. e h | rw | q q h | rw | q. e h | rw | h h"), sc, 56, 70, 61)
    put(mix, arr, brass, horn, -0.25, 0.32, 0.45, 0.9, tag="медь")
    b2 = arr.sec("A2")[1]
    put(mix, arr, brass, vary(arr, shift_notes(horn, b2 - b1), rng, sc, 0.3), -0.25, 0.32, 0.45, 0.9, tag="медь")
    bB = arr.sec("B1")[1]
    lead = gen_phrase(arr, rng, bB, rh("h q q | w | h. q | w | h q q | w | h h | w"), sc, 61, 76, 68)
    put(mix, arr, slead, lead, 0.2, 0.42, 0.45, 0.95, vib=0.004, odd=False)
    bB2 = arr.sec("B2")[1]
    l2 = vary(arr, shift_notes(lead, bB2 - bB), rng, sc, 0.25)
    put(mix, arr, slead, l2, 0.2, 0.42, 0.45, 0.95, vib=0.004, odd=False)
    put(mix, arr, strings, shift_notes(l2, 0, -12), -0.3, 0.3, 0.5, 0.97, tag="струнные")
    bk = arr.sec("brk")[1]
    bell = gen_phrase(arr, rng, bk, rh("e e e e h | w | e e e e h | w | e e q e e q | w | e e e e h | w"), sc, 73, 88, 80, pc("C#"), leap=0.4)
    for dl, vv in ((0.0, 0.32), (0.75, 0.16), (1.5, 0.08)):
        put(mix, arr, glock, shift_notes(bell, dl), 0.4 - dl * 0.5, vv, 0.6, tag="колокольцы")
    for name, b, nb, root, kind in events(arr):
        if name in ("A1", "B1", "A2", "B2"):
            mix.add(polysynth([mf(m) for m in voicing(root, kind, 52)], arr.D(b, nb), rng, 0.22, 900, a=0.6, r=1.0), T(b), 0.1, 1.0, 0.5, "пэд")
        if name in ("B1", "A2", "B2"):
            r1 = low_root(root, 30)
            for k in range(8):
                mix.add(spluck(mf(r1 + (12 if k in (3, 6) else 0)), arr.D(b + k / 2, 0.4), rng, 0.5 if k % 2 == 0 else 0.36, 0.5), T(b + k / 2), 0, 1.0, 0.05, "бас", 0.002)
    pipes = [mf(m) for m in (73, 74, 76, 80)]
    for b, name, i, k in bars(arr):
        if name in ("intro", "outro", "brk"):
            if rng.random() < (0.8 if name != "brk" else 0.4) and not (name == "outro" and i >= 6):
                mix.add(metal(pipes[int(rng.integers(0, 4))] / 2, rng, 0.22, 1.4, 3.0), T(b + int(rng.integers(0, 8)) / 2), rng.uniform(-0.7, 0.7), 1.0, 0.8, "металл")
            if i % 3 == 0:
                mix.add(steam(arr.D(b, 6), rng, 0.2), T(b + 1), rng.uniform(-0.6, 0.6), 1.0, 0.6, "пар")
            if name == "outro" and i < 4:
                mix.add(press(rng, 0.7 - 0.15 * i), T(b), 0, 1.0, 0.4, "пресс")
            continue
        full = name in ("A2", "B2")
        mix.add(press(rng, 0.9), T(b), 0, 1.0, 0.3, "пресс")
        if full or name == "B1":
            mix.add(press(rng, 0.6), T(b + 2), 0, 1.0, 0.3, "пресс")
        for st, pi in ((3, 0), (6, 1), (11, 2), (14, 3 if i % 2 else 1)):
            mix.add(metal(pipes[pi], rng, 0.3, 3.0, 1.6), T(b + st / 4), [-0.5, 0.4, -0.2, 0.6][pi], 1.0, 0.4, "металл", 0.002)
        if full:
            mix.add(metal(1450, rng, 0.28, 5.0, 1.4), T(b + 2.5), 0.25, 1.0, 0.35, "металл")
        if name in ("B1", "B2", "A2"):
            for h in range(8):
                mix.add(hat(rng, 0.08 if h % 2 else 0.05), T(b + h / 2), 0.5, 1.0, 0.1, "металл", 0.002)
        if i % 4 == 2:
            mix.add(steam(arr.D(b, 4), rng, 0.16), T(b + 1), rng.uniform(-0.6, 0.6), 1.0, 0.5, "пар")
    finish("music_foundry", mix, 0.86, 3200, 0.4)


# ---------------------------------------------------------------- 5. «Буфет на втором этаже»

def music_jazz():
    A = [("F", "maj7"), ("D", "7"), ("G", "m7"), ("C", "7"), ("A", "m7", 2), ("D", "7", 2), ("G", "m7", 2), ("C", "7", 2),
         ("F", "6"), ("G", "m7", 2), ("C", "7", 2)]
    A2 = A[:8] + [("F", "6"), ("F", "6")]
    B = [("C", "m7"), ("F", "7"), ("A#", "maj7"), ("A#", "maj7"), ("D", "m7"), ("G", "7"), ("G", "m7"), ("C", "7")]
    secs = [("intro", [("G", "m7", 2), ("C", "7", 2)] * 4), ("hA1", A), ("hA2", A2), ("hB", B), ("hA3", A2),
            ("sA1", A), ("sA2", A2), ("sB", B), ("sA3", A2), ("oA", A2),
            ("outro", [("G", "m7", 2), ("C", "7", 2), ("A", "m7", 2), ("D", "7", 2), ("G", "m7", 2), ("C", "7", 2), ("F", "maj9", 8)])]
    arr = Arr(132, 4, secs, strong=(0, 2), swing=0.16, rit=8, rit_amt=0.7)
    mix = Mix(arr.length(), 1315)
    rng = mix.rng
    sc = scale("F", "major")
    T = arr.T
    r8 = rh("q. e q q | h. rq | q e e q q | h rh | q. e q q | h q q | q. e h | w")
    b1 = arr.sec("hA1")[1]
    h1 = gen_phrase(arr, rng, b1, r8, sc, 65, 84, 72, pc("E"))
    b2 = arr.sec("hA2")[1]
    h2 = shift_notes([n for n in h1 if n[0] < b1 + 16], b2 - b1) + refit(arr, [n for n in h1 if n[0] >= b1 + 16], b2 - b1, sc, pc("F"))
    bB = arr.sec("hB")[1]
    hb = gen_phrase(arr, rng, bB, rh("h. q | q q h | h. q | w | h. q | q q h | q q q q | w"), sc, 67, 86, 74, pc("E"))
    b3 = arr.sec("hA3")[1]
    h3 = vary(arr, shift_notes(h2, b3 - b2), rng, sc, 0.25)
    for mm in (h1, h2, hb, h3):
        put(mix, arr, clarinet, mm, 0.15, 0.6, 0.3, 0.92, tag="кларнет")
    put(mix, arr, vibes, shift_notes(h3, 0, 12), -0.3, 0.18, 0.35, tag="вибрафон")
    pats = ["e e e e e e q", "q e e e e q", "e e q e e q", "q. e e e q", "h e e e e", "e e e e h", "rq e e e e q", "e e e e e e e e"]
    for nm in ("sA1", "sA2", "sB", "sA3"):
        b0, nb = arr.sec(nm)[1], arr.sec(nm)[2]
        solo = gen_phrase(arr, rng, b0, licks(rng, int(nb / 4), pats), sc, 65, 89, 72 + int(rng.integers(0, 6)), leap=0.35)
        put(mix, arr, vibes, solo, -0.25, 0.42, 0.3, 0.9, tag="вибрафон")
    bo = arr.sec("oA")[1]
    ho = vary(arr, shift_notes(h2, bo - b2), rng, sc, 0.2)
    put(mix, arr, clarinet, ho, 0.15, 0.6, 0.3, 0.92, tag="кларнет")
    put(mix, arr, vibes, shift_notes(ho, 0, 12), -0.3, 0.15, 0.35, tag="вибрафон")
    bt = arr.sec("outro")[1]
    put(mix, arr, clarinet, refit(arr, h1[:4], bt - b1, sc) + [(bt + 12, 8, 77)], 0.15, 0.6, 0.35, 0.95, tag="кларнет")
    put(mix, arr, vibes, [(bt + 12 + k * 0.5, 4, m) for k, m in enumerate([65, 69, 72, 76, 79, 81])], -0.3, 0.22, 0.4, tag="вибрафон")
    evs = events(arr)
    cur = 41
    for j, (name, b, nb, root, kind) in enumerate(evs):
        nxt = evs[j + 1] if j + 1 < len(evs) else None
        rt = low_root(root, 29)
        ct = tones(root, kind)
        last = name == "outro" and nb == 8
        if last:
            mix.add(upright(mf(rt), arr.D(b, 6), rng, 0.8), T(b), 0, 1.0, 0.15, "бас")
        else:
            steps = [0, 2] if name == "intro" else list(range(int(nb)))
            for i in steps:
                if i == 0:
                    m = rt
                elif i == steps[-1] and nxt is not None:
                    nr = low_root(nxt[3], 29)
                    m = nr + (1 if rng.random() < 0.5 else -1)
                else:
                    cands = [x for x in range(28, 52) if x % 12 in ct[:3] and x != cur]
                    m = nearest(cands, cur + int(rng.integers(-3, 4)))
                cur = m
                dur = 2 if name == "intro" else 1
                mix.add(upright(mf(m), arr.D(b + i, dur) * 0.92, rng, 0.75 if i == 0 else 0.62), T(b + i), 0.0, 1.0, 0.12, "бас", 0.003)
        shell = sorted(set(voicing(root, kind, 53)) - ({voicing(root, kind, 53)[0]} if len(CH[kind]) > 3 else set()))
        opts = [[0.0], [0.5], [1.5], [0.0, 1.5], [1.5, 3.5], [0.5, 2.5]] if nb >= 4 else [[0.0], [0.5], [1.5], [0.0, 1.5]]
        offs = [0.0] if last else opts[int(rng.integers(0, len(opts)))]
        for o in offs:
            if o < nb:
                dur = arr.D(b + o, 6 if last else (0.9 if rng.random() < 0.5 else 0.45))
                for m in shell:
                    mix.add(piano(mf(m), dur, rng, 0.22 if name.startswith("s") else 0.17), T(b + o), 0.3, 1.0, 0.3, "рояль", 0.004)
    for b, name, i, k in bars(arr):
        if name == "outro" and i >= 3:
            if i == 3:
                mix.add(ride(rng, 0.6), T(b), 0.35, 1.0, 0.4, "щётки")
                mix.add(swish(arr.D(b, 4), rng, 0.6), T(b), -0.2, 1.0, 0.3, "щётки")
            continue
        solo = name.startswith("s")
        for q in range(4):
            if q % 2 == 0:
                mix.add(swish(arr.D(b + q, 2) * 0.9, rng, 0.55), T(b + q), -0.25, 1.0, 0.25, "щётки")
            else:
                mix.add(snare(rng, 0.14, brush=True), T(b + q), -0.1, 1.0, 0.25, "щётки", 0.003)
                mix.add(hat(rng, 0.05), T(b + q), 0.3, 1.0, 0.05, "щётки")
        if solo or name in ("hB", "oA"):
            for o in (0, 1, 1.5, 2, 3, 3.5):
                mix.add(ride(rng, 0.38 if o % 1 == 0 else 0.25), T(b + o), 0.4, 1.0, 0.2, "щётки", 0.003)
        if i == k - 1 and name != "intro":
            mix.add(snare(rng, 0.12), T(b + 3.5), 0.0, 1.0, 0.3, "щётки")
    finish("music_jazz", mix, 0.76, 4200, 0.25)


# ---------------------------------------------------------------- 6. «Ударная вахта»

def music_march2():
    A = [("D", ""), ("A", "7"), ("D", ""), ("G", ""), ("D", ""), ("B", "m"), ("E", "7"), ("A", "7")]
    A2 = [("D", ""), ("A", "7"), ("D", ""), ("G", ""), ("E", "m"), ("A", "7"), ("D", ""), ("D", "")]
    C = [("B", "m"), ("F#", "7"), ("B", "m"), ("E", "m"), ("G", ""), ("D", ""), ("E", "7"), ("A", "7")]
    TR = [("G", ""), ("D", "7"), ("G", ""), ("C", ""), ("G", ""), ("E", "7"), ("A", "7"), ("D", "7"),
          ("G", ""), ("D", "7"), ("G", ""), ("C", ""), ("C", "m"), ("G", ""), ("D", "7"), ("G", "")]
    secs = [("intro", [("D", ""), ("D", ""), ("A", "7"), ("A", "7")]), ("A1", A), ("A2", A2), ("C", C), ("A2b", A2),
            ("trio", TR), ("brk", [("A", "7"), ("A", "7")]), ("A3", A), ("A4", A2), ("coda", [("G", ""), ("A", "7"), ("D", ""), ("D", "")])]
    arr = Arr(124, 4, secs, strong=(0, 2), rit=6, rit_amt=0.5)
    mix = Mix(arr.length(), 1316)
    rng = mix.rng
    sc, sct = scale("D", "major"), scale("G", "major")
    T = arr.T
    fan = gen_phrase(arr, rng, 0, rh("t t t h q | h h | t t t h q | w"), sc, 62, 81, 69, pc("E"), leap=0.5)
    put(mix, arr, brass, fan, 0.1, 0.45, 0.35, 0.85, tag="медь")
    put(mix, arr, brass, shift_notes(fan, 0, -12), -0.2, 0.25, 0.35, 0.85, tag="медь")
    b1 = arr.sec("A1")[1]
    motif = gen_phrase(arr, rng, b1, rh("q q q. e | h h | q e e q q | h. rq"), sc, 66, 86, 74)
    mA = motif + refit(arr, motif, 16, sc)
    b2 = arr.sec("A2")[1]
    mA2 = vary(arr, shift_notes(motif, b2 - b1), rng, sc, 0.15) + refit(arr, motif, b2 - b1 + 16, sc, pc("D"))
    put(mix, arr, brass, mA, 0.1, 0.5, 0.3, 0.88, tag="медь")
    put(mix, arr, brass, mA2, 0.1, 0.5, 0.3, 0.88, tag="медь")
    put(mix, arr, glock, shift_notes(mA2, 0, 12), 0.4, 0.14, 0.35, tag="колокольчики")
    bc = arr.sec("C")[1]
    mc = gen_phrase(arr, rng, bc, rh("h q q | q. e h | q q q q | w"), sc, 64, 84, 71)
    mC = mc + refit(arr, mc, 16, sc, pc("E"))
    put(mix, arr, brass, shift_notes(mC, 0, -12), -0.2, 0.5, 0.3, 0.9, tag="медь")
    put(mix, arr, flute, mC, 0.35, 0.3, 0.3, 0.88, tag="флейта")
    bb = arr.sec("A2b")[1]
    mAb = vary(arr, shift_notes(mA2, bb - b2), rng, sc, 0.2)
    put(mix, arr, brass, mAb, 0.1, 0.5, 0.3, 0.88, tag="медь")
    put(mix, arr, flute, shift_notes(mAb, 0, 12), 0.35, 0.18, 0.3, 0.88, tag="флейта")
    bt = arr.sec("trio")[1]
    tm = gen_phrase(arr, rng, bt, rh("h. q | q q h | h q q | w"), sct, 64, 83, 71)
    trio = tm + refit(arr, tm, 16, sct, pc("F#")) + vary(arr, shift_notes(tm, 32), rng, sct, 0.25) + refit(arr, tm, 48, sct, pc("G"))
    put(mix, arr, flute, trio, 0.3, 0.45, 0.35, 0.92, tag="флейта")
    put(mix, arr, clarinet, shift_notes(trio, 0, -12), -0.1, 0.4, 0.35, 0.92, tag="кларнет")
    put(mix, arr, brass, counter_line(arr, ["trio"], 50, 62, 55)[8:], -0.35, 0.3, 0.4, 0.9, tag="медь")
    b3, b4 = arr.sec("A3")[1], arr.sec("A4")[1]
    for mm in (shift_notes(mA, b3 - b1), vary(arr, shift_notes(mA2, b4 - b2), rng, sc, 0.15)):
        put(mix, arr, brass, mm, 0.1, 0.55, 0.3, 0.88, tag="медь")
        put(mix, arr, flute, shift_notes(mm, 0, 12), 0.35, 0.2, 0.3, 0.88, tag="флейта")
        put(mix, arr, glock, shift_notes(mm, 0, 12), 0.45, 0.13, 0.35, tag="колокольчики")
    bk = arr.sec("coda")[1]
    put(mix, arr, brass, [(bk, 2, 71), (bk + 2, 2, 74), (bk + 4, 2, 73), (bk + 6, 2, 76), (bk + 8, 1, 74), (bk + 9.5, 0.5, 74), (bk + 10, 6, 74)],
        0.1, 0.55, 0.35, 0.9, tag="медь")
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 58, top=3)
        lr = low_root(root, 38)
        fin = name == "coda" and b >= bk + 8
        if fin:
            if b == bk + 8:
                for m in vc + [lr]:
                    mix.add(brass(mf(m), arr.D(b, 7), rng, 0.2), T(b), -0.2, 1.0, 0.4, "аккомп.")
                mix.add(brass(mf(lr - 12), arr.D(b, 7), rng, 0.5), T(b), 0, 1.0, 0.3, "туба")
            continue
        soft = name == "trio"
        mix.add(brass(mf(lr - 12), arr.D(b, 0.8), rng, 0.5), T(b), 0, 1.0, 0.2, "туба", 0.003)
        mix.add(brass(mf(lr - 5 if lr - 5 >= 33 else lr + 7 - 12), arr.D(b + 2, 0.8), rng, 0.45), T(b + 2), 0, 1.0, 0.2, "туба", 0.003)
        for q in (1, 3):
            for m in vc:
                mix.add((accordion if soft else brass)(mf(m), arr.D(b + q, 0.45), rng, 0.25 if soft else 0.11), T(b + q), -0.3, 1.0, 0.3, "аккомп.", 0.003)
    for b, name, i, k in bars(arr):
        if name == "coda" and i >= 2:
            if i == 2:
                mix.add(crash(rng, 0.9, 4.0), T(b), -0.2, 1.0, 0.4, "ударные")
                mix.add(kick(rng, 1.0), T(b), 0, 1.0, 0.2, "ударные")
                for r in range(24):
                    mix.add(snare(rng, 0.08 + 0.006 * r), T(b + 1 + r / 8), 0.15, 1.0, 0.2, "ударные")
                mix.add(timp(mf(38), rng, 0.9), T(b + 4), 0, 1.0, 0.3, "ударные")
                mix.add(crash(rng, 0.8, 4.0), T(b + 4), 0.3, 1.0, 0.4, "ударные")
            continue
        if name == "brk":
            for r in range(32):
                mix.add(snare(rng, 0.08 + 0.009 * r + (0.12 if r % 4 == 0 else 0)), T(b + r / 4 if i == 0 else b + r / 8), 0.15, 1.0, 0.2, "ударные")
                if i == 1 and r >= 15:
                    break
            mix.add(timp(mf(45), rng, 0.6 + 0.2 * i), T(b), 0, 1.0, 0.3, "ударные")
            continue
        if i == 0:
            mix.add(crash(rng, 0.6 if name != "trio" else 0.35), T(b), -0.3, 1.0, 0.3, "ударные")
        mix.add(kick(rng, 0.8), T(b), 0, 1.0, 0.2, "ударные")
        mix.add(kick(rng, 0.65), T(b + 2), 0, 1.0, 0.2, "ударные")
        if name == "trio" and i % 2 == 0 and i > 0:
            mix.add(crash(rng, 0.25, 1.2), T(b), 0.4, 1.0, 0.2, "ударные")
        roll = i % 4 == 3
        for e in range(8):
            if roll and e >= 6:
                break
            acc = e in (2, 6)
            mix.add(snare(rng, (0.32 if acc else 0.14) * (0.6 if name == "trio" else 1.0)), T(b + e / 2), 0.15, 1.0, 0.2, "ударные", 0.002)
        if roll:
            for r in range(4):
                mix.add(snare(rng, 0.14 + 0.05 * r), T(b + 3 + r / 4), 0.15, 1.0, 0.2, "ударные")
    finish("music_march2", mix, 0.8, 4000, 0.28)


# ---------------------------------------------------------------- 7. «Дождь над крышей цеха»

def music_rain():
    A = [("C#", "maj7"), ("A#", "m7"), ("F#", "maj7"), ("G#", "sus"), ("C#", "maj7"), ("F", "m7"), ("F#", "maj7"), ("G#", "7")]
    A2 = [("C#", "maj7"), ("A#", "m7"), ("F#", "maj7"), ("G#", "7"), ("F", "m7"), ("A#", "m7"), ("D#", "m7", 2), ("G#", "7", 2), ("C#", "maj9")]
    B = [("A#", "m9"), ("F", "m7"), ("F#", "maj7"), ("C#", "maj7"), ("D#", "m7"), ("A#", "m7"), ("F#", "maj7"), ("G#", "sus")]
    secs = [("intro", [("C#", "maj7"), ("F#", "maj7"), ("C#", "maj7"), ("F#", "maj7")]), ("A1", A), ("A2", A2), ("B", B), ("A3", A2),
            ("outro", [("F#", "maj7"), ("G#", "7sus"), ("C#", "maj9"), ("C#", "maj9")])]
    arr = Arr(66, 4, secs, strong=(0, 2), rit=8, rit_amt=0.8)
    mix = Mix(arr.length(), 1317)
    rng = mix.rng
    sc = scale("C#", "major")
    T = arr.T
    b1 = arr.sec("A1")[1]
    r4 = rh("h. q | q q h | h q q | w")
    motif = gen_phrase(arr, rng, b1, r4, sc, 63, 82, 68)
    m1 = motif + refit(arr, motif, 16, sc)
    b2 = arr.sec("A2")[1]
    m2 = vary(arr, shift_notes(motif, b2 - b1), rng, sc, 0.3) + refit(arr, motif, b2 - b1 + 16, sc, pc("C#"))
    bB = arr.sec("B")[1]
    mb = gen_phrase(arr, rng, bB, rh("q q q q | h. q | q. e q q | w"), sc, 65, 84, 77)
    mB = mb + refit(arr, mb, 16, sc, pc("D#"))
    b3 = arr.sec("A3")[1]
    m3 = vary(arr, shift_notes(m2, b3 - b2), rng, sc, 0.25)
    for mm in (m1, m2, mB, m3):
        put(mix, arr, piano, mm, 0.15, 0.62, 0.4, 1.0, tag="мелодия", vel=1.0)
    put(mix, arr, piano, shift_notes(m3, 0, 12), 0.3, 0.2, 0.45, 1.0, tag="мелодия", vel=1.0)
    put(mix, arr, strings, counter_line(arr, ["B", "A3"], 53, 66, 58), -0.35, 0.22, 0.55, 0.98, tag="струнные")
    bo = arr.sec("outro")[1]
    put(mix, arr, piano, refit(arr, motif[:2], bo - b1, sc) + [(bo + 8, 8, 72), (bo + 8.5, 7.5, 77)], 0.15, 0.55, 0.45, 1.0, tag="мелодия")
    for name, b, nb, root, kind in events(arr):
        R = low_root(root, 37)
        ivs = CH[kind]
        third = ivs[1]
        nine = 14
        pat = [R, R + 7, R + 12 + third, R + 7, R + nine, R + 7, R + 12 + third, R + 7]
        step = 1.0 if name == "outro" else 0.5
        cnt = int(nb / step)
        fin = name == "outro" and b >= bo + 8
        if fin:
            if b == bo + 8:
                for j, m in enumerate([R - 12, R, R + 7, R + 12 + third, R + 14, R + 19]):
                    mix.add(piano(mf(m), arr.D(b + j * 0.5, 7), rng, 0.3), T(b + j * 0.5), -0.15, 1.0, 0.5, "рояль")
            continue
        for k in range(cnt):
            m = pat[(k * (1 if step == 0.5 else 2)) % 8]
            mix.add(piano(mf(m), arr.D(b + k * step, 1.6), rng, 0.27 if k % 2 == 0 else 0.2), T(b + k * step), -0.2, 1.0, 0.4, "рояль", 0.006)
        if name in ("B", "A3"):
            mix.add(pad([mf(m) for m in voicing(root, kind, 56)], arr.D(b, nb), rng, 900, 0.3), T(b), 0.0, 1.0, 0.6, "пэд")
    drops = [m for m in range(82, 98) if m % 12 in {pc(x) for x in ("C#", "D#", "F", "G#", "A#")}]
    for b, name, i, k in bars(arr):
        if name in ("intro", "B", "outro"):
            for _ in range(int(rng.integers(1, 3))):
                mix.add(piano(mf(drops[int(rng.integers(0, len(drops)))]), 0.4, rng, 0.07), T(b + rng.uniform(0, 4)), rng.uniform(-0.8, 0.8), 1.0, 0.8, "капли")
    finish("music_rain", mix, 0.88, 3200, 0.42)


# ---------------------------------------------------------------- 8. «Ночной эфир»

def music_radio():
    A = [("B", "m9"), ("G", "maj7"), ("E", "m9"), ("F#", "7sus"), ("B", "m9"), ("G", "maj7"), ("E", "m7"), ("F#", "7")]
    B = [("D", "maj7"), ("A", "add9"), ("G", "maj7"), ("F#", "m7"), ("E", "m7"), ("G", "maj7"), ("E", "m7"), ("F#", "7")]
    secs = [("intro", [("B", "m9"), ("B", "m9")]), ("A1", A), ("B1", B), ("A2", A), ("C", [("G", "maj7"), ("E", "m9"), ("B", "m9"), ("F#", "7sus")]),
            ("A3", A), ("outro", [("B", "m9"), ("G", "maj7"), ("B", "m9"), ("B", "m9")])]
    arr = Arr(60, 4, secs, strong=(0, 2), rit=6, rit_amt=0.5)
    mix = Mix(arr.length(), 1318)
    rng = mix.rng
    sc = scale("B", "minor")
    T = arr.T
    bB = arr.sec("B1")[1]
    mb = gen_phrase(arr, rng, bB, rh("h. q | w | q q h | w | h. q | h h | q q h | w"), sc, 66, 81, 74)
    b3 = arr.sec("A3")[1]
    m3 = refit(arr, mb, b3 - bB, sc, pc("F#"))
    b2 = arr.sec("A2")[1]
    m2 = vary(arr, refit(arr, mb[:len(mb) // 2], b2 - bB + 16, sc), rng, sc, 0.3)
    lead = part_buf(mix, arr, epiano, mb + m2 + m3, 0.98, vel=1.0)
    mix.add(radio(lead), 0, 0.1, 0.5, 0.5, "мелодия")
    mix.add(radio(part_buf(mix, arr, whistle, shift_notes(m3, 0, 12), 0.98)), 0, -0.2, 0.12, 0.6, "мелодия")
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 54)
        mix.add(polysynth([mf(m) for m in vc], arr.D(b, nb) + 0.3, rng, 0.55, 1000, a=1.5, r=2.0), T(b), -0.15, 1.0, 0.6, "пэд")
        mix.add(pad([mf(m + 12) for m in vc[:3]], arr.D(b, nb), rng, 1400, 0.2), T(b), 0.3, 1.0, 0.6, "пэд")
        if name != "intro":
            mix.add(bass(mf(low_root(root, 33)), arr.D(b, nb) * 0.95, rng, 0.25, 0.0), T(b), 0, 1.0, 0.1, "бас")
        if name in ("A1", "A2", "A3", "C", "outro"):
            arp = vc + [m + 12 for m in vc]
            seq = arp if int(b / 4) % 2 == 0 else arp[::-1]
            step = 1.0 if name in ("C", "outro") else 0.5
            for k in range(int(nb / step)):
                mix.add(vibes(mf(seq[k % len(seq)] + 12), arr.D(b + k * step, 0.8), rng, 0.16), T(b + k * step), 0.5 if k % 2 else -0.5, 1.0, 0.55, "вибрафон", 0.004)
    for b, name, i, k in bars(arr):
        if name in ("A2", "B1", "A3"):
            for q in (1, 3):
                mix.add(snare(rng, 0.08, brush=True), T(b + q), 0.2, 1.0, 0.4, "щётки", 0.004)
                mix.add(swish(arr.D(b + q - 1, 1.6), rng, 0.12), T(b + q - 1), -0.3, 1.0, 0.4, "щётки")
            mix.add(kick(rng, 0.25), T(b), 0, 1.0, 0.1, "щётки")
            mix.add(kick(rng, 0.18), T(b + 2.5), 0, 1.0, 0.1, "щётки")
    n = mix.n
    cr = crackle(n, rng, 0.06)
    t = np.arange(n) / SR
    tune_n = n_of(8.0)
    f = 700 + 500 * np.sin(np.minimum(t[:tune_n], 8.0) / 8.0 * np.pi / 2)
    car = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t[:tune_n] * 0.5) * 0.05
    noise = radio(mix.rng.standard_normal(tune_n)) * 0.08 * np.exp(-t[:tune_n] * 0.6)
    cr[:tune_n] += car + noise
    mix.add(cr, 0, 0, 1.0, 0.05, "эфир")
    finish("music_radio", mix, 0.9, 2800, 0.45)


# ---------------------------------------------------------------- 9. «Первый снег»

def music_winter():
    A = [("A", ""), ("C#", "m"), ("D", ""), ("A", ""), ("F#", "m"), ("B", "m7"), ("E", ""), ("E", "7")]
    A2 = [("A", ""), ("C#", "m"), ("D", ""), ("A", ""), ("F#", "m"), ("B", "m7"), ("E", "7"), ("A", "")]
    B = [("F#", "m"), ("D", ""), ("A", ""), ("E", ""), ("B", "m"), ("C#", "7"), ("F#", "m"), ("E", "7")]
    secs = [("intro", [("A", ""), ("F#", "m"), ("D", ""), ("E", "")]), ("A1", A), ("A2", A2), ("B1", B), ("A3", A2), ("B2", B), ("A4", A2),
            ("outro", [("D", ""), ("E", ""), ("A", ""), ("A", "")])]
    arr = Arr(82, 4, secs, strong=(0, 2), rit=8, rit_amt=0.7)
    mix = Mix(arr.length(), 1319)
    rng = mix.rng
    sc = scale("A", "major")
    T = arr.T
    b1 = arr.sec("A1")[1]
    motif = gen_phrase(arr, rng, b1, rh("h q q | h. q | q q h | w"), sc, 69, 88, 76)
    mA = motif + refit(arr, motif, 16, sc)
    put(mix, arr, celesta, mA, 0.2, 0.55, 0.45, tag="челеста")
    b2 = arr.sec("A2")[1]
    mA2 = vary(arr, shift_notes(motif, b2 - b1, -12), rng, sc, 0.2) + refit(arr, motif, b2 - b1 + 16, sc, pc("A"), shift=-12)
    put(mix, arr, strings, mA2, 0.15, 0.5, 0.45, 0.97, tag="струнные")
    bB = arr.sec("B1")[1]
    mb = gen_phrase(arr, rng, bB, rh("q. e q q | h h | q. e q q | w"), sc, 66, 84, 73)
    mB = mb + refit(arr, mb, 16, sc, pc("G#"))
    put(mix, arr, flute, mB, 0.3, 0.42, 0.4, 0.92, tag="флейта")
    b3 = arr.sec("A3")[1]
    m3 = vary(arr, shift_notes(mA2, b3 - b2, 12), rng, sc, 0.2)
    put(mix, arr, strings, shift_notes(m3, 0, -12), 0.1, 0.45, 0.45, 0.97, tag="струнные")
    put(mix, arr, glock, m3, 0.4, 0.15, 0.45, tag="колокольчики")
    bB2 = arr.sec("B2")[1]
    mB2 = vary(arr, shift_notes(mB, bB2 - bB), rng, sc, 0.25)
    put(mix, arr, clarinet, shift_notes(mB2, 0, -12), -0.2, 0.42, 0.4, 0.93, tag="кларнет")
    put(mix, arr, flute, third_below(mB2, sc), 0.35, 0.3, 0.4, 0.92, tag="флейта")
    b4 = arr.sec("A4")[1]
    m4 = vary(arr, shift_notes(mA2, b4 - b2, 12), rng, sc, 0.15)
    put(mix, arr, strings, shift_notes(m4, 0, -12), 0.1, 0.5, 0.45, 0.97, tag="струнные")
    put(mix, arr, celesta, m4, 0.35, 0.4, 0.45, tag="челеста")
    put(mix, arr, flute, m4, 0.3, 0.2, 0.4, 0.92, tag="флейта")
    bo = arr.sec("outro")[1]
    put(mix, arr, celesta, refit(arr, motif[:3], bo - b1, sc) + [(bo + 8, 8, 81)], 0.25, 0.5, 0.5, tag="челеста")
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 76, top=3)
        lr = low_root(root, 38)
        fin = name == "outro" and b >= bo + 8
        if fin:
            if b == bo + 8:
                for j, m in enumerate([vc[0], vc[1], vc[2], vc[0] + 12]):
                    mix.add(celesta(mf(m), 1.0, rng, 0.18), T(b + j * 0.5), 0.3, 1.0, 0.6, "остинато")
                mix.add(strings(mf(lr), arr.D(b, 7), rng, 0.3), T(b), 0, 1.0, 0.5, "струнные")
                mix.add(timp(mf(lr - 12 + 12 * (lr < 40)), rng, 0.6), T(b), 0, 1.0, 0.4, "литавры")
            continue
        pat = [vc[0], vc[1], vc[2], vc[0] + 12, vc[2], vc[1], vc[0], vc[1]]
        ov = 0.24 if name in ("intro", "A2", "B1", "outro") else 0.14
        for k in range(8):
            mix.add(celesta(mf(pat[k]), 0.4, rng, ov), T(b + k / 2), -0.35, 1.0, 0.45, "остинато", 0.003)
        if name != "intro":
            mix.add(pizz(mf(lr), 0.5, rng, 0.75), T(b), 0, 1.0, 0.25, "пиццикато", 0.003)
            mix.add(pizz(mf(lr + 7), 0.5, rng, 0.6), T(b + 2), 0, 1.0, 0.25, "пиццикато", 0.003)
            mix.add(upright(mf(lr - 12 if lr >= 45 else lr), arr.D(b, 1.8), rng, 0.45), T(b), 0, 1.0, 0.15, "бас", 0.003)
            mix.add(upright(mf(lr - 5 if lr >= 45 else lr + 7), arr.D(b + 2, 1.8), rng, 0.38), T(b + 2), 0, 1.0, 0.15, "бас", 0.003)
        if name in ("A2", "A3", "B2", "A4", "B1"):
            mix.add(strings(mf(voicing(root, kind, 57)[0]), arr.D(b, nb), rng, 0.15), T(b), -0.3, 1.0, 0.5, "струнные")
            mix.add(strings(mf(voicing(root, kind, 57)[1]), arr.D(b, nb), rng, 0.15), T(b), 0.3, 1.0, 0.5, "струнные")
        if name in ("A3", "B2", "A4"):
            for k in range(8):
                mix.add(sleigh(rng, 0.5 if k % 2 == 0 else 0.3), T(b + k / 2), 0.5, 1.0, 0.3, "бубенцы", 0.003)
    for b, name, i, k in bars(arr):
        if i == 0 and name not in ("intro", "outro"):
            mix.add(timp(mf(low_root(arr.chord_at(b)[0], 38) - 12 + 12), rng, 0.5), T(b), 0, 1.0, 0.4, "литавры")
    finish("music_winter", mix, 0.88, 4200, 0.4)


# ---------------------------------------------------------------- 10. «Утренний автобус»

def music_dawn():
    A = [("G", ""), ("F", ""), ("C", ""), ("G", ""), ("G", ""), ("F", ""), ("C", ""), ("D", "")]
    B = [("E", "m7"), ("C", ""), ("G", ""), ("D", ""), ("E", "m7"), ("C", ""), ("A", "m7"), ("D", "")]
    secs = [("intro", [("G", ""), ("G", ""), ("F", ""), ("G", "")]), ("A1", A), ("B1", B), ("A2", A), ("brk", [("C", ""), ("C", ""), ("D", ""), ("D", "")]),
            ("B2", B), ("A3", A), ("outro", A[:7] + [("G", "")])]
    arr = Arr(104, 4, secs, strong=(0, 2), rit=4, rit_amt=0.3)
    mix = Mix(arr.length(), 1320)
    rng = mix.rng
    sc = scale("G", "mixo")
    T = arr.T
    b1 = arr.sec("A1")[1]
    motif = gen_phrase(arr, rng, b1, rh("q. e q q | h h | q. e q e e | w"), sc, 64, 83, 71)
    mA = motif + refit(arr, motif, 16, sc, pc("A"))
    put(mix, arr, slead, mA, 0.2, 0.6, 0.35, 0.9, vib=0.004, odd=False)
    bB = arr.sec("B1")[1]
    mb = gen_phrase(arr, rng, bB, rh("h q q | h q q | q q q q | w"), sc, 67, 86, 76)
    mB = mb + refit(arr, mb, 16, sc, pc("F#"))
    put(mix, arr, epiano, mB, -0.2, 0.7, 0.4, tag="электропиано")
    b2 = arr.sec("A2")[1]
    m2 = vary(arr, shift_notes(mA, b2 - b1), rng, sc, 0.25)
    put(mix, arr, whistle, m2, 0.25, 0.5, 0.4, 0.9, tag="свист")
    bB2 = arr.sec("B2")[1]
    mB2 = vary(arr, shift_notes(mB, bB2 - bB), rng, sc, 0.25)
    put(mix, arr, epiano, mB2, -0.2, 0.7, 0.4, tag="электропиано")
    put(mix, arr, whistle, shift_notes(third_below(mB2, sc), 0, 0), 0.3, 0.25, 0.45, 0.9, tag="свист")
    b3 = arr.sec("A3")[1]
    m3 = vary(arr, shift_notes(mA, b3 - b1), rng, sc, 0.2)
    put(mix, arr, whistle, m3, 0.25, 0.5, 0.4, 0.9, tag="свист")
    put(mix, arr, slead, shift_notes(m3, 0, -12), -0.2, 0.25, 0.35, 0.9, vib=0.004, odd=False)
    bo = arr.sec("outro")[1]
    nbo = arr.sec("outro")[2]
    put(mix, arr, whistle, refit(arr, motif, bo - b1, sc) + [(bo + 28, 4, 74)], 0.25, 0.35, 0.5, 0.9, tag="свист")
    for name, b, nb, root, kind in events(arr):
        vc = voicing(root, kind, 50, top=3)
        b0s = arr.sec(name)[1]
        prog = (b - b0s) / arr.sec(name)[2]
        bright = {"intro": 0.25 + 0.75 * prog, "outro": 1.0 - 0.75 * prog, "brk": 0.45}.get(name, 1.0)
        seq = [vc[0], vc[0] + 12, vc[2], vc[0] + 12, vc[1], vc[0] + 12, vc[2], vc[1] + 12] * 2
        for k in range(16):
            acc = 1.3 if k in (0, 3, 6, 10, 12) else 1.0
            mix.add(spluck(mf(seq[k] + 12), arr.D(b + k / 4, 0.22), rng, 0.13 * acc, bright), T(b + k / 4), 0.3 if k % 2 else -0.3, 1.0, 0.3, "секвенсор")
        if name not in ("intro", "brk") and not (name == "outro" and prog >= 0.5):
            r2 = low_root(root, 31)
            for k in range(8):
                mix.add(spluck(mf(r2 + (12 if k % 4 == 3 else 0)), arr.D(b + k / 2, 0.4), rng, 0.32 if k % 2 else 0.22, 0.5), T(b + k / 2), 0, 1.0, 0.05, "бас", 0.002)
        if name in ("B1", "B2", "brk", "A3"):
            mix.add(pad([mf(m + 12) for m in vc], arr.D(b, nb), rng, 1600, 0.35), T(b), 0.1, 1.0, 0.5, "синт-струнные")
    for b, name, i, k in bars(arr):
        if name in ("intro",) or (name == "outro" and i >= 4):
            continue
        brk = name == "brk"
        for q in range(4):
            if not brk:
                mix.add(kick(rng, 0.55), T(b + q), 0, 1.0, 0.05, "ударные")
            if q % 2 == 1 and not brk:
                mix.add(clap(rng, 0.35), T(b + q), 0.1, 1.0, 0.3, "ударные", 0.002)
            mix.add(hat(rng, 0.13), T(b + q + 0.5), 0.4, 1.0, 0.05, "ударные", 0.002)
        if i == 0 and not brk:
            mix.add(crash(rng, 0.4), T(b), -0.3, 1.0, 0.3, "ударные")
    finish("music_dawn", mix, 0.8, 4200, 0.3)


TRACKS = [music_estrada, music_accwaltz, music_folk, music_foundry, music_jazz, music_march2, music_rain, music_radio, music_winter, music_dawn]

if __name__ == "__main__":
    only = sys.argv[1:]
    for fn in TRACKS:
        if not only or fn.__name__ in only:
            print(fn.__name__)
            fn()
    if not only or "renorm" in only:
        renorm("music_calm")
        renorm("music_waltz")
