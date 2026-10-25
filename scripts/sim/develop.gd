class_name Develop
extends RefCounted
## Развитие завода (1.11): восемь веток по три ступени (data/develop.json); 1.13 — ветка «Земля»:
## покупка соседних участков.
## Ступени-отделы открываются сами, когда отдел заработал. Остальные ступени директор
## исследует из своего кабинета за деньги и время, по одной за раз. Этап роста разрешает
## ступень, а не дарит её. Ступень держат люди: нет человека в отделе-хранителе — не работает.

const ROOT_ROOM := "director_office"

var sim: Sim
var done: Array[String] = []     ## исследованные ступени
var cur := ""                    ## ступень, которая исследуется сейчас
var cur_start := 0.0
var cur_end := 0.0
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ справочник

static func branches() -> Array:
	return Defs.develop.get("branches", [])


static func step_def(id: String) -> Dictionary:
	for b: Dictionary in branches():
		for s: Dictionary in b.get("steps", []):
			if str(s["id"]) == id:
				return s
	return {}


## 1.39: название ступени на языке игры.
static func sname(sd: Dictionary) -> String:
	return L.dt("develop.%s.name" % str(sd.get("id", "")), str(sd.get("name", "")))


static func branch_of(id: String) -> Dictionary:
	for b: Dictionary in branches():
		for s: Dictionary in b.get("steps", []):
			if str(s["id"]) == id:
				return b
	return {}


## Предыдущая ступень той же ветки ("" — первая).
static func prev_of(id: String) -> String:
	var steps: Array = branch_of(id).get("steps", [])
	for i in steps.size():
		if str(steps[i]["id"]) == id:
			return str(steps[i - 1]["id"]) if i > 0 else ""
	return ""


static func is_dept_step(id: String) -> bool:
	return step_def(id).has("dept")


static func is_lot_step(id: String) -> bool:
	return step_def(id).has("lot")


## Цена ступени: у участков — цена земли на этой карте.
func cost_of(id: String) -> float:
	var sd := step_def(id)
	if sd.has("lot"):
		var k := int(sd["lot"])
		if k < sim.world.lots.size():
			return float(sim.world.lots[k].get("price", 0.0))
		return 0.0
	return float(sd.get("cost", 0.0))


static func all_ids() -> Array[String]:
	var out: Array[String] = []
	for b: Dictionary in branches():
		for s: Dictionary in b.get("steps", []):
			out.append(str(s["id"]))
	return out


# ================================================================ состояние

## Кабинет директора есть (без него ступени не исследуются).
func root_ok() -> bool:
	for r in sim.rooms.of_type(ROOT_ROOM):
		if r.valid:
			return true
	return false


## Ступень работает: отдел заработал, или исследована и её держит человек.
func on(id: String) -> bool:
	var sd := step_def(id)
	if sd.has("lot"):
		return sim.world.lot_bought(int(sd["lot"]))
	if sim.progress.all_open or sim.office.all_depts:
		return true
	if sd.is_empty():
		return false
	if sd.has("dept"):
		return sim.office.active(str(sd["dept"]))
	if id == "city1" and sim.crew.union_on():
		return true   # профсоюз уже есть — профком создан
	if not done.has(id):
		return false
	var holder := str(sd.get("holder", ""))
	return holder == "" or sim.office.active(holder)


## Исследована (или отдел работает), даже если сейчас её некому держать.
func has(id: String) -> bool:
	if is_dept_step(id):
		return on(id)
	return done.has(id) or on(id)


## Сколько ступеней открыто (для целей и интерфейса).
func count_on() -> int:
	var n := 0
	for id in all_ids():
		if on(id):
			n += 1
	return n


## Почему ступень нельзя начать исследовать ("" — можно).
func block_reason(id: String) -> String:
	var sd := step_def(id)
	if sd.is_empty():
		return L.t("Нет такой ступени")
	if sd.has("dept"):
		var d := str(sd["dept"])
		if not sim.progress.dept_open(d):
			return sim.progress.dept_lock_text(d)
		return L.t("Наймите: %s") % L.t(str(Worker.PROF_NAMES.get(str(Defs.departments.get(d, {}).get("prof", "")), ""))).to_lower()
	if done.has(id) or (sd.has("lot") and on(id)):
		return L.t("Уже открыто") if not sd.has("lot") else L.t("Участок уже куплен")
	if cur == id:
		return L.t("Уже исследуется") if not sd.has("lot") else L.t("Сделка уже идёт")
	if sd.has("lot") and int(sd["lot"]) >= sim.world.lots.size():
		return L.t("На этой карте больше нет свободных участков") if not sim.world.lots.is_empty() else L.t("На этой карте нет соседних участков")
	var pv := prev_of(id)
	if pv != "" and not on(pv):
		return L.t("Сначала: «%s»") % sname(step_def(pv))
	var st := int(sd.get("stage", 1))
	if sim.progress.stage < st and not sim.progress.all_open:
		return L.t("Нужен этап «%s»") % sim.progress.stage_title(st)
	var need_staff := int(sd.get("staff", 0))
	if sim.workers.size() < need_staff:
		return L.t("Нужно %d человек в штате") % need_staff
	var holder := str(sd.get("holder", ""))
	if holder != "" and not sim.office.active(holder):
		return L.t("Нужен работающий отдел «%s»") % Defs.dept_name(holder)
	if bool(sd.get("own_room", false)) and holder != "" and int(sim.office.room_status(holder)[0]) < 1:
		var room := str(Defs.departments.get(holder, {}).get("room", ""))
		return L.t("Нужен свой кабинет: «%s»") % Defs.room_name(room)
	if not root_ok():
		return L.t("Нужен кабинет директора")
	if cur != "":
		return L.t("Директор занят: «%s»") % sname(step_def(cur))
	if sim.money < cost_of(id):
		return L.t("Не хватает денег: %s") % Defs.money_str(cost_of(id))
	return ""


## Состояние для карточки: works / idle / busy / ready / locked.
func status(id: String) -> String:
	if on(id):
		return "works"
	if done.has(id):
		return "idle"
	if cur == id:
		return "busy"
	if not is_dept_step(id) and block_reason(id) == "":
		return "ready"
	return "locked"


## Сколько осталось дней до конца исследования.
func days_left() -> float:
	return maxf(0.0, (cur_end - sim.minute) / 1440.0) if cur != "" else 0.0


func progress01() -> float:
	if cur == "" or cur_end <= cur_start:
		return 0.0
	return clampf((sim.minute - cur_start) / (cur_end - cur_start), 0.0, 1.0)


## Ближайшая ступень, которую можно начать (самая дешёвая).
func next_ready() -> String:
	var best := ""
	var bc := INF
	for id in all_ids():
		if is_dept_step(id) or done.has(id) or cur == id:
			continue
		if is_lot_step(id):
			continue   # землю директор покупает только по решению игрока
		if block_reason(id) == "" and cost_of(id) < bc:
			bc = cost_of(id)
			best = id
	return best


# ================================================================ действия

func start(id: String) -> String:
	var err := block_reason(id)
	if err != "":
		return err
	var sd := step_def(id)
	var cost := cost_of(id)
	sim.spend(cost, ("Земля: «%s»" if sd.has("lot") else "Развитие: «%s»") % str(sd["name"]))
	cur = id
	cur_start = sim.minute
	cur_end = sim.minute + float(sd.get("days", 1)) * 1440.0
	sim.notify(L.t("Директор взялся за «%s» (%s): %d %s.") % [sname(sd), L.dt("develop.branch.%s.name" % str(branch_of(id).get("id", "")), str(branch_of(id).get("name", ""))).to_lower(), int(sd.get("days", 1)), Defs.plural(int(sd.get("days", 1)), "день", "дня", "дней")], Sim.LVL_INFO)
	return ""


## Отменить исследование: деньги возвращаются наполовину.
func cancel() -> void:
	if cur == "":
		return
	var sd := step_def(cur)
	var back := roundf(cost_of(cur) * 0.5)
	if back > 0.0:
		sim.earn(back, "Развитие: отмена «%s»" % str(sd["name"]))
	sim.notify(L.t("«%s» отложено. Вернули половину денег.") % sname(sd), Sim.LVL_INFO)
	cur = ""


func tick(dt: float) -> void:
	_t -= dt
	if _t > 0.0:
		return
	_t = 10.0
	if cur != "" and sim.minute >= cur_end:
		_finish(cur)


func _finish(id: String) -> void:
	var sd := step_def(id)
	cur = ""
	if not done.has(id):
		done.append(id)
	sim.thing_rev += 1
	sim.story.info(L.t("Открыто: «%s»") % sname(sd), L.dt("develop.%s.desc" % str(sd.get("id", "")), str(sd.get("desc", ""))), "stage_up", Sim.LVL_GOOD)
	sim.paper.add(L.t("Развитие"), L.t("На заводе — «%s»") % sname(sd).to_lower(), L.dt("develop.%s.desc" % str(sd.get("id", "")), str(sd.get("desc", ""))))
	if id == "city1" and not sim.crew.union_on():
		sim.crew.found_union()
	if sd.has("lot"):
		sim.buy_lot(int(sd["lot"]))
	var holder := str(sd.get("holder", ""))
	if holder != "" and not sim.office.active(holder):
		sim.notify(L.t("«%s» открыто, но не работает: нет человека в отделе «%s».") % [sname(sd), Defs.dept_name(holder)], Sim.LVL_WARN)


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"done": done, "cur": cur, "cur_start": cur_start, "cur_end": cur_end, "v": 1}


func from_dict(d: Dictionary) -> void:
	done.clear()
	for x in d.get("done", []):
		done.append(str(x))
	cur = str(d.get("cur", ""))
	cur_start = float(d.get("cur_start", 0.0))
	cur_end = float(d.get("cur_end", 0.0))
	if d.is_empty():
		_migrate()


## Сохранение до 1.11: то, что раньше открывал этап, остаётся открытым.
func _migrate() -> void:
	for id in all_ids():
		var sd := step_def(id)
		if sd.has("dept") or sd.has("lot"):
			continue
		if int(sd.get("stage", 1)) <= sim.progress.stage and (int(sd.get("stage", 1)) >= 2 or id == "city1" and sim.crew.union_on()):
			done.append(id)
