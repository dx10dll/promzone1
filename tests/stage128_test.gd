extends SceneTree
## Тест версии 1.28 «Музыка»: шесть новых композиций, выбор по времени суток и авралу, режимы из настроек.
## godot --headless --path . -s res://tests/stage128_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()
	print("— композиции")
	for n: String in MusicDirector.TITLES.keys():
		var ok := ResourceLoader.exists("res://assets/sound/%s.ogg" % n)
		var len_s := 0.0
		if ok:
			var st := load("res://assets/sound/%s.ogg" % n) as AudioStream
			len_s = st.get_length() if st else 0.0
		check(ok and len_s >= 35.0, "%s %s: %d с" % [n, MusicDirector.TITLES[n], int(len_s)])
	for n2: String in MusicDirector.ALL:
		check(MusicDirector.TITLES.has(n2), "у трека %s есть название" % n2)

	print("— выбор по времени суток")
	var g := Scenario.new_garage(128)
	g.story.enabled = false
	g.orders.list.clear()
	var want := {3: "night", 7: "morning", 13: "day", 19: "evening", 23: "night"}
	for h: int in want.keys():
		g.minute = float(g.day() - 1) * 1440.0 + float(h) * 60.0 + 5.0
		check(MusicDirector.mood(g) == want[h], "%d:00 — %s (%s)" % [h, want[h], MusicDirector.mood(g)])
		var pl := MusicDirector.playlist(g, 0)
		check(not pl.is_empty() and ResourceLoader.exists("res://assets/sound/%s.ogg" % pl[0]), "  список: %s" % ", ".join(pl))
	g.minute = float(g.day() - 1) * 1440.0 + 13.0 * 60.0
	g.orders.list.append({"status": "active", "deadline": g.minute + 600.0, "product": "x"})
	check(MusicDirector.mood(g) == "rush", "заказ горит — марш (%s)" % MusicDirector.mood(g))
	check(MusicDirector.playlist(g, 0)[0] == "music_march", "первым идёт «Встречный план»")
	g.orders.list[0]["status"] = "shipping"
	check(MusicDirector.mood(g) == "day", "заказ отгружен — снова «Норма»")
	g.orders.list.clear()

	print("— режимы")
	check(MusicDirector.playlist(g, 1).size() == MusicDirector.ALL.size(), "«всё подряд» — все треки")
	check(MusicDirector.playlist(g, 2) == MusicDirector.CLASSIC, "«только вальсы» — старые два")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
