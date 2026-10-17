extends SceneTree
## Тест версии 1.21 «Удобство»: гранты по ситуации, готовые помещения к готовой стене (общая стена),
## выбор пола и стен для готовых помещений, новые стены/двери/ворота.
## godot --headless --path . -s res://tests/stage121_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _ids(a: Array) -> Array:
	return a.map(func(g: Dictionary) -> String: return str(g["id"]))


func _init() -> void:
	Defs.load_all()

	print("— гранты по ситуации")
	var g := Scenario.new_game("garage", "mech", "calm", 211)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.rooms.update()
	var ids := _ids(g.grants.offers())
	print("    предложено: ", ", ".join(PackedStringArray(ids)))
	check(Defs.grants.size() >= 20, "программ стало больше: %d" % Defs.grants.size())
	check(not ids.has("wc_locker"), "туалет и бытовка уже есть — грант на их постройку не предлагают")
	check(ids.has("locker_grow"), "зато предлагают расширить бытовку")
	check(not ids.has("canteen"), "столовая есть — на неё гранта нет")
	check(not ids.has("crisis"), "касса в плюсе — антикризисной поддержки нет")
	g.money = -5000.0
	check(_ids(g.grants.offers()).has("crisis"), "касса в минусе — появилась антикризисная поддержка")
	g.money = 1000000.0
	# расширение бытовки: условие считается от состояния на момент оформления
	check(g.grants.take("locker_grow") == "", "оформили «Расширение бытовки»")
	var a: Dictionary = g.grants.active[0]
	var gd := Grants.def("locker_grow")
	check(not g.grants.goal_ok(gd["goals"][0], a), "бытовка ещё не расширена")
	check(not g.grants.goal_ok(gd["goals"][1], a), "шкафчиков не прибавилось")
	var d0 := g.to_dict()
	var gb := Sim.from_dict(d0)
	check(gb.grants.active.size() == 1 and (gb.grants.active[0] as Dictionary)["base"].has("things"), "оформленная программа сохраняется вместе с базой")

	print("— готовое помещение к готовой стене")
	var s := Scenario.new_game("sandbox", "mech", "calm", 212, {"money": 5000000, "all_open": true})
	s.story.enabled = false
	s.bmats.enabled = false
	var c0 := Vector2i(int(s.world.plot.get_center().x) - 10, int(s.world.plot.get_center().y) - 8)
	check(Templates.place(s, "storage", c0) == "", "первый склад поставлен")
	var sz := Templates.size("storage")
	# второе — вплотную справа: левая стена второго совпадает с правой стеной первого
	var c1 := c0 + Vector2i(sz.x - 1, 0)
	var err := Templates.check(s, "storage", c1)
	check(err == "", "второе помещение встаёт к готовой стене: «%s»" % err)
	var full := Templates.cost(s, "storage")
	var shared := Templates.cost(s, "storage", c1)
	check(shared < full, "общая стена не оплачивается: %s вместо %s" % [Defs.money_str(shared), Defs.money_str(full)])
	var bp0 := 0
	for i in s.world.w * s.world.h:
		if s.world.bp_wall[i] != World.BP_NONE:
			bp0 += 1
	check(Templates.place(s, "storage", c1) == "", "второй склад поставлен")
	var bp1 := 0
	for i2 in s.world.w * s.world.h:
		if s.world.bp_wall[i2] != World.BP_NONE:
			bp1 += 1
	var perim := 2 * (sz.x + sz.y) - 4
	check(bp1 - bp0 < perim, "стен второго строят меньше контура: %d из %d" % [bp1 - bp0, perim])
	check(Templates.check(s, "storage", c1 + Vector2i(1, 0)) != "", "внахлёст (стена внутри) — нельзя")

	print("— выбор пола и стен")
	var base := Templates.cost(s, "workshop")
	Templates.pick_floor = int(Defs.floors["parquet"]["id"])
	var parq := Templates.cost(s, "workshop")
	Templates.pick_floor = -1
	Templates.pick_wall = World.W_PARTITION
	var part := Templates.cost(s, "workshop")
	Templates.pick_wall = -1
	check(parq > base, "паркет дороже бетона: %s > %s" % [Defs.money_str(parq), Defs.money_str(base)])
	check(part < base, "перегородки дешевле кирпича: %s < %s" % [Defs.money_str(part), Defs.money_str(base)])
	Templates.pick_wall = World.W_SILICATE
	var wc := Templates.wall_cells("workshop", Vector2i.ZERO)
	var sil := 0
	for k in wc.keys():
		if int(wc[k]) == World.W_SILICATE:
			sil += 1
	Templates.pick_wall = -1
	check(sil > 10, "стены из выбранного материала (силикат): %d кл." % sil)

	print("— новые стены, двери, ворота")
	for key in ["silicate", "gasblock", "glass_door", "gate_warm"]:
		check(Defs.walls.has(key) and bool(Defs.walls[key].get("buildable", false)), "есть «%s»" % str(Defs.walls.get(key, {}).get("name", key)))
	check(WallKinds.is_plain(World.W_SILICATE) and WallKinds.is_plain(World.W_GASBLOCK), "силикат и газобетон — глухие стены")
	check(WallKinds.is_door(World.W_GLASS_DOOR) and not Defs.wall_solid(World.W_GLASS_DOOR), "остеклённая дверь — проход")
	check(WallKinds.is_gate(World.W_GATE_WARM) and WallKinds.is_room_wall(World.W_GATE_WARM), "синие ворота — ворота помещения")
	# помещение с остеклённой дверью и синими воротами распознаётся
	var s2 := Scenario.new_game("sandbox", "mech", "calm", 213, {"money": 5000000, "all_open": true})
	var o := Vector2i(int(s2.world.plot.get_center().x) - 3, int(s2.world.plot.get_center().y) - 3)
	for y in 6:
		for x in 7:
			var c := o + Vector2i(x, y)
			var ii := s2.world.idx(c)
			if x == 0 or y == 0 or x == 6 or y == 5:
				s2.world.wall[ii] = World.W_SILICATE
			else:
				s2.world.flr[ii] = 1
	s2.world.wall[s2.world.idx(o + Vector2i(3, 5))] = World.W_GLASS_DOOR
	s2.world.wall[s2.world.idx(o + Vector2i(0, 2))] = World.W_GATE_WARM
	s2.world.refresh_all()
	s2.rooms.update()
	var r := s2.rooms.room_at(o + Vector2i(2, 2))
	check(r != null, "помещение из силиката с остеклённой дверью и синими воротами распознано")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
