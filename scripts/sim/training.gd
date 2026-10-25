class_name Training
extends RefCounted
## Люди и обучение: курсы повышения разряда и смежной профессии (в своём учебном классе
## или с выездом в учебный центр), инструктаж по охране труда, наставники и ученики,
## отношения в коллективе (дружба и вражда), практиканты из ПТУ.

## Чему учат на курсах.
const SKILLS := ["turning", "milling", "welding", "heat", "casting", "stamping", "paint", "assembly", "qc", "electric", "build"]
## Цена и длительность: up — повышение разряда (+2 к навыку), new — смежная профессия (навык до 3).
const COURSE := {
	"up": {"cls": 6000.0, "ctr": 15000.0, "study": 720.0, "days": 3},
	"new": {"cls": 9000.0, "ctr": 22000.0, "study": 960.0, "days": 4},
}
const TB_COST := 3000.0         ## инструктаж по охране труда: приглашённый инженер по ОТ
const TB_DAYS := 60              ## сколько дней действует инструктаж
const TB_INJURY_K := 0.7         ## травм меньше на 30%
const PTU_COST := 10000.0
const PTU_DAYS := 20             ## длительность практики
const PTU_WAGE := 1200           ## стипендия практиканта за смену
const FRIEND := 40.0
const FOE := -40.0

var sim: Sim
var courses: Array = []          ## [{wid, skill, kind, where, need, done, until, from, to}]
var tb_day := -999               ## день последнего инструктажа по охране труда
var tb_wait: Array = []          ## кого ещё нужно проинструктировать (идёт инструктаж)
var tb_until := -1.0             ## до какой минуты идёт инструктаж
var tb_people := 0
var ptu := false                 ## договор с ПТУ
var mentored := 0                ## сколько учеников выучили наставники
var _rel_t := 0.0
var _feud_cd: Dictionary = {}    ## «a-b» -> день, раньше которого письмо о ссоре не повторять


func _init(s: Sim) -> void:
	sim = s


# ================================================================ учебный класс и курсы

func classrooms() -> Array[Rooms.Room]:
	return sim.rooms.of_type("classroom")


## Мест в учебных классах: по местам за партами в оборудованных классах.
func class_seats() -> int:
	var n := 0
	for t in sim.things_of("school_desk"):
		if sim.rooms.thing_in(t, "classroom"):
			n += t.spots().size()
	return n


func class_busy() -> int:
	return courses.filter(func(c: Dictionary) -> bool: return str(c["where"]) == "class").size()


func course_of(w: Worker) -> Dictionary:
	for c: Dictionary in courses:
		if int(c["wid"]) == w.id:
			return c
	return {}


## Профессия, для которой этот навык основной («Фрезеровщик» для фрезерного дела).
static func prof_for_skill(sk: String) -> String:
	for p in Worker.PROF_SKILL.keys():
		if str(Worker.PROF_SKILL[p]) == sk and not Worker.ITR.has(p):
			return str(p)
	return ""


## Что даст курс по навыку: {kind, from, to, cls, ctr, days, why}. why — почему нельзя.
func offer(w: Worker, sk: String) -> Dictionary:
	var cur := w.skill(sk)
	var kind := "up" if cur >= 3 or sk == w.main_skill() else "new"
	var d: Dictionary = COURSE[kind]
	var to := mini(10, cur + 2) if kind == "up" else 3
	var why := ""
	if w.is_itr() or w.visitor:
		why = L.t("ИТР учатся у себя в отделе")
	elif cur >= 10:
		why = L.t("уже мастер своего дела")
	elif not course_of(w).is_empty():
		why = L.t("уже на курсах")
	return {"kind": kind, "from": cur, "to": to, "cls": d["cls"], "ctr": d["ctr"], "days": d["days"], "why": why}


## Отправить на курсы. where: "class" — в своём учебном классе, "center" — с выездом в учебный центр.
func start_course(w: Worker, sk: String, where: String) -> String:
	if not SKILLS.has(sk):
		return L.t("Таким курсам не учат")
	var o := offer(w, sk)
	if str(o["why"]) != "":
		return "%s: %s" % [w.full_name(), o["why"]]
	var cost := float(o["cls"] if where == "class" else o["ctr"])
	if where == "class":
		if classrooms().is_empty():
			return L.t("Нет учебного класса: постройте помещение с партами и доской (Помещения → Учебный класс)")
		if class_busy() >= class_seats():
			return L.t("В учебном классе нет свободных мест — поставьте ещё парт")
	if not sim.can_afford(cost):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(cost)
	var kind := str(o["kind"])
	var c := {"wid": w.id, "skill": sk, "kind": kind, "where": where, "need": float(COURSE[kind]["study"]),
		"done": 0.0, "until": -1, "from": int(o["from"]), "to": int(o["to"]), "day": sim.day()}
	var skn := L.t(str(Worker.SKILL_NAMES.get(sk, sk))).to_lower()
	sim.spend(cost, "Обучение: %s (%s)" % [w.full_name(), skn])
	if where == "center":
		var days := int(o["days"])
		c["until"] = sim.day() + days
		w.sick_until = float(sim.day() + days - 1) * 1440.0 + 300.0
		w.away_why = "на курсах"
		if w.present:
			sim.brain.send_home(w, L.t("Уезжает на курсы"))
		sim.notify(L.t("%s уезжает на курсы в учебный центр (%s) на %d %s.") % [w.full_name(), skn, days, Defs.plural(days, "день", "дня", "дней")], Sim.LVL_INFO)
	else:
		sim.notify(L.t("%s пойдёт на курсы в учебный класс: %s. Учится в свою смену.") % [w.full_name(), skn], Sim.LVL_INFO)
	w.add_history(sim.day(), L.t("Направлен на курсы: %s") % skn)
	courses.append(c)
	return ""


func cancel_course(w: Worker) -> void:
	var c := course_of(w)
	if c.is_empty():
		return
	courses.erase(c)
	if str(c["where"]) == "center" and w.away_why == "на курсах":
		w.sick_until = -1.0
	w.add_history(sim.day(), L.t("Курсы отменены"))


## Учится ли сейчас в своём учебном классе (а не работает).
func in_class(w: Worker) -> bool:
	var c := course_of(w)
	return not c.is_empty() and str(c["where"]) == "class" and not classrooms().is_empty()


## Минуты занятий за партой (с учётом черты «Любознательный»).
func add_study(w: Worker, minutes: float) -> void:
	var c := course_of(w)
	if c.is_empty():
		return
	c["done"] = float(c["done"]) + minutes * Mood.trait_val(w, "course_k", 1.0)
	if float(c["done"]) >= float(c["need"]):
		_complete(c)


func progress(w: Worker) -> float:
	var c := course_of(w)
	if c.is_empty():
		return 0.0
	if str(c["where"]) == "center":
		var total := float(COURSE[str(c["kind"])]["days"])
		return clampf(1.0 - float(int(c["until"]) - sim.day()) / total, 0.0, 1.0)
	return clampf(float(c["done"]) / float(c["need"]), 0.0, 1.0)


func _complete(c: Dictionary) -> void:
	courses.erase(c)
	var w := sim.get_worker(int(c["wid"]))
	if w == null:
		return
	var sk := str(c["skill"])
	var before := w.skill(sk)
	w.skills[sk] = maxi(before, int(c["to"]))
	var skn := L.t(str(Worker.SKILL_NAMES.get(sk, sk))).to_lower()
	sim.stats["courses"] = int(sim.stats.get("courses", 0)) + 1
	Mood.add(sim, w, "course_done")
	if str(c["kind"]) == "new":
		var pf := prof_for_skill(sk)
		var pn := Worker.lc(L.t(str(Worker.PROF_NAMES.get(pf, skn))))
		w.add_history(sim.day(), L.t("Освоил смежную профессию: %s") % pn)
		sim.notify(Nicks.gendered(L.t("%s окончил{|а} курсы и освоил{|а} смежную профессию: %s. Теперь может работать и на этих станках."), w.female) % [w.full_name(), pn], Sim.LVL_GOOD)
		sim.paper.add(L.t("Учёба"), L.t("Смежная профессия: %s") % w.full_name(), L.t("Окончил курсы и теперь может подменить %s. Широкий профиль — надёжный цех!") % (L.t("фрезеровщика") if sk == "milling" else pn))
	else:
		w.add_history(sim.day(), L.t("Окончил курсы: %s %d → %d") % [skn, before, w.skill(sk)])
		var next_g := (L.t(" Можно сдавать на %d-й разряд.") % w.pot_grade()) if w.has_grade() and w.pot_grade() > w.grade() else ""
		sim.notify(Nicks.gendered(L.t("%s окончил{|а} курсы: %s %d → %d.%s"), w.female) % [w.full_name(), skn, before, w.skill(sk), next_g], Sim.LVL_GOOD)
	Mood.refresh(sim, w)


# ================================================================ инструктаж по охране труда

func tb_valid() -> bool:
	return sim.day() - tb_day <= TB_DAYS


func tb_active() -> bool:
	return not tb_wait.is_empty() and sim.minute < tb_until


func injury_k() -> float:
	return TB_INJURY_K if tb_valid() else 1.0


## Провести инструктаж: все рабочие на смене по очереди идут в учебный класс (или к доске почёта
## в цеху, если класса нет) и слушают инженера по охране труда.
func start_tb() -> String:
	if tb_active():
		return L.t("Инструктаж уже идёт")
	if not sim.is_work_time():
		return L.t("Инструктаж проводят в рабочее время")
	var who: Array = []
	for w in sim.workers:
		if w.present and not w.is_itr():
			who.append(w.id)
	if who.is_empty():
		return L.t("Сейчас на смене никого нет")
	if not sim.can_afford(TB_COST):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(TB_COST)
	sim.spend(TB_COST, "Инструктаж по охране труда")
	tb_wait = who
	var lead := tb_lead()
	if lead:
		sim.brain.abort(lead)   # ведущий бросает бумаги и идёт к доске
	tb_people = 0
	tb_until = sim.minute + 180.0
	sim.notify(L.t("Начался инструктаж по охране труда: %d %s по очереди пройдут его в %s.") % [who.size(), Defs.plural(who.size(), "человек", "человека", "человек"), L.t("учебном классе") if not classrooms().is_empty() else L.t("цеху")], Sim.LVL_INFO)
	return ""


## Ведущий инструктажа (1.14): инженер по охране труда, иначе начальник цеха или мастер на смене.
func tb_lead() -> Worker:
	for prof in ["safety_engineer", "chief", "foreman"]:
		for w in sim.workers:
			if w.present and w.prof == prof and not w.hidden:
				return w
	return null


## Где стоит ведущий: у доски в учебном классе, а без класса — у стенда или посреди цеха.
var _tb_spot := Vector2i(-1, -1)
var _tb_spot_at := -1.0


func tb_spot() -> Vector2i:
	if _tb_spot_at == tb_until and _tb_spot.x >= 0:
		return _tb_spot
	_tb_spot_at = tb_until
	_tb_spot = Vector2i(-1, -1)
	var anchors: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.built and t.def_id in ["chalkboard", "safety_stand", "days_board"]:
			anchors.append(t)
	# у какой доски больше места перед ней для слушателей (доска в классе — лучше стенда)
	var best_a := -1.0
	for a in anchors:
		var c := a.cell + Vector2i(0, a.size().y)
		if not sim.world.passable(c):
			continue
		var sc := float(front_room(c)) + (4.0 if a.def_id == "chalkboard" else 0.0)
		if sc > best_a:
			best_a = sc
			_tb_spot = c
	if _tb_spot.x >= 0 and best_a >= 3.0:
		return _tb_spot
	_tb_spot = Vector2i(-1, -1)
	var rr: Array[Rooms.Room] = classrooms()
	if rr.is_empty():
		rr = sim.rooms.of_type("workshop", false)
	if not rr.is_empty():
		var r0: Rooms.Room = rr[0]
		var best := INF
		for c2 in r0.cells:
			if not sim.world.passable(c2) or sim.world.occ[sim.world.idx(c2)] >= 0:
				continue
			var d := absf(float(c2.x) - r0.center.x) + float(c2.y - r0.rect.position.y) * 1.5
			if d < best:
				best = d
				_tb_spot = c2
	return _tb_spot


## Сколько свободных клеток перед ведущим (2–5 клеток вниз), куда встанут слушатели.
func front_room(spot: Vector2i) -> int:
	var n := 0
	var sp := sim.rooms.space_id_at(spot)
	for dy in range(2, 6):
		for dx in range(-3, 4):
			var c := spot + Vector2i(dx, dy)
			if sim.world.passable(c) and sim.world.occ[sim.world.idx(c)] < 0 and sim.rooms.space_id_at(c) == sp:
				n += 1
	return n


func wants_tb(w: Worker) -> bool:
	return tb_active() and tb_wait.has(w.id)


func tb_done(w: Worker) -> void:
	tb_wait.erase(w.id)
	tb_people += 1
	w.add_history(sim.day(), L.t("Прослушал инструктаж по охране труда"))
	if tb_wait.is_empty():
		_tb_finish()


func _tb_finish() -> void:
	tb_wait.clear()
	tb_until = -1.0
	if tb_people > 0:
		tb_day = sim.day()
		sim.notify(L.t("Инструктаж по охране труда проведён (%d чел.). Ближайшие %d дней травм будет меньше на 30%%, журнал для трудовой инспекции заполнен.") % [tb_people, TB_DAYS], Sim.LVL_GOOD)


# ================================================================ наставники

func mentor_of(w: Worker) -> Worker:
	return sim.get_worker(w.mentor) if w.mentor >= 0 else null


## 1.23: ученики по наставникам — одной картой на минуту (раньше перебор всех для каждого).
## Карту сбрасывает любая смена наставника (_appr_sig = "").
var _appr: Dictionary = {}
var _appr_sig := ""


func apprentices(m: Worker) -> Array[Worker]:
	var sig := "%d|%d|%d" % [int(sim.minute), sim.workers.size(), sim.worker_rev]
	if sig != _appr_sig:
		_appr_sig = sig
		_appr.clear()
		for w in sim.workers:
			if w.mentor >= 0:
				if not _appr.has(w.mentor):
					var lst: Array[Worker] = []
					_appr[w.mentor] = lst
				(_appr[w.mentor] as Array[Worker]).append(w)
	var out: Array[Worker] = []
	if _appr.has(m.id):
		out.assign(_appr[m.id])
	return out


## Кто может учить этого человека: опытнее на 2+ по основному навыку ученика, не сам ученик,
## не больше двух учеников.
func mentor_candidates(w: Worker) -> Array[Worker]:
	var sk := w.main_skill()
	var out: Array[Worker] = []
	if w.is_itr() or w.visitor:
		return out
	for o in sim.workers:
		if o == w or o.is_itr() or o.mentor >= 0:
			continue
		if o.skill(sk) < 6 or o.skill(sk) < w.skill(sk) + 2:
			continue
		if apprentices(o).size() >= 2:
			continue
		out.append(o)
	out.sort_custom(func(a: Worker, b: Worker) -> bool: return a.skill(sk) + (2 if Mood.has_trait(a, "born_mentor") else 0) > b.skill(sk) + (2 if Mood.has_trait(b, "born_mentor") else 0))
	return out


func set_mentor(w: Worker, m: Worker) -> String:
	if m == null:
		if w.mentor >= 0:
			w.mentor = -1
			_appr_sig = ""
			w.add_history(sim.day(), L.t("Наставничество снято"))
		return ""
	if not mentor_candidates(w).has(m):
		return L.t("%s не может быть наставником для %s") % [m.full_name(), w.full_name()]
	for a in apprentices(w):
		a.mentor = -1
		_appr_sig = ""
	w.mentor = m.id
	_appr_sig = ""
	var skn := L.t(str(Worker.SKILL_NAMES.get(w.main_skill(), ""))).to_lower()
	w.add_history(sim.day(), L.t("Наставник: %s (%s)") % [m.full_name(), skn])
	m.add_history(sim.day(), L.t("Взял ученика: %s") % w.full_name())
	if m.shift != w.shift:
		sim.notify(L.t("%s и наставник %s работают в разные смены — учить получится, только когда смены совпадут.") % [w.full_name(), m.full_name()], Sim.LVL_WARN)
	else:
		sim.notify(L.t("%s теперь учится у %s.") % [w.full_name(), m.full_name()], Sim.LVL_INFO)
	return ""


## Подобрать наставников всем, кто ещё учится (до 3-го разряда) и без наставника.
func auto_mentors() -> int:
	var n := 0
	var students := sim.workers.filter(func(w: Worker) -> bool: return not w.is_itr() and w.mentor < 0 and w.grade() <= 3 and apprentices(w).is_empty())
	students.sort_custom(func(a: Worker, b: Worker) -> bool: return a.grade() < b.grade())
	for w: Worker in students:
		var cands := mentor_candidates(w).filter(func(o: Worker) -> bool: return o.shift == w.shift)
		if not cands.is_empty():
			set_mentor(w, cands[0])
			n += 1
	return n


## Наставник рядом: оба на работе в одну смену.
func _together(a: Worker, b: Worker) -> bool:
	return a.present and b.present and a.shift == b.shift


## Множитель роста навыка: наставник, практика, черты.
func growth_k(w: Worker, sk: String) -> float:
	var k := Mood.trait_val(w, "learn_k", 1.0)
	var m := mentor_of(w)
	if m and sk == w.main_skill() and _together(w, m):
		k *= 3.0 * Mood.trait_val(m, "mentor_k", 1.0)
	return k


## Наставник тратит время на ученика: чуть медленнее работает сам.
func speed_k(w: Worker) -> float:
	if Mood.has_trait(w, "born_mentor"):
		return 1.0
	for a in apprentices(w):
		if _together(a, w):
			return 0.92
	return 1.0


func _mentor_morning() -> void:
	for w: Worker in sim.workers.duplicate():
		var m := mentor_of(w)
		if w.mentor >= 0 and m == null:
			w.mentor = -1
			_appr_sig = ""
			continue
		if m == null:
			continue
		var sk := w.main_skill()
		# за прошлую смену вместе — шанс подрасти даже без станка
		if m.shift == w.shift and w.sick_until < sim.minute and m.sick_until < sim.minute and sim.rng.randf() < 0.18 * Mood.trait_val(m, "mentor_k", 1.0):
			if w.skill(sk) < m.skill(sk) - 1:
				w.skills[sk] = w.skill(sk) + 1
				w.add_history(sim.day(), L.t("Подрос у наставника: %s %d") % [L.t(str(Worker.SKILL_NAMES.get(sk, ""))).to_lower(), w.skill(sk)])
		if w.skill(sk) >= m.skill(sk) - 1 or w.skill(sk) >= 8:
			w.mentor = -1
			_appr_sig = ""
			mentored += 1
			sim.stats["mentored"] = int(sim.stats.get("mentored", 0)) + 1
			Mood.add(sim, m, "mentor_proud")
			Nicks.count(m, "mentor")
			w.add_history(sim.day(), Nicks.gendered(L.t("Выучил{ся|ась} у наставника %s"), w.female) % m.full_name())
			m.add_history(sim.day(), L.t("Выучил ученика: %s") % w.full_name())
			sim.notify(L.t("Ученик вырос: %s работает самостоятельно%s. Спасибо наставнику %s!") % [w.full_name(), (L.t(" и готов сдавать на %d-й разряд") % w.pot_grade()) if w.has_grade() and w.pot_grade() > w.grade() else "", m.full_name()], Sim.LVL_GOOD)
			sim.paper.add(L.t("Наставники"), L.t("%s вырастил смену") % m.full_name(), L.t("%s теперь работает самостоятельно. «Руки золотые, голова светлая», — говорит наставник.") % w.full_name())


# ================================================================ отношения

static func _rk(id: int) -> String:
	return str(id)


func rel(a: Worker, b: Worker) -> float:
	return float(a.rel.get(_rk(b.id), 0.0))


func _add_rel(a: Worker, b: Worker, v: float) -> void:
	var old := rel(a, b)
	var nv := clampf(old + v, -100.0, 100.0)
	a.rel[_rk(b.id)] = nv
	b.rel[_rk(a.id)] = nv
	if (old >= FRIEND) != (nv >= FRIEND) or (old <= FOE) != (nv <= FOE):
		rel_rev += 1
	if old < FRIEND and nv >= FRIEND:
		a.add_history(sim.day(), Nicks.gendered(L.t("Подружил{ся|ась} с %s"), a.female) % b.full_name())
		b.add_history(sim.day(), Nicks.gendered(L.t("Подружил{ся|ась} с %s"), b.female) % a.full_name())
		sim.notify(L.t("%s и %s подружились: вместе работается веселее.") % [a.full_name(), b.full_name()], Sim.LVL_INFO)
	elif old > FOE and nv <= FOE:
		a.add_history(sim.day(), L.t("Не поладил с %s") % b.full_name())
		b.add_history(sim.day(), L.t("Не поладил с %s") % a.full_name())
		sim.notify(L.t("%s и %s не ладят — в одной смене будут цапаться. Можно развести их по разным сменам.") % [a.full_name(), b.full_name()], Sim.LVL_WARN)


## 1.23: идём только по тем, с кем есть отношения (раньше — по всем людям), порядок — по id, как в списке.
## Списки запоминаются, пока не поменялись отношения или состав (rel_rev, число людей).
var rel_rev := 0
var _rel_cache: Dictionary = {}   ## id → [друзья, недруги]
var _rel_sig := Vector3i(-1, -1, -1)


func friends(w: Worker) -> Array[Worker]:
	return _rel_lists(w)[0]


func foes(w: Worker) -> Array[Worker]:
	return _rel_lists(w)[1]


func _rel_lists(w: Worker) -> Array:
	var sig := Vector3i(rel_rev, sim.workers.size(), sim.worker_rev)
	if sig != _rel_sig:
		_rel_sig = sig
		_rel_cache.clear()
	var c: Variant = _rel_cache.get(w.id)
	if c == null:
		c = [_rel_where(w, true), _rel_where(w, false)]
		_rel_cache[w.id] = c
	return c


func _rel_where(w: Worker, good: bool) -> Array[Worker]:
	var out: Array[Worker] = []
	for k: Variant in w.rel:
		var v := float(w.rel[k])
		if (good and v >= FRIEND) or (not good and v <= FOE):
			var o := sim.get_worker(int(str(k)))
			if o != null and o != w:
				out.append(o)
	if out.size() > 1:
		out.sort_custom(func(a: Worker, b: Worker) -> bool: return a.id < b.id)
	return out


## Раз в час: кто работает рядом (в одном помещении), понемногу сближается или раздражает друг друга.
func _tick_rel() -> void:
	var groups: Dictionary = {}
	for w in sim.workers:
		if not w.present or w.hidden:
			continue
		var r := sim.rooms.room_at(w.cell())
		var key: int = r.id if r else -1
		if not groups.has(key):
			groups[key] = []
		(groups[key] as Array).append(w)
	for key in groups.keys():
		var g: Array = groups[key]
		for i in g.size():
			for j in range(i + 1, g.size()):
				var a: Worker = g[i]
				var b: Worker = g[j]
				if int(key) < 0 and a.cell().distance_to(b.cell()) > 8.0:
					continue
				_add_rel(a, b, _drift(a, b))


func _drift(a: Worker, b: Worker) -> float:
	var v := 0.1 + sim.rng.randf_range(-0.5, 0.5)
	for w in [a, b]:
		v += Mood.trait_val(w, "rel_add", 0.0)
	if Mood.has_trait(a, "smoker") and Mood.has_trait(b, "smoker"):
		v += 0.2
	if absi(a.age - b.age) <= 8:
		v += 0.08
	v *= Mood.trait_val(a, "rel_k", 1.0) * Mood.trait_val(b, "rel_k", 1.0)
	return v


## Слагаемые настроения от людей вокруг: друзья, недруги, наставник, ученики, курсы.
func mood_parts(w: Worker) -> Array:
	var out: Array = []
	if not w.present:
		return out
	var fn := 0
	for o in friends(w):
		if fn < 2 and o.present and o.shift == w.shift:
			out.append([L.t("Работает вместе с другом: %s") % o.call_name(), 2.0])
			fn += 1
	var en := 0
	for o2 in foes(w):
		if en < 2 and o2.present and o2.shift == w.shift:
			out.append([L.t("Опять рядом этот %s") % o2.call_name(), -4.0])
			en += 1
	var m := mentor_of(w)
	if m and _together(w, m):
		out.append([L.t("Есть у кого поучиться: %s") % m.call_name(), 3.0])
	for a in apprentices(w):
		if _together(a, w):
			out.append([L.t("Учит молодых"), 5.0 if Mood.has_trait(w, "born_mentor") else 3.0])
			break
	if w.practice_until >= 0:
		out.append([L.t("Практика на настоящем заводе"), 4.0])
	return out


## Конфликт: двое недругов третий день в одной смене — письмо директору.
func _check_feuds() -> void:
	for a in sim.workers:
		for b in foes(a):
			if a.id > b.id or a.shift != b.shift:
				continue
			var key := "%d-%d" % [a.id, b.id]
			if sim.day() < int(_feud_cd.get(key, 0)) or sim.rng.randf() > 0.25:
				continue
			_feud_cd[key] = sim.day() + 14
			sim.story.letter("feud", L.t("Конфликт в смене"), L.t("%s и %s третий день цапаются в смене: то инструмент не поделят, то станок. Остальные уже ставки делают.") % [a.full_name(), b.full_name()], "staff", Sim.LVL_WARN,
				[{"text": L.t("Развести по разным сменам"), "hint": L.t("%s перейдёт в %s") % [b.full_name(), L.t("1-ю смену") if b.shift == 1 else L.t("2-ю смену")]},
				 {"text": L.t("Поговорить с обоими"), "hint": L.t("Скорее всего помирятся")},
				 {"text": L.t("Пусть сами разбираются"), "hint": L.t("Может дойти до драки")}], 1, {"a": a.id, "b": b.id})
			return


func resolve_feud(d: Dictionary, choice: int) -> void:
	var a := sim.get_worker(int(d.get("a", -1)))
	var b := sim.get_worker(int(d.get("b", -1)))
	if a == null or b == null:
		return
	match choice:
		0:
			sim.set_shift(b, 1 - b.shift)
		1:
			if sim.rng.randf() < 0.75:
				_add_rel(a, b, 45.0)
				sim.notify(L.t("%s и %s пожали друг другу руки. Мир.") % [a.full_name(), b.full_name()], Sim.LVL_GOOD)
			else:
				sim.notify(L.t("Разговор не помог: %s и %s остались при своём.") % [a.full_name(), b.full_name()], Sim.LVL_WARN)
		2:
			if sim.rng.randf() < 0.4:
				Mood.add(sim, a, "fight")
				Mood.add(sim, b, "fight")
				sim.notify(L.t("%s и %s подрались в курилке. Мастер разнял.") % [a.full_name(), b.full_name()], Sim.LVL_BAD)


# ================================================================ ПТУ

func practicants() -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.practice_until >= 0:
			out.append(w)
	return out


func ptu_cap() -> int:
	return 2 + int(sim.progress.stage / 2)


func ptu_sign() -> String:
	if ptu:
		return L.t("Договор с ПТУ уже есть")
	if not sim.dev.on("hr2"):
		return L.t("Договор с ПТУ заключает кадровик после ступени «Связь с ПТУ» (Управление → Развитие)")
	if not sim.can_afford(PTU_COST):
		return L.t("Не хватает денег: нужно %s") % Defs.money_str(PTU_COST)
	sim.spend(PTU_COST, "Договор с ПТУ о практике")
	ptu = true
	sim.notify(L.t("Договор с ПТУ подписан: по понедельникам будут приходить практиканты на %d дней.") % PTU_DAYS, Sim.LVL_GOOD)
	_ptu_arrive()
	return ""


func ptu_cancel() -> void:
	ptu = false
	sim.notify(L.t("Договор с ПТУ расторгнут. Нынешние практиканты доработают свой срок."), Sim.LVL_INFO)


## Нужные заводу рабочие профессии (по станкам), иначе токарь.
func _ptu_prof() -> String:
	var profs: Array[String] = []
	for pr in sim.prod.processes_available().keys():
		var pf := str(Defs.processes.get(pr, {}).get("prof", ""))
		if pf != "" and not Worker.ITR.has(pf):
			profs.append(pf)
	if profs.is_empty():
		profs = ["turner"]
	profs.append("laborer")
	return profs[sim.rng.randi_range(0, profs.size() - 1)]


func _ptu_arrive() -> void:
	if practicants().size() >= ptu_cap():
		return
	var w := People.make(sim.rng, _ptu_prof(), 0.3)
	w.age = sim.rng.randi_range(18, 19)
	for k in w.skills.keys():
		w.skills[k] = mini(int(w.skills[k]), 2)
	w.skills[w.main_skill()] = sim.rng.randi_range(2, 3)
	w.skills["haul"] = maxi(w.skill("haul"), 3)
	w.traits = ["student"]
	if sim.rng.randf() < 0.6:
		var extra := People.random_traits(sim.rng, w)
		for t in extra:
			if not w.traits.has(t) and w.traits.size() < 2:
				w.traits.append(t)
	w.look = People.random_look(sim.rng, w)
	w.wage = PTU_WAGE
	w.practice_until = sim.day() + PTU_DAYS
	sim.add_worker(w)
	w.add_history(sim.day(), L.t("Пришёл на практику из ПТУ: будущий %s") % Worker.lc(L.t(str(Worker.PROF_NAMES.get(w.prof, "")))))
	sim.notify(Nicks.gendered(L.t("Из ПТУ приш{ёл|ла} практикант{|ка}: %s, будущий %s. Учится вдвое быстрее, стипендия %s за смену."), w.female) % [w.full_name(), Worker.lc(L.t(str(Worker.PROF_NAMES.get(w.prof, "")))), Defs.money_str(PTU_WAGE)], Sim.LVL_GOOD)


func _ptu_morning() -> void:
	for w in practicants():
		if sim.day() >= w.practice_until and sim.story.get_letter_by_ev("practice_end").is_empty():
			var mw := People.wage_for(w)
			sim.story.letter("practice_end", L.t("Практика окончена"), L.t("%s, %d лет, заканчивает практику: %s, тянет на %d-й разряд. Мастер говорит: «%s».") % [w.full_name(), w.age, w.prof_lc(), w.pot_grade(), L.t("Толковый, берите") if w.pot_grade() >= 3 else L.t("Старается, руки растут откуда надо")], "staff", Sim.LVL_INFO,
				[{"text": L.t("Взять в штат"), "hint": L.t("Ставка %s за смену") % Defs.money_str(mw)}, {"text": L.t("Отпустить с благодарностью"), "hint": ""}], 0, {"w": w.id})
			return
	if ptu and sim.weekday() == 0:
		_ptu_arrive()


func resolve_practice(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("w", -1)))
	if w == null:
		return
	if choice == 0:
		w.traits.erase("student")
		w.practice_until = -1
		if w.has_grade():
			w.grade_n = w.pot_grade()   # квалификационный экзамен сдан в ПТУ
		w.wage = People.wage_for(w)
		Mood.add(sim, w, "practice_kept")
		w.add_history(sim.day(), Nicks.gendered(L.t("Взят{|а} в штат после практики"), w.female))
		sim.stats["ptu_kept"] = int(sim.stats.get("ptu_kept", 0)) + 1
		sim.notify(Nicks.gendered(L.t("%s взят{|а} в штат: %s, ставка %s."), w.female) % [w.full_name(), w.prof_lc(), Defs.money_str(w.wage)], Sim.LVL_GOOD)
	else:
		sim.brain.abort(w)
		sim.office.on_quit(w)
		var owed := float(w.get_meta("wage_due", 0.0))
		if owed > 0.0:
			sim.spend(owed, "Стипендия практиканту: " + w.full_name())
		on_leave(w)
		sim.workers.erase(w)
		sim.worker_rev += 1
		sim.notify(Nicks.gendered(L.t("%s закончил{|а} практику и вернул{ся|ась} в училище."), w.female) % w.full_name(), Sim.LVL_INFO)


# ================================================================ общее

## Человек ушёл с завода: курсы, наставничество, друзья.
func on_leave(w: Worker) -> void:
	var c := course_of(w)
	if not c.is_empty():
		courses.erase(c)
	for o in sim.workers:
		if o == w:
			continue
		if o.mentor == w.id:
			o.mentor = -1
			_appr_sig = ""
		if rel(o, w) >= FRIEND:
			Mood.add(sim, o, "friend_left")
		o.rel.erase(_rk(w.id))
		rel_rev += 1
	tb_wait.erase(w.id)


func tick(dt: float) -> void:
	if tb_until >= 0.0 and sim.minute >= tb_until:
		_tb_finish()
	_rel_t += dt
	if _rel_t >= 60.0:
		_rel_t = 0.0
		if sim.is_work_time():
			_tick_rel()


func morning() -> void:
	# курсы в учебном центре: вернулся — навык вырос
	for c: Dictionary in courses.duplicate():
		if str(c["where"]) == "center" and sim.day() >= int(c["until"]):
			_complete(c)
	_mentor_morning()
	_ptu_morning()
	if sim.is_workday():
		_check_feuds()


func to_dict() -> Dictionary:
	return {"courses": courses, "tb_day": tb_day, "tb_wait": tb_wait, "tb_until": tb_until, "tb_people": tb_people,
		"ptu": ptu, "mentored": mentored, "feud_cd": _feud_cd}


func from_dict(d: Dictionary) -> void:
	courses = d.get("courses", [])
	tb_day = int(d.get("tb_day", -999))
	tb_wait = []
	for i in d.get("tb_wait", []):
		tb_wait.append(int(i))
	tb_until = float(d.get("tb_until", -1.0))
	tb_people = int(d.get("tb_people", 0))
	ptu = bool(d.get("ptu", false))
	mentored = int(d.get("mentored", 0))
	_feud_cd = d.get("feud_cd", {})
