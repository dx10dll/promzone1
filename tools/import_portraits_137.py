#!/usr/bin/env python3
"""1.37: импорт набора портретов v5 (14 изолированных наборов: m|f × 7 телосложений) в assets/portrait2/.

Запуск (из корня проекта):
    python3 -I tools/import_portraits_137.py <папка_набора> [размер=512]
где <папка_набора> — распакованный promzona_v5 (male/<телосложение>/, female/<телосложение>/ с set.json).

Правило набора (README_CLAUDE_RU.md): все детали человека — из папки его пола и телосложения, без подмен из
других наборов. Каждый набор кладётся в assets/portrait2/<set_id>/ (set_id = <телосложение>_<m|f>), его описание —
в layers.json → sets[set_id]: головы, причёски, бороды, одежда (шея, изнанка, перед — один связанный выбор),
gain ткани, регистрация (макушка, подбородок). base_template — не слой, в игру не идёт.

Что кладётся в игру (только то, что рисуется):
  * головы, шеи под каждую одежду, веки, морщины, причёски, брови, бороды — серые (красятся кожей/волосами);
  * одежда (перед и изнанка) — ЦВЕТНАЯ. Серые версии набора — ровно её яркость (BT.601), поэтому в игру
    не копируются: шейдер перекрашивает основную ткань (маска mask_<одежда>_fab, L8) по яркости × gain в цвет
    спецовки; галстук, полосы боёвки, рубашка под комбинезоном остаются своего цвета;
  * глаза, рты, веснушки, очки, серьги (только у женщин — мужчинам игра серьги не даёт), уборы;
    eyes_*_iris — радужка (красится цветом глаз); cap, helmet — яркость приведена к опорному серому, kerchief_f —
    серая копия (красятся цветом убора); mask_hat_<убор> — где под убором прячутся волосы.
Сжатие (.import, мипмапы): одежда, шеи, головы, причёски, бороды — WebP с потерями (q 0.8, альфа без потерь),
мелкие черты и маски — без потерь. Файлы, одинаковые в разных наборах (по содержимому), кладутся один раз —
в layers.json → alias.
"""
import hashlib
import json
import os
import shutil
import sys
from multiprocessing import Pool

import numpy as np
from PIL import Image, ImageFilter

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "assets", "portrait2")
REF = 200.0
FITS = ["very_thin", "thin", "normal", "strong", "powerful", "full", "very_full"]
HATS = ["cap", "helmet", "welder_mask", "ushanka"]
LOSSY = ("collar_", "neck_", "head_", "hair_", "beard_")
SIZE = 512

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


def down_rgba(a):
    im = Image.fromarray(a, "RGBA")
    if SIZE != im.width:
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    arr = np.asarray(im).copy()
    arr[arr[..., 3] == 0] = 0   # полностью прозрачное — чёрное: лучше жмётся
    return arr


def down_l(m):
    im = Image.fromarray(np.clip(m * 255.0 + 0.5, 0, 255).astype(np.uint8), "L")
    if SIZE != im.width:
        im = im.resize((SIZE, SIZE), Image.LANCZOS)
    return np.asarray(im).copy()


def do_set(job):
    """Один набор: {имя слоя: RGBA 512}, {имя маски: L 512}, описание набора."""
    folder, = job
    s = json.load(open(os.path.join(folder, "set.json")))
    sid = s["set_id"]
    g = s["gender"]
    assert s["body_type"] in FITS and sid == "%s_%s" % (s["body_type"], g), sid
    parts = s["parts"]
    mat = s["materials"]
    out = {}
    masks = {}

    def ld(n):
        return load(os.path.join(folder, parts[n]))

    used = set()
    for h in s["heads"]:
        used.add("head_%s_%s" % (g, h))
    for h in s["hair"]:
        used.add("hair_%s_front" % h)
        used.add("hair_%s_back" % h)
    for k in ("eyes", "brows", "nose", "mouth"):
        for v in s[k]:
            used.add("%s_%s" % (k, v))
            if k == "eyes":
                used.add("eyes_%s_lids" % v)
    for b in s["beard"]:
        used.add("beard_" + b)
    for acc in s["accessories"]:
        if acc == "earrings" and g == "m":
            continue
        used.add(acc)
    outfits = {}
    gain = {}
    for o, e in s["outfits"].items():
        front = ld(e["outer"])
        fm = fabric_mask(o, front)
        fab = fm.astype(np.float32)
        used.add(e["neck"])
        used.add(e["outer"])
        inner = None
        if e["inner"]:
            ia = ld(e["inner"])
            if ia[..., 3].max() > 0:
                inner = e["inner"]
                used.add(inner)
                im = fabric_mask(o, ia, True)
                fab = np.where(front[..., 3] > 0, fab, im.astype(np.float32))
        gain[o] = round(gain_of(front, fm), 4)
        masks["mask_%s_fab" % o] = down_l(fab)
        outfits[o] = {"neck": e["neck"], "outer": e["outer"], "inner": inner}
    for n in sorted(used):
        assert n in parts and not n.endswith("_gray"), (sid, n)
        a = ld(n)
        if mat.get(n) in ("skin", "hair"):
            assert np.abs(a[..., 0].astype(int) - a[..., 2].astype(int))[a[..., 3] > 0].max() <= 2, (sid, n, "не серый")
        if n.startswith("eyes_") and not n.endswith("_lids"):
            out[n] = down_rgba(a)
            out[n + "_iris"] = down_rgba(iris_of(a))
        elif n in ("cap", "helmet"):
            gr = gray_norm(a)
            gr[..., 3] = a[..., 3]
            out[n] = down_rgba(gr)
            masks["mask_hat_" + n] = down_l(hat_clip(a))
        elif n in HATS:
            out[n] = down_rgba(a)
            masks["mask_hat_" + n] = down_l(hat_clip(a))
        elif n == "kerchief_f":
            out[n] = down_rgba(gray_norm(a, 85))
        else:
            out[n] = down_rgba(a)
    reg = s.get("registration", {})
    desc = {"gender": g, "body": s["body_type"], "heads": s["heads"], "hair": s["hair"], "beard": s["beard"],
            "outfits": outfits, "gain": gain, "crown": float(reg.get("crown", 100)), "chin": float(reg.get("chin", 570))}
    return sid, out, masks, desc


def main():
    global SIZE
    args = sys.argv[1:]
    if not args:
        print(__doc__)
        sys.exit(1)
    src = args[0]
    if len(args) > 1:
        SIZE = int(args[1])
    jobs = []
    for gd in ("male", "female"):
        for fit in FITS:
            jobs.append((os.path.join(src, gd, fit),))
    with Pool(min(8, os.cpu_count() or 2)) as p:
        res = p.map(do_set, jobs)
    if os.path.isdir(OUT):
        shutil.rmtree(OUT)   # всё старое — долой (набор v3: основы, одежда по посадкам, маски body_keep …)
    os.makedirs(OUT)
    meta = {"size": SIZE, "src": 1024, "version": 5, "sets": {}, "layers": {}, "masks": [], "alias": {}}
    seen = {}   # хэш содержимого -> имя файла
    total = 0
    nfiles = 0

    def write(key, arr, mode, lossy):
        nonlocal total, nfiles
        h = hashlib.sha256(arr.tobytes() + mode.encode()).hexdigest()
        if h in seen:
            meta["alias"][key] = seen[h]
            return
        seen[h] = key
        p = os.path.join(OUT, key + ".png")
        os.makedirs(os.path.dirname(p), exist_ok=True)
        Image.fromarray(arr, mode).save(p, optimize=True)
        total += os.path.getsize(p)
        nfiles += 1
        with open(p + ".import", "w") as f:
            f.write(IMPORT_TMPL % (1 if lossy else 0))

    for sid, out, masks, desc in res:
        meta["sets"][sid] = desc
        for n, a in sorted(out.items()):
            key = sid + "/" + n
            ys, xs = np.nonzero(a[..., 3] > 0)
            meta["layers"][key] = [int(xs.min()), int(ys.min()), int(xs.max()) + 1, int(ys.max()) + 1] if xs.size else [0, 0, 0, 0]
            write(key, a, "RGBA", n.startswith(LOSSY))
        for n, m in sorted(masks.items()):
            key = sid + "/" + n
            meta["masks"].append(key)
            write(key, m, "L", False)
    meta["masks"].sort()
    with open(os.path.join(OUT, "layers.json"), "w") as f:
        json.dump(meta, f, indent=1, sort_keys=True)
    print("наборов: %d, слоёв: %d, масок: %d, файлов: %d (одинаковых убрано: %d), PNG: %.1f МБ -> %s" % (
        len(meta["sets"]), len(meta["layers"]), len(meta["masks"]), nfiles, len(meta["alias"]), total / 1048576.0, OUT))


if __name__ == "__main__":
    main()
