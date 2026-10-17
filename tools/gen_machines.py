#!/usr/bin/env python3
"""1.16 «Станки»: парк советских станков по пять на передел и станки с ЧПУ.

Спрайты строятся параметрически — семейство (токарный, фрезерный, сверлильный, сварка, сборка, печь,
покраска, ЧПУ) × размер × окраска. Для каждого станка три вида: спереди, сбоку («_v», рабочая сторона
слева, футпринт повёрнут) и со спины («_b»). Якоря (лампа, патрон, резец, рабочая точка, вход, выход,
свечение печи, туман краски, вспышка сварки) — те же имена, что у старых станков.

Запуск — из gen_assets.py: gen_machines.run(ga), где ga — модуль генератора (общие помощники и META).
"""
import math

ga = None
OUT = "#23262a"

PAL = {
    "green": ("#7d9283", "#5e7364"),
    "bluegrey": ("#8e9fa8", "#6f8089"),
    "cream": ("#c9c2a4", "#a8a084"),
    "lgrey": ("#b4bcc0", "#949ca0"),
    "dkgreen": ("#62806c", "#4a6453"),
    "blue": ("#6d8fae", "#52728f"),
    "olive": ("#8c8f6a", "#6e7152"),
}
STEEL, STEEL_D, STEEL_L = "#9aa3a8", "#7b8286", "#cdd3d7"
DARK = "#3a3f43"
WOOD, WOOD_D = "#a8845a", "#6b5236"


def dark(c, k=0.78):
    c = c.lstrip("#")
    r, g, b = (int(c[i:i + 2], 16) for i in (0, 2, 4))
    return "#%02x%02x%02x" % (int(r * k), int(g * k), int(b * k))


def R(*a, **k):
    return ga.rect(*a, **k)


def C(*a, **k):
    return ga.circ(*a, **k)


def L(*a, **k):
    return ga.line(*a, **k)


def P(*a, **k):
    return ga.path(*a, **k)


def B(*a, **k):
    return ga.box(*a, **k)


def lamp(x, y):
    return R(x - 5, y - 4, 10, 8, DARK, OUT, 1) + C(x, y, 2.4, "#c94a3a", None, 0)


def wheel(x, y, r=6, col="#c9ccce"):
    return C(x, y, r, None, col, 2.0) + L(x - r, y, x + r, y, col, 1.1) + L(x, y - r, x, y + r, col, 1.1)


def save(key, wt, ht, T0, body, anchors):
    ga.obj(key, wt, ht, T0, body)
    ga.META[key]["anchors"] = anchors


# =============================================================== токарные

def lathe(key, wt, pal, kind):
    """Токарно-винторезный: bench (настольный на тумбе), small, std, heavy."""
    GT, GF = PAL[pal]
    W = wt * 64
    Ln = W - 8
    s = {"bench": 0.8, "small": 0.86, "std": 1.0, "heavy": 1.18}[kind]
    hw = int(52 * s)
    hx = int((s - 1.0) * 40)
    cw, ch = int(13 * s), int(26 * s)
    tw = int(38 * s)
    # ---- спереди
    T0 = 44 + max(0, hx)
    b = ga.shadow(12, T0 - 8 - hx, W - 6, 82 + hx)
    if kind == "bench":
        # тумба-стол, станок сверху
        b += B(2, T0 + 18, W - 4, 8, 36, "#8a8f86", "#6e736a")
        b += R(8, T0 + 30, (W - 20) // 2, 22, None, "#565b54", 1.3) + R(W // 2 + 2, T0 + 30, (W - 20) // 2, 22, None, "#565b54", 1.3)
        base = T0 - 2
    else:
        base = T0 + 10
        LEG = dark(GF, 0.82)
        b += R(4, T0 + 40, hw - 8, 22, LEG, OUT, 2) + R(4 + Ln - 44, T0 + 40, 44, 22, LEG, OUT, 2)
        b += R(hw - 4, T0 + 42, Ln - hw - 40, 18, "#33383c", OUT, 2)
        b += P(f"M{hw + 4} {T0+52}q4 -5 8 0t8 0M{hw + 34} {T0+56}q3 -4 6 0t6 0", None, "#b9c2c8", 1.5)
    bh = 18 if kind != "bench" else 12
    b += R(4, base, Ln, bh, "#8b9296", OUT, 2)
    b += L(4, base + 5, 4 + Ln, base + 5, "#b2b9bd", 1.4) + L(4, base + bh - 5, 4 + Ln, base + bh - 5, "#b2b9bd", 1.4)
    if kind != "bench":
        b += R(4, base + bh, Ln, 14, "#5c6267", OUT, 2) + L(hw + 8, base + bh + 7, 2 + Ln, base + bh + 7, "#9aa1a5", 2)
    hy = base - 28 - hx
    b += B(4, hy, hw, 20 + max(0, hx // 3), 30 + hx - max(0, hx // 3), GT, GF)
    b += C(4 + hw * 0.25, hy + 34 + hx * 0.6, 4.5 * s, "#c9ccce", OUT, 1.1) + C(4 + hw * 0.55, hy + 34 + hx * 0.6, 4.5 * s, "#c9ccce", OUT, 1.1)
    b += L(4 + hw * 0.8, hy + 30, 4 + hw * 0.95, hy + 22, "#2a2e31", 2.0) + C(4 + hw * 0.95, hy + 22, 2.4, "#b0483d", None, 0)
    lx, ly = 4 + hw * 0.32, hy + 8
    b += lamp(lx, ly)
    x0 = 4 + hw
    cy = base + bh / 2 - ch / 2 + 2
    b += R(x0, cy, cw, ch, "#9ca3a7", OUT, 2, 2)
    tx = 4 + Ln - tw - 4
    car = x0 + cw + (tx - x0 - cw) * 0.38
    b += R(x0 + cw, base + bh / 2 - 3, car - x0 - cw + 12, 8, STEEL_L, OUT, 1.4)
    b += L(x0 + cw, base + bh / 2 - 1, car + 10, base + bh / 2 - 1, "#fff", 1.1, 0.7)
    b += B(car, base - 8, 30 * s, 14 * s, 14 * s, "#6f8275" if pal != "cream" else "#9a9278", "#55665a" if pal != "cream" else "#7c755f")
    b += R(car + 6, base - 7, 12 * s, 8, DARK, OUT, 1.1) + L(car + 6, base - 3, car + 1, base - 2, "#e8e0c0", 2.4)
    if kind != "bench":
        b += wheel(car + 15 * s, base + bh + 16, 5.5 * s)
    b += B(tx, base - 12, tw, 14, 16, GT, GF)
    b += R(tx - 14, base + 1, 14, 6, "#aab1b5", OUT, 1.1)
    b += C(4 + Ln - 2, base + 8, 5 * s, None, "#c9ccce", 1.8)
    b += P(f"M{4 + hw * 0.7} {hy + 4}Q{car - 10} {hy - 14} {car + 8} {base - 8}", None, "#3f6f9a", 2.2, dash="3 1.4")
    save(key, wt, 1, T0, b, {"chuck": [x0, cy, cw, ch], "tool": [car + 4, base], "lamp": [lx, ly],
                              "bar": [car - 6, T0 + 60], "out": [4 + Ln - 40, T0 + 40], "light": [car - 16, base - 14]})
    # ---- сбоку (1×wt): бабка сверху, станина вниз, рабочая сторона слева
    H = wt * 64
    T1 = 46 + max(0, hx)
    b = ga.shadow(12, T1 - 10, 52, H + 6)
    b += R(14, T1 + 30, 36, H - 44, "#5c6267", OUT, 2) + R(20, T1 + 30, 24, H - 50, "#8b9296", OUT, 1.6)
    b += L(26, T1 + 32, 26, T1 + H - 22, "#b2b9bd", 1.3) + L(38, T1 + 32, 38, T1 + H - 22, "#b2b9bd", 1.3)
    b += R(4, T1 + 60, 10, H - 92, "#33383c", OUT, 1.4)
    b += B(10, T1 - 26 - hx, 44, 44, 26 + hx, GT, GF)
    b += lamp(18, T1 - 17 - hx)
    b += R(22, T1 + 44, 20, 12 * s, "#9ca3a7", OUT, 1.6, 2) + R(28, T1 + 56, 8, H * 0.18, STEEL_L, OUT, 1.2)
    cy2 = T1 + H * 0.5
    b += B(6, cy2, 52, 18, 10, "#6f8275" if pal != "cream" else "#9a9278", "#55665a" if pal != "cream" else "#7c755f")
    b += wheel(4, cy2 + 12, 5)
    b += B(18, T1 + H - 52, 28, 20, 14, GT, GF)
    b += R(12, T1 + H - 14, 40, 14, dark(GF, 0.82), OUT, 2)
    save(key + "_v", 1, wt, T1, b, {"lamp": [18, T1 - 17 - hx], "work": [32, T1 + 70], "bar": [-6, T1 + H - 22], "out": [6, T1 + H - 16]})
    # ---- со спины: бабка справа, гладкие кожухи
    b = ga.shadow(12, T0 - 8 - hx, W - 6, 82 + hx)
    if kind == "bench":
        b += B(2, T0 + 18, W - 4, 8, 36, "#8a8f86", "#6e736a")
    else:
        b += R(4, T0 + 40, 44, 22, dark(GF, 0.82), OUT, 2) + R(4 + Ln - hw + 8, T0 + 40, hw - 8, 22, dark(GF, 0.82), OUT, 2)
        b += R(48, T0 + 42, Ln - hw - 40, 18, DARK, OUT, 2)
    b += R(4, base, Ln, bh, "#8b9296", OUT, 2)
    if kind != "bench":
        b += R(4, base + bh, Ln, 14, "#5c6267", OUT, 2) + R(60, base + bh + 4, Ln - 120, 6, "#6a7075", None, 0, 1)
    b += B(4 + Ln - hw, hy, hw, 20 + max(0, hx // 3), 30 + hx - max(0, hx // 3), GT, GF)
    for k in range(4):
        b += L(4 + Ln - hw + 4, hy + 26 + k * 6, 4 + Ln - 4, hy + 26 + k * 6, "#4f6056", 1.2)
    b += lamp(4 + Ln - hw * 0.3, hy + 8)
    b += B(8, base - 12, tw, 14, 16, GT, GF)
    b += B(W * 0.4, base - 8, 30 * s, 14 * s, 14 * s, "#6f8275", "#55665a")
    save(key + "_b", wt, 1, T0, b, {"lamp": [4 + Ln - hw * 0.3, hy + 8], "work": [W * 0.55, base], "bar": [W * 0.45, T0 + 60], "out": [40, T0 + 40]})


# =============================================================== фрезерные

def mill(key, wt, pal, kind):
    """Консольно-фрезерный: vertical (головка с вертикальным шпинделем) / horizontal (хобот и оправка)."""
    GT, GF = PAL[pal]
    W = wt * 64
    big = wt >= 3
    T0 = 74 + (10 if big else 0) + (12 if kind == "horizontal" else 0)
    cx = W * 0.42
    cwid = 54 if not big else 66
    b = ga.shadow(14, T0 - 10, W - 8, 76)
    b += B(cx - cwid / 2, T0 - 62 - (10 if big else 0), cwid, 10, 72 + (10 if big else 0), GT, GF)          # колонна
    if kind == "vertical":
        b += B(cx - cwid / 2 - 10, T0 - 70 - (10 if big else 0), cwid + 20, 12, 22, GT, GF)                  # головка
        b += R(cx - 7, T0 - 36, 14, 10, STEEL, OUT, 1.5) + R(cx - 4, T0 - 26, 8, 12, "#c9ccce", OUT, 1.2)
        b += R(cx - 9, T0 - 14, 18, 6, "#5a6268", OUT, 1.2)
        for k in range(5):
            b += L(cx - 8 + k * 4, T0 - 14, cx - 6 + k * 4, T0 - 8, "#d0d5d8", 1)
        work = [cx, T0 - 10]
    else:
        b += B(cx - cwid / 2 - 4, T0 - 74, W * 0.62, 10, 14, GT, GF)                                         # хобот
        b += R(cx - 30, T0 - 52, 60, 6, STEEL, OUT, 1.2)                                                       # оправка
        b += R(cx - 10, T0 - 58, 20, 18, "#5a6268", OUT, 1.4)
        for k in range(5):
            b += L(cx - 9 + k * 4, T0 - 58, cx - 9 + k * 4, T0 - 40, "#d0d5d8", 1)
        b += R(cx + W * 0.25, T0 - 64, 8, 26, GF, OUT, 1.2)                                                    # серьга
        work = [cx, T0 - 30]
    mx = cx + cwid / 2 + 2
    b += B(mx, T0 - 66, 26, 10, 18, dark(GT, 0.9), dark(GF, 0.9))  # двигатель на колонне
    for k in range(4):
        b += L(mx + 2, T0 - 54 + k * 4, mx + 24, T0 - 54 + k * 4, dark(GF, 0.7), 1.2)
    b += B(6, T0 - 8, W - 12, 14, 10, "#9aa1a5", "#7b8286")                                                    # стол
    for k in range(3):
        b += L(8, T0 - 4 + k * 4, W - 8, T0 - 4 + k * 4, "#5f666a", 1.2)
    b += B(cx - 22, T0 + 16, 44, 8, 34, GT, GF)                                                                # консоль
    b += wheel(20, T0 + 10, 7) + wheel(W - 20, T0 + 10, 7) + wheel(cx + 36, T0 + 34, 5)
    lx, ly = cx + cwid / 2 - 12, T0 - 43
    b += lamp(lx, ly)
    b += P(f"M{cx - cwid / 2 + 4} {T0-56}Q{cx - cwid / 2 - 10} {T0-40} {cx - 12} {T0-18}", None, "#3f6f9a", 2.2, dash="3 1.4")
    b += R(cx - 18, T0 + 52, 36, 8, "#4e5f54", OUT, 1.5)
    save(key, wt, 1, T0, b, {"lamp": [lx, ly], "work": work, "in": [18, T0 - 6], "out": [W - 24, T0 - 6]})
    # сбоку
    H = wt * 64
    b = ga.shadow(10, T0 - 4, 54, H + 2)
    b += B(14, T0 + 40, 26, 8, 34, GT, GF)
    b += B(6, T0 + 8, 36, H - 28, 10, "#9aa1a5", "#7b8286")
    for k in range(3):
        b += L(13 + k * 8, T0 + 10, 13 + k * 8, T0 + H - 22, "#5f666a", 1.2)
    b += B(42, T0 + 2, 18, 12, H * 0.7, GT, GF)
    b += B(12, T0 + 14, 48, 12, 22, GT, GF)
    b += R(20, T0 + 36, 14, 8, STEEL, OUT, 1.5) + R(21, T0 + 50, 12, 5, "#5a6268", OUT, 1.2)
    b += wheel(4, T0 + 40, 6) + wheel(4, T0 + H * 0.65, 5)
    b += lamp(52, T0 + 54)
    b += R(14, T0 + H - 16, 30, 8, "#4e5f54", OUT, 1.5)
    save(key + "_v", 1, wt, T0, b, {"lamp": [52, T0 + 54], "work": [26, T0 + 60], "in": [20, T0 + 20], "out": [20, T0 + H - 30]})
    # со спины
    b = ga.shadow(14, T0 - 10, W - 8, 76)
    b += B(6, T0 - 8, W - 12, 14, 10, "#9aa1a5", "#7b8286")
    b += B(cx - cwid / 2, T0 - 62, cwid, 10, 72, GT, GF)
    for k in range(5):
        b += L(cx - cwid / 2 + 6, T0 - 44 + k * 10, cx + cwid / 2 - 6, T0 - 44 + k * 10, "#4f6056", 1.4)
    b += B(cx - cwid / 2 - 10, T0 - 70, cwid + 20, 12, 22, GT, GF)
    b += B(6, T0 - 66, 26, 10, 18, GF, GF)
    b += B(cx - 22, T0 + 16, 44, 8, 34, GT, GF)
    b += lamp(cx - cwid / 2 + 10, T0 - 43)
    save(key + "_b", wt, 1, T0, b, {"lamp": [cx - cwid / 2 + 10, T0 - 43], "work": [cx, T0 - 12], "in": [W - 18, T0 - 6], "out": [18, T0 - 6]})


# =============================================================== сверлильные

def drill(key, wt, ht, pal, kind):
    """bench — настольный, column — вертикально-сверлильный, radial — радиально-сверлильный."""
    GT, GF = PAL[pal]
    W, H = wt * 64, ht * 64
    if kind == "radial":
        T0 = 96
        b = ga.shadow(14, T0 - 20, W - 10, H + 10)
        b += B(4, T0 + H - 46, W - 8, 12, 30, "#5c6267", "#464b4f")                       # плита
        b += R(16, T0 + H - 40, W - 32, 4, STEEL_L, None, 0, 0, 0.6)
        b += B(14, T0 - 76, 22, 10, H + 34, GT, GF)                                           # колонна
        b += B(8, T0 - 60, W - 20, 12, 16, GT, GF)                                            # рукав
        b += B(W * 0.55, T0 - 66, 34, 12, 40, GT, GF)                                         # головка
        b += R(W * 0.55 + 13, T0 - 14, 8, 24, STEEL_L, OUT, 1.2) + P(f"M{W*0.55+17} {T0+10}l-2 5h4z", STEEL_L, OUT, 0.8)
        b += B(W * 0.3, T0 + H - 80, 50, 10, 24, "#7b8286", "#5f666a")                         # стол-куб
        lx, ly = W * 0.55 + 26, T0 - 52
        b += lamp(lx, ly)
        for a in (0, 2.1, 4.2):
            b += L(W * 0.55 + 4, T0 - 40, W * 0.55 + 4 + math.cos(a) * 10, T0 - 40 + math.sin(a) * 5, "#2a2e31", 1.8)
        save(key, wt, ht, T0, b, {"lamp": [lx, ly], "work": [W * 0.55 + 17, T0 + 14], "in": [W * 0.3 + 6, T0 + H - 74], "out": [W - 24, T0 + H - 40]})
        save(key + "_v", ht, wt, T0, b, {"lamp": [lx, ly], "work": [W * 0.55 + 17, T0 + 14], "in": [W * 0.3 + 6, T0 + H - 74], "out": [W - 24, T0 + H - 40]})
        b = ga.shadow(14, T0 - 20, W - 10, H + 10)
        b += B(4, T0 + H - 46, W - 8, 12, 30, "#5c6267", "#464b4f")
        b += B(W - 36, T0 - 76, 22, 10, H + 34, GT, GF)
        b += B(12, T0 - 60, W - 20, 12, 16, GT, GF)
        b += B(W * 0.2, T0 - 66, 34, 12, 40, GT, GF)
        b += lamp(W * 0.2 + 8, T0 - 52)
        save(key + "_b", wt, ht, T0, b, {"lamp": [W * 0.2 + 8, T0 - 52], "work": [W * 0.2 + 17, T0 + 14], "in": [W * 0.6, T0 + H - 74], "out": [24, T0 + H - 40]})
        return
    tall = kind == "column"
    heavy = key.endswith("2n150")
    T0 = 94 if tall else 52
    b = ga.shadow(14, T0 - 12, 50, 72)
    if tall:
        b += R(10, T0 + 36, 48, 18, "#4e5f54" if pal == "green" else GF, OUT, 2, 2)
        cw = 12 if not heavy else 16
        b += R(36, T0 - 60, cw, 98, "#a8b0b4", OUT, 2, 3) + L(39, T0 - 58, 39, T0 + 34, "#fff", 1.4, 0.5)
        b += B(14 if heavy else 16, T0 - 76 - (6 if heavy else 0), 44 if heavy else 40, 9, 26 + (6 if heavy else 0), GT, GF)
        b += B(22, T0 - 88 - (6 if heavy else 0), 26, 8, 10, GF, GF)
        b += R(22, T0 - 44, 12, 14, STEEL, OUT, 1.5) + R(26, T0 - 30, 4, 12, "#d0d5d8", OUT, 1)
        for a in (0, 2.1, 4.2):
            b += L(44, T0 - 54, 44 + math.cos(a) * 12, T0 - 54 + math.sin(a) * 6, "#2a2e31", 2)
            b += C(44 + math.cos(a) * 12, T0 - 54 + math.sin(a) * 6, 2.4, "#1d1d1d", None, 0)
        b += B(12, T0 - 2, 34, 8, 6, "#9aa1a5", "#7b8286")
        lx, ly = 24.5, T0 - 66.5
        work = [28, T0 - 10]
        ins, outs = [16, T0 + 2], [40, T0 + 2]
    else:
        # настольный: тумба, на ней маленький станок
        b += B(6, T0 + 10, 52, 8, 34, "#8a8f86", "#6e736a")
        b += R(30, T0 - 34, 8, 46, "#a8b0b4", OUT, 1.6, 2)
        b += B(14, T0 - 44, 32, 8, 18, GT, GF)
        b += R(20, T0 - 18, 8, 10, STEEL, OUT, 1.2) + R(22.5, T0 - 8, 3, 9, "#d0d5d8", OUT, 0.8)
        b += L(40, T0 - 30, 52, T0 - 34, "#2a2e31", 1.8) + C(52, T0 - 34, 2, "#1d1d1d", None, 0)
        b += B(14, T0 + 2, 28, 6, 4, "#9aa1a5", "#7b8286")
        lx, ly = 20, T0 - 40
        work = [24, T0 + 2]
        ins, outs = [12, T0 + 6], [48, T0 + 6]
    b += lamp(lx, ly)
    save(key, 1, 1, T0, b, {"lamp": [lx, ly], "work": work, "in": ins, "out": outs})
    # сбоку и со спины — 1×1, тот же станок под другим углом (колонна сзади-справа)
    bv = ga.shadow(14, T0 - 12, 50, 72)
    if tall:
        bv += R(10, T0 + 36, 48, 18, "#4e5f54" if pal == "green" else GF, OUT, 2, 2)
        bv += R(40, T0 - 60, 12, 98, "#a8b0b4", OUT, 2, 3)
        bv += B(18, T0 - 76, 36, 9, 26, GT, GF)
        bv += R(22, T0 - 44, 12, 14, STEEL, OUT, 1.5) + R(26, T0 - 30, 4, 12, "#d0d5d8", OUT, 1)
        bv += B(12, T0 - 2, 34, 8, 6, "#9aa1a5", "#7b8286")
    else:
        bv += B(6, T0 + 10, 52, 8, 34, "#8a8f86", "#6e736a") + R(36, T0 - 34, 8, 46, "#a8b0b4", OUT, 1.6, 2)
        bv += B(16, T0 - 44, 30, 8, 18, GT, GF) + R(22, T0 - 18, 8, 10, STEEL, OUT, 1.2)
    bv += lamp(lx, ly)
    save(key + "_v", 1, 1, T0, bv, {"lamp": [lx, ly], "work": work, "in": ins, "out": outs})
    bb = ga.shadow(14, T0 - 12, 50, 72)
    if tall:
        bb += R(10, T0 + 36, 48, 18, "#4e5f54" if pal == "green" else GF, OUT, 2, 2)
        bb += B(12, T0 - 2, 34, 8, 6, "#9aa1a5", "#7b8286")
        bb += R(26, T0 - 60, 12, 98, "#a8b0b4", OUT, 2, 3)
        bb += B(14, T0 - 76, 40, 9, 26, GT, GF)
        for k in range(3):
            bb += L(18, T0 - 60 + k * 6, 50, T0 - 60 + k * 6, "#4f6056", 1.2)
    else:
        bb += B(6, T0 + 10, 52, 8, 34, "#8a8f86", "#6e736a") + R(26, T0 - 34, 8, 46, "#a8b0b4", OUT, 1.6, 2)
        bb += B(14, T0 - 44, 32, 8, 18, GT, GF)
    bb += lamp(lx, ly)
    save(key + "_b", 1, 1, T0, bb, {"lamp": [lx, ly], "work": work, "in": outs, "out": ins})


# =============================================================== сварка

def welder(key, wt, ht, kind):
    """manual — ручная дуговая (трансформатор на колёсах), semi — полуавтомат, spot — точечная машина,
    stand — сварочный стенд с кантователем."""
    W, Hh = wt * 64, ht * 64
    if kind == "spot":
        T0 = 70
        b = ga.shadow(12, T0 - 20, 50, 82)
        b += B(10, T0 - 30, 44, 10, 92, "#6d8fae", "#52728f")
        b += R(4, T0 - 44, 46, 10, "#52728f", OUT, 1.6) + R(4, T0 + 20, 46, 10, "#52728f", OUT, 1.6)       # хоботы
        b += R(6, T0 - 34, 6, 12, "#c98d63", OUT, 1.2) + R(6, T0 + 8, 6, 12, "#c98d63", OUT, 1.2)          # электроды
        b += R(36, T0 - 10, 14, 12, "#2a2e31", OUT, 1) + C(43, T0 + 40, 2.4, "#6fbf86", None, 0)
        b += R(14, T0 + 58, 40, 6, "#2a2e31", OUT, 1)
        lx, ly = 43, T0 + 40
        save(key, 1, 1, T0, b, {"lamp": [lx, ly], "work": [9, T0 - 4], "flash": [9, T0 - 4], "in": [30, T0 + 54], "out": [50, T0 + 54]})
        save(key + "_v", 1, 1, T0, b, {"lamp": [lx, ly], "work": [9, T0 - 4], "flash": [9, T0 - 4], "in": [30, T0 + 54], "out": [50, T0 + 54]})
        bb = ga.shadow(12, T0 - 20, 50, 82) + B(10, T0 - 30, 44, 10, 92, "#6d8fae", "#52728f")
        for k in range(5):
            bb += L(16, T0 - 6 + k * 8, 48, T0 - 6 + k * 8, "#3f5a72", 1.4)
        bb += R(40, T0 - 44, 20, 10, "#52728f", OUT, 1.6)
        save(key + "_b", 1, 1, T0, bb, {"lamp": [lx, ly], "work": [50, T0 - 4], "flash": [50, T0 - 4], "in": [50, T0 + 54], "out": [30, T0 + 54]})
        return
    if kind == "stand":
        T0 = 56
        b = ga.shadow(14, T0 - 10, W - 10, Hh + 6)
        b += B(10, T0 + Hh - 62, W - 20, 10, 40, "#5c6267", "#464b4f")                                     # основание
        b += B(14, T0 - 6, 22, 10, Hh + 10, "#d9b13b", "#b8932c") + B(W - 36, T0 - 6, 22, 10, Hh + 10, "#d9b13b", "#b8932c")   # стойки кантователя
        b += R(36, T0 + 24, W - 72, 46, "#6a7074", OUT, 2)                                                  # рама на кантователе
        b += R(44, T0 + 32, W - 88, 30, None, "#3e4246", 2)
        for k in range(4):
            b += L(44 + k * (W - 88) / 3, T0 + 32, 44 + k * (W - 88) / 3, T0 + 62, "#3e4246", 2)
        b += C(25, T0 + 46, 9, "#8a6e20", OUT, 1.6) + C(W - 25, T0 + 46, 9, "#8a6e20", OUT, 1.6)
        b += B(W - 30, T0 - 40, 26, 10, 40, "#d9b13b", "#b8932c") + R(W - 26, T0 - 24, 14, 9, "#2a2e31", OUT, 1)
        b += R(4, T0 - 48, 10, 46, "#4a7f78", OUT, 1.6, 4)
        b += P(f"M{W - 28} {T0 - 10}Q{W * 0.6} {T0 + 20} {W * 0.5} {T0 + 40}", None, "#1d1d1d", 2.4)
        lx, ly = W - 18, T0 - 19
        b += C(lx, ly, 2.4, "#6fbf86", None, 0)
        an = {"lamp": [lx, ly], "work": [W * 0.5, T0 + 44], "flash": [W * 0.5, T0 + 44], "in": [24, T0 + Hh - 30], "out": [W - 24, T0 + Hh - 30]}
        save(key, wt, ht, T0, b, an)
        bv = ga.shadow(14, T0 - 10, Hh - 10, W + 6)
        bv += B(10, T0 + 10, Hh - 20, W - 40, 30, "#5c6267", "#464b4f")
        bv += B(10, T0 - 6, Hh - 20, 12, 18, "#d9b13b", "#b8932c") + B(10, T0 + W - 40, Hh - 20, 12, 18, "#d9b13b", "#b8932c")
        bv += R(24, T0 + 24, Hh - 48, W - 70, "#6a7074", OUT, 2) + R(30, T0 + 30, Hh - 60, W - 82, None, "#3e4246", 2)
        bv += C(Hh - 18, T0 + 4, 2.4, "#6fbf86", None, 0)
        save(key + "_v", ht, wt, T0, bv, {"lamp": [Hh - 18, T0 + 4], "work": [Hh * 0.5, T0 + W * 0.45], "flash": [Hh * 0.5, T0 + W * 0.45], "in": [16, T0 + 30], "out": [16, T0 + W - 30]})
        bb = ga.shadow(14, T0 - 10, W - 10, Hh + 6)
        bb += B(10, T0 + Hh - 62, W - 20, 10, 40, "#5c6267", "#464b4f")
        bb += B(14, T0 - 6, 22, 10, Hh + 10, "#d9b13b", "#b8932c") + B(W - 36, T0 - 6, 22, 10, Hh + 10, "#d9b13b", "#b8932c")
        bb += R(36, T0 + 24, W - 72, 46, "#6a7074", OUT, 2)
        bb += B(6, T0 - 40, 26, 10, 40, "#d9b13b", "#b8932c")
        bb += C(18, T0 - 19, 2.4, "#6fbf86", None, 0)
        save(key + "_b", wt, ht, T0, bb, {"lamp": [18, T0 - 19], "work": [W * 0.5, T0 + 44], "flash": [W * 0.5, T0 + 44], "in": [W - 24, T0 + Hh - 30], "out": [24, T0 + Hh - 30]})
        return
    # manual / semi: стол 2×1 + аппарат
    T0 = 46
    b = ga.shadow(12, T0, W - 6, 64)
    b += B(4, T0 + 2, 84, 26, 30, "#6a7074", "#4f5458")
    for yy in range(3):
        for xx in range(7):
            b += C(12 + xx * 11, T0 + 8 + yy * 7, 1.5, "#3a3e42", None, 0)
    b += R(8, T0 + 34, 4, 22, "#3a3e42", None, 0) + R(80, T0 + 34, 4, 22, "#3a3e42", None, 0)
    if kind == "manual":
        b += B(94, T0 + 10, 30, 10, 34, "#5d6b5f", "#46524a")                                               # трансформатор
        for k in range(4):
            b += L(98, T0 + 26 + k * 5, 120, T0 + 26 + k * 5, "#3a443c", 1.2)
        b += C(100, T0 + 50, 4, "#2a2e31", OUT, 1) + C(118, T0 + 50, 4, "#2a2e31", OUT, 1)
        b += R(98, T0 + 12, 12, 7, "#2a2e31", OUT, 1)
        lx, ly = 116, T0 + 16
        b += P(f"M96 {T0+24}Q66 {T0+46} 50 {T0+18}", None, "#1d1d1d", 2.4)
        b += R(44, T0 + 12, 10, 3, "#c98d63", OUT, 0.8)
    else:
        b += B(94, T0 - 6, 30, 10, 44, "#c94a3a", "#a83a2c")                                                 # полуавтомат
        b += R(98, T0 + 8, 14, 9, "#2a2e31", OUT, 1) + C(104, T0 + 26, 4, None, OUT, 1.4)
        b += C(109, T0 - 1, 7, "#5a3a2a", OUT, 1.3) + C(109, T0 - 1, 3, "#c98d63", None, 0)
        b += R(116, T0 - 40, 9, 42, "#3d6a9a", OUT, 1.6, 4)
        lx, ly = 118, T0 + 12
        b += P(f"M96 {T0+20}Q70 {T0+44} 52 {T0+18}", None, "#1d1d1d", 2.4)
        b += R(46, T0 + 10, 8, 4, DARK, OUT, 1)
    b += C(lx, ly, 2.4, "#6fbf86", None, 0)
    save(key, 2, 1, T0, b, {"lamp": [lx, ly], "work": [40, T0 + 10], "flash": [40, T0 + 10], "in": [14, T0 + 4], "out": [72, T0 + 4]})
    bv = ga.shadow(12, T0 - 6, 52, 132)
    bv += B(6, T0 + 2, 48, 66, 26, "#6a7074", "#4f5458")
    for yy in range(8):
        for xx in range(4):
            bv += C(14 + xx * 11, T0 + 8 + yy * 8, 1.4, "#3a3e42", None, 0)
    bv += B(8, T0 + 96, 30, 10, 26, "#5d6b5f" if kind == "manual" else "#c94a3a", "#46524a" if kind == "manual" else "#a83a2c")
    bv += C(31, T0 + 112, 2.4, "#6fbf86", None, 0)
    bv += P(f"M14 {T0+104}Q-2 {T0+80} 14 {T0+46}", None, "#1d1d1d", 2.4)
    save(key + "_v", 1, 2, T0, bv, {"lamp": [31, T0 + 112], "work": [26, T0 + 34], "flash": [26, T0 + 34], "in": [12, T0 + 10], "out": [46, T0 + 20]})
    bb = ga.shadow(12, T0, W - 6, 64)
    bb += B(40, T0 + 2, 84, 26, 30, "#6a7074", "#4f5458")
    bb += B(6, T0 + (10 if kind == "manual" else -6), 30, 10, 34 if kind == "manual" else 44, "#5d6b5f" if kind == "manual" else "#c94a3a", "#46524a" if kind == "manual" else "#a83a2c")
    bb += C(12, T0 + 16, 2.4, "#6fbf86", None, 0)
    bb += P(f"M30 {T0+20}Q52 {T0+40} 84 {T0+14}", None, "#1d1d1d", 2.4)
    save(key + "_b", 2, 1, T0, bb, {"lamp": [12, T0 + 16], "work": [88, T0 + 10], "flash": [88, T0 + 10], "in": [114, T0 + 4], "out": [56, T0 + 4]})


# =============================================================== сборка

def assembly(key, wt, ht, kind):
    """bench — верстак сборщика 1×1, press — стол с прессом 2×1, stand — сборочный стенд 3×2,
    line — участок на рольганге 4×1."""
    W, Hh = wt * 64, ht * 64
    if kind == "bench":
        T0 = 40
        b = ga.shadow(12, T0 + 4, 50, 62)
        b += B(4, T0 + 4, 56, 22, 32, "#7d8a92", "#5e6a72")
        b += R(8, T0 + 30, 48, 26, None, "#4a555c", 1.3)
        b += R(10, T0 - 2, 16, 8, "#3d5a7a", OUT, 1.3) + R(8, T0 + 2, 20, 3, "#8b9296", OUT, 1)
        b += R(36, T0 - 26, 6, 30, "#4a555c", OUT, 1.2) + R(30, T0 - 30, 22, 8, "#c94a3a", OUT, 1.2)    # щит с инструментом
        lx, ly = 48, T0 - 26
        b += C(lx, ly, 2.3, "#6fbf86", None, 0)
        an = {"lamp": [lx, ly], "work": [30, T0 + 12], "in": [12, T0 + 14], "out": [50, T0 + 18]}
        save(key, 1, 1, T0, b, an)
        save(key + "_v", 1, 1, T0, b, an)
        save(key + "_b", 1, 1, T0, ga.shadow(12, T0 + 4, 50, 62) + B(4, T0 + 4, 56, 22, 32, "#7d8a92", "#5e6a72") + R(12, T0 - 26, 6, 30, "#4a555c", OUT, 1.2), an)
        return
    if kind == "press":
        T0 = 70
        b = ga.shadow(12, T0 - 20, W - 6, 86)
        b += B(2, T0 + 4, W - 4, 22, 32, "#7d8a92", "#5e6a72")
        b += B(W - 52, T0 - 60, 44, 10, 66, "#c9a24a", "#a8862f")                                             # пресс П6324
        b += R(W - 40, T0 - 30, 20, 30, "#3a3f43", OUT, 1.4) + R(W - 34, T0 - 2, 8, 6, STEEL_L, OUT, 1)
        b += R(W - 48, T0 - 54, 14, 10, "#2a2e31", OUT, 1)
        b += R(10, T0 - 4, 22, 10, "#3d5a7a", OUT, 1.5) + R(6, T0, 30, 4, "#8b9296", OUT, 1.2)
        b += R(42, T0 + 6, 12, 7, "#2a2e31", OUT, 1, 2) + L(54, T0 + 9, 62, T0 + 9, "#c9ccce", 2)
        lx, ly = W - 41, T0 - 49
        b += C(lx, ly, 2.4, "#6fbf86", None, 0)
        an = {"lamp": [lx, ly], "work": [W - 30, T0 + 2], "in": [16, T0 + 12], "out": [W * 0.5, T0 + 18]}
        save(key, 2, 1, T0, b, an)
        bv = ga.shadow(12, T0 - 20, 52, 124 + 20) + B(4, T0 + 2, 56, 98, 26, "#7d8a92", "#5e6a72")
        bv += B(30, T0 - 50, 28, 8, 56, "#c9a24a", "#a8862f") + R(36, T0 - 26, 16, 22, "#3a3f43", OUT, 1.3)
        bv += C(46, T0 - 44, 2.4, "#6fbf86", None, 0)
        save(key + "_v", 1, 2, T0, bv, {"lamp": [46, T0 - 44], "work": [44, T0], "in": [14, T0 + 14], "out": [44, T0 + 86]})
        bb = ga.shadow(12, T0 - 20, W - 6, 86) + B(2, T0 + 4, W - 4, 22, 32, "#7d8a92", "#5e6a72")
        bb += B(8, T0 - 60, 44, 10, 66, "#c9a24a", "#a8862f")
        bb += C(20, T0 - 49, 2.4, "#6fbf86", None, 0)
        save(key + "_b", 2, 1, T0, bb, {"lamp": [20, T0 - 49], "work": [30, T0 + 2], "in": [W - 16, T0 + 12], "out": [W * 0.5, T0 + 18]})
        return
    if kind == "line":
        T0 = 44
        b = ga.shadow(12, T0 + 4, W - 6, 62)
        b += B(2, T0 + 8, W - 4, 22, 28, "#5c6267", "#464b4f")
        for k in range(int(W / 12)):
            b += R(6 + k * 12, T0 + 10, 8, 18, STEEL, OUT, 0.8, 4)                                            # ролики
        for x in (W * 0.25, W * 0.6):
            b += B(x - 14, T0 - 24, 28, 8, 30, "#4a7f9a", "#3d6a82")                                            # стойки с гайковёртами
            b += L(x, T0 - 24, x, T0 - 40, "#2a2e31", 1.6) + R(x - 6, T0 - 6, 12, 8, "#2a2e31", OUT, 1)
        b += R(W - 30, T0 - 20, 22, 30, "#3d4652", OUT, 1.4) + R(W - 26, T0 - 16, 14, 8, "#6fd0e0", None, 0, 1, 0.8)
        lx, ly = W - 19, T0 - 26
        b += C(lx, ly, 2.4, "#6fbf86", None, 0)
        an = {"lamp": [lx, ly], "work": [W * 0.45, T0 + 14], "in": [14, T0 + 16], "out": [W - 18, T0 + 20]}
        save(key, wt, 1, T0, b, an)
        bv = ga.shadow(12, T0, 52, W + 4) + B(6, T0 + 4, 48, W - 30, 22, "#5c6267", "#464b4f")
        for k in range(int(W / 12)):
            bv += R(10, T0 + 8 + k * 12, 40, 8, STEEL, OUT, 0.8, 4)
        bv += B(36, T0 + W * 0.3, 20, 8, 24, "#4a7f9a", "#3d6a82") + C(46, T0 - 2, 2.4, "#6fbf86", None, 0)
        save(key + "_v", 1, wt, T0, bv, {"lamp": [46, T0 - 2], "work": [30, T0 + W * 0.45], "in": [14, T0 + 14], "out": [30, T0 + W - 20]})
        bb = ga.shadow(12, T0 + 4, W - 6, 62) + B(2, T0 + 8, W - 4, 22, 28, "#5c6267", "#464b4f")
        for x in (W * 0.4, W * 0.75):
            bb += B(x - 14, T0 - 24, 28, 8, 30, "#4a7f9a", "#3d6a82")
        bb += R(8, T0 - 20, 22, 30, "#3d4652", OUT, 1.4) + C(19, T0 - 26, 2.4, "#6fbf86", None, 0)
        save(key + "_b", wt, 1, T0, bb, {"lamp": [19, T0 - 26], "work": [W * 0.55, T0 + 14], "in": [W - 14, T0 + 16], "out": [18, T0 + 20]})
        return
    # stand 3×2: сварная плита с Т-пазами, кран-укосина, тумба с инструментом
    T0 = 60
    b = ga.shadow(14, T0 - 10, W - 10, Hh + 4)
    b += B(14, T0 + 6, W - 40, Hh - 50, 28, "#5c6267", "#464b4f")
    for k in range(5):
        b += L(20, T0 + 12 + k * (Hh - 62) / 4, W - 32, T0 + 12 + k * (Hh - 62) / 4, "#3e4246", 1.6)
    b += B(W - 26, T0 - 50, 14, 8, Hh + 6, "#d9b13b", "#b8932c")                                              # укосина
    b += R(W * 0.45, T0 - 50, W * 0.55 - 20, 8, "#d9b13b", OUT, 1.4) + L(W * 0.5, T0 - 42, W * 0.5, T0 + 10, "#2a2e31", 1.2)
    b += R(W * 0.5 - 6, T0 + 8, 12, 6, "#c94a3a", OUT, 1)
    b += B(4, T0 + Hh - 44, 40, 10, 30, "#7d8a92", "#5e6a72")
    lx, ly = W - 19, T0 - 40
    b += C(lx, ly, 2.4, "#6fbf86", None, 0)
    an = {"lamp": [lx, ly], "work": [W * 0.45, T0 + 30], "in": [22, T0 + Hh - 40], "out": [W - 30, T0 + Hh - 14]}
    save(key, wt, ht, T0, b, an)
    bv = ga.shadow(14, T0 - 10, Hh - 10, W + 4) + B(10, T0 + 6, Hh - 30, W - 50, 24, "#5c6267", "#464b4f")
    bv += B(Hh - 22, T0 - 40, 12, 8, W - 10, "#d9b13b", "#b8932c") + C(Hh - 16, T0 - 30, 2.4, "#6fbf86", None, 0)
    save(key + "_v", ht, wt, T0, bv, {"lamp": [Hh - 16, T0 - 30], "work": [Hh * 0.45, T0 + W * 0.4], "in": [14, T0 + 20], "out": [14, T0 + W - 30]})
    bb = ga.shadow(14, T0 - 10, W - 10, Hh + 4) + B(26, T0 + 6, W - 40, Hh - 50, 28, "#5c6267", "#464b4f")
    bb += B(12, T0 - 50, 14, 8, Hh + 6, "#d9b13b", "#b8932c") + C(19, T0 - 40, 2.4, "#6fbf86", None, 0)
    save(key + "_b", wt, ht, T0, bb, {"lamp": [19, T0 - 40], "work": [W * 0.55, T0 + 30], "in": [W - 22, T0 + Hh - 40], "out": [30, T0 + Hh - 14]})


# =============================================================== термообработка

def furnace(key, wt, ht, kind):
    """muffle — муфельная 1×1, tvch — установка ТВЧ 2×1, shaft — шахтная 2×2 (круглая, в полу),
    bogie — печь с выкатным подом 3×2."""
    W, Hh = wt * 64, ht * 64
    if kind == "muffle":
        T0 = 40
        b = ga.shadow(12, T0, 50, 62)
        b += B(4, T0 + 22, 56, 8, 32, "#8a8f86", "#6e736a")                              # подставка
        b += B(8, T0 - 22, 48, 10, 44, "#d9d6cf", "#bdb9b0")                             # печь
        b += R(14, T0 - 4, 26, 20, "#8a7a6a", OUT, 1.4, 2) + R(20, T0 + 2, 14, 9, "#2a1d16", OUT, 1.2)
        b += R(44, T0 - 6, 8, 20, "#3d4652", OUT, 1) + C(48, T0 + 2, 2.2, "#6fbf86", None, 0)
        an = {"lamp": [48, T0 + 2], "glow": [20, T0 + 2, 14, 9], "in": [12, T0 + 30], "out": [52, T0 + 30]}
        save(key, 1, 1, T0, b, an)
        save(key + "_v", 1, 1, T0, b, an)
        bb = ga.shadow(12, T0, 50, 62) + B(4, T0 + 22, 56, 8, 32, "#8a8f86", "#6e736a") + B(8, T0 - 22, 48, 10, 44, "#d9d6cf", "#bdb9b0")
        for k in range(4):
            bb += L(14, T0 - 6 + k * 8, 50, T0 - 6 + k * 8, "#a8a49c", 1.2)
        save(key + "_b", 1, 1, T0, bb, {"lamp": [16, T0 + 2], "glow": [24, T0 + 2, 14, 9], "in": [52, T0 + 30], "out": [12, T0 + 30]})
        return
    if kind == "tvch":
        T0 = 60
        b = ga.shadow(12, T0 - 10, W - 8, 70)
        b += B(4, T0 - 30, 52, 10, 88, "#d8dcdd", "#bfc5c8")                                  # генератор
        b += R(10, T0 - 14, 40, 18, "#2a2e31", OUT, 1) + R(12, T0 - 12, 20, 8, "#6fd0e0", None, 0, 1, 0.7)
        for k in range(3):
            b += C(16 + k * 10, T0 + 14, 3, ["#6fbf86", "#d9b13b", "#c94a3a"][k], OUT, 0.8)
        b += B(62, T0 + 8, 60, 14, 30, "#6a7074", "#4f5458")                                  # закалочный стол
        b += C(90, T0 + 4, 9, None, "#c98d63", 3) + C(90, T0 + 4, 5, None, "#c98d63", 2)      # индуктор
        b += P(f"M52 {T0+6}Q70 {T0-10} 82 {T0+2}", None, "#c98d63", 3)
        b += R(110, T0 - 20, 8, 30, "#4a7f9a", OUT, 1.2) + P(f"M114 {T0-20}Q114 {T0-30} 100 {T0-28}", None, "#4a7f9a", 2)   # спрейер
        an = {"lamp": [16, T0 + 14], "glow": [80, T0 - 4, 20, 14], "in": [70, T0 + 14], "out": [112, T0 + 14]}
        save(key, 2, 1, T0, b, an)
        bv = ga.shadow(12, T0 - 10, 52, 134) + B(6, T0 - 30, 50, 10, 60, "#d8dcdd", "#bfc5c8")
        bv += R(12, T0 - 14, 36, 14, "#2a2e31", OUT, 1) + C(18, T0 + 10, 3, "#6fbf86", OUT, 0.8)
        bv += B(8, T0 + 60, 48, 40, 22, "#6a7074", "#4f5458") + C(32, T0 + 76, 9, None, "#c98d63", 3)
        save(key + "_v", 1, 2, T0, bv, {"lamp": [18, T0 + 10], "glow": [22, T0 + 68, 20, 14], "in": [12, T0 + 66], "out": [52, T0 + 96]})
        bb = ga.shadow(12, T0 - 10, W - 8, 70) + B(68, T0 - 30, 52, 10, 88, "#d8dcdd", "#bfc5c8")
        for k in range(5):
            bb += L(74, T0 - 14 + k * 8, 114, T0 - 14 + k * 8, "#a7adb0", 1.4)
        bb += B(6, T0 + 8, 60, 14, 30, "#6a7074", "#4f5458") + C(34, T0 + 4, 9, None, "#c98d63", 3)
        save(key + "_b", 2, 1, T0, bb, {"lamp": [110, T0 - 20], "glow": [24, T0 - 4, 20, 14], "in": [56, T0 + 14], "out": [12, T0 + 14]})
        return
    if kind == "shaft":
        T0 = 60
        b = ga.shadow(16, T0 - 10, W - 14, Hh + 2)
        b += R(4, T0 + 6, W - 8, Hh - 8, "#8f8b84", OUT, 2, 4)                                    # приямок
        b += ga.ell(W * 0.42, T0 + Hh * 0.45, W * 0.32, Hh * 0.3, "#7a7066", OUT, 2.2)              # кожух шахты
        b += ga.ell(W * 0.42, T0 + Hh * 0.4, W * 0.24, Hh * 0.2, "#5a524a", OUT, 1.8)
        b += ga.ell(W * 0.42, T0 + Hh * 0.38, W * 0.16, Hh * 0.13, "#2a1d16", OUT, 1.4)              # жерло
        b += R(W * 0.42 - 3, T0 - 46, 6, 60, "#4a5156", OUT, 1.2) + R(W * 0.42 - 24, T0 - 50, 48, 8, "#d9b13b", OUT, 1.4)   # тельфер над шахтой
        b += B(W - 34, T0 - 20, 28, 10, 96, "#8e9fa8", "#6f8089")
        b += R(W - 30, T0 + 0, 20, 12, "#2a2e31", OUT, 1) + R(W - 28, T0 + 2, 16, 5, "#c94a3a", None, 0, 0, 0.8)
        for k in range(3):
            b += C(W - 27 + k * 7, T0 + 22, 2.4, ["#6fbf86", "#d9b13b", "#c94a3a"][k], OUT, 0.8)
        an = {"lamp": [W - 27, T0 + 22], "glow": [W * 0.42 - W * 0.12, T0 + Hh * 0.38 - 8, W * 0.24, 16], "in": [14, T0 + Hh - 10], "out": [W * 0.6, T0 + Hh - 10]}
        save(key, wt, ht, T0, b, an)
        save(key + "_v", ht, wt, T0, b, an)
        save(key + "_b", wt, ht, T0, b.replace("#8e9fa8", "#8e9fa8"), an)
        return
    # bogie 3×2: печь с выкатным подом, рельсы спереди
    T0 = 70
    b = ga.shadow(16, T0 - 26, W - 14, Hh + 20)
    b += B(8, T0 - 46, W - 50, 14, 112, "#9a8f84", "#7a7066")
    b += R(22, T0 + 2, W - 78, 58, "#6a5a4e", OUT, 2, 3)
    for yy in range(3):
        for xx in range(6):
            b += R(26 + xx * (W - 86) / 6 + (yy % 2) * 6, T0 + 6 + yy * 17, (W - 86) / 6 - 2, 15, "#8a6a52", OUT, 0.8)
    b += R(W * 0.3, T0 + 18, W * 0.22, 18, "#2a1d16", OUT, 1.6, 2)
    b += R(14, T0 + Hh - 10, W - 60, 4, "#5a6268", None, 0) + R(14, T0 + Hh - 2, W - 60, 4, "#5a6268", None, 0)   # рельсы
    b += B(20, T0 + 60, W - 76, 8, 16, "#4f5458", "#3a3e42")                                                         # выкатной под
    b += B(W - 40, T0 - 26, 32, 10, 104, "#8e9fa8", "#6f8089")
    b += R(W - 36, T0 - 6, 22, 12, "#2a2e31", OUT, 1)
    for k in range(3):
        b += C(W - 32 + k * 7, T0 + 16, 2.4, ["#6fbf86", "#d9b13b", "#c94a3a"][k], OUT, 0.8)
    b += B(W * 0.25, T0 - 64, W * 0.3, 8, 14, "#7a7066", "#5a524a")
    an = {"lamp": [W - 32, T0 + 16], "glow": [W * 0.3, T0 + 18, W * 0.22, 18], "in": [20, T0 + Hh - 8], "out": [W - 50, T0 + Hh - 8]}
    save(key, wt, ht, T0, b, an)
    bv = ga.shadow(16, T0 - 26, Hh - 14, W + 20) + B(8, T0 - 46, Hh - 30, W - 30, 70, "#9a8f84", "#7a7066")
    bv += R(18, T0 + W - 64, Hh - 50, 40, "#6a5a4e", OUT, 2, 3) + R(Hh * 0.3, T0 + W - 52, Hh * 0.3, 16, "#2a1d16", OUT, 1.4)
    bv += C(Hh - 20, T0 - 30, 2.4, "#6fbf86", None, 0)
    save(key + "_v", ht, wt, T0, bv, {"lamp": [Hh - 20, T0 - 30], "glow": [Hh * 0.3, T0 + W - 52, Hh * 0.3, 16], "in": [14, T0 + W - 10], "out": [Hh - 14, T0 + W - 10]})
    bb = ga.shadow(16, T0 - 26, W - 14, Hh + 20) + B(42, T0 - 46, W - 50, 14, 112, "#9a8f84", "#7a7066")
    for k in range(6):
        bb += L(52, T0 - 20 + k * 14, W - 18, T0 - 20 + k * 14, "#8a7f74", 1.6)
    bb += B(8, T0 - 26, 32, 10, 104, "#8e9fa8", "#6f8089") + C(18, T0 + 16, 2.4, "#6fbf86", None, 0)
    save(key + "_b", wt, ht, T0, bb, {"lamp": [18, T0 + 16], "glow": [W * 0.5, T0 + 18, W * 0.22, 18], "in": [W - 20, T0 + Hh - 8], "out": [50, T0 + Hh - 8]})


# =============================================================== покраска

def paint(key, wt, ht, kind):
    """table — окрасочный стол с зонтом 2×1, small — камера ОК-1 2×1, powder — порошковая 2×2,
    line — проходная с сушкой 3×2."""
    W, Hh = wt * 64, ht * 64
    if kind in ("table", "small"):
        T0 = 70
        b = ga.shadow(12, T0 - 20, W - 8, 82)
        if kind == "table":
            b += B(6, T0 + 8, W - 12, 18, 30, "#6a7074", "#4f5458")                                  # решётчатый стол
            for k in range(10):
                b += L(10 + k * 11, T0 + 10, 10 + k * 11, T0 + 24, "#3e4246", 1.2)
            b += P(f"M14 {T0-36}H{W-14}L{W-30} {T0-12}H30Z", "#c9cfd2", OUT, 1.8)                     # зонт
            b += R(W * 0.5 - 8, T0 - 62, 16, 26, "#9aa3a8", OUT, 1.4)
            mist = [W * 0.5, T0]
        else:
            b += B(4, T0 - 50, W - 8, 12, 106, "#c9cfd2", "#aab2b6")
            b += R(12, T0 - 30, W - 24, 78, "#5a6268", OUT, 2) + R(14, T0 - 28, W - 28, 74, "#7c868c", None, 0)
            for k in range(8):
                b += R(14 + k * (W - 28) / 8, T0 - 28, (W - 28) / 8 - 1, 74, "#d8e4ea", "#9fb0b8", 0.8, 0, 0.45)
            b += R(26, T0 - 44, W - 52, 8, "#fff6d8", OUT, 1)
            mist = [W * 0.5, T0 + 10]
        b += R(W - 18, T0 - 10, 12, 20, "#3a3f43", OUT, 1.2) + C(W - 12, T0 - 4, 2.4, "#6fbf86", None, 0)
        an = {"lamp": [W - 12, T0 - 4], "work": mist, "mist": mist, "in": [16, T0 + 50], "out": [W - 18, T0 + 50]}
        save(key, wt, 1, T0, b, an)
        bv = ga.shadow(12, T0 - 20, 52, 146)
        bv += B(6, T0 - 40, 50, 12, 146 - 30, "#c9cfd2", "#aab2b6") if kind == "small" else B(8, T0 + 6, 46, 88, 24, "#6a7074", "#4f5458")
        bv += C(46, T0 - 4, 2.4, "#6fbf86", None, 0)
        save(key + "_v", 1, 2, T0, bv, {"lamp": [46, T0 - 4], "work": [30, T0 + 50], "mist": [30, T0 + 40], "in": [12, T0 + 20], "out": [12, T0 + 100]})
        bb = ga.shadow(12, T0 - 20, W - 8, 82) + (B(4, T0 - 50, W - 8, 12, 106, "#c9cfd2", "#aab2b6") if kind == "small" else B(6, T0 + 8, W - 12, 18, 30, "#6a7074", "#4f5458"))
        bb += R(W * 0.4, T0 - 70, 22, 20, "#8a9196", OUT, 1.4) + C(14, T0 - 4, 2.4, "#6fbf86", None, 0)
        save(key + "_b", wt, 1, T0, bb, {"lamp": [14, T0 - 4], "work": mist, "mist": mist, "in": [W - 16, T0 + 50], "out": [18, T0 + 50]})
        return
    T0 = 70
    col_t, col_f = ("#e2e4dc", "#c4c7bc") if kind == "powder" else ("#c9cfd2", "#aab2b6")
    b = ga.shadow(16, T0 - 26, W - 14, Hh + 10)
    FH = Hh + 26                       # высота передней стенки: низ — у края футпринта
    b += B(4, T0 - 50, W - 8, 12, FH, col_t, col_f)
    b += R(14, T0 - 30, W * 0.55, FH - 16, "#5a6268", OUT, 2) + R(16, T0 - 28, W * 0.55 - 4, FH - 20, "#7c868c", None, 0)
    if kind == "powder":
        # подвес с деталями и пистолет-распылитель; справа — печь полимеризации
        for k in range(3):
            hx = 26 + k * (W * 0.55 - 24) / 3
            b += L(hx + 8, T0 - 28, hx + 8, T0 + 8, "#3a3f43", 1.4)
            b += R(hx, T0 + 8, 16, 26, "#c9a24a" if k != 1 else "#5a8f4e", OUT, 1.2, 2)
        b += P(f"M{W*0.5} {T0+FH-40}l-14 -10h-6v6h6z", "#3a3f43", OUT, 1)
        b += B(W * 0.6 + 14, T0 - 24, W * 0.32, 10, FH - 22, "#3d4652", "#2e3640")
        b += R(W * 0.6 + 22, T0, W * 0.32 - 16, 18, "#c94a3a", None, 0, 2, 0.75)
        for k in range(4):
            b += L(W * 0.6 + 22, T0 + 30 + k * 8, W * 0.92 - 2, T0 + 30 + k * 8, "#1d2228", 1.4)
    else:
        for k in range(10):
            b += R(16 + k * (W * 0.55 - 4) / 10, T0 - 28, (W * 0.55 - 4) / 10 - 1, FH - 20, "#d8e4ea", "#9fb0b8", 0.8, 0, 0.45)
        b += B(W * 0.62, T0 - 20, W * 0.32, 12, FH - 30, "#9a8f84", "#7a7066")                                 # сушильная камера
        b += R(W * 0.62 + 10, T0 + 6, W * 0.32 - 20, 26, "#2a1d16", OUT, 1.4, 2)
    b += R(10, T0 - 46, W - 20, 6, "#4a5156", OUT, 1) + R(W * 0.3, T0 - 54, 6, 14, "#4a5156", OUT, 1)       # подвесной конвейер
    b += C(W - 18, T0 - 34, 2.4, "#6fbf86", OUT, 0.8)
    an = {"lamp": [W - 18, T0 - 34], "work": [W * 0.3, T0 + 20], "mist": [W * 0.3, T0 + 10], "in": [20, T0 + Hh - 6], "out": [W - 20, T0 + Hh - 6]}
    save(key, wt, ht, T0, b, an)
    bv = ga.shadow(16, T0 - 26, Hh - 14, W + 10) + B(4, T0 - 50, Hh - 8, 12, W + 26, col_t, col_f)
    bv += R(12, T0 - 30, Hh - 24, W * 0.5, "#5a6268", OUT, 2) + C(Hh - 18, T0 - 34, 2.4, "#6fbf86", OUT, 0.8)
    save(key + "_v", ht, wt, T0, bv, {"lamp": [Hh - 18, T0 - 34], "work": [Hh * 0.5, T0 + W * 0.25], "mist": [Hh * 0.5, T0 + W * 0.2], "in": [12, T0 + 20], "out": [12, T0 + W - 10]})
    bb = ga.shadow(16, T0 - 26, W - 14, Hh + 10) + B(4, T0 - 50, W - 8, 12, Hh + 26, col_t, col_f)
    for k in range(7):
        bb += L(14, T0 - 26 + k * 14, W - 14, T0 - 26 + k * 14, "#a7adb0", 1.6)
    bb += B(W * 0.4, T0 - 74, 40, 8, 16, "#9aa3a8", "#7b8286") + C(18, T0 - 34, 2.4, "#6fbf86", OUT, 0.8)
    save(key + "_b", wt, ht, T0, bb, {"lamp": [18, T0 - 34], "work": [W * 0.6, T0 + 20], "mist": [W * 0.6, T0 + 10], "in": [W - 20, T0 + Hh - 6], "out": [20, T0 + Hh - 6]})


# =============================================================== станки с ЧПУ

def cnc(key, wt, ht, kind, accent, body=("#e4e7e8", "#c6cbcd")):
    """lathe — токарный в кожухе (окно вдоль), vmc — вертикальный обрабатывающий центр (высокий кожух,
    магазин инструмента), heavy — тяжёлый токарный (длинный, ниже), small — компактный с прутковым податчиком."""
    WH, WF = body
    W, Hh = wt * 64, ht * 64
    tall = kind == "vmc"
    T0 = 66 + (34 if tall else 0)
    hh = 90 + (34 if tall else 0)
    b = ga.shadow(14, T0 - 20 - (34 if tall else 0), W - 10, Hh + 20)
    ew = W - 30
    dt = Hh // 2 + 2                        # глубина верхней грани кожуха
    b += B(4, T0 - 30 - (34 if tall else 0), ew, dt, hh, WH, WF)
    top = T0 - 30 - (34 if tall else 0)
    fy = top + dt                           # верх передней стенки
    b += R(10, top + 4, ew - 12, 7, accent, None, 0, 1)                                                          # фирменная полоса
    for k in range(4):
        b += L(16, top + 18 + k * 9, ew * 0.55, top + 18 + k * 9, "#cfd4d6", 1.4)
    # дверь со смотровым окном
    dx, dw = 14, ew * 0.62
    b += R(dx, fy + 10, dw, hh - 30, "#2a3036", OUT, 2, 3)
    b += R(dx + 4, fy + 14, dw - 8, hh - 38, "#3e5866", None, 0, 2, 0.85)
    b += ga.poly([(dx + 8, fy + 14), (dx + 28, fy + 14), (dx + 12, fy + hh - 24), (dx + 4, fy + hh - 24)], "#ffffff", None, 0, 0.12)
    cy = fy + 10 + (hh - 30) * 0.45
    if kind == "vmc":
        b += R(dx + dw * 0.4, fy + 14, 18, 26, STEEL, OUT, 1.2) + R(dx + dw * 0.4 + 5, fy + 40, 8, 14, "#c9ccce", OUT, 1)
        b += R(dx + 10, fy + hh - 40, dw - 20, 10, "#7b8286", OUT, 1.2)                                         # стол
        b += C(ew - 10, top + dt * 0.5, 15, "#9aa3a8", OUT, 1.6) + C(ew - 10, top + dt * 0.5, 8, None, "#5a6268", 1.2)   # магазин
        work = [dx + dw * 0.4 + 9, fy + 50]
    else:
        b += R(dx + 10, cy - 11, 22, 22, STEEL, OUT, 1.2, 2) + R(dx + 32, cy - 4, dw * 0.45, 8, "#c9ccce", OUT, 1.2)
        b += R(dx + 32 + dw * 0.45, cy - 2, 10, 4, "#c9ccce", OUT, 1)
        work = [dx + 32 + dw * 0.25, cy]
    b += R(dx + dw + 2, fy + 10, 4, hh - 30, STEEL, None, 0)
    b += R(10, fy + hh - 10, ew - 8, 10, accent, OUT, 1.4)                                                        # конвейер стружки / цоколь
    # пульт
    b += B(W - 26, fy - 24, 22, 12, hh + 10, "#3d4652", "#2e3640")
    b += R(W - 22, fy - 4, 14, 12, "#1d2a34", OUT, 1) + R(W - 20, fy - 2, 10, 8, "#6fd0e0", None, 0, 1, 0.8)
    for yy in range(2):
        for xx in range(3):
            b += R(W - 22 + xx * 5, fy + 14 + yy * 6, 4, 4, ["#c9ccce", "#e2b73a", "#6fbf86"][(xx + yy) % 3], None, 0, 1)
    b += C(W - 15, fy + 36, 3.5, "#c94a3a", OUT, 1)
    if kind == "small":
        b += R(12, fy - 16, ew * 0.55, 9, "#d9b13b", OUT, 1.3, 4) + L(16, fy - 13, 10 + ew * 0.5, fy - 13, "#f0d27a", 1.5)   # прутковый податчик
    lx, ly = ew * 0.75, top - 10
    b += R(lx - 3, top - 16, 6, 14, DARK, OUT, 1) + C(lx, ly - 6, 4, "#6fbf86", OUT, 1)
    an = {"lamp": [lx, ly - 6], "work": work, "in": [W - 40, fy + hh - 8], "out": [16, fy + hh - 8], "screen": [W - 15, fy + 2]}
    save(key, wt, ht, T0, b, an)
    # сбоку (ht × wt)
    Wv, Hv = Hh, W
    b = ga.shadow(14, T0 - 30, Wv - 10, Hv + 22)
    b += B(8, T0 - 50 - (24 if tall else 0), Wv - 16, Hv - 18, 64 + (24 if tall else 0), WH, WF)
    b += R(22, T0 - 36, Wv - 52, Hv - 54, "#2a3036", OUT, 2, 3)
    b += R(26, T0 - 32, Wv - 60, Hv - 62, "#3e5866", None, 0, 2, 0.85)
    b += R(Wv * 0.35, T0 - 22, 24, 22, STEEL, OUT, 1.2, 2) + R(Wv * 0.35 + 7, T0, 10, Hv * 0.3, "#c9ccce", OUT, 1.2)
    b += R(Wv - 18, T0 - 46 - (24 if tall else 0), 8, Hv - 24, accent, None, 0, 1)
    b += B(Wv - 24, T0 + Hv - 118, 22, 30, 50, "#3d4652", "#2e3640")
    b += R(Wv - 20, T0 + Hv - 112, 14, 12, "#1d2a34", OUT, 1) + R(Wv - 19, T0 + Hv - 110, 12, 8, "#6fd0e0", None, 0, 1, 0.8)
    b += R(12, T0 + Hv - 10, Wv - 24, 10, accent, OUT, 1.4)
    vy = T0 - 46 - (24 if tall else 0)
    b += R(Wv - 32, vy - 10, 6, 14, DARK, OUT, 1) + C(Wv - 29, vy - 12, 4, "#6fbf86", OUT, 1)
    save(key + "_v", ht, wt, T0, b, {"lamp": [Wv - 29, vy - 12], "work": [Wv * 0.35 + 12, T0 + 30], "in": [8, T0 + Hv - 22], "out": [Wv - 10, T0 + Hv - 22]})
    # со спины
    b = ga.shadow(14, T0 - 20 - (34 if tall else 0), W - 10, Hh + 20)
    b += B(26, top, ew, dt, hh, "#d8dbdc", "#bcc1c3")
    for k in range(7):
        b += L(38, fy + 12 + k * 9, 38 + ew * 0.5, fy + 12 + k * 9, "#a7adb0", 2)
    b += R(26 + ew * 0.62, fy + 12, ew * 0.3, 42, STEEL, OUT, 1.4, 2) + R(26 + ew * 0.62 + 4, fy + 16, ew * 0.3 - 8, 34, None, "#7a8388", 1, 1)
    b += R(30, fy + hh - 10, ew - 8, 10, accent, OUT, 1.4)
    b += B(2, fy - 24, 22, 12, hh + 10, "#3d4652", "#2e3640")
    b += R(26 + ew * 0.25 - 3, top - 16, 6, 14, DARK, OUT, 1) + C(26 + ew * 0.25, top - 16, 4, "#6fbf86", OUT, 1)
    save(key + "_b", wt, ht, T0, b, {"lamp": [26 + ew * 0.25, top - 16], "work": [W * 0.55, cy], "in": [40, fy + hh - 8], "out": [W - 20, fy + hh - 8]})


# =============================================================== каталог

def run(module):
    global ga
    ga = module
    # токарные
    lathe("lathe_tv4", 2, "cream", "bench")
    lathe("lathe_1a616", 2, "bluegrey", "small")
    lathe("lathe_16k20", 3, "lgrey", "std")
    lathe("lathe_1m63", 4, "dkgreen", "heavy")
    # фрезерные
    mill("mill_6t80", 2, "bluegrey", "horizontal")
    mill("mill_6r10", 2, "olive", "vertical")
    mill("mill_6r82", 2, "green", "horizontal")
    mill("mill_6r13", 3, "dkgreen", "vertical")
    # сверлильные
    drill("drill_ns12", 1, 1, "cream", "bench")
    drill("drill_2n118", 1, 1, "bluegrey", "column")
    drill("drill_2n150", 1, 1, "dkgreen", "column")
    drill("drill_2m55", 2, 2, "green", "radial")
    # сварка
    welder("weld_vd306", 2, 1, "manual")
    welder("weld_pdg251", 2, 1, "semi")
    welder("weld_spot", 1, 1, "spot")
    welder("weld_stand", 3, 2, "stand")
    # сборка
    assembly("asm_bench", 1, 1, "bench")
    assembly("asm_press", 2, 1, "press")
    assembly("asm_stand", 3, 2, "stand")
    assembly("asm_line", 4, 1, "line")
    # термо
    furnace("heat_snol", 1, 1, "muffle")
    furnace("heat_tvch", 2, 1, "tvch")
    furnace("heat_shaft", 2, 2, "shaft")
    furnace("heat_bogie", 3, 2, "bogie")
    # покраска
    paint("paint_table", 2, 1, "table")
    paint("paint_small", 2, 1, "small")
    paint("paint_powder", 2, 2, "powder")
    paint("paint_line", 3, 2, "line")
    # ЧПУ: советские и по мотивам импортных (названия вымышленные)
    cnc("cnc_65a60", 3, 2, "vmc", "#3d5a7a", ("#d9dcd2", "#bcc0b4"))
    cnc("cnc_panther", 3, 2, "lathe", "#e2752c", ("#eceeee", "#cfd3d4"))
    cnc("cnc_sidway", 2, 2, "small", "#3f8a5a")
    cnc("cnc_hangan", 4, 2, "heavy", "#c94a3a", ("#e6e4dc", "#c8c5ba"))
    cnc("cnc_hartwood", 3, 2, "vmc", "#2f6ab0", ("#f0f1f1", "#d3d7d8"))
    cnc("cnc_minger", 2, 2, "vmc", "#d9a62a", ("#e9eaea", "#cbcfd0"))
