extends SceneTree
## Тест версии 1.27 «Литьё и штамповка»: новые переделы, профессии, станки за исследованием,
## изделия идут по маршруту до отгрузки, звуки и картинки на месте.
## godot --headless --path . -s res://tests/stage127_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _put(g: Sim, id: String, c: Vector2i) -> Thing:
	var why := g.can_place(id, c)
	if why != "" and not why.begins_with("Нужна ступень") and not why.begins_with("Откроется"):
		print("    (не встал %s в %s: %s)" % [id, c, why])
		return null
	return g.place_thing(id, c, true, false)


func _init() -> void:
	Defs.load_all()

	print("— данные")
	for pr in ["casting", "stamping"]:
		check(Defs.processes.has(pr), "передел «%s»" % Defs.process_name(pr))
	check(Defs.consumables.has("sand"), "расходник: формовочная смесь")
	check(Defs.materials.has("charge") and Defs.materials.has("strip2"), "материалы: шихта и полоса")
	for id in ["cast_ist", "cast_line", "press_kd", "press_kb"]:
		check(Defs.objects.has(id) and Defs.sprites.has(id) and Defs.sprites.has(id + "_v") and Defs.sprites.has(id + "_b"), "станок %s: три вида" % id)
		check(ResourceLoader.exists("res://assets/objects/%s.svg" % id), "%s: картинка" % id)
	for p in ["cast_cover", "cast_body", "washer", "clamp", "bracket_st"]:
		check(Defs.products.has(p) and ResourceLoader.exists("res://assets/items/%s.svg" % p), "изделие «%s» и значок" % Defs.product_name(p))
	for snd in ["m_casting", "m_stamp", "pour"]:
		check(ResourceLoader.exists("res://assets/sound/%s.ogg" % snd), "звук %s" % snd)
	check(Worker.PROF_NAMES.has("caster") and Worker.PROF_NAMES.has("presser"), "профессии: литейщик и штамповщик")
	check(Worker.SKILL_NAMES.has("casting") and Worker.SKILL_NAMES.has("stamping"), "навыки литья и штамповки")

	print("— исследования")
	var g := Scenario.new_garage(127)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	S.big_shop(g)
	check(not g.office.unlocked(Defs.objects["cast_ist"]) and not g.office.unlocked(Defs.products["washer"]), "без исследований — закрыто")
	g.office.research_done.append("stamping_shop")
	g.office.research_done.append("casting_shop")
	check(g.office.unlocked(Defs.objects["press_kd"]) and g.office.unlocked(Defs.products["cast_body"]), "после исследований — открыто")

	print("— литейка и прессы в работе")
	var tile := int(Defs.floors["concrete"]["id"]) if Defs.floors.has("concrete") else 1
	S._box(g, Rect2i(1, 20, 18, 7), tile, Vector2i(18, 22))
	g.rooms.update()
	var rm := g.rooms.room_at(Vector2i(5, 23))
	if rm:
		g.rooms.assign(rm, "workshop")
	var ms: Array[Thing] = []
	for e in [["cast_ist", 2, 21], ["press_kd", 6, 21], ["press_kb", 8, 21], ["press_kd", 11, 21], ["pallet", 14, 21], ["pallet", 15, 21], ["pallet", 16, 21]]:
		var t := _put(g, str(e[0]), Vector2i(int(e[1]), int(e[2])))
		if t and t.kind() == "machine":
			ms.append(t)
	check(ms.size() == 4, "поставлены печь и три пресса (%d)" % ms.size())
	Scenario.autowire(g)
	Scenario.autolight(g, false)
	g.power.grid_level = 2
	g.power.update_topology()
	g.rooms.update()
	S.hire(g, "caster", "casting", 6)
	S.hire(g, "presser", "stamping", 6)
	S.hire(g, "presser", "stamping", 5)
	S.hire(g, "laborer", "haul", 4)
	S.hire(g, "laborer", "haul", 4)
	var cands := 0
	for pf in ["caster", "presser"]:
		g.refresh_candidates(pf)
		for c: Dictionary in g.candidates:
			if str(c.get("prof", "")) == pf and int((c["skills"] as Dictionary).get("casting" if pf == "caster" else "stamping", 0)) >= 3:
				cands += 1
	check(cands >= 2, "по объявлению приходят литейщики и штамповщики с навыком (%d)" % cands)
	g.cons["sand"] = 60.0
	g.auto_supply = true
	for i in 6:
		g.put_on_ground(g.new_item("mat", "charge", "raw"), Vector2i(14 + i % 3, 24))
		g.put_on_ground(g.new_item("mat", "strip2", "raw"), Vector2i(14 + i % 3, 25))
	S.complex_orders(g, 10, {"washer": 40, "cast_cover": 3, "clamp": 20})
	var t0 := g.minute
	while g.minute < t0 + 3.0 * 1440.0:
		g.tick(0.5)
	var by := {}
	for m in ms:
		by[m.process()] = int(by.get(m.process(), 0)) + m.parts_made
	check(int(by.get("stamping", 0)) >= 20, "прессы отштамповали: %d" % int(by.get("stamping", 0)))
	check(int(by.get("casting", 0)) >= 2, "печь отлила: %d" % int(by.get("casting", 0)))
	check(float(g.cons["sand"]) < 60.0, "смесь расходуется (осталось %d)" % int(g.cons["sand"]))
	var shipped := 0
	for o: Dictionary in g.orders.list:
		if str(o["product"]) in ["washer", "clamp", "cast_cover"] and str(o["status"]) in ["shipped", "done", "ready", "loading"]:
			shipped += 1
	var arch := 0
	for o2: Dictionary in g.orders.archive if "archive" in g.orders else []:
		if str(o2.get("product", "")) in ["washer", "clamp", "cast_cover"]:
			arch += 1
	check(shipped + arch >= 1, "хотя бы один заказ из новых изделий готов (%d + %d в архиве)" % [shipped, arch])
	check(Stall.list(g).size() <= g.things_of("machine").size(), "«Что стоит» понимает новые станки")
	var again := Sim.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(again.things.size() == g.things.size(), "сохраняется")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
