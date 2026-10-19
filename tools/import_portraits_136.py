#!/usr/bin/env python3
"""1.36: импорт набора портретов v3 (цельные основы «голова + шея + плечи», одежда по посадке) в assets/portrait2/.

Запуск (из корня проекта):
    python3 -I tools/import_portraits_136.py <папка_набора> [размер=512]
где <папка_набора> — распакованный promzona_portraits_v3 (bases/, clothes/, masks/, assets/, outfits.json).

Схема сборки — как в compose_example.py набора (см. README_CLAUDE_RU.md): изнанка одежды -> волосы сзади ->
цельная основа (альфа × masks/<одежда>_body_keep) -> веки, глаза, нос, рот, брови, морщины, борода ->
перед одежды -> волосы спереди, очки, серьги, головной убор. Никаких старых голов, шей, щёк и масок v2.

Что кладётся в игру (только то, что рисуется):
  * base_<посадка>_<m|f> — 14 основ (красятся цветом кожи);
  * collar_<одежда>_<m|f>_<посадка> и непустые …_inner — ЦВЕТНЫЕ перед и изнанка одежды (119 сочетаний).
    Серые версии *_gray набора — это ровно яркость цветных (BT.601), поэтому в игру они не копируются:
    шейдер берёт яркость цветной картинки и красит основную ткань в цвет спецовки, а галстук, полосы боёвки,
    рубашка под комбинезоном остаются своего цвета;
  * mask_<одежда>_keep — маска body_keep (где видна основа), L8;
  * mask_<одежда>_fab — где основная ткань (перед и изнанка вместе), L8; во layers.json "gain" — во сколько раз
    поднять яркость ткани, чтобы её медиана стала опорным серым (200) — тогда цвет ткани = цвет спецовки;
  * черты лица, причёски, уборы из assets/: eyes_*_iris — радужка (красится цветом глаз); cap и helmet —
    яркость приведена к опорному серому (красятся цветом убора); kerchief_f — серая копия (цвет платка);
    mask_hat_<убор> — где под убором прячутся волосы.
Всё — на полном холсте размер×размер (Lanczos по премультиплицированной альфе), начало слоёв (0,0).
Пишет .import (мипмапы; одежда — WebP с потерями q 0.8, остальное без потерь) и layers.json — рамки непустой части слоёв, маски, gain, посадки.
"""
import json
import os
import shutil
import sys

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portrait2")
REF = 200.0
FITS = ["very_thin", "thin", "normal", "strong", "powerful", "full", "very_full"]
HATS = ["cap", "helmet", "welder_mask", "ushanka"]

IMPORT_TMPL = """[remap]

importer="texture"
type="CompressedTexture2D"

[params]

compress/mode=%d
compress/high_quality=false
compress/lossy_quality=0.8
mipmaps/generate=true
mipmaps/limit=-1
process/fix_alpha_border=true
process/premult_alpha=false
process/size_limit=0
detect_3d/compress_to=0
"""


def lum(a):
    """Яркость, как у серых версий набора (BT.601)."""
    c = a[..., :3].astype(np.float32)
    return c[..., 0] * 0.299 + c[..., 1] * 0.587 + c[..., 2] * 0.114


def fabric_mask(kind, a, inner=False):
    """Основная ткань одежды по цветному рисунку (то, что красим цветом спецовки)."""
    L = lum(a)
    c = a[..., :3].astype(np.int32)
    r, g, b = c[..., 0], c[..., 1], c[..., 2]
    op = a[..., 3] > 0
    Lb = np.asarray(Image.fromarray(np.where(op, L, 0).astype(np.uint8)).filter(ImageFilter.BoxBlur(9))).astype(np.float32)
    Ob = np.asarray(Image.fromarray((op * 255).astype(np.uint8)).filter(ImageFilter.BoxBlur(9))).astype(np.float32) / 255.0
    Lm = Lb / np.maximum(Ob, 0.05)
    if kind == "overall":
        m = b > r + 6                                  # синий комбинезон; рубашка под ним — своя
    elif kind in ("jacket", "vest"):
        m = Lm < 140                                   # без светлой рубашки
    elif kind == "suit":
        rg = np.where(op, np.clip(r - g + 128, 0, 255), 128).astype(np.uint8)
        rgm = np.asarray(Image.fromarray(rg).filter(ImageFilter.BoxBlur(7))).astype(np.float32) - 128.0
        m = (Lm < 125) & (rgm < 16)                    # пиджак; рубашка и красный галстук — свои
    elif kind == "robe":
        m = np.ones_like(op) if inner else ((L > 135) | (L < 70))   # белый халат; серая рубашка — своя
    elif kind == "firefighter":
        m = ~((r > 140) & (g > 120) & (b < 110))       # без жёлтых полос
    else:
        m = np.ones_like(op)                           # рубашка, свитер, рабочая рубашка с косынкой
    m = m & op
    im = Image.fromarray((m * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.MinFilter(9))
    return (np.asarray(im) > 127) & op


def gain_of(a, m):
    sel = m & (a[..., 3] > 128)
    med = float(np.median(lum(a)[sel])) if sel.any() else REF
    return float(np.clip(REF / max(med, 1.0), 0.8, 2.6))


def gray_norm(a, ref_pct=None):
    """Серая копия, яркость приведена к опорному серому (медиана или процентиль)."""
    L = lum(a)
    op = a[..., 3] > 128
    ref = (np.percentile(L[op], ref_pct) if ref_pct else np.median(L[op])) if op.any() else REF
    v = np.clip(L * float(np.clip(REF / max(ref, 1.0), 0.8, 2.6)), 0, 255).astype(np.uint8)
    g = a.copy()
    g[..., 0] = v
    g[..., 1] = v
    g[..., 2] = v
    return g


def iris_of(a):
    """Радужка: средне-серое толстое пятно внутри глаза (без белков, ресниц и тонких теней)."""
    h, w = a.shape[:2]
    L = a[..., :3].astype(np.float32).mean(-1)
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
    """Маска волос под убором: 0 — волосы прячутся (выше полей и макушки убора), 1 — видны."""
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


def load(p):
    return np.asarray(Image.open(p).convert("RGBA")).copy()


def load_l(p):
    return np.asarray(Image.open(p).convert("L")).astype(np.float32) / 255.0


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    size = int(args[1]) if len(args) > 1 else 512
    outfits = json.load(open(os.path.join(src, "outfits.json")))
    out = {}      # имя -> RGBA
    masks = {}    # имя -> float 0..1
    gain = {}
    # основы
    for fit in FITS:
        for g in ("m", "f"):
            out["base_%s_%s" % (fit, g)] = load(os.path.join(src, "bases", "base_%s_%s.png" % (fit, g)))
    # одежда по посадкам
    cdir = os.path.join(src, "clothes")
    for name, e in sorted(outfits.items()):
        assert e["body"] in FITS and e["base"] == "base_%s_%s" % (e["body"], e["gender"]), name
        front = load(os.path.join(cdir, e["front"] + ".png"))
        inner = load(os.path.join(cdir, e["inner"] + ".png"))
        out[name] = front
        fm = fabric_mask(e["garment"], front)
        fab = fm.astype(np.float32)
        if inner[..., 3].max() > 0:
            out[name + "_inner"] = inner
            im = fabric_mask(e["garment"], inner, True)
            fab = np.where(front[..., 3] > 0, fab, im.astype(np.float32))
        gain[name] = round(gain_of(front, fm), 4)
        masks["mask_%s_fab" % name] = fab
        masks["mask_%s_keep" % name] = load_l(os.path.join(src, "masks", e["body_mask"] + ".png"))
    # черты лица, волосы, уборы
    adir = os.path.join(src, "assets")
    for f in sorted(os.listdir(adir)):
        if not f.endswith(".png"):
            continue
        n = f[:-4]
        a = load(os.path.join(adir, f))
        if n.startswith(("head_", "neck_", "cheeks_", "chin_")):
            continue   # анатомия v2 в v3 не накладывается
        if n.startswith("eyes_") and not n.endswith("_lids"):
            out[n] = a
            out[n + "_iris"] = iris_of(a)
        elif n in ("cap", "helmet"):
            g = gray_norm(a)
            g[..., 3] = a[..., 3]
            out[n] = g
            masks["mask_hat_" + n] = hat_clip(a)
        elif n in HATS:
            out[n] = a
            masks["mask_hat_" + n] = hat_clip(a)
        elif n == "kerchief_f":
            out[n] = gray_norm(a, 85)
        else:
            out[n] = a
    # всё старое — долой (v2-головы, шеи, щёки, маски keep_face/skin_keep, _fab, _skinpart …)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)
    os.makedirs(OUT)
    meta = {"size": size, "src": 1024, "version": 3, "layers": {}, "masks": sorted(masks), "gain": gain,
            "fits": {"vthin": "very_thin", "thin": "thin", "normal": "normal", "stout": "strong", "strong": "powerful",
                     "fat": "full", "vfat": "very_full"}}
    total = 0

    def write(n, im):
        nonlocal total
        p = os.path.join(OUT, n + ".png")
        im.save(p, optimize=True)
        total += os.path.getsize(p)
        with open(p + ".import", "w") as f:
            # одежда — самая крупная часть набора: WebP с потерями (q 0.8, альфа без потерь) — в 4 раза меньше
            f.write(IMPORT_TMPL % (1 if n.startswith("collar_") else 0))

    for n, a in sorted(out.items()):
        im = Image.fromarray(a, "RGBA")
        if size != im.width:
            im = im.resize((size, size), Image.LANCZOS)
        # полностью прозрачные пиксели — чёрные: лучше жмётся
        arr = np.asarray(im).copy()
        arr[arr[..., 3] == 0] = 0
        im = Image.fromarray(arr, "RGBA")
        write(n, im)
        ys, xs = np.nonzero(arr[..., 3] > 0)
        meta["layers"][n] = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if xs.size else [0, 0, 0, 0]
    for n, m in sorted(masks.items()):
        im = Image.fromarray(np.clip(m * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")
        if size != im.width:
            im = im.resize((size, size), Image.LANCZOS)
        write(n, im)
    with open(os.path.join(OUT, "layers.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("слоёв: %d, масок: %d, PNG: %.1f МБ -> %s" % (len(out), len(masks), total / 1048576.0, OUT))


if __name__ == "__main__":
    main()
