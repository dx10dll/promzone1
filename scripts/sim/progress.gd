class_name Progress
extends RefCounted
## Прогрессия: этапы роста завода (цели перехода и что открывается), рейтинг в звёздах
## цели сценария, профиль завода, особенности сценариев
## (бродячие собаки, течь крыши, долги по зарплате), пошаговое обучение.

const STAGE_COUNT := 6

var sim: Sim
var profile := "mech"
var stage := 1
var ooo := false                 ## оформлено ООО (цель этапа «Мастерская»)
var all_open := false            ## песочница: всё открыто сразу
var flags: Dictionary = {}       ## разовые достижения: big_order, export, state ...
var rating: Dictionary = {}      ## критерий -> 0..1
var stars := 3
var history: Array = []          ## ежедневные срезы для рейтинга
var scn_done := false
var stage_up := -1               ## новый этап, о котором ещё не показали окно
var scn_up := false              ## сценарий пройден — показать окно
var tutorial := -1               ## шаг обучения (-1 — выключено)
var start_staff := 0
var start_day := 1
var quiet_until := 0   ## 1.17: до этого дня заказов нет — неделя на стройку (чистое поле, песочница)
var roof_leak := false
var roof_fix_at := -1.0
var dogs: Array = []             ## [{x, y, tx, ty, wait, f}]
var dogs_tame := false
var arrears_until := -1.0        ## до какой минуты погасить долги по зарплате (моногород)
var keep_fail := false
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


func pdef() -> Dictionary:
	return Defs.profiles.get(profile, {})


func sdef() -> Dictionary:
	return Defs.scenarios.get(sim.scenario, {})


func stage_def(i: int = -1) -> Dictionary:
	var arr: Array = Defs.stages.get("stages", [])
	var k := clampi((stage if i < 0 else i) - 1, 0, arr.size() - 1)
	return arr[k] if not arr.is_empty() else {}


func stage_name(i: int = -1) -> String:
	return str(stage_def(i).get("name", ""))


# ================================================================ что открыто

## Почему объект пока нельзя ставить ("" — можно).
func locked_reason(def_id: String) -> String:
	var d: Dictionary = Defs.objects.get(def_id, {})
	if d.is_empty():
		return "Неизвестный объект"
	if not sim.office.unlocked(d):
		return "Нужна разработка техотдела: «%s»" % str(Defs.research.get(str(d.get("research", "")), {}).get("name", ""))
	var req := int(d.get("stage", 1))
	if all_open or req <= stage or (pdef().get("early", []) as Array).has(def_id):
		var dv := str(d.get("dev", ""))
		if dv != "" and not sim.dev.on(dv):
			return "Нужна ступень развития «%s» (Управление → Развитие)" % str(Develop.step_def(dv).get("name", dv))
		return ""
	return "Откроется на этапе «%s»" % stage_name(req)


func dept_open(d: String) -> bool:
	return all_open or int(Defs.departments.get(d, {}).get("stage", 1)) <= stage


func dept_lock_text(d: String) -> String:
	return "Откроется на этапе «%s»" % stage_name(int(Defs.departments.get(d, {}).get("stage", 1)))


## Изделия, которые заказывают заводу этого профиля.
func products() -> Array:
	var arr: Array = pdef().get("products", [])
	if arr.is_empty():
		return Defs.products.keys()
	return arr


## Множитель числа заказов: профиль и сезон (сельхозмаш весной).
func offers_k() -> float:
	var k := float(pdef().get("offers_k", 1.0))
	var sea: Array = pdef().get("season", [])
	if sea.size() == 12:
		k *= float(sea[sim.season.month()])
	return k


func price_k() -> float:
	var k := float(pdef().get("price_k", 1.0))
	var sea: Array = pdef().get("season", [])
	if sea.size() == 12:
		k *= lerpf(0.9, 1.15, clampf((float(sea[sim.season.month()]) - 0.5) / 1.5, 0.0, 1.0))
	return k


func qty_k() -> float:
	return float(pdef().get("qty_k", 1.0))


func strict() -> bool:
	return bool(pdef().get("strict", false))


# ================================================================ цели

## [выполнено, текст прогресса]
func goal_state(g: Dictionary) -> Array:
	var t := str(g.get("type", ""))
	var n := int(g.get("n", 0))
	match t:
		"orders":
			var v := int(sim.stats.get("orders_done", 0))
			return [v >= n, "%d/%d" % [mini(v, n), n]]
		"turnover":
			var e := float(sim.stats.get("earned", 0.0))
			return [e >= n, "%s / %s" % [_short(e), _short(float(n))]]
		"ooo":
			return [ooo, "оформлено" if ooo else "нет"]
		"building":
			var best := 0
			for r in sim.rooms.list:
				if r.type == "workshop" and r.valid:
					best = maxi(best, r.area())
			var area := int(g.get("area", 60))
			return [best >= area, "%d/%d клеток" % [mini(best, area), area]]
		"staff":
			var s := sim.workers.size()
			return [s >= n, "%d/%d" % [mini(s, n), n]]
		"big_order":
			return [bool(flags.get("big_order", false)), "выполнен" if flags.get("big_order", false) else "нет"]
		"clean":
			var c := int(sim.stats.get("clean_inspections", 0))
			return [c >= n, "%d/%d" % [mini(c, n), n]]
		"plans":
			var p := int(sim.stats.get("plans_done", 0))
			return [p >= n, "%d/%d" % [mini(p, n), n]]
		"reputation":
			return [sim.reputation >= n, "%d/%d" % [int(sim.reputation), n]]
		"stars":
			return [stars >= n, "%d/%d ★" % [stars, n]]
		"export":
			var ok := bool(flags.get("export", false)) or bool(flags.get("state", false))
			return [ok, "выполнен" if ok else "нет"]
		"stage":
			return [stage >= n, stage_name()]
		"grants":
			var gd := sim.grants.done.size()
			return [gd >= int(g.get("n", 1)), "выполнено %d из %d" % [gd, int(g.get("n", 1))]]
		"no_loans":
			var d := sim.office.debt()
			return [sim.office.loans.is_empty(), "долг %s" % Defs.money_str(d) if d > 0.0 else "долгов нет"]
		"restore":
			var broken := 0
			for oid in flags.get("old_ids", []):
				var m: Thing = sim.things.get(int(oid))
				if m and (m.broken or m.condition < 50.0):
					broken += 1
			return [broken == 0, "осталось %d" % broken if broken > 0 else "все работают"]
		"roof":
			return [not roof_leak, "течёт" if roof_leak else "отремонтирована"]
		"arrears":
			var a := arrears_total()
			var late := arrears_until > 0.0 and sim.minute > arrears_until and a > 0.0
			return [a <= 0.0, ("долг %s" % Defs.money_str(a)) + (" — срок вышел!" if late else "") if a > 0.0 else "погашены"]
		"mood":
			var ms := int(g.get("staff", 0))
			var avg := avg_mood()
			var okm := sim.workers.size() >= ms and avg >= float(n)
			return [okm, "%d чел., настроение %d" % [sim.workers.size(), int(avg)]]
		"town_rel":
			var tr := sim.town.rel if sim.town else 0.0
			return [tr >= float(n), "%d/%d" % [int(tr), n]]
		"quality":
			var q := week_quality()
			var mn := int(g.get("min", 50))
			var pct := float(g.get("pct", 3))
			var okq := int(q[0]) >= mn and float(q[1]) * 100.0 < pct
			return [okq, ("брак %.1f%% из %d дет." % [float(q[1]) * 100.0, int(q[0])]) if int(q[0]) > 0 else "деталей ещё нет"]
		"steps":
			var c := sim.dev.count_on()
			return [c >= n, "%d/%d" % [mini(c, n), n]]
		"keep_staff":
			var share := float(g.get("share", 0.9))
			var need := int(ceil(start_staff * share))
			var days := int(g.get("days", 56))
			var passed := sim.day() - start_day
			var okk := not keep_fail and passed >= days
			return [okk, "%d/%d чел., %d/%d дн.%s" % [sim.workers.size(), need, mini(passed, days), days, " — нарушено" if keep_fail else ""]]
	return [false, ""]


func _short(v: float) -> String:
	if v >= 1000000.0:
		return "%.1f млн" % (v / 1000000.0)
	return "%d тыс." % int(v / 1000.0)


func stage_goals() -> Array:
	return stage_def().get("goals", [])


## Цели этапа на выбор (РП-25): {need, list}. Разные заводы приходят к этапу разными дорогами.
func stage_choice() -> Dictionary:
	return stage_def().get("choice", {})


func choice_done() -> int:
	var n := 0
	for g: Dictionary in stage_choice().get("list", []):
		if bool(goal_state(g)[0]):
			n += 1
	return n


func choice_need() -> int:
	return mini(int(stage_choice().get("need", 0)), (stage_choice().get("list", []) as Array).size())


## Все обязательные цели и нужное число целей на выбор выполнены.
func stage_ready() -> bool:
	if stage_goals().is_empty() and stage_choice().is_empty():
		return false
	for g: Dictionary in stage_goals():
		if not bool(goal_state(g)[0]):
			return false
	return choice_done() >= choice_need()


## [выполнено целей, всего нужно] — для панели задач.
func stage_progress() -> Array:
	var d := 0
	for g: Dictionary in stage_goals():
		if bool(goal_state(g)[0]):
			d += 1
	return [d + mini(choice_done(), choice_need()), stage_goals().size() + choice_need()]


func avg_mood() -> float:
	if sim.workers.is_empty():
		return 0.0
	var t := 0.0
	for w in sim.workers:
		t += w.mood
	return t / float(sim.workers.size())


## [деталей за 7 дней, доля брака] по ежедневным срезам.
func week_quality() -> Array:
	if history.is_empty():
		return [0, 0.0]
	var last: Dictionary = history[-1]
	var first: Dictionary = history[maxi(0, history.size() - 8)]
	var made := int(sim.stats.get("made", 0)) - int(first.get("made", 0))
	var scrap := int(sim.stats.get("scrap", 0)) - int(first.get("scrap", 0))
	if last.is_empty():
		return [0, 0.0]
	return [made, float(scrap) / float(maxi(1, made + scrap))]


func scenario_goals() -> Array:
	return sdef().get("goals", [])


# ================================================================ ход времени

func tick(dt: float) -> void:
	_tick_dogs(dt)
	if roof_fix_at > 0.0 and sim.minute >= roof_fix_at:
		roof_fix_at = -1.0
		roof_leak = false
		sim.story.info("Крыша отремонтирована", "Кровельщики закончили: в цеху больше не капает.", "build", Sim.LVL_GOOD)
	_t -= dt
	if _t <= 0.0:
		_t = 30.0
		_check_goals()


## Утро: срез для рейтинга, пересчёт звёзд, проверка целей.
func morning() -> void:
	history.append({"day": sim.day(), "made": int(sim.stats.get("made", 0)), "scrap": int(sim.stats.get("scrap", 0)),
		"money": sim.money})
	while history.size() > 30:
		history.pop_front()
	_rate()
	if roof_leak and sim.season.is_raining_day():
		for w in sim.workers:
			if not w.is_itr():
				Mood.add(sim, w, "roof_leak")
	if arrears_total() > 0.0:
		for w2 in sim.workers:
			if float(w2.get_meta("arrears", 0.0)) > 0.0:
				Mood.add(sim, w2, "arrears")
	_check_keep()
	_check_goals()


func _check_goals() -> void:
	# этап
	if stage < STAGE_COUNT:
		if stage_ready():
			stage += 1
			stage_up = stage
			sim.reputation = minf(100.0, sim.reputation + 5.0)
			sim.story.info("Новый этап: «%s»" % stage_name(), "Завод вырос! Открылось: %s." % str(stage_def().get("opens", "")).to_lower(), "stage_up", Sim.LVL_GOOD)
			sim.paper.add("Главное", "Наш завод — %s!" % stage_name().to_lower(), "Коллектив поздравляет руководство и себя. Открываются новые участки и службы.")
	# сценарий
	if not scn_done and not scenario_goals().is_empty():
		var all2 := true
		for g2: Dictionary in scenario_goals():
			if not bool(goal_state(g2)[0]):
				all2 = false
				break
		if all2:
			scn_done = true
			scn_up = true
			sim.stats["scenario_done"] = true
			sim.story.info("Сценарий «%s» пройден!" % str(sdef().get("name", "")), "Все цели выполнены. Можно продолжать без ограничений — завод ваш.", "star", Sim.LVL_GOOD)


## Отметки о достижениях от других систем.
func on_order_done(o: Dictionary) -> void:
	var total := float(o.get("price", 0)) * int(o.get("qty", 0))
	if total >= 250000.0:
		flags["big_order"] = true
	if str(o.get("kind", "")) == "export":
		flags["export"] = true
	if str(o.get("kind", "")) == "state":
		flags["state"] = true


# ================================================================ рейтинг (звёзды)

func _rate() -> void:
	# выпуск: доля заказов в срок среди последних
	var on_time := 0
	var late := 0
	var failed := 0
	for o: Dictionary in sim.orders.list:
		match str(o["status"]):
			"done":
				if int(o.get("late_days", 0)) == 0:
					on_time += 1
				else:
					late += 1
			"failed":
				failed += 1
			"active", "ready", "shipping":
				# 1.20: просроченный заказ в работе — уже срыв срока
				if sim.minute > float(o["deadline"]):
					late += 1
	var tot := on_time + late + failed
	var output := 0.6 if tot == 0 else clampf((on_time + late * 0.5) / float(tot), 0.0, 1.0)
	if not sim.story.plan.is_empty():
		var got := int(sim.stats.get("shipped", 0)) - int(sim.story.plan.get("base", 0))
		var tgt := maxi(1, int(sim.story.plan.get("target", 1)))
		var frac := float(sim.season.dom()) / float(sim.season.dpm())
		var plan_k := clampf(float(got) / (tgt * maxf(0.2, frac)), 0.0, 1.2)
		output = clampf(output * 0.7 + minf(plan_k, 1.0) * 0.3, 0.0, 1.0)
	# качество: брак за последние ~2 недели
	var made := 0
	var scrap := 0
	if history.size() >= 2:
		var a: Dictionary = history[maxi(0, history.size() - 14)]
		var b: Dictionary = history[-1]
		made = int(b["made"]) - int(a["made"])
		scrap = int(b["scrap"]) - int(a["scrap"])
	var quality := 0.75 if made + scrap == 0 else clampf(1.0 - float(scrap) / float(made + scrap) * 4.0, 0.0, 1.0)
	# безопасность
	var safety := 1.0 - sim.story.injuries_month() * 0.18 - (0.3 if sim.story.has_mod("fire_recent") else 0.0) - (0.2 if not sim.inspect.marks.is_empty() else 0.0)
	safety = clampf(safety, 0.0, 1.0)
	# люди
	var ms := 0.0
	for w in sim.workers:
		ms += w.mood
	var people := clampf((ms / maxf(1.0, sim.workers.size()) - 20.0) / 55.0, 0.0, 1.0)
	# финансы: деньги и динамика за две недели, долги
	var fin := 0.5
	if history.size() >= 2:
		var m0 := float(history[maxi(0, history.size() - 14)]["money"])
		var trend := sim.money - m0
		fin = 0.55 + clampf(trend / 300000.0, -0.4, 0.4)
	if sim.money < 0.0:
		fin -= 0.35
	if sim.office.debt() > maxf(sim.money, 0.0) * 3.0 + 500000.0:
		fin -= 0.15
	fin = clampf(fin, 0.0, 1.0)
	rating = {"output": output, "quality": quality, "safety": safety, "people": people, "finance": fin}
	var avg := (output + quality + safety + people + fin) / 5.0
	stars = clampi(1 + int(avg * 4.0 + 0.3), 1, 5)


const RATING_NAMES := {"output": "Выпуск и сроки", "quality": "Качество", "safety": "Безопасность", "people": "Настроение людей", "finance": "Финансы"}


func stars_text(n: int = -1) -> String:
	var k := stars if n < 0 else n
	return "★".repeat(k) + "☆".repeat(5 - k)


# ================================================================ действия игрока

func register_ooo() -> String:
	if ooo:
		return "ООО уже оформлено"
	var cost := 50000.0
	if not sim.can_afford(cost):
		return "Нужно %s на регистрацию, печать и расчётный счёт" % Defs.money_str(cost)
	sim.spend(cost, "Регистрация ООО")
	ooo = true
	sim.story.info("ООО зарегистрировано", "Теперь вы — %s. Устав, печать, расчётный счёт — всё как у людей, на вывеске у ворот новая строчка. С вами охотнее работают крупные заказчики." % Company.title(sim), "office", Sim.LVL_GOOD)
	sim.reputation = minf(100.0, sim.reputation + 3.0)
	_check_goals()
	return ""


func repair_roof() -> String:
	if not roof_leak or roof_fix_at > 0.0:
		return "Крыша уже в порядке или ремонт идёт"
	var cost := 180000.0
	if not sim.can_afford(cost):
		return "Нужно %s на кровельные работы" % Defs.money_str(cost)
	sim.spend(cost, "Ремонт: кровля цеха")
	roof_fix_at = sim.minute + 3.0 * 1440.0
	sim.notify("Кровельщики приступили: через три дня крыша перестанет течь.", Sim.LVL_INFO)
	return ""


func arrears_total() -> float:
	var t := 0.0
	for w in sim.workers:
		t += float(w.get_meta("arrears", 0.0))
	return t


func pay_arrears() -> String:
	var a := arrears_total()
	if a <= 0.0:
		return "Долгов по зарплате нет"
	if not sim.can_afford(a):
		return "Нужно %s, на счёте %s" % [Defs.money_str(a), Defs.money_str(sim.money)]
	sim.spend(a, "Зарплата: погашение долгов")
	for w in sim.workers:
		w.set_meta("arrears", 0.0)
		for i in range(w.thoughts.size() - 1, -1, -1):
			if str(w.thoughts[i]["id"]) == "arrears":
				w.thoughts.remove_at(i)
		Mood.add(sim, w, "arrears_paid")
	sim.story.info("Долги по зарплате погашены", "Люди получили всё, что им задолжали. В городе выдохнули.", "money", Sim.LVL_GOOD)
	sim.reputation = minf(100.0, sim.reputation + 5.0)
	return ""


func _check_keep() -> void:
	if keep_fail or start_staff <= 0:
		return
	for g: Dictionary in scenario_goals():
		if str(g.get("type", "")) == "keep_staff":
			var need := int(ceil(start_staff * float(g.get("share", 0.9))))
			if sim.workers.size() < need and sim.day() - start_day < int(g.get("days", 56)):
				keep_fail = true
				sim.reputation = maxf(0.0, sim.reputation - 10.0)
				sim.story.info("Губернатор недоволен", "Завод сократил слишком много людей. «Город на вас рассчитывал!» Репутация упала.", "staff", Sim.LVL_BAD, Vector2i(-1, -1), true)


# ================================================================ бродячие собаки

func _tick_dogs(dt: float) -> void:
	if dogs.is_empty():
		return
	var w := sim.world
	for d: Dictionary in dogs:
		var wait := float(d.get("wait", 0.0)) - dt
		d["wait"] = wait
		if wait > 0.0:
			d["moving"] = false
			continue
		var pos := Vector2(float(d["x"]), float(d["y"]))
		var tgt := Vector2(float(d["tx"]), float(d["ty"]))
		var v := tgt - pos
		var step := 1.1 * dt
		if v.length() <= step:
			d["x"] = tgt.x
			d["y"] = tgt.y
			d["wait"] = sim.rng.randf_range(5.0, 40.0)
			d["moving"] = false
			# новая цель: случайная клетка улицы рядом
			for k in 12:
				var c := Vector2i(int(tgt.x) + sim.rng.randi_range(-7, 7), int(tgt.y) + sim.rng.randi_range(-5, 5))
				if w.in_plot(c) and w.passable(c) and sim.rooms.room_at(c) == null:
					d["tx"] = c.x + 0.5
					d["ty"] = c.y + 0.5
					break
		else:
			var np := pos + v.normalized() * step
			var nc := Vector2i(floori(np.x), floori(np.y))
			if not w.passable(nc):
				d["tx"] = pos.x
				d["ty"] = pos.y
				d["wait"] = 2.0
				continue
			d["x"] = np.x
			d["y"] = np.y
			d["moving"] = true
			d["right"] = v.x >= 0.0
	# люди рядом с собаками
	for wk in sim.workers:
		if not wk.present or sim.rooms.room_at(wk.cell()) != null:
			continue
		for d2: Dictionary in dogs:
			if wk.pos.distance_squared_to(Vector2(float(d2["x"]), float(d2["y"]))) < 9.0:
				Mood.add(sim, wk, "dogs_tame" if dogs_tame else "dogs")
				break


func spawn_dogs(n: int) -> void:
	var w := sim.world
	for i in n:
		for k in 40:
			var c := Vector2i(sim.rng.randi_range(w.plot.position.x + 1, w.plot.end.x - 2), sim.rng.randi_range(w.plot.position.y + 1, w.plot.end.y - 2))
			if w.passable(c) and sim.rooms.room_at(c) == null:
				dogs.append({"x": c.x + 0.5, "y": c.y + 0.5, "tx": c.x + 0.5, "ty": c.y + 0.5, "wait": sim.rng.randf_range(0.0, 20.0), "f": sim.rng.randi_range(0, 3)})
				break


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"profile": profile, "stage": stage, "ooo": ooo, "all_open": all_open, "flags": flags, "rating": rating, "stars": stars,
		"hist": history, "scn_done": scn_done, "tut": tutorial, "start_staff": start_staff, "start_day": start_day,
		"roof": roof_leak, "roof_at": roof_fix_at, "dogs": dogs, "tame": dogs_tame, "arr_until": arrears_until, "keep_fail": keep_fail, "quiet": quiet_until}


func from_dict(d: Dictionary) -> void:
	profile = str(d.get("profile", "mech"))
	quiet_until = int(d.get("quiet", 0))
	stage = int(d.get("stage", 1))
	ooo = bool(d.get("ooo", false))
	all_open = bool(d.get("all_open", false))
	flags = d.get("flags", {})
	rating = d.get("rating", {})
	stars = int(d.get("stars", 3))
	history = d.get("hist", [])
	scn_done = bool(d.get("scn_done", false))
	tutorial = int(d.get("tut", -1))
	start_staff = int(d.get("start_staff", 0))
	start_day = int(d.get("start_day", 1))
	roof_leak = bool(d.get("roof", false))
	roof_fix_at = float(d.get("roof_at", -1.0))
	dogs = d.get("dogs", [])
	dogs_tame = bool(d.get("tame", false))
	arrears_until = float(d.get("arr_until", -1.0))
	keep_fail = bool(d.get("keep_fail", false))


## Сохранение старой версии (до этапа 6): этап по тому, что уже построено и сделано.
func migrate() -> void:
	profile = "mech"
	var st := 1
	if int(sim.stats.get("orders_done", 0)) >= 10 and float(sim.stats.get("earned", 0.0)) >= 1000000.0:
		st = 2
	for t: Thing in sim.things.values():
		st = maxi(st, int(t.def().get("stage", 1)))
	for w in sim.workers:
		if w.is_itr():
			st = maxi(st, int(Defs.departments.get(w.dept(), {}).get("stage", 1)))
	stage = st
	ooo = st >= 3
	if bool(sim.stats.get("stage1_done", false)):
		stage = maxi(stage, 2)
	_rate()


# ================================================================ неделя стройки (1.17)

const QUIET_DAYS := 7


## Идёт неделя стройки: сбыт заявок не берёт.
func quiet() -> bool:
	return quiet_until > 0 and sim.day() < quiet_until


func quiet_left() -> int:
	return maxi(0, quiet_until - sim.day())


## Утро: неделя стройки кончилась сама.
func quiet_morning() -> void:
	if quiet_until > 0 and sim.day() >= quiet_until:
		quiet_until = 0
		sim.notify("Неделя стройки позади: отдел сбыта начинает принимать заявки. Проверьте, что станки под током и есть кому работать.", Sim.LVL_GOOD)


## Кнопка «Начать производство раньше».
func start_early() -> void:
	if not quiet():
		return
	quiet_until = 0
	sim.notify("Производство открыто раньше срока: сбыт уже принимает заявки — первые придут сегодня.", Sim.LVL_GOOD)
	sim.orders.open_early()

