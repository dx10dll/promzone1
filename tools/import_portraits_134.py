#!/usr/bin/env python3
"""1.34: импорт исправленного набора портретов (версия 2, слои 1024×1024 на общем холсте) в assets/portrait2/.

Запуск (из корня проекта):
    python3 -I tools/import_portraits_134.py <папка_набора> [размер=512] [--debug <файл.png>]
где <папка_набора> — распакованный promzona_portrait_constructor (в нём assets/*.png и masks/*.png).

Схема сборки — как в compose_example.py набора; обходные правки 1.33 (вырезание изнанок, удаление черты у
hair_slick_front, грудь из base_template, автоматическое выделение век) больше не нужны — всё это есть в PNG.
Что делает импорт:
  * каждый слой уменьшается до размер×размер (Lanczos, по премультиплицированной альфе), холст не обрезается;
    base_template и вспомогательные collar_*_skin не копируются;
  * head_*_cut — голова с альфой × masks/<head>_keep_face (когда рисуется дополнительная шея — она заменяет исходную);
  * masks/<collar>_skin_keep -> mask_<collar>_keep (ограничение тела одеждой; в игре — маска шейдера);
  * collar_*_skinpart — кожа выреза женских воротников (воротник × masks/<collar>_skin_mask), красится цветом кожи;
  * collar_*_fab / collar_*_inner_fab — серая версия одежды только по основной ткани (без рубашки под комбинезоном,
    галстука, светоотражающих полос, кожи выреза), яркость приведена к опорному серому — красится цветом спецовки;
  * cap и helmet — яркость приведена к опорному серому (красятся цветом головного убора);
    mask_hat_<убор> — где под убором прячутся волосы (выше полей);
  * eyes_*_iris — радужка (красится цветом глаз; сами eyes_* не красятся);
  * kerchief_f_g — серая копия косынки (красится цветом платка, как у человечка на карте);
  * пишет .import (текстура без потерь, мипмапы) и layers.json — рамки непустой части слоёв.
"""
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portrait2")
REF = 200.0

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

HATS = ["cap", "helmet", "welder_mask", "ushanka"]


def lum(a):
    return a[..., :3].astype(np.float32).mean(-1)


def sat(a):
    c = a[..., :3].astype(np.int32)
    return c.max(-1) - c.min(-1)


def fabric_mask(name, a):
    """Основная ткань одежды по цветному оригиналу (то, что красим цветом спецовки)."""
    L = lum(a)
    S = sat(a)
    c = a[..., :3].astype(np.int32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    op = a[..., 3] > 0
    kind = name.split("_")[1]
    # средняя яркость по окрестности: светлая рубашка остаётся светлой и в тени, ткань куртки/жилета — тёмная
    Lb = np.asarray(Image.fromarray(np.where(op, L, 0).astype(np.uint8)).filter(ImageFilter.BoxBlur(9))).astype(np.float32)
    Ob = np.asarray(Image.fromarray((op * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(9))).astype(np.float32) / 255.0
    Lm = Lb / np.maximum(Ob, 0.05)
    if kind == "overall":
        m = b > r + 6                                  # синий комбинезон, рубашка под ним — своя
    elif kind in ("jacket", "vest"):
        m = Lm < 140                                   # без светлой рубашки
    elif kind == "suit":
        rg = np.where(op, np.clip(r - g + 128, 0, 255), 128).astype(np.uint8)
        rgm = np.asarray(Image.fromarray(rg).filter(ImageFilter.BoxBlur(7))).astype(np.float32) - 128.0
        m = (Lm < 125) & (rgm < 16)                    # пиджак; рубашка и красный галстук — свои
    elif kind == "robe":
        m = (L > 135) | (L < 70)                       # белый халат; серая рубашка под ним — своя
        if name.endswith("_inner"):
            m = np.ones_like(op)
    elif kind == "firefighter":
        m = ~((r > 140) & (g > 120) & (b < 110))       # без жёлтых полос
    else:
        m = np.ones_like(op)                           # рубашка, свитер, рабочая рубашка с косынкой
    m = m & op
    # мелкие крапинки и штрихи внутри ткани — тоже ткань: закрыть дырочки
    im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    m2 = (np.asarray(im) > 127) & op
    return m2


def normalized_gray(g, m, factor=None):
    """Серая ткань: медиана яркости по маске -> опорный серый (200). Возвращает (rgba, коэффициент)."""
    L = lum(g)
    sel = m & (g[..., 3] > 128)
    if factor is None:
        med = float(np.median(L[sel])) if sel.any() else REF
        factor = float(np.clip(REF / max(med, 1.0), 0.8, 2.6))
    v = np.clip(L * factor, 0, 255).astype(np.uint8)
    out = g.copy()
    out[..., 0] = v
    out[..., 1] = v
    out[..., 2] = v
    out[..., 3] = (g[..., 3].astype(np.float32) * m).astype(np.uint8)
    return out, factor


def iris_of(a):
    """Радужка: средне-серое толстое пятно внутри глаза (без белков, ресниц и тонких теней)."""
    h, w = a.shape[:2]
    L = lum(a)
    iris = (a[..., 3] > 200) & (L >= 60) & (L < 178)
    k = 4
    pad = np.pad(iris, k)
    cnt = np.zeros(iris.shape, np.int32)
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            cnt += pad[k + dy:k + dy + h, k + dx:k + dx + w]
    core = cnt >= (2 * k + 1) ** 2 * 0.8
    pad = np.pad(core, k)
    grow = np.zeros_like(core)
    for dy in range(-k, k + 1):
        for dx in range(-k, k + 1):
            grow |= pad[k + dy:k + dy + h, k + dx:k + dx + w]
    out = np.zeros_like(a)
    sel = grow & iris
    out[sel] = a[sel]
    return out


def hat_clip(a):
    """Маска для волос под убором: 0 — волосы прячутся (выше полей убора и выше его макушки), 1 — видны."""
    h, w = a.shape[:2]
    al = a[..., 3] > 128
    cols = np.nonzero(al.any(0))[0]
    m = np.ones((h, w), np.float32)
    if cols.size == 0:
        return m
    x0, x1 = cols.min(), cols.max()
    top = np.nonzero(al.any(1))[0].min()
    for x in range(x0, x1 + 1):
        ys = np.nonzero(al[:, x])[0]
        if ys.size:
            m[: max(0, ys.max() - 6), x] = 0.0
    edge_l = np.nonzero(al[:, x0])[0].max()
    edge_r = np.nonzero(al[:, x1])[0].max()
    m[: max(top, min(edge_l, edge_r) - 40), :x0] = 0.0
    m[: max(top, min(edge_l, edge_r) - 40), x1 + 1:] = 0.0
    im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(4))
    return np.asarray(im).astype(np.float32) / 255.0


def gray_copy(a):
    g = a.copy()
    L = lum(a)
    op = a[..., 3] > 128
    ref = np.percentile(L[op], 85) if op.any() else REF
    v = np.clip(L * (REF / max(ref, 1.0)), 0, 255).astype(np.uint8)
    g[..., 0] = v
    g[..., 1] = v
    g[..., 2] = v
    return g


def down(a, size):
    im = Image.fromarray(a, "RGBA")
    if size != im.width:
        im = im.resize((size, size), Image.LANCZOS)
    return im


def down_l(m, size):
    im = Image.fromarray(np.clip(m * 255.0, 0, 255).astype(np.uint8) if m.dtype != np.uint8 else m, "L")
    if size != im.width:
        im = im.resize((size, size), Image.LANCZOS)
    return im


def main():
    args = [x for x in sys.argv[1:]]
    debug = None
    if "--debug" in args:
        i = args.index("--debug")
        debug = args[i + 1]
        del args[i:i + 2]
    if not args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    size = int(args[1]) if len(args) > 1 else 512
    adir = os.path.join(src, "assets")
    mdir = os.path.join(src, "masks")
    os.makedirs(OUT, exist_ok=True)
    names = sorted(f[:-4] for f in os.listdir(adir) if f.endswith(".png"))
    raw = {n: np.asarray(Image.open(os.path.join(adir, n + ".png")).convert("RGBA")).copy() for n in names}

    def mask(n):
        p = os.path.join(mdir, n + ".png")
        return np.asarray(Image.open(p).convert("L")).astype(np.float32) / 255.0 if os.path.exists(p) else None

    out = {}
    masks = {}
    dbg = []
    for n in names:
        a = raw[n]
        if n == "base_template" or n.endswith("_gray") or (n.startswith("collar_") and n.endswith("_skin")):
            continue
        if n.startswith("head_"):
            out[n] = a
            kf = mask(n + "_keep_face")
            if kf is not None:
                cut = a.copy()
                cut[..., 3] = (a[..., 3].astype(np.float32) * kf).astype(np.uint8)
                out[n + "_cut"] = cut
        elif n.startswith("eyes_") and not n.endswith("_lids"):
            out[n] = a
            out[n + "_iris"] = iris_of(a)
        elif n.startswith("collar_"):
            out[n] = a
            base = n[:-6] if n.endswith("_inner") else n
            sm = mask(base + "_skin_mask")
            fm = fabric_mask(n, a)
            if sm is not None:
                sp = a.copy()
                sp[..., 3] = (a[..., 3].astype(np.float32) * sm).astype(np.uint8)
                out[n + "_skinpart"] = sp
                fm = fm & (sm < 0.5)
            gname = n + "_gray"
            if gname in raw:
                if n.endswith("_inner"):
                    _, fct = normalized_gray(raw[base + "_gray"], fabric_mask(base, raw[base]))
                    fab, _ = normalized_gray(raw[gname], fm, fct)
                else:
                    fab, fct = normalized_gray(raw[gname], fm)
                out[n + "_fab"] = fab
                if debug:
                    dbg.append((n, a, fm))
            keep = mask(n + "_skin_keep")
            if keep is not None and not n.endswith("_inner"):
                masks["mask_%s_keep" % n] = keep
        elif n in ("cap", "helmet"):
            g, _ = normalized_gray(a, a[..., 3] > 0)
            g[..., 3] = a[..., 3]
            out[n] = g
            masks["mask_hat_" + n] = hat_clip(a)
        elif n in HATS:
            out[n] = a
            masks["mask_hat_" + n] = hat_clip(a)
        elif n == "kerchief_f":
            out[n] = a
            out[n + "_g"] = gray_copy(a)
        else:
            out[n] = a
    # старые файлы, которых больше нет в наборе, — убрать (вместе с .import)
    keep_names = set(out) | set(masks)
    for f in os.listdir(OUT):
        base = f.split(".png")[0] if ".png" in f else None
        if base is not None and base not in keep_names:
            os.remove(os.path.join(OUT, f))
    meta = {"size": size, "src": 1024, "version": 2, "layers": {}, "masks": sorted(masks)}
    total = 0
    for n, a in sorted(out.items()):
        im = down(a, size)
        p = os.path.join(OUT, n + ".png")
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        if not os.path.exists(p + ".import"):
            with open(p + ".import", "w") as f:
                f.write(IMPORT_TMPL)
        al = np.asarray(im)[..., 3]
        ys, xs = np.nonzero(al > 0)
        meta["layers"][n] = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if xs.size else [0, 0, 0, 0]
    for n, m in sorted(masks.items()):
        im = down_l(m, size)
        p = os.path.join(OUT, n + ".png")
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        if not os.path.exists(p + ".import"):
            with open(p + ".import", "w") as f:
                f.write(IMPORT_TMPL)
    with open(os.path.join(OUT, "layers.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("слоёв: %d, масок: %d, PNG: %.1f МБ -> %s" % (len(out), len(masks), total / 1048576.0, OUT))
    if debug and dbg:
        tiles = []
        for n, a, fm in dbg:
            t = a[640:1024, 40:984, :3].copy()
            t2 = t.copy()
            t2[fm[640:1024, 40:984]] = (t2[fm[640:1024, 40:984]] * 0.4 + np.array([255, 0, 255]) * 0.6).astype(np.uint8)
            tiles.append(np.concatenate([t, t2], 1))
        Image.fromarray(np.concatenate(tiles, 0)).resize((944, 192 * len(tiles))).save(debug)


if __name__ == "__main__":
    main()
