extends SceneTree
## Тест 1.50d: облачка-мысли над людьми — выбор значка и цвета по состоянию, «проблема перекрывает действие»,
## анти-мигание (смена не чаще раза в 2 с), видимость действий, чёткие SVG-облачка, слой без узлов на человека.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage150d_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _norm(w: Worker) -> void:
	w.present = true
	w.hidden = false
	w.visitor = false
	w.dressed = false
	w.needs["bladder"] = 90.0
	w.needs["food"] = 90.0
	w.needs["rest"] = 90.0
	w.mood = 70.0
	w.bubble = ""
	w.task = null
	w.thoughts.clear()
	w.ppe = 100.0


func _task(kind: String) -> Task:
	var t := Task.new()
	t.kind = kind
	return t


func _init() -> void:
	Defs.load_all()
	L.apply("ru")
	var g := Scenario.new_garage(150)
	g.story.enabled = false
	g.progress.tutorial = -1
	S.big_shop(g)
	for i in 4:
		g.tick(0.5)
	var w: Worker = null
	for x: Worker in g.workers:
		if not x.is_director() and not x.is_itr():
			w = x
			break
	check(w != null, "есть рабочий для проверки")
	_norm(w)

	print("— действия: по задаче и типу станка")
	var cases := {"haul": "haul", "haul_cell": "haul", "load": "haul", "build_bp": "build", "build_thing": "build", "demolish": "demolish",
		"sweep": "clean", "clean": "clean", "repair": "repair", "fix": "repair", "study": "study", "exam": "exam", "eat": "eat",
		"rest": "rest", "smoke": "smoke", "toilet": "wc", "go_home": "home", "wander": "idle", "inspect": "inspect",
		"office": "office", "extinguish": "fire", "strike": "strike"}
	var bad_kinds: Array[String] = []
	for tk: String in cases:
		_norm(w)
		w.task = _task(tk)
		var p := BubbleLogic.pick(g, w)
		if str(p["k"]) != str(cases[tk]) or int(p["t"]) != BubbleLogic.T_ACT:
			bad_kinds.append("%s→%s/%d" % [tk, p["k"], p["t"]])
	check(bad_kinds.is_empty(), "задача → значок действия, ярус «действие» (%s)" % ", ".join(bad_kinds))
	_norm(w)
	check(str(BubbleLogic.pick(g, w)["k"]) == "idle", "без задачи — «ждёт работы»")
	var by_proc: Dictionary = {}
	for m: Thing in g.things_of("machine"):
		if m.process() != "" and not by_proc.has(m.process()):
			by_proc[m.process()] = m
	check(by_proc.size() >= 2, "в цеху станки разных типов (%s)" % ", ".join(by_proc.keys()))
	var all_ok := true
	for pr: String in by_proc:
		_norm(w)
		w.task = _task("operate")
		w.task.res_users.append((by_proc[pr] as Thing).id)
		var pk := BubbleLogic.pick(g, w)
		if str(pk["k"]) != "op_" + pr:
			all_ok = false
			print("    ", pr, " → ", pk["k"])
	check(all_ok, "работа у станка — значок по типу станка (op_<процесс>)")
	_norm(w)
	w.task = _task("operate")
	check(str(BubbleLogic.pick(g, w)["k"]) == "op_gear", "станок неизвестен — общая шестерня")

	print("— проблемы и желания: цвет по серьёзности")
	var rows := [["food", 15.0, "hungry", 2], ["food", 4.0, "hungry", 3], ["rest", 12.0, "tired", 2], ["rest", 3.0, "tired", 3],
		["bladder", 20.0, "wc", 2], ["bladder", 5.0, "wc", 3]]
	for r: Array in rows:
		_norm(w)
		w.needs[str(r[0])] = float(r[1])
		var p2 := BubbleLogic.pick(g, w)
		check(str(p2["k"]) == str(r[2]) and int(p2["t"]) == int(r[3]), "%s=%s → %s, ярус %d (жёлтая=2, красная=3)" % [r[0], r[1], p2["k"], p2["t"]])
	_norm(w)
	w.mood = 20.0
	check(str(BubbleLogic.pick(g, w)["k"]) == "angry" and int(BubbleLogic.pick(g, w)["t"]) == 2, "настроение 20 → недоволен, жёлтая")
	w.mood = 8.0
	check(int(BubbleLogic.pick(g, w)["t"]) == 3, "настроение 8 → красная")
	_norm(w)
	w.bubble = "injury"
	check(str(BubbleLogic.pick(g, w)["k"]) == "injury" and int(BubbleLogic.pick(g, w)["t"]) == 3, "травма → красная")
	w.bubble = "fight"
	check(str(BubbleLogic.pick(g, w)["k"]) == "fight" and int(BubbleLogic.pick(g, w)["t"]) == 3, "драка → красная")
	w.bubble = "argue"
	check(str(BubbleLogic.pick(g, w)["k"]) == "argue" and int(BubbleLogic.pick(g, w)["t"]) == 2, "спор → жёлтая")
	w.bubble = "chat"
	check(str(BubbleLogic.pick(g, w)["k"]) == "chat" and int(BubbleLogic.pick(g, w)["t"]) == 1, "болтает → действие")
	_norm(w)
	Mood.add(g, w, "arrears")
	check(str(BubbleLogic.pick(g, w)["k"]) == "wait_pay" and int(BubbleLogic.pick(g, w)["t"]) == 3, "долги по зарплате → «ждёт зарплату», красная")
	_norm(w)
	w.dressed = true
	w.ppe = 0.0
	w.days_worked = 3
	check(str(BubbleLogic.pick(g, w)["k"]) == "no_ppe", "в спецовке, СИЗ изношены → «нет СИЗ»")
	_norm(w)
	w.dressed = true
	var cold_at := Defs.sea("freezing_below") - 1.0
	g.season.room_temp.clear()
	var real_out: float = g.season.outside_temp()
	if real_out < Defs.sea("freezing_below"):
		check(str(BubbleLogic.pick(g, w)["k"]) == "cold", "мороз → «мёрзнет»")
	else:
		print("    (на улице %.1f° — холод пропускаем, cold_at=%.1f)" % [real_out, cold_at])

	print("— проблема перекрывает действие")
	_norm(w)
	w.task = _task("operate")
	w.needs["food"] = 15.0
	var po := BubbleLogic.pick(g, w)
	check(str(po["k"]) == "hungry" and int(po["t"]) == 2, "у станка, но голоден → значок голода, а не станка")
	w.task = _task("eat")
	check(str(BubbleLogic.pick(g, w)["k"]) == "eat", "уже ест — показываем «ест», голод не дублируем")
	_norm(w)
	w.needs["food"] = 15.0
	w.needs["rest"] = 3.0
	check(str(BubbleLogic.pick(g, w)["k"]) == "tired", "красное (усталость) важнее жёлтого (голод)")
	_norm(w)
	w.bubble = "injury"
	w.needs["food"] = 5.0
	check(str(BubbleLogic.pick(g, w)["k"]) == "injury" or int(BubbleLogic.pick(g, w)["t"]) == 3, "красное событие и красная потребность — оба красные")
	_norm(w)
	w.present = false
	check(str(BubbleLogic.pick(g, w)["k"]) == "", "не на заводе — значка нет")

	print("— анти-мигание: смена значка не чаще раза в 2 с")
	var st := {"k": "", "t": 0, "since": -99.0, "a": 0.0}
	var flips := 0
	var last := ""
	var now := 0.0
	var seq := ["haul", "repair"]
	var i := 0
	while now < 20.0:
		var cand := {"k": seq[i % 2], "t": 1, "u": 0.0}
		BubbleLogic.step(st, cand, now)
		if str(st["k"]) != last:
			flips += 1
			last = str(st["k"])
		now += 0.25
		i += 1
	check(flips <= 11, "задачи меняются каждые 0,25 с, значок — %d раз за 20 с (не больше 11)" % flips)
	var s2 := {"k": "haul", "t": 1, "since": 0.0, "a": 1.0}
	BubbleLogic.step(s2, {"k": "repair", "t": 1, "u": 0.0}, 0.5)
	check(str(s2["k"]) == "haul", "через 0,5 с действие ещё не сменилось")
	BubbleLogic.step(s2, {"k": "repair", "t": 1, "u": 0.0}, 2.1)
	check(str(s2["k"]) == "repair", "через 2,1 с — сменилось")
	var s3 := {"k": "haul", "t": 1, "since": 10.0, "a": 1.0}
	BubbleLogic.step(s3, {"k": "hungry", "t": 2, "u": 0.5}, 10.1)
	check(str(s3["k"]) == "hungry", "проблема перебивает действие сразу, без ожидания")
	BubbleLogic.step(s3, {"k": "haul", "t": 1, "u": 0.0}, 10.6)
	check(str(s3["k"]) == "hungry", "проблема не исчезает раньше 2 с (мигание у порога)")
	BubbleLogic.step(s3, {"k": "haul", "t": 1, "u": 0.0}, 12.2)
	check(str(s3["k"]) == "haul", "через 2 с после проблемы возвращается действие")
	var s4 := {"k": "hungry", "t": 2, "since": 20.0, "a": 1.0}
	BubbleLogic.step(s4, {"k": "wc", "t": 3, "u": 0.9}, 20.5)
	check(str(s4["k"]) == "wc", "жёлтое → красное: сразу показываем более серьёзное")

	print("— видимость: проблемы всегда, действия — выбранному, под мышью и когда людей мало")
	check(BubbleLogic.shown(3, false, false, 99, "auto"), "красная проблема видна сама")
	check(not BubbleLogic.shown(2, false, false, 99, "auto"), "1.51: жёлтое желание само не всплывает")
	check(not BubbleLogic.shown(1, false, false, 3, "auto"), "1.51: действие само не всплывает, даже когда людей мало")
	check(BubbleLogic.shown(2, true, false, 40, "auto"), "желание видно у выбранного")
	check(BubbleLogic.shown(1, true, false, 40, "auto"), "действие видно у выбранного")
	check(BubbleLogic.shown(1, false, true, 40, "auto"), "действие видно под мышью")
	check(not BubbleLogic.shown(3, true, true, 3, "off"), "режим «off» прячет всё")
	check(BubbleLogic.shown(1, false, false, 40, "all"), "режим «all» показывает все действия")

	print("— картинки: каждый вид рисуется чётким SVG")
	var miss: Array[String] = []
	for kd: String in BubbleLogic.TITLES:
		for tier in [1, 2, 3]:
			var img := Image.new()
			if img.load_svg_from_string(BubbleArt.svg(kd, tier), 1.0) != OK or img.is_empty():
				miss.append("%s/%d" % [kd, tier])
	check(miss.is_empty(), "%d видов × 3 яруса: SVG разобран (%s)" % [BubbleLogic.TITLES.size(), ", ".join(miss)])
	var used: Dictionary = {}
	for tk2: String in BubbleLogic.TASK_KIND:
		used[BubbleLogic.TASK_KIND[tk2]] = true
	for ek: String in BubbleLogic.EVENT_TIER:
		used[ek] = true
	var untitled: Array[String] = []
	for uk: String in used:
		if not BubbleLogic.TITLES.has(uk):
			untitled.append(uk)
	check(untitled.is_empty(), "у каждого вида есть подпись для подсказки (%s)" % ", ".join(untitled))
	check(BubbleLogic.TITLES.size() >= 40, "видов значков: %d (нужно ≥ 40)" % BubbleLogic.TITLES.size())

	print("— подсказки словами")
	_norm(w)
	w.needs["food"] = 10.0
	var tp := BubbleLogic.tip(g, w, "hungry", 2)
	check(str(tp["head"]) == "Хочет есть" and str(tp["why"]) != "", "голод: «%s — %s»" % [tp["head"], tp["why"]])
	L.apply("en")
	var tp2 := BubbleLogic.tip(g, w, "hungry", 2)
	check(str(tp2["head"]) == "Wants to eat", "по-английски: «%s»" % tp2["head"])
	L.apply("ru")

	print("— слой: без узлов на человека, состояние по людям")
	for x2: Worker in g.workers:
		if not x2.is_director():
			_norm(x2)
	var layer := WorkerBubbles.new()
	layer.sim = g
	root.add_child(layer)
	var n0 := layer.get_child_count()
	w.needs["food"] = 5.0
	layer.refresh(0.3)
	check(str(layer.state_of(w.id).get("k", "")) == "hungry", "слой выбрал значок голода")
	check(layer.get_child_count() == n0 and n0 == 0, "узлов на человека нет (детей у слоя: %d)" % layer.get_child_count())
	w.needs["food"] = 90.0
	layer.refresh(0.5)
	check(str(layer.state_of(w.id).get("k", "")) == "hungry", "через 0,5 с значок не пропал (держится)")
	layer.refresh(2.0)
	check(str(layer.state_of(w.id).get("k", "")) != "hungry", "через 2,5 с после исчезновения причины значок сменился")
	layer.queue_free()

	print("ИТОГ: " + ("провалено %d" % fails.size() if not fails.is_empty() else "всё хорошо"))
	quit(1 if not fails.is_empty() else 0)
