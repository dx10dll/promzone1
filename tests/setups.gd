extends RefCounted
## Общие заготовки для тестов и снимков: большой цех этапа 3.


static func hire(sim: Sim, prof: String, skill_key: String, lvl: int) -> Worker:
	var w := People.make(sim.rng, prof)
	w.skills[skill_key] = lvl
	w.traits = []
	w.wage = People.wage_for(w)
	sim.add_worker(w)
	return w


## Большой цех справа от гаража со всем оборудованием этапа 3, людьми и расходниками.
static func big_shop(sim: Sim, with_people: bool = true) -> void:
	sim.money = maxf(sim.money, 5000000.0)
	sim.progress.stage = maxi(sim.progress.stage, 3)
	sim.progress.ooo = true
	var w := sim.world
	var shop := Rect2i(29, 3, 17, 17)
	for y in range(shop.position.y, shop.end.y):
		for x in range(shop.position.x, shop.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = 1
			var edge := x == shop.position.x or x == shop.end.x - 1 or y == shop.position.y or y == shop.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(Vector2i(29, 14))] = World.W_DOOR
	w.wall[w.idx(Vector2i(29, 15))] = World.W_DOOR
	for x in [36, 37, 38]:
		w.wall[w.idx(Vector2i(x, 19))] = World.W_GATE
	for x in [32, 33, 40, 41]:
		w.wall[w.idx(Vector2i(x, 3))] = World.W_WINDOW
	w.refresh_all()
	sim.place_thing("mill", Vector2i(31, 5), true, false)
	sim.place_thing("drill", Vector2i(35, 5), true, false)
	sim.place_thing("lathe", Vector2i(38, 5), true, false)
	sim.place_thing("weld_post", Vector2i(31, 9), true, false)
	sim.place_thing("assembly_table", Vector2i(35, 9), true, false)
	sim.place_thing("furnace", Vector2i(31, 13), true, false)
	sim.place_thing("paint_booth", Vector2i(35, 13), true, false)
	sim.place_thing("wip_rack", Vector2i(42, 5), true, false)
	sim.place_thing("wip_rack", Vector2i(42, 7), true, false)
	sim.place_thing("rack", Vector2i(42, 9), true, false)
	sim.place_thing("rack", Vector2i(42, 11), true, false)
	sim.place_thing("pallet", Vector2i(42, 13), true, false)
	sim.place_thing("pallet", Vector2i(43, 13), true, false)
	sim.place_thing("pallet", Vector2i(44, 13), true, false)
	sim.place_thing("qc_table", Vector2i(39, 9), true, false)
	sim.place_thing("crane", Vector2i(44, 4), true, false)
	sim.place_thing("cart", Vector2i(40, 17), true, false)
	sim.place_thing("tool_cabinet", Vector2i(39, 13), true, false)
	sim.place_thing("toilet", Vector2i(44, 17), true, false)
	var ktp := sim.place_thing("ktp", Vector2i(40, 21), true, false)
	sim.power.grid_level = 2
	Scenario.autowire(sim)
	Scenario._route(sim, ktp.cells())
	sim.world.cable_rev += 1
	sim.rooms.update()
	var sr := sim.rooms.room_at(Vector2i(37, 10))
	if sr:
		sim.rooms.assign(sr, "workshop")
	# 1.13: зоны обязательны — туалет в своей зоне, подстанция на улице как в старых сохранениях
	sim.rooms.paint(Rect2i(43, 16, 2, 3), "wc")
	sim.rooms.legacy[ktp.id] = true
	# свет под потолком цеха и водопровод к туалету
	Scenario.autolight(sim, false)
	sim.place_thing("water_inlet", Vector2i(46, 17), true, false)
	Scenario.autopipe(sim)
	sim.rooms.update()
	if with_people:
		hire(sim, "turner", "turning", 6)
		hire(sim, "miller", "milling", 6)
		hire(sim, "welder", "welding", 6)
		hire(sim, "heat_treater", "heat", 5)
		hire(sim, "painter", "paint", 5)
		hire(sim, "assembler", "assembly", 6)
		hire(sim, "laborer", "haul", 7)
		hire(sim, "laborer", "haul", 6)
		hire(sim, "qc", "qc", 6)
	for k in sim.cons.keys():
		sim.cons[k] = 80.0
	sim.power.tick(0.1)


## Заказы на сложные изделия этапа 3.
static func complex_orders(sim: Sim, days: int, want: Dictionary = {}) -> void:
	if want.is_empty():
		want = {"bracket": 10, "housing": 4, "frame": 3, "spline_shaft": 4, "drive_unit": 2}
	for p in want.keys():
		var o := sim.orders.make_offer(p)
		o["qty"] = want[p]
		o["lead"] = days
		o["status"] = "offer"
		sim.orders.list.append(o)
		sim.orders.accept(int(o["id"]), true)


static func _box(sim: Sim, r: Rect2i, floor_id: int, door: Vector2i) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(door)] = World.W_DOOR
	w.refresh_all()


## Заводоуправление слева от гаража: общая контора на 5 столов, техотдел, конторка мастера.
## 1.15: сдвинуто в верхний левый угол — ниже теперь пристройка гаража (столовая, туалет, бытовка).
static func offices(sim: Sim) -> void:
	sim.progress.stage = maxi(sim.progress.stage, 3)
	_box(sim, Rect2i(1, 1, 10, 6), 3, Vector2i(6, 6))     # контора: дверь вниз, в коридорчик
	_box(sim, Rect2i(1, 6, 5, 5), 3, Vector2i(5, 8))      # техотдел: дверь в коридорчик
	_box(sim, Rect2i(7, 6, 4, 5), 3, Vector2i(7, 8))      # конторка мастера
	sim.world.wall[sim.world.idx(Vector2i(4, 1))] = World.W_WINDOW
	sim.world.wall[sim.world.idx(Vector2i(7, 1))] = World.W_WINDOW
	# 1.18: в гараже ниже стоит техпомещение — коридорчик контор выходит наружу через его дверь
	if sim.world.wall[sim.world.idx(Vector2i(4, 15))] != World.W_NONE and sim.scenario == "garage":
		sim.world.wall[sim.world.idx(Vector2i(4, 15))] = World.W_DOOR
	sim.world.refresh_all()
	for c in [Vector2i(2, 2), Vector2i(5, 2), Vector2i(8, 2), Vector2i(2, 4), Vector2i(5, 4), Vector2i(2, 7), Vector2i(8, 7)]:
		sim.place_thing("office_desk", c, true, false)
	sim.place_thing("drawing_board", Vector2i(4, 7), true, false)
	sim.place_thing("plant", Vector2i(9, 5), true, false)
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(5, 3)), "office")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(3, 8)), "tech_office")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(8, 8)), "foreman_office")
	sim.rooms.update()
