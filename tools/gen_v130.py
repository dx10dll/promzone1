#!/usr/bin/env python3
"""1.30 «Проходная»: будка охранника и два турникета-триппода одним объектом (4×1).

Футпринт: клетки 0–1 — будка (непроходима, охранник сидит в клетке 1 у окна), клетки 2 и 3 — проходы
с турникетами. Виды: спереди (checkpoint), сбоку (checkpoint_v, будка сверху — для забора слева/справа),
со спины (checkpoint_b, будка справа). Окно будки в основном спрайте — стекло без «нутра»; у каждого вида есть
внутренний слой (_in): задняя стенка, полка, монитор, спинка стула. Он рисуется ПОЗАДИ сидящего охранника,
а основной спрайт — поверх: охранник виден в окне, ноги скрыты стенкой.
Лиц на спрайте нет: в будке сидит настоящий охранник, если он на смене.
Планки турникетов рисуются кодом (ThingView) — крутятся, когда человек проходит. Якоря hub1/hub2:
[x, y, rx, ry] — ось и радиусы проекции планок первого и второго турникета (по порядку клеток «walk»).

Запуск: python3 tools/gen_v130.py (из корня проекта) — пишет SVG и обновляет свои ключи в data/sprite_meta.json.
"""
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_assets as ga  # noqa: E402

OUT = ga.OUT
R, C, L, P, B, E, PL = ga.rect, ga.circ, ga.line, ga.path, ga.box, ga.ell, ga.poly
WALL, WALL_F = "#d3dbd2", "#b7c3b8"
ROOF, ROOF_F = "#5b636c", "#464d55"
PLINTH = "#6d736e"
GLASS = "#b4d8ea"
INNER, INNER_D = "#8d9d94", "#6f7d75"
STEEL, STEEL_D, STEEL_L = "#b9c2c8", "#8a9398", "#e1e6e9"
T0 = 104
T0V = 96


def _cabinet(x, y, w, depth, h):
    """Тумба турникета: верх с табло (зелёная стрелка), передняя панель."""
    s = B(x, y, w, depth, h, STEEL_L, STEEL)
    s += R(x + 2, y + 3, w - 4, depth - 6, "#2b3034", OUT, 1, 2)
    cx, cy = x + w * 0.5, y + depth * 0.5
    s += PL([(cx - 3, cy + 2), (cx + 3, cy + 2), (cx, cy - 3)], "#6fdc8a", None, 0)
    s += R(x + 3, y + depth + 5, w - 6, h - 10, None, STEEL_D, 1, 1)
    return s


def _rail(x0, y0, x1, y1):
    return L(x0, y0, x1, y1, OUT, 4.6) + L(x0, y0, x1, y1, STEEL, 2.8) + L(x0, y0 - 0.8, x1, y1 - 0.8, STEEL_L, 0.9)


def _post(x, y_top, y_bot):
    return L(x, y_top, x, y_bot, OUT, 5.2) + L(x, y_top, x, y_bot, STEEL, 3.2) + C(x, y_top, 2.6, STEEL_L, OUT, 1) + R(x - 4, y_bot - 2, 8, 4, STEEL_D, OUT, 1, 1)


def _window_inside(wl, wt, wr, wb, seat_x, back):
    """Что видно в окно за охранником: задняя стенка, полка, телефон, монитор, ключи; спинка стула."""
    s = R(wl, wt, wr - wl, wb - wt, INNER, None, 0)
    s += R(wl, wt + (wb - wt) * 0.55, wr - wl, 3, INNER_D, None, 0)
    if not back:
        s += R(wl + 6, wt + 5, 16, 12, "#a8865a", OUT, 0.8)          # доска с ключами
        for k in range(4):
            s += L(wl + 9 + k * 3.4, wt + 8, wl + 9 + k * 3.4, wt + 13, "#e0c060", 1.1)
        s += R(wl + 28, wt + 4, 10, 13, "#f0ebde", OUT, 0.8) + L(wl + 30, wt + 8, wl + 36, wt + 8, "#c94a3a", 0.9)  # график
        s += R(wl + 6, wt + (wb - wt) * 0.55 - 9, 18, 9, "#2e3438", OUT, 1, 1) + R(wl + 8, wt + (wb - wt) * 0.55 - 7.5, 14, 6, "#6fa8c8", None, 0)  # монитор
        s += R(wl + 30, wt + (wb - wt) * 0.55 - 5, 9, 5, "#3a3f43", OUT, 0.8, 1)   # телефон
        s += R(wl + 44, wt + (wb - wt) * 0.55 - 8, 6, 8, "#e8e4da", OUT, 0.8) + E(wl + 47, wt + (wb - wt) * 0.55 - 8, 3, 1, "#7a4a2a", None, 0)  # кружка
    s += R(seat_x - 9, wt + (wb - wt) * 0.42, 18, 16, "#455768", OUT, 1.2, 3)   # спинка стула
    return s


def _booth_front(bx, bw, top_y, dtop, face_y, bot, wl, wt, wr, wb, back, seat_x, sign=True):
    """Будка: (наружный слой — стены с окном, рисуется поверх охранника; внутренний слой — что видно в окно)."""
    inner = _window_inside(wl, wt, wr, wb, seat_x, back)
    f = R(bx - 5, top_y - 9, bw + 10, 11, ROOF, OUT, 2, 2) + R(bx - 5, top_y + 1, bw + 10, 4, ROOF_F, OUT, 1.4)
    f += R(bx, top_y + 5, bw, dtop - 5, "#8a939b", OUT, 2)              # крыша сверху: профлист
    step = 9
    k = bx + step
    while k < bx + bw - 3:
        f += L(k, top_y + 7, k, top_y + dtop - 2, "#6d767e", 1.2)
        k += step
    f += R(bx, top_y + dtop - 5, bw, 5, WALL, OUT, 1.2)                     # карниз
    f += R(bx, wb, bw, bot - wb, WALL_F, OUT, 2)
    f += R(bx, bot - 9, bw, 9, PLINTH, OUT, 1.6)
    f += R(bx, face_y, bw, wt - face_y, WALL_F, OUT, 2)
    f += R(bx, wt - 1, wl - bx, wb - wt + 2, WALL_F, None, 0) + R(wr, wt - 1, bx + bw - wr, wb - wt + 2, WALL_F, None, 0)
    f += L(bx, face_y, bx, bot, OUT, 2) + L(bx + bw, face_y, bx + bw, bot, OUT, 2)
    f += R(wl, wt, wr - wl, wb - wt, GLASS, None, 0, 0, None, 0.2)
    f += PL([(wl + 4, wt + 2), (wl + 14, wt + 2), (wl + 6, wb - 2), (wl + 2, wb - 2)], "#ffffff", None, 0, 0.32)
    f += PL([(wr - 16, wt + 2), (wr - 11, wt + 2), (wr - 19, wb - 2), (wr - 24, wb - 2)], "#ffffff", None, 0, 0.2)
    f += R(wl, wt, wr - wl, wb - wt, None, "#f4f6f4", 3.4) + R(wl, wt, wr - wl, wb - wt, None, OUT, 1.2)
    nm = 2 if wr - wl > 70 else 1
    for k in range(1, nm + 1):
        mx = wl + (wr - wl) * k / (nm + 1)
        f += L(mx, wt, mx, wb, "#f4f6f4", 2.6) + L(mx, wt, mx, wb, OUT, 0.8)
    f += R(wl - 5, wb - 1, wr - wl + 10, 6, "#8a8270", OUT, 1.2)       # подоконник-стойка
    if sign:
        sx = bx + bw * 0.5
        f += R(sx - 26, face_y + 3, 52, 10, "#2f5f8a", OUT, 1, 1)       # табличка «Проходная» (без букв)
        f += L(sx - 20, face_y + 8, sx + 20, face_y + 8, "#e8edf2", 1.6)
        f += R(seat_x - 8, wb - 8, 16, 7, "#3a3f43", OUT, 0.8, 1, 0.7)  # окошко для пропусков
    f += C(bx + bw - 7, face_y + 7, 2.8, "#ffe9a0", OUT, 0.8)          # фонарь
    return f, inner


def front(back=False):
    """Вид спереди: будка слева (клетки 0–1), турникеты в клетках 2 и 3. Со спины — зеркально, окно поменьше."""
    W = 4 * 64
    bx, bw = 3, 122
    top_y, dtop = T0 - 64, 28
    face_y = top_y + dtop
    bot = T0 + 58
    seat_x = 96
    wt, wb = face_y + 18, face_y + 58
    wl, wr = (bx + 8, bx + bw - 8) if not back else (bx + 52, bx + bw - 10)
    b = ""
    hubs = []
    for k in range(2):
        cx0 = 128 + k * 64
        b += _cabinet(cx0 + 3, T0 - 2, 14, 40, 24)
        hubs.append([cx0 + 17, T0 + 18, 30, 8])
        b += C(cx0 + 17, T0 + 18, 3.2, "#5a6064", OUT, 1)
    xr = W - 4
    b += _post(xr, T0 - 22, T0 + 6) + _rail(xr, T0 - 20, xr, T0 + 30) + _post(xr, T0 + 30, T0 + 58)
    ext, ff = _booth_front(bx, bw, top_y, dtop, face_y, bot, wl, wt, wr, wb, back, seat_x, not back)
    b = ext + b
    sh = ga.shadow(8, T0 - 4, W + 4, 70, 6, 0.24)
    if back:
        tr = f"translate({W},0) scale(-1,1)"
        b = sh + ga.g(b, tr)
        ff = ga.g(ff, tr)
        hubs = [[W - h[0], h[1], -h[2], h[3]] for h in hubs]
        glass = [W - wr, wt, wr - wl, wb - wt]
    else:
        b = sh + b
        glass = [wl, wt, wr - wl, wb - wt]
    return b, ff, {"hub1": hubs[0], "hub2": hubs[1], "glass": glass}


def side():
    """Вид сбоку: будка в двух верхних клетках, два прохода под ней (люди идут слева направо)."""
    H0 = T0V
    bx, bw = 6, 52
    top_y = H0 - 40
    dtop = 84
    face_y = top_y + dtop
    bot = H0 + 124
    seat_x = 32
    wt, wb = face_y + 12, face_y + 48
    wl, wr = bx + 8, bx + bw - 8
    b = ga.shadow(8, H0 - 2, 68, 4 * 64 + 2, 6, 0.24)
    ext, ff = _booth_front(bx, bw, top_y, dtop, face_y, bot, wl, wt, wr, wb, False, seat_x, False)
    b += ext + R(bx + bw - 1, face_y + 6, 3, bot - face_y - 16, "#9aa59a", OUT, 1)   # край двери сбоку
    hubs = []
    for k in range(2):
        cy0 = H0 + 128 + k * 64
        b += _cabinet(12, cy0 - 6, 40, 12, 20)
        hubs.append([32, cy0 + 26, 10, 20])
    yb = H0 + 4 * 64 - 4
    b += _post(10, yb - 28, yb) + _post(54, yb - 28, yb) + _rail(10, yb - 24, 54, yb - 24)
    for h in hubs:
        b += C(h[0], h[1], 3.2, "#5a6064", OUT, 1)
    return b, ff, {"hub1": hubs[0], "hub2": hubs[1], "glass": [wl, wt, wr - wl, wb - wt]}


def run(module=None):
    global ga
    if module is not None:
        ga = module
    for key, (b, f, a) in (("checkpoint", front(False)), ("checkpoint_b", front(True))):
        ga.obj(key, 4, 1, T0, b)
        ga.META[key]["anchors"] = a
        ga.obj(key + "_in", 4, 1, T0, f)
    b, f, a = side()
    ga.obj("checkpoint_v", 1, 4, T0V, b)
    ga.META["checkpoint_v"]["anchors"] = a
    ga.obj("checkpoint_v_in", 1, 4, T0V, f)


def main():
    ga.META.clear()
    run()
    path = os.path.join(ga.ROOT, "data/sprite_meta.json")
    with open(path, encoding="utf-8") as fh:
        meta = json.load(fh)
    for k, v in ga.META.items():
        meta[k] = v
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, ensure_ascii=False, indent=1)
    print("1.30: проходная —", ", ".join(sorted(ga.META)))


if __name__ == "__main__":
    main()
