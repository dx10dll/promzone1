class_name MenuScenes
extends RefCounted
## 1.24: фон главного меню — один показательный завод «Горизонт» в течение дня.
## Утро с высоты (город, поезд), цех в работе, обед в столовой, двор и проходная, вечер второй смены.
## Завод строится дважды (два одинаковых мира): пока один показывается, второй тихо
## «проматывается» до времени следующего вида — поэтому смена видов без рывков.

## [ключ, время суток (мин), камера от, камера до (клетки), зум, подпись]
const SHOTS := [
	["overview", 9.0 * 60.0 + 10.0, Vector2(20.0, 17.0), Vector2(27.0, 15.0), 0.64, "Завод с высоты"],
	["shop", 10.0 * 60.0, Vector2(35.5, 10.0), Vector2(39.5, 11.5), 1.35, "Механический цех"],
	["canteen", 12.0 * 60.0 + 34.0, Vector2(5.0, 23.5), Vector2(9.5, 24.0), 1.9, "Обед в столовой"],
	["yard", 16.0 * 60.0 + 52.0, Vector2(17.0, 23.0), Vector2(26.0, 22.0), 1.3, "Пересменка у проходной"],
	["evening", 20.0 * 60.0 + 40.0, Vector2(26.0, 13.0), Vector2(33.0, 12.0), 0.95, "Вторая смена"],
]
const CANTEEN := Rect2i(1, 21, 13, 7)


static func count() -> int:
	return SHOTS.size()


static func key(i: int) -> String:
	return str(SHOTS[i % SHOTS.size()][0])


static func caption(i: int) -> String:
	return str(SHOTS[i % SHOTS.size()][5])


static func tod_of(i: int) -> float:
	return float(SHOTS[i % SHOTS.size()][1])


## Камера: [от, до, зум].
static func cam(i: int) -> Array:
	var s: Array = SHOTS[i % SHOTS.size()]
	return [s[2], s[3], s[4]]


## Ближайшая минута (абсолютная) не раньше now, когда на часах tod.
static func next_minute(now: float, tod: float) -> float:
	var m := floorf(now / 1440.0) * 1440.0 + tod
	if m < now - 0.01:
		m += 1440.0
	return m


## Промотать мир к минуте target, не больше steps шагов. true — дошли.
static func advance_to(sim: Sim, target: float, steps: int) -> bool:
	for i in steps:
		if sim.minute >= target:
			return true
		sim.tick(minf(0.5, target - sim.minute + 0.001))
	return sim.minute >= target


## Показательный завод: гараж с пристройкой, большой цех, заводоуправление, столовая на 18 мест,
## двор с клумбами и флагштоком, 31 человек в две смены.
static func build() -> Sim:
	var sim := Scenario.new_garage(7731)
	sim.story.enabled = false
	sim.progress.tutorial = -1
	sim.bmats.enabled = false
	sim.money = 12000000.0
	sim.progress.stage = 3
	sim.progress.ooo = true
	sim.reputation = 72.0
	_shop(sim)
	_offices(sim)
	_canteen(sim)
	_yard(sim)
	sim.power.grid_level = 2
	Scenario.autowire(sim)
	Scenario.autolight(sim, false)
	Scenario.autopipe(sim)
	sim.world.cable_rev += 1
	sim.rooms.update()
	_crew(sim)
	for k in sim.cons.keys():
		sim.cons[k] = 200.0
	for p in [["bracket", 10], ["housing", 4], ["shaft", 8], ["bushing", 20], ["frame", 3]]:
		var o := sim.orders.make_offer(str(p[0]))
		o["qty"] = int(p[1])
		o["lead"] = 20
		o["status"] = "offer"
		sim.orders.list.append(o)
		sim.orders.accept(int(o["id"]), true)
	var n := 0
	for mt in ["bar45", "bar40x", "forging", "hex27", "plate8", "profile40"]:
		for q in 5:
			sim.put_on_ground(sim.new_item("mat", mt, "raw"), Vector2i(42 + n % 3, 15 + (n / 3) % 3))
			n += 1
	sim.office.policies["auto_accept"] = true
	Workplace.auto_assign(sim)
	sim.power.update_topology()
	sim.power.tick(0.1)
	sim.events.clear()
	return sim


static func _box(sim: Sim, r: Rect2i, floor_id: int, doors: Array, windows: Array = []) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	for d: Vector2i in doors:
		w.wall[w.idx(d)] = World.W_DOOR
	for wn: Vector2i in windows:
		w.wall[w.idx(wn)] = World.W_WINDOW
	w.refresh_all()


static func _put(sim: Sim, id: String, c: Vector2i) -> void:
	var why := sim.can_place(id, c)
	if why == "" or why.begins_with("Нужна ступень"):   # витрина: всё открыто
		sim.place_thing(id, c, true, false)


## Большой цех справа от гаража: все переделы, кран, стеллажи, ОТК.
static func _shop(sim: Sim) -> void:
	var w := sim.world
	_box(sim, Rect2i(29, 3, 17, 17), 1, [Vector2i(29, 14), Vector2i(29, 15)], [Vector2i(32, 3), Vector2i(33, 3), Vector2i(40, 3), Vector2i(41, 3)])
	for x in [36, 37, 38]:
		w.wall[w.idx(Vector2i(x, 19))] = World.W_GATE
	w.refresh_all()
	for e in [["mill", 31, 5], ["drill", 35, 5], ["lathe", 38, 5], ["weld_post", 31, 9], ["assembly_table", 35, 9], ["furnace", 31, 13],
			["paint_booth", 35, 13], ["wip_rack", 42, 5], ["wip_rack", 42, 7], ["rack", 42, 9], ["rack", 42, 11], ["pallet", 42, 13],
			["pallet", 43, 13], ["pallet", 44, 13], ["qc_table", 39, 9], ["crane", 44, 4], ["cart", 40, 17], ["tool_cabinet", 39, 13], ["toilet", 44, 17],
			["extinguisher", 30, 11], ["notice_board", 33, 18]]:
		_put(sim, str(e[0]), Vector2i(int(e[1]), int(e[2])))
	var ktp := sim.place_thing("ktp", Vector2i(40, 21), true, false)
	sim.rooms.update()
	var sr := sim.rooms.room_at(Vector2i(37, 10))
	if sr:
		sim.rooms.assign(sr, "workshop")
	sim.rooms.paint(Rect2i(43, 16, 2, 3), "wc")
	sim.rooms.legacy[ktp.id] = true
	Scenario._route(sim, ktp.cells())
	sim.place_thing("water_inlet", Vector2i(46, 17), true, false)


## Заводоуправление в левом верхнем углу: контора, техотдел, конторка мастера.
static func _offices(sim: Sim) -> void:
	_box(sim, Rect2i(1, 1, 10, 6), 3, [Vector2i(6, 6)], [Vector2i(4, 1), Vector2i(7, 1)])
	_box(sim, Rect2i(1, 6, 5, 5), 3, [Vector2i(5, 8)])
	_box(sim, Rect2i(7, 6, 4, 5), 3, [Vector2i(7, 8)])
	if sim.world.wall[sim.world.idx(Vector2i(4, 15))] != World.W_NONE:
		sim.world.wall[sim.world.idx(Vector2i(4, 15))] = World.W_DOOR
	sim.world.refresh_all()
	for c in [Vector2i(2, 2), Vector2i(5, 2), Vector2i(2, 4), Vector2i(5, 4), Vector2i(2, 7), Vector2i(8, 7)]:
		_put(sim, "office_desk", c)
	for e in [["drawing_board", 4, 7], ["plant", 9, 5], ["floor_clock", 9, 2], ["water_cooler", 8, 2], ["trophy_case", 9, 3], ["coat_rack", 8, 5]]:
		_put(sim, str(e[0]), Vector2i(int(e[1]), int(e[2])))
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(5, 3)), "office")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(3, 8)), "tech_office")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(8, 8)), "foreman_office")


## Столовая на 18 мест внизу слева: плита, раздача, холодильник, самовар, радио.
static func _canteen(sim: Sim) -> void:
	_box(sim, CANTEEN, 3, [Vector2i(6, 21)], [Vector2i(3, 21), Vector2i(10, 21), Vector2i(1, 24)])
	for x in [2, 5, 8]:
		_put(sim, "dining_table", Vector2i(x, 23))
		_put(sim, "dining_table", Vector2i(x, 26))
		for dx in 2:
			_put(sim, "chair", Vector2i(x + dx, 22))
			_put(sim, "chair", Vector2i(x + dx, 24))
			_put(sim, "chair", Vector2i(x + dx, 25))
	for e in [["stove", 11, 22], ["serving_line", 11, 24], ["fridge", 12, 26], ["samovar", 11, 26], ["radio", 4, 22], ["plant", 12, 23]]:
		_put(sim, str(e[0]), Vector2i(int(e[1]), int(e[2])))
	sim.rooms.update()
	var cr := sim.rooms.room_at(Vector2i(6, 24))
	if cr:
		sim.rooms.assign(cr, "canteen")


## Двор: клумбы, флагшток, скульптуры, скамейки у проходной.
static func _yard(sim: Sim) -> void:
	for e in [["flower_bed", 15, 22], ["flower_bed", 15, 25], ["statue_worker", 17, 23], ["bench", 15, 27], ["flagpole", 28, 22],
			["flower_bed", 30, 22], ["flower_bed", 33, 22], ["bench", 30, 24], ["statue_worker", 36, 23], ["flower_bed", 30, 26]]:
		_put(sim, str(e[0]), Vector2i(int(e[1]), int(e[2])))


static func _crew(sim: Sim) -> void:
	var list := [["turner", "turning", 0], ["turner", "turning", 0], ["turner", "turning", 1], ["miller", "milling", 0], ["miller", "milling", 1],
		["welder", "welding", 0], ["welder", "welding", 1], ["heat_treater", "heat", 0], ["painter", "paint", 0], ["assembler", "assembly", 0],
		["assembler", "assembly", 1], ["laborer", "haul", 0], ["laborer", "haul", 0], ["laborer", "haul", 1], ["laborer", "haul", 0],
		["qc", "qc", 0], ["qc", "qc", 1], ["cleaner", "clean", 0], ["cook", "cook", 0], ["electrician", "electric", 0], ["setter", "setup", 0],
		["foreman", "manage", 0], ["chief", "manage", 0], ["accountant", "office", 0], ["buyer", "office", 0], ["dispatcher", "office", 0],
		["technologist", "engineering", 0], ["turner", "turning", 1], ["laborer", "haul", 1], ["miller", "milling", 0], ["turner", "turning", 0]]
	for p in list:
		var wk := People.make(sim.rng, str(p[0]))
		wk.skills[str(p[1])] = 6
		wk.traits = []
		wk.wage = People.wage_for(wk)
		wk.shift = int(p[2])
		sim.add_worker(wk)
