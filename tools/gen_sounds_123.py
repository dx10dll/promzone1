#!/usr/bin/env python3
"""1.23: новые звуки «Промзоны» — фон помещений и случайные звуки рядом с камерой.

Запуск: python3 tools/gen_sounds_123.py  (из корня проекта; нужны numpy, scipy и ffmpeg)
Старые звуки не трогает (их делает gen_sounds.py). Всё синтезируется.
Петли (имена на amb_/m_) бесшовные; остальное — короткие эффекты.
"""
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sounds as g  # noqa: E402
from gen_sounds import SR, secs, loop_noise, band, tone, lfo, harmonics, env_decay, lowpass, highpass, clicks, fade, save, bell  # noqa: E402

rng = np.random.default_rng(2310)
g.rng = rng


def put(buf, x, pos, circular=True):
    n = len(buf)
    idx = (pos + np.arange(len(x)))
    if circular:
        buf[idx % n] += x
    else:
        idx = idx[idx < n]
        buf[idx] += x[:len(idx)]


def clink(f=None, dur=0.35):
    """Звяканье посуды: металл/фаянс — несколько негармонических обертонов, быстрое затухание."""
    f = f or rng.uniform(2200, 4200)
    return bell(f, dur, ((1, 1.0), (1.48, 0.6), (2.31, 0.4), (3.7, 0.2)), tau=rng.uniform(0.05, 0.12))


def murmur(n, voices=10, lo=120, hi=260):
    """Неразборчивый гомон: полосовой шум с «слоговыми» огибающими."""
    x = np.zeros(n)
    for _ in range(voices):
        f0 = rng.uniform(lo, hi)
        x += loop_noise(n, band(f0 * 2, f0 * 7, 0.5)) * lfo(rng.uniform(2.5, 5.0), n, 1.0, 0.0) ** 2 * lfo(rng.uniform(0.2, 0.5), n, 1.0, 0.0)
    return lowpass(x, 2200)


def loops():
    n = secs(8.0)
    # столовая: гомон, звяканье ложек и тарелок, шипение плиты
    can = 0.6 * murmur(n, 12)
    for _ in range(26):
        put(can, clink() * rng.uniform(0.25, 0.7), rng.integers(0, n))
    for _ in range(3):
        k = secs(0.5)
        put(can, lowpass(rng.standard_normal(k), 700) * np.hanning(k) * 0.35, rng.integers(0, n))   # двигают стул
    can += 0.12 * loop_noise(n, band(2500, 7000, 0.3))
    save("amb_canteen", can, 0.5)
    # бытовка и душевая: вода, хлопают дверцы шкафчиков, разговор
    water = 0.45 * loop_noise(n, band(1200, 8000, 0.25)) * lfo(0.3, n, 0.3, 0.7)
    lock = np.zeros(n)
    for _ in range(6):
        k = secs(0.4)
        tt = np.arange(k) / SR
        bang = (np.sin(2 * np.pi * 180 * tt) * 0.5 + lowpass(rng.standard_normal(k), 2500) * 0.6) * env_decay(k, 0.04)
        bang += bell(rng.uniform(600, 900), 0.4, ((1, 0.5), (2.6, 0.3), (4.1, 0.15)), tau=0.1)
        put(lock, bang * rng.uniform(0.5, 1.0), rng.integers(0, n))
    save("amb_locker", water + lock + 0.35 * murmur(n, 5), 0.5)
    # контора: печатная машинка очередями, щелчки калькулятора, тихий гул ламп
    off = 0.06 * harmonics(100, n, [0.6, 0.3, 0.2])
    for _ in range(5):
        p = rng.integers(0, n)
        for j in range(rng.integers(6, 16)):
            k = secs(0.05)
            hit = (lowpass(rng.standard_normal(k), 4000) * 0.8 + np.sin(2 * np.pi * 1300 * np.arange(k) / SR) * 0.3) * env_decay(k, 0.008)
            put(off, hit * rng.uniform(0.5, 1.0), p + j * secs(rng.uniform(0.09, 0.16)))
        put(off, bell(2600, 0.4, tau=0.15) * 0.4, p + secs(2.2))     # звоночек каретки
    put(off, 0.2 * murmur(n, 3)[:n], 0)
    save("amb_office", off, 0.4)
    # цех: общий гул (вентиляция, компрессор вдали), редкий лязг железа
    shop = 0.5 * lowpass(loop_noise(n, lambda f: 1 / f), 350) + 0.25 * harmonics(50, n, [0.5, 0.4, 0.2, 0.1])
    shop += 0.15 * loop_noise(n, band(800, 2500)) * lfo(0.2, n, 0.5, 0.5)
    for _ in range(4):
        cl = bell(rng.uniform(300, 700), 1.0, ((1, 1.0), (2.76, 0.6), (5.4, 0.35)), tau=0.25) * rng.uniform(0.3, 0.6)
        put(shop, cl, rng.integers(0, n))
    save("amb_shop", shop, 0.5)
    # котельная, компрессорная, техпомещение: низкий рокот, гул насосов
    save("amb_boiler", 0.7 * lowpass(loop_noise(n, lambda f: 1 / f), 200) * lfo(0.4, n, 0.2, 0.8) + 0.35 * harmonics(25, n, [0.6, 0.5, 0.4, 0.2]) + 0.15 * tone(150, n), 0.5)
    # город при отдалении: шум улиц, далёкие гудки, поезд
    city = 0.6 * lowpass(loop_noise(n, lambda f: 1 / f), 400) * lfo(0.15, n, 0.4, 0.6) + 0.2 * loop_noise(n, band(300, 1500))
    for _ in range(2):
        k = secs(0.5)
        tt = np.arange(k) / SR
        hn = (np.sign(np.sin(2 * np.pi * rng.uniform(380, 480) * tt)) * 0.3) * np.hanning(k)
        put(city, lowpass(hn, 1500) * 0.25, rng.integers(0, n))
    save("amb_city", city, 0.45)
    # поезд: стук колёс на стыках
    tr = 0.4 * lowpass(loop_noise(n, lambda f: 1 / f), 300)
    for i in range(16):
        p = int(i * n / 16)
        for d in (0, secs(0.12)):
            k = secs(0.12)
            put(tr, (lowpass(rng.standard_normal(k), 1200) * 0.8 + np.sin(2 * np.pi * 90 * np.arange(k) / SR) * 0.5) * env_decay(k, 0.025), p + d)
    save("amb_train", tr, 0.55)
    # болгарка: вой диска и визг по металлу
    m = secs(2.4)
    gr = 0.35 * tone(610, m) + 0.2 * tone(1220, m) + 0.5 * loop_noise(m, band(3000, 9000, 0.2)) * lfo(1.5, m, 0.5, 0.5) + 0.2 * harmonics(50, m, [0.4, 0.2])
    save("m_grinder", gr, 0.6)


def oneshots():
    # болгарка очередью: разгон, рез, остановка
    k = secs(1.6)
    tt = np.arange(k) / SR
    f = np.interp(tt, [0, 0.25, 1.3, 1.6], [150, 640, 600, 200])
    ph = 2 * np.pi * np.cumsum(f) / SR
    body = 0.4 * np.sin(ph) + 0.2 * np.sin(2 * ph)
    cut = highpass(rng.standard_normal(k), 3000) * ((tt > 0.35) & (tt < 1.25)) * 0.7
    save("grinder", fade(lowpass(body + cut, 9000) * np.minimum(1, (1.6 - tt) * 4)), 0.55)
    # лязг металла (уронили деталь, бросили пруток)
    for i, f0 in enumerate([520, 740]):
        cl = bell(f0, 0.9, ((1, 1.0), (2.76, 0.7), (5.4, 0.45), (8.9, 0.25)), tau=0.22)
        cl[:secs(0.02)] += rng.standard_normal(secs(0.02)) * 0.6
        save("clank%d" % (i + 1), cl, 0.55)
    # удар молотком по металлу
    save("anvil", bell(1250, 0.7, ((1, 1.0), (2.2, 0.5), (3.9, 0.3)), tau=0.15) + np.concatenate([rng.standard_normal(secs(0.01)), np.zeros(secs(0.69))]) * 0.5, 0.5)
    # погрузчик: пищалка заднего хода
    k = secs(1.5)
    tt = np.arange(k) / SR
    save("beeper", np.sin(2 * np.pi * 1200 * tt) * ((tt % 0.5) < 0.25) * 0.5, 0.35)
    # посуда
    k = secs(0.6)
    x = np.zeros(k)
    for j in range(3):
        put(x, clink() * (1 - j * 0.25), secs(j * rng.uniform(0.06, 0.14)), circular=False)
    save("dishes", x, 0.45)
    # чайник засвистел (в столовой и комнате отдыха)
    k = secs(1.4)
    tt = np.arange(k) / SR
    save("kettle", fade(np.sin(2 * np.pi * 2300 * tt * (1 + 0.02 * tt)) * np.minimum(1, tt * 2) + 0.2 * highpass(rng.standard_normal(k), 4000)), 0.3)
    # телефон в конторе
    k = secs(1.3)
    tt = np.arange(k) / SR
    ring = (np.sin(2 * np.pi * 440 * tt) + np.sin(2 * np.pi * 480 * tt)) * (np.sin(2 * np.pi * 20 * tt) > 0) * ((tt < 0.4) | ((tt > 0.6) & (tt < 1.0)))
    save("phone", ring, 0.3)
    # хлопнула дверь
    k = secs(0.35)
    save("door", (np.sin(2 * np.pi * 110 * np.arange(k) / SR) * 0.6 + lowpass(rng.standard_normal(k), 1500) * 0.5) * env_decay(k, 0.05), 0.5)
    # голуби: хлопанье крыльев и воркование
    k = secs(0.7)
    flap = np.zeros(k)
    for j in range(8):
        kk = secs(0.04)
        put(flap, highpass(rng.standard_normal(kk), 800) * np.hanning(kk) * (1 - j * 0.1), j * secs(0.075), circular=False)
    save("pigeon_flap", flap, 0.4)
    k = secs(0.9)
    tt = np.arange(k) / SR
    coo = np.sin(2 * np.pi * (330 + 40 * np.sin(2 * np.pi * 3 * tt)) * tt) * (np.sin(np.pi * tt / 0.9) ** 2) * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt))
    save("pigeon_coo", lowpass(coo, 900), 0.35)
    # кот мяукает
    k = secs(0.7)
    tt = np.arange(k) / SR
    f = np.interp(tt, [0, 0.2, 0.5, 0.7], [520, 760, 640, 480])
    ph = 2 * np.pi * np.cumsum(f) / SR
    meow = (np.sin(ph) + 0.5 * np.sin(2 * ph) + 0.3 * np.sin(3 * ph)) * np.sin(np.pi * tt / 0.7) ** 1.5
    save("meow", lowpass(meow, 3000), 0.4)
    # мышь пищит
    k = secs(0.25)
    tt = np.arange(k) / SR
    save("squeak", np.sin(2 * np.pi * (5200 + 800 * np.sin(2 * np.pi * 14 * tt)) * tt) * np.hanning(k), 0.25)
    # гудок тепловоза
    k = secs(1.8)
    tt = np.arange(k) / SR
    hn = sum(a * np.sin(2 * np.pi * f0 * tt) for f0, a in [(311, 1.0), (370, 0.8), (466, 0.6), (622, 0.3)])
    save("train_horn", lowpass(hn * np.minimum(1, tt * 8) * np.minimum(1, (1.8 - tt) * 4), 2000), 0.45)
    # гудок машины
    k = secs(0.35)
    tt = np.arange(k) / SR
    save("car_horn", lowpass(np.sign(np.sin(2 * np.pi * 420 * tt)) * 0.4 * np.minimum(1, tt * 60) * np.minimum(1, (0.35 - tt) * 30), 1800), 0.35)
    # кашель / смех вдалеке — шумовые «слоги»
    k = secs(0.6)
    x = np.zeros(k)
    for j in range(3):
        kk = secs(0.12)
        put(x, lowpass(rng.standard_normal(kk), 1600) * np.hanning(kk) * (1 - j * 0.25), j * secs(0.17), circular=False)
    save("cough", x, 0.35)
    # скрип тележки
    k = secs(0.8)
    tt = np.arange(k) / SR
    save("cart", (0.3 * np.sin(2 * np.pi * (900 + 300 * np.sin(2 * np.pi * 2 * tt)) * tt) + 0.4 * lowpass(rng.standard_normal(k), 500)) * np.hanning(k), 0.35)
    # пар/воздух: сброс давления компрессора
    k = secs(0.9)
    save("hiss", highpass(rng.standard_normal(k), 2500) * env_decay(k, 0.3), 0.35)
    # краска из баллончика
    k = secs(0.8)
    save("spray", highpass(rng.standard_normal(k), 4000) * np.hanning(k), 0.3)


def main():
    loops()
    oneshots()
    print("1.23: звуки готовы")


if __name__ == "__main__":
    main()
