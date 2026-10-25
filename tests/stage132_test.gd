extends SceneTree
## Тест версии 1.32 «Создать рабочего» (свои рабочие): файл списка (запись и чтение), проверка ФИО, свой рабочий приходит
## кандидатом ровно таким, каким его собрали (имя, внешность, черты), не бывает в игре дважды,
## переживает сохранение и загрузку, игра с одним зерном идёт одинаково; редактор в меню собирается.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage132_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	CustomWorkers.path = "user://test132_custom_workers.json"
	_persist()
	_names()
	_appears()
	_never_twice()
	_profs()
	_save_load()
	_determinism()
	await _editor()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(CustomWorkers.path))
	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)


func _entry(id: String, prof: String = "") -> Dictionary:
	return {"id": id, "enabled": true, "last": "Громова", "first": "Зинаида", "patr": "Петровна", "female": true, "age": 47,
		"prof": prof, "traits": ["veteran", "cheerful"],
		"look": {"skin": 3, "hair": "braid", "hair_col": "#b5562e", "beard": "", "glasses": true, "body": "stout", "h": 1.06,
			"street": "coat", "street_col": "#6a3a3a", "eye_col": "#5d7a4a",
			"face_ovr": {"head": "round", "eyes": "deep", "brows": "arched", "nose": "hooked", "mouth": "full", "freckles": true, "earrings": true}}}


func _man(id: String, prof: String = "") -> Dictionary:
	return {"id": id, "enabled": true, "last": "Петров-Водкин", "first": "Кузьма", "patr": "Сергеевич", "female": false, "age": 33,
		"prof": prof, "traits": ["workaholic"],
		"look": {"skin": 0, "hair": "mullet", "hair_col": "#c9a45a", "beard": "chevron", "glasses": false, "body": "strong", "h": 0.94,
			"street": "jacket", "street_col": "#2f3a4a", "eye_col": "#3f6a8a", "face_ovr": {"head": "square", "nose": "wide"}}}


func _persist() -> void:
	print("— файл списка")
	var d := {"chance": 0.4, "workers": [_entry("a1", "turner"), _man("b2")]}
	check(CustomWorkers.save_data(d), "записали %s" % CustomWorkers.path)
	var r := CustomWorkers.load_data()
	var ws: Array = r["workers"]
	check(absf(float(r["chance"]) - 0.4) < 0.001, "шанс сохранился: %.2f" % float(r["chance"]))
	check(ws.size() == 2, "записей: %d" % ws.size())
	if ws.size() == 2:
		var a: Dictionary = ws[0]
		check(str(a["last"]) == "Громова" and str(a["first"]) == "Зинаида" and str(a["patr"]) == "Петровна", "ФИО: %s" % CustomWorkers.fio(a))
		check(bool(a["female"]) and int(a["age"]) == 47 and str(a["prof"]) == "turner", "пол, возраст, профессия")
		check(a["traits"] == ["veteran", "cheerful"], "черты: %s" % str(a["traits"]))
		var lk: Dictionary = a["look"]
		check(lk["skin"] is int and int(lk["skin"]) == 3, "кожа — целое число (из JSON приходит дробным)")
		check(str(lk["hair"]) == "braid" and str(lk["hair_col"]) == "#b5562e" and bool(lk["glasses"]), "причёска, цвет волос, очки")
		check(str((lk["face_ovr"] as Dictionary)["nose"]) == "hooked", "черты лица")
		check(str((ws[1] as Dictionary)["last"]) == "Петров-Водкин", "двойная фамилия")
	var big: Array = []
	for i in 70:
		big.append(_man("m%d" % i))
	CustomWorkers.save_data({"chance": 2.0, "workers": big})
	var r2 := CustomWorkers.load_data()
	check((r2["workers"] as Array).size() == CustomWorkers.MAX, "не больше %d записей" % CustomWorkers.MAX)
	check(float(r2["chance"]) <= 1.0, "шанс не больше 100%")
	var f := FileAccess.open(CustomWorkers.path, FileAccess.WRITE)
	f.store_string("{сломано")
	f.close()
	check((CustomWorkers.load_data()["workers"] as Array).is_empty(), "испорченный файл — пустой список, без падения")
	var off := _man("off")
	off["enabled"] = false
	var bad := _man("bad")
	bad["first"] = "John"
	CustomWorkers.save_data({"chance": 0.3, "workers": [_man("on"), off, bad]})
	var go := CustomWorkers.game_opts()
	check((go.get("customs", []) as Array).size() == 1, "в игру едут только включённые и правильные: %d" % (go.get("customs", []) as Array).size())


func _names() -> void:
	print("— проверка ФИО")
	for ok: String in ["Иванов", "Петров-Водкин", "Ёлкин", "Ли", "салтыков-щедрин"]:
		check(CustomWorkers.check_part(ok) == "", "«%s» подходит" % ok)
	for bad: Array in [["Ivanov", "латиница"], ["Ив анов", "пробел"], ["-Иван", "дефис в начале"], ["Иван--ов", "двойной дефис"],
			["И", "одна буква"], ["Иванов1", "цифра"], ["", "пусто"], ["Абвгдеёжзийклмнопрстуфхцчш", "длиннее 24"]]:
		var m := CustomWorkers.check_part(str(bad[0]))
		check(m != "", "«%s» (%s) — нельзя: %s" % [bad[0], bad[1], m])
	check(CustomWorkers.check_part("", false) == "", "отчество можно не писать")
	check(CustomWorkers.nice(" иВАНОВ-петров ") == "Иванов-Петров", "«иВАНОВ-петров» → «%s»" % CustomWorkers.nice(" иВАНОВ-петров "))
	var e := {"female": true, "last": "Петров", "patr": "Ильич", "look": {"hair": "short"}}
	CustomWorkers.regender(e)
	check(str(e["last"]) == "Петрова" and str(e["patr"]) == "Ильинична", "стала женщиной: %s %s" % [e["last"], e["patr"]])
	check(People.HAIR_F.has(str((e["look"] as Dictionary)["hair"])), "  и причёска женская")
	e["female"] = false
	CustomWorkers.regender(e)
	check(str(e["last"]) == "Петров" and str(e["patr"]) == "Ильич", "обратно: %s %s" % [e["last"], e["patr"]])
	var e2 := {"female": false, "last": "Ковальский", "patr": "Сергеевич"}
	e2["female"] = true
	CustomWorkers.regender(e2)
	check(str(e2["last"]) == "Ковальская" and str(e2["patr"]) == "Сергеевна", "%s %s" % [e2["last"], e2["patr"]])
	var r := RandomNumberGenerator.new()
	r.seed = 5
	for i in 30:
		var ne := CustomWorkers.new_entry(r)
		if not CustomWorkers.validate(ne).is_empty():
			check(false, "случайное ФИО не прошло проверку: %s" % CustomWorkers.fio(ne))
			return
	check(true, "30 случайных ФИО проходят проверку")


func _cands(s: Sim, cid: String) -> Array:
	return s.candidates.filter(func(c: Dictionary) -> bool: return str(c.get("cust", "")) == cid)


func _copies(s: Sim, cid: String) -> int:
	return _cands(s, cid).size() + s.workers.filter(func(w: Worker) -> bool: return w.custom_id == cid).size()


func _appears() -> void:
	print("— свой рабочий приходит кандидатом")
	var e := _entry("zina")
	var s := Scenario.new_game("garage", "mech", "market", 777, {"customs": [e], "custom_chance": 1.0})
	check(s.customs.size() == 1 and absf(s.custom_chance - 1.0) < 0.001, "список и шанс в симуляции")
	var cs := _cands(s, "zina")
	check(cs.size() == 1, "при 100%% пришла сразу, в начале игры (%d)" % cs.size())
	if cs.is_empty():
		return
	var w := Worker.from_dict(cs[0])
	check(w.first == "Зинаида" and w.last == "Громова" and w.patronymic == "Петровна", "ФИО ровно как в редакторе: %s %s %s" % [w.last, w.first, w.patronymic])
	check(w.female and w.age == 47, "пол и возраст")
	check(w.traits == ["veteran", "cheerful"], "черты ровно те: %s" % str(w.traits))
	var lk := w.look
	check(int(lk["skin"]) == 3 and str(lk["hair"]) == "braid" and str(lk["hair_col"]) == "#b5562e", "кожа, причёска, цвет волос")
	check(bool(lk["glasses"]) and str(lk["body"]) == "stout" and absf(float(lk["h"]) - 1.06) < 0.001, "очки, телосложение, рост")
	check(str(lk["street"]) == "coat" and str(lk["street_col"]) == "#6a3a3a", "своя одежда")
	check(People.eye_color(lk) == Color("#5d7a4a"), "цвет глаз")
	var fc := People.face(lk, w.age)
	check(str(fc["head"]) == "round" and str(fc["eyes"]) == "deep" and str(fc["brows"]) == "arched" and str(fc["nose"]) == "hooked" and str(fc["mouth"]) == "full", "черты лица: %s" % str(fc))
	check(bool(fc["freckles"]) and not bool(fc["earrings"]), "веснушки есть, серёг нет (1.40: серьги убраны)")
	check(bool(lk["fem"]) and str(lk.get("beard", "")) == "", "женщина без бороды")
	check(w.skills.size() > 3 and w.wage > 0 and Worker.PROF_NAMES.has(w.prof), "навыки и ставка — как у обычного кандидата (%s, %s)" % [w.prof_name(), Defs.money_str(w.wage)])
	check(s.events.any(func(ev: Variant) -> bool: return str(ev).contains("Зинаида Громова")), "в журнале — что пришла наниматься")
	# без своих — ничего лишнего
	var s0 := Scenario.new_game("garage", "mech", "market", 777, {})
	var s1 := Scenario.new_game("garage", "mech", "market", 777, {"customs": [], "custom_chance": 1.0})
	check(s0.rng.state == s1.rng.state and JSON.stringify(s0.candidates) == JSON.stringify(s1.candidates), "пустой список не трогает кубик игры")
	var off := _entry("off")
	off["enabled"] = false
	var s2 := Scenario.new_game("garage", "mech", "market", 777, {"customs": [off], "custom_chance": 1.0})
	check(s2.customs.is_empty() and _cands(s2, "off").is_empty(), "выключенный не едет в игру")
	var s3 := Scenario.new_game("garage", "mech", "market", 777, {"customs": [_entry("z0")], "custom_chance": 0.0})
	for i in 20:
		s3.refresh_candidates()
	check(_cands(s3, "z0").is_empty(), "шанс 0 — не приходит")
	var s4 := Scenario.new_game("garage", "mech", "market", 31, {"customs": [_entry("half")], "custom_chance": 0.25})
	var seen := 0
	for i2 in 200:
		s4.refresh_candidates()
		seen += _cands(s4, "half").size()
	check(seen > 20 and seen < 90, "шанс 25%%: пришла в %d обновлениях из 200" % seen)
	for x in [s, s0, s1, s2, s3, s4]:
		(x as Sim).dispose()


func _never_twice() -> void:
	print("— не бывает дважды")
	var s := Scenario.new_game("garage", "mech", "market", 4242, {"customs": [_entry("z"), _man("k")], "custom_chance": 1.0})
	var worst := 0
	var per := 0
	for i in 40:
		s.refresh_candidates()
		worst = maxi(worst, maxi(_copies(s, "z"), _copies(s, "k")))
		per = maxi(per, s.candidates.filter(func(c: Dictionary) -> bool: return str(c.get("cust", "")) != "").size())
	check(worst == 1, "40 обновлений: в игре не больше одной копии каждого (%d)" % worst)
	check(per == 1, "за одно обновление — не больше одного своего (%d)" % per)
	# нанимаем — больше не приходит, пока работает
	s.refresh_candidates()
	var idx := -1
	for j in s.candidates.size():
		if str(s.candidates[j].get("cust", "")) != "":
			idx = j
	var cid := str(s.candidates[idx].get("cust", "")) if idx >= 0 else ""
	var err := s.hire(idx) if idx >= 0 else "нет кандидата"
	check(err == "", "наняли своего (%s) %s" % [cid, err])
	var hired: Worker = null
	for w in s.workers:
		if w.custom_id == cid:
			hired = w
	check(hired != null and hired.custom_id == cid, "в штате, отмечен как свой")
	var again := 0
	var other := 0
	for i2 in 30:
		s.refresh_candidates()
		again += _cands(s, cid).size()
		other += _cands(s, "k" if cid == "z" else "z").size()
	check(again == 0, "пока работает — кандидатом не приходит (%d)" % again)
	check(other > 0, "второй свой при этом приходит (%d)" % other)
	if hired:
		s.fire(hired, false, true)
	var back := 0
	for i3 in 10:
		s.refresh_candidates()
		back += _cands(s, cid).size()
	check(back > 0, "уволили — может прийти снова (%d из 10)" % back)
	s.dispose()


func _profs() -> void:
	print("— профессия")
	var s := Scenario.new_game("garage", "mech", "market", 99, {"customs": [_man("w", "welder")], "custom_chance": 1.0})
	var c := _cands(s, "w")
	check(c.size() == 1 and str(c[0]["prof"]) == "welder", "выбранная профессия — сварщик")
	s.refresh_candidates("cook")
	check(_cands(s, "w").is_empty(), "объявление «повар» — сварщик не приходит")
	var s2 := Scenario.new_game("garage", "mech", "market", 99, {"customs": [_man("any")], "custom_chance": 1.0})
	s2.refresh_candidates("cook")
	var c2 := _cands(s2, "any")
	check(c2.size() == 1 and str(c2[0]["prof"]) == "cook", "«любая» профессия по объявлению «повар» — повар")
	s.dispose()
	s2.dispose()


func _save_load() -> void:
	print("— сохранение и загрузка")
	var s := Scenario.new_game("garage", "mech", "market", 1234, {"customs": [_entry("z"), _man("k")], "custom_chance": 0.5})
	for i in 6:
		s.refresh_candidates()
	var txt := JSON.stringify(s.to_dict())
	var l := Sim.from_dict(JSON.parse_string(txt))
	check(l.customs.size() == 2 and absf(l.custom_chance - 0.5) < 0.001, "список и шанс в сохранении")
	check(JSON.stringify(l.candidates) == JSON.stringify(JSON.parse_string(JSON.stringify(s.candidates))), "кандидаты те же (со звёздочкой)")
	var idx := -1
	for j in l.candidates.size():
		if str(l.candidates[j].get("cust", "")) != "":
			idx = j
	if idx < 0:
		for k in 10:
			s.refresh_candidates()
			l.refresh_candidates()
		for j2 in l.candidates.size():
			if str(l.candidates[j2].get("cust", "")) != "":
				idx = j2
	check(idx >= 0, "свой среди кандидатов загруженной игры")
	if idx >= 0:
		var cid := str(l.candidates[idx]["cust"])
		l.hire(idx)
		var l2 := Sim.from_dict(JSON.parse_string(JSON.stringify(l.to_dict())))
		var w2: Array = l2.workers.filter(func(w: Worker) -> bool: return w.custom_id == cid)
		check(w2.size() == 1 and (w2[0] as Worker).patronymic != "", "нанятый свой после загрузки — свой, с отчеством")
		for i2 in 10:
			l2.refresh_candidates()
		check(_copies(l2, cid) == 1, "после загрузки второй раз не приходит")
		l2.dispose()
	# дальше обе игры идут одинаково
	var s2 := Sim.from_dict(JSON.parse_string(txt))
	var same := true
	for i3 in 8:
		s2.refresh_candidates()
		var l3 := Sim.from_dict(JSON.parse_string(txt))
		for k2 in i3 + 1:
			l3.refresh_candidates()
		same = same and JSON.stringify(l3.candidates) == JSON.stringify(s2.candidates)
		l3.dispose()
	check(same, "загрузка детерминирована: те же кандидаты")
	s.dispose()
	l.dispose()
	s2.dispose()


func _run(seed_v: int) -> String:
	var s := Scenario.new_game("garage", "mech", "market", seed_v, {"customs": [_entry("z"), _man("k"), _man("w", "welder")], "custom_chance": 0.35})
	var trace := PackedStringArray()
	for i in 12:
		s.refresh_candidates()
		for t in 30:
			s.tick(0.5)
		trace.append(JSON.stringify(s.candidates))
	trace.append(str(s.rng.state))
	s.dispose()
	return "|".join(trace)


func _determinism() -> void:
	print("— одно зерно — одна игра")
	var a := _run(555)
	var b := _run(555)
	check(a == b, "дважды с зерном 555 — то же самое")
	check(a.contains("\"cust\":\"z\"") or a.contains("\"cust\":\"k\"") or a.contains("\"cust\":\"w\""), "за 12 обновлений свои приходили")
	check(_run(556) != a, "другое зерно — другая игра")


func _editor() -> void:
	print("— редактор в меню")
	UITheme.build()
	CustomWorkers.save_data({"chance": 0.25, "workers": []})
	var ed := CustomWorkersUI.new(null)
	root.add_child(ed)
	await process_frame
	check(ed.sel == -1 and not ed.cur.is_empty(), "пустой список — сразу черновик нового")
	check(ed.find_children("*", "Label", true, false).any(func(l: Node) -> bool: return (l as Label).text == "Создать рабочего"), "заголовок «Создать рабочего»")
	check(not ed.save_btn.disabled and ed.save_btn.text == "Добавить в список", "кнопка «%s»" % ed.save_btn.text)
	ed.cur["last"] = "Smith"
	ed._changed(false)
	check(ed.save_btn.disabled, "латиница — добавить нельзя")
	ed.cur["last"] = "сидоров"
	ed.cur["traits"] = ["lazy", "workaholic", "smoker"]
	ed._changed(true)
	ed._save()
	var d := CustomWorkers.load_data()
	var ws: Array = d["workers"]
	check(ws.size() == 1 and str((ws[0] as Dictionary)["last"]) == "Сидоров", "добавлен в файл, фамилия с большой буквы")
	check(ws.size() == 1 and ((ws[0] as Dictionary)["traits"] as Array).size() <= 2 and not (((ws[0] as Dictionary)["traits"] as Array).has("lazy") and ((ws[0] as Dictionary)["traits"] as Array).has("workaholic")), "черты: не больше двух и без несовместимых")
	ed._new_draft()
	ed._save()
	check((CustomWorkers.load_data()["workers"] as Array).size() == 2, "второй добавлен")
	ed._delete()
	check((CustomWorkers.load_data()["workers"] as Array).size() == 1, "удалён")
	ed.queue_free()
	await process_frame
