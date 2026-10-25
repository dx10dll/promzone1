#!/usr/bin/env python3
"""1.45 «Классика»: 14 оригинальных пьес «в духе» классических жанров для «Промзоны».

Все ноты сочиняет этот скрипт (ни одной чужой ноты и ни одного чужого MIDI): гармония задана римскими цифрами
(побочные доминанты, модуляции, неаполитанский секстаккорд, ундецимы, целотонный и пентатонный лады), мелодия строится
мотивом, секвенциями и каденциями; фактура (вальс, ноктюрн, марш, прелюдия, жимнопедия, баркарола, полонез…) и
оркестровка по группам — отдельные функции. MIDI пишется вручную, звук — fluidsynth + FluidR3_GM (MIT, Frank Wen).

Запуск (из корня проекта):  python3 tools/gen_music_145.py [имя ...] [--midi-only]
Нужны: python3 (numpy не нужен), fluidsynth + fluid-soundfont-gm, ffmpeg.
Рендер: fluidsynth -ni -g 0.6 -r 44100 → ffmpeg: обрезка тишины в начале, хвост, нормализация ≈ −17,5 дБ (mean), ogg vorbis q5.
Фразы (PHRASE в music_director.gd) печатаются в конце.
"""
import os
import random
import re
import struct
import subprocess
import sys
import tempfile

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "sound")
SF2 = "/usr/share/sounds/sf2/FluidR3_GM.sf2"
TPQ = 480
TARGET_DB = -17.5

# ------------------------------------------------------------------ теория

MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]
NOTE_PC = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def pc_of(name):
    """'Eb' -> 3, 'F#' -> 6."""
    v = NOTE_PC[name[0]]
    for c in name[1:]:
        v += 1 if c == "#" else -1
    return v % 12


class Key:
    def __init__(self, tonic, mode="maj"):
        self.t = pc_of(tonic)
        self.minor = mode == "min"
        self.sc = MIN if self.minor else MAJ

    def scale_pcs(self, raised7=False):
        s = list(self.sc)
        if self.minor and raised7:
            s[6] = 11
        return [(self.t + x) % 12 for x in s]


ROMAN = re.compile(r"^(b|#)?(VII|VI|IV|V|III|II|I|vii|vi|iv|v|iii|ii|i)(o|\+|ø)?(7|M7|6|9|add9|sus4)?(?:/(\S+))?$")
DEG = {"i": 0, "ii": 1, "iii": 2, "iv": 3, "v": 4, "vi": 5, "vii": 6}
QUAL = {"": [0, 4, 7], "m": [0, 3, 7], "o": [0, 3, 6], "+": [0, 4, 8], "ø": [0, 3, 6, 10]}


class Chord:
    def __init__(self, root, ivs, bass_iv=0, key=None, dom=False):
        self.root = root % 12
        self.ivs = ivs
        self.pcs = [(root + i) % 12 for i in ivs]
        self.bass_pc = (root + bass_iv) % 12
        self.key = key
        self.dom = dom   # доминантовая функция: в миноре поднимаем VII ступень в мелодии

    def __repr__(self):
        return "Chord(%d %s)" % (self.root, self.ivs)


def roman(sym, key):
    """'V7/V', 'bII', 'vii°7' (как 'viio7' не поддерживаем: 'viio' + '7'), инверсия через _3 / _5 / _7 (бас)."""
    inv = 0
    if "_" in sym:
        sym, i = sym.split("_")
        inv = int(i)
    m = ROMAN.match(sym)
    if not m:
        raise ValueError("римская цифра? " + sym)
    acc, deg, q, ext, tgt = m.groups()
    k = key
    if tgt:
        tchord = roman(tgt, key)
        k = Key(["C", "C#", "D", "Eb", "E", "F", "F#", "G", "Ab", "A", "Bb", "B"][tchord.root], "maj" if tchord.ivs[1] == 4 else "min")
    d = DEG[deg.lower()]
    minor_here = k.minor
    base = (MIN if minor_here else MAJ)[d]
    if minor_here and d == 6 and q in ("o", "ø") or (minor_here and d == 6 and deg == "vii" and q == "o"):
        base = 11
    root = k.t + base + (1 if acc == "#" else -1 if acc == "b" else 0)
    if q:
        ivs = list(QUAL[q])
    else:
        ivs = list(QUAL["" if deg.isupper() else "m"])
    if ext == "7":
        if q == "o":
            ivs = [0, 3, 6, 9]
        elif q == "ø":
            pass
        elif deg.isupper():
            ivs = ivs + [10]
        else:
            ivs = ivs + [10]
    elif ext == "M7":
        ivs = ivs + [11]
    elif ext == "6":
        ivs = ivs + [9]
    elif ext == "9":
        ivs = ivs + [10, 14] if deg.isupper() else ivs + [10, 14]
    elif ext == "add9":
        ivs = ivs + [14]
    elif ext == "sus4":
        ivs = [0, 5, 7]
    dom = bool(tgt) or (deg in ("V", "VII", "vii") and not (minor_here and deg == "VII" and not q))
    if minor_here and deg == "V":
        dom = True
        ivs = ivs[:] if ivs[1] == 4 else [0, 4, 7] + ivs[3:]
    if minor_here and deg == "v" and not q:
        ivs = [0, 4, 7] + ivs[3:]
        dom = True
    bass_iv = 0
    if inv:
        bass_iv = {3: ivs[1], 5: ivs[2], 7: ivs[3] if len(ivs) > 3 else ivs[0]}[inv]
    return Chord(root, ivs, bass_iv, key, dom)


def parse_bar(s, key, bar_len):
    """'I:2 V7:1' -> [(Chord, offset, dur)]"""
    toks = s.split()
    ws = []
    for t in toks:
        w = 1.0
        if ":" in t:
            t, w_s = t.rsplit(":", 1)
            w = float(w_s)
        ws.append((t, w))
    tot = sum(w for _, w in ws)
    out, off = [], 0.0
    for t, w in ws:
        d = bar_len * w / tot
        out.append((roman(t, key), off, d))
        off += d
    return out


# ------------------------------------------------------------------ MIDI

class Track:
    def __init__(self, name, prog, ch, vol=100, pan=64, rev=50):
        self.name, self.prog, self.ch, self.vol, self.pan, self.rev = name, prog, ch, vol, pan, rev
        self.notes = []   # (beat, dur, pitch, vel)
        self.ccs = []     # (beat, cc, val)

    def add(self, b, d, p, v):
        if d > 0.01 and 0 < p < 128:
            self.notes.append((b, d, int(p), int(max(1, min(127, v)))))


class Piece:
    def __init__(self, name, bpm, bpb=4.0):
        self.name, self.bpm, self.bpb = name, bpm, bpb
        self.tr = {}
        self.pos = 0.0
        self.rng = random.Random(hash(name) & 0xffff)
        self.rit = []        # (beat_from, beat_to, factor_at_end) - замедления
        self.tempo_mul = []  # (beat, mul) - смены темпа
        self.fermata = []
        self.marks = {}

    def track(self, name, prog, ch=None, vol=100, pan=64, rev=50):
        if name not in self.tr:
            if ch is None:
                used = {t.ch for t in self.tr.values()}
                ch = next(c for c in range(16) if c != 9 and c not in used)
            self.tr[name] = Track(name, prog, ch, vol, pan, rev)
        return self.tr[name]

    def drums(self, vol=95):
        if "drums" not in self.tr:
            self.tr["drums"] = Track("drums", 0, 9, vol, 64, 40)
        return self.tr["drums"]

    def tempo_at(self, beat):
        mul = 1.0
        for b, m in self.tempo_mul:
            if beat >= b:
                mul = m
        for a, b, f in self.rit:
            if a <= beat <= b:
                x = (beat - a) / max(0.001, b - a)
                mul *= 1 + (f - 1) * (x * x if f < 1 else x)
            elif beat > b:
                mul *= 1.0
        # лёгкое «дыхание» на границе фразы: к концу каждого такта-четвёрки чуть медленнее
        ph = (beat % (self.bpb * 4)) / (self.bpb * 4)
        if ph > 0.88 and not self.no_breath:
            mul *= 1 - 0.05 * (ph - 0.88) / 0.12
        return self.bpm * mul

    no_breath = False

    def write(self, path, end_beat):
        trks = []
        # tempo track
        ev = []
        b = 0.0
        while b <= end_beat + 1:
            us = int(60e6 / self.tempo_at(b))
            ev.append((int(b * TPQ), 0, b"\xff\x51\x03" + struct.pack(">I", us)[1:]))
            b += 0.5
        ev.append((int((end_beat + 1) * TPQ), 9, b"\xff\x2f\x00"))
        trks.append(ev)
        r = random.Random(7)
        for t in self.tr.values():
            ev = []
            ch = t.ch
            ev.append((0, 0, bytes([0xB0 | ch, 7, t.vol])))
            ev.append((0, 0, bytes([0xB0 | ch, 10, t.pan])))
            ev.append((0, 0, bytes([0xB0 | ch, 91, t.rev])))
            if ch != 9:
                ev.append((0, 0, bytes([0xC0 | ch, t.prog])))
            for b, cc, v in t.ccs:
                ev.append((int(b * TPQ), 1, bytes([0xB0 | ch, cc, max(0, min(127, int(v)))])))
            for b, d, p, v in t.notes:
                j = 0 if ch == 9 else r.uniform(-0.012, 0.012)
                on = max(0, int((b + j) * TPQ))
                off = max(on + 1, int((b + j + d) * TPQ))
                ev.append((on, 3, bytes([0x90 | ch, p, v])))
                ev.append((off, 2, bytes([0x80 | ch, p, 0])))
            ev.append((int((end_beat + 1) * TPQ), 9, b"\xff\x2f\x00"))
            trks.append(ev)
        data = b"MThd" + struct.pack(">IHHH", 6, 1, len(trks), TPQ)
        for ev in trks:
            ev.sort(key=lambda e: (e[0], e[1]))
            body = b""
            last = 0
            for tick, _, msg in ev:
                body += vlq(tick - last) + msg
                last = tick
            data += b"MTrk" + struct.pack(">I", len(body)) + body
        with open(path, "wb") as f:
            f.write(data)


def vlq(n):
    out = [n & 0x7f]
    n >>= 7
    while n:
        out.append((n & 0x7f) | 0x80)
        n >>= 7
    return bytes(reversed(out))


# ------------------------------------------------------------------ голосоведение

def nearest_pitch(pc, target):
    best = None
    for o in range(0, 11):
        p = o * 12 + pc
        if best is None or abs(p - target) < abs(best - target):
            best = p
    return best


def voice(chord, center, n, prev=None, span=14):
    """Расположение аккорда из n голосов около center с минимальным движением от prev."""
    pcs = list(dict.fromkeys(chord.pcs))
    cands = []
    lo, hi = center - span, center + span
    pool = sorted({p for pc in pcs for p in range(lo, hi + 1) if p % 12 == pc})
    if len(pool) < n:
        return pool
    import itertools
    best, bc = None, 1e9
    for comb in itertools.combinations(pool, n):
        have = {p % 12 for p in comb}
        need = set(pcs[:3]) if n >= 3 else {pcs[0]}
        if not need <= have and not (n >= 4 and len(pcs) > 3 and {pcs[0], pcs[1], pcs[2]} <= have):
            continue
        if comb[-1] - comb[0] > 17:
            continue
        gaps = [comb[i + 1] - comb[i] for i in range(n - 1)]
        if min(gaps) < 3 and n > 2:
            continue
        c = abs(sum(comb) / n - center) * 0.8
        if prev:
            m = min(len(prev), n)
            c += sum(abs(a - b) for a, b in zip(sorted(prev)[:m], comb[:m])) * 1.0
        if c < bc:
            best, bc = comb, c
    return list(best) if best else list(pool[:n])


def bass_note(chord, lo=36, hi=52, target=None):
    t = target if target else (lo + hi) // 2
    p = nearest_pitch(chord.bass_pc, t)
    while p > hi:
        p -= 12
    while p < lo:
        p += 12
    return p


# ------------------------------------------------------------------ мелодия

def scale_pitches(key, lo, hi, raised7):
    pcs = set(key.scale_pcs(raised7))
    return [p for p in range(lo, hi + 1) if p % 12 in pcs]


def gen_melody(rng, bars_ch, bpb, lo, hi, start, cells, endcells, motif=None, cad="auth", amp=7, rest_p=0.0,
               key=None, peak=0.65, step_bias=1.0):
    """bars_ch: [[(Chord, off, dur)...] на такт]. start: целевая высота первой ноты.
    cells: списки длительностей на такт (в четвертях); motif: [(dur, steps)] на первый такт (steps — ступени шкалы).
    Возвращает [(beat_in_phrase, dur, pitch)]."""
    nb = len(bars_ch)
    ring = lambda ch: [p for p in range(lo, hi + 1) if p % 12 in ch.pcs]
    def scl(ch):
        base = set(key.scale_pcs(ch.dom)) | set(ch.pcs)
        return [p for p in range(lo, hi + 1) if p % 12 in base]
    def chord_at(b):
        bi = min(nb - 1, int(b // bpb))
        off = b - bi * bpb
        for ch, o, d in bars_ch[bi]:
            if o - 1e-6 <= off < o + d - 1e-6:
                return ch
        return bars_ch[bi][-1][0]
    # ритм
    rhythm = []
    first = None
    for bi in range(nb):
        if bi == nb - 1 and nb > 1:
            c = rng.choice(endcells)
        elif motif and bi == 0:
            c = [d for d, _ in motif]
        elif bi == 1 and first and rng.random() < 0.7:
            c = first
        elif bi == 2 and motif and rng.random() < 0.45:
            c = [d for d, _ in motif]
        else:
            c = rng.choice(cells)
        if bi == 0:
            first = c
        t = bi * bpb
        for d in c:
            rhythm.append((t, d))
            t += d
    # целевая линия
    total = nb * bpb
    final_ch = chord_at(total - 0.01)
    cad_pc = {"auth": final_ch.root, "half": None, "open": None, "plag": final_ch.root}[cad] if cad in ("auth", "plag") else None
    notes = []
    prev = start
    prev_leap = 0
    for i, (t, d) in enumerate(rhythm):
        ch = chord_at(t)
        x = t / total
        # контур: старт -> пик -> конец
        if x < peak:
            tgt = start + amp * (x / peak) ** 0.8
        else:
            endt = start - 2 if cad in ("auth", "plag") else start + 1
            tgt = start + amp + (endt - start - amp) * ((x - peak) / (1 - peak))
        strong = abs((t % bpb) % 1.0) < 1e-6 and (t % bpb == 0 or (bpb % 3 == 0 and (t % bpb) % 1.5 == 0) or bpb in (4.0, 2.0) and (t % bpb) % 2 == 0 or (t % bpb) % 1.0 == 0 and d >= 1.0)
        last = i == len(rhythm) - 1
        pen = i == len(rhythm) - 2
        if motif and i < len(motif) and t < bpb:
            # мотив: ступени от стартовой высоты
            base_sc = scl(chord_at(0))
            s0 = min(base_sc, key=lambda p: abs(p - start))
            idx0 = base_sc.index(s0)
            j = max(0, min(len(base_sc) - 1, idx0 + motif[i][1]))
            p = base_sc[j]
            if strong and p % 12 not in ch.pcs:
                p = min(ring(ch) or [p], key=lambda q: abs(q - p))
            notes.append([t, d, p])
            prev_leap = p - prev
            prev = p
            continue
        if last:
            if cad == "half":
                opts = [q for q in ring(ch)]
                p = min(opts, key=lambda q: abs(q - (prev - 1)) + (0 if q % 12 == ch.root or q % 12 == ch.pcs[2] % 12 else 2))
            elif cad == "open":
                p = min(ring(ch), key=lambda q: abs(q - prev) + rng.random())
            else:
                # тоника: тоника аккорда, ближайшая к цели
                cands = [q for q in range(lo, hi + 1) if q % 12 == final_ch.root]
                if rng.random() < 0.35:
                    cands += [q for q in range(lo, hi + 1) if q % 12 == final_ch.pcs[1 if len(final_ch.pcs) > 1 else 0] and rng.random() < 0.0]
                p = min(cands, key=lambda q: abs(q - (prev if prev else start)))
        else:
            cand = ring(ch) if (strong or d >= 1.5) else scl(ch)
            if not cand:
                cand = scl(ch)
            best, bc = None, 1e9
            for q in cand:
                dd = q - prev
                c = abs(q - tgt) * 0.55 * step_bias
                if abs(dd) > 5:
                    c += (abs(dd) - 5) * 1.3
                if dd == 0:
                    c += 1.6
                if abs(dd) == 6:
                    c += 4
                if abs(prev_leap) > 4 and dd * prev_leap > 0:
                    c += 3
                if abs(prev_leap) > 4 and abs(dd) > 2:
                    c += 2
                if not strong and abs(dd) > 2:
                    c += 2.5
                if pen and cad != "open":
                    # подход к финалу ступенью
                    ft = min([q2 for q2 in range(lo, hi + 1) if q2 % 12 == final_ch.root] or [q], key=lambda z: abs(z - prev))
                    if cad == "half":
                        ft = prev
                    c += abs(abs(q - ft) - 2) * 0.8
                if q % 12 == 11 and key.minor and not ch.dom:
                    c += 3
                c += rng.random() * 1.4
                if c < bc:
                    best, bc = q, c
            p = best
        if rest_p and not last and not pen and i > 0 and rng.random() < rest_p and d <= 0.5:
            prev_leap = 0
            continue
        notes.append([t, d, p])
        prev_leap = p - prev
        prev = p
    # слияние пауз: ноты со стартом t и длиной d; пропущенные оставляют паузы
    return [(t, d, p) for t, d, p in notes]


def counter_line(melody, bars_ch, bpb, key, lo, hi, interval=2):
    """Диатоническая терция/секста под мелодией: сдвиг по ступеням шкалы."""
    out = []
    for t, d, p in melody:
        bi = int(t // bpb)
        off = t - bi * bpb
        ch = bars_ch[min(bi, len(bars_ch) - 1)][-1][0]
        for c, o, dd in bars_ch[min(bi, len(bars_ch) - 1)]:
            if o - 1e-6 <= off < o + dd - 1e-6:
                ch = c
        pool = sorted({q for q in range(lo, hi + 1) if q % 12 in set(key.scale_pcs(ch.dom)) | set(ch.pcs)})
        if p not in pool:
            pool = sorted(pool + [p])
        i = pool.index(p)
        out.append((t, d, pool[max(0, i - interval)]))
    return out


# ------------------------------------------------------------------ секция

class Sec:
    """Раздел пьесы: тональность, такты (римские цифры), мелодия, фактура, динамика."""

    def __init__(self, P, key, bars, vel=80, mel=None, tex=None):
        self.P, self.key, self.bars = P, key, bars
        self.vel = vel


def bar_chords(P, key, bars):
    return [b if isinstance(b, list) else parse_bar(b, key, P.bpb) for b in bars]


class Penta(Key):
    """Пентатоника (импрессионизм): гамма из пяти звуков, гармония — аккорды с септимой/нонами."""
    def scale_pcs(self, raised7=False):
        return [(self.t + x) % 12 for x in (0, 2, 4, 7, 9)]


class Whole(Key):
    """Целотонный лад."""
    def scale_pcs(self, raised7=False):
        return [(self.t + x) % 12 for x in (0, 2, 4, 6, 8, 10)]


def wt_bar(P, root_pc, kind=(0, 4, 8, 10)):
    return [(Chord(root_pc, list(kind)), 0.0, P.bpb)]


def phrase_melody(P, key, bars, lo, hi, start, seeds, cells, endcells, cads, plen=4, motif=None, amp=7, rest_p=0.0,
                  peak=0.65, motif_every=True, step_bias=1.0):
    """Мелодия на все такты секции фразами по plen тактов; seeds[i] — семя фразы (повтор семени = повтор/секвенция)."""
    bc = bar_chords(P, key, bars)
    out = []
    n = len(bars)
    pi = 0
    for b0 in range(0, n, plen):
        sub = bc[b0:b0 + plen]
        seed = seeds[pi % len(seeds)]
        cad = cads[pi % len(cads)]
        rng = random.Random(seed * 7919 + hash(P.name) % 1000)
        mot = motif if (motif and (motif_every or pi == 0)) else None
        mel = gen_melody(rng, sub, P.bpb, lo, hi, start, cells, endcells, mot, cad, amp, rest_p, key, peak, step_bias)
        for t, d, p in mel:
            out.append((P.pos + b0 * P.bpb + t, d, p))
        pi += 1
    return out, bc


def swell(tr, beat, dur, lo=62, hi=108, steps=6):
    """Огибающая громкости (CC11) на отрезке: нарастает к середине и спадает."""
    for i in range(steps + 1):
        x = i / steps
        a = 1 - abs(2 * x - 1) ** 1.6
        tr.ccs.append((beat + dur * x, 11, lo + (hi - lo) * a))


def place(tr, notes, vel, articulate=1.0, hum=None, accent=0):
    for t, d, p in notes:
        v = vel + (accent if abs(t % 1.0) < 1e-6 else 0)
        tr.add(t, d * articulate, p, v)


def ornament_trill(tr, t, d, p, key, vel, up=2, rate=0.125):
    n = int(d / rate)
    for i in range(n):
        tr.add(t + i * rate, rate * 0.95, p + (up if i % 2 else 0), vel - 4)


def run_notes(tr, t, p0, p1, key, vel, rate=0.125, pcs=None):
    """Быстрая гамма от p0 к p1 по ступеням тональности."""
    pcs = set(pcs or key.scale_pcs(True))
    pool = [p for p in range(min(p0, p1), max(p0, p1) + 1) if p % 12 in pcs]
    if p1 < p0:
        pool = pool[::-1]
    for i, p in enumerate(pool):
        tr.add(t + i * rate, rate * 1.4, p, vel + (i * 6 // max(1, len(pool))))
    return t + len(pool) * rate


# ------------------------------------------------------------------ фактуры

def tex_waltz(P, bc, bass, chord_tr, bass_tr, vel=64, bvel=74, prev=None, center=64, bar_lo=40, pizz=None, n=3, short=0.85):
    """Вальс: бас на раз, аккорд на два и три."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, bar_lo, bar_lo + 14)
            bass_tr.add(b0 + off, 0.9, bp, bvel)
            prev = voice(ch, center, n, prev)
            for k in range(1, int(round(dur))):
                for q in prev:
                    chord_tr.add(b0 + off + k, short, q, vel - (4 if k == 2 else 0))
    return prev


def tex_nocturne(P, bc, tr, vel=58, prev=None, lo=36, spread=2, pattern=None, pedal=True, hi_center=60):
    """Ноктюрн: бас-октава и широкий арпеджио левой руки (8-е/6-е), педаль — ноты тянутся до конца такта."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, lo + 12)
            mid = voice(ch, hi_center - 6, 3, prev)
            prev = mid
            seq = [bp, mid[0], mid[1], mid[2], mid[1], mid[0]] if pattern is None else [([bp] + mid)[i] for i in pattern]
            step = dur / len(seq) if pattern is None else (0.5 if P.bpb != 3.0 else 0.5)
            n_steps = int(round(dur / step))
            for k in range(n_steps):
                p = seq[k % len(seq)]
                t = b0 + off + k * step
                held = (b0 + off + dur) - t if pedal else step * 1.5
                tr.add(t, held * 0.98, p, vel + (8 if k == 0 else 0) - (k % 2) * 4)
            tr.add(b0 + off, dur * 0.99, bp - 12 if bp - 12 >= 24 else bp, vel + 6)
    return prev


def tex_arp16(P, bc, tr, vel=62, pattern=(0, 1, 2, 3, 4, 2, 3, 4), lo=40, hi_c=62, hold=True, prev=None, rate=0.25, extra_bass=None, pedal_pc=None):
    """Прелюдия в духе Баха: непрерывное арпеджио 16-ми по аккорду, 5 звуков (бас, 3 середина, верх) — своя схема."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, lo + 10) if pedal_pc is None else nearest_pitch(pedal_pc, lo + 5)
            vs = voice(ch, hi_c, 4, prev)
            prev = vs
            notes5 = [bp, vs[0], vs[1], vs[2], vs[3] if len(vs) > 3 else vs[2] + 12]
            n_steps = int(round(dur / rate))
            for k in range(n_steps):
                p = notes5[pattern[k % len(pattern)]]
                tr.add(b0 + off + k * rate, rate * 1.8 if hold else rate * 0.9, p, vel + (6 if k % len(pattern) == 0 else 0) + (k % 2) * 2)
            if extra_bass:
                extra_bass.add(b0 + off, dur * 0.98, bp - 12 if bp > 40 else bp, vel + 4)
    return prev


def tex_sat(P, bc, bass_tr, chord_tr, vel=44, prev=None, center=62, lo=36, n=4, sustain=2.0, bvel=50):
    """Жимнопедия: бас на раз (октавой ниже), аккорд-пятно на два-три."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, lo + 10)
            bass_tr.add(b0 + off, dur * 0.99, bp, bvel)
            prev = voice(ch, center, n, prev)
            for q in prev:
                chord_tr.add(b0 + off + 1.0, min(sustain, dur - 1.0 + 0.01) * 0.98, q, vel)
    return prev


def tex_march(P, bc, bass_tr, chord_tr, vel=70, bvel=88, prev=None, center=62, lo=34, n=3, eighth=False):
    """Марш: бас на сильные доли, аккорды — оффбит."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, lo + 12)
            fifth = nearest_pitch((ch.root + 7) % 12, bp + 5)
            while fifth > bp + 9:
                fifth -= 12
            prev = voice(ch, center, n, prev)
            beats = int(round(dur))
            for k in range(beats):
                t = b0 + off + k
                if k % 2 == 0:
                    bass_tr.add(t, 0.7, bp if k % 4 == 0 else fifth, bvel)
                else:
                    bass_tr.add(t, 0.7, fifth if k % 4 == 1 else bp, bvel - 10)
                for q in prev:
                    chord_tr.add(t + 0.5, 0.4, q, vel)
    return prev


def tex_pad(P, bc, tr, vel=60, prev=None, center=60, n=4, swell_cc=True, lo=48, hi=76):
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            prev = voice(ch, center, n, prev)
            for q in prev:
                tr.add(b0 + off, dur * 1.02, q, vel)
    return prev


def tex_pulse(P, bc, tr, vel=56, prev=None, center=60, n=3, step=1.0, dur_f=0.5, lo=48):
    """Пиццикато/стаккато-пульс аккордов."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            prev = voice(ch, center, n, prev)
            k = 0
            while k * step < dur - 1e-6:
                for q in prev:
                    tr.add(b0 + off + k * step, step * dur_f, q, vel + (6 if k == 0 else 0))
                k += 1
    return prev


def tex_bassline(P, bc, tr, vel=70, lo=30, hi=50, style="root", step=1.0, dur_f=0.9):
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, hi)
            n = int(round(dur / step))
            for k in range(max(1, n)):
                p = bp
                if style == "rf" and k % 2 == 1:
                    p = nearest_pitch((ch.root + 7) % 12, bp + 6)
                    if p > hi:
                        p -= 12
                tr.add(b0 + off + k * step, step * dur_f, p, vel if k == 0 else vel - 8)


def tex_planing(P, bc, tr, vel=46, shape=(0, 4, 7, 11, 14), lo=52, prev=None, dur_f=0.99, lift=0):
    """Импрессионизм: параллельные аккорды (7/9) одним расположением, смещающимся вместе с басом."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            base = nearest_pitch(ch.root, lo + 2)
            for iv in ch.ivs[:4] + ([14] if 14 not in ch.ivs else []):
                tr.add(b0 + off, dur * dur_f, base + iv + 0, vel)
    return prev


def tex_harp_arp(P, bc, tr, vel=50, lo=40, hi=84, step=0.5, up=True, dur_f=6.0):
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            pool = [p for p in range(lo, hi) if p % 12 in ch.pcs]
            n = int(round(dur / step))
            seq = pool[::2] if len(pool) > 8 else pool
            for k in range(n):
                i = (k * 2) % max(1, len(seq)) if up else -(k + 1) % len(seq)
                tr.add(b0 + off + k * step, min(dur_f, 3.0), seq[(k * 2 + (k // 5)) % len(seq)], vel - (k % 3) * 3)


def tex_barcarolle(P, bc, bass_tr, chord_tr, vel=58, bvel=70, prev=None, center=62, lo=38):
    """Баркарола 6/8 (такт = 3 четверти): бас на 1, аккорд на 2-ю и 3-ю восьмую, и т.д."""
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            bp = bass_note(ch, lo, lo + 12)
            prev = voice(ch, center, 3, prev)
            n_beats = int(round(dur / 1.5))
            for k in range(n_beats):
                t = b0 + off + 1.5 * k
                bass_tr.add(t, 1.4, bp if k % 2 == 0 else nearest_pitch((ch.root + 7) % 12, bp + 6), bvel)
                for q in prev:
                    chord_tr.add(t + 0.5, 0.45, q, vel)
                    chord_tr.add(t + 1.0, 0.45, q, vel - 4)
    return prev


def tex_alberti(P, bc, tr, vel=54, prev=None, center=58, lo=44, step=0.5, hold=1.0):
    for bi, bar in enumerate(bc):
        b0 = P.pos + bi * P.bpb
        for ch, off, dur in bar:
            prev = voice(ch, center, 3, prev)
            lowp, mid, hi_ = prev[0], prev[1], prev[2]
            seq = [lowp, hi_, mid, hi_]
            n = int(round(dur / step))
            for k in range(n):
                tr.add(b0 + off + k * step, step * 0.95 * hold, seq[k % 4], vel + (6 if k % 4 == 0 else 0))
    return prev


def drums_march(P, d, bars, start=None, vel=70, kick=36, snare=38, roll=False):
    """Малый барабан и бас-бочка: на каждую долю."""
    b0 = P.pos if start is None else start
    for bi in range(bars):
        for k in range(int(P.bpb)):
            t = b0 + bi * P.bpb + k
            if k % 2 == 0:
                d.add(t, 0.2, kick, vel)
            else:
                d.add(t, 0.2, snare, vel - 6)
            d.add(t + 0.75, 0.1, snare, vel - 24)
            if roll and k == int(P.bpb) - 1:
                for z in range(4):
                    d.add(t + 0.5 + z * 0.125, 0.1, snare, vel - 18 + z * 3)


def final_chord(P, tr_list, chord, center, n, vel, dur=6.0, lo=None):
    prev = voice(chord, center, n)
    for tr in tr_list:
        for q in prev:
            tr.add(P.pos, dur, q, vel)


def advance(P, bars):
    P.pos += bars * P.bpb


def finish_marks(P, tail=8.0):
    """Конец пьесы: педаль/удержание и тихий CC-маркер, чтобы fluidsynth доиграл хвост реверберации."""
    for t in P.tr.values():
        t.ccs.append((P.pos + tail, 64, 0))


# ================================================================== ПЬЕСЫ

PIECES = {}


def piece(fn):
    PIECES[fn.__name__.replace("p_", "music_")] = fn
    return fn


C_MAJ_RHY = [[1, 1, 1, 1], [1.5, 0.5, 1, 1], [1, 0.5, 0.5, 1, 1], [0.5, 0.5, 1, 1, 1], [2, 1, 1]]
END4 = [[1, 1, 2], [1.5, 0.5, 2], [2, 2], [1, 1, 1, 1]]


def melody_into(tr, mel, vel, art=0.95, accent=6, glide=None):
    for t, d, p in mel:
        tr.add(t, d * art, p, vel + (accent if abs(t % 1.0) < 1e-6 else 0))


# ---------------- 1. Проходная — торжественное Andante (в духе Чайковского), ре мажор, 4/4
@piece
def p_menu(P):
    P.bpm, P.bpb = 66, 4.0
    vl1 = P.track("vl1", 48, vol=100, pan=48, rev=70)
    vla = P.track("vla", 49, vol=88, pan=72, rev=70)
    cel = P.track("cello", 42, vol=96, pan=84, rev=70)
    cb = P.track("cb", 43, vol=84, pan=60, rev=70)
    hrn = P.track("horn", 60, vol=80, pan=90, rev=70)
    fl = P.track("flute", 73, vol=80, pan=40, rev=70)
    tim = P.track("timp", 47, vol=80, rev=60)
    K = Key("D")
    Kb = Key("B", "min")
    Ka = Key("A")
    cells = [[2, 1, 1], [1.5, 0.5, 1, 1], [1, 1, 2], [1, 1, 1, 1], [3, 1], [2, 0.5, 0.5, 1]]
    mot = [(1.5, 0), (0.5, 1), (1, 2), (1, 1)]
    secs = [
        # A: тема — период из двух фраз
        (K, ["I", "I_3 vi", "IV ii6", "V", "I", "V7/IV IV", "ii V7", "I"], [1, 2, 1, 3], ["half", "auth"], 66, 74, "vl1"),
        # B: в доминанту, секвенция по квинтовому кругу
        (Ka, ["I", "vi", "ii", "V7", "I", "V7/ii ii", "V7/V V", "V"], [4, 5, 4, 6], ["half", "half"], 68, 76, "flute"),
        # A': возвращение, тема у виолончелей/валторны выше, расширенное кадансирование
        (K, ["I", "I_3 vi", "IV ii6", "V7", "vi", "bII IV", "I_5 V7", "I"], [1, 2, 1, 3], ["half", "auth"], 69, 82, "vl1"),
    ]
    for i, (key, bars, seeds, cads, st, vel, lead) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 62, 86, st, seeds, cells, END4, cads, 4, mot, amp=7)
        n = len(bars)
        melody_into(P.tr[lead], mel, vel - 4, 0.97, 0)
        swell(P.tr[lead], P.pos, n * P.bpb, 70, 118, n * 2)
        if i == 2:
            melody_into(hrn, [(t, d, p - 12) for t, d, p in mel], vel - 14, 0.95, 0)
            swell(hrn, P.pos, n * P.bpb, 60, 108, n * 2)
        tex_pad(P, bc, vla, vel - 18, center=58, n=3)
        swell(vla, P.pos, n * P.bpb, 64, 100, n * 2)
        # виолончели: контрмелодия — длинные ноты терцией ниже
        cm = counter_line(mel, bc, P.bpb, key, 48, 70, 4)
        melody_into(cel, [(t, d, p) for t, d, p in cm], vel - 20, 1.0, 0)
        swell(cel, P.pos, n * P.bpb, 66, 100, n * 2)
        tex_bassline(P, bc, cb, vel - 10, 28, 46, step=2.0, dur_f=1.9)
        # литавры на сильных тактах
        for bi in range(0, n, 4):
            tim.add(P.pos + bi * P.bpb, 3.0, pc_of("D") + 38 if i != 1 else pc_of("A") + 33, vel - 14)
        advance(P, n)
    # кода: плагальный оборот и тоника
    kb = ["IV", "I_5", "V7", "I:2 I:2"]
    bc = bar_chords(P, K, ["IV", "V7", "I"])
    for t in (vl1, vla, cel, hrn):
        pass
    final_chord(P, [vl1, vla], roman("I", K), 69, 3, 76, 7.0)
    final_chord(P, [cel], roman("I", K), 50, 2, 70, 7.0)
    cb.add(P.pos, 7, 38, 72)
    tim.add(P.pos, 4, 50, 80)
    P.rit.append((P.pos - 8, P.pos, 0.72))
    return P.pos


# ---------------- 2. Первая смена — пасторальное утро (в духе Грига), ми мажор, 6/8
@piece
def p_morning(P):
    P.bpm, P.bpb = 92, 3.0
    P.no_breath = True
    ob = P.track("oboe", 68, vol=100, pan=50, rev=70)
    fl = P.track("flute", 73, vol=94, pan=76, rev=70)
    vl = P.track("vl", 49, vol=84, pan=60, rev=70)
    pz = P.track("pizz", 45, vol=88, pan=68, rev=60)
    hrn = P.track("horn", 60, vol=70, pan=90, rev=70)
    cb = P.track("cb", 43, vol=80, rev=60)
    tri = P.track("harp", 46, vol=76, pan=40, rev=70)
    cells = [[1.5, 0.5, 0.5, 0.5], [0.5, 0.5, 0.5, 1.5], [1.5, 1.5], [1.0, 0.5, 0.5, 0.5, 0.5], [0.5] * 6]
    endc = [[1.5, 3.0 - 1.5], [2.0, 1.0]]
    mot = [(1.5, 0), (0.5, 1), (0.5, 2), (0.5, 1)]
    K, Kg, Kc = Key("E"), Key("G"), Key("C#", "min")
    secs = [
        (K, ["I", "I", "V", "V", "I", "IV", "I_5", "V7"], [1, 2], ["open", "half"], 76, 76, ob),
        (K, ["I", "I", "V", "V", "I", "V7/V", "V", "I"], [1, 3], ["open", "auth"], 76, 80, fl),
        (Kc, ["i", "iv", "i", "V7", "i", "VI", "iv_3", "V"], [4, 5], ["open", "half"], 76, 78, ob),
        (Kg, ["I", "IV", "I", "V7", "I", "IV", "ii", "V7/III"], [6, 7], ["open", "half"], 79, 82, fl),
        (K, ["I", "I", "V", "V", "I", "IV", "bVII", "V7"], [1, 2], ["open", "half"], 76, 88, ob),
        (K, ["I", "vi", "IV", "V", "I", "IV", "I_5", "V7", "I"], [1, 8], ["open", "auth"], 79, 92, fl),
    ]
    for i, (key, bars, seeds, cads, st, vel, lead) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 66, 92, st, seeds, cells, endc, cads, 4, mot, amp=6, step_bias=1.2)
        n = len(bars)
        melody_into(lead, mel, vel - 6, 1.0, 4)
        swell(lead, P.pos, n * P.bpb, 72, 112, n)
        if i >= 1:
            cm = counter_line(mel, bc, P.bpb, key, 60, 90, 2)
            other = fl if lead is ob else ob
            melody_into(other, cm, vel - 20, 1.0, 2)
            swell(other, P.pos, n * P.bpb, 64, 100, n)
        tex_barcarolle(P, bc, cb, pz, vel - 24, 62)
        tex_pad(P, bc, vl, vel - 30, center=60, n=3)
        swell(vl, P.pos, n * P.bpb, 58, 96, n)
        if i >= 4:
            tex_harp_arp(P, bc, tri, vel - 20, 52, 90, 0.5)
            for bi in range(0, n, 2):
                pass
        if i in (2, 3, 5):
            tex_pad(P, bc, hrn, vel - 28, center=54, n=2)
        advance(P, n)
    final_chord(P, [vl, ob, fl], roman("I", K), 76, 3, 70, 8.0)
    cb.add(P.pos, 8, 40, 66)
    tri.add(P.pos, 6, 64, 56)
    tri.add(P.pos + 0.25, 6, 68, 52)
    tri.add(P.pos + 0.5, 6, 71, 50)
    P.rit.append((P.pos - 9, P.pos, 0.78))
    return P.pos


# ---------------- 3. Норма — скерцо/рондо (в духе Моцарта/Гайдна), до мажор, 2/4
@piece
def p_shop(P):
    P.bpm, P.bpb = 126, 2.0
    vl = P.track("vl", 40, vol=100, pan=46, rev=55)
    vl2 = P.track("vl2", 40, vol=84, pan=70, rev=55)
    vla = P.track("vla", 41, vol=78, pan=76, rev=55)
    cel = P.track("cello", 42, vol=88, pan=90, rev=55)
    ob = P.track("oboe", 68, vol=82, pan=36, rev=55)
    fag = P.track("bassoon", 70, vol=72, pan=84, rev=55)
    cl = P.track("clar", 71, vol=80, pan=44, rev=55)
    C, G, Am, F = Key("C"), Key("G"), Key("A", "min"), Key("F")
    cells = [[0.5, 0.5, 0.5, 0.5], [1, 0.5, 0.5], [0.5, 0.5, 1], [0.5, 0.25, 0.25, 0.5, 0.5], [1.0, 1.0]]
    endc = [[1.0, 1.0], [1.5, 0.5], [0.5, 0.5, 1.0]]
    mot = [(0.5, 0), (0.5, 2), (0.5, 1), (0.5, 0), (1.0, -1), (1.0, 0)]

    def refrain(vel):
        return (C, ["I", "I", "V", "V7", "I", "IV", "V7", "I"], [1, 2], ["half", "auth"], 72, vel)
    # форма рондо: A B A C A коды
    plan = [
        ("A", refrain(80)),
        ("B", (G, ["I", "V7", "I", "V7/V", "V", "V7", "vi", "ii V7/V", "V:2 V7/V:1 V:1", "V7"], [3, 4, 5], ["half", "half", "auth"], 74, 76)),
        ("A", refrain(84)),
        ("C", (Am, ["i", "iv", "V7", "i", "i", "iv_3", "viio7/V V", "V", "i", "VI", "iio6 V7", "i"], [6, 7, 8], ["half", "half", "auth"], 72, 84)),
        ("B", (F, ["I", "V7", "I", "V7/V", "V", "V7", "vi", "ii V7/V", "V:2 V7/V:1 V:1", "V7"], [3, 4, 5], ["half", "half", "auth"], 74, 80)),
        ("A", refrain(90)),
    ]
    for tag, (key, bars, seeds, cads, st, vel) in plan:
        plen = 4
        mel, bc = phrase_melody(P, key, bars, 62, 92, st, seeds, cells, endc, cads, plen, mot, amp=8, rest_p=0.06, motif_every=(tag != "B"))
        n = len(bars)
        lead = ob if tag == "B" else vl
        melody_into(lead, mel, vel, 0.78, 8)
        if tag == "A" and vel >= 84:
            melody_into(ob, [(t, d, p + 12) for t, d, p in mel], vel - 26, 0.75, 4)
        cm = counter_line(mel, bc, P.bpb, key, 54, 84, 2)
        melody_into(vl2 if tag != "B" else cl, cm, vel - 22, 0.78, 3)
        tex_alberti(P, bc, vla, vel - 28, center=56, step=0.5)
        tex_bassline(P, bc, cel, vel - 14, 36, 52, step=1.0, dur_f=0.55)
        tex_bassline(P, bc, fag, vel - 26, 34, 50, step=2.0, dur_f=1.6)
        advance(P, n)
    # кода с трелью и каденцией
    K = C
    bc = bar_chords(P, K, ["ii", "V7:1 V7:1", "I"])
    ornament_trill(vl, P.pos, 1.5, 79, K, 78, 2, 0.125)
    melody_into(vl, [(P.pos + 1.5, 0.5, 77), (P.pos + 2.0, 1.0, 76), (P.pos + 3.0, 1.0, 74), (P.pos + 4.0, 3.0, 72)], 82, 1.0, 0)
    tex_alberti(P, bc, vla, 54, center=56)
    tex_bassline(P, bc, cel, 70, 36, 52, step=1.0, dur_f=0.55)
    P.pos += 4.0
    final_chord(P, [vl, vl2, vla], roman("I", C), 72, 3, 74, 4.5)
    cel.add(P.pos, 4.5, 36, 76)
    P.rit.append((P.pos - 10, P.pos, 0.8))
    return P.pos


# ---------------- 4. Встречный план — военный марш с трио (в духе Глинки/Сузы-жанра), си-бемоль → ми-бемоль, 4/4
@piece
def p_march(P):
    P.bpm, P.bpb = 112, 4.0
    P.no_breath = True
    tp = P.track("trumpet", 56, vol=100, pan=46, rev=45)
    tp2 = P.track("trumpet2", 56, vol=84, pan=66, rev=45)
    hn = P.track("horn", 60, vol=88, pan=84, rev=45)
    tb = P.track("trombone", 57, vol=88, pan=76, rev=45)
    tu = P.track("tuba", 58, vol=96, pan=60, rev=40)
    pic = P.track("piccolo", 72, vol=76, pan=36, rev=50)
    cl = P.track("clarinet", 71, vol=78, pan=50, rev=45)
    d = P.drums(90)
    Bb, Eb, F = Key("Bb"), Key("Eb"), Key("F")
    cells = [[1, 1, 1, 1], [1.5, 0.5, 1, 1], [1.5, 0.5, 1.5, 0.5], [0.5, 0.5, 1, 1, 1], [1, 0.5, 0.5, 1, 1], [2, 1, 1]]
    endc = [[1, 1, 2], [1.5, 0.5, 2], [2, 2]]
    mot = [(1.5, 0), (0.5, 2), (1, 1), (1, 0)]
    # вступление: 4 такта на доминанте барабанной дробью
    bcI = bar_chords(P, Bb, ["V7", "V7", "V7", "V7"])
    for bi in range(4):
        for k in range(4):
            for z in range(4):
                d.add(P.pos + bi * 4 + k + z * 0.25, 0.1, 38, 52 + bi * 6 + (10 if z == 0 else 0))
    tex_bassline(P, bcI, tu, 70, 30, 46, step=2.0)
    tex_pulse(P, bcI, tb, 66, center=58, n=3, step=1.0, dur_f=0.5)
    advance(P, 4)
    plan = [
        ("strain1", Bb, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "I", "V7/V", "V7", "I", "IV", "I_5 V7", "I", "I"], [1, 1, 2, 3], ["half", "auth"], 74, 92, 4),
        ("strain1", Bb, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "I", "V7/V", "V7", "I", "IV", "I_5 V7", "I", "I"], [1, 1, 2, 3], ["half", "auth"], 74, 96, 4),
        ("strain2", F, ["I", "vi", "ii", "V7", "I", "V7/ii ii", "V7/V V", "V7", "I", "vi", "IV", "V7", "I", "V7/V V", "V7", "I"], [4, 5, 4, 6], ["half", "half", "half", "auth"], 74, 94, 4),
        ("trio", Eb, ["I", "I", "IV", "I", "V7", "V7", "I", "I", "I", "I", "IV", "iv", "I_5", "V7/V V7", "I", "I"], [7, 8, 7, 9], ["half", "auth"], 74, 80, 4),
        ("trio", Eb, ["I", "I", "IV", "I", "V7", "V7", "I", "I", "I", "I", "IV", "iv", "I_5", "V7/V V7", "I", "I"], [7, 8, 7, 9], ["half", "auth"], 76, 98, 4),
        ("strain1", Bb, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "I", "V7/V", "V7", "I", "IV", "I_5 V7", "I", "I"], [1, 1, 2, 3], ["half", "auth"], 74, 106, 4),
    ]
    for tag, key, bars, seeds, cads, st, vel, plen in plan:
        lead_hi = tag == "trio"
        mel, bc = phrase_melody(P, key, bars, 60, 90, st, seeds, cells, endc, cads, plen, mot, amp=6, motif_every=True)
        n = len(bars)
        if tag == "trio":
            hmel = mel
            melody_into(hn, [(t, d, p) for t, d, p in mel], vel, 0.85, 6)
            melody_into(cl, [(t, d, p + 12) for t, d, p in mel], vel - 12, 0.85, 4)
            melody_into(tb, [(t, d, p - 12) for t, d, p in counter_line(mel, bc, P.bpb, key, 48, 82, 4)], vel - 18, 0.85, 0)
            if vel > 90:
                melody_into(tp, [(t, d, p + 12) for t, d, p in mel], vel - 10, 0.85, 4)
        else:
            melody_into(tp, mel, vel, 0.82, 8)
            melody_into(pic, [(t, d, p + 12) for t, d, p in mel], vel - 24, 0.82, 4)
            melody_into(tp2, counter_line(mel, bc, P.bpb, key, 52, 84, 2), vel - 16, 0.82, 4)
            melody_into(cl, [(t, d, p) for t, d, p in counter_line(mel, bc, P.bpb, key, 52, 84, 4)], vel - 22, 0.82, 4)
        tex_march(P, bc, tu, tb if tag != "trio" else hn, vel - 18, vel - 2, center=56, lo=32, n=3)
        drums_march(P, d, n, vel=vel - 22, roll=(tag == "strain2"))
        advance(P, n)
    # кода: полная каденция I-IV-I_5-V7-I
    bc = bar_chords(P, Bb, ["IV", "I_5", "V7", "I"])
    for bi, bar in enumerate(bc):
        pass
    melody_into(tp, [(P.pos, 1, 74), (P.pos + 1, 1, 77), (P.pos + 2, 1, 79), (P.pos + 3, 1, 77), (P.pos + 4, 2, 72), (P.pos + 6, 2, 74),
                     (P.pos + 8, 2, 77), (P.pos + 10, 2, 76), (P.pos + 12, 2, 74)], 112, 0.85, 4)
    tex_march(P, bc, tu, tb, 96, 106, center=56, lo=32, n=3)
    drums_march(P, d, 4, vel=96, roll=True)
    advance(P, 4)
    final_chord(P, [tp, tp2, hn, tb, cl], roman("I", Bb), 70, 3, 100, 5.0)
    tu.add(P.pos, 5, 34, 100)
    d.add(P.pos, 1.0, 36, 100)
    d.add(P.pos, 1.0, 49, 90)
    P.rit.append((P.pos - 4, P.pos, 0.82))
    return P.pos


# ---------------- 5. Пересменка — ноктюрн (в духе Шопена), ми-бемоль мажор, 4/4, рояль с украшениями
@piece
def p_evening(P):
    P.bpm, P.bpb = 58, 4.0
    rh = P.track("rh", 0, vol=100, pan=60, rev=75)
    lh = P.track("lh", 0, vol=90, pan=68, rev=75)
    st = P.track("strings", 49, vol=60, pan=64, rev=80)
    ce = P.track("cello", 42, vol=70, pan=84, rev=80)
    Eb, Cm, Ab, Bb = Key("Eb"), Key("C", "min"), Key("Ab"), Key("Bb")
    cells = [[1.5, 0.5, 1, 1], [1, 1, 0.5, 0.5, 1], [2, 0.5, 0.25, 0.25, 1], [0.75, 0.25, 1, 2], [1.5, 0.5, 2], [1, 0.5, 0.5, 0.25, 0.25, 0.25, 0.25, 1]]
    endc = [[2, 2], [1, 1, 2], [1.5, 0.5, 2]]
    mot = [(1.5, 0), (0.5, 1), (1, 2), (1, 1)]
    secs = [
        # A: период 8 тактов + расширение
        (Eb, ["I", "I_3 V7/ii", "ii_3 V7/V", "V", "I", "V7/IV IV", "ii7 V7", "I"], [1, 2], ["half", "auth"], 70, 54),
        # B: в до минор и ля-бемоль мажор (VI), неаполитанская гармония
        (Cm, ["i", "iv_3", "V7/III III", "bVI", "iv", "bII", "V7", "V7"], [3, 4], ["half", "half"], 70, 62),
        # A': украшенное возвращение, тема октавой выше
        (Eb, ["I", "I_3 V7/ii", "ii_3 V7/V", "V", "I", "V7/IV IV", "ii7 V7", "I"], [1, 5], ["half", "auth"], 74, 70),
        # C: в ля-бемоль, кульминация
        (Ab, ["I", "IV", "I_5 V7", "I", "IV", "bII", "V7/V V", "V7"], [6, 7], ["half", "half"], 75, 84),
        (Eb, ["I", "I_3 V7/ii", "ii_3 V7/V", "V", "I", "IV", "I_5 V7", "I"], [1, 2], ["half", "auth"], 70, 56),
    ]
    prev = None
    for i, (key, bars, seeds, cads, stt, vel) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 63, 92, stt, seeds, cells, endc, cads, 4, mot, amp=7, step_bias=1.1)
        n = len(bars)
        melody_into(rh, mel, vel, 1.02, 5)
        # украшения: форшлаги и трель на кадансовых нотах
        for t, d, p in mel:
            if d >= 2 and abs(t % 4.0) < 1e-6 and i in (2, 4):
                ornament_trill(rh, t + d * 0.45, d * 0.45, p, key, vel - 14, 1 if key.minor else 2, 0.1)
        prev = tex_nocturne(P, bc, lh, vel - 14, prev, lo=34, hi_center=58)
        tex_pad(P, bc, st, vel - 38, center=60, n=3)
        swell(st, P.pos, n * P.bpb, 50, 92, n)
        melody_into(ce, [(t, d, p - 12) for t, d, p in counter_line(mel, bc, P.bpb, key, 54, 80, 4) if d >= 1.0], vel - 26, 1.0, 0)
        if i == 3:
            run_notes(rh, P.pos + n * P.bpb - 1.5, 67, 91, key, vel - 4, 0.0625)
        advance(P, n)
    # каденция: нисходящий пассаж и тоника
    run_notes(rh, P.pos - 0.0, 91, 67, Eb, 60, 0.0625)
    final_chord(P, [rh], roman("I", Eb), 70, 3, 50, 8.0)
    final_chord(P, [lh], roman("I", Eb), 48, 3, 54, 8.0)
    st.add(P.pos, 8, 63, 40)
    P.rit.append((P.pos - 10, P.pos, 0.7))
    return P.pos


# ---------------- 6. Ночная смена — импрессионистская пьеса (в духе Дебюсси), ре-бемоль, пентатоника/целотон, 4/4
@piece
def p_night(P):
    P.bpm, P.bpb = 54, 4.0
    P.no_breath = True
    pn = P.track("piano", 0, vol=100, pan=58, rev=95)
    pl = P.track("piano_lh", 0, vol=86, pan=70, rev=95)
    hp = P.track("harp", 46, vol=80, pan=40, rev=100)
    fl = P.track("flute", 73, vol=76, pan=84, rev=100)
    st = P.track("strings", 48, vol=54, pan=64, rev=100)
    cel = P.track("celesta", 8, vol=56, pan=50, rev=95)
    Db = Penta("Db")
    cells = [[2, 1, 1], [3, 1], [1.5, 0.5, 2], [1, 1, 2], [2, 2]]
    endc = [[3, 1], [2, 2]]
    mot = [(2, 0), (1, 1), (1, 2)]
    # I: план Db: гармония параллельными 7- и 9-аккордами, смещающимися по тону (Dbmaj9 - Ebm9 - Fm9 - Ebm9 ...)
    A = ["IM7", "ii9", "iii7", "ii9", "IM7", "IVM7", "I6", "iii7"]
    A = [s.replace("9", "7") if False else s for s in A]
    Dk = Key("Db")
    secs = [
        (Penta("Db"), Dk, ["IM7", "ii7", "iii7", "ii7", "IM7", "IVM7", "I6", "iii7"], [1, 2], ["open", "open"], 69, 44, "piano"),
        (Penta("Db"), Dk, ["IM7", "ii7", "iii7", "bVIM7", "IM7", "IVM7", "bVII", "iii7"], [3, 4], ["open", "half"], 72, 50, "flute"),
    ]
    prev = None
    for i, (pk, ck, bars, seeds, cads, st0, vel, lead) in enumerate(secs):
        mel, bc = phrase_melody(P, ck, bars, 62, 92, st0, seeds, cells, endc, cads, 4, mot, amp=5, rest_p=0.15, step_bias=1.4)
        # пентатоника: подгоняем мелодию к ней, не трогая сильные доли (аккорды всё равно даёт M7)
        n = len(bars)
        melody_into(P.tr[lead], mel, vel + 6, 1.05, 3)
        swell(P.tr[lead], P.pos, n * P.bpb, 70, 105, n)
        tex_planing(P, bc, pl, vel - 18, lo=44)
        tex_harp_arp(P, bc, hp, vel - 12, 46, 88, 1.0)
        tex_pad(P, bc, st, vel - 24, center=60, n=4)
        swell(st, P.pos, n * P.bpb, 50, 86, n)
        advance(P, n)
    # II: целотонный эпизод: восьмёрка тактов, аккорды-«облака» с шагом в большую секунду вверх, мелодия — целотонный ход
    wroots = [pc_of("Db"), pc_of("Eb"), pc_of("F"), pc_of("G"), pc_of("A"), pc_of("G"), pc_of("F"), pc_of("Eb")]
    wbars = [wt_bar(P, r) for r in wroots]
    rng = random.Random(145)
    wk = Whole("Db")
    pool = [p for p in range(64, 90) if p % 12 in set(wk.scale_pcs())]
    idx = 4
    t = P.pos
    for bi in range(8):
        for q in range(4):
            if rng.random() < 0.8:
                step = rng.choice([-2, -1, 1, 1, 2])
                idx = max(0, min(len(pool) - 1, idx + step + (1 if bi < 4 else -1) * (1 if q == 0 else 0)))
                d = rng.choice([1.0, 1.0, 2.0])
                if q == 3 and bi % 2:
                    d = 1.0
                pn.add(t + bi * 4 + q, d * 0.98, pool[idx], 52 + bi * 2)
    tex_planing(P, wbars, pl, 40, lo=46)
    tex_harp_arp(P, wbars, hp, 40, 48, 90, 0.5)
    tex_pad(P, wbars, st, 32, center=62, n=4)
    for bi in range(8):
        cel.add(t + bi * 4 + 2.0, 2.0, pool[(bi * 3) % len(pool)] + 12, 44)
    advance(P, 8)
    # III: возвращение темы, ниже и тише (флейта и фортепиано), с чистым IM7 в конце
    bars = ["IM7", "ii7", "iii7", "ii7", "IM7", "IVM7", "I6", "IM7"]
    mel, bc = phrase_melody(P, Dk, bars, 62, 92, 69, [1, 2], cells, endc, ["open", "auth"], 4, mot, amp=5, rest_p=0.15, step_bias=1.4)
    melody_into(pn, mel, 46, 1.05, 3)
    melody_into(fl, [(t, d, p + 12) for t, d, p in mel], 34, 1.0, 0)
    tex_planing(P, bc, pl, 30, lo=44)
    tex_harp_arp(P, bc, hp, 34, 46, 88, 1.0)
    tex_pad(P, bc, st, 24, center=60, n=4)
    swell(st, P.pos, 32, 40, 70, 8)
    advance(P, 8)
    final_chord(P, [pn, st], roman("IM7", Dk), 66, 4, 34, 10.0)
    final_chord(P, [pl], roman("IM7", Dk), 48, 2, 34, 10.0)
    cel.add(P.pos + 1, 6, 84, 40)
    P.rit.append((P.pos - 8, P.pos, 0.7))
    return P.pos


# ---------------- 7. Тихий цех — прелюдия в духе Баха, ля минор, непрерывное арпеджио, канонические вступления
@piece
def p_calm(P):
    P.bpm, P.bpb = 76, 4.0
    P.no_breath = True
    pn = P.track("piano", 0, vol=96, pan=56, rev=60)
    hc = P.track("harpsichord", 6, vol=58, pan=72, rev=60)
    ce = P.track("cello", 42, vol=82, pan=88, rev=65)
    vl = P.track("violin", 40, vol=72, pan=40, rev=65)
    og = P.track("organ", 19, vol=48, pan=64, rev=70)
    Am, C, Dm, Em = Key("A", "min"), Key("C"), Key("D", "min"), Key("E", "min")
    cells = [[4], [2, 2], [2, 1, 1], [1, 1, 2], [3, 1]]
    endc = [[4], [2, 2]]
    mot = [(2, 0), (1, 1), (1, 2)]
    secs = [
        # I: тоника-субдоминанта-доминанта по ступеням: круг квинт c секвенциями
        (Am, ["i", "iv", "VII", "III", "VI", "iiø7", "V7", "i"], [1, 2], ["half", "auth"], 69, 56, None),
        # II: побочные доминанты - ход к соль мажору и ми минору
        (Am, ["i", "V7/iv", "iv", "V7/VII", "VII", "V7/III", "III", "V7/VI"], [3, 4], ["open", "half"], 72, 60, None),
        (Am, ["VI", "V7/iv iv", "iiø7 V7", "i", "viio7/V i_5", "V7/V V7", "i_5 V7", "i"], [1, 5], ["half", "auth"], 72, 64, None),
        # III: нонаккорды и педальный бас на доминанте E
        (Am, ["i_5", "viio7/V", "V7", "V7", "i_5", "iv_3", "V7", "V7"], [6, 7], ["open", "open"], 71, 66, pc_of("E")),
        (Am, ["i", "iv", "V7/V V7", "i", "iv_3 V7", "i", "V7/iv iv", "i_5 V7", "i"], [1, 8], ["half", "auth"], 69, 58, None),
    ]
    prev = None
    first_mel = None
    for i, (key, bars, seeds, cads, st0, vel, ped) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 60, 84, st0, seeds, cells, endc, cads, 4, mot, amp=5, step_bias=1.4)
        n = len(bars)
        prev = tex_arp16(P, bc, pn, vel - 6, lo=38, hi_c=61, hold=True, prev=prev, pedal_pc=ped, rate=0.25)
        # длинная мелодия виолончели/скрипки; а вступление — каноном: через 2 такта в нижней октаве повторяется
        melody_into(vl, mel, vel + 6, 1.0, 0)
        swell(vl, P.pos, n * P.bpb, 62, 104, n)
        canon = [(t + 2 * P.bpb, d, p - 12) for t, d, p in counter_line(mel, bc, P.bpb, key, 52, 80, 3) if t + 2 * P.bpb < P.pos + n * P.bpb]
        melody_into(ce, canon, vel - 6, 1.0, 0)
        swell(ce, P.pos, n * P.bpb, 56, 96, n)
        tex_bassline(P, bc, og, vel - 18, 26, 44, step=4.0, dur_f=3.95) if ped is None else og.add(P.pos, n * P.bpb, nearest_pitch(ped, 33), vel - 14)
        if i % 2 == 0:
            tex_arp16(P, bc, hc, vel - 24, lo=50, hi_c=72, hold=False, rate=0.5, pattern=(0, 2, 1, 3))
        advance(P, n)
    final_chord(P, [pn, vl, hc], roman("i", Am), 64, 3, 58, 8.0)
    final_chord(P, [ce, og], roman("i", Am), 40, 2, 56, 8.0)
    P.rit.append((P.pos - 10, P.pos, 0.7))
    return P.pos


# ---------------- 8. Заводской вальс — венский вальс (в духе Штрауса), цепочка вальсов, ре → соль → ля → ре, 3/4
@piece
def p_waltz(P):
    P.bpm, P.bpb = 156, 3.0
    vl = P.track("violin", 40, vol=100, pan=46, rev=60)
    fl = P.track("flute", 73, vol=82, pan=36, rev=60)
    ob = P.track("oboe", 68, vol=76, pan=72, rev=60)
    cl = P.track("clar", 71, vol=70, pan=84, rev=60)
    pz = P.track("pizz", 45, vol=94, pan=58, rev=55)
    ac = P.track("accomp", 48, vol=72, pan=66, rev=55)
    cel = P.track("cello", 42, vol=90, pan=90, rev=55)
    hn = P.track("horn", 60, vol=80, pan=76, rev=55)
    tim = P.track("timp", 47, vol=70, rev=50)
    cells = [[1.5, 0.5, 1], [1, 1, 1], [2, 1], [0.5, 0.5, 1, 1], [1, 0.5, 0.5, 1], [1.5, 0.5, 0.5, 0.5]]
    endc = [[2, 1], [3], [1.5, 0.5, 1]]
    mot = [(1.5, 0), (0.5, 1), (1, 2), (1, 1), (0.5, 0), (0.5, 1), (2, 2)]
    D, G, A, Bm = Key("D"), Key("G"), Key("A"), Key("B", "min")
    # вступление: 8 тактов (тремоло-доминанта и фанфара), затем вальсы
    bcI = bar_chords(P, D, ["V7", "V7", "I", "I", "V7/V", "V", "V7", "V7"])
    tex_pad(P, bcI, ac, 52, center=60, n=3)
    swell(ac, P.pos, 24, 40, 100, 8)
    tex_bassline(P, bcI, cel, 60, 30, 46, step=3.0, dur_f=2.0)
    for bi in (0, 2, 4, 6):
        tim.add(P.pos + bi * 3, 2.0, 45, 60 + bi * 3)
    melody_into(hn, [(P.pos + 6, 1, 69), (P.pos + 7, 1, 74), (P.pos + 8, 1, 78), (P.pos + 9, 3, 76), (P.pos + 15, 1.5, 74), (P.pos + 16.5, 1.5, 71), (P.pos + 18, 2, 69)], 80, 1.0, 0)
    advance(P, 8)
    plan = [
        ("W1", D, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "V7 I_5", "I"], [1, 2, 1, 3], ["half", "auth"], 74, 84),
        ("W1", D, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "V7 I_5", "I"], [1, 2, 1, 3], ["half", "auth"], 74, 92),
        ("W2", G, ["I", "I_3", "ii", "V7", "I", "V7/V", "V", "V7", "I", "IV", "V7/ii ii", "V7", "I", "vi", "ii V7", "I"], [4, 5, 4, 6], ["half", "auth"], 74, 86),
        ("W3", A, ["I", "V7/V V", "I", "V7/V V", "I", "IV", "I_5", "V7", "vi", "ii", "V7/V V", "V7", "I", "IV", "I_5 V7", "I"], [7, 8, 7, 9], ["half", "auth"], 76, 90),
        ("W4", Bm, ["i", "V7", "i", "VI", "iv", "V7", "i", "V7/III", "III", "V7/III", "III", "V7/V", "V", "V7", "III", "V7/V V7"], [10, 11, 10, 12], ["half", "half"], 76, 94),
        ("W1", D, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "V7 I_5", "I"], [1, 2, 1, 3], ["half", "auth"], 74, 100),
    ]
    for tag, key, bars, seeds, cads, st, vel in plan:
        mel, bc = phrase_melody(P, key, bars, 62, 92, st, seeds, cells, endc, cads, 4, mot, amp=7, rest_p=0.0)
        n = len(bars)
        lead = {"W1": vl, "W2": fl, "W3": vl, "W4": ob}[tag]
        melody_into(lead, mel, vel, 0.97, 7)
        swell(lead, P.pos, n * 3, 76, 112, n)
        if tag in ("W1", "W3"):
            melody_into(fl, [(t, d, p + 12) for t, d, p in mel], vel - 20, 0.95, 4)
        melody_into(cl, counter_line(mel, bc, P.bpb, key, 54, 84, 2), vel - 22, 0.95, 4)
        tex_waltz(P, bc, None, pz, cel, vel - 18, vel - 6, center=62, bar_lo=38, short=0.55)
        tex_waltz(P, bc, None, ac, hn, vel - 40, vel - 50, center=58, bar_lo=45, short=0.8, n=3) if vel > 90 else None
        advance(P, n)
    # кода: перепев начала темы и завершающие аккорды
    bc = bar_chords(P, D, ["I", "I", "V7", "I", "IV", "I_5", "V7:2 V7:1", "I"])
    cd, bc2 = phrase_melody(P, D, ["I", "I", "V7", "I"], 62, 92, 74, [1], cells, endc, ["auth"], 4, mot, amp=7)
    melody_into(vl, cd, 100, 0.97, 7)
    melody_into(fl, [(t, d, p + 12) for t, d, p in cd], 82, 0.97, 4)
    tex_waltz(P, bc2, None, pz, cel, 80, 94, center=62, bar_lo=38, short=0.55)
    advance(P, 4)
    bc3 = bar_chords(P, D, ["IV", "I_5", "V7", "I"])
    melody_into(vl, [(P.pos, 1.5, 78), (P.pos + 1.5, 1.5, 76), (P.pos + 3, 1.5, 74), (P.pos + 4.5, 1.5, 73), (P.pos + 6, 3, 71), (P.pos + 9, 3, 74)], 104, 1.0, 0)
    tex_waltz(P, bc3, None, pz, cel, 80, 94, center=62, bar_lo=38, short=0.55)
    advance(P, 4)
    final_chord(P, [vl, fl, cl, ac, hn], roman("I", D), 71, 3, 96, 5.0)
    cel.add(P.pos, 5, 38, 96)
    tim.add(P.pos, 3, 50, 96)
    P.rit.append((P.pos - 10, P.pos, 0.82))
    return P.pos


# ---------------- 9. Над заводской рекой — лирический вальс (в духе Чайковского), си минор → ре мажор, 3/4
@piece
def p_accwaltz(P):
    P.bpm, P.bpb = 126, 3.0
    vl = P.track("vl", 48, vol=100, pan=46, rev=80)
    vl2 = P.track("vl2", 49, vol=82, pan=70, rev=80)
    cel = P.track("cello", 42, vol=96, pan=90, rev=80)
    fl = P.track("flute", 73, vol=78, pan=36, rev=80)
    cl = P.track("clar", 71, vol=70, pan=80, rev=80)
    pz = P.track("pizz", 45, vol=88, pan=58, rev=70)
    hp = P.track("harp", 46, vol=70, pan=50, rev=80)
    cb = P.track("cb", 43, vol=82, rev=70)
    hn = P.track("horn", 60, vol=76, pan=84, rev=80)
    cells = [[3], [2, 1], [1.5, 0.5, 1], [1, 2], [2, 0.5, 0.5], [1, 1, 1]]
    endc = [[2, 1], [3], [1, 2]]
    mot = [(2, 0), (1, 1), (2, 2), (1, 1)]
    Bm, D, Fs, Em = Key("B", "min"), Key("D"), Key("F#", "min"), Key("E", "min")
    secs = [
        (Bm, ["i", "i", "iv", "V7", "i", "VI", "iio6 V7", "i"], [1, 2], ["half", "auth"], 66, 70, vl),
        (Bm, ["i", "i_3", "iv", "bII", "V7/III", "III", "V7", "V7"], [3, 4], ["half", "half"], 66, 78, vl),
        (D, ["I", "I_3", "IV", "V7", "I", "V7/ii", "ii", "V7"], [5, 6], ["half", "auth"], 69, 76, fl),
        (D, ["I", "V7/vi", "vi", "V7/V", "V", "V7/ii ii", "V7", "I"], [5, 7], ["half", "half"], 71, 88, vl),
        (Bm, ["i", "i_3", "iv", "bII", "V7/III", "III", "V7", "V7"], [3, 8], ["half", "half"], 66, 96, vl),
        (Fs, ["i", "iv", "V7", "i", "VI", "iv_3", "V7/V V", "V7"], [10, 11], ["half", "half"], 68, 84, vl),
        (D, ["I", "vi", "ii", "V7", "I", "V7/vi", "vi", "V7/V"], [12, 13], ["open", "half"], 71, 90, fl),
        (Em, ["i", "iv", "V7", "i", "bII", "i_5", "V7", "V7/III"], [14, 15], ["half", "half"], 67, 94, vl),
        (D, ["I", "I_3", "IV", "V7", "I", "V7/ii", "ii", "V7"], [5, 16], ["half", "auth"], 71, 100, vl),
        (Bm, ["i", "i", "iv", "V7", "i", "VI", "iio6 V7", "i"], [1, 2], ["half", "auth"], 66, 72, cel),
        (D, ["I", "IV", "I_5 V7", "I"], [9], ["auth"], 69, 60, vl),
    ]
    prev = None
    for i, (key, bars, seeds, cads, st, vel, lead) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 58, 90, st, seeds, cells, endc, cads, 4, mot, amp=8, step_bias=1.2)
        n = len(bars)
        melody_into(lead, mel, vel, 1.0, 3)
        swell(lead, P.pos, n * 3, 70, 118, n)
        if i in (3, 4):
            melody_into(fl, [(t, d, p + 12) for t, d, p in mel], vel - 20, 1.0, 0)
        cm = counter_line(mel, bc, P.bpb, key, 52, 82, 5)
        melody_into(vl2 if lead is not vl2 else cl, cm, vel - 24, 1.0, 0)
        swell(vl2, P.pos, n * 3, 60, 100, n)
        tex_waltz(P, bc, None, pz, cb, vel - 22, vel - 8, center=60, bar_lo=33, short=0.5)
        if i in (1, 3, 4):
            tex_harp_arp(P, bc, hp, vel - 24, 48, 88, 0.5)
            tex_pad(P, bc, hn, vel - 34, center=56, n=2)
        advance(P, n)
    final_chord(P, [vl, vl2, fl, cl], roman("I", D), 74, 3, 62, 8.0)
    cel.add(P.pos, 8, 38, 66)
    cb.add(P.pos, 8, 38, 64)
    hp.add(P.pos, 5, 62, 50)
    hp.add(P.pos + 0.3, 5, 66, 48)
    hp.add(P.pos + 0.6, 5, 69, 46)
    P.rit.append((P.pos - 10, P.pos, 0.72))
    return P.pos


# ---------------- 10. Тропинка к проходной — вариации на русскую песенную тему (в духе Глинки/Бородина), ля минор → ля мажор, 2/4
@piece
def p_folk(P):
    P.bpm, P.bpb = 96, 2.0
    P.no_breath = True
    gt = P.track("guitar", 24, vol=96, pan=44, rev=55)
    fl = P.track("flute", 73, vol=86, pan=36, rev=60)
    cl = P.track("clar", 71, vol=80, pan=84, rev=60)
    ac = P.track("accordion", 21, vol=76, pan=76, rev=55)
    vl = P.track("violins", 48, vol=92, pan=50, rev=65)
    cel = P.track("cello", 42, vol=90, pan=88, rev=60)
    pz = P.track("pizz", 45, vol=88, pan=66, rev=50)
    ob = P.track("oboe", 68, vol=82, pan=60, rev=60)
    tr_ = P.track("triangle", 8, vol=40, pan=56, rev=60)
    tm = P.track("timp", 47, vol=76, rev=55)
    d = P.drums(60)
    Am, A = Key("A", "min"), Key("A")
    cells = [[1, 0.5, 0.5], [0.5, 0.5, 1], [1, 1], [0.5, 0.5, 0.5, 0.5], [1.5, 0.5]]
    endc = [[1, 1], [2], [1.5, 0.5]]
    mot = [(1, 0), (0.5, 1), (0.5, 0), (1, -1), (1, 0)]
    theme_bars = ["i", "i", "VII", "i", "iv", "i", "V7", "i", "i", "III", "VII", "i", "iv", "VII", "V7", "i"]
    mel, bc = phrase_melody(P, Am, theme_bars, 57, 81, 69, [3, 4, 3, 5], cells, endc, ["half", "auth"], 4, mot, amp=5, step_bias=1.1)
    n = len(theme_bars)
    T = [(t - P.pos, d_, p) for t, d_, p in mel]

    def shifted(f=1.0, add=0):
        return [(P.pos + t, d_, p + add) for t, d_, p in T]

    def ornament(m, fill=0.5):
        out = []
        for t, d_, p in m:
            if d_ >= 1.0:
                out.append((t, 0.5, p))
                out.append((t + 0.5, 0.25, p + 2 if (p + 2) % 12 in set(Am.scale_pcs()) else p + 1))
                out.append((t + 0.75, 0.25, p))
                if d_ > 1.0:
                    out.append((t + 1.0, d_ - 1.0, p))
            else:
                out.append((t, d_, p))
        return out
    # тема: гитара соло и пиццикато
    melody_into(gt, shifted(), 78, 0.9, 6)
    tex_bassline(P, bc, pz, 60, 33, 48, step=1.0, dur_f=0.6, style="rf")
    advance(P, n)
    # вар. 1: флейта, аккордеон-аккомпанемент oom-pah
    melody_into(fl, shifted(), 84, 0.95, 6)
    melody_into(gt, [(t, d_, p - 12) for t, d_, p in shifted()], 60, 0.9, 0)
    tex_march(P, bc, pz, ac, 56, 66, center=58, lo=34, n=3)
    advance(P, n)
    # вар. 2: гобой с кларнетом, скрипки играют пиццикато-пульс, мелодия украшена
    om = ornament(shifted())
    melody_into(ob, om, 84, 0.9, 6)
    melody_into(cl, counter_line(shifted(), bc, P.bpb, Am, 52, 80, 2), 66, 0.9, 4)
    tex_pulse(P, bc, vl, 58, center=62, n=3, step=0.5, dur_f=0.5)
    tex_bassline(P, bc, cel, 74, 33, 48, step=1.0, dur_f=0.6, style="rf")
    advance(P, n)
    # вар. 3: tutti струнные, мелодия в виолончелях, быстрый фон скрипок
    melody_into(cel, [(t, d_, p - 12) for t, d_, p in shifted()], 90, 1.0, 6)
    melody_into(vl, ornament([(t, d_, p + 12) for t, d_, p in shifted()]), 80, 0.9, 4)
    tex_march(P, bc, pz, ac, 60, 70, center=58, lo=34, n=3)
    swell(cel, P.pos, n * 2, 70, 112, 8)
    tm.add(P.pos, 1.5, 45, 70)
    advance(P, n)
    # вар. 4: гитара и аккордеон, мелодия в нижней октаве с перебором; вар. 5: валторна-пастушья тема у гобоя, скрипки сопровождают
    melody_into(ac, [(t, d_, p - 12) for t, d_, p in shifted()], 80, 0.95, 6)
    tex_pulse(P, bc, gt, 64, center=58, n=3, step=0.5, dur_f=0.6)
    tex_bassline(P, bc, cel, 72, 33, 48, step=1.0, dur_f=0.6, style="rf")
    advance(P, n)
    melody_into(ob, ornament([(t, d_, p + 12) for t, d_, p in shifted()]), 86, 0.9, 6)
    melody_into(cl, [(t, d_, p) for t, d_, p in shifted()], 70, 0.9, 4)
    tex_pad(P, bc, vl, 52, center=62, n=3)
    swell(vl, P.pos, n * 2, 50, 100, 8)
    tex_march(P, bc, pz, ac, 58, 70, center=58, lo=34, n=3)
    drums_march(P, d, n, vel=50)
    advance(P, n)
    # вар. 6: в мажоре, быстрее, весь оркестр; новая мелодия из того же мотива
    P.tempo_mul.append((P.pos, 1.18))
    maj_bars = ["I", "I", "VII", "I", "IV", "I", "V7", "I", "I", "V7/ii", "ii", "I_5", "IV", "ii", "V7", "I"]
    mel2, bc2 = phrase_melody(P, A, maj_bars, 60, 88, 69, [3, 4, 3, 5], cells, endc, ["half", "auth"], 4, mot, amp=6)
    melody_into(vl, mel2, 94, 0.92, 6)
    melody_into(fl, [(t, d_, p + 12) for t, d_, p in mel2], 80, 0.92, 4)
    melody_into(cl, counter_line(mel2, bc2, P.bpb, A, 54, 82, 2), 72, 0.92, 4)
    tex_march(P, bc2, cel, ac, 66, 80, center=58, lo=34, n=3)
    drums_march(P, d, n, vel=60)
    tm.add(P.pos, 1.5, 45, 76)
    tm.add(P.pos + 16, 1.5, 45, 80)
    for bi in range(0, n, 2):
        tr_.add(P.pos + bi * 2 + 1.0, 0.5, 96, 56)
    advance(P, n)
    # кода: тема в мажоре, темп замедляется
    cad = bar_chords(P, A, ["IV", "I_5", "V7", "I"])
    melody_into(vl, [(P.pos, 1, 76), (P.pos + 1, 1, 74), (P.pos + 2, 1, 73), (P.pos + 3, 1, 71), (P.pos + 4, 2, 73), (P.pos + 6, 2, 69)], 96, 1.0, 0)
    tex_march(P, cad, cel, ac, 64, 80, center=58, lo=34, n=3)
    advance(P, 4)
    final_chord(P, [vl, fl, cl, ac], roman("I", A), 69, 3, 90, 4.5)
    cel.add(P.pos, 4.5, 33, 90)
    tm.add(P.pos, 2, 45, 90)
    P.rit.append((P.pos - 8, P.pos, 0.78))
    return P.pos


# ---------------- 11. Дождь над крышей цеха — жимнопедия (в духе Сати), ре мажор, 3/4, медленно
@piece
def p_rain(P):
    P.bpm, P.bpb = 66, 3.0
    P.no_breath = True
    pn = P.track("piano", 0, vol=100, pan=60, rev=85)
    pl = P.track("piano_lh", 0, vol=88, pan=66, rev=85)
    ob = P.track("oboe", 68, vol=70, pan=46, rev=90)
    ce = P.track("cello", 42, vol=60, pan=84, rev=90)
    D = Key("D")
    cells = [[3], [2, 1], [1, 2], [3], [1.5, 1.5], [2, 1]]
    endc = [[3], [2, 1]]
    mot = [(2, 0), (1, 1)]
    A = ["IVM7", "IM7"] * 4
    B = ["iii7", "vi7", "ii7", "V9", "IVM7", "IM7", "ii7", "V7"]
    # (бас, аккорд) движется как у Сати: тянет на раз, пятно на два-три
    plan = [
        (A, [1, 2], ["open", "open"], 69, 40, pn, False),
        (A, [1, 3], ["open", "open"], 69, 44, pn, False),
        (B, [4, 5], ["open", "half"], 71, 48, ob, True),
        (A, [1, 4], ["open", "open"], 69, 44, ob, True),
        (B, [6, 7], ["open", "half"], 71, 50, pn, True),
        (B, [4, 8], ["open", "half"], 71, 48, ob, True),
        (A, [1, 2], ["open", "auth"], 69, 46, pn, True),
    ]
    prev = None
    for i, (bars, seeds, cads, st0, vel, lead, strings) in enumerate(plan):
        mel, bc = phrase_melody(P, D, bars, 62, 84, st0, seeds, cells, endc, cads, 4, mot, amp=4, rest_p=0.0, step_bias=1.6)
        n = len(bars)
        if i == 0:
            mel = [(t, d, p) for t, d, p in mel if t >= P.pos + 2 * P.bpb]   # первые два такта — только сопровождение (как вступление)
        melody_into(lead, mel, vel + 10, 1.04, 2)
        if i == 3:
            melody_into(ce, [(t, d, p - 12) for t, d, p in mel], vel - 6, 1.0, 0)
        prev = tex_sat(P, bc, pl, pl, vel - 8, prev, center=60, lo=36, n=3, bvel=vel - 2)
        # капли дождя: высокие тихие ноты пентатоники
        rng = random.Random(i + 11)
        for k in range(n * 3):
            if rng.random() < 0.22:
                pn.add(P.pos + k * 1.0 + rng.choice([0.0, 0.5]), 0.5, rng.choice([86, 88, 90, 93, 95]), 22 + i * 3)
        if strings:
            tex_pad(P, bc, ce, vel - 24, center=52, n=2)
            swell(ce, P.pos, n * 3, 40, 80, n)
        advance(P, n)
    final_chord(P, [pn, pl], roman("IM7", D), 62, 4, 38, 10.0)
    ce.add(P.pos, 10, 38, 40)
    P.rit.append((P.pos - 9, P.pos, 0.7))
    return P.pos


# ---------------- 12. Первый снег — «снежный» вальс на челесте и пиццикато (в духе Чайковского), си минор → ре мажор, 3/4
@piece
def p_winter(P):
    P.bpm, P.bpb = 132, 3.0
    P.no_breath = True
    ce = P.track("celesta", 8, vol=100, pan=52, rev=85)
    gl = P.track("glock", 9, vol=70, pan=64, rev=90)
    pz = P.track("pizz", 45, vol=94, pan=62, rev=65)
    fl = P.track("flute", 73, vol=80, pan=36, rev=80)
    vl = P.track("violins", 48, vol=78, pan=48, rev=80)
    hp = P.track("harp", 46, vol=78, pan=40, rev=90)
    cb = P.track("cb", 43, vol=78, rev=70)
    bl = P.track("bells", 112, vol=60, pan=78, rev=85)
    cells = [[1, 1, 1], [1.5, 0.5, 1], [0.5, 0.5, 0.5, 0.5, 1], [2, 1], [1, 0.5, 0.5, 1], [0.5, 0.5, 1, 1]]
    endc = [[2, 1], [1.5, 0.5, 1], [3]]
    mot = [(1, 0), (0.5, 1), (0.5, 2), (1, 1), (1, 0), (1, -1), (1, 0)]
    Bm, D, Em = Key("B", "min"), Key("D"), Key("E", "min")
    secs = [
        (Bm, ["i", "i", "V7", "i", "iv", "i", "V7", "i", "VI", "iv", "V7/V", "V", "i", "iv_3", "V7", "i"], [1, 2, 1, 3], ["half", "auth"], 78, 62, ce),
        (D, ["I", "I", "V7", "I", "IV", "I_5", "V7/V V", "V7", "I", "V7/ii", "ii", "V7", "I", "vi", "ii V7", "I"], [4, 5, 4, 6], ["half", "auth"], 78, 70, ce),
        (Em, ["i", "i", "V7", "i", "iv", "i", "V7", "i", "VI", "bII", "V7/V", "V", "i", "iv_3", "V7", "i"], [7, 8, 7, 9], ["half", "half"], 76, 72, fl),
        (D, ["I", "V7/vi", "vi", "V7/V", "V", "V7/ii", "ii", "V7", "I", "vi", "ii", "V7", "I", "IV", "V7/V V", "V7"], [10, 11, 10, 12], ["half", "half"], 78, 80, ce),
        (D, ["I", "I", "V7", "I", "IV", "I_5", "V7/V V", "V7", "I", "V7/ii", "ii", "V7", "I", "vi", "ii V7", "I"], [13, 14, 13, 15], ["half", "half"], 78, 74, ce),
        (Bm, ["i", "i", "V7", "i", "bII", "i", "V7", "i", "VI", "iv", "V7/V", "V", "i", "iv_3", "V7", "i"], [1, 2, 1, 3], ["half", "auth"], 78, 76, fl),
    ]
    prev = None
    for i, (key, bars, seeds, cads, st, vel, lead) in enumerate(secs):
        mel, bc = phrase_melody(P, key, bars, 64, 96, st, seeds, cells, endc, cads, 4, mot, amp=7, step_bias=1.2)
        n = len(bars)
        melody_into(lead, mel, vel, 0.92, 5)
        melody_into(gl, [(t, d, p + 12) for t, d, p in mel if d >= 1.0], vel - 24, 0.8, 0)
        if i == 2:
            melody_into(ce, [(t, d, p + 12) for t, d, p in mel], vel - 14, 0.9, 4)
        tex_waltz(P, bc, None, pz, cb, vel - 12, vel - 4, center=62, bar_lo=36, short=0.4)
        tex_pad(P, bc, vl, vel - 36, center=60, n=3)
        swell(vl, P.pos, n * 3, 50, 90, n)
        # хрустальные нисходящие пассажи арфы на концах фраз
        for b0 in range(3, n, 4):
            run_notes(hp, P.pos + b0 * 3 + 1.0, 93, 74, key, vel - 20, 0.125)
        # бубенцы на каждой второй доле
        for bi in range(n):
            if bi % 2 == 0:
                bl.add(P.pos + bi * 3 + 1.0, 0.25, 96, 34 + i * 4)
                bl.add(P.pos + bi * 3 + 2.0, 0.25, 98, 30 + i * 4)
        advance(P, n)
    final_chord(P, [ce, vl, fl], roman("i", Bm), 74, 3, 54, 8.0)
    final_chord(P, [gl], roman("i", Bm), 86, 2, 40, 8.0)
    cb.add(P.pos, 8, 35, 60)
    for k in range(8):
        bl.add(P.pos + k * 0.5, 0.4, 96 + (k % 3), 30 - k)
    P.rit.append((P.pos - 10, P.pos, 0.72))
    return P.pos


# ---------------- 13. Утренний автобус — сонатное аллегро (в духе Моцарта), соль мажор, 4/4
@piece
def p_dawn(P):
    P.bpm, P.bpb = 132, 4.0
    pn = P.track("piano", 0, vol=100, pan=56, rev=55)
    pl = P.track("piano_lh", 0, vol=84, pan=66, rev=55)
    vl = P.track("violins", 48, vol=70, pan=44, rev=60)
    vla = P.track("violas", 49, vol=60, pan=74, rev=60)
    ce = P.track("cello", 42, vol=88, pan=90, rev=60)
    fl = P.track("flute", 73, vol=72, pan=40, rev=60)
    ob = P.track("oboe", 68, vol=64, pan=80, rev=60)
    G, D, Em, C = Key("G"), Key("D"), Key("E", "min"), Key("C")
    cells1 = [[1, 0.5, 0.5, 1, 1], [0.5, 0.5, 0.5, 0.5, 1, 1], [1, 1, 1, 1], [0.5, 0.5, 1, 1, 1], [1.5, 0.5, 1, 1]]
    cells2 = [[2, 1, 1], [1.5, 0.5, 1, 1], [1, 1, 2], [2, 2]]
    endc = [[1, 1, 2], [2, 2], [1.5, 0.5, 2]]
    mot1 = [(1, 0), (0.5, 1), (0.5, 2), (1, 3), (1, 2)]
    mot2 = [(2, 0), (1, -1), (1, 0)]

    def play(key, bars, seeds, cads, st, vel, motif, cells, lead, extra=None, rest=0.0):
        mel, bc = phrase_melody(P, key, bars, 60, 92, st, seeds, cells, endc, cads, 4, motif, amp=7, rest_p=rest)
        n = len(bars)
        melody_into(lead, mel, vel, 0.9, 7)
        if extra:
            melody_into(extra, [(t, d, p + 12) for t, d, p in mel], vel - 22, 0.9, 4)
        for t, d, p in mel:
            if d >= 2 and abs(t % 4.0) < 1e-6 and (t - P.pos) / P.bpb % 4 == 3:
                pass
        tex_alberti(P, bc, pl, vel - 26, center=54, step=0.5)
        tex_pad(P, bc, vl, vel - 40, center=62, n=3)
        swell(vl, P.pos, n * 4, 56, 90, n)
        tex_bassline(P, bc, ce, vel - 14, 33, 50, step=2.0, dur_f=1.4)
        counter = counter_line(mel, bc, P.bpb, key, 54, 84, 2)
        melody_into(ob if lead is pn else fl, counter, vel - 30, 0.9, 0)
        advance(P, n)
        return mel, bc
    # --- экспозиция
    play(G, ["I", "I", "V7", "I", "IV", "I_5", "V7", "I"], [1, 2], ["half", "auth"], 74, 84, mot1, cells1, pn)
    play(G, ["I", "V7/V", "V", "V7/V", "V", "V7/V V", "V7/V", "V:2 V:2"], [3, 4], ["open", "half"], 76, 88, mot1, cells1, pn)    # связка: модуляция в D
    play(D, ["I", "I_3", "IV", "V7", "I", "V7/vi", "vi", "ii V7", "I", "V7/V", "V", "V7", "I", "I"], [5, 6, 5, 7], ["half", "auth"], 76, 78, mot2, cells2, pn, fl)   # побочная
    # --- разработка: секвенции по малым терциям и кварто-квинтовому кругу, Em → Am → C → ... → ретрансляция на D7
    play(Em, ["i", "iv", "V7", "i", "VI", "iiø7", "V7", "i"], [1, 2], ["half", "half"], 74, 86, mot1, cells1, pn)
    play(C, ["I", "V7/ii", "ii", "V7/V", "V", "V7/vi", "vi", "V7/V"], [3, 8], ["open", "half"], 76, 92, mot1, cells1, pn)
    play(G, ["V7/V", "V7", "V7/V", "V7", "V7/V V7", "V7", "V7", "V7"], [3, 4], ["open", "open"], 76, 96, mot1, cells1, pn)
    # --- реприза: обе темы в соль мажоре (второй раз та же тональность вместо D)
    play(G, ["I", "I", "V7", "I", "IV", "I_5", "V7", "I"], [1, 2], ["half", "auth"], 74, 90, mot1, cells1, pn)
    play(G, ["I", "I_3", "IV", "V7", "I", "V7/vi", "vi", "ii V7", "I", "V7/V", "V", "V7", "I", "I"], [5, 6, 5, 7], ["half", "auth"], 76, 82, mot2, cells2, pn, fl)
    # кода: подтверждающие каденции и трель
    bc = bar_chords(P, G, ["IV", "I_5", "V7", "I"])
    ornament_trill(pn, P.pos + 4.0, 3.0, 76, G, 80, 2, 0.125)
    melody_into(pn, [(P.pos, 1, 79), (P.pos + 1, 1, 83), (P.pos + 2, 1, 81), (P.pos + 3, 1, 79), (P.pos + 7, 1, 74), (P.pos + 8, 1, 72), (P.pos + 9, 1, 74), (P.pos + 12, 3, 79)], 96, 0.95, 0)
    tex_alberti(P, bc, pl, 70, center=54, step=0.5)
    tex_bassline(P, bc, ce, 80, 33, 50, step=2.0, dur_f=1.4)
    advance(P, 4)
    final_chord(P, [pn, vl, vla, fl], roman("I", G), 70, 3, 86, 5.0)
    final_chord(P, [pl, ce], roman("I", G), 48, 2, 84, 5.0)
    P.rit.append((P.pos - 8, P.pos, 0.8))
    return P.pos


# ---------------- 14. Ударная вахта — полонез (в духе Шопена/Огинского), ля мажор → ре мажор, 3/4
@piece
def p_march2(P):
    P.bpm, P.bpb = 118, 3.0
    P.no_breath = True
    tp = P.track("trumpet", 56, vol=96, pan=46, rev=55)
    hn = P.track("horn", 60, vol=86, pan=84, rev=55)
    vl = P.track("violins", 48, vol=92, pan=44, rev=60)
    vl2 = P.track("violins2", 49, vol=80, pan=72, rev=60)
    cel = P.track("cello", 42, vol=88, pan=90, rev=55)
    tb = P.track("trombone", 57, vol=84, pan=76, rev=50)
    tu = P.track("tuba", 58, vol=90, rev=50)
    fl = P.track("flute", 73, vol=76, pan=36, rev=60)
    cl = P.track("clar", 71, vol=70, pan=60, rev=55)
    tm = P.track("timp", 47, vol=86, rev=50)
    d = P.drums(70)
    A, D, Fsm, E = Key("A"), Key("D"), Key("F#", "min"), Key("E")
    cells = [[1.5, 0.5, 0.5, 0.5], [1, 0.5, 0.5, 1], [1.5, 0.5, 1], [0.5, 0.5, 1, 1], [1.5, 0.5, 0.5, 0.5]]
    endc = [[2, 1], [1, 2], [1.5, 0.5, 1]]
    mot = [(1.5, 0), (0.5, 1), (0.5, 2), (0.5, 1)]

    def poly(bc, vel, lead_hi=False):
        """Полонезный ритм: бас на раз, аккорд «раз-и» на второй доле (восьмая, восьмая)."""
        for bi, bar in enumerate(bc):
            b0 = P.pos + bi * P.bpb
            for ch, off, dur in bar:
                bp = bass_note(ch, 33, 47)
                tu.add(b0 + off, 0.9, bp, vel)
                cel.add(b0 + off, 0.9, bp + 12, vel - 8)
                vs = voice(ch, 60, 3)
                for q in vs:
                    vl2.add(b0 + off + 1.0, 0.45, q, vel - 12)
                    vl2.add(b0 + off + 1.5, 0.45, q, vel - 16)
                    hn.add(b0 + off + 2.0, 0.8, q - 12 if q > 60 else q, vel - 28)
            d.add(b0, 0.2, 36, vel - 26)
            d.add(b0 + 1.0, 0.2, 38, vel - 36)
            d.add(b0 + 1.5, 0.2, 38, vel - 40)
            d.add(b0 + 2.0, 0.2, 38, vel - 40)
    fan = bar_chords(P, A, ["V7", "V7", "I", "I"])
    for bi in range(4):
        tm.add(P.pos + bi * 3, 0.5, 40, 60 + bi * 10)
        tm.add(P.pos + bi * 3 + 1.5, 0.5, 40, 56 + bi * 8)
        tm.add(P.pos + bi * 3 + 2.0, 0.5, 40, 56 + bi * 8)
    melody_into(tp, [(P.pos + 6, 1.5, 76), (P.pos + 7.5, 0.5, 80), (P.pos + 8, 1, 81), (P.pos + 9, 1.5, 85), (P.pos + 10.5, 1.5, 84)], 100, 0.9, 4)
    advance(P, 4)
    plan = [
        ("A", A, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "I_5 V7", "I"], [1, 2, 1, 3], ["half", "auth"], 76, 86),
        ("B", Fsm, ["i", "i", "V7", "i", "iv", "i", "V7", "i", "VI", "bII", "i_5", "V7", "i", "V7/III", "III", "V7/V"], [4, 5, 4, 6], ["half", "half"], 76, 90),
        ("A", A, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "I_5 V7", "I"], [1, 2, 1, 3], ["half", "auth"], 76, 100),
        ("T", D, ["I", "I", "IV", "I", "V7", "V7", "I", "I", "vi", "ii", "V7/V V", "V7", "I", "IV", "I_5 V7", "I"], [7, 8, 7, 9], ["half", "auth"], 74, 70),
        ("A", A, ["I", "I", "V7", "I", "I", "IV", "V7", "I", "vi", "V7/V", "V", "V7", "I", "IV", "I_5 V7", "I"], [1, 2, 1, 3], ["half", "auth"], 76, 106),
    ]
    for tag, key, bars, seeds, cads, st, vel in plan:
        mel, bc = phrase_melody(P, key, bars, 60, 92, st, seeds, cells, endc, cads, 4, mot, amp=7)
        n = len(bars)
        if tag == "T":
            melody_into(vl, mel, vel + 8, 0.95, 6)
            melody_into(fl, [(t, d, p + 12) for t, d, p in mel], vel - 12, 0.95, 0)
            melody_into(cl, counter_line(mel, bc, P.bpb, key, 54, 84, 2), vel - 14, 0.95, 0)
            poly(bc, vel - 24)
        else:
            melody_into(tp, mel, vel, 0.88, 8)
            melody_into(vl, [(t, d, p + 12) for t, d, p in mel], vel - 18, 0.88, 4)
            melody_into(tb, [(t, d, p - 12) for t, d, p in counter_line(mel, bc, P.bpb, key, 52, 84, 4)], vel - 22, 0.88, 0)
            poly(bc, vel)
        advance(P, n)
    # кода
    bc = bar_chords(P, A, ["IV", "ii", "V7:2 V7:1", "I"])
    melody_into(tp, [(P.pos, 1.5, 81), (P.pos + 1.5, 1.5, 78), (P.pos + 3, 1.5, 81), (P.pos + 4.5, 1.5, 85), (P.pos + 6, 3, 83), (P.pos + 9, 3, 81)], 108, 0.95, 0)
    poly(bc, 100)
    advance(P, 4)
    final_chord(P, [tp, vl, hn, vl2], roman("I", A), 72, 3, 100, 4.5)
    tu.add(P.pos, 4.5, 33, 100)
    tm.add(P.pos, 3, 45, 100)
    d.add(P.pos, 1.0, 49, 90)
    P.rit.append((P.pos - 4, P.pos, 0.85))
    return P.pos


# ================================================================== рендер

MIDI_DIR = os.path.join(ROOT, "tools", "midi_145")


def sh(cmd):
    return subprocess.run(cmd, capture_output=True, text=True)


def measure(path):
    det = sh(["ffmpeg", "-i", path, "-af", "volumedetect", "-f", "null", "-"]).stderr
    return float(det.split("mean_volume:")[1].split("dB")[0])


def render(name, mid):
    tmp = tempfile.mkdtemp()
    wav = os.path.join(tmp, "a.wav")
    sh(["fluidsynth", "-ni", "-g", "0.6", "-r", "44100", "-F", wav, SF2, mid])
    t1 = os.path.join(tmp, "t.wav")
    # тишина в начале и в конце — долой
    r = sh(["ffmpeg", "-loglevel", "error", "-y", "-i", wav, "-af",
            "silenceremove=start_periods=1:start_threshold=-55dB,areverse,silenceremove=start_periods=1:start_threshold=-48dB,areverse,aformat=channel_layouts=stereo",
            t1])
    dur = float(sh(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", t1]).stdout.strip())
    t2 = os.path.join(tmp, "c.wav")
    # мягкая компрессия: у фортепианных пьес большой разброс громкости, без неё лимитер «глотает» пики
    sh(["ffmpeg", "-loglevel", "error", "-y", "-i", t1, "-af", "acompressor=threshold=0.06:ratio=3:attack=25:release=350", t2])
    mean = measure(t2)
    out = os.path.join(OUT, name + ".ogg")
    fade = 3.0
    gain = TARGET_DB - mean
    for _ in range(3):
        sh(["ffmpeg", "-loglevel", "error", "-y", "-i", t2, "-af",
            "volume=%.2fdB,alimiter=limit=0.93,afade=t=out:st=%.2f:d=%.2f" % (gain, dur - fade, fade),
            "-c:a", "libvorbis", "-q:a", "5", "-ac", "2", out])
        got = measure(out)
        if abs(got - TARGET_DB) < 0.25:
            break
        gain += TARGET_DB - got
    return dur, mean


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    midi_only = "--midi-only" in sys.argv
    os.makedirs(MIDI_DIR, exist_ok=True)
    names = args or list(PIECES)
    for nm in names:
        P = Piece(nm, 100)
        end = PIECES[nm](P)
        finish_marks(P)
        mid = os.path.join(MIDI_DIR, nm + ".mid")
        P.write(mid, P.pos + 9)
        bar_s = P.bpb * 60.0 / P.bpm
        info = "%s: %.0f тактов-долей, фраза(4 такта)=%.2f с" % (nm, P.pos, bar_s * 4)
        if not midi_only:
            dur, mean = render(nm, mid)
            info += ", %.0f с, было %.1f дБ" % (dur, mean)
        print(info, flush=True)


if __name__ == "__main__":
    main()
