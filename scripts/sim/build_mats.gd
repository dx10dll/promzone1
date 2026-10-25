class_name BuildMats
extends RefCounted
## Стройматериалы (1.13). Стены и полы строят не из воздуха: под каждую клетку чертежа нужна
## единица материала — кирпич, блоки, панели, мешки цемента, коробки плитки. Деньги за материал
## входят в цену чертежа, а сам материал заказывается у поставщика автоматически и приезжает
## машиной: поддоны разгружают в зону разгрузки (или у ворот), оттуда строитель уносит сколько
## поднимет и строит клетки рядом одну за другой.

var sim: Sim
var enabled := true
var orders: Array = []          ## заказы в пути: [{id, mats: {def: n}, eta, spawned}]
var _t := 0.0
var _have_sig := -1
var _have: Dictionary = {}


func _init(s: Sim) -> void:
	sim = s


static func def(key: String) -> Dictionary:
	return Defs.build_mats.get(key, {})


static func mat_name(key: String) -> String:
	return str(def(key).get("name", key))


static func pallet(key: String) -> int:
	return maxi(1, int(def(key).get("pallet", 6)))


static func carry(key: String) -> int:
	return maxi(1, int(def(key).get("carry", 2)))


## Какой материал нужен чертежу в клетке ("" — никакой: снос, расчистка).
func mat_for(i: int) -> String:
	var w := sim.world
	var wv := w.bp_wall[i]
	if wv != World.BP_NONE:
		if wv == 0:
			return ""
		return str(Defs.wall_by_id.get(int(wv), {}).get("mat", ""))
	var fv := w.bp_floor[i]
	if fv != World.BP_NONE and fv != 0:
		return str(Defs.floor_by_id.get(int(fv), {}).get("mat", ""))
	return ""


## Сколько клеток чертежей ждут каждого материала.
func needed() -> Dictionary:
	var out := {}
	for i in sim.bp_cells.keys():
		var m := mat_for(int(i))
		if m != "":
			out[m] = int(out.get(m, 0)) + 1
	return out


## Сколько материала уже есть на участке, в кузове или в руках: {def: n}.
func have() -> Dictionary:
	if _have_sig == sim.item_rev:
		return _have
	_have_sig = sim.item_rev
	_have = {}
	for it: Item in sim.items.values():
		if it.kind == "bmat":
			_have[it.def_id] = int(_have.get(it.def_id, 0)) + 1
	return _have


## Сколько едет (заказано, ещё не разгружено).
func coming() -> Dictionary:
	var out := {}
	for o: Dictionary in orders:
		for k in (o["mats"] as Dictionary).keys():
			out[k] = int(out.get(k, 0)) + int(o["mats"][k])
	return out


## Свободные (не занятые) единицы материала на земле. Пересчёт раз в игровой тик:
## бронь меняется без item_rev, а спрашивают про каждую клетку чертежа.
var _free_at := -1.0
var _free: Dictionary = {}


func free_on_ground(key: String) -> int:
	if sim.minute != _free_at:
		_free_at = sim.minute
		_free = {}
		for gid in sim.ground_items:
			var it: Item = sim.items.get(gid)
			if it and it.kind == "bmat" and it.reserved_by < 0:
				_free[it.def_id] = int(_free.get(it.def_id, 0)) + 1
	return int(_free.get(key, 0))


## Можно ли строить клетку: материал не нужен или лежит на участке свободный.
func ready(i: int) -> bool:
	if not enabled:
		return true
	var m := mat_for(i)
	return m == "" or free_on_ground(m) > 0


func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0 or not enabled:
		return
	_t = 10.0
	var need := needed()
	if need.is_empty():
		return
	var hv := have()
	var cm := coming()
	var add := {}
	for k in need.keys():
		var lack := int(need[k]) - int(hv.get(k, 0)) - int(cm.get(k, 0))
		if lack > 0:
			# 1.15: заказываем ровно недостающее — поддоны вместительные, лишнее не копится
			add[k] = lack
	if add.is_empty():
		return
	# всё, что заказано почти одновременно, едет одной машиной
	for o: Dictionary in orders:
		if not bool(o["spawned"]) and float(o["eta"]) - sim.minute > 15.0:
			for k2 in add.keys():
				o["mats"][k2] = int(o["mats"].get(k2, 0)) + int(add[k2])
			return
	var eta := sim.to_work_time(sim.minute + sim.rng.randf_range(35.0, 80.0))
	orders.append({"id": sim.new_id(), "mats": add, "eta": eta, "spawned": false})
	sim.notify_once("bmat_order", L.t("Заказаны стройматериалы: %s. Привезут %s.") % [desc(add), sim._eta_str(eta)], Sim.LVL_INFO, Vector2i(-1, -1), 240.0)


## «кирпич ×8, плитка ×16»
static func desc(mats: Dictionary) -> String:
	var parts: Array[String] = []
	for k in mats.keys():
		parts.append("%s ×%d" % [mat_name(str(k)).to_lower(), int(mats[k])])
	return ", ".join(parts)


## Машины со стройматериалами: когда подошёл срок — к воротам.
func tick_trucks() -> void:
	for o: Dictionary in orders:
		if bool(o["spawned"]) or sim.minute < float(o["eta"]):
			continue
		o["spawned"] = true
		var v := sim.spawn_vehicle("delivery")
		v.bmat_order = int(o["id"])
		v.body = "flatbed"
		v.cargo_desc = L.t("стройматериалы: ") + desc(o["mats"])


## Бортовой грузовик встал у ворот: поддоны в кузове.
func on_park(v: Vehicle) -> void:
	for i in range(orders.size() - 1, -1, -1):
		var o: Dictionary = orders[i]
		if int(o["id"]) != v.bmat_order:
			continue
		for k in (o["mats"] as Dictionary).keys():
			for n in int(o["mats"][k]):
				var it := sim.new_item("bmat", str(k), "bmat")
				sim.put_in_vehicle(it, v)
		orders.remove_at(i)
	v.bmat_order = -1
	var where := L.t("в зону разгрузки") if sim.logi.has_zone() else L.t("у ворот (зоны разгрузки нет)")
	sim.notify(L.t("Привезли %s. Разгружают %s.") % [v.cargo_desc, where], Sim.LVL_INFO, v.access_cell(sim.world.sidewalk_row))


## Куда сгрузить поддон без зоны разгрузки: свободная земля у ворот, не в помещении.
func yard_cell(it: Item, near: Vector2i) -> Vector2i:
	var w := sim.world
	var start := Vector2i(sim.gate_x + 1, w.plot.end.y - 2)
	for r in range(0, 9):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if absi(dx) != r and absi(dy) != r:
					continue
				var c := start + Vector2i(dx, -absi(dy))
				if not w.in_plot(c) or not w.passable(c) or sim.rooms.room_at(c) != null:
					continue
				if w.ground[w.idx(c)] == World.Ground.ASPHALT and absi(c.x - sim.gate_x - 1) <= 2:
					continue   # проезд у самых ворот не загромождаем
				if sim.logi.cell_space(c, it) > 0:
					return c
	return w.nearest_passable(near)


func to_dict() -> Dictionary:
	return {"orders": orders, "on": enabled}


func from_dict(d: Dictionary) -> void:
	orders = d.get("orders", [])
	enabled = bool(d.get("on", true))
