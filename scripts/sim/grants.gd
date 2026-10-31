class_name Grants
extends RefCounted
## Гранты и программы поддержки — мини-задания с возмещением затрат.
## Сначала берёте программу (окно «Финансы» → «Гранты»), потом делаете то, что требуется
## (оборудовать туалет, столовую, цех, нанять людей…), и только после проверки фонд
## возмещает деньги. Не успели к сроку — денег нет, репутация немного падает.

var sim: Sim
var active: Array = []     ## [{id, start_day, until_day, base}]
var done: Array = []       ## id выполненных
var failed: Array = []     ## id сорванных
var seen: Array = []       ## 1.21: о каких программах уже сообщили
var pending: Array = []    ## 1.62: поданные заявки [{id, fee, sent, ready, p}] — документы готовятся несколько дней
var next_offer := -1       ## 1.62: день, когда фонд пришлёт следующую памятку
var offered := 0           ## сколько памяток прислано (для тестов и статистики)
var rejected: Array = []   ## id программ, по которым заявку отклонили
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


static func def(id: String) -> Dictionary:
	for g: Dictionary in Defs.grants:
		if str(g["id"]) == id:
			return g
	return {}


## 1.39: текст программы на языке игры: title, org, desc (ключ grant.<id>.<поле>).
static func text(g: Dictionary, f: String) -> String:
	return L.dt("grant.%s.%s" % [str(g.get("id", "")), f], str(g.get(f, "")))


## Условие программы № i (ключ grant.<id>.goal<i>).
static func goal_text(g: Dictionary, i: int) -> String:
	var gl: Array = g.get("goals", [])
	return L.dt("grant.%s.goal%d" % [str(g.get("id", "")), i], str((gl[i] as Dictionary).get("text", "")) if i < gl.size() else "")


## 1.62: заявка стоит денег — документы, нотариус, консультант (около 10% возмещения).
static func fee_of(g: Dictionary) -> float:
	return maxf(2000.0, roundf(float(g.get("reward", 0)) * 0.1 / 500.0) * 500.0)


## 1.62: сколько дней готовятся документы.
static func docs_days(g: Dictionary) -> int:
	return clampi(2 + int(g.get("stage", 1)) + int(float(g.get("days", 14)) / 21.0), 3, 7)


## 1.62: шанс одобрения заявки: репутация, сертификат ISO 9001 и этап роста.
func approval_chance(g: Dictionary = {}) -> float:
	var p := 0.45 + sim.reputation / 100.0 * 0.3 + 0.03 * float(sim.progress.stage)
	if sim.market.iso_ok():
		p += 0.12
	if not g.is_empty() and int(g.get("stage", 1)) > 1:
		p -= 0.03 * float(int(g.get("stage", 1)) - 1)
	return clampf(p, 0.25, 0.92)


func is_pending(id: String) -> bool:
	for a: Dictionary in pending:
		if str(a["id"]) == id:
			return true
	return false


## Подать заявку: списывает расходы и ставит заявку в очередь на проверку.
func apply(id: String) -> String:
	var g := def(id)
	if g.is_empty():
		return L.t("Нет такой программы")
	if is_pending(id) or is_active(id):
		return L.t("Заявка по этой программе уже подана")
	var fee := fee_of(g)
	if not sim.can_afford(fee):
		return L.t("Не хватает денег на оформление: нужно %s") % Defs.money_str(fee)
	sim.spend(fee, "Грант: оформление заявки «%s»" % text(g, "title"))
	var n := docs_days(g)
	pending.append({"id": id, "fee": fee, "sent": sim.day(), "ready": sim.day() + n, "p": approval_chance(g)})
	sim.notify(L.t("Заявка на «%s» подана (%s). Документы будут готовы через %d %s — тогда и узнаем решение.") % [text(g, "title"), Defs.money_str(fee), n, Defs.plural(n, "день", "дня", "дней")], Sim.LVL_INFO)
	return ""


## Решение по заявке: одобрили — программа берётся в работу, отказ — расходы не возвращаются.
func _decide(a: Dictionary) -> void:
	pending.erase(a)
	var g := def(str(a["id"]))
	if g.is_empty():
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash("%s:%d" % [str(a["id"]), int(a["ready"])]) + sim.rng.seed
	if r.randf() < float(a["p"]):
		var err := take(str(a["id"]))
		if err != "":
			sim.notify(L.t("Заявку на «%s» одобрили, но взять программу сейчас нельзя: %s. Расходы %s возвращены.") % [text(g, "title"), err, Defs.money_str(float(a["fee"]))], Sim.LVL_WARN)
			sim.earn(float(a["fee"]), "Грант: возврат за оформление")
		else:
			sim.story.info(L.t("Заявку одобрили"), L.t("%s одобрил заявку на «%s». Выполните условия до срока — тогда фонд возместит %s.") % [text(g, "org"), text(g, "title"), Defs.money_str(float(g["reward"]))], "medal", Sim.LVL_GOOD)
	else:
		rejected.append(str(a["id"]))
		sim.story.info(L.t("Заявку отклонили"), L.t("%s отказал по заявке «%s»: не хватило баллов в конкурсе. Расходы на оформление (%s) не возвращаются.") % [text(g, "org"), text(g, "title"), Defs.money_str(float(a["fee"]))], "medal", Sim.LVL_WARN)


## 1.62: памятка фонда раз в 2–3 недели: подать заявку (деньги и время) или пропустить.
func _maybe_offer() -> void:
	var d := sim.day()
	if next_offer < 0:
		next_offer = d + 10 + (hash("grant%d" % sim.rng.seed) & 7)
		return
	if d < next_offer or not sim.story.enabled:
		return
	if not sim.story.get_letter_by_ev("grant_offer").is_empty():
		return
	var pool: Array = offers().filter(func(g: Dictionary) -> bool: return not is_pending(str(g["id"])) and not rejected.has(str(g["id"])))
	if pool.is_empty() or active.size() + pending.size() >= max_active():
		next_offer = d + 3
		return
	var r := RandomNumberGenerator.new()
	r.seed = hash("go%d:%d" % [d, sim.rng.seed])
	var g: Dictionary = pool[r.randi_range(0, pool.size() - 1)]
	next_offer = d + r.randi_range(14, 21)
	offered += 1
	var fee := fee_of(g)
	var n := docs_days(g)
	var goals: Array[String] = []
	for gi in (g.get("goals", []) as Array).size():
		goals.append(goal_text(g, gi))
	sim.story.letter("grant_offer", L.t("Программа поддержки: %s") % text(g, "title"),
		L.t("%s: %s Условия: %s. Срок — %d дн., возмещение %s.") % [text(g, "org"), text(g, "desc"), ", ".join(goals), int(g.get("days", 14)), Defs.money_str(float(g["reward"]))],
		"medal", Sim.LVL_INFO,
		[{"text": L.t("Подать заявку (%s)") % Defs.money_str(fee), "hint": L.t("Документы %d дн., одобрят с вероятностью ~%d%%") % [n, int(round(approval_chance(g) * 100.0))]},
		 {"text": L.t("Пропустить"), "hint": L.t("Ничего не тратим")}], 1, {"id": str(g["id"])})


func on_letter(d: Dictionary, choice: int) -> void:
	if choice != 0:
		return
	var err := apply(str(d.get("id", "")))
	if err != "":
		sim.notify(err, Sim.LVL_WARN)


func max_active() -> int:
	return 2 if sim.progress.stage < 3 else 3


## Программы, которые можно взять сейчас (по этапу роста, ещё не брали).
func offers() -> Array:
	var out: Array = []
	for g: Dictionary in Defs.grants:
		var id := str(g["id"])
		if done.has(id) or failed.has(id) or is_active(id):
			continue
		if int(g.get("stage", 1)) > sim.progress.stage:
			continue
		if not needed(g):
			continue
		out.append(g)
	return out


## 1.21: программа по ситуации — туалет уже есть, значит «построить туалет» не предложат, а предложат расширить.
func needed(g: Dictionary) -> bool:
	for n: Dictionary in g.get("need", []):
		if not _need_ok(n):
			return false
	return true


func _need_ok(n: Dictionary) -> bool:
	match str(n["type"]):
		"no_room":
			return sim.rooms.of_type(str(n["room"])).is_empty()
		"has_room":
			return not sim.rooms.of_type(str(n["room"])).is_empty()
		"no_room_any":
			for r in n.get("rooms", []):
				if sim.rooms.of_type(str(r)).is_empty():
					return true
			return false
		"no_room_area":
			return _max_area(str(n["room"])) < int(n["area"])
		"has_room_area":
			return _max_area(str(n["room"])) >= int(n["area"])
		"staff_min":
			return _staff() >= int(n["n"])
		"staff_max":
			return _staff() <= int(n["n"])
		"no_thing":
			return _count(str(n["def"])) == 0
		"has_thing":
			return _count(str(n["def"])) >= int(n.get("n", 1))
		"money_below":
			return sim.money < float(n.get("v", 0))
		"smoky":
			for m in sim.things_of("machine"):
				if m.process() in ["welding", "paint", "heat", "casting"]:
					return true
			return false
		"not_goal":
			return not goal_ok(n["goal"], {}) or not goal_ok(n.get("or", n["goal"]), {})
	return true


func _staff() -> int:
	return sim.workers.filter(func(w: Worker) -> bool: return not w.visitor).size()


func _count(def_id: String) -> int:
	var c := 0
	for t: Thing in sim.things.values():
		if t.built and t.def_id == def_id:
			c += 1
	return c


func _max_area(room: String) -> int:
	var a := 0
	for r in sim.rooms.of_type(room):
		a = maxi(a, r.area())
	return a


func is_active(id: String) -> bool:
	for a: Dictionary in active:
		if str(a["id"]) == id:
			return true
	return false


func take(id: String) -> String:
	var g := def(id)
	if g.is_empty():
		return L.t("Нет такой программы")
	if active.size() >= max_active():
		return L.t("Одновременно можно вести не больше %d программ") % max_active()
	var base := {"workers": [], "machines": [], "orders": int(sim.stats.get("orders_done", 0)), "things": {}, "areas": {}}
	for goal: Dictionary in g.get("goals", []):
		if goal.has("def"):
			(base["things"] as Dictionary)[str(goal["def"])] = _count(str(goal["def"])) + (_count(str(goal["alt"])) if goal.has("alt") else 0)
		if goal.has("room"):
			(base["areas"] as Dictionary)[str(goal["room"])] = _max_area(str(goal["room"]))
	for w in sim.workers:
		(base["workers"] as Array).append(w.id)
	for m in sim.things_of("machine"):
		(base["machines"] as Array).append(m.id)
	active.append({"id": id, "start": sim.day(), "until": sim.day() + int(g.get("days", 14)), "base": base})
	sim.notify(L.t("Программа «%s» оформлена. Выполните условия до %s — %s возместит %s.") % [text(g, "title"), sim.season.date_str(sim.day() + int(g.get("days", 14))), text(g, "org"), Defs.money_str(float(g["reward"]))], Sim.LVL_GOOD)
	return ""


## Выполнено ли условие программы.
func goal_ok(goal: Dictionary, a: Dictionary) -> bool:
	var base: Dictionary = a.get("base", {})
	match str(goal["type"]):
		"room":
			return not sim.rooms.of_type(str(goal["room"])).is_empty()
		"room_area":
			for r in sim.rooms.of_type(str(goal["room"])):
				if r.area() >= int(goal.get("area", 1)):
					return true
			return false
		"lamps":
			for r2 in sim.rooms.of_type(str(goal["room"])):
				var n := 0
				for c in r2.cells:
					var lt := sim.ceiling_at(c)
					if lt and lt.built and lt.kind() == "light" and sim.power.powered(lt):
						n += 1
				if n >= maxi(1, int(r2.area() / 30)):
					return true
			return false
		"hire":
			var old: Array = base.get("workers", [])
			var nw := 0
			for w in sim.workers:
				if not old.has(w.id):
					nw += 1
			return nw >= int(goal.get("n", 1))
		"new_machines":
			var oldm: Array = base.get("machines", [])
			var nm := 0
			for m in sim.things_of("machine"):
				if not oldm.has(m.id) and sim.power.powered(m):
					nm += 1
			return nm >= int(goal.get("n", 1))
		"extinguishers":
			if sim.rooms.spaces.is_empty():
				return false
			for sp in sim.rooms.spaces:
				if sim.rooms.space_count(sp.id, "extinguisher") == 0:
					return false
			return true
		"thing":
			var cnt := 0
			for t2: Thing in sim.things.values():
				if t2.built and t2.def_id == str(goal["def"]):
					cnt += 1
			return cnt >= int(goal.get("n", 1))
		"prof":
			for w2 in sim.workers:
				if w2.prof == str(goal["prof"]):
					return true
			return false
		"orders_done":
			return int(sim.stats.get("orders_done", 0)) - int(base.get("orders", 0)) >= int(goal.get("n", 1))
		"staff":
			return sim.workers.size() >= int(goal.get("n", 1))
		"thing_more":
			var now := _count(str(goal["def"])) + (_count(str(goal["alt"])) if goal.has("alt") else 0)
			return now - int((base.get("things", {}) as Dictionary).get(str(goal["def"]), 0)) >= int(goal.get("n", 1))
		"room_grow":
			return _max_area(str(goal["room"])) - int((base.get("areas", {}) as Dictionary).get(str(goal["room"]), 0)) >= int(goal.get("area", 1))
	return false


func all_ok(a: Dictionary) -> bool:
	for goal: Dictionary in def(str(a["id"])).get("goals", []):
		if not goal_ok(goal, a):
			return false
	return true


func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 30.0
	_maybe_offer()
	for pa: Dictionary in pending.duplicate():
		if sim.day() >= int(pa["ready"]):
			_decide(pa)
	for a: Dictionary in active.duplicate():
		var g := def(str(a["id"]))
		if g.is_empty():
			active.erase(a)
			continue
		if all_ok(a):
			active.erase(a)
			done.append(str(a["id"]))
			sim.earn(float(g["reward"]), L.t("Грант: %s") % text(g, "title"))
			sim.reputation = minf(100.0, sim.reputation + 2.0)
			sim.sfx.emit("cash", Vector2i(-1, -1))
			sim.story.info(L.t("Грант выплачен"), L.t("%s проверил выполнение программы «%s» и перечислил %s.") % [text(g, "org"), text(g, "title"), Defs.money_str(float(g["reward"]))], "money", Sim.LVL_GOOD, Vector2i(-1, -1), true)
			sim.paper.add(L.t("Экономика"), L.t("Завод получил грант: «%s»") % text(g, "title"), L.t("%s поддержал предприятие: %s на развитие.") % [text(g, "org"), Defs.money_str(float(g["reward"]))])
		elif sim.day() > int(a["until"]):
			active.erase(a)
			failed.append(str(a["id"]))
			sim.reputation = maxf(0.0, sim.reputation - 1.0)
			sim.notify(L.t("Срок программы «%s» вышел — условия не выполнены, денег не будет.") % text(g, "title"), Sim.LVL_WARN)


func to_dict() -> Dictionary:
	return {"active": active, "done": done, "failed": failed, "seen": seen, "pending": pending, "next_offer": next_offer, "offered": offered, "rejected": rejected}


func from_dict(d: Dictionary) -> void:
	active = d.get("active", [])
	done = d.get("done", [])
	failed = d.get("failed", [])
	seen = d.get("seen", [])
	pending = d.get("pending", [])
	next_offer = int(d.get("next_offer", -1))
	offered = int(d.get("offered", 0))
	rejected = d.get("rejected", [])
