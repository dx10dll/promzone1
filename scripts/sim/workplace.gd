class_name Workplace
extends RefCounted
## 1.15: закреплённые рабочие места. Станок, стол ОТК, ленточная пила и слесарный верстак
## закрепляются за человеком (Thing.owner). Хозяин работает на своём месте первым. Если он не может —
## не на смене, на больничном, в отпуске или на курсах, занят другим делом — встаёт любой, кто умеет.
## Освободился хозяин — сменщик доделывает деталь и уступает место.

## Короткие перерывы: место всё равно держим за хозяином.
const BREAK_KINDS := ["eat", "toilet", "rest", "smoke", "wander", "dress", "ppe"]


static func is_place(t: Thing) -> bool:
	return t != null and (t.kind() in ["machine", "qc", "saw"] or t.def_id == "workbench")


## Подходит ли человек для этого места (может ли вообще здесь работать).
static func fits(sim: Sim, w: Worker, t: Thing) -> bool:
	if w == null or w.visitor or w.is_itr():
		return false
	match t.kind():
		"machine":
			return sim.prod.can_operate(w, t)
		"qc":
			return w.skill("qc") >= 2
		"saw":
			return w.prof in ["laborer", "turner", "miller", "setter", "fitter"] or w.skill("haul") >= 4
	if t.def_id == "workbench":
		return w.prof == "fitter" or w.skill("fitting") >= 5
	return false


static func owner_of(sim: Sim, t: Thing) -> Worker:
	return sim.get_worker(t.owner) if t.owner >= 0 else null


## Хозяин сейчас на заводе и может работать на своём месте — тогда место держим за ним.
static func owner_ready(sim: Sim, t: Thing) -> bool:
	var o := owner_of(sim, t)
	if o == null or not o.present or o.visitor:
		return false
	if o.sick_until > sim.minute or o.away_why != "":
		return false
	if not fits(sim, o, t):
		return false
	if o.task == null or BREAK_KINDS.has(o.task.kind):
		return true
	return o.task.res_users.has(t.id)   # уже работает здесь; занят другим делом — место свободно


## Хозяин освободился и ждёт своё место: сменщику пора уступить.
static func owner_waiting(sim: Sim, t: Thing, w: Worker) -> bool:
	if t.owner < 0 or t.owner == w.id:
		return false
	var o := owner_of(sim, t)
	if o == null or not o.present or o.sick_until > sim.minute or o.away_why != "" or not fits(sim, o, t):
		return false
	return o.task == null or o.task.kind == "wander"


## Можно ли человеку сейчас занять это место.
static func may_use(sim: Sim, w: Worker, t: Thing) -> bool:
	if t.owner < 0 or t.owner == w.id or int(w.get_meta("order_only", -1)) == t.id:
		return true   # по приказу игрока — можно и на чужое место
	return not owner_ready(sim, t)


## Прибавка к выбору работы: своё место — в первую очередь.
static func bonus(w: Worker, t: Thing) -> float:
	return 45.0 if t.owner == w.id else 0.0


## Места, закреплённые за человеком.
static func places_of(sim: Sim, w: Worker) -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.owner == w.id and is_place(t):
			out.append(t)
	return out


## Кто может работать на месте: [Worker, ...], сначала по профессии и навыку.
static func candidates(sim: Sim, t: Thing) -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if fits(sim, w, t):
			out.append(w)
	out.sort_custom(func(a: Worker, b: Worker) -> bool: return _fit_score(t, a) > _fit_score(t, b))
	return out


static func _fit_score(t: Thing, w: Worker) -> float:
	var sk := "qc"
	var prof := "qc"
	match t.kind():
		"machine":
			var pd: Dictionary = Defs.processes.get(t.process(), {})
			sk = str(pd.get("skill", "turning"))
			prof = str(pd.get("prof", ""))
		"saw":
			sk = "haul"
			prof = "laborer"
	if t.def_id == "workbench":
		sk = "fitting"
		prof = "fitter"
	return float(w.skill(sk)) + (5.0 if w.prof == prof else 0.0)


## Закрепить место за человеком (или снять: w = null). Одно место — один хозяин.
static func assign(sim: Sim, t: Thing, w: Worker) -> void:
	t.owner = w.id if w else -1
	sim.thing_rev += 1


## Утром: свободные места — тем, у кого своего места ещё нет; уволенные хозяева снимаются.
static func auto_assign(sim: Sim) -> void:
	var taken := {}
	for t: Thing in sim.things.values():
		if not is_place(t) or t.owner < 0:
			continue
		var o := sim.get_worker(t.owner)
		if o == null or o.visitor:
			t.owner = -1
		else:
			taken[o.id] = true
	# 1.16: сначала — по профессии (токарю токарный), потом остальные места тем, кто умеет
	for pass_i in 2:
		for t2: Thing in sim.things.values():
			if not is_place(t2) or not t2.built or t2.demolish or t2.owner >= 0:
				continue
			var prof := _place_prof(t2)
			for c in candidates(sim, t2):
				if taken.has(c.id) or (pass_i == 0 and c.prof != prof):
					continue
				t2.owner = c.id
				taken[c.id] = true
				break


static func _place_prof(t: Thing) -> String:
	if t.def_id == "workbench":
		return "fitter"
	match t.kind():
		"machine":
			return str(Defs.processes.get(t.process(), {}).get("prof", ""))
		"saw":
			return "laborer"
	return "qc"
