#!/usr/bin/env python3
"""1.19 «Станки с ЧПУ по прототипам»: у каждого станка — свой силуэт.

Токарные: 16А20Ф3 (советский открытый, револьверная головка, отдельный шкаф с пультом),
Пантера-2600 (длинный токарный центр в кожухе, транспортёр стружки), Ханган HL-1600 (тяжёлый
открытый токарный, огромный патрон, люнет, щиток на рельсе), Майдэй MBL-400 (компактный токарный
в кожухе со скошенным верхом).
Фрезерные: 65А60 (советский: колонна, крестовый стол, цепной магазин, шкафы электроавтоматики),
Сайдвей ВМ-2215 (станок с ЧПУ «на станине»: колонна, голова с мотором, стол с гармошками, поддон),
Хартвуд VMC-3260 (портальный: две стойки, траверса, лесенка), Мингер VM-540 (кубический центр в кожухе,
две двери, магазин сбоку, пульт справа).

Три вида у каждого: спереди, сбоку («_v», рабочая сторона слева) и со спины («_b»).
Якоря: lamp (сигнальная лампа), work (зона резания), in/out (заготовки и готовое), screen;
у открытых токарных — chuck/tool/bar (вращение патрона и стружка как у универсальных).
Запуск — из gen_assets.py после gen_machines: gen_cnc.run(ga).
"""

ga = None
OUT = "#23262a"
STEEL, STEEL_D, STEEL_L = "#9aa3a8", "#7b8286", "#cdd3d7"
DARK = "#3a3f43"
GLASS, GLASS_D = "#46677a", "#2a3036"
PANEL, PANEL_D = "#3d4652", "#2e3640"


def R(*a, **k):
    return ga.rect(*a, **k)


def C(*a, **k):
    return ga.circ(*a, **k)


def E(*a, **k):
    return ga.ell(*a, **k)


def L(*a, **k):
    return ga.line(*a, **k)


def P(*a, **k):
    return ga.path(*a, **k)


def B(*a, **k):
    return ga.box(*a, **k)


def Q(*a, **k):
    return ga.poly(*a, **k)


def mirror(body, W):
    return ga.g(body, f"translate({W} 0) scale(-1 1)")


def save(key, wt, ht, T0, body, anchors):
    ga.obj(key, wt, ht, T0, body)
    ga.META[key]["anchors"] = anchors


def mx(a, W):
    """Якорь для отражённого вида: x -> W - x."""
    out = {}
    for k, v in a.items():
        v = list(v)
        v[0] = W - v[0] - (v[2] if len(v) == 4 else 0)
        out[k] = v
    return out


# ---------------------------------------------------------------- детали

def window(x, y, w, h, frame=GLASS_D):
    s = R(x, y, w, h, frame, OUT, 1.8, 3)
    s += R(x + 3, y + 3, w - 6, h - 6, GLASS, None, 0, 2, 0.88)
    s += Q([(x + 5, y + 3), (x + 5 + w * 0.22, y + 3), (x + 5 + w * 0.08, y + h - 3), (x + 3, y + h - 3)], "#ffffff", None, 0, 0.13)
    return s


def tower(x, y):
    """Сигнальная колонна: красный, жёлтый, зелёный; возвращает (svg, якорь зелёной лампы)."""
    s = R(x - 1.5, y + 10, 3, 12, DARK, None, 0)
    s += R(x - 4, y - 14, 8, 8, "#c94a3a", OUT, 1, 2) + R(x - 4, y - 6, 8, 8, "#e2b73a", OUT, 1, 2)
    s += R(x - 4, y + 2, 8, 8, "#6fbf86", OUT, 1, 2)
    return s, [x, y + 6]


def pendant(x, y, w=26, h=40, scr="#6fd0e0", seg=False):
    """Пульт ЧПУ: экран и клавиатура."""
    s = R(x, y, w, h, PANEL, OUT, 1.6, 3)
    s += R(x + 3, y + 3, w - 6, h * 0.38, "#1d2a34", OUT, 1, 1)
    if seg:
        for k in range(4):
            s += R(x + 5 + k * (w - 10) / 4, y + 6, (w - 10) / 4 - 2, h * 0.38 - 6, "#e8853a", None, 0, 0.5, 0.9)
    else:
        s += R(x + 5, y + 5, w - 10, h * 0.38 - 4, scr, None, 0, 1, 0.8)
    ky = y + h * 0.38 + 6
    for yy in range(3):
        for xx in range(4):
            if ky + yy * 5 + 4 > y + h - 8:
                break
            s += R(x + 4 + xx * (w - 8) / 4, ky + yy * 5, (w - 8) / 4 - 1.5, 3.4, ["#c9ccce", "#e2b73a", "#c9ccce", "#6fbf86"][(xx + yy) % 4], None, 0, 0.6)
    s += C(x + w - 6, y + h - 5, 2.8, "#c94a3a", OUT, 0.8)
    return s


def louvers(x, y, w, n, step=5, col="#7f878b"):
    return "".join(L(x, y + k * step, x + w, y + k * step, col, 1.6) for k in range(n))


def cabinet(x, yb, w, d, z, top="#d6d2bf", front="#bdb8a2"):
    """Шкаф электроавтоматики: стоит на линии yb (низ передней грани)."""
    s = B(x, yb - z - d, w, d, z, top, front)
    s += L(x + w / 2, yb - z + 4, x + w / 2, yb - 4, OUT, 1.2)
    s += R(x + w / 2 - 5, yb - z * 0.55, 3, 8, DARK, None, 0) + R(x + w / 2 + 2, yb - z * 0.55, 3, 8, DARK, None, 0)
    s += louvers(x + 5, yb - 16, w / 2 - 9, 3, 4, "#8f8a76") + louvers(x + w / 2 + 4, yb - 16, w / 2 - 9, 3, 4, "#8f8a76")
    return s


def conveyor(x0, y0, x1, y1, w=14, col="#5d6a74"):
    """Наклонный транспортёр стружки от (x0,y0) вверх к (x1,y1) и бункер."""
    s = P(f"M{x0} {y0}L{x1} {y1}L{x1} {y1 + w}L{x0} {y0 + w}Z", col, OUT, 1.6)
    n = 6
    for k in range(1, n):
        t = k / n
        xa, ya = x0 + (x1 - x0) * t, y0 + (y1 - y0) * t
        s += L(xa, ya + 2, xa, ya + w - 2, "#3f4a52", 1.2)
    s += R(x1 - 6, y1 + w - 2, 20, 18, "#4f5a3e", OUT, 1.4, 2) + R(x1 - 4, y1 + w, 16, 4, "#a59a78", None, 0)
    return s


def chuck_side(x, cy, r, jaws=True):
    """Патрон, видимый с ребра (ось шпинделя — вправо): высокий цилиндр."""
    s = R(x, cy - r, r * 0.55, r * 2, "#a2abb0", OUT, 1.6, 3)
    s += R(x + 2, cy - r + 3, r * 0.55 - 4, 4, "#fff", None, 0, 1, 0.25)
    if jaws:
        for dy in (-r * 0.62, 0, r * 0.62):
            s += R(x + r * 0.5, cy + dy - 3, 6, 6, STEEL_D, OUT, 1)
    return s


def turret(cx, cy, r, col="#9aa3a8"):
    pts = []
    import math
    for k in range(6):
        a = math.pi / 6 + k * math.pi / 3
        pts.append((cx + r * math.cos(a), cy + r * 0.62 * math.sin(a)))
    s = Q(pts, col, OUT, 1.5)
    s += C(cx, cy, r * 0.3, STEEL_D, OUT, 1)
    s += R(cx - 2, cy + r * 0.5, 4, r * 0.7, "#e8e0c0", OUT, 0.8)
    return s


def bed_chips(x, y, w, h):
    s = R(x, y, w, h, "#33383c", OUT, 1.6)
    k = 0
    xx = x + 8
    while xx < x + w - 12:
        s += P(f"M{xx} {y + h * 0.6}q3 -4 6 0t6 0", None, "#b9c2c8" if k % 2 else "#c7a46a", 1.3)
        xx += 17
        k += 1
    return s


# ================================================================ 16А20Ф3 (cnc_lathe, 3×2)

def lathe_16a20f3():
    key, wt, ht = "cnc_lathe", 3, 2
    W, H = wt * 64, ht * 64
    T0 = 70
    GT, GF = "#c8c6b2", "#a9a690"          # серо-бежевая советская краска
    AC = "#d27a2c"
    yb = T0 + H - 6                         # линия пола спереди
    def body(back):
        b = ga.shadow(14, T0 - 10, W - 8, H + 8)
        # шкаф электроавтоматики и пульт — сзади справа
        b += cabinet(W - 58, T0 + 40, 50, 18, 92, "#c9cdc4", "#aeb3a8")
        # станина на тумбах
        b += R(8, yb - 34, 46, 34, GF, OUT, 2) + R(W - 70, yb - 34, 46, 34, GF, OUT, 2)
        b += bed_chips(54, yb - 28, W - 124, 22)
        b += R(6, yb - 54, W - 30, 20, "#8b9296", OUT, 2)
        b += L(6, yb - 48, W - 24, yb - 48, "#b2b9bd", 1.4) + L(6, yb - 40, W - 24, yb - 40, "#b2b9bd", 1.4)
        # передняя бабка
        b += B(6, yb - 104, 60, 16, 50, GT, GF)
        b += R(12, yb - 82, 22, 12, "#2a2e31", OUT, 1) + R(14, yb - 80, 18, 8, "#e8853a", None, 0, 1, 0.85)
        b += R(10, yb - 100, 52, 6, AC, None, 0, 1)
        # патрон и откидной щиток патрона
        cx = 66
        b += chuck_side(cx, yb - 70, 15)
        b += P(f"M{cx - 2} {yb - 92}h22q6 0 6 6v26h-28z", "#e2c25a", OUT, 1.4, 0.55)
        # деталь
        b += R(cx + 12, yb - 74, 34, 8, STEEL_L, OUT, 1.2)
        # суппорт с 6-позиционной револьверной головкой
        b += B(cx + 40, yb - 64, 40, 10, 14, "#7e8a80", "#636e64")
        b += turret(cx + 60, yb - 70, 15)
        # задняя бабка
        b += B(W - 82, yb - 80, 46, 12, 30, GT, GF)
        b += R(W - 98, yb - 72, 16, 7, "#aab1b5", OUT, 1.1)
        # раздвижной прозрачный щиток на рельсе
        b += R(cx - 6, yb - 112, 100, 4, STEEL_D, OUT, 1)
        b += R(cx + 30, yb - 108, 62, 52, "#a8d0e0", OUT, 1.4, 2, 0.32)
        b += L(cx + 34, yb - 104, cx + 44, yb - 62, "#ffffff", 1.2, 0.5)
        # пульт «НЦ» на поворотной консоли перед шкафом
        b += L(W - 34, T0 + 0, W - 34, T0 + 30, DARK, 3)
        b += pendant(W - 50, T0 + 26, 30, 36, seg=True)
        return b
    lamp_xy = [W - 33, T0 - 46]
    b = body(False)
    tw, lamp = tower(W - 33, T0 - 52)
    b += tw
    an = {"lamp": lamp, "chuck": [66, yb - 85, 8, 30], "tool": [126, yb - 62], "bar": [70, yb - 20],
          "out": [W - 50, yb - 4], "in": [18, yb - 4], "work": [100, yb - 70], "screen": [W - 35, T0 + 34]}
    save(key, wt, ht, T0, b, an)
    # со спины: станок зеркально, шкаф ближе к зрителю, щитки и пульт не видны
    b = ga.shadow(14, T0 - 10, W - 8, H + 8)
    bb = ""
    bb += R(8, yb - 34, 46, 34, GF, OUT, 2) + R(W - 70, yb - 34, 46, 34, GF, OUT, 2)
    bb += R(54, yb - 30, W - 124, 24, "#4a5054", OUT, 1.6)
    bb += R(6, yb - 54, W - 30, 20, "#8b9296", OUT, 2)
    bb += B(6, yb - 104, 60, 16, 50, GT, GF) + louvers(14, yb - 80, 44, 5, 5, "#8c8a76")
    bb += B(W - 82, yb - 80, 46, 12, 30, GT, GF)
    bb += B(106, yb - 64, 40, 10, 14, "#7e8a80", "#636e64")
    bb += cabinet(W - 58, yb + 2, 50, 18, 92, "#c9cdc4", "#aeb3a8")
    b += mirror(bb, W)
    tw, lamp = tower(30, T0 - 40)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 110, yb - 60], "in": [W - 30, yb - 4], "out": [40, yb - 4]})
    # сбоку (2×3): бабка сверху, станина вниз, рабочая сторона слева, шкаф справа
    _side_lathe("cnc_lathe_v", 2, 3, GT, GF, AC, open_=True, cabinet_=True)


# ---------------------------------------------------------------- вид сбоку для токарных

def _side_lathe(key, wt, ht, GT, GF, AC, open_=False, cabinet_=False, encl=None, conveyor_=False, big=False):
    """Токарный, повёрнутый: длинная ось вниз. Бабка вверху, задняя бабка внизу, рабочая сторона слева."""
    Wv, Hv = wt * 64, ht * 64
    T0 = 90
    b = ga.shadow(14, T0 - 26, Wv - 12, Hv + 20)
    if encl:
        WH, WF = encl
        b += B(8, T0 - 44, Wv - 30, Hv - 10, 54, WH, WF)
        b += window(18, T0 - 34, Wv * 0.42, Hv - 40)
        cx = 18 + Wv * 0.21
        b += R(cx - 12, T0 - 30, 24, 16 if not big else 22, "#a2abb0", OUT, 1.4, 2)
        b += R(cx - 4, T0 - 14, 8, Hv * 0.32, STEEL_L, OUT, 1.1)
        b += R(Wv - 26, T0 - 40, 6, Hv - 20, AC, None, 0, 1)
        b += pendant(Wv - 30, T0 + Hv - 128, 22, 36)
        if conveyor_:
            b += R(Wv - 22, T0 + Hv - 30, 18, 26, "#4f5a3e", OUT, 1.4, 2)
        tw, lamp = tower(Wv - 40, T0 - 62)
        b += tw
        work = [cx, T0 + 20]
    else:
        # открытый: станина вдоль, бабка вверху
        b += R(Wv * 0.3, T0 - 4, Wv * 0.34, Hv - 18, "#5c6267", OUT, 2)
        b += R(Wv * 0.34, T0, Wv * 0.26, Hv - 26, "#8b9296", OUT, 1.6)
        b += B(Wv * 0.2, T0 - 44 - (10 if big else 0), Wv * 0.56, 40, 30 + (10 if big else 0), GT, GF)
        b += R(Wv * 0.3, T0 - 4 + (6 if big else 0), Wv * 0.36, 16 if not big else 22, "#a2abb0", OUT, 1.4, 3)
        b += R(Wv * 0.45, T0 + 14, 8, Hv * 0.3, STEEL_L, OUT, 1.1)
        b += B(Wv * 0.16, T0 + Hv * 0.5, Wv * 0.6, 18, 12, "#7e8a80", "#636e64")
        b += turret(Wv * 0.24, T0 + Hv * 0.5 + 10, 11)
        b += B(Wv * 0.28, T0 + Hv - 70, Wv * 0.4, 22, 16, GT, GF)
        if cabinet_:
            b += cabinet(Wv - 34, T0 + 30, 28, 30, 60, "#c9cdc4", "#aeb3a8")
            b += pendant(Wv - 36, T0 + Hv - 110, 26, 34, seg=True)
        else:
            b += R(Wv * 0.78, T0 - 20, Wv * 0.12, Hv * 0.6, "#a8d0e0", OUT, 1.2, 2, 0.35)   # щиток на рельсе
            b += pendant(Wv - 30, T0 - 30, 24, 34)
        tw, lamp = tower(Wv * 0.24, T0 - 60)
        b += tw
        work = [Wv * 0.45, T0 + 40]
    b += R(12, T0 + Hv - 12, Wv - 28, 10, AC, OUT, 1.2)
    save(key, wt, ht, T0, b, {"lamp": lamp, "work": work, "in": [8, T0 + Hv - 24], "out": [8, T0 + Hv * 0.5 - 10]})


def _side_box(key, wt, ht, WH, WF, AC, z=64, magazine=False, portal=False, cabinets=False, table=False):
    """Фрезерный, повёрнутый: верх кожуха с окном, торец снизу; рабочая сторона слева."""
    Wv, Hv = wt * 64, ht * 64
    T0 = 104 + max(0, z - 64)
    b = ga.shadow(14, T0 - 26, Wv - 12, Hv + 20)
    if portal:
        # стойки вверху и внизу, траверса между ними, стол вдоль
        b += R(Wv * 0.28, T0 - 10, Wv * 0.44, Hv - 20, "#7b8286", OUT, 2)
        b += R(Wv * 0.32, T0 - 4, Wv * 0.36, Hv - 34, "#9aa3a8", OUT, 1.6)
        for k in range(1, 7):
            b += L(Wv * 0.32, T0 - 4 + k * (Hv - 34) / 7, Wv * 0.68, T0 - 4 + k * (Hv - 34) / 7, "#6b7378", 1.1)
        b += B(Wv * 0.12, T0 - 60, Wv * 0.76, 22, 50, WH, WF)
        b += B(Wv * 0.12, T0 + Hv - 76, Wv * 0.76, 22, 50, WH, WF)
        b += R(Wv * 0.44, T0 - 40, Wv * 0.12, Hv - 50, WH, OUT, 2)
        b += R(Wv * 0.45, T0 - 38, Wv * 0.1, 6, AC, None, 0)
        b += B(Wv * 0.36, T0 + Hv * 0.38, Wv * 0.28, 22, 30, WH, WF)
        b += C(Wv * 0.82, T0 - 44, 12, STEEL, OUT, 1.4) + C(Wv * 0.82, T0 - 44, 6, None, "#5a6268", 1.1)
        b += pendant(Wv - 30, T0 + Hv * 0.5, 24, 34)
        tw, lamp = tower(Wv * 0.2, T0 - 80)
        b += tw
        work = [Wv * 0.5, T0 + Hv * 0.5]
    elif table:
        # открытый: колонна вверху, стол вдоль вниз
        b += R(Wv * 0.25, T0 + 10, Wv * 0.5, Hv - 26, "#5c6267", OUT, 2)
        b += R(Wv * 0.3, T0 + 18, Wv * 0.4, Hv - 50, "#8b9296", OUT, 1.6)
        for k in range(1, 6):
            b += L(Wv * 0.3, T0 + 18 + k * (Hv - 50) / 6, Wv * 0.7, T0 + 18 + k * (Hv - 50) / 6, "#6b7378", 1.1)
        b += B(Wv * 0.18, T0 - 50, Wv * 0.64, 34, z, WH, WF)
        b += B(Wv * 0.3, T0 - 30, Wv * 0.4, 18, 30, WH, WF)
        b += R(Wv * 0.45, T0 + 18, 10, 14, "#c9ccce", OUT, 1)
        if magazine:
            b += E(Wv * 0.12, T0 - 20, 9, 26, "#7b8286", OUT, 1.6)
        if cabinets:
            b += cabinet(Wv - 30, T0 + Hv - 30, 24, 26, 70)
        b += pendant(4, T0 + Hv * 0.55, 22, 32)
        tw, lamp = tower(Wv * 0.8, T0 - 70)
        b += tw
        work = [Wv * 0.5, T0 + 30]
    else:
        b += B(8, T0 - 50 - z + 64, Wv - 30, Hv - 10, z, WH, WF)
        b += window(18, T0 - 38 - z + 64, Wv * 0.5, Hv - 40)
        cx = 18 + Wv * 0.25
        b += R(cx - 9, T0 - 30 - z + 64, 18, 20, STEEL, OUT, 1.2) + R(cx - 4, T0 - 10 - z + 64, 8, 14, "#c9ccce", OUT, 1)
        b += R(Wv - 26, T0 - 46 - z + 64, 6, Hv - 20, AC, None, 0, 1)
        if magazine:
            b += C(Wv - 34, T0 - 10, 13, STEEL, OUT, 1.4) + C(Wv - 34, T0 - 10, 6, None, "#5a6268", 1.1)
        b += pendant(Wv - 30, T0 + Hv - 120, 22, 34)
        tw, lamp = tower(Wv - 44, T0 - 66 - z + 64)
        b += tw
        work = [cx, T0 + 6 - z + 64]
    b += R(12, T0 + Hv - 12, Wv - 28, 10, AC, OUT, 1.2)
    save(key, wt, ht, T0, b, {"lamp": lamp, "work": work, "in": [8, T0 + Hv - 24], "out": [8, T0 + Hv * 0.5 - 10]})


# ================================================================ Пантера-2600 (Puma 1000MB), 3×2

def panther():
    key, wt, ht = "cnc_panther", 3, 2
    W, H = wt * 64, ht * 64
    T0 = 70
    WH, WF = "#eceeee", "#d0d4d5"
    AC = "#e2752c"
    yb = T0 + H - 6
    z = 74
    b = ga.shadow(14, T0 - 10, W - 8, H + 8)
    # транспортёр стружки из правого торца назад-вверх
    b += conveyor(W - 70, T0 + 30, W - 34, T0 - 30, 14)
    # длинный низкий кожух
    top = yb - z - 44
    b += B(4, top, W - 42, 44, z, WH, WF)
    b += R(10, top + 4, W - 54, 6, AC, None, 0, 1)
    # кожух бабки — выше и с жалюзи
    b += B(4, top - 18, 46, 30, z + 32, "#dfe2e3", "#c3c8ca")
    b += louvers(10, top - 10, 34, 3, 5, "#b3b9bc")
    b += louvers(10, yb - 40, 34, 5, 5, "#b3b9bc")
    # две раздвижные двери с длинными окнами
    dy = top + 50
    b += window(54, dy, (W - 100) * 0.5, z - 34)
    b += window(54 + (W - 100) * 0.5 + 2, dy, (W - 100) * 0.5 - 4, z - 34)
    b += R(52 + (W - 100) * 0.5 - 4, dy + 16, 4, 12, DARK, None, 0) + R(54 + (W - 100) * 0.5 + 6, dy + 16, 4, 12, DARK, None, 0)
    # внутри: патрон, деталь, револьвер, задняя бабка
    b += R(58, dy + 8, 8, 24, "#a2abb0", OUT, 1, 2)
    b += R(66, dy + 16, 56, 7, "#c9ccce", OUT, 1)
    b += turret(96, dy + 30, 9, "#8e979c")
    b += R(W - 64, dy + 12, 14, 14, "#b7bdc0", OUT, 1)
    # цоколь
    b += R(8, yb - 10, W - 50, 10, "#4b5257", OUT, 1.4)
    # пульт на поворотном кронштейне у бабки
    b += L(48, top - 2, 64, top - 14, DARK, 3) + L(64, top - 14, 64, top + 2, DARK, 3)
    b += pendant(52, top - 4, 28, 40)
    tw, lamp = tower(28, top - 38)
    b += tw
    an = {"lamp": lamp, "work": [92, dy + 20], "in": [W - 52, yb - 2], "out": [18, yb - 2], "screen": [66, top + 6]}
    save(key, wt, ht, T0, b, an)
    # со спины
    bb = ""
    top_b = yb - z - 44
    bb += B(4, top_b, W - 42, 44, z, "#d8dbdc", "#bcc1c3")
    bb += B(4, top_b - 18, 46, 30, z + 32, "#d2d6d7", "#b6bbbd")
    for k in range(6):
        bb += L(60, top_b + 52 + k * 6, W - 60, top_b + 52 + k * 6, "#a7adb0", 1.8)
    bb += R(8, yb - 10, W - 50, 10, "#4b5257", OUT, 1.4)
    bb += conveyor(W - 70, yb - 34, W - 34, top_b - 4, 14)
    b = ga.shadow(14, T0 - 10, W - 8, H + 8) + mirror(bb, W)
    tw, lamp = tower(W - 28, top_b - 38)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 92, top_b + 70], "in": [52, yb - 2], "out": [W - 30, yb - 2]})
    _side_lathe(key + "_v", ht, wt, None, None, AC, encl=(WH, WF), conveyor_=True)


# ================================================================ Ханган HL-1600 (Hankook Protec 9NC), 4×2

def hangan():
    key, wt, ht = "cnc_hangan", 4, 2
    W, H = wt * 64, ht * 64
    T0 = 64
    GT, GF = "#9fb39a", "#7e9479"          # серо-зелёная
    CR = "#e3dcc4"
    AC = "#c94a3a"
    yb = T0 + H - 6
    b = ga.shadow(14, T0 - 10, W - 8, H + 8)
    # поддон стружки и станина
    b += R(4, yb - 22, W - 10, 22, "#4b5257", OUT, 2)
    b += bed_chips(78, yb - 46, W - 120, 22)
    b += R(70, yb - 62, W - 80, 18, "#8b9296", OUT, 2)
    b += L(70, yb - 56, W - 10, yb - 56, "#b2b9bd", 1.4)
    # щиток на рельсе за станиной (только над суппортом)
    b += R(70, yb - 128, W - 80, 5, STEEL_D, OUT, 1.1)
    b += R(150, yb - 124, 70, 64, CR, OUT, 1.6, 2)
    b += window(158, yb - 116, 54, 30)
    b += R(150, yb - 124, 70, 6, AC, None, 0)
    # массивная передняя бабка
    b += B(4, yb - 126, 70, 26, 104, GT, GF)
    b += louvers(12, yb - 92, 54, 4, 6, "#6c8068")
    b += R(10, yb - 120, 58, 6, AC, None, 0, 1)
    # огромный патрон (4-кулачковый) — с ребра
    cx = 74
    b += chuck_side(cx, yb - 78, 30)
    # длинный вал в центрах
    b += R(cx + 16, yb - 84, W - cx - 76, 12, STEEL_L, OUT, 1.3)
    b += L(cx + 18, yb - 81, W - 64, yb - 81, "#ffffff", 1.1, 0.6)
    # люнет
    b += P(f"M{cx + 50} {yb - 60}v-30q0 -10 10 -10h8q10 0 10 10v30z", GT, OUT, 1.6)
    b += C(cx + 64, yb - 78, 8, None, OUT, 1.6)
    # суппорт с четырёхпозиционным резцедержателем
    b += B(178, yb - 66, 44, 12, 16, "#7e8a80", "#636e64")
    b += B(188, yb - 82, 22, 10, 14, STEEL, STEEL_D)
    b += L(196, yb - 74, 192, yb - 80, "#e8e0c0", 3)
    # задняя бабка
    b += B(W - 66, yb - 96, 56, 16, 40, GT, GF)
    b += R(W - 82, yb - 84, 18, 9, "#aab1b5", OUT, 1.1)
    b += C(W - 14, yb - 66, 6, None, "#c9ccce", 1.8)
    # пульт на поворотной штанге у бабки
    b += L(68, yb - 124, 96, yb - 140, DARK, 3) + L(96, yb - 140, 96, yb - 128, DARK, 3)
    b += pendant(84, yb - 130, 26, 38)
    tw, lamp = tower(20, yb - 150)
    b += tw
    an = {"lamp": lamp, "chuck": [cx, yb - 108, 16, 60], "tool": [192, yb - 80], "bar": [100, yb - 14],
          "out": [W - 40, yb - 4], "in": [18, yb - 4], "work": [192, yb - 80]}
    save(key, wt, ht, T0, b, an)
    # со спины
    bb = ""
    bb += R(4, yb - 22, W - 10, 22, "#4b5257", OUT, 2)
    bb += R(70, yb - 62, W - 80, 40, "#6b7378", OUT, 2)
    bb += B(4, yb - 126, 70, 26, 104, GT, GF) + louvers(12, yb - 92, 54, 6, 6, "#6c8068")
    bb += B(W - 66, yb - 96, 56, 16, 40, GT, GF)
    bb += R(70, yb - 128, W - 80, 5, STEEL_D, OUT, 1.1)
    bb += R(150, yb - 124, 70, 64, CR, OUT, 1.6, 2)
    bb += B(178, yb - 66, 44, 12, 16, "#7e8a80", "#636e64")
    b = ga.shadow(14, T0 - 10, W - 8, H + 8) + mirror(bb, W)
    tw, lamp = tower(W - 20, yb - 150)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 192, yb - 80], "in": [W - 18, yb - 4], "out": [40, yb - 4]})
    _side_lathe(key + "_v", ht, wt, GT, GF, AC, open_=True, big=True)


# ================================================================ Майдэй MBL-400 (Myday MBL-400), 2×2

def maiday():
    key, wt, ht = "cnc_maiday", 2, 2
    W, H = wt * 64, ht * 64
    T0 = 74
    WH, WF = "#f1f2f0", "#d5d9d6"
    LOW = "#4a5560"
    AC = "#2a9d9a"
    yb = T0 + H - 6
    z = 78
    b = ga.shadow(14, T0 - 10, W - 8, H + 8)
    top = yb - z - 40
    ew = W - 34
    # кожух со скошенной передней кромкой (наклонная станина)
    b += R(4, top, ew, 34, WH, OUT, 2)
    b += Q([(4, top + 34), (4 + ew, top + 34), (4 + ew, top + 46), (4, top + 46)], "#e2e5e2", OUT, 2)
    b += R(4, top + 46, ew, z - 6, WF, OUT, 2)
    b += R(4, yb - 22, ew, 22, LOW, OUT, 2)
    b += R(8, top + 36, ew - 8, 6, AC, None, 0, 1)
    # одна большая раздвижная дверь с окном
    b += window(10, top + 52, ew * 0.66, z - 34)
    b += R(10 + ew * 0.66 + 2, top + 58, 4, 22, DARK, None, 0, 1)
    b += R(18, top + 62, 10, 18, "#a2abb0", OUT, 1, 2) + R(28, top + 68, 30, 6, "#c9ccce", OUT, 1)
    b += turret(46, top + 86, 8, "#8e979c")
    # встроенная панель справа
    b += R(4 + ew * 0.72, top + 50, ew * 0.26, z - 30, PANEL_D, OUT, 1.6, 2)
    b += pendant(4 + ew * 0.72 + 2, top + 52, ew * 0.26 - 4, 46)
    # бак СОЖ сбоку
    b += B(W - 30, yb - 46, 24, 10, 36, "#5e6a74", "#4b5660")
    tw, lamp = tower(ew - 10, top - 20)
    b += tw
    an = {"lamp": lamp, "work": [40, top + 72], "in": [W - 24, yb - 2], "out": [14, yb - 2], "screen": [4 + ew * 0.85, top + 60]}
    save(key, wt, ht, T0, b, an)
    bb = ""
    bb += R(4, top, ew, 34, "#e2e5e2", OUT, 2) + R(4, top + 34, ew, z + 6, "#c7cbc8", OUT, 2)
    bb += R(4, yb - 22, ew, 22, LOW, OUT, 2)
    for k in range(6):
        bb += L(14, top + 46 + k * 7, 14 + ew * 0.5, top + 46 + k * 7, "#a7adb0", 1.8)
    bb += R(ew * 0.62, top + 46, ew * 0.3, 34, STEEL, OUT, 1.3, 2)
    bb += B(W - 30, yb - 46, 24, 10, 36, "#5e6a74", "#4b5660")
    b = ga.shadow(14, T0 - 10, W - 8, H + 8) + mirror(bb, W)
    tw, lamp = tower(W - ew + 10, top - 20)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 40, top + 72], "in": [24, yb - 2], "out": [W - 16, yb - 2]})
    _side_lathe(key + "_v", ht, wt, None, None, AC, encl=(WH, WF))


# ================================================================ 65А60, 3×2 — открытый советский центр

def c65a60():
    key, wt, ht = "cnc_65a60", 3, 2
    W, H = wt * 64, ht * 64
    T0 = 124
    GT, GF = "#a9b6a3", "#8a9784"
    AC = "#3d5a7a"
    yb = T0 + H - 6
    b = ga.shadow(14, T0 - 34, W - 8, H + 30)
    # шкафы электроавтоматики сзади справа
    b += cabinet(W - 64, T0 + 24, 30, 16, 108)
    b += cabinet(W - 34, T0 + 30, 30, 16, 108)
    # колонна
    cx0 = 62
    b += B(cx0, T0 - 76, 58, 22, 132, GT, GF)
    b += R(cx0 + 6, T0 - 70, 46, 6, AC, None, 0, 1)
    # шпиндельная бабка на колонне
    b += B(cx0 - 4, T0 - 40, 66, 14, 40, "#97a491", "#7b8875")
    b += R(cx0 + 24, T0 + 14, 14, 14, STEEL, OUT, 1.2) + R(cx0 + 27, T0 + 28, 8, 12, "#c9ccce", OUT, 1)
    # цепной магазин инструментов слева от колонны
    b += R(10, T0 - 62, 44, 104, "#7b8286", OUT, 2, 18)
    b += R(16, T0 - 56, 32, 92, "#5c6267", OUT, 1.2, 14)
    for k in range(8):
        yy = T0 - 50 + k * 11
        b += R(14, yy, 6, 6, "#c9ccce", OUT, 0.8) + R(44, yy, 6, 6, "#c9ccce", OUT, 0.8)
    # станина и крестовый стол
    b += R(16, yb - 30, W - 50, 30, GF, OUT, 2)
    b += B(8, yb - 54, W - 48, 16, 10, "#8b9296", "#6f777b")
    for k in range(5):
        b += L(14, yb - 52 + k * 3, W - 46, yb - 52 + k * 3, "#6b7378", 1)
    b += R(cx0 + 4, yb - 66, 40, 14, "#b9a77a", OUT, 1.4)           # заготовка-корпус
    b += C(28, yb - 15, 6, None, "#c9ccce", 2) + C(W - 52, yb - 15, 6, None, "#c9ccce", 2)
    # пульт на стойке спереди справа
    b += R(W - 54, yb - 40, 6, 40, DARK, OUT, 1)
    b += pendant(W - 66, yb - 84, 30, 44, seg=True)
    tw, lamp = tower(cx0 + 50, T0 - 104)
    b += tw
    an = {"lamp": lamp, "work": [cx0 + 31, T0 + 44], "in": [W - 30, yb - 2], "out": [14, yb - 2], "screen": [W - 51, yb - 76]}
    save(key, wt, ht, T0, b, an)
    bb = ""
    bb += R(16, yb - 30, W - 50, 30, GF, OUT, 2)
    bb += B(8, yb - 54, W - 48, 16, 10, "#8b9296", "#6f777b")
    bb += B(cx0, T0 - 76, 58, 22, 132, GT, GF) + louvers(cx0 + 10, T0 - 10, 38, 6, 6, "#7b8875")
    bb += R(10, T0 - 62, 44, 104, "#7b8286", OUT, 2, 18)
    bb += cabinet(W - 64, yb + 4, 30, 16, 112) + cabinet(W - 34, yb + 4, 30, 16, 112)
    b = ga.shadow(14, T0 - 34, W - 8, H + 30) + mirror(bb, W)
    tw, lamp = tower(W - cx0 - 50, T0 - 104)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - cx0 - 31, T0 + 44], "in": [30, yb - 2], "out": [W - 14, yb - 2]})
    _side_box(key + "_v", ht, wt, GT, GF, AC, z=110, magazine=True, cabinets=True, table=True)


# ================================================================ Сайдвей ВМ-2215, 2×2 — фрезерный на станине

def sidway():
    key, wt, ht = "cnc_sidway", 2, 2
    W, H = wt * 64, ht * 64
    T0 = 110
    GT, GF = "#7aa08a", "#5d8370"
    AC = "#e2b73a"
    yb = T0 + H - 6
    b = ga.shadow(14, T0 - 34, W - 8, H + 30)
    # колонна сзади
    b += B(30, T0 - 64, 52, 18, 120, GT, GF)
    # голова (ползун) с двигателем сверху
    b += B(24, T0 - 54, 64, 14, 36, "#e9ebe8", "#ccd0cc")
    b += R(30, T0 - 50, 52, 5, AC, None, 0, 1)
    b += R(46, T0 - 84, 22, 30, "#4b5660", OUT, 1.6, 4)
    for k in range(4):
        b += L(48, T0 - 78 + k * 6, 66, T0 - 78 + k * 6, "#6b7884", 1.2)
    b += R(48, T0 - 4, 16, 14, STEEL, OUT, 1.2) + R(52, T0 + 10, 8, 14, "#c9ccce", OUT, 1)
    # поддон-ограждение стола
    b += R(6, yb - 46, W - 32, 46, "#5c6267", OUT, 2, 2)
    b += R(10, yb - 64, W - 40, 20, "#a8d0e0", OUT, 1.2, 2, 0.30)
    # стол с гармошками
    b += B(14, yb - 60, W - 48, 14, 10, "#8b9296", "#6f777b")
    for k in range(6):
        b += L(16 + k * 4, yb - 58, 16 + k * 4, yb - 48, "#2e3336", 1.2)
        b += L(W - 38 - k * 4, yb - 58, W - 38 - k * 4, yb - 48, "#2e3336", 1.2)
    b += R(40, yb - 70, 30, 12, "#b9a77a", OUT, 1.3)
    # пульт на поворотной консоли от колонны
    b += L(82, T0 - 30, 104, T0 - 30, DARK, 3) + L(104, T0 - 30, 104, T0 - 14, DARK, 3)
    b += pendant(92, T0 - 16, 28, 40)
    tw, lamp = tower(36, T0 - 90)
    b += tw
    an = {"lamp": lamp, "work": [56, T0 + 26], "in": [W - 24, yb - 2], "out": [14, yb - 2], "screen": [106, T0 - 8]}
    save(key, wt, ht, T0, b, an)
    bb = ""
    bb += R(6, yb - 46, W - 32, 46, "#5c6267", OUT, 2, 2)
    bb += B(30, T0 - 64, 52, 18, 120, GT, GF) + louvers(38, T0 - 20, 36, 6, 6, "#4f7360")
    bb += B(24, T0 - 54, 64, 14, 36, "#e9ebe8", "#ccd0cc")
    bb += R(46, T0 - 84, 22, 30, "#4b5660", OUT, 1.6, 4)
    bb += B(W - 34, yb - 50, 26, 12, 40, "#5e6a74", "#4b5660")
    b = ga.shadow(14, T0 - 34, W - 8, H + 30) + mirror(bb, W)
    tw, lamp = tower(W - 36, T0 - 90)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 56, T0 + 26], "in": [24, yb - 2], "out": [W - 14, yb - 2]})
    _side_box(key + "_v", ht, wt, GT, GF, AC, z=96, table=True)


# ================================================================ Хартвуд VMC-3260 (Hartford HSA-320), 3×2 — портал

def hartwood():
    key, wt, ht = "cnc_hartwood", 3, 2
    W, H = wt * 64, ht * 64
    T0 = 140
    WH, WF = "#f0f1f1", "#d3d7d8"
    AC = "#2f6ab0"
    yb = T0 + H - 6
    b = ga.shadow(14, T0 - 50, W - 8, H + 46)
    # стойки портала (сзади), траверса сверху
    b += B(14, T0 - 96, 30, 20, 150, WH, WF)
    b += B(W - 62, T0 - 96, 30, 20, 150, WH, WF)
    b += B(8, T0 - 110, W - 34, 22, 36, WH, WF)
    b += R(14, T0 - 84, W - 46, 7, AC, None, 0, 1)
    # каретка и вертикальный ползун со шпинделем
    b += B(76, T0 - 100, 44, 14, 50, "#e3e6e7", "#c6cbcd")
    b += R(88, T0 - 36, 20, 58, "#d6dadb", OUT, 1.8)
    b += R(92, T0 + 22, 12, 12, STEEL, OUT, 1.2) + R(95, T0 + 34, 6, 10, "#c9ccce", OUT, 1)
    # магазин инструментов на правой стойке
    b += C(W - 47, T0 - 30, 16, "#9aa3a8", OUT, 1.6) + C(W - 47, T0 - 30, 8, None, "#5a6268", 1.2)
    # длинный стол с плитой и шнеки стружки
    b += R(6, yb - 26, W - 30, 26, "#4b5257", OUT, 2)
    for k in range(9):
        b += P(f"M{14 + k * 18} {yb - 8}q5 -8 10 0", None, "#8c949a", 1.6)
    b += B(16, yb - 52, W - 50, 22, 12, "#8b9296", "#6f777b")
    for k in range(1, 8):
        b += L(16 + k * (W - 50) / 8, yb - 50, 16 + k * (W - 50) / 8, yb - 32, "#6b7378", 1)
    b += R(56, yb - 62, 84, 14, "#b9a77a", OUT, 1.3)                     # крупная плита-заготовка
    # площадка с лесенкой у левой стойки
    b += R(2, T0 + 8, 16, 4, "#e2b73a", OUT, 1)
    b += L(4, T0 + 12, 4, yb - 4, "#e2b73a", 2) + L(16, T0 + 12, 16, yb - 4, "#e2b73a", 2)
    for k in range(5):
        b += L(4, T0 + 24 + k * 14, 16, T0 + 24 + k * 14, "#e2b73a", 1.6)
    # пульт на поворотной штанге справа
    b += L(W - 32, T0 + 0, W - 20, T0 + 0, DARK, 3)
    b += pendant(W - 32, T0 + 2, 28, 42)
    tw, lamp = tower(W - 74, T0 - 128)
    b += tw
    an = {"lamp": lamp, "work": [98, T0 + 44], "in": [W - 30, yb + 2], "out": [26, yb + 2], "screen": [W - 18, T0 + 10]}
    save(key, wt, ht, T0, b, an)
    bb = ""
    bb += R(6, yb - 26, W - 30, 26, "#4b5257", OUT, 2)
    bb += B(16, yb - 52, W - 50, 22, 12, "#8b9296", "#6f777b")
    bb += B(14, T0 - 96, 30, 20, 150, "#e3e5e5", "#c6cacb")
    bb += B(W - 62, T0 - 96, 30, 20, 150, "#e3e5e5", "#c6cacb")
    bb += B(8, T0 - 110, W - 34, 22, 36, "#e3e5e5", "#c6cacb")
    bb += B(76, T0 - 100, 44, 14, 50, "#d6d9da", "#bcc1c3")
    bb += R(88, T0 - 36, 20, 58, "#c9cdce", OUT, 1.8)
    b = ga.shadow(14, T0 - 50, W - 8, H + 46) + mirror(bb, W)
    tw, lamp = tower(74, T0 - 128)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 98, T0 + 44], "in": [30, yb + 2], "out": [W - 26, yb + 2]})
    _side_box(key + "_v", ht, wt, WH, WF, AC, portal=True)


# ================================================================ Мингер VM-540 (Mynx 750/50), 2×2 — куб в кожухе

def minger():
    key, wt, ht = "cnc_minger", 2, 2
    W, H = wt * 64, ht * 64
    T0 = 110
    WH, WF = "#e9eaea", "#cbcfd0"
    AC = "#d9a62a"
    yb = T0 + H - 6
    z = 124
    b = ga.shadow(14, T0 - 46, W - 8, H + 42)
    top = yb - z - 40
    ew = W - 36
    # транспортёр стружки сзади, торчит над кожухом
    b += conveyor(ew - 34, top + 20, ew - 4, top - 24, 12)
    # магазин инструментов — барабан на левом боку
    b += R(2, top + 12, 14, 56, "#9aa3a8", OUT, 1.6, 6)
    b += L(9, top + 18, 9, top + 62, "#5a6268", 1.4)
    # кожух
    b += B(12, top, ew, 40, z, WH, WF)
    b += R(18, top + 6, ew - 12, 7, AC, None, 0, 1)
    b += R(12, yb - 16, ew, 16, "#4b5257", OUT, 1.6)
    # две распашные двери с окнами
    dy = top + 50
    dw = (ew - 20) / 2
    b += window(18, dy, dw - 2, z - 58)
    b += window(18 + dw + 2, dy, dw - 2, z - 58)
    b += R(18 + dw - 6, dy + 24, 4, 16, DARK, None, 0, 1) + R(18 + dw + 4, dy + 24, 4, 16, DARK, None, 0, 1)
    b += R(36, dy + 4, 16, 22, STEEL, OUT, 1.2) + R(40, dy + 26, 8, 12, "#c9ccce", OUT, 1)
    b += R(24, dy + z - 76, dw * 1.6, 8, "#7b8286", OUT, 1.1)
    # пульт справа — наклонная панель на кожухе
    b += P(f"M{W - 26} {top + 46}h20l-2 54h-18z", PANEL, OUT, 1.6)
    b += R(W - 23, top + 50, 14, 14, "#1d2a34", OUT, 1) + R(W - 21, top + 52, 10, 10, "#6fd0e0", None, 0, 1, 0.8)
    for yy in range(3):
        for xx in range(3):
            b += R(W - 23 + xx * 5, top + 70 + yy * 6, 3.6, 3.6, ["#c9ccce", "#e2b73a", "#6fbf86"][(xx + yy) % 3], None, 0, 0.6)
    tw, lamp = tower(ew - 18, top - 20)
    b += tw
    an = {"lamp": lamp, "work": [44, dy + 40], "in": [W - 24, yb - 2], "out": [22, yb - 2], "screen": [W - 16, top + 57]}
    save(key, wt, ht, T0, b, an)
    bb = ""
    bb += conveyor(36, yb - 30, 6, yb - 60, 12)
    bb += B(12, top, ew, 40, z, "#d8dbdc", "#bcc1c3")
    for k in range(8):
        bb += L(22, top + 50 + k * 8, 22 + ew * 0.5, top + 50 + k * 8, "#a7adb0", 2)
    bb += R(14 + ew * 0.6, top + 50, ew * 0.32, 50, STEEL, OUT, 1.4, 2)
    bb += R(12, yb - 16, ew, 16, "#4b5257", OUT, 1.6)
    bb += R(2, top + 12, 14, 56, "#9aa3a8", OUT, 1.6, 6)
    b = ga.shadow(14, T0 - 46, W - 8, H + 42) + mirror(bb, W)
    tw, lamp = tower(W - ew + 18, top - 20)
    b += tw
    save(key + "_b", wt, ht, T0, b, {"lamp": lamp, "work": [W - 44, dy + 40], "in": [24, yb - 2], "out": [W - 22, yb - 2]})
    _side_box(key + "_v", ht, wt, WH, WF, AC, z=110, magazine=True)


def run(module):
    global ga
    ga = module
    lathe_16a20f3()
    panther()
    hangan()
    maiday()
    c65a60()
    sidway()
    hartwood()
    minger()
