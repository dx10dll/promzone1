extends SceneTree
## 1.39, перевод D1 «люди в симуляции»: мысли, бригады, обучение, карьера, настроение, город, имена.
## 1) Перевод не трогает симуляцию: одна и та же игра по-русски и по-английски даёт то же состояние.
## 2) По-английски: имена латиницей, звания, разряды, занятия, история, мысли и настроение, ответы
##    бригад/курсов/экзаменов, уведомления и письма — без кириллицы. Названия из данных других срезов
##    (изделия, станки, материалы, помещения) вырезаем перед проверкой — их переводят там.
## godot --headless --path . -s res://tests/stage14d1_test.gd

var fails: Array[String] = []
var _data_names: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(sim: Sim, minutes: float) -> void:
	var end := sim.minute + minutes
	while sim.minute < end:
		sim.tick(0.5)


func _state(sim: Sim) -> String:
	var parts: Array[String] = ["%.2f" % sim.money, str(sim.rng.state), str(sim.workers.size()), str(sim.events.size())]
	for w in sim.workers:
		parts.append("%d:%.3f,%.3f:%.2f:%s" % [w.id, w.pos.x, w.pos.y, w.mood, w.first + w.last])
	return "|".join(parts)


func _collect_names() -> void:
	var seen := {}
	for dict: Dictionary in [Defs.products, Defs.materials, Defs.objects, Defs.rooms, Defs.consumables, Defs.wall_by_id, Defs.build_mats]:
		for k in dict.keys():
			var d: Variant = dict[k]
			if d is Dictionary:
				for f in ["name", "short"]:
					var n := str((d as Dictionary).get(f, ""))
					if n != "" and not seen.has(n):
						seen[n] = true
						_data_names.append(n)
	_data_names.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())


## Текст без названий из чужих данных.
func _strip(s: String) -> String:
	if not L.has_cyr(s):
		return s
	for n in _data_names:
		s = s.replace(n, "X").replace(n.to_lower(), "X")
	return s


func _no_cyr(texts: Array, what: String) -> void:
	var bad: Array[String] = []
	for t in texts:
		var s := _strip(str(t))
		if L.has_cyr(s):
			bad.append("«%s»" % s.replace("\n", " ").left(90))
	check(not texts.is_empty() and bad.is_empty(), "%s: %d строк без кириллицы%s" % [what, texts.size(), "" if bad.is_empty() else ": " + "; ".join(bad.slice(0, 6)) + (" …ещё %d" % (bad.size() - 6) if bad.size() > 6 else "")])


func _new(lang: String) -> Sim:
	L.apply(lang)
	var sim := Scenario.new_game("garage", "mech", "calm", 21)
	sim.money = 900000.0
	sim.sales.enabled = false   # сбыт — чужой срез (D2); здесь сравниваем людей
	return sim


func _init() -> void:
	Defs.load_all()
	_collect_names()

	print("— перевод не меняет симуляцию")
	var ru := _new("ru")
	_run(ru, 1440.0 * 3)
	var st_ru := _state(ru)
	var ev_ru: Array = ru.events.map(func(e: Dictionary) -> String: return str(e["text"]))
	var en := _new("en")
	_run(en, 1440.0 * 3)
	if _state(en) != st_ru:
		print("    ru: ", st_ru.left(300), "\n    en: ", _state(en).left(300))
	check(_state(en) == st_ru, "3 дня по-английски — то же состояние, что по-русски (деньги, ГСЧ, люди, позиции, настроение)")
	check(en.events.size() == ev_ru.size(), "столько же уведомлений: %d" % en.events.size())
	check(L.has_cyr(st_ru) and en.workers[0].first == ru.workers[0].first, "имена хранятся по-русски (%s)" % en.workers[0].first)
	L.apply("ru")
	check(ru.workers[0].full_name() == ru.workers[0].first + " " + ru.workers[0].last, "по-русски имя как было: %s" % ru.workers[0].full_name())
	L.apply("en")

	print("— по-английски: люди")
	var sim := en
	var names: Array = []
	var titles: Array = []
	var acts: Array = []
	var hist: Array = []
	var moods: Array = []
	for w in sim.workers:
		names.append_array([w.full_name(), w.short_name(), w.formal_name(), w.call_name()])
		titles.append_array([w.prof_name(), w.prof_lc(), w.title(), w.title_lc(), w.rank_text(), w.prof_rank(), People.body_name(w)])
		titles.append_array(w.trait_names())
		acts.append(w.activity)
		hist.append_array(w.history)
		for p in Mood.breakdown(sim, w):
			moods.append(str(p[0]))
		var lf := Mood.life(sim, w)
		for g in lf.keys():
			for p2 in lf[g]["parts"]:
				moods.append(str(p2[0]))
		moods.append(Mood.label(w.mood))
		for wl in Mood.life_worst(sim, w):
			moods.append(str(wl))
	print("    ", names.slice(0, 4), " · ", titles.slice(0, 4))
	_no_cyr(names, "имена")
	_no_cyr(titles, "профессии, звания, черты, телосложение")
	_no_cyr(acts, "занятия")
	var th: Array = []
	for id in Defs.thoughts.keys():
		th.append(Mood.thought_text(str(id)))
	_no_cyr(th, "все мысли (thoughts.json)")
	_no_cyr(moods, "настроение и потребности")
	var ranks: Array = []
	var probe := Worker.new()
	probe.first = "Юрий"
	probe.last = "Щукин"
	probe.nick = "Батя"
	for pf in Worker.PROF_NAMES.keys():
		probe.prof = str(pf)
		for s in [0, 4, 6, 8, 10]:
			probe.skills = {probe.main_skill(): s}
			probe.grade_n = 0
			ranks.append_array([probe.title(), probe.rank_text(), probe.prof_rank()])
	_no_cyr(ranks, "все профессии и разряды")
	check(probe.full_name() == "Yuriy Shchukin" and probe.short_name() == "Y. Shchukin", "имя латиницей: %s / %s" % [probe.full_name(), probe.short_name()])

	print("— по-английски: бригады, обучение, карьера, город")
	var ev0 := sim.events.size()
	var h0 := {}
	for w in sim.workers:
		h0[w.id] = w.history.size()
	var ans: Array = []
	var w0: Worker = sim.workers[0]
	var w1: Worker = sim.workers[1] if sim.workers.size() > 1 else w0
	ans.append(sim.crew.auto_form())
	ans.append(sim.crew.sched_text(sim.crew.get_sched("0"), 0))
	ans.append_array(sim.crew.sched_problems("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww") + sim.crew.sched_problems("wwwwlwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww"))
	for k in Crew.CAUSES.keys():
		ans.append(sim.crew.cause_text(str(k)))
	ans.append(sim.crew.sign([]))
	for w in sim.workers:
		ans.append(sim.career.exam_block(w))
		var o := sim.training.offer(w, "milling")
		ans.append(str(o["why"]))
		ans.append(sim.brain.order_block(w))
		for op: Dictionary in sim.brain.order_options(w, w.cell()):
			ans.append_array([str(op["label"]), str(op["why"])])
	ans.append(sim.training.start_course(w0, "milling", "class"))
	ans.append(sim.training.start_course(w0, "milling", "center"))
	ans.append(sim.training.start_tb())
	ans.append(sim.training.set_mentor(w1, w0))
	ans.append(sim.training.ptu_sign())
	ans.append(sim.town.vaccinate())
	ans.append(sim.town.kg_upgrade())
	ans.append(sim.town.dk_buy())
	ans.append(sim.town.rel_text())
	ans.append(sim.town.kg_name())
	for w in sim.workers:
		for p in sim.training.mood_parts(w) + sim.town.mood_parts(w):
			ans.append(str(p[0]))
	var cand := Worker.new()
	cand.from_away = true
	ans.append(sim.town.can_hire(cand))
	sim.career._ask_raise(w0)
	sim.career.exams[w0.id] = sim.day()
	sim.career.finish_exam(w0)
	sim.career._quarter()
	sim.crew.on_injury(w1, "rush")
	sim.crew.found_union()
	sim.town._cat_offer(true)
	sim.brain.give_order(w0, w0.cell())
	var lt: Array = []
	for l: Dictionary in sim.story.letters:
		lt.append_array([str(l["title"]), str(l["text"])])
		for c: Dictionary in l["choices"]:
			lt.append_array([str(c.get("text", "")), str(c.get("hint", ""))])
	lt = lt.filter(func(s: Variant) -> bool: return str(s) != "")
	_no_cyr(lt, "письма D1 (прибавка, индексация, кот, профсоюз, акт Н-1)")
	_run(sim, 1440.0 * 2)
	ans = ans.filter(func(s: Variant) -> bool: return str(s) != "")
	_no_cyr(ans, "ответы и подсказки бригад, курсов, экзаменов, приказов, города")
	var evs: Array = []
	for e: Dictionary in sim.events.slice(0, sim.events.size() - ev0 + 0):
		evs.append(str(e["text"]))
	var mine: Array = evs.filter(func(s: Variant) -> bool: return _mine(str(s)))
	_no_cyr(mine, "уведомления D1 за эти дни (по шаблонам strings_d1.csv)")
	hist.clear()
	acts.clear()
	for w in sim.workers:
		hist.append_array(w.history.slice(0, w.history.size() - int(h0.get(w.id, 0))))
		acts.append(w.activity)
	_no_cyr(hist + acts, "история и занятия после событий")

	L.apply("ru")
	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: %d" % fails.size()))
	quit(0 if fails.is_empty() else 1)


## Уведомление из этого среза: совпадает с английским шаблоном из strings_d1.csv (или осталось
## русским и совпадает с русским ключом — тогда проверка его и поймает).
var _pats: Array[RegEx] = []


func _mine(s: String) -> bool:
	if _pats.is_empty():
		var f := FileAccess.open("res://assets/i18n/strings_d1.csv", FileAccess.READ)
		f.get_csv_line()
		while not f.eof_reached():
			var row := f.get_csv_line()
			if row.size() < 2 or not "%" in row[0] or row[0].length() < 12:
				continue
			for t in [row[0], row[1]]:
				var esc := ""
				for ch in t:
					esc += ("\\" + ch) if ch in ".^$*+?()[]{}|\\" else ch
				esc = esc.replace("%%", "%").replace("%s", ".*").replace("%d", "-?\\d+").replace("%05d", "\\d+")
				esc = RegEx.create_from_string("\\\\\\{[^}]*\\\\\\}").sub(esc, ".*", true)
				var re := RegEx.create_from_string("^" + esc + "$")
				if re.is_valid():
					_pats.append(re)
	for re in _pats:
		if re.search(s) != null:
			return true
	return false
