class_name Fauna
extends RefCounted
## 1.22: живность вокруг завода.
## — Голуби: днём прилетают во двор, ходят и клюют, разлетаются от людей, машин и кота; иногда залетают
##   в цех через открытые ворота и через какое-то время улетают. На ночь улетают совсем.
## — Мыши: заводятся в очень грязных помещениях, бегают вдоль стен; люди недовольны, проверка придерётся.
## — Кот охотится: подкрадывается к голубю или мыши и прыгает. Голуби обычно успевают улететь, мышей кот ловит.
## Своя случайность (rng) — не сбивает остальную симуляцию.

const MAX_PIGEONS := 7
const MAX_MICE := 4
const MOUSE_DIRT := 130.0       ## средняя грязь помещения (0–255), с которой заводятся мыши
const PIGEON_SPEED := 1.1       ## клеток в минуту пешком
const FLY_SPEED := 14.0         ## клеток в минуту в полёте

var sim: Sim
var rng := RandomNumberGenerator.new()
var pigeons: Array = []         ## [{pos: Vector2, to: Vector2, st: walk|peck|fly|gone, until, dir, fly_t, inside}]
var mice: Array = []            ## [{pos, to, room, st: run|hide, until, dir}]
var caught_mice := 0
var caught_pigeons := 0
var _t := 0.0
var _spawn_t := 0.0


func _init(s: Sim) -> void:
	sim = s
	rng.seed = 7700


func _yard_cell() -> Vector2i:
	var w := sim.world
	var pr := w.plot
	for k in 12:
		var c := Vector2i(rng.randi_range(pr.position.x + 1, pr.end.x - 2), rng.randi_range(pr.position.y + 1, pr.end.y - 2))
		var i := w.idx(c)
		if w.flr[i] == 0 and w.passable(c) and w.occ[i] < 0 and sim.rooms.room_at(c) == null:
			return c
	return Vector2i(-1, -1)


## Клетка внутри помещения с воротами — голубь «залетел в цех».
func _gate_room_cell() -> Vector2i:
	var w := sim.world
	for r in sim.rooms.list:
		if r.cells.is_empty():
			continue
		var has_gate := false
		for y in range(r.srect.position.y - 1, r.srect.end.y + 1):
			for x in [r.srect.position.x - 1, r.srect.end.x]:
				if WallKinds.is_gate(w.get_wall(Vector2i(x, y))):
					has_gate = true
		for x2 in range(r.srect.position.x - 1, r.srect.end.x + 1):
			for y2 in [r.srect.position.y - 1, r.srect.end.y]:
				if WallKinds.is_gate(w.get_wall(Vector2i(x2, y2))):
					has_gate = true
		if has_gate:
			var c2: Vector2i = r.cells[rng.randi_range(0, r.cells.size() - 1)]
			if w.passable(c2) and w.occ[w.idx(c2)] < 0:
				return c2
	return Vector2i(-1, -1)


func _edge_point() -> Vector2:
	var w := sim.world
	match rng.randi_range(0, 2):
		0:
			return Vector2(rng.randf_range(-6.0, w.w + 6.0), -6.0)
		1:
			return Vector2(-6.0, rng.randf_range(0.0, w.h * 0.7))
	return Vector2(w.w + 6.0, rng.randf_range(0.0, w.h * 0.7))


func _day() -> bool:
	var t := sim.tod()
	return t >= 390.0 and t <= 1200.0


func tick(dt: float) -> void:
	_t -= dt
	_move(dt)
	if _t > 0.0:
		return
	_t = 2.0
	_spawn()
	_scare()
	_mice_spawn()
	_hunt()


# ================================================================ голуби

func _spawn() -> void:
	var alive := pigeons.filter(func(p: Dictionary) -> bool: return str(p["st"]) != "gone")
	pigeons = alive
	if not _day():
		for p: Dictionary in pigeons:
			if str(p["st"]) != "fly" or not bool(p.get("leave", false)):
				_fly(p, _edge_point(), true)
		return
	var want := mini(MAX_PIGEONS, 2 + int(sim.workers.size() / 6))
	if pigeons.size() < want and rng.randf() < 0.25:
		var c := _yard_cell()
		if c.x >= 0:
			var p2 := {"pos": _edge_point(), "to": Vector2(c) + Vector2(0.5, 0.5), "st": "walk", "until": 0.0, "dir": 1, "fly_t": 0.0, "inside": false}
			_fly(p2, Vector2(c) + Vector2(0.5, 0.5), false)
			pigeons.append(p2)
			# стайкой: ещё один-два рядом
			for k in rng.randi_range(0, 2):
				if pigeons.size() >= want:
					break
				var c3 := c + Vector2i(rng.randi_range(-2, 2), rng.randi_range(-2, 2))
				if sim.world.in_plot(c3) and sim.world.passable(c3) and sim.world.flr[sim.world.idx(c3)] == 0:
					var p3 := {"pos": _edge_point(), "to": Vector2(c3) + Vector2(0.5, 0.5), "st": "walk", "until": 0.0, "dir": 1, "fly_t": 0.0, "inside": false}
					_fly(p3, Vector2(c3) + Vector2(0.5, 0.5), false)
					pigeons.append(p3)


func _fly(p: Dictionary, to: Vector2, leave: bool) -> void:
	p["st"] = "fly"
	p["to"] = to
	p["leave"] = leave
	p["fly_t"] = 0.0
	p["from"] = p["pos"]
	var d: Vector2 = to - (p["pos"] as Vector2)
	if absf(d.x) > 0.1:
		p["dir"] = 1 if d.x > 0.0 else -1


## Люди, машины и кот рядом — голуби взлетают.
func _scare() -> void:
	var cat: Cat = sim.town.cat if sim.town else null
	for p: Dictionary in pigeons:
		if str(p["st"]) == "fly":
			continue
		var pp: Vector2 = p["pos"]
		var scared := false
		for w in sim.workers:
			if w.present and w.pos.distance_to(pp) < 1.3:
				scared = true
				break
		if not scared:
			for v in sim.vehicles:
				if absf(v.x + 1.5 - pp.x) < 3.0 and pp.y > float(sim.world.sidewalk_row) - 2.0:
					scared = true
					break
		if not scared and cat and cat.pos.distance_to(pp) < (1.2 if cat.state == "hunt" else 2.2):
			scared = true
		if scared:
			# 1 из 8 — улетает совсем, иначе — пересаживается подальше; иногда — в цех через ворота
			var r := rng.randf()
			if r < 0.12:
				_fly(p, _edge_point(), true)
			else:
				var c := _gate_room_cell() if r < 0.24 else _yard_cell()
				if c.x >= 0:
					_fly(p, Vector2(c) + Vector2(0.5, 0.5), false)
					if r < 0.24:
						p["inside"] = true
						sim.notify_once("pigeon_in", "Голубь залетел в цех через открытые ворота — ходит между станками. Улетит сам.", Sim.LVL_INFO, c, 2880.0)
				else:
					_fly(p, _edge_point(), true)


func _move(dt: float) -> void:
	for p: Dictionary in pigeons:
		match str(p["st"]):
			"fly":
				var to: Vector2 = p["to"]
				var pos: Vector2 = p["pos"]
				var v := to - pos
				var ln := v.length()
				var step := FLY_SPEED * dt
				p["fly_t"] = float(p["fly_t"]) + dt
				if ln <= step:
					p["pos"] = to
					if bool(p.get("leave", false)):
						p["st"] = "gone"
					else:
						p["st"] = "peck"
						p["until"] = sim.minute + rng.randf_range(1.0, 4.0)
				else:
					p["pos"] = pos + v / ln * step
			"walk":
				var to2: Vector2 = p["to"]
				var pos2: Vector2 = p["pos"]
				var v2 := to2 - pos2
				var ln2 := v2.length()
				var st2 := PIGEON_SPEED * dt
				if ln2 <= st2:
					p["pos"] = to2
					p["st"] = "peck"
					p["until"] = sim.minute + rng.randf_range(0.5, 3.0)
				else:
					p["pos"] = pos2 + v2 / ln2 * st2
					if absf(v2.x) > 0.05:
						p["dir"] = 1 if v2.x > 0.0 else -1
			"peck":
				if sim.minute >= float(p["until"]):
					if bool(p.get("inside", false)) and rng.randf() < 0.08:
						p["inside"] = false
						_fly(p, Vector2(_yard_cell()) + Vector2(0.5, 0.5) if _yard_cell().x >= 0 else _edge_point(), _yard_cell().x < 0)
						continue
					var pos3: Vector2 = p["pos"]
					var n := pos3 + Vector2(rng.randf_range(-1.2, 1.2), rng.randf_range(-1.0, 1.0))
					var nc := Vector2i(floori(n.x), floori(n.y))
					if sim.world.in_plot(nc) and sim.world.passable(nc) and (bool(p.get("inside", false)) == (sim.rooms.room_at(nc) != null)):
						p["to"] = n
						p["st"] = "walk"
					else:
						p["until"] = sim.minute + 1.0
	for m: Dictionary in mice:
		if str(m["st"]) != "run":
			if sim.minute >= float(m["until"]):
				m["st"] = "run"
				m["to"] = _mouse_target(int(m["room"]), m["pos"])
			continue
		var to3: Vector2 = m["to"]
		var pos4: Vector2 = m["pos"]
		var v3 := to3 - pos4
		var ln3 := v3.length()
		var st3 := 6.0 * dt
		if ln3 <= st3:
			m["pos"] = to3
			m["st"] = "hide" if rng.randf() < 0.35 else "sit"
			m["until"] = sim.minute + rng.randf_range(1.0, 6.0) * (3.0 if str(m["st"]) == "hide" else 1.0)
		else:
			m["pos"] = pos4 + v3 / ln3 * st3
			if absf(v3.x) > 0.05:
				m["dir"] = 1 if v3.x > 0.0 else -1


# ================================================================ мыши

func _mouse_target(room_id: int, from: Vector2) -> Vector2:
	var r: Rooms.Room = sim.rooms.list[room_id] if room_id >= 0 and room_id < sim.rooms.list.size() else null
	if r == null or r.cells.is_empty():
		return from
	# вдоль стен: клетки у края помещения
	for k in 10:
		var c: Vector2i = r.cells[rng.randi_range(0, r.cells.size() - 1)]
		var edge := false
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			if WallKinds.is_room_wall(sim.world.get_wall(c + d)):
				edge = true
		if edge and sim.world.passable(c):
			return Vector2(c) + Vector2(rng.randf_range(0.2, 0.8), rng.randf_range(0.3, 0.8))
	return from


func _mice_spawn() -> void:
	# мыши уходят, когда убрали
	mice = mice.filter(func(m: Dictionary) -> bool:
		var rid := int(m["room"])
		if rid < 0 or rid >= sim.rooms.list.size():
			return false
		return sim.upkeep.room_dirt(sim.rooms.list[rid]) >= MOUSE_DIRT * 0.7)
	if mice.size() >= MAX_MICE or rng.randf() > 0.15:
		return
	for i in sim.rooms.list.size():
		var r: Rooms.Room = sim.rooms.list[i]
		if r.cells.size() < 6:
			continue
		if sim.upkeep.room_dirt(r) < MOUSE_DIRT:
			continue
		var n := mice.filter(func(m2: Dictionary) -> bool: return int(m2["room"]) == i).size()
		if n >= 2:
			continue
		var start := _mouse_target(i, Vector2(r.cells[0]) + Vector2(0.5, 0.5))
		mice.append({"pos": start, "to": start, "room": i, "st": "sit", "until": sim.minute + 1.0, "dir": 1})
		sim.notify_once("mice", "В помещении «%s» завелись мыши — там очень грязно. Нужна уборка: уборщица или разнорабочие (Люди → График смены → «Уборка»). Кот поможет." % r.title(), Sim.LVL_WARN, r.cells[0], 2880.0)
		for w in sim.workers:
			if w.present and sim.rooms.room_at(w.cell()) == r:
				Mood.add(sim, w, "mice")
		return


func mice_in(r: Rooms.Room) -> int:
	if r == null:
		return 0
	var idx := sim.rooms.list.find(r)
	return mice.filter(func(m: Dictionary) -> bool: return int(m["room"]) == idx).size()


# ================================================================ кот охотится

func _hunt() -> void:
	var cat: Cat = sim.town.cat if sim.town else null
	if cat == null or cat.state in ["sleep", "eat", "hunt", "pounce"]:
		return
	if cat.state == "walk" and str(cat.next_state) == "hunt":
		return
	# мышь — главная добыча
	var best: Dictionary = {}
	var bd := INF
	for m: Dictionary in mice:
		if str(m["st"]) == "hide":
			continue
		var d := cat.pos.distance_to(m["pos"])
		if d < bd and d < 14.0:
			bd = d
			best = m
	var kind := "mouse"
	if best.is_empty() and rng.randf() < 0.25:
		for p: Dictionary in pigeons:
			if str(p["st"]) == "fly":
				continue
			var d2 := cat.pos.distance_to(p["pos"])
			if d2 < bd and d2 < 9.0:
				bd = d2
				best = p
				kind = "pigeon"
	if best.is_empty():
		return
	var tc := Vector2i(floori((best["pos"] as Vector2).x), floori((best["pos"] as Vector2).y))
	if cat.hunt(tc, kind):
		cat.prey = best


## Кот прыгнул: поймал ли? Голубь обычно улетает, мышь ловится чаще.
func pounce(cat: Cat) -> void:
	var prey: Dictionary = cat.prey
	cat.prey = {}
	if prey.is_empty():
		return
	var close := cat.pos.distance_to(prey["pos"]) < 1.6
	if mice.has(prey):
		if close and rng.randf() < 0.6:
			mice.erase(prey)
			caught_mice += 1
			cat.mice += 1
			cat.activity = "Поймал мышь!" if not cat.female else "Поймала мышь!"
			if cat.mice % 3 == 1:
				sim.notify("%s поймал%s мышь. Уже %d за всё время!" % [cat.name, "а" if cat.female else "", cat.mice], Sim.LVL_GOOD, cat.cell())
		else:
			prey["st"] = "run"
			prey["to"] = _mouse_target(int(prey["room"]), prey["pos"])
			cat.activity = "Мышь удрала"
	elif pigeons.has(prey):
		if close and rng.randf() < 0.08:
			pigeons.erase(prey)
			caught_pigeons += 1
			cat.activity = "Поймал голубя" if not cat.female else "Поймала голубя"
			sim.notify_once("cat_pigeon", "%s поймал%s голубя — гордо несёт показать рабочим." % [cat.name, "а" if cat.female else ""], Sim.LVL_INFO, cat.cell(), 4320.0)
		else:
			var c := _yard_cell()
			_fly(prey, Vector2(c) + Vector2(0.5, 0.5) if c.x >= 0 else _edge_point(), c.x < 0)
			cat.activity = "Голубь улетел"


func to_dict() -> Dictionary:
	return {"rng": rng.state, "mice_c": caught_mice, "pig_c": caught_pigeons}


func from_dict(d: Dictionary) -> void:
	if d.has("rng"):
		rng.state = int(d["rng"])
	caught_mice = int(d.get("mice_c", 0))
	caught_pigeons = int(d.get("pig_c", 0))
