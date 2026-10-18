#!/usr/bin/env python3
"""Генератор SVG-графики «Промзоны».

Масштаб: 64 px на тайл. В Godot спрайты показываются с масштабом 0.5 (тайл = 32 мировые единицы),
поэтому при приближении камеры картинка остаётся чёткой.

Запуск: python3 tools/gen_assets.py  (из корня проекта)
Создаёт assets/**/*.svg и data/sprite_meta.json.
"""
import json
import math
import os
import sys
import random
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = "#23262a"  # цвет обводки
META = {}


def save(rel, w, h, body):
    path = os.path.join(ROOT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    folder = rel.split("/")[1] if rel.count("/") >= 2 else ""
    defs = ""
    if folder in SHADED:
        body, defs = shade(body, people=(folder == "people"))
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{w}" height="{h}" '
           f'viewBox="0 0 {w} {h}">{defs}{body}</svg>')
    with open(path, "w", encoding="utf-8") as f:
        f.write(svg)


# ------------------------------------------------------------------ объём: градиенты, фаски, блики, мягкие тени

SHADED = {"objects", "items", "vehicles", "people", "fx"}
_ATTR = re.compile(r'([a-zA-Z][\w:-]*)="([^"]*)"')
_EL = re.compile(r'<(rect|circle|ellipse|path|polygon)\b([^>]*?)/>')
_SKIP = re.compile(r'(<(clipPath|mask|defs|linearGradient|radialGradient)\b.*?</\2>)', re.S)


def _rgb(c):
    c = c.lstrip("#")
    if len(c) == 3:
        c = "".join(ch * 2 for ch in c)
    return tuple(int(c[i:i + 2], 16) for i in (0, 2, 4))


def _hex(t):
    return "#%02x%02x%02x" % tuple(max(0, min(255, int(round(v)))) for v in t)


def _mix(c, to, k):
    a = _rgb(c)
    b = _rgb(to)
    return _hex(tuple(a[i] + (b[i] - a[i]) * k for i in range(3)))


def _lum(c):
    r, g_, b = _rgb(c)
    return (0.299 * r + 0.587 * g_ + 0.114 * b) / 255.0


def shade(body, people=False):
    """Объём для всей графики: вместо плоской заливки — мягкий градиент (свет сверху-слева),
    у панелей — фаска (блик по верхней кромке, тень по нижней), у круглых деталей — глянцевый блик,
    у теней — размытые края. Внутри clipPath/mask/defs ничего не трогаем."""
    grads = {}
    parts = _SKIP.split(body)
    out = []
    i = 0
    while i < len(parts):
        chunk = parts[i]
        if i + 2 < len(parts) + 1 and i % 3 == 1:
            out.append(chunk)       # пропускаемый блок целиком
            i += 2
            continue
        out.append(_EL.sub(lambda m: _shade_el(m, grads, people), chunk))
        i += 1
    defs = ""
    if grads:
        defs = "<defs>" + "".join(grads.values()) + "</defs>"
    return "".join(out), defs


def _shade_el(m, grads, people):
    tag = m.group(1)
    at = dict(_ATTR.findall(m.group(2)))
    fill = at.get("fill", "")
    whole = m.group(0)
    # мягкая тень: чёрный эллипс или прямоугольник с прозрачностью
    if fill in ("#000", "#000000") and "opacity" in at and tag in ("ellipse", "rect") and "stroke" not in at:
        grads["shd"] = ('<radialGradient id="shd"><stop offset="0" stop-color="#000" stop-opacity="0.9"/>'
                        '<stop offset="0.55" stop-color="#000" stop-opacity="0.6"/><stop offset="1" stop-color="#000" stop-opacity="0"/></radialGradient>')
        op = float(at["opacity"])
        if tag == "ellipse":
            cx, cy, rx, ry = (float(at[k]) for k in ("cx", "cy", "rx", "ry"))
            return f'<ellipse cx="{fmt(cx)}" cy="{fmt(cy)}" rx="{fmt(rx * 1.25)}" ry="{fmt(ry * 1.35)}" fill="url(#shd)" opacity="{fmt(min(1.0, op * 1.25))}"/>'
        x, y, w, h = (float(at[k]) for k in ("x", "y", "width", "height"))
        rx = float(at.get("rx", 0))
        # прямоугольная тень: несколько слоёв — размытые края
        a = 1.0 - (1.0 - min(0.9, op * 1.1)) ** (1.0 / 4.0)
        s = ""
        for gr in (3.5, 2.0, 0.5, -1.0):
            s += f'<rect x="{fmt(x - gr)}" y="{fmt(y - gr)}" width="{fmt(max(1.0, w + 2 * gr))}" height="{fmt(max(1.0, h + 2 * gr))}" rx="{fmt(max(0.0, rx + gr))}" fill="#000" opacity="{fmt(a)}"/>'
        return s
    if not fill.startswith("#") or "opacity" in at or "fill-opacity" in at:
        return whole
    if fill in ("#000", "#000000"):
        return whole
    lum = _lum(fill)
    gid = "s" + fill.lstrip("#")
    if gid not in grads:
        lo = _mix(fill, "#ffffff", 0.22 if lum < 0.85 else 0.0)
        mid = fill
        hi = _mix(fill, "#000000", 0.20 if not people else 0.16)
        grads[gid] = (f'<linearGradient id="{gid}" x1="0" y1="0" x2="0.3" y2="1"><stop offset="0" stop-color="{lo}"/>'
                      f'<stop offset="0.5" stop-color="{mid}"/><stop offset="1" stop-color="{hi}"/></linearGradient>')
    new = whole.replace(f'fill="{fill}"', f'fill="url(#{gid})"', 1)
    extra = ""
    stroked = "stroke" in at and at.get("stroke", "none") != "none"
    if not people and stroked:
        if tag == "rect":
            x, y, w, h = (float(at[k]) for k in ("x", "y", "width", "height"))
            rx = float(at.get("rx", 0))
            sw = float(at.get("stroke-width", 2))
            if w >= 9 and h >= 6:
                ins = sw * 0.5 + 0.9
                x0 = x + max(rx, ins) + 0.5
                x1 = x + w - max(rx, ins) - 0.5
                if x1 > x0:
                    extra += f'<path d="M{fmt(x0)} {fmt(y + ins)}H{fmt(x1)}" stroke="#fff" stroke-opacity="0.38" stroke-width="1.3" stroke-linecap="round" fill="none"/>'
                    extra += f'<path d="M{fmt(x0)} {fmt(y + h - ins)}H{fmt(x1)}" stroke="#000" stroke-opacity="0.22" stroke-width="1.3" stroke-linecap="round" fill="none"/>'
                if h >= 12:
                    extra += f'<path d="M{fmt(x + ins)} {fmt(y + max(rx, ins) + 1)}V{fmt(y + h - max(rx, ins) - 1)}" stroke="#fff" stroke-opacity="0.18" stroke-width="1.1" stroke-linecap="round" fill="none"/>'
        elif tag == "circle":
            r = float(at.get("r", 0))
            if r >= 3.5:
                cx, cy = float(at["cx"]), float(at["cy"])
                extra += f'<ellipse cx="{fmt(cx - r * 0.33)}" cy="{fmt(cy - r * 0.38)}" rx="{fmt(r * 0.36)}" ry="{fmt(r * 0.22)}" fill="#fff" opacity="0.42" transform="rotate(-30 {fmt(cx - r * 0.33)} {fmt(cy - r * 0.38)})"/>'
    return new + extra


# ------------------------------------------------------------------ примитивы

def fmt(v):
    if isinstance(v, float):
        return f"{v:.2f}".rstrip("0").rstrip(".")
    return str(v)


def attrs(fill=None, stroke=None, sw=None, op=None, fop=None, extra=""):
    a = ""
    a += f' fill="{fill}"' if fill is not None else ' fill="none"'
    if stroke:
        a += f' stroke="{stroke}"'
        a += f' stroke-width="{fmt(sw if sw is not None else 2)}"'
        a += ' stroke-linejoin="round" stroke-linecap="round"'
    if op is not None:
        a += f' opacity="{fmt(op)}"'
    if fop is not None:
        a += f' fill-opacity="{fmt(fop)}"'
    return a + extra


def rect(x, y, w, h, fill=None, stroke=OUT, sw=2, rx=0, op=None, fop=None):
    r = f' rx="{fmt(rx)}"' if rx else ""
    return f'<rect x="{fmt(x)}" y="{fmt(y)}" width="{fmt(w)}" height="{fmt(h)}"{r}{attrs(fill, stroke, sw, op, fop)}/>'


def circ(cx, cy, r, fill=None, stroke=OUT, sw=2, op=None, fop=None):
    return f'<circle cx="{fmt(cx)}" cy="{fmt(cy)}" r="{fmt(r)}"{attrs(fill, stroke, sw, op, fop)}/>'


def ell(cx, cy, rx, ry, fill=None, stroke=OUT, sw=2, op=None, fop=None):
    return f'<ellipse cx="{fmt(cx)}" cy="{fmt(cy)}" rx="{fmt(rx)}" ry="{fmt(ry)}"{attrs(fill, stroke, sw, op, fop)}/>'


def path(d, fill=None, stroke=OUT, sw=2, op=None, fop=None, dash=None):
    extra = f' stroke-dasharray="{dash}"' if dash else ""
    return f'<path d="{d}"{attrs(fill, stroke, sw, op, fop, extra)}/>'


def line(x1, y1, x2, y2, stroke=OUT, sw=2, op=None, dash=None):
    return path(f"M{fmt(x1)} {fmt(y1)}L{fmt(x2)} {fmt(y2)}", None, stroke, sw, op, dash=dash)


def poly(pts, fill=None, stroke=OUT, sw=2, op=None):
    d = "M" + "L".join(f"{fmt(x)} {fmt(y)}" for x, y in pts) + "Z"
    return path(d, fill, stroke, sw, op)


def g(content, tr=None, op=None):
    a = f' transform="{tr}"' if tr else ""
    a += f' opacity="{fmt(op)}"' if op is not None else ""
    return f"<g{a}>{content}</g>"



def text_svg(x, y, s, size, fill):
    return (f'<text x="{fmt(x)}" y="{fmt(y)}" font-family="sans-serif" font-size="{size}" font-weight="bold" '
            f'fill="{fill}" text-anchor="middle">{s}</text>')


def shadow(x, y, w, h, rx=4, op=0.28):
    return rect(x, y, w, h, "#000", None, 0, rx, op)


def box(x, y, w, dtop, hfront, top, front, sw=2, hl=True):
    """Коробка в ракурсе 3/4: верхняя грань высотой dtop и передняя грань высотой hfront."""
    s = rect(x, y, w, dtop, top, OUT, sw)
    if hl:
        s += rect(x + 2, y + 2, w - 4, min(4, dtop - 3), "#fff", None, 0, 0, 0.12)
    s += rect(x, y + dtop, w, hfront, front, OUT, sw)
    return s


def bolts(pts, r=2.2, fill="#4a5156"):
    return "".join(circ(x, y, r, fill, None, 0) for x, y in pts)


# ------------------------------------------------------------------ тайлы

def speckle(rng, w, h, n, cols, rmin=0.6, rmax=1.6):
    s = ""
    for _ in range(n):
        s += circ(rng.uniform(0, w), rng.uniform(0, h), rng.uniform(rmin, rmax), rng.choice(cols), None, 0)
    return s


def tiles():
    T = 64
    # верх стены: бетон кладки — мелкая фактура, чтобы стена не была плоским пятном
    rng = random.Random(77)
    s = rect(0, 0, T, T, "#353a40", None, 0)
    s += speckle(rng, T, T, 70, ["#3d4248", "#2f3338", "#40454c", "#30343a"], 0.6, 1.8)
    for k in range(5):
        x0 = rng.uniform(4, 56)
        y0 = rng.uniform(4, 56)
        s += path(f"M{x0:.1f} {y0:.1f}l{rng.uniform(3, 8):.1f} {rng.uniform(-2, 2):.1f}", None, "#2a2e33", 0.8, 0.6)
    save("assets/tiles/wall_top.svg", T, T, s)
    # грунт: гравий/земля
    for v in range(4):
        rng = random.Random(100 + v)
        s = rect(0, 0, T, T, "#a09a86", None, 0)
        s += speckle(rng, T, T, 46, ["#8f8975", "#b3ad99", "#96907c", "#aaa48f"], 0.8, 2.2)
        if v == 1:
            s += path("M8 50l10 -4 6 3 9 -6", None, "#857f6c", 1.2)
        if v == 2:
            s += ell(40, 22, 9, 5, "#8c8672", None, 0, 0.6)
        save(f"assets/tiles/dirt_{v}.svg", T, T, s)
    # трава
    for v in range(4):
        rng = random.Random(200 + v)
        s = rect(0, 0, T, T, "#7d8f5c", None, 0)
        s += speckle(rng, T, T, 18, ["#6f8150", "#8a9c66"], 1.5, 3.5)
        for _ in range(26):
            x, y = rng.uniform(2, T - 2), rng.uniform(4, T - 2)
            c = rng.choice(["#62744a", "#93a56c", "#6b7d4f"])
            s += path(f"M{fmt(x)} {fmt(y)}l{fmt(rng.uniform(-2, 2))} -{fmt(rng.uniform(3, 6))}", None, c, 1.2)
        save(f"assets/tiles/grass_{v}.svg", T, T, s)
    # асфальт
    for v in range(2):
        rng = random.Random(300 + v)
        s = rect(0, 0, T, T, "#55585c", None, 0)
        s += speckle(rng, T, T, 60, ["#4c4f53", "#5f6266", "#505357"], 0.5, 1.3)
        if v == 1:
            s += path("M10 12l8 6 4 10 10 4", None, "#45484c", 1.4)
        save(f"assets/tiles/asphalt_{v}.svg", T, T, s)
    # дорога
    for v in range(2):
        rng = random.Random(400 + v)
        s = rect(0, 0, T, T, "#4a4d51", None, 0)
        s += speckle(rng, T, T, 60, ["#414448", "#55585c"], 0.5, 1.3)
        save(f"assets/tiles/road_{v}.svg", T, T, s)
    # тротуар (плитка) с бордюром снизу
    rng = random.Random(500)
    s = rect(0, 0, T, T, "#a9aaa4", None, 0)
    s += line(0, 32, T, 32, "#95968f", 1.2) + line(32, 0, 32, T, "#95968f", 1.2)
    s += line(0, 0.6, T, 0.6, "#95968f", 1.2) + line(0.6, 0, 0.6, T, "#95968f", 1.2)
    s += speckle(rng, T, T, 20, ["#9d9e98", "#b4b5af"], 0.5, 1.2)
    s += rect(0, 56, T, 8, "#8a8b85", None, 0) + line(0, 56, T, 56, "#6f706a", 1.5)
    save("assets/tiles/sidewalk.svg", T, T, s)
    # бетонный пол
    for v in range(4):
        rng = random.Random(600 + v)
        s = rect(0, 0, T, T, "#b8b9b3", None, 0)
        s += speckle(rng, T, T, 16, ["#afb0aa", "#c0c1bb", "#b1b2ac"], 0.6, 1.5)
        s += line(0, 0.5, T, 0.5, "#a7a8a2", 1.2) + line(0.5, 0, 0.5, T, "#a7a8a2", 1.2)
        if v == 1:
            s += path("M14 40l7 3 5 -2", None, "#a9aaa4", 1.1)
        if v == 2:
            s += ell(42, 44, 8, 4, "#4a3a2a", None, 0, 0.12)
        save(f"assets/tiles/concrete_{v}.svg", T, T, s)
    # кафель
    s = rect(0, 0, T, T, "#d6dad7", None, 0)
    for k in range(0, T + 1, 16):
        s += line(k, 0, k, T, "#bfc4c1", 1.2) + line(0, k, T, k, "#bfc4c1", 1.2)
    s += rect(2, 2, 12, 3, "#fff", None, 0, 0, 0.35)
    save("assets/tiles/tile.svg", T, T, s)
    # линолеум
    s = rect(0, 0, T, T, "#b7ad8c", None, 0)
    for k in range(0, T, 8):
        s += line(0, k, T, k, "#ada382", 0.8)
    s += line(0, 0.5, T, 0.5, "#a59b7b", 1)
    save("assets/tiles/lino.svg", T, T, s)

    # стены: верх (шапка) и лицевая грань (кирпич)
    s = rect(0, 0, T, T, "#2e3136", None, 0)
    s += rect(0, 0, T, T, "#3a3e44", None, 0, 0, 0.0)
    save("assets/tiles/wall_top.svg", T, T, s)
    s = rect(0, 0, T, T, "#2e3136", None, 0)
    s += rect(0, 24, T, 16, "#8fb3c8", None, 0, 0, 0.9)
    s += line(0, 32, T, 32, "#c9dde8", 1.2, 0.8) + line(0, 24, T, 24, "#23262a", 1.5) + line(0, 40, T, 40, "#23262a", 1.5)
    save("assets/tiles/wall_top_window_h.svg", T, T, s)
    s = rect(0, 0, T, T, "#2e3136", None, 0)
    s += rect(24, 0, 16, T, "#8fb3c8", None, 0, 0, 0.9)
    s += line(32, 0, 32, T, "#c9dde8", 1.2, 0.8) + line(24, 0, 24, T, "#23262a", 1.5) + line(40, 0, 40, T, "#23262a", 1.5)
    save("assets/tiles/wall_top_window_v.svg", T, T, s)

    FH = 30  # высота лицевой грани
    def bricks(w, h, seed):
        rng = random.Random(seed)
        s = rect(0, 0, w, h, "#6e5a4c", None, 0)
        row = 0
        for y in range(0, h, 8):
            off = 0 if row % 2 == 0 else 10
            s += line(0, y + 0.5, w, y + 0.5, "#56463a", 1.2)
            for x in range(-off, w, 20):
                s += line(x + 0.5, y, x + 0.5, y + 8, "#56463a", 1.2)
                if rng.random() < 0.25:
                    s += rect(x + 2, y + 2, 15, 4, rng.choice(["#7a6555", "#634f42"]), None, 0, 0, 0.6)
            row += 1
        return s
    # лицевая грань стены внутри клетки: 24 px текстуры = 12 мировых единиц (см. WallPiece.FACE)
    FH24 = 24
    s = bricks(T, FH24, 1) + rect(0, FH24 - 2, T, 2, "#000", None, 0, 0, 0.25)
    save("assets/tiles/wall_face.svg", T, FH24, s)
    # иконки для меню стройки: кусок стены в том же виде, что и в игре
    def framed(body_cap, body_face):
        out = rect(0, 10, 64, 30, "#33373d", None, 0) + line(0, 11, 64, 11, "#50565e", 2) + body_cap
        out += g(bricks(64, 24, 7) + line(0, 0.5, 64, 0.5, "#1d2023", 1.5) + body_face, "translate(0 40)")
        out += rect(0, 64 - 2, 64, 2, "#000", None, 0, 0, 0.2)
        return out
    save("assets/tiles/icon_wall.svg", 64, 64, framed("", ""))
    win_cap = rect(0, 18, 64, 14, "#b9bbb5", None, 0) + rect(2, 20, 60, 10, "#dcdfd9", None, 0) + rect(5, 22, 54, 6, "#8fbcd6", None, 0)
    win_cap += line(5, 25, 59, 25, "#d8ecf5", 1.4) + line(32, 20, 32, 30, "#dcdfd9", 2.5)
    win_face = rect(10, 4, 44, 14, "#dcdfd9", None, 0) + rect(13, 7, 38, 9, "#8fbcd6", None, 0) + line(32, 4, 32, 18, "#dcdfd9", 2)
    win_face += path("M16 16l6 -9h5l-6 9z", "#fff", None, 0, 0.35) + rect(8, 18, 48, 3, "#a7a9a3", None, 0)
    save("assets/tiles/icon_window.svg", 64, 64, framed(win_cap, win_face))
    door = rect(0, 10, 8, 30, "#33373d", None, 0) + rect(56, 10, 8, 30, "#33373d", None, 0)
    door += g(bricks(8, 24, 3), "translate(0 40)") + g(bricks(8, 24, 4), "translate(56 40)")
    door += rect(8, 30, 48, 8, "#7d7e78", None, 0)
    door += path("M8 34A40 40 0 0 1 48 34", None, "#ffffff", 1.2, 0.25)
    door += g(rect(0, -5, 48, 10, "#8a6646", "#5e432c", 2) + circ(42, 0, 2.4, "#d6d9dc", None, 0), "translate(8 34) rotate(55)")
    save("assets/tiles/icon_door.svg", 64, 64, door)
    gate = rect(0, 10, 8, 30, "#33373d", None, 0) + rect(56, 10, 8, 30, "#33373d", None, 0)
    gate += g(bricks(8, 24, 3), "translate(0 40)") + g(bricks(8, 24, 4), "translate(56 40)")
    gate += rect(0, 16, 64, 14, "#8b9296", "#5c6368", 2) + line(0, 21, 64, 21, "#ffffff", 1.6, 0.3)
    hz = rect(8, 54, 48, 8, "#d9b13b", None, 0)
    for k in range(8, 56, 12):
        hz += poly([(k, 62), (k + 4, 54), (k + 10, 54), (k + 6, 62)], "#2a2c2e", None, 0)
    gate += hz
    save("assets/tiles/icon_gate.svg", 64, 64, gate)
    # иконки зоны разгрузки
    z = rect(4, 4, 56, 56, "#d9b13b", None, 0, 2, 0.18) + rect(4, 4, 56, 56, None, "#d9b13b", 3, 2)
    for k in range(-56, 56, 12):
        z += line(4 + max(0, k), 60 - max(0, -k), 60 - max(0, -k) if k < 0 else 60, 4 + max(0, k) if k < 0 else 4 + k, "#d9b13b", 2, 0.5)
    z += rect(18, 22, 28, 22, "#b48a58", OUT, 2) + line(18, 30, 46, 30, "#8a6640", 1.5) + line(32, 22, 32, 44, "#8a6640", 1.5)
    save("assets/tiles/icon_zone.svg", 64, 64, z)
    z2 = rect(4, 4, 56, 56, None, "#d9b13b", 3, 2, 0.6) + line(14, 14, 50, 50, "#d8644e", 5) + line(50, 14, 14, 50, "#d8644e", 5)
    save("assets/tiles/icon_zone_off.svg", 64, 64, z2)
    # трубы водопровода
    pp = path("M8 44H30V20H56", None, "#2e5a88", 12) + path("M8 44H30V20H56", None, "#4a8fd0", 8) + path("M8 42H28V18H56", None, "#9cc8f0", 2, 0.7)
    pp += rect(24, 38, 12, 12, "#2e5a88", OUT, 1.5, 2) + rect(24, 14, 12, 12, "#2e5a88", OUT, 1.5, 2)
    save("assets/tiles/icon_pipe.svg", 64, 64, pp)
    pu = path("M8 44H30V20H56", None, "#4a8fd0", 8, 0.5) + line(14, 14, 50, 50, "#d8644e", 5) + line(50, 14, 14, 50, "#d8644e", 5)
    save("assets/tiles/icon_unpipe.svg", 64, 64, pu)
    s = bricks(T, FH, 2)
    s += rect(8, 4, 48, 20, "#2b2e33", None, 0) + rect(11, 7, 42, 14, "#8fb3c8", None, 0)
    s += line(25, 7, 25, 21, "#2b2e33", 1.5) + line(39, 7, 39, 21, "#2b2e33", 1.5) + line(11, 14, 53, 14, "#2b2e33", 1.5)
    s += path("M14 19l6 -10M28 19l4 -7", None, "#fff", 1.4, 0.45)
    s += rect(6, 23, 52, 3, "#8f8d86", None, 0)
    s += rect(0, 0, T, 2, "#2e3136", None, 0) + rect(0, FH - 3, T, 3, "#000", None, 0, 0, 0.25)
    save("assets/tiles/wall_face_window.svg", T, FH, s)
    # дверной проём в лицевой грани: открыт / закрыт
    def door_face(closed):
        s = bricks(T, FH, 3)
        s += rect(10, 0, 44, FH, "#1e2023", None, 0)
        if closed:
            s += rect(12, 1, 40, FH - 1, "#7a5a3a", OUT, 1.5) + rect(14, 4, 36, 10, "#8a6a48", None, 0)
            s += circ(46, 18, 2, "#c9ccce", None, 0)
        s += rect(8, 0, 3, FH, "#3a3e44", None, 0) + rect(53, 0, 3, FH, "#3a3e44", None, 0)
        s += rect(0, FH - 3, T, 3, "#000", None, 0, 0, 0.25)
        return s
    save("assets/tiles/door_face_closed.svg", T, FH, door_face(True))
    save("assets/tiles/door_face_open.svg", T, FH, door_face(False))
    # ворота: рулон сверху, проём
    s = rect(0, 0, T, FH, "#1e2023", None, 0)
    s += rect(0, 0, T, 9, "#8b9296", OUT, 1.5) + line(0, 4.5, T, 4.5, "#6d7478", 1.2)
    s += rect(0, FH - 3, T, 3, "#000", None, 0, 0, 0.25)
    save("assets/tiles/gate_face.svg", T, FH, s)
    # порог двери/ворот (вид сверху, рисуется на уровне пола)
    s = rect(0, 22, T, 20, "#7d7e78", None, 0) + line(0, 22, T, 22, "#5d5e58", 1.5) + line(0, 42, T, 42, "#5d5e58", 1.5)
    s += rect(0, 18, 8, 28, "#2e3136", None, 0) + rect(56, 18, 8, 28, "#2e3136", None, 0)
    save("assets/tiles/door_sill_h.svg", T, T, s)
    s = rect(22, 0, 20, T, "#7d7e78", None, 0) + line(22, 0, 22, T, "#5d5e58", 1.5) + line(42, 0, 42, T, "#5d5e58", 1.5)
    s += rect(18, 0, 28, 8, "#2e3136", None, 0) + rect(18, 56, 28, 8, "#2e3136", None, 0)
    save("assets/tiles/door_sill_v.svg", T, T, s)
    s = rect(0, 26, T, 12, "#6d7478", None, 0) + line(0, 26, T, 26, "#4d5458", 1.5) + line(0, 38, T, 38, "#4d5458", 1.5)
    save("assets/tiles/gate_sill.svg", T, T, s)
    # дверное полотно (вид сверху, закрыто)
    s = rect(8, 28, 48, 8, "#7a5a3a", OUT, 1.5)
    save("assets/tiles/door_leaf_h.svg", T, T, s)
    s = rect(28, 8, 8, 48, "#7a5a3a", OUT, 1.5)
    save("assets/tiles/door_leaf_v.svg", T, T, s)

    # забор-рабица: горизонтальный (лицо вверх на 40 px) и вертикальный
    FH2 = 44
    s = ""
    s += rect(0, FH2 - 46 + 8, T, 34, "#8a9196", None, 0, 0, 0.08)
    for k in range(-40, T, 7):
        s += line(k, 6, k + 34, 40, "#8a9196", 1, 0.85) + line(k + 34, 6, k, 40, "#8a9196", 1, 0.85)
    s = g(s)
    s += line(0, 6, T, 6, "#6a7176", 2) + line(0, 40, T, 40, "#6a7176", 2)
    s += rect(0, 2, 5, 42, "#5c6368", OUT, 1.2)
    s += ell(32, 43, 30, 2.5, "#000", None, 0, 0.18)
    save("assets/tiles/fence_h.svg", T, FH2, s)
    s = rect(28, 0, 8, T, "#8a9196", None, 0, 0, 0.35)
    for k in range(0, T, 8):
        s += line(28, k, 36, k + 8, "#8a9196", 1, 0.9) + line(36, k, 28, k + 8, "#8a9196", 1, 0.9)
    s += line(28, 0, 28, T, "#6a7176", 1.5) + line(36, 0, 36, T, "#6a7176", 1.5)
    s += rect(27, 0, 10, 8, "#5c6368", OUT, 1.2)
    save("assets/tiles/fence_v.svg", T, T, s)
    s = rect(0, 0, 8, 46, "#5c6368", OUT, 1.5) + rect(56, 0, 8, 46, "#5c6368", OUT, 1.5)
    s += rect(-2, -2, 12, 6, "#d9b13b", OUT, 1)
    save("assets/tiles/fence_post.svg", T, 48, s)


# ------------------------------------------------------------------ объекты

def obj(key, wt, ht, top, body, pad=16):
    """Сохраняет объект: футпринт wt×ht тайлов, top px сверху на высоту, тень справа/снизу."""
    W = wt * 64 + pad
    H = top + ht * 64 + pad
    save(f"assets/objects/{key}.svg", W, H, body)
    META[key] = {"file": f"res://assets/objects/{key}.svg", "w": W, "h": H, "ox": 0, "oy": top + ht * 64}


def objects():
    GREEN_T, GREEN_F = "#7d9283", "#5e7364"
    # --- токарный станок 3×1
    T0 = 44
    b = shadow(12, T0 - 8, 186, 82)
    b += rect(4, T0 + 40, 44, 22, "#4e5f54", OUT, 2) + rect(146, T0 + 40, 44, 22, "#4e5f54", OUT, 2)
    b += rect(8, T0 + 44, 36, 14, None, "#3d4b42", 1.5) + rect(150, T0 + 44, 36, 14, None, "#3d4b42", 1.5)
    b += rect(48, T0 + 42, 98, 18, "#33383c", OUT, 2)
    b += path(f"M56 {T0+52}q4 -5 8 0t8 0M86 {T0+56}q3 -4 6 0t6 0t5 -1M112 {T0+50}q4 -4 8 0t7 1", None, "#b9c2c8", 1.5)
    b += path(f"M70 {T0+56}q3 -4 6 0M126 {T0+55}q3 -4 6 0t5 0", None, "#c7a46a", 1.5)
    b += rect(4, T0 + 10, 186, 18, "#8b9296", OUT, 2)
    b += line(4, T0 + 15, 190, T0 + 15, "#b2b9bd", 1.6) + line(4, T0 + 23, 190, T0 + 23, "#b2b9bd", 1.6)
    b += rect(4, T0 + 28, 186, 14, "#5c6267", OUT, 2) + line(60, T0 + 35, 188, T0 + 35, "#9aa1a5", 2)
    b += line(60, T0 + 33, 188, T0 + 33, "#d0d5d8", 0.8, dash="2 2")
    b += box(4, T0 - 18, 52, 22, 34, GREEN_T, GREEN_F)
    b += circ(16, T0 + 14, 5, "#c9ccce", OUT, 1.2) + circ(30, T0 + 14, 5, "#c9ccce", OUT, 1.2)
    b += line(16, T0 + 14, 19, T0 + 11, OUT, 1.2) + line(30, T0 + 14, 27, T0 + 11, OUT, 1.2)
    b += line(42, T0 + 12, 50, T0 + 4, "#2a2e31", 2.2) + line(46, T0 + 22, 53, T0 + 15, "#2a2e31", 2.2)
    b += circ(50, T0 + 4, 2.6, "#b0483d", None, 0) + circ(53, T0 + 15, 2.6, "#1d1d1d", None, 0)
    b += rect(10, T0 + 26, 22, 6, "#c9b37a", None, 0)
    b += rect(12, T0 - 14, 22, 12, "#3a3f43", OUT, 1.2) + circ(18, T0 - 8, 2.8, "#c94a3a", None, 0)
    b += path(f"M50 {T0-12}L66 {T0-26}L80 {T0-20}", None, "#2a2e31", 2.2)
    b += poly([(76, T0 - 24), (90, T0 - 19), (84, T0 - 10)], "#3a3f43", OUT, 1.2)
    b += path(f"M38 {T0-14}Q62 {T0-36} 96 {T0-6}Q104 {T0} 104 {T0+8}", None, "#3f6f9a", 2.6, dash="3 1.4")
    b += rect(56, T0 + 4, 13, 26, "#9ca3a7", OUT, 2, 2)
    b += rect(69, T0 + 12, 40, 10, "#cdd3d7", OUT, 1.5) + rect(109, T0 + 14, 30, 6, "#cdd3d7", OUT, 1.2)
    b += line(69, T0 + 14, 109, T0 + 14, "#fff", 1.2, 0.7)
    b += box(100, T0 + 2, 34, 18, 16, "#6f8275", "#55665a")
    b += rect(108, T0 + 3, 14, 9, "#3a3f43", OUT, 1.2) + line(108, T0 + 8, 103, T0 + 9, "#e8e0c0", 2.6)
    b += circ(117, T0 + 28, 6, None, "#c9ccce", 2) + line(117, T0 + 22, 117, T0 + 34, "#c9ccce", 1.2) + line(111, T0 + 28, 123, T0 + 28, "#c9ccce", 1.2)
    b += box(146, T0 - 2, 38, 16, 18, GREEN_T, GREEN_F)
    b += rect(130, T0 + 12, 16, 7, "#aab1b5", OUT, 1.2) + poly([(130, T0 + 13), (124, T0 + 15.5), (130, T0 + 18)], "#cdd3d7", None, 0)
    b += circ(188, T0 + 18, 6, None, "#c9ccce", 2)
    obj("lathe", 3, 1, T0, b)
    META["lathe"]["anchors"] = {"chuck": [56, T0 + 4, 13, 26], "tool": [104, T0 + 16], "lamp": [33, T0 - 8],
                                "bar": [100, T0 + 60], "out": [150, T0 + 40], "light": [84, T0 - 4]}

    # --- слесарный верстак 2×1
    T0 = 30
    b = shadow(12, T0 + 4, 120, 64)
    b += box(2, T0 + 4, 124, 26, 30, "#a8845a", "#6b5236")
    for x in (20, 46, 74, 100):
        b += line(x, T0 + 5, x, T0 + 29, "#8f6f48", 1.2)
    b += line(44, T0 + 30, 44, T0 + 60, "#523e28", 1.5) + line(84, T0 + 30, 84, T0 + 60, "#523e28", 1.5) + line(44, T0 + 45, 84, T0 + 45, "#523e28", 1.5)
    b += rect(58, T0 + 37, 12, 3, "#c9ccce", None, 0) + rect(58, T0 + 51, 12, 3, "#c9ccce", None, 0) + rect(18, T0 + 43, 12, 3, "#c9ccce", None, 0) + rect(98, T0 + 43, 12, 3, "#c9ccce", None, 0)
    b += rect(10, T0 - 2, 26, 16, "#3d5a7a", OUT, 1.5) + rect(6, T0 + 2, 34, 5, "#8b9296", OUT, 1.2) + line(23, T0 + 14, 23, T0 + 24, "#2a2e31", 2.2)
    b += rect(96, T0 - 6, 18, 14, "#5e7364", OUT, 1.5, 4) + rect(88, T0 - 7, 8, 18, "#8a8a84", OUT, 1.2, 2) + rect(114, T0 - 7, 8, 18, "#8a8a84", OUT, 1.2, 2)
    b += rect(92, T0 + 10, 26, 4, "#3a3f43", None, 0)
    b += line(50, T0 + 12, 68, T0 + 18, "#7a5c38", 3) + rect(46, T0 + 9, 7, 7, "#5c6267", OUT, 1)
    b += line(70, T0 + 22, 86, T0 + 16, "#9aa1a5", 3) + circ(87, T0 + 15.5, 3, None, "#9aa1a5", 2)
    b += rect(40, T0 + 18, 12, 6, "#cdd3d7", OUT, 1)
    obj("workbench", 2, 1, T0, b)

    # --- стеллаж для металла 2×1 (две полки)
    T0 = 44
    b = shadow(12, T0 - 14, 120, 78)
    b += rect(2, T0 - 22, 124, 14, "#6a8aaa", OUT, 2) + rect(4, T0 - 20, 120, 3, "#fff", None, 0, 0, 0.15)
    b += rect(2, T0 - 8, 124, 70, "#2f3a46", OUT, 2)
    b += rect(2, T0 - 8, 7, 70, "#4d6d8d", OUT, 1.2) + rect(60.5, T0 - 8, 7, 70, "#4d6d8d", OUT, 1.2) + rect(119, T0 - 8, 7, 70, "#4d6d8d", OUT, 1.2)
    b += rect(2, T0 + 20, 124, 5, "#d97a2c", OUT, 1.2) + rect(2, T0 + 57, 124, 5, "#d97a2c", OUT, 1.2)
    obj("rack", 2, 1, T0, b)
    META["rack"]["slots"] = [[11, T0 - 6, 106, 26], [11, T0 + 26, 106, 31]]

    # --- поддон 1×1
    T0 = 10
    b = shadow(10, T0 + 12, 56, 50)
    b += rect(4, T0 + 6, 56, 42, "#b48a58", OUT, 2)
    for y in (T0 + 14, T0 + 24, T0 + 34):
        b += line(4, y, 60, y, "#8a6640", 1.5)
    b += rect(4, T0 + 48, 56, 10, "#8a6640", OUT, 2)
    b += rect(8, T0 + 48, 8, 10, "#5a4024", None, 0) + rect(28, T0 + 48, 8, 10, "#5a4024", None, 0) + rect(48, T0 + 48, 8, 10, "#5a4024", None, 0)
    obj("pallet", 1, 1, T0, b)
    META["pallet"]["slots"] = [[6, T0 + 4, 52, 42]]

    # --- тара для брака 1×1
    T0 = 24
    b = shadow(14, T0, 52, 60)
    b += rect(6, T0 - 4, 52, 20, "#3a2a28", OUT, 2) + rect(6, T0 - 4, 52, 5, "#8a2e2a", None, 0)
    b += rect(6, T0 + 16, 52, 42, "#b0483d", OUT, 2) + rect(14, T0 + 26, 36, 14, "#ece8dc", None, 0)
    b += line(18, T0 + 30, 46, T0 + 30, "#b0483d", 2) + line(18, T0 + 36, 40, T0 + 36, "#b0483d", 2)
    b += rect(6, T0 + 52, 52, 6, "#7a2e26", None, 0)
    obj("scrap_bin", 1, 1, T0, b)
    META["scrap_bin"]["slots"] = [[10, T0 - 2, 44, 16]]

    # --- стол ОТК 2×1 (поверочная плита)
    T0 = 30
    b = shadow(12, T0 + 6, 120, 60)
    b += rect(10, T0 + 40, 7, 22, "#5c6267", OUT, 1.5) + rect(111, T0 + 40, 7, 22, "#5c6267", OUT, 1.5)
    b += rect(4, T0 + 2, 120, 26, "#4a4e52", OUT, 2)
    rng = random.Random(7)
    b += g(speckle(rng, 116, 22, 60, ["#5a5f63", "#3c4044", "#62676b"], 0.5, 1.1), f"translate(6 {T0 + 4})")
    b += rect(4, T0 + 28, 120, 12, "#2f3337", OUT, 2)
    b += rect(96, T0 + 4, 12, 12, "#8b9296", OUT, 1.2) + rect(100, T0 - 20, 4, 26, "#c9ccce", OUT, 1) + rect(94, T0 - 14, 16, 5, "#d9b13b", OUT, 1)
    b += path(f"M70 {T0+18}H96M80 {T0+14}V{T0+22}", None, "#c9ccce", 2.2)
    b += rect(60, T0 + 6, 24, 9, "#ece8dc", OUT, 1) + line(63, T0 + 9, 80, T0 + 9, "#8a8a84", 1) + line(63, T0 + 12, 76, T0 + 12, "#8a8a84", 1)
    b += circ(112, T0 + 22, 4, "#3d5a7a", OUT, 1)
    obj("qc_table", 2, 1, T0, b)
    META["qc_table"]["slots"] = [[8, T0 + 4, 48, 22]]

    # --- туалетная кабинка 1×1
    T0 = 56
    b = shadow(14, T0 - 44, 52, 104)
    b += rect(4, T0 - 50, 56, 50, "#d6dad7", OUT, 2)
    for k in range(0, 56, 14):
        b += line(4 + k, T0 - 50, 4 + k, T0, "#c3c7c4", 1)
    b += rect(22, T0 - 46, 20, 9, "#ecefef", OUT, 1.5, 2)
    b += ell(32, T0 - 26, 11, 13, "#ecefef", OUT, 1.8) + ell(32, T0 - 25, 6.5, 8.5, "#bcd0da", OUT, 1)
    b += rect(2, T0 - 52, 4, 54, "#7f949e", OUT, 1.2) + rect(58, T0 - 52, 4, 54, "#7f949e", OUT, 1.2)
    b += rect(2, T0, 60, 58, "#9aaab5", OUT, 2) + rect(8, T0 + 4, 48, 50, "#8a9ba6", OUT, 1.2)
    b += rect(26, T0 + 8, 12, 9, "#ece8dc", OUT, 1) + circ(32, T0 + 12.5, 2.5, "#3d5a7a", None, 0)
    b += rect(48, T0 + 28, 4, 9, "#c9ccce", OUT, 0.8)
    obj("toilet", 1, 1, T0, b)
    META["toilet"]["anchors"] = {"busy": [44, T0 + 12]}

    # --- обеденный стол 2×1
    T0 = 26
    b = shadow(12, T0 + 4, 120, 60)
    b += rect(10, T0 + 42, 7, 20, "#6b5236", OUT, 1.5) + rect(111, T0 + 42, 7, 20, "#6b5236", OUT, 1.5)
    b += rect(4, T0 + 2, 120, 32, "#b88d5c", OUT, 2) + line(4, T0 + 18, 124, T0 + 18, "#a07a4c", 1.2)
    b += rect(6, T0 + 4, 116, 4, "#fff", None, 0, 0, 0.12)
    b += rect(4, T0 + 34, 120, 8, "#8a6640", OUT, 2)
    b += ell(30, T0 + 12, 8, 4.5, "#ece8dc", OUT, 1.2) + ell(30, T0 + 12, 4, 2.2, "#c9692e", None, 0)
    b += ell(92, T0 + 24, 8, 4.5, "#ece8dc", OUT, 1.2)
    b += rect(56, T0 + 8, 9, 10, "#ece8dc", OUT, 1.2, 2) + rect(70, T0 + 18, 9, 10, "#4d7fb0", OUT, 1.2, 2)
    b += rect(100, T0 + 6, 16, 10, "#ece8dc", OUT, 1) + line(102, T0 + 9, 114, T0 + 9, "#8a8a84", 0.8)
    obj("dining_table", 2, 1, T0, b)

    # --- стул: три варианта ориентации
    def chair(back):
        T0 = 20
        b = shadow(16, T0 + 14, 36, 44)
        if back == "top":   # спинка сверху — сидят лицом вниз
            b += rect(16, T0 + 50, 4, 10, "#3a3e42", None, 0) + rect(44, T0 + 50, 4, 10, "#3a3e42", None, 0)
            b += rect(14, T0 + 24, 36, 26, "#8a6640", OUT, 2) + rect(16, T0 + 26, 32, 4, "#fff", None, 0, 0, 0.15)
            b += rect(14, T0 + 4, 36, 12, "#7a5a36", OUT, 2) + rect(16, T0 + 16, 4, 10, "#3a3e42", None, 0) + rect(44, T0 + 16, 4, 10, "#3a3e42", None, 0)
        elif back == "bottom":  # спинка снизу — сидят спиной к зрителю
            b += rect(14, T0 + 14, 36, 26, "#8a6640", OUT, 2) + rect(16, T0 + 16, 32, 4, "#fff", None, 0, 0, 0.15)
            b += rect(16, T0 + 40, 4, 8, "#3a3e42", None, 0) + rect(44, T0 + 40, 4, 8, "#3a3e42", None, 0)
            b += rect(14, T0 + 44, 36, 14, "#7a5a36", OUT, 2)
        else:  # спинка слева — сидят лицом вправо
            b += rect(18, T0 + 18, 32, 30, "#8a6640", OUT, 2)
            b += rect(10, T0 + 8, 10, 44, "#7a5a36", OUT, 2)
            b += rect(20, T0 + 48, 4, 10, "#3a3e42", None, 0) + rect(44, T0 + 48, 4, 10, "#3a3e42", None, 0)
        return b
    obj("chair_down", 1, 1, 20, chair("top"))
    obj("chair_up", 1, 1, 20, chair("bottom"))
    obj("chair_side", 1, 1, 20, chair("side"))
    META["chair"] = dict(META["chair_down"])

    # --- скамейка 2×1
    T0 = 22
    b = shadow(12, T0 + 6, 120, 52)
    b += rect(12, T0 + 46, 6, 16, "#3a3e42", OUT, 1) + rect(110, T0 + 46, 6, 16, "#3a3e42", OUT, 1)
    for k, y in enumerate((T0 + 22, T0 + 31, T0 + 40)):
        b += rect(4, y, 120, 8, "#a07a4c" if k % 2 == 0 else "#946f43", OUT, 1.5)
    for k, y in enumerate((T0 - 2, T0 + 7)):
        b += rect(4, y, 120, 8, "#a07a4c" if k % 2 == 0 else "#946f43", OUT, 1.5)
    b += rect(12, T0 - 4, 6, 26, "#3a3e42", OUT, 1) + rect(110, T0 - 4, 6, 26, "#3a3e42", OUT, 1)
    obj("bench", 2, 1, T0, b)

    # --- тумба с чайником
    T0 = 30
    b = shadow(14, T0 + 4, 52, 60)
    b += box(6, T0 + 2, 52, 18, 38, "#a8845a", "#6b5236")
    b += rect(12, T0 + 24, 40, 30, None, "#523e28", 1.5) + circ(46, T0 + 39, 2, "#c9ccce", None, 0)
    b += rect(16, T0 - 14, 18, 22, "#d0d5d8", OUT, 1.5, 5) + rect(14, T0 - 18, 22, 6, "#3a3f43", OUT, 1.2, 3)
    b += path(f"M34 {T0-8}q8 0 8 8", None, OUT, 2.2) + rect(19, T0 - 8, 4, 8, "#4d7fb0", None, 0)
    b += rect(40, T0 + 2, 10, 10, "#b0483d", OUT, 1.2, 2)
    obj("kettle", 1, 1, T0, b)

    # --- урна-курилка
    T0 = 22
    b = ell(36, T0 + 52, 18, 6, "#000", None, 0, 0.25)
    b += rect(18, T0 + 12, 28, 38, "#8b8d88", OUT, 2) + ell(32, T0 + 12, 14, 5, "#5a5c58", OUT, 2)
    b += ell(32, T0 + 12, 10, 3.2, "#2e3032", None, 0)
    b += rect(18, T0 + 44, 28, 6, "#6a6c68", None, 0) + line(24, T0 + 18, 24, T0 + 44, "#fff", 2, 0.2)
    b += line(28, T0 + 11, 31, T0 + 10, "#ece8dc", 1.6) + line(34, T0 + 13, 37, T0 + 12, "#ece8dc", 1.6)
    obj("urn", 1, 1, T0, b)
    META["urn"]["anchors"] = {"smoke": [32, T0 + 8]}

    # --- фикус
    T0 = 40
    b = ell(36, T0 + 56, 16, 5, "#000", None, 0, 0.28)
    b += path(f"M18 {T0+26}H46L42 {T0+54}H22Z", "#8a5a3a", OUT, 2) + rect(16, T0 + 22, 32, 7, "#9a6a46", OUT, 2)
    for (cx, cy, r, c) in [(24, T0 + 4, 11, "#4a8f3c"), (40, T0 + 2, 11, "#5aa04a"), (32, T0 - 10, 11, "#68b058"),
                           (20, T0 - 12, 9, "#4a8f3c"), (44, T0 - 16, 9, "#5aa04a"), (32, T0 + 12, 9, "#3f7f35")]:
        b += circ(cx, cy, r, c, OUT, 1.5)
    obj("plant", 1, 1, T0, b)

    # --- огнетушитель
    T0 = 30
    b = ell(36, T0 + 54, 14, 4.5, "#000", None, 0, 0.3)
    b += rect(20, T0 + 46, 24, 8, "#5c6267", OUT, 1.2)
    b += rect(23, T0 + 2, 18, 46, "#c0392b", OUT, 2, 7) + rect(26, T0 + 16, 12, 14, "#ece8dc", None, 0)
    b += rect(27, T0 - 6, 10, 9, "#23262a", None, 0) + path(f"M37 {T0-2}q10 4 6 20", None, "#1d1d1d", 2.4)
    b += line(27, T0 + 6, 27, T0 + 44, "#fff", 2, 0.25)
    obj("extinguisher", 1, 1, T0, b)

    # --- электрощит
    T0 = 40
    b = shadow(14, T0 - 26, 52, 84)
    b += box(6, T0 - 32, 52, 12, 78, "#b8c0c4", "#9aa3a8")
    b += line(32, T0 - 20, 32, T0 + 58, OUT, 1.5)
    b += rect(26, T0 + 10, 3, 12, "#2a2e31", None, 0) + rect(35, T0 + 10, 3, 12, "#2a2e31", None, 0)
    b += poly([(18, T0 - 12), (26, T0 + 2), (10, T0 + 2)], "#d9b13b", OUT, 1.2)
    b += path(f"M18.5 {T0-8}l-2.5 4h3l-2.5 4", None, OUT, 1.2)
    b += circ(44, T0 - 12, 2.6, "#6fbf86", None, 0) + circ(51, T0 - 12, 2.6, "#d9b13b", None, 0)
    obj("cabinet", 1, 1, T0, b)


def objects2():
    """Этап 2: быт, столовая, электрика."""
    # --- шкафчик для одежды 1×1 (высокий, две створки)
    T0 = 56
    b = shadow(14, T0 - 44, 50, 104)
    b += box(8, T0 - 50, 48, 9, 104, "#a9b8c2", "#8798a4")
    b += line(32, T0 - 41, 32, T0 + 63, OUT, 1.5)
    for door_x in (10, 34):
        for k in range(4):
            b += rect(door_x + 4, T0 - 35 + k * 5, 14, 2, "#5f6f7a", None, 0)
        b += rect(door_x + 6, T0 + 40, 10, 6, "#d9d2bc", OUT, 0.8)
    b += rect(26, T0 + 4, 3, 12, "#3a3f43", None, 0) + rect(35, T0 + 4, 3, 12, "#3a3f43", None, 0)
    b += rect(10, T0 - 39, 2, 100, "#fff", None, 0, 0, 0.18)
    b += rect(8, T0 + 60, 48, 4, "#5f6f7a", OUT, 1)
    obj("locker", 1, 1, T0, b)

    # --- раковина 1×1: зеркало, раковина на тумбе
    T0 = 44
    b = shadow(14, T0 - 2, 48, 64)
    b += rect(16, T0 - 40, 32, 24, "#b9d3df", OUT, 2, 3) + path(f"M20 {T0-22}L30 {T0-36}M26 {T0-20}L38 {T0-36}", None, "#fff", 2, 0.6)
    b += rect(12, T0 + 14, 40, 40, "#e6e9e8", OUT, 2) + rect(16, T0 + 20, 32, 30, None, "#c4cac8", 1.2)
    b += ell(32, T0 + 8, 22, 10, "#f4f6f5", OUT, 2) + ell(32, T0 + 9, 15, 6, "#bcd0da", OUT, 1.2)
    b += circ(32, T0 + 10, 1.6, "#5a6468", None, 0)
    b += rect(30, T0 - 6, 4, 10, "#b8c0c4", OUT, 1) + path(f"M32 {T0-6}q0 -5 6 -5", None, "#b8c0c4", 2.4)
    b += circ(24, T0 - 3, 2.6, "#c94a3a", OUT, 0.8) + circ(40, T0 - 3, 2.6, "#4d7fb0", OUT, 0.8)
    b += rect(46, T0 - 30, 6, 14, "#7fb3d9", OUT, 1, 2)
    obj("sink", 1, 1, T0, b)

    # --- холодильник 1×1
    T0 = 58
    b = shadow(14, T0 - 46, 50, 106)
    b += box(8, T0 - 52, 48, 9, 106, "#f2f3f0", "#dfe2de")
    b += line(8, T0 - 8, 56, T0 - 8, OUT, 1.6)
    b += rect(46, T0 - 36, 4, 18, "#9aa3a8", OUT, 1, 2) + rect(46, T0 + 2, 4, 26, "#9aa3a8", OUT, 1, 2)
    b += rect(14, T0 - 30, 9, 9, "#e2752c", OUT, 0.8, 2) + rect(16, T0 + 14, 12, 8, "#ece8dc", OUT, 0.8)
    b += line(18, T0 + 17, 26, T0 + 17, "#8a8a84", 0.8) + line(18, T0 + 19, 24, T0 + 19, "#8a8a84", 0.8)
    b += rect(10, T0 - 41, 2, 100, "#fff", None, 0, 0, 0.5)
    b += rect(10, T0 + 56, 44, 6, "#3a3f43", OUT, 1)
    obj("fridge", 1, 1, T0, b)

    # --- микроволновка на тумбе 1×1
    T0 = 32
    b = shadow(14, T0 + 2, 52, 60)
    b += box(6, T0 + 2, 52, 18, 38, "#a8845a", "#6b5236")
    b += rect(12, T0 + 24, 40, 30, None, "#523e28", 1.5) + circ(46, T0 + 39, 2, "#c9ccce", None, 0)
    b += box(8, T0 - 20, 48, 8, 22, "#d6dad7", "#bfc4c1")
    b += rect(11, T0 - 10, 30, 17, "#2b3136", OUT, 1.2) + rect(13, T0 - 8, 10, 4, "#fff", None, 0, 0, 0.25)
    b += rect(44, T0 - 10, 9, 5, "#6fbf86", None, 0) + circ(48.5, T0 - 1, 2.2, "#5a6468", None, 0)
    obj("microwave", 1, 1, T0, b)

    # --- кулер с водой 1×1
    T0 = 50
    b = ell(36, T0 + 58, 17, 5, "#000", None, 0, 0.28)
    b += rect(18, T0 - 4, 28, 60, "#e9ecec", OUT, 2, 3) + rect(20, T0 + 30, 24, 14, "#c9ced0", OUT, 1.2)
    b += rect(23, T0 + 10, 6, 7, "#c94a3a", OUT, 1, 1) + rect(35, T0 + 10, 6, 7, "#4d7fb0", OUT, 1, 1)
    b += path(f"M22 {T0-4}Q22 {T0-14} 32 {T0-14}Q42 {T0-14} 42 {T0-4}", "#9fc4dd", OUT, 1.5)
    b += rect(19, T0 - 44, 26, 32, "#8fbbd9", OUT, 2, 8) + rect(23, T0 - 40, 5, 22, "#fff", None, 0, 2, 0.45)
    b += line(19, T0 - 32, 45, T0 - 32, "#6f9fc0", 1.2) + line(19, T0 - 24, 45, T0 - 24, "#6f9fc0", 1.2)
    obj("cooler", 1, 1, T0, b)

    # --- диван 2×1
    T0 = 26
    b = shadow(12, T0 + 4, 120, 58)
    SOFA, SOFA_D = "#6a7a52", "#55633f"
    b += rect(8, T0 + 54, 6, 8, "#2e3236", None, 0) + rect(114, T0 + 54, 6, 8, "#2e3236", None, 0)
    b += rect(6, T0 - 6, 116, 26, SOFA_D, OUT, 2, 6)
    b += rect(10, T0 - 2, 52, 18, SOFA, OUT, 1.5, 5) + rect(66, T0 - 2, 52, 18, SOFA, OUT, 1.5, 5)
    b += rect(6, T0 + 18, 116, 36, SOFA, OUT, 2, 5)
    b += rect(14, T0 + 20, 48, 24, "#7a8a60", OUT, 1.2, 4) + rect(66, T0 + 20, 48, 24, "#7a8a60", OUT, 1.2, 4)
    b += rect(2, T0 + 6, 12, 48, SOFA_D, OUT, 2, 5) + rect(114, T0 + 6, 12, 48, SOFA_D, OUT, 2, 5)
    b += path(f"M30 {T0+30}q4 3 9 0M88 {T0+28}q5 4 10 0", None, "#55633f", 1.2)
    b += rect(80, T0 + 2, 18, 12, "#c9a45a", OUT, 1, 3)
    obj("sofa", 2, 1, T0, b)

    # --- доска почёта 2×1
    T0 = 62
    b = shadow(14, T0 + 34, 116, 26)
    b += rect(14, T0 + 30, 6, 30, "#5a4636", OUT, 1.5) + rect(108, T0 + 30, 6, 30, "#5a4636", OUT, 1.5)
    b += rect(4, T0 - 54, 120, 88, "#8a2a24", OUT, 2.4, 3)
    b += rect(8, T0 - 50, 112, 14, "#a8322b", None, 0)
    for k in range(9):
        b += rect(20 + k * 10, T0 - 46, 6, 6, "#d9b13b", None, 0, 1)
    b += poly([(64, T0 - 62), (67, T0 - 55), (75, T0 - 55), (69, T0 - 50), (71, T0 - 43), (64, T0 - 47), (57, T0 - 43), (59, T0 - 50), (53, T0 - 55), (61, T0 - 55)], "#d9b13b", OUT, 1.2)
    skins = ["#e8bc94", "#f0cdb0", "#d8a47c", "#c98d63", "#e8bc94", "#f0cdb0"]
    hairs = ["#4a3020", "#9a9a94", "#2a2420", "#6b4428", "#c9a45a", "#2a2420"]
    for k in range(6):
        x = 12 + (k % 3) * 36
        y = T0 - 32 + (k // 3) * 32
        b += rect(x, y, 30, 26, "#ece8dc", OUT, 1.2)
        b += rect(x + 3, y + 3, 24, 20, "#b9c4cc", None, 0)
        b += circ(x + 15, y + 11, 5, skins[k], OUT, 0.8) + path(f"M{x+10} {y+9}q5 -7 10 0", hairs[k], None, 0)
        b += path(f"M{x+6} {y+23}q9 -9 18 0", "#3d5a7a", OUT, 0.8)
    b += rect(4, T0 + 30, 120, 6, "#6a2420", OUT, 1.5)
    obj("honor_board", 2, 1, T0, b)

    # --- трансформаторная подстанция КТП 2×2
    T0 = 40
    b = rect(4, T0 + 100, 132, 28, "#8f8b84", None, 0, 2, 0.6)
    b += speckle(random.Random(5), 132, 20, 40, ["#6f6b64", "#a9a59e"]).replace('cx="', 'cx="4+') if False else ""
    for k in range(14):
        b += circ(10 + k * 9, T0 + 112 + (k % 3) * 4, 1.8, "#6f6b64", None, 0)
    b += shadow(16, T0 - 6, 124, 128)
    b += poly([(6, T0 - 6), (14, T0 - 22), (126, T0 - 22), (134, T0 - 6)], "#9da4a8", OUT, 2)
    b += rect(6, T0 - 6, 128, 14, "#b5bcc0", OUT, 2)
    b += rect(8, T0 + 8, 124, 96, "#a7aeb2", OUT, 2)
    for dx in (12, 72):
        b += rect(dx, T0 + 14, 56, 86, "#98a0a5", OUT, 1.6)
        b += line(dx + 28, T0 + 14, dx + 28, T0 + 100, OUT, 1.2)
        for k in range(5):
            b += rect(dx + 6, T0 + 22 + k * 6, 16, 3, "#6f777c", None, 0)
            b += rect(dx + 34, T0 + 22 + k * 6, 16, 3, "#6f777c", None, 0)
        b += rect(dx + 24, T0 + 60, 3, 12, "#2a2e31", None, 0) + rect(dx + 30, T0 + 60, 3, 12, "#2a2e31", None, 0)
    b += poly([(70, T0 + 54), (82, T0 + 76), (58, T0 + 76)], "#d9b13b", OUT, 1.4)
    b += path(f"M70.5 {T0+60}l-4 7h5l-4 7", None, OUT, 1.6)
    b += rect(40, T0 + 82, 60, 8, "#ece8dc", OUT, 1)
    for k in range(5):
        b += rect(44 + k * 11, T0 + 84, 7, 4, "#c94a3a", None, 0)
    b += rect(122, T0 + 40, 10, 64, "#5a6268", OUT, 1.4) + rect(8, T0 + 40, 10, 64, "#5a6268", OUT, 1.4)
    obj("ktp", 2, 2, T0, b)


def objects3():
    """Этап 3: фрезерный и сверлильный станки, сварка, сборка, печь, покраска, логистика."""
    GT, GF = "#7d9283", "#5e7364"      # станочная зелёная краска
    GT2, GF2 = "#8e9fa8", "#6f8089"    # серо-голубая
    # --- фрезерный станок 6Р12, 2×1
    T0 = 74
    b = shadow(14, T0 - 10, 122, 76)
    b += box(40, T0 - 62, 54, 10, 72, GT, GF)                       # станина-колонна
    b += box(30, T0 - 70, 74, 12, 22, GT, GF)                       # шпиндельная головка
    b += box(96, T0 - 66, 26, 10, 18, "#6a7c70", "#566659")         # электродвигатель
    for k in range(4):
        b += line(98, T0 - 54 + k * 4, 120, T0 - 54 + k * 4, "#4a5a4e", 1.2)
    b += rect(58, T0 - 36, 14, 10, "#9aa3a8", OUT, 1.5) + rect(61, T0 - 26, 8, 12, "#c9ccce", OUT, 1.2)   # шпиндель
    b += rect(56, T0 - 14, 18, 6, "#5a6268", OUT, 1.2)                # фреза
    for k in range(5):
        b += line(57 + k * 4, T0 - 14, 59 + k * 4, T0 - 8, "#d0d5d8", 1)
    b += box(6, T0 - 8, 118, 14, 10, "#9aa1a5", "#7b8286")          # стол
    for k in range(3):
        b += line(8, T0 - 4 + k * 4, 122, T0 - 4 + k * 4, "#5f666a", 1.2)
    b += box(44, T0 + 16, 44, 8, 34, GT, GF)                         # консоль
    b += circ(20, T0 + 10, 7, None, "#c9ccce", 2.2) + line(13, T0 + 10, 27, T0 + 10, "#c9ccce", 1.2) + line(20, T0 + 3, 20, T0 + 17, "#c9ccce", 1.2)
    b += circ(110, T0 + 10, 7, None, "#c9ccce", 2.2) + line(103, T0 + 10, 117, T0 + 10, "#c9ccce", 1.2)
    b += circ(100, T0 + 34, 5, None, "#c9ccce", 2) + line(96, T0 + 34, 104, T0 + 34, "#c9ccce", 1)
    b += rect(78, T0 - 48, 14, 10, "#3a3f43", OUT, 1.2) + circ(82, T0 - 43, 2.6, "#c94a3a", None, 0)
    b += path(f"M44 {T0-56}Q30 {T0-40} 52 {T0-18}", None, "#3f6f9a", 2.4, dash="3 1.4")
    b += rect(48, T0 + 52, 36, 8, "#4e5f54", OUT, 1.5)
    obj("mill", 2, 1, T0, b)
    META["mill"]["anchors"] = {"lamp": [88, T0 - 43], "work": [64, T0 - 10], "in": [18, T0 - 6], "out": [104, T0 - 6]}

    # --- сверлильный станок 2Н135, 1×1
    T0 = 82
    b = shadow(14, T0 - 12, 50, 72)
    b += rect(10, T0 + 36, 48, 18, "#4e5f54", OUT, 2, 2) + rect(12, T0 + 38, 44, 4, "#fff", None, 0, 0, 0.12)
    b += rect(36, T0 - 60, 12, 98, "#a8b0b4", OUT, 2, 3) + line(39, T0 - 58, 39, T0 + 34, "#fff", 1.4, 0.5)
    b += box(16, T0 - 76, 40, 9, 26, GT, GF)
    b += box(22, T0 - 88, 26, 8, 10, "#6a7c70", "#566659")
    b += rect(22, T0 - 44, 12, 14, "#9aa3a8", OUT, 1.5) + rect(26, T0 - 30, 4, 12, "#d0d5d8", OUT, 1)
    b += path(f"M28 {T0-18}l-2 4h4z", "#d0d5d8", OUT, 0.8)
    for a in (0, 2.1, 4.2):
        b += line(44, T0 - 54, 44 + math.cos(a) * 12, T0 - 54 + math.sin(a) * 6, "#2a2e31", 2)
        b += circ(44 + math.cos(a) * 12, T0 - 54 + math.sin(a) * 6, 2.4, "#1d1d1d", None, 0)
    b += box(12, T0 - 2, 34, 8, 6, "#9aa1a5", "#7b8286")
    b += rect(20, T0 - 70, 9, 7, "#3a3f43", OUT, 1) + circ(24.5, T0 - 66.5, 2.2, "#c94a3a", None, 0)
    obj("drill", 1, 1, T0, b)
    META["drill"]["anchors"] = {"lamp": [24.5, T0 - 66.5], "work": [28, T0 - 10], "in": [16, T0 + 2], "out": [40, T0 + 2]}

    # --- сварочный пост 2×1: стол с отверстиями, полуавтомат, баллон
    T0 = 46
    b = shadow(12, T0, 122, 64)
    b += box(4, T0 + 2, 84, 26, 30, "#6a7074", "#4f5458")
    for yy in range(3):
        for xx in range(7):
            b += circ(12 + xx * 11, T0 + 8 + yy * 7, 1.6, "#3a3e42", None, 0)
    b += rect(8, T0 + 34, 4, 22, "#3a3e42", None, 0) + rect(80, T0 + 34, 4, 22, "#3a3e42", None, 0)
    b += path(f"M10 {T0+12}L40 {T0+6}M12 {T0+20}L42 {T0+14}", None, "#8f969a", 4)
    b += box(94, T0 - 8, 30, 10, 46, "#d9b13b", "#b8932c")
    b += rect(98, T0 + 8, 14, 9, "#2a2e31", OUT, 1) + circ(118, T0 + 12, 2.4, "#6fbf86", None, 0) + circ(104, T0 + 26, 4, None, OUT, 1.5)
    b += circ(109, T0 - 3, 7, "#5a3a2a", OUT, 1.4) + circ(109, T0 - 3, 3, "#c98d63", None, 0)
    b += rect(116, T0 - 44, 10, 46, "#4a7f78", OUT, 1.6, 4) + rect(117, T0 - 50, 8, 8, "#3a3f43", OUT, 1.2, 2)
    b += path(f"M96 {T0+20}Q70 {T0+44} 52 {T0+18}", None, "#1d1d1d", 2.4)
    b += rect(46, T0 + 10, 8, 4, "#3a3f43", OUT, 1)
    obj("weld_post", 2, 1, T0, b)
    META["weld_post"]["anchors"] = {"lamp": [118, T0 + 12], "work": [40, T0 + 10], "in": [14, T0 + 4], "out": [72, T0 + 4], "flash": [40, T0 + 10]}

    # --- сборочный верстак 2×1: тиски, ручной пресс, гайковёрт, ящики
    T0 = 40
    b = shadow(12, T0 + 4, 120, 62)
    b += box(2, T0 + 4, 124, 22, 32, "#7d8a92", "#5e6a72")
    b += rect(8, T0 + 30, 50, 26, None, "#4a555c", 1.4) + rect(64, T0 + 30, 56, 26, None, "#4a555c", 1.4)
    for k in range(3):
        b += rect(12, T0 + 34 + k * 7, 42, 5, "#6f7c84", OUT, 0.8) + rect(30, T0 + 35 + k * 7, 6, 2, "#c9ccce", None, 0)
    b += rect(80, T0 - 34, 12, 40, "#4a7f9a", OUT, 1.6) + box(72, T0 - 40, 28, 6, 10, "#5a8fa8", "#4a7f9a")
    b += rect(84, T0 - 26, 4, 22, "#c9ccce", OUT, 1) + line(92, T0 - 34, 106, T0 - 44, "#2a2e31", 2.4) + circ(107, T0 - 45, 2.6, "#1d1d1d", None, 0)
    b += rect(10, T0 - 4, 22, 10, "#3d5a7a", OUT, 1.5) + rect(6, T0, 30, 4, "#8b9296", OUT, 1.2)
    b += rect(42, T0 + 6, 12, 7, "#2a2e31", OUT, 1, 2) + line(54, T0 + 9, 62, T0 + 9, "#c9ccce", 2)
    b += path(f"M48 {T0+6}Q52 {T0-20} 70 {T0-30}", None, "#1d1d1d", 1.6)
    for k in range(3):
        b += rect(104 + k * 7, T0 + 8, 6, 8, ["#c94a3a", "#d9b13b", "#4d7fb0"][k], OUT, 0.8, 1)
    obj("assembly_table", 2, 1, T0, b)
    META["assembly_table"]["anchors"] = {"lamp": [107, T0 - 45], "work": [64, T0 + 10], "in": [16, T0 + 12], "out": [110, T0 + 18]}

    # --- камерная печь 2×2
    T0 = 54
    b = shadow(16, T0 - 20, 126, 140)
    b += box(6, T0 - 36, 98, 14, 128, "#9a8f84", "#7a7066")
    b += rect(18, T0 + 10, 74, 62, "#6a5a4e", OUT, 2, 3)                  # дверца
    for yy in range(4):
        for xx in range(4):
            b += rect(22 + xx * 17 + (yy % 2) * 8, T0 + 14 + yy * 14, 15, 12, "#8a6a52", OUT, 0.8)
    b += rect(40, T0 + 26, 30, 18, "#2a1d16", OUT, 1.6, 2)              # смотровое окно
    b += rect(26, T0 + 76, 58, 8, "#4f5458", OUT, 1.4) + rect(22, T0 + 88, 66, 6, "#3a3e42", OUT, 1)
    b += box(106, T0 - 20, 30, 10, 102, "#8e9fa8", "#6f8089")              # шкаф управления
    b += rect(110, T0 + 0, 22, 14, "#2a2e31", OUT, 1) + rect(112, T0 + 2, 18, 6, "#c94a3a", None, 0, 0, 0.8)
    for k in range(3):
        b += circ(114 + k * 7, T0 + 22, 2.6, ["#6fbf86", "#d9b13b", "#c94a3a"][k], OUT, 0.8)
    b += circ(121, T0 + 38, 6, "#d0d5d8", OUT, 1.4) + line(121, T0 + 38, 125, T0 + 34, OUT, 1.2)
    b += box(26, T0 - 54, 58, 8, 14, "#7a7066", "#5a524a")                 # вытяжной зонт
    b += rect(44, T0 - 70, 22, 16, "#6a625a", OUT, 1.6)
    obj("furnace", 2, 2, T0, b)
    META["furnace"]["anchors"] = {"lamp": [114, T0 + 22], "glow": [40, T0 + 26, 30, 18], "in": [24, T0 + 92], "out": [80, T0 + 92]}

    # --- покрасочная камера 2×2
    T0 = 64
    b = shadow(16, T0 - 26, 126, 138)
    b += box(4, T0 - 50, 132, 12, 120, "#c9cfd2", "#aab2b6")
    b += rect(12, T0 - 30, 116, 92, "#5a6268", OUT, 2)                     # проём
    b += rect(14, T0 - 28, 112, 88, "#7c868c", None, 0)
    for k in range(10):
        b += rect(14 + k * 11.2, T0 - 28, 10, 88, "#d8e4ea", "#9fb0b8", 0.8, 0, 0.45)   # шторки
    b += rect(30, T0 - 44, 80, 10, "#e9ecec", OUT, 1.4) + rect(32, T0 - 42, 76, 6, "#fff6d8", None, 0, 0, 0.8)   # свет
    b += box(48, T0 - 74, 44, 8, 16, "#9aa3a8", "#7b8286")                  # вентиляция
    b += rect(60, T0 - 86, 20, 12, "#8a9196", OUT, 1.4)
    b += rect(116, T0 + 0, 14, 22, "#3a3f43", OUT, 1.2) + circ(123, T0 + 6, 2.4, "#6fbf86", None, 0)
    obj("paint_booth", 2, 2, T0, b)
    META["paint_booth"]["anchors"] = {"lamp": [123, T0 + 6], "work": [70, T0 + 20], "in": [20, T0 + 64], "out": [110, T0 + 64], "mist": [70, T0 + 10]}

    # --- стеллаж НЗП 2×1: жёлтые стойки и пластиковая тара
    T0 = 54
    b = shadow(12, T0 - 22, 122, 82)
    b += rect(6, T0 - 44, 6, 104, "#d9a43a", OUT, 1.5) + rect(116, T0 - 44, 6, 104, "#d9a43a", OUT, 1.5)
    for y in (T0 - 16, T0 + 24, T0 + 56):
        b += rect(4, y, 120, 6, "#c98a2c", OUT, 1.5)
    for row, y in enumerate((T0 - 38, T0 + 2)):
        for k in range(3):
            b += rect(14 + k * 34, y, 30, 22, "#3f6f9a" if (k + row) % 2 == 0 else "#4a7fa8", OUT, 1.2, 2)
            b += rect(20 + k * 34, y + 4, 18, 4, "#2a4f70", None, 0, 1)
    b += rect(60, T0 - 52, 8, 8, "#ece8dc", OUT, 1)
    obj("wip_rack", 2, 1, T0, b)
    META["wip_rack"]["slots"] = [[14, T0 - 38, 100, 22], [14, T0 + 2, 100, 22]]

    # --- шкаф с инструментом 1×1
    T0 = 60
    b = shadow(14, T0 - 46, 50, 104)
    b += box(8, T0 - 4, 48, 8, 60, "#b0483d", "#8e3a31")
    for k in range(5):
        b += rect(12, T0 + 6 + k * 10, 40, 8, "#a03f35", OUT, 1) + rect(26, T0 + 9 + k * 10, 12, 2, "#d0d5d8", None, 0)
    b += rect(8, T0 - 52, 48, 46, "#c9b37a", OUT, 1.6)                       # перфопанель
    for yy in range(4):
        for xx in range(5):
            b += circ(14 + xx * 9, T0 - 46 + yy * 10, 0.9, "#8a7a4e", None, 0)
    b += path(f"M16 {T0-44}V{T0-22}M24 {T0-44}V{T0-26}M32 {T0-44}V{T0-18}", None, "#5a6268", 2.6)
    b += circ(44, T0 - 36, 5, None, "#5a6268", 2.2) + path(f"M40 {T0-20}h10l-2 -6", None, "#3d5a7a", 2)
    obj("tool_cabinet", 1, 1, T0, b)

    # --- грузовая тележка 1×1
    T0 = 26
    b = ell(34, T0 + 56, 22, 6, "#000", None, 0, 0.25)
    b += rect(8, T0 + 30, 48, 20, "#3d5a7a", OUT, 2, 2) + rect(10, T0 + 32, 44, 4, "#fff", None, 0, 0, 0.18)
    b += rect(8, T0 + 50, 48, 4, "#2f4a68", OUT, 1)
    for x in (14, 48):
        b += circ(x, T0 + 56, 4.5, "#1d1d1d", OUT, 1.2) + circ(x, T0 + 56, 1.6, "#9aa1a5", None, 0)
    b += path(f"M52 {T0+30}V{T0+2}Q52 {T0-4} 46 {T0-4}H40", None, "#2a2e31", 3)
    obj("cart", 1, 1, T0, b)

    # --- электропогрузчик 2×1
    T0 = 70
    b = shadow(14, T0 - 4, 122, 64)
    b += rect(4, T0 - 66, 6, 110, "#3a3f43", OUT, 1.5) + rect(16, T0 - 66, 6, 110, "#3a3f43", OUT, 1.5)   # мачта
    b += line(10, T0 - 60, 16, T0 - 60, "#3a3f43", 2) + line(10, T0 - 20, 16, T0 - 20, "#3a3f43", 2)
    b += rect(0, T0 + 34, 30, 5, "#5a6268", OUT, 1.2) + rect(0, T0 + 44, 30, 5, "#5a6268", OUT, 1.2)       # вилы
    b += box(24, T0 - 6, 90, 14, 46, "#e2b73a", "#c99a28")                    # корпус
    b += rect(90, T0 - 20, 30, 50, "#c99a28", OUT, 2, 6)                        # противовес
    b += rect(48, T0 - 18, 26, 12, "#2a2e31", OUT, 1.4, 3)                       # сиденье
    b += path(f"M30 {T0-6}V{T0-64}H96V{T0-20}", None, "#2a2e31", 3)                # защитная крыша
    b += line(30, T0 - 64, 96, T0 - 64, "#2a2e31", 4)
    b += circ(36, T0 + 44, 10, "#1d1d1d", OUT, 1.5) + circ(36, T0 + 44, 4, "#6a6e72", None, 0)
    b += circ(100, T0 + 44, 10, "#1d1d1d", OUT, 1.5) + circ(100, T0 + 44, 4, "#6a6e72", None, 0)
    b += rect(40, T0 - 26, 4, 14, "#2a2e31", None, 0) + circ(42, T0 - 28, 4, None, "#2a2e31", 2)
    b += rect(104, T0 - 30, 8, 6, "#e2752c", OUT, 1, 2)
    obj("forklift", 2, 1, T0, b)

    # --- кран-балка: на клетке установки — подвесной пульт управления (балку рисует слой крана)
    T0 = 40
    b = ell(32, T0 + 52, 12, 4, "#000", None, 0, 0.25)
    b += line(32, 0, 32, T0 + 10, "#1d1d1d", 1.6)
    b += rect(24, T0 + 8, 16, 30, "#e2b73a", OUT, 1.8, 3) + rect(26, T0 + 10, 12, 4, "#fff", None, 0, 1, 0.25)
    b += circ(32, T0 + 18, 2.6, "#3e9a5a", None, 0) + circ(32, T0 + 25, 2.6, "#3e9a5a", None, 0) + circ(32, T0 + 32, 2.8, "#c94a3a", None, 0)
    b += path("M8 54h48M8 54l6 -6M56 54l-6 -6", None, "#d9b13b", 2, 0.6)
    obj("crane", 1, 1, T0, b)


def objects4():
    """Этап 4: офисная мебель и станок с ЧПУ."""
    # --- стол ИТР 2×1 со стулом перед ним (стул — в клетке рабочего места)
    T0 = 46
    b = shadow(10, T0 + 6, 120, 58)
    # стул (виден, пока никто не сидит)
    cy = T0 + 64 + 30
    b += ell(32, cy + 18, 16, 4, "#000", None, 0, 0.22)
    b += path(f"M18 {cy+16}L32 {cy+10}L46 {cy+16}M32 {cy+10}V{cy+18}", None, "#2a2e31", 2.4)
    b += rect(29, cy, 6, 10, "#3a3f43", OUT, 1.2)
    b += ell(32, cy - 2, 15, 6, "#3d4652", OUT, 1.6)
    b += rect(19, cy - 26, 26, 22, "#3d4652", OUT, 1.6, 6) + rect(22, cy - 23, 20, 4, "#fff", None, 0, 2, 0.12)
    # стол
    b += box(2, T0 + 2, 124, 30, 30, "#b08a5e", "#8c6a44")
    b += rect(84, T0 + 34, 38, 26, None, "#6a5034", 1.4) + rect(98, T0 + 38, 10, 2.4, "#d0c4a8", None, 0) + line(84, T0 + 47, 122, T0 + 47, "#6a5034", 1.2) + rect(98, T0 + 51, 10, 2.4, "#d0c4a8", None, 0)
    b += rect(6, T0 + 34, 4, 26, "#6a5034", None, 0)
    # монитор, клавиатура, телефон, бумаги, лампа
    b += rect(20, T0 - 24, 40, 28, "#2a2e31", OUT, 1.8, 3) + rect(23, T0 - 21, 34, 21, "#4d7fb0", None, 0, 1) + rect(25, T0 - 19, 18, 3, "#9cc4e4", None, 0) + rect(25, T0 - 14, 26, 2, "#9cc4e4", None, 0, 0, 0.7) + rect(25, T0 - 10, 22, 2, "#9cc4e4", None, 0, 0, 0.7)
    b += rect(36, T0 + 4, 8, 6, "#3a3f43", OUT, 1) + rect(28, T0 + 10, 24, 3, "#3a3f43", None, 0)
    b += rect(22, T0 + 16, 34, 8, "#e8e6de", OUT, 1.2, 1)
    for k in range(3):
        b += line(25, T0 + 18 + k * 2, 53, T0 + 18 + k * 2, "#9a9890", 0.8)
    b += rect(66, T0 + 12, 16, 10, "#c94a3a", OUT, 1.2, 2) + path(f"M67 {T0+12}Q74 {T0+6} 81 {T0+12}", None, OUT, 2.4)
    b += rect(88, T0 + 8, 20, 14, "#f4f1e6", OUT, 1, 0) + rect(90, T0 + 6, 20, 14, "#ffffff", OUT, 1, 0)
    for k in range(4):
        b += line(93, T0 + 10 + k * 2.5, 106, T0 + 10 + k * 2.5, "#9a9890", 0.7)
    b += path(f"M114 {T0+20}L110 {T0-6}L102 {T0-12}", None, "#2a2e31", 2.2) + path(f"M96 {T0-14}L106 {T0-18}L108 {T0-8}Z", "#3d6a4e", OUT, 1.2) + ell(114, T0 + 21, 6, 2, "#2a2e31", None, 0)
    obj("office_desk", 2, 1, T0, b, pad=72)
    META["office_desk"]["anchors"] = {"screen": [40, T0 - 10]}

    # --- шкаф для документов
    T0 = 64
    b = shadow(14, T0 - 52, 50, 110)
    b += box(6, T0 - 58, 52, 8, 112, "#c9c3b0", "#a9a390")
    b += rect(10, T0 - 46, 44, 46, "#cfe2ea", OUT, 1.4) + line(32, T0 - 46, 32, T0, OUT, 1.4)
    cols = ["#c94a3a", "#3d6a9a", "#e2b73a", "#4a7a4a", "#7a4a7a", "#3d6a9a", "#c97a3a", "#5a5a60"]
    for row in range(2):
        for k in range(8):
            b += rect(12 + k * 5.2, T0 - 44 + row * 22, 4.4, 19, cols[(k + row * 3) % 8], OUT, 0.6)
    b += rect(10, T0 + 4, 44, 22, "#b3ad99", OUT, 1.2) + rect(10, T0 + 28, 44, 22, "#b3ad99", OUT, 1.2)
    b += rect(27, T0 + 13, 10, 3, "#6a6458", None, 0) + rect(27, T0 + 37, 10, 3, "#6a6458", None, 0)
    obj("doc_cabinet", 1, 1, T0, b)

    # --- сейф
    T0 = 40
    b = shadow(14, T0 - 26, 50, 86)
    b += box(8, T0 - 30, 48, 10, 80, "#4a5a4e", "#3a4a3e")
    b += rect(13, T0 - 14, 38, 60, None, "#2a3a2e", 1.6, 2)
    b += circ(32, T0 + 8, 9, "#8a9196", OUT, 1.6) + circ(32, T0 + 8, 4, "#c9ccce", OUT, 1)
    for k in range(8):
        a = k * math.pi / 4
        b += line(32 + math.cos(a) * 6.5, T0 + 8 + math.sin(a) * 6.5, 32 + math.cos(a) * 8.5, T0 + 8 + math.sin(a) * 8.5, OUT, 0.8)
    b += path(f"M44 {T0+22}h4v14h-4", None, "#c9ccce", 2.4)
    b += rect(18, T0 - 10, 12, 4, "#d9b13b", OUT, 0.8)
    obj("safe", 1, 1, T0, b)

    # --- доска планирования
    T0 = 70
    b = ell(32, T0 + 58, 24, 5, "#000", None, 0, 0.22)
    b += line(14, T0 - 10, 10, T0 + 56, "#5a6268", 2.6) + line(50, T0 - 10, 54, T0 + 56, "#5a6268", 2.6)
    b += line(8, T0 + 56, 20, T0 + 56, "#3a3f43", 2.4) + line(44, T0 + 56, 56, T0 + 56, "#3a3f43", 2.4)
    b += rect(2, T0 - 64, 60, 58, "#f4f6f6", OUT, 2, 2) + rect(2, T0 - 64, 60, 58, None, "#9aa3a8", 3, 2)
    for k in range(6):
        b += line(6, T0 - 54 + k * 8, 58, T0 - 54 + k * 8, "#cfd6db", 0.8)
    bars = [(8, 18, "#c94a3a"), (22, 26, "#3d6a9a"), (12, 30, "#e2b73a"), (30, 20, "#4a7a4a"), (16, 34, "#7a4a7a"), (36, 18, "#3d6a9a")]
    for k, (x, w, c) in enumerate(bars):
        b += rect(x, T0 - 58 + k * 8, w, 5, c, None, 0, 1)
    b += line(40, T0 - 62, 40, T0 - 8, "#c94a3a", 1.2, dash="2 2")
    b += rect(6, T0 - 8, 52, 3, "#9aa3a8", None, 0)
    obj("plan_board", 1, 1, T0, b)

    # --- кульман
    T0 = 72
    b = ell(32, T0 + 58, 24, 5, "#000", None, 0, 0.22)
    b += line(32, T0 - 2, 32, T0 + 52, "#3a3f43", 3) + path(f"M14 {T0+56}L32 {T0+50}L50 {T0+56}", None, "#3a3f43", 2.6)
    b += poly([(4, T0 - 58), (60, T0 - 58), (62, T0), (2, T0)], "#e9e6da", OUT, 2)
    b += poly([(8, T0 - 52), (56, T0 - 52), (57, T0 - 6), (7, T0 - 6)], "#ffffff", "#bdb8a6", 1)
    b += path(f"M14 {T0-40}H44V{T0-22}H30V{T0-14}H14Z", None, "#4a5a7a", 1.2)
    b += circ(36, T0 - 31, 5, None, "#4a5a7a", 1.1) + line(14, T0 - 46, 50, T0 - 46, "#4a5a7a", 0.6, dash="2 1.5")
    b += path(f"M58 {T0-56}L44 {T0-36}L52 {T0-20}", None, "#7a8288", 2) + line(40, T0 - 20, 60, T0 - 20, "#c94a3a", 2) + line(52, T0 - 30, 52, T0 - 10, "#c94a3a", 2)
    obj("drawing_board", 1, 1, T0, b)

    # --- токарный станок с ЧПУ 3×1 (закрытый кожух, пульт)
    T0 = 66
    b = shadow(12, T0 - 30, 186, 96)
    b += box(4, T0 - 56, 160, 16, 98, "#e4e7e8", "#c6cbcd")
    b += rect(10, T0 + 46, 150, 10, "#3d5a7a", OUT, 1.6)
    b += rect(20, T0 - 34, 104, 54, "#2a3036", OUT, 2, 3)
    b += rect(24, T0 - 30, 96, 46, "#3e5866", None, 0, 2, 0.85) + poly([(30, T0 - 30), (52, T0 - 30), (34, T0 + 16), (24, T0 + 16)], "#ffffff", None, 0, 0.12)
    b += rect(36, T0 - 14, 20, 20, "#9aa3a8", OUT, 1.2, 2) + rect(56, T0 - 8, 40, 8, "#c9ccce", OUT, 1.2) + rect(96, T0 - 6, 10, 4, "#c9ccce", OUT, 1)
    b += rect(124, T0 - 34, 4, 54, "#9aa3a8", None, 0)
    b += box(166, T0 - 64, 26, 10, 80, "#3d4652", "#2e3640")
    b += rect(170, T0 - 48, 18, 14, "#1d2a34", OUT, 1) + rect(172, T0 - 46, 14, 10, "#6fd0e0", None, 0, 1, 0.8)
    for yy in range(3):
        for xx in range(3):
            b += rect(171 + xx * 6, T0 - 28 + yy * 6, 4, 4, ["#c9ccce", "#e2b73a", "#6fbf86"][(xx + yy) % 3], None, 0, 1)
    b += circ(179, T0 - 2, 4, "#c94a3a", OUT, 1)
    b += rect(140, T0 - 70, 6, 14, "#3a3f43", OUT, 1) + circ(143, T0 - 74, 4, "#6fbf86", OUT, 1)
    b += rect(30, T0 - 52, 60, 8, "#3d5a7a", None, 0, 1)
    obj("cnc_lathe", 3, 1, T0, b)
    META["cnc_lathe"]["anchors"] = {"lamp": [143, T0 - 74], "work": [70, T0 - 6], "in": [150, T0 + 30], "out": [16, T0 + 30], "screen": [179, T0 - 41]}


def objects_v14():
    """Версия 1.4: учебный класс — парта и школьная доска."""
    # --- парта 2×1 на двоих, стулья — в клетках учеников (ниже)
    T0 = 40
    b = shadow(10, T0 + 6, 120, 56)
    for cx in (32, 96):
        cy = T0 + 64 + 30
        b += ell(cx, cy + 18, 14, 4, "#000", None, 0, 0.22)
        b += line(cx - 11, cy + 16, cx - 11, cy + 2, "#4a5156", 2.2) + line(cx + 11, cy + 16, cx + 11, cy + 2, "#4a5156", 2.2)
        b += rect(cx - 14, cy - 4, 28, 8, "#b58a58", OUT, 1.6, 2)
        b += rect(cx - 13, cy - 24, 26, 14, "#b58a58", OUT, 1.6, 3) + rect(cx - 10, cy - 22, 20, 3, "#fff", None, 0, 1, 0.18)
        b += line(cx - 11, cy - 10, cx - 11, cy - 4, "#4a5156", 2) + line(cx + 11, cy - 10, cx + 11, cy - 4, "#4a5156", 2)
    # металлическая рама
    b += line(10, T0 + 30, 10, T0 + 60, "#4a5156", 3) + line(118, T0 + 30, 118, T0 + 60, "#4a5156", 3)
    b += line(10, T0 + 52, 118, T0 + 52, "#4a5156", 2.4)
    b += rect(6, T0 + 58, 10, 4, "#2e3236", None, 0, 1) + rect(112, T0 + 58, 10, 4, "#2e3236", None, 0, 1)
    # полка под столешницей и наклонная крышка
    b += rect(8, T0 + 24, 112, 10, "#8c6a44", OUT, 1.6)
    b += box(4, T0 + 2, 120, 20, 8, "#d2b383", "#a8845a")
    b += line(64, T0 + 2, 64, T0 + 22, "#a8845a", 1.2)
    # тетради, ручка, учебник
    b += rect(16, T0 + 6, 22, 12, "#e9e4d2", OUT, 1, 1) + line(27, T0 + 6, 27, T0 + 18, "#b9b29c", 0.8)
    for k in range(3):
        b += line(18, T0 + 9 + k * 3, 25, T0 + 9 + k * 3, "#7b8fb0", 0.6) + line(29, T0 + 9 + k * 3, 36, T0 + 9 + k * 3, "#7b8fb0", 0.6)
    b += line(42, T0 + 16, 54, T0 + 9, "#2f4a68", 1.6)
    b += rect(78, T0 + 5, 26, 14, "#3d6a4e", OUT, 1.2, 1) + rect(80, T0 + 7, 22, 3, "#d9c48a", None, 0)
    b += rect(108, T0 + 7, 8, 10, "#c94a3a", OUT, 1, 1)
    obj("school_desk", 2, 1, T0, b, pad=72)

    # --- школьная доска 2×1 на ножках
    T0 = 76
    b = ell(64, T0 + 58, 54, 6, "#000", None, 0, 0.22)
    b += line(14, T0 - 6, 10, T0 + 56, "#5a4a3a", 3.2) + line(114, T0 - 6, 118, T0 + 56, "#5a4a3a", 3.2)
    b += line(4, T0 + 56, 20, T0 + 56, "#3a3027", 3) + line(108, T0 + 56, 124, T0 + 56, "#3a3027", 3)
    b += rect(2, T0 - 70, 124, 66, "#8c6a44", OUT, 2, 3)
    b += rect(7, T0 - 65, 114, 56, "#2f5a44", None, 0, 1)
    b += rect(9, T0 - 63, 110, 16, "#ffffff", None, 0, 1, 0.05)
    # надписи мелом: формула, чертёж детали, дата
    b += path(f"M14 {T0-55}h10M19 {T0-60}v10M30 {T0-58}q4 -4 8 0t8 0M50 {T0-55}h8", None, "#e8efe8", 1.3)
    b += path(f"M16 {T0-40}h30v12h-30zM46 {T0-37}h14v6h-14", None, "#e8efe8", 1.2)
    b += line(16, T0 - 24, 60, T0 - 24, "#e8efe8", 0.8, dash="3 2")
    b += path(f"M72 {T0-56}h40M72 {T0-48}h32M72 {T0-40}h36M72 {T0-32}h24", None, "#e8efe8", 1.1, 0.85)
    b += path(f"M74 {T0-22}l6 6l12 -12", None, "#f0d58a", 1.6)
    b += rect(4, T0 - 8, 120, 5, "#6b5236", OUT, 1.2)
    b += rect(30, T0 - 10, 8, 3, "#f4f4f0", None, 0, 1) + rect(42, T0 - 10, 5, 3, "#f0d58a", None, 0, 1)
    b += line(70, T0 - 9, 110, T0 - 11, "#a8845a", 2.2)
    b += rect(92, T0 - 12, 12, 5, "#5a6a7a", OUT, 0.8, 1)
    obj("chalkboard", 2, 1, T0, b)


def objects_rot():
    """1.4: честные повороты объектов. «_v» — объект смотрит влево (рабочая сторона слева; для поворота
    вправо спрайт отражается), «_b» — смотрит вверх (видна задняя стенка). Тень везде справа-снизу."""
    GT, GF = "#7d9283", "#5e7364"
    SIDE = "#71828e"

    # ---------------- шкафчик для одежды
    T0 = 56

    def locker(view):
        b = shadow(14, T0 - 44, 50, 104)
        b += box(8, T0 - 50, 48, 9, 104, "#a9b8c2", "#7f909c")
        if view == "v":
            b += rect(8, T0 - 41, 9, 101, "#8798a4", OUT, 1.4)
            for k in range(4):
                b += rect(10, T0 - 35 + k * 5, 5, 2, "#5f6f7a", None, 0)
            b += rect(3, T0 + 2, 6, 14, "#3a3f43", OUT, 0.8, 1)
            b += rect(23, T0 - 32, 26, 42, None, SIDE, 1.2, 3) + rect(23, T0 + 16, 26, 36, None, SIDE, 1.2, 3)
        else:
            b += line(32, T0 - 41, 32, T0 + 59, SIDE, 1.2)
            b += rect(16, T0 - 32, 32, 10, "#ece8dc", OUT, 0.8) + line(19, T0 - 28, 44, T0 - 28, "#8a8a84", 0.8) + line(19, T0 - 25, 36, T0 - 25, "#8a8a84", 0.8)
            b += bolts([(14, T0 - 36), (50, T0 - 36), (14, T0 + 52), (50, T0 + 52)], 1.6)
        b += rect(8, T0 + 60, 48, 4, "#5f6f7a", OUT, 1)
        return b
    obj("locker_v", 1, 1, T0, locker("v"))
    obj("locker_b", 1, 1, T0, locker("b"))

    # ---------------- раковина: тумба, чаша, кран, зеркало на стене
    T0 = 44
    b = shadow(14, T0 - 2, 48, 64)
    b += rect(48, T0 - 42, 7, 52, "#b9d3df", OUT, 1.6, 2) + line(51, T0 - 38, 51, T0 + 4, "#fff", 1.4, 0.6)   # зеркало ребром у стены справа
    b += rect(12, T0 + 14, 40, 40, "#d9dddc", OUT, 2) + rect(12, T0 + 14, 7, 40, "#e6e9e8", OUT, 1.2)
    b += circ(9, T0 + 32, 2, "#9aa3a8", OUT, 0.8)
    b += rect(24, T0 + 22, 20, 26, None, "#c4cac8", 1.2)
    b += ell(30, T0 + 8, 19, 11, "#f4f6f5", OUT, 2) + ell(28, T0 + 9, 12, 7, "#bcd0da", OUT, 1.2)
    b += circ(28, T0 + 10, 1.6, "#5a6468", None, 0)
    b += rect(42, T0 - 2, 8, 9, "#b8c0c4", OUT, 1) + path(f"M44 {T0-1}q-6 -4 -10 2", None, "#b8c0c4", 2.4)
    b += circ(45, T0 - 7, 2.4, "#c94a3a", OUT, 0.8) + circ(45, T0 + 11, 2.4, "#4d7fb0", OUT, 0.8)
    obj("sink_v", 1, 1, T0, b)
    b = shadow(14, T0 - 2, 48, 64)
    b += rect(12, T0 + 14, 40, 40, "#d9dddc", OUT, 2) + line(32, T0 + 16, 32, T0 + 52, "#c4cac8", 1)
    b += ell(32, T0 + 6, 22, 10, "#f4f6f5", OUT, 2) + ell(32, T0 + 5, 15, 6, "#bcd0da", OUT, 1.2)
    b += circ(32, T0 + 4, 1.6, "#5a6468", None, 0)
    b += rect(30, T0 + 12, 4, 8, "#b8c0c4", OUT, 1) + path(f"M32 {T0+12}q0 -7 0 -9", None, "#b8c0c4", 2.4)
    b += circ(24, T0 + 15, 2.4, "#c94a3a", OUT, 0.8) + circ(40, T0 + 15, 2.4, "#4d7fb0", OUT, 0.8)
    b += rect(16, T0 + 22, 32, 22, "#8a9196", OUT, 1.4, 2) + bolts([(19, T0 + 25), (45, T0 + 25), (19, T0 + 41), (45, T0 + 41)], 1.2, "#5a6064")   # зеркало со спины
    obj("sink_b", 1, 1, T0, b)

    # ---------------- холодильник
    T0 = 58

    def fridge(view):
        b = shadow(14, T0 - 46, 50, 106)
        b += box(8, T0 - 52, 48, 9, 106, "#f2f3f0", "#dcdfdb")
        if view == "v":
            b += rect(8, T0 - 43, 8, 100, "#e8eae6", OUT, 1.4) + line(8, T0 - 8, 16, T0 - 8, OUT, 1.4)
            b += rect(3, T0 - 36, 6, 18, "#9aa3a8", OUT, 1, 2) + rect(3, T0 + 2, 6, 26, "#9aa3a8", OUT, 1, 2)
            b += line(34, T0 - 40, 34, T0 + 52, "#cfd2ce", 1.2)
        else:
            b += rect(14, T0 - 34, 36, 66, "#2e3236", None, 0, 2, 0.15)
            for k in range(9):
                b += line(16, T0 - 30 + k * 7, 48, T0 - 30 + k * 7, "#3a3f43", 1.4)
            b += line(18, T0 - 32, 18, T0 + 30, "#3a3f43", 1.2) + line(46, T0 - 32, 46, T0 + 30, "#3a3f43", 1.2)
            b += rect(18, T0 + 36, 28, 16, "#3a3f43", OUT, 1.2, 3) + rect(36, T0 - 40, 12, 6, "#ece8dc", OUT, 0.6)
        b += rect(10, T0 + 56, 44, 6, "#3a3f43", OUT, 1)
        return b
    obj("fridge_v", 1, 1, T0, fridge("v"))
    obj("fridge_b", 1, 1, T0, fridge("b"))

    # ---------------- микроволновка на тумбе
    T0 = 32

    def micro(view):
        b = shadow(14, T0 + 2, 52, 60)
        b += box(6, T0 + 2, 52, 18, 38, "#a8845a", "#7a5d3e")
        b += box(8, T0 - 20, 48, 8, 22, "#d6dad7", "#bdc2bf")
        if view == "v":
            b += rect(6, T0 + 20, 7, 38, "#6b5236", OUT, 1.2) + circ(4, T0 + 39, 2, "#c9ccce", OUT, 0.6)
            b += rect(8, T0 - 12, 7, 22, "#2b3136", OUT, 1.2) + rect(3, T0 - 8, 5, 12, "#5a6468", OUT, 0.8, 1)
            for k in range(4):
                b += line(22, T0 - 8 + k * 4, 50, T0 - 8 + k * 4, "#a6aba8", 1)
        else:
            for k in range(3):
                for j in range(6):
                    b += rect(16 + j * 6, T0 - 9 + k * 5, 4, 2, "#8e938f", None, 0)
            b += path(f"M44 {T0+2}q4 8 -4 12", None, "#2a2e31", 1.6)
            b += rect(12, T0 + 26, 40, 28, None, "#6b5236", 1.2)
        return b
    obj("microwave_v", 1, 1, T0, micro("v"))
    obj("microwave_b", 1, 1, T0, micro("b"))

    # ---------------- кулер
    T0 = 50

    def cooler(view):
        b = ell(36, T0 + 58, 17, 5, "#000", None, 0, 0.28)
        b += rect(18, T0 - 4, 28, 60, "#e3e7e7", OUT, 2, 3) + rect(20, T0 + 30, 24, 14, "#c9ced0", OUT, 1.2)
        if view == "v":
            b += rect(13, T0 + 8, 7, 6, "#c94a3a", OUT, 1, 1) + rect(13, T0 + 16, 7, 6, "#4d7fb0", OUT, 1, 1)
        else:
            b += rect(26, T0 + 4, 12, 16, "#ece8dc", OUT, 0.8) + path(f"M40 {T0+50}q8 2 6 8", None, "#2a2e31", 1.6)
        b += path(f"M22 {T0-4}Q22 {T0-14} 32 {T0-14}Q42 {T0-14} 42 {T0-4}", "#9fc4dd", OUT, 1.5)
        b += rect(19, T0 - 44, 26, 32, "#8fbbd9", OUT, 2, 8) + rect(23 if view != "b" else 36, T0 - 40, 5, 22, "#fff", None, 0, 2, 0.45)
        b += line(19, T0 - 32, 45, T0 - 32, "#6f9fc0", 1.2) + line(19, T0 - 24, 45, T0 - 24, "#6f9fc0", 1.2)
        return b
    obj("cooler_v", 1, 1, T0, cooler("v"))
    obj("cooler_b", 1, 1, T0, cooler("b"))

    # ---------------- туалетная кабинка (дверь слева / сзади)
    T0 = 56
    b = shadow(14, T0 - 44, 52, 104)
    b += rect(4, T0 - 50, 56, 50, "#d6dad7", OUT, 2)
    for k in range(0, 50, 12):
        b += line(4, T0 - 50 + k, 60, T0 - 50 + k, "#c3c7c4", 1)
    b += rect(46, T0 - 44, 10, 26, "#ecefef", OUT, 1.5, 2)                    # бачок справа
    b += ell(32, T0 - 30, 13, 10, "#ecefef", OUT, 1.8) + ell(30, T0 - 30, 8, 6, "#bcd0da", OUT, 1)
    b += rect(2, T0 - 52, 4, 54, "#7f949e", OUT, 1.2) + rect(58, T0 - 52, 4, 54, "#7f949e", OUT, 1.2)
    b += rect(2, T0, 60, 58, "#9aaab5", OUT, 2)
    for k in range(1, 4):
        b += line(2 + k * 15, T0 + 2, 2 + k * 15, T0 + 56, "#8a9ba6", 1)
    b += rect(0, T0 - 50, 9, 108, "#8a9ba6", OUT, 1.4) + rect(1, T0 + 24, 4, 9, "#c9ccce", OUT, 0.8)
    b += rect(1, T0 + 6, 6, 8, "#ece8dc", OUT, 0.6)
    obj("toilet_v", 1, 1, T0, b)
    META["toilet_v"]["anchors"] = {"busy": [44, T0 + 12]}
    b = shadow(14, T0 - 44, 52, 104)
    b += rect(4, T0 - 50, 56, 50, "#d6dad7", OUT, 2)
    for k in range(0, 56, 14):
        b += line(4 + k, T0 - 50, 4 + k, T0, "#c3c7c4", 1)
    b += rect(4, T0 - 50, 56, 5, "#8a9ba6", OUT, 1.2)                           # дверь — сверху
    b += ell(32, T0 - 30, 11, 12, "#ecefef", OUT, 1.8) + ell(32, T0 - 31, 6.5, 8, "#bcd0da", OUT, 1)
    b += rect(22, T0 - 14, 20, 9, "#ecefef", OUT, 1.5, 2)                       # бачок у ближней стенки
    b += rect(2, T0 - 52, 4, 54, "#7f949e", OUT, 1.2) + rect(58, T0 - 52, 4, 54, "#7f949e", OUT, 1.2)
    b += rect(2, T0, 60, 58, "#9aaab5", OUT, 2)
    for k in range(1, 4):
        b += line(2 + k * 15, T0 + 2, 2 + k * 15, T0 + 56, "#8a9ba6", 1)
    obj("toilet_b", 1, 1, T0, b)
    META["toilet_b"]["anchors"] = {"busy": [44, T0 + 12]}

    # ---------------- тумба с чайником
    T0 = 30

    def kettle(view):
        b = shadow(14, T0 + 4, 52, 60)
        b += box(6, T0 + 2, 52, 18, 38, "#a8845a", "#7a5d3e")
        if view == "v":
            b += rect(6, T0 + 20, 7, 38, "#6b5236", OUT, 1.2) + circ(4, T0 + 39, 2, "#c9ccce", OUT, 0.6)
            b += rect(22, T0 - 14, 18, 22, "#d0d5d8", OUT, 1.5, 5) + rect(20, T0 - 18, 22, 6, "#3a3f43", OUT, 1.2, 3)
            b += path(f"M22 {T0-8}l-8 -4", None, "#b8c0c4", 3) + path(f"M40 {T0-10}q8 2 2 14", None, OUT, 2.2)
        else:
            b += rect(22, T0 - 14, 18, 22, "#d0d5d8", OUT, 1.5, 5) + rect(20, T0 - 18, 22, 6, "#3a3f43", OUT, 1.2, 3)
            b += rect(27, T0 - 10, 8, 16, "#3a3f43", OUT, 1.2, 3) + path(f"M44 {T0+8}q6 6 0 14", None, "#2a2e31", 1.4)
            b += rect(12, T0 + 24, 40, 30, None, "#6b5236", 1.2)
        return b
    obj("kettle_v", 1, 1, T0, kettle("v"))
    obj("kettle_b", 1, 1, T0, kettle("b"))

    # ---------------- шкаф с инструментом: перфопанель у стены
    T0 = 60
    b = shadow(14, T0 - 46, 50, 104)
    b += rect(48, T0 - 54, 8, 54, "#c9b37a", OUT, 1.6)                        # перфопанель ребром
    for k in range(4):
        b += path(f"M48 {T0-46+k*10}h-8", None, "#5a6268", 2.4)
    b += circ(40, T0 - 20, 4, None, "#5a6268", 2)
    b += box(8, T0 - 4, 48, 8, 60, "#b0483d", "#8a3830")
    b += rect(8, T0 + 4, 8, 60, "#a03f35", OUT, 1.2)
    for k in range(5):
        b += rect(3, T0 + 8 + k * 10, 6, 3, "#d0d5d8", OUT, 0.6)
    obj("tool_cabinet_v", 1, 1, T0, b)
    b = shadow(14, T0 - 46, 50, 104)
    b += box(8, T0 - 4, 48, 8, 60, "#b0483d", "#8a3830")
    b += rect(8, T0 - 52, 48, 46, "#a99a66", OUT, 1.6)                       # перфопанель со спины
    b += rect(12, T0 - 48, 40, 38, None, "#8a7a4e", 1, 2) + line(32, T0 - 48, 32, T0 - 10, "#8a7a4e", 1)
    b += bolts([(14, T0 - 46), (50, T0 - 46), (14, T0 - 12), (50, T0 - 12)], 1.4)
    obj("tool_cabinet_b", 1, 1, T0, b)

    # ---------------- шкаф для документов
    T0 = 64

    def docs(view):
        b = shadow(14, T0 - 52, 50, 110)
        b += box(6, T0 - 58, 52, 8, 112, "#c9c3b0", "#aaa491")
        if view == "v":
            b += rect(6, T0 - 50, 8, 104, "#b3ad99", OUT, 1.2) + line(6, T0 + 2, 14, T0 + 2, OUT, 1)
            b += rect(9, T0 - 46, 3, 44, "#cfe2ea", None, 0)
            b += rect(2, T0 + 13, 5, 3, "#6a6458", None, 0) + rect(2, T0 + 37, 5, 3, "#6a6458", None, 0)
        else:
            b += line(32, T0 - 50, 32, T0 + 54, "#9a9480", 1) + rect(14, T0 - 40, 36, 10, "#ece8dc", OUT, 0.8)
        return b
    obj("doc_cabinet_v", 1, 1, T0, docs("v"))
    obj("doc_cabinet_b", 1, 1, T0, docs("b"))

    # ---------------- сейф
    T0 = 40

    def safe(view):
        b = shadow(14, T0 - 26, 50, 86)
        b += box(8, T0 - 30, 48, 10, 80, "#4a5a4e", "#3e4d42")
        if view == "v":
            b += rect(8, T0 - 20, 8, 80, "#4a5a4e", OUT, 1.2)
            b += circ(5, T0 + 8, 4, "#8a9196", OUT, 1.2) + path(f"M6 {T0+24}h-4v12h4", None, "#c9ccce", 2.2)
            b += rect(24, T0 - 10, 24, 60, None, "#33433a", 1.2, 2)
        else:
            b += rect(16, T0 - 8, 32, 52, None, "#33433a", 1.2, 2) + bolts([(20, T0 - 4), (44, T0 - 4), (20, T0 + 40), (44, T0 + 40)], 1.6, "#2a3a2e")
        return b
    obj("safe_v", 1, 1, T0, safe("v"))
    obj("safe_b", 1, 1, T0, safe("b"))

    # ---------------- аптечка на стойке
    T0 = 56

    def aid(view):
        b = ell(32, T0 + 56, 16, 4, "#000", None, 0, 0.22)
        b += rect(29, T0 + 4, 6, 52, "#6a7075", OUT, 1.4) + rect(20, T0 + 52, 24, 5, "#4a5055", OUT, 1.2, 2)
        b += box(12, T0 - 40, 40, 8, 40, "#f2f0ea", "#d6d2c6")
        if view == "v":
            b += rect(12, T0 - 32, 7, 40, "#e8e4da", OUT, 1.2) + rect(13, T0 - 18, 5, 10, "#c9372c", None, 0)
            b += rect(9, T0 - 20, 3, 10, "#9a968a", None, 0, 1)
            b += rect(30, T0 - 22, 6, 18, "#c9372c", None, 0, 0, 0.5) + rect(24, T0 - 16, 18, 6, "#c9372c", None, 0, 0, 0.5)
        else:
            b += bolts([(18, T0 - 26), (46, T0 - 26), (18, T0 + 2), (46, T0 + 2)], 1.4, "#9a968a")
            b += rect(26, T0 - 12, 12, 24, "#6a7075", OUT, 1)
        return b
    obj("first_aid_v", 1, 1, T0, aid("v"))
    obj("first_aid_b", 1, 1, T0, aid("b"))

    # ---------------- батарея отопления вдоль стены
    T0 = 30
    b = shadow(18, T0 - 18, 30, 72)
    b += line(32, T0 - 26, 32, T0 + 44, "#8a8f92", 3)
    for k in range(7):
        y = T0 - 22 + k * 9
        b += rect(22, y, 22, 8, "#e9e4d6", OUT, 1.3, 3) + line(24, y + 2, 42, y + 2, "#ffffff", 1, 0.7)
    b += rect(24, T0 + 44, 4, 10, "#5a6064", OUT, 1) + rect(38, T0 + 44, 4, 10, "#5a6064", OUT, 1)
    b += path(f"M44 {T0-20}H50V{T0-34}", None, "#8a8f92", 3) + circ(44, T0 - 20, 3, "#c94a3a", OUT, 1)
    obj("radiator_v", 1, 1, T0, b)
    META["radiator_v"]["anchors"] = {"heat": [32, T0 - 10]}
    b = shadow(10, T0 + 10, 50, 40)
    b += line(10, T0 + 2, 54, T0 + 2, "#8a8f92", 3) + line(10, T0 + 40, 54, T0 + 40, "#8a8f92", 3)
    for k in range(7):
        x = 8 + k * 7
        b += rect(x, T0 - 6, 6.4, 50, "#ddd8ca", OUT, 1.4, 3) + line(x + 3.2, T0 - 2, x + 3.2, T0 + 40, "#c8c2b2", 1.2, 0.8)
    b += rect(6, T0 + 44, 4, 10, "#5a6064", OUT, 1) + rect(54, T0 + 44, 4, 10, "#5a6064", OUT, 1)
    b += path(f"M6 {T0+2}H2V{T0-20}", None, "#8a8f92", 3)
    obj("radiator_b", 1, 1, T0, b)
    META["radiator_b"]["anchors"] = {"heat": [32, T0 - 10]}

    # ---------------- доски на стойках: планирования, кульман — ребром и со спины
    def board_edge(T0, face, frame):
        b = ell(32, T0 + 58, 14, 24, "#000", None, 0, 0.18)
        b += line(32, T0 - 8, 32, T0 + 56, "#5a6268", 2.6) + line(26, T0 + 56, 38, T0 + 56, "#3a3f43", 2.4)
        b += line(30, T0 - 36, 30, T0 + 50, "#5a6268", 2)
        b += poly([(36, T0 - 70), (44, T0 - 62), (44, T0 + 4), (36, T0 - 4)], frame, OUT, 1.6)
        b += poly([(32, T0 - 74), (36, T0 - 70), (36, T0 - 4), (32, T0 - 8)], face, OUT, 1.2)
        return b

    def board_back(T0, back):
        b = ell(32, T0 + 58, 24, 5, "#000", None, 0, 0.22)
        b += line(14, T0 - 10, 10, T0 + 56, "#5a6268", 2.6) + line(50, T0 - 10, 54, T0 + 56, "#5a6268", 2.6)
        b += line(8, T0 + 56, 20, T0 + 56, "#3a3f43", 2.4) + line(44, T0 + 56, 56, T0 + 56, "#3a3f43", 2.4)
        b += rect(2, T0 - 64, 60, 58, back, OUT, 2, 2) + line(32, T0 - 62, 32, T0 - 8, OUT, 1, 0.3) + line(4, T0 - 36, 60, T0 - 36, OUT, 1, 0.3)
        return b
    obj("plan_board_v", 1, 1, 70, board_edge(70, "#f4f6f6", "#9aa3a8"))
    obj("plan_board_b", 1, 1, 70, board_back(70, "#9aa3a8"))
    obj("drawing_board_v", 1, 1, 72, board_edge(72, "#ffffff", "#e9e6da"))
    obj("drawing_board_b", 1, 1, 72, board_back(72, "#cfcabb"))

    # ---------------- вводной электрощит
    T0 = 40

    def cab(view):
        b = shadow(14, T0 - 26, 52, 84)
        b += box(6, T0 - 32, 52, 12, 78, "#b8c0c4", "#a2abb0")
        if view == "v":
            b += rect(6, T0 - 20, 8, 78, "#b0b8bc", OUT, 1.2) + rect(2, T0 + 10, 5, 12, "#2a2e31", None, 0)
            b += poly([(34, T0 - 8), (42, T0 + 6), (26, T0 + 6)], "#d9b13b", OUT, 1.2) + path(f"M34.5 {T0-4}l-2.5 4h3l-2.5 4", None, OUT, 1.2)
        else:
            b += rect(26, T0 - 20, 12, 78, "#8a9296", OUT, 1.2)                # кабельный короб
            b += bolts([(12, T0 - 16), (52, T0 - 16), (12, T0 + 52), (52, T0 + 52)], 1.6)
        return b
    obj("cabinet_v", 1, 1, T0, cab("v"))
    obj("cabinet_b", 1, 1, T0, cab("b"))

    # ---------------- сверлильный станок
    T0 = 82
    b = shadow(14, T0 - 12, 50, 72)
    b += rect(10, T0 + 36, 48, 18, "#4e5f54", OUT, 2, 2) + rect(12, T0 + 38, 44, 4, "#fff", None, 0, 0, 0.12)
    b += rect(42, T0 - 60, 12, 98, "#a8b0b4", OUT, 2, 3) + line(45, T0 - 58, 45, T0 + 34, "#fff", 1.4, 0.5)
    b += box(10, T0 - 76, 46, 9, 26, GT, GF)
    b += box(30, T0 - 88, 24, 8, 10, "#6a7c70", "#566659")
    b += rect(14, T0 - 44, 12, 14, "#9aa3a8", OUT, 1.5) + rect(18, T0 - 30, 4, 12, "#d0d5d8", OUT, 1)
    b += path(f"M20 {T0-18}l-2 4h4z", "#d0d5d8", OUT, 0.8)
    for a in (0.6, 2.4, 4.4):
        b += line(34, T0 - 54, 34 + math.cos(a) * 11, T0 - 54 + math.sin(a) * 6, "#2a2e31", 2)
        b += circ(34 + math.cos(a) * 11, T0 - 54 + math.sin(a) * 6, 2.4, "#1d1d1d", None, 0)
    b += box(6, T0 - 2, 34, 8, 6, "#9aa1a5", "#7b8286")
    b += rect(12, T0 - 70, 9, 7, "#3a3f43", OUT, 1) + circ(16.5, T0 - 66.5, 2.2, "#c94a3a", None, 0)
    obj("drill_v", 1, 1, T0, b)
    META["drill_v"]["anchors"] = {"lamp": [16.5, T0 - 66.5], "work": [20, T0 - 10], "in": [10, T0 + 2], "out": [34, T0 + 2]}
    b = shadow(14, T0 - 12, 50, 72)
    b += rect(10, T0 + 36, 48, 18, "#4e5f54", OUT, 2, 2)
    b += box(16, T0 - 76, 36, 9, 22, GT, GF)
    b += box(18, T0 - 6, 30, 8, 6, "#9aa1a5", "#7b8286")                      # стол — за колонной
    b += rect(26, T0 - 64, 12, 98, "#a8b0b4", OUT, 2, 3) + line(29, T0 - 62, 29, T0 + 34, "#fff", 1.4, 0.5)
    b += box(22, T0 - 88, 26, 8, 10, "#6a7c70", "#566659")
    for k in range(3):
        b += line(24, T0 - 84 + k * 3, 46, T0 - 84 + k * 3, "#4a5a4e", 1)
    b += rect(44, T0 - 72, 9, 7, "#3a3f43", OUT, 1) + circ(48.5, T0 - 68.5, 2.2, "#c94a3a", None, 0)
    obj("drill_b", 1, 1, T0, b)
    META["drill_b"]["anchors"] = {"lamp": [48.5, T0 - 68.5], "work": [34, T0 - 12], "in": [22, T0 - 2], "out": [44, T0 - 2]}

    # ---------------- доска почёта и школьная доска: ребром (1×2) и со спины (2×1)
    def long_board_v(zlo, zhi, face, frame, legs, deco):
        """Доска ребром вдоль длинной оси 1×2: лицевая сторона смотрит влево, чуть видна в ракурсе."""
        T0 = zhi + 10
        y0, y1 = T0 + 10, T0 + 118
        b = rect(38, y0, 14, y1 - y0, "#000", None, 0, 4, 0.18)
        b += line(34, y0 - zlo, 34, y0, legs, 3) + line(34, y1 - zlo, 34, y1, legs, 3)
        b += line(27, y0, 41, y0, legs, 2.6) + line(27, y1, 41, y1, legs, 2.6)
        top, bot = y0 - zhi, y1 - zlo
        b += poly([(22, top + 6), (34, top), (34, bot - 6), (22, bot)], face, OUT, 1.4)
        b += rect(34, top, 7, bot - top - 6, frame, OUT, 1.4, 1)
        n = 5
        for k in range(n):
            yy = top + 14 + k * (bot - top - 30) / n
            b += deco(yy)
        return T0, b

    def photo(yy):
        return rect(25, yy, 7, 9, "#ece8dc", OUT, 0.6) + circ(28.5, yy + 3.5, 1.6, "#d8a47c", None, 0)

    def chalk(yy):
        return line(25, yy + 2, 32, yy, "#e8efe8", 1, 0.8) + line(25, yy + 6, 31, yy + 4, "#e8efe8", 1, 0.6)
    tv, bv = long_board_v(30, 118, "#a8322b", "#6a2420", "#5a4636", photo)
    obj("honor_board_v", 1, 2, tv, bv)
    tv, bv = long_board_v(68, 134, "#2f5a44", "#8c6a44", "#5a4a3a", chalk)
    obj("chalkboard_v", 1, 2, tv, bv)
    T0 = 62
    b = shadow(14, T0 + 34, 116, 26)
    b += rect(14, T0 + 30, 6, 30, "#5a4636", OUT, 1.5) + rect(108, T0 + 30, 6, 30, "#5a4636", OUT, 1.5)
    b += rect(4, T0 - 54, 120, 88, "#6a2420", OUT, 2.4, 3) + rect(12, T0 - 46, 104, 72, None, "#5a1e1a", 1.4, 2)
    b += line(64, T0 - 46, 64, T0 + 26, "#5a1e1a", 1.2)
    obj("honor_board_b", 2, 1, T0, b)
    T0 = 76
    b = ell(64, T0 + 58, 54, 6, "#000", None, 0, 0.22)
    b += line(14, T0 - 6, 10, T0 + 56, "#5a4a3a", 3.2) + line(114, T0 - 6, 118, T0 + 56, "#5a4a3a", 3.2)
    b += line(4, T0 + 56, 20, T0 + 56, "#3a3027", 3) + line(108, T0 + 56, 124, T0 + 56, "#3a3027", 3)
    b += rect(2, T0 - 70, 124, 66, "#7a5c3c", OUT, 2, 3) + rect(10, T0 - 62, 108, 50, None, "#5a4430", 1.2, 2)
    b += line(64, T0 - 62, 64, T0 - 12, "#5a4430", 1.2)
    obj("chalkboard_b", 2, 1, T0, b)

    # ---------------- парта: ребром (1×2, ученики слева) и со спины (ученики сверху)
    T0 = 40
    H = 128
    b = shadow(12, T0 + 4, 52, 120)
    for cy in (T0 + 20, T0 + 84):
        b += ell(10, cy + 22, 10, 4, "#000", None, 0, 0.2)
        b += rect(0, cy, 16, 22, "#b58a58", OUT, 1.4, 2) + rect(-2, cy - 4, 8, 28, "#b58a58", OUT, 1.4, 2)
    b += line(24, T0 + 8, 24, T0 + 120, "#4a5156", 3) + line(52, T0 + 8, 52, T0 + 120, "#4a5156", 3)
    b += box(16, T0 - 2, 44, 112, 10, "#d2b383", "#a8845a")
    b += line(16, T0 + 54, 60, T0 + 54, "#a8845a", 1.2)
    b += rect(22, T0 + 10, 14, 22, "#e9e4d2", OUT, 1, 1) + rect(22, T0 + 70, 14, 22, "#3d6a4e", OUT, 1, 1)
    b += line(42, T0 + 36, 48, T0 + 46, "#2f4a68", 1.6)
    obj("school_desk_v", 1, 2, T0, b)
    T0 = 92
    b = shadow(10, T0 - 10, 120, 70)
    for cx in (32, 96):                                                          # стулья — за партой
        b += rect(cx - 13, T0 - 46, 26, 14, "#b58a58", OUT, 1.6, 3)
        b += rect(cx - 14, T0 - 34, 28, 8, "#a07a4c", OUT, 1.4, 2)
    b += line(10, T0 + 30, 10, T0 + 60, "#4a5156", 3) + line(118, T0 + 30, 118, T0 + 60, "#4a5156", 3)
    b += line(10, T0 + 52, 118, T0 + 52, "#4a5156", 2.4)
    b += box(4, T0 + 2, 120, 20, 10, "#d2b383", "#8c6a44")
    b += rect(8, T0 + 32, 112, 16, "#8c6a44", OUT, 1.4)                        # передняя стенка
    b += rect(18, T0 + 6, 20, 10, "#e9e4d2", OUT, 1, 1) + rect(84, T0 + 6, 24, 12, "#3d6a4e", OUT, 1, 1)
    obj("school_desk_b", 2, 1, T0, b)

    # ---------------- стол ИТР со спины: стул сверху, монитор задней стенкой
    T0 = 92
    b = shadow(10, T0 + 4, 120, 58)
    b += rect(83, T0 - 52, 26, 22, "#3d4652", OUT, 1.6, 6) + ell(96, T0 - 30, 15, 6, "#3d4652", OUT, 1.6)
    b += box(2, T0 + 2, 124, 30, 30, "#b08a5e", "#8c6a44")
    b += rect(8, T0 + 34, 112, 22, "#7e5f3e", OUT, 1.4)                         # стенка стола
    b += rect(76, T0 - 8, 40, 26, "#2a2e31", OUT, 1.8, 3) + rect(92, T0 + 18, 8, 6, "#3a3f43", OUT, 1)
    b += rect(80, T0 - 4, 32, 6, "#3a3f43", None, 0, 1)
    b += rect(80, T0 + 22, 24, 3, "#3a3f43", None, 0) + rect(52, T0 + 8, 20, 14, "#f4f1e6", OUT, 1, 0)
    b += path(f"M14 {T0+20}L18 {T0-6}L26 {T0-12}", None, "#2a2e31", 2.2) + path(f"M30 {T0-14}L20 {T0-18}L18 {T0-8}Z", "#3d6a4e", OUT, 1.2) + ell(14, T0 + 21, 6, 2, "#2a2e31", None, 0)
    b += rect(30, T0 + 8, 16, 10, "#c94a3a", OUT, 1.2, 2)
    obj("office_desk_b", 2, 1, T0, b)
    META["office_desk_b"]["anchors"] = {"screen": [96, T0 + 4]}

    # ---------------- диван и скамейка со спины: спинка ближе к нам
    T0 = 26
    SOFA, SOFA_D = "#6a7a52", "#55633f"
    b = shadow(12, T0 + 4, 120, 58)
    b += rect(6, T0 - 6, 116, 30, SOFA, OUT, 2, 5)
    b += rect(14, T0 - 2, 48, 22, "#7a8a60", OUT, 1.2, 4) + rect(66, T0 - 2, 48, 22, "#7a8a60", OUT, 1.2, 4)
    b += rect(2, T0 - 4, 12, 44, SOFA_D, OUT, 2, 5) + rect(114, T0 - 4, 12, 44, SOFA_D, OUT, 2, 5)
    b += rect(6, T0 + 20, 116, 34, SOFA_D, OUT, 2, 6)
    b += rect(10, T0 + 26, 108, 2, "#000", None, 0, 0, 0.12)
    b += rect(8, T0 + 54, 6, 8, "#2e3236", None, 0) + rect(114, T0 + 54, 6, 8, "#2e3236", None, 0)
    obj("sofa_b", 2, 1, T0, b)
    T0 = 22
    b = shadow(12, T0 + 6, 120, 52)
    for k, y in enumerate((T0 - 2, T0 + 7, T0 + 16)):
        b += rect(4, y, 120, 8, "#a07a4c" if k % 2 == 0 else "#946f43", OUT, 1.5)
    b += rect(12, T0 + 20, 6, 42, "#3a3e42", OUT, 1) + rect(110, T0 + 20, 6, 42, "#3a3e42", OUT, 1)
    for k, y in enumerate((T0 + 26, T0 + 35)):
        b += rect(4, y, 120, 8, "#a07a4c" if k % 2 == 0 else "#946f43", OUT, 1.5)
    obj("bench_b", 2, 1, T0, b)

    # ---------------- верстак слесарный со спины (тиски у дальнего края)
    T0 = 30
    b = shadow(12, T0 + 4, 120, 64)
    b += box(2, T0 + 4, 124, 26, 30, "#a8845a", "#7a5d3e")
    for x in (20, 46, 74, 100):
        b += line(x, T0 + 5, x, T0 + 29, "#8f6f48", 1.2)
    b += rect(10, T0 + 34, 108, 22, "#6b5236", OUT, 1.2)
    b += rect(92, T0 - 4, 26, 12, "#3d5a7a", OUT, 1.5) + rect(88, T0 - 8, 34, 5, "#8b9296", OUT, 1.2)
    b += rect(14, T0 + 8, 18, 12, "#5e7364", OUT, 1.5, 4)
    b += line(50, T0 + 16, 68, T0 + 10, "#7a5c38", 3) + rect(46, T0 + 13, 7, 7, "#5c6267", OUT, 1)
    obj("workbench_b", 2, 1, T0, b)

    # ---------------- токарный станок со спины (рабочий сверху): видна задняя сторона станины
    T0 = 44
    b = shadow(12, T0 - 8, 186, 82)
    b += rect(4, T0 + 40, 44, 22, "#4e5f54", OUT, 2) + rect(146, T0 + 40, 44, 22, "#4e5f54", OUT, 2)
    b += rect(48, T0 + 42, 98, 18, "#3a3f43", OUT, 2)
    b += rect(4, T0 + 4, 186, 18, "#8b9296", OUT, 2)
    b += line(4, T0 + 9, 190, T0 + 9, "#b2b9bd", 1.6) + line(4, T0 + 17, 190, T0 + 17, "#b2b9bd", 1.6)
    b += rect(4, T0 + 22, 186, 20, "#5c6267", OUT, 2) + rect(60, T0 + 26, 120, 6, "#6a7075", None, 0, 1)
    b += box(138, T0 - 18, 52, 22, 34, GT, GF)                                  # передняя бабка справа (отражено)
    for k in range(4):
        b += line(142, T0 + 8 + k * 6, 186, T0 + 8 + k * 6, "#4f6056", 1.2)
    b += rect(150, T0 - 30, 22, 12, "#3a3f43", OUT, 1.2)
    b += rect(108, T0 - 4, 18, 14, "#9ca3a7", OUT, 1.6, 2)
    b += box(64, T0 - 6, 40, 14, 12, "#6f8275", "#55665a")                       # суппорт
    b += box(8, T0 - 2, 38, 16, 18, GT, GF)                                      # задняя бабка
    b += rect(176, T0 - 34, 8, 16, "#3a3f43", OUT, 1) + circ(180, T0 - 38, 3, "#c94a3a", None, 0)
    obj("lathe_b", 3, 1, T0, b)
    META["lathe_b"]["anchors"] = {"lamp": [180, T0 - 38], "work": [116, T0 + 2], "bar": [94, T0 + 60], "out": [40, T0 + 40]}

    # ---------------- станок с ЧПУ со спины: глухой кожух, вентиляция, кабельный канал
    T0 = 66
    b = shadow(12, T0 - 30, 186, 96)
    b += box(28, T0 - 56, 160, 16, 98, "#d8dbdc", "#bcc1c3")
    for k in range(6):
        b += line(40, T0 - 30 + k * 10, 120, T0 - 30 + k * 10, "#a7adb0", 2)
    b += rect(130, T0 - 30, 46, 40, "#9aa3a8", OUT, 1.4, 2) + rect(134, T0 - 26, 38, 32, None, "#7a8388", 1, 1)
    b += rect(34, T0 + 46, 150, 10, "#3d5a7a", OUT, 1.6)
    b += box(2, T0 - 64, 24, 10, 80, "#3d4652", "#2e3640")
    b += rect(140, T0 - 70, 6, 14, "#3a3f43", OUT, 1) + circ(143, T0 - 74, 4, "#6fbf86", OUT, 1)
    obj("cnc_lathe_b", 3, 1, T0, b)
    META["cnc_lathe_b"]["anchors"] = {"lamp": [143, T0 - 74], "work": [100, T0 - 6], "in": [40, T0 + 30], "out": [170, T0 + 30]}

    # ---------------- фрезерный со спины
    T0 = 74
    b = shadow(14, T0 - 10, 122, 76)
    b += box(6, T0 - 8, 118, 14, 10, "#9aa1a5", "#7b8286")
    b += box(40, T0 - 62, 54, 10, 72, GT, GF)
    for k in range(5):
        b += line(46, T0 - 44 + k * 10, 88, T0 - 44 + k * 10, "#4f6056", 1.4)
    b += box(30, T0 - 70, 74, 12, 22, GT, GF)
    b += box(6, T0 - 66, 26, 10, 18, "#6a7c70", "#566659")
    b += box(44, T0 + 16, 44, 8, 34, GT, GF)
    b += rect(48, T0 + 52, 36, 8, "#4e5f54", OUT, 1.5)
    b += rect(36, T0 - 48, 14, 10, "#3a3f43", OUT, 1.2) + circ(40, T0 - 43, 2.6, "#c94a3a", None, 0)
    obj("mill_b", 2, 1, T0, b)
    META["mill_b"]["anchors"] = {"lamp": [40, T0 - 43], "work": [64, T0 - 12], "in": [110, T0 - 6], "out": [18, T0 - 6]}

    # ---------------- сварочный пост со спины: аппарат и баллон слева-спереди
    T0 = 46
    b = shadow(12, T0, 122, 64)
    b += box(40, T0 + 2, 84, 26, 30, "#6a7074", "#4f5458")
    for yy in range(3):
        for xx in range(7):
            b += circ(48 + xx * 11, T0 + 8 + yy * 7, 1.6, "#3a3e42", None, 0)
    b += rect(44, T0 + 34, 4, 22, "#3a3e42", None, 0) + rect(116, T0 + 34, 4, 22, "#3a3e42", None, 0)
    b += rect(2, T0 - 44, 10, 46, "#4a7f78", OUT, 1.6, 4) + rect(3, T0 - 50, 8, 8, "#3a3f43", OUT, 1.2, 2)
    b += box(6, T0 - 8, 30, 10, 46, "#d9b13b", "#b8932c")
    for k in range(4):
        b += line(10, T0 + 10 + k * 6, 32, T0 + 10 + k * 6, "#8a6e20", 1.2)
    b += circ(12, T0 + 12, 2.4, "#6fbf86", None, 0)
    b += path(f"M30 {T0+14}Q52 {T0+40} 84 {T0+14}", None, "#1d1d1d", 2.4)
    obj("weld_post_b", 2, 1, T0, b)
    META["weld_post_b"]["anchors"] = {"lamp": [12, T0 + 12], "work": [88, T0 + 10], "in": [114, T0 + 4], "out": [56, T0 + 4], "flash": [88, T0 + 10]}

    # ---------------- сборочный верстак со спины
    T0 = 40
    b = shadow(12, T0 + 4, 120, 62)
    b += box(2, T0 + 4, 124, 22, 32, "#7d8a92", "#626e76")
    b += rect(8, T0 + 30, 112, 26, None, "#4a555c", 1.4) + line(64, T0 + 30, 64, T0 + 56, "#4a555c", 1.2)
    b += rect(36, T0 - 34, 12, 40, "#4a7f9a", OUT, 1.6) + box(28, T0 - 40, 28, 6, 10, "#5a8fa8", "#4a7f9a")
    b += rect(96, T0 - 2, 22, 10, "#3d5a7a", OUT, 1.5) + rect(92, T0 + 2, 30, 4, "#8b9296", OUT, 1.2)
    for k in range(3):
        b += rect(8 + k * 7, T0 + 8, 6, 8, ["#c94a3a", "#d9b13b", "#4d7fb0"][k], OUT, 0.8, 1)
    b += circ(22, T0 - 45, 2.6, "#1d1d1d", None, 0) + line(36, T0 - 34, 22, T0 - 44, "#2a2e31", 2.4)
    obj("assembly_table_b", 2, 1, T0, b)
    META["assembly_table_b"]["anchors"] = {"lamp": [22, T0 - 45], "work": [64, T0 + 10], "in": [112, T0 + 12], "out": [18, T0 + 18]}

    # ---------------- испытательный стенд со спины
    T0 = 54
    b = shadow(12, T0 - 20, 120, 80)
    b += box(4, T0 - 2, 120, 14, 50, "#3d6a9a", "#2e5478")
    b += rect(10, T0 + 16, 108, 22, None, "#24405c", 1.4, 2)
    b += box(82, T0 - 40, 34, 10, 40, "#9aa3a8", "#7a8388")
    b += box(8, T0 - 44, 22, 8, 40, "#2e3440", "#232830")
    for k in range(4):
        b += line(11, T0 - 32 + k * 6, 27, T0 - 32 + k * 6, "#3d4652", 1.2)
    b += circ(20, T0 - 22, 2, "#e8c34a", None, 0)
    b += path(f"M66 {T0-20}H82M34 {T0-8}H66V{T0-20}", None, "#5a6064", 3)
    obj("test_stand_b", 2, 1, T0, b)
    META["test_stand_b"]["anchors"] = {"lamp": [20, T0 - 22], "work": [72, T0 + 4], "in": [16, T0 + 30], "out": [112, T0 + 30], "gauge": [98, T0 - 30], "gauge2": [98, T0 - 30], "screen": [19, T0 - 33]}

    # ---------------- печь 2×2: дверца слева / сзади
    T0 = 54
    b = shadow(16, T0 - 20, 126, 140)
    b += box(16, T0 - 36, 90, 14, 128, "#9a8f84", "#82786e")
    for yy in range(6):
        for xx in range(5):
            b += rect(20 + xx * 17 + (yy % 2) * 8, T0 - 14 + yy * 16, 15, 13, None, "#8a7e72", 0.8)
    b += rect(4, T0 + 4, 14, 78, "#6a5a4e", OUT, 2, 3) + rect(6, T0 + 26, 10, 22, "#2a1d16", OUT, 1.4, 2)
    b += rect(1, T0 + 52, 5, 14, "#4f5458", OUT, 0.8, 1)
    b += box(106, T0 - 20, 30, 10, 102, "#8e9fa8", "#6f8089")
    b += rect(110, T0 + 0, 22, 14, "#2a2e31", OUT, 1) + rect(112, T0 + 2, 18, 6, "#c94a3a", None, 0, 0, 0.8)
    for k in range(3):
        b += circ(114 + k * 7, T0 + 22, 2.6, ["#6fbf86", "#d9b13b", "#c94a3a"][k], OUT, 0.8)
    b += box(30, T0 - 54, 58, 8, 14, "#7a7066", "#5a524a") + rect(48, T0 - 70, 22, 16, "#6a625a", OUT, 1.6)
    obj("furnace_v", 2, 2, T0, b)
    META["furnace_v"]["anchors"] = {"lamp": [114, T0 + 22], "glow": [6, T0 + 26, 10, 22], "in": [10, T0 + 92], "out": [40, T0 + 92]}
    b = shadow(16, T0 - 20, 126, 140)
    b += box(36, T0 - 36, 98, 14, 128, "#9a8f84", "#82786e")
    for yy in range(6):
        for xx in range(5):
            b += rect(40 + xx * 18 + (yy % 2) * 8, T0 - 14 + yy * 16, 16, 13, None, "#8a7e72", 0.8)
    b += box(4, T0 - 20, 30, 10, 102, "#8e9fa8", "#6f8089")
    b += rect(8, T0 + 0, 22, 14, "#2a2e31", OUT, 1)
    b += circ(14, T0 + 22, 2.6, "#6fbf86", OUT, 0.8)
    b += path(f"M30 {T0+40}H40", None, "#2a2e31", 3)
    b += box(56, T0 - 54, 58, 8, 14, "#7a7066", "#5a524a") + rect(74, T0 - 70, 22, 16, "#6a625a", OUT, 1.6)
    obj("furnace_b", 2, 2, T0, b)
    META["furnace_b"]["anchors"] = {"lamp": [14, T0 + 22], "in": [56, T0 + 92], "out": [112, T0 + 92]}

    # ---------------- покрасочная камера 2×2: проём слева / сзади
    T0 = 64
    b = shadow(16, T0 - 26, 126, 138)
    b += box(4, T0 - 50, 132, 12, 120, "#c9cfd2", "#b0b8bc")
    for k in range(1, 6):
        b += line(4 + k * 22, T0 - 38, 4 + k * 22, T0 + 70, "#9aa3a8", 1.2)
    b += rect(4, T0 - 38, 14, 108, "#5a6268", OUT, 1.6)
    for k in range(8):
        b += rect(6, T0 - 34 + k * 13, 10, 11, "#d8e4ea", "#9fb0b8", 0.8, 0, 0.45)
    b += box(48, T0 - 74, 44, 8, 16, "#9aa3a8", "#7b8286") + rect(60, T0 - 86, 20, 12, "#8a9196", OUT, 1.4)
    b += rect(116, T0 + 0, 14, 22, "#3a3f43", OUT, 1.2) + circ(123, T0 + 6, 2.4, "#6fbf86", None, 0)
    obj("paint_booth_v", 2, 2, T0, b)
    META["paint_booth_v"]["anchors"] = {"lamp": [123, T0 + 6], "work": [40, T0 + 20], "in": [12, T0 + 64], "out": [40, T0 + 64], "mist": [12, T0 + 10]}
    b = shadow(16, T0 - 26, 126, 138)
    b += box(4, T0 - 50, 132, 12, 120, "#c9cfd2", "#b0b8bc")
    for k in range(1, 6):
        b += line(4 + k * 22, T0 - 38, 4 + k * 22, T0 + 70, "#9aa3a8", 1.2)
    b += box(50, T0 - 74, 40, 8, 16, "#9aa3a8", "#7b8286") + rect(60, T0 - 86, 20, 12, "#8a9196", OUT, 1.4)
    b += rect(58, T0 - 30, 24, 100, "#9aa3a8", OUT, 1.4)
    b += rect(10, T0 + 0, 14, 22, "#3a3f43", OUT, 1.2) + circ(17, T0 + 6, 2.4, "#6fbf86", None, 0)
    obj("paint_booth_b", 2, 2, T0, b)
    META["paint_booth_b"]["anchors"] = {"lamp": [17, T0 + 6], "in": [110, T0 + 64], "out": [20, T0 + 64]}


def objects_v15():
    """1.5: контейнер для стружки, ленточная пила (три вида), декор, стружка на полу, веник."""
    # --- контейнер для стружки 1×1 на колёсах
    T0 = 34
    b = shadow(14, T0 + 8, 50, 52)
    b += path(f"M8 {T0+2}L56 {T0+2}L52 {T0+48}L12 {T0+48}Z", "#5a7a9a", OUT, 2)
    b += path(f"M8 {T0+2}L56 {T0+2}L54 {T0+10}L10 {T0+10}Z", "#6f8fae", OUT, 1.4)
    b += rect(12, T0 - 4, 40, 10, "#3a3f43", OUT, 1.4, 2)
    for k in range(5):
        x = 16 + k * 7
        b += path(f"M{x} {T0+2}q3 -6 6 -2t4 -3", None, "#c9ccce", 1.3) + path(f"M{x+2} {T0}q2 -4 5 -1", None, "#c7a46a", 1.1)
    b += rect(14, T0 + 18, 36, 12, "#e8e4d6", OUT, 0.8, 1) + path(f"M18 {T0+24}h28", None, "#5a6468", 1.4)
    for x in (16, 48):
        b += circ(x, T0 + 52, 4.5, "#2a2e31", OUT, 1) + circ(x, T0 + 52, 1.6, "#9aa1a5", None, 0)
    obj("chip_bin", 1, 1, T0, b)
    META["chip_bin"]["anchors"] = {"fill": [12, T0 - 4, 40, 12]}

    # --- ленточнопильный станок 2×1: станина, рама с лентой, тиски, рольганг
    GT, GF = "#7d9283", "#5e7364"
    T0 = 60
    b = shadow(12, T0 - 8, 122, 72)
    b += box(4, T0 + 2, 120, 16, 40, GT, GF)
    b += rect(10, T0 + 22, 30, 32, None, "#4f6056", 1.4) + circ(34, T0 + 38, 2, "#c9ccce", None, 0)
    b += rect(74, T0 + 4, 46, 10, "#8b9296", OUT, 1.4)
    for k in range(5):
        b += circ(78 + k * 10, T0 + 9, 3, "#c9ccce", OUT, 0.8)
    b += box(30, T0 - 44, 46, 10, 34, "#d9a43a", "#b8862c")
    b += rect(38, T0 - 30, 30, 18, "#3a3f43", None, 0, 2, 0.5)
    b += line(52, T0 - 34, 52, T0 + 4, "#d0d5d8", 2.2) + line(52, T0 - 34, 52, T0 + 4, "#ffffff", 0.8, 0.8)
    b += rect(42, T0 - 2, 22, 8, "#5a6268", OUT, 1.2) + rect(36, T0 + 2, 34, 6, "#4a5156", OUT, 1)
    b += rect(6, T0 - 6, 14, 10, "#3a3f43", OUT, 1) + circ(10, T0 - 1, 2.2, "#c94a3a", None, 0) + circ(16, T0 - 1, 2.2, "#6fbf86", None, 0)
    b += rect(80, T0 - 2, 34, 6, "#9aa1a5", OUT, 1, 2)
    obj("band_saw", 2, 1, T0, b)
    META["band_saw"]["anchors"] = {"blade": [52, T0 - 34, 52, T0 + 4], "lamp": [10, T0 - 1], "out": [96, T0 + 2]}
    T0 = 60
    b = shadow(12, T0 - 8, 52, 136)
    b += box(8, T0 + 2, 48, 82, 40, GT, GF)
    b += rect(10, T0 + 6, 10, 74, "#8b9296", OUT, 1.2)
    b += box(20, T0 - 30, 34, 50, 30, "#d9a43a", "#b8862c")
    b += line(36, T0 - 20, 36, T0 + 30, "#d0d5d8", 2.2)
    b += rect(14, T0 + 70, 36, 8, "#9aa1a5", OUT, 1, 2)
    b += rect(40, T0 + 92, 14, 10, "#3a3f43", OUT, 1) + circ(44, T0 + 97, 2.2, "#c94a3a", None, 0)
    obj("band_saw_v", 1, 2, T0, b)
    META["band_saw_v"]["anchors"] = {"blade": [36, T0 - 20, 36, T0 + 30], "lamp": [44, T0 + 97], "out": [16, T0 + 100]}
    T0 = 60
    b = shadow(12, T0 - 8, 122, 72)
    b += box(4, T0 + 2, 120, 16, 40, GT, GF)
    b += rect(8, T0 + 4, 46, 10, "#8b9296", OUT, 1.4)
    b += box(52, T0 - 44, 46, 10, 34, "#c9962c", "#a8782a")
    for k in range(4):
        b += line(56, T0 - 28 + k * 6, 94, T0 - 28 + k * 6, "#8a6a20", 1.2)
    b += rect(106, T0 - 6, 14, 10, "#3a3f43", OUT, 1) + circ(112, T0 - 1, 2.2, "#c94a3a", None, 0)
    obj("band_saw_b", 2, 1, T0, b)
    META["band_saw_b"]["anchors"] = {"lamp": [112, T0 - 1], "out": [30, T0 + 2]}

    # --- стенд «Охрана труда»
    T0 = 70
    b = ell(32, T0 + 58, 22, 5, "#000", None, 0, 0.22)
    b += line(32, T0 - 4, 32, T0 + 54, "#5a6268", 3) + line(20, T0 + 56, 44, T0 + 56, "#3a3f43", 2.6)
    b += rect(4, T0 - 64, 56, 62, "#f4f1e6", OUT, 2, 2) + rect(4, T0 - 64, 56, 10, "#2f6a3e", OUT, 1.4, 2)
    b += rect(9, T0 - 50, 22, 20, "#ffffff", OUT, 1) + poly([(20, T0 - 48), (29, T0 - 32), (11, T0 - 32)], "#e2b73a", OUT, 1) + path(f"M20 {T0-43}v6M20 {T0-35}v1", None, OUT, 1.6)
    b += rect(34, T0 - 50, 22, 20, "#ffffff", OUT, 1) + circ(45, T0 - 40, 8, "#c94a3a", OUT, 1) + line(39, T0 - 46, 51, T0 - 34, "#ffffff", 2)
    b += rect(9, T0 - 26, 47, 20, "#ffffff", OUT, 1) + circ(18, T0 - 16, 6, "#3d6a9a", OUT, 1) + path(f"M28 {T0-20}h24M28 {T0-15}h20M28 {T0-10}h22", None, "#6a6458", 1.2)
    obj("safety_stand", 1, 1, T0, b)

    # --- пальма в кадке
    T0 = 56
    b = ell(34, T0 + 58, 18, 5, "#000", None, 0, 0.28)
    b += path(f"M18 {T0+24}H46L42 {T0+56}H22Z", "#7a5a3a", OUT, 2) + rect(16, T0 + 20, 32, 7, "#8a6a46", OUT, 2)
    b += path(f"M32 {T0+22}Q29 {T0-8} 33 {T0-34}", None, "#6a4a2c", 5) + path(f"M31 {T0+10}h4M31 {T0}h4M32 {T0-12}h4M32 {T0-24}h3", None, "#4f3820", 1.2)
    top = (33, T0 - 36)
    fronds = [(-30, 6, "#3f7f35"), (30, 4, "#4a8f3c"), (-26, -14, "#5aa04a"), (27, -16, "#3f7f35"), (-10, -28, "#68b058"), (12, -30, "#5aa04a"), (-32, 22, "#4a8f3c"), (32, 20, "#5aa04a")]
    for (dx, dy, c) in fronds:
        x2, y2 = top[0] + dx, top[1] + dy
        mx, my = top[0] + dx * 0.5, top[1] + dy * 0.5 - 10
        b += path(f"M{top[0]} {top[1]}Q{mx} {my-5} {x2} {y2}Q{mx} {my+5} {top[0]} {top[1]+2}Z", c, OUT, 1.2)
        b += path(f"M{top[0]} {top[1]+1}Q{mx} {my} {x2} {y2}", None, "#2f5f28", 0.8, 0.7)
    obj("palm", 1, 1, T0, b)

    # --- аквариум 2×1 на тумбе
    T0 = 54
    b = shadow(12, T0 - 6, 120, 68)
    b += box(6, T0 + 8, 116, 12, 34, "#6a5236", "#4f3d28")
    b += rect(10, T0 - 40, 108, 48, "#5fa8c8", OUT, 2, 2) + rect(10, T0 - 40, 108, 8, "#2a2e31", OUT, 1.4, 2)
    b += rect(12, T0 - 30, 104, 36, "#7fc0dc", None, 0, 0, 0.6)
    b += path(f"M14 {T0+6}Q30 {T0-2} 46 {T0+6}T80 {T0+6}T114 {T0+6}", "#c9b37a", None, 0)
    for (x, c) in [(30, "#e2752c"), (62, "#e2b73a"), (88, "#c94a3a")]:
        b += ell(x, T0 - 14 + (x % 7), 6, 3.4, c, OUT, 0.8) + poly([(x + 5, T0 - 14 + (x % 7)), (x + 10, T0 - 18 + (x % 7)), (x + 10, T0 - 10 + (x % 7))], c, OUT, 0.8)
    b += path(f"M22 {T0+4}Q18 {T0-14} 24 {T0-24}M100 {T0+4}Q106 {T0-12} 98 {T0-22}", None, "#3f8a3c", 2.4)
    for k in range(4):
        b += circ(106, T0 - 8 - k * 7, 1.6 + k * 0.3, "#ffffff", None, 0, 0.7)
    obj("aquarium", 2, 1, T0, b)
    META["aquarium"]["anchors"] = {"bubbles": [106, T0 - 8]}

    # --- ковёр 2×1 (и вдоль 1×2)
    def rug(w, h):
        b = rect(4, 6, w - 8, h - 8, "#8a2a24", OUT, 1.4, 2)
        b += rect(9, 11, w - 18, h - 18, None, "#d9b13b", 1.6, 1)
        b += rect(15, 17, w - 30, h - 30, None, "#c9a45a", 1, 1, 0.8)
        cx, cy = w / 2, h / 2
        b += poly([(cx, cy - 12), (cx + 12, cy), (cx, cy + 12), (cx - 12, cy)], "#3d5a7a", "#d9b13b", 1.2)
        for x in range(8, w - 6, 6):
            b += line(x, 2, x, 6, "#d9b13b", 1) + line(x, h - 2, x, h - 6, "#d9b13b", 1)
        return b
    obj("rug", 2, 1, 0, rug(128, 64), pad=0)
    META["rug"]["oy"] = 64
    obj("rug_v", 1, 2, 0, rug(64, 128), pad=0)
    META["rug_v"]["oy"] = 128

    # --- книжный шкаф
    T0 = 66
    b = shadow(14, T0 - 52, 50, 110)
    b += box(6, T0 - 58, 52, 8, 112, "#7a5a3a", "#6a4c30")
    cols = ["#8a2a24", "#3d5a7a", "#c9a45a", "#4a7a4a", "#5a4a6a", "#b08a5e", "#2f4a68", "#7a3a3a"]
    for row in range(4):
        y = T0 - 46 + row * 26
        b += rect(10, y + 20, 44, 3, "#4f3d28", None, 0)
        x = 11
        k = 0
        while x < 50:
            ww = 3.4 + ((row * 3 + k) % 3)
            b += rect(x, y + (k % 2), ww, 20 - (k % 2), cols[(row * 5 + k) % 8], OUT, 0.5)
            x += ww + 0.6
            k += 1
    obj("bookcase", 1, 1, T0, b)

    # --- телевизор на тумбе
    T0 = 44
    b = shadow(14, T0 + 2, 52, 60)
    b += box(6, T0 + 4, 52, 16, 36, "#6a6d74", "#55585e")
    b += rect(12, T0 + 26, 40, 10, None, "#3a3d42", 1.2)
    b += rect(8, T0 - 36, 48, 36, "#1d2024", OUT, 2, 3) + rect(11, T0 - 33, 42, 28, "#3d6a8a", None, 0, 1)
    b += path(f"M14 {T0-12}l8 -8 6 5 8 -10 10 9", None, "#8fcf78", 1.6) + rect(13, T0 - 31, 14, 4, "#ffffff", None, 0, 0, 0.35)
    b += rect(28, T0, 8, 5, "#2a2e31", None, 0)
    obj("tv", 1, 1, T0, b)
    META["tv"]["anchors"] = {"screen": [32, T0 - 19]}

    # --- переходящее знамя
    T0 = 80
    b = ell(32, T0 + 58, 14, 4, "#000", None, 0, 0.25)
    b += rect(22, T0 + 48, 20, 8, "#5a4030", OUT, 1.2, 2)
    b += line(30, T0 - 74, 30, T0 + 50, "#b08a5e", 2.6) + circ(30, T0 - 76, 3, "#d9b13b", OUT, 1)
    b += path(f"M31 {T0-70}H58Q54 {T0-46} 58 {T0-20}H31Z", "#b0282a", OUT, 1.6)
    b += path(f"M34 {T0-22}h22", None, "#d9b13b", 2.4)
    for k in range(6):
        b += line(35 + k * 4, T0 - 20, 35 + k * 4, T0 - 15, "#d9b13b", 1.2)
    b += poly([(44, T0 - 62), (46, T0 - 57), (51, T0 - 57), (47, T0 - 54), (49, T0 - 49), (44, T0 - 52), (39, T0 - 49), (41, T0 - 54), (37, T0 - 57), (42, T0 - 57)], "#d9b13b", None, 0)
    b += path(f"M37 {T0-42}h14M37 {T0-36}h12M37 {T0-30}h14", None, "#f2d58a", 1.2)
    obj("pennant", 1, 1, T0, b)

    # --- стружка и грязь на полу (эффекты 64×64)
    def chips(seed):
        rnd = random.Random(seed)
        d = ""
        for k in range(9):
            x, y = rnd.uniform(8, 56), rnd.uniform(8, 56)
            c = rnd.choice(["#c9ccce", "#aab1b5", "#c7a46a", "#9aa1a5", "#d8dcde"])
            r = rnd.uniform(2.5, 5)
            d += path(f"M{x:.1f} {y:.1f}q{r:.1f} {-r:.1f} {r*1.6:.1f} 0t{r*1.4:.1f} {r*0.4:.1f}", None, "#4a4f55", 2.4, 0.6)
            d += path(f"M{x:.1f} {y:.1f}q{r:.1f} {-r:.1f} {r*1.6:.1f} 0t{r*1.4:.1f} {r*0.4:.1f}", None, c, 1.4)
        for k in range(10):
            d += circ(rnd.uniform(6, 58), rnd.uniform(6, 58), rnd.uniform(0.8, 1.6), "#5a5f64", None, 0, 0.6)
        return d
    for k in range(3):
        save(f"assets/fx/chips_{k}.svg", 64, 64, chips(70 + k))
    save("assets/fx/dust.svg", 64, 64, '<defs><radialGradient id="g" cx="50%" cy="50%" r="50%"><stop offset="0" stop-color="#6a5a44" stop-opacity="0.55"/><stop offset="1" stop-color="#6a5a44" stop-opacity="0"/></radialGradient></defs><ellipse cx="32" cy="32" rx="30" ry="26" fill="url(#g)"/>')

    # --- иконки «помещение рамкой»: план комнаты с полом и дверью
    for key, fl, ln in [("concrete", "#a9a59c", "#8f8b83"), ("tile", "#e6ebec", "#c2c9cc"), ("lino", "#c9b38a", "#ab9670")]:
        d = rect(6, 6, 52, 52, fl, None, 0)
        for k in range(1, 4):
            d += line(6 + k * 13, 6, 6 + k * 13, 58, ln, 1) + line(6, 6 + k * 13, 58, 6 + k * 13, ln, 1)
        d += rect(4, 4, 56, 56, None, "#5a4a3e", 6) + rect(4, 4, 56, 56, None, "#6e5a4c", 3.4)
        d += rect(26, 56, 12, 6, "#c98a3a", OUT, 1.2)
        d += path("M18 30h28M32 18v24", None, "#3d5a7a", 1.4, 0.0)
        save(f"assets/tiles/icon_room_{key}.svg", 64, 64, d)

    # --- веник уборщицы
    save("assets/people/prop_broom.svg", 32, 32, line(16, 1, 16, 20, "#a07a4c", 2.4) + path("M10 20H22L25 31H7Z", "#c9a45a", OUT, 1.2)
         + path("M11 23L9 31M14 23L13 31M18 23L19 31M21 23L23 31", None, "#a07a4c", 1))


# ------------------------------------------------------------------ грузы (иконки 32×32)

def items():
    def save_item(key, body):
        save(f"assets/items/{key}.svg", 32, 32, body)
    s = ell(17, 26, 13, 3, "#000", None, 0, 0.25)
    s += rect(3, 13, 26, 8, "#9aa1a5", OUT, 1.5, 4) + line(5, 15, 27, 15, "#fff", 1.2, 0.6) + ell(28, 17, 2.4, 4, "#c7cdd0", OUT, 1)
    save_item("bar45", s)
    s = ell(17, 26, 13, 3, "#000", None, 0, 0.25)
    s += poly([(3, 14), (27, 14), (29, 17), (27, 20), (3, 20), (1, 17)], "#8e9a92", OUT, 1.5) + line(3, 17, 27, 17, "#6e7a72", 1)
    save_item("hex27", s)
    s = ell(17, 27, 14, 3, "#000", None, 0, 0.25)
    s += rect(2, 11, 28, 11, "#7d848a", OUT, 1.5, 5) + line(4, 13, 28, 13, "#fff", 1.2, 0.5) + rect(25, 11, 5, 11, "#3d6fb0", OUT, 1, 2)
    save_item("bar40x", s)
    s = ell(16, 26, 9, 3, "#000", None, 0, 0.25) + rect(8, 9, 16, 15, "#c3c9cd", OUT, 1.5, 3) + ell(16, 10, 8, 3, "#e1e5e8", OUT, 1.2) + line(11, 13, 11, 22, "#fff", 1.2, 0.5)
    save_item("pin", s)
    s = ell(16, 26, 11, 3, "#000", None, 0, 0.25) + rect(5, 10, 22, 14, "#b9c0c4", OUT, 1.5, 3) + ell(16, 11, 11, 4, "#d5dadd", OUT, 1.2) + ell(16, 11, 5, 2, "#55595d", None, 0)
    save_item("bushing", s)
    s = ell(16, 27, 10, 3, "#000", None, 0, 0.25) + poly([(7, 16), (12, 12), (20, 12), (25, 16), (20, 20), (12, 20)], "#b0b8bc", OUT, 1.5)
    s += rect(12, 5, 8, 9, "#c7cdd0", OUT, 1.2) + path("M12 7h8M12 10h8", None, "#8a9196", 1) + rect(13, 20, 6, 6, "#c7cdd0", OUT, 1)
    save_item("fitting", s)
    s = ell(16, 26, 14, 3, "#000", None, 0, 0.25) + rect(2, 13, 9, 9, "#bfc6ca", OUT, 1.5, 2) + rect(10, 11, 13, 13, "#cdd3d7", OUT, 1.5, 2) + rect(22, 14, 8, 7, "#bfc6ca", OUT, 1.5, 2)
    save_item("shaft", s)
    s = ell(16, 26, 12, 3, "#000", None, 0, 0.25) + poly([(5, 20), (10, 12), (17, 15), (22, 9), (27, 18), (20, 24), (9, 24)], "#8a5a3a", OUT, 1.5)
    s += circ(13, 18, 2.2, "#6e4428", None, 0) + circ(21, 17, 2.4, "#a8703e", None, 0)
    save_item("scrap", s)
    s = rect(3, 3, 26, 26, "#000", None, 0, 2, 0.22) + rect(1, 1, 26, 10, "#c8a06c", OUT, 1.2) + rect(1, 11, 26, 15, "#a77e4c", OUT, 1.2)
    s += line(14, 1, 14, 11, "#dcc08e", 2) + rect(4, 15, 10, 6, "#ebe5d3", None, 0, 0, 0.9)
    save_item("crate", s)
    # ящик с оборудованием (крупный, 64×64): доски, обвязка, знак «верх», маркировка
    ec = ell(34, 58, 28, 5, "#000", None, 0, 0.25)
    ec += rect(6, 18, 52, 38, "#b88d5c", OUT, 2) + rect(6, 8, 52, 12, "#c99e6a", OUT, 2)
    for y in (27, 36, 45):
        ec += line(7, y, 57, y, "#946f43", 1.4)
    ec += line(7, 14, 57, 14, "#a07a4c", 1.2)
    ec += rect(6, 18, 6, 38, "#8a6640", OUT, 1.2) + rect(52, 18, 6, 38, "#8a6640", OUT, 1.2) + rect(29, 18, 6, 38, "#8a6640", None, 0, 0, 0.6)
    ec += path("M16 30v-8l-3 3M16 22l3 3M22 30v-8l-3 3M22 22l3 3", None, "#2a2e31", 1.6)
    ec += rect(38, 24, 12, 8, "#2a2e31", None, 0, 0, 0.75) + rect(38, 36, 14, 3, "#2a2e31", None, 0, 0, 0.6) + rect(38, 42, 10, 3, "#2a2e31", None, 0, 0, 0.6)
    save("assets/items/equip_crate.svg", 64, 64, ec)


def items3():
    def save_item(key, body):
        save(f"assets/items/{key}.svg", 32, 32, body)
    s = ell(16, 27, 13, 3, "#000", None, 0, 0.25) + poly([(3, 18), (8, 12), (29, 12), (24, 18)], "#a9b2b8", OUT, 1.5) + poly([(3, 18), (24, 18), (24, 22), (3, 22)], "#7d868c", OUT, 1.2)
    s += line(10, 14, 22, 14, "#fff", 1, 0.5)
    save_item("plate8", s)
    s = ell(16, 27, 12, 3, "#000", None, 0, 0.25) + ell(16, 16, 12, 9, "#5a5250", OUT, 1.5) + ell(16, 14, 9, 6, "#6e6460", None, 0) + circ(12, 13, 1.4, "#3a3432", None, 0) + circ(20, 17, 1.2, "#3a3432", None, 0) + circ(17, 11, 1, "#8a7a6a", None, 0)
    save_item("forging", s)
    s = ell(16, 27, 14, 3, "#000", None, 0, 0.25) + poly([(2, 14), (24, 14), (28, 10), (6, 10)], "#9aa1a5", OUT, 1.4) + rect(2, 14, 22, 9, "#7b8286", OUT, 1.4)
    s += poly([(24, 14), (28, 10), (28, 19), (24, 23)], "#8a9196", OUT, 1.4) + poly([(25, 15), (27, 13), (27, 18), (25, 20)], "#3a3f43", None, 0)
    save_item("profile40", s)
    s = ell(16, 27, 11, 3, "#000", None, 0, 0.25) + path("M6 8H14V18H26V25H6Z", "#5e7a54", OUT, 1.5) + circ(10, 12, 1.8, "#2a3a28", None, 0) + circ(21, 21, 1.8, "#2a3a28", None, 0) + line(8, 10, 12, 10, "#fff", 1, 0.4)
    save_item("bracket", s)
    s = ell(16, 27, 12, 3, "#000", None, 0, 0.25) + rect(4, 20, 24, 5, "#8a9196", OUT, 1.4) + circ(16, 14, 10, "#a9b0b4", OUT, 1.5) + circ(16, 14, 5, "#3a3f43", OUT, 1.2) + circ(16, 14, 2.6, "#c9ccce", None, 0)
    s += circ(7, 22.5, 1.2, "#3a3f43", None, 0) + circ(25, 22.5, 1.2, "#3a3f43", None, 0)
    save_item("housing", s)
    s = ell(16, 27, 14, 3, "#000", None, 0, 0.25) + rect(3, 6, 26, 19, None, "#3d5a48", 3.4) + rect(3, 6, 26, 19, None, OUT, 0.8) + rect(6.5, 9.5, 19, 12, None, OUT, 0.8)
    s += line(16, 6, 16, 25, "#3d5a48", 3) + circ(3, 6, 1.6, "#c98d63", None, 0) + circ(29, 25, 1.6, "#c98d63", None, 0)
    save_item("frame", s)
    s = ell(16, 27, 14, 3, "#000", None, 0, 0.25) + rect(1, 13, 30, 6, "#cdd3d7", OUT, 1.2, 2) + rect(9, 8, 14, 16, "#3d5a7a", OUT, 1.5, 3) + rect(11, 10, 10, 3, "#5a7a9a", None, 0)
    s += rect(4, 11, 4, 10, "#b9c0c4", OUT, 1) + rect(24, 11, 4, 10, "#b9c0c4", OUT, 1)
    save_item("drive_unit", s)
    s = ell(16, 26, 14, 3, "#000", None, 0, 0.25) + rect(2, 13, 9, 9, "#bfc6ca", OUT, 1.5, 2) + rect(10, 11, 18, 13, "#aab1b5", OUT, 1.5, 2)
    for k in range(5):
        s += line(12 + k * 3.4, 11, 12 + k * 3.4, 24, "#6a7074", 1.2)
    s += rect(27, 14, 4, 7, "#bfc6ca", OUT, 1.2, 1) + line(4, 15, 26, 15, "#fff", 1, 0.4)
    save_item("spline_shaft", s)


def items_v119():
    """1.19: мелкий крепёж — болт, гайка, шпилька."""
    def save_item(key, body):
        save(f"assets/items/{key}.svg", 32, 32, body)
    # болт: шестигранная головка слева, стержень с резьбой
    s = ell(16, 26, 13, 3, "#000", None, 0, 0.25)
    s += rect(9, 13, 20, 7, "#c3c9cd", OUT, 1.4, 1.5)
    for k in range(6):
        s += line(15 + k * 2.4, 13.5, 13.6 + k * 2.4, 19.5, "#7b8286", 1.0)
    s += poly([(2, 10), (6, 8), (10, 10), (10, 23), (6, 25), (2, 23)], "#9aa3a8", OUT, 1.5)
    s += line(6, 8.5, 6, 24.5, "#6f777b", 1) + line(3.5, 11, 3.5, 22, "#fff", 1, 0.5)
    s = f'<g transform="translate(16 18) scale(0.66) translate(-16 -18)">{s}</g>'   # 1.21: болт мельче — не крупнее других деталей
    save_item("bolt", s)
    # гайка: шестигранник сверху, отверстие с резьбой
    s = ell(16, 26, 12, 3, "#000", None, 0, 0.25)
    s += poly([(4, 18), (10, 22), (22, 22), (28, 18), (28, 14), (22, 10), (10, 10), (4, 14)], "#8e979c", OUT, 1.4)
    s += poly([(4, 14), (10, 10), (22, 10), (28, 14), (22, 18), (10, 18)], "#b3bbbf", OUT, 1.3)
    s += ell(16, 14, 5, 2.8, "#3a3f43", OUT, 1) + path("M12.5 14a3.5 1.8 0 0 0 7 0", None, "#7b8286", 0.9)
    s += line(7, 13, 11, 11, "#fff", 1, 0.5)
    save_item("nut", s)
    # шпилька: пруток с резьбой на обоих концах, гладкая середина
    s = ell(16, 25, 14, 3, "#000", None, 0, 0.25)
    s += rect(2, 13, 28, 6, "#c9ccce", OUT, 1.3, 2)
    for k in range(4):
        s += line(4 + k * 2.4, 13.5, 2.6 + k * 2.4, 18.5, "#7b8286", 1.0)
        s += line(21 + k * 2.4, 13.5, 19.6 + k * 2.4, 18.5, "#7b8286", 1.0)
    s += line(12, 14.5, 19, 14.5, "#fff", 1, 0.55)
    s = f'<g transform="translate(16 17) scale(0.72) translate(-16 -17)">{s}</g>'
    save_item("stud", s)


def emo_v119():
    """1.19: значки над людьми (нужды, эмоции) и «пилюля» под них — вектором, игра растеризует под зум."""
    S = 4.0          # 1 единица мира = 4 единицы SVG
    STEP, H = 8.4, 8.6
    BG = "#1c2024"
    out = {}

    def svg(w, h, body):
        return f'<svg xmlns="http://www.w3.org/2000/svg" width="{fmt(w)}" height="{fmt(h)}" viewBox="0 0 {fmt(w)} {fmt(h)}">{body}</svg>'
    for n in (1, 2, 3):
        w = (STEP * n + 1.4) * S
        h = H * S
        W, Hh = w + 6, h + 16
        x0, y0 = 3, 2
        r = h / 2
        b = f'<rect x="{fmt(x0)}" y="{fmt(y0 + 3)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}" fill="#000" opacity="0.22"/>'
        b += f'<path d="M{fmt(W / 2 - 9)} {fmt(y0 + h - 1)}L{fmt(W / 2)} {fmt(y0 + h + 11)}L{fmt(W / 2 + 9)} {fmt(y0 + h - 1)}Z" fill="{BG}" stroke="#ffffff" stroke-opacity="0.25" stroke-width="2.2"/>'
        b += f'<rect x="{fmt(x0)}" y="{fmt(y0)}" width="{fmt(w)}" height="{fmt(h)}" rx="{fmt(r)}" fill="{BG}" fill-opacity="0.93" stroke="#ffffff" stroke-opacity="0.25" stroke-width="2.2"/>'
        b += f'<path d="M{fmt(W / 2 - 7.5)} {fmt(y0 + h - 2.5)}L{fmt(W / 2)} {fmt(y0 + h + 8.5)}L{fmt(W / 2 + 7.5)} {fmt(y0 + h - 2.5)}Z" fill="{BG}"/>'
        b += f'<path d="M{fmt(x0 + r)} {fmt(y0 + 4)}H{fmt(x0 + w - r)}" stroke="#fff" stroke-opacity="0.12" stroke-width="2" stroke-linecap="round"/>'
        out[f"chip{n}"] = svg(W, Hh, b)
    cols = {"hot": "#d8644e", "wc": "#3f8de0", "food": "#e0883a", "rest": "#7a64c8", "cold": "#5fa8d8", "mood": "#6d747c",
            "inspect": "#7a5236", "strike": "#c9372c", "injury": "#c9372c", "fire": "#e0602c",
            "idea": "#3f8a5a", "talk": "#4a7aa8", "chat": "#5a9a6a", "argue": "#d08a35", "fight": "#c9372c", "laugh": "#d9a13a"}
    G = {
        "wc": lambda c: f'<path d="M16 4C16 4 8 14 8 19.5A8 8 0 0 0 24 19.5C24 14 16 4 16 4Z" fill="{c}"/><path d="M12.5 19a3.5 4 0 0 0 2.5 4" stroke="#fff" stroke-opacity="0.6" stroke-width="1.8" fill="none" stroke-linecap="round"/>',
        "food": lambda c: f'<path d="M9 5V12.5Q9 15 11.5 15V27M14 5V12.5Q14 15 11.5 15" stroke="{c}" stroke-width="2.4" fill="none" stroke-linecap="round" stroke-linejoin="round"/><path d="M11.5 5V11" stroke="{c}" stroke-width="2" stroke-linecap="round"/><path d="M21 27V5Q25.5 8 25 17H21" fill="{c}" stroke="{c}" stroke-width="2" stroke-linejoin="round" stroke-linecap="round"/>',
        "rest": lambda c: f'<path d="M19 5A11 11 0 1 0 27 21A9 9 0 0 1 19 5Z" fill="{c}"/><path d="M22 6h4l-4 4h4" stroke="{c}" stroke-width="1.6" fill="none" stroke-linejoin="round" stroke-linecap="round"/>',
        "cold": lambda c: f'<g stroke="{c}" stroke-width="2.4" stroke-linecap="round"><path d="M16 4V28M5.6 10L26.4 22M5.6 22L26.4 10"/><path d="M12.5 6.5L16 9L19.5 6.5M12.5 25.5L16 23L19.5 25.5" fill="none" stroke-width="1.8"/></g>',
        "hot": lambda c: f'<rect x="13" y="4" width="6" height="17" rx="3" fill="none" stroke="{c}" stroke-width="2.2"/><circle cx="16" cy="23" r="5.5" fill="{c}"/><rect x="15" y="10" width="2" height="10" fill="{c}"/><path d="M22 8h4M22 12h3M22 16h4" stroke="{c}" stroke-width="1.6" stroke-linecap="round"/>',
        "mood": lambda c: f'<path d="M9 21A5 5 0 0 1 9.5 11A7 7 0 0 1 23 10A5.5 5.5 0 0 1 23.5 21Z" fill="{c}"/><path d="M12 24l-1.5 3.5M17 24l-1.5 3.5M22 24l-1.5 3.5" stroke="#9cc8e8" stroke-width="2" stroke-linecap="round"/>',
        "inspect": lambda c: f'<rect x="8" y="4" width="16" height="24" rx="2" fill="{c}"/><rect x="12" y="2.5" width="8" height="4" rx="1.5" fill="{c}" stroke="#1c2024" stroke-width="1"/><path d="M11.5 17l3 3.5l6 -7" stroke="#3f9a4a" stroke-width="2.6" fill="none" stroke-linecap="round" stroke-linejoin="round"/>',
        "strike": lambda c: f'<rect x="13.5" y="4" width="5" height="16" rx="2.5" fill="{c}"/><circle cx="16" cy="25" r="3" fill="{c}"/>',
        "injury": lambda c: f'<path d="M12.5 5h7v7.5h7.5v7h-7.5v7.5h-7v-7.5h-7.5v-7h7.5z" fill="{c}" stroke-linejoin="round"/>',
        "fire": lambda c: f'<path d="M16 3Q24 10 24 18A8 8 0 0 1 8 18Q8 13 12 9Q12 14 15 15Q14 9 16 3Z" fill="{c}"/><path d="M16 15Q20 19 19.5 22A3.5 3.5 0 0 1 12.5 22Q12.5 19 16 15Z" fill="#ffd54a"/>',
        "idea": lambda c: f'<circle cx="16" cy="13" r="8" fill="{c}"/><rect x="12" y="19" width="8" height="5" rx="1" fill="{c}"/><path d="M12.5 27h7" stroke="{c}" stroke-width="2" stroke-linecap="round"/><path d="M12.5 11a4 4 0 0 1 3.5 -3" stroke="#fff" stroke-opacity="0.65" stroke-width="1.6" fill="none" stroke-linecap="round"/>',
        "talk": lambda c: f'<path d="M16 4C9 4 5 8.5 5 13.5C5 17 7 19.5 10 21L8 27L14.5 22.5Q15.2 23 16 23C23 23 27 18.5 27 13.5S23 4 16 4Z" fill="{c}"/><circle cx="11" cy="13.5" r="1.8" fill="#1c2024"/><circle cx="16" cy="13.5" r="1.8" fill="#1c2024"/><circle cx="21" cy="13.5" r="1.8" fill="#1c2024"/>',
        "argue": lambda c: f'<path d="M18.5 3L8 18H15L12.5 29L24 13H17Z" fill="{c}" stroke-linejoin="round"/>',
        "fight": lambda c: "",
        "laugh": lambda c: f'<circle cx="16" cy="16" r="11" fill="none" stroke="{c}" stroke-width="2.4"/><circle cx="12" cy="13" r="1.9" fill="{c}"/><circle cx="20" cy="13" r="1.9" fill="{c}"/><path d="M10 18Q16 25 22 18Z" fill="{c}"/>',
    }
    star = ""
    for k in range(10):
        a = -math.pi / 2 + 2 * math.pi * k / 10
        rr = 12 if k % 2 == 0 else 5.2
        star += ("M" if k == 0 else "L") + f"{fmt(16 + math.cos(a) * rr)} {fmt(16 + math.sin(a) * rr)}"
    G["fight"] = lambda c: f'<path d="{star}Z" fill="{c}" stroke-linejoin="round"/>'
    G["chat"] = G["talk"]
    for k, fn in G.items():
        c = _mix(cols[k], "#ffffff", 0.22)
        out[k] = svg(32, 32, fn(c))
    os.makedirs(os.path.join(ROOT, "assets/vec"), exist_ok=True)
    with open(os.path.join(ROOT, "assets/vec/emo.json"), "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


def ui_v119():
    """1.19: значок «Под управлением» — человек и курсор-указатель."""
    C = "#e7e4d8"
    A = "#e8b13a"
    b = circ(19, 14, 7, None, C, 3) + path("M6 40Q6 25 19 25Q26 25 29 29", None, C, 3)
    b += path("M27 24L27 44L32 39L35.5 46L39 44.5L35.5 37.5L42 37Z", A, "#1b1d20", 2)
    save("assets/ui/control.svg", 48, 48, b)


def ground_v119():
    """1.19: земля богаче — пятна, камешки со светом и тенью, кустики травы пучками, трещины и заплатки
    на асфальте; ничего не обрезано краем клетки (сетка не читается). Плюс кромки травы — пучки,
    которые свешиваются на соседний грунт, чтобы газон был не «квадратами»."""
    T = 64

    def blot(rng, n, cols, rmin, rmax, op):
        o = ""
        for _ in range(n):
            x, y = rng.uniform(10, T - 10), rng.uniform(10, T - 10)
            rx, ry = rng.uniform(rmin, rmax), rng.uniform(rmin, rmax) * 0.7
            rx, ry = min(rx, x - 1, T - 1 - x), min(ry, y - 1, T - 1 - y)
            o += ell(x, y, max(2, rx), max(2, ry), rng.choice(cols), None, 0, op)
        return o

    def pebble(rng, x, y, r, base):
        lo = _mix(base, "#000000", 0.28)
        hi = _mix(base, "#ffffff", 0.35)
        o = ell(x + r * 0.25, y + r * 0.3, r, r * 0.72, "#000000", None, 0, 0.18)
        o += ell(x, y, r, r * 0.72, base, None, 0)
        o += ell(x - r * 0.25, y - r * 0.25, r * 0.5, r * 0.32, hi, None, 0, 0.7)
        o += path(f"M{fmt(x - r * 0.8)} {fmt(y + r * 0.35)}Q{fmt(x)} {fmt(y + r * 0.95)} {fmt(x + r * 0.8)} {fmt(y + r * 0.35)}", None, lo, 0.7, 0.6)
        return o

    def inner(rng, m=3):
        return rng.uniform(m, T - m), rng.uniform(m, T - m)

    # ---- грунт
    for v in range(4):
        rng = random.Random(1900 + v)
        base = "#a39c86"
        s = rect(0, 0, T, T, base, None, 0)
        s += blot(rng, 5, ["#968f79", "#aea791", "#9b947d"], 8, 16, 0.55)
        for _ in range(70):
            x, y = inner(rng, 1.5)
            s += circ(x, y, rng.uniform(0.4, 1.0), rng.choice(["#8c866f", "#b8b29c", "#938c76", "#7f7966"]), None, 0, 0.8)
        for _ in range(rng.randint(5, 8)):
            x, y = inner(rng, 5)
            s += pebble(rng, x, y, rng.uniform(1.4, 2.8), rng.choice(["#b9b3a0", "#9e9886", "#c4bfae", "#8f8a7a"]))
        if v == 1:
            s += path("M9 44q8 -5 15 -2t13 -6", None, "#857f6a", 1.1, 0.7) + path("M9 45q8 -5 15 -2t13 -6", None, "#bdb7a3", 0.6, 0.6)
        if v == 3:
            for _ in range(3):
                x, y = inner(rng, 8)
                for k in range(3):
                    s += path(f"M{fmt(x + k * 1.6)} {fmt(y)}l{fmt(rng.uniform(-1.6, 1.6))} -{fmt(rng.uniform(2.5, 4.5))}", None, rng.choice(["#6f8550", "#86995e"]), 1.0)
        save(f"assets/tiles/dirt_{v}.svg", T, T, s)
    # ---- трава
    for v in range(4):
        rng = random.Random(2900 + v)
        s = rect(0, 0, T, T, "#7f955a", None, 0)
        s += blot(rng, 5, ["#748a50", "#8ba265", "#71874d"], 8, 15, 0.6)
        for _ in range(40):
            x, y = inner(rng, 1.5)
            s += circ(x, y, rng.uniform(0.5, 1.3), rng.choice(["#6a7f48", "#93aa6c", "#5f7442"]), None, 0, 0.7)
        # пучки травы: 3–5 травинок веером, тёмные снизу, светлые кончики
        for _ in range(16):
            x, y = rng.uniform(5, T - 5), rng.uniform(9, T - 3)
            n = rng.randint(3, 5)
            for k in range(n):
                a = -0.9 + 1.8 * k / max(1, n - 1) + rng.uniform(-0.2, 0.2)
                ln = rng.uniform(4, 7.5)
                tx, ty = x + math.sin(a) * ln * 0.6, y - math.cos(a) * ln
                s += path(f"M{fmt(x)} {fmt(y)}Q{fmt(x + math.sin(a) * ln * 0.2)} {fmt(y - ln * 0.6)} {fmt(tx)} {fmt(ty)}", None,
                          rng.choice(["#5d7240", "#688049"]), 1.3)
                s += path(f"M{fmt(x + math.sin(a) * ln * 0.3)} {fmt(y - ln * 0.55)}L{fmt(tx)} {fmt(ty)}", None, rng.choice(["#9cb373", "#a9bf7d"]), 0.9)
        if v in (2, 3):
            for _ in range(2 if v == 2 else 4):
                x, y = inner(rng, 6)
                col = rng.choice(["#f2efe0", "#e9cf4a", "#f2efe0"])
                s += circ(x, y, 1.3, col, None, 0) + circ(x, y, 0.5, "#c9a227" if col != "#e9cf4a" else "#b07f1a", None, 0)
        save(f"assets/tiles/grass_{v}.svg", T, T, s)
    # ---- асфальт: 0–1 ровный, 2 — заплатка, 3 — пятно масла, 4 — трещина (особые клетки — редкие)
    for v in range(5):
        rng = random.Random(3900 + v)
        s = rect(0, 0, T, T, "#56595d", None, 0)
        s += blot(rng, 4, ["#505357", "#5c5f63"], 10, 18, 0.6)
        for _ in range(110):
            x, y = inner(rng, 1)
            s += circ(x, y, rng.uniform(0.35, 0.9), rng.choice(["#6a6d71", "#47494d", "#74777b", "#4e5155"]), None, 0, 0.85)
        if v == 4:
            pts = [(8, 14)]
            for _ in range(5):
                px, py = pts[-1]
                pts.append((px + rng.uniform(6, 10), py + rng.uniform(2, 8)))
            d = "M" + "L".join(f"{fmt(a)} {fmt(b)}" for a, b in pts)
            s += path(d, None, "#3d3f42", 1.3) + ga_shift(d, 0.7, "#6c6f73", 0.6)
        if v == 2:
            s += path("M14 20l26 -3l8 5l-2 22l-28 4l-6 -12z", "#4c4f53", "#45474b", 1.2, None, 0.9)
        if v == 3:
            s += ell(38, 34, 11, 6, "#2d2f33", None, 0, 0.35) + ell(36, 33, 5, 2.5, "#3c3946", None, 0, 0.35)
        save(f"assets/tiles/asphalt_{v}.svg", T, T, s)
    # ---- кромки газона: волнистая полоса травы + травинки свешиваются на соседнюю клетку (поверх грунта)
    rng = random.Random(4900)
    EH = 16
    ws = [rng.uniform(2.5, 9.0) for _ in range(9)]
    d = "M0 0"
    for k in range(9):
        x0, x1 = k * 8, k * 8 + 8
        d += f"L{fmt(x0 + 2)} {fmt(ws[k])}Q{fmt(x0 + 4)} {fmt(ws[k] + 2.5)} {fmt(x1 - 2)} {fmt(ws[(k + 1) % 9] if k < 8 else 1.5)}"
    d += f"L{T} 0Z"
    tufts = path(d, "#7f955a", None, 0)
    tufts += path(d.replace("Z", ""), None, "#6b8049", 0.8, 0.5)
    x = 1.5
    while x < T - 1.5:
        h = rng.uniform(6, 14)
        tufts += path(f"M{fmt(x - 2)} 1Q{fmt(x - 1)} {fmt(h * 0.6)} {fmt(x + rng.uniform(-1.4, 1.4))} {fmt(h)}Q{fmt(x + 1)} {fmt(h * 0.5)} {fmt(x + 2)} 1Z", rng.choice(["#7f955a", "#768c52", "#87a061", "#6f8550"]), None, 0)
        tufts += path(f"M{fmt(x)} 1L{fmt(x + rng.uniform(-1, 1))} {fmt(h * 0.85)}", None, rng.choice(["#5d7240", "#9cb373"]), 0.8)
        x += rng.uniform(2.2, 3.8)
    for side, tr in (("s", ""), ("n", f"translate(0 {EH}) scale(1 -1)"), ("e", "matrix(0 1 1 0 0 0)"), ("w", f"matrix(0 1 -1 0 {EH} 0)")):
        if side in ("s", "n"):
            save(f"assets/tiles/grass_edge_{side}.svg", T, EH, g(tufts, tr) if tr else tufts)
        else:
            save(f"assets/tiles/grass_edge_{side}.svg", EH, T, g(tufts, tr))


def walls_v119():
    """1.19.1: скаты стен «пирамидкой» — фактура на всю клетку: ряды вдоль (h) и поперёк (v)."""
    T = 64

    def bricks(seed, cols, mortar, bw=16, bh=8):
        rng = random.Random(seed)
        o = rect(0, 0, T, T, mortar, None, 0)
        for row in range(T // bh):
            off = (bw // 2) if row % 2 else 0
            x = -off
            while x < T:
                c = rng.choice(cols)
                o += rect(x + 0.8, row * bh + 0.8, bw - 1.6, bh - 1.6, c, None, 0, 0.8)
                o += line(x + 1.5, row * bh + 1.4, x + bw - 2, row * bh + 1.4, "#ffffff", 0.7, 0.18)
                x += bw
        return o

    def concrete(seed):
        rng = random.Random(seed)
        o = rect(0, 0, T, T, "#9a9b96", None, 0) + speckle(rng, T, T, 60, ["#8f908b", "#a6a7a2", "#888984"], 0.4, 1.1)
        o += line(0, 31.5, T, 31.5, "#7d7e79", 1.2) + line(0, 0.6, T, 0.6, "#7d7e79", 1.2)
        for x in (12, 44):
            o += circ(x, 16, 1.2, "#7d7e79", None, 0) + circ(x, 48, 1.2, "#7d7e79", None, 0)
        return o

    def sandwich(seed):
        o = rect(0, 0, T, T, "#b9c2c8", None, 0)
        for k in range(8):
            o += rect(0, k * 8 + 1, T, 3, "#a3adb4", None, 0) + line(0, k * 8 + 1, T, k * 8 + 1, "#d4dbe0", 0.8)
        return o

    def partition(seed):
        rng = random.Random(seed)
        return rect(0, 0, T, T, "#c9c4b6", None, 0) + speckle(rng, T, T, 40, ["#bfbaac", "#d2cdc0"], 0.4, 1.0)

    kinds = {"brick": lambda sd: bricks(sd, ["#8f5a44", "#97624a", "#87533f", "#9d6a50", "#8a5843"], "#6a4a3c"),
             "concrete": concrete, "sandwich": sandwich, "partition": partition,
             "silicate": lambda sd: bricks(sd, ["#e4e0d6", "#dcd8cc", "#ebe7de", "#d6d1c4", "#e0dbd0"], "#b9b3a6"),
             "gasblock": lambda sd: bricks(sd, ["#d2d0ca", "#c9c7c0", "#d8d6d0", "#cdcbc4"], "#a9a7a0", 32, 16)}
    for k, fn in kinds.items():
        body = fn(7100 + len(k))
        save(f"assets/tiles/wslope_{k}_h.svg", T, T, body)
        save(f"assets/tiles/wslope_{k}_v.svg", T, T, g(body, "matrix(0 1 1 0 0 0)"))


def ga_shift(d, dy, col, sw):
    return f'<path d="{d}" transform="translate(0 {dy})" fill="none" stroke="{col}" stroke-width="{sw}" stroke-linecap="round"/>'


def items4():
    def save_item(key, body):
        save(f"assets/items/{key}.svg", 32, 32, body)
    s = ell(16, 27, 13, 3, "#000", None, 0, 0.25) + ell(16, 16, 13, 10, "#a9b0b4", OUT, 1.5) + ell(16, 15, 6, 4.5, "#3a3f43", OUT, 1.2)
    for k in range(6):
        a = k * math.pi / 3
        s += ell(16 + math.cos(a) * 9.5, 16 + math.sin(a) * 7.2, 1.5, 1.2, "#3a3f43", None, 0)
    save_item("flange", s)
    s = ell(16, 27, 13, 3, "#000", None, 0, 0.25)
    pts = []
    for k in range(24):
        a = k * math.pi / 12
        r = 13 if k % 2 == 0 else 10.5
        pts.append((16 + math.cos(a) * r, 15 + math.sin(a) * r * 0.85))
    s += poly(pts, "#9aa3a8", OUT, 1.2) + ell(16, 15, 7, 6, "#b9c0c4", OUT, 1) + ell(16, 15, 3, 2.6, "#3a3f43", None, 0) + rect(15, 11.5, 2, 2, "#3a3f43", None, 0)
    save_item("gear", s)
    s = ell(16, 27, 14, 3, "#000", None, 0, 0.25) + rect(5, 9, 22, 16, "#4a6a8a", OUT, 1.5, 3) + rect(7, 11, 18, 3, "#6a8aaa", None, 0)
    s += rect(1, 14, 5, 5, "#c9ccce", OUT, 1) + rect(26, 17, 5, 4, "#c9ccce", OUT, 1) + circ(10, 21, 1.2, "#2a3a4a", None, 0) + circ(22, 21, 1.2, "#2a3a4a", None, 0)
    save_item("gearbox", s)


# ------------------------------------------------------------------ люди (64×112, начало координат 32,76)

PO = (32, 76)
WHITE = "#ffffff"


def pt(x, y):
    return x + PO[0], y + PO[1]


def P(d):
    """Сдвинуть относительный путь (начало в точке стопы) в координаты холста."""
    return d


def person_layer(name, body):
    # тонируемые слои (белая основа): контур серый — после умножения на цвет кожи, волос или одежды
    # он становится тёмным оттенком того же цвета, а не чёрной обводкой
    if f'fill="{WHITE}"' in body:
        body = body.replace(f'stroke="{OUT}"', 'stroke="#4e4e4e"')   # 1.14.2: контур темнее — силуэт чётче
    save(f"assets/people/{name}.svg", 64, 112, g(body, f"translate({PO[0]} {PO[1]})"))


TORSO_F = "M-22 6Q-24 -15 -12 -19H12Q24 -15 22 6Q21 25 0 25.6Q-21 25 -22 6Z"
TORSO_S = "M-16 6Q-18 -15 -9 -19H9Q18 -15 16 6Q15 25 0 25.6Q-15 25 -16 6Z"
SHADE_F = "M10 -19H12Q24 -15 22 6Q21 25 0 25.6Q12 20 12 4Z"
SHADE_S = "M6 -19H9Q18 -15 16 6Q15 25 0 25.6Q8 20 8 4Z"


def people():
    person_layer("shadow", ell(4, 26, 28, 9, "#000", None, 0, 0.3))
    # туловище (белое — тонируется цветом одежды)
    for d, tp, sh in (("front", TORSO_F, SHADE_F), ("back", TORSO_F, SHADE_F), ("side", TORSO_S, SHADE_S)):
        b = path(tp, WHITE, OUT, 2) + path(sh, "#000", None, 0, 0.2)
        b += path("M-19 -4Q-18 -15 -11 -17Q-14 -8 -15 2Z" if d != "side" else "M-13 -4Q-13 -15 -7 -17Q-10 -8 -11 2Z", "#fff", None, 0, 0.2)
        person_layer(f"torso_{d}", b)
    # силуэты туловища: мужские и женские, пять телосложений (вид спереди/сзади и сбоку)
    BODY_SHAPES = {
        # плечи, талия, бёдра, верх (y), глубина спины/груди сбоку, живот сбоку
        "m_vthin": (11, 9, 10, -21, 8, 9, 0),
        "m_strong": (29, 20, 21, -20, 17, 18, 0),
        "f_vthin": (10, 8, 12, -20, 7, 9, 0),
        "f_strong": (22, 16, 21, -19, 14, 15, 0),
        "m_thin": (14, 12, 13, -21, 10, 11, 0),
        "m_norm": (20, 18, 19, -19, 14, 14, 0),
        "m_stout": (25, 21, 21, -19, 16, 16, 0),
        "m_fat": (21, 25, 27, -18, 15, 18, 7),
        "m_vfat": (24, 30, 32, -17, 17, 20, 12),
        "f_thin": (13, 10, 15, -20, 9, 11, 0),
        "f_norm": (16, 13, 20, -18, 11, 13, 0),
        "f_stout": (19, 16, 23, -18, 13, 15, 0),
        "f_fat": (19, 22, 27, -17, 14, 17, 6),
        "f_vfat": (22, 27, 32, -16, 16, 19, 10),
    }
    BOT = 25.6
    def front_path(sh, wa, hp, top):
        sr = 6.5
        return (f"M{-sh} {top+sr}Q{-sh} {top} {-sh+sr} {top}H{sh-sr}Q{sh} {top} {sh} {top+sr}"
                f"C{sh} {top+sr+9} {wa} -4 {wa} 2C{wa} 8 {hp} 9 {hp} 15Q{hp} {BOT} 0 {BOT}"
                f"Q{-hp} {BOT} {-hp} 15C{-hp} 9 {-wa} 8 {-wa} 2C{-wa} -4 {-sh} {top+sr+9} {-sh} {top+sr}Z")
    def front_shade(sh, wa, hp, top):
        sr = 6.5
        return (f"M{sh*0.5} {top}H{sh-sr}Q{sh} {top} {sh} {top+sr}C{sh} {top+sr+9} {wa} -4 {wa} 2"
                f"C{wa} 8 {hp} 9 {hp} 15Q{hp} {BOT} 0 {BOT}Q{hp*0.55} 18 {wa*0.6} 4Q{sh*0.55} {top+8} {sh*0.5} {top}Z")
    # 1.22: живот сбоку — плавный овал от груди до бёдер (раньше выпирал «шишкой» внизу)
    def front_edge(front, belly, top):
        if belly <= 0:
            return f"C{front} 2 {front} 8 {front*0.92} 14Q{front*0.7} {BOT} 0 {BOT}"
        return (f"C{front+belly*0.55} {top+10} {front+belly} -2 {front+belly} 7"
                f"C{front+belly} 17 {front*0.55+belly*0.5} {BOT} 0 {BOT}")
    def side_path(back, front, belly, top):
        bk = back + belly * 0.22
        return (f"M{-back+3} {top}H{front-4}Q{front} {top} {front} {top+6}" + front_edge(front, belly, top)
                + f"Q{-bk} {BOT-1} {-bk} 10L{-back} {top+5}Q{-back} {top} {-back+3} {top}Z")
    def side_shade(back, front, belly, top):
        return (f"M{front*0.35} {top}H{front-4}Q{front} {top} {front} {top+6}" + front_edge(front, belly, top)
                + f"Q{front*0.5} 16 {front*0.35} {top}Z")
    for key, (sh, wa, hp, top, back, frt, belly) in BODY_SHAPES.items():
        fp = front_path(sh, wa, hp, top)
        hl = f"M{-sh+3} {top+8}Q{-sh+3} {top+3} {-sh+8} {top+2}Q{-sh+6} {top+10} {-sh+5} {top+20}Z"
        bf = path(fp, WHITE, OUT, 2.5) + path(front_shade(sh, wa, hp, top), "#000", None, 0, 0.2) + path(hl, "#fff", None, 0, 0.22)
        if key.startswith("f_"):
            bf += path(f"M{-wa+1} 3Q0 6 {wa-1} 3", None, "#000", 1.2, 0.12)
        if belly > 0:
            bf += path(f"M{-wa*0.55} 14Q0 {19 + belly * 0.3} {wa*0.55} 14", None, "#000", 1.3, 0.16)
        person_layer(f"torso_front_{key}", bf)
        person_layer(f"torso_back_{key}", path(fp, WHITE, OUT, 2.5) + path(front_shade(sh, wa, hp, top), "#000", None, 0, 0.2) + path(hl, "#fff", None, 0, 0.18))
        sp = side_path(back, frt, belly, top)
        bs = path(sp, WHITE, OUT, 2.5) + path(side_shade(back, frt, belly, top), "#000", None, 0, 0.2)
        bs += path(f"M{-back+3} {top+7}Q{-back+3} {top+3} {-back+7} {top+2}Q{-back+5} {top+10} {-back+5} {top+18}Z", "#fff", None, 0, 0.2)
        if key.startswith("f_"):
            bs += path(f"M{frt-1} {top+6}Q{frt+2.5} {top+11} {frt-1} {top+15}", None, "#000", 1.1, 0.14)
        person_layer(f"torso_side_{key}", bs)
    # детали одежды (не тонируются)
    D = "#000"
    # комбинезон
    person_layer("outfit_overall_front", path("M-12 -19V6M12 -19V6", None, D, 4.8, 0.25) + rect(-12, -8, 24, 14, D, None, 0, 1.5, 0.12)
                 + rect(-12, -8, 24, 14, None, D, 1.4, 1.5, 0.25) + circ(-12, -13, 1.8, "#d0d5d8", None, 0) + circ(12, -13, 1.8, "#d0d5d8", None, 0) + path("M-21 12H21", None, D, 2, 0.2))
    person_layer("outfit_overall_back", path("M-14 -18L10 10M14 -18L-10 10", None, D, 4.8, 0.25) + path("M-21 12H21", None, D, 3, 0.25))
    person_layer("outfit_overall_side", path("M4 -19V6", None, D, 4.8, 0.25) + rect(2, -8, 13, 14, D, None, 0, 1.5, 0.12) + path("M-15 12H15", None, D, 2, 0.2))
    # халат
    person_layer("outfit_coat_front", poly([(-7, -19), (0, -8), (7, -19)], "#7fa4c4", None, 0) + path("M-9 -19L0 -3L9 -19", None, "#9aa0a2", 2)
                 + rect(-18, -6, 10, 10, None, "#9aa0a2", 1.6) + path("M-16 -6V-12M-12 -6V-13", None, "#3f6f9a", 2) + path("M0 -3V24", None, "#9aa0a2", 1.4) + circ(0, 4, 1.4, "#9aa0a2", None, 0) + circ(0, 14, 1.4, "#9aa0a2", None, 0))
    person_layer("outfit_coat_back", path("M0 -18V24", None, "#9aa0a2", 1.4) + path("M-16 8H16", None, "#9aa0a2", 2))
    person_layer("outfit_coat_side", path("M6 -19L4 -6", None, "#9aa0a2", 2) + rect(2, -4, 10, 10, None, "#9aa0a2", 1.4))
    # жилет мастера: полосы
    person_layer("outfit_vest_front", poly([(-8, -19), (0, -9), (8, -19)], "#2a3a5a", None, 0) + path("M-21 -4H21M-21.6 9H21.6", None, "#e7e4d8", 4) + path("M0 -9V25", None, D, 2, 0.3))
    person_layer("outfit_vest_back", path("M-21 -4H21M-21.6 9H21.6", None, "#e7e4d8", 4))
    person_layer("outfit_vest_side", path("M-15 -4H15M-15.6 9H15.6", None, "#e7e4d8", 4))
    # клетчатая рубашка
    chk = path("M-21 -6H21M-22 6H22M-19 17H19M-10 -19V25M10 -19V25", None, D, 2, 0.22)
    person_layer("outfit_shirt_front", chk + poly([(-6, -19), (0, -12), (6, -19)], D, None, 0, 0.2))
    person_layer("outfit_shirt_back", chk)
    person_layer("outfit_shirt_side", path("M-15 -6H15M-16 6H16M-14 17H14M0 -19V25", None, D, 2, 0.22))
    # куртка
    # 1.14.2: молния не светлой полосой через всю фигуру, а тёмным швом ниже воротника
    person_layer("outfit_jacket_front", path("M0 -8V25", None, D, 1.3, 0.3) + rect(-1.2, -9, 2.4, 3, "#9aa0a4", OUT, 0.6, 0.6)
                 + path("M-10 -19Q-4 -10 0 -9Q4 -10 10 -19", None, D, 2.6, 0.3) + rect(-18, 4, 9, 7, None, D, 1.4, 1, 0.3) + rect(9, 4, 9, 7, None, D, 1.4, 1, 0.3))
    person_layer("outfit_jacket_back", path("M-8 -19Q0 -14 8 -19", None, D, 3, 0.3) + path("M-21 18H21", None, D, 3, 0.25))
    person_layer("outfit_jacket_side", path("M10 -8V24", None, D, 1.2, 0.28) + path("M6 -19Q9 -12 11 -9", None, D, 2.2, 0.28))

    # голова (белая — тонируется цветом кожи)
    HY = -34
    hf = circ(-16.6, HY + 2, 4, WHITE, OUT, 1.4) + circ(16.6, HY + 2, 4, WHITE, OUT, 1.4) + circ(0, HY, 17, WHITE, OUT, 2)
    hf += path(f"M9 {HY-14}Q18 {HY-4} 14 {HY+10}Q10 {HY+15} 4 {HY+16.5}Q13 {HY+6} 9 {HY-14}Z", "#000", None, 0, 0.12)
    person_layer("head_front", hf)
    hb = circ(-16.6, HY + 2, 4, WHITE, OUT, 1.4) + circ(16.6, HY + 2, 4, WHITE, OUT, 1.4) + circ(0, HY, 17, WHITE, OUT, 2)
    person_layer("head_back", hb)
    hs = circ(0, HY, 17, WHITE, OUT, 2) + path(f"M15 {HY+1}Q20 {HY+3} 16 {HY+6}", WHITE, OUT, 1.6)
    hs += ell(-3, HY + 2, 4, 5, WHITE, OUT, 1.4) + path(f"M-4 {HY}q2 2 0 4", None, OUT, 1, 0.5)
    person_layer("head_side", hs)
    # лицо (не тонируется)
    EL = "#2b2421"
    ff = ""
    for ex in (-6.2, 6.2):
        ff += ell(ex, HY + 1, 3.4, 2.7, "#fbf7f2", EL, 0.8)
        ff += circ(ex + 0.3, HY + 1.2, 2.0, "#5a3a24", None, 0) + circ(ex + 0.3, HY + 1.2, 1.0, "#141010", None, 0)
        ff += circ(ex + 1.1, HY + 0.3, 0.75, "#fff", None, 0)
        ff += path(f"M{ex - 3.6} {HY + 1}Q{ex} {HY - 3.4} {ex + 3.6} {HY + 0.6}", None, EL, 1.5)
    ff += path(f"M0 {HY+3}V{HY+7}", None, "#000", 1.8, 0.25) + path(f"M-4.5 {HY+11}Q0 {HY+13.5} 4.5 {HY+11}", None, "#6a2f25", 1.8)
    ff += circ(-8, HY - 8, 5, "#fff", None, 0, 0.18) + circ(-10, HY + 7, 3, "#d06050", None, 0, 0.18) + circ(10, HY + 7, 3, "#d06050", None, 0, 0.18)
    person_layer("face_front", ff)
    fs = ell(8.6, HY + 1, 2.4, 2.7, "#fbf7f2", "#2b2421", 0.8) + circ(9.6, HY + 1.2, 1.7, "#5a3a24", None, 0) + circ(9.8, HY + 1.2, 0.85, "#141010", None, 0)
    fs += circ(10.3, HY + 0.4, 0.6, "#fff", None, 0) + path(f"M6.2 {HY + 0.8}Q8.8 {HY - 3} 11.4 {HY}", None, "#2b2421", 1.4)
    fs += path(f"M7 {HY+11}Q10 {HY+12} 12 {HY+10.5}", None, "#6a2f25", 1.8) + circ(9, HY + 7, 2.6, "#d06050", None, 0, 0.18)
    person_layer("face_side", fs)
    person_layer("brows_front", path(f"M-10 {HY-4}H-3M3 {HY-4}H10", None, WHITE, 2.6) + path(f"M-10 {HY-4}H-3M3 {HY-4}H10", None, "#000", 2.6, 0.55))
    person_layer("brows_side", path(f"M5 {HY-4}H12", None, WHITE, 2.6) + path(f"M5 {HY-4}H12", None, "#000", 2.6, 0.55))

    # причёски (белые — тонируются)
    def hair(style, d):
        y = HY
        o = OUT
        if style == "short":
            if d == "front":
                return path(f"M-17.2 {y-1}Q-18 {y-20} 0 {y-20}Q18 {y-20} 17.2 {y-1}Q14 {y-10} 0 {y-11}Q-14 {y-10} -17.2 {y-1}Z", WHITE, o, 1.4)
            if d == "back":
                return path(f"M-17.2 {y+4}Q-19 {y-20} 0 {y-20}Q19 {y-20} 17.2 {y+4}Q16 {y+12} 8 {y+13}H-8Q-16 {y+12} -17.2 {y+4}Z", WHITE, o, 1.4)
            return path(f"M-17.2 {y+4}Q-19 {y-20} 0 {y-20}Q16 {y-20} 16.8 {y-6}Q8 {y-11} -2 {y-9}Q-6 {y+2} -12 {y+10}Q-17 {y+10} -17.2 {y+4}Z", WHITE, o, 1.4)
        if style == "buzz":
            if d == "front":
                return path(f"M-16.6 {y-3}Q-17 {y-18.4} 0 {y-18.4}Q17 {y-18.4} 16.6 {y-3}Q13 {y-11} 0 {y-12}Q-13 {y-11} -16.6 {y-3}Z", WHITE, o, 1.0) + path(f"M-8 {y-15}l1 1M4 {y-14}l1 1M-2 {y-13}l1 1", None, "#000", 1.2, 0.25)
            if d == "back":
                return path(f"M-16.6 {y+2}Q-18 {y-18.4} 0 {y-18.4}Q18 {y-18.4} 16.6 {y+2}Q15 {y+10} 8 {y+11}H-8Q-15 {y+10} -16.6 {y+2}Z", WHITE, o, 1.0) + path(f"M-8 {y-10}l1 1M4 {y-6}l1 1M-4 {y}l1 1M6 {y+4}l1 1", None, "#000", 1.2, 0.25)
            return path(f"M-16.6 {y+2}Q-18 {y-18.4} 0 {y-18.4}Q15 {y-18.4} 16 {y-7}Q8 {y-12} -2 {y-10}Q-6 {y+1} -12 {y+8}Q-16 {y+8} -16.6 {y+2}Z", WHITE, o, 1.0)
        if style == "bald":
            if d == "front":
                return path(f"M-17 {y+2}Q-18 {y-6} -15 {y-9}M17 {y+2}Q18 {y-6} 15 {y-9}", None, WHITE, 4.5) + path(f"M-17 {y+2}Q-18 {y-6} -15 {y-9}M17 {y+2}Q18 {y-6} 15 {y-9}", None, o, 1, 0.5)
            if d == "back":
                return path(f"M-17 {y+2}Q-16 {y+10} -8 {y+11}H8Q16 {y+10} 17 {y+2}Q17.5 {y-5} 14 {y-9}Q8 {y-1} 0 {y-1}Q-8 {y-1} -14 {y-9}Q-17.5 {y-5} -17 {y+2}Z", WHITE, o, 1.2)
            return path(f"M-17 {y+2}Q-16 {y+10} -8 {y+10}Q-4 {y+2} -4 {y-6}Q-10 {y-6} -15 {y-10}Q-17.5 {y-5} -17 {y+2}Z", WHITE, o, 1.2)
        if style == "ponytail":
            if d == "front":
                return path(f"M-17 {y+6}Q-19 {y-19.5} 0 {y-19.5}Q19 {y-19.5} 17 {y+6}Q15 {y-6} 6 {y-12}Q-8 {y-12} -15 {y-2}Z", WHITE, o, 1.4)
            if d == "back":
                return (path(f"M-17 {y+4}Q-19 {y-20} 0 {y-20}Q19 {y-20} 17 {y+4}Q15 {y+11} 7 {y+12}H-7Q-15 {y+11} -17 {y+4}Z", WHITE, o, 1.4)
                        + path(f"M-4.4 {y+10}Q-8 {y+28} 0 {y+36}Q8 {y+28} 4.4 {y+10}Z", WHITE, o, 1.4) + rect(-4.6, y + 9, 9.2, 4, "#3f8de0", None, 0))
            return (path(f"M-17 {y+4}Q-19 {y-20} 0 {y-20}Q16 {y-20} 16.8 {y-6}Q8 {y-11} -2 {y-9}Q-6 {y+2} -12 {y+10}Q-17 {y+10} -17 {y+4}Z", WHITE, o, 1.4)
                    + path(f"M-16 {y}Q-26 {y+12} -20 {y+26}Q-14 {y+14} -12 {y+4}Z", WHITE, o, 1.4))
        if style == "bun":
            if d == "front":
                return circ(0, y - 21, 8, WHITE, o, 1.4) + path(f"M-17 {y+6}Q-19 {y-19.5} 0 {y-19.5}Q19 {y-19.5} 17 {y+6}Q15 {y-6} 6 {y-12}Q-8 {y-12} -15 {y-2}Z", WHITE, o, 1.4)
            if d == "back":
                return path(f"M-17 {y+4}Q-19 {y-20} 0 {y-20}Q19 {y-20} 17 {y+4}Q15 {y+11} 7 {y+12}H-7Q-15 {y+11} -17 {y+4}Z", WHITE, o, 1.4) + circ(0, y - 10, 8.5, WHITE, o, 1.4)
            return path(f"M-17 {y+4}Q-19 {y-20} 0 {y-20}Q16 {y-20} 16.8 {y-6}Q8 {y-11} -2 {y-9}Q-6 {y+2} -12 {y+10}Q-17 {y+10} -17 {y+4}Z", WHITE, o, 1.4) + circ(-14, y - 12, 8, WHITE, o, 1.4)
        if style == "long":
            if d == "front":
                return path(f"M-17.5 {y+20}Q-21 {y-20} 0 {y-20}Q21 {y-20} 17.5 {y+20}L13 {y+20}Q15 {y-4} 6 {y-12}Q-8 {y-12} -13 {y+2}Q-13 {y+14} -12 {y+20}Z", WHITE, o, 1.4)
            if d == "back":
                return path(f"M-18 {y+22}Q-21 {y-20} 0 {y-20}Q21 {y-20} 18 {y+22}Q8 {y+26} 0 {y+26}Q-8 {y+26} -18 {y+22}Z", WHITE, o, 1.4)
            return path(f"M-18 {y+22}Q-21 {y-20} 0 {y-20}Q16 {y-20} 16.8 {y-6}Q8 {y-11} -2 {y-9}Q-4 {y+8} -2 {y+24}Q-12 {y+26} -18 {y+22}Z", WHITE, o, 1.4)
        if style == "curly":
            pts = []
            if d == "front":
                cs = [(-14, y - 8), (-11, y - 15), (-4, y - 19), (4, y - 19), (11, y - 15), (14, y - 8), (16, y - 1), (-16, y - 1)]
            elif d == "back":
                cs = [(-14, y - 10), (-8, y - 17), (0, y - 19), (8, y - 17), (14, y - 10), (15, y - 1), (12, y + 7), (4, y + 10), (-4, y + 10), (-12, y + 7), (-15, y - 1), (0, y - 6)]
            else:
                cs = [(-14, y - 8), (-8, y - 16), (0, y - 19), (8, y - 16), (13, y - 10), (-15, y), (-11, y + 7), (-5, y + 6)]
            return "".join(circ(x, yy, 7, WHITE, o, 1.2) for x, yy in cs) + "".join(circ(x, yy, 5.5, WHITE, None, 0) for x, yy in cs)
        return ""
    for st in ("short", "buzz", "bald", "ponytail", "bun", "long", "curly"):
        for d in ("front", "back", "side"):
            person_layer(f"hair_{st}_{d}", hair(st, d))

    # бороды
    def beard(st, d):
        y = HY
        if st == "full":
            if d == "front":
                return path(f"M-16 {y+2}Q-16 {y+18} 0 {y+20}Q16 {y+18} 16 {y+2}Q12 {y+10} 6 {y+9}Q0 {y+12} -6 {y+9}Q-12 {y+10} -16 {y+2}Z", WHITE, OUT, 1.2)
            return path(f"M-2 {y+4}Q-2 {y+18} 8 {y+19}Q16 {y+16} 16 {y+6}Q12 {y+10} 8 {y+9}Q4 {y+10} -2 {y+4}Z", WHITE, OUT, 1.2)
        if st == "mustache":
            if d == "front":
                return path(f"M-9 {y+8.5}Q-4 {y+5.5} 0 {y+8}Q4 {y+5.5} 9 {y+8.5}Q6 {y+11.5} 0 {y+10}Q-6 {y+11.5} -9 {y+8.5}Z", WHITE, OUT, 1)
            return path(f"M6 {y+8}Q11 {y+6} 15 {y+8.5}Q11 {y+11} 6 {y+9.5}Z", WHITE, OUT, 1)
        if st == "goatee":
            if d == "front":
                return path(f"M-6 {y+12}Q0 {y+22} 6 {y+12}Q3 {y+15} 0 {y+15}Q-3 {y+15} -6 {y+12}Z", WHITE, OUT, 1) + path(f"M-7 {y+8.5}Q0 {y+6} 7 {y+8.5}", None, WHITE, 2.4)
            return path(f"M8 {y+12}Q12 {y+20} 15 {y+12}Z", WHITE, OUT, 1)
        if st == "stubble":
            if d == "front":
                return path(f"M-15 {y+3}Q-15 {y+16} 0 {y+17}Q15 {y+16} 15 {y+3}Q12 {y+11} 0 {y+11}Q-12 {y+11} -15 {y+3}Z", WHITE, None, 0, 0.55)
            return path(f"M0 {y+5}Q0 {y+16} 9 {y+16}Q15 {y+14} 15 {y+5}Q10 {y+10} 0 {y+5}Z", WHITE, None, 0, 0.55)
        return ""
    for st in ("full", "mustache", "goatee", "stubble"):
        for d in ("front", "side"):
            person_layer(f"beard_{st}_{d}", beard(st, d))

    # очки
    gf = circ(-6.4, HY + 1, 5.2, "#cfe3ee", OUT, 1.6, None, 0.35) + circ(6.4, HY + 1, 5.2, "#cfe3ee", OUT, 1.6, None, 0.35) + line(-1.2, HY + 1, 1.2, HY + 1, OUT, 1.5)
    gf += line(-11.6, HY, -16, HY - 1, OUT, 1.4) + line(11.6, HY, 16, HY - 1, OUT, 1.4)
    person_layer("glasses_front", gf)
    person_layer("glasses_side", circ(9, HY + 1, 5, "#cfe3ee", OUT, 1.6, None, 0.35) + line(4, HY, -4, HY - 1, OUT, 1.5))

    # головные уборы (белые — тонируются)
    def hat(t, d):
        y = HY
        if t == "helmet":
            if d == "front":
                return path(f"M-19 {y-3}Q-19 {y-24} 0 {y-24}Q19 {y-24} 19 {y-3}Z", WHITE, OUT, 2) + path(f"M0 {y-24}V{y-5}", None, "#000", 3, 0.15) + rect(-22, y - 5, 44, 5, WHITE, OUT, 1.4, 2) + circ(-6, y - 17, 4, "#fff", None, 0, 0.45)
            if d == "back":
                return path(f"M-19.6 {y-1}Q-20 {y-24} 0 {y-24}Q20 {y-24} 19.6 {y-1}Z", WHITE, OUT, 2) + path(f"M0 {y-24}V{y-3}", None, "#000", 3, 0.15) + path(f"M-22 {y}Q0 {y+6} 22 {y}L21 {y+4}Q0 {y+10} -21 {y+4}Z", WHITE, OUT, 1.2)
            return path(f"M-19 {y-2}Q-19 {y-24} 0 {y-24}Q19 {y-24} 19 {y-2}Z", WHITE, OUT, 2) + path(f"M17 {y-4}L25 {y-1}L24 {y+1}L16 {y}Z", WHITE, OUT, 1.4) + path(f"M-2 {y-24}Q8 {y-18} 10 {y-3}", None, "#000", 3, 0.15)
        if t == "cap":
            if d == "front":
                return path(f"M-17.6 {y-4}Q-18 {y-21} 0 {y-21}Q18 {y-21} 17.6 {y-4}Z", WHITE, OUT, 1.6) + path(f"M-15 {y-5}Q0 {y+1} 15 {y-5}L13 {y-1}Q0 {y+4} -13 {y-1}Z", WHITE, OUT, 1.2) + path(f"M-15 {y-5}Q0 {y+1} 15 {y-5}L13 {y-1}Q0 {y+4} -13 {y-1}Z", "#000", None, 0, 0.25)
            if d == "back":
                return path(f"M-17.6 {y-2}Q-18 {y-21} 0 {y-21}Q18 {y-21} 17.6 {y-2}Z", WHITE, OUT, 1.6) + path(f"M-6 {y-4}H6", None, "#000", 3, 0.3)
            return path(f"M-17.6 {y-3}Q-18 {y-21} 0 {y-21}Q18 {y-21} 17.6 {y-3}Z", WHITE, OUT, 1.6) + path(f"M15 {y-6}L28 {y-3}L27 {y}L15 {y-1}Z", WHITE, OUT, 1.2) + path(f"M15 {y-6}L28 {y-3}L27 {y}L15 {y-1}Z", "#000", None, 0, 0.25)
        if t == "kerchief":
            if d == "front":
                return path(f"M-17.6 {y-1}Q-19 {y-21} 0 {y-21}Q19 {y-21} 17.6 {y-1}Q12 {y-9} 0 {y-9}Q-12 {y-9} -17.6 {y-1}Z", WHITE, OUT, 1.4) + path(f"M-12 {y-15}h2M2 {y-17}h2M8 {y-12}h2", None, "#fff", 2, 0.5)
            if d == "back":
                return path(f"M-17.6 {y+3}Q-19 {y-21} 0 {y-21}Q19 {y-21} 17.6 {y+3}Q10 {y+8} 0 {y+8}Q-10 {y+8} -17.6 {y+3}Z", WHITE, OUT, 1.4) + path(f"M-3 {y+7}L-7 {y+15}L0 {y+12}L7 {y+15}L3 {y+7}Z", WHITE, OUT, 1.2)
            return path(f"M-17.6 {y+3}Q-19 {y-21} 0 {y-21}Q17 {y-21} 16.8 {y-6}Q8 {y-10} -2 {y-9}Q-6 {y+2} -12 {y+8}Q-17 {y+8} -17.6 {y+3}Z", WHITE, OUT, 1.4) + path(f"M-14 {y+5}L-20 {y+12}L-12 {y+9}Z", WHITE, OUT, 1)
        return ""
    for t in ("helmet", "cap", "kerchief"):
        for d in ("front", "back", "side"):
            person_layer(f"hat_{t}_{d}", hat(t, d))
    # наушники
    ph = path(f"M-19 {HY+2}Q-20 {HY-26} 0 {HY-26}Q20 {HY-26} 19 {HY+2}", None, "#1d1d1d", 3)
    person_layer("phones_front", ph + rect(-23, HY - 6, 7, 14, "#2a2e31", OUT, 1.2, 3) + rect(16, HY - 6, 7, 14, "#2a2e31", OUT, 1.2, 3))
    person_layer("phones_back", ph + rect(-23, HY - 6, 7, 14, "#2a2e31", OUT, 1.2, 3) + rect(16, HY - 6, 7, 14, "#2a2e31", OUT, 1.2, 3))
    person_layer("phones_side", path(f"M-4 {HY-6}Q-4 {HY-26} 2 {HY-24}", None, "#1d1d1d", 3) + rect(-8, HY - 7, 10, 16, "#2a2e31", OUT, 1.2, 4))

    # --- этап 3: сварочная маска, фартук, респиратор
    def wmask(d):
        y = HY
        if d == "front":
            return (path(f"M-18 {y-6}Q-18 {y-24} 0 {y-24}Q18 {y-24} 18 {y-6}Z", WHITE, OUT, 1.8)
                    + rect(-9, y - 22, 18, 8, "#3a5a48", OUT, 1.2, 2) + rect(-7, y - 21, 6, 3, "#fff", None, 0, 0, 0.35)
                    + path(f"M-18 {y-6}H18", None, OUT, 2))
        if d == "back":
            return path(f"M-18 {y-2}Q-18 {y-24} 0 {y-24}Q18 {y-24} 18 {y-2}Z", WHITE, OUT, 1.8) + path(f"M-10 {y-4}H10", None, "#000", 3, 0.3)
        return (path(f"M-16 {y-4}Q-17 {y-24} 2 {y-24}Q18 {y-22} 20 {y-12}L24 {y-6}L16 {y-4}Z", WHITE, OUT, 1.8)
                + rect(12, y - 20, 7, 9, "#3a5a48", OUT, 1, 2))
    for d in ("front", "back", "side"):
        person_layer(f"hat_weldmask_{d}", wmask(d))
    AP = "#7a5236"
    person_layer("outfit_apron_front", path("M-15 -12H15V24Q0 27 -15 24Z", AP, OUT, 1.6) + path("M-15 -12L-12 -19M15 -12L12 -19", None, "#4a3020", 2.4) + rect(-8, 2, 16, 8, None, "#5a3a24", 1.2, 1))
    person_layer("outfit_apron_back", path("M-14 -18L12 8M14 -18L-12 8", None, "#4a3020", 2.6) + path("M-20 8H20", None, "#4a3020", 2.4))
    person_layer("outfit_apron_side", path("M8 -12H14Q16 6 14 24H6Q8 6 8 -12Z", AP, OUT, 1.4))
    person_layer("resp_front", path(f"M-8 {HY+5}Q0 {HY+2} 8 {HY+5}Q8 {HY+14} 0 {HY+15}Q-8 {HY+14} -8 {HY+5}Z", "#e9ecec", OUT, 1.2)
                 + circ(-8, HY + 11, 3.6, "#b0483d", OUT, 1) + circ(8, HY + 11, 3.6, "#b0483d", OUT, 1) + path(f"M-15 {HY+2}L-8 {HY+5}M15 {HY+2}L8 {HY+5}", None, "#3a3f43", 1.2))
    person_layer("resp_side", path(f"M4 {HY+4}Q12 {HY+2} 15 {HY+7}Q15 {HY+14} 8 {HY+15}Q4 {HY+12} 4 {HY+4}Z", "#e9ecec", OUT, 1.2) + circ(13, HY + 11, 3.4, "#b0483d", OUT, 1) + path(f"M4 {HY+5}L-6 {HY+1}", None, "#3a3f43", 1.2))

    # --- этап 4: костюм ИТР с галстуком
    person_layer("outfit_suit_front", poly([(-7, -19), (0, -3), (7, -19)], "#f2f2ee", OUT, 1)
                 + poly([(-1.8, -16), (1.8, -16), (3, 3), (0, 7), (-3, 3)], "#8a2e2e", OUT, 0.8)
                 + path("M-9 -19L-2 0M9 -19L2 0", None, "#000", 2.6, 0.35) + circ(0, 11, 1.3, "#000", None, 0, 0.4) + circ(0, 18, 1.3, "#000", None, 0, 0.4)
                 + path("M10 -6h7", None, "#f2f2ee", 2))
    person_layer("outfit_suit_back", path("M-8 -19Q0 -15 8 -19", None, "#f2f2ee", 2.4) + path("M0 -14V24", None, "#000", 1.2, 0.25))
    person_layer("outfit_suit_side", path("M8 -19L6 -2", None, "#000", 2.4, 0.35) + path("M10 -19L12 -14", None, "#f2f2ee", 2.4))
    # кисть руки
    save("assets/people/hand.svg", 16, 16, circ(8, 8, 6.2, WHITE, "#4e4e4e", 2.0))


# ------------------------------------------------------------------ фургон

def vehicles():
    # фургон «Газель»-образный, смотрит вправо. 3 тайла длиной.
    W, H = 216, 120
    base_y = 104  # линия колёс
    body = ell(110, base_y + 6, 100, 9, "#000", None, 0, 0.3)
    # кузов (белый — тонируется)
    body += rect(6, 18, 138, 26, "#ffffff", OUT, 2)                    # крыша фургона
    body += rect(6, 44, 138, 50, "#ffffff", OUT, 2)                    # борт
    body += rect(6, 44, 138, 50, "#000", None, 0, 0, 0.08)
    body += path("M144 30H170Q186 30 194 52L204 62V94H144Z", "#ffffff", OUT, 2)  # кабина
    save("assets/vehicles/van_body.svg", W, H, body)
    det = path("M150 36H168Q180 36 186 52L190 58H150Z", "#7fa4c4", OUT, 1.6)   # лобовое/боковое окно
    det += path("M154 40L162 54", None, "#fff", 2, 0.5)
    det += rect(8, 88, 196, 8, "#3a3e42", OUT, 1.5)                     # низ
    det += rect(196, 70, 8, 8, "#ffe9a8", OUT, 1) + rect(6, 70, 6, 10, "#c0392b", OUT, 1)
    det += line(144, 44, 144, 94, OUT, 2) + rect(160, 64, 8, 3, "#3a3e42", None, 0)
    for cx in (42, 172):
        det += circ(cx, base_y - 4, 13, "#1d1d1d", OUT, 1.5) + circ(cx, base_y - 4, 6, "#8a9196", OUT, 1)
    det += line(12, 22, 140, 22, "#fff", 2, 0.35)
    save("assets/vehicles/van_details.svg", W, H, det)
    META["van"] = {"w": W, "h": H, "ox": 0, "oy": base_y}


# ------------------------------------------------------------------ интерфейс и эффекты

def ui():
    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    icon("build", rect(8, 28, 14, 10, None, C, 3) + rect(22, 28, 14, 10, None, C, 3) + rect(15, 18, 14, 10, None, C, 3) + path("M30 10L40 20L36 24L26 14Z", None, C, 3))
    icon("objects", path("M10 18L24 10L38 18V32L24 40L10 32Z", None, C, 3) + path("M10 18L24 26L38 18M24 26V40", None, C, 3))
    icon("demolish", path("M12 36L28 20M24 12L36 24L32 28L20 16Z", None, C, 3.4) + path("M30 34l6 6M36 34l-6 6", None, "#d99a6a", 3))
    icon("orders", rect(12, 10, 24, 30, None, C, 3, 3) + rect(18, 7, 12, 6, C, None, 0, 2) + path("M17 22H31M17 28H31M17 34H26", None, C, 2.6))
    icon("supply", rect(6, 16, 22, 18, None, C, 3) + path("M28 22H36L42 28V34H28Z", None, C, 3) + circ(14, 37, 4, None, C, 3) + circ(36, 37, 4, None, C, 3))
    icon("staff", circ(24, 16, 7, None, C, 3) + path("M10 40Q10 26 24 26Q38 26 38 40", None, C, 3))
    icon("pause", rect(14, 12, 7, 24, C, None, 0, 1) + rect(27, 12, 7, 24, C, None, 0, 1))
    icon("play1", poly([(16, 12), (34, 24), (16, 36)], C, None, 0))
    icon("medal", poly([(14, 4), (22, 4), (27, 18), (19, 18)], "#c0392b", None, 0) + poly([(34, 4), (26, 4), (21, 18), (29, 18)], "#2e5f9e", None, 0)
         + circ(24, 30, 12, "#e2b33c", "#8a6a1c", 2) + circ(24, 30, 8, None, "#fff0b8", 1.4)
         + path("M24 23.5L25.9 27.6L30.3 28L27 31L28 35.4L24 33.1L20 35.4L21 31L17.7 28L22.1 27.6Z", "#fff6d6", None, 0))
    icon("medal_off", poly([(14, 4), (22, 4), (27, 18), (19, 18)], "#5a5d60", None, 0) + poly([(34, 4), (26, 4), (21, 18), (29, 18)], "#4a4d50", None, 0)
         + circ(24, 30, 12, "#55595d", "#3a3d40", 2) + circ(24, 30, 8, None, "#6c7074", 1.4))
    icon("play2", poly([(9, 12), (24, 24), (9, 36)], C, None, 0) + poly([(24, 12), (39, 24), (24, 36)], C, None, 0))
    icon("play3", poly([(4, 13), (17, 24), (4, 35)], C, None, 0) + poly([(17, 13), (30, 24), (17, 35)], C, None, 0) + poly([(30, 13), (43, 24), (30, 35)], C, None, 0))
    icon("money", rect(8, 14, 32, 20, None, "#9fd28a", 3, 3) + circ(24, 24, 5, None, "#9fd28a", 3))
    icon("clock", circ(24, 24, 15, None, C, 3) + path("M24 14V24L31 28", None, C, 3))
    icon("cancel", circ(24, 24, 15, None, C, 3) + path("M14 34L34 14", None, C, 3))
    icon("menu", path("M10 14H38M10 24H38M10 34H38", None, C, 3.4))
    icon("log", rect(10, 10, 28, 28, None, C, 3, 3) + path("M16 18H32M16 24H32M16 30H26", None, C, 2.6))
    icon("finance", path("M8 38H40M12 34V26M20 34V18M28 34V22M36 34V12", None, C, 3.4))
    icon("rooms", rect(8, 8, 32, 32, None, C, 3, 2) + path("M24 8V22M8 26H20M28 26H40M24 30V40", None, C, 3))
    icon("power", poly([(27, 6), (12, 27), (22, 27), (19, 42), (36, 19), (26, 19)], "#e8c34a", None, 0))
    icon("cable", path("M8 34Q8 14 24 14Q40 14 40 30", None, C, 3.4) + rect(4, 32, 8, 8, "#e8c34a", None, 0, 2) + rect(36, 28, 8, 8, "#e8c34a", None, 0, 2))
    icon("uncable", path("M8 34Q8 14 24 14Q40 14 40 30", None, C, 3.4, dash="4 4") + path("M30 32l10 10M40 32l-10 10", None, "#d99a6a", 3))
    icon("mood", circ(24, 24, 15, None, C, 3) + circ(18, 20, 2.4, C, None, 0) + circ(30, 20, 2.4, C, None, 0) + path("M16 28Q24 36 32 28", None, C, 3))
    icon("bolt_off", circ(24, 24, 18, "#2a1d1d", "#d8644e", 3) + poly([(27, 9), (14, 27), (22, 27), (19, 40), (34, 20), (26, 20)], "#e8c34a", None, 0) + path("M11 37L37 11", None, "#d8644e", 4))
    icon("power_off", circ(24, 24, 18, "#2a1d1d", "#d8644e", 3) + poly([(27, 9), (14, 27), (22, 27), (19, 40), (34, 20), (26, 20)], "#8a8a84", None, 0))
    # этапы 3–7
    gear = ""
    for k in range(8):
        a = k * math.pi / 4
        gear += line(24 + math.cos(a) * 12, 24 + math.sin(a) * 12, 24 + math.cos(a) * 18, 24 + math.sin(a) * 18, C, 5)
    icon("shop", gear + circ(24, 24, 12, None, C, 3.4) + circ(24, 24, 4.5, None, C, 3))
    icon("wrench", path("M12 38L28 22", None, C, 5) + path("M26 14a8 8 0 1 0 8 8l-5 -1l-2 -2z", None, C, 3))
    icon("research", path("M18 6H30M20 6V18L10 38Q9 42 13 42H35Q39 42 38 38L28 18V6", None, C, 3) + path("M14 30H34", None, "#8fd0e8", 3) + circ(22, 36, 2, "#8fd0e8", None, 0) + circ(28, 33, 1.5, "#8fd0e8", None, 0))
    icon("paper", rect(8, 10, 32, 30, None, C, 3, 2) + rect(13, 15, 22, 7, C, None, 0) + path("M13 27H22M13 32H22M13 37H22M26 27H35M26 32H35M26 37H35", None, C, 2))
    icon("goals", poly([(24, 6), (29, 18), (42, 19), (32, 28), (35, 41), (24, 34), (13, 41), (16, 28), (6, 19), (19, 18)], None, C, 3))
    icon("office", rect(7, 16, 34, 24, None, C, 3, 3) + path("M18 16V11H30V16M7 26H41", None, C, 3) + rect(21, 23, 6, 6, C, None, 0, 1))
    icon("overlay", path("M24 8L42 17L24 26L6 17Z", None, C, 3) + path("M6 24L24 33L42 24M6 31L24 40L42 31", None, C, 3))
    icon("calendar", rect(8, 10, 32, 30, None, C, 3, 3) + path("M8 19H40M16 6V13M32 6V13", None, C, 3) + rect(14, 24, 6, 5, C, None, 0) + rect(24, 24, 6, 5, C, None, 0) + rect(14, 32, 6, 5, C, None, 0))
    icon("strike", rect(10, 8, 26, 16, None, C, 3, 2) + path("M14 14H32M14 19H26M18 24V42", None, C, 3) + path("M30 30l10 10M40 30l-10 10", None, "#d8644e", 3))
    icon("snow", path("M24 6V42M8.4 15L39.6 33M8.4 33L39.6 15", None, "#bfe3f2", 3) + path("M19 9L24 13L29 9M19 39L24 35L29 39", None, "#bfe3f2", 2.4))
    icon("fire", path("M24 42Q10 40 12 28Q14 20 20 14Q20 22 25 24Q24 14 30 6Q32 16 36 22Q40 30 35 37Q31 42 24 42Z", "#e8853a", "#fff3c8", 2))
    # эффекты
    save("assets/fx/glow.svg", 128, 128,
         '<defs><radialGradient id="g" cx="50%" cy="50%" r="50%"><stop offset="0%" stop-color="#fff2c8" stop-opacity="0.55"/>'
         '<stop offset="60%" stop-color="#ffe9a8" stop-opacity="0.15"/><stop offset="100%" stop-color="#ffe9a8" stop-opacity="0"/></radialGradient></defs>'
         '<circle cx="64" cy="64" r="64" fill="url(#g)"/>')
    save("assets/fx/smoke.svg", 32, 32, circ(16, 16, 12, "#e8ecef", None, 0, 0.8))
    save("assets/fx/beam.svg", 128, 128, poly([(0, 0), (70, 0), (128, 128), (58, 128)], "#fff3cf", None, 0))
    # иконка приложения
    b = rect(0, 0, 256, 256, "#1d2024", None, 0, 40)
    b += rect(28, 120, 200, 100, "#6e5a4c", OUT, 6) + rect(28, 104, 200, 22, "#2e3136", OUT, 6)
    b += poly([(28, 104), (70, 60), (112, 104)], "#3a3e44", OUT, 6) + poly([(112, 104), (154, 60), (196, 104)], "#3a3e44", OUT, 6)
    b += rect(176, 30, 26, 74, "#8a3e3a", OUT, 6) + rect(176, 30, 26, 10, "#d9b13b", None, 0)
    b += rect(52, 146, 46, 32, "#8fb3c8", OUT, 5) + rect(158, 146, 46, 32, "#8fb3c8", OUT, 5) + rect(108, 160, 40, 60, "#3a3f43", OUT, 5)
    b += circ(196, 196, 34, "#d9b13b", OUT, 6) + circ(196, 196, 12, "#1d2024", OUT, 5)
    for k in range(8):
        a = k * math.pi / 4
        b += rect(196 + math.cos(a) * 34 - 6, 196 + math.sin(a) * 34 - 6, 12, 12, "#d9b13b", OUT, 3)
    save("icon.svg", 256, 256, b)


# ------------------------------------------------------------------ этап 5: мир и события

def stage5():
    """Отопление, безопасность, проходная, огонь, снег, реквизит людей, зимние шапки, иконки событий."""
    HY = -34
    # --- чугунная батарея отопления 1×1 (7 секций на ножках, крашеная)
    T0 = 30
    b = shadow(10, T0 + 10, 50, 40)
    b += line(10, T0 + 2, 54, T0 + 2, "#8a8f92", 3) + line(10, T0 + 40, 54, T0 + 40, "#8a8f92", 3)
    for k in range(7):
        x = 8 + k * 7
        b += rect(x, T0 - 6, 6.4, 50, "#e9e4d6", OUT, 1.4, 3)
        b += line(x + 1.6, T0 - 2, x + 1.6, T0 + 40, "#ffffff", 1.2, 0.7) + line(x + 4.8, T0 - 2, x + 4.8, T0 + 40, "#b9b3a2", 1.2, 0.8)
    b += rect(6, T0 + 44, 4, 10, "#5a6064", OUT, 1) + rect(54, T0 + 44, 4, 10, "#5a6064", OUT, 1)
    b += path(f"M58 {T0+2}H62V{T0-20}", None, "#8a8f92", 3) + circ(58, T0 + 2, 3, "#c94a3a", OUT, 1)
    obj("radiator", 1, 1, T0, b)
    META["radiator"]["anchors"] = {"heat": [32, T0 - 10]}

    # --- аптечка на стойке
    T0 = 56
    b = ell(32, T0 + 56, 16, 4, "#000", None, 0, 0.22)
    b += rect(29, T0 + 4, 6, 52, "#6a7075", OUT, 1.4) + rect(20, T0 + 52, 24, 5, "#4a5055", OUT, 1.2, 2)
    b += box(12, T0 - 40, 40, 8, 40, "#f2f0ea", "#d8d4c8")
    b += rect(27, T0 - 22, 10, 26, "#c9372c", None, 0) + rect(19, T0 - 14, 26, 10, "#c9372c", None, 0)
    b += rect(48, T0 - 20, 3, 10, "#9a968a", None, 0, 1)
    obj("first_aid", 1, 1, T0, b)

    # --- проходная: с 1.30 — будка охранника и два турникета 4×1, рисует tools/gen_v130.py (без лица вахтёрши)

    # --- пламя (эффект): три слоя
    fl = path("M32 62Q8 58 10 38Q12 26 20 16Q20 28 27 31Q24 16 34 2Q38 18 44 26Q50 18 48 10Q58 24 56 40Q54 58 32 62Z", "#d8452a", None, 0, 0.92)
    fl += path("M32 60Q16 56 17 42Q18 32 24 26Q25 36 31 38Q30 26 36 16Q40 28 44 34Q48 30 48 24Q52 36 49 46Q46 58 32 60Z", "#f08a2a", None, 0)
    fl += path("M32 58Q23 55 24 46Q25 40 29 36Q30 44 34 44Q34 36 38 30Q42 40 42 46Q42 56 32 58Z", "#ffd54a", None, 0)
    fl += ell(32, 54, 6, 3, "#fff6c8", None, 0, 0.8)
    save("assets/fx/flame.svg", 64, 64, fl)
    save("assets/fx/soot.svg", 64, 64, ell(32, 32, 28, 22, "#1d1a18", None, 0, 0.55) + ell(24, 28, 9, 6, "#000", None, 0, 0.3) + ell(40, 38, 8, 5, "#000", None, 0, 0.3))
    save("assets/fx/smoke_dark.svg", 32, 32, circ(16, 16, 12, "#4a4a4a", None, 0, 0.75))
    save("assets/fx/flake.svg", 16, 16, circ(8, 8, 3.2, "#ffffff", None, 0, 0.95) + circ(8, 8, 6, "#ffffff", None, 0, 0.2))
    save("assets/fx/spark.svg", 16, 16, circ(8, 8, 3, "#fff3b0", None, 0) + circ(8, 8, 6, "#ffb040", None, 0, 0.35))

    # --- снег: 4 варианта тайла, белый с голубыми тенями и искрами
    for v in range(4):
        rng = random.Random(500 + v)
        s = rect(0, 0, 64, 64, "#eef3f6", None, 0)
        for _ in range(9):
            s += ell(rng.uniform(4, 60), rng.uniform(4, 60), rng.uniform(5, 13), rng.uniform(3, 7), "#d6e2ea", None, 0, 0.7)
        for _ in range(14):
            s += circ(rng.uniform(2, 62), rng.uniform(2, 62), rng.uniform(0.6, 1.3), "#ffffff", None, 0)
        if v == 2:
            s += path("M6 40q8 -4 14 0t14 0", None, "#c8d6e0", 1.4)
        save(f"assets/tiles/snow_{v}.svg", 64, 64, s)
    save("assets/fx/snow_blob.svg", 96, 96,
         '<defs><radialGradient id="s" cx="50%" cy="50%" r="50%"><stop offset="0%" stop-color="#eef3f6" stop-opacity="1"/>'
         '<stop offset="55%" stop-color="#e8eff4" stop-opacity="0.92"/><stop offset="100%" stop-color="#e2eaf0" stop-opacity="0"/></radialGradient></defs>'
         '<circle cx="48" cy="48" r="48" fill="url(#s)"/>')
    save("assets/tiles/ice.svg", 64, 64, rect(0, 0, 64, 64, "#bcd8e8", None, 0, 0, 0.6) + path("M8 50L30 30L52 40M30 30L36 8", None, "#ffffff", 1.6, 0.7))

    # --- реквизит людей (32×32, держат в руке)
    def prop(key, body):
        save(f"assets/people/prop_{key}.svg", 32, 32, body)
    prop("folder", rect(7, 4, 18, 24, "#7a5236", OUT, 1.4, 2) + rect(9, 7, 14, 19, "#f4f1e6", None, 0) + rect(12, 2, 8, 5, "#9aa3a8", OUT, 1, 1)
         + path("M11 12h10M11 16h10M11 20h7", None, "#6a6458", 1.2))
    prop("camera", rect(4, 10, 24, 16, "#2a2e31", OUT, 1.4, 3) + rect(8, 7, 8, 4, "#3a3f43", OUT, 1, 1) + circ(17, 18, 6, "#5a6a7a", OUT, 1.4) + circ(17, 18, 3, "#9cc4dc", None, 0) + rect(23, 12, 3, 2, "#e8e4d8", None, 0))
    prop("sign", rect(14.5, 14, 3, 18, "#8a6a44", OUT, 1) + rect(2, 1, 28, 16, "#f4f1e6", OUT, 1.6, 1) + path("M6 6h20M6 10h14", None, "#c9372c", 2.2) + path("M22 10h4", None, "#23262a", 2))
    prop("shovel", line(16, 2, 16, 22, "#8a6a44", 2.6) + rect(12, 1, 8, 3, "#5a4030", OUT, 1, 1) + path("M7 22H25L23 31H9Z", "#5a7a9a", OUT, 1.4) + line(9, 25, 23, 25, "#8aaac8", 1.2))
    prop("ext", rect(10, 8, 12, 22, "#c9372c", OUT, 1.4, 4) + rect(13, 4, 6, 5, "#2a2e31", OUT, 1) + path("M19 6Q27 6 27 14", None, "#2a2e31", 2) + rect(12, 14, 8, 6, "#f4f1e6", None, 0, 1))
    prop("flowers", path("M16 30L12 14M16 30L16 12M16 30L20 14", None, "#4a7a3a", 1.6) + circ(12, 12, 4, "#e85a7a", OUT, 1) + circ(16, 9, 4, "#f2c94a", OUT, 1) + circ(20, 12, 4, "#e85a7a", OUT, 1) + poly([(10, 22), (22, 22), (18, 30), (14, 30)], "#e8e4d8", OUT, 1))

    # --- форма инспектора, шапка-ушанка, фуражка
    person_layer("outfit_uniform_front", path("M0 -19V25", None, "#000", 1.4, 0.35) + circ(0, -8, 1.4, "#d9b13b", None, 0) + circ(0, 2, 1.4, "#d9b13b", None, 0) + circ(0, 12, 1.4, "#d9b13b", None, 0)
                 + rect(-21, -18, 9, 4, "#d9b13b", OUT, 0.8, 1) + rect(12, -18, 9, 4, "#d9b13b", OUT, 0.8, 1) + rect(-22, 8, 44, 4, "#2a2e31", None, 0, 0, 0.7) + rect(-3, 7, 6, 6, "#c9b37a", OUT, 0.8)
                 + poly([(-6, -19), (0, -13), (6, -19)], "#f2f2ee", OUT, 0.8))
    person_layer("outfit_uniform_back", rect(-21, -18, 9, 4, "#d9b13b", OUT, 0.8, 1) + rect(12, -18, 9, 4, "#d9b13b", OUT, 0.8, 1) + rect(-22, 8, 44, 4, "#2a2e31", None, 0, 0, 0.7))
    person_layer("outfit_uniform_side", rect(-6, -18, 10, 4, "#d9b13b", OUT, 0.8, 1) + rect(-16, 8, 32, 4, "#2a2e31", None, 0, 0, 0.7) + circ(10, -4, 1.3, "#d9b13b", None, 0) + circ(10, 6, 1.3, "#d9b13b", None, 0))

    def hat2(t, d):
        y = HY
        if t == "ushanka":
            fur = "#ffffff"
            D = "#000"
            tuft = lambda x0, y0, n, step: "".join(f"M{x0 + k*step} {y0}q1.5 -2.5 3 0" for k in range(n))
            if d == "front":
                return (path(f"M-21 {y+12}Q-25 {y-2} -20 {y-7}L-12 {y-7}Q-12 {y+4} -14 {y+13}Z", fur, OUT, 1.4) + path(f"M21 {y+12}Q25 {y-2} 20 {y-7}L12 {y-7}Q12 {y+4} 14 {y+13}Z", fur, OUT, 1.4)
                        + path(f"M-20 {y-5}Q-21 {y-27} 0 {y-27}Q21 {y-27} 20 {y-5}Z", fur, OUT, 1.8)
                        + path(f"M0 {y-27}V{y-9}", None, D, 1.4, 0.3) + path(f"M-20 {y-10}Q0 {y-16} 20 {y-10}", None, D, 1.2, 0.3)
                        + path(f"M-22 {y-8}Q0 {y-14} 22 {y-8}L22 {y-1}Q0 {y-7} -22 {y-1}Z", fur, OUT, 1.4)
                        + path(f"M-22 {y-8}Q0 {y-14} 22 {y-8}L22 {y-1}Q0 {y-7} -22 {y-1}Z", D, None, 0, 0.28)
                        + path(tuft(-19, y - 4, 13, 3), None, D, 1.1, 0.35)
                        + path(f"M-21 {y+12}Q-25 {y-2} -20 {y-7}L-12 {y-7}Q-12 {y+4} -14 {y+13}Z", D, None, 0, 0.28)
                        + path(f"M21 {y+12}Q25 {y-2} 20 {y-7}L12 {y-7}Q12 {y+4} 14 {y+13}Z", D, None, 0, 0.28))
            if d == "back":
                return (path(f"M-21 {y+8}Q-23 {y-27} 0 {y-27}Q23 {y-27} 21 {y+8}Q0 {y+14} -21 {y+8}Z", fur, OUT, 1.8)
                        + path(f"M0 {y-27}V{y+10}", None, D, 1.4, 0.3)
                        + path(f"M-21 {y+8}Q0 {y+14} 21 {y+8}L21 {y}Q0 {y+6} -21 {y}Z", D, None, 0, 0.3) + path(tuft(-18, y + 6, 12, 3), None, D, 1.1, 0.35))
            return (path(f"M-19 {y+8}Q-21 {y-27} 2 {y-27}Q21 {y-26} 21 {y-7}L14 {y-7}Q6 {y-13} -4 {y-9}Q-6 {y+4} -11 {y+14}Q-18 {y+14} -19 {y+8}Z", fur, OUT, 1.8)
                    + path(f"M-11 {y+14}Q-18 {y+14} -19 {y+8}Q-20 {y-2} -16 {y-7}Q-9 {y-4} -6 {y-5}Q-7 {y+5} -11 {y+14}Z", D, None, 0, 0.3)
                    + path(f"M-4 {y-9}Q6 {y-13} 14 {y-7}L21 {y-7}Q21 {y-12} 18 {y-15}Q6 {y-18} -6 {y-14}Z", D, None, 0, 0.28)
                    + path(f"M2 {y-27}Q-2 {y-18} -4 {y-9}", None, D, 1.3, 0.3) + path(tuft(-2, y - 12, 7, 3), None, D, 1.1, 0.35))
        if t == "peaked":
            if d == "front":
                return (path(f"M-20 {y-10}Q-20 {y-26} 0 {y-27}Q20 {y-26} 20 {y-10}Z", WHITE, OUT, 1.6) + rect(-17, y - 13, 34, 6, "#c9372c", OUT, 1)
                        + path(f"M-15 {y-7}Q0 {y-1} 15 {y-7}L13 {y-3}Q0 {y+1} -13 {y-3}Z", "#1d1d1d", OUT, 1) + circ(0, y - 18, 3, "#d9b13b", OUT, 0.8))
            if d == "back":
                return path(f"M-20 {y-6}Q-20 {y-26} 0 {y-27}Q20 {y-26} 20 {y-6}Z", WHITE, OUT, 1.6) + rect(-17, y - 10, 34, 6, "#c9372c", OUT, 1)
            return (path(f"M-18 {y-8}Q-19 {y-26} 2 {y-27}Q22 {y-26} 20 {y-8}Z", WHITE, OUT, 1.6) + rect(-16, y - 12, 34, 6, "#c9372c", OUT, 1)
                    + path(f"M14 {y-8}L27 {y-5}L26 {y-2}L14 {y-4}Z", "#1d1d1d", OUT, 1))
        return ""
    for t in ("ushanka", "peaked"):
        for d in ("front", "back", "side"):
            person_layer(f"hat_{t}_{d}", hat2(t, d))

    # --- иконки событий и окон
    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    icon("inspect", rect(10, 8, 28, 34, None, C, 3, 3) + rect(18, 5, 12, 6, C, None, 0, 2) + path("M16 24l5 5 10 -11", None, "#8fcf78", 3.4) + path("M16 36H32", None, C, 2.4))
    icon("injury", rect(6, 6, 36, 36, None, C, 3, 8) + rect(20, 12, 8, 24, "#d8644e", None, 0, 1) + rect(12, 20, 24, 8, "#d8644e", None, 0, 1))
    icon("party", path("M6 12Q24 24 42 12", None, C, 2.4) + poly([(10, 14), (16, 17), (12, 24)], "#d8644e", None, 0) + poly([(20, 18), (27, 19), (23, 27)], "#e8c34a", None, 0) + poly([(31, 18), (37, 15), (36, 23)], "#8fd0e8", None, 0)
         + path("M14 34l2 -4 2 4M30 38l2 -4 2 4M22 42l2 -4 2 4", None, C, 2))
    icon("idea", path("M24 6Q36 6 36 18Q36 25 30 29V34H18V29Q12 25 12 18Q12 6 24 6Z", None, "#e8c34a", 3) + path("M18 38H30M20 42H28", None, C, 3) + path("M24 14V24", None, "#e8c34a", 2.4))
    icon("press", rect(6, 14, 36, 24, None, C, 3, 4) + rect(14, 9, 10, 6, C, None, 0, 1) + circ(25, 26, 7, None, C, 3) + circ(25, 26, 2.5, C, None, 0) + rect(34, 18, 4, 3, "#e8c34a", None, 0))
    icon("chart_up", path("M8 38H40M8 38V8", None, C, 3) + path("M12 32L20 24L26 28L38 14", None, "#d8644e", 3.4) + path("M31 14H38V21", None, "#d8644e", 3.4))
    icon("chart_down", path("M8 38H40M8 38V8", None, C, 3) + path("M12 14L20 22L26 18L38 32", None, "#8fcf78", 3.4) + path("M31 32H38V25", None, "#8fcf78", 3.4))
    icon("letter", rect(6, 12, 36, 26, None, C, 3, 3) + path("M6 14L24 28L42 14", None, C, 3))
    icon("thief", circ(24, 18, 10, None, C, 3) + rect(13, 14, 22, 7, C, None, 0, 3) + circ(19, 17, 2, "#1d2024", None, 0) + circ(29, 17, 2, "#1d2024", None, 0) + path("M10 42Q10 30 24 30Q38 30 38 42", None, C, 3))
    icon("heat", rect(8, 14, 32, 24, None, C, 3, 3) + path("M15 14V38M21 14V38M27 14V38M33 14V38", None, C, 2.4) + path("M16 8q3 -3 0 -6M24 10q3 -3 0 -6M32 8q3 -3 0 -6", None, "#d8644e", 2))
    icon("thermo", rect(20, 6, 8, 28, None, C, 3, 4) + circ(24, 37, 7, "#d8644e", C, 3) + rect(22.5, 18, 3, 16, "#d8644e", None, 0) + path("M30 12h5M30 18h5M30 24h5", None, C, 2))
    icon("handshake", path("M4 22L14 14L22 18L30 14L44 22", None, C, 3) + path("M10 24L20 34Q24 37 27 33L36 24", None, C, 3) + path("M18 26l6 6M23 24l6 6", None, C, 2.4))
    icon("court", path("M8 40H40M12 36H36M14 18V34M22 18V34M30 18V34M10 16L24 8L38 16Z", None, C, 3))
    icon("star", poly([(24, 5), (29, 18), (43, 18), (32, 27), (36, 41), (24, 33), (12, 41), (16, 27), (5, 18), (19, 18)], "#e8c34a", None, 0))


# ------------------------------------------------------------------ этап 6: профили заводов, сценарии

def stage6():
    """Новые изделия по профилям, испытательный стенд, собаки, лужи, иконки сценариев и профилей."""
    def save_item(key, body):
        save(f"assets/items/{key}.svg", 32, 32, body)
    sh = ell(16, 27, 13, 3, "#000", None, 0, 0.25)
    # диск бороны
    save_item("disc", sh + ell(16, 15, 13, 10, "#8f979c", OUT, 1.5) + ell(16, 14, 9, 6.5, "#a9b0b4", None, 0) + ell(16, 14, 3, 2.2, "#3a3f43", OUT, 1) + path("M7 18Q16 24 25 18", None, "#6a7276", 1.2))
    # секция бороны (рама с зубьями)
    b = sh + rect(4, 8, 24, 13, None, "#c9372c", 3) + rect(4, 8, 24, 13, None, OUT, 0.8) + line(16, 8, 16, 21, "#c9372c", 2.6)
    for k in range(5):
        b += line(6 + k * 5, 21, 6 + k * 5, 26, "#6a7074", 2)
    save_item("harrow", b)
    # балка двутавр
    save_item("beam", sh + poly([(2, 10), (26, 10), (30, 7), (6, 7)], "#8a949c", OUT, 1.2) + rect(2, 10, 24, 3, "#6a7480", OUT, 1.2) + rect(12, 13, 4, 7, "#6a7480", OUT, 1.2) + rect(2, 20, 24, 3, "#6a7480", OUT, 1.2)
              + poly([(26, 10), (30, 7), (30, 10), (26, 13)], "#5a646c", OUT, 1))
    # ферма
    save_item("truss", sh + path("M2 23H30L16 6Z", None, "#5a6a58", 2.6) + path("M9 23L16 6L23 23M9 23L12.5 14.5M23 23L19.5 14.5", None, "#5a6a58", 1.6) + path("M2 23H30L16 6Z", None, OUT, 0.6))
    # задвижка
    save_item("valve", sh + rect(4, 15, 24, 9, "#3d6a9a", OUT, 1.4, 2) + rect(1, 14, 4, 11, "#8a9196", OUT, 1) + rect(27, 14, 4, 11, "#8a9196", OUT, 1)
              + rect(14, 7, 4, 9, "#9aa3a8", OUT, 1) + ell(16, 6, 9, 2.6, None, "#c9372c", 2.2))
    # насос
    save_item("pump", sh + rect(14, 10, 15, 13, "#3d6a9a", OUT, 1.4, 3) + line(16, 12, 16, 21, "#2a4a6a", 1) + line(19, 12, 19, 21, "#2a4a6a", 1) + line(22, 12, 22, 21, "#2a4a6a", 1)
              + circ(9, 16, 7, "#5a8aba", OUT, 1.4) + circ(9, 16, 2.4, "#2a3a4a", None, 0) + rect(6, 4, 6, 6, "#8a9196", OUT, 1) + rect(3, 22, 26, 3, "#4a5056", OUT, 1))
    # ось вагонная
    save_item("axle", sh + rect(3, 14, 26, 4, "#b9c0c4", OUT, 1.2, 1) + rect(5, 11, 5, 10, "#a9b0b4", OUT, 1.2, 1) + rect(22, 11, 5, 10, "#a9b0b4", OUT, 1.2, 1)
              + rect(1, 13, 3, 6, "#cdd3d7", OUT, 1) + rect(28, 13, 3, 6, "#cdd3d7", OUT, 1) + line(10, 15, 22, 15, "#fff", 1, 0.5))
    # тормозной цилиндр
    save_item("brake_cyl", sh + rect(6, 9, 18, 14, "#4a4f55", OUT, 1.4, 4) + rect(8, 11, 14, 2.5, "#6a7076", None, 0) + rect(23, 13, 7, 6, "#b9c0c4", OUT, 1) + rect(2, 11, 5, 10, "#8a9196", OUT, 1) + circ(15, 18, 1.4, "#c9372c", None, 0))
    # станок настольный
    save_item("bench_lathe", sh + rect(3, 19, 26, 5, "#4a7a5a", OUT, 1.2) + rect(3, 9, 9, 10, "#4a7a5a", OUT, 1.2) + rect(12, 13, 15, 3, "#9aa3a8", OUT, 1) + rect(22, 10, 5, 9, "#4a7a5a", OUT, 1)
              + circ(7, 13, 2.2, "#c9ccce", OUT, 0.8) + rect(4, 24, 3, 3, "#3a3f43", None, 0) + rect(25, 24, 3, 3, "#3a3f43", None, 0))
    # изделие 7Т и узел 12-К — абстрактно
    save_item("item7t", sh + rect(4, 8, 24, 16, "#4a5a3a", OUT, 1.5, 3) + rect(6, 10, 20, 3, "#6a7a5a", None, 0) + rect(8, 15, 7, 6, "#e8e4d0", None, 0, 1) + rect(17, 15, 7, 6, "#e8e4d0", None, 0, 1)
              + line(9, 16.5, 14, 16.5, "#3a3a30", 1) + line(18, 16.5, 23, 16.5, "#3a3a30", 1) + line(9, 19, 13, 19, "#3a3a30", 1) + circ(26, 10, 1.4, "#c9372c", None, 0))
    save_item("node12k", sh + rect(5, 9, 22, 14, "#7a8086", OUT, 1.4, 6) + rect(9, 9, 3, 14, "#5a6066", None, 0) + rect(20, 9, 3, 14, "#5a6066", None, 0) + ell(16, 16, 3, 3, "#c9a45a", OUT, 1))

    # испытательный стенд 2×1: рама, бак, манометры, дефектоскоп
    T0 = 54
    b = shadow(12, T0 - 20, 120, 80)
    b += box(4, T0 - 2, 120, 14, 50, "#3d6a9a", "#2e5478")
    b += rect(10, T0 + 16, 108, 22, None, "#24405c", 1.4, 2)
    b += box(12, T0 - 40, 34, 10, 40, "#9aa3a8", "#7a8388")
    b += rect(16, T0 - 34, 26, 6, "#6fa8d8", None, 0, 1, 0.8)
    b += path(f"M46 {T0-20}H62V{T0-2}", None, "#5a6064", 3) + path(f"M62 {T0-8}H96", None, "#5a6064", 3)
    for gx in (60, 82):
        b += circ(gx, T0 - 30, 9, "#f4f1e6", OUT, 1.6) + circ(gx, T0 - 30, 6.5, None, "#c9ccce", 1) + line(gx, T0 - 30, gx + 4, T0 - 35, "#c9372c", 1.6) + rect(gx - 1.5, T0 - 21, 3, 8, "#5a6064", None, 0)
    b += box(98, T0 - 44, 22, 8, 40, "#2e3440", "#232830") + rect(101, T0 - 38, 16, 11, "#1d2a34", OUT, 1) + path(f"M102 {T0-32}l3 -3 2 5 3 -6 2 4 3 -2", None, "#6fe08a", 1)
    b += circ(108, T0 - 22, 2, "#e8c34a", None, 0) + circ(114, T0 - 22, 2, "#6fbf86", None, 0)
    b += rect(20, T0 + 2, 70, 9, "#cdd3d7", OUT, 1.2, 4)
    obj("test_stand", 2, 1, T0, b)
    META["test_stand"]["anchors"] = {"lamp": [108, T0 - 22], "work": [56, T0 + 4], "in": [112, T0 + 30], "out": [16, T0 + 30], "gauge": [60, T0 - 30], "gauge2": [82, T0 - 30], "screen": [109, T0 - 33]}

    # бродячая собака (вид сбоку, смотрит вправо) — два кадра шага
    def dog(frame):
        col = "#ffffff"
        legs = [(14, 0), (20, 0), (34, 0), (40, 0)]
        d = ell(28, 41, 18, 3.5, "#000", None, 0, 0.25)
        for k, (x, _) in enumerate(legs):
            off = (2 if (k % 2 == frame) else -2)
            d += path(f"M{x} 30L{x + off} 40", None, OUT, 4.2) + path(f"M{x} 30L{x + off} 40", None, col, 2.6)
        d += path("M8 24Q2 20 4 14", None, OUT, 3.6) + path("M8 24Q2 20 4 14", None, col, 2)
        d += path("M10 22Q10 15 22 15H34Q44 15 44 24Q44 31 34 31H20Q10 31 10 22Z", col, OUT, 1.8)
        d += path("M38 18Q40 8 48 9Q56 10 56 17Q55 22 48 22Q42 23 38 18Z", col, OUT, 1.8)
        d += path("M42 11L40 3L47 9Z", col, OUT, 1.4) + circ(50, 14, 1.6, "#1d1d1d", None, 0) + circ(56, 17, 1.8, "#1d1d1d", None, 0)
        d += path("M14 18Q24 16 34 18", None, "#000", 3, 0.12)
        return d
    for f in (0, 1):
        save(f"assets/fx/dog_{f}.svg", 64, 48, dog(f))
    save("assets/fx/dog_spots.svg", 64, 48, ell(24, 21, 6, 4, "#000", None, 0, 0.35) + ell(46, 13, 4, 3, "#000", None, 0, 0.35) + path("M42 11L40 3L47 9Z", "#000", None, 0, 0.35))
    # лужа и капли
    save("assets/fx/puddle.svg", 64, 64, ell(32, 34, 24, 14, "#5f8fb0", None, 0, 0.55) + ell(26, 30, 10, 4, "#cfe6f4", None, 0, 0.45) + ell(40, 38, 8, 3, "#3f6f90", None, 0, 0.35))
    save("assets/fx/drop.svg", 16, 16, path("M8 2Q12 9 8 14Q4 9 8 2Z", "#8fc4e8", None, 0, 0.9))

    # иконки сценариев и этапов
    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    icon("scn_garage", rect(6, 16, 36, 26, None, C, 3, 2) + path("M4 18L24 6L44 18", None, C, 3) + rect(16, 26, 16, 16, None, C, 2.6) + path("M16 31H32M16 36H32", None, C, 2))
    icon("scn_field", path("M4 38H44", None, C, 3) + path("M8 38L14 26L20 38M24 38V20H36V38", None, C, 2.6) + path("M30 20V12M26 12H40", None, "#e8c34a", 2.6) + circ(38, 8, 3, "#e8c34a", None, 0))
    icon("scn_ussr", rect(6, 18, 36, 22, None, C, 3) + path("M6 18L14 10H34L42 18", None, C, 3) + path("M14 28L18 24L22 30M30 26l4 6", None, "#d8644e", 2.4) + rect(30, 4, 6, 10, None, C, 2.4))
    icon("scn_mono", path("M4 40H44M8 40V22H18V40M22 40V14H34V40M38 40V26H44", None, C, 2.8) + path("M26 14V6M30 14V9", None, C, 2.4) + path("M26 4q2 -2 4 0", None, "#9aa3ab", 2))
    icon("scn_sandbox", rect(6, 24, 36, 16, None, C, 3, 3) + circ(16, 18, 6, None, "#e8c34a", 2.6) + path("M28 24L34 10L40 24", None, C, 2.6))
    icon("stage_up", path("M8 38H16V30H24V22H32V14H40", None, C, 3.2) + path("M30 8H40V18", None, "#8fcf78", 3.2))



def objects_v():
    """Повёрнутые на 90° варианты вытянутых объектов (футпринт 1×N): длинная ось — сверху вниз,
    рабочая сторона (где стоит человек) — слева. Для поворота на 270° спрайт отражается."""
    GT, GF = "#7d9283", "#5e7364"
    # --- токарный 1×3: передняя бабка вверху, станина вниз, суппорт, задняя бабка
    T0 = 46
    H = 192
    b = shadow(12, T0 - 10, 52, H + 6)
    b += rect(14, T0 + 30, 36, H - 44, "#5c6267", OUT, 2)                      # станина (основание)
    b += rect(20, T0 + 30, 24, H - 50, "#8b9296", OUT, 1.6)                     # направляющие
    b += line(26, T0 + 32, 26, T0 + H - 22, "#b2b9bd", 1.4) + line(38, T0 + 32, 38, T0 + H - 22, "#b2b9bd", 1.4)
    b += rect(4, T0 + 60, 10, H - 92, "#33383c", OUT, 1.4)                     # лоток для стружки слева
    b += path(f"M6 {T0+80}q3 4 0 8t0 8M8 {T0+120}q3 4 0 8M6 {T0+150}q3 3 0 7", None, "#c7a46a", 1.2)
    b += box(10, T0 - 26, 44, 44, 26, GT, GF)                                   # передняя бабка
    b += rect(12, T0 - 22, 12, 10, "#3a3f43", OUT, 1.2) + circ(18, T0 - 17, 2.6, "#c94a3a", None, 0)   # пульт слева
    b += circ(42, T0 - 10, 4, "#c9ccce", OUT, 1) + circ(42, T0 + 4, 4, "#c9ccce", OUT, 1)
    b += rect(22, T0 + 44, 20, 12, "#9ca3a7", OUT, 1.6, 2)                      # патрон
    b += rect(28, T0 + 56, 8, 30, "#cdd3d7", OUT, 1.2)                         # заготовка
    b += box(6, T0 + 92, 52, 20, 10, "#6f8275", "#55665a")                     # суппорт
    b += rect(8, T0 + 94, 12, 8, "#3a3f43", OUT, 1) + poly([(20, T0 + 96), (27, T0 + 94), (27, T0 + 100)], "#cdd3d7", None, 0)
    b += circ(4, T0 + 104, 5, None, "#c9ccce", 2)                               # маховик слева
    b += box(18, T0 + 140, 28, 22, 14, GT, GF)                                  # задняя бабка
    b += rect(28, T0 + 132, 8, 10, "#aab1b5", OUT, 1)
    b += rect(12, T0 + H - 14, 40, 14, "#4e5f54", OUT, 2)                       # торец основания
    b += rect(30, T0 - 36, 4, 12, "#2a2e31", None, 0) + circ(32, T0 - 38, 3, "#3a3f43", None, 0)
    obj("lathe_v", 1, 3, T0, b)
    META["lathe_v"]["anchors"] = {"lamp": [18, T0 - 17], "work": [32, T0 + 70], "bar": [-6, T0 + 170], "out": [6, T0 + 176]}

    # --- ЧПУ 1×3: закрытый кожух со смотровым окном сверху, пульт слева внизу
    T0 = 70
    b = shadow(12, T0 - 30, 52, H + 20)
    b += box(6, T0 - 60, 52, H - 20, 70, "#e4e7e8", "#c6cbcd")
    b += rect(14, T0 - 44, 36, H - 60, "#2a3036", OUT, 2, 3)
    b += rect(17, T0 - 41, 30, H - 66, "#3e5866", None, 0, 2, 0.85) + poly([(18, T0 - 40), (30, T0 - 40), (20, T0 + 40), (18, T0 + 40)], "#ffffff", None, 0, 0.12)
    b += rect(24, T0 - 30, 16, 18, "#9aa3a8", OUT, 1.2, 2) + rect(28, T0 - 12, 8, 50, "#c9ccce", OUT, 1.2)
    b += box(0, T0 + H - 110, 14, 30, 44, "#3d4652", "#2e3640")
    b += rect(2, T0 + H - 104, 10, 12, "#1d2a34", OUT, 1) + rect(3, T0 + H - 102, 8, 8, "#6fd0e0", None, 0, 1, 0.8)
    b += rect(10, T0 + H - 12, 44, 10, "#3d5a7a", OUT, 1.6)
    b += rect(48, T0 - 70, 6, 12, "#3a3f43", OUT, 1) + circ(51, T0 - 72, 4, "#6fbf86", OUT, 1)
    obj("cnc_lathe_v", 1, 3, T0, b)
    META["cnc_lathe_v"]["anchors"] = {"lamp": [51, T0 - 72], "work": [32, T0 + 10], "in": [4, T0 + H - 20], "out": [56, T0 + H - 20]}

    # --- фрезерный 1×2 (вид сбоку): стол вдоль оси на консоли, колонна справа посередине длины,
    #     хобот с головкой нависает над серединой стола — фреза смотрит в центр стола (1.12)
    T0 = 74
    H = 128
    b = shadow(10, T0 - 4, 54, H + 2)
    b += box(14, T0 + 40, 26, 8, 34, GT, GF)                                   # консоль под серединой стола
    b += box(6, T0 + 8, 36, H - 28, 10, "#9aa1a5", "#7b8286")                  # стол вдоль оси
    for k in range(3):
        b += line(13 + k * 8, T0 + 10, 13 + k * 8, T0 + H - 22, "#5f666a", 1.2)
    b += rect(14, T0 + 60, 20, 12, "#c9ccce", OUT, 1.2, 1)                     # заготовка в тисках
    b += rect(12, T0 + 58, 4, 16, "#5a6268", None, 0) + rect(32, T0 + 58, 4, 16, "#5a6268", None, 0)
    b += box(42, T0 + 2, 18, 12, 92, GT, GF)                                  # колонна справа
    b += box(44, T0 - 12, 16, 8, 14, "#6a7c70", "#566659")                     # двигатель на колонне
    b += box(12, T0 + 14, 48, 12, 22, GT, GF)                                   # хобот с головкой над столом
    b += rect(20, T0 + 36, 14, 8, "#9aa3a8", OUT, 1.5) + rect(23, T0 + 44, 8, 8, "#c9ccce", OUT, 1.2)   # шпиндель
    b += rect(21, T0 + 52, 12, 5, "#5a6268", OUT, 1.2)                         # фреза над заготовкой
    for k in range(3):
        b += line(22 + k * 4, T0 + 52, 23 + k * 4, T0 + 57, "#d0d5d8", 1)
    b += circ(4, T0 + 40, 6, None, "#c9ccce", 2.2) + line(-1, T0 + 40, 9, T0 + 40, "#c9ccce", 1.2)   # маховики слева
    b += circ(4, T0 + 84, 5, None, "#c9ccce", 2)
    b += rect(46, T0 + 50, 12, 9, "#3a3f43", OUT, 1.2) + circ(52, T0 + 54.5, 2.4, "#c94a3a", None, 0)   # пульт на колонне
    b += rect(14, T0 + H - 16, 30, 8, "#4e5f54", OUT, 1.5)                     # основание
    obj("mill_v", 1, 2, T0, b)
    META["mill_v"]["anchors"] = {"lamp": [52, T0 + 54], "work": [26, T0 + 62], "in": [20, T0 + 20], "out": [20, T0 + 96]}

    # --- сварочный пост 1×2: стол вверху, полуавтомат и баллон внизу
    T0 = 46
    b = shadow(12, T0 - 6, 52, 132)
    b += box(6, T0 + 2, 48, 66, 26, "#6a7074", "#4f5458")
    for yy in range(8):
        for xx in range(4):
            b += circ(14 + xx * 11, T0 + 8 + yy * 8, 1.5, "#3a3e42", None, 0)
    b += path(f"M14 {T0+14}L18 {T0+50}M26 {T0+12}L30 {T0+48}", None, "#8f969a", 4)
    b += box(8, T0 + 96, 30, 10, 26, "#d9b13b", "#b8932c")
    b += rect(12, T0 + 108, 14, 8, "#2a2e31", OUT, 1) + circ(31, T0 + 112, 2.4, "#6fbf86", None, 0)
    b += circ(23, T0 + 101, 6, "#5a3a2a", OUT, 1.4) + circ(23, T0 + 101, 2.6, "#c98d63", None, 0)
    b += rect(44, T0 + 66, 12, 46, "#4a7f78", OUT, 1.6, 4) + rect(45, T0 + 60, 10, 8, "#3a3f43", OUT, 1.2, 2)
    b += path(f"M14 {T0+104}Q-2 {T0+80} 14 {T0+46}", None, "#1d1d1d", 2.4)
    obj("weld_post_v", 1, 2, T0, b)
    META["weld_post_v"]["anchors"] = {"lamp": [31, T0 + 112], "work": [26, T0 + 34], "flash": [26, T0 + 34], "in": [12, T0 + 10], "out": [46, T0 + 20]}

    # --- сборочный верстак 1×2: столешница вдоль, пресс сверху справа, ящики
    T0 = 40
    b = shadow(12, T0, 52, 124)
    b += box(4, T0 + 2, 56, 98, 26, "#7d8a92", "#5e6a72")
    b += rect(8, T0 + 104, 48, 18, None, "#4a555c", 1.4)
    b += rect(40, T0 - 20, 12, 36, "#4a7f9a", OUT, 1.6) + box(34, T0 - 26, 24, 6, 10, "#5a8fa8", "#4a7f9a")
    b += rect(44, T0 - 14, 4, 20, "#c9ccce", OUT, 1)
    b += rect(8, T0 + 60, 22, 10, "#3d5a7a", OUT, 1.5) + rect(6, T0 + 64, 26, 4, "#8b9296", OUT, 1.2)
    b += rect(12, T0 + 30, 12, 7, "#2a2e31", OUT, 1, 2)
    for k in range(3):
        b += rect(40, T0 + 50 + k * 10, 10, 7, ["#c94a3a", "#d9b13b", "#4d7fb0"][k], OUT, 0.8, 1)
    obj("assembly_table_v", 1, 2, T0, b)
    META["assembly_table_v"]["anchors"] = {"lamp": [46, T0 - 20], "work": [22, T0 + 40], "in": [14, T0 + 14], "out": [44, T0 + 86]}

    # --- испытательный стенд 1×2: бак вдоль, манометры и пульт справа
    T0 = 54
    b = shadow(12, T0 - 14, 52, 124)
    b += box(4, T0 - 2, 56, 92, 22, "#3d6a9a", "#2e5478")
    b += rect(12, T0 + 6, 22, 70, "#cdd3d7", OUT, 1.2, 4)
    b += box(36, T0 - 36, 22, 8, 34, "#2e3440", "#232830") + rect(39, T0 - 30, 16, 10, "#1d2a34", OUT, 1)
    b += path(f"M40 {T0-26}l3 -3 2 5 3 -6 2 4 3 -2", None, "#6fe08a", 1)
    for gy in (T0 + 20, T0 + 48):
        b += circ(46, gy, 8, "#f4f1e6", OUT, 1.6) + line(46, gy, 50, gy - 5, "#c9372c", 1.6)
    obj("test_stand_v", 1, 2, T0, b)
    META["test_stand_v"]["anchors"] = {"lamp": [46, T0 - 26], "work": [24, T0 + 30], "in": [8, T0 + 100], "out": [52, T0 + 100]}

    # --- слесарный верстак 1×2
    T0 = 30
    b = shadow(12, T0 + 4, 52, 120)
    b += box(4, T0 + 4, 56, 96, 26, "#a8845a", "#6b5236")
    for y in range(T0 + 20, T0 + 96, 24):
        b += line(5, y, 59, y, "#8f6f48", 1.2)
    b += rect(10, T0 + 12, 16, 22, "#3d5a7a", OUT, 1.5) + rect(6, T0 + 16, 24, 5, "#8b9296", OUT, 1.2)       # тиски слева
    b += rect(32, T0 + 50, 16, 14, "#5e7364", OUT, 1.5, 4)
    b += line(18, T0 + 70, 26, T0 + 88, "#7a5c38", 3) + line(36, T0 + 76, 44, T0 + 92, "#9aa1a5", 3)
    b += rect(14, T0 + 106, 36, 16, None, "#523e28", 1.4)
    obj("workbench_v", 1, 2, T0, b)

    # --- стеллаж для металла 1×2: полки вдоль стены, торец снизу
    T0 = 44
    b = shadow(12, T0 - 10, 52, 132)
    b += rect(6, T0 - 22, 52, 12, "#6a8aaa", OUT, 2)
    b += rect(6, T0 - 10, 52, 118, "#2f3a46", OUT, 2)
    b += rect(6, T0 - 10, 52, 6, "#4d6d8d", OUT, 1.2) + rect(6, T0 + 50, 52, 6, "#4d6d8d", OUT, 1.2) + rect(6, T0 + 102, 52, 6, "#4d6d8d", OUT, 1.2)
    b += rect(6, T0 - 10, 5, 118, "#d97a2c", OUT, 1.2) + rect(53, T0 - 10, 5, 118, "#d97a2c", OUT, 1.2)
    obj("rack_v", 1, 2, T0, b)
    META["rack_v"]["slots"] = [[14, T0 - 2, 36, 50], [14, T0 + 58, 36, 42]]

    # --- стеллаж НЗП 1×2
    T0 = 54
    b = shadow(12, T0 - 14, 52, 132)
    b += rect(6, T0 - 44, 52, 6, "#d9a43a", OUT, 1.5) + rect(6, T0 + 120, 52, 6, "#d9a43a", OUT, 1.5)
    b += rect(4, T0 - 38, 6, 158, "#c98a2c", OUT, 1.5) + rect(54, T0 - 38, 6, 158, "#c98a2c", OUT, 1.5)
    for k in range(4):
        b += rect(14, T0 - 30 + k * 36, 36, 30, "#3f6f9a" if k % 2 == 0 else "#4a7fa8", OUT, 1.2, 2)
        b += rect(20, T0 - 26 + k * 36, 22, 4, "#2a4f70", None, 0, 1)
    obj("wip_rack_v", 1, 2, T0, b)
    META["wip_rack_v"]["slots"] = [[14, T0 - 30, 36, 64], [14, T0 + 42, 36, 64]]

    # --- стол ОТК 1×2: плита вдоль, стойка индикатора справа
    T0 = 30
    b = shadow(12, T0 + 6, 52, 120)
    b += rect(8, T0 + 2, 48, 100, "#4a4e52", OUT, 2)
    rng = random.Random(9)
    b += g(speckle(rng, 44, 96, 70, ["#5a5f63", "#3c4044", "#62676b"], 0.5, 1.1), f"translate(10 {T0 + 4})")
    b += rect(8, T0 + 102, 48, 12, "#2f3337", OUT, 2)
    b += rect(40, T0 + 70, 12, 12, "#8b9296", OUT, 1.2) + rect(44, T0 + 46, 4, 26, "#c9ccce", OUT, 1) + rect(38, T0 + 52, 16, 5, "#d9b13b", OUT, 1)
    b += rect(14, T0 + 60, 20, 12, "#ece8dc", OUT, 1)
    b += rect(12, T0 + 114, 6, 14, "#5c6267", OUT, 1.2) + rect(46, T0 + 114, 6, 14, "#5c6267", OUT, 1.2)
    obj("qc_table_v", 1, 2, T0, b)
    META["qc_table_v"]["slots"] = [[12, T0 + 6, 36, 48]]

    # --- обеденный стол 1×2
    T0 = 26
    b = shadow(12, T0 + 4, 52, 120)
    b += rect(8, T0 + 2, 48, 98, "#b88d5c", OUT, 2) + line(32, T0 + 2, 32, T0 + 100, "#a07a4c", 1.2)
    b += rect(10, T0 + 4, 44, 4, "#fff", None, 0, 0, 0.12)
    b += rect(8, T0 + 100, 48, 8, "#8a6640", OUT, 2)
    b += rect(12, T0 + 108, 6, 18, "#6b5236", OUT, 1.5) + rect(46, T0 + 108, 6, 18, "#6b5236", OUT, 1.5)
    b += ell(20, T0 + 24, 8, 4.5, "#ece8dc", OUT, 1.2) + ell(20, T0 + 24, 4, 2.2, "#c9692e", None, 0)
    b += ell(44, T0 + 70, 8, 4.5, "#ece8dc", OUT, 1.2)
    b += rect(36, T0 + 30, 9, 10, "#ece8dc", OUT, 1.2, 2) + rect(16, T0 + 58, 9, 10, "#4d7fb0", OUT, 1.2, 2)
    obj("dining_table_v", 1, 2, T0, b)

    # --- скамейка 1×2 (сидят лицом влево)
    T0 = 22
    b = shadow(12, T0 + 6, 52, 120)
    for k, x in enumerate((14, 25, 36)):
        b += rect(x, T0 + 2, 11, 110, "#a07a4c" if k % 2 == 0 else "#946f43", OUT, 1.5)
    b += rect(48, T0 - 10, 10, 116, "#946f43", OUT, 1.5)                        # спинка справа
    b += rect(14, T0 + 112, 34, 8, "#7a5a36", OUT, 1.2)
    b += rect(16, T0 + 120, 6, 14, "#3a3e42", OUT, 1) + rect(40, T0 + 120, 6, 14, "#3a3e42", OUT, 1)
    obj("bench_v", 1, 2, T0, b)

    # --- диван 1×2 (сидят лицом влево)
    T0 = 26
    SOFA, SOFA_D = "#6a7a52", "#55633f"
    b = shadow(12, T0 + 4, 52, 124)
    b += rect(40, T0 - 8, 20, 120, SOFA_D, OUT, 2, 6)                            # спинка справа
    b += rect(8, T0 + 2, 36, 108, SOFA, OUT, 2, 5)
    b += rect(12, T0 + 6, 28, 48, "#7a8a60", OUT, 1.2, 4) + rect(12, T0 + 58, 28, 48, "#7a8a60", OUT, 1.2, 4)
    b += rect(6, T0 - 6, 52, 12, SOFA_D, OUT, 2, 5) + rect(6, T0 + 106, 52, 12, SOFA_D, OUT, 2, 5)
    b += rect(10, T0 + 118, 6, 8, "#2e3236", None, 0) + rect(48, T0 + 118, 6, 8, "#2e3236", None, 0)
    obj("sofa_v", 1, 2, T0, b)

    # --- стол ИТР 1×2 (сидят слева, монитор справа)
    T0 = 46
    b = shadow(12, T0 + 6, 52, 120)
    b += box(8, T0 + 2, 50, 96, 24, "#b08a5e", "#8c6a44")
    b += rect(38, T0 - 10, 18, 40, "#2a2e31", OUT, 1.8, 3) + rect(41, T0 - 7, 12, 34, "#4d7fb0", None, 0, 1)
    b += rect(22, T0 + 4, 8, 30, "#3a3f43", None, 0, 1)
    b += rect(14, T0 + 46, 30, 22, "#ffffff", OUT, 1)
    for k in range(4):
        b += line(17, T0 + 50 + k * 4, 40, T0 + 50 + k * 4, "#9a9890", 0.7)
    b += rect(14, T0 + 76, 12, 14, "#c94a3a", OUT, 1.2, 2)
    obj("office_desk_v", 1, 2, T0, b)
    META["office_desk_v"]["anchors"] = {"screen": [47, T0 + 10]}


def lights_water():
    """0.8: светильники (под потолком), уличный фонарь, ввод водопровода."""
    # лампа накаливания: плафон-«тарелка» под потолком, вид сверху-сбоку
    T0 = 30
    b = line(32, 0, 32, 16, "#2a2e31", 1.6)
    b += ell(32, 22, 15, 7, "#e9ecec", OUT, 1.8) + ell(32, 21, 10, 4, "#ffffff", None, 0, 0.6)
    b += circ(32, 26, 5, "#fff2b0", OUT, 1.2) + circ(31, 25, 2, "#ffffff", None, 0, 0.9)
    obj("lamp_bulb", 1, 1, T0, b, pad=0)
    # ЛПО: длинный корпус с двумя трубками
    T0 = 22
    b = line(14, 2, 14, 10, "#2a2e31", 1.4) + line(50, 2, 50, 10, "#2a2e31", 1.4)
    b += rect(4, 10, 56, 16, "#d6dad7", OUT, 1.8, 3) + rect(8, 13, 48, 4, "#f8f6e8", None, 0, 2) + rect(8, 19, 48, 4, "#f8f6e8", None, 0, 2)
    b += line(8, 15, 56, 15, "#fff", 1, 0.8) + line(8, 21, 56, 21, "#fff", 1, 0.8)
    obj("lamp_tube", 1, 1, T0, b, pad=0)
    # ДРЛ: промышленный колокол
    T0 = 34
    b = line(32, 0, 32, 10, "#2a2e31", 2)
    b += rect(26, 8, 12, 8, "#5a6268", OUT, 1.5, 2)
    b += path("M14 30Q16 16 32 15Q48 16 50 30Z", "#7d8a92", OUT, 1.8) + ell(32, 30, 18, 5, "#4a5156", OUT, 1.5)
    b += ell(32, 31, 10, 3, "#fff6c8", None, 0, 0.95)
    obj("lamp_drl", 1, 1, T0, b, pad=0)
    # уличный фонарь на столбе
    T0 = 96
    b = ell(36, T0 + 52, 12, 4, "#000", None, 0, 0.25)
    b += rect(29, T0 + 40, 14, 12, "#5a6064", OUT, 1.5, 2)
    b += rect(33, 10, 6, T0 + 32, "#6a7176", OUT, 1.5)
    b += path(f"M36 14Q36 4 50 4H54", None, "#6a7176", 4)
    b += path("M46 4H62L58 14H50Z", "#3a3f43", OUT, 1.4) + rect(50, 12, 8, 4, "#fff2b0", None, 0, 1)
    obj("lamp_street", 1, 1, T0, b)
    # ввод водопровода: колодец-тумба с трубой, задвижкой (синий маховик) и счётчиком
    T0 = 34
    b = shadow(10, T0 + 6, 50, 54)
    b += box(8, T0 + 6, 48, 18, 30, "#7a8a96", "#5c6c78")
    b += rect(4, T0 + 30, 56, 8, "#4a7fb0", OUT, 1.6, 3) + rect(4, T0 + 31, 56, 2, "#fff", None, 0, 0, 0.25)
    b += rect(26, T0 - 10, 8, 20, "#4a7fb0", OUT, 1.4)
    b += circ(30, T0 - 12, 9, None, "#2e6aa8", 3) + line(21, T0 - 12, 39, T0 - 12, "#2e6aa8", 2) + line(30, T0 - 21, 30, T0 - 3, "#2e6aa8", 2)
    b += circ(46, T0 + 14, 6, "#f4f1e6", OUT, 1.2) + line(46, T0 + 14, 49, T0 + 11, "#c9372c", 1.2)
    obj("water_inlet", 1, 1, T0, b)

def objects_v16():
    """1.6: вытяжной вентилятор, вытяжной зонт, компрессор, газовый котёл, шкаф СИЗ, иконки сетей."""
    # --- вытяжной вентилятор 1×1: кожух на раме, решётка, крыльчатка (рисуется в игре), коробка двигателя
    T0 = 50
    b = shadow(14, T0 + 4, 48, 56)
    b += rect(14, T0 + 36, 6, 22, "#4a5156", OUT, 1.2) + rect(44, T0 + 36, 6, 22, "#4a5156", OUT, 1.2)
    b += rect(10, T0 + 54, 44, 6, "#3a3f43", OUT, 1.2, 1)
    b += circ(32, T0 + 8, 27, "#8a959c", OUT, 2.2) + circ(32, T0 + 8, 23, "#2a2e31", OUT, 1.2)
    for k in range(5):
        b += circ(32, T0 + 8, 4 + k * 4.4, None, "#6a757c", 0.9)
    b += line(9, T0 + 8, 55, T0 + 8, "#6a757c", 1) + line(32, T0 - 15, 32, T0 + 31, "#6a757c", 1)
    b += rect(26, T0 + 30, 12, 8, "#5a6268", OUT, 1) + rect(46, T0 - 22, 10, 12, "#3a3f43", OUT, 1) + circ(51, T0 - 16, 2, "#6fbf86", None, 0)
    obj("vent_fan", 1, 1, T0, b)
    META["vent_fan"]["anchors"] = {"rotor": [32, T0 + 8, 20], "lamp": [51, T0 - 16]}

    # --- вытяжной зонт (под потолком): пирамидальный колпак с патрубком
    T0 = 30
    b = rect(26, 0, 12, 14, "#9aa6ae", OUT, 1.4)
    b += line(28, 2, 28, 14, "#c8d0d6", 1, 0.7)
    b += poly([(24, 12), (40, 12), (58, 34), (6, 34)], "#b8c2c8", OUT, 1.8)
    b += poly([(24, 12), (40, 12), (48, 22), (16, 22)], "#ccd5da", None, 0)
    b += rect(4, 33, 56, 5, "#7a868e", OUT, 1.4, 1)
    b += line(10, 36, 54, 36, "#2a2e31", 0.8, 0.5)
    obj("vent_hood", 1, 1, T0, b, pad=0)

    # --- винтовой компрессор 2×1: ресивер (горизонтальный бак), блок с двигателем, манометр
    T0 = 56
    b = shadow(12, T0 - 6, 120, 68)
    b += rect(8, T0 + 30, 112, 24, "#c94a3a", OUT, 2, 12) + rect(14, T0 + 33, 100, 5, "#fff", None, 0, 2, 0.25)
    b += rect(14, T0 + 52, 8, 8, "#3a3f43", OUT, 1) + rect(106, T0 + 52, 8, 8, "#3a3f43", OUT, 1)
    b += box(10, T0 - 30, 74, 10, 50, "#5f7a8e", "#4a6476")
    for k in range(6):
        b += line(18 + k * 9, T0 - 14, 18 + k * 9, T0 + 12, "#3a5060", 1.4)
    b += rect(88, T0 - 12, 30, 32, "#3a3f43", OUT, 1.6, 2)
    for k in range(4):
        b += line(92, T0 - 6 + k * 6, 114, T0 - 6 + k * 6, "#5a6268", 1.4)
    b += circ(100, T0 + 26, 7, "#f4f1e6", OUT, 1.4)
    b += rect(60, T0 - 26, 18, 10, "#2a2e31", OUT, 1) + circ(65, T0 - 21, 2, "#6fbf86", None, 0) + circ(72, T0 - 21, 2, "#c94a3a", None, 0)
    b += path(f"M84 {T0+6}h8v14", None, "#9aa1a5", 3)
    obj("compressor", 2, 1, T0, b)
    META["compressor"]["anchors"] = {"gauge": [100, T0 + 26], "lamp": [65, T0 - 21]}

    # --- газовый котёл 2×2: корпус, горелка с окошком пламени, дымоход, трубы подачи и обратки
    T0 = 70
    b = shadow(12, T0 - 10, 122, 136)
    b += rect(56, 2, 16, T0 - 14, "#8a959c", OUT, 2) + rect(58, 4, 4, T0 - 18, "#fff", None, 0, 0, 0.2)
    b += rect(52, 0, 24, 8, "#6a757c", OUT, 1.6, 2)
    b += box(10, T0 - 22, 108, 16, 112, "#e8e4dc", "#d4cfc4")
    b += rect(16, T0 + 2, 96, 16, "#b0282a", OUT, 1.4, 2) + path(f"M22 {T0+10}h30", None, "#fff", 2.2, 0.8)
    b += rect(34, T0 + 30, 40, 28, "#2a2e31", OUT, 1.6, 3) + rect(38, T0 + 34, 32, 20, "#3a2a20", None, 0, 2)
    b += circ(90, T0 + 40, 9, "#f4f1e6", OUT, 1.4) + line(90, T0 + 40, 95, T0 + 35, "#c9372c", 1.4)
    b += circ(90, T0 + 64, 7, "#f4f1e6", OUT, 1.2) + line(90, T0 + 64, 86, T0 + 60, "#2a2e31", 1.2)
    b += rect(18, T0 + 66, 28, 10, "#3a3f43", OUT, 1, 2) + circ(24, T0 + 71, 2, "#6fbf86", None, 0) + circ(32, T0 + 71, 2, "#e2b73a", None, 0)
    b += rect(4, T0 + 82, 120, 7, "#c94a3a", OUT, 1.4, 3) + rect(4, T0 + 94, 120, 7, "#4a7fb0", OUT, 1.4, 3)
    b += rect(14, T0 + 108, 100, 6, "#6a757c", OUT, 1)
    obj("boiler", 2, 2, T0, b)
    META["boiler"]["anchors"] = {"flame": [54, T0 + 44, 32, 20], "lamp": [24, T0 + 71], "smoke": [64, 0]}

    # --- шкаф СИЗ: металлический шкаф со знаками «каска», «очки», «наушники» (три вида)
    T0 = 58
    SIDE = "#5f7f6a"
    def ppe(view):
        b = shadow(14, T0 - 44, 50, 104)
        b += box(8, T0 - 50, 48, 9, 104, "#9fbfa8", "#7fa08a")
        if view == "v":
            b += rect(8, T0 - 41, 9, 101, "#7a9a84", OUT, 1.4)
            b += rect(23, T0 - 32, 26, 84, None, SIDE, 1.2, 3)
            b += circ(36, T0 - 10, 7, "#e2b73a", OUT, 1) + rect(29, T0 - 10, 14, 3, "#e2b73a", OUT, 0.8)
        elif view == "b":
            b += bolts([(14, T0 - 36), (50, T0 - 36), (14, T0 + 52), (50, T0 + 52)], 1.6)
            b += rect(16, T0 - 20, 32, 40, None, SIDE, 1, 2)
        else:
            b += line(32, T0 - 41, 32, T0 + 59, SIDE, 1.2)
            b += rect(12, T0 - 34, 16, 16, "#ffffff", OUT, 0.8) + path(f"M14 {T0-22}q6 -12 12 0Z", "#e2b73a", OUT, 0.8) + rect(13, T0 - 23, 14, 2, "#e2b73a", OUT, 0.6)
            b += rect(36, T0 - 34, 16, 16, "#ffffff", OUT, 0.8) + circ(41, T0 - 26, 3, "#9cc8e8", OUT, 0.8) + circ(47, T0 - 26, 3, "#9cc8e8", OUT, 0.8) + line(44, T0 - 26, 44, T0 - 26, OUT, 1)
            b += rect(12, T0 - 12, 16, 16, "#ffffff", OUT, 0.8) + path(f"M15 {T0}q5 -12 10 0", None, "#c94a3a", 1.6) + rect(13, T0 - 2, 3, 5, "#c94a3a", None, 0) + rect(24, T0 - 2, 3, 5, "#c94a3a", None, 0)
            b += rect(36, T0 - 12, 16, 16, "#ffffff", OUT, 0.8) + path(f"M39 {T0-6}h10l-1 8h-8Z", "#c9ccce", OUT, 0.8)
            b += rect(14, T0 + 14, 36, 8, "#2f6a3e", OUT, 0.8) + path(f"M18 {T0+18}h28", None, "#fff", 1.2, 0.8)
            b += rect(29, T0 + 30, 3, 10, "#3a3f43", None, 0) + rect(34, T0 + 30, 3, 10, "#3a3f43", None, 0)
        b += rect(8, T0 + 60, 48, 4, "#5f6f7a", OUT, 1)
        return b
    obj("ppe_cabinet", 1, 1, T0, ppe("f"))
    obj("ppe_cabinet_v", 1, 1, T0, ppe("v"))
    obj("ppe_cabinet_b", 1, 1, T0, ppe("b"))

    # --- иконки сетей: воздуховод и пневмомагистраль
    dd = path("M8 44H30V20H56", None, "#4a5560", 16) + path("M8 44H30V20H56", None, "#9aa6ae", 12) + path("M8 41H27V17H56", None, "#d8e0e6", 2, 0.6)
    for (x, y) in [(18, 44), (30, 32), (44, 20)]:
        dd += rect(x - 2, y - 8, 4, 16, "#6a757c", None, 0) if y != 32 else rect(x - 8, y - 2, 16, 4, "#6a757c", None, 0)
    save("assets/tiles/icon_duct.svg", 64, 64, dd)
    save("assets/tiles/icon_unduct.svg", 64, 64, path("M8 44H30V20H56", None, "#9aa6ae", 12, 0.5) + line(14, 14, 50, 50, "#d8644e", 5) + line(50, 14, 14, 50, "#d8644e", 5))
    aa = path("M8 44H30V20H56", None, "#8a3e1a", 8) + path("M8 44H30V20H56", None, "#e2843a", 5) + path("M8 43H29V19H56", None, "#f8c8a0", 1.4, 0.7)
    aa += circ(48, 44, 9, "#f4f1e6", OUT, 2) + line(48, 44, 53, 39, "#c9372c", 2)
    save("assets/tiles/icon_air.svg", 64, 64, aa)
    save("assets/tiles/icon_unair.svg", 64, 64, path("M8 44H30V20H56", None, "#e2843a", 5, 0.5) + line(14, 14, 50, 50, "#d8644e", 5) + line(50, 14, 14, 50, "#d8644e", 5))


def objects_v17():
    """1.7: видеокамера, доска профкома, табло «Дней без травм», иконка «Бригады»."""
    # --- купольная видеокамера под потолком
    T0 = 30
    b = rect(28, 0, 8, 8, "#5a6268", OUT, 1.2)
    b += rect(18, 7, 28, 6, "#c9ccce", OUT, 1.4, 2)
    b += path("M20 13Q20 30 32 30Q44 30 44 13Z", "#2a2e31", OUT, 1.6)
    b += path("M23 14Q23 26 32 27", None, "#6a7a86", 1.4, 0.8)
    b += circ(32, 21, 3.4, "#11161a", "#8fa4b0", 1)
    b += circ(31, 20, 1.1, "#ffffff", None, 0, 0.8)
    obj("camera", 1, 1, T0, b, pad=0)
    META["camera"]["anchors"] = {"led": [40, 10]}

    # --- доска профкома
    T0 = 70
    b = ell(32, T0 + 58, 22, 5, "#000", None, 0, 0.22)
    b += line(14, T0 - 4, 14, T0 + 56, "#5a4030", 3) + line(50, T0 - 4, 50, T0 + 56, "#5a4030", 3)
    b += rect(4, T0 - 64, 56, 62, "#b08a5e", OUT, 2, 2) + rect(7, T0 - 52, 50, 47, "#c9a46a", None, 0, 1)
    b += rect(4, T0 - 64, 56, 11, "#b0282a", OUT, 1.4, 2) + path(f"M10 {T0-58}h44", None, "#f2d58a", 1.6, 0.9)
    notes = [(9, T0 - 49, 18, 14, "#f4f1e6", "#c94a3a"), (31, T0 - 50, 22, 12, "#e8f0f4", "#3d6a9a"), (10, T0 - 31, 16, 20, "#fff6c8", "#5a8a4a"), (30, T0 - 34, 22, 18, "#f4f1e6", "#8a6a20")]
    for (x, y, w, h, c, pin) in notes:
        b += rect(x, y, w, h, c, OUT, 0.8) + circ(x + w / 2, y + 2, 1.6, pin, None, 0)
        for k in range(int(h / 5)):
            b += line(x + 2, y + 5 + k * 4, x + w - 3, y + 5 + k * 4, "#8a8478", 0.8)
    obj("union_board", 1, 1, T0, b)

    # --- табло «Дней без травм»
    T0 = 70
    b = ell(32, T0 + 58, 22, 5, "#000", None, 0, 0.22)
    b += line(32, T0 - 4, 32, T0 + 54, "#5a6268", 3) + line(20, T0 + 56, 44, T0 + 56, "#3a3f43", 2.6)
    b += rect(4, T0 - 66, 56, 64, "#2f6a3e", OUT, 2, 3)
    b += rect(8, T0 - 62, 48, 12, "#f4f1e6", OUT, 1, 1)
    b += path(f"M12 {T0-58}h18M12 {T0-54}h26", None, "#2f6a3e", 1.4)
    b += rect(42, T0 - 60, 9, 8, "#ffffff", OUT, 0.8) + rect(45.5, T0 - 59, 2, 6, "#2f9a4e", None, 0) + rect(43.5, T0 - 57, 6, 2, "#2f9a4e", None, 0)
    b += rect(11, T0 - 44, 42, 26, "#14181b", OUT, 1.4, 2) + rect(13, T0 - 42, 38, 4, "#ffffff", None, 0, 1, 0.08)
    b += path(f"M12 {T0-12}h40M12 {T0-8}h30", None, "#cfe0c8", 1.4, 0.8)
    obj("days_board", 1, 1, T0, b)
    META["days_board"]["anchors"] = {"digits": [32, T0 - 31]}

    # --- иконка «Бригады»: трое, средний — бригадир в каске
    C = "#e7e4d8"
    ic = circ(13, 20, 5, None, C, 2.6) + path("M4 38Q4 28 13 28Q18 28 20 31", None, C, 2.6)
    ic += circ(35, 20, 5, None, C, 2.6) + path("M44 38Q44 28 35 28Q30 28 28 31", None, C, 2.6)
    ic += circ(24, 17, 6.5, None, C, 3) + path("M17.5 15Q24 6 30.5 15Z", "#e0aa48", None, 0) + path("M12 42Q12 28 24 28Q36 28 36 42", None, C, 3)
    save("assets/ui/crew.svg", 48, 48, ic)


def objects_v18():
    """1.8 «Рынок»: иконки конкурентов, страхования, ISO и главного инженера."""
    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    # завод-конкурент: корпус с трубой и стрелкой вниз
    icon("factory", path("M4 42V22L14 28V22L24 28V22L34 28V12H42V42Z", None, C, 2.8) + rect(10, 33, 5, 5, None, C, 2) + rect(20, 33, 5, 5, None, C, 2) + path("M37 8q2 -3 4 0", None, "#9aa3ab", 2))
    # страхование: щит с галочкой
    icon("shield", path("M24 4L40 10V22Q40 36 24 44Q8 36 8 22V10Z", None, C, 3) + path("M16 24L22 30L33 18", None, "#8fcf78", 3.2))
    # ISO: розетка-медаль с лентами
    icon("iso", circ(24, 19, 13, None, C, 3) + circ(24, 19, 7, None, "#e0aa48", 2.4) + path("M16 30L12 44L19 40L22 46M32 30L36 44L29 40L26 46", None, C, 2.6))
    # главный инженер: голова в каске, очки
    icon("engineer", circ(24, 22, 9, None, C, 2.8) + path("M13 18Q14 8 24 8Q34 8 35 18Z", "#e0aa48", None, 0) + path("M11 18H37", None, C, 2.8)
         + circ(20, 23, 2.6, None, C, 1.8) + circ(28, 23, 2.6, None, C, 1.8) + path("M22.6 23H25.4", None, C, 1.6) + path("M8 44Q8 33 24 33Q40 33 40 44", None, C, 3))


def objects_v110():
    """1.10 «Отделы»: телефон на тумбе (отдел сбыта), стенд по охране труда, шкаф с кодексами (юротдел)."""
    # --- телефон на тумбе 1×1
    T0 = 64
    b = shadow(12, T0 - 8, 48, 62)
    b += box(10, T0 - 12, 44, 8, 60, "#a8774a", "#86603a")
    b += rect(14, T0 + 6, 36, 20, "#93683f", OUT, 1.2) + rect(14, T0 + 30, 36, 20, "#93683f", OUT, 1.2)
    b += rect(27, T0 + 14, 10, 3, "#5a3e24", None, 0) + rect(27, T0 + 38, 10, 3, "#5a3e24", None, 0)
    # аппарат
    b += path(f"M16 {T0-6}L20 {T0-22}H44L48 {T0-6}Z", "#2c3034", OUT, 1.6)
    b += circ(32, T0 - 13, 6.5, "#d9d4c4", OUT, 1.2) + circ(32, T0 - 13, 2.4, "#2c3034", None, 0)
    for k in range(8):
        import math
        a = k * math.pi / 4.5 - 0.6
        b += circ(32 + 4.4 * math.cos(a), T0 - 13 + 4.4 * math.sin(a), 0.9, "#6a6458", None, 0)
    b += path(f"M14 {T0-24}Q14 {T0-32} 22 {T0-31}H42Q50 {T0-32} 50 {T0-24}", None, "#1f2326", 5)
    b += rect(11, T0 - 28, 8, 7, "#1f2326", None, 0, 2) + rect(45, T0 - 28, 8, 7, "#1f2326", None, 0, 2)
    b += path(f"M48 {T0-8}q8 4 4 12q-4 8 4 14", None, "#1f2326", 1.4)
    b += rect(36, T0 - 4, 14, 9, "#f4f1e6", OUT, 0.8) + line(38, T0 - 1, 48, T0 - 1, "#9a9890", 0.7) + line(38, T0 + 2, 46, T0 + 2, "#9a9890", 0.7)
    obj("phone_stand", 1, 1, T0, b)

    # --- стенд «Охрана труда» 1×1
    T0 = 70
    b = ell(32, T0 + 58, 22, 5, "#000", None, 0, 0.22)
    b += line(14, T0 - 4, 14, T0 + 56, "#4a5a50", 3) + line(50, T0 - 4, 50, T0 + 56, "#4a5a50", 3)
    b += rect(4, T0 - 64, 56, 62, "#e9ece6", OUT, 2, 2)
    b += rect(4, T0 - 64, 56, 12, "#2f7a4a", OUT, 1.4, 2) + path(f"M11 {T0-58}h42", None, "#ffffff", 1.6, 0.9)
    # знаки: треугольник «осторожно», каска, «работать в очках»
    b += path(f"M18 {T0-48}L27 {T0-32}H9Z", "#f2c230", OUT, 1.2) + rect(17.2, T0 - 44, 1.6, 7, "#1f2326", None, 0) + circ(18, T0 - 35, 1, "#1f2326", None, 0)
    b += circ(44, T0 - 40, 8, "#2f6fb0", OUT, 1.2) + path(f"M38 {T0-38}Q38 {T0-46} 44 {T0-46}Q50 {T0-46} 50 {T0-38}Z", "#ffffff", None, 0) + rect(37, T0 - 39, 14, 2, "#ffffff", None, 0)
    b += rect(9, T0 - 26, 46, 20, "#ffffff", OUT, 0.8)
    for k in range(4):
        b += line(12, T0 - 22 + k * 4.5, 52 - (k % 2) * 8, T0 - 22 + k * 4.5, "#8a8478", 0.8)
    b += rect(40, T0 - 10, 12, 6, "#d8644e", None, 0, 1)
    obj("safety_stand", 1, 1, T0, b)

    # --- шкаф с кодексами 1×1
    T0 = 64
    b = shadow(14, T0 - 52, 50, 110)
    b += box(6, T0 - 58, 52, 8, 112, "#6e4a30", "#563826")
    b += rect(10, T0 - 46, 44, 46, "#3a2a20", OUT, 1.4)
    cols = ["#7a2a2a", "#6a2424", "#8a3a2a", "#2a3a5a", "#7a2a2a", "#5a2020", "#8a3a2a", "#6a2424"]
    for row in range(2):
        for k in range(8):
            c = cols[(k + row * 2) % 8]
            b += rect(12 + k * 5.2, T0 - 44 + row * 22, 4.4, 19, c, OUT, 0.6)
            b += line(12.6 + k * 5.2, T0 - 39 + row * 22, 15.8 + k * 5.2, T0 - 39 + row * 22, "#d8b45a", 0.9)
            b += line(12.6 + k * 5.2, T0 - 31 + row * 22, 15.8 + k * 5.2, T0 - 31 + row * 22, "#d8b45a", 0.9)
    b += rect(10, T0 - 46, 44, 46, "#cfe2ea", None, 0, 0, None, 0.18) + line(32, T0 - 46, 32, T0, OUT, 1.4)
    b += rect(10, T0 + 4, 44, 46, "#7a5236", OUT, 1.2) + line(32, T0 + 4, 32, T0 + 50, OUT, 1.2)
    b += circ(29, T0 + 27, 1.6, "#d8b45a", None, 0) + circ(35, T0 + 27, 1.6, "#d8b45a", None, 0)
    obj("law_shelf", 1, 1, T0, b)

    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    icon("lock", rect(10, 22, 28, 20, None, C, 2.8, 4) + path("M16 22V15Q16 7 24 7Q32 7 32 15V22", None, C, 2.8) + circ(24, 31, 2.6, "#e0aa48", None, 0)
         + path("M24 33V37", None, "#e0aa48", 2.4))
    icon("phone", path("M14 10L20 8L24 17L20 20Q23 27 28 30L31 26L40 30L38 36Q36 40 30 39Q12 34 9 16Q9 11 14 10Z", None, C, 2.6))
    icon("law", path("M24 6V40M14 40H34", None, C, 2.8) + path("M10 14H38", None, C, 2.6) + path("M10 14L5 27H15Z", None, C, 2.2) + path("M38 14L33 27H43Z", None, C, 2.2)
         + circ(24, 9, 2.4, "#e0aa48", None, 0))


def objects_v111():
    """1.11 «Развитие»: стол директора 2×1 (кресло за столом, зелёная лампа, два телефона); иконка «Развитие»."""
    T0 = 62
    b = shadow(10, T0 - 6, 122, 70)
    # кожаное кресло за столом (спинка над столешницей)
    b += rect(42, T0 - 46, 44, 40, "#5a2e26", OUT, 1.8, 8) + rect(46, T0 - 42, 36, 6, "#fff", None, 0, 3, 0.10)
    for k in range(3):
        b += circ(52 + k * 12, T0 - 30, 1.4, "#3a1c16", None, 0)
    b += rect(36, T0 - 16, 10, 14, "#4a2620", OUT, 1.4, 3) + rect(82, T0 - 16, 10, 14, "#4a2620", OUT, 1.4, 3)
    # столешница с сукном
    b += box(2, T0 - 4, 124, 34, 34, "#6b4026", "#55321e")
    b += rect(14, T0 - 1, 100, 26, "#2f5a3e", "#24452f", 1.2, 2) + rect(16, T0 + 1, 96, 4, "#fff", None, 0, 1, 0.08)
    # тумбы
    b += rect(6, T0 + 34, 34, 26, None, "#3d2416", 1.4) + rect(88, T0 + 34, 34, 26, None, "#3d2416", 1.4)
    for x in (16, 98):
        b += rect(x, T0 + 40, 14, 2.4, "#c9a24a", None, 0) + rect(x, T0 + 50, 14, 2.4, "#c9a24a", None, 0)
    b += line(6, T0 + 47, 40, T0 + 47, "#3d2416", 1.2) + line(88, T0 + 47, 122, T0 + 47, "#3d2416", 1.2)
    # зелёная лампа
    b += rect(22, T0 + 4, 4, 14, "#c9a24a", OUT, 0.8) + ell(24, T0 + 18, 7, 2.6, "#c9a24a", OUT, 1)
    b += path(f"M12 {T0+4}Q12 {T0-8} 24 {T0-8}Q36 {T0-8} 36 {T0+4}Z", "#2f7a4a", OUT, 1.4) + path(f"M15 {T0+1}Q16 {T0-5} 24 {T0-5}", None, "#ffffff", 1.2, 0.35)
    b += ell(24, T0 + 7, 10, 3, "#f6e8a0", None, 0, 0.35)
    # бумаги и папка
    b += rect(44, T0 + 6, 24, 17, "#f4f1e6", OUT, 1) + rect(46, T0 + 4, 24, 17, "#ffffff", OUT, 1)
    for k in range(4):
        b += line(49, T0 + 8 + k * 3, 67, T0 + 8 + k * 3, "#9a9890", 0.7)
    b += rect(72, T0 + 6, 16, 18, "#8a2a2a", OUT, 1, 1) + line(74, T0 + 12, 86, T0 + 12, "#d8b45a", 0.9)
    # два телефона: чёрный и красный
    b += path(f"M92 {T0+20}L94 {T0+8}H106L108 {T0+20}Z", "#2c3034", OUT, 1.2) + rect(91, T0 + 4, 18, 5, "#1f2326", None, 0, 2)
    b += path(f"M110 {T0+20}L111 {T0+10}H120L121 {T0+20}Z", "#b8392e", OUT, 1.2) + rect(109, T0 + 7, 13, 4, "#8e2a22", None, 0, 2)
    # табличка и подставка с ручками
    b += path(f"M50 {T0+26}L52 {T0+22}H76L78 {T0+26}Z", "#c9a24a", OUT, 1) + line(56, T0 + 24, 72, T0 + 24, "#6b4a1a", 0.8)
    b += rect(34, T0 + 14, 6, 8, "#3a3f43", OUT, 0.8) + line(36, T0 + 14, 34, T0 + 6, "#2a5a9a", 1.2) + line(38, T0 + 14, 40, T0 + 7, "#c94a3a", 1.2)
    obj("director_desk", 2, 1, T0, b, pad=24)

    C = "#e7e4d8"
    save("assets/ui/develop.svg", 48, 48, path("M24 42V22M24 30L12 20M24 26L36 16M12 20V12M36 16V9", None, C, 2.8)
         + circ(12, 10, 4, None, C, 2.4) + circ(36, 8, 4, None, C, 2.4) + circ(24, 18, 4, "#e0aa48", None, 0) + path("M14 42H34", None, C, 2.8))


def zone_icons():
    """1.12 «Зоны»: свой значок у каждой зоны (48×48, светлая линия, янтарная деталь)."""
    C = "#e7e4d8"
    A = "#e0aa48"
    W = 2.6
    def ic(name, body):
        save(f"assets/ui/zone_{name}.svg", 48, 48, body)
    import math
    # шестерня
    g = ""
    for k in range(8):
        a = k * math.pi / 4
        g += rect(24 + 13 * math.cos(a) - 3, 24 + 13 * math.sin(a) - 3, 6, 6, C, None, 0)
    ic("workshop", g + circ(24, 24, 11, None, C, W) + circ(24, 24, 4, A, None, 0))
    ic("storage", path("M8 8V42M40 8V42M8 18H40M8 30H40M8 42H40", None, C, W) + rect(12, 21, 9, 8, A, None, 0) + rect(24, 22, 8, 7, None, C, 2) + rect(14, 33, 12, 8, None, C, 2))
    ic("locker", rect(10, 6, 28, 36, None, C, W, 2) + line(24, 6, 24, 42, C, 2) + line(14, 12, 20, 12, C, 2) + line(28, 12, 34, 12, C, 2) + circ(21, 26, 1.6, A, None, 0) + circ(27, 26, 1.6, A, None, 0))
    ic("canteen", circ(24, 26, 13, None, C, W) + circ(24, 26, 7, None, A, 2) + path("M6 8V18M3 8V14Q3 18 6 18Q9 18 9 14V8M6 18V40", None, C, 2) + path("M42 8Q38 14 42 22V40", None, C, 2.2))
    ic("wc", path("M12 10H30V22H12Z", None, C, W) + path("M10 22H36Q36 34 26 36L28 42H16L18 36Q10 34 10 22Z", None, C, W) + line(30, 14, 36, 14, A, 2.4))
    ic("restroom", path("M10 20H34V28Q34 38 22 38Q10 38 10 28Z", None, C, W) + path("M34 22Q42 22 42 27Q42 32 34 32", None, C, W) + path("M16 14Q14 10 17 7M23 14Q21 10 24 7M30 14Q28 10 31 7", None, A, 2) + line(8, 42, 36, 42, C, 2))
    ic("toolroom", path("M10 38L30 18M28 10Q34 6 38 10L34 14L36 16L40 12Q42 18 36 20Q32 21 30 18", None, C, W) + path("M14 10L38 34M10 14L14 10L20 16L16 20Z", None, A, 2.4))
    ic("office", rect(8, 28, 32, 6, None, C, W) + line(12, 34, 12, 42, C, 2) + line(36, 34, 36, 42, C, 2) + rect(15, 10, 18, 13, None, C, W, 1) + line(24, 23, 24, 28, C, 2) + rect(18, 13, 12, 7, A, None, 0, 1, 0.8))
    ic("director_office", path("M16 24Q16 12 24 12Q32 12 32 24Z", A, C, 2) + line(24, 24, 24, 38, C, W) + path("M14 40H34", None, C, W) + circ(24, 8, 2, C, None, 0) + line(8, 42, 40, 42, C, 1.6))
    ic("foreman_office", path("M8 30Q8 14 24 14Q40 14 40 30Z", None, C, W) + path("M6 30H42V34H6Z", None, C, 2) + rect(22, 10, 4, 6, A, None, 0))
    ic("chief_office", path("M8 32Q8 16 24 16Q40 16 40 32Z", None, C, W) + path("M6 32H42V36H6Z", None, C, 2) + path("M24 19L25.8 23.5L30.6 23.6L26.8 26.5L28.2 31L24 28.4L19.8 31L21.2 26.5L17.4 23.6L22.2 23.5Z", A, None, 0))
    ic("accounting", path("M14 8V40M14 8H28Q36 8 36 16Q36 24 28 24H10M10 32H28", None, C, W) + circ(36, 36, 4, A, None, 0))
    ic("supply_office", path("M4 14H28V34H4Z", None, C, W) + path("M28 20H36L42 27V34H28", None, C, W) + circ(12, 36, 4, A, C, 2) + circ(34, 36, 4, A, C, 2))
    ic("pdo", rect(6, 8, 36, 32, None, C, W, 2) + line(6, 16, 42, 16, C, 2) + rect(10, 20, 14, 4, A, None, 0) + rect(18, 26, 16, 4, None, C, 1.6) + rect(14, 32, 10, 4, None, C, 1.6))
    ic("hr_office", circ(17, 16, 5, None, C, W) + path("M7 38Q7 26 17 26Q27 26 27 38", None, C, W) + circ(32, 18, 4.5, None, A, 2.2) + path("M27 28Q29 26 32 26Q41 26 41 38H30", None, A, 2.2))
    ic("tech_office", path("M24 8L14 40M24 8L34 40M18 28H30", None, C, W) + circ(24, 8, 3, A, None, 0) + path("M8 42H40", None, C, 1.6))
    ic("sales_office", path("M14 10L20 8L24 17L20 20Q23 27 28 30L31 26L40 30L38 36Q36 40 30 39Q12 34 9 16Q9 11 14 10Z", None, C, W) + path("M30 8Q38 10 40 18M30 14Q34 15 35 19", None, A, 2))
    ic("safety_office", path("M24 6L40 12V24Q40 36 24 42Q8 36 8 24V12Z", None, C, W) + path("M24 16V32M16 24H32", None, A, 3.4))
    ic("engineer_office", circ(24, 24, 15, None, C, W) + path("M26 10L16 27H24L21 38L33 20H25Z", A, None, 0))
    ic("legal_office", path("M24 6V40M14 40H34", None, C, W) + path("M10 14H38", None, C, 2.4) + path("M10 14L5 27H15Z", None, C, 2) + path("M38 14L33 27H43Z", None, A, 2) + circ(24, 9, 2.4, A, None, 0))
    ic("classroom", rect(6, 8, 36, 24, None, C, W, 1) + path("M12 16H24M12 22H30", None, A, 2) + path("M18 32L14 42M30 32L34 42", None, C, 2))
    ic("compressor_room", circ(24, 24, 15, None, C, W) + path("M24 24L33 16", None, A, 3) + circ(24, 24, 2.6, C, None, 0) + path("M14 30H34", None, C, 1.6) + path("M24 39V44", None, C, W))
    ic("boiler_room", path("M24 6Q36 18 34 30Q32 40 24 42Q16 40 14 30Q12 18 24 6Z", None, C, W) + path("M24 22Q30 28 28 34Q26 38 24 38Q20 37 20 32Q20 27 24 22Z", A, None, 0))
    ic("union_office", line(12, 6, 12, 42, C, W) + path("M12 8H38L32 15L38 22H12", None, A, 2.4) + line(6, 42, 20, 42, C, 2))
    ic("dorm", path("M6 14V38M6 30H42V38M6 24H42", None, C, W) + rect(9, 17, 9, 6, A, None, 0, 2) + path("M20 24V20H42V24", None, C, 2))
    ic("medbay", circ(24, 24, 16, None, C, W) + path("M24 14V34M14 24H34", None, A, 4))
    ic("unload", rect(10, 22, 28, 20, None, C, W) + line(10, 30, 38, 30, C, 1.6) + path("M24 4V18M18 12L24 18L30 12", None, A, 3))
    ic("ship", rect(10, 22, 28, 20, None, C, W) + line(10, 30, 38, 30, C, 1.6) + path("M24 18V4M18 10L24 4L30 10", None, A, 3))
    ic("erase", path("M10 32L26 12L40 24L28 40H16Z", None, C, W) + path("M18 22L32 34", None, C, 2) + path("M6 42H42", None, A, 2.4))


def overlay_icons():
    """1.12: значки панели оверлеев справа."""
    C = "#e7e4d8"
    A = "#e0aa48"
    W = 2.6
    def ic(name, body):
        save(f"assets/ui/ov_{name}.svg", 48, 48, body)
    ic("rooms", rect(6, 6, 36, 36, None, C, W, 3) + line(24, 6, 24, 42, C, 2) + line(6, 24, 42, 24, C, 2) + rect(9, 9, 12, 12, A, None, 0, 1, 0.8))
    ic("power", path("M27 4L12 27H23L20 44L36 19H25Z", None, C, W) + path("M27 4L12 27H23", None, A, W))
    ic("water", path("M24 6Q36 22 36 30Q36 42 24 42Q12 42 12 30Q12 22 24 6Z", None, C, W) + path("M18 32Q19 37 24 38", None, A, 2.4))
    ic("light", path("M16 26Q12 22 12 17Q12 6 24 6Q36 6 36 17Q36 22 32 26V32H16Z", None, C, W) + path("M18 37H30M20 42H28", None, C, 2.4) + path("M20 18Q24 14 28 18", None, A, 2.4))
    ic("temp", path("M20 8Q20 4 24 4Q28 4 28 8V28Q34 32 32 38Q30 44 24 44Q18 44 16 38Q14 32 20 28Z", None, C, W) + circ(24, 36, 4, A, None, 0) + line(24, 14, 24, 33, A, 3))
    ic("noise", path("M8 18H16L26 9V39L16 30H8Z", None, C, W) + path("M32 17Q36 24 32 31M37 12Q44 24 37 36", None, A, 2.4))
    ic("traffic", ell(16, 14, 5, 7, None, C, 2.4) + ell(16, 26, 3, 3, None, C, 2) + ell(32, 26, 5, 7, None, A, 2.4) + ell(32, 38, 3, 3, None, A, 2))
    ic("load", path("M8 40H40", None, C, 2) + rect(10, 26, 6, 14, None, C, 2) + rect(21, 16, 6, 24, A, None, 0) + rect(32, 8, 6, 32, None, C, 2))
    ic("dirt", path("M30 6L18 30", None, C, W) + path("M12 28L26 34L22 44H6Z", None, C, W) + path("M10 38L12 44M16 36L17 44", None, A, 2) + circ(36, 38, 2.4, A, None, 0) + circ(40, 32, 1.6, C, None, 0))
    ic("vent", circ(24, 24, 18, None, C, W) + path("M24 24Q20 12 26 8Q30 16 24 24ZM24 24Q36 20 40 26Q32 30 24 24ZM24 24Q28 36 22 40Q18 32 24 24ZM24 24Q12 28 8 22Q16 18 24 24Z", A, None, 0))
    ic("air", circ(24, 22, 15, None, C, W) + path("M24 22L32 14", None, A, 3) + circ(24, 22, 2.4, C, None, 0) + path("M20 37V44H28V37", None, C, 2))
    # 1.15: все коммуникации одним слоем — кабель с молнией, труба с каплей
    ic("nets", path("M6 14H22Q28 14 28 20V44", None, C, W) + path("M42 34H30Q22 34 22 26V4", None, A, W)
       + path("M12 6L8 12H12L10 17", None, A, 1.8) + path("M38 18Q42 24 42 26Q42 30 38 30Q34 30 34 26Q34 24 38 18Z", C, None, 0))
    ic("crew", circ(16, 15, 5, None, C, W) + circ(32, 15, 5, None, A, 2.4) + path("M6 38Q6 26 16 26Q22 26 24 30Q26 26 32 26Q42 26 42 38", None, C, W))
    ic("off", circ(24, 24, 16, None, C, W) + line(13, 13, 35, 35, A, 3))


def materials_v112():
    """1.12: новые полы (наливной, голубая плитка, паркет), фактуры стен (бетон, сэндвич, перегородка) и значки меню."""
    T = 64
    rng = random.Random(1112)
    # наливной пол: гладкий серо-зелёный, блики и редкие швы
    s = rect(0, 0, T, T, "#9fa79f", None, 0)
    s += speckle(rng, T, T, 10, ["#a6aea6", "#98a098"], 0.5, 1.4)
    s += path("M6 52L22 36M30 60L50 40", None, "#ffffff", 2.2, 0.10)
    s += line(0, 0.5, T, 0.5, "#949c94", 0.8) + line(0.5, 0, 0.5, T, "#949c94", 0.8)
    save("assets/tiles/epoxy.svg", T, T, s)
    # голубая плитка: мелкая, со швами
    s = rect(0, 0, T, T, "#b9d2dc", None, 0)
    for k in range(0, T + 1, 16):
        s += line(k, 0, k, T, "#97b4c0", 1.2) + line(0, k, T, k, "#97b4c0", 1.2)
    for y in range(0, T, 16):
        for x in range(0, T, 16):
            if rng.random() < 0.25:
                s += rect(x + 1, y + 1, 14, 14, "#a9c5d1", None, 0)
    s += rect(2, 2, 12, 3, "#fff", None, 0, 0, 0.35)
    save("assets/tiles/tile_blue.svg", T, T, s)
    # паркет «ёлочкой»
    s = rect(0, 0, T, T, "#8f6c4c", None, 0)
    cols = ["#9a7656", "#86654a", "#937052", "#8b6a4e"]
    for y in range(-16, T + 16, 16):
        for x in range(-16, T + 16, 32):
            c = cols[(x // 32 + y // 16) % 4]
            s += poly([(x, y), (x + 16, y + 16), (x + 16, y + 24), (x, y + 8)], c, "#6e5038", 0.8)
            c2 = cols[(x // 32 + y // 16 + 1) % 4]
            s += poly([(x + 16, y + 16), (x + 32, y), (x + 32, y + 8), (x + 16, y + 24)], c2, "#6e5038", 0.8)
    s += rect(0, 0, T, T, "#ffd9a0", None, 0, 0, 0.06)
    save("assets/tiles/parquet.svg", T, T, s)
    # шапки стен
    s = rect(0, 0, T, T, "#4a4e53", None, 0) + speckle(rng, T, T, 40, ["#53575c", "#43474c"], 0.6, 1.6)
    save("assets/tiles/wall_top_concrete.svg", T, T, s)
    s = rect(0, 0, T, T, "#5a6670", None, 0)
    for k in range(4, T, 8):
        s += line(k, 0, k, T, "#6c7882", 1.2)
    save("assets/tiles/wall_top_sandwich.svg", T, T, s)
    s = rect(0, 0, T, T, "#6b6559", None, 0) + speckle(rng, T, T, 20, ["#726c60", "#655f53"], 0.5, 1.2)
    save("assets/tiles/wall_top_partition.svg", T, T, s)
    # лицевые грани (24 px текстуры = 12 мировых единиц)
    FH = 24
    s = rect(0, 0, T, FH, "#8f9294", None, 0) + speckle(rng, T, FH, 30, ["#868a8c", "#999c9e"], 0.5, 1.2)
    s += line(31.5, 0, 31.5, FH, "#6f7375", 1.4) + line(63.5, 0, 63.5, FH, "#6f7375", 1.4)
    for x in (8, 24, 40, 56):
        s += circ(x, 6, 1.2, "#6f7375", None, 0) + circ(x, 18, 1.2, "#6f7375", None, 0)
    s += rect(0, FH - 2, T, 2, "#000", None, 0, 0, 0.25)
    save("assets/tiles/wall_face_concrete.svg", T, FH, s)
    s = rect(0, 0, T, FH, "#c9d2d8", None, 0)
    for k in range(0, T, 8):
        s += rect(k, 0, 4, FH, "#b3bec5", None, 0) + line(k + 0.5, 0, k + 0.5, FH, "#dde4e8", 1)
    s += rect(0, 0, T, 3, "#3e6f9a", None, 0) + rect(0, FH - 2, T, 2, "#000", None, 0, 0, 0.25)
    save("assets/tiles/wall_face_sandwich.svg", T, FH, s)
    s = rect(0, 0, T, FH, "#e3dccb", None, 0) + speckle(rng, T, FH, 10, ["#ddd5c3", "#e8e1d1"], 0.5, 1.0)
    s += rect(0, FH - 5, T, 3, "#8a7a62", None, 0) + rect(0, FH - 2, T, 2, "#000", None, 0, 0, 0.25)
    save("assets/tiles/wall_face_partition.svg", T, FH, s)
    # значки меню: кусок стены как в игре
    def piece(top_fill, top_line, face_svg):
        out = rect(0, 10, 64, 30, top_fill, None, 0) + line(0, 11, 64, 11, top_line, 2)
        out += g(face_svg, "translate(0 40) scale(1 1)")
        out += rect(0, 62, 64, 2, "#000", None, 0, 0, 0.2)
        return out
    conc_face = rect(0, 0, 64, 24, "#8f9294", None, 0) + line(31.5, 0, 31.5, 24, "#6f7375", 1.4) + circ(16, 8, 1.4, "#6f7375", None, 0) + circ(48, 8, 1.4, "#6f7375", None, 0) + circ(16, 18, 1.4, "#6f7375", None, 0) + circ(48, 18, 1.4, "#6f7375", None, 0)
    save("assets/tiles/icon_wall_concrete.svg", 64, 64, piece("#4a4e53", "#61666c", conc_face))
    sw = rect(0, 0, 64, 24, "#c9d2d8", None, 0)
    for k in range(0, 64, 8):
        sw += rect(k, 0, 4, 24, "#b3bec5", None, 0)
    sw += rect(0, 0, 64, 3, "#3e6f9a", None, 0)
    save("assets/tiles/icon_wall_sandwich.svg", 64, 64, piece("#5a6670", "#77838d", sw))
    pt = rect(0, 0, 64, 24, "#e3dccb", None, 0) + rect(0, 19, 64, 3, "#8a7a62", None, 0)
    save("assets/tiles/icon_wall_partition.svg", 64, 64, piece("#6b6559", "#857e70", pt))
    md = rect(0, 10, 8, 30, "#33373d", None, 0) + rect(56, 10, 8, 30, "#33373d", None, 0)
    md += rect(8, 14, 48, 48, "#6f767b", None, 0) + rect(12, 18, 40, 44, "#7c858b", "#4b5257", 2)
    for k in range(3):
        md += rect(14, 24 + k * 13, 36, 3, "#5d656a", None, 0)
    md += rect(44, 40, 4, 8, "#d8dbde", None, 0) + circ(32, 21, 1.6, "#2a2e31", None, 0)
    save("assets/tiles/icon_door_metal.svg", 64, 64, md)
    for key in ["epoxy", "tile_blue", "parquet"]:
        pass


def flora_v113():
    """1.13: деревья (тополь, берёза, клён) и кусты (сирень, шиповник) — лето, осень, зима; значок «Земля»."""
    rng = random.Random(1113)
    W, H = 96, 128
    BX, BY = 48, 120          # точка у основания ствола

    def crown(cx, cy, rx, ry, cols, n, rr=(9, 15), seed=0):
        r2 = random.Random(seed)
        out = ""
        dark, mid, light = cols
        # тёмная подложка, затем средние листья, сверху светлые с бликом
        out += ell(cx, cy + ry * 0.15, rx, ry, dark, OUT, 1.8)
        for k in range(n):
            a = r2.random() * math.pi * 2
            d = r2.random() ** 0.6
            x = cx + math.cos(a) * rx * 0.72 * d
            y = cy + math.sin(a) * ry * 0.72 * d
            r = r2.uniform(*rr)
            out += circ(x, y, r, mid, None, 0)
        for k in range(n // 2):
            a = r2.uniform(math.pi * 0.9, math.pi * 1.9)
            d = r2.random() ** 0.8
            x = cx + math.cos(a) * rx * 0.55 * d
            y = cy + math.sin(a) * ry * 0.55 * d - ry * 0.12
            r = r2.uniform(rr[0] * 0.6, rr[1] * 0.75)
            out += circ(x, y, r, light, None, 0)
        out += path(f"M{cx - rx * 0.55} {cy - ry * 0.35}Q{cx - rx * 0.2} {cy - ry * 0.85} {cx + rx * 0.25} {cy - ry * 0.7}", None, "#ffffff", 2.2, 0.18)
        return out

    def branches(cx, top, spread, col, snow, seed=0):
        r2 = random.Random(seed)
        out = ""
        for k in range(7):
            ang = -math.pi / 2 + r2.uniform(-1.0, 1.0)
            l = r2.uniform(spread * 0.5, spread)
            y0 = top + r2.uniform(10, 40)
            x1 = cx + math.cos(ang) * l
            y1 = y0 + math.sin(ang) * l
            out += line(cx, y0, x1, y1, col, 2.2)
            for j in range(2):
                a2 = ang + r2.uniform(-0.7, 0.7)
                l2 = l * 0.45
                out += line(x1, y1, x1 + math.cos(a2) * l2, y1 + math.sin(a2) * l2, col, 1.3)
            if snow:
                out += line(x1 - 3, y1 - 1, x1 + 3, y1 - 1, "#f4f6f8", 2.2)
        return out

    def trunk(h, col, w=7, birch=False):
        out = path(f"M{BX - w / 2} {BY}L{BX - w / 2 + 1} {BY - h}H{BX + w / 2 - 1}L{BX + w / 2} {BY}Z", col, OUT, 1.6)
        if birch:
            for k in range(5):
                y = BY - 6 - k * (h / 5.5)
                out += rect(BX - w / 2 + (1 if k % 2 else 3), y, 3 + (k % 3), 1.6, "#2a2c2e", None, 0)
        else:
            out += line(BX - 1, BY - 4, BX - 1, BY - h + 4, "#000000", 1, 0.18)
        out += path(f"M{BX - w / 2 - 3} {BY}Q{BX} {BY - 4} {BX + w / 2 + 3} {BY}", None, OUT, 1.4, 0.6)
        return out

    def shadow_base(rx=26):
        return ell(BX + 10, BY - 1, rx, 6, "#000", None, 0, 0.22)

    trees = {
        "poplar": {"h": 44, "col": "#7a6e60", "cx": BX, "cy": 50, "rx": 22, "ry": 44, "n": 26, "rr": (7, 12),
                   "summer": ("#3f6a32", "#4f8240", "#6f9e52"), "autumn": ("#9a7a26", "#c9a13a", "#e2c45a")},
        "birch": {"h": 52, "col": "#e9e6dc", "cx": BX, "cy": 54, "rx": 30, "ry": 34, "n": 30, "rr": (6, 10), "birch": True,
                  "summer": ("#4f7a36", "#689a48", "#8cb862"), "autumn": ("#a8892c", "#d8b440", "#efd76a")},
        "maple": {"h": 36, "col": "#6e5a48", "cx": BX, "cy": 58, "rx": 36, "ry": 32, "n": 30, "rr": (9, 14),
                  "summer": ("#3a6630", "#4c7e3c", "#679a4c"), "autumn": ("#9a3e22", "#c8582c", "#e48a3c")},
    }
    for name, d in trees.items():
        for sea in ("summer", "autumn"):
            b = shadow_base()
            b += trunk(d["h"], d["col"], 7 if name != "maple" else 9, d.get("birch", False))
            b += crown(d["cx"], d["cy"], d["rx"], d["ry"], d[sea], d["n"], d["rr"], seed=sum(map(ord, name)))
            if sea == "autumn":
                r3 = random.Random(7)
                for k in range(5):
                    b += circ(BX + r3.uniform(-26, 30), BY - r3.uniform(0, 4), 1.6, d[sea][1], None, 0)
            save(f"assets/objects/tree_{name}_{sea}.svg", W, H, b)
        b = shadow_base(18) + trunk(d["h"] + 24, d["col"], 7 if name != "maple" else 9, d.get("birch", False))
        b += branches(BX, BY - d["h"] - 34, 34 if name != "poplar" else 20, d["col"] if name != "birch" else "#6a6458", True, seed=len(name))
        b += ell(BX, BY - 2, 20, 4, "#f4f6f8", None, 0, 0.8)
        save(f"assets/objects/tree_{name}_winter.svg", W, H, b)
    # кусты 64×64, основание (32, 58)
    bushes = {"lilac": {"summer": ("#3d6a36", "#4f8244", "#6a9a56"), "autumn": ("#5a6a2e", "#76863c", "#94a052"), "dots": "#a77ad0"},
              "rose": {"summer": ("#3f6a30", "#548440", "#6e9c50"), "autumn": ("#8a4a22", "#b8642c", "#d88a3c"), "dots": "#c8302a"}}
    for name, d in bushes.items():
        for sea in ("summer", "autumn"):
            b = ell(38, 57, 26, 6, "#000", None, 0, 0.22)
            r3 = random.Random(len(name) + len(sea))
            dark, mid, light = d[sea]
            b += ell(32, 42, 26, 16, dark, OUT, 1.6)
            for k in range(14):
                b += circ(32 + r3.uniform(-20, 20), 42 + r3.uniform(-10, 8), r3.uniform(6, 9), mid, None, 0)
            for k in range(7):
                b += circ(32 + r3.uniform(-16, 14), 36 + r3.uniform(-6, 4), r3.uniform(4, 6), light, None, 0)
            if name == "lilac" and sea == "summer" or name == "rose":
                for k in range(9):
                    b += circ(32 + r3.uniform(-18, 18), 38 + r3.uniform(-8, 8), 2.2 if name == "lilac" else 1.8, d["dots"], None, 0)
            save(f"assets/objects/bush_{name}_{sea}.svg", 64, 64, b)
        b = ell(38, 57, 22, 5, "#000", None, 0, 0.18)
        r3 = random.Random(3)
        for k in range(10):
            a = -math.pi / 2 + r3.uniform(-1.2, 1.2)
            l = r3.uniform(14, 24)
            b += line(32, 56, 32 + math.cos(a) * l, 56 + math.sin(a) * l, "#5a4a3a", 1.6)
        if name == "rose":
            for k in range(6):
                b += circ(32 + r3.uniform(-14, 14), 42 + r3.uniform(-8, 8), 1.8, d["dots"], None, 0)
        b += ell(32, 55, 18, 4, "#f4f6f8", None, 0, 0.85)
        save(f"assets/objects/bush_{name}_winter.svg", 64, 64, b)
    # значок ветки «Земля»: участок с колышками и флажком
    C = "#e7e4d8"
    A = "#e0aa48"
    save("assets/ui/land.svg", 48, 48, path("M6 38L18 30L42 34L30 44Z", None, C, 2.4) + line(18, 30, 18, 8, C, 2.4)
         + path("M18 8H32L28 13L32 18H18", A, None, 0) + circ(6, 38, 2, A, None, 0) + circ(42, 34, 2, A, None, 0) + circ(30, 44, 2, A, None, 0))


def cnc_v113():
    """Правка 1.13: токарный с ЧПУ стал 3×2 — кожух глубокий, и в повороте он широкий, а не «пенал»."""
    T0 = 66
    WH, WF = "#e4e7e8", "#c6cbcd"
    # --- спереди 3×2
    b = shadow(14, T0 - 20, 186, 148)
    b += box(4, T0 - 30, 166, 66, 90, WH, WF)
    for k in range(5):
        b += line(22, T0 - 16 + k * 9, 120, T0 - 16 + k * 9, "#cfd4d6", 1.6)
    b += rect(128, T0 - 20, 34, 40, "#cfd4d6", OUT, 1.2, 2) + rect(132, T0 - 16, 26, 32, None, "#aab1b5", 1, 1)
    b += rect(20, T0 + 44, 108, 58, "#2a3036", OUT, 2, 3)
    b += rect(24, T0 + 48, 100, 50, "#3e5866", None, 0, 2, 0.85) + poly([(30, T0 + 48), (54, T0 + 48), (36, T0 + 98), (24, T0 + 98)], "#ffffff", None, 0, 0.12)
    b += rect(36, T0 + 62, 22, 22, "#9aa3a8", OUT, 1.2, 2) + rect(58, T0 + 69, 42, 8, "#c9ccce", OUT, 1.2) + rect(100, T0 + 71, 10, 4, "#c9ccce", OUT, 1)
    b += rect(130, T0 + 44, 4, 58, "#9aa3a8", None, 0)
    b += rect(10, T0 + 112, 156, 12, "#3d5a7a", OUT, 1.6)
    b += box(172, T0 + 2, 24, 12, 112, "#3d4652", "#2e3640")
    b += rect(176, T0 + 22, 16, 14, "#1d2a34", OUT, 1) + rect(178, T0 + 24, 12, 10, "#6fd0e0", None, 0, 1, 0.8)
    for yy in range(3):
        for xx in range(3):
            b += rect(176 + xx * 5.5, T0 + 44 + yy * 6, 4, 4, ["#c9ccce", "#e2b73a", "#6fbf86"][(xx + yy) % 3], None, 0, 1)
    b += circ(184, T0 + 80, 4, "#c94a3a", OUT, 1)
    b += rect(140, T0 - 46, 6, 16, "#3a3f43", OUT, 1) + circ(143, T0 - 50, 4, "#6fbf86", OUT, 1)
    b += rect(24, T0 - 26, 60, 7, "#3d5a7a", None, 0, 1)
    obj("cnc_lathe", 3, 2, T0, b)
    META["cnc_lathe"]["anchors"] = {"lamp": [143, T0 - 50], "work": [70, T0 + 72], "in": [150, T0 + 100], "out": [16, T0 + 100], "screen": [184, T0 + 29]}
    # --- со спины 3×2
    b = shadow(14, T0 - 20, 186, 148)
    b += box(28, T0 - 30, 166, 66, 90, "#d8dbdc", "#bcc1c3")
    for k in range(7):
        b += line(40, T0 + 46 + k * 9, 130, T0 + 46 + k * 9, "#a7adb0", 2)
    b += rect(140, T0 + 46, 44, 42, "#9aa3a8", OUT, 1.4, 2) + rect(144, T0 + 50, 36, 34, None, "#7a8388", 1, 1)
    b += rect(34, T0 + 112, 156, 12, "#3d5a7a", OUT, 1.6)
    b += box(2, T0 + 2, 24, 12, 112, "#3d4652", "#2e3640")
    b += rect(146, T0 - 46, 6, 16, "#3a3f43", OUT, 1) + circ(149, T0 - 50, 4, "#6fbf86", OUT, 1)
    obj("cnc_lathe_b", 3, 2, T0, b)
    META["cnc_lathe_b"]["anchors"] = {"lamp": [149, T0 - 50], "work": [100, T0 + 72], "in": [40, T0 + 100], "out": [170, T0 + 100]}
    # --- в повороте 2×3: длинный кожух вдоль, смотровое окно сверху, пульт сбоку
    T0 = 70
    H = 192
    b = shadow(14, T0 - 30, 116, H + 22)
    b += box(8, T0 - 50, 112, H - 18, 64, WH, WF)
    b += rect(22, T0 - 36, 64, H - 54, "#2a3036", OUT, 2, 3)
    b += rect(26, T0 - 32, 56, H - 62, "#3e5866", None, 0, 2, 0.85) + poly([(28, T0 - 30), (44, T0 - 30), (32, T0 + 50), (28, T0 + 50)], "#ffffff", None, 0, 0.12)
    b += rect(42, T0 - 22, 24, 22, "#9aa3a8", OUT, 1.2, 2) + rect(49, T0, 10, 56, "#c9ccce", OUT, 1.2)
    for k in range(5):
        b += line(94, T0 - 30 + k * 10, 112, T0 - 30 + k * 10, "#cfd4d6", 1.6)
    b += box(100, T0 + H - 118, 22, 30, 50, "#3d4652", "#2e3640")
    b += rect(104, T0 + H - 112, 14, 12, "#1d2a34", OUT, 1) + rect(105, T0 + H - 110, 12, 8, "#6fd0e0", None, 0, 1, 0.8)
    b += circ(111, T0 + H - 74, 3.5, "#c94a3a", OUT, 1)
    b += rect(12, T0 + H - 10, 104, 10, "#3d5a7a", OUT, 1.6)
    b += rect(96, T0 - 64, 6, 14, "#3a3f43", OUT, 1) + circ(99, T0 - 66, 4, "#6fbf86", OUT, 1)
    obj("cnc_lathe_v", 2, 3, T0, b)
    META["cnc_lathe_v"]["anchors"] = {"lamp": [99, T0 - 66], "work": [54, T0 + 30], "in": [8, T0 + H - 22], "out": [118, T0 + H - 22]}


def bmats_v113():
    """1.13: стройматериалы — штабели на поддонах (3 степени заполнения), единица в руках, бортовой грузовик."""
    WOOD, WOOD_D = "#b48a58", "#8a6440"

    def pallet_base(x, y, w):
        out = rect(x, y, w, 5, WOOD, OUT, 1.4)
        for k in range(3):
            out += rect(x + 2 + k * (w - 10) / 2, y + 5, 6, 4, WOOD_D, OUT, 1)
        return out

    def layer(key, x, y, w, h, k):
        """Один слой материала шириной w и высотой h, верх в y."""
        out = ""
        if key == "bm_brick":
            out += rect(x, y, w, h, "#a8503a", OUT, 1.4)
            for r in range(2):
                yy = y + r * h / 2
                out += line(x, yy, x + w, yy, "#7a3426", 1)
                off = 0 if (r + k) % 2 == 0 else 5
                for cx in range(int(x + off + 10), int(x + w), 10):
                    out += line(cx, yy, cx, yy + h / 2, "#7a3426", 1)
        elif key == "bm_block":
            out += rect(x, y, w, h, "#a3a6a8", OUT, 1.4)
            for cx in range(int(x + 13), int(x + w), 13):
                out += line(cx, y, cx, y + h, "#7c8082", 1.2)
            out += line(x + 2, y + 2, x + w - 2, y + 2, "#ffffff", 1, 0.3)
        elif key == "bm_panel":
            out += rect(x, y, w, h, "#c9d2d8", OUT, 1.4) + rect(x, y, w, 2.5, "#3e6f9a", None, 0)
            for cx in range(int(x + 4), int(x + w), 6):
                out += line(cx, y + 3, cx, y + h, "#b3bec5", 1)
        elif key == "bm_gkl":
            out += rect(x, y, w, h, "#ece6d6", OUT, 1.4) + line(x, y + h / 2, x + w, y + h / 2, "#c9c0aa", 1)
            if k == 0:
                out += rect(x + 2, y - 3, w - 4, 3, "#a9b0b4", OUT, 0.8)
        elif key == "bm_window":
            out += rect(x, y, w, h, "#f2f4f4", OUT, 1.4) + rect(x + 3, y + 2, w / 2 - 4, h - 4, "#8fb8d4", None, 0) + rect(x + w / 2 + 1, y + 2, w / 2 - 4, h - 4, "#8fb8d4", None, 0)
        elif key == "bm_door":
            out += rect(x, y, w, h, "#8a5a36", OUT, 1.4) + rect(x + 3, y + 2, w - 6, h - 4, None, "#6a4226", 1) + rect(x, y, w, h, "#ffffff", None, 0, 0, 0.18)
        elif key == "bm_gate":
            out += rect(x, y, w, h, "#9ca3a8", OUT, 1.4)
            for r in range(1, 3):
                out += line(x, y + r * h / 3, x + w, y + r * h / 3, "#7a8186", 1)
        elif key == "bm_cement":
            for cx in range(0, 3):
                out += rect(x + cx * w / 3 + 0.5, y, w / 3 - 1, h, "#c8c2b0", OUT, 1.2, 3) + line(x + cx * w / 3 + 3, y + h / 2, x + (cx + 1) * w / 3 - 3, y + h / 2, "#3d6a9a", 1.6)
        elif key == "bm_tile":
            for cx in range(0, 2):
                out += rect(x + cx * w / 2 + 0.5, y, w / 2 - 1, h, "#c9a26e", OUT, 1.2) + line(x + cx * w / 2 + 2, y + 2, x + (cx + 1) * w / 2 - 2, y + 2, "#e8d4a8", 1)
                out += rect(x + cx * w / 2 + 4, y + h / 2 - 1.5, 7, 3, "#3d6a9a", None, 0)
        elif key == "bm_lino":
            for cx in range(0, 3):
                out += ell(x + w / 6 + cx * w / 3, y + h / 2, w / 6 - 0.5, h / 2, "#9a8a6a", OUT, 1.2) + circ(x + w / 6 + cx * w / 3, y + h / 2, 2, "#6a5a3a", None, 0)
        elif key == "bm_epoxy":
            for cx in range(0, 3):
                xx = x + cx * w / 3 + 1
                out += rect(xx, y, w / 3 - 2, h, "#6f8a72", OUT, 1.2, 2) + rect(xx, y, w / 3 - 2, 2.5, "#4a5e4c", None, 0)
        elif key == "bm_parquet":
            out += rect(x, y, w, h, "#b07a4a", OUT, 1.4)
            for cx in range(int(x + 8), int(x + w), 8):
                out += line(cx, y, cx, y + h, "#8a5a32", 1)
            out += rect(x, y + h / 2 - 1, w, 2, "#e8e0c8", None, 0, 0, 0.7)
        return out

    keys = ["bm_brick", "bm_block", "bm_panel", "bm_gkl", "bm_window", "bm_door", "bm_gate", "bm_cement", "bm_tile", "bm_lino", "bm_epoxy", "bm_parquet"]
    for key in keys:
        for lv in (1, 2, 3):
            b = ell(34, 58, 26, 5, "#000", None, 0, 0.22)
            b += pallet_base(8, 49, 48)
            tall = key in ("bm_window", "bm_door", "bm_gate")
            lh = 8 if not tall else 11
            # 1.18: поддоны полнее — штабель почти во всю высоту клетки
            nl = {1: 2, 2: 4, 3: 6}[lv] if not tall else {1: 1, 2: 2, 3: 4}[lv]
            for k in range(nl):
                b += layer(key, 9, 49 - (k + 1) * lh, 46, lh, k)
            if key in ("bm_brick", "bm_block", "bm_gkl", "bm_panel"):
                top = 49 - nl * lh
                b += line(9, top + 1, 55, 49, "#ffffff", 1.2, 0.35) + line(55, top + 1, 9, 49, "#ffffff", 1.2, 0.2)   # стрейч-плёнка
            save(f"assets/items/{key}_p{lv}.svg", 64, 64, b)
        # единица «в руках» (32×32)
        b = ell(16, 27, 12, 3, "#000", None, 0, 0.22)
        b += layer(key, 4, 13, 24, 11 if key not in ("bm_window", "bm_door", "bm_gate") else 13, 0)
        save(f"assets/items/{key}.svg", 32, 32, b)
    # бортовой грузовик (смотрит вправо), 3,4 тайла
    W, H = 216, 120
    base_y = 104
    body = ell(110, base_y + 6, 100, 9, "#000", None, 0, 0.3)
    body += path("M150 26H176Q190 26 198 48L206 60V94H150Z", "#ffffff", OUT, 2)      # кабина (тонируется)
    save("assets/vehicles/flatbed_body.svg", W, H, body)
    det = rect(6, 70, 142, 12, "#5a6268", OUT, 1.6)                                   # платформа
    det += rect(6, 58, 142, 12, "#8a9a7a", OUT, 1.4) + line(54, 58, 54, 70, OUT, 1.2) + line(100, 58, 100, 70, OUT, 1.2)  # борт
    det += path("M156 32H174Q184 32 190 48L193 54H156Z", "#7fa4c4", OUT, 1.6) + path("M160 36L168 50", None, "#fff", 2, 0.5)
    det += rect(8, 86, 196, 8, "#3a3e42", OUT, 1.5)
    det += rect(198, 70, 8, 8, "#ffe9a8", OUT, 1) + rect(6, 74, 5, 8, "#c0392b", OUT, 1)
    det += line(150, 44, 150, 94, OUT, 2)
    for cx in (40, 76, 176):
        det += circ(cx, base_y - 4, 13, "#1d1d1d", OUT, 1.5) + circ(cx, base_y - 4, 6, "#8a9196", OUT, 1)
    save("assets/vehicles/flatbed_details.svg", W, H, det)
    # груз на платформе: два поддона в плёнке
    cg = ""
    for i, col in enumerate(("#a8503a", "#c9a26e")):
        x = 14 + i * 66
        cg += rect(x, 52, 58, 6, WOOD, OUT, 1.4)
        cg += rect(x + 2, 20, 54, 32, col, OUT, 1.6)
        for r in range(1, 4):
            cg += line(x + 2, 20 + r * 8, x + 56, 20 + r * 8, "#000", 1, 0.25)
        cg += line(x + 2, 21, x + 56, 51, "#ffffff", 1.4, 0.35)
    save("assets/vehicles/flatbed_cargo.svg", W, H, cg)


def power_v113():
    """1.13: аккумуляторный шкаф 1×1, насосная станция 2×1, значок зоны «Техпомещение»."""
    T0 = 56
    b = shadow(10, T0 - 6, 50, 62)
    b += box(6, T0 - 44, 52, 12, 92, "#c9ced1", "#aeb5b9")
    b += rect(12, T0 - 24, 40, 64, None, "#8a9398", 1.4, 2)
    for k in range(6):
        b += rect(16, T0 - 18 + k * 9, 32, 5, "#7c868c", None, 0, 1)
    b += rect(14, T0 + 44, 36, 4, "#3a3f43", None, 0)
    b += path(f"M30 {T0-40}L24 {T0-30}H30L27 {T0-22}L36 {T0-33}H30Z", "#e2b73a", OUT, 1)
    obj("battery", 1, 1, T0, b)
    META["battery"]["anchors"] = {"lamp": [32, T0 - 30]}
    # насосная: два насоса на раме, трубы, манометр, шкаф управления
    T0 = 40
    b = shadow(12, T0 - 4, 118, 62)
    b += rect(6, T0 + 38, 116, 14, "#4e5f54", OUT, 1.8)
    for x in (14, 66):
        b += rect(x, T0 + 10, 30, 28, "#3d6fb0", OUT, 1.8, 6) + rect(x + 3, T0 + 13, 24, 5, "#ffffff", None, 0, 2, 0.25)
        for k in range(4):
            b += line(x + 5 + k * 6, T0 + 22, x + 5 + k * 6, T0 + 34, "#2c5288", 1.2)
        b += rect(x + 30, T0 + 18, 12, 16, "#9aa3a8", OUT, 1.4, 3)
    b += rect(4, T0 - 2, 120, 9, "#8a949c", OUT, 1.6, 4) + rect(4, T0 - 2, 120, 3, "#ffffff", None, 0, 2, 0.25)
    b += rect(22, T0 + 6, 6, 6, "#8a949c", OUT, 1) + rect(74, T0 + 6, 6, 6, "#8a949c", OUT, 1)
    b += circ(100, T0 - 12, 7, "#f4f6f6", OUT, 1.4) + line(100, T0 - 12, 104, T0 - 16, "#c94a3a", 1.4)
    b += line(100, T0 - 5, 100, T0 - 2, OUT, 1.6)
    b += box(108, T0 - 14, 16, 8, 44, "#d8dcdd", "#bfc5c8") + circ(116, T0 + 6, 2.4, "#6fbf86", None, 0)
    obj("pump_station", 2, 1, T0, b)
    META["pump_station"]["anchors"] = {"lamp": [116, T0 + 6]}
    C = "#e7e4d8"
    A = "#e0aa48"
    save("assets/ui/zone_tech_room.svg", 48, 48, rect(6, 8, 36, 34, None, C, 2.6, 3) + path("M22 12L14 27H21L18 38L30 21H23L26 12Z", A, None, 0) + path("M36 16Q42 24 42 28Q42 34 36 34Q30 34 30 28Q30 24 36 16Z", None, C, 2))


def carry_v114():
    """1.14: что человек несёт и чем работает — ящик с инструментом, катушка кабеля, кельма, пульт крана;
    пруток на плече, лист, лоток с деталями."""
    def prop(key, body, w=32, h=32):
        save(f"assets/people/prop_{key}.svg", w, h, body)
    prop("toolbox", rect(4, 13, 24, 15, "#c9372c", OUT, 1.4, 2) + rect(4, 13, 24, 5, "#a82c22", None, 0) + path("M11 13V8H21V13", None, "#3a3f43", 2.2)
         + rect(14, 18, 4, 3, "#d8dbde", OUT, 0.8) + line(6, 25, 26, 25, "#000", 1, 0.2))
    prop("reel", circ(16, 17, 12, "#8a6a44", OUT, 1.4) + circ(16, 17, 8, "#2a2e31", None, 0) + circ(16, 17, 7, None, "#3a3f43", 2.2) + circ(16, 17, 4, None, "#3a3f43", 2.2)
         + circ(16, 17, 2.5, "#c9a24a", OUT, 0.8) + path("M26 22Q30 26 28 31", None, "#2a2e31", 1.8))
    prop("trowel", path("M8 24L22 10L27 15L13 29Z", "#b9c0c4", OUT, 1.2) + line(22, 10, 26, 4, "#3a3f43", 1.6) + rect(24, 1, 5, 6, "#8a5a36", OUT, 1, 1))
    prop("pendant", rect(10, 12, 12, 18, "#e0b73a", OUT, 1.4, 3) + circ(16, 17, 2.2, "#3d8a4a", OUT, 0.8) + circ(16, 23, 2.2, "#c9372c", OUT, 0.8)
         + path("M16 12V2", None, "#2a2e31", 1.6))
    # пруток на плече: длинный, сбоку; и с торца (спереди/сзади)
    bars = {"bar45": ("#9aa1a5", "#c7cdd0", "round"), "bar40x": ("#7d848a", "#a9b0b5", "round"), "hex27": ("#8e9a92", "#b4bfb7", "hex"), "profile40": ("#8a9196", "#b9c0c4", "square")}
    for key, (c1, c2, shape) in bars.items():
        b = rect(0, 3, 76, 7, c1, OUT, 1.2, 3) + line(2, 5, 74, 5, "#ffffff", 1.2, 0.45)
        b += ell(75, 6.5, 2.2, 3.5, c2, OUT, 0.8) if shape == "round" else rect(73, 3, 3, 7, c2, OUT, 0.8)
        save(f"assets/people/carry_bar_{key}.svg", 78, 13, b)
        e = circ(6, 6, 4.5, c2, OUT, 1.2) if shape == "round" else (poly([(2, 6), (4, 2), (8, 2), (10, 6), (8, 10), (4, 10)], c2, OUT, 1.2) if shape == "hex" else rect(1.5, 1.5, 9, 9, c2, OUT, 1.2))
        save(f"assets/people/carry_barend_{key}.svg", 12, 12, e)
    save("assets/people/carry_sheet.svg", 40, 30, rect(1, 1, 38, 28, "#9aa3a8", OUT, 1.4, 1) + line(4, 4, 30, 26, "#ffffff", 1.4, 0.25) + rect(1, 1, 38, 3, "#c7cdd0", None, 0, 0, 0.6))
    save("assets/people/carry_sheet_edge.svg", 8, 30, rect(2, 1, 4, 28, "#8a9398", OUT, 1.2))
    # лоток (тара для мелких деталей)
    save("assets/people/carry_tray.svg", 34, 20, path("M2 6H32L29 19H5Z", "#4a6a8a", OUT, 1.4) + rect(2, 4, 30, 4, "#5f84a8", OUT, 1.2) + line(9, 10, 25, 10, "#ffffff", 1, 0.25))


def vehicles_v114():
    """1.14: грузовик-самосвал с бортами (металл, лом), фура с полуприцепом (станки, большие партии)."""
    base_y = 104
    # --- бортовой грузовик с кабиной над мотором, 4 тайла
    W, H = 264, 120
    body = ell(132, base_y + 6, 122, 9, "#000", None, 0, 0.3)
    body += path("M190 20H236Q248 20 250 34V94H190Z", "#ffffff", OUT, 2)            # кабина (тонируется)
    save("assets/vehicles/truck_body.svg", W, H, body)
    det = rect(6, 72, 182, 12, "#4a5156", OUT, 1.6)                                    # рама и платформа
    det += rect(6, 48, 182, 24, "#6f7a5a", OUT, 1.6)                                   # борт
    for x in (52, 98, 144):
        det += line(x, 48, x, 72, OUT, 1.2)
    det += rect(6, 48, 182, 4, "#86926e", None, 0)
    det += rect(198, 28, 44, 26, "#7fa4c4", OUT, 1.6) + path("M204 32L214 50", None, "#fff", 2, 0.5)
    det += rect(190, 60, 60, 4, "#000", None, 0, 0, 0.18) + rect(244, 70, 8, 8, "#ffe9a8", OUT, 1) + rect(186, 22, 4, 72, "#3a3e42", None, 0)
    det += rect(240, 82, 12, 12, "#3a3e42", OUT, 1)                                    # бампер
    det += rect(8, 84, 244, 8, "#2f3336", OUT, 1.5)
    for cx in (40, 76, 222):
        det += circ(cx, base_y - 4, 14, "#1d1d1d", OUT, 1.5) + circ(cx, base_y - 4, 6.5, "#8a9196", OUT, 1)
    save("assets/vehicles/truck_details.svg", W, H, det)
    cg = ""
    for i in range(3):
        x = 12 + i * 58
        for j in range(4):
            cg += rect(x, 30 + j * 4.5, 52, 5, "#9aa1a5", OUT, 1, 2) + line(x + 2, 31 + j * 4.5, x + 50, 31 + j * 4.5, "#fff", 1, 0.4)
        cg += rect(x + 10, 28, 3, 22, "#c94a3a", None, 0, 0, 0.9) + rect(x + 38, 28, 3, 22, "#c94a3a", None, 0, 0, 0.9)
    save("assets/vehicles/truck_cargo.svg", W, H, cg)
    # --- фура: тягач и полуприцеп-фургон, 7 тайлов
    W2 = 448
    body = ell(224, base_y + 6, 214, 10, "#000", None, 0, 0.3)
    body += rect(4, 10, 330, 74, "#ffffff", OUT, 2)                                     # фургон (тонируется)
    body += path("M352 14H408Q428 14 432 34V94H352Z", "#ffffff", OUT, 2)               # кабина тягача
    save("assets/vehicles/semi_body.svg", W2, H, body)
    det = rect(4, 10, 330, 74, "#000", None, 0, 0, 0.06)
    for x in range(30, 330, 44):
        det += line(x, 12, x, 82, "#000", 1, 0.12)
    det += rect(4, 10, 330, 6, "#ffffff", None, 0, 0, 0.5) + line(6, 80, 332, 80, "#3a3e42", 2)
    det += rect(336, 70, 18, 14, "#3a3e42", OUT, 1.2)                                  # седло
    det += rect(360, 22, 64, 30, "#7fa4c4", OUT, 1.6) + path("M368 26L380 48", None, "#fff", 2, 0.5)
    det += rect(352, 58, 80, 4, "#000", None, 0, 0, 0.18) + rect(424, 68, 8, 8, "#ffe9a8", OUT, 1) + rect(348, 16, 4, 78, "#3a3e42", None, 0)
    det += rect(358, 54, 6, 30, "#b8c0c6", OUT, 1)                                     # выхлопная труба
    det += rect(8, 84, 330, 8, "#2f3336", OUT, 1.5) + rect(340, 84, 96, 8, "#2f3336", OUT, 1.5)
    for cx in (40, 72, 104, 372, 410):
        det += circ(cx, base_y - 4, 14, "#1d1d1d", OUT, 1.5) + circ(cx, base_y - 4, 6.5, "#8a9196", OUT, 1)
    det += rect(6, 70, 6, 10, "#c0392b", OUT, 1)
    save("assets/vehicles/semi_details.svg", W2, H, det)


def shower_v114():
    """1.14: душевая кабина 1×1 (вид сверху-спереди: кафель, стеклянная дверца, лейка) и значок зоны."""
    T0 = 58
    b = shadow(8, T0 - 4, 52, 66)
    b += rect(4, T0 - 50, 56, 112, "#d9e6ec", OUT, 2, 2)                 # кафельные стенки
    for y in range(T0 - 46, T0 + 60, 9):
        b += line(6, y, 58, y, "#b9ccd6", 0.8)
    for x in range(14, 58, 10):
        b += line(x, T0 - 48, x, T0 + 60, "#c6d6de", 0.6)
    b += rect(10, T0 + 30, 44, 26, "#eef3f6", OUT, 1.4, 3) + circ(32, T0 + 43, 3, "#8a9398", OUT, 1)   # поддон и слив
    b += path(f"M32 {T0-46}V{T0-30}H44", None, "#9aa3a8", 2.4) + rect(40, T0 - 33, 10, 5, "#c7cdd0", OUT, 1, 2)   # лейка
    b += rect(8, T0 - 12, 48, 70, "#9cc8e0", "#5a8aa8", 1.6, 2, 0.35)      # стеклянная дверца
    b += path(f"M12 {T0-8}L22 {T0+50}", None, "#ffffff", 2, 0.4) + rect(48, T0 + 18, 3, 12, "#c7cdd0", OUT, 0.8)
    obj("shower", 1, 1, T0, b)
    C = "#e7e4d8"
    A = "#e0aa48"
    save("assets/ui/zone_shower.svg", 48, 48, path("M10 8H22V14", None, C, 2.6) + rect(18, 14, 12, 5, C, None, 0, 2)
         + path("M19 24V30M24 24V34M29 24V30M21 36V40M27 36V42", None, A, 2.4) + path("M8 44H40", None, C, 2))


def objects_v19():
    """1.9 «Город»: двухъярусная кровать, плита, раздача, кушетка, шкаф с лекарствами,
    радиоузел, громкоговоритель, миска для кота; кот; иконки."""
    # --- двухъярусная кровать 2×1
    T0 = 70
    b = shadow(10, T0 + 2, 122, 62)
    FR, FRD = "#5d6b78", "#46525d"
    for x in (6, 118):
        b += rect(x, T0 - 66, 6, 128, FR, OUT, 1.6, 1)
    # нижний ярус
    b += rect(10, T0 + 22, 110, 30, "#d9d6cc", OUT, 1.6, 3) + rect(10, T0 + 22, 110, 8, "#b8c4cf", None, 0, 2)
    b += rect(14, T0 + 26, 22, 12, "#f4f2ea", OUT, 1, 4) + path(f"M44 {T0+34}h70", None, "#9aa6b0", 1.2)
    b += rect(40, T0 + 30, 78, 22, "#4f6f96", OUT, 1.4, 3) + path(f"M48 {T0+38}h60M48 {T0+44}h60", None, "#3e5a7c", 1)
    # верхний ярус
    b += rect(10, T0 - 30, 110, 30, "#d9d6cc", OUT, 1.6, 3)
    b += rect(14, T0 - 26, 22, 12, "#f4f2ea", OUT, 1, 4)
    b += rect(40, T0 - 22, 78, 22, "#8a4f4a", OUT, 1.4, 3) + path(f"M48 {T0-14}h60M48 {T0-8}h60", None, "#6f3d39", 1)
    b += rect(6, T0 - 34, 116, 5, FRD, OUT, 1.2) + rect(6, T0 + 18, 116, 5, FRD, OUT, 1.2)
    for y in range(T0 - 22, T0 + 18, 9):
        b += line(118, y, 124, y, FR, 2)
    b += rect(6, T0 + 56, 6, 6, "#2e3236", None, 0) + rect(118, T0 + 56, 6, 6, "#2e3236", None, 0)
    obj("bunk_bed", 2, 1, T0, b)

    # --- промышленная электроплита 2×1
    T0 = 40
    b = shadow(12, T0 - 4, 120, 70)
    b += box(6, T0 - 14, 116, 34, 42, "#c9ccce", "#a9aeb2")
    for cx in (28, 60, 92):
        b += circ(cx, T0 + 3, 11, "#2a2e31", OUT, 1.4) + circ(cx, T0 + 3, 6, None, "#4a5156", 1.2)
    b += rect(108, T0 - 10, 10, 26, "#8b9296", OUT, 1.2, 2)
    b += circ(26, T0 + 1, 8, "#5a6268", OUT, 1.4) + rect(20, T0 - 9, 12, 4, "#8b9296", OUT, 1, 1)
    b += path(f"M22 {T0-12}q2 -8 0 -14M28 {T0-12}q2 -8 0 -14", None, "#ffffff", 1.6, 0.6)
    b += ell(62, T0 + 3, 12, 6, "#7a8086", OUT, 1.4) + path(f"M62 {T0-2}q-6 -8 0 -16", None, "#ffffff", 1.4, 0.5)
    for i, cx in enumerate((20, 40, 60, 80, 100)):
        b += circ(cx, T0 + 32, 3.2, "#3a3f43", OUT, 1) + line(cx, T0 + 32, cx + 2, T0 + 29, "#d0d5d8", 1)
    b += rect(14, T0 + 40, 100, 14, "#8b9296", OUT, 1.4, 2) + rect(54, T0 + 44, 20, 3, "#d0d5d8", None, 0, 1)
    obj("stove", 2, 1, T0, b)

    # --- линия раздачи 2×1
    T0 = 34
    b = shadow(12, T0 - 2, 120, 64)
    b += box(6, T0 - 6, 116, 26, 46, "#d0d5d8", "#b8bec2")
    for i, (x, c) in enumerate([(12, "#e0aa48"), (38, "#8fbf5a"), (64, "#d8644e"), (90, "#e8dcc0")]):
        b += rect(x, T0 - 3, 24, 18, "#9aa1a5", OUT, 1.2, 2) + rect(x + 2, T0 - 1, 20, 14, c, None, 0, 2)
        b += ell(x + 8, T0 + 3, 4, 2, "#ffffff", None, 0, 0.35)
    b += rect(6, T0 + 22, 116, 6, "#8b9296", OUT, 1.4) + rect(12, T0 + 32, 104, 4, "#7a8086", None, 0)
    b += path(f"M18 {T0-8}q2 -6 0 -10M70 {T0-8}q2 -6 0 -10", None, "#ffffff", 1.2, 0.5)
    obj("serving_line", 2, 1, T0, b)

    # --- медицинская кушетка 2×1
    T0 = 30
    b = shadow(12, T0 + 6, 118, 56)
    b += rect(12, T0 + 40, 5, 20, "#9aa1a5", OUT, 1.2) + rect(112, T0 + 40, 5, 20, "#9aa1a5", OUT, 1.2)
    b += rect(8, T0 + 6, 114, 36, "#e9ecea", OUT, 1.8, 6) + rect(8, T0 + 6, 30, 36, "#dfe5e8", OUT, 1.4, 6)
    b += rect(12, T0 + 10, 22, 10, "#ffffff", OUT, 1, 4)
    b += rect(40, T0 + 10, 78, 28, "#f6f7f5", None, 0, 4) + path(f"M44 {T0+24}h70", None, "#cdd3d6", 1, 0.8)
    b += rect(8, T0 + 38, 114, 6, "#7fa8c9", OUT, 1.2)
    obj("med_couch", 2, 1, T0, b)

    # --- шкаф с лекарствами 1×1
    T0 = 62
    b = shadow(14, T0 - 46, 48, 104)
    b += box(8, T0 - 56, 48, 8, 110, "#f2f3f0", "#e3e6e2")
    b += rect(12, T0 - 44, 40, 44, "#cfe0ea", OUT, 1.4, 1)
    for y in (T0 - 30, T0 - 16):
        b += line(12, y, 52, y, OUT, 1.2)
    for x, y, c in [(16, T0 - 40, "#d8644e"), (24, T0 - 38, "#7fb6d8"), (34, T0 - 41, "#f2f2ee"), (42, T0 - 37, "#8fcf78"),
                    (17, T0 - 26, "#e0aa48"), (28, T0 - 27, "#c98bb9"), (40, T0 - 25, "#f2f2ee"), (18, T0 - 12, "#7fb6d8"), (34, T0 - 11, "#d8644e")]:
        b += rect(x, y, 6, 9, c, OUT, 0.8, 1)
    b += line(32, T0 - 44, 32, T0, OUT, 1.2)
    b += rect(12, T0 + 6, 40, 40, "#e3e6e2", OUT, 1.4, 1) + rect(28, T0 + 22, 8, 3, "#9aa1a5", None, 0, 1)
    b += rect(26, T0 - 54, 12, 7, "#ffffff", OUT, 1) + rect(30.5, T0 - 53, 3, 5, "#d8302c", None, 0) + rect(28.5, T0 - 51, 7, 1.6, "#d8302c", None, 0)
    obj("med_cabinet", 1, 1, T0, b)

    # --- радиоузел 1×1: тумба с усилителем, микрофоном и пультом
    T0 = 36
    b = shadow(12, T0 - 6, 50, 70)
    b += box(6, T0 - 6, 52, 20, 46, "#7a5a3e", "#6a4c34")
    b += rect(10, T0 - 22, 44, 20, "#3a3f43", OUT, 1.6, 2) + rect(14, T0 - 18, 18, 10, "#9ec7a4", OUT, 1, 1)
    b += path(f"M16 {T0-12}l3 -3 3 3 3 -4 3 4 3 -2", None, "#2f6a3e", 1.2)
    for cx in (38, 46):
        b += circ(cx, T0 - 12, 3.4, "#c9ccce", OUT, 1) + line(cx, T0 - 12, cx + 2, T0 - 14, OUT, 0.8)
    b += line(50, T0 + 4, 48, T0 - 6, "#2a2e31", 1.6) + ell(48, T0 - 8, 3, 4, "#5a6268", OUT, 1)
    b += rect(12, T0 + 20, 40, 18, None, "#5a4030", 1.2) + rect(28, T0 + 26, 8, 3, "#c9a45a", None, 0, 1)
    b += circ(18, T0 + 2, 2.2, "#d8302c", None, 0)
    obj("radio_station", 1, 1, T0, b)

    # --- громкоговоритель под потолком (рупор)
    T0 = 30
    b = rect(28, 0, 8, 10, "#5a6268", OUT, 1.2)
    b += path("M24 10L40 10L46 26L18 26Z", "#c9ccce", OUT, 1.6)
    b += ell(32, 26, 15, 5, "#8b9296", OUT, 1.6) + ell(32, 26, 9, 3, "#2a2e31", None, 0)
    b += path("M20 30q-4 6 0 12M44 30q4 6 0 12", None, "#e0aa48", 1.4, 0.7)
    obj("loudspeaker", 1, 1, T0, b, pad=0)

    # --- миска для кота
    T0 = 4
    b = ell(32, T0 + 40, 14, 5, "#000", None, 0, 0.2)
    b += ell(26, T0 + 34, 9, 4.5, "#d8644e", OUT, 1.4) + ell(26, T0 + 33, 6, 2.6, "#8a5a3a", None, 0)
    b += ell(40, T0 + 38, 8, 4, "#7fb6d8", OUT, 1.4) + ell(40, T0 + 37, 5.5, 2.2, "#cfe6f4", None, 0)
    for dx, dy in [(-3, 0), (0, -1), (3, 0)]:
        b += circ(26 + dx, T0 + 33 + dy, 1.3, "#5a3a24", None, 0)
    obj("cat_bowl", 1, 1, T0, b, pad=0)

    # --- кот: тонируемая шерсть (fur) и детали (fx): глаза, нос, обводка, белые лапки
    LU = "#2b2421"

    def cat(pose, legs=0):
        fur = ""
        fx = ""
        if pose in ("walk", "walk2"):
            tail = "M10 21Q2 18 4 7Q5 4 8 6Q7 14 13 18Z"
            body = (22, 22, 13, 7.2)
            head = (36, 15, 6.6)
            ea = "M31 11L32 3L36 9ZM37 9L41 3L42 11Z"
            lg = [(13, 26), (18, 26), (27, 26), (32, 26)] if legs == 0 else [(11, 26), (20, 26), (25, 26), (34, 26)]
            fur += path(tail, "#d8d8d8", None, 0) + ell(*body, "#f0f0f0", None, 0) + ell(22, 25, 11, 3.5, "#d6d6d6", None, 0)
            fur += "".join(rect(x, y, 3.4, 7, "#e2e2e2", None, 0, 1.4) for x, y in lg)
            fur += circ(*head, "#f2f2f2", None, 0) + path(ea, "#e8e8e8", None, 0)
            fur += path("M16 17q3 -2 5 0M22 16q3 -2 5 0M28 17q2 -2 4 0", None, "#bdbdbd", 1.6)
            fx += path(tail, None, LU, 1.2) + ell(*body, None, LU, 1.3) + circ(*head, None, LU, 1.3) + path(ea, None, LU, 1.1)
            fx += "".join(rect(x, y + 4.6, 3.4, 2.6, "#fbfaf4", LU, 0.8, 1.2) for x, y in lg)
            fx += path("M33 11.5l1 1.5M39 11.5l-1 1.5", None, "#ffb0b0", 1, 0.8)
            fx += ell(39.5, 14.5, 1.3, 1.6, "#9ad46a", LU, 0.6) + ell(35, 14.5, 1.3, 1.6, "#9ad46a", LU, 0.6)
            fx += circ(42.2, 17.2, 1, "#e07a8a", None, 0) + path("M42.6 18.4l3 -0.4M42.6 19.2l3 0.6", None, LU, 0.5, 0.7)
        elif pose == "sit":
            fur += path("M14 34Q6 33 6 26Q6 22 9 23Q9 29 16 31Z", "#d8d8d8", None, 0)
            fur += path("M14 34Q11 22 18 17L28 17Q35 22 32 34Z", "#f0f0f0", None, 0)
            fur += circ(23, 13, 7, "#f2f2f2", None, 0) + path("M17.5 9L17 1L22 7ZM24 7L29 1L28.5 9Z", "#e8e8e8", None, 0)
            fur += path("M19 22q4 2 8 0M18 26q5 2 10 0", None, "#bdbdbd", 1.6)
            fx += path("M14 34Q6 33 6 26Q6 22 9 23Q9 29 16 31Z", None, LU, 1.1) + path("M14 34Q11 22 18 17L28 17Q35 22 32 34Z", None, LU, 1.3)
            fx += circ(23, 13, 7, None, LU, 1.3) + path("M17.5 9L17 1L22 7ZM24 7L29 1L28.5 9Z", None, LU, 1.1)
            fx += rect(17.5, 31, 4, 3.5, "#fbfaf4", LU, 0.8, 1.4) + rect(24.5, 31, 4, 3.5, "#fbfaf4", LU, 0.8, 1.4)
            fx += ell(20.2, 12.5, 1.4, 1.8, "#9ad46a", LU, 0.6) + ell(25.8, 12.5, 1.4, 1.8, "#9ad46a", LU, 0.6)
            fx += circ(23, 15.6, 1, "#e07a8a", None, 0) + path("M21 16.5l-4 -0.5M21 17.3l-4 0.8M25 16.5l4 -0.5M25 17.3l4 0.8", None, LU, 0.5, 0.7)
        else:  # sleep: свернулся клубком
            fur += ell(22, 26, 14, 8, "#f0f0f0", None, 0) + path("M9 28Q10 35 22 35Q32 35 35 30Q30 33 22 32Q13 32 9 28Z", "#d8d8d8", None, 0)
            fur += circ(31, 24, 6, "#f2f2f2", None, 0) + path("M28 19L30 14L33 19Z", "#e8e8e8", None, 0)
            fur += path("M14 23q4 -2 7 0M19 21q4 -2 7 0", None, "#bdbdbd", 1.6)
            fx += ell(22, 26, 14, 8, None, LU, 1.3) + path("M9 28Q10 35 22 35Q32 35 35 30", None, LU, 1.1)
            fx += circ(31, 24, 6, None, LU, 1.2) + path("M28 19L30 14L33 19Z", None, LU, 1)
            fx += path("M29 24q1.5 1 3 0M33 24.5q1 0.8 2 0", None, LU, 0.9)
        save(f"assets/fx/cat_{pose}_fur.svg", 48, 38, fur)
        save(f"assets/fx/cat_{pose}_fx.svg", 48, 38, fx)
    cat("walk", 0)
    cat("walk2", 1)
    cat("sit")
    cat("sleep")

    # --- иконки раздела «Город»
    C = "#e7e4d8"

    def icon(name, body):
        save(f"assets/ui/{name}.svg", 48, 48, body)
    icon("town", path("M4 42H44", None, C, 3) + rect(8, 22, 12, 20, None, C, 2.6) + rect(24, 12, 16, 30, None, C, 2.6)
         + path("M12 28h4M12 34h4M28 18h8M28 24h8M28 30h8M28 36h8", None, C, 2))
    icon("cat", path("M10 40Q8 24 16 20L14 8L22 15H26L34 8L32 20Q40 24 38 40Z", None, C, 2.8)
         + circ(19, 27, 1.8, "#e0aa48", None, 0) + circ(29, 27, 1.8, "#e0aa48", None, 0) + path("M22 33q2 2 4 0", None, C, 2))
    icon("radio", rect(6, 16, 36, 24, None, C, 2.8, 3) + circ(17, 28, 6, None, C, 2.4) + path("M28 24h9M28 30h9M28 36h6", None, C, 2.2)
         + path("M12 16L34 6", None, C, 2.4))
    icon("kid", circ(24, 13, 6, None, C, 2.8) + path("M12 42Q12 24 24 24Q36 24 36 42", None, C, 2.8) + path("M17 31L10 26M31 31L38 26", None, C, 2.4)
         + circ(38, 22, 3, "#e0aa48", None, 0))
    icon("culture", path("M6 18L24 6L42 18Z", None, C, 2.8) + path("M10 20V38M18 20V38M30 20V38M38 20V38", None, C, 2.6) + path("M4 42H44", None, C, 3)
         + circ(24, 14, 2.4, "#e0aa48", None, 0))
    icon("bed", rect(6, 26, 36, 10, None, C, 2.8, 2) + rect(9, 19, 11, 7, None, C, 2.2, 2) + path("M6 36V42M42 36V42M6 26V14", None, C, 2.8))
    icon("med", rect(8, 12, 32, 28, None, C, 2.8, 4) + path("M24 18V34M16 26H32", None, "#d8644e", 3.4) + path("M18 12V8H30V12", None, C, 2.4))



def utils_v115():
    """1.15: без городских сетей. Трансформатор ТМ-25 (1×1) и ТМ-63 (2×1) дают ток сами,
    скважинный насос (1×1) — воду. Рисуются поверх старых «щита» и «ввода водопровода»."""
    TANK_T, TANK_F, RIB = "#a9b2a4", "#8d978a", "#727c6f"
    BUSH, BUSH_D = "#9c5634", "#6e3a22"

    def bushing(x, y, n=3, r=5.0):
        o = rect(x - 2.2, y - n * 5 - 4, 4.4, n * 5 + 4, "#c9c9c2", OUT, 1.2)
        for k in range(n):
            o += ell(x, y - 3 - k * 5, r, 2.0, BUSH, OUT, 1.1)
        o += rect(x - 1.6, y - n * 5 - 9, 3.2, 6, "#d8d2b8", OUT, 1)
        return o

    def bolt_sign(x, y, sc=1.0):
        return (poly([(x, y), (x + 9 * sc, y + 16 * sc), (x - 9 * sc, y + 16 * sc)], "#e2b73a", OUT, 1.2)
                + path(f"M{x+0.5} {y+4*sc}l-2.6 {5*sc}h3.6l-2.6 {5*sc}", None, OUT, 1.3))

    # --- ТМ-25: малый масляный трансформатор на бетонной плите
    T0 = 40
    b = shadow(10, T0 + 4, 54, 62)
    b += box(4, T0 + 40, 56, 8, 16, "#b3aea4", "#97928a", 1.6)
    b += box(12, T0 - 4, 40, 10, 46, TANK_T, TANK_F)
    for k in range(7):
        b += rect(14.5 + k * 5.2, T0 + 9, 3.2, 34, RIB, OUT, 0.9, 1.4)
    b += rect(12, T0 + 6, 40, 3, "#ffffff", None, 0, 0, 0.18)
    for x in (21, 32, 43):
        b += bushing(x, T0 + 2, 3, 4.4)
    b += rect(40, T0 + 46, 10, 6, "#ece8dc", OUT, 0.8)
    b += bolt_sign(23, T0 + 16, 0.8)
    obj("cabinet", 1, 1, T0, b)

    # --- ТМ-63: трансформатор побольше, с расширителем и радиаторами
    T0 = 48
    b = shadow(12, T0 + 2, 116, 66)
    b += box(4, T0 + 40, 120, 8, 16, "#b3aea4", "#97928a", 1.6)
    # радиаторы по бокам
    for x0 in (8, 98):
        for k in range(4):
            b += rect(x0 + k * 5.4, T0 + 6, 4, 36, "#7f8a7c", OUT, 0.9, 1.5)
        b += rect(x0 - 1, T0 + 4, 24, 4, "#6c7669", OUT, 1) + rect(x0 - 1, T0 + 40, 24, 4, "#6c7669", OUT, 1)
    b += box(30, T0 - 6, 68, 10, 50, TANK_T, TANK_F)
    for k in range(10):
        b += line(34 + k * 6.6, T0 + 8, 34 + k * 6.6, T0 + 40, RIB, 1.4)
    b += rect(30, T0 + 4, 68, 3, "#ffffff", None, 0, 0, 0.18)
    # расширитель (бачок) на стойках
    b += rect(36, T0 - 24, 4, 20, "#7a8478", OUT, 1) + rect(88, T0 - 24, 4, 20, "#7a8478", OUT, 1)
    b += rect(32, T0 - 40, 64, 18, "#a3ac9e", OUT, 1.8, 9) + rect(36, T0 - 37, 56, 4, "#ffffff", None, 0, 2, 0.25)
    b += circ(92, T0 - 31, 3.4, "#f4f1e6", OUT, 1)
    for x in (46, 64, 82):
        b += bushing(x, T0, 4, 5.0)
    b += rect(70, T0 + 22, 18, 10, "#ece8dc", OUT, 1)
    for k in range(3):
        b += line(73, T0 + 25 + k * 2.6, 85, T0 + 25 + k * 2.6, "#7a7a72", 0.8)
    b += bolt_sign(46, T0 + 16, 0.9)
    obj("tr_63", 2, 1, T0, b)

    # --- скважинный насос: оголовок скважины, синий насос с мотором, задвижка, манометр
    T0 = 40
    b = shadow(10, T0 + 6, 52, 56)
    b += rect(8, T0 + 26, 48, 26, "#a8a39a", OUT, 1.8) + ell(32, T0 + 52, 24, 6, "#97928a", OUT, 1.8)
    b += rect(9, T0 + 27, 46, 24, "#a8a39a", None, 0)
    b += ell(32, T0 + 26, 24, 7, "#bdb8ae", OUT, 1.8) + ell(32, T0 + 26, 18, 4.5, "#6d6a64", OUT, 1.2)
    for k in range(5):
        b += line(12 + k * 10, T0 + 34 + (k % 2) * 4, 15 + k * 10, T0 + 36 + (k % 2) * 4, "#8c877e", 1)
    # мотор (рёбра) и улитка насоса
    b += rect(12, T0 + 2, 26, 18, "#3d6fb0", OUT, 1.8, 5)
    for k in range(4):
        b += line(17 + k * 5, T0 + 4, 17 + k * 5, T0 + 18, "#2c5288", 1.2)
    b += rect(14, T0 + 4, 22, 3, "#ffffff", None, 0, 1.5, 0.25)
    b += circ(44, T0 + 10, 10, "#4a7fb0", OUT, 1.8) + circ(44, T0 + 10, 3.4, "#2c5288", None, 0)
    b += rect(8, T0 + 18, 48, 5, "#6a737a", OUT, 1.4, 2)
    # напорная труба вверх и задвижка с маховиком
    b += rect(41, T0 - 18, 6, 20, "#4a7fb0", OUT, 1.4)
    b += circ(44, T0 - 20, 7, None, "#c94a3a", 2.4) + line(37, T0 - 20, 51, T0 - 20, "#c94a3a", 1.8) + line(44, T0 - 27, 44, T0 - 13, "#c94a3a", 1.8)
    b += circ(24, T0 - 6, 6, "#f4f1e6", OUT, 1.3) + line(24, T0 - 6, 27, T0 - 9, "#c9372c", 1.2) + line(24, T0, 24, T0 + 2, OUT, 1.6)
    obj("water_inlet", 1, 1, T0, b)
    # у трансформатора нет поворотов: старые боковые виды электрощита больше не нужны
    for k in ("cabinet_v", "cabinet_b"):
        META.pop(k, None)
        fp = os.path.join(ROOT, "assets/objects/%s.svg" % k)
        if os.path.exists(fp):
            os.remove(fp)


def toilet_v115():
    """1.15: понятная туалетная кабинка. Вид сверху: три перегородки, унитаз у глухой стенки,
    вход — открытая дверь и дуга её хода. Основной — вход снизу, «_v» — слева, «_b» — сверху."""
    T0 = 34
    PART, PART_T, FLOOR, TILE = "#8fa1ad", "#b4c3cc", "#e3e9ea", "#cdd6d8"
    WHITE, WATER = "#f4f6f6", "#bcd6e2"
    DOOR, DOOR_D = "#7d93a2", "#62798a"

    def floor():
        o = rect(4, T0 + 2, 56, 58, FLOOR, None, 0)
        for k in range(1, 4):
            o += line(4 + k * 14, T0 + 2, 4 + k * 14, T0 + 60, TILE, 1) + line(4, T0 + 2 + k * 14.5, 60, T0 + 2 + k * 14.5, TILE, 1)
        return o

    def back_face():
        # глухая задняя перегородка: видна её лицевая сторона
        o = rect(2, T0 - 26, 60, 30, PART, OUT, 2) + rect(2, T0 - 30, 60, 5, PART_T, OUT, 1.6)
        o += rect(5, T0 - 23, 54, 3, "#ffffff", None, 0, 0, 0.18)
        o += rect(8, T0 - 20, 9, 9, "#3d6fb0", OUT, 1) + circ(12.5, T0 - 17.5, 1.6, "#fff", None, 0) + rect(11, T0 - 15.5, 3, 4, "#fff", None, 0)
        return o

    def side(x):
        return rect(x, T0 - 30, 5, 92, PART_T, OUT, 1.6) + line(x + 2.5, T0 - 26, x + 2.5, T0 + 58, "#ffffff", 1, 0.3)

    def bottom_strip():
        return rect(2, T0 + 57, 60, 5, PART_T, OUT, 1.6)

    def top_strip_open():
        return rect(2, T0 - 2, 6, 5, PART_T, OUT, 1.4)

    # --- основной: вход снизу, человек сидит лицом вниз
    b = shadow(10, T0 - 22, 56, 88)
    b += floor() + back_face() + side(2) + side(57)
    b += rect(22, T0 + 1, 20, 9, WHITE, OUT, 1.6, 2)                            # бачок
    b += ell(32, T0 + 22, 10.5, 13, WHITE, OUT, 1.8) + ell(32, T0 + 23, 6, 8.5, WATER, OUT, 1)
    # дверь открыта внутрь, прижата к правой перегородке, дуга хода — вход снизу
    b += path(f"M55 {T0+20}A40 40 0 0 0 15 {T0+60}", None, DOOR_D, 1.3, 0.8, dash="3 3")
    b += rect(51, T0 + 20, 6, 40, DOOR, OUT, 1.6) + rect(51.5, T0 + 38, 2.4, 6, "#d8dcdd", OUT, 0.6)
    b += rect(18, T0 + 60, 28, 3, "#7a8a72", None, 0, 1, 0.5)                   # коврик у входа
    obj("toilet", 1, 1, T0, b)
    META["toilet"]["anchors"] = {"busy": [52, T0 - 18]}

    # --- «_v»: вход слева, унитаз у правой стенки
    b = shadow(10, T0 - 22, 56, 88)
    b += floor() + back_face() + side(57) + bottom_strip()
    b += rect(47, T0 + 14, 9, 22, WHITE, OUT, 1.6, 2)
    b += ell(34, T0 + 25, 13, 10, WHITE, OUT, 1.8) + ell(33, T0 + 25, 8.5, 6, WATER, OUT, 1)
    b += path(f"M44 {T0+58}A40 40 0 0 0 4 {T0+18}", None, DOOR_D, 1.3, 0.8, dash="3 3")
    b += rect(4, T0 + 53, 40, 6, DOOR, OUT, 1.6) + rect(22, T0 + 53.5, 6, 2.4, "#d8dcdd", OUT, 0.6)
    b += rect(1, T0 + 14, 3, 30, "#7a8a72", None, 0, 1, 0.5)
    obj("toilet_v", 1, 1, T0, b)
    META["toilet_v"]["anchors"] = {"busy": [52, T0 - 18]}

    # --- «_b»: вход сверху, унитаз у нижней стенки
    b = shadow(10, T0 - 6, 56, 72)
    b += floor() + side(2) + side(57) + bottom_strip()
    b += rect(22, T0 + 46, 20, 9, WHITE, OUT, 1.6, 2)
    b += ell(32, T0 + 34, 10.5, 13, WHITE, OUT, 1.8) + ell(32, T0 + 33, 6, 8.5, WATER, OUT, 1)
    b += path(f"M8 {T0+42}A40 40 0 0 1 48 {T0+2}", None, DOOR_D, 1.3, 0.8, dash="3 3")
    b += rect(7, T0 + 2, 6, 40, DOOR, OUT, 1.6) + rect(10, T0 + 16, 2.4, 6, "#d8dcdd", OUT, 0.6)
    b += rect(18, T0 - 1, 28, 3, "#7a8a72", None, 0, 1, 0.5)
    obj("toilet_b", 1, 1, T0, b)
    META["toilet_b"]["anchors"] = {"busy": [52, T0 + 52]}


def locker2_v115():
    """1.15: шкафчик на двоих — две узкие секции со своими дверцами и табличками."""
    T0 = 56
    BODY_T, BODY_F, SIDE = "#a9b8c2", "#8798a4", "#71828e"
    TINT = ("#8798a4", "#7f9c92")

    def front():
        b = shadow(10, T0 - 44, 56, 104)
        b += box(4, T0 - 50, 56, 9, 104, BODY_T, BODY_F)
        for i, x0 in enumerate((6, 33)):
            b += rect(x0, T0 - 39, 25, 98, TINT[i], OUT, 1.4, 1.5)
            for k in range(4):
                b += rect(x0 + 5, T0 - 34 + k * 4.6, 15, 2, "#5f6f7a", None, 0)
            b += line(x0, T0 + 10, x0 + 25, T0 + 10, SIDE, 1.2)
            b += rect(x0 + 19, T0 - 6, 3, 11, "#3a3f43", None, 0) + rect(x0 + 19, T0 + 22, 3, 11, "#3a3f43", None, 0)
            b += rect(x0 + 6, T0 + 40, 13, 7, "#ece8dc", OUT, 0.8)
            b += text_svg(x0 + 12.5, T0 + 46, str(i + 1), 6.5, "#3a3f43")
            b += rect(x0 + 2, T0 - 37, 2, 94, "#fff", None, 0, 0, 0.16)
        b += rect(4, T0 + 60, 56, 4, "#5f6f7a", OUT, 1)
        return b

    def side():
        b = shadow(14, T0 - 44, 50, 104)
        b += box(8, T0 - 50, 48, 9, 104, BODY_T, SIDE)
        b += rect(8, T0 - 41, 9, 101, BODY_F, OUT, 1.4) + line(8, T0 + 10, 17, T0 + 10, OUT, 1.2)
        for k in range(4):
            b += rect(10, T0 - 35 + k * 5, 5, 2, "#5f6f7a", None, 0)
        b += rect(3, T0 - 6, 6, 11, "#3a3f43", OUT, 0.8, 1) + rect(3, T0 + 22, 6, 11, "#3a3f43", OUT, 0.8, 1)
        b += rect(23, T0 - 32, 26, 42, None, "#61727e", 1.2, 3) + rect(23, T0 + 16, 26, 36, None, "#61727e", 1.2, 3)
        b += rect(8, T0 + 60, 48, 4, "#5f6f7a", OUT, 1)
        return b

    def back():
        b = shadow(10, T0 - 44, 56, 104)
        b += box(4, T0 - 50, 56, 9, 104, BODY_T, SIDE)
        b += line(32, T0 - 41, 32, T0 + 59, "#61727e", 1.2)
        b += bolts([(10, T0 - 36), (54, T0 - 36), (10, T0 + 52), (54, T0 + 52)], 1.6)
        b += rect(4, T0 + 60, 56, 4, "#5f6f7a", OUT, 1)
        return b

    obj("locker2", 1, 1, T0, front())
    obj("locker2_v", 1, 1, T0, side())
    obj("locker2_b", 1, 1, T0, back())


def props_v115():
    """1.15: понятный молоток строителя (вид сбоку: рукоять и стальной боёк с гвоздодёром)."""
    b = path("M14.2 30.5L15.4 11H19.6L20.8 30.5Q17.5 32 14.2 30.5Z", "#b07a40", OUT, 1.4)
    b += line(16.6, 13, 16, 29, "#d9a566", 1.2, 0.8)
    b += rect(14.6, 23, 5.8, 1.6, "#6e4422", None, 0) + rect(14.4, 26, 6.2, 1.6, "#6e4422", None, 0)
    # боёк: ударная часть справа, гвоздодёр — раздвоенный загнутый хвост слева
    b += path("M13 5H24.5V12.5H13Z", "#8d969c", OUT, 1.5)
    b += rect(24.5, 4, 4.5, 9.5, "#6f787e", OUT, 1.5, 1) + line(27.5, 5.5, 27.5, 12, "#b9c2c8", 0.9)
    b += path("M13 5Q8 5 3.5 1.5Q6 6.5 9 9.5Q8 11 3.5 12.5Q8.5 12.8 13 12.5Z", "#8d969c", OUT, 1.5)
    b += line(14, 6.5, 23.5, 6.5, "#ffffff", 1.1, 0.45)
    save("assets/people/prop_hammer.svg", 32, 32, b)


def ui_v117():
    """1.17: значки — план (калька с карандашом), шаблон помещения."""
    C = "#e7e4d8"
    body = rect(6, 8, 30, 34, None, C, 2.4, 2) + path("M12 16h18M12 22h18M12 28h10", None, C, 1.6, 0.7)
    body += path("M14 16v20M24 16v12", None, C, 1.6, 0.5)
    body += path("M30 40L42 18L46 20L34 42L29 44Z", None, C, 2.4) + line(39, 23, 43, 25, C, 2)
    save("assets/ui/plan.svg", 48, 48, body)
    t = rect(5, 7, 38, 32, None, C, 2.4, 2) + line(5, 22, 28, 22, C, 2.4) + line(28, 7, 28, 39, C, 2.4)
    t += path("M14 39v-5h6v5", None, C, 2) + rect(32, 12, 7, 6, None, C, 1.8) + rect(10, 11, 10, 6, None, C, 1.8, 1, 0.8)
    save("assets/ui/template.svg", 48, 48, t)


def nets_v118():
    """1.18: один трансформатор — подстанция 2×2 (к ней вплотную ставят аккумуляторы), насосная станция 2×2."""
    TANK_T, TANK_F, RIB = "#a9b2a4", "#8d978a", "#727c6f"
    BUSH = "#9c5634"

    def bushing(x, y, n=4, r=5.4):
        o = rect(x - 2.4, y - n * 5 - 4, 4.8, n * 5 + 4, "#c9c9c2", OUT, 1.2)
        for k in range(n):
            o += ell(x, y - 3 - k * 5, r, 2.2, BUSH, OUT, 1.1)
        o += rect(x - 1.8, y - n * 5 - 10, 3.6, 7, "#d8d2b8", OUT, 1)
        return o

    def bolt_sign(x, y, sc=1.0):
        return (poly([(x, y), (x + 9 * sc, y + 16 * sc), (x - 9 * sc, y + 16 * sc)], "#e2b73a", OUT, 1.2)
                + path(f"M{x+0.5} {y+4*sc}l-2.6 {5*sc}h3.6l-2.6 {5*sc}", None, OUT, 1.3))

    # --- подстанция: масляный трансформатор на плите, радиаторы, расширитель, вводы, шкаф учёта
    T0 = 70
    b = shadow(12, T0 + 4, 124, 128)
    b += box(4, T0 + 92, 136, 10, 30, "#b3aea4", "#97928a", 1.8)          # бетонная плита
    for k in range(9):
        b += line(10 + k * 15, T0 + 104, 14 + k * 15, T0 + 110, "#8c877e", 1)
    # радиаторы слева и справа
    for x0 in (8, 110):
        for k in range(5):
            b += rect(x0 + k * 5.2, T0 + 22, 4, 66, "#7f8a7c", OUT, 0.9, 1.5)
        b += rect(x0 - 1, T0 + 18, 28, 5, "#6c7669", OUT, 1) + rect(x0 - 1, T0 + 86, 28, 5, "#6c7669", OUT, 1)
    # бак
    b += box(34, T0 + 4, 76, 14, 84, TANK_T, TANK_F)
    for k in range(11):
        b += line(38 + k * 6.6, T0 + 22, 38 + k * 6.6, T0 + 86, RIB, 1.5)
    b += rect(34, T0 + 18, 76, 3, "#ffffff", None, 0, 0, 0.18)
    # расширитель на стойках
    b += rect(40, T0 - 20, 4, 26, "#7a8478", OUT, 1) + rect(100, T0 - 20, 4, 26, "#7a8478", OUT, 1)
    b += rect(36, T0 - 38, 72, 20, "#a3ac9e", OUT, 1.8, 10) + rect(40, T0 - 35, 64, 4, "#ffffff", None, 0, 2, 0.25)
    b += circ(102, T0 - 28, 3.6, "#f4f1e6", OUT, 1)
    # вводы высокого и низкого напряжения
    for x in (50, 72, 94):
        b += bushing(x, T0 + 10, 4, 5.4)
    for x in (58, 80):
        b += rect(x - 2, T0 + 2, 4, 9, "#c9c9c2", OUT, 1) + ell(x, T0 + 2, 3.4, 1.6, BUSH, OUT, 1)
    # табличка и знак
    b += rect(76, T0 + 46, 22, 12, "#ece8dc", OUT, 1)
    for k in range(3):
        b += line(79, T0 + 49 + k * 3, 95, T0 + 49 + k * 3, "#7a7a72", 0.8)
    b += bolt_sign(50, T0 + 42, 1.1)
    # индикатор нагрузки
    b += rect(110, T0 + 64, 26, 20, "#3d4652", OUT, 1.4, 2) + rect(113, T0 + 67, 20, 8, "#1d2a34", None, 0, 1)
    obj("substation", 2, 2, T0, b)
    META["substation"]["anchors"] = {"lamp": [123, T0 + 79], "screen": [123, T0 + 71]}

    # --- насосная станция: два насоса с моторами на раме, гидробак, коллектор, шкаф управления
    T0 = 54
    BLUE, BLUE_D = "#3d6fb0", "#2c5288"
    b = shadow(12, T0 + 6, 124, 122)
    b += box(4, T0 + 98, 136, 8, 22, "#b3aea4", "#97928a", 1.8)
    b += rect(10, T0 + 88, 124, 10, "#4f5a52", OUT, 1.6, 2)                 # рама
    # гидробак сзади
    b += rect(14, T0 - 6, 34, 60, BLUE, OUT, 1.8, 14) + rect(18, T0 - 2, 8, 50, "#ffffff", None, 0, 4, 0.18)
    b += ell(31, T0 - 4, 15, 5, "#5a8bc6", OUT, 1.4)
    b += circ(31, T0 + 18, 5, "#f4f1e6", OUT, 1.2) + line(31, T0 + 18, 34, T0 + 15, "#c9372c", 1.2)
    # коллектор
    b += rect(48, T0 + 8, 84, 8, "#6d7a84", OUT, 1.6, 3) + rect(50, T0 + 9, 80, 2, "#ffffff", None, 0, 1, 0.25)
    for x in (66, 104):
        b += rect(x - 3, T0 + 14, 6, 22, "#6d7a84", OUT, 1.4)
        b += circ(x, T0 + 20, 6, None, "#c94a3a", 2.2) + line(x - 6, T0 + 20, x + 6, T0 + 20, "#c94a3a", 1.6)
    # два насоса: улитка + мотор с рёбрами
    for x in (52, 90):
        b += circ(x + 14, T0 + 58, 14, BLUE, OUT, 1.8) + circ(x + 14, T0 + 58, 5, BLUE_D, None, 0)
        b += rect(x + 18, T0 + 46, 30, 26, BLUE, OUT, 1.8, 6) if x == 52 else rect(x + 18, T0 + 46, 30, 26, BLUE, OUT, 1.8, 6)
        for k in range(5):
            b += line(x + 23 + k * 5, T0 + 48, x + 23 + k * 5, T0 + 70, BLUE_D, 1.2)
        b += rect(x + 20, T0 + 48, 26, 3, "#ffffff", None, 0, 1.5, 0.22)
        b += rect(x + 8, T0 + 36, 12, 10, "#6d7a84", OUT, 1.2)
    # шкаф управления
    b += box(14, T0 + 58, 30, 8, 30, "#d9dcd2", "#bcc0b4", 1.6)
    b += rect(18, T0 + 70, 22, 8, "#1d2a34", OUT, 1, 1) + circ(22, T0 + 84, 2.4, "#6fbf86", OUT, 0.8) + circ(30, T0 + 84, 2.4, "#c94a3a", OUT, 0.8)
    obj("pump_house", 2, 2, T0, b)
    META["pump_house"]["anchors"] = {"lamp": [22, T0 + 84]}


def company_v117():
    """1.17: вывеска завода (эмблема и название рисуются в игре поверх таблички)."""
    T0 = 84
    b = ell(72, T0 + 58, 56, 6, "#000", None, 0, 0.22)
    for x in (26, 118):
        b += rect(x - 3, T0 - 20, 6, 76, "#5a6268", OUT, 1.4, 1) + rect(x - 6, T0 + 52, 12, 5, "#3a3f43", OUT, 1, 1)
    b += rect(4, T0 - 78, 136, 62, "#8a9399", OUT, 2, 4)
    b += rect(8, T0 - 74, 128, 54, "#1d2a38", "#5f6a72", 1.2, 3)
    b += rect(10, T0 - 72, 124, 6, "#ffffff", None, 0, 2, 0.07)
    for x in (12, 132):
        b += circ(x, T0 - 70, 1.6, "#c9ced2", None, 0) + circ(x, T0 - 24, 1.6, "#c9ced2", None, 0)
    obj("company_board", 2, 1, T0, b)
    META["company_board"]["anchors"] = {"plate": [10, T0 - 72, 124, 50]}


def flora_v115():
    """1.15: деревья и кусты заново — чёткий общий контур кроны из лопастей, объём градиентом
    по маске кроны, блики и прожилки листвы; у зимних — ветвистый скелет со снегом на ветках."""
    W, H = 96, 128
    BX, BY = 48, 120
    uid = [0]

    def nid(p):
        uid[0] += 1
        return f"{p}{uid[0]}"

    def lobes_for(cx, cy, rx, ry, seed, n_ring, n_in, rk=0.34):
        r2 = random.Random(seed)
        out = []
        base = (rx + ry) * 0.5 * rk
        for k in range(n_ring):
            a = math.pi * 2 * k / n_ring + r2.uniform(-0.18, 0.18)
            x = cx + math.cos(a) * rx * 0.74
            y = cy + math.sin(a) * ry * 0.74
            out.append((x, y, base * r2.uniform(0.82, 1.12)))
        for k in range(n_in):
            a = r2.random() * math.pi * 2
            d = r2.random() ** 0.7 * 0.45
            out.append((cx + math.cos(a) * rx * d, cy + math.sin(a) * ry * d, base * r2.uniform(1.0, 1.3)))
        return out

    def crown(lobes, pal, line_col, seed, leaf_marks=True):
        dark, mid, light, hi = pal
        r2 = random.Random(seed)
        cid, gid = nid("cr"), nid("cg")
        xs = [x for x, y, r in lobes]
        ys = [y for x, y, r in lobes]
        x0, x1 = min(x - r for x, y, r in lobes), max(x + r for x, y, r in lobes)
        y0, y1 = min(y - r for x, y, r in lobes), max(y + r for x, y, r in lobes)
        o = f'<defs><clipPath id="{cid}">' + "".join(f'<circle cx="{fmt(x)}" cy="{fmt(y)}" r="{fmt(r)}"/>' for x, y, r in lobes) + "</clipPath>"
        o += (f'<linearGradient id="{gid}" x1="0.15" y1="0.05" x2="0.85" y2="0.95">'
              f'<stop offset="0" stop-color="{light}"/><stop offset="0.5" stop-color="{mid}"/><stop offset="1" stop-color="{dark}"/></linearGradient></defs>')
        # общий контур: лопасти чуть крупнее, тёмные
        for x, y, r in lobes:
            o += circ(x, y, r + 1.9, line_col, None, 0)
        o += f'<g clip-path="url(#{cid})">'
        o += f'<rect x="{fmt(x0)}" y="{fmt(y0)}" width="{fmt(x1 - x0)}" height="{fmt(y1 - y0)}" fill="url(#{gid})"/>'
        # тень снизу-справа у каждой лопасти и объём «шапок»
        for x, y, r in lobes:
            o += circ(x + r * 0.28, y + r * 0.34, r * 0.9, dark, None, 0, 0.45)
        for x, y, r in sorted(lobes, key=lambda t: t[1]):
            o += circ(x - r * 0.12, y - r * 0.16, r * 0.78, mid, None, 0, 0.55)
        for x, y, r in lobes:
            if (x - (x0 + x1) / 2) + (y - (y0 + y1) / 2) < (x1 - x0) * 0.05:
                rr = r * 0.62
                a0, a1 = math.radians(195), math.radians(265)
                o += path(f"M{fmt(x + math.cos(a0) * rr)} {fmt(y + math.sin(a0) * rr)}A{fmt(rr)} {fmt(rr)} 0 0 1 {fmt(x + math.cos(a1) * rr)} {fmt(y + math.sin(a1) * rr)}",
                          None, hi, max(1.4, r * 0.2), 0.75)
        if leaf_marks:
            for k in range(int(len(lobes) * 0.9)):
                x, y, r = r2.choice(lobes)
                a = r2.uniform(0, math.pi * 2)
                px, py = x + math.cos(a) * r * 0.5, y + math.sin(a) * r * 0.5
                o += path(f"M{fmt(px - 2.6)} {fmt(py)}q2.6 -3 5.2 0", None, dark, 1.1, 0.55)
        o += "</g>"
        return o

    def trunk(h, col, w=7, birch=False, seed=0):
        r2 = random.Random(seed)
        top = BY - h
        o = path(f"M{BX - w / 2 - 3.5} {BY}Q{BX - w / 2} {BY - 3} {BX - w / 2 + 0.6} {BY - 10}L{BX - w / 2 + 1.6} {top}"
                 f"H{BX + w / 2 - 1.6}L{BX + w / 2 - 0.6} {BY - 10}Q{BX + w / 2} {BY - 3} {BX + w / 2 + 3.5} {BY}Z", col, OUT, 1.7)
        if birch:
            for k in range(7):
                y = BY - 5 - k * (h / 7.2)
                x = BX - w / 2 + 0.6 + r2.uniform(0, 2.5)
                o += rect(x, y, 2.6 + r2.uniform(0, 2.2), 1.5, "#2a2c2e", None, 0, 0.6)
            o += line(BX + w / 2 - 2, BY - 6, BX + w / 2 - 2, top + 3, "#b9b3a2", 1.3)
        else:
            o += line(BX + w / 2 - 2.2, BY - 6, BX + w / 2 - 2.2, top + 3, "#000000", 1.4, 0.22)
            for k in range(3):
                y = BY - 8 - k * h / 3.4
                o += path(f"M{BX - 1.5} {y}q1 -3 0 -6", None, "#000000", 0.9, 0.3)
        return o

    def limbs(cx, top_y, n, spread, col, seed, w=2.4):
        r2 = random.Random(seed)
        o = ""
        for k in range(n):
            y0 = top_y + r2.uniform(0, 10)
            ang = -math.pi / 2 + (k - (n - 1) / 2) * 0.55 + r2.uniform(-0.15, 0.15)
            l = spread * r2.uniform(0.6, 1.0)
            o += line(cx, y0, cx + math.cos(ang) * l, y0 + math.sin(ang) * l, col, w)
        return o

    def bare(cx, y0, length, ang, depth, col, w, r2, snow):
        if depth == 0 or length < 3:
            return ""
        x1 = cx + math.cos(ang) * length
        y1 = y0 + math.sin(ang) * length
        lim = bounds[0]
        k_fit = 1.0
        if x1 < lim[0]:
            k_fit = min(k_fit, (cx - lim[0]) / max(0.01, cx - x1))
        if x1 > lim[2]:
            k_fit = min(k_fit, (lim[2] - cx) / max(0.01, x1 - cx))
        if y1 < lim[1]:
            k_fit = min(k_fit, (y0 - lim[1]) / max(0.01, y0 - y1))
        if k_fit < 1.0:
            length *= max(0.0, k_fit)
            x1 = cx + math.cos(ang) * length
            y1 = y0 + math.sin(ang) * length
        o = line(cx, y0, x1, y1, col, w)
        if snow and depth in (2, 3) and -2.5 < ang < -0.65 and r2.random() < 0.55:
            o += line(cx + (x1 - cx) * 0.3, y0 + (y1 - y0) * 0.3 - w * 0.5, cx + (x1 - cx) * 0.75, y0 + (y1 - y0) * 0.75 - w * 0.5, "#f6f8fa", w * 0.55 + 0.5)
        for s_ in (-1, 1):
            o += bare(x1, y1, length * r2.uniform(0.62, 0.76), ang + s_ * r2.uniform(0.32, 0.6), depth - 1, col, max(0.8, w * 0.68), r2, snow)
        return o

    bounds = [(5, 5, 91)]

    def ground_shadow(rx=28):
        return ell(BX + 9, BY - 1, rx, 6.5, "#000", None, 0, 0.22)

    PAL = {
        "poplar": {"summer": ("#2f5a2a", "#47803a", "#6fa553", "#a6cf78"), "autumn": ("#7e6018", "#b48c28", "#d9b444", "#f2dc84")},
        "birch": {"summer": ("#4a7631", "#64983f", "#88bc58", "#c0e08a"), "autumn": ("#93761e", "#c9a232", "#e7c654", "#f8e8a0")},
        "maple": {"summer": ("#2c5627", "#437a35", "#62a049", "#9ccb6c"), "autumn": ("#7e2a18", "#b84622", "#de7230", "#f4ac5a")},
    }
    LINE = {"summer": "#1e2b19", "autumn": "#3b2314"}
    trunk_col = {"poplar": "#7a6e60", "birch": "#ece8dd", "maple": "#6e5a48"}
    for name in ("poplar", "birch", "maple"):
        seed = sum(map(ord, name))
        if name == "poplar":
            h, tw = 34, 7
            lobes = lobes_for(BX, 52, 21, 42, seed, 12, 6, 0.4)
        elif name == "birch":
            h, tw = 44, 6.5
            lobes = []
            for (cx, cy, rx, ry, sd) in ((BX - 12, 44, 15, 16, 1), (BX + 13, 50, 14, 15, 2), (BX, 30, 15, 14, 3), (BX - 2, 64, 17, 11, 4)):
                lobes += lobes_for(cx, cy, rx, ry, seed + sd, 7, 2, 0.42)
        else:
            h, tw = 30, 9
            lobes = lobes_for(BX, 56, 36, 31, seed, 13, 7, 0.36)
        for sea in ("summer", "autumn"):
            b = ground_shadow(30 if name == "maple" else 24)
            b += trunk(h + 14, trunk_col[name], tw, name == "birch", seed)
            b += limbs(BX, BY - h - 12, 3, 14, trunk_col[name] if name != "birch" else "#5e584c", seed)
            b += crown(lobes, PAL[name][sea], LINE[sea], seed + (0 if sea == "summer" else 9))
            if sea == "autumn":
                r3 = random.Random(7 + seed)
                for k in range(7):
                    x, y = BX + r3.uniform(-28, 32), BY - r3.uniform(-1, 4)
                    b += ell(x, y, 2.2, 1.2, PAL[name][sea][2], OUT, 0.6)
            save(f"assets/objects/tree_{name}_{sea}.svg", W, H, b)
        # зима: ветвистый скелет, снег на ветках и у ствола
        r4 = random.Random(seed)
        b = ground_shadow(20) + trunk(h + 14, trunk_col[name], tw, name == "birch", seed)
        bc = trunk_col[name] if name != "birch" else "#6a6458"
        top = BY - h - 14
        if name == "poplar":
            for k, a in enumerate((-1.75, -1.5, -1.36, -1.64)):
                b += bare(BX + (k - 1.5) * 1.2, top + k * 6, 26 - k * 3, a, 4, bc, 2.6, r4, True)
        elif name == "birch":
            for a in (-2.2, -1.85, -1.3, -0.95):
                b += bare(BX, top + 4, 19, a, 4, bc, 2.2, r4, True)
            for k in range(6):
                x0 = BX + r4.uniform(-30, 30)
                b += path(f"M{fmt(x0)} {fmt(30 + r4.uniform(0, 20))}q-2 10 1 20", None, bc, 0.8, 0.7)
        else:
            for a in (-2.45, -2.0, -1.57, -1.14, -0.7):
                b += bare(BX, top + 2, 20, a, 4, bc, 2.8, r4, True)
        b += ell(BX, BY - 1.5, 21, 4.2, "#f4f6f8", OUT, 0.8)
        save(f"assets/objects/tree_{name}_winter.svg", W, H, b)

    # кусты 64×64, основание (32, 58)
    BPAL = {"lilac": {"summer": ("#365f30", "#4c7f40", "#6c9e55", "#a3cd7a"), "autumn": ("#566428", "#748636", "#94a54e", "#c6d084"), "dots": "#a77ad0", "dots2": "#d2b4ee"},
            "rose": {"summer": ("#365f2b", "#4f823c", "#6e9e50", "#a3cb74"), "autumn": ("#7e4420", "#b0602a", "#d68a3c", "#f0b86a"), "dots": "#c8302a", "dots2": "#ff8a7a"}}
    for name, d in BPAL.items():
        seed = len(name) * 31
        lobes = lobes_for(32, 42, 22, 13, seed, 9, 3, 0.55)
        for sea in ("summer", "autumn"):
            b = ell(37, 57, 26, 5.5, "#000", None, 0, 0.22)
            b += crown(lobes, d[sea], LINE[sea], seed + len(sea), False)
            r3 = random.Random(seed)
            if name == "lilac" and sea == "summer" or name == "rose":
                for k in range(10):
                    x, y, r = r3.choice(lobes)
                    px, py = x + r3.uniform(-r * 0.5, r * 0.5), y + r3.uniform(-r * 0.6, r * 0.2)
                    if name == "lilac":
                        for (dx, dy, rr) in ((0, -2.6, 1.3), (-1.3, -0.6, 1.5), (1.3, -0.6, 1.5), (0, 1.2, 1.7)):
                            b += circ(px + dx, py + dy, rr + 0.5, "#4a2e66", None, 0)
                        for (dx, dy, rr) in ((0, -2.6, 1.3), (-1.3, -0.6, 1.5), (1.3, -0.6, 1.5), (0, 1.2, 1.7)):
                            b += circ(px + dx, py + dy, rr, d["dots"], None, 0)
                        b += circ(px - 0.5, py - 2.8, 0.6, d["dots2"], None, 0)
                    else:
                        b += circ(px, py, 2.0, d["dots"], OUT, 0.7) + circ(px - 0.5, py - 0.6, 0.7, d["dots2"], None, 0)
            save(f"assets/objects/bush_{name}_{sea}.svg", 64, 64, b)
        r5 = random.Random(3 + seed)
        b = ell(37, 57, 22, 5, "#000", None, 0, 0.18)
        for k in range(7):
            a = -math.pi / 2 + (k - 3) * 0.32 + r5.uniform(-0.1, 0.1)
            b += bare(32 + (k - 3) * 1.5, 56, r5.uniform(9, 13), a, 3, "#5a4a3a", 1.6, r5, True)
        if name == "rose":
            for k in range(6):
                b += circ(32 + r5.uniform(-14, 14), 40 + r5.uniform(-8, 8), 1.8, d["dots"], OUT, 0.6)
        b += ell(32, 55, 19, 4, "#f4f6f8", OUT, 0.8)
        save(f"assets/objects/bush_{name}_winter.svg", 64, 64, b)


def cat_v122():
    """1.22: кот заново — крупнее и выразительнее: выгнутая спина, хвост трубой, полоски, ушки с розовым,
    миндалевидные глаза. Позы: идёт (2 кадра), сидит, спит клубком, прыжок. fur — тонируется, fx — детали."""
    LU = "#2b2421"
    STR = "#000000"

    def save2(pose, fur, fx):
        save(f"assets/fx/cat_{pose}_fur.svg", 64, 48, fur)
        save(f"assets/fx/cat_{pose}_fx.svg", 64, 48, fx)

    def head(cx, cy, r=7.6, look=1, ears_flat=False):
        fur = ""
        fx = ""
        if ears_flat:
            ea = f"M{cx-6} {cy-3}L{cx-9} {cy-7}L{cx-2} {cy-6}ZM{cx+3} {cy-6}L{cx+10} {cy-7}L{cx+6} {cy-2}Z"
        else:
            ea = f"M{cx-6.5} {cy-3}L{cx-5.5} {cy-12}L{cx-0.5} {cy-6.5}ZM{cx+1.5} {cy-6.5}L{cx+6.5} {cy-12}L{cx+7} {cy-3}Z"
        fur += path(ea, "#e6e6e6", None, 0) + circ(cx, cy, r, "#f4f4f4", None, 0)
        fur += ell(cx + look * 4.2, cy + 2.6, 4.6, 3.4, "#fafafa", None, 0)
        fx += path(ea, None, LU, 1.1) + circ(cx, cy, r, None, LU, 1.3)
        if not ears_flat:
            fx += path(f"M{cx-5} {cy-4.5}L{cx-4.6} {cy-9.5}L{cx-2} {cy-6}ZM{cx+3} {cy-6}L{cx+5.6} {cy-9.5}L{cx+5.6} {cy-4.5}Z", "#f2a5a8", None, 0, 0.9)
        # полоски на лбу
        fx += path(f"M{cx-2} {cy-7}l0.6 3M{cx} {cy-7.4}l0 3.2M{cx+2} {cy-7}l-0.6 3", None, STR, 1.1, 0.28)
        return fur, fx

    def eyes_side(cx, cy, look=1):
        x = cx + look * 3.6
        return (path(f"M{x-1.8} {cy}Q{x} {cy-2.2} {x+1.8} {cy}Q{x} {cy+1.6} {x-1.8} {cy}Z", "#a6d860", LU, 0.7)
                + rect(x - 0.35, cy - 1.4, 0.7, 2.8, "#1a1410", None, 0) + circ(x + 0.6, cy - 0.5, 0.45, "#fff", None, 0))

    def muzzle_side(cx, cy, look=1):
        x = cx + look * 7.2
        return (path(f"M{x-1.2} {cy+2}l1.4 -0.4l-0.4 1.4Z", "#e07a8a", LU, 0.4)
                + path(f"M{x-1} {cy+3.4}q-1.2 1.2 -2.4 0.4", None, LU, 0.7)
                + path(f"M{x-2} {cy+2.6}l6 -1.2M{x-2} {cy+3.2}l6 0.6M{x-2.2} {cy+3.8}l5 2", None, LU, 0.45, 0.6))

    # --- идёт: два кадра
    for pose, ph in (("walk", 0), ("walk2", 1)):
        fur = ""
        fx = ""
        tail = "M14 25Q6 22 7 12Q8 6 11 8Q11 16 17 21Z" if ph == 0 else "M14 25Q5 24 5 14Q6 7 9 8Q10 17 17 21Z"
        bodyd = "M13 28Q12 20 20 18Q30 15 40 18Q47 20 46 27Q45 33 38 33H20Q13 33 13 28Z"
        legs = [(16, 30), (22, 30), (35, 30), (41, 30)] if ph == 0 else [(14, 30), (24, 30), (33, 30), (43, 30)]
        fur += path(tail, "#dadada", None, 0) + path(bodyd, "#f0f0f0", None, 0)
        fur += path("M18 31Q29 35 42 31L41 33H19Z", "#d4d4d4", None, 0)
        fur += "".join(rect(x, y, 3.8, 8.5, "#e4e4e4", None, 0, 1.6) for x, y in legs)
        hf, hx = head(48, 18)
        fur += hf
        fx += path(tail, None, LU, 1.2) + path(bodyd, None, LU, 1.3)
        fx += "".join(rect(x, y + 5.8, 3.8, 2.7, "#fbfaf4", LU, 0.8, 1.3) for x, y in legs)
        fx += path("M22 18.5q2 4 0 8M28 17q2 4.5 0 9M34 17.5q2 4 0 8.5M40 19q1.6 3.5 0 7", None, STR, 1.6, 0.22)
        fx += path("M8.5 11q2.5 1 3.6 -0.6M8 15q2.8 0.8 4 -0.8" if ph == 0 else "M6.5 12q2.5 1 3.6 -0.6M6.5 16q2.8 0.8 4 -0.8", None, STR, 1.3, 0.22)
        fx += hx + eyes_side(48, 17.5) + muzzle_side(48, 17.5)
        save2(pose, fur, fx)

    # --- сидит (вид спереди): груша, хвост обвивает лапы
    fur = path("M20 44Q8 44 9 36Q10 31 14 33Q13 40 22 41Z", "#dadada", None, 0)
    fur += path("M20 44Q16 30 24 24H40Q48 30 44 44Z", "#f0f0f0", None, 0) + ell(32, 36, 7, 7.5, "#fafafa", None, 0)
    hf, hx = head(32, 17, 8.4, 0)
    fur += hf
    fx = path("M20 44Q8 44 9 36Q10 31 14 33Q13 40 22 41Z", None, LU, 1.1) + path("M20 44Q16 30 24 24H40Q48 30 44 44Z", None, LU, 1.3)
    fx += path("M10.5 37.5q2 -1.6 3.6 -0.2M13 41q1.6 -1.6 3.4 -0.4", None, STR, 1.3, 0.22)
    fx += path("M22 30q3 1 2 5M42 30q-3 1 -2 5", None, STR, 1.5, 0.22)
    fx += rect(25, 40.5, 5, 4, "#fbfaf4", LU, 0.8, 1.6) + rect(34, 40.5, 5, 4, "#fbfaf4", LU, 0.8, 1.6)
    fx += hx
    for ex in (28.6, 35.4):
        fx += path(f"M{ex-2} 16.5Q{ex} 14.2 {ex+2} 16.5Q{ex} 18.4 {ex-2} 16.5Z", "#a6d860", LU, 0.7) + rect(ex - 0.35, 15, 0.7, 3, "#1a1410", None, 0) + circ(ex + 0.7, 15.8, 0.45, "#fff", None, 0)
    fx += path("M30.8 19.6h2.4l-1.2 1.4Z", "#e07a8a", LU, 0.4) + path("M32 21v0.8M32 21.8q-1.4 1 -2.4 0.2M32 21.8q1.4 1 2.4 0.2", None, LU, 0.7)
    fx += path("M29 20.6l-6 -1M29 21.4l-6 0.8M35 20.6l6 -1M35 21.4l6 0.8", None, LU, 0.45, 0.6)
    save2("sit", fur, fx)

    # --- спит клубком
    fur = ell(31, 35, 18, 9.5, "#f0f0f0", None, 0) + path("M13 37Q14 45 30 45Q44 45 48 39Q42 43 30 42Q18 42 13 37Z", "#d6d6d6", None, 0)
    fur += circ(43, 32, 7, "#f4f4f4", None, 0) + path("M39 27L41 21L45 26.5ZM45.5 26.5L49.5 22L49 29Z", "#e6e6e6", None, 0)
    fx = ell(31, 35, 18, 9.5, None, LU, 1.3) + path("M13 37Q14 45 30 45Q44 45 48 39", None, LU, 1.1)
    fx += circ(43, 32, 7, None, LU, 1.2) + path("M39 27L41 21L45 26.5ZM45.5 26.5L49.5 22L49 29Z", None, LU, 1)
    fx += path("M18 30q3 -3 6 0M24 28q3 -3 6 0M30 27.5q3 -3 6 0", None, STR, 1.5, 0.22)
    fx += path("M40 32q1.6 1.1 3.2 0M45 32.6q1.2 0.8 2.2 0", None, LU, 0.9)
    fx += path("M50 22q2 -3 4 -1q-2 0 -2 2M53 18q1.6 -2 3 -0.6", None, "#7a8aa8", 0.9, 0.7)
    save2("sleep", fur, fx)

    # --- прыжок: низко припал, зад приподнят, лапы вперёд, хвост назад, уши прижаты
    fur = path("M10 22Q4 20 2 16Q6 18 12 19Z", "#dadada", None, 0)
    bodyd = "M10 22Q14 16 24 18Q36 21 44 26Q47 30 42 33H22Q12 32 10 22Z"
    fur += path(bodyd, "#f0f0f0", None, 0)
    fur += rect(14, 26, 4, 9, "#e4e4e4", None, 0, 1.6) + rect(20, 27, 4, 8, "#e4e4e4", None, 0, 1.6)
    fur += path("M40 31L54 34L54 37L40 35Z", "#e4e4e4", None, 0)
    hf, hx = head(50, 28, 7.2, 1, True)
    fur += hf
    fx = path("M10 22Q4 20 2 16Q6 18 12 19Z", None, LU, 1.1) + path(bodyd, None, LU, 1.3)
    fx += rect(14, 32, 4, 3, "#fbfaf4", LU, 0.8, 1.3) + rect(20, 32, 4, 3, "#fbfaf4", LU, 0.8, 1.3) + rect(52, 33.6, 3.6, 3.4, "#fbfaf4", LU, 0.8, 1.3)
    fx += path("M20 19q2 4 0 8M27 19.5q2 4 0 8M34 22q1.8 3.5 0 7", None, STR, 1.6, 0.22)
    fx += hx + eyes_side(50, 27.4) + muzzle_side(50, 27.4)
    save2("pounce", fur, fx)


def icons_v121():
    """1.21: значки окна, двери, металлической двери и ворот — вид спереди, сразу отличимые."""
    WALL = "#a65a44"
    def wall_bg():
        b = rect(2, 2, 60, 60, WALL, OUT, 2, 4)
        for y in range(8, 62, 8):
            b += line(3, y, 61, y, "#8a4a38", 1)
        for r_ in range(7):
            off = 0 if r_ % 2 == 0 else 6
            for x in range(4 + off, 60, 12):
                b += line(x, 2 + r_ * 8 + 1, x, 2 + r_ * 8 + 7, "#8a4a38", 1)
        return b
    # окно: рама, переплёт, стекло с бликом, подоконник
    b = wall_bg()
    b += rect(12, 10, 40, 38, "#e8e4da", OUT, 2, 1)
    b += rect(16, 14, 32, 30, "#8fc0dc", OUT, 1.5)
    b += line(32, 14, 32, 44, "#e8e4da", 3) + line(16, 26, 48, 26, "#e8e4da", 3)
    b += path("M19 40L27 17", None, "#ffffff", 2.4, op=0.7) + path("M36 40L42 30", None, "#ffffff", 2, op=0.6)
    b += rect(9, 48, 46, 5, "#d6d2c6", OUT, 1.5)
    save("assets/tiles/icon_window.svg", 64, 64, b)
    # деревянная дверь: филёнки, ручка, наличник
    b = wall_bg()
    b += rect(16, 6, 32, 56, "#efe9dc", OUT, 2)
    b += rect(19, 9, 26, 53, "#b07a45", OUT, 1.8)
    b += rect(23, 13, 18, 18, "#9c6a3a", "#7d522b", 1.4, 1) + rect(23, 36, 18, 21, "#9c6a3a", "#7d522b", 1.4, 1)
    b += rect(21, 10, 3, 51, "#ffffff", None, 0, 0, 0.18)
    b += circ(40, 35, 2.6, "#e2b73a", OUT, 1) + rect(37, 34, 6, 2.2, "#e2b73a", OUT, 0.8)
    save("assets/tiles/icon_door.svg", 64, 64, b)
    # металлическая дверь: серая сталь, рёбра, заклёпки, нажимная ручка, табличка
    b = wall_bg()
    b += rect(16, 6, 32, 56, "#5d6469", OUT, 2)
    b += rect(19, 9, 26, 53, "#8e979d", OUT, 1.8)
    for y in (16, 30, 44, 56):
        b += line(21, y, 43, y, "#6f777c", 1.6)
    for (x, y) in ((22, 12), (42, 12), (22, 58), (42, 58)):
        b += circ(x, y, 1.3, "#c9ced1", OUT, 0.6)
    b += rect(36, 33, 9, 3, "#2e3336", OUT, 1, 1) + circ(37, 34.5, 2, "#2e3336", OUT, 0.8)
    b += rect(25, 19, 14, 8, "#e9d24a", OUT, 1) + path("M32 20l-2 3h3l-2 3", None, OUT, 1)
    b += rect(21, 10, 3, 51, "#ffffff", None, 0, 0, 0.2)
    save("assets/tiles/icon_door_metal.svg", 64, 64, b)
    # ворота: секционные, полосы, жёлто-чёрные столбы
    b = wall_bg()
    b += rect(6, 8, 52, 54, "#3a3f43", OUT, 2)
    for k in range(6):
        y = 11 + k * 8.4
        b += rect(9, y, 46, 7.4, "#b3b8bb", OUT, 1, 1) + line(10, y + 3.7, 54, y + 3.7, "#8f9597", 0.9)
    for x in (3, 58):
        for k in range(7):
            b += rect(x, 8 + k * 8, 4, 8, "#e2b73a" if k % 2 == 0 else "#2a2a2a", None, 0)
    b += rect(28, 54, 8, 3, "#2e3336", OUT, 0.8)
    save("assets/tiles/icon_gate.svg", 64, 64, b)
    # остеклённая дверь: алюминиевая рама, стекло с бликом
    b = wall_bg()
    b += rect(16, 6, 32, 56, "#e9ebec", OUT, 2)
    b += rect(19, 9, 26, 53, "#aab3b9", OUT, 1.8)
    b += rect(22, 12, 20, 44, "#8fc0dc", OUT, 1.2) + line(22, 36, 42, 36, "#aab3b9", 2.4)
    b += path("M25 30L31 14", None, "#ffffff", 2.2, op=0.7) + path("M33 52L38 42", None, "#ffffff", 1.8, op=0.6)
    b += rect(38, 33, 3, 7, "#5d6469", OUT, 0.8, 1)
    save("assets/tiles/icon_door_glass.svg", 64, 64, b)
    b = wall_bg()
    b += rect(6, 8, 52, 54, "#2a3c52", OUT, 2)
    for k in range(6):
        y = 11 + k * 8.4
        b += rect(9, y, 46, 7.4, "#4f78a8", OUT, 1, 1) + line(10, y + 3.7, 54, y + 3.7, "#3d618c", 0.9)
    for x in (3, 58):
        for k in range(7):
            b += rect(x, 8 + k * 8, 4, 8, "#e2b73a" if k % 2 == 0 else "#2a2a2a", None, 0)
    save("assets/tiles/icon_gate_warm.svg", 64, 64, b)
    # стены: силикатный кирпич и газобетон — кусок кладки
    def masonry(cols, mortar, bw, bh):
        o = rect(2, 2, 60, 60, mortar, OUT, 2, 4)
        rr = random.Random(bw * 7 + bh)
        for row in range(int(60 // bh)):
            off = (bw / 2) if row % 2 else 0
            x = 2 - off
            while x < 62:
                x0 = max(2.0, x)
                x1 = min(62.0, x + bw)
                o += rect(x0 + 0.8, 2 + row * bh + 0.8, x1 - x0 - 1.6, bh - 1.6, rr.choice(cols), None, 0, 1)
                x += bw
        return o
    save("assets/tiles/icon_wall_silicate.svg", 64, 64, masonry(["#e4e0d6", "#dcd8cc", "#ebe7de"], "#a9a396", 16, 8))
    save("assets/tiles/icon_wall_gasblock.svg", 64, 64, masonry(["#d2d0ca", "#c9c7c0", "#d8d6d0"], "#9c9a93", 30, 15))


def objects_v120():
    """1.20: электрокотёл отопления 1×1 — ставится рядом с насосной, греет воду для батарей."""
    T0 = 40
    b = shadow(10, T0 + 6, 50, 52)
    # подставка
    b += rect(12, T0 + 50, 40, 8, "#4f5a52", OUT, 1.4, 2)
    # корпус: белый эмалированный шкаф
    b += rect(12, T0 - 22, 40, 74, "#e6e3da", OUT, 1.8, 6)
    b += rect(15, T0 - 19, 8, 66, "#ffffff", None, 0, 3, 0.35)
    b += rect(12, T0 - 22, 40, 10, "#c9372c", OUT, 1.4, 5)              # красная крышка — «горячо»
    # табло и ручка регулятора
    b += rect(19, T0 - 6, 26, 10, "#1d2a34", OUT, 1, 1.5) + rect(22, T0 - 4, 10, 6, "#e2b73a", None, 0, 1, 0.85)
    b += circ(32, T0 + 16, 7, "#c9ccce", OUT, 1.4) + line(32, T0 + 16, 36, T0 + 11, OUT, 1.6)
    for k in range(5):
        a = -2.4 + k * 0.6
        import math
        b += line(32 + 9.5 * math.cos(a), T0 + 16 + 9.5 * math.sin(a), 32 + 11.5 * math.cos(a), T0 + 16 + 11.5 * math.sin(a), "#7a7a72", 1)
    b += circ(20, T0 + 34, 2.4, "#6fbf86", OUT, 0.8) + circ(27, T0 + 34, 2.4, "#c94a3a", OUT, 0.8)
    # трубы подачи и обратки слева
    b += path(f"M12 {T0+6}H4V{T0+56}", None, "#c94a3a", 3.4) + path(f"M12 {T0+26}H8V{T0+56}", None, "#3d6fb0", 3.4)
    # значок «молния»
    b += path(f"M45 {T0+30}l-4 7h4l-4 7", None, "#e2b73a", 1.8)
    obj("water_heater", 1, 1, T0, b)
    META["water_heater"]["anchors"] = {"lamp": [27, T0 + 34]}


def objects_v123():
    """1.23: новый декор — растения, клумба, бюст, часы, кулер, вешалка, радио, самовар, кубки, глобус,
    ёлка, флагшток, скульптура, доска объявлений. Анимация (стрелки часов, флаг, огоньки ёлки, пар
    самовара, пузырьки кулера) рисуется в игре по точкам привязки (anchors)."""
    import math
    # --- кактус
    T0 = 30
    b = ell(32, T0 + 56, 14, 4.5, "#000", None, 0, 0.28)
    b += path(f"M20 {T0+34}H44L41 {T0+56}H23Z", "#b06a40", OUT, 2) + rect(18, T0 + 30, 28, 6, "#c27a4c", OUT, 1.8)
    b += rect(26, T0 - 16, 12, 48, "#4f9a4a", OUT, 2, 6)
    b += path(f"M26 {T0+8}H18V{T0-4}", None, OUT, 9) + path(f"M26 {T0+8}H18V{T0-4}", None, "#4f9a4a", 5.5)
    b += path(f"M38 {T0+2}H46V{T0-10}", None, OUT, 9) + path(f"M38 {T0+2}H46V{T0-10}", None, "#4f9a4a", 5.5)
    b += line(30, T0 - 12, 30, T0 + 28, "#7fc070", 1.4) + circ(32, T0 - 17, 3.5, "#e85a8a", OUT, 1)
    obj("cactus", 1, 1, T0, b)

    # --- монстера в большом горшке
    T0 = 44
    b = ell(36, T0 + 56, 17, 5, "#000", None, 0, 0.28)
    b += path(f"M16 {T0+28}H48L44 {T0+56}H20Z", "#5a6a72", OUT, 2) + rect(14, T0 + 24, 36, 7, "#6c7c84", OUT, 2)
    for (x, y, rx, ry, rot, c) in [(18, T0 + 2, 14, 9, -35, "#3f8f4a"), (46, T0 + 0, 14, 9, 35, "#4a9a52"), (32, T0 - 16, 13, 10, 0, "#56a85c"),
                                   (16, T0 - 18, 12, 8, -55, "#3f8f4a"), (48, T0 - 20, 12, 8, 55, "#4a9a52"), (32, T0 + 10, 12, 7, 0, "#357a3e")]:
        b += g(ell(0, 0, rx, ry, c, OUT, 1.5) + line(-rx * 0.8, 0, rx * 0.8, 0, "#2c6a34", 1) + line(-2, -ry * 0.9, 3, -2, "#2c6a34", 1.2) + line(4, ry * 0.9, -1, 2, "#2c6a34", 1.2), f"translate({x} {y}) rotate({rot})")
    obj("monstera", 1, 1, T0, b)

    # --- клумба 2×1 (на улице)
    T0 = 14
    b = shadow(6, T0 + 10, 120, 56, 10)
    b += rect(4, T0 + 4, 120, 56, "#a8553e", OUT, 2, 10) + rect(10, T0 + 10, 108, 44, "#5a3e2a", OUT, 1.4, 8)
    rnd = random.Random(1231)
    for k in range(30):
        x, y = rnd.uniform(16, 112), rnd.uniform(16, 50)
        b += circ(x, y + 3, 5.5, "#3f7f35", None, 0)
    for k in range(26):
        x, y = rnd.uniform(16, 112), rnd.uniform(14, 48)
        c = rnd.choice(["#e8484a", "#f2c84b", "#f5f1e8", "#d968b0", "#ff8a3a"])
        b += circ(x, y, 3.4, c, OUT, 0.8) + circ(x, y, 1.1, "#f5d24a" if c != "#f2c84b" else "#a8553e", None, 0)
    obj("flower_bed", 2, 1, T0, b)

    # --- бюст на постаменте
    T0 = 70
    b = ell(32, T0 + 58, 16, 5, "#000", None, 0, 0.3)
    b += box(14, T0 - 6, 36, 10, 52, "#c9c3b5", "#a9a294")
    b += rect(18, T0 + 18, 28, 10, "#8a8478", None, 0, 1, 0.5)
    b += path(f"M12 {T0-4}Q12 {T0-24} 32 {T0-26}Q52 {T0-24} 52 {T0-4}Z", "#8a6a3a", OUT, 2)
    b += rect(27, T0 - 30, 10, 8, "#8a6a3a", OUT, 1.6)
    b += path(f"M26 {T0-24}L32 {T0-14}L38 {T0-24}", None, "#6a5232", 1.4)
    b += ell(32, T0 - 38, 11, 13, "#9a7a48", OUT, 2) + path(f"M23 {T0-40}Q32 {T0-52} 41 {T0-40}", "#6a5232", OUT, 1.4)
    b += line(28, T0 - 34, 29, T0 - 34, "#4a3a22", 2) + line(35, T0 - 34, 36, T0 - 34, "#4a3a22", 2)
    b += path(f"M26 {T0-20}Q32 {T0-14} 38 {T0-20}", None, "#6a5232", 1.4)
    obj("bust", 1, 1, T0, b)

    # --- напольные часы
    T0 = 76
    b = shadow(18, T0 + 48, 32, 10)
    b += rect(18, T0 - 64, 28, 116, "#6a3e24", OUT, 2, 3) + rect(14, T0 - 70, 36, 10, "#5a3220", OUT, 2, 3)
    b += circ(32, T0 - 46, 11, "#f2ead8", OUT, 1.8)
    for k in range(12):
        a = k * math.pi / 6
        b += line(32 + 8.5 * math.cos(a), T0 - 46 + 8.5 * math.sin(a), 32 + 10 * math.cos(a), T0 - 46 + 10 * math.sin(a), "#3a2a1a", 1)
    b += rect(23, T0 - 30, 18, 46, "#2e2218", OUT, 1.4, 2) + rect(25, T0 - 28, 14, 42, "#d9c27a", None, 0, 2, 0.15)
    b += rect(18, T0 + 40, 28, 12, "#5a3220", OUT, 1.6)
    obj("floor_clock", 1, 1, T0, b)
    META["floor_clock"]["anchors"] = {"face": [32, T0 - 46], "pend": [32, T0 - 26]}

    # --- кулер с водой
    T0 = 56
    b = shadow(16, T0 + 46, 34, 12)
    b += rect(18, T0 - 6, 28, 58, "#e8ecee", OUT, 2, 4) + rect(22, T0 + 10, 20, 10, "#c8d0d4", OUT, 1.2, 2)
    b += rect(25, T0 + 13, 4, 6, "#d9493a", None, 0) + rect(35, T0 + 13, 4, 6, "#3d7fd0", None, 0)
    b += path(f"M22 {T0-6}V{T0-34}Q22 {T0-42} 32 {T0-42}Q42 {T0-42} 42 {T0-34}V{T0-6}Z", "#8fc8f0", OUT, 2, None, 0.85)
    b += rect(29, T0 - 47, 6, 6, "#3d7fd0", OUT, 1.2) + line(26, T0 - 36, 26, T0 - 10, "#fff", 2, 0.45)
    obj("water_cooler", 1, 1, T0, b)
    META["water_cooler"]["anchors"] = {"bottle": [32, T0 - 10]}

    # --- вешалка с одеждой
    T0 = 64
    b = ell(32, T0 + 56, 14, 4, "#000", None, 0, 0.28)
    b += path(f"M20 {T0+54}L32 {T0+44}L44 {T0+54}", None, OUT, 3) + line(32, T0 + 46, 32, T0 - 52, "#5a3a24", 3.4)
    b += circ(32, T0 - 54, 3, "#5a3a24", OUT, 1)
    b += path(f"M30 {T0-46}Q16 {T0-40} 18 {T0-6}H30Z", "#3f5f7a", OUT, 1.6)
    b += path(f"M34 {T0-46}Q48 {T0-40} 46 {T0-14}H34Z", "#7a5a3a", OUT, 1.6)
    b += ell(38, T0 - 50, 8, 3.5, "#2e2e30", OUT, 1.2)
    obj("coat_rack", 1, 1, T0, b)

    # --- радиоприёмник на тумбе
    T0 = 36
    b = shadow(10, T0 + 6, 50, 52)
    b += box(8, T0 + 4, 48, 16, 36, "#8a6a46", "#6b5236")
    b += rect(12, T0 - 22, 40, 28, "#7a4a2a", OUT, 2, 5) + rect(15, T0 - 19, 18, 22, "#d6c8a2", OUT, 1, 3)
    for k in range(5):
        b += line(17, T0 - 16 + k * 4, 31, T0 - 16 + k * 4, "#8a7a5a", 1)
    b += rect(36, T0 - 18, 13, 6, "#f2e2a0", OUT, 1) + circ(39, T0 - 3, 3, "#3a2a1a", None, 0) + circ(46, T0 - 3, 3, "#3a2a1a", None, 0)
    obj("radio", 1, 1, T0, b)
    META["radio"]["anchors"] = {"dial": [42, T0 - 15]}

    # --- самовар на столике
    T0 = 50
    b = shadow(10, T0 + 6, 50, 52)
    b += box(8, T0 + 4, 48, 14, 38, "#a07a4c", "#7a5a36")
    b += path(f"M20 {T0+6}H44L40 {T0-2}H24Z", "#b8862e", OUT, 1.6)
    b += ell(32, T0 - 18, 14, 16, "#d9a53a", OUT, 2) + ell(28, T0 - 22, 4, 8, "#fff", None, 0, 0.3)
    b += rect(28, T0 - 40, 8, 8, "#b8862e", OUT, 1.4) + ell(32, T0 - 42, 6, 2.5, "#8a6a26", OUT, 1)
    b += path(f"M18 {T0-22}H12M46 {T0-22}H52", None, "#3a2a1a", 3) + path(f"M40 {T0-10}h8v4", None, OUT, 2)
    b += rect(48, T0 - 2, 6, 6, "#f5f1e8", OUT, 1, 2)
    obj("samovar", 1, 1, T0, b)
    META["samovar"]["anchors"] = {"steam": [32, T0 - 46]}

    # --- шкаф с кубками
    T0 = 66
    b = shadow(10, T0 + 48, 52, 10)
    b += rect(8, T0 - 58, 48, 112, "#7a4a2a", OUT, 2, 3)
    b += rect(12, T0 - 54, 40, 96, "#c8dce6", OUT, 1.4, 2, None, 0.35)
    for k, y in enumerate((T0 - 22, T0 + 10)):
        b += line(12, y, 52, y, "#5a3a24", 2)
    for (x, y, c) in [(20, T0 - 22, "#d9b13b"), (32, T0 - 22, "#c0c4c8"), (44, T0 - 22, "#c08050"), (24, T0 + 10, "#d9b13b"), (40, T0 + 10, "#d9b13b")]:
        b += path(f"M{x-5} {y-16}H{x+5}Q{x+5} {y-8} {x} {y-6}Q{x-5} {y-8} {x-5} {y-16}Z", c, OUT, 1) + rect(x - 1, y - 6, 2, 3, c, None, 0) + rect(x - 4, y - 3, 8, 3, c, OUT, 0.8)
    b += rect(14, T0 + 20, 36, 18, "#7a4a2a", None, 0) + rect(18, T0 + 26, 28, 4, "#f2d58a", None, 0, 1, 0.6)
    obj("trophy_case", 1, 1, T0, b)

    # --- глобус
    T0 = 40
    b = ell(32, T0 + 56, 14, 4, "#000", None, 0, 0.28)
    b += path(f"M22 {T0+54}L32 {T0+36}L42 {T0+54}", None, "#5a3a24", 3) + line(32, T0 + 36, 32, T0 + 24, "#5a3a24", 3)
    b += circ(32, T0 + 2, 20, "#4f88b8", OUT, 2)
    b += path(f"M20 {T0-6}q6 -6 10 0t8 4q2 6 -4 8t-10 -2z", "#7aa860", None, 0) + path(f"M34 {T0+10}q6 -2 8 4t-4 6q-6 0 -4 -10z", "#7aa860", None, 0)
    b += path(f"M14 {T0+8}A20 20 0 0 0 50 {T0-4}", None, "#b8862e", 2.4)
    obj("globe", 1, 1, T0, b)

    # --- новогодняя ёлка
    T0 = 80
    b = ell(32, T0 + 56, 20, 6, "#000", None, 0, 0.3)
    b += rect(26, T0 + 38, 12, 14, "#6a4a2a", OUT, 1.6) + rect(20, T0 + 46, 24, 10, "#b0282a", OUT, 1.6, 2)
    for (w, y) in [(26, T0 + 40), (22, T0 + 14), (18, T0 - 12), (13, T0 - 36)]:
        b += poly([(32 - w, y), (32, y - 34), (32 + w, y)], "#2f6f3a", OUT, 1.8)
        b += poly([(32 - w + 6, y - 2), (32, y - 26), (32 + w - 10, y - 4)], "#3f8a4a", None, 0)
    b += poly([(32, T0 - 80), (35, T0 - 73), (42, T0 - 73), (36, T0 - 68), (38, T0 - 61), (32, T0 - 65), (26, T0 - 61), (28, T0 - 68), (22, T0 - 73), (29, T0 - 73)], "#f2c84b", OUT, 1)
    b += path(f"M14 {T0+30}Q32 {T0+20} 50 {T0+26}M18 {T0+4}Q32 {T0-4} 46 {T0+2}M22 {T0-20}Q32 {T0-26} 42 {T0-22}", None, "#d9b13b", 1.4)
    obj("ny_tree", 1, 1, T0, b)
    META["ny_tree"]["anchors"] = {"lights": [[18, T0 + 28], [26, T0 + 24], [38, T0 + 23], [46, T0 + 26], [22, T0 + 3], [30, T0 - 1], [40, T0 + 1],
                                             [26, T0 - 21], [34, T0 - 24], [40, T0 - 22], [32, T0 - 44], [28, T0 + 10], [36, T0 - 10]]}

    # --- флагшток (флаг рисуется в игре — развевается)
    T0 = 112
    b = ell(32, T0 + 56, 14, 4, "#000", None, 0, 0.3)
    b += rect(20, T0 + 44, 24, 10, "#9a9a92", OUT, 1.6, 2)
    b += line(30, T0 - 108, 30, T0 + 46, "#c8ccce", 3.2) + circ(30, T0 - 110, 3, "#d9b13b", OUT, 1)
    obj("flagpole", 1, 1, T0, b)
    META["flagpole"]["anchors"] = {"flag": [31, T0 - 104]}

    # --- скульптура «Рабочий с молотом»
    T0 = 92
    b = ell(32, T0 + 58, 18, 5, "#000", None, 0, 0.3)
    b += box(12, T0 + 4, 40, 10, 44, "#b0aa9c", "#8f897c")
    b += rect(16, T0 + 24, 32, 8, "#6f6a60", None, 0, 1, 0.5)
    fig = "#7a8a90"
    b += path(f"M26 {T0+6}L28 {T0-26}H36L38 {T0+6}H33L32 {T0-10}L31 {T0+6}Z", fig, OUT, 1.6)
    b += rect(26, T0 - 52, 12, 28, fig, OUT, 1.6, 3) + circ(32, T0 - 60, 6.5, fig, OUT, 1.6)
    b += path(f"M37 {T0-48}L48 {T0-70}", None, OUT, 5) + path(f"M37 {T0-48}L48 {T0-70}", None, fig, 3)
    b += line(46, T0 - 66, 52, T0 - 82, "#5a6a70", 2.4) + rect(46, T0 - 88, 12, 7, "#5a6a70", OUT, 1.2, 1)
    b += path(f"M27 {T0-46}L20 {T0-30}", None, OUT, 5) + path(f"M27 {T0-46}L20 {T0-30}", None, fig, 3)
    obj("statue_worker", 1, 1, T0, b)

    # --- доска объявлений
    T0 = 48
    b = shadow(6, T0 + 44, 116, 10)
    b += rect(14, T0 + 2, 6, 50, "#5a3a24", OUT, 1.4) + rect(108, T0 + 2, 6, 50, "#5a3a24", OUT, 1.4)
    b += rect(6, T0 - 40, 116, 50, "#a07a4c", OUT, 2, 3) + rect(10, T0 - 36, 108, 42, "#c8a878", None, 0, 2)
    rnd = random.Random(1232)
    for k in range(9):
        x, y = 14 + (k % 5) * 21 + rnd.uniform(-2, 2), T0 - 32 + (k // 5) * 20 + rnd.uniform(-2, 2)
        b += rect(x, y, 16, 15, rnd.choice(["#f5f1e8", "#f2e6a0", "#e8f0f5", "#f5e0e0"]), OUT, 0.8)
        b += line(x + 3, y + 5, x + 13, y + 5, "#7a7a72", 1) + line(x + 3, y + 9, x + 11, y + 9, "#7a7a72", 1)
        b += circ(x + 8, y + 1.5, 1.6, "#d9493a", None, 0)
    b += text_svg(64, T0 - 41, "ОБЪЯВЛЕНИЯ", 8, "#f5f1e8")
    obj("notice_board", 2, 1, T0, b)


def main():
    tiles()
    objects()
    objects2()
    objects3()
    objects4()
    items()
    items3()
    items4()
    items_v119()
    emo_v119()
    ui_v119()
    ground_v119()
    walls_v119()
    objects_v120()
    people()
    vehicles()
    ui()
    stage5()
    stage6()
    objects_v()
    lights_water()
    objects_v14()
    objects_rot()
    objects_v15()
    objects_v16()
    objects_v17()
    objects_v18()
    objects_v19()
    objects_v110()
    objects_v111()
    zone_icons()
    overlay_icons()
    materials_v112()
    flora_v113()
    cnc_v113()
    bmats_v113()
    power_v113()
    carry_v114()
    vehicles_v114()
    shower_v114()
    import gen_people   # 1.15: новый облик людей — перекрывает старые слои головы, лица и причёсок
    utils_v115()
    toilet_v115()
    locker2_v115()
    props_v115()
    flora_v115()
    company_v117()
    ui_v117()
    nets_v118()
    import gen_machines   # 1.16: парк станков — по пять на передел и ЧПУ
    gen_machines.run(sys.modules[__name__])
    import gen_cnc        # 1.19: станки с ЧПУ по прототипам — у каждого свой силуэт
    gen_cnc.run(sys.modules[__name__])
    gen_people.people_v115()
    icons_v121()          # 1.21: окно, двери, ворота — вид спереди (перекрывает старые значки)
    cat_v122()            # 1.22: кот заново
    objects_v123()        # 1.23: новый декор
    import gen_v130       # 1.30: проходная с турникетами (будка, «нутро» будки, три вида)
    gen_v130.run(sys.modules[__name__])
    os.makedirs(os.path.join(ROOT, "data"), exist_ok=True)
    with open(os.path.join(ROOT, "data/sprite_meta.json"), "w", encoding="utf-8") as f:
        json.dump(META, f, ensure_ascii=False, indent=1)
    n = sum(len(fs) for _, _, fs in os.walk(os.path.join(ROOT, "assets")))
    print("Готово, файлов в assets:", n)


if __name__ == "__main__":
    main()
