class_name StreetFolk
extends Node2D
## 1.30: люди не пропадают у края карты. Кто уходит со смены (или уволился, или инспектор после проверки),
## идёт по тротуару дальше: через «зебру» — к своему подъезду пятиэтажки (дверь открывается, человек входит)
## или на остановку, ждёт автобус и уезжает. Утром — наоборот: выходят из подъездов и из автобуса и приходят
## к краю карты ровно тогда, когда симуляция выпускает их на участок. По улице ходят и горожане.
## Только картинка: симуляцию не трогает (её время лишь читается), своя случайность — от хешей.
## Позы людей на улице — в pose: WorkerView берёт их вместо положения из симуляции.

const T := World.T
const BUS_V := 6.0 * T       ## скорость автобуса, точек за игровую минуту
const DWELL := 1.5           ## стоянка на остановке, игровых минут
const BUS_SHARE := 35        ## доля (%) тех, кто ездит автобусом
const FOLK_N := 22           ## горожан в квартале
const DOOR_OFF := [1.6, -1.2]   ## двери автобуса от его середины, в клетках

## id человека -> [Vector2 стопа (INF — там, где он в симуляции), направление, анимация, прозрачность]
static var pose: Dictionary = {}

var sim: Sim
var backdrop: CityBackdrop
var ents: Node2D
var _sim_ref: Sim = null
var _last_min := -1.0
var _dm := 0.0
var _vm := 0.0
var _pres: Dictionary = {}       ## id -> был ли на участке в прошлом кадре
var _objs: Dictionary = {}       ## id -> Worker (сотрудники в прошлом кадре)
var _vis: Dictionary = {}        ## id -> [Worker, минута появления] — посетители
var _trips: Dictionary = {}      ## id -> поездка (уход/приход настоящих людей)
var _own: Dictionary = {}        ## id -> WorkerView: куклы уволенных и ушедших посетителей (их уже нет в симуляции)
var _folk: Array = []            ## горожане: [{w, view, c, trip}]
var _open: Dictionary = {}       ## индекс подъезда -> true (дверь сейчас открыта)
var _bus_x := NAN
var _sched := {}
var _arr_t := 0.0
var _trees: Array[Sprite2D] = []
var _tree_sig := ""


func _ready() -> void:
	pose.clear()


func _exit_tree() -> void:
	pose.clear()


# ---------------------------------------------------------------- геометрия улицы (общая с WorldView)

## Клетка «зебры» через главную дорогу: слева и справа от участка.
static func cross_x(w: World, side: int) -> int:
	return -7 if side < 0 else w.w + 6


## Клетка остановки (середина павильона) на газоне южной стороны.
static func stop_x(w: World, side: int) -> int:
	return -16 if side < 0 else w.w + 15


## Сторона «зебры» в столбце x (-1/1), 0 — её тут нет.
static func zebra_at(w: World, x: int) -> int:
	for sd: int in [-1, 1]:
		var xc := cross_x(w, sd)
		if x >= xc - 1 and x <= xc + 1:
			return sd
	return 0


static func platform_at(w: World, x: int) -> bool:
	return absi(x - stop_x(w, -1)) <= 3 or absi(x - stop_x(w, 1)) <= 3


## Въезд боковой улицы (проезд вокруг участка) пересекает северный тротуар.
static func side_street_at(w: World, x: int) -> bool:
	return (x >= -3 and x < 0) or (x >= w.w and x < w.w + 3)


func _yn() -> float:
	return (sim.world.sidewalk_row + 0.5) * T


func _yv() -> float:
	return (sim.world.h - 0.5) * T


func _ys() -> float:
	return (sim.world.h + 0.5) * T


func _yb() -> float:
	return (sim.world.sidewalk_row + 3.95) * T


func _xc(side: int) -> float:
	return (cross_x(sim.world, side) + 0.5) * T


func _xs(side: int) -> float:
	return (stop_x(sim.world, side) + 0.5) * T


# ---------------------------------------------------------------- автобус: расписание — функция игрового времени

func _schedule() -> Dictionary:
	var w := sim.world
	var key := w.w
	if int(_sched.get("key", -1)) == key:
		return _sched
	var x0 := (-CityBackdrop.M - 4) * T
	var s1 := _xs(-1)
	var s2 := _xs(1)
	var x3 := (w.w + CityBackdrop.M + 4) * T
	var t1 := (s1 - x0) / BUS_V
	var t2 := t1 + DWELL + (s2 - s1) / BUS_V
	var t3 := t2 + DWELL + (x3 - s2) / BUS_V
	_sched = {"key": key, "x0": x0, "s1": s1, "s2": s2, "x3": x3, "t1": t1, "t2": t2, "t3": t3, "p": maxf(40.0, ceilf(t3 + 4.0))}
	return _sched


func _bus_at(m: float) -> float:
	var s := _schedule()
	var u := fposmod(m, float(s["p"]))
	var t1: float = s["t1"]
	var t2: float = s["t2"]
	if u < t1:
		return float(s["x0"]) + u * BUS_V
	if u < t1 + DWELL:
		return s["s1"]
	if u < t2:
		return float(s["s1"]) + (u - t1 - DWELL) * BUS_V
	if u < t2 + DWELL:
		return s["s2"]
	if u < float(s["t3"]):
		return float(s["s2"]) + (u - t2 - DWELL) * BUS_V
	return NAN


func _dwell_base(side: int) -> float:
	return float(_schedule()["t1" if side < 0 else "t2"])


## Начало первой стоянки на остановке, которая ещё не закончилась к моменту t.
func next_dwell(side: int, t: float) -> float:
	var p := float(_schedule()["p"])
	var b := _dwell_base(side)
	return ceilf((t - DWELL - b) / p) * p + b


## Начало последней стоянки, начавшейся не позже t.
func prev_dwell(side: int, t: float) -> float:
	var p := float(_schedule()["p"])
	var b := _dwell_base(side)
	return floorf((t - b) / p) * p + b


func _bus_door(side: int, k: int) -> Vector2:
	return Vector2(_xs(side) + float(DOOR_OFF[k % 2]) * T, (sim.world.sidewalk_row + 4.55) * T)


func _wait_x(side: int, h: int) -> float:
	var offs := [-2.2, -1.7, 1.7, 2.2, 2.7, -2.7, 1.2, -1.25]
	return _xs(side) + float(offs[h % offs.size()]) * T


# ---------------------------------------------------------------- маршруты

## Подъезды первого ряда домов (у южного тротуара).
func _doors() -> Array:
	return backdrop.doors if backdrop else []


func _front_door(i: int) -> bool:
	var d: Dictionary = _doors()[i]
	return float(d["top"]) <= (sim.world.h + 3) * T


## От подъезда до южного тротуара: во двор, по дорожке к краю квартала, по краю — к улице.
func _door_leg(d: Dictionary, toward_x: float) -> PackedVector2Array:
	var door: Vector2 = d["door"]
	var yy: float = d["yard_y"]
	var lx: float = d["lx"] if absf(float(d["lx"]) - toward_x) < absf(float(d["rx"]) - toward_x) else d["rx"]
	return PackedVector2Array([door + Vector2(0, 2), Vector2(door.x, yy), Vector2(lx, yy), Vector2(lx, _ys())])


static func _rev(a: PackedVector2Array) -> PackedVector2Array:
	var r := PackedVector2Array()
	for i in range(a.size() - 1, -1, -1):
		r.append(a[i])
	return r


## От выхода с участка (на северном тротуаре) к подъезду: до «зебры», через дорогу, по южному тротуару.
func _exit_to_door(from: Vector2, side: int, d: Dictionary) -> PackedVector2Array:
	var xc := _xc(side)
	var p := PackedVector2Array([from, Vector2(xc, _yn()), Vector2(xc, _ys())])
	p.append_array(_rev(_door_leg(d, xc)))
	return p


func _exit_to_stop(from: Vector2, side: int, h: int) -> PackedVector2Array:
	var xc := _xc(side)
	return PackedVector2Array([from, Vector2(xc, _yn()), Vector2(xc, _yv()), Vector2(_wait_x(side, h), _yv())])


## Подъезд этой стороны для человека (у каждого свой «дом» — по хешу id).
func _home_door(id: int, side: int) -> int:
	var ds := _doors()
	var lo := -40.0 * T if side < 0 else (sim.world.w - 4) * T
	var hi := 4.0 * T if side < 0 else (sim.world.w + 40) * T
	var pick: Array[int] = []
	for i in ds.size():
		var x := ((ds[i] as Dictionary)["door"] as Vector2).x
		if x >= lo and x <= hi and _front_door(i):
			pick.append(i)
	if pick.is_empty():
		return -1
	return pick[WorldView.vhash(id, 77) % pick.size()]


static func _plen(p: PackedVector2Array) -> float:
	var l := 0.0
	for i in range(1, p.size()):
		l += p[i].distance_to(p[i - 1])
	return l


## Поездка: идёт по pts с t0 со скоростью spd. pre — как появляется (door/bus/""), post — чем кончается
## (door — входит в подъезд, bus — ждёт автобус и садится, edge — стоит у края участка, пока не выйдет в симуляцию).
func _trip(w: Worker, pts: PackedVector2Array, t0: float, spd: float, pre: String, post: String, door_a: int, door_b: int, side: int) -> Dictionary:
	var ln := _plen(pts)
	var tr := {"w": w, "pts": pts, "len": ln, "t0": t0, "spd": spd, "pre": pre, "post": post, "da": door_a, "db": door_b, "side": side,
		"te": t0 + ln / maxf(spd, 0.01), "tb": -1.0}
	if post == "bus":
		tr["tb"] = maxf(float(tr["te"]), next_dwell(side, float(tr["te"])))
	return tr


## Пройденная к моменту m часть пути; hs/hd — у «зебры» пропускает автобус (где и сколько стоит).
func _arc(tr: Dictionary, m: float) -> float:
	var t := m - float(tr["t0"])
	var spd := float(tr["spd"])
	var hs := float(tr.get("hs", -1.0))
	if hs >= 0.0 and t * spd > hs:
		return maxf(hs, (t - float(tr.get("hd", 0.0))) * spd)
	return t * spd


func _t_of(tr: Dictionary, s: float) -> float:
	var t := float(tr["t0"]) + s / float(tr["spd"])
	if float(tr.get("hs", -1.0)) >= 0.0 and s > float(tr["hs"]):
		t += float(tr.get("hd", 0.0))
	return t


## Дуга начала перехода по «зебре» (-1 — путь дорогу не переходит).
func _zebra_seg(pts: PackedVector2Array) -> Vector2:
	var s := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		if absf(a.x - b.x) < 0.5 and d > T and zebra_at(sim.world, floori(a.x / T)) != 0:
			return Vector2(s, d)
		s += d
	return Vector2(-1, 0)


## Автобус проезжает «зебру», пока человек идёт по его полосе?
func _bus_hits(tr: Dictionary) -> bool:
	var pts: PackedVector2Array = tr["pts"]
	var s := 0.0
	for i in range(1, pts.size()):
		var a := pts[i - 1]
		var b := pts[i]
		var d := a.distance_to(b)
		if absf(a.x - b.x) < 0.5 and d > T and zebra_at(sim.world, floori(a.x / T)) != 0:
			var lo := _yb() - 0.9 * T
			var hi := _yb() + 0.8 * T
			var u1 := clampf((lo - a.y) / (b.y - a.y), 0.0, 1.0)
			var u2 := clampf((hi - a.y) / (b.y - a.y), 0.0, 1.0)
			var t1 := _t_of(tr, s + minf(u1, u2) * d)
			var t2 := _t_of(tr, s + maxf(u1, u2) * d)
			var tt := t1
			while tt <= t2:
				var bx := _bus_at(tt)
				if not is_nan(bx) and absf(bx - a.x) < 3.4 * T:
					return true
				tt += 0.05
		s += d
	return false


## Уходящий ждёт у бордюра, пока автобус проедет.
func _hold_for_bus(tr: Dictionary) -> void:
	var z := _zebra_seg(tr["pts"])
	if z.x < 0.0:
		return
	tr["hs"] = z.x
	tr["hd"] = 0.0
	while _bus_hits(tr) and float(tr["hd"]) < 4.0:
		tr["hd"] = float(tr["hd"]) + 0.2
	tr["te"] = float(tr["t0"]) + float(tr["len"]) / float(tr["spd"]) + float(tr["hd"])
	if str(tr["post"]) == "bus":
		tr["tb"] = maxf(float(tr["te"]), next_dwell(int(tr["side"]), float(tr["te"])))


## Приходящий выходит чуть раньше и переходит дорогу до автобуса (потом ждёт у края участка).
func _early_for_bus(tr: Dictionary) -> void:
	var k := 0
	while _bus_hits(tr) and k < 17:
		tr["t0"] = float(tr["t0"]) - 0.2
		tr["te"] = float(tr["te"]) - 0.2
		k += 1


func _walk() -> float:
	return Defs.b("walk_speed") * T if Defs.b("walk_speed") > 0.0 else 1.25 * T


static func _dir_of(v: Vector2) -> String:
	if absf(v.x) > absf(v.y):
		return "right" if v.x > 0 else "left"
	return "down" if v.y > 0 else "up"


static func _along(p: PackedVector2Array, s: float) -> Array:
	for i in range(1, p.size()):
		var d := p[i].distance_to(p[i - 1])
		if s <= d:
			return [p[i - 1].lerp(p[i], s / maxf(d, 0.001)), p[i] - p[i - 1]]
		s -= d
	var n := p.size()
	return [p[n - 1], (p[n - 1] - p[n - 2]) if n > 1 else Vector2.DOWN]


## Поза в момент m; [] — человека на улице не видно; "done" в tr — поездка закончилась.
func _pose_of(tr: Dictionary, m: float) -> Array:
	var pts: PackedVector2Array = tr["pts"]
	var t0: float = tr["t0"]
	var te: float = tr["te"]
	var pre: String = tr["pre"]
	if m < t0:
		if pre == "door" and m >= t0 - 0.5:
			_open[int(tr["da"])] = true
			return [pts[0] + Vector2(0, -6.0 * (t0 - m) / 0.5), "down", "walk", clampf(1.0 - (t0 - m) / 0.5, 0.0, 1.0)]
		if pre == "bus" and m >= t0 - 0.35:
			return [pts[0], "down", "idle", clampf(1.0 - (t0 - m) / 0.35, 0.0, 1.0)]
		return []
	if m < te:
		var sa := _arc(tr, m)
		var a := _along(pts, sa)
		var held := tr.has("hs") and absf(sa - float(tr["hs"])) < 0.01 and m - t0 > 0.01
		return [a[0], _dir_of(a[1]), "idle" if held else "walk", 1.0]
	var end := pts[pts.size() - 1]
	match str(tr["post"]):
		"door":
			if m < te + 0.5:
				_open[int(tr["db"])] = true
				return [end + Vector2(0, -6.0 * (m - te) / 0.5), "up", "walk", clampf(1.0 - (m - te) / 0.5, 0.0, 1.0)]
		"bus":
			var tb: float = tr["tb"]
			if m < tb:
				return [end, "up" if m - te > 0.4 else _dir_of(pts[pts.size() - 1] - pts[pts.size() - 2]), "idle", 1.0]
			if m < tb + 0.45:
				var k := (m - tb) / 0.45
				var bd := _bus_door(int(tr["side"]), WorldView.vhash((tr["w"] as Worker).id, 5) % 2)
				return [end.lerp(bd, k), "up", "walk", clampf(1.0 - k * k, 0.0, 1.0)]
		"edge":
			if m < te + 4.0:
				return [end, "right" if end.x < sim.world.w * T * 0.5 else "left", "idle", clampf((te + 4.0 - m) / 0.6, 0.0, 1.0)]
		"off":
			pass
	tr["done"] = true
	return []


# ---------------------------------------------------------------- кадр

func _process(delta: float) -> void:
	if sim == null or ents == null:
		return
	if sim != _sim_ref:
		_reset()
		_sim_ref = sim
	var m := sim.minute
	if m < _last_min - 0.01:
		_reset()
	if m > _last_min and _last_min >= 0.0:
		_dm = minf(m - _last_min, 30.0)
	_last_min = m
	_vm = m - _dm * (1.0 - Worker.view_alpha)
	_open.clear()
	var np := {}
	_track_workers()
	_track_visitors(np)
	_arr_t -= delta
	if _arr_t <= 0.0:
		_arr_t = 0.25
		_plan_arrivals()
	for id: int in _trips.keys():
		var tr: Dictionary = _trips[id]
		var w: Worker = tr["w"]
		if w.present and not _own.has(id):
			_trips.erase(id)   # пришёл (или вернулся): дальше его ведёт симуляция
			continue
		var ps := _pose_of(tr, _vm)
		if tr.has("done"):
			_trips.erase(id)
			continue
		if not ps.is_empty():
			np[id] = ps
	_folk_tick(np)
	pose = np
	for id2: int in _own.keys():
		if not _trips.has(id2):
			(_own[id2] as Node).queue_free()
			_own.erase(id2)
	_bus_x = _bus_at(_vm)
	_sync_trees()
	queue_redraw()


func _reset() -> void:
	_trips.clear()
	_pres.clear()
	_objs.clear()
	_vis.clear()
	for v: Node in _own.values():
		v.queue_free()
	_own.clear()
	for f: Dictionary in _folk:
		(f["view"] as Node).queue_free()
	_folk.clear()
	_sched = {}
	_last_min = -1.0
	_dm = 0.0
	pose.clear()


func _edge_exit(w: Worker) -> int:
	var c := w.exit_cell
	if c.y != sim.world.sidewalk_row:
		return 0
	if c.x == 0:
		return -1
	if c.x == sim.world.w - 1:
		return 1
	return 0


## Ушёл со смены (исчез у края) или уволен (исчез из списка) — поездка с улицы.
func _track_workers() -> void:
	var now := {}
	for w: Worker in sim.workers:
		now[w.id] = true
		var was: bool = _pres.get(w.id, w.present)
		if was and not w.present and not _trips.has(w.id):
			var sd := _edge_exit(w)
			if sd != 0 and w.pos.distance_to(Vector2(w.exit_cell) + Vector2(0.5, 0.5)) < 1.6:
				_depart(w, sd, PackedVector2Array([(Vector2(w.exit_cell) + Vector2(0.5, 0.5)) * T]), 7)
		_pres[w.id] = w.present
	for id: int in _objs.keys():
		if now.has(id):
			continue
		var gone: Worker = _objs[id]
		if bool(_pres.get(id, false)) and not gone.hidden and sim.world.inb(gone.cell()):
			var sd2 := _edge_exit(gone)
			var ex := gone.exit_cell
			if sd2 == 0:
				sd2 = -1 if gone.id % 2 == 0 else 1
				ex = Vector2i(0 if sd2 < 0 else sim.world.w - 1, sim.world.sidewalk_row)
			var path := sim.world.find_path(gone.cell(), ex)
			if not path.is_empty():
				var pts := PackedVector2Array([gone.pos * T])
				for c: Vector2i in path:
					pts.append((Vector2(c) + Vector2(0.5, 0.5)) * T)
				_own_view(gone)
				_depart(gone, sd2, pts, 11)
		_pres.erase(id)
	_objs.clear()
	for w2: Worker in sim.workers:
		_objs[w2.id] = w2


func _track_visitors(np: Dictionary) -> void:
	var now := {}
	for v: Worker in sim.visitors:
		if v.has_meta("veh"):
			continue   # 1.30: пожарные и водитель ломовоза приезжают и уезжают на своей машине
		now[v.id] = true
		if not _vis.has(v.id):
			_vis[v.id] = [v, _vm]
		var t: float = (_vis[v.id] as Array)[1]
		if _vm - t < 0.7 and _vm >= t:
			np[v.id] = [Vector2.INF, "", "", clampf((_vm - t) / 0.7, 0.0, 1.0)]   # выходит из такси у ворот
	for id: int in _vis.keys():
		if now.has(id):
			continue
		var v2: Worker = (_vis[id] as Array)[0]
		_vis.erase(id)
		if not sim.world.inb(v2.cell()):
			continue
		var sd := -1 if v2.pos.x < sim.world.w * 0.5 else 1
		var pts := PackedVector2Array([v2.pos * T])
		var gate := v2.exit_cell
		if v2.cell() != gate and sim.world.inb(gate):
			for c: Vector2i in sim.world.find_path(v2.cell(), gate):
				pts.append((Vector2(c) + Vector2(0.5, 0.5)) * T)
		pts.append(Vector2(pts[pts.size() - 1].x, _yn()))
		_own_view(v2)
		pts.append_array(_exit_to_stop(Vector2(pts[pts.size() - 1].x, _yn()), sd, WorldView.vhash(v2.id, 3)).slice(1))
		_trips[v2.id] = _trip(v2, pts, _vm, _walk(), "", "bus", -1, -1, sd)
		_hold_for_bus(_trips[v2.id])


func _own_view(w: Worker) -> void:
	if _own.has(w.id):
		return
	var v := WorkerView.new()
	ents.add_child(v)
	v.setup(sim, w)
	_own[w.id] = v


## Уход: к подъезду или на автобус (по хешу id и дня; на автобус — если ждать недолго).
func _depart(w: Worker, side: int, head: PackedVector2Array, salt: int) -> void:
	var from := head[head.size() - 1]
	var day := int(_vm / 1440.0)
	var hv := WorldView.vhash(w.id * 13 + salt, day)
	var door := _home_door(w.id, side)
	var pts := PackedVector2Array(head)
	var spd := _walk()
	var by_bus := hv % 100 < BUS_SHARE or door < 0
	if by_bus:
		var tail := _exit_to_stop(from, side, hv >> 7)
		var ta := _vm + (_plen(head) + _plen(tail)) / spd
		if door >= 0 and next_dwell(side, ta) - ta > 15.0:
			by_bus = false
	if by_bus:
		pts.append_array(_exit_to_stop(from, side, hv >> 7).slice(1))
		_trips[w.id] = _trip(w, pts, _vm, spd, "", "bus", -1, -1, side)
	else:
		pts.append_array(_exit_to_door(from, side, _doors()[door]).slice(1))
		_trips[w.id] = _trip(w, pts, _vm, spd, "", "door", -1, door, side)
	_hold_for_bus(_trips[w.id])


## Приход: заранее знаем, когда симуляция выпустит человека на участок (начало смены + arrive_off) —
## выпускаем его из подъезда или из автобуса так, чтобы он дошёл до края карты как раз к этому времени.
func _plan_arrivals() -> void:
	for w: Worker in sim.workers:
		if w.present or _own.has(w.id):
			continue
		var tr0: Dictionary = _trips.get(w.id, {})
		if not tr0.is_empty() and str(tr0["post"]) != "edge":
			continue   # ещё идёт домой
		var sd := _edge_exit(w)
		if sd == 0:
			continue
		var win := sim.shift_window(w, _vm)
		if w.shift_anchor != win.x or not sim.shift_is_workday(win) or w.skip_shift or w.gone_anchor == win.x:
			continue
		var a := win.x + w.arrive_off
		if a >= win.y - 30.0 or w.sick_until > a or _vm > a + 3.0 or _vm < a - 90.0:
			continue
		if not tr0.is_empty() and absf(float(tr0["arr"]) - a) < 0.01:
			continue
		var tr := _arrival(w, sd, a)
		if not tr.is_empty():
			_trips[w.id] = tr


func _arrival(w: Worker, side: int, a: float) -> Dictionary:
	var exit := (Vector2(w.exit_cell) + Vector2(0.5, 0.5)) * T
	var hv := WorldView.vhash(w.id * 17 + 3, int(a / 1440.0))
	var spd := _walk()
	var door := _home_door(w.id, side)
	var tr := {}
	if hv % 100 < BUS_SHARE or door < 0:
		var pts := _rev(_exit_to_stop(exit, side, hv >> 7))
		pts.insert(0, _bus_door(side, hv >> 3))
		var dur := _plen(pts) / spd
		var ds := prev_dwell(side, a - dur - 0.3)
		if a - dur - 0.3 - ds <= 8.0 or door < 0:
			var t0 := ds + 0.3
			tr = _trip(w, pts, t0, _plen(pts) / maxf(a - t0, 0.5), "bus", "edge", -1, -1, side)
	if tr.is_empty():
		var pts2 := _rev(_exit_to_door(exit, side, _doors()[door]))
		tr = _trip(w, pts2, a - _plen(pts2) / spd, spd, "door", "edge", door, -1, side)
		_early_for_bus(tr)
	tr["arr"] = a
	return tr


# ---------------------------------------------------------------- горожане

func _folk_tick(np: Dictionary) -> void:
	var ds := _doors()
	var fr: Array[int] = []
	for i in ds.size():
		if _front_door(i):
			fr.append(i)
	if fr.size() < 2:
		return
	if _folk.is_empty():
		var rng := RandomNumberGenerator.new()
		rng.seed = 13030
		for k in FOLK_N:
			var w := People.make(rng, "laborer", 0.5)
			w.id = -9000 - k
			w.present = false
			w.dressed = false
			w.age = rng.randi_range(18, 75)
			w.pos = Vector2(-1000, -1000)
			var v := WorkerView.new()
			ents.add_child(v)
			v.setup(sim, w)
			_folk.append({"w": w, "view": v, "c": -999999, "trip": {}})
	var cyc := float(_schedule()["p"]) * 3.0
	for k2 in _folk.size():
		var f: Dictionary = _folk[k2]
		var off := float(k2) * 37.3
		var c := int(floorf((_vm + off) / cyc))
		if int(f["c"]) != c:
			f["c"] = c
			f["trip"] = _folk_trip(f["w"], k2, c, float(c) * cyc - off, fr)
		var tr: Dictionary = f["trip"]
		if tr.is_empty() or tr.has("done"):
			continue
		var ps := _pose_of(tr, _vm)
		if not ps.is_empty():
			np[(f["w"] as Worker).id] = ps


func _folk_trip(w: Worker, k: int, c: int, cs: float, fr: Array[int]) -> Dictionary:
	var hv := WorldView.vhash(k * 31 + 7, c)
	var ds := _doors()
	var ia := fr[(hv >> 2) % fr.size()]
	var da: Dictionary = ds[ia]
	var ax := (da["door"] as Vector2).x
	var side := -1 if absf(ax - _xs(-1)) < absf(ax - _xs(1)) else 1
	var t_start := cs + float((hv >> 12) % 25)
	var tod := fposmod(t_start, 1440.0)
	if (tod > 1380.0 or tod < 330.0) and hv % 6 != 0:
		return {}   # ночью в квартале почти никто не ходит
	var spd := _walk() * (0.85 + float((hv >> 6) % 5) * 0.06)
	match hv % 4:
		2:   # из подъезда — на автобус
			var pts := _door_leg(da, _xs(side))
			var wx := _wait_x(side, hv >> 9)
			pts.append(Vector2(wx, _ys()))
			pts.append(Vector2(wx, _yv()))
			return _trip(w, pts, t_start, spd, "door", "bus", ia, -1, side)
		3:   # с автобуса — домой
			var wx2 := _wait_x(side, hv >> 9)
			var pts2 := PackedVector2Array([_bus_door(side, hv >> 3), Vector2(wx2, _yv()), Vector2(wx2, _ys())])
			pts2.append_array(_rev(_door_leg(da, wx2)))
			return _trip(w, pts2, next_dwell(side, t_start) + 0.3, spd, "bus", "door", -1, ia, side)
		_:   # в гости к соседнему подъезду
			var j := clampi(fr.find(ia) + (1 + (hv >> 8) % 4) * (1 if (hv >> 5) % 2 == 0 else -1), 0, fr.size() - 1)
			var ib := fr[j]
			if ib == ia:
				return {}
			var db: Dictionary = ds[ib]
			var pts3 := _door_leg(da, (db["door"] as Vector2).x)
			pts3.append_array(_rev(_door_leg(db, ax)))
			return _trip(w, pts3, t_start, spd, "door", "door", ia, ib, side)
	return {}


# ---------------------------------------------------------------- деревья на газоне за краем карты

func _sync_trees() -> void:
	var w := sim.world
	var sea := sim.season.season_id()
	var mon := sim.season.month()
	var sig := "%d|%d|%s|%d" % [w.w, w.h, sea, mon]
	if sig == _tree_sig:
		return
	_tree_sig = sig
	for t in _trees:
		t.queue_free()
	_trees.clear()
	var names := ["poplar", "birch", "maple"]
	var gy := w.sidewalk_row + 5
	if gy >= w.h:
		return
	for x in range(-CityBackdrop.M, w.w + CityBackdrop.M):
		if x >= 0 and x < w.w:
			continue
		var hv := WorldView.vhash(x, gy)
		if posmod(x, 3) != 0 or zebra_at(w, x) != 0 or platform_at(w, x) or hv % 7 == 0 or CityBackdrop.bridge_at(w, x):
			continue
		var look := "summer"
		match sea:
			"winter":
				look = "winter"
			"autumn":
				look = "autumn" if mon >= 9 or hv % 3 != 0 else "summer"
		var sp := Sprite2D.new()
		sp.texture = Tex.obj("tree_%s_%s" % [names[hv % 3], look])
		sp.centered = false
		var k := 0.7 * (0.92 + float(hv % 5) * 0.04)
		sp.scale = Vector2(k, k)
		sp.offset = Vector2(-48, -120)
		sp.flip_h = hv % 2 == 0
		if sp.flip_h:
			sp.offset.x = -sp.offset.x - 96.0
		sp.position = Vector2(x * T + T * 0.5, gy * T + T * 0.94)
		ents.add_child(sp)
		_trees.append(sp)


# ---------------------------------------------------------------- рисунок: остановки, автобус, открытые двери

func _draw() -> void:
	if sim == null:
		return
	var ds := _doors()
	for i: int in _open.keys():
		if i < 0 or i >= ds.size():
			continue
		var p: Vector2 = (ds[i] as Dictionary)["door"]
		draw_rect(Rect2(p.x - 5, p.y - 7, 10, 7), Color("#1c1915"))
		draw_rect(Rect2(p.x + 5, p.y - 7, 3, 7), Color("#7a5e48"))
		draw_rect(Rect2(p.x - 4, p.y - 6, 8, 2), Color(0.95, 0.85, 0.55, 0.35))
	for sd: int in [-1, 1]:
		_shelter(sd)
	if not is_nan(_bus_x):
		_bus(Vector2(_bus_x, _yb()))


## Павильон остановки: навес, задняя стенка из стекла, скамейка, табличка «А».
func _shelter(side: int) -> void:
	var cx := _xs(side)
	var y0 := (sim.world.h - 1) * T
	var r := Rect2(cx - 1.2 * T, y0 + 2, 2.4 * T, T - 6)
	draw_rect(Rect2(r.position + Vector2(5, 7), r.size), Color(0, 0, 0, 0.25))
	draw_rect(Rect2(r.position.x, r.end.y - 9, r.size.x, 9), Color(0.62, 0.78, 0.86, 0.55))
	draw_rect(Rect2(r.position.x + 6, r.end.y - 14, r.size.x - 12, 5), Color("#6b4f3a"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - 9)), Color("#4f7d9a"))
	draw_rect(Rect2(r.position, Vector2(r.size.x, r.size.y - 9)), Color("#36576b"), false, 1.5)
	var sp := Vector2(r.end.x + 0.35 * T, y0 + 4)
	draw_line(sp, sp + Vector2(0, T - 8), Color("#8a8f92"), 2.0)
	draw_circle(sp + Vector2(0, 4), 6.0, Color("#e8e2c8"))
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	draw_string(f, sp + Vector2(-4, 8), "А", HORIZONTAL_ALIGNMENT_LEFT, -1, 10, Color("#2a5a3a"))


## Городской автобус «три четверти» (едет вправо): жёлтая крыша с люками, ближний борт с окнами и дверями.
func _bus(c: Vector2) -> void:
	var ln := 5.2 * T
	var top := c.y - 0.85 * T
	var roof := Rect2(c.x - ln * 0.5, top, ln, 1.05 * T)
	var side := Rect2(c.x - ln * 0.5, roof.end.y, ln, 0.5 * T)
	draw_rect(Rect2(roof.position + Vector2(6, 10), Vector2(ln, roof.size.y + side.size.y)), Color(0, 0, 0, 0.3))
	draw_rect(roof, Color("#d9a83a"))
	draw_rect(roof.grow(-4), Color("#e8c46a"))
	for k in 3:
		draw_rect(Rect2(roof.position.x + 26 + k * 46, c.y - 0.45 * T, 18, 14), Color("#c9a85a"))
		draw_rect(Rect2(roof.position.x + 28 + k * 46, c.y - 0.45 * T + 2, 14, 10), Color("#d8bd7a"))
	draw_rect(Rect2(roof.end.x - 10, roof.position.y + 4, 7, roof.size.y - 8), Color("#2f4652"))   # лобовое стекло
	draw_rect(side, Color("#c8962e"))
	draw_line(side.position, Vector2(side.end.x, side.position.y), Color("#8a6420"), 1.5)
	var stopped := absf(c.x - _xs(-1)) < 0.5 or absf(c.x - _xs(1)) < 0.5
	var wx := side.position.x + 6
	while wx + 12 < side.end.x - 4:
		var over_door := false
		for o: float in DOOR_OFF:
			if absf(wx + 6 - (c.x + o * T)) < 14:
				over_door = true
		if not over_door:
			draw_rect(Rect2(wx, side.position.y + 2, 12, side.size.y * 0.5), Color("#3e5866"))
		wx += 15
	for o2: float in DOOR_OFF:
		var dr := Rect2(c.x + o2 * T - 9, side.position.y + 2, 18, side.size.y - 2)
		draw_rect(dr, Color("#1c1915") if stopped else Color("#4a5a62"))
		if not stopped:
			draw_line(Vector2(dr.get_center().x, dr.position.y), Vector2(dr.get_center().x, dr.end.y), Color("#2a3238"), 1.0)
	draw_line(Vector2(side.position.x, side.end.y - 3), Vector2(side.end.x, side.end.y - 3), Color("#b0472e"), 2.0)
	draw_circle(Vector2(side.position.x + 26, side.end.y), 5.0, Color("#222426"))
	draw_circle(Vector2(side.end.x - 30, side.end.y), 5.0, Color("#222426"))
	draw_rect(Rect2(side.end.x - 3, side.position.y + 3, 4, 5), Color("#f4ecc0"))
