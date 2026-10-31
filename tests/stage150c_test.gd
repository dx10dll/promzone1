extends SceneTree
## Тест 1.50c: значки проблем над не-станками (батарея, туалет, светильник, шкаф-аккумулятор, зонт, склад).
## godot --headless --path . -s res://tests/stage150c_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _k(g: Sim, t: Thing) -> String:
	return str(ObjectBadges.reason(g, t).get("k", ""))


## Свежий трекер: причина должна продержаться, потом значок виден.
func _shown(g: Sim, tr: ObjectBadges) -> void:
	tr.refresh(g)
	g.minute += ObjectBadges.HOLD_MIN + 1.0
	tr.refresh(g)


func _init() -> void:
	Defs.load_all()
	var g := Scenario.new_garage(150)
	g.story.enabled = false
	g.progress.tutorial = -1
	g.bmats.enabled = false
	g.money = 3000000.0
	S.big_shop(g)
	for i in 4:
		g.tick(0.5)
	var w := g.world

	print("— порядок есть: у исправных объектов значков нет")
	var toilet: Thing = g.things_of("toilet")[0]
	var lamp: Thing = null
	for t: Thing in g.things_of("light"):
		lamp = t
		break
	check(lamp != null, "в цеху есть светильник")
	check(_k(g, toilet) == "", "туалет с водой — без значка")
	check(_k(g, lamp) == "", "светильник на кабеле — без значка")
	var machines := g.things_of("machine")
	var mk0: Array = machines.map(func(m: Thing) -> String: return str(Stall.reason(g, m).get("k", "?")))

	print("— туалет без воды")
	var tin := toilet.inlet_cell()
	var pi := w.idx(tin)
	var pipe_was: int = w.pipe[pi]
	w.pipe[pi] = 0
	w.pipe_rev += 1
	g.tick(0.1)
	check(_k(g, toilet) == "water", "труба оборвана — значок «вода»")
	var tr := ObjectBadges.new()
	tr.refresh(g)
	check(not tr.shown.has(toilet.id), "свежая причина сразу не показывается (не мигает)")
	g.minute += ObjectBadges.HOLD_MIN + 1.0
	tr.refresh(g)
	check(tr.shown.has(toilet.id) and str(tr.shown[toilet.id]["k"]) == "water", "после выдержки значок «вода» виден")
	check(str(tr.shown[toilet.id]["hint"]) != "" and ObjectBadges.title("water") != "", "есть подсказка «что делать»")
	w.pipe[pi] = pipe_was
	w.pipe_rev += 1
	g.tick(0.1)
	check(_k(g, toilet) == "", "труба на месте — причина ушла")
	check(tr.refresh(g) and not tr.shown.has(toilet.id), "значок снят сразу после подключения")

	print("— светильник без питания")
	var cab := w.cable.duplicate()
	var li := w.idx(lamp.cell)
	w.cable.fill(0)
	w.cable_rev += 1
	g.tick(0.1)
	check(_k(g, lamp) == "power", "кабеля нет — значок «питание»")
	var tr2 := ObjectBadges.new()
	_shown(g, tr2)
	check(tr2.shown.has(lamp.id), "значок светильника виден после выдержки")
	check(tr2.shown.keys().all(func(id: int) -> bool: return g.things[id].kind() != "machine"), "станков в этом слое нет")
	w.cable = cab
	w.cable_rev += 1
	g.tick(0.1)
	check(_k(g, lamp) == "", "кабель вернули — причина ушла")
	check(tr2.refresh(g) and not tr2.shown.has(lamp.id), "значок снят")
	check(li >= 0, "индекс клетки")

	print("— батарея (радиатор) без отопления")
	var rad := g.place_thing("radiator", Vector2i(31, 17), true, false)
	check(rad != null, "батарея поставлена")
	g.season.temp_day = -5.0
	for ht: Thing in g.things_of("heater"):   # в гараже уже стоит электрокотёл — убираем, чтобы батарея осталась без тепла
		g.things.erase(ht.id)
	g.thing_rev += 1
	check(g.season.heating_season(), "отопительный сезон включён")
	var rr := ObjectBadges.reason(g, rad)
	check(str(rr.get("k", "")) == "heat", "нет котла — значок «тепло»: %s" % str(rr.get("why", "")))
	var tr3 := ObjectBadges.new()
	_shown(g, tr3)
	check(tr3.shown.has(rad.id), "значок батареи виден")
	g.eng.boiler_rads[rad.id] = 1
	check(_k(g, rad) == "", "батарея подключена к котлу — причина ушла")
	check(tr3.refresh(g) and not tr3.shown.has(rad.id), "значок снят")
	g.eng.boiler_rads.erase(rad.id)
	g.season.temp_day = 20.0
	check(_k(g, rad) == "", "летом батарею не ругаем")

	print("— аккумуляторный шкаф и зонт")
	var ktp: Thing = g.things.values().filter(func(t: Thing) -> bool: return t.def_id == "ktp")[0]
	var bat := g.place_thing("battery", Vector2i(31, 16), true, false)
	check(bat != null and _k(g, bat) == "power", "шкаф не у подстанции — значок «питание»")
	var hood := g.place_thing("vent_hood", Vector2i(33, 17), true, false)
	g.tick(0.1)
	check(hood != null and _k(g, hood) == "vent", "зонт без короба — значок «вытяжка»")
	check(_k(g, ktp) in ["", "room"], "подстанция не падает в чужие причины")

	print("— склад полон")
	var rack: Thing = g.things.values().filter(func(t: Thing) -> bool: return t.def_id == "rack")[0]
	var before := _k(g, rack)
	for s in rack.slot_count():
		for i in rack.slot_cap(s):
			g.put_in_thing(g.new_item("part", "bracket", "ok"), rack, s)
	check(before != "full" and _k(g, rack) != "full", "забитый стеллаж при свободном другом складе — без «полно» (1.58, см. stage158b)")
	for s in rack.slot_count():
		for id in g.slot_ids(rack, s).duplicate():
			g.delete_item(g.items[id])
	check(_k(g, rack) == "", "стеллаж освободили — значок ушёл")

	print("— призраки и станки")
	var ghost := g.place_thing("toilet", Vector2i(31, 15), false, false)
	check(ghost != null and not ghost.built, "недостроенный туалет поставлен")
	var tr4 := ObjectBadges.new()
	w.pipe.fill(0)
	w.pipe_rev += 1
	g.tick(0.1)
	_shown(g, tr4)
	check(not tr4.shown.has(ghost.id), "недостроенный объект без значка")
	check(machines.all(func(m: Thing) -> bool: return not tr4.shown.has(m.id)), "станки слоем объектов не затронуты")
	var mk1: Array = machines.map(func(m: Thing) -> String: return str(Stall.reason(g, m).get("k", "?")))
	check(mk0.size() == mk1.size(), "причины станков считаются как раньше")
	# производительность: сотни объектов
	for i in 300:
		g.place_thing("lamp_bulb", Vector2i(30 + i % 15, 4 + i / 15 % 12), true, false)
	var t0 := Time.get_ticks_usec()
	var tr5 := ObjectBadges.new()
	tr5.refresh(g)
	var dt := (Time.get_ticks_usec() - t0) / 1000.0
	check(dt < 60.0, "пересчёт ~%d объектов за %.1f мс" % [g.things.size(), dt])
	var n5 := tr5._real
	tr5._real = 0.0
	tr5.tick(g, 0.016)
	check(tr5._real > 0.4, "пересчёт не чаще раза в полсекунды")

	print("ИТОГ: " + ("провалено %d" % fails.size() if not fails.is_empty() else "всё хорошо"))
	quit(1 if not fails.is_empty() else 0)
