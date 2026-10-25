extends SceneTree
## 1.39, перевод, срез C: события, письма, проверки, газета, прозвища, кот, пожарные, достижения.
## 1) Детерминизм: одна и та же партия (сид) по-русски и по-английски идёт одинаково — те же деньги,
##    счётчики и число событий (перевод не трогает случайные числа).
## 2) По-английски вызываем все события рассказчика, праздники, забастовку, месячный план, бартер,
##    травмы и пожар, кризисные письма, причины увольнения, все проверки (каждое нарушение и совет,
##    акты, визиты губернатора и журналиста), выпуск газеты, все прозвища, драку, кота и пожарных —
##    и проверяем, что в получившихся текстах нет кириллицы. Имена людей, названия изделий, металла,
##    помещений, расходников и клиентов приходят из чужих срезов — их вырезаем и считаем отдельно.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage14c_test.gd

var fails: Array[String] = []
var sim: Sim
var foreign: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _run(seed_v: int, days: int) -> Sim:
	var s := Scenario.new_garage(seed_v)
	s.auto_supply = true
	while s.day() <= days:
		s.tick(0.5)
	return s


## Чужие для этого среза фрагменты (имена, изделия, помещения…) — их переводят другие срезы.
func _foreign_bits() -> Array[String]:
	var out: Array[String] = []
	for w in sim.workers + sim.visitors:
		for s: String in [w.full_name(), w.formal_name(), w.short_name(), w.first, w.last, w.prof_name(), w.prof_lc(), w.title_lc(), L.name(w.first), L.name(w.last)]:
			out.append(s)
	for p in Defs.products.keys():
		out.append(Defs.product_name(str(p)))
	for m in Defs.materials.keys():
		out.append(Defs.material_name(str(m)))
	for r in sim.rooms.list:
		out.append(r.title())
	for c in Defs.consumables.keys():
		var cd: Dictionary = Defs.consumables[c]
		for k in ["name", "short", "pack"]:
			out.append(str(cd.get(k, "")))
	for o: Dictionary in sim.orders.list:
		out.append(str(o.get("client", "")))
		out.append(sim.orders.short(o))
	for t: Thing in sim.things.values():
		out.append(t.title())
	for k in Defs.objects.keys():
		out.append(str(Defs.objects[k].get("name", "")))
	out.append(Company.title(sim))
	out.append(sim.season.season_name())
	for d in range(1, 400):
		out.append(sim.season.date_str(d))
	out.sort_custom(func(a: String, b: String) -> bool: return a.length() > b.length())
	return out.filter(func(s: String) -> bool: return s.length() >= 2 and L.has_cyr(s))


func _texts() -> Array[String]:
	var out: Array[String] = []
	for a: Dictionary in sim.story.archive:
		out.append(str(a["title"]))
		out.append(str(a["text"]))
	for l: Dictionary in sim.story.letters:
		out.append(str(l["title"]))
		out.append(str(l["text"]))
		for c: Dictionary in l["choices"]:
			out.append(str(c.get("text", "")))
			out.append(str(c.get("hint", "")))
	for e: Dictionary in sim.events:
		out.append(str(e["text"]))
	for m: Dictionary in sim.story.mods:
		out.append(str(m["text"]))
	for iss: Dictionary in sim.paper.issues:
		for it: Dictionary in iss["items"]:
			out.append(str(it.get("rubric", "")))
			out.append(str(it.get("title", "")))
			out.append(str(it.get("text", "")))
	for p: Dictionary in sim.paper.pending:
		out.append(str(p["rubric"]) + " " + str(p["title"]) + " " + str(p["text"]))
	for w in sim.workers:
		out.append(w.nick)
		out.append(w.nick_why)
		if w.task:
			out.append(w.task.label)
	for v in sim.visitors:
		out.append(v.activity)
	for m: Dictionary in sim.inspect.marks:
		out.append(str(m["text"]))
	for q: Dictionary in sim.inspect.queue:
		out.append(str(q.get("why", "")))
	return out


var _keys: Array[String] = []
var _seen: Array[String] = []


## Журнал и ленты обрезаются (80/120 записей) — собираем тексты по ходу теста.
func _snap() -> void:
	for t in _texts():
		if not _seen.has(t):
			_seen.append(t)


## Остаток по-русски — из этого среза (кусок русского ключа strings_c.csv)? Иначе — из чужого среза
## (уведомления сбыта, людей, заказов…), их переводят там.
func _mine(s: String) -> bool:
	if _keys.is_empty():
		var f := FileAccess.open("res://assets/i18n/strings_c.csv", FileAccess.READ)
		while f and not f.eof_reached():
			var row := f.get_csv_line()
			if row.size() >= 1 and L.has_cyr(row[0]):
				_keys.append(row[0])
	var re := RegEx.create_from_string("[А-Яа-яЁё][А-Яа-яЁё ,.:—-]{15,}")
	for m in re.search_all(s):
		var run := m.get_string().strip_edges()
		for k in _keys:
			if k.contains(run):
				return true
	return false


## Сколько строк с кириллицей после вырезания чужих фрагментов.
func _no_cyr(what: String, extra: Array[String] = []) -> void:
	var bits := _foreign_bits()
	var bad: Array[String] = []
	var n := 0
	_snap()
	for t: String in _seen + extra:
		if t == "":
			continue
		n += 1
		var s := t
		for b: String in bits:
			if s.contains(b):
				if not foreign.has(b):
					foreign.append(b)
				s = s.replace(b, "")
		if L.has_cyr(s):
			if _mine(s):
				bad.append("«%s»" % t.replace("\n", " ").left(90))
			elif not foreign.has(t.left(60)):
				foreign.append(t.left(60))
	check(n > 0 and bad.is_empty(), "%s: %d строк, без кириллицы%s" % [what, n, "" if bad.is_empty() else " — " + str(bad.size()) + ": " + "; ".join(bad.slice(0, 10))])


func _init() -> void:
	# 1) детерминизм русский/английский
	L.apply("ru")
	var a := _run(777, 6)
	var ra := [a.money, a.stats.duplicate(), a.events.size(), a.story.archive.size(), a.paper.issues.size(), a.workers.size()]
	L.apply("en")
	var b := _run(777, 6)
	var rb := [b.money, b.stats.duplicate(), b.events.size(), b.story.archive.size(), b.paper.issues.size(), b.workers.size()]
	check(str(ra) == str(rb), "одна партия по-русски и по-английски идёт одинаково: деньги %s / %s, событий %d / %d" % [Defs.money_str(a.money), Defs.money_str(b.money), int(ra[2]), int(rb[2])])
	# 2) всё по-английски
	sim = b
	sim.notified.connect(func(t: String, _l: int, _c: Vector2i) -> void:
		if not _seen.has(t):
			_seen.append(t))
	sim.story.enabled = true
	while sim.tod() < 600.0 or not sim.is_workday():   # утро рабочего дня: люди на смене
		sim.tick(0.5)
	sim.money = 2000000.0
	# все события рассказчика
	var evs: Array = Defs.events["events"].keys()
	for ev in evs:
		sim.story.cooldowns.clear()
		sim.story._start(str(ev), false)
	for ev2 in ["retire", "poach", "rational", "wedding", "baby"]:
		for w in sim.workers:
			w.age = 63 if ev2 == "retire" else 30
		sim.story._start(ev2, false)
	sim.story._ev_drinking()
	sim.story._ev_theft()
	sim.story.mode = "wild"
	for i in 12:
		sim.story.defer_payment(50000.0, "Tambovmash", "Втулка")
	sim.story.mode = "market"
	for r: Dictionary in sim.story.receivables.duplicate():
		sim.story._collect(r)
	sim.story._ev_reclamation({"client": "Tambovmash", "product": str(Defs.products.keys()[0]), "bad": 3, "comp": 12000.0})
	_snap()
	# пожар и травмы
	var c := sim.story._fire_spot()
	if c.x >= 0:
		sim.story.ignite(c, L.t("Загорелась проводка"))
		sim.story.brigade.request()
		sim.story._fire_out(true)
		sim.story.ignite(c, L.t("Загорелась проводка"))
		sim.story._fire_out(false)
	for cause in ["event", "work", "slip", "burn", "fight", "other"]:
		for w in sim.workers:
			if w.sick_until < sim.minute and w.present:
				sim.story.injure(w, cause)
				break
	_snap()
	# забастовка — все требования
	for dm in ["canteen", "locker", "rush", "wage", "bonus", "arrears"]:
		sim.story.strike = {"active": true, "demand": dm, "leader": sim.workers[0].id, "days": 0, "offers": 0}
		sim.story._strike_letter(false)
		sim.story._strike_letter(true)
		sim.story.strike["days"] = 2
		sim.story._strike_letter(false)
		sim.story._apply_demand(dm, 0.5)
		sim.story._demand_cost(dm)
	_snap()
	sim.story._start_strike(false)
	sim.story._end_strike("strike_won", L.t("Требования выполнены, рабочие вернулись к станкам."))
	_snap()
	# праздники
	for d in range(sim.day(), sim.day() + 370):
		var h := sim.season.holiday(d)
		if not h.is_empty():
			var keep := sim.minute
			sim.minute = float(d - 1) * 1440.0 + 400.0
			sim.story._holidays()
			sim.minute = keep
	for hid in ["new_year", "feb23", "mar8", "subbotnik", "machine_day"]:
		for ch in 3:
			sim.story._res_holiday({"h": hid}, ch)
	_snap()
	# месячный план: выполнен и не выполнен
	sim.story.plan = {"m": sim.season.month_abs() - 1, "target": 1, "base": -100}
	sim.story._month_plan()
	sim.story.plan = {"m": sim.season.month_abs() - 1, "target": 100000, "base": 0}
	sim.story._month_plan()
	sim.story._res_vacation({}, 0)
	_snap()
	# письма — все решения
	for l: Dictionary in sim.story.letters.duplicate():
		var n := (l["choices"] as Array).size()
		sim.story.resolve(int(l["id"]), int(l["id"]) % n)
	_snap()
	# кризис
	sim.money = -10000.0
	sim.crisis.wage_credit_day = -9999
	sim.crisis.pay_wages(50000.0)
	sim.crisis.pay_wages(50000.0)
	sim.crisis._loan_hint()
	sim.crisis._debt_daily()
	sim.crisis._debt_daily()
	var extra: Array[String] = []
	for w in sim.workers:
		for r2: Dictionary in sim.crisis.fire_reasons(w):
			extra.append(str(r2["name"]))
			extra.append(str(r2["why"]))
	sim.money = 2000000.0
	if sim.workers.size() > 4:
		extra.append(sim.crisis.fire_with(sim.workers[-1], "agree"))
		extra.append(sim.crisis.fire_with(sim.workers[-1], "none"))
	sim.crisis._suits_daily()
	_snap()
	# проверки: все нарушения и советы, акты всех типов, визиты
	var types: Array = Defs.inspections["types"].keys()
	for t in types:
		var found: Array = []
		for key in Defs.inspections["texts"].keys():
			found.append(sim.inspect._v(str(t), str(key), Vector2i(-1, -1), -1, ["X"] if not str(Defs.inspections["texts"][key]).contains("%d") else [3], true))
			extra.append(Inspections.fix_text(str(key)))
		extra.append(sim.inspect.type_name(str(t)))
		extra.append(sim.inspect.who_name(str(t)))
		for s2 in sim.inspect.checklist(str(t)):
			extra.append(str(s2))
		sim.inspect._act(str(t), found.slice(0, 6), [], L.t("плановая"))
		sim.inspect.warned.clear()
		sim.inspect._act(str(t), found.slice(0, 3), [found[0]["key"]], "")
		sim.inspect._act(str(t), [], [], "")
		sim.inspect.schedule(str(t), sim.minute + 3.0 * 1440.0, true, L.t("плановая"))
		sim.inspect.violations(str(t))
		_snap()
	sim.inspect._desk_audit("tax")
	for kind in ["governor", "press"]:
		sim.inspect.announce_visit(kind)
		sim.inspect._visit_result(kind)
	for l2: Dictionary in sim.story.letters.duplicate():
		sim.story.resolve(int(l2["id"]), 1)
	_snap()
	# прозвища: каждое правило
	var wi := 0
	for rule: Dictionary in Nicks.RULES:
		var w2: Worker = sim.workers[wi % sim.workers.size()]
		wi += 1
		w2.nick = ""
		Nicks._give(sim, w2, rule, wi % 2 == 0)
		extra.append(w2.nick)
	_snap()
	# драка, кот, пожарные
	if sim.workers.size() >= 2:
		var e := {"kind": "fight", "a": sim.workers[0].id, "b": sim.workers[1].id, "end": sim.minute, "watchers": [], "breaker": sim.workers[0].id}
		sim.social._after_fight(e, sim.workers[0], sim.workers[1])
		for k3 in ["chat", "argue", "fight"]:
			extra.append(sim.social._task(sim.workers[0], sim.workers[1], k3, sim.workers[0].cell(), 2.0).label)
	var cat := Cat.make(sim)
	extra.append(cat.title())
	extra.append(cat.fur_name())
	extra.append(cat.activity)
	for st in ["sleep", "eat", "beg", "sit", "hunt"]:
		cat.next_state = st
		cat._arrive()
		extra.append(cat.activity)
	var g := FireBrigade.make_guest(sim, "Пожарный", "fireman", "#2b3038", "helmet", "#e8c02a", "nozzle")
	extra.append(g.activity)
	_snap()
	# газета: несколько номеров
	for i2 in 4:
		sim.paper.publish(true)
	extra.append(Paper.title_str())
	extra.append(Paper.subtitle_str())
	# достижения и музыка
	Achievements.load_all()
	for ad: Dictionary in Achievements.defs:
		extra.append(Achievements.name_of(ad))
		extra.append(Achievements.desc_of(ad))
	for mt in MusicDirector.TITLES.values():
		extra.append(L.t(str(mt)))
	_no_cyr("события, письма, проверки, газета, прозвища, достижения", extra)
	var issues := 0
	for iss: Dictionary in sim.paper.issues:
		issues += (iss["items"] as Array).size()
	check(issues >= 10 and sim.story.archive.size() >= 40, "сгенерировано: %d событий в журнале, %d заметок в газете, %d уведомлений" % [sim.story.archive.size(), issues, sim.events.size()])
	if not foreign.is_empty():
		print("  · по-русски из чужих срезов (имена, изделия, помещения…): %d, напр.: %s" % [foreign.size(), ", ".join(foreign.slice(0, 8))])
	# русский остался русским
	L.apply("ru")
	check(L.t("Пожар!") == "Пожар!" and Achievements.name_of(Achievements.defs[0]) == str(Achievements.defs[0]["name"]), "по-русски тексты прежние")
	print("РЕЗУЛЬТАТ: %s" % ("OK" if fails.is_empty() else "ОШИБКИ: " + "; ".join(fails)))
	quit(0 if fails.is_empty() else 1)
