"""1.17: логотип «ПРОМЗОНА» — контуры букв шрифта IBM Plex Sans SemiBold в SVG (assets/vec/logo.json).
В игре SVG растеризуется под точный размер экрана — заголовок чёткий при любом масштабе окна.
1.39: python3 tools/gen_logo.py PROMZONA logo_en.json — английский логотип (assets/vec/logo_en.json)."""
import json, os, sys
from fontTools.ttLib import TTFont
from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
font = TTFont(os.path.join(ROOT, "assets/fonts/IBMPlexSans-SemiBold.ttf"))
gs = font.getGlyphSet()
cmap = font.getBestCmap()
upm = font["head"].unitsPerEm
TEXT = sys.argv[1] if len(sys.argv) > 1 else "ПРОМЗОНА"
OUT = sys.argv[2] if len(sys.argv) > 2 else "logo.json"
SIZE = 100.0            # кегль, px
TRACK = 6.0             # разрядка, px
k = SIZE / upm
asc = font["hhea"].ascent * k
x = 0.0
paths = []
for ch in TEXT:
    gname = cmap[ord(ch)]
    pen = SVGPathPen(gs)
    tp = TransformPen(pen, (k, 0, 0, -k, x, asc))
    gs[gname].draw(tp)
    paths.append(pen.getCommands())
    x += gs[gname].width * k + TRACK
W = x - TRACK
cap = font["OS/2"].sCapHeight * k if hasattr(font["OS/2"], "sCapHeight") else SIZE * 0.7
top = asc - cap
H = asc + 4
d = " ".join(paths)
svg = (f'<svg xmlns="http://www.w3.org/2000/svg" width="{W + 8:.0f}" height="{H - top + 10:.0f}" viewBox="-2 {top - 3:.1f} {W + 8:.1f} {H - top + 10:.1f}">'
       f'<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#f6efd9"/><stop offset="0.55" stop-color="#e6dcc0"/><stop offset="1" stop-color="#c9bb97"/></linearGradient></defs>'
       f'<path d="{d}" fill="#000" opacity="0.45" transform="translate(2.5 4)"/>'
       f'<path d="{d}" fill="url(#g)" stroke="#2a2620" stroke-width="1.2" stroke-opacity="0.5"/>'
       f'</svg>')
os.makedirs(os.path.join(ROOT, "assets/vec"), exist_ok=True)
with open(os.path.join(ROOT, "assets/vec", OUT), "w", encoding="utf-8") as f:
    json.dump({"svg": svg, "w": W + 8, "h": H - top + 10}, f, ensure_ascii=False)
print("logo", round(W), "x", round(H - top), len(svg), "bytes")
