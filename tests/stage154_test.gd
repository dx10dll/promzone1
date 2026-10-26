extends SceneTree
## Тест версии 1.54: дневная история для графиков (Финансы → Статистика).
## godot --headless --path . --audio-driver Dummy -s res://tests/stage154_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _roundtrip(d: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(d))


func _init() -> void:
	Defs.load_all()
	L.apply("ru")
	var g := Scenario.new_game("garage", "mech", "calm", 1541)
	g.story.enabled = false
	g.tick(0.5)

	print("— новая игра: история пустая")
	check(g.statlog.days.is_empty(), "по умолчанию пусто")

	print("— запись раз в сутки")
	g.stats["made"] = 10
	g.stats["scrap"] = 2
	g.stats["earned"] = 5000.0
	g.stats["spent"] = 1500.0
	g.minute += 1440.0
	g._on_new_day()
	check(g.statlog.days.size() == 1, "одна запись за сутки")
	var e: Dictionary = g.statlog.days[0]
	check(int(e["made"]) == 10 and int(e["scrap"]) == 2, "выпуск и брак за сутки")
	check(absf(float(e["defect"]) - 2.0 / 12.0) < 0.001, "доля брака")
	check(absf(float(e["profit"]) - ((float(g.stats["earned"]) - 0.0) - (float(g.stats["spent"]) - 0.0))) < 0.01, "прибыль = доход − расход (в т.ч. аренда и электричество)")
	g.statlog.record()
	check(g.statlog.days.size() == 1, "повторный вызов в те же сутки не пишет")
	var sp1 := float(g.stats["spent"])
	g.stats["made"] = 25
	g.stats["earned"] = 6000.0
	g.minute += 1440.0
	g._on_new_day()
	var e2: Dictionary = g.statlog.days[1]
	check(int(e2["made"]) == 15 and absf(float(e2["profit"]) - (1000.0 - (float(g.stats["spent"]) - sp1))) < 0.01, "вторые сутки считаются от первых")
	check(int(e2["d"]) == int(e["d"]) + 1, "номера суток подряд")

	print("— значения графика совпадают со stats")
	check(absf(float(g.statlog.series("money", 7)[1]) - float(e2["money"])) < 0.001, "series = записи")
	var tot := 0
	for v in g.statlog.series("made", 0):
		tot += int(v)
	check(tot == int(g.stats["made"]), "сумма выпуска = stats.made (%d)" % tot)
	check(g.statlog.series("kwh", 7).size() == 2, "кВт·ч за каждые сутки")

	print("— буфер ограничен")
	for i in 80:
		g.stats["made"] = int(g.stats["made"]) + 1
		g.minute += 1440.0
		g._on_new_day()
	check(g.statlog.days.size() == StatLog.CAP, "не больше %d записей" % StatLog.CAP)
	check(g.statlog.last(7).size() == 7 and g.statlog.last(30).size() == 30, "срезы 7 и 30")
	check(int(g.statlog.days[-1]["d"]) == g.day() - 1, "последняя запись — вчера")

	print("— сохранение и загрузка")
	var back := Sim.from_dict(_roundtrip(g.to_dict()))
	check(back.statlog.days.size() == g.statlog.days.size(), "история сохранена")
	check(absf(float(back.statlog.days[-1]["money"]) - float(g.statlog.days[-1]["money"])) < 0.01, "значения сохранены")
	back.stats["made"] = int(back.stats["made"]) + 7
	back.minute += 1440.0
	back._on_new_day()
	check(int(back.statlog.days[-1]["made"]) == 7, "после загрузки дельты продолжаются")

	print("— старый сейв без истории")
	var d := _roundtrip(g.to_dict())
	d.erase("statlog")
	var old := Sim.from_dict(d)
	check(old.statlog.days.is_empty(), "история пустая")
	old.minute += 1440.0
	old._on_new_day()
	check(old.statlog.days.size() == 1 and int(old.statlog.days[0]["made"]) == 0, "первые сутки после загрузки: без скачка")

	print("— окно")
	var cv := ChartView.new().setup([{"name": "x", "color": Color.WHITE, "values": g.statlog.series("made", 30), "kind": "bar"}], [], "num")
	check(cv._count() == 30, "график получает 30 точек")
	cv.free()

	print("")
	if fails.is_empty():
		print("СТАДИЯ 1.54: ВСЕ ПРОВЕРКИ ПРОЙДЕНЫ")
	else:
		print("ПРОВАЛЕНО: %d" % fails.size())
		for f in fails:
			print("  - " + f)
	quit(0 if fails.is_empty() else 1)
