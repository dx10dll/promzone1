class_name Plan
extends RefCounted
## 1.17: режим планировки (как в Prison Architect). Игрок рисует будущий завод на «кальке»: стены, полы,
## зоны и объекты. Это бесплатно и ни к чему не обязывает — рабочие план не трогают. «Утвердить план»
## превращает его в обычные чертежи (с оплатой); зоны и объекты, которым ещё нужны стены и пол,
## ждут постройки и размечаются сами.

var sim: Sim
var walls := {}     ## idx -> вид стены (World.W_*)
var floors := {}    ## idx -> id пола
var zones := {}     ## idx -> тип зоны
var objs: Array = []   ## [{def, x, y, rot, ok}] ok — утверждён, ждёт места
var ok_zones := {}  ## idx -> тип: утверждённые зоны, ждут, пока помещение построят
var rev := 0
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


func is_empty() -> bool:
	return walls.is_empty() and floors.is_empty() and zones.is_empty() and objs.is_empty() and ok_zones.is_empty()


func pending_empty() -> bool:
	return walls.is_empty() and floors.is_empty() and zones.is_empty() and objs.filter(func(o: Dictionary) -> bool: return not bool(o.get("ok", false))).is_empty()


func _touch() -> void:
	rev += 1


func add_wall(c: Vector2i, kind: int) -> bool:
	var w := sim.world
	if not w.in_plot(c):
		return false
	var i := w.idx(c)
	if w.wall[i] == kind:
		return false
	walls[i] = kind
	_touch()
	return true


func add_floor(c: Vector2i, fid: int) -> bool:
	var w := sim.world
	if not w.in_plot(c):
		return false
	var i := w.idx(c)
	if w.flr[i] == fid or walls.has(i):
		return false
	floors[i] = fid
	_touch()
	return true


func paint_zone(r: Rect2i, type: String) -> int:
	var w := sim.world
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not w.in_plot(c):
				continue
			var i := w.idx(c)
			if type == "":
				if zones.erase(i):
					n += 1
				ok_zones.erase(i)
			elif str(zones.get(i, "")) != type:
				zones[i] = type
				n += 1
	if n > 0:
		_touch()
	return n


## Объект на плане: в пределах участка, не поверх другого объекта плана. Стены и полы пока не важны.
func add_obj(def_id: String, c: Vector2i, rot: int) -> String:
	var err := can_add_obj(def_id, c, rot)
	if err != "":
		return err
	objs.append({"def": def_id, "x": c.x, "y": c.y, "rot": rot, "ok": false})
	_touch()
	return ""


func can_add_obj(def_id: String, c: Vector2i, rot: int) -> String:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if d.is_empty():
		return L.t("Неизвестный объект")
	var r := obj_rect(def_id, c, rot)
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			if not sim.world.in_plot(Vector2i(x, y)):
				return L.t("Только внутри участка")
	for o: Dictionary in objs:
		if obj_rect(str(o["def"]), Vector2i(int(o["x"]), int(o["y"])), int(o["rot"])).intersects(r):
			return L.t("Здесь на плане уже стоит объект")
	return ""


static func obj_rect(def_id: String, c: Vector2i, rot: int) -> Rect2i:
	var bs: Array = Defs.objects.get(def_id, {}).get("size", [1, 1])
	return Rect2i(c, Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), rot))


## Стереть план в прямоугольнике.
func erase(r: Rect2i) -> int:
	var w := sim.world
	var n := 0
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			if not w.inb(c):
				continue
			var i := w.idx(c)
			for dct: Dictionary in [walls, floors, zones, ok_zones]:
				if dct.erase(i):
					n += 1
	var keep: Array = []
	for o: Dictionary in objs:
		if obj_rect(str(o["def"]), Vector2i(int(o["x"]), int(o["y"])), int(o["rot"])).intersects(r):
			n += 1
		else:
			keep.append(o)
	objs = keep
	if n > 0:
		_touch()
	return n


func clear() -> void:
	walls.clear()
	floors.clear()
	zones.clear()
	ok_zones.clear()
	objs.clear()
	_touch()


## Сколько будет стоить построить по плану.
func cost() -> float:
	var s := 0.0
	var w := sim.world
	for i in walls.keys():
		if w.wall[int(i)] != int(walls[i]):
			s += sim.wall_cost(int(walls[i]))
	for i2 in floors.keys():
		if w.flr[int(i2)] != int(floors[i2]):
			s += sim.floor_cost(int(floors[i2]))
	for o: Dictionary in objs:
		if not bool(o.get("ok", false)):
			s += sim.thing_cost(str(o["def"]))
	return s


func counts() -> Dictionary:
	var zc := {}
	for t in zones.values():
		zc[t] = true
	return {"walls": walls.size(), "floors": floors.size(), "zones": zc.size(), "objs": objs.filter(func(o: Dictionary) -> bool: return not bool(o.get("ok", false))).size()}


## Утвердить: полы, стены, объекты — в чертежи (пока хватает денег); зоны ждут постройки.
## Возвращает {"floors", "walls", "objs", "wait", "broke"}.
func approve() -> Dictionary:
	var w := sim.world
	var res := {"floors": 0, "walls": 0, "objs": 0, "wait": 0, "broke": false}
	# деревья и кусты на месте будущих стен, полов и станков — под снос
	var cells := {}
	for i0 in walls.keys():
		cells[int(i0)] = true
	for i1 in floors.keys():
		cells[int(i1)] = true
	for o0: Dictionary in objs:
		var orr := obj_rect(str(o0["def"]), Vector2i(int(o0["x"]), int(o0["y"])), int(o0["rot"]))
		for y in range(orr.position.y, orr.end.y):
			for x in range(orr.position.x, orr.end.x):
				if w.inb(Vector2i(x, y)):
					cells[w.idx(Vector2i(x, y))] = true
	for ci in cells.keys():
		if w.flora[int(ci)] != 0:
			sim.place_demolish(w.cell_of(int(ci)))
	for i in floors.keys():
		var c := w.cell_of(int(i))
		if not sim.can_afford(sim.floor_cost(int(floors[i]))):
			res["broke"] = true
			break
		if sim.place_floor_bp(c, int(floors[i])):
			res["floors"] = int(res["floors"]) + 1
	if not bool(res["broke"]):
		floors.clear()
	for i2 in walls.keys():
		var c2 := w.cell_of(int(i2))
		if not sim.can_afford(sim.wall_cost(int(walls[i2]))):
			res["broke"] = true
			break
		if sim.place_wall_bp(c2, int(walls[i2])):
			res["walls"] = int(res["walls"]) + 1
	if not bool(res["broke"]):
		walls.clear()
	for o: Dictionary in objs:
		if bool(o.get("ok", false)):
			continue
		o["ok"] = true
	for i3 in zones.keys():
		ok_zones[i3] = zones[i3]
	zones.clear()
	_place_waiting(res)
	_apply_zones()
	res["wait"] = objs.size()
	_touch()
	return res


## Утверждённые объекты, которым теперь хватает места (пол, нет стен) — заказать.
func _place_waiting(res: Dictionary = {}) -> void:
	var keep: Array = []
	for o: Dictionary in objs:
		if not bool(o.get("ok", false)):
			keep.append(o)
			continue
		var def_id := str(o["def"])
		var c := Vector2i(int(o["x"]), int(o["y"]))
		var rot := int(o["rot"])
		if sim.can_place(def_id, c, rot) == "" and sim.can_afford(sim.thing_cost(def_id)):
			sim.place_thing(def_id, c, false, true, rot)
			if res.has("objs"):
				res["objs"] = int(res["objs"]) + 1
			continue
		# объект уже стоит на этом месте (поставили руками) — из плана убрать
		var t := sim.thing_at(c)
		if t and t.def_id == def_id:
			continue
		keep.append(o)
	if keep.size() != objs.size():
		objs = keep
		_touch()


## Утверждённые зоны там, где помещение уже построено, — разметить.
func _apply_zones() -> void:
	if ok_zones.is_empty():
		return
	var by_type := {}
	for i in ok_zones.keys():
		var c := sim.world.cell_of(int(i))
		if sim.rooms.room_at(c) == null:
			continue
		var t := str(ok_zones[i])
		if not by_type.has(t):
			by_type[t] = []
		(by_type[t] as Array).append(c)
	if by_type.is_empty():
		return
	for t2 in by_type.keys():
		var cells: Array = by_type[t2]
		sim.rooms.paint_cells(cells, str(t2))
		for c2: Vector2i in cells:
			ok_zones.erase(sim.world.idx(c2))
	_touch()


func tick(dt: float) -> void:
	if ok_zones.is_empty() and not objs.any(func(o: Dictionary) -> bool: return bool(o.get("ok", false))):
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 20.0
	_place_waiting()
	_apply_zones()


func to_dict() -> Dictionary:
	return {"walls": walls, "floors": floors, "zones": zones, "objs": objs, "okz": ok_zones}


func from_dict(d: Dictionary) -> void:
	walls = {}
	for k in (d.get("walls", {}) as Dictionary).keys():
		walls[int(k)] = int(d["walls"][k])
	floors = {}
	for k2 in (d.get("floors", {}) as Dictionary).keys():
		floors[int(k2)] = int(d["floors"][k2])
	zones = {}
	for k3 in (d.get("zones", {}) as Dictionary).keys():
		zones[int(k3)] = str(d["zones"][k3])
	ok_zones = {}
	for k4 in (d.get("okz", {}) as Dictionary).keys():
		ok_zones[int(k4)] = str(d["okz"][k4])
	objs = d.get("objs", [])
	_touch()
