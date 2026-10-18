class_name FireBrigade
extends RefCounted
## 1.30: пожарный расчёт. Если огонь не удержать своими силами, вызывают 01: через несколько минут
## по встречной полосе с сиреной приезжает красная машина и встаёт на дороге напротив очага.
## Трое пожарных в боёвке и жёлтых касках бегут к огню, тянут за собой рукава от машины и сбивают
## пламя струёй (сила огня падает), потом сматывают рукава, садятся и уезжают.
## Если к огню не подобраться (дорогу перегородили), расчёт через MAX_ON_SITE минут тушит его
## «снаружи» — пожар кончается в любом случае.

const CREW := 3
const DISPATCH := 6.0      ## минут от вызова до выезда машины из-за края карты
const RATE := 0.16         ## сколько силы огня в минуту сбивает струя (огнетушитель — ~0.1)
const REACH := 3.2         ## на сколько клеток бьёт ствол
const MAX_ON_SITE := 40.0  ## запасной выход: дольше расчёт не возится — заливает «через забор»
const TRUCK_LEN := 4.1     ## длина машины в клетках

var sim: Sim
var vid := -1                  ## id пожарной машины (−1 — расчёт не на выезде)
var dispatch_at := -1.0        ## когда машина выедет к заводу
var on_site := 0.0             ## сколько минут расчёт на месте
var crew: Array = []           ## [{w: Worker, st: run|spray|back|in, fire: индекс клетки, stand: [x, y]}]
var calls := 0                 ## сколько раз приезжали


func _init(s: Sim) -> void:
	sim = s


## Пожарный расчёт на месте (кто-то из пожарных уже вышел из машины).
func deployed() -> bool:
	return not crew.is_empty()


func truck() -> Vehicle:
	return sim.get_vehicle(vid) if vid >= 0 else null


## Вызов 01: машина выедет через DISPATCH минут.
func request() -> void:
	if vid >= 0 or dispatch_at >= 0.0:
		return
	dispatch_at = sim.minute + DISPATCH
	sim.notify("Огонь не удержать — вызвали пожарных (01). Расчёт будет минут через десять.", Sim.LVL_BAD)


## Гость завода в своей форме: пожарный, водитель ломовоза. Облик — из sim.rng (детерминированно).
static func make_guest(s: Sim, who: String, outfit: String, col: String, hat: String, hat_col: String, prop: String) -> Worker:
	var v := People.make(s.rng, "laborer", 0.0)
	v.id = s.new_id()
	v.visitor = true
	v.prof = "guest"
	v.age = s.rng.randi_range(24, 52)
	var lk := v.look
	lk["outfit"] = outfit
	lk["outfit_col"] = col
	lk["hat"] = hat
	lk["hat_col"] = hat_col
	lk["resp"] = false
	lk["phones"] = false
	lk["glasses"] = false
	v.dressed = true
	v.prop = prop
	v.present = true
	v.activity = who
	v.set_meta("who", who)
	v.set_meta("veh", true)   # приехал на своей машине (уличная толпа его не уводит на автобус)
	return v


func tick(dt: float) -> void:
	var st := sim.story
	if dispatch_at >= 0.0 and vid < 0 and sim.minute >= dispatch_at:
		dispatch_at = -1.0
		if st.fires.is_empty():
			sim.notify("Огонь потушили до приезда пожарных — вызов отменили.", Sim.LVL_INFO)
		else:
			_send_truck()
	var v := truck()
	if vid >= 0 and v == null:
		_clear_crew()   # машину убрали (загрузка старого сохранения и т. п.)
		vid = -1
		return
	if v == null or v.state != "parked":
		return
	on_site += dt
	if not st.fires.is_empty() and on_site > MAX_ON_SITE:
		# запасной выход: к огню не подобраться — заливают из лафетного ствола с дороги
		for i: int in st.fires.keys():
			st.soot[i] = true
		st.fires.clear()
		st._fire_out(true)
	var all_in := true
	for c: Dictionary in crew:
		_tick_man(c, dt, v)
		if str(c["st"]) != "in":
			all_in = false
	if st.fires.is_empty() and all_in:
		_leave(v)


func _send_truck() -> void:
	var w := sim.world
	var fc := _fire_center()
	var v := sim.spawn_vehicle("fire")
	v.body = "fire"
	v.lane = 1
	v.color = 0
	v.hold = true
	v.cargo_desc = "Пожарная охрана"
	v.x = float(w.w) + 8.0
	# машина встаёт серединой напротив очага (x — задний край; едет влево, кабина слева)
	v.park_x = clampf(float(fc.x) + 0.5 + TRUCK_LEN * 0.5, TRUCK_LEN + 1.0, float(w.w) - 1.0)
	v.state = "arriving"
	vid = v.id
	on_site = 0.0
	calls += 1


## Середина пожара (ближайшая к дороге клетка огня).
func _fire_center() -> Vector2i:
	var best := Vector2i(sim.gate_x, sim.world.sidewalk_row - 2)
	var by := -1
	for i: int in sim.story.fires.keys():
		var c := sim.world.cell_of(i)
		if c.y > by:
			by = c.y
			best = c
	return best


## Где у машины дверь и рукавный отсек — оттуда выходят пожарные и тянутся рукава.
func door_pos(v: Vehicle, k: int = 0) -> Vector2:
	return Vector2(v.x - TRUCK_LEN * 0.35 - 0.7 * k, float(sim.world.road_row) + 1.5)


## Машина встала: расчёт выходит.
func on_park(v: Vehicle) -> void:
	if sim.story.fires.is_empty():
		sim.notify("Пожарные приехали, но огонь уже потушили — расчёт уехал обратно.", Sim.LVL_INFO, Vector2i(int(v.x - 2.0), sim.world.road_row))
		_leave(v)
		return
	_clear_crew()
	for k in CREW:
		var f := make_guest(sim, "Пожарный", "fireman", "#2b3038", "helmet", "#e8c02a", "nozzle")
		f.pos = door_pos(v, k)
		f.exit_cell = Vector2i(floori(f.pos.x), floori(f.pos.y))
		f.dir = "up"
		sim.visitors.append(f)
		crew.append({"w": f, "st": "run", "fire": -1, "stand": [-1, -1]})
	sim.notify("Приехали пожарные: расчёт тянет рукава к огню.", Sim.LVL_WARN, _fire_center())


func _tick_man(c: Dictionary, dt: float, v: Vehicle) -> void:
	var f: Worker = c["w"]
	var st := sim.story
	match str(c["st"]):
		"run":
			if st.fires.is_empty():
				c["st"] = "back"
				return
			var near := _fire_in_reach(f.pos)
			if near >= 0:
				c["st"] = "spray"
				c["fire"] = near
				return
			var stand := Vector2i(int(c["stand"][0]), int(c["stand"][1]))
			if stand.x < 0 or st.fires.has(sim.world.idx(stand)):
				stand = _stand_for(f)
				c["stand"] = [stand.x, stand.y]
			f.activity = "Бежит к огню с рукавом"
			f.bubble = "fire"
			var r := sim.brain.move_to(f, stand, dt * 1.35)
			if r == 1:
				c["stand"] = [-1, -1]
			elif r == -1:
				f.anim = "idle"   # не пройти — ждёт; через MAX_ON_SITE расчёт зальёт огонь с дороги
		"spray":
			var fi := int(c["fire"])
			if not st.fires.has(fi) or Vector2(sim.world.cell_of(fi)).distance_to(f.pos - Vector2(0.5, 0.5)) > REACH + 0.3:
				fi = _fire_in_reach(f.pos)
				c["fire"] = fi
			if fi < 0:
				c["st"] = "run" if not st.fires.is_empty() else "back"
				c["stand"] = [-1, -1]
				return
			var fc := sim.world.cell_of(fi)
			sim.brain._set_dir(f, Vector2(fc) + Vector2(0.5, 0.5) - f.pos)
			f.anim = "work"
			f.activity = "Тушит пожар из рукава"
			f.bubble = ""
			st.extinguish(fi, RATE * dt)
			# струя проливает и соседние клетки
			for d: Vector2i in Rooms.DIRS:
				var n: Vector2i = fc + d
				if sim.world.inb(n) and st.fires.has(sim.world.idx(n)):
					st.extinguish(sim.world.idx(n), RATE * 0.35 * dt)
		"back":
			c["fire"] = -1
			f.bubble = ""
			f.activity = "Сматывает рукав"
			var dp := door_pos(v, crew.find(c))
			var cell := Vector2i(floori(dp.x), floori(dp.y))
			var r2 := sim.brain.move_to(f, cell, dt * 1.1)
			if r2 != 0:
				c["st"] = "in"
				f.present = false
				sim.visitors.erase(f)


## Ближайший очаг, до которого достаёт струя с этого места (−1 — нет). Сквозь стены не бьёт.
func _fire_in_reach(p: Vector2) -> int:
	var best := -1
	var bd := REACH
	for i: int in sim.story.fires.keys():
		var fc := Vector2(sim.world.cell_of(i)) + Vector2(0.5, 0.5)
		var d := fc.distance_to(p)
		if d <= bd and los(p, fc):
			bd = d
			best = i
	return best


## Куда встать, чтобы достать струёй до ближайшего очага: проходимая клетка без огня, до которой можно дойти.
func _stand_for(f: Worker) -> Vector2i:
	var w := sim.world
	var from := f.cell()
	var best := Vector2i(-1, -1)
	var bd := INF
	var target := -1
	var td := INF
	for i: int in sim.story.fires.keys():
		var d0 := Vector2(w.cell_of(i)).distance_to(Vector2(from))
		if d0 < td:
			td = d0
			target = i
	if target < 0:
		return best
	var fc := w.cell_of(target)
	var r := int(REACH)
	for dy in range(-r, r + 1):
		for dx in range(-r, r + 1):
			var c := fc + Vector2i(dx, dy)
			if Vector2(dx, dy).length() > REACH - 0.6 or not w.passable(c) or sim.story.fires.has(w.idx(c)):
				continue
			if not los(Vector2(c) + Vector2(0.5, 0.5), Vector2(fc) + Vector2(0.5, 0.5)):
				continue
			var d := Vector2(c).distance_to(Vector2(from)) + Vector2(dx, dy).length() * 0.3
			if d < bd and w.reachable(from, c):
				bd = d
				best = c
	return best


## Струя долетает: на прямой между точками нет стены (открытая дверь — не помеха).
func los(a: Vector2, b: Vector2) -> bool:
	var w := sim.world
	var n := int(ceil(a.distance_to(b) / 0.25))
	var ca := Vector2i(floori(a.x), floori(a.y))
	var cb := Vector2i(floori(b.x), floori(b.y))
	for k in range(1, n):
		var p := a.lerp(b, float(k) / float(n))
		var c := Vector2i(floori(p.x), floori(p.y))
		if c == ca or c == cb or not w.inb(c):
			continue
		if Defs.wall_solid(w.wall[w.idx(c)]):
			return false
	return true


func _leave(v: Vehicle) -> void:
	if deployed():
		sim.notify("Пожарные смотали рукава и уехали.", Sim.LVL_INFO, Vector2i(int(v.x - 2.0), sim.world.road_row))
	_clear_crew()
	v.hold = false
	v.state = "leaving"
	vid = -1
	on_site = 0.0


func _clear_crew() -> void:
	for c: Dictionary in crew:
		sim.visitors.erase(c["w"])
	crew.clear()


# ================================================================ сохранение

func to_dict() -> Dictionary:
	var cs: Array = []
	for c: Dictionary in crew:
		var f: Worker = c["w"]
		var wd := f.to_dict()
		wd["prop_"] = f.prop
		cs.append({"w": wd, "st": c["st"], "fire": c["fire"], "stand": c["stand"]})
	return {"vid": vid, "at": dispatch_at, "site": on_site, "crew": cs, "calls": calls}


func from_dict(d: Dictionary) -> void:
	vid = int(d.get("vid", -1))
	dispatch_at = float(d.get("at", -1.0))
	on_site = float(d.get("site", 0.0))
	calls = int(d.get("calls", 0))
	crew.clear()
	for cd: Dictionary in d.get("crew", []):
		var wd: Dictionary = cd["w"]
		var f := Worker.from_dict(wd)
		f.visitor = true
		f.prop = str(wd.get("prop_", "nozzle"))
		f.activity = "Пожарный"
		f.set_meta("who", "Пожарный")
		f.set_meta("veh", true)
		var stn: Array = cd.get("stand", [-1, -1])
		var ce := {"w": f, "st": str(cd.get("st", "run")), "fire": int(cd.get("fire", -1)), "stand": [int(stn[0]), int(stn[1])]}
		crew.append(ce)
		if str(ce["st"]) != "in":
			sim.visitors.append(f)
