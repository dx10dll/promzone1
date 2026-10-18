#!/usr/bin/env python3
"""1.30 «Машины и пожарные»: пожарная автоцистерна, грузы в кузовах по назначению, боёвка пожарного,
пожарный ствол и короб со стружкой в руках.

Запуск: python3 tools/gen_veh130.py  (из корня проекта), затем python3 tools/pack_vec.py — люди
растеризуются из assets/vec/people.json. Пишет только свои новые файлы — gen_assets.py целиком
перезапускать не нужно.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_assets import rect, circ, ell, path, line, poly, OUT, save, person_layer  # noqa: E402

RED = "#c8261e"
WHITE_S = "#f2f2ee"
STEEL, STEEL_D, STEEL_L = "#9aa1a5", "#6f777c", "#c7cdd0"
WOOD = "#b98a55"


def fire_truck():
    """Пожарная автоцистерна (смотрит вправо, 4 тайла): кабина, кузов с отсеками-шторками,
    белая полоса, лестница на крыше, балка проблесковых маячков (мигание — в VehicleFx)."""
    W, H = 264, 120
    base_y = 104
    body = ell(132, base_y + 6, 122, 9, "#000", None, 0, 0.3)
    body += rect(6, 22, 178, 64, RED, OUT, 2, 3)                                  # кузов с отсеками
    body += path("M188 26H232Q246 26 250 40V90H188Z", RED, OUT, 2)                 # кабина
    save("assets/vehicles/fire_body.svg", W, H, body)
    det = ""
    for x in (10, 66, 122):                                                        # отсеки со шторками
        det += rect(x, 30, 52, 40, "#b3201a", OUT, 1.2, 2)
        for j in range(1, 8):
            det += line(x + 2, 30 + j * 5, x + 50, 30 + j * 5, "#000", 1, 0.22)
        det += rect(x + 22, 64, 8, 3, STEEL_L, OUT, 0.8, 1)
    det += rect(6, 70, 178, 7, WHITE_S, OUT, 1.2) + rect(188, 70, 62, 7, WHITE_S, OUT, 1.2)   # белая полоса
    det += rect(14, 12, 150, 4, STEEL_L, OUT, 1.2, 1) + rect(14, 18, 150, 3, STEEL, OUT, 1, 1)  # лестница
    for x in range(20, 162, 12):
        det += line(x, 14, x, 20, STEEL_D, 1.6)
    det += rect(12, 16, 6, 8, "#3a3e42", OUT, 1) + rect(160, 16, 6, 8, "#3a3e42", OUT, 1)
    det += path("M196 32H228Q238 32 242 44L244 50H196Z", "#7fa4c4", OUT, 1.6) + path("M202 36L212 48", None, "#fff", 2, 0.5)
    det += line(220, 32, 220, 50, OUT, 1.4) + rect(206, 56, 10, 3, "#3a3e42", None, 0)
    det += rect(188, 20, 4, 70, "#3a3e42", None, 0)
    # балка маячков над кабиной (стёкла синие; сами вспышки рисует игра)
    det += rect(198, 18, 40, 7, "#2a2e31", OUT, 1.2, 2) + rect(200, 19, 12, 5, "#3a6ad0", None, 0, 1) + rect(224, 19, 12, 5, "#3a6ad0", None, 0, 1)
    det += rect(214, 19, 8, 5, "#c9d0d4", None, 0, 1)
    det += rect(244, 62, 8, 7, "#ffe9a8", OUT, 1) + rect(242, 80, 12, 10, "#3a3e42", OUT, 1)
    det += rect(6, 58, 5, 9, "#c0392b", OUT, 1)
    det += rect(8, 84, 244, 8, "#2f3336", OUT, 1.5)
    det += rect(96, 78, 30, 6, STEEL, OUT, 1) + circ(110, 80, 4, "#d9b13b", OUT, 1)   # патрубки насоса
    for cx in (44, 82, 220):
        det += circ(cx, base_y - 4, 14, "#1d1d1d", OUT, 1.5) + circ(cx, base_y - 4, 6.5, "#8a9196", OUT, 1)
    save("assets/vehicles/fire_details.svg", W, H, det)


def parts_pallet(x, y, w, h):
    out = rect(x, y + h, w, 5, WOOD, OUT, 1.2)
    out += rect(x + 2, y, w - 4, h, "#c9a26e", OUT, 1.4, 1)                   # коробки с деталями
    for k in range(1, 3):
        xx = x + 2 + k * (w - 4) / 3
        out += line(xx, y, xx, y + h, "#8a6a44", 1)
    out += line(x + 2, y + h / 2, x + w - 2, y + h / 2, "#8a6a44", 1)
    out += rect(x + 6, y + 4, 10, 6, "#f2f2ee", OUT, 0.6)                      # этикетка
    out += line(x + 2, y + 1, x + w - 2, y + h - 1, "#ffffff", 1.2, 0.35)      # стрейч-плёнка
    return out


def cargo():
    """Груз в кузове по назначению: прутки (металл), ящики (оборудование), поддоны с деталями
    (заказ клиента), стружка и лом (ломовоз)."""
    cg = ""
    for j in range(5):                                   # бортовой 216×120, платформа под y=58
        cg += rect(10, 42 + j * 3.4, 134, 4.4, STEEL if j % 2 else STEEL_L, OUT, 0.9, 2)
    cg += rect(30, 56, 8, 3, WOOD, OUT, 0.8) + rect(110, 56, 8, 3, WOOD, OUT, 0.8)
    for x in (40, 104):
        cg += rect(x, 40, 3, 18, "#c94a3a", None, 0, 0, 0.9)
    save("assets/vehicles/flatbed_cargo_bars.svg", 216, 120, cg)
    cg = ""
    for x, w, h in ((12, 60, 36), (76, 44, 26), (124, 22, 20)):
        y = 58 - h
        cg += rect(x, y, w, h, WOOD, OUT, 1.6, 1)
        cg += line(x + 3, y + 3, x + w - 3, y + h - 3, "#8a6236", 2) + line(x + w - 3, y + 3, x + 3, y + h - 3, "#8a6236", 2)
        cg += rect(x, y, w, 4, "#c9a26e", None, 0)
        cg += rect(x + w / 2 - 5, y + h / 2 - 4, 10, 8, "#f2f2ee", OUT, 0.8)
    save("assets/vehicles/flatbed_cargo_crates.svg", 216, 120, cg)
    save("assets/vehicles/flatbed_cargo_parts.svg", 216, 120, parts_pallet(14, 26, 58, 27) + parts_pallet(80, 26, 58, 27))
    save("assets/vehicles/truck_cargo_parts.svg", 264, 120, parts_pallet(12, 22, 54, 27) + parts_pallet(70, 22, 54, 27) + parts_pallet(128, 22, 54, 27))
    cg = path("M10 50Q24 30 52 34Q76 20 104 30Q130 18 156 32Q176 32 184 50Z", "#6e6a64", OUT, 1.6)
    for k in range(26):
        x = 16 + (k * 37) % 164
        y = 36 + (k * 13) % 12
        cg += path(f"M{x} {y}q4 -5 8 0t8 0", None, "#c7cdd0" if k % 3 else "#b07a4a", 1.4, 0.9)
    for x, y, a in ((40, 34, 8), (90, 26, 6), (140, 30, 7)):
        cg += rect(x, y, 22, 5, STEEL_D, OUT, 1, 1) + circ(x + a, y + 9, 5, STEEL, OUT, 1)
    save("assets/vehicles/truck_cargo_scrap.svg", 264, 120, cg)


def people():
    """Боёвка пожарного (основа тонируется в тёмный цвет, светоотражающие полосы — свои),
    пожарный ствол, короб со стружкой."""
    Y, S = "#d8df3a", "#d9dde0"

    def stripes(x0, x1, ys):
        s = ""
        for y in ys:
            s += rect(x0, y, x1 - x0, 5, Y, None, 0) + rect(x0, y + 1.6, x1 - x0, 1.8, S, None, 0)
        return s
    person_layer("outfit_fireman_front", stripes(-23, 23, (-3, 13)) + path("M0 -19V25", None, "#000", 1.6, 0.4)
                 + poly([(-8, -19), (0, -11), (8, -19)], "#1c2026", OUT, 0.8) + rect(-20, -19, 8, 4, Y, None, 0) + rect(12, -19, 8, 4, Y, None, 0))
    person_layer("outfit_fireman_back", stripes(-23, 23, (-3, 13)) + rect(-14, -16, 28, 10, "#1c2026", None, 0, 2, 0.5))
    person_layer("outfit_fireman_side", stripes(-17, 17, (-3, 13)))

    def prop(key, body):
        save(f"assets/people/prop_{key}.svg", 32, 32, body)
    prop("nozzle", path("M4 30Q6 22 12 18", None, "#d8d2c0", 4.2) + path("M4 30Q6 22 12 18", None, "#a8a290", 1.4)
         + rect(10, 13, 10, 8, "#2a2e31", OUT, 1.2, 2) + poly([(19, 14), (29, 15.5), (29, 18.5), (19, 20)], "#d9b13b", OUT, 1.2)
         + rect(13, 10, 3, 4, "#c9372c", OUT, 0.8))
    prop("chips", path("M4 12H28L26 28H6Z", "#5a6a7a", OUT, 1.4) + rect(3, 10, 26, 4, "#6f8090", OUT, 1.2)
         + path("M7 11q3 -5 6 0t6 0t6 0", None, "#c7cdd0", 1.6) + path("M9 9q2 -3 4 0", None, "#b07a4a", 1.2))


def run():
    fire_truck()
    cargo()
    people()
    print("1.30: пожарная машина, грузы в кузовах, боёвка пожарного — готово")


if __name__ == "__main__":
    run()
