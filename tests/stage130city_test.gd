extends SceneTree
## Тест версии 1.30 «Улица и город»: зебры и остановки за краем карты, расписание автобуса,
## люди идут от подъезда/автобуса и приходят к краю карты ровно к выходу на смену, уходят к подъезду или на автобус;
## улица не трогает симуляцию (sim.rng, время прихода).
## godot --headless --path . -s res://tests/stage130city_test.gd

const T := World.T

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_garage(130)
	var w := sim.world
	var bd := CityBackdrop.new()
	bd.sim = sim
	# подъезды первого ряда домов: слева и справа от участка (как их записывает CityBackdrop)
	for x: float in [-30.0, -12.0, 3.0, w.w - 2.0, w.w + 12.0, w.w + 30.0]:
		bd.doors.append({"door": Vector2(x * T, (w.h + 4.6) * T), "yard_y": (w.h + 6.5) * T, "lx": (x - 4.0) * T, "rx": (x + 5.0) * T, "top": (w.h + 2) * T})
	var sf := StreetFolk.new()
	sf.sim = sim
	sf.backdrop = bd
	sf.ents = Node2D.new()

	print("— улица за краем карты")
	for sd: int in [-1, 1]:
		var xc := StreetFolk.cross_x(w, sd)
		var xs := StreetFolk.stop_x(w, sd)
		check(xc < -3 or xc >= w.w + 3, "зебра (%d) за краем карты и не на въезде боковой улицы" % xc)
		check(StreetFolk.zebra_at(w, xc) == sd and StreetFolk.zebra_at(w, xc + 1) == sd, "зебра шириной в две клетки")
		check(xs < 0 or xs >= w.w, "остановка (%d) за краем карты" % xs)
		check(StreetFolk.platform_at(w, xs) and StreetFolk.zebra_at(w, xs) == 0, "у остановки — плитка, зебры там нет")
		check(absi(xs) > absi(xc) if sd < 0 else xs > xc, "остановка дальше зебры от участка")
	check(StreetFolk.side_street_at(w, -1) and StreetFolk.side_street_at(w, w.w) and not StreetFolk.side_street_at(w, 5), "въезды боковых улиц — у краёв участка")
	check(StreetFolk.zebra_at(w, 10) == 0, "на участке зебр нет — разметка дороги не прерывается")

	print("— автобус по расписанию")
	var sch := sf._schedule()
	var p := float(sch["p"])
	check(p >= 40.0 and p < 80.0, "период автобуса %.0f мин" % p)
	for sd2: int in [-1, 1]:
		var d1 := sf.next_dwell(sd2, 1000.0)
		check(d1 + StreetFolk.DWELL >= 1000.0 and d1 - 1000.0 <= p, "следующая стоянка (%d) — не раньше нужного и в пределах периода" % sd2)
		check(absf(sf._bus_at(d1 + 0.5) - sf._xs(sd2)) < 0.01, "во время стоянки автобус у павильона (%d)" % sd2)
		var d0 := sf.prev_dwell(sd2, 1000.0)
		check(d0 <= 1000.0 and 1000.0 - d0 < p, "предыдущая стоянка (%d)" % sd2)
	var prev := -INF
	var mono := true
	for i in 200:
		var bx := sf._bus_at(float(i) * p / 200.0)
		if is_nan(bx):
			continue
		mono = mono and bx >= prev - 0.01
		prev = bx
	check(mono, "автобус едет в одну сторону (вправо, по южной полосе)")

	print("— приход на смену")
	var rs := sim.rng.state
	var wk: Worker = sim.workers[0]
	wk.present = false
	wk.exit_cell = Vector2i(0, w.sidewalk_row)
	var exit_px := (Vector2(wk.exit_cell) + Vector2(0.5, 0.5)) * T
	var n_bus := 0
	var n_door := 0
	for k in 12:
		wk.id = 300 + k
		var a := 1440.0 * 2.0 + 470.0 + float(k)
		var tr := sf._arrival(wk, -1, a)
		check(absf(float(tr["te"]) - a) < 0.05, "id %d: дошёл до края карты к выходу на смену (%.2f / %.2f)" % [wk.id, float(tr["te"]), a])
		var ps := sf._pose_of(tr, a - 0.001)
		check(not ps.is_empty() and (ps[0] as Vector2).distance_to(exit_px) < 3.0, "id %d: перед выходом — у самого края участка" % wk.id)
		var pre := str(tr["pre"])
		if pre == "bus":
			n_bus += 1
			var t0 := float(tr["t0"])
			check(absf(sf._bus_at(t0 - 0.3) - sf._xs(-1)) < 0.01, "id %d: вышел из автобуса, когда тот стоял на остановке" % wk.id)
		else:
			n_door += 1
			var ps0 := sf._pose_of(tr, float(tr["t0"]) - 0.25)
			check(not ps0.is_empty() and float(ps0[3]) < 1.0 and sf._open.size() > 0, "id %d: выходит из подъезда — дверь открыта" % wk.id)
		var early := sf._pose_of(tr, float(tr["t0"]) - 2.0)
		check(early.is_empty(), "id %d: до выхода из дома его на улице нет" % wk.id)
	check(n_door > 0, "кто-то идёт из подъездов (%d)" % n_door)
	print("  автобусом: %d, из подъездов: %d" % [n_bus, n_door])

	print("— уход со смены")
	sf._vm = 1440.0 * 2.0 + 1030.0
	var ends_door := 0
	var ends_bus := 0
	for k2 in 12:
		wk.id = 500 + k2
		sf._depart(wk, -1, PackedVector2Array([exit_px]), 7)
		var tr2: Dictionary = sf._trips[wk.id]
		var pts: PackedVector2Array = tr2["pts"]
		var ok := true
		for q in pts:
			var inside := q.x > 0.0 and q.x < w.w * T and q.y < w.h * T
			if inside and absf(q.y - sf._yn()) > 0.5:
				ok = false
		check(ok, "id %d: путь идёт по улице за участком (без срезов по заводу)" % wk.id)
		check(pts[0].distance_to(exit_px) < 0.5, "id %d: начинает путь там, где ушёл с участка" % wk.id)
		var post := str(tr2["post"])
		if post == "door":
			ends_door += 1
			var te := float(tr2["te"])
			var pa := sf._pose_of(tr2, te + 0.25)
			check(not pa.is_empty() and float(pa[3]) < 1.0 and sf._open.has(int(tr2["db"])), "id %d: входит в подъезд — дверь открыта, тает" % wk.id)
			tr2.erase("done")
			sf._pose_of(tr2, te + 0.6)
			check(tr2.has("done"), "id %d: зашёл в дом — пропал" % wk.id)
		else:
			ends_bus += 1
			var tb := float(tr2["tb"])
			check(tb >= float(tr2["te"]) and absf(sf._bus_at(tb + 0.01) - sf._xs(-1)) < 0.01, "id %d: садится, когда автобус стоит на остановке" % wk.id)
			check(not sf._pose_of(tr2, tb - 0.01).is_empty(), "id %d: ждёт автобус на остановке" % wk.id)
		sf._trips.erase(wk.id)
	check(ends_door > 0 and ends_bus > 0, "одни идут домой (%d), другие на автобус (%d)" % [ends_door, ends_bus])

	print("— автобус не наезжает на пешеходов на «зебре»")
	var hits := 0
	var holds := 0
	for k4 in 60:
		wk.id = 700 + k4
		sf._vm = 1440.0 * 4.0 + 1000.0 + float(k4) * 1.7
		var sd4 := -1 if k4 % 2 == 0 else 1
		var ex4 := (Vector2(0 if sd4 < 0 else w.w - 1, w.sidewalk_row) + Vector2(0.5, 0.5)) * T
		sf._depart(wk, sd4, PackedVector2Array([ex4]), 7)
		var tr4: Dictionary = sf._trips[wk.id]
		if float(tr4.get("hd", 0.0)) > 0.0:
			holds += 1
		var tt := float(tr4["t0"])
		while tt < float(tr4["te"]):
			var ps4 := sf._pose_of(tr4, tt)
			var bx := sf._bus_at(tt)
			if not ps4.is_empty() and not is_nan(bx):
				var pp: Vector2 = ps4[0]
				if absf(pp.y - sf._yb()) < 0.55 * T and absf(pp.x - bx) < 2.7 * T:
					hits += 1
			tt += 0.05
		sf._trips.erase(wk.id)
	for k5 in 60:
		wk.id = 900 + k5
		wk.exit_cell = Vector2i(0 if k5 % 2 == 0 else w.w - 1, w.sidewalk_row)
		var tr5 := sf._arrival(wk, -1 if k5 % 2 == 0 else 1, 1440.0 * 5.0 + 440.0 + float(k5) * 0.9)
		var tt5 := float(tr5["t0"])
		while tt5 < float(tr5["te"]):
			var ps5 := sf._pose_of(tr5, tt5)
			var bx5 := sf._bus_at(tt5)
			if not ps5.is_empty() and not is_nan(bx5):
				var pp5: Vector2 = ps5[0]
				if absf(pp5.y - sf._yb()) < 0.55 * T and absf(pp5.x - bx5) < 2.7 * T:
					hits += 1
			tt5 += 0.05
	wk.exit_cell = Vector2i(0, w.sidewalk_row)
	check(hits == 0, "никто не оказался под автобусом (%d)" % hits)
	print("  ждали у бордюра, пока проедет автобус: %d из 60" % holds)

	print("— горожане")
	var fr: Array[int] = [0, 1, 2, 3, 4, 5]
	var vis := 0
	for k3 in 30:
		var trf := sf._folk_trip(wk, k3, 7, 1440.0 * 3.0 + 600.0, fr)
		if trf.is_empty():
			continue
		var tt := float(trf["t0"]) + 1.0
		if not sf._pose_of(trf, tt).is_empty():
			vis += 1
	check(vis >= 20, "горожане ходят между подъездами и остановкой (%d из 30)" % vis)

	print("— симуляция не тронута")
	check(sim.rng.state == rs, "улица не берёт числа из sim.rng")

	sf.ents.free()
	sf.free()
	bd.free()
	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for f in fails:
			print("  ✗ ", f)
	quit(0 if fails.is_empty() else 1)
