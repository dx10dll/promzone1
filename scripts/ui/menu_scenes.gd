class_name MenuScenes
extends RefCounted
## 1.17: виды завода для главного меню — сменяются плавно, камера медленно плывёт.
## garage — гараж утром; hall — большой цех со станками всех переделов; cnc — ряд станков с ЧПУ;
## field — чистое поле: бытовка и стройка по готовым шаблонам.

const ORDER := ["garage", "hall", "cnc", "field"]
## [что показываем: от, до (в клетках), зум]. Камера смещена влево — слева меню, предмет справа от центра.
const CAMS := {
	"garage": [Vector2(19.0, 13.5), Vector2(21.5, 14.5), 1.9],
	"hall": [Vector2(13.0, 8.0), Vector2(27.0, 9.5), 1.35],
	"cnc": [Vector2(11.0, 14.5), Vector2(22.0, 13.5), 1.7],
	"field": [Vector2(25.0, 18.0), Vector2(33.0, 17.0), 1.35],
}


static func sim_key(scene: String) -> String:
	return "hall" if scene == "cnc" else scene


static func build(key: String) -> Sim:
	match key:
		"hall":
			return _hall()
		"field":
			return _field()
	return _garage()


## До какого времени дня «прокрутить» вид перед показом (люди пришли и работают).
static func ready_tod(key: String) -> float:
	match key:
		"hall":
			return 8.75 * 60.0
		"field":
			return 9.5 * 60.0
	return 9.5 * 60.0


## Прокрутить несколько шагов; true — вид готов к показу.
static func advance(sim: Sim, key: String, steps: int) -> bool:
	for i in steps:
		if sim.tod() >= ready_tod(key):
			return true
		sim.tick(0.5)
	return sim.tod() >= ready_tod(key)


static func _garage() -> Sim:
	var sim := Scenario.new_garage(7731)
	sim.events.clear()
	return sim


static func _field() -> Sim:
	var sim := Scenario.new_game("field", "mech", "calm", 5501, {"flora": true})
	sim.story.enabled = false
	sim.money += 3000000.0
	Templates.place(sim, "workshop", Vector2i(22, 12))
	Templates.place(sim, "storage", Vector2i(36, 14))
	# часть стен уже подняли — стройка в разгаре
	var w := sim.world
	var n := 0
	for i in sim.bp_cells.keys():
		var c := w.cell_of(int(i))
		if w.bp_floor[int(i)] != World.BP_NONE and w.bp_floor[int(i)] > 0 and (c.x + c.y) % 3 != 0:
			w.flr[int(i)] = int(w.bp_floor[int(i)])
			w.bp_floor[int(i)] = World.BP_NONE
		if w.bp_wall[int(i)] != World.BP_NONE and c.x < 30 and n < 22:
			w.wall[int(i)] = int(w.bp_wall[int(i)])
			w.bp_wall[int(i)] = World.BP_NONE
			n += 1
	w.refresh_all()
	for i2 in sim.bp_cells.keys():
		if w.bp_floor[int(i2)] == World.BP_NONE and w.bp_wall[int(i2)] == World.BP_NONE:
			sim.bp_cells.erase(i2)
	Scenario.hire_builders(sim, 3)
	return sim


static func _hall() -> Sim:
	var sim := Scenario.new_game("sandbox", "mech", "calm", 9917, {"money": 20000000, "map": "large", "all_open": true})
	sim.story.enabled = false
	sim.progress.stage = 4
	sim.progress.quiet_until = 0
	var w := sim.world
	var hall := Rect2i(2, 2, 40, 22)
	for y in range(hall.position.y, hall.end.y):
		for x in range(hall.position.x, hall.end.x):
			var c := Vector2i(x, y)
			w.flr[w.idx(c)] = 4
			if x == hall.position.x or x == hall.end.x - 1 or y == hall.position.y or y == hall.end.y - 1:
				w.wall[w.idx(c)] = World.W_BRICK
	w.wall[w.idx(Vector2i(2, 12))] = World.W_DOOR
	for x2 in [20, 21, 22]:
		w.wall[w.idx(Vector2i(x2, 23))] = World.W_GATE
	for x3 in [6, 7, 14, 15, 26, 27, 34, 35]:
		w.wall[w.idx(Vector2i(x3, 2))] = World.W_WINDOW
	w.refresh_all()
	var rows := [
		[4, ["lathe_tv4", 4], ["lathe_1a616", 7], ["lathe", 10], ["lathe_16k20", 14], ["lathe_1m63", 18], ["mill_6r10", 23], ["mill", 26], ["mill_6r82", 29], ["mill_6r13", 32], ["drill_2n118", 36], ["drill", 38]],
		[9, ["weld_pdg251", 4], ["weld_post", 7], ["weld_stand", 10], ["asm_press", 15], ["assembly_table", 18], ["asm_stand", 21], ["heat_tvch", 26], ["furnace", 29], ["paint_powder", 33], ["paint_booth", 36]],
		[18, ["cnc_lathe", 4], ["cnc_65a60", 8], ["cnc_sidway", 12], ["cnc_panther", 15], ["cnc_hangan", 19], ["cnc_hartwood", 24], ["cnc_minger", 28], ["cnc_maiday", 31]],
	]
	for row: Array in rows:
		for j in range(1, row.size()):
			var e: Array = row[j]
			var sz: Array = Defs.objects[str(e[0])]["size"]
			sim.place_thing(str(e[0]), Vector2i(int(e[1]), int(row[0]) - (int(sz[1]) - 1)), true, false)
	for c2 in [Vector2i(33, 15), Vector2i(36, 15), Vector2i(33, 17), Vector2i(36, 17)]:
		sim.place_thing("rack", c2, true, false)
	sim.place_thing("qc_table", Vector2i(33, 20), true, false)
	sim.place_thing("qc_table", Vector2i(36, 20), true, false)
	for x4 in range(30, 33):
		sim.place_thing("pallet", Vector2i(x4, 21), true, false)
	var kt: Array[Thing] = []
	for k in 3:
		var t := sim.place_thing("ktp", Vector2i(46, 3 + k * 4), true, false)
		if t:
			sim.rooms.legacy[t.id] = true
			kt.append(t)
	sim.rooms.update()
	var r := sim.rooms.room_at(Vector2i(20, 14))
	if r:
		sim.rooms.assign(r, "workshop")
	Scenario.autolight(sim, false)
	Scenario.autowire(sim)
	for t2 in kt:
		Scenario._route(sim, t2.cells())
	w.cable_rev += 1
	sim.rooms.update()
	var crew := [["turner", "turning"], ["turner", "turning"], ["turner", "turning"], ["miller", "milling"], ["miller", "milling"], ["welder", "welding"],
		["assembler", "assembly"], ["heat_treater", "heat"], ["painter", "paint"], ["laborer", "haul"], ["laborer", "haul"], ["laborer", "haul"], ["qc", "qc"]]
	for i in crew.size():
		var wk := People.make(sim.rng, str(crew[i][0]))
		wk.skills[str(crew[i][1])] = 6
		wk.wage = People.wage_for(wk)
		sim.add_worker(wk)
		wk.present = true
		wk.pos = Vector2(14.5 + i, 14.5 + (i % 3))
	for ck in sim.cons.keys():
		sim.cons[ck] = 200.0
	for p in [["pin", 12], ["bushing", 10], ["shaft", 6], ["housing", 4], ["bracket", 8], ["axle", 4], ["frame", 3], ["gear", 4]]:
		var o := sim.orders.make_offer(str(p[0]))
		o["qty"] = int(p[1])
		o["lead"] = 14
		o["status"] = "offer"
		sim.orders.list.append(o)
		sim.orders.accept(int(o["id"]), true)
	var n := 0
	for mt in ["bar45", "bar40x", "forging", "hex27", "plate8", "profile40"]:
		for q in 6:
			sim.put_on_ground(sim.new_item("mat", mt, "raw"), Vector2i(24 + n % 8, 20 + (n / 8) % 3))
			n += 1
	Workplace.auto_assign(sim)
	sim.power.update_topology()
	sim.power.tick(0.1)
	# станки с ЧПУ работают сами — в меню видно, как крутится шпиндель
	for m in sim.things_of("machine"):
		if m.is_cnc():
			m.product = "housing" if m.process() == "milling" else "shaft"
			m.working = true
			m.progress = 0.2 + 0.15 * (m.id % 4)
	return sim
