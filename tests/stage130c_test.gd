extends SceneTree
## Тест версии 1.30 «Проходная»: будка охранника и два турникета одним объектом (4×1) — в заборе у ворот,
## люди приходят и уходят через турникеты, охранник сидит в будке, досмотр — только при охраннике,
## сохранение и старые сохранения (проходная 2×1).
## godot --headless --path . -s res://tests/stage130c_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


## Гоняем симуляцию и записываем клетки, которые прошёл каждый человек с момента прихода до первой
## клетки внутри участка (вход) и с последней клетки внутри до ухода (выход).
var entered: Dictionary = {}   ## id -> через какую клетку турникета вошёл (Vector2i(-1,-1) — мимо)
var left: Dictionary = {}      ## id -> через какую клетку вышел
var _trail: Dictionary = {}    ## id -> клетки пути за пределами участка
var _was_in: Dictionary = {}
var seated_seen := false
var seated_ok := false


func _track(sim: Sim, ts: Array[Vector2i], seat: Vector2i) -> void:
	for w in sim.workers:
		if not w.present:
			if _was_in.has(w.id):
				# ушёл: смотрим, через что выходил
				var tr: Array = _trail.get(w.id, [])
				var via := Vector2i(-1, -1)
				for c: Vector2i in tr:
					if ts.has(c):
						via = c
				left[w.id] = via
				_was_in.erase(w.id)
			_trail.erase(w.id)
			continue
		var c := w.cell()
		var inside := sim.world.in_plot(c)
		if not _trail.has(w.id):
			_trail[w.id] = []
		if inside:
			if not _was_in.has(w.id):
				var tr2: Array = _trail[w.id]
				var via2 := Vector2i(-1, -1)
				for c2: Vector2i in tr2:
					if ts.has(c2):
						via2 = c2
				if not tr2.is_empty():
					entered[w.id] = via2
				_was_in[w.id] = true
			_trail[w.id] = []
		else:
			(_trail[w.id] as Array).append(c)
		if w.prof == "guard" and w.has_meta("booth"):
			seated_seen = true
			if c == seat and w.anim == "sit" and w.task and w.task.kind == "guard":
				seated_ok = true


func _run(sim: Sim, minutes: float, ts: Array[Vector2i], seat: Vector2i) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(0.5)
		_track(sim, ts, seat)


func _init() -> void:
	Defs.load_all()
	print("— данные и графика")
	var d: Dictionary = Defs.objects.get("checkpoint", {})
	var sz: Array = d.get("size", [])
	check(sz.size() == 2 and int(sz[0]) == 4 and int(sz[1]) == 1, "проходная 4×1: будка и два турникета")
	check((d.get("walk", []) as Array).size() == 2 and (d.get("seat", []) as Array).size() == 2, "две проходимые клетки турникетов и место охранника")
	check(str(d.get("desc", "")).contains("охранник") and str(d.get("desc", "")).contains("турникет"), "в описании — турникеты и охранник")
	for k in ["checkpoint", "checkpoint_v", "checkpoint_b", "checkpoint_in", "checkpoint_v_in", "checkpoint_b_in"]:
		var m: Dictionary = Defs.sprites.get(k, {})
		check(not m.is_empty() and FileAccess.file_exists(str(m.get("file", ""))), "спрайт %s есть" % k)
	for k2 in ["checkpoint", "checkpoint_v", "checkpoint_b"]:
		var an: Dictionary = (Defs.sprites.get(k2, {}) as Dictionary).get("anchors", {})
		check(an.has("hub1") and an.has("hub2"), "%s: оси планок турникетов" % k2)
	check(Thing.rotations("checkpoint") == 4, "проходную можно поворачивать на все четыре стороны")
	check(FileAccess.file_exists("res://assets/sound/turnstile.ogg"), "щелчок турникета")
	var svg := FileAccess.get_file_as_string("res://assets/objects/checkpoint.svg")
	check(svg.length() > 1000 and not svg.contains("#e8c9a8"), "на спрайте нет нарисованного лица (вахтёрши)")

	print("— установка в забор у ворот")
	var sim := Scenario.new_game("garage", "mech", "calm", 130)
	sim.story.enabled = false
	sim.progress.stage = maxi(sim.progress.stage, 2)
	sim.money += 500000.0
	var wd := sim.world
	var fy := wd.plot.end.y
	var c0 := Vector2i(sim.gate_x - 4, fy)
	check(wd.get_wall(c0) == World.W_FENCE, "у ворот — забор")
	check(sim.can_place("checkpoint", c0) == "", "проходную можно поставить прямо в забор: %s" % sim.can_place("checkpoint", c0))
	check(sim.can_place("checkpoint", Vector2i(sim.gate_x - 1, fy)) != "", "на ворота для машин — нельзя")
	check(sim.can_place("checkpoint", Vector2i(sim.gate_x - 4, fy + 2)) != "", "посреди тротуара — нельзя")
	var inner_ok := false
	for y in range(wd.plot.position.y + 2, fy - 1):
		for x in range(wd.plot.position.x + 1, wd.plot.end.x - 4):
			if not inner_ok and sim.can_place("checkpoint", Vector2i(x, y)) == "":
				inner_ok = true
	check(inner_ok, "и по-старому, внутри участка, тоже можно")
	var cp := sim.place_thing("checkpoint", c0, true, false)
	var ts := cp.walk_cells()
	var seat := cp.seat_cell()
	check(ts == [Vector2i(c0.x + 2, fy), Vector2i(c0.x + 3, fy)] and seat == Vector2i(c0.x + 1, fy), "турникеты %s, будка %s" % [str(ts), str(seat)])
	var opened := true
	for cc in cp.cells():
		opened = opened and wd.get_wall(cc) == World.W_NONE
	check(opened, "забор под проходной убран")
	check(wd.passable(ts[0]) and wd.passable(ts[1]), "через турникеты можно пройти")
	check(not wd.passable(seat) and not wd.passable(c0), "сквозь будку — нельзя")
	check(sim.crew.post() == cp and sim.crew.turnstiles() == ts, "проходная — пост охраны, турникеты известны")
	var p := sim.crew.gate_path(Vector2i(0, wd.sidewalk_row), Vector2i(sim.gate_x, fy - 4))
	check(not p.is_empty() and (p.has(ts[0]) or p.has(ts[1])), "путь с улицы на участок — через турникет")
	check(sim.crew.gate_path(Vector2i(sim.gate_x, fy - 4), Vector2i(sim.gate_x + 2, fy - 6)).is_empty(), "по участку — обычный путь, без крюка")

	print("— без охранника: турникеты работают, досмотра нет")
	sim.story.guard = true
	check(sim.crew.guards().is_empty() and not sim.crew.search_on(), "досмотр включён, но охранника нет — не работает")
	check(sim.crew.detect_k() == 0.0, "шанс поймать несуна без охраны — 0")
	_run(sim, 1440.0 + 600.0 - fmod(sim.minute, 1440.0), ts, seat)
	var n_in := 0
	var n_ts := 0
	for id: int in entered.keys():
		n_in += 1
		if ts.has(entered[id] as Vector2i):
			n_ts += 1
	check(n_in >= 3, "люди пришли на смену: %d" % n_in)
	check(n_ts == n_in, "все вошли через турникеты: %d из %d" % [n_ts, n_in])
	var via_far := 0
	for id2: int in entered.keys():
		if entered[id2] == ts[1]:
			via_far += 1
	check(via_far == n_in, "на вход — дальний от будки турникет")
	_run(sim, 1440.0 + 60.0 - fmod(sim.minute, 1440.0), ts, seat)
	var n_out := 0
	var n_out_ts := 0
	for id3: int in left.keys():
		n_out += 1
		if left[id3] == ts[0]:
			n_out_ts += 1
	check(n_out >= 3 and n_out_ts == n_out, "домой — через ближний турникет: %d из %d" % [n_out_ts, n_out])

	print("— охранник в будке")
	var g := S.hire(sim, "guard", "security", 6)
	g.shift = 0
	check(not sim.crew.search_on(), "охранник ещё не пришёл — досмотра нет")
	var on_seen := false
	var end := sim.minute + 1440.0
	while sim.minute < end and not seated_ok:
		sim.tick(0.5)
		_track(sim, ts, seat)
		if g.present and sim.crew.search_on():
			on_seen = true
	check(seated_ok, "охранник на смене сидит в будке (клетка %s)" % str(seat))
	check(g.pos.distance_to(Vector2(seat) + Brain.BOOTH_SEAT) < 0.01, "сидит у окна: %s" % str(g.pos))
	check(on_seen and sim.crew.search_on(), "охранник на посту — досмотр работает")
	check(sim.crew.detect_k() >= 0.85, "шанс поймать несуна: %d%%" % int(sim.crew.detect_k() * 100.0))
	sim.brain.abort(g)
	check(not g.has_meta("booth") and sim.world.passable(g.cell()), "встал — вышел из будки к турникету")

	print("— сохранение")
	var s2 := Sim.from_dict(JSON.parse_string(JSON.stringify(sim.to_dict())))
	var cp2 := s2.crew.post()
	check(cp2 != null and cp2.cell == c0 and cp2.walk_cells() == ts, "проходная на месте")
	check(s2.world.passable(ts[0]) and s2.world.passable(ts[1]) and not s2.world.passable(seat), "турникеты проходимы, будка — нет")
	check(s2.world.get_wall(c0) == World.W_NONE and s2.story.guard, "проём в заборе и досмотр сохранились")

	print("— снос: забор заделывается")
	sim.remove_thing(cp, 0.0)
	var closed := true
	for x2 in range(c0.x, c0.x + 4):
		closed = closed and wd.get_wall(Vector2i(x2, fy)) == World.W_FENCE
	check(closed and not wd.passable(ts[0]), "снесли проходную — на её месте снова забор")
	check(sim.crew.turnstiles().is_empty() and sim.crew.gate_path(Vector2i(0, wd.sidewalk_row), Vector2i(sim.gate_x, fy - 4)).is_empty(), "без проходной — обычные пути")

	print("— монтаж в заборе")
	var cp3 := sim.place_thing("checkpoint", c0, false, true)
	check(wd.get_wall(c0) == World.W_FENCE and not cp3.built, "заказана: пока стоит забор")
	var end3 := sim.minute + 1440.0 * 4.0
	while sim.minute < end3 and not cp3.built:
		sim.tick(0.5)
	check(cp3.built and wd.get_wall(c0) == World.W_NONE and wd.passable(cp3.walk_cells()[1]), "рабочие смонтировали проходную в заборе")

	print("— старое сохранение: проходная 2×1")
	var o := Scenario.new_game("garage", "mech", "calm", 131)
	o.story.enabled = false
	o.progress.all_open = true
	var spot := Vector2i(-1, -1)
	for y3 in range(o.world.plot.position.y + 2, o.world.plot.end.y - 2):
		for x3 in range(o.world.plot.position.x + 2, o.world.plot.end.x - 8):
			if spot.x < 0 and o.can_place("checkpoint", Vector2i(x3, y3)) == "" and o.can_place("rack", Vector2i(x3 + 2, y3)) == "":
				spot = Vector2i(x3, y3)
	var rack := o.place_thing("rack", spot + Vector2i(2, 0), true, false)
	var nid := o.new_id()
	var od := o.to_dict()
	(od["things"] as Array).append({"id": nid, "def": "checkpoint", "cx": spot.x, "cy": spot.y, "built": true, "paid": 45000.0, "rot": 0})
	var o2 := Sim.from_dict(JSON.parse_string(JSON.stringify(od)))
	var oc: Thing = o2.things.get(nid)
	check(oc != null, "старая проходная загрузилась")
	if oc:
		var clash := false
		for cc2 in oc.cells():
			clash = clash or o2.world.occ[o2.world.idx(cc2)] != oc.id
		check(not clash and oc.cell != spot, "стала 4×1 и не налезла на стеллаж: сдвинута с %s на %s" % [str(spot), str(oc.cell)])
		check(o2.things.has(rack.id) and o2.things.size() == o.things.size() + 1, "остальные объекты на месте")
		check(o2.world.occ[o2.world.idx(rack.cell)] == rack.id, "стеллаж на месте")
		check(o2.world.passable(oc.walk_cells()[0]) and not o2.world.passable(oc.seat_cell()), "у старой — тоже турникеты и будка")
	var o3 := Sim.from_dict(JSON.parse_string(JSON.stringify(o2.to_dict())))
	check(o3.things.has(nid) and (o3.things[nid] as Thing).cell == oc.cell, "после пересохранения не двигается")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
