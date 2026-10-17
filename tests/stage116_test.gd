extends SceneTree
## Тест версии 1.16 «Станки»: по пять советских станков на каждый передел, размеры деталей
## (мелкие / средние / крупные), станки с ЧПУ — советские и вымышленные по мотивам импортных.
## godot --headless --path . -s res://tests/stage116_test.gd

const S := preload("res://tests/setups.gd")
const PROCS := ["turning", "milling", "drilling", "welding", "assembly", "heat", "paint"]

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()

	print("— каталог станков")
	var per := {}
	var cnc: Array[String] = []
	var no_size: Array[String] = []
	var no_spr: Array[String] = []
	for k in Defs.objects.keys():
		var od: Dictionary = Defs.objects[k]
		if str(od.get("kind", "")) != "machine":
			continue
		var md: Dictionary = od["machine"]
		if not md.has("part_size"):
			no_size.append(str(k))
		for suf in ["", "_v", "_b"]:
			if not Defs.sprites.has(str(k) + suf):
				no_spr.append(str(k) + suf)
		if bool(md.get("cnc", false)):
			cnc.append(str(k))
			continue
		var pr := str(md["process"])
		if not per.has(pr):
			per[pr] = []
		(per[pr] as Array).append(str(k))
	check(no_size.is_empty(), "у каждого станка указан размер деталей %s" % str(no_size))
	check(no_spr.is_empty(), "у каждого станка три вида: спереди, сбоку, со спины %s" % str(no_spr))
	for pr in PROCS:
		var arr: Array = per.get(pr, [])
		var sizes := {}
		for k2 in arr:
			sizes[Defs.machine_rank(str(k2))] = true
		check(arr.size() >= 5 and sizes.size() >= 2, "%s: %d станков, размеров %d" % [Defs.process_name(pr), arr.size(), sizes.size()])
	check(cnc.size() == 8, "станков с ЧПУ восемь: %s" % ", ".join(cnc))
	var names: Array[String] = []
	var imp := 0
	for k3 in cnc:
		names.append(str(Defs.objects[k3]["name"]))
		if str(Defs.objects[k3].get("research", "")) == "cnc_import":
			imp += 1
	var all_names := " ".join(names)
	check(all_names.contains("16А20Ф3") and all_names.contains("65А60"), "советские ЧПУ: 16А20Ф3 и 65А60")
	check(imp == 6, "шесть импортных — по разработке «Импортное ЧПУ»")
	var real := false
	for bad in ["Hartford", "Doosan", "Puma", "Hankook", "Mynx", "SDV", "Haas", "DMG", "Mazak"]:
		if all_names.contains(bad):
			real = true
	check(not real, "названия импортных вымышленные: %s" % all_names)
	check(Defs.research.has("cnc_mill") and (Defs.research["cnc_import"]["req"] as Array).has("cnc_mill"), "дерево: ЧПУ токарный → обрабатывающий центр → импорт")
	check(FileAccess.get_file_as_string("res://scripts/ui/hud.gd").contains("\"Станки\", \"ЧПУ\"") and str(Defs.objects["cnc_lathe"]["cat"]) == "ЧПУ", "в меню объектов отдельный раздел «ЧПУ»")

	print("— размеры деталей")
	var unsized: Array[String] = []
	for p in Defs.products.keys():
		if not Defs.products[p].has("size"):
			unsized.append(str(p))
	check(unsized.is_empty(), "у каждого изделия есть размер")
	check(Defs.product_rank("pin") == 0 and Defs.product_rank("shaft") == 1 and Defs.product_rank("axle") == 2, "палец мелкий, вал средний, вагонная ось крупная")
	check(Production.size_ok("pin", "turning", {"turning": 0}) and not Production.size_ok("shaft", "turning", {"turning": 0}), "на настольном токарном — только мелочь")
	check(Production.size_ok("axle", "turning", {"turning": 2}) and not Production.size_ok("axle", "turning", {"turning": 1}), "ось — только на тяжёлом станке")
	check(Production.need_rank("drive_unit", "turning") == 1 and Production.need_rank("pump", "assembly") == 2, "размер для сборки считается по деталям узла")
	check(Defs.machine_spec("cnc_panther").contains("быстрее") and Defs.machine_spec("lathe_tv4").contains("только мелкие"), "паспорт станка: %s" % Defs.machine_spec("cnc_panther"))

	var g := Scenario.new_game("garage", "mech", "calm", 161)
	g.story.enabled = false
	S.big_shop(g)
	var avail := g.prod.processes_available()
	check(int(avail.get("turning", -1)) == 1, "в цехе с 1К62 токарка берёт до средних деталей")
	check(g.prod.can_make("drive_unit") and not g.prod.can_make("axle"), "узел приводной сделаем, вагонную ось — нет")
	var mn := g.prod.missing_name("axle", "turning", avail)
	check(mn.contains("крупных"), "сбыт объясняет: %s" % mn)
	var tv4: Thing = null
	var big: Thing = null
	for c in [Vector2i(31, 16), Vector2i(32, 16), Vector2i(31, 17)]:
		if tv4 == null and g.can_place("lathe_tv4", c) == "":
			tv4 = g.place_thing("lathe_tv4", c, true, false)
	for c2 in [Vector2i(34, 16), Vector2i(35, 16), Vector2i(34, 17), Vector2i(33, 16)]:
		if big == null and g.can_place("lathe_1m63", c2) == "":
			big = g.place_thing("lathe_1m63", c2, true, false)
	check(tv4 != null and big != null, "поставили ТВ-4 и 1М63 (%s / %s)" % [g.can_place("lathe_tv4", Vector2i(31, 16)), g.can_place("lathe_1m63", Vector2i(34, 16))])
	if tv4 == null or big == null:
		_done()
		return
	Scenario.autowire(g)
	g.world.cable_rev += 1
	g.rooms.update()
	g.power.update_topology()
	g.power.tick(0.1)
	avail = g.prod.processes_available()
	check(int(avail.get("turning", -1)) == 2, "с 1М63 токарка берёт крупные детали")
	check(tv4.part_rank() == 0 and big.part_rank() == 2 and tv4.fits_part("pin") and not tv4.fits_part("shaft"), "ТВ-4 берёт палец, но не вал")

	print("— скорость и точность")
	var turner := S.hire(g, "turner", "turning", 5)
	turner.present = true
	var l62: Thing = null
	for m in g.things_of("machine"):
		if m.def_id == "lathe":
			l62 = m
	var tk := {}
	for m2: Thing in [l62, tv4]:
		m2.product = "pin"
		m2.job_step = 0
		tk[m2.def_id] = g.brain._op_time(turner, m2)
		m2.product = ""
	check(float(tk["lathe_tv4"]) > float(tk["lathe"]), "настольный ТВ-4 медленнее 1К62: %.1f против %.1f мин" % [float(tk["lathe_tv4"]), float(tk["lathe"])])

	print("— планировщик раздаёт детали по размеру")
	for k4 in ["pin", "shaft", "axle"]:
		var o := g.orders.make_offer(k4)
		o["qty"] = 4
		o["lead"] = 6
		o["status"] = "offer"
		g.orders.list.append(o)
		g.orders.accept(int(o["id"]), true)
	for i in 6:
		g.put_on_ground(g.new_item("mat", "bar40x", "raw"), Vector2i(38 + i % 3, 16 + i / 3))
		g.put_on_ground(g.new_item("mat", "bar45", "raw"), Vector2i(41 + i % 3, 16 + i / 3))
	var bad_fit := {"n": 0, "axle_big": false}
	var t := 0.0
	while t < 240.0:
		g.tick(0.5)
		t += 0.5
		for m3 in g.things_of("machine"):
			if m3.product != "" and not m3.fits_part(m3.product):
				bad_fit["n"] = int(bad_fit["n"]) + 1
		if big.product == "axle":
			bad_fit["axle_big"] = true
	check(int(bad_fit["n"]) == 0, "ни один станок не взял деталь не по размеру")
	check(bool(bad_fit["axle_big"]), "вагонную ось поставили на 1М63 (станок в деле, хоть токарей мало)")
	check(g.planner.staffed(big), "крупный станок не простаивает из-за очереди мелких")

	print("— печи и покраска")
	var md2: Dictionary = Defs.objects["heat_tvch"]["machine"]
	check(bool(md2["batch"]) and float(md2["speed_k"]) < 0.5 and not bool(md2.get("smoke", true)), "ТВЧ: партия маленькая, но быстро и без дыма")
	check(float(Defs.objects["paint_powder"]["machine"]["cons_k"]) < 1.0, "порошковая камера экономит краску")
	var pp: Thing = null
	for c5 in [Vector2i(31, 17), Vector2i(36, 17), Vector2i(31, 15)]:
		if pp == null and g.can_place("paint_table", c5) == "":
			pp = g.place_thing("paint_table", c5, true, false)
	if pp:
		pp.product = "bracket"
		pp.job_step = 2
		var booth: Thing = null
		for m4 in g.things_of("machine"):
			if m4.def_id == "paint_booth":
				booth = m4
		booth.product = "bracket"
		booth.job_step = 2
		check(is_equal_approx(float(g.prod.cons_need(pp)[1]), float(g.prod.cons_need(booth)[1])), "стол окраски тратит краску как камера")
	_done()


func _done() -> void:
	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
