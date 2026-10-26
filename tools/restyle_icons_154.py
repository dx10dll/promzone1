#!/usr/bin/env python3
"""1.54 (4.1): приведение встроенных SVG-значков интерфейса к стилю значков владельца (assets/ui/icons).

Что делает для каждого значка из списка NAMES:
  * палитра владельца: песочный #e4cc9c, тень #b49c84, красный #b43c24, оливковый #848454;
  * одна толщина обводки (STROKE = 3 px холста 48×48) и круглые концы;
  * одинаковые поля: содержимое вписывается в рамку 6…42 (как у значков владельца, ~12 % поля).
Границы содержимого берутся из /tmp/claude-0/bbox.json (его пишет растеризатор Godot: used_rect).
Запуск: python3 tools/restyle_icons_154.py [--from DIR_С_ИСХОДНЫМИ_SVG]; затем python3 tools/pack_vec.py (ui.json).
"""
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = ("build calendar chart_up crew demolish factory finance office ov_crew ov_dirt ov_light ov_load ov_nets ov_power "
         "ov_rooms ov_temp ov_traffic overlay plan play1 play2 play3 power rooms stage_up thermo town zone_erase").split()
PAL = {"#e7e4d8": "#e4cc9c", "#e0aa48": "#b43c24", "#d8644e": "#b43c24", "#d99a6a": "#b49c84", "#9aa3ab": "#b49c84",
       "#e8c34a": "#e4cc9c", "#9fd28a": "#848454", "#8fcf78": "#848454"}
STROKE = 3.0
BOX = (6.0, 42.0)


def main() -> None:
    src = os.path.join(ROOT, "assets", "ui")
    for a in sys.argv[1:]:
        if a.startswith("--from="):
            src = a.split("=", 1)[1]
    bb = json.load(open("/tmp/claude-0/bbox.json"))
    for n in NAMES:
        s = open(os.path.join(src, n + ".svg"), encoding="utf-8").read()
        x0, y0, x1, y1 = bb[n]
        w, h = x1 - x0, y1 - y0
        k = min((BOX[1] - BOX[0]) / w, (BOX[1] - BOX[0]) / h, 1.3)
        cx, cy = (x0 + x1) / 2.0, (y0 + y1) / 2.0
        tx, ty = 24.0 - cx * k, 24.0 - cy * k
        inner = s[s.index(">", s.index("<svg")) + 1:s.rindex("</svg>")]
        for a, b in PAL.items():
            inner = re.sub(a, b, inner, flags=re.I)
        sw = STROKE / k
        inner = re.sub(r'stroke-width="[\d.]+"', 'stroke-width="%.2f"' % sw, inner)
        inner = inner.replace('stroke-linecap="butt"', 'stroke-linecap="round"')
        out = ('<svg xmlns="http://www.w3.org/2000/svg" width="48" height="48" viewBox="0 0 48 48">'
               '<g transform="translate(%.2f %.2f) scale(%.4f)">%s</g></svg>' % (tx, ty, k, inner))
        open(os.path.join(ROOT, "assets", "ui", n + ".svg"), "w", encoding="utf-8").write(out)
        print(n, "k=%.2f" % k)


if __name__ == "__main__":
    main()
