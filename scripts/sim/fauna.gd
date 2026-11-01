class_name Fauna
extends RefCounted
## 1.22: живность вокруг завода.
## — Голуби: днём прилетают во двор, ходят и клюют, разлетаются от людей, машин и кота; иногда залетают
##   в цех через открытые ворота и через какое-то время улетают. На ночь улетают совсем.
## — Кот охотится: подкрадывается к голубю и прыгает. Голуби обычно успевают улететь. (1.65: мыши убраны.)
## Своя случайность (rng) — не сбивает остальную симуляцию.

const MAX_PIGEONS := 7
const PIGEON_SPEED := 1.1       ## клеток в минуту пешком
const FLY_SPEED := 14.0         ## клеток в минуту в полёте

var sim: Sim
var rng := RandomNumberGenerator.new()
var pigeons: Array = []         ## [{pos: Vector2, to: Vector2, st: walk|peck|fly|gone, until, dir, fly_t, inside}]
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
	var want := CityMode.count(mini(MAX_PIGEONS, 2 + int(sim.workers.size() / 6)))
	if want == 0:   # 1.60: «Живость города: выкл.» — голуби улетают и не возвращаются
		for p0: Dictionary in pigeons:
			if str(p0["st"]) != "fly" or not bool(p0.get("leave", false)):
				_fly(p0, _edge_point(), true)
		return
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
						sim.notify_once("pigeon_in", L.t("Голубь залетел в цех через открытые ворота — ходит между станками. Улетит сам."), Sim.LVL_INFO, c, 2880.0)
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


# ================================================================ кот охотится

func _hunt() -> void:
	var cat: Cat = sim.town.cat if sim.town else null
	if cat == null or cat.state in ["sleep", "eat", "hunt", "pounce"]:
		return
	if cat.state == "walk" and str(cat.next_state) == "hunt":
		return
	var best: Dictionary = {}
	var bd := INF
	var kind := "pigeon"
	if rng.randf() < 0.25:
		for p: Dictionary in pigeons:
			if str(p["st"]) == "fly":
				continue
			var d2 := cat.pos.distance_to(p["pos"])
			if d2 < bd and d2 < 9.0:
				bd = d2
				best = p
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
	if pigeons.has(prey):
		if close and rng.randf() < 0.08:
			pigeons.erase(prey)
			caught_pigeons += 1
			cat.activity = L.t("Поймал голубя") if not cat.female else L.t("Поймала голубя")
			sim.notify_once("cat_pigeon", Nicks.gendered(L.t("%s поймал{|а} голубя — гордо несёт показать рабочим."), cat.female) % cat.shown_name(), Sim.LVL_INFO, cat.cell(), 4320.0)
		else:
			var c := _yard_cell()
			_fly(prey, Vector2(c) + Vector2(0.5, 0.5) if c.x >= 0 else _edge_point(), c.x < 0)
			cat.activity = L.t("Голубь улетел")


func to_dict() -> Dictionary:
	return {"rng": rng.state, "pig_c": caught_pigeons}


func from_dict(d: Dictionary) -> void:
	if d.has("rng"):
		rng.state = int(d["rng"])
	caught_pigeons = int(d.get("pig_c", 0))
