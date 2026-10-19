#!/usr/bin/env python3
"""1.33: импорт нового набора портретов (слои 1024×1024 на общем холсте) в assets/portrait2/.

Запуск (из корня проекта):
    python3 -I tools/import_portraits_133.py <папка_набора> [размер=512]
где <папка_набора> — распакованный promzona_portrait_constructor (в нём assets/*.png).

Что делает:
  * каждый слой уменьшается до размера×размер (Lanczos, по премультиплицированной альфе — без тёмной каймы),
    холст и выравнивание сохраняются: слои накладываются от (0,0), без обрезки;
  * base_template не копируется (только для выравнивания), но служит заливкой кожи в вырезах одежды;
  * eyes_*: веки и кожа вокруг глаз (нейтральный серый снаружи контура) выносятся в eyes_*_lid — их красим цветом
    кожи; радужка — в eyes_*_iris (красим цветом глаз); белки и контур остаются в eyes_*;
  * collar_*: изнанка одежды в вырезе (задняя часть воротника) выносится в collar_*_back — её рисуем позади шеи;
    kerchief_f_g — серая копия косынки (красится цветом головного убора);
    грудь из base_template в вырезе ниже шеи головы — collar_*_skin (иначе просвечивает фон), красится цветом кожи;
  * пишет .import (текстура, без сжатия с потерями, мипмапы) и layers.json — список слоёв с рамками
    (в пикселях итогового холста), чтобы игра рисовала только непустую часть.
"""
import json
import os
import sys
from collections import deque

import numpy as np
from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portrait2")

IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=0
compress/high_quality=false
compress/lossy_quality=0.7
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def lum(a):
    return a[..., :3].astype(np.int32).mean(-1)


def sat(a):
    c = a[..., :3].astype(np.int32)
    return c.max(-1) - c.min(-1)


def flood(passable, seeds):
    """Заливка по 4-соседству: какие клетки достижимы из seeds через passable."""
    h, w = passable.shape
    seen = np.zeros_like(passable, dtype=bool)
    q = deque()
    for (y, x) in seeds:
        if 0 <= y < h and 0 <= x < w and passable[y, x] and not seen[y, x]:
            seen[y, x] = True
            q.append((y, x))
    while q:
        y, x = q.popleft()
        for ny, nx in ((y - 1, x), (y + 1, x), (y, x - 1), (y, x + 1)):
            if 0 <= ny < h and 0 <= nx < w and not seen[ny, nx] and passable[ny, nx]:
                seen[ny, nx] = True
                q.append((ny, nx))
    return seen


def split_eyes(a):
    """-> (глаза: белки+контур, веки: кожа, радужка)."""
    al = a[..., 3]
    L = lum(a)
    # снаружи контура глаза: прозрачное или светлее линий; тёмные линии — стена
    outside_pass = (al < 40) | (L >= 70)
    h, w = al.shape
    seeds = [(0, x) for x in range(w)] + [(h - 1, x) for x in range(w)] + [(y, 0) for y in range(h)] + [(y, w - 1) for y in range(h)]
    outside = flood(outside_pass, seeds)
    opaque = al >= 1
    lid = outside & opaque & (L >= 70)
    inner = (~outside) & opaque & (L >= 70)
    iris = inner & (L < 178)
    # тень от века на белке — узкая полоса сверху; радужка — крупное пятно: оставляем только толстые места
    from_iris = np.zeros_like(iris)
    k = 4
    pad = np.pad(iris, k)
    cnt = np.zeros(iris.shape, np.int32)
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            cnt += pad[k + dy:k + dy + h, k + dx:k + dx + w]
    core = cnt >= (2 * k + 1) ** 2 * 0.8
    # расширяем ядро обратно, но только внутри iris
    pad = np.pad(core, k)
    grow = np.zeros_like(core)
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            grow |= pad[k + dy:k + dy + h, k + dx:k + dx + w]
    from_iris = grow & iris
    base = a.copy()
    lid_l = np.zeros_like(a)
    iris_l = np.zeros_like(a)
    lid_l[lid] = a[lid]
    base[lid, 3] = 0
    iris_l[from_iris] = a[from_iris]
    # радужка остаётся и в базе (если цвет глаз не задан — серые глаза как в наборе)
    return base, lid_l, iris_l


# Внутренняя сторона одежды за шеей (задняя часть воротника, подкладка в вырезе): рисуется ПОЗАДИ шеи.
# Многоугольники в координатах исходного холста 1024 подобраны по рисунку (tools/import_portraits_133.py),
# у остальных воротников вырез прозрачный и так.
BACK_POLYS = {
    "collar_robe_m": [(395, 672), (650, 672), (650, 750), (620, 757), (600, 775), (592, 790), (570, 800), (548, 815), (520, 800), (505, 787), (500, 775), (480, 762), (450, 752), (420, 730), (407, 702), (395, 690)],
    "collar_vest_m": [(370, 672), (652, 672), (652, 690), (632, 700), (634, 720), (630, 745), (620, 760), (600, 770), (570, 777), (535, 782), (520, 790), (497, 810), (490, 810), (475, 800), (455, 787), (430, 780), (405, 772), (380, 755), (370, 750)],
    "collar_robe_f": [(400, 672), (650, 672), (642, 700), (620, 767), (595, 810), (570, 850), (540, 880), (522, 900), (504, 880), (480, 850), (455, 810), (430, 767), (408, 705)],
    "collar_vest_f": [(390, 672), (605, 672), (598, 700), (580, 735), (555, 765), (530, 787), (502, 812), (470, 790), (442, 770), (415, 740), (393, 705)],
    "collar_sweater_m": [(335, 672), (695, 672), (695, 727), (650, 735), (600, 743), (550, 749), (500, 749), (450, 747), (420, 743), (370, 736), (335, 728)],
    "collar_sweater_f": [(385, 672), (645, 672), (640, 695), (615, 712), (560, 721), (500, 722), (450, 719), (415, 710), (390, 698)],
    "collar_firefighter_f": [(385, 672), (650, 672), (645, 705), (600, 725), (580, 735), (555, 760), (540, 780), (505, 782), (490, 770), (470, 755), (450, 738), (420, 720), (392, 705)],
}
CHEST_Y = 770   ## выше грудь и шею закрывает сама голова (её нижний край — до y≈819)


def poly_mask(poly, h, w):
    from PIL import ImageDraw
    m = Image.new("L", (w, h), 0)
    ImageDraw.Draw(m).polygon(poly, fill=255)
    return np.asarray(m) > 0


def split_collar(name, a, tmpl):
    """-> (одежда спереди, изнанка за шеей или None, кожа в вырезе или None)."""
    h, w = a.shape[:2]
    back = None
    front = a.copy()
    mask = np.zeros((h, w), bool)
    if name in BACK_POLYS:
        mask = poly_mask(BACK_POLYS[name], h, w) & (a[..., 3] > 0)
        back = np.zeros_like(a)
        back[mask] = a[mask]
        front[mask, 3] = 0
    al = front[..., 3].astype(np.int32)
    # вырез ниже шеи головы: прозрачное между левым и правым краем одежды — грудь из base_template
    hole = np.zeros((h, w), bool)
    for y in range(CHEST_Y, h):
        xs = np.nonzero(al[y, 300:724] > 128)[0] + 300
        left = xs[xs < 512]
        right = xs[xs > 512]
        if left.size == 0 or right.size == 0:
            continue
        x0, x1 = left.max(), right.min()
        if x1 - x0 < 2:
            continue
        seg = np.arange(x0, x1 + 1)
        hole[y, seg[al[y, seg] < 250]] = True
    hole |= mask
    hole[:CHEST_Y] = False
    skin = None
    if hole.sum() > 200:
        k = 3   # чуть шире — край всё равно под одеждой
        pad = np.pad(hole, k)
        g = np.zeros_like(hole)
        for dy in range(-k, k + 1):
            for dx in range(-k, k + 1):
                g |= pad[k + dy:k + dy + h, k + dx:k + dx + w]
        g[:CHEST_Y] = False
        g &= tmpl[..., 3] > 0
        skin = np.zeros_like(a)
        skin[g] = tmpl[g]
    return front, back, skin


FACE_BOX = (400, 340, 624, 600)   ## x0, y0, x1, y1: глаза, нос, рот — у причёсок там не должно быть отдельных черт


def drop_islands(a, box):
    """Убрать «острова» — куски слоя, целиком лежащие в box и не связанные с основной частью (сор после нарезки)."""
    al = a[..., 3] > 0
    x0, y0, x1, y1 = box
    inside = np.zeros_like(al)
    inside[y0:y1, x0:x1] = True
    seeds = list(zip(*np.nonzero(al & ~inside)))
    main = flood(al, seeds)
    isl = al & ~main
    out = a.copy()
    out[isl, 3] = 0
    return out, int(isl.sum())


def down(a, size):
    im = Image.fromarray(a, "RGBA")
    if size != im.width:
        im = im.resize((size, size), Image.LANCZOS)
    return im


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        sys.exit(1)
    src = sys.argv[1]
    if os.path.isdir(os.path.join(src, "assets")):
        src = os.path.join(src, "assets")
    size = int(sys.argv[2]) if len(sys.argv) > 2 else 512
    os.makedirs(OUT, exist_ok=True)
    names = sorted(f[:-4] for f in os.listdir(src) if f.endswith(".png"))
    raw = {n: np.asarray(Image.open(os.path.join(src, n + ".png")).convert("RGBA")).copy() for n in names}
    tmpl = raw["base_template"]
    out = {}
    for n in names:
        if n == "base_template":
            continue
        a = raw[n]
        if n.startswith("eyes_"):
            base, lid, iris = split_eyes(a)
            out[n] = base
            out[n + "_lid"] = lid
            out[n + "_iris"] = iris
        elif n.startswith("collar_"):
            front, back, skin = split_collar(n, a, tmpl)
            out[n] = front
            if back is not None:
                out[n + "_back"] = back
            if skin is not None:
                out[n + "_skin"] = skin
        elif n == "kerchief_f":
            # косынка в наборе красная; серая копия — чтобы красить цветом головного убора (как у человечка)
            out[n] = a
            g = a.copy()
            L = lum(a).astype(np.float32)
            op = a[..., 3] > 128
            ref = np.percentile(L[op], 85) if op.any() else 200.0
            v = np.clip(L * (200.0 / max(ref, 1.0)), 0, 255).astype(np.uint8)
            g[..., 0] = v
            g[..., 1] = v
            g[..., 2] = v
            out[n + "_g"] = g
        elif n.startswith("hair_") and n.endswith("_front"):
            out[n], cnt = drop_islands(a, FACE_BOX)
            if cnt:
                print("  %s: убрано лишних пикселей на лице: %d" % (n, cnt))
        else:
            out[n] = a
    # старые файлы, которых больше нет в наборе, — убрать (вместе с .import)
    for f in os.listdir(OUT):
        base = f.split(".png")[0] if ".png" in f else None
        if base is not None and base not in out:
            os.remove(os.path.join(OUT, f))
    meta = {"size": size, "src": 1024, "layers": {}}
    total = 0
    for n, a in sorted(out.items()):
        im = down(a, size)
        p = os.path.join(OUT, n + ".png")
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        ip = p + ".import"
        if not os.path.exists(ip):
            with open(ip, "w") as f:
                f.write(IMPORT_TMPL)
        al = np.asarray(im)[..., 3]
        ys, xs = np.nonzero(al > 0)
        bb = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if xs.size else [0, 0, 0, 0]
        meta["layers"][n] = bb
    with open(os.path.join(OUT, "layers.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("слоёв: %d, PNG: %.1f МБ -> %s" % (len(out), total / 1048576.0, OUT))


if __name__ == "__main__":
    main()
