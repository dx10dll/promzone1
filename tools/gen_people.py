#!/usr/bin/env python3
"""Люди 1.15: новый облик — пропорции взрослее (голова меньше и сидит на плечах), лица из деталей.

Слои кладутся в assets/people/ под теми же правилами, что и в gen_assets.py: холст 64×112, точка стопы —
(0, 26) в координатах слоя; белая заливка тонируется в игре (кожа, волосы, одежда, головной убор, цвет глаз).

Лицо собирается из частей, у каждой несколько видов:
  голова (5 форм), глаза (5 разрезов, мужские и женские), радужка (тонируется цветом глаз), брови (6),
  нос (5), рот (5, у женщин — с губами), морщины по возрасту, веснушки, серьги.
Причёски: 9 мужских и 8 женских; бороды и усы — 6 видов; головные уборы, очки, наушники, респиратор.
Запуск: из gen_assets.main() после остальных людей (перекрывает старые слои головы и лица)."""
import math

import gen_assets as ga
from gen_assets import path, circ, ell, rect, line, WHITE, OUT, person_layer

HY = -25.0       # центр головы
HR = 13.0        # радиус головы
EY = HY + 1.2    # линия глаз
EX = 4.6         # глаза от середины
RH = 13.9        # полуширина причёски у висков
MY = EY + 7.3    # линия рта
D = "#000"       # тени — чёрным с прозрачностью
LID = "#2a1d17"  # веки и ресницы
LIP = "#5e2f26"  # линия рта

# формы головы: полуширина у скул, низ челюсти (от центра), ширина подбородка, высота подбородка
HEADS = {
    "oval": (13.0, 5.5, 0.62, 14.2),
    "square": (13.3, 7.6, 0.82, 13.9),
    "round": (13.6, 7.0, 0.76, 13.7),
    "long": (12.4, 6.0, 0.6, 15.0),
    "soft": (12.6, 5.0, 0.52, 13.8),
}


def f(v):
    return ga.fmt(round(v, 2))


def P(*parts):
    """Склейка команд пути: P('M', x, y, 'Q', ...) → 'M1 2Q...'."""
    out = []
    for p in parts:
        out.append(p if isinstance(p, str) else f(p))
    s = ""
    for i, t in enumerate(out):
        if i and not t[0].isalpha() and not s[-1].isalpha():
            s += " "
        s += t
    return s


# ------------------------------------------------------------------ голова

def head_front_d(shape):
    w, jy, ck, cy = HEADS[shape]
    y = HY
    return P("M", -w, y - 1, "C", -w, y - HR * 1.36, w, y - HR * 1.36, w, y - 1,
             "C", w, y + jy, w * ck, y + cy - 0.6, 0, y + cy, "C", -w * ck, y + cy - 0.6, -w, y + jy, -w, y - 1, "Z")


def head_side_d(shape):
    w, jy, ck, cy = HEADS[shape]
    y = HY
    return P("M", -w * 0.66, y + HR * 0.74, "Q", -w - 0.9, y + 6, -w - 0.4, y - 1,
             "C", -w, y - HR * 1.36, w - 0.6, y - HR * 1.36, w - 0.3, y - 2.5,
             "C", w + 0.1, y + 1.5, w - 0.4, y + 3.5, w - 0.2, y + 5,
             "C", w + 0.1, y + jy + 1.2, w * (0.55 + ck * 0.25), y + cy, w * 0.22, y + cy,
             "C", -w * 0.25, y + cy - 0.3, -w * 0.5, y + HR * 0.86, -w * 0.66, y + HR * 0.74, "Z")


def heads():
    y = HY
    for shape, (w, jy, ck, cy) in HEADS.items():
        neck = ell(0, y + cy + 1.4, w * 0.62, 3.0, D, None, 0, 0.18)
        ears = ""
        for sx in (-1, 1):
            ears += ell(sx * (w - 0.2), y + 1.6, 2.6, 3.4, WHITE, OUT, 1.7)
            ears += path(P("M", sx * (w + 0.6), y - 0.2, "Q", sx * (w + 1.6), y + 1.6, sx * (w + 0.4), y + 3.4), None, D, 0.8, 0.25)
        body = path(head_front_d(shape), WHITE, OUT, 2.3)
        # объём: тень по правой щеке и под челюстью
        shade = P("M", w - 0.6, y - 2, "C", w, y + jy, w * ck, y + cy - 0.6, 0, y + cy,
                  "C", w * 0.55, y + cy - 2.2, w - 2.8, y + jy - 0.6, w - 2.2, y - 2, "Z")
        body += path(shade, D, None, 0, 0.1)
        body += ell(-w * 0.45, y - 6.5, w * 0.32, 3.2, "#fff", None, 0, 0.16)
        person_layer(f"head_{shape}_front", neck + ears + body)
        # затылок
        back = neck + ears + path(head_front_d(shape), WHITE, OUT, 2.3) + path(shade, D, None, 0, 0.08)
        person_layer(f"head_{shape}_back", back)
        # профиль (лицом вправо), ухо сзади щеки
        side = ell(-w * 0.1, y + cy + 1.2, w * 0.5, 2.8, D, None, 0, 0.18)
        side += path(head_side_d(shape), WHITE, OUT, 2.3)
        side += path(P("M", w - 1.4, y + 4, "C", w - 1.2, y + jy + 1, w * 0.6, y + cy - 0.6, w * 0.22, y + cy - 0.3,
                       "C", w * 0.45, y + cy - 2.2, w - 3, y + jy - 0.5, w - 3.2, y + 4, "Z"), D, None, 0, 0.1)
        person_layer(f"head_{shape}_side", side)
    # второй подбородок у полных
    for shape, (w, jy, ck, cy) in HEADS.items():
        pass
    person_layer("chin_front", path(P("M", -6.4, HY + 14.4, "Q", 0, HY + 17.6, 6.4, HY + 14.4), None, D, 1.0, 0.22)
                 + path(P("M", -5.6, HY + 15.2, "Q", 0, HY + 18.4, 5.6, HY + 15.2, "Q", 0, HY + 16.6, -5.6, HY + 15.2, "Z"), D, None, 0, 0.08))
    person_layer("chin_side", path(P("M", 1.4, HY + 14.6, "Q", 5.4, HY + 17.2, 9.6, HY + 14.2), None, D, 1.0, 0.22))
    # ухо в профиль — отдельным слоем поверх волос (короткие стрижки его не закрывают)
    person_layer("ear_side", ell(-1.4, y + 1.8, 2.5, 3.4, WHITE, OUT, 2.0) + path(P("M", -2.2, y + 0.2, "Q", -3.1, y + 1.8, -2, y + 3.7), None, D, 0.8, 0.3))
    # старые имена (для запасного пути)
    person_layer("head_front", "")
    person_layer("head_back", "")
    person_layer("head_side", "")


# ------------------------------------------------------------------ глаза

EYES = {
    #        rx   ry   складка  тяжёлое веко  глубоко
    "almond": (2.3, 1.25, True, False, False),
    "narrow": (2.45, 0.82, False, False, False),
    "round": (2.15, 1.55, True, False, False),
    "heavy": (2.3, 1.05, False, True, False),
    "deep": (2.2, 1.2, True, False, True),
}


def eye_shape(ex, ry_k=1.0, rx=2.3, ry=1.25, sx=1, narrow=False):
    """Миндалина глаза (внешний угол у narrow чуть выше)."""
    lift = 0.35 if narrow else 0.0
    xi, xo = ex - sx * rx, ex + sx * rx      # внутренний и внешний угол
    return P("M", xi, EY, "Q", ex, EY - ry * 1.95 * ry_k, xo, EY - lift, "Q", ex, EY + ry * 1.45 * ry_k, xi, EY, "Z")


def eyes():
    for kind, (rx, ry, crease, heavy, deep) in EYES.items():
        narrow = kind == "narrow"
        white, iris, lids = {"m": "", "f": ""}, "", {"m": "", "f": ""}
        defs = ""
        for sx in (-1, 1):
            ex = EX * sx
            sh = eye_shape(ex, 1.0, rx, ry, sx, narrow)
            # белок
            for gk in ("m", "f"):
                white[gk] += path(sh, "#f3eee7", None, 0)
            # радужка внутри разреза (тонируется цветом глаз)
            cid = f"ec_{kind}_{'l' if sx < 0 else 'r'}"
            defs += f'<clipPath id="{cid}"><path d="{sh}"/></clipPath>'
            ir = min(1.22, ry * 1.05 + 0.18)
            cx = ex + sx * 0.12
            iris += (f'<g clip-path="url(#{cid})">' + circ(cx, EY - 0.15, ir, WHITE, None, 0)
                     + circ(cx, EY - 0.15, ir * 0.48, "#111", None, 0) + circ(cx - 0.35, EY - 0.6, 0.32, "#fff", None, 0, 0.75) + "</g>")
            # верхнее веко, складка, ресницы
            xi, xo = ex - sx * rx, ex + sx * rx
            lift = 0.35 if narrow else 0.0
            upper = P("M", xi - sx * 0.2, EY + 0.1, "Q", ex, EY - ry * (1.95 if not narrow else 1.7), xo + sx * 0.25, EY - lift - 0.1)
            for gk in ("m", "f"):
                lw = 1.2 if gk == "m" else 1.55
                s = ""
                if deep:
                    s += ell(ex, EY - 1.7, 2.9, 1.7, D, None, 0, 0.14)
                if heavy:
                    s += path(P("M", xi, EY, "Q", ex, EY - ry * 1.95, xo, EY - lift, "Q", ex, EY - ry * 0.5, xi, EY, "Z"), D, None, 0, 0.22)
                s += path(upper, None, LID, lw + (0.25 if heavy else 0.0))
                if crease:
                    s += path(P("M", xi + sx * 0.3, EY - 0.9, "Q", ex, EY - ry * 2.6 - 0.4, xo - sx * 0.1, EY - 1.2), None, D, 0.6, 0.22)
                elif narrow:
                    s += path(P("M", xi + sx * 0.2, EY - 0.5, "Q", ex, EY - ry * 1.9 - 0.3, xo, EY - 0.9), None, D, 0.5, 0.12)
                s += path(P("M", xi + sx * 0.6, EY + 0.55, "Q", ex, EY + ry * 1.25, xo - sx * 0.3, EY + 0.2), None, D, 0.5, 0.18)
                if gk == "f":
                    s += path(P("M", xo + sx * 0.15, EY - lift - 0.15, "l", sx * 1.0, -0.75), None, LID, 0.9)
                    s += path(P("M", ex + sx * 1.0, EY - ry * 1.55, "l", sx * 0.5, -0.7), None, LID, 0.6, 0.8)
                lids[gk] += s
        for gk in ("m", "f"):
            person_layer(f"eyes_{kind}_{gk}_front", white[gk])
            person_layer(f"lids_{kind}_{gk}_front", lids[gk])
        person_layer(f"iris_{kind}_front", f"<defs>{defs}</defs>" + iris)
        # профиль: один глаз у края лица
        ex = 7.9
        srx, sry = rx * 0.62, ry
        sh = P("M", ex - srx, EY, "Q", ex, EY - sry * 1.9, ex + srx, EY - 0.1, "Q", ex, EY + sry * 1.4, ex - srx, EY, "Z")
        cid = f"es_{kind}"
        person_layer(f"eyes_{kind}_m_side", path(sh, "#f3eee7", None, 0))
        person_layer(f"eyes_{kind}_f_side", path(sh, "#f3eee7", None, 0))
        person_layer(f"iris_{kind}_side", f'<defs><clipPath id="{cid}"><path d="{sh}"/></clipPath></defs>'
                     f'<g clip-path="url(#{cid})">' + circ(ex + 0.55, EY - 0.1, min(1.1, sry + 0.15), WHITE, None, 0)
                     + circ(ex + 0.75, EY - 0.1, 0.5, "#111", None, 0) + "</g>")
        for gk in ("m", "f"):
            s = path(P("M", ex - srx - 0.2, EY + 0.1, "Q", ex, EY - sry * 1.95, ex + srx + 0.2, EY - 0.2), None, LID, 1.2 if gk == "m" else 1.5)
            if heavy:
                s += path(P("M", ex - srx, EY, "Q", ex, EY - sry * 1.9, ex + srx, EY - 0.1, "Q", ex, EY - sry * 0.4, ex - srx, EY, "Z"), D, None, 0, 0.22)
            if deep:
                s += ell(ex - 0.3, EY - 1.6, 2.2, 1.5, D, None, 0, 0.14)
            if gk == "f":
                s += path(P("M", ex + srx + 0.1, EY - 0.3, "l", 1.0, -0.6), None, LID, 0.9)
            person_layer(f"lids_{kind}_{gk}_side", s)


def eyes_lod():
    """Глаза для мелкого масштаба: тёмные овалы без белка и век — на экране в несколько пикселей читаются чётче."""
    for gk in ("m", "f"):
        s = ""
        for sx in (-1, 1):
            s += ell(sx * EX, EY, 1.45, 1.75, "#21170f", None, 0)
            if gk == "f":
                s += path(P("M", sx * (EX + 1.2), EY - 1.1, "l", sx * 1.2, -0.8), None, "#21170f", 1.1)
        person_layer(f"eyeslod_{gk}_front", s)
        ss = ell(7.9, EY, 1.1, 1.7, "#21170f", None, 0)
        if gk == "f":
            ss += path(P("M", 8.8, EY - 1.2, "l", 1.1, -0.7), None, "#21170f", 1.0)
        person_layer(f"eyeslod_{gk}_side", ss)


# ------------------------------------------------------------------ брови (белые — тонируются цветом волос)

BROWS = {
    #          ширина  дуга  наклон к переносице  толщина
    "straight": (2.5, 0.4, 0.0, 1.5),
    "arched": (2.5, 1.2, 0.0, 1.35),
    "thick": (2.7, 0.5, 0.2, 2.2),
    "thin": (2.4, 1.1, 0.0, 0.85),
    "angled": (2.5, 0.5, 0.7, 1.6),
    "bushy": (2.8, 0.6, 0.1, 2.0),
}


def brows():
    by = EY - 3.4
    for kind, (hw, arc, tilt, th) in BROWS.items():
        s = ""
        for sx in (-1, 1):
            ex = EX * sx
            xi, xo = ex - sx * (hw - 0.3), ex + sx * hw
            yi, yo = by + tilt, by - tilt * 0.3
            d = P("M", xi, yi, "Q", ex, by - arc - 0.6, xo, yo + 0.4)
            s += path(d, None, WHITE, th + 0.3)
            if kind == "bushy":
                s += path(P("M", xi + sx * 0.8, yi - 0.6, "l", sx * 0.9, -0.9, "M", ex, by - arc - 0.3, "l", sx * 1.0, -0.8, "M", xo - sx * 0.8, yo, "l", sx * 0.9, -0.6), None, WHITE, 0.8)
            s += path(d, None, D, th + 0.3, 0.22)
        person_layer(f"brows_{kind}_front", s)
        ex = 7.9
        d2 = P("M", ex - 2.2, by + tilt * 0.6, "Q", ex, by - arc - 0.5, ex + 2.0, by + 0.3)
        person_layer(f"brows_{kind}_side", path(d2, None, WHITE, th) + path(d2, None, D, th, 0.18))
    person_layer("brows_front", "")
    person_layer("brows_side", "")


# ------------------------------------------------------------------ нос

NOSES = ("small", "straight", "long", "wide", "hooked")


def noses():
    for kind in NOSES:
        tip = {"small": 3.6, "straight": 4.0, "long": 5.0, "wide": 3.8, "hooked": 4.3}[kind]
        s = ""
        if kind == "hooked":
            s += path(P("M", 0.7, EY - 1.4, "Q", -1.5, EY + 0.6, -0.5, EY + 1.8, "Q", 0.7, EY + 2.8, -0.1, tip), None, D, 1.15, 0.55)
        else:
            s += path(P("M", 0.7, EY - (1.6 if kind in ("straight", "long") else 0.6), "Q", -1.2, EY + tip * 0.7, 0.1, EY + tip), None, D, 1.15, 0.52)
        nw = 2.3 if kind == "wide" else 1.6
        s += path(P("M", -nw, EY + tip + 0.4, "Q", 0, EY + tip + 1.3, nw, EY + tip + 0.4), None, D, 1.1, 0.62)
        if kind == "wide":
            s += path(P("M", -2.6, EY + tip - 0.8, "Q", -3.2, EY + tip + 0.4, -2.2, EY + tip + 0.9, "M", 2.6, EY + tip - 0.8, "Q", 3.2, EY + tip + 0.4, 2.2, EY + tip + 0.9), None, D, 0.8, 0.3)
        s += circ(0.4, EY + tip - 0.4, 0.75, "#fff", None, 0, 0.2)
        person_layer(f"nose_{kind}_front", s)
        # профиль: выступает за край лица, тонируется кожей
        w = 12.9
        shapes = {
            "small": P("M", w - 1.5, EY - 0.6, "Q", w + 1.2, EY + 2.2, w + 1.0, EY + 3.3, "Q", w + 0.2, EY + 4.1, w - 1.5, EY + 3.8, "Z"),
            "straight": P("M", w - 1.5, EY - 1.6, "L", w + 1.8, EY + 3.0, "Q", w + 1.7, EY + 4.2, w - 1.5, EY + 4.0, "Z"),
            "long": P("M", w - 1.5, EY - 1.8, "L", w + 2.4, EY + 3.8, "Q", w + 2.0, EY + 5.0, w - 1.5, EY + 4.6, "Z"),
            "wide": P("M", w - 1.5, EY - 0.8, "Q", w + 1.0, EY + 1.4, w + 1.7, EY + 3.0, "Q", w + 1.6, EY + 4.6, w - 1.5, EY + 4.2, "Z"),
            "hooked": P("M", w - 1.5, EY - 1.8, "Q", w + 2.4, EY - 0.6, w + 2.1, EY + 3.4, "Q", w + 1.4, EY + 4.6, w - 1.5, EY + 4.2, "Z"),
        }
        d = shapes[kind]
        person_layer(f"nose_{kind}_side", path(d, WHITE, None, 0) + path(d.replace("Z", ""), None, OUT, 1.3)
                     + path(P("M", w - 0.4, EY + 3.6, "q", 0.8, 0.2, 1.0, -0.4), None, D, 0.8, 0.4))


# ------------------------------------------------------------------ рот

MOUTHS = ("neutral", "smile", "thin", "full", "down")


def mouths():
    my = MY
    for kind in MOUTHS:
        for gk in ("m", "f"):
            s = ""
            hw = 2.4 if kind != "thin" else 2.0
            if kind == "smile":
                line_d = P("M", -hw - 0.3, my - 0.4, "Q", 0, my + 1.5, hw + 0.3, my - 0.4)
            elif kind == "down":
                line_d = P("M", -hw, my + 0.5, "Q", 0, my - 0.45, hw, my + 0.5)
            else:
                line_d = P("M", -hw, my, "Q", 0, my + 0.45, hw, my)
            if gk == "f" or kind == "full":
                # губы: верхняя «лодочкой», нижняя полнее
                lc = "#a7564a" if gk == "f" else "#8a4a3e"
                up = 0.9 if kind == "full" or gk == "f" else 0.6
                lo = 1.6 if kind == "full" else 1.3
                s += path(P("M", -hw, my, "Q", -hw * 0.5, my - up, 0, my - up * 0.55, "Q", hw * 0.5, my - up, hw, my, "Z"), lc, None, 0, 0.85 if gk == "f" else 0.45)
                s += path(P("M", -hw + 0.2, my + 0.1, "Q", 0, my + lo + 0.4, hw - 0.2, my + 0.1, "Z"), lc, None, 0, 0.8 if gk == "f" else 0.4)
            s += path(line_d, None, LIP, 1.35 if kind != "thin" else 1.15)
            if gk == "m" and kind != "full":
                s += path(P("M", -1.0, my + 1.7, "H", 1.0), None, D, 0.8, 0.22)
            if kind == "smile":
                s += path(P("M", -hw - 1.2, my - 1.3, "q", -0.4, 0.8, 0.1, 1.5, "M", hw + 1.2, my - 1.3, "q", 0.4, 0.8, -0.1, 1.5), None, D, 0.6, 0.2)
            person_layer(f"mouth_{kind}_{gk}_front", s)
            # профиль
            x0, x1 = 9.3, 12.2
            if kind == "smile":
                sd = P("M", x0, my - 0.3, "Q", (x0 + x1) / 2, my + 0.9, x1, my - 0.2)
            elif kind == "down":
                sd = P("M", x0, my + 0.5, "Q", (x0 + x1) / 2, my - 0.2, x1, my + 0.1)
            else:
                sd = P("M", x0, my + 0.1, "L", x1, my)
            ss = ""
            if gk == "f":
                ss += ell(x1 - 0.6, my + 0.4, 1.0, 1.0, "#a7564a", None, 0, 0.75)
            ss += path(sd, None, LIP, 1.3)
            person_layer(f"mouth_{kind}_{gk}_side", ss)


# ------------------------------------------------------------------ морщины, веснушки, серьги

def lines_age():
    for age in ("mid", "old"):
        k = 0.2 if age == "mid" else 0.38
        s = path(P("M", -2.6, EY + 4.3, "Q", -4.5, EY + 6.2, -3.9, EY + 8.6, "M", 2.6, EY + 4.3, "Q", 4.5, EY + 6.2, 3.9, EY + 8.6), None, D, 0.8, k)
        s += path(P("M", -3.5, HY - 7.6, "Q", 0, HY - 8.6, 3.5, HY - 7.6), None, D, 0.7, k * 0.8)
        if age == "old":
            s += path(P("M", -3, HY - 9.4, "Q", 0, HY - 10.2, 3, HY - 9.4), None, D, 0.7, 0.28)
            for sx in (-1, 1):
                xo = sx * (EX + 2.6)
                s += path(P("M", xo, EY - 0.6, "l", sx * 1.4, -0.7, "M", xo + sx * 0.2, EY + 0.3, "l", sx * 1.5, 0.1, "M", xo, EY + 1.1, "l", sx * 1.3, 0.8), None, D, 0.55, 0.3)
                s += path(P("M", sx * (EX - 1.8), EY + 2.1, "Q", sx * EX, EY + 3.0, sx * (EX + 1.8), EY + 2.0), None, D, 0.6, 0.3)
            s += path(P("M", -3.6, MY + 1.0, "q", -0.3, 1.6, 0.4, 2.8, "M", 3.6, MY + 1.0, "q", 0.3, 1.6, -0.4, 2.8), None, D, 0.6, 0.22)
        person_layer(f"lines_{age}_front", s)
        ss = path(P("M", 10.6, EY + 4.4, "Q", 8.8, EY + 6.4, 9.3, EY + 8.4), None, D, 0.8, k)
        ss += path(P("M", 6.4, HY - 7.8, "Q", 9, HY - 8.4, 11.6, HY - 7.4), None, D, 0.7, k * 0.8)
        if age == "old":
            ss += path(P("M", 5.4, EY - 0.4, "l", -1.3, -0.6, "M", 5.4, EY + 0.6, "l", -1.4, 0.3), None, D, 0.55, 0.3)
            ss += path(P("M", 6.6, EY + 2.0, "Q", 8, EY + 2.9, 9.6, EY + 2.0), None, D, 0.6, 0.3)
        person_layer(f"lines_{age}_side", ss)
    fr = ""
    pts = [(-6.6, EY + 3.0), (-5.2, EY + 3.9), (-3.6, EY + 3.1), (-1.6, EY + 2.4), (1.6, EY + 2.4), (3.4, EY + 3.3), (5.1, EY + 3.8), (6.5, EY + 2.9), (-0.4, EY + 1.2), (0.6, EY + 1.6)]
    for x, y in pts:
        fr += circ(x, y, 0.42, "#8a4a2a", None, 0, 0.5)
    person_layer("freckles_front", fr)
    person_layer("freckles_side", "".join(circ(x, y, 0.42, "#8a4a2a", None, 0, 0.5) for x, y in [(6.4, EY + 3.0), (8.0, EY + 3.6), (9.6, EY + 2.6), (10.8, EY + 3.4)]))
    er = ""
    for sx in (-1, 1):
        er += circ(sx * 13.0, HY + 4.6, 0.95, "#e2b33c", "#8a6a1c", 0.5)
    person_layer("earrings_front", er)
    person_layer("earrings_side", circ(-1.4, HY + 5.2, 0.95, "#e2b33c", "#8a6a1c", 0.5))


# ------------------------------------------------------------------ причёски (белые — тонируются)

def cap_front(y, ext=0.0):
    """Свод причёски спереди: от левого виска через макушку к правому (без линии лба)."""
    t = y - HR - 2.4 - ext
    return P("M", -RH - ext * 0.5, y + 1.5, "Q", -RH - 1.2 - ext, t, 0, t, "Q", RH + 1.2 + ext, t, RH + ext * 0.5, y + 1.5)


def back_cover(y, low=0.0, ext=0.0):
    t = y - HR - 2.4 - ext
    bot = y + HR * 0.84 + low
    return P("M", -RH - ext * 0.5, y + 1.5, "Q", -RH - 1.2 - ext, t, 0, t, "Q", RH + 1.2 + ext, t, RH + ext * 0.5, y + 1.5,
             "Q", RH - 0.4, y + 7.5 + low, RH * 0.55, bot - 1.6, "Q", 0, bot, -RH * 0.55, bot - 1.6, "Q", -RH + 0.4, y + 7.5 + low, -RH - ext * 0.5, y + 1.5, "Z")


def side_cover(y, fringe, low=0.0, ext=0.0, burn=True):
    """Профиль лицом вправо: затылок, макушка, чёлка спереди, бакенбард перед ухом, волосы за ухом."""
    t = y - HR - 2.4 - ext
    w = RH
    nape = (-w * 0.6, y + HR * 0.74 + low)
    s = P("M", nape[0], nape[1], "Q", -w - 1.2 - ext, y + 6 + low * 0.5, -w - 0.8 - ext * 0.6, y - 1,
          "Q", -w - 0.6 - ext, t, 1, t, "Q", w + 0.2 + ext * 0.5, t + 0.5, w + 0.3, y - 5)
    s += fringe
    if burn:
        s += P("L", 2.6, y + 4.4, "L", 0.6, y + 4.6)
    else:
        s += P("L", 1.2, y - 1.8, "Q", 0.4, y + 2, 0.4, y + 4.6)
    s += P("L", -4.8, y + 5.2 + low * 0.4, "Q", -5.8, y + 8 + low * 0.7, nape[0], nape[1], "Z")
    return s


def tex_strands(ds, op=0.22):
    return path(ds, None, D, 0.7, op)


def hair_styles():
    y = HY
    H = {}
    burns = (P("M", RH - 0.2, y + 0.5, "L", RH - 0.1, y + 4.2, "L", RH - 1.9, y + 4.2, "L", RH - 2.0, y - 0.5, "Z")
             + P("M", -RH + 0.2, y + 0.5, "L", -RH + 0.1, y + 4.2, "L", -RH + 1.9, y + 4.2, "L", -RH + 2.0, y - 0.5, "Z"))

    def front(cap_line, extra="", strands="", burn=True):
        s = path(cap_front(y) + cap_line + "Z", WHITE, OUT, 1.9)
        if burn:
            s += path(burns, WHITE, None, 0)
        return s + extra + (tex_strands(strands) if strands else "")

    # --- мужские
    H["short"] = {
        "front": front(P("Q", RH - 1.2, y - 4.8, RH - 3.6, y - 6.8, "Q", 3, y - 9, -2.4, y - 6.2, "Q", -5.6, y - 8.2, -RH + 2.6, y - 5.2, "Q", -RH + 0.6, y - 2.4, -RH, y + 1.5),
                       strands=P("M", -6, y - 10.5, "q", 3, -2, 7, -1, "M", 1, y - 12.5, "q", 3, 0, 6, 2.4)),
        "back": path(back_cover(y), WHITE, OUT, 1.9) + tex_strands(P("M", -5, y - 8, "q", 2, 5, 1, 12, "M", 4, y - 9, "q", -1, 6, 0, 13)),
        "side": path(side_cover(y, P("Q", RH - 2.5, y - 7.6, RH - 5.4, y - 6.2, "Q", 3.4, y - 7.4, 2.6, y - 2)), WHITE, OUT, 1.9),
    }
    H["crew"] = {
        "front": path(cap_front(y, -0.8) + P("Q", RH - 1, y - 5.2, RH - 3.5, y - 7.4, "Q", 0, y - 8.8, -RH + 3.5, y - 7.4, "Q", -RH + 1, y - 5.2, -RH + 0.4, y + 1.5, "Z"), WHITE, OUT, 1.1, 0.95)
        + path(burns, WHITE, None, 0, 0.9),
        "back": path(back_cover(y, -1, -0.8), WHITE, OUT, 1.1, 0.95),
        "side": path(side_cover(y, P("Q", RH - 2, y - 7.4, RH - 4.4, y - 7, "Q", 2.8, y - 6.8, 2.6, y - 2), -0.5, -0.8), WHITE, OUT, 1.1, 0.95),
    }
    H["side"] = {
        "front": front(P("Q", RH - 0.8, y - 5.6, RH - 4, y - 8.6, "Q", 0, y - 10.8, -3.8, y - 9.1, "L", -4.8, y - 8.2, "Q", -RH + 1.6, y - 7, -RH, y + 1.5),
                       strands=P("M", -4.2, y - 9, "Q", -3.6, y - 12, -2.4, y - 15.2, "M", -1, y - 10.4, "q", 4, -2.2, 9, -0.6)),
        "back": path(back_cover(y), WHITE, OUT, 1.9) + tex_strands(P("M", -6, y - 10, "q", 1, 6, 0, 12, "M", 3, y - 11, "q", 1, 6, 0, 13)),
        "side": path(side_cover(y, P("Q", RH - 1.5, y - 8.4, RH - 4.6, y - 8.2, "Q", 2.6, y - 8, 2.6, y - 2)), WHITE, OUT, 1.9)
        + tex_strands(P("M", RH - 4.6, y - 8.2, "q", -6, -3, -14, -0.6)),
    }
    H["slick"] = {
        "front": front(P("Q", RH - 0.6, y - 6, RH - 4.5, y - 9.3, "Q", 0, y - 11, -RH + 4.5, y - 9.3, "Q", -RH + 0.6, y - 6, -RH, y + 1.5),
                       strands=P("M", -4, y - 10.6, "Q", -4.4, y - 13, -5.6, y - 15, "M", 0, y - 11, "V", y - 15.4, "M", 4, y - 10.6, "Q", 4.4, y - 13, 5.6, y - 15)),
        "back": path(back_cover(y), WHITE, OUT, 1.9) + tex_strands(P("M", -5, y - 14, "q", -1, 8, 0, 16, "M", 0, y - 15, "v", 17, "M", 5, y - 14, "q", 1, 8, 0, 16)),
        "side": path(side_cover(y, P("Q", RH - 1.2, y - 8.6, RH - 4.2, y - 9.2, "Q", 2.6, y - 8, 2.6, y - 2)), WHITE, OUT, 1.9)
        + tex_strands(P("M", RH - 4.2, y - 9.2, "q", -7, -1.6, -15, 1.4, "M", RH - 4.6, y - 11.6, "q", -6, -1, -14, 3)),
    }
    H["receding"] = {
        "front": front(P("Q", RH - 0.2, y - 4, RH - 3.6, y - 6.8, "Q", RH * 0.4, y - 10.4, 0, y - 9.6, "Q", -RH * 0.4, y - 10.4, -RH + 3.6, y - 6.8, "Q", -RH + 0.2, y - 4, -RH, y + 1.5)),
        "back": path(back_cover(y), WHITE, OUT, 1.9),
        "side": path(side_cover(y, P("Q", RH - 3.5, y - 9.5, RH - 6.4, y - 8.4, "Q", 2.4, y - 6.4, 2.6, y - 2)), WHITE, OUT, 1.9),
    }
    tuft_l = P("M", -RH + 0.1, y + 3, "Q", -RH - 0.6, y - 3, -RH + 2.2, y - 6.4, "Q", -RH + 2.4, y - 1.6, -RH + 2.0, y + 3, "Z")
    tuft_r = P("M", RH - 0.1, y + 3, "Q", RH + 0.6, y - 3, RH - 2.2, y - 6.4, "Q", RH - 2.4, y - 1.6, RH - 2.0, y + 3, "Z")
    H["bald"] = {
        "front": path(tuft_l, WHITE, OUT, 1.1) + path(tuft_r, WHITE, OUT, 1.1),
        "back": path(P("M", -RH, y - 2, "Q", -RH + 0.4, y + 8, -RH * 0.5, y + HR * 0.74, "Q", 0, y + HR * 0.86, RH * 0.5, y + HR * 0.74,
                       "Q", RH - 0.4, y + 8, RH, y - 2, "Q", RH - 2.6, y + 4.4, 0, y + 5.2, "Q", -RH + 2.6, y + 4.4, -RH, y - 2, "Z"), WHITE, OUT, 1.2),
        "side": path(P("M", -RH * 0.6, y + HR * 0.74, "Q", -RH - 1, y + 6, -RH - 0.6, y - 3, "Q", -RH + 2, y - 4, -4.2, y - 2.8,
                       "L", -4.6, y + 4.5, "Q", -5.8, y + 8, -RH * 0.6, y + HR * 0.74, "Z"), WHITE, OUT, 1.2)
        + path(P("M", 0.9, y - 3.6, "Q", 2.4, y - 2.4, 2.6, y + 4.4, "L", 0.9, y + 4.4, "Z"), WHITE, OUT, 1.0),
    }

    def curls(cs, r0, tex=True, base=""):
        # подложка под кудрями — между кружками не просвечивает кожа головы
        s0 = path(base, WHITE, None, 0) if base else ""
        s0 += "".join(circ(cx, cy, r0, WHITE, OUT, 1.5) for cx, cy in cs) + "".join(circ(cx, cy, r0 - 0.12, WHITE, None, 0) for cx, cy in cs)
        if tex:
            s0 += "".join(path(P("M", cx - r0 * 0.55, cy + r0 * 0.15, "Q", cx - r0 * 0.1, cy - r0 * 0.7, cx + r0 * 0.45, cy - r0 * 0.05), None, D, 0.65, 0.28) for cx, cy in cs)
        return s0
    cf = [(-RH + 1.4, y - 2), (-RH + 2.2, y - 7), (-8, y - 11.6), (-3, y - 13.4), (3, y - 13.4), (8, y - 11.6), (RH - 2.2, y - 7), (RH - 1.4, y - 2),
          (-6.4, y - 8.4), (-1.8, y - 9.2), (2.6, y - 9), (6.6, y - 8.2)]
    cb = [(-RH + 1.2, y - 1), (-RH + 1.8, y - 7), (-8, y - 11.4), (-3, y - 13.2), (3, y - 13.2), (8, y - 11.4), (RH - 1.8, y - 7), (RH - 1.2, y - 1),
          (-RH + 2.6, y + 5), (RH - 2.6, y + 5), (-5, y + 8), (0, y + 9), (5, y + 8), (-5, y - 4), (0, y - 6), (5, y - 4), (-6, y + 2), (0, y + 2), (6, y + 2)]
    cs = [(-RH + 0.6, y), (-RH + 1, y - 6), (-7, y - 11.6), (-1, y - 13.6), (5, y - 12.6), (RH - 2.8, y - 9), (-RH + 2.4, y + 6), (-6, y + 7.4),
          (-4.6, y - 5), (1, y - 8.4), (7, y - 7.6)]
    base_m = cap_front(y, -0.6) + P("Q", RH - 1.6, y - 5, RH - 3.8, y - 7.2, "Q", 0, y - 8.8, -RH + 3.8, y - 7.2, "Q", -RH + 1.6, y - 5, -RH + 0.4, y + 1.5, "Z")
    H["curly"] = {"front": curls(cf, 3.4, True, base_m) + path(burns, WHITE, None, 0), "back": curls(cb, 3.6, True, back_cover(y, -1.5, -0.8)),
                  "side": curls(cs, 3.4, True, side_cover(y, P("Q", RH - 2, y - 7.4, RH - 4.4, y - 7, "Q", 2.8, y - 6.8, 2.6, y - 2), -0.5, -0.8))}
    H["mullet"] = {
        "front": H["short"]["front"] + path(P("M", -RH + 0.2, y + 3, "Q", -RH - 1.2, y + 9, -RH + 1.4, y + 13, "L", -RH + 2.6, y + 4, "Z",
                                              "M", RH - 0.2, y + 3, "Q", RH + 1.2, y + 9, RH - 1.4, y + 13, "L", RH - 2.6, y + 4, "Z"), WHITE, OUT, 1.2),
        "back": path(back_cover(y, 6.0), WHITE, OUT, 1.9) + tex_strands(P("M", -5, y + 4, "q", 0, 6, -1, 10, "M", 0, y + 5, "v", 11, "M", 5, y + 4, "q", 0, 6, 1, 10)),
        "side": path(side_cover(y, P("Q", RH - 2.5, y - 7.6, RH - 5.4, y - 6.2, "Q", 3.4, y - 7.4, 2.6, y - 2), 6.0), WHITE, OUT, 1.9),
    }

    # --- женские
    H["bob"] = {
        "front": path(P("M", -RH - 1.6, y + 7, "Q", -RH - 2.4, y - HR - 2.6, 0, y - HR - 2.6, "Q", RH + 2.4, y - HR - 2.6, RH + 1.6, y + 7,
                        "Q", RH, y + 7.8, RH - 1.6, y + 6.4, "Q", RH - 1.8, y - 4, 3, y - 7.6, "Q", -3, y - 7.4, -RH + 2, y - 2.6,
                        "L", -RH + 1.6, y + 6.4, "Q", -RH, y + 7.8, -RH - 1.6, y + 7, "Z"), WHITE, OUT, 1.9)
        + tex_strands(P("M", 3, y - 7.6, "Q", 4, y - 12, 2, y - 15.4, "M", -RH + 2, y - 2.6, "q", 1, -5, 6, -9)),
        "back": path(back_cover(y, 4.0, 1.2), WHITE, OUT, 1.9) + tex_strands(P("M", -6, y + 2, "q", 0, 5, -1, 9, "M", 0, y + 2, "v", 10, "M", 6, y + 2, "q", 0, 5, 1, 9)),
        "side": path(side_cover(y, P("Q", RH - 1.5, y - 8, RH - 4, y - 7.8, "Q", 3.4, y - 6.4, 3.6, y + 0.8), 4.0, 1.2, burn=False)
                     .replace(P("L", 1.2, y - 1.8), P("L", 3.6, y + 6.2, "Q", 1, y + 7.6, -1, y + 5.4, "L", -1.6, y - 1.8)), WHITE, OUT, 1.9),
    }
    pulled = P("Q", RH - 1.2, y - 5.8, 0, y - 8.2, "Q", -RH + 1.2, y - 5.8, -RH, y + 1.5)
    part = path(P("M", 0, y - 8.2, "Q", -0.5, y - 11.5, 0, y - 15.2), None, D, 0.9, 0.3) + tex_strands(P("M", -1.4, y - 8, "q", -4, 0, -9, 5, "M", 1.4, y - 8, "q", 4, 0, 9, 5))
    bun = lambda cx, cy, r0: circ(cx, cy, r0, WHITE, OUT, 1.7) + path(P("M", cx - r0 * 0.6, cy - r0 * 0.2, "q", r0 * 0.6, r0 * 0.6, r0 * 1.2, 0), None, D, 0.7, 0.25)
    H["bun"] = {
        "front": bun(0, y - HR - 3.6, 4.6) + path(cap_front(y) + pulled + "Z", WHITE, OUT, 1.9) + part,
        "back": path(back_cover(y, -1.2), WHITE, OUT, 1.9) + bun(0, y - 4.6, 5.0) + tex_strands(P("M", -8, y + 4, "Q", -5, y - 2, -2, y - 4, "M", 8, y + 4, "Q", 5, y - 2, 2, y - 4)),
        "side": bun(-RH + 1.6, y - 7.6, 4.8) + path(side_cover(y, P("Q", RH - 2, y - 7.2, RH - 3.6, y - 6.2, "Q", 3, y - 4.4, 2.6, y - 1.4), -1.0, burn=False), WHITE, OUT, 1.9),
    }
    tail_b = path(P("M", -2.8, y + 2, "Q", -5.6, y + 14, -1.6, y + 22, "Q", 0, y + 23.6, 1.6, y + 22, "Q", 5.6, y + 14, 2.8, y + 2, "Z"), WHITE, OUT, 1.7) \
        + rect(-3.1, y + 1.2, 6.2, 2.6, "#c9372c", OUT, 0.6, 1.2)
    H["ponytail"] = {
        "front": path(cap_front(y) + pulled + "Z", WHITE, OUT, 1.9) + part,
        "back": path(back_cover(y, -1.2), WHITE, OUT, 1.9) + tail_b,
        "side": path(P("M", -RH + 0.4, y - 3, "Q", -RH - 7, y + 4, -RH - 3, y + 15, "Q", -RH + 0.6, y + 9, -RH + 2.4, y - 1, "Z"), WHITE, OUT, 1.7)
        + path(side_cover(y, P("Q", RH - 2, y - 7.2, RH - 3.6, y - 6.2, "Q", 3, y - 4.4, 2.6, y - 1.4), -1.0, burn=False), WHITE, OUT, 1.9),
    }
    H["long"] = {
        "front": path(P("M", -RH - 1.8, y + 17, "Q", -RH - 3, y - HR - 2.8, 0, y - HR - 2.8, "Q", RH + 3, y - HR - 2.8, RH + 1.8, y + 17,
                        "Q", RH, y + 18, RH - 1.4, y + 16.4, "Q", RH - 1.2, y - 2, 1, y - 8.4, "Q", -RH + 1.2, y - 2, -RH + 1.4, y + 16.4,
                        "Q", -RH, y + 18, -RH - 1.8, y + 17, "Z"), WHITE, OUT, 1.9)
        + tex_strands(P("M", 1, y - 8.4, "Q", 0.4, y - 12, 0.8, y - 15.6, "M", -RH + 1.4, y + 6, "q", -0.6, 4, 0, 9, "M", RH - 1.4, y + 6, "q", 0.6, 4, 0, 9)),
        "back": path(P("M", -RH - 1.6, y + 1.5, "Q", -RH - 3, y - HR - 2.8, 0, y - HR - 2.8, "Q", RH + 3, y - HR - 2.8, RH + 1.6, y + 1.5,
                       "Q", RH + 2.6, y + 14, RH, y + 20, "Q", 0, y + 23, -RH, y + 20, "Q", -RH - 2.6, y + 14, -RH - 1.6, y + 1.5, "Z"), WHITE, OUT, 1.9)
        + tex_strands(P("M", -6, y + 2, "q", -1, 8, 0, 17, "M", 0, y - 4, "v", 25, "M", 6, y + 2, "q", 1, 8, 0, 17)),
        "side": path(P("M", -RH + 0.6, y - 2, "Q", -RH - 3.4, y + 8, -RH - 1, y + 20, "Q", -4, y + 22, 0.4, y + 19, "Q", -2.6, y + 10, -1.2, y + 2, "Z"), WHITE, OUT, 1.7)
        + path(side_cover(y, P("Q", RH - 1.6, y - 8, RH - 3.8, y - 7.4, "Q", 3, y - 5.6, 2.4, y - 1.4), 2.0, 1.2, burn=False), WHITE, OUT, 1.9),
    }
    H["pixie"] = {
        "front": path(cap_front(y, 0.4) + P("Q", RH - 0.4, y - 3.2, RH - 2.6, y - 5.8, "Q", 2, y - 6.4, -4.4, y - 3.4, "Q", -6.4, y - 6.6, -RH + 2.2, y - 4.6,
                                           "Q", -RH + 0.4, y - 1, -RH + 0.4, y + 3.6, "Z"), WHITE, OUT, 1.9)
        + tex_strands(P("M", -4.4, y - 3.4, "q", 2, -4, 8, -6.6, "M", 4, y - 12.6, "q", 3, 1, 5, 4)),
        "back": path(back_cover(y, -0.4, 0.4), WHITE, OUT, 1.9) + tex_strands(P("M", -4, y - 6, "q", 1, 5, 0, 11, "M", 4, y - 6, "q", -1, 5, 0, 11)),
        "side": path(side_cover(y, P("Q", RH - 0.6, y - 4.6, RH - 2.6, y - 4.4, "Q", 3.6, y - 5.4, 2.4, y - 1.4), 0, 0.4, burn=False), WHITE, OUT, 1.9),
    }
    cff = [(-RH, y + 5), (-RH - 0.4, y), (-RH + 0.6, y - 6), (-8, y - 11.6), (-3, y - 14), (3, y - 14), (8, y - 11.6), (RH - 0.6, y - 6), (RH + 0.4, y), (RH, y + 5),
           (-6, y - 8.6), (0, y - 10), (6, y - 8.6)]
    cfb = [(-RH, y + 5), (-RH - 0.4, y - 1), (-RH + 0.6, y - 7), (-8, y - 11.6), (-3, y - 14), (3, y - 14), (8, y - 11.6), (RH - 0.6, y - 7), (RH + 0.4, y - 1), (RH, y + 5),
           (-8, y + 9), (-3, y + 11), (3, y + 11), (8, y + 9), (-6, y - 4), (0, y - 6), (6, y - 4), (-6, y + 3), (0, y + 3), (6, y + 3)]
    cfs = [(-RH, y + 5), (-RH - 0.6, y - 1), (-RH + 0.4, y - 7), (-7, y - 12), (-1, y - 14), (5, y - 13), (RH - 2.4, y - 9.6), (-RH + 3, y + 10), (-7, y + 9),
           (-5, y - 5), (1, y - 9), (-4, y + 3)]
    base_f = P("M", -RH, y + 5, "Q", -RH - 1, y - HR - 1.6, 0, y - HR - 1.6, "Q", RH + 1, y - HR - 1.6, RH, y + 5,
               "L", RH - 2.2, y + 5, "Q", RH - 2.4, y - 4.6, 0, y - 7.6, "Q", -RH + 2.4, y - 4.6, -RH + 2.2, y + 5, "Z")
    H["curly_f"] = {"front": curls(cff, 3.8, True, base_f), "back": curls(cfb, 4.0, True, back_cover(y, 3.0, 0.4)),
                    "side": curls(cfs, 3.8, True, side_cover(y, P("Q", RH - 1.6, y - 8, RH - 3.8, y - 7.4, "Q", 3, y - 5.6, 2.4, y - 1.4), 2.0, 0.4, burn=False))}
    pf = []
    for k in range(11):
        a = math.pi * (1.02 + 0.96 * k / 10)
        pf.append((math.cos(a) * (RH + 0.4), y - 3.4 + math.sin(a) * (HR + 0.6)))
    pf += [(-RH - 0.8, y + 2.4), (RH + 0.8, y + 2.4), (-7, y - 10.6), (-2.4, y - 12), (2.4, y - 12), (7, y - 10.6), (-4.6, y - 8.4), (0, y - 9.4), (4.6, y - 8.4)]
    pb = []
    for k in range(13):
        a = math.pi * (0.95 + 1.1 * k / 12)
        pb.append((math.cos(a) * (RH + 0.4), y - 2.4 + math.sin(a) * (HR + 1.4)))
    pb += [(-RH + 1, y + 6), (RH - 1, y + 6), (-6, y + 8.4), (0, y + 9.2), (6, y + 8.4), (-7, y + 1), (0, y + 1), (7, y + 1), (-4, y - 6), (4, y - 6), (0, y - 11), (-8, y - 9), (8, y - 9)]
    ps = []
    for k in range(10):
        a = math.pi * (0.8 + 1.05 * k / 9)
        ps.append((math.cos(a) * (RH + 0.3) - 0.6, y - 3 + math.sin(a) * (HR + 0.8)))
    ps += [(-RH + 1.2, y + 6.4), (-6, y + 7.6), (-6, y - 3), (-1, y - 9), (4, y - 10), (-4, y + 2)]
    base_p = P("M", -RH - 0.6, y + 3, "Q", -RH - 2, y - HR - 3.2, 0, y - HR - 3.2, "Q", RH + 2, y - HR - 3.2, RH + 0.6, y + 3,
               "L", RH - 1.6, y + 3, "Q", RH - 2.2, y - 5, 0, y - 7.4, "Q", -RH + 2.2, y - 5, -RH + 1.6, y + 3, "Z")
    H["perm"] = {"front": curls(pf, 3.1, True, base_p), "back": curls(pb, 3.2, True, back_cover(y, 2.0, 0.8)),
                 "side": curls(ps, 3.1, True, side_cover(y, P("Q", RH - 1.6, y - 8, RH - 3.8, y - 7.4, "Q", 3, y - 5.6, 2.4, y - 1.4), 1.0, 0.8, burn=False))}
    braid = ""
    for k in range(5):
        by = y + 4 + k * 3.6
        braid += ell(0 + (0.6 if k % 2 else -0.6), by, 2.9 - k * 0.12, 2.3, WHITE, OUT, 1.1)
    braid += rect(-1.8, y + 21.4, 3.6, 1.8, "#3f6fa0", OUT, 0.5, 0.8) + path(P("M", -1.2, y + 23, "L", -1.6, y + 26, "M", 0, y + 23, "V", y + 26.4, "M", 1.2, y + 23, "L", 1.6, y + 26), None, WHITE, 1.2)
    braid_front = ""
    for k in range(4):
        by = y + 8 + k * 3.4
        braid_front += ell(RH - 1.6 + (0.5 if k % 2 else -0.5), by, 2.5, 2.0, WHITE, OUT, 1.0)
    braid_front += rect(RH - 3.2, y + 20.4, 3.2, 1.6, "#3f6fa0", OUT, 0.5, 0.8)
    H["braid"] = {
        "front": braid_front + path(cap_front(y) + pulled + "Z", WHITE, OUT, 1.9) + part,
        "back": path(back_cover(y, -1.2), WHITE, OUT, 1.9) + braid,
        "side": "".join(ell(-RH + 2.2 - k * 0.3 + (0.5 if k % 2 else -0.5), y + 4 + k * 3.6, 2.6, 2.1, WHITE, OUT, 1.0) for k in range(5))
        + path(side_cover(y, P("Q", RH - 2, y - 7.2, RH - 3.6, y - 6.2, "Q", 3, y - 4.4, 2.6, y - 1.4), -1.0, burn=False), WHITE, OUT, 1.9),
    }
    for st, dd in H.items():
        for d, body in dd.items():
            person_layer(f"hair_{st}_{d}", body)
    # старые названия причёсок из сохранений
    for old, new in (("buzz", "crew"),):
        for d in ("front", "back", "side"):
            person_layer(f"hair_{old}_{d}", H[new][d])


# ------------------------------------------------------------------ бороды и усы (белые — тонируются)

def beards():
    y = HY
    jaw = P("M", -12.2, y + 2.4, "Q", -11.6, y + HR + 0.4, 0, y + HR + 1.3, "Q", 11.6, y + HR + 0.4, 12.2, y + 2.4,
            "Q", 10, y + 7, 5, MY - 0.2, "Q", 2, MY - 1.2, 0, MY - 1, "Q", -2, MY - 1.2, -5, MY - 0.2, "Q", -10, y + 7, -12.2, y + 2.4, "Z")
    lip = P("M", -3.9, MY - 1.3, "Q", 0, MY - 2.6, 3.9, MY - 1.3, "L", 3.6, MY - 0.4, "Q", 0, MY - 1.2, -3.6, MY - 0.4, "Z")
    must = P("M", -4.3, MY - 0.9, "Q", -2.2, MY - 2.8, 0, MY - 2.1, "Q", 2.2, MY - 2.8, 4.3, MY - 0.9, "Q", 2.2, MY - 0.4, 0, MY - 0.9, "Q", -2.2, MY - 0.4, -4.3, MY - 0.9, "Z")
    chev = P("M", -4.8, MY + 0.2, "Q", -3.6, MY - 3.0, 0, MY - 2.4, "Q", 3.6, MY - 3.0, 4.8, MY + 0.2, "Q", 2.4, MY - 0.6, 0, MY - 0.4, "Q", -2.4, MY - 0.6, -4.8, MY + 0.2, "Z")
    full = P("M", -12.4, y + 1.6, "Q", -12.6, y + HR + 3.6, 0, y + HR + 4.6, "Q", 12.6, y + HR + 3.6, 12.4, y + 1.6,
             "Q", 10.4, y + 6, 5.6, MY - 0.6, "Q", 2.2, MY - 1.8, 0, MY - 1.4, "Q", -2.2, MY - 1.8, -5.6, MY - 0.6, "Q", -10.4, y + 6, -12.4, y + 1.6, "Z")
    short = P("M", -12.2, y + 2.4, "Q", -11.8, y + HR + 1.8, 0, y + HR + 2.6, "Q", 11.8, y + HR + 1.8, 12.2, y + 2.4,
              "Q", 10, y + 7, 5, MY - 0.4, "Q", 2, MY - 1.4, 0, MY - 1.2, "Q", -2, MY - 1.4, -5, MY - 0.4, "Q", -10, y + 7, -12.2, y + 2.4, "Z")
    goat = P("M", -3.4, MY + 1.2, "Q", -3.2, y + HR + 3, 0, y + HR + 3.4, "Q", 3.2, y + HR + 3, 3.4, MY + 1.2, "Q", 0, MY + 2.2, -3.4, MY + 1.2, "Z")
    B = {
        "stubble": path(jaw, WHITE, None, 0, 0.38) + path(lip, WHITE, None, 0, 0.38),
        "mustache": path(must, WHITE, OUT, 0.9),
        "chevron": path(chev, WHITE, OUT, 1.0),
        "full": path(full, WHITE, OUT, 1.2) + path(must, WHITE, OUT, 0.8) + tex_strands(P("M", -6, y + 7, "q", 0, 4, 1, 6, "M", 0, MY + 2.4, "v", 4, "M", 6, y + 7, "q", 0, 4, -1, 6)),
        "short": path(short, WHITE, None, 0, 0.8) + path(must, WHITE, None, 0, 0.85),
        "goatee": path(goat, WHITE, OUT, 0.9) + path(must, WHITE, OUT, 0.8),
    }
    # профиль (лицом вправо)
    sjaw = P("M", -2.2, y + 3, "Q", -1.4, y + HR, 4, y + HR + 1.2, "Q", 11.6, y + HR - 1, 12.4, MY + 0.8, "Q", 10, MY - 0.4, 9, MY - 1.2, "Q", 7, y + 6, -2.2, y + 3, "Z")
    smust = P("M", 8.6, MY - 1.2, "Q", 11, MY - 2.8, 13.4, MY - 1.4, "Q", 11.4, MY - 0.4, 8.6, MY - 1.2, "Z")
    sfull = P("M", -2.6, y + 2, "Q", -2.4, y + HR + 2.6, 4, y + HR + 4.2, "Q", 13, y + HR + 2, 13.2, MY + 0.6, "Q", 11, MY - 0.4, 9, MY - 1.4, "Q", 6, y + 5, -2.6, y + 2, "Z")
    sgoat = P("M", 8.6, MY + 1.2, "Q", 9, y + HR + 3, 11.4, y + HR + 2.4, "Q", 12.6, MY + 3, 12.2, MY + 1.2, "Z")
    S = {
        "stubble": path(sjaw, WHITE, None, 0, 0.38),
        "mustache": path(smust, WHITE, OUT, 0.9),
        "chevron": path(P("M", 8.2, MY - 1.0, "Q", 10.8, MY - 3.4, 13.6, MY - 1.6, "Q", 13.2, MY + 0.4, 12.4, MY + 0.6, "Q", 11, MY - 0.6, 8.2, MY - 1.0, "Z"), WHITE, OUT, 1.0),
        "full": path(sfull, WHITE, OUT, 1.2) + path(smust, WHITE, OUT, 0.8),
        "short": path(sjaw, WHITE, None, 0, 0.8) + path(smust, WHITE, None, 0, 0.85),
        "goatee": path(sgoat, WHITE, OUT, 0.9) + path(smust, WHITE, OUT, 0.8),
    }
    for k in B:
        person_layer(f"beard_{k}_front", B[k])
        person_layer(f"beard_{k}_side", S[k])


# ------------------------------------------------------------------ головные уборы (белые — тонируются)

def hats():
    y = HY
    T = {}
    dome = lambda ext, low: P("M", -RH - ext, y - low, "Q", -RH - ext - 0.4, y - HR - 4 - ext, 0, y - HR - 4 - ext, "Q", RH + ext + 0.4, y - HR - 4 - ext, RH + ext, y - low, "Z")
    # каска
    T["helmet"] = {
        "front": path(dome(1.6, 2.6), WHITE, OUT, 2.2) + path(P("M", 0, y - HR - 5.6, "V", y - 3), None, D, 2.6, 0.12)
        + rect(-RH - 4.2, y - 4.2, 2 * RH + 8.4, 3.2, WHITE, OUT, 1.3, 1.6) + ell(-5, y - 12, 3.6, 2.2, "#fff", None, 0, 0.4),
        "back": path(dome(1.6, 1.6), WHITE, OUT, 2.2) + path(P("M", 0, y - HR - 5.6, "V", y - 2), None, D, 2.6, 0.12)
        + path(P("M", -RH - 4, y - 2.2, "Q", 0, y + 3.4, RH + 4, y - 2.2, "L", RH + 3.4, y + 0.8, "Q", 0, y + 6.4, -RH - 3.4, y + 0.8, "Z"), WHITE, OUT, 1.2),
        "side": path(dome(1.6, 2.2), WHITE, OUT, 2.2) + path(P("M", RH - 1, y - 4.4, "L", RH + 7.2, y - 2.4, "L", RH + 6.6, y - 0.6, "L", RH - 1.6, y - 2, "Z"), WHITE, OUT, 1.2)
        + path(P("M", -RH - 3.6, y - 1.6, "L", -RH + 2, y - 2.2, "L", -RH + 1.4, y - 0.4, "L", -RH - 3.2, y + 0.4, "Z"), WHITE, OUT, 1.1)
        + path(P("M", -2, y - HR - 5.4, "Q", 6, y - 12, 7.4, y - 3), None, D, 2.6, 0.12),
    }
    crown = lambda low: P("M", -RH - 0.7, y - low, "Q", -RH - 1, y - HR - 3.8, 0, y - HR - 3.8, "Q", RH + 1, y - HR - 3.8, RH + 0.7, y - low, "Z")
    visor_f = P("M", -RH + 1.2, y - 3.6, "Q", 0, y + 2.2, RH - 1.2, y - 3.6, "Q", 0, y - 0.6, -RH + 1.2, y - 3.6, "Z")
    visor_s = P("M", RH - 2.2, y - 4.8, "L", RH + 8.6, y - 2.6, "Q", RH + 9.2, y - 1.2, RH + 7.6, y - 1, "L", RH - 2, y - 2.4, "Z")
    T["cap"] = {
        "front": path(crown(3.4), WHITE, OUT, 1.9) + path(P("M", 0, y - HR - 3.8, "V", y - 4), None, D, 0.8, 0.18) + circ(0, y - HR - 3.6, 1.0, WHITE, OUT, 0.6)
        + path(visor_f, WHITE, OUT, 1.2) + path(visor_f, D, None, 0, 0.22),
        "back": path(crown(2.6), WHITE, OUT, 1.9) + path(P("M", -4.4, y - 4, "H", 4.4), None, D, 2.4, 0.3) + circ(0, y - HR - 3.6, 1.0, WHITE, OUT, 0.6),
        "side": path(crown(3.0), WHITE, OUT, 1.9) + path(visor_s, WHITE, OUT, 1.2) + path(visor_s, D, None, 0, 0.22),
    }
    # косынка
    T["kerchief"] = {
        "front": path(P("M", -RH - 0.9, y + 0.6, "Q", -RH - 1.6, y - HR - 3, 0, y - HR - 3, "Q", RH + 1.6, y - HR - 3, RH + 0.9, y + 0.6,
                        "Q", RH - 2.6, y - 6, 0, y - 7.2, "Q", -RH + 2.6, y - 6, -RH - 0.9, y + 0.6, "Z"), WHITE, OUT, 1.7)
        + "".join(circ(x, yy, 0.9, "#fff", None, 0, 0.55) for x, yy in [(-7, y - 11), (-1, y - 13.4), (5, y - 11.6), (9, y - 7), (-10, y - 6), (2, y - 9)]),
        "back": path(P("M", -RH - 0.9, y + 3, "Q", -RH - 1.6, y - HR - 3, 0, y - HR - 3, "Q", RH + 1.6, y - HR - 3, RH + 0.9, y + 3,
                       "Q", 8, y + 8, 0, y + 8.4, "Q", -8, y + 8, -RH - 0.9, y + 3, "Z"), WHITE, OUT, 1.7)
        + path(P("M", -2.6, y + 7.6, "L", -6, y + 14, "L", 0, y + 11.6, "L", 6, y + 14, "L", 2.6, y + 7.6, "Z"), WHITE, OUT, 1.1)
        + "".join(circ(x, yy, 0.9, "#fff", None, 0, 0.55) for x, yy in [(-7, y - 8), (0, y - 11), (6, y - 6), (-3, y - 1), (4, y + 3)]),
        "side": path(P("M", -RH * 0.6, y + HR * 0.6, "Q", -RH - 1.4, y + 4, -RH - 1, y - 2, "Q", -RH - 0.8, y - HR - 3, 1, y - HR - 3,
                       "Q", RH + 0.8, y - HR - 2.2, RH + 0.6, y - 4.6, "Q", RH - 3, y - 7, 1.4, y - 5.4, "Q", -1.8, y - 3, -4.4, y + 0.4,
                       "Q", -5.4, y + 6, -RH * 0.6, y + HR * 0.6, "Z"), WHITE, OUT, 1.7)
        + path(P("M", -RH + 1, y + 6, "L", -RH - 3.6, y + 12, "L", -RH + 3, y + 9, "Z"), WHITE, OUT, 1.0),
    }
    # сварочная маска
    shield = P("M", -RH + 0.6, y - HR + 0.4, "Q", 0, y - HR - 4.2, RH - 0.6, y - HR + 0.4, "L", RH - 1, y + HR - 0.6, "Q", 0, y + HR + 3, -RH + 1, y + HR - 0.6, "Z")
    T["weldmask"] = {
        "front": path(shield, WHITE, OUT, 2.0) + rect(-7.4, EY - 2.8, 14.8, 5.6, "#20352b", "#0d1410", 1.0, 1.4) + rect(-5.6, EY - 2, 4.4, 1.6, "#7fd4a8", None, 0, 0, 0.45)
        + path(P("M", -RH + 1, y + 3.6, "Q", 0, y + 5.6, RH - 1, y + 3.6), None, D, 1.0, 0.25),
        "back": path(P("M", -RH - 1, y - 1, "Q", -RH - 1, y - HR - 3.6, 0, y - HR - 3.6, "Q", RH + 1, y - HR - 3.6, RH + 1, y - 1), None, WHITE, 3.4)
        + path(P("M", -RH - 1, y - 1, "Q", -RH - 1, y - HR - 3.6, 0, y - HR - 3.6, "Q", RH + 1, y - HR - 3.6, RH + 1, y - 1), None, D, 3.4, 0.2)
        + path(P("M", -RH + 1, y - HR - 1, "Q", 0, y - HR - 4.6, RH - 1, y - HR - 1), None, WHITE, 2.2),
        "side": path(P("M", RH - 6.4, y - HR - 1.4, "Q", RH + 5, y - 5, RH + 3.4, y + HR - 1.6, "L", RH - 3.6, y + HR - 0.4, "Q", RH - 1.4, y, RH - 6.4, y - HR - 1.4, "Z"), WHITE, OUT, 2.0)
        + rect(RH + 1.4, EY - 2.6, 2.4, 5.2, "#20352b", "#0d1410", 0.8, 0.8)
        + path(P("M", -RH + 1.6, y - HR + 2.4, "Q", 0, y - HR - 2.6, RH - 5.4, y - HR - 0.6), None, WHITE, 3.0)
        + circ(-1.4, y + 1.4, 2.2, WHITE, OUT, 1.0),
    }
    # ушанка
    fur_band_f = P("M", -RH - 3.2, y - 6.6, "Q", 0, y - 12.6, RH + 3.2, y - 6.6, "L", RH + 3.2, y - 1.6, "Q", 0, y - 7.2, -RH - 3.2, y - 1.6, "Z")
    flap_l = P("M", -RH - 3.6, y - 3, "Q", -RH - 4.6, y + 6, -RH - 1.4, y + 10.6, "Q", -RH + 0.8, y + 6, -RH + 0.4, y - 3, "Z")
    flap_r = P("M", RH + 3.6, y - 3, "Q", RH + 4.6, y + 6, RH + 1.4, y + 10.6, "Q", RH - 0.8, y + 6, RH - 0.4, y - 3, "Z")
    tufts = path(P("M", -RH, y - 9, "q", 1.4, -1.6, 2.8, 0, "M", -6, y - 10.6, "q", 1.4, -1.6, 2.8, 0, "M", 2, y - 11, "q", 1.4, -1.6, 2.8, 0, "M", 8, y - 9.6, "q", 1.4, -1.6, 2.8, 0), None, D, 0.8, 0.25)
    T["ushanka"] = {
        "front": path(flap_l, WHITE, OUT, 1.7) + path(flap_r, WHITE, OUT, 1.7) + path(dome(2.4, 4.6), WHITE, OUT, 2.0)
        + path(P("M", 0, y - HR - 6.2, "V", y - 9), None, D, 1.1, 0.25) + path(fur_band_f, WHITE, OUT, 1.7) + tufts,
        "back": path(flap_l, WHITE, OUT, 1.7) + path(flap_r, WHITE, OUT, 1.7) + path(dome(2.6, 1.6), WHITE, OUT, 2.0)
        + path(P("M", -RH - 2.6, y - 2, "Q", 0, y + 3, RH + 2.6, y - 2, "L", RH + 2.4, y + 2, "Q", 0, y + 7, -RH - 2.4, y + 2, "Z"), WHITE, OUT, 1.2) + tufts,
        "side": path(P("M", -3.6, y - 2, "Q", -4.8, y + 6, -1.4, y + 10.8, "Q", 1.2, y + 6, 0.8, y - 2, "Z"), WHITE, OUT, 1.7) + path(dome(2.4, 3.2), WHITE, OUT, 2.0)
        + path(P("M", RH - 3, y - 11.4, "Q", RH + 2.6, y - 9.4, RH + 3, y - 3.6, "L", RH - 0.6, y - 3.2, "Q", RH - 1.6, y - 7.4, RH - 4.4, y - 8.4, "Z"), WHITE, OUT, 1.2) + tufts,
    }
    # фуражка (охрана, инспектор)
    band = rect(-RH - 0.4, y - 7.4, 2 * RH + 0.8, 4.4, WHITE, OUT, 1.3, 1)
    top = P("M", -RH - 3.4, y - 7.2, "Q", -RH - 4, y - HR - 6.4, 0, y - HR - 6.8, "Q", RH + 4, y - HR - 6.4, RH + 3.4, y - 7.2, "Q", 0, y - 9.8, -RH - 3.4, y - 7.2, "Z")
    pvis = P("M", -RH + 2, y - 3.4, "Q", 0, y + 1.6, RH - 2, y - 3.4, "L", RH - 2.4, y - 3, "Q", 0, y - 1.2, -RH + 2.4, y - 3, "Z")
    T["peaked"] = {
        "front": path(top, WHITE, OUT, 1.9) + band + rect(-RH - 0.4, y - 7.4, 2 * RH + 0.8, 4.4, D, None, 0, 1, 0.25)
        + path(pvis, "#1d1f22", OUT, 1.1) + circ(0, y - 8.6, 1.7, "#d9b13b", "#7a5a1c", 0.6),
        "back": path(top, WHITE, OUT, 1.9) + band + rect(-RH - 0.4, y - 7.4, 2 * RH + 0.8, 4.4, D, None, 0, 1, 0.25),
        "side": path(P("M", -RH - 2.4, y - 7, "Q", -RH - 2.6, y - HR - 6, 0, y - HR - 6.4, "Q", RH + 3.4, y - HR - 6, RH + 2.4, y - 7, "Q", 0, y - 9.4, -RH - 2.4, y - 7, "Z"), WHITE, OUT, 1.9)
        + rect(-RH + 0.6, y - 7.4, 2 * RH - 1.2, 4.4, WHITE, OUT, 1.3, 1) + rect(-RH + 0.6, y - 7.4, 2 * RH - 1.2, 4.4, D, None, 0, 1, 0.25)
        + path(P("M", RH - 1.8, y - 3.6, "L", RH + 5.4, y - 1.6, "L", RH + 4.8, y - 0.4, "L", RH - 2, y - 2.2, "Z"), "#1d1f22", OUT, 1.0),
    }
    for t, dd in T.items():
        for d, body in dd.items():
            person_layer(f"hat_{t}_{d}", body)


# ------------------------------------------------------------------ очки, наушники, респиратор

def gear():
    y = HY
    gf = ""
    for sx in (-1, 1):
        gf += circ(sx * EX, EY + 0.2, 3.0, "#cfe3ee", "#2a2e31", 1.0, None, 0.3)
        gf += path(P("M", sx * (EX + 3.0), EY - 0.3, "L", sx * 12.8, EY - 0.8), None, "#2a2e31", 0.9)
    gf += path(P("M", -1.6, EY - 0.2, "Q", 0, EY - 1.2, 1.6, EY - 0.2), None, "#2a2e31", 0.9)
    person_layer("glasses_front", gf)
    person_layer("glasses_side", circ(8.6, EY + 0.2, 2.6, "#cfe3ee", "#2a2e31", 1.0, None, 0.3) + path(P("M", 6, EY - 0.4, "L", -1.2, EY - 0.2), None, "#2a2e31", 1.0))
    band = path(P("M", -RH, y + 1, "Q", -RH - 1.6, y - HR - 4.2, 0, y - HR - 4.2, "Q", RH + 1.6, y - HR - 4.2, RH, y + 1), None, "#1d1d1d", 2.2)
    cups = rect(-RH - 2.8, y - 3, 4.6, 8.6, "#2a2e31", OUT, 1.0, 2.2) + rect(RH - 1.8, y - 3, 4.6, 8.6, "#2a2e31", OUT, 1.0, 2.2)
    person_layer("phones_front", band + cups)
    person_layer("phones_back", band + cups)
    person_layer("phones_side", path(P("M", -3, y - 3, "Q", -3.4, y - HR - 4.2, 2, y - HR - 3.8), None, "#1d1d1d", 2.2) + rect(-4.4, y - 3.2, 6.4, 9.6, "#2a2e31", OUT, 1.0, 3))
    mask = P("M", -5.6, EY + 2.6, "Q", 0, EY + 0.8, 5.6, EY + 2.6, "Q", 6.2, EY + 10.4, 0, EY + 11.2, "Q", -6.2, EY + 10.4, -5.6, EY + 2.6, "Z")
    person_layer("resp_front", path(mask, "#e9ecec", OUT, 1.0) + circ(-5.6, EY + 8, 2.5, "#b0483d", OUT, 0.8) + circ(5.6, EY + 8, 2.5, "#b0483d", OUT, 0.8)
                 + path(P("M", -12.4, EY + 0.6, "L", -5.6, EY + 3.4, "M", 12.4, EY + 0.6, "L", 5.6, EY + 3.4), None, "#3a3f43", 0.9))
    person_layer("resp_side", path(P("M", 6.4, EY + 2, "Q", 12.6, EY + 1, 14.4, EY + 5, "Q", 14.6, EY + 10.4, 9, EY + 11, "Q", 6.2, EY + 8.6, 6.4, EY + 2, "Z"), "#e9ecec", OUT, 1.0)
                 + circ(12.8, EY + 8.4, 2.4, "#b0483d", OUT, 0.8) + path(P("M", 6.4, EY + 3, "L", -1.6, EY + 0.6), None, "#3a3f43", 0.9))
    # старые слои лица больше не нужны
    person_layer("face_front", "")
    person_layer("face_side", "")


def people_v115():
    heads()
    eyes()
    eyes_lod()
    brows()
    noses()
    mouths()
    lines_age()
    hair_styles()
    beards()
    hats()
    gear()


if __name__ == "__main__":
    people_v115()
    print("ok")
