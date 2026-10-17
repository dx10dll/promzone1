#!/usr/bin/env python3
"""Растеризация SVG в высоком разрешении: svg/scale в .import-файлах.

Графика рисуется в «логических» единицах SVG (64 px на клетку), а импортируется в K раз крупнее.
Tex (scripts/view/tex.gd) подменяет у текстуры размер на логический — код отрисовки не меняется,
а на экран идут чёткие пиксели даже при сильном приближении и на больших мониторах.
Запуск после gen_assets.py: python3 tools/set_import_scale.py
"""
import glob
import os
import re

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
K = 3.0
HI = ["objects", "people", "items", "tiles", "vehicles", "ui", "fx", "portrait"]
KEEP = {"glow.svg"}   # текстура света: размер света считается от неё


def main():
    n = 0
    for d in HI:
        for svg in glob.glob(os.path.join(ROOT, "assets", d, "*.svg")):
            imp = svg + ".import"
            want = 1.0 if os.path.basename(svg) in KEEP else K
            if not os.path.exists(imp):
                continue
            s = open(imp, encoding="utf-8").read()
            s2 = re.sub(r"svg/scale=[0-9.]+", f"svg/scale={want}", s)
            # 1.15: мип-карты строит сама игра при загрузке (Tex._logical) — в сборку их не кладём, она легче
            s2 = re.sub(r"mipmaps/generate=\w+", "mipmaps/generate=false", s2)
            if s2 != s:
                open(imp, "w", encoding="utf-8").write(s2)
                n += 1
    print("обновлено .import:", n)


if __name__ == "__main__":
    main()
