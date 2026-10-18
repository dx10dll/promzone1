#!/usr/bin/env python3
"""1.27: данные литья и штамповки — переделы, расходник, материалы, станки, изделия, исследования."""
import json, sys, os
from collections import OrderedDict

ROOT = sys.argv[1]


IND = {}


def load(n):
    with open(os.path.join(ROOT, "data", n), encoding="utf-8") as f:
        txt = f.read()
    lines = txt.split("\n")
    l1 = lines[1]
    IND[n] = ("\t" if l1.startswith("\t") else len(l1) - len(l1.lstrip(" ")), txt.endswith("\n"))
    return json.loads(txt, object_pairs_hook=OrderedDict)


def dump(n, d):
    ind, nl = IND[n]
    with open(os.path.join(ROOT, "data", n), "w", encoding="utf-8") as f:
        json.dump(d, f, ensure_ascii=False, indent=ind if ind else None)
        if nl:
            f.write("\n")


pr = load("processes.json")
pr["casting"] = {"name": "Литьё", "skill": "casting", "prof": "caster", "cons": "sand", "cons_use": 1.0}
pr["stamping"] = {"name": "Штамповка", "skill": "stamping", "prof": "presser", "cons": "", "cons_use": 0.0}
dump("processes.json", pr)

cs = load("consumables.json")
cs["sand"] = {"name": "Формовочная смесь", "short": "смесь", "pack": "мешки песчано-глинистой смеси на 20 опок", "price": 2400,
              "units": 20, "start": 0, "desc": "Расходуется на литье: одна опока на отливку."}
dump("consumables.json", cs)

ms = load("materials.json")
ms["charge"] = {"name": "Шихта", "price": 140, "desc": "Стальной лом и чушки для плавки — дёшево, но литьё нужно ещё обработать."}
ms["strip2"] = {"name": "Полоса 2 мм", "price": 160, "desc": "Нарезанная лента из листа 2 мм — под штамп."}
dump("materials.json", ms)

ob = load("objects.json")
ob["cast_ist"] = {"name": "Индукционная печь ИСТ-0,16", "cat": "Литьё и штамповка", "cost": 680000, "build_time": 180, "size": [2, 2],
                  "blocks": True, "kind": "machine", "needs_floor": True, "spots": [[0, 2, "up"]], "research": "casting_shop",
                  "machine": {"in_cap": 6, "out_cap": 4, "power_kw": 40.0, "process": "casting", "part_size": "m", "room_heat": 0.35, "smoke": True},
                  "desc": "Плавит шихту в тигле токами высокой частоты, литейщик разливает металл по опокам. Даёт заготовки сложной формы, которых не выточить из прутка. Очень много тока, жарко, нужна вытяжка.",
                  "stage": 3, "crates": 4}
ob["cast_line"] = {"name": "Литейный участок ЛУ-2", "cat": "Литьё и штамповка", "cost": 1450000, "build_time": 260, "size": [3, 2],
                   "blocks": True, "kind": "machine", "needs_floor": True, "spots": [[1, 2, "up"]], "research": "casting_shop",
                   "machine": {"in_cap": 10, "out_cap": 6, "power_kw": 55.0, "process": "casting", "part_size": "l", "speed_k": 0.6, "room_heat": 0.45, "smoke": True},
                   "desc": "Печь, ковш на тельфере и рольганг с опоками: льют быстрее и крупнее, но и тока надо как на целый цех.",
                   "stage": 4, "crates": 6}
ob["press_kd"] = {"name": "Пресс кривошипный КД2126", "cat": "Литьё и штамповка", "cost": 260000, "build_time": 80, "size": [1, 1],
                  "blocks": True, "kind": "machine", "needs_floor": True, "spots": [[0, 1, "up"]], "research": "stamping_shop",
                  "machine": {"in_cap": 10, "out_cap": 12, "power_kw": 4.0, "process": "stamping", "part_size": "s"},
                  "desc": "Пресс на 16 тонн: вырубает и гнёт мелкие детали из полосы за один удар. Быстро и дёшево, но очень громко — нужны беруши.",
                  "stage": 3, "crates": 2}
ob["press_kb"] = {"name": "Пресс листоштамповочный КБ235", "cat": "Литьё и штамповка", "cost": 720000, "build_time": 160, "size": [2, 1],
                  "blocks": True, "kind": "machine", "needs_floor": True, "spots": [[0, 1, "up"]], "research": "stamping_shop",
                  "machine": {"in_cap": 14, "out_cap": 16, "power_kw": 15.0, "process": "stamping", "part_size": "m", "speed_k": 0.55},
                  "desc": "Пресс двойного действия на 100 тонн: штампует средние детали почти вдвое быстрее малого.",
                  "stage": 4, "crates": 4}
dump("objects.json", ob)

pd = load("products.json")
pd["cast_cover"] = {"name": "Крышка литая", "size": "m", "material": "charge", "mat_qty": 3,
                    "route": [{"op": "casting", "time": 40, "skill": 2}, {"op": "turning", "time": 20, "skill": 2}],
                    "qc_time": 8, "price": [5200, 6300], "qty": [6, 18], "heavy": True, "research": "casting_shop",
                    "desc": "Крышка подшипникового узла: отливка и подрезка торца на токарном."}
pd["cast_body"] = {"name": "Корпус редуктора литой", "size": "m", "material": "charge", "mat_qty": 6,
                   "route": [{"op": "casting", "time": 70, "skill": 4}, {"op": "milling", "time": 40, "skill": 3}, {"op": "drilling", "time": 20, "skill": 2}],
                   "qc_time": 14, "price": [17800, 21500], "qty": [2, 8], "heavy": True, "research": "casting_shop", "paint_col": "#4a5a6a",
                   "desc": "Чугунный корпус: отливка, фрезеровка плоскостей и сверловка под крепёж."}
pd["washer"] = {"name": "Шайба пружинная", "size": "s", "material": "strip2", "mat_qty": 1,
                "route": [{"op": "stamping", "time": 2, "skill": 1}],
                "qc_time": 1, "price": [210, 260], "qty": [120, 400], "research": "stamping_shop",
                "desc": "Вырубка и разводка — одним ударом пресса. Заказывают сотнями."}
pd["clamp"] = {"name": "Хомут крепёжный", "size": "s", "material": "strip2", "mat_qty": 1,
               "route": [{"op": "stamping", "time": 4, "skill": 2}, {"op": "paint", "time": 3, "skill": 1, "cons": 1}],
               "qc_time": 2, "price": [640, 790], "qty": [60, 200], "research": "stamping_shop", "paint_col": "#3d4a5a",
               "desc": "Вырубка, гибка и покраска: дёшево и много."}
pd["bracket_st"] = {"name": "Кронштейн гнутый", "size": "s", "material": "strip2", "mat_qty": 2,
                    "route": [{"op": "stamping", "time": 6, "skill": 2}, {"op": "drilling", "time": 5, "skill": 1}],
                    "qc_time": 3, "price": [1250, 1500], "qty": [30, 100], "research": "stamping_shop",
                    "desc": "Штампованный уголок с отверстиями — замена фрезерованному там, где не нужна точность."}
dump("products.json", pd)

rs = load("research.json")
rs["casting_shop"] = {"name": "Литейный участок", "branch": "Изделия", "cost": 40,
                      "desc": "Открывает индукционную печь и литейный участок, профессию литейщика и литые изделия: крышки и корпуса редукторов. Нужен ток и вытяжка.", "req": ["product_flange"]}
rs["stamping_shop"] = {"name": "Штамповка", "branch": "Изделия", "cost": 28,
                       "desc": "Открывает кривошипные и листоштамповочные прессы, профессию штамповщика и штампованные изделия: шайбы, хомуты, кронштейны — дёшево и сотнями.", "req": []}
dump("research.json", rs)
print("ok")
