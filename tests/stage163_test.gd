extends SceneTree
## Тест 1.63 «Разгрузка: изделия и ISO»: изделия открываются по этапам, станкам и репутации (5–8 в начале),
## закрытые заявками не приходят, старые сейвы сохраняют то, что уже делали; ISO 9001 — один чек-лист из 6 условий.
## Окна (рынок с закрытыми изделиями, карточка ISO) проверяются в stage163_ui.tscn — этот файл запускает её отдельно.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage163_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _game(seed_v: int, profile: String = "mech") -> Sim:
	var g := Scenario.new_game("garage", profile, "calm", seed_v)
	g.story.enabled = false
	g.progress.tutorial = -1
	return g


func _initialize() -> void:
	print("— старт: 5–8 изделий, все выполнимы")
	var g := _game(1630)
	var op := g.progress.open_products()
	check(op.size() >= 5 and op.size() <= 8, "открыто изделий: %d %s" % [op.size(), str(op)])
	var all_make := true
	for p in op:
		if not g.prod.can_make(str(p)):
			all_make = false
	check(all_make, "все открытые делаются на стартовом станке")
	check(not g.progress.product_open("drive_unit") and not g.progress.product_open("gearbox") and not g.progress.product_open("shaft"), "сложные изделия закрыты")
	check(Defs.products.size() >= 30 and g.progress.PRODUCT_GATES.size() >= 28, "ворота заданы для всех изделий (%d)" % g.progress.PRODUCT_GATES.size())
	for pr in ["agri", "steel", "pumps", "rail", "tools", "secret"]:
		var gp := _game(1631, pr)
		var n := gp.progress.open_products().size()
		check(n >= 3 and n <= 8 and n < gp.progress.products().size(), "профиль %s: открыто %d из %d" % [pr, n, gp.progress.products().size()])
		gp.dispose()

	print("— закрытые не приходят заказами")
	var bad := 0
	for i in 300:
		var o := g.orders.make_offer()
		if not g.progress.product_open(str(o["product"])):
			bad += 1
	check(bad == 0, "300 заявок без закрытых изделий (нарушений %d)" % bad)
	var vd := g.sales.verdict({"product": "gearbox", "qty": 5, "price": 100000, "deadline": 1e9})
	check(str(vd[0]) != "", "сбыт не берёт закрытое изделие: %s" % str(vd[0]))

	print("— подсказка «откроется»")
	var lt := g.progress.lock_text("bracket")
	check(lt.begins_with("откроется: ") and lt.contains("станк") and lt.contains("этап «"), "кронштейн: %s" % lt)
	check(g.progress.lock_text("pin") == "", "открытое — без подсказки")
	check(g.progress.lock_text("shaft").contains("этап"), "вал: %s" % g.progress.lock_text("shaft"))

	print("— ворота: этап и репутация")
	g.progress.stage = 2
	g.reputation = 40.0
	var f0 := g.progress.refresh_products()
	check(f0.is_empty() and not g.progress.product_open("shaft"), "этап 2, репутация 40: вал закрыт (нужна 50)")
	check(g.progress.lock_text("shaft").contains("репутация 50") and not g.progress.lock_text("shaft").contains("этап"), "в подсказке только репутация: %s" % g.progress.lock_text("shaft"))
	g.reputation = 51.0
	var f1 := g.progress.refresh_products()
	check(f1.has("shaft") and g.progress.product_open("shaft"), "репутация 51: вал открылся (%s)" % str(f1))
	check(g.events.any(func(e: Dictionary) -> bool: return str(e["text"]).begins_with("Новое изделие в ассортименте") and str(e["text"]).contains("Вал")), "уведомление «Новое изделие в ассортименте: Вал»")
	g.reputation = 10.0
	g.progress.refresh_products()
	check(g.progress.product_open("shaft"), "раз открытое не закрывается при падении репутации")
	check(not g.progress.product_open("housing"), "корпус (этап 3) ещё закрыт")
	g.progress.stage = 3
	g.reputation = 56.0
	g.progress.refresh_products()
	check(g.progress.product_open("housing"), "этап 3 и репутация 56: корпус открыт")
	check(not g.progress.product_open("gearbox"), "редуктор всё ещё закрыт")

	print("— станок: открыто, но без станка заявок нет")
	var offers_housing := 0
	for i in 400:
		if str(g.orders.make_offer()["product"]) == "housing":
			offers_housing += 1
	check(offers_housing == 0, "корпус открыт, но фрезы нет — заявок нет (%d)" % offers_housing)
	S.big_shop(g, false)
	check(g.prod.can_make("housing"), "после станков корпус выполним")
	var got := 0
	for i in 600:
		if str(g.orders.make_offer()["product"]) == "housing":
			got += 1
	check(got > 0, "со станками заявки на корпус приходят (%d)" % got)

	print("— песочница: всё открыто")
	var sb := Scenario.new_game("sandbox", "mech", "calm", 1632)
	check(sb.progress.all_open and sb.progress.product_open("item7t"), "песочница открывает всё")
	sb.dispose()

	print("— старый сейв: сделанное и заказанное остаётся открытым")
	var og := _game(1633)
	var ord := og.orders.make_offer("drive_unit")
	ord["status"] = "active"
	og.orders.list.append(ord)
	var ord2 := og.orders.make_offer("gearbox")
	ord2["status"] = "done"
	og.orders.list.append(ord2)
	var od := JSON.parse_string(JSON.stringify(og.to_dict())) as Dictionary
	(od["progress"] as Dictionary).erase("pset")
	var ol := Sim.from_dict(od)
	check(ol.progress.product_open("drive_unit") and ol.progress.product_open("gearbox"), "заказанные узел и редуктор открыты")
	check(not ol.progress.product_open("pump") and ol.progress.product_open("pin"), "остальное — по воротам")
	var rt := Sim.from_dict(JSON.parse_string(JSON.stringify(g.to_dict())))
	check(rt.progress.product_open("shaft") and rt.progress.product_open("housing") and rt.progress.pset_init, "новый сейв хранит открытые изделия")
	ol.dispose()
	rt.dispose()
	og.dispose()

	print("— ISO 9001: чек-лист из 6 условий")
	var m := _game(1634)
	var cl := m.market.iso_checklist()
	check(cl.size() == 6, "условий: %d" % cl.size())
	var full := true
	for r: Dictionary in cl:
		if str(r.get("cur", "")) == "" or str(r.get("need", "")) == "" or str(r.get("fix", "")) == "" or not r.has("go") or not r.has("ok"):
			full = false
	check(full, "у каждого есть значение, требование, что делать и куда вести")
	var r0 := m.market.iso_ready()
	check(m.market.iso_reqs().size() == 6 and r0 < 6, "готово в начале: %d из 6" % r0)
	check(not bool(cl[4]["ok"]) and (cl[4]["go"] as Dictionary).get("win", "") == "people:safety", "инструктаж не проведён, «Показать» ведёт в «Охрана труда»")
	var all_fix := true
	for r2: Dictionary in cl:
		if not bool(r2["ok"]) and str(r2["fix"]) == "":
			all_fix = false
	check(all_fix, "у каждого невыполненного есть «что сделать»")
	m.training.tb_day = m.day()
	check(bool(m.market.iso_checklist()[4]["ok"]) and m.market.iso_ready() == r0 + 1, "инструктаж проведён — пункт стал ✓ (%s)" % str(m.market.iso_checklist()[4]["cur"]))
	m.progress.rating["quality"] = 0.5
	var r1 := m.market.iso_ready()
	check(not bool(m.market.iso_checklist()[1]["ok"]), "качество 50%% — пункт ✗ (%s против %s)" % [str(m.market.iso_checklist()[1]["cur"]), str(m.market.iso_checklist()[1]["need"])])
	m.progress.rating["quality"] = 0.8
	check(bool(m.market.iso_checklist()[1]["ok"]) and m.market.iso_ready() == r1 + 1, "качество 80% — пункт стал ✓")
	m.market.last_reclam = m.day()
	check(not bool(m.market.iso_checklist()[5]["ok"]) and m.market.iso_checklist()[5]["cur"] == "дней без рекламаций: 0", "свежая рекламация — пункт ✗")
	m.market.last_reclam = m.day() - 20
	check(bool(m.market.iso_checklist()[5]["ok"]), "14 дней без рекламаций — пункт ✓")
	m.dispose()

	print("— окна")
	var out: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"),
		"--audio-driver", "Dummy", "res://tests/stage163_ui.tscn"], out, true)
	var text := "\n".join(PackedStringArray(out))
	for ln in text.split("\n"):
		if ln.contains("✓") or ln.contains("✗") or ln.contains("—") or ln.contains("ERROR"):
			print(ln)
	check(code == 0 and text.contains("ВСЁ ВЕРНО"), "окна «Рынок» (закрытые изделия) и «ISO 9001» (код %d)" % code)
	g.dispose()
	print("РЕЗУЛЬТАТ: " + ("ВСЁ ВЕРНО" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)
