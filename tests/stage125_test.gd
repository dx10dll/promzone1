extends SceneTree
## Тест версии 1.25 «Живые люди и цех»: то, на что опираются новые анимации и эффекты.
## godot --headless --path . -s res://tests/stage125_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()
	print("— обед, отдых, перекур, без дела")
	var a := MenuScenes.build()
	var target := MenuScenes.next_minute(a.minute, 12.0 * 60.0 + 30.0)
	var guard := 0
	while not MenuScenes.advance_to(a, target, 50) and guard < 400:
		guard += 1
	var eat_sit := 0
	var kinds := {}
	for w in a.workers:
		if w.task:
			kinds[w.task.kind] = int(kinds.get(w.task.kind, 0)) + 1
			if w.task.kind == "eat" and w.anim == "sit":
				eat_sit += 1
	print("  задачи в обед: ", kinds)
	check(eat_sit >= 5, "в обед сидят и едят (ложка в руке): %d" % eat_sit)
	var seen_rest := false
	var seen_wander := false
	var seen_smoke := false
	var t1 := a.minute
	while a.minute < t1 + 600.0:
		a.tick(0.5)
		for w in a.workers:
			if w.task == null:
				continue
			if w.task.kind == "rest" and w.anim == "sit":
				seen_rest = true
			if w.task.kind == "wander" and w.anim == "idle":
				seen_wander = true
			if w.anim == "smoke":
				seen_smoke = true
	check(seen_rest, "отдыхают сидя (кружка чая)")
	check(seen_wander, "бывают без дела стоя (потягиваются)")
	print("  перекур замечен: ", seen_smoke, " (нужна урна — на витрине её может не быть)")

	print("— станки для искр и пара")
	var procs := {}
	for m in a.things_of("machine"):
		procs[m.process()] = true
	for p in ["welding", "assembly", "heat", "turning"]:
		check(procs.has(p), "на витрине есть передел %s" % p)
	var meta: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sprite_meta.json"))
	for k in ["weld_post", "assembly_table"]:
		var an: Dictionary = (meta.get(k, {}) as Dictionary).get("anchors", {})
		check(an.has("work") or an.has("flash"), "у %s есть точка работы для искр" % k)

	print("— звук по категориям")
	var src := FileAccess.get_file_as_string("res://scripts/autoload/snd.gd")
	for b in ["People", "City", "UI"]:
		check(src.contains("\"%s\"" % b), "есть шина %s" % b)
	var gsrc := FileAccess.get_file_as_string("res://scripts/autoload/game.gd")
	for k2 in ["vol_people", "vol_city", "vol_ui", "quality"]:
		check(gsrc.contains("\"%s\"" % k2), "настройка %s" % k2)

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
