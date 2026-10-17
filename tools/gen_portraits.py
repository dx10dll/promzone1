#!/usr/bin/env python3
"""Портреты людей «Промзоны» — 1.20: плоский «гранёный» стиль.

Лицо — многоугольник с плоскими гранями-тенями (без обводок и градиентов), глаза — тёмные прямоугольники
с бликом, брови — трапеции, плечи — большие треугольники с воротником, фон — светлая стена с силуэтом завода.
Слои те же, что раньше (portrait.gd собирает их по чертам человека):
  bg → hairback → body → body_fx → neck → neck_fx → outfit → head → head_fx → eyes → iris → eyes_top → nose
  → mouth → lines → freckles → beard → brows → hair → bald_fx → earrings → glasses → hat → hat_fx → phones
Слои «т» (тонируемые) нарисованы оттенками серого и в игре умножаются на цвет кожи, волос, глаз, одежды,
головного убора: белое — основной тон, серые — грани в тени. Остальные слои — готовые цвета.

Холст 128×148. Запуск: python3 tools/gen_portraits.py (из корня проекта), затем tools/pack_vec.py.
"""
import math
import os
import random

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
W, H = 128, 148
CX = 64

# телосложения: полуширина плеч, полуширина у шеи, женское
SHAPES = {
    "m_vthin": (28, 10, False), "m_strong": (56, 17, False), "f_vthin": (27, 9, True), "f_strong": (46, 13, True),
    "m_thin": (34, 11, False), "m_norm": (42, 13, False), "m_stout": (48, 15, False),
    "m_fat": (53, 17, False), "m_vfat": (58, 19, False),
    "f_thin": (31, 10, True), "f_norm": (37, 11, True), "f_stout": (42, 12.5, True),
    "f_fat": (47, 14, True), "f_vfat": (52, 16, True),
}

# тона тонируемых граней (умножаются на цвет)
T0, T1, T2, T3 = "#ffffff", "#ebebeb", "#d6d6d6", "#bcbcbc"
DK = "#2a1c14"          # тени на коже (полупрозрачные)


def f(v):
    if isinstance(v, float):
        return f"{v:.2f}".rstrip("0").rstrip(".")
    return str(v)


def save(name, body):
    path = os.path.join(ROOT, "assets/portrait", name + ".svg")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8") as fp:
        fp.write(f'<svg xmlns="http://www.w3.org/2000/svg" width="{W}" height="{H}" viewBox="0 0 {W} {H}">{body}</svg>')


def Q(pts, fill, op=None):
    d = "M" + "L".join(f"{f(float(x))} {f(float(y))}" for x, y in pts) + "Z"
    o = f' opacity="{f(op)}"' if op is not None else ""
    return f'<path d="{d}" fill="{fill}"{o}/>'


def R(x, y, w, h, fill, op=None):
    o = f' opacity="{f(op)}"' if op is not None else ""
    return f'<rect x="{f(float(x))}" y="{f(float(y))}" width="{f(float(w))}" height="{f(float(h))}" fill="{fill}"{o}/>'


def L(pts, col, sw, op=None):
    d = "M" + "L".join(f"{f(float(x))} {f(float(y))}" for x, y in pts)
    o = f' opacity="{f(op)}"' if op is not None else ""
    return f'<path d="{d}" fill="none" stroke="{col}" stroke-width="{f(sw)}" stroke-linejoin="miter"{o}/>'


def mir(pts):
    return [(2 * CX - x, y) for x, y in pts]


def sym(half):
    """Половина контура справа (сверху вниз) → полный симметричный многоугольник."""
    right = half
    left = [(2 * CX - x, y) for x, y in reversed(half)]
    return right + left


# ------------------------------------------------------------------ фон

def background():
    b = R(0, 0, W, H, "#c9c3bb")
    b += R(0, 0, W, 34, "#bdb6ae") + R(0, 34, W, 30, "#c4bdb5", 0.9)
    # силуэт завода: пилообразные крыши, труба, корпус
    roof = [(0, 98), (0, 86), (10, 78), (10, 86), (22, 78), (22, 86), (34, 78), (34, 98)]
    b += Q(roof, "#d8d2ca")
    b += Q([(92, 98), (92, 80), (104, 72), (104, 80), (116, 72), (116, 80), (128, 72), (128, 98)], "#d8d2ca")
    b += R(108, 40, 9, 58, "#d3ccc4") + R(108, 40, 9, 3, "#c6bfb7")
    b += Q([(116, 28), (122, 22), (128, 28), (122, 34)], "#e6e1db", 0.9) + Q([(110, 16), (115, 11), (120, 16), (115, 21)], "#e6e1db", 0.8)
    b += R(0, 98, W, H - 98, "#e9e5e0")
    return b


# ------------------------------------------------------------------ голова

# половина контура лица справа: (dx, y) от верха к подбородку
HEADS = {
    "oval":   [(12, 23), (25, 32), (28, 48), (28, 66), (22, 82), (9, 95)],
    "square": [(14, 23), (27, 31), (29, 48), (29, 68), (26, 86), (12, 96)],
    "round":  [(14, 24), (28, 33), (31, 50), (30, 70), (22, 87), (9, 95)],
    "long":   [(11, 21), (24, 30), (26, 48), (26, 70), (20, 88), (8, 99)],
    "soft":   [(12, 25), (25, 34), (27, 50), (26, 68), (18, 84), (7, 94)],
}


def head_poly(hs):
    pts = [(CX + dx, y) for dx, y in HEADS[hs]]
    return sym(pts)


def head():
    for hs, half in list(HEADS.items()) + [("m", HEADS["oval"]), ("f", HEADS["soft"])]:
        pts = [(CX + dx, y) for dx, y in half]
        cheek = half[2][0]
        jaw = half[4]
        chin = half[5]
        b = ""
        # уши: пятиугольники, внутри — тень
        for s in (-1, 1):
            ex = CX + s * (cheek + 0.5)
            ear = [(ex, 52), (ex + s * 5, 54), (ex + s * 6, 61), (ex + s * 3.5, 70), (ex - s * 0.5, 70)]
            b += Q(ear, T1 if s < 0 else T2) + Q([(ex + s * 1.2, 56), (ex + s * 4, 58), (ex + s * 3, 66), (ex + s * 0.8, 65)], T3)
        b += Q(sym(pts), T0)
        # правая сторона лица — в тени (свет слева)
        rs = [(CX + 7, half[0][1]), pts[0], pts[1], pts[2], pts[3], pts[4], pts[5], (CX + 3, chin[1])]
        b += Q(rs, T1)
        # скулы-впадины: треугольные грани под скулами
        b += Q([(CX - cheek + 1, 64), (CX - 15, 70), (CX - jaw[0] + 1.5, 80)], "#f3f3f3")
        b += Q([(CX + cheek - 1, 64), (CX + 15, 70), (CX + jaw[0] - 1.5, 80)], T2)
        # нижняя челюсть: грань от углов к подбородку
        b += Q([(CX - jaw[0], jaw[1]), (CX - 9, 90), (CX - chin[0], chin[1])], T1)
        b += Q([(CX + jaw[0], jaw[1]), (CX + 9, 90), (CX + chin[0], chin[1])], T2)
        # виски
        b += Q([(CX - half[1][0], half[1][1]), (CX - half[2][0], half[2][1]), (CX - half[2][0] + 4, 44)], T1)
        b += Q([(CX + half[1][0], half[1][1]), (CX + half[2][0], half[2][1]), (CX + half[2][0] - 4, 44)], T2)
        save(f"head_{hs}", b)
        # блики лба — тонкие светлые грани поверх (не тонируются)
        fx = Q([(CX - 10, 30), (CX - 2, 28), (CX - 4, 34), (CX - 12, 36)], "#ffffff", 0.16)
        save(f"head_fx_{hs}", fx)
    # шея: прямоугольник, сверху — тень от подбородка
    for nm, nw in (("neck", 11.5), ("neck_wide", 15.5)):
        b = Q([(CX - nw, 80), (CX + nw, 80), (CX + nw, 112), (CX - nw, 112)], T0)
        b += Q([(CX - nw, 80), (CX + nw, 80), (CX + nw, 100), (CX, 103), (CX - nw, 100)], T3)
        b += Q([(CX + 3, 100), (CX + nw, 100), (CX + nw, 112), (CX + 3, 112)], T1)
        save(nm, b)
    save("neck_fx", "")
    save("chin", Q([(CX - 18, 88), (CX + 18, 88), (CX + 12, 99), (CX - 12, 99)], T2) + Q([(CX - 12, 99), (CX + 12, 99), (CX + 9, 101), (CX - 9, 101)], T3))


# ------------------------------------------------------------------ глаза

EYE_C = (51, 77)
EY = 59
EYES = {
    #          ширина высота
    "almond": (8.6, 7.0),
    "narrow": (9.0, 4.6),
    "round": (8.0, 8.0),
    "heavy": (8.6, 5.8),
    "deep": (8.2, 7.0),
}


def eyes():
    for kind, (w0, h0) in list(EYES.items()) + [("", (8.6, 7.0))]:
        for g in ("m", "f"):
            fem = g == "f"
            w, h = (w0 + 0.4, h0 + 0.4) if fem else (w0, h0)
            sfx = f"{kind}_{g}" if kind else g
            white, iris, top = "", "", ""
            for cx in EYE_C:
                s = 1 if cx > CX else -1
                x0, y0 = cx - w / 2, EY - h / 2
                # глазница — тёмная грань над глазом
                white += Q([(x0 - 2, y0 - 1.5), (x0 + w + 2, y0 - 1.5), (x0 + w + 1, y0), (x0 - 1, y0)], DK, 0.18)
                if kind == "deep":
                    white += Q([(x0 - 3, y0 - 4), (x0 + w + 3, y0 - 4), (x0 + w + 2, y0), (x0 - 2, y0)], DK, 0.16)
                # сам глаз — тёмный прямоугольник (тонируется цветом глаз)
                iris += Q([(x0, y0), (x0 + w, y0 + (0.6 if kind == "almond" else 0)), (x0 + w, y0 + h), (x0, y0 + h)], "#3c3c3c")
                # блик и веко
                top += R(x0 + w * 0.22, y0 + h * 0.18, max(1.2, w * 0.2), max(1.2, h * 0.24), "#ffffff", 0.95)
                if kind == "heavy":
                    top += Q([(x0 - 1, y0 - 0.5), (x0 + w + 1, y0 - 0.5), (x0 + w + 0.5, y0 + h * 0.35), (x0 - 0.5, y0 + h * 0.35)], "#2a1a14", 0.55)
                if kind == "narrow":
                    top += Q([(x0 - 0.5, y0 - 0.8), (x0 + w + 0.5, y0 - 0.8), (x0 + w, y0 + 0.4), (x0, y0 + 0.4)], "#2a1a14", 0.5)
                if fem:
                    xo = x0 + w if s > 0 else x0
                    top += Q([(xo, y0), (xo + s * 3, y0 - 2.2), (xo + s * 1.4, y0 + 1.2)], "#1e1612")
                    white += Q([(x0 - 2, y0 - 4), (x0 + w + 2, y0 - 4), (x0 + w + 2, y0 - 1.4), (x0 - 2, y0 - 1.4)], "#7a4a5a", 0.18)
            save(f"eyes_{sfx}", white)
            save(f"iris_{sfx}", iris)
            save(f"eyes_top_{sfx}", top)


# ------------------------------------------------------------------ нос, рот, морщины

def noses():
    N = {   # верх спинки, низ, полуширина кончика
        "small": (64, 74, 4.0), "straight": (56, 77, 4.5), "long": (54, 81, 4.6),
        "wide": (60, 77, 6.5), "hooked": (54, 78, 4.8),
    }
    for kind, (y0, y1, nw) in N.items():
        b = Q([(CX + 0.5, y0), (CX + 4.5, y0 + 2), (CX + 5, y1 - 3), (CX + 1, y1 - 4)], DK, 0.16)      # тень спинки
        b += Q([(CX - 3, y0 + 2), (CX + 0.5, y0), (CX + 1, y1 - 4), (CX - 2.5, y1 - 4)], "#ffffff", 0.14)   # освещённая спинка
        if kind == "hooked":
            b += Q([(CX + 1, 63), (CX + 5, 62), (CX + 5.5, 67), (CX + 2, 68)], DK, 0.14)
        # кончик носа — трапеция, под ней тень
        b += Q([(CX - nw * 0.6, y1 - 4), (CX + nw * 0.6, y1 - 4), (CX + nw, y1), (CX - nw, y1)], DK, 0.2)
        b += Q([(CX - nw, y1), (CX + nw, y1), (CX + nw * 0.4, y1 + 2.2), (CX - nw * 0.4, y1 + 2.2)], DK, 0.3)
        save(f"nose_{kind}", b)


def mouths():
    M = {   # точки линии рта (слева направо)
        "neutral": [(57, 85.5), (71, 85.5)],
        "smile": [(56, 84), (60, 86.5), (68, 86.5), (72, 84)],
        "down": [(57, 87), (61, 85.4), (67, 85.4), (71, 87)],
        "thin": [(58.5, 85.5), (69.5, 85.5)],
        "full": [(57, 85.3), (71, 85.3)],
    }
    for kind, line in M.items():
        # мужские: тёмная линия, нижняя губа — светлая грань, под ней тень
        b = L(line, "#6a3a2c", 1.8 if kind != "thin" else 1.3)
        b += Q([(59, 87.6), (69, 87.6), (67.5, 89.4), (60.5, 89.4)], DK, 0.18 if kind != "full" else 0.26)
        if kind == "smile":
            b += Q([(58, 86.6), (70, 86.6), (68, 88.2), (60, 88.2)], "#ffffff", 0.35)
        save(f"mouth_{kind}_m", b)
        # женские: губы плоскими гранями
        lip, lip2 = "#b8564c", "#9a4038"
        top = {"neutral": 83.6, "smile": 83.4, "down": 84.6, "thin": 84.4, "full": 82.8}[kind]
        bot = {"neutral": 88.2, "smile": 89.4, "down": 88.4, "thin": 87.0, "full": 89.6}[kind]
        mid = (top + bot) / 2 + (0.6 if kind == "smile" else (-0.4 if kind == "down" else 0))
        xl, xr = (57, 71) if kind != "thin" else (58.5, 69.5)
        ends = mid - 1.4 if kind == "smile" else (mid + 1.2 if kind == "down" else mid)
        b = Q([(xl, ends), (CX - 3, top), (CX, top + 1), (CX + 3, top), (xr, ends), (CX, mid + 0.4)], lip2)
        b += Q([(xl, ends), (CX, mid + 0.4), (xr, ends), (CX + 3.5, bot), (CX - 3.5, bot)], lip)
        b += R(CX - 3, bot - 2.2, 4, 1.0, "#ffffff", 0.28)
        save(f"mouth_{kind}_f", b)
    # старые имена
    for g in ("m", "f"):
        save(f"mouth_{g}_happy", open(os.path.join(ROOT, f"assets/portrait/mouth_smile_{g}.svg")).read().split(">", 1)[1].rsplit("</svg>", 1)[0])
        save(f"mouth_{g}_neutral", open(os.path.join(ROOT, f"assets/portrait/mouth_neutral_{g}.svg")).read().split(">", 1)[1].rsplit("</svg>", 1)[0])
        save(f"mouth_{g}_sad", open(os.path.join(ROOT, f"assets/portrait/mouth_down_{g}.svg")).read().split(">", 1)[1].rsplit("</svg>", 1)[0])


def wrinkles():
    w = DK
    save("lines_mid", L([(56, 74), (54, 82)], w, 0.9, 0.22) + L([(72, 74), (74, 82)], w, 0.9, 0.22) + L([(54, 35), (74, 35)], w, 0.9, 0.18))
    b = L([(50, 33), (78, 33)], w, 0.9, 0.24) + L([(52, 37), (76, 37)], w, 0.9, 0.22) + L([(54, 41), (74, 41)], w, 0.8, 0.18)
    b += L([(56, 73), (53.5, 84)], w, 1.0, 0.26) + L([(72, 73), (74.5, 84)], w, 1.0, 0.26)
    for s in (-1, 1):
        x = CX + s * 23
        b += L([(x, 57), (x + s * 3, 55)], w, 0.8, 0.26) + L([(x, 60), (x + s * 3.4, 60)], w, 0.8, 0.26) + L([(x, 63), (x + s * 3, 65)], w, 0.8, 0.26)
        b += L([(CX + s * 8, 65), (CX + s * 18, 65)], w, 0.8, 0.18)
    b += L([(60, 98), (64, 99.5), (68, 98)], w, 0.8, 0.2)
    save("lines_old", b)
    save("wrinkles", "")
    rnd = random.Random(3)
    fr = "".join(R(x, y, 1.3, 1.3, "#8a4a2a", 0.4) for x, y in
                 [(45, 68), (48, 71), (52, 68.5), (55, 71.5), (73, 71.5), (76, 68.5), (79.5, 71), (83, 68), (61, 69), (66, 69), (63.5, 66.5)])
    save("freckles", fr)
    ear = ""
    for s in (-1, 1):
        ex = CX + s * 29
        ear += Q([(ex, 68), (ex + 2, 70.5), (ex, 73), (ex - 2, 70.5)], "#e2b33c")
    save("earrings", ear)


# ------------------------------------------------------------------ брови

BROWS = {
    #            внутренний низ, внутр. верх, внешн. верх, внешн. низ   (для правой брови, x от центра)
    "straight": [(5, 50.5), (5, 47.5), (21, 47.0), (21, 50.0)],
    "arched":   [(5, 50.5), (6, 47.5), (14, 45.0), (22, 48.5), (21, 50.8), (14, 48.2)],
    "thick":    [(4.5, 51), (4.5, 46.5), (21.5, 45.8), (21.5, 50.2)],
    "thin":     [(5.5, 50), (5.5, 48.2), (20, 46.8), (20, 48.6)],
    "angled":   [(5, 49.0), (5, 46.6), (21, 49.0), (21, 51.4)],
    "bushy":    [(4, 51), (4, 46), (12, 44.6), (22.5, 46.2), (22.5, 50.6)],
}


def brows():
    for kind, pts in BROWS.items():
        right = [(CX + dx, y) for dx, y in pts]
        b = Q(right, "#8a8a8a") + Q(mir(right), "#8a8a8a")   # брови темнее волос, как на образце
        save(f"brows_{kind}", b)
    save("brows_m", "")
    save("brows_f", "")


# ------------------------------------------------------------------ волосы

def shade_r(poly, x_from=70):
    """Правая часть фигуры — в тени: та же фигура, обрезанная справа (клип через многоугольник)."""
    pts = [(max(x, x_from), y) for x, y in poly]
    return Q(pts, T2)


def hair():
    burns = Q([(CX - 28, 46), (CX - 24, 46), (CX - 24, 64), (CX - 27.5, 62)], T0) + Q([(CX + 28, 46), (CX + 24, 46), (CX + 24, 64), (CX + 27.5, 62)], T2)
    short = [(CX - 29, 56), (CX - 30, 38), (CX - 22, 24), (CX - 10, 17), (CX + 10, 17), (CX + 22, 24), (CX + 30, 38), (CX + 29, 56),
             (CX + 26, 44), (CX + 18, 36), (CX + 4, 38), (CX - 8, 34), (CX - 20, 38), (CX - 26, 44)]
    hs = Q(short, T0) + shade_r(short) + Q([(CX - 10, 17), (CX + 2, 17), (CX - 8, 26), (CX - 18, 28)], "#ffffff") + burns
    save("hair_short", hs)
    save("hair_mullet", hs)
    crew = [(CX - 28, 50), (CX - 28, 36), (CX - 18, 24), (CX - 6, 21), (CX + 6, 21), (CX + 18, 24), (CX + 28, 36), (CX + 28, 50),
            (CX + 22, 40), (CX + 8, 37), (CX - 8, 37), (CX - 22, 40)]
    cb = Q(crew, T1) + shade_r(crew) + "".join(R(CX - 18 + (i * 7.3) % 34, 27 + (i * 5.1) % 8, 1.2, 1.2, T3, 0.6) for i in range(18))
    save("hair_buzz", cb)
    save("hair_crew", cb)
    side = [(CX - 29, 56), (CX - 30, 38), (CX - 22, 23), (CX - 8, 16), (CX + 12, 17), (CX + 24, 24), (CX + 30, 38), (CX + 29, 56),
            (CX + 26, 42), (CX + 16, 35), (CX - 8, 35), (CX - 14, 30), (CX - 18, 36), (CX - 26, 44)]
    save("hair_side", Q(side, T0) + shade_r(side) + Q([(CX - 14, 30), (CX - 12, 18), (CX - 8, 17), (CX - 10, 31)], T3) + burns)
    slick = [(CX - 29, 54), (CX - 29, 36), (CX - 20, 22), (CX - 8, 17), (CX + 8, 17), (CX + 20, 22), (CX + 29, 36), (CX + 29, 54),
             (CX + 25, 40), (CX + 14, 32), (CX - 14, 32), (CX - 25, 40)]
    sl = Q(slick, T0) + shade_r(slick, 68) + "".join(Q([(x, 31), (x + 2, 31), (x + 4, 19), (x + 2, 19)], T2, 0.8) for x in (CX - 14, CX - 6, CX + 2))
    save("hair_slick", sl + burns)
    rec = [(CX - 29, 56), (CX - 29, 40), (CX - 22, 26), (CX - 14, 22), (CX - 16, 32), (CX - 24, 40), (CX - 26, 46)]
    save("hair_receding", Q(rec, T0) + Q(mir(rec), T2) + Q([(CX - 8, 24), (CX + 8, 24), (CX + 6, 28), (CX - 6, 28)], T1, 0.6) + burns)
    bald = [(CX - 29, 48), (CX - 26, 48), (CX - 25, 64), (CX - 28.5, 62)]
    save("hair_bald", Q(bald, T1) + Q(mir(bald), T2))
    save("bald_fx", Q([(CX - 14, 27), (CX - 4, 24), (CX - 6, 29), (CX - 15, 31)], "#ffffff", 0.35))
    # кудри — кольцо ромбов
    def curls(cx, cy, rx, ry, n, a0, a1, r=6.0):
        o = ""
        for k in range(n):
            a = a0 + (a1 - a0) * k / (n - 1)
            x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
            tone = T0 if x < CX + 4 else T2
            o += Q([(x, y - r), (x + r, y), (x, y + r), (x - r, y)], tone)
        return o
    base = [(CX - 29, 56), (CX - 30, 36), (CX - 18, 22), (CX, 19), (CX + 18, 22), (CX + 30, 36), (CX + 29, 56), (CX + 22, 40), (CX, 37), (CX - 22, 40)]
    save("hair_curly", Q(base, T1) + curls(CX, 46, 27, 26, 13, math.pi * 1.0, math.pi * 2.0) + curls(CX, 40, 16, 12, 5, math.pi * 1.15, math.pi * 1.85, 5))
    save("hairback_mullet", Q([(CX - 30, 58), (CX + 30, 58), (CX + 32, 104), (CX + 18, 110), (CX - 18, 110), (CX - 32, 104)], T2))
    # --- женские
    bob = [(CX - 31, 72), (CX - 33, 40), (CX - 22, 22), (CX - 8, 17), (CX + 8, 17), (CX + 22, 22), (CX + 33, 40), (CX + 31, 72),
           (CX + 24, 72), (CX + 24, 48), (CX + 14, 37), (CX - 4, 35), (CX - 12, 42), (CX - 24, 48), (CX - 24, 72)]
    bb = Q(bob, T0) + shade_r(bob, 69) + Q([(CX - 4, 35), (CX + 2, 18), (CX + 6, 18), (CX + 2, 36)], T3, 0.7)
    save("hair_bob", bb)
    save("hair_short_f", bb)
    pix = [(CX - 29, 60), (CX - 31, 38), (CX - 20, 22), (CX - 6, 17), (CX + 10, 17), (CX + 24, 24), (CX + 30, 38), (CX + 29, 54),
           (CX + 24, 44), (CX + 14, 44), (CX + 10, 40), (CX, 46), (CX - 6, 42), (CX - 14, 48), (CX - 22, 46), (CX - 26, 50)]
    save("hair_pixie", Q(pix, T0) + shade_r(pix))
    cap = [(CX - 29, 56), (CX - 30, 36), (CX - 18, 22), (CX, 18), (CX + 18, 22), (CX + 30, 36), (CX + 29, 56), (CX + 24, 42), (CX + 12, 35), (CX, 34), (CX - 12, 35), (CX - 24, 42)]
    pulled = Q(cap, T0) + shade_r(cap) + Q([(CX - 1, 18), (CX + 1, 18), (CX + 1, 34), (CX - 1, 34)], T3, 0.8)
    save("hair_ponytail", pulled)
    save("hairback_ponytail", Q([(CX + 22, 56), (CX + 34, 68), (CX + 33, 104), (CX + 27, 108), (CX + 28, 74)], T2) + Q([(CX + 20, 54), (CX + 27, 54), (CX + 27, 60), (CX + 20, 60)], T3))
    bun = Q([(CX - 9, 8), (CX + 9, 8), (CX + 12, 15), (CX + 8, 22), (CX - 8, 22), (CX - 12, 15)], T0) + Q([(CX + 2, 8), (CX + 9, 8), (CX + 12, 15), (CX + 8, 22), (CX + 2, 22)], T2)
    save("hair_bun", bun + pulled)
    long_ = [(CX - 31, 102), (CX - 32, 40), (CX - 22, 22), (CX - 8, 17), (CX + 8, 17), (CX + 22, 22), (CX + 32, 40), (CX + 31, 102),
             (CX + 23, 102), (CX + 24, 56), (CX + 14, 38), (CX, 32), (CX - 14, 38), (CX - 24, 56), (CX - 23, 102)]
    save("hair_long", Q(long_, T0) + shade_r(long_, 66) + Q([(CX - 1, 18), (CX + 1, 18), (CX + 1, 32), (CX - 1, 32)], T3, 0.8))
    save("hairback_long", Q([(CX - 34, 40), (CX - 22, 16), (CX + 22, 16), (CX + 34, 40), (CX + 36, 122), (CX - 36, 122)], T2))
    braid = ""
    for k in range(7):
        y = 70 + k * 8
        x = CX + 26 + k * 1.2
        braid += Q([(x, y - 4.5), (x + 5, y), (x, y + 4.5), (x - 5, y)], T0 if k % 2 else T2)
    braid += R(CX + 23, 124, 10, 4, "#4a7ab0")
    save("hair_braid", pulled + braid)
    cf = [(CX - 31, 82), (CX - 33, 40), (CX - 20, 21), (CX, 18), (CX + 20, 21), (CX + 33, 40), (CX + 31, 82), (CX + 24, 80), (CX + 24, 50), (CX, 38), (CX - 24, 50), (CX - 24, 80)]
    save("hair_curly_f", Q(cf, T1) + curls(CX, 50, 30, 32, 15, math.pi * 0.95, math.pi * 2.05))
    save("hairback_curly_f", curls(CX, 86, 32, 14, 6, 0, math.pi, 8))
    pf = [(CX - 31, 70), (CX - 33, 38), (CX - 18, 20), (CX, 18), (CX + 18, 20), (CX + 33, 38), (CX + 31, 70), (CX + 24, 66), (CX + 24, 46), (CX, 37), (CX - 24, 46), (CX - 24, 66)]
    save("hair_perm", Q(pf, T1) + curls(CX, 48, 30, 30, 17, math.pi * 0.92, math.pi * 2.08, 5.2) + curls(CX, 44, 20, 18, 7, math.pi * 1.1, math.pi * 1.9, 4.5))
    save("hairback_perm", curls(CX, 72, 31, 8, 6, 0, math.pi, 6))


def beards():
    # полная борода: от висков по челюсти к подбородку, вокруг рта открыто (как на образце)
    full = [(CX - 28, 56), (CX - 24, 56), (CX - 22, 72), (CX - 14, 79), (CX - 8, 80), (CX - 8, 84), (CX - 5, 90), (CX + 5, 90), (CX + 8, 84),
            (CX + 8, 80), (CX + 14, 79), (CX + 22, 72), (CX + 24, 56), (CX + 28, 56), (CX + 26, 84), (CX + 12, 99), (CX - 12, 99), (CX - 26, 84)]
    must = [(CX - 10, 82.6), (CX - 6, 79.4), (CX, 80.6), (CX + 6, 79.4), (CX + 10, 82.6), (CX + 5, 82), (CX, 83), (CX - 5, 82)]
    save("beard_full", Q(full, T1) + shade_r(full, 66) + Q(must, T0) + Q([(CX, 80.6), (CX + 6, 79.4), (CX + 10, 82.6), (CX + 5, 82), (CX, 83)], T2))
    short = [(CX - 27, 60), (CX - 23, 60), (CX - 20, 74), (CX - 10, 81), (CX - 9, 87), (CX + 9, 87), (CX + 10, 81), (CX + 20, 74), (CX + 23, 60), (CX + 27, 60),
             (CX + 24, 84), (CX + 10, 96), (CX - 10, 96), (CX - 24, 84)]
    save("beard_short", Q(short, T1, 0.85) + shade_r(short, 66) + Q(must, T0))
    # усы-«шеврон» как у образца: две трапеции вниз
    chev = [(CX - 12, 85.5), (CX - 7, 80), (CX, 81.5), (CX + 7, 80), (CX + 12, 85.5), (CX + 6, 83.4), (CX, 83.8), (CX - 6, 83.4)]
    save("beard_mustache", Q(must, T0) + Q([(CX, 80.6), (CX + 6, 79.4), (CX + 10, 82.6), (CX + 5, 82), (CX, 83)], T2))
    save("beard_chevron", Q(chev, T0) + Q([(CX, 81.5), (CX + 7, 80), (CX + 12, 85.5), (CX + 6, 83.4), (CX, 83.8)], T2))
    save("beard_goatee", Q([(CX - 6, 89), (CX + 6, 89), (CX + 5, 97), (CX, 100), (CX - 5, 97)], T1) + Q(must, T0))
    st = Q(full, "#6a6a6a", 0.32) + Q(must, "#6a6a6a", 0.3)
    rnd = random.Random(7)
    st += "".join(R(rnd.uniform(40, 87), rnd.uniform(66, 97), 0.8, 0.8, "#3a3a3a", 0.35) for _ in range(60))
    save("beard_stubble", st)


# ------------------------------------------------------------------ головные уборы, очки, наушники

def save_hat(name, body):
    """1.20: уборы выше — козырёк над бровями, глаза открыты."""
    if name.startswith("hat_"):
        body = f'<g transform="translate(0 -10)">{body}</g>'
    save(name, body)


def hats():
    save = save_hat
    # каска: гранёный купол, светлое ребро по центру, длинный козырёк (как на образце)
    dome = [(CX - 31, 52), (CX - 30, 34), (CX - 20, 20), (CX - 8, 14), (CX + 8, 14), (CX + 20, 20), (CX + 30, 34), (CX + 31, 52)]
    hb = Q(dome, T0) + Q([(CX + 4, 14), (CX + 8, 14), (CX + 20, 20), (CX + 30, 34), (CX + 31, 52), (CX + 4, 52)], T1)
    hb += Q([(CX - 4, 14), (CX + 4, 14), (CX + 4, 52), (CX - 4, 52)], "#ffffff")
    hb += Q([(CX - 22, 22), (CX - 14, 17), (CX - 20, 34), (CX - 27, 36)], "#ffffff")
    hb += Q([(CX - 38, 52), (CX + 38, 52), (CX + 40, 58), (CX - 40, 58)], T2) + Q([(CX - 40, 58), (CX + 40, 58), (CX + 39, 60), (CX - 39, 60)], T3)
    save("hat_helmet", hb)
    save("hat_helmet_fx", Q([(CX - 6, 26), (CX + 6, 26), (CX + 6, 36), (CX - 6, 36)], "#3a3f44") + Q([(CX - 4, 28), (CX + 4, 28), (CX + 4, 34), (CX - 4, 34)], "#f2f0d8")
         + Q([(CX + 14, 33), (CX + 24, 33), (CX + 24, 38), (CX + 14, 38)], "#c94a3a") + R(CX + 16, 35, 6, 1, "#ffffff", 0.8)
         + L([(CX - 17, 30), (CX - 14, 27)], "#5a3a10", 0.8, 0.5) + L([(CX + 22, 44), (CX + 25, 46)], "#5a3a10", 0.8, 0.5))
    cap = [(CX - 29, 50), (CX - 28, 32), (CX - 18, 18), (CX, 14), (CX + 18, 18), (CX + 28, 32), (CX + 29, 50)]
    save("hat_cap", Q(cap, T0) + shade_r(cap, 66) + Q([(CX - 31, 50), (CX + 31, 50), (CX + 34, 56), (CX - 34, 56)], T2) + Q([(CX - 1, 14), (CX + 1, 14), (CX + 1, 50), (CX - 1, 50)], T3))
    save("hat_cap_fx", Q([(CX - 34, 56), (CX + 34, 56), (CX + 32, 58), (CX - 32, 58)], DK, 0.25))
    ker = [(CX - 30, 54), (CX - 30, 34), (CX - 18, 18), (CX, 15), (CX + 18, 18), (CX + 30, 34), (CX + 30, 54), (CX + 22, 44), (CX, 40), (CX - 22, 44)]
    save("hat_kerchief", Q(ker, T0) + shade_r(ker, 66) + Q([(CX + 28, 54), (CX + 38, 62), (CX + 32, 70), (CX + 26, 60)], T2)
         + "".join(Q([(x, y - 1.6), (x + 1.6, y), (x, y + 1.6), (x - 1.6, y)], "#ffffff", 0.8) for x, y in
                   [(CX - 16, 26), (CX - 4, 22), (CX + 8, 24), (CX + 18, 30), (CX - 22, 38), (CX - 8, 34), (CX + 6, 34)]))
    ush = [(CX - 31, 54), (CX - 30, 30), (CX - 18, 14), (CX + 18, 14), (CX + 30, 30), (CX + 31, 54)]
    ub = Q(ush, T1) + shade_r(ush, 66)
    ub += Q([(CX - 32, 52), (CX - 24, 54), (CX - 24, 86), (CX - 30, 90), (CX - 34, 86)], T0) + Q([(CX + 32, 52), (CX + 24, 54), (CX + 24, 86), (CX + 30, 90), (CX + 34, 86)], T2)
    ub += Q([(CX - 32, 36), (CX + 32, 36), (CX + 32, 48), (CX - 32, 48)], "#ffffff")
    save("hat_ushanka", ub)
    pk = [(CX - 36, 42), (CX - 30, 26), (CX - 12, 18), (CX + 12, 18), (CX + 30, 26), (CX + 36, 42)]
    save("hat_peaked", Q(pk, T0) + shade_r(pk, 66) + Q([(CX - 28, 42), (CX + 28, 42), (CX + 28, 50), (CX - 28, 50)], T2)
         + Q([(CX - 28, 50), (CX + 28, 50), (CX + 22, 58), (CX - 22, 58)], "#2e3236"))
    save("hat_peaked_fx", Q([(CX, 40), (CX + 4, 44), (CX, 48), (CX - 4, 44)], "#d9b13b") + R(CX - 1.2, 42.8, 2.4, 2.4, "#a8322c"))
    wm = [(CX - 29, 50), (CX - 28, 30), (CX - 16, 15), (CX + 16, 15), (CX + 28, 30), (CX + 29, 50)]
    save("hat_weldmask", Q(wm, T1) + shade_r(wm, 66) + Q([(CX - 34, 50), (CX - 29, 46), (CX - 27, 62), (CX - 32, 62)], T3) + Q([(CX + 34, 50), (CX + 29, 46), (CX + 27, 62), (CX + 32, 62)], T3))
    save("hat_weldmask_fx", Q([(CX - 15, 26), (CX + 15, 26), (CX + 15, 38), (CX - 15, 38)], "#22301c") + Q([(CX - 12, 37), (CX - 4, 28), (CX - 1, 28), (CX - 9, 37)], "#9fd28a", 0.45))
    # очки: толстая чёрная оправа прямоугольником (как на образце)
    gl = ""
    for x in (CX - 23, CX + 4):
        gl += R(x, 52, 19, 13, "#cfe6f2", 0.18)
        gl += R(x, 52, 19, 2.6, "#1c1c1e") + R(x, 62.4, 19, 2.6, "#1c1c1e") + R(x, 52, 2.6, 13, "#1c1c1e") + R(x + 16.4, 52, 2.6, 13, "#1c1c1e")
        gl += Q([(x + 4, 61), (x + 9, 55), (x + 11, 55), (x + 6, 61)], "#ffffff", 0.45)
    gl += R(CX - 4, 54, 8, 2.4, "#1c1c1e") + R(CX - 30, 54, 7, 2.2, "#1c1c1e") + R(CX + 23, 54, 7, 2.2, "#1c1c1e")
    save("glasses", gl)
    save("phones", L([(CX - 33, 62), (CX - 30, 30), (CX - 14, 16), (CX + 14, 16), (CX + 30, 30), (CX + 33, 62)], "#2a2c30", 4.5)
         + Q([(CX - 39, 52), (CX - 29, 52), (CX - 29, 72), (CX - 39, 72)], "#33363b") + Q([(CX + 39, 52), (CX + 29, 52), (CX + 29, 72), (CX + 39, 72)], "#2a2d31"))
    save("resp", Q([(CX - 14, 102), (CX + 14, 102), (CX + 12, 116), (CX - 12, 116)], "#d9d9d0") + Q([(CX, 102), (CX + 14, 102), (CX + 12, 116), (CX, 116)], "#c4c4ba")
         + Q([(CX - 20, 106), (CX - 13, 106), (CX - 13, 114), (CX - 20, 114)], "#c86a62") + Q([(CX + 20, 106), (CX + 13, 106), (CX + 13, 114), (CX + 20, 114)], "#a8524a"))


# ------------------------------------------------------------------ туловище и одежда

def body_pts(sh, nk, fem):
    top = 102 if not fem else 103
    return [(CX - nk - 3, top), (CX - sh * 0.62, top + 6), (CX - sh, top + 16), (CX - sh - 10, H + 2),
            (CX + sh + 10, H + 2), (CX + sh, top + 16), (CX + sh * 0.62, top + 6), (CX + nk + 3, top)]


def bodies():
    for key, (sh, nk, fem) in SHAPES.items():
        pts = body_pts(sh, nk, fem)
        top = pts[0][1]
        b = Q(pts, T2)
        # правая половина — в тени
        b += Q([(CX + 2, top + 4), (CX + nk + 3, top), (CX + sh * 0.62, top + 6), (CX + sh, top + 16), (CX + sh + 10, H + 2), (CX + 2, H + 2)], T3)
        # плечи — светлые верхние грани
        b += Q([(CX - nk - 3, top), (CX - sh * 0.62, top + 6), (CX - sh, top + 16), (CX - sh + 10, top + 18), (CX - nk - 4, top + 6)], T1)
        # воротник «V»: светлый слева, темнее справа (как на образце)
        b += Q([(CX - nk - 3, top - 1), (CX - nk - 15, top + 9), (CX - 2, top + 28), (CX - 1, top + 14)], T0)
        b += Q([(CX + nk + 3, top - 1), (CX + nk + 15, top + 9), (CX + 2, top + 28), (CX + 1, top + 14)], T1)
        save(f"body_{key}", b)
        save(f"body_fx_{key}", L([(CX - sh + 2, top + 22), (CX - sh + 6, H)], DK, 1.0, 0.12) + L([(CX + sh - 2, top + 22), (CX + sh - 6, H)], DK, 1.0, 0.16))
        outfits(key, sh, nk, fem, pts)


def outfits(key, sh, nk, fem, pts):
    top = pts[0][1]
    clip = '<clipPath id="b"><path d="M' + "L".join(f"{f(float(x))} {f(float(y))}" for x, y in pts) + 'Z"/></clipPath>'
    g = lambda body: f'{clip}<g clip-path="url(#b)">{body}</g>'
    placket = R(CX - 2, top + 14, 4, H - top, "#000000", 0.28) + R(CX - 2, top + 50, 4, 4, "#c9a85a")
    pocket = R(CX - sh * 0.6, top + 26, 14, 14, "#000000", 0.18) + R(CX - sh * 0.6, top + 26, 14, 2, "#000000", 0.2)
    pencil = R(CX - sh * 0.6 + 4, top + 18, 2.4, 10, "#d9a62a") + Q([(CX - sh * 0.6 + 4, top + 18), (CX - sh * 0.6 + 6.4, top + 18), (CX - sh * 0.6 + 5.2, top + 15)], "#2a2a2a")
    badge = R(CX + sh * 0.35, top + 26, 13, 8, "#f0ece2") + R(CX + sh * 0.35, top + 26, 13, 2.2, "#c94a3a") + R(CX + sh * 0.35 + 2, top + 30, 8, 1, "#a09a8a") + R(CX + sh * 0.35 + 2, top + 32, 6, 1, "#a09a8a")
    tee = Q([(CX - nk - 1, top), (CX + nk + 1, top), (CX, top + 12)], "#e4e0d4")
    # рабочая куртка-спецовка (как на образце): планка с пуговицей, карман с карандашом, бейдж
    save(f"outfit_overall_{key}", g(placket + pocket + pencil + badge))
    # халат ОТК: голубая рубашка в вырезе, планка, ручки в кармане
    b = Q([(CX - nk + 1, top), (CX + nk - 1, top), (CX, top + 22)], "#7fa4c4") + R(CX - 1, top + 22, 2, H, "#000000", 0.2)
    b += pocket + R(CX - sh * 0.6 + 3, top + 18, 2, 9, "#2e5a8a") + R(CX - sh * 0.6 + 7, top + 19, 2, 8, "#c94a3a") + badge
    save(f"outfit_coat_{key}", g(b))
    # жилет электрика: тёмная футболка, светоотражающие полосы
    b = Q([(CX - nk - 1, top), (CX + nk + 1, top), (CX, top + 12)], "#3a3f44")
    for y in (top + 22, top + 36):
        b += R(CX - sh - 12, y, sh * 2 + 24, 5, "#e3e6e2") + R(CX - sh - 12, y + 3.6, sh * 2 + 24, 1.4, "#b8bcb8")
    save(f"outfit_vest_{key}", g(b))
    # брезентовая куртка: молния, два кармана
    b = R(CX - 1, top + 12, 2, H, "#c9ccce") + tee
    for s in (-1, 1):
        px = CX + s * sh * 0.5
        b += R(px - 7, top + 26, 14, 11, "#000000", 0.16) + R(px - 7, top + 26, 14, 2, "#000000", 0.22)
    save(f"outfit_jacket_{key}", g(b))
    # клетчатая рубашка: крупная клетка полупрозрачными полосами
    b = ""
    for x in range(CX - 70, CX + 71, 10):
        b += R(x, top - 4, 4, H, "#000000", 0.14)
    for y in range(int(top) + 2, H + 1, 10):
        b += R(CX - 80, y, 160, 4, "#000000", 0.14)
    b += R(CX - 1, top + 14, 2, H, "#000000", 0.3)
    save(f"outfit_shirt_{key}", g(b))
    # фартук термиста: кожаный нагрудник с лямками
    b = tee + L([(CX - 15, top + 18), (CX - nk + 2, top)], "#3a2a1c", 2.4) + L([(CX + 15, top + 18), (CX + nk - 2, top)], "#3a2a1c", 2.4)
    b += Q([(CX - 17, top + 18), (CX + 17, top + 18), (CX + 21, H + 2), (CX - 21, H + 2)], "#5a3f28") + Q([(CX, top + 18), (CX + 17, top + 18), (CX + 21, H + 2), (CX, H + 2)], "#4a3220")
    save(f"outfit_apron_{key}", g(b))
    # костюм ИТР (как у мастера на образце): белая рубашка, бордовый галстук, планки в кармане, значок
    b = Q([(CX - nk + 1, top), (CX + nk - 1, top), (CX, top + 26)], "#f2f1ec")
    b += Q([(CX - 3, top + 2), (CX + 3, top + 2), (CX + 2.5, top + 7), (CX - 2.5, top + 7)], "#8a2e34")
    b += Q([(CX - 2.5, top + 7), (CX + 2.5, top + 7), (CX + 4, top + 30), (CX, top + 36), (CX - 4, top + 30)], "#9a343c")
    b += Q([(CX, top + 7), (CX + 2.5, top + 7), (CX + 4, top + 30), (CX, top + 36)], "#7a262e")
    b += R(CX - sh * 0.6, top + 26, 16, 14, "#000000", 0.18)
    for i, c in enumerate(("#d9a62a", "#c94a3a", "#4a7ab0")):
        b += R(CX - sh * 0.6 + 3 + i * 4, top + 19 + (i % 2), 2.2, 9, c)
    b += R(CX + sh * 0.45, top + 22, 3, 3, "#c94a3a") + Q([(CX + sh * 0.45 + 1.5, top + 26), (CX + sh * 0.45 + 5, top + 30), (CX + sh * 0.45 + 1.5, top + 34), (CX + sh * 0.45 - 2, top + 30)], "#d9b13b")
    save(f"outfit_suit_{key}", g(b))
    # мундир инспектора: стойка, погоны, пуговицы
    b = Q([(CX - nk - 3, top - 2), (CX + nk + 3, top - 2), (CX + nk + 3, top + 6), (CX - nk - 3, top + 6)], "#000000", 0.2)
    b += R(CX - sh + 2, top + 8, 14, 5, "#d9b13b") + R(CX + sh - 16, top + 8, 14, 5, "#d9b13b")
    b += "".join(R(CX - 1.6, top + y, 3.2, 3.2, "#d9b13b") for y in (14, 24, 34, 44))
    save(f"outfit_uniform_{key}", g(b))


def main():
    save("bg", background())
    head()
    eyes()
    noses()
    mouths()
    wrinkles()
    brows()
    hair()
    beards()
    hats()
    bodies()
    n = len([x for x in os.listdir(os.path.join(ROOT, "assets/portrait")) if x.endswith(".svg")])
    print("портреты: файлов", n)


if __name__ == "__main__":
    main()
