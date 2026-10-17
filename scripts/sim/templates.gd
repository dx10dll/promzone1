class_name Templates
extends RefCounted
## 1.17: готовые помещения (шаблоны). Ставятся одним щелчком как чертёж: пол, стены с проёмами,
## мебель и оборудование; зона размечается сама, когда помещение достроят. В режиме планировки —
## ложатся на план.


## 1.21: выбор игрока в меню — пол и стены для готовых помещений (-1 — как задумано в шаблоне).
static var pick_floor := -1
static var pick_wall := -1


static func def(id: String) -> Dictionary:
	return Defs.templates.get(id, {})


static func floor_id(id: String) -> int:
	return pick_floor if pick_floor > 0 else int(def(id).get("floor", 1))


static func wall_id(id: String) -> int:
	return pick_wall if pick_wall > 0 else int(def(id).get("wall", World.W_BRICK))


## 1.21: в этой клетке контура уже есть стена (своя или чужого помещения) — её используем, не строим.
static func shared(sim: Sim, c: Vector2i) -> bool:
	var w := sim.world
	if not w.inb(c):
		return false
	var v := w.wall[w.idx(c)]
	return WallKinds.is_room_wall(v) or (w.bp_wall[w.idx(c)] != World.BP_NONE and WallKinds.is_room_wall(w.bp_wall[w.idx(c)]))


static func size(id: String) -> Vector2i:
	var d := def(id)
	return Vector2i(int(d.get("w", 3)), int(d.get("h", 3)))


## Внутренний размер (без стен): «помещение 10×6».
static func inner(id: String) -> Vector2i:
	return size(id) - Vector2i(2, 2)


## {Vector2i -> wall_id} для контура с проёмами.
static func wall_cells(id: String, o: Vector2i) -> Dictionary:
	var d := def(id)
	var s := size(id)
	var out := {}
	for y in s.y:
		for x in s.x:
			if x == 0 or y == 0 or x == s.x - 1 or y == s.y - 1:
				out[o + Vector2i(x, y)] = wall_id(id)
	for op: Array in d.get("open", []):
		out[o + Vector2i(int(op[0]), int(op[1]))] = int(op[2])
	return out


static func floor_cells(id: String, o: Vector2i) -> Array[Vector2i]:
	var s := size(id)
	var out: Array[Vector2i] = []
	for y in range(1, s.y - 1):
		for x in range(1, s.x - 1):
			out.append(o + Vector2i(x, y))
	return out


static func objs(id: String) -> Array:
	return def(id).get("objs", [])


static func cost(sim: Sim, id: String, o: Vector2i = Vector2i(-9999, -9999)) -> float:
	var s := 0.0
	var fid := floor_id(id)
	s += sim.floor_cost(fid) * floor_cells(id, Vector2i.ZERO).size()
	var at := o.x > -9999
	var wc := wall_cells(id, o if at else Vector2i.ZERO)
	for c in wc.keys():
		if at and shared(sim, c) and not _opening(int(wc[c])):
			continue   # общая стена с соседним помещением — бесплатно
		s += sim.wall_cost(int(wc[c]))
	for ob: Array in objs(id):
		s += sim.thing_cost(str(ob[0]))
	return s


static func _opening(wid: int) -> bool:
	return wid == World.W_WINDOW or WallKinds.is_door(wid) or WallKinds.is_gate(wid)


## Почему шаблон недоступен (этап, разработка) — по первому закрытому предмету.
static func locked(sim: Sim, id: String) -> String:
	for ob: Array in objs(id):
		var r := sim.progress.locked_reason(str(ob[0]))
		if r != "":
			return r
	return ""


## Можно ли поставить здесь: весь контур на участке, на месте нет стен, объектов и чертежей.
static func check(sim: Sim, id: String, o: Vector2i) -> String:
	var w := sim.world
	var s := size(id)
	for y in s.y:
		for x in s.x:
			var c := o + Vector2i(x, y)
			if not w.in_plot(c):
				return "Помещение не помещается на участке"
			var i := w.idx(c)
			var edge := x == 0 or y == 0 or x == s.x - 1 or y == s.y - 1
			if edge and shared(sim, c) and w.occ[i] < 0:
				continue   # 1.21: пристраиваемся к готовой стене — она станет общей
			if w.wall[i] != World.W_NONE or w.bp_wall[i] != World.BP_NONE:
				return "Мешает стена — пристройте помещение вплотную к стене (общая стена) или выберите свободное место"
			if w.occ[i] >= 0:
				return "Мешает объект — освободите место"
			if w.bp_floor[i] != World.BP_NONE or sim.plan.ok_zones.has(i):
				return "Здесь уже строится другое помещение"
	return locked(sim, id)


## Поставить как чертёж (деньги — по смете) или на план. Возвращает текст ошибки или "".
static func place(sim: Sim, id: String, o: Vector2i, to_plan: bool = false) -> String:
	var d := def(id)
	if d.is_empty():
		return "Нет такого шаблона"
	var w := sim.world
	var fid := floor_id(id)
	var zone := str(d.get("zone", ""))
	if to_plan:
		var s := size(id)
		for y in s.y:
			for x in s.x:
				if not w.in_plot(o + Vector2i(x, y)):
					return "Помещение не помещается на участке"
		for c in floor_cells(id, o):
			sim.plan.add_floor(c, fid)
		var wc := wall_cells(id, o)
		for c2 in wc.keys():
			sim.plan.add_wall(c2, int(wc[c2]))
		if zone != "":
			sim.plan.paint_zone(Rect2i(o + Vector2i.ONE, inner(id)), zone)
		for ob: Array in objs(id):
			sim.plan.add_obj(str(ob[0]), o + Vector2i(int(ob[1]), int(ob[2])), int(ob[3]))
		return ""
	var err := check(sim, id, o)
	if err != "":
		return err
	var total := cost(sim, id, o)
	if not sim.can_afford(total):
		return "Не хватает денег: нужно %s" % Defs.money_str(total)
	# деревья и кусты внутри — под снос
	var s2 := size(id)
	for y2 in s2.y:
		for x2 in s2.x:
			var cf := o + Vector2i(x2, y2)
			if w.flora[w.idx(cf)] != 0:
				sim.place_demolish(cf)
	for c3 in floor_cells(id, o):
		sim.place_floor_bp(c3, fid)
	var wc2 := wall_cells(id, o)
	for c4 in wc2.keys():
		var wid := int(wc2[c4])
		if shared(sim, c4):
			# общая стена: глухую оставляем, проём (дверь, окно, ворота) прорезаем в ней;
			# в уже готовом проёме ничего не меняем
			var cur := sim.world.wall[sim.world.idx(c4)]
			if not _opening(wid) or _opening(cur):
				continue
		sim.place_wall_bp(c4, wid)
	# объекты: что можно — сразу в заказ, остальное (мешает куст) — через план, поставится само
	for ob2: Array in objs(id):
		var def_id := str(ob2[0])
		var cc := o + Vector2i(int(ob2[1]), int(ob2[2]))
		var rot := int(ob2[3])
		if sim.can_place(def_id, cc, rot) == "":
			sim.place_thing(def_id, cc, false, true, rot)
		else:
			sim.plan.objs.append({"def": def_id, "x": cc.x, "y": cc.y, "rot": rot, "ok": true})
	# зона разметится сама, когда помещение достроят
	if zone != "":
		for c5 in floor_cells(id, o):
			sim.plan.ok_zones[w.idx(c5)] = zone
		sim.plan.rev += 1
	return ""
