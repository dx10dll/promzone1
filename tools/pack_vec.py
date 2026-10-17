#!/usr/bin/env python3
"""Упаковка исходных SVG людей и портретов в JSON (assets/vec/*.json).

Игра растеризует их на лету точно под размер на экране (портреты в карточках, люди при сильном
приближении) — так картинка остаётся векторно-чёткой при любом масштабе и разрешении монитора.
Запуск после gen_assets.py / gen_portraits.py: python3 tools/pack_vec.py
"""
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def pack(folder, out):
    data = {}
    for svg in sorted(glob.glob(os.path.join(ROOT, "assets", folder, "*.svg"))):
        name = os.path.splitext(os.path.basename(svg))[0]
        data[name] = open(svg, encoding="utf-8").read()
    path = os.path.join(ROOT, "assets", "vec", out)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, separators=(",", ":"))
    print(out, len(data), "файлов,", os.path.getsize(path) // 1024, "КБ")


if __name__ == "__main__":
    os.makedirs(os.path.join(ROOT, "assets", "vec"), exist_ok=True)
    pack("portrait", "portrait.json")
    pack("people", "people.json")
    pack("ui", "ui.json")   # 1.19: значки интерфейса растеризуются под экран (VecIcon)
