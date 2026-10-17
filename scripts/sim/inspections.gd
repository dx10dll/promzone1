class_name Inspections
extends RefCounted
## Проверки: инспектор приходит через проходную и обходит завод.
## Нарушения проверяются в момент, когда он заходит в помещение, — пока он идёт, их можно
## успеть исправить. Найденное подсвечивается на карте. В конце — акт: штраф и предписание
## со сроком; повторное нарушение — двойной штраф и приостановка участка.
## Здесь же визиты губернатора и журналиста.

const VISIT_KINDS := {
	"governor": {"name": "Визит губернатора", "who": "Губернатор области", "outfit": "suit", "col": "#1d2230", "hat": "", "prop": ""},
	"press": {"name": "Визит журналиста", "who": "Корреспондент областной газеты", "outfit": "jacket", "col": "#7a4a3a", "hat": "cap", "prop": "camera"},
}

var sim: Sim
var queue: Array = []          ## [{type, at, announced, why}]
var visit: Dictionary = {}     ## текущий визит
var marks: Array = []          ## нарушения на карте [{cell, text, until, type}]
var prescriptions: Array = []  ## предписания [{type, keys, due}]
var history: Array = []        ## [{day, type, n, fine, result}]
var next_due: Dictionary = {}  ## тип -> день следующей плановой проверки
var clean := 0
var total := 0
var suspended: Dictionary = {} ## id станка -> до какой минуты остановлен по предписанию
var warned: Dictionary = {}    ## тип -> [ключи нарушений, за которые уже было предупреждение] (1.9.1)


func _init(s: Sim) -> void:
	sim = s


func tdef(t: String) -> Dictionary:
	if VISIT_KINDS.has(t):
		return VISIT_KINDS[t]
	return Defs.inspections.get("types", {}).get(t, {})


func type_name(t: String) -> String:
	return str(tdef(t).get("name", t))


func busy() -> bool:
	return not visit.is_empty()


func fine_k() -> float:
	return float(Defs.inspections.get("fine_k", {}).get(sim.story.mode, 1.0)) * (0.85 if escort_safety() else 1.0)


## 1.14: кто сопровождает инспектора — инженер по охране труда, мастер или начальник цеха на смене.
var _act_escort := -1   ## кто сопровождал — помним до конца оформления акта


func escort() -> Worker:
	if visit.is_empty():
		return sim.get_worker(_act_escort) if _act_escort >= 0 else null
	var eid := int(visit.get("escort", -1))
	if eid >= 0:
		var e := sim.get_worker(eid)
		if e and e.present:
			return e
	for prof in ["safety_engineer", "chief", "foreman"]:
		for w in sim.workers:
			if w.present and w.prof == prof and not w.hidden:
				visit["escort"] = w.id
				return w
	return null


## Сопровождает инженер по охране труда: знает, что показать, — штрафы меньше на 15%.
func escort_safety() -> bool:
	var e := escort()
	return e != null and e.prof == "safety_engineer"


func freq_k() -> float:
	return float(Defs.inspections.get("freq_k", {}).get(sim.story.mode, 1.0))


func is_suspended(m: Thing) -> bool:
	return float(suspended.get(m.id, -1.0)) > sim.minute


# ================================================================ расписание

func schedule(t: String, at: float, announced: bool, why: String = "", repeat: Array = []) -> void:
	for q: Dictionary in queue:
		if str(q["type"]) == t and absf(float(q["at"]) - at) < 3.0 * 1440.0:
			if not repeat.is_empty():
				q["repeat"] = repeat
			return
	var at2 := sim.to_work_time(at)
	var d := int(at2 / 1440.0)
	at2 = float(d) * 1440.0 + sim.rng.randf_range(570.0, 690.0)
	queue.append({"type": t, "at": at2, "announced": announced, "why": why, "repeat": repeat})
	queue.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["at"]) < float(b["at"]))
	if announced:
		var dd := int(at2 / 1440.0) + 1
		var txt := "%s: %s, %s" % [type_name(t), sim.season.date_str(dd), "в " + ("%02d:%02d" % [int(fmod(at2, 1440.0) / 60.0), int(fmod(at2, 60.0))])]
		if why != "":
			txt += " (%s)" % why
		sim.notify("Объявлена проверка. " + txt + ". Подготовьтесь — список требований в окне «События».", Sim.LVL_WARN)


func announce_visit(kind: String) -> void:
	var at := sim.minute + 2.0 * 1440.0
	schedule(kind, at, false, "")
	var who := "губернатор области" if kind == "governor" else "корреспондент областной газеты"
	var txt := "Через два дня завод посетит %s. Наведите порядок: уберите грузы с пола, почините станки, оборудуйте помещения, позаботьтесь о настроении людей." % who
	if kind == "governor":
		txt += " Если понравится — будет областная поддержка."
	else:
		txt += " От статьи зависит репутация завода."
	sim.story.info(str(VISIT_KINDS[kind]["name"]), txt, "goals" if kind == "governor" else "press", Sim.LVL_INFO, Vector2i(-1, -1), true)


## Утро: плановые проверки, внезапные, проверки исполнения предписаний.
func morning() -> void:
	var d := sim.day()
	var calm := 1.5 if sim.story.mode == "calm" else 1.0
	for t in Defs.inspections.get("types", {}).keys():
		var td: Dictionary = Defs.inspections["types"][t]
		if not next_due.has(t):
			next_due[t] = int(float(td.get("first", 10)) * calm) + sim.rng.randi_range(0, 4)
		if d < int(next_due[t]) or not _applicable(str(t)):
			continue
		var every := float(td.get("every", 30)) / freq_k()
		next_due[t] = d + int(every * sim.rng.randf_range(0.8, 1.25))
		if bool(td.get("planned", true)):
			schedule(str(t), sim.minute + 3.0 * 1440.0, true, "плановая")
		else:
			schedule(str(t), sim.minute + sim.rng.randf_range(0.0, 2.0) * 1440.0, false, "")
	# внезапная
	if d > 12 and sim.is_workday() and sim.rng.randf() < 0.025 * freq_k():
		var opts: Array = []
		for t2 in ["fire", "labor", "sanitary", "tech"]:
			if _applicable(t2):
				opts.append(t2)
		if not opts.is_empty():
			schedule(str(opts[sim.rng.randi_range(0, opts.size() - 1)]), sim.minute + 120.0, false, "внеплановая")
	# предписания
	for p: Dictionary in prescriptions.duplicate():
		if d >= int(p["due"]):
			prescriptions.erase(p)
			schedule(str(p["type"]), sim.minute + 60.0, false, "проверка исполнения предписания", p["keys"])
	for m: Dictionary in marks.duplicate():
		if float(m["until"]) <= sim.minute:
			marks.erase(m)


func _applicable(t: String) -> bool:
	match t:
		"labor", "sanitary":
			return sim.workers.size() >= 3
		"tech":
			return sim.things_of("machine").size() >= 2
		"ecology":
			return not sim.story.hot_machines().is_empty()
		"military":
			return bool(sim.progress.pdef().get("state", false))
	return true


# ================================================================ ход визита

func tick(dt: float) -> void:
	if visit.is_empty():
		if queue.is_empty():
			return
		var q: Dictionary = queue[0]
		if sim.minute < float(q["at"]):
			return
		var t := sim.tod()
		if not sim.is_workday() or t < 540.0 or t > 900.0:
			q["at"] = sim.to_work_time(sim.minute + (60.0 if t < 540.0 and sim.is_workday() else 1440.0))
			if t > 900.0 or not sim.is_workday():
				var dd := int(float(q["at"]) / 1440.0)
				q["at"] = float(dd) * 1440.0 + sim.rng.randf_range(570.0, 690.0)
			return
		queue.pop_front()
		_start(q)
		return
	_step(dt)


func _start(q: Dictionary) -> void:
	var t := str(q["type"])
	var td := tdef(t)
	total += 1 if not VISIT_KINDS.has(t) else 0
	if bool(td.get("desk", false)):
		_desk_audit(t)
		return
	var v := People.make(sim.rng, "laborer", 0.35)
	v.id = sim.new_id()
	v.visitor = true
	v.prof = "visitor"
	v.age = sim.rng.randi_range(32, 58)
	var lk := v.look
	lk["outfit"] = str(td.get("outfit", "suit"))
	lk["outfit_col"] = str(td.get("col", "#3b4252"))
	lk["hat"] = str(td.get("hat", ""))
	lk["hat_col"] = "#2a3550" if lk["hat"] == "peaked" else ("#efefe9" if lk["hat"] == "helmet" else "#3a3a40")
	lk["resp"] = false
	lk["phones"] = false
	v.dressed = true
	v.prop = str(td.get("prop", "folder"))
	v.present = true
	var gate := Vector2i(sim.gate_x, sim.world.sidewalk_row)
	if not sim.world.passable(gate):
		gate = sim.world.nearest_passable(gate)
	v.pos = Vector2(gate) + Vector2(0.5, 0.5)
	v.exit_cell = gate
	v.activity = str(td.get("who", "Инспектор"))
	sim.visitors.append(v)
	visit = {"type": t, "vid": v.id, "stops": _route(t), "i": 0, "wait": 0.0, "phase": "walk",
		"found": [], "why": str(q.get("why", "")), "repeat": q.get("repeat", []), "started": sim.minute}
	var who := str(td.get("who", "Инспектор"))
	sim.sfx.emit("doorbell", gate)
	if VISIT_KINDS.has(t):
		sim.notify(Nicks.gendered("%s приехал{|а} на завод.", v.female) % who, Sim.LVL_INFO, gate)
	else:
		sim.notify("На завод пришёл %s. %s" % [who.to_lower(), "Проверка внезапная!" if not bool(q.get("announced", false)) else "Плановая проверка."], Sim.LVL_WARN, gate)


func visitor() -> Worker:
	if visit.is_empty():
		return null
	for v in sim.visitors:
		if v.id == int(visit["vid"]):
			return v
	return null


## Маршрут: проходная (если есть) → помещения по кругу → контора (оформить акт).
func _route(t: String) -> Array:
	var stops: Array = []
	var w := sim.world
	for th: Thing in sim.things.values():
		if th.built and th.def_id == "checkpoint":
			var acc := sim.brain.best_access(th, th.cell)
			if acc.x >= 0:
				stops.append({"cell": [acc.x, acc.y], "room": -1, "what": "Отмечается на проходной", "dur": 4.0})
			break
	var rooms_left: Array = []
	for r in sim.rooms.list:
		rooms_left.append(r)
	var cur := Vector2i(sim.gate_x, w.plot.end.y - 2)
	while not rooms_left.is_empty() and stops.size() < 12:
		var best: Rooms.Room = null
		var bd := INF
		for r2: Rooms.Room in rooms_left:
			var dd := Vector2(cur).distance_to(r2.center)
			if dd < bd:
				bd = dd
				best = r2
		rooms_left.erase(best)
		var c := _stand_cell(best)
		if c.x < 0:
			continue
		stops.append({"cell": [c.x, c.y], "room": best.id, "what": "Осматривает: " + best.title().to_lower(), "dur": sim.rng.randf_range(3.0, 5.0)})
		cur = c
	# уличные нарушения (захламление, лом)
	var office_r: Rooms.Room = null
	for r3 in sim.rooms.list:
		if Rooms.OFFICE_TYPES.has(r3.type):
			office_r = r3
			break
	var oc := _stand_cell(office_r) if office_r else Vector2i(sim.gate_x, w.plot.end.y - 2)
	oc = w.nearest_passable(oc)
	stops.append({"cell": [oc.x, oc.y], "room": -2, "what": "Оформляет акт" if not VISIT_KINDS.has(t) else "Беседует с руководством", "dur": 10.0})
	return stops


func _stand_cell(r: Rooms.Room) -> Vector2i:
	if r == null:
		return Vector2i(-1, -1)
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in r.cells:
		if not sim.world.passable(c):
			continue
		var d := Vector2(c).distance_to(r.center)
		if d < bd:
			bd = d
			best = c
	return best


func _step(dt: float) -> void:
	var v := visitor()
	if v == null:
		visit.clear()
		return
	# 1.14: сопровождающий бросает дела и идёт рядом с инспектором
	var e := escort()
	if e and (e.task == null or e.task.kind != "escort") and not e.hidden:
		sim.brain.abort(e)
		sim.brain.assign(e, sim.brain.escort_task(e))
	var stops: Array = visit["stops"]
	var i := int(visit["i"])
	if str(visit["phase"]) == "leave":
		var r := sim.brain.move_to(v, v.exit_cell, dt)
		v.activity = "Уходит"
		if r != 0:
			_finish()
		return
	if i >= stops.size():
		visit["phase"] = "leave"
		return
	var st: Dictionary = stops[i]
	var target := Vector2i(int(st["cell"][0]), int(st["cell"][1]))
	if str(visit["phase"]) == "walk":
		v.activity = "Идёт по заводу"
		var res := sim.brain.move_to(v, target, dt)
		if res == 1:
			visit["phase"] = "look"
			visit["wait"] = float(st["dur"])
			v.anim = "idle"
			v.bubble = "inspect"
		elif res == -1:
			visit["i"] = i + 1
		return
	# осмотр
	v.activity = str(st["what"])
	v.anim = "idle"
	visit["wait"] = float(visit["wait"]) - dt
	if float(visit["wait"]) <= 0.0:
		v.bubble = ""
		_check_stop(int(st["room"]))
		visit["i"] = i + 1
		visit["phase"] = "walk"


## Осмотр точки маршрута: нарушения в этом помещении фиксируются (с учётом того, что уже исправили).
func _check_stop(room_id: int) -> void:
	var t := str(visit["type"])
	if VISIT_KINDS.has(t):
		return
	var found: Array = visit["found"]
	for vi: Dictionary in violations(t):
		var rid := int(vi.get("room", -1))
		var match_stop := rid == room_id or (room_id == -2 and (rid == -1 or bool(vi.get("global", false))))
		if not match_stop:
			continue
		var key := str(vi["key"]) + str(vi.get("text", ""))
		var dup := false
		for f: Dictionary in found:
			if str(f["key"]) + str(f.get("text", "")) == key:
				dup = true
				break
		if dup:
			continue
		found.append(vi)
		var c: Array = vi.get("cell", [-1, -1])
		var cell := Vector2i(int(c[0]), int(c[1]))
		if cell.x >= 0:
			marks.append({"cell": [cell.x, cell.y], "text": str(vi["text"]), "until": sim.minute + 6.0 * 1440.0, "type": t})
		sim.notify("Инспектор записал нарушение: %s." % str(vi["text"]), Sim.LVL_WARN, cell)


func _finish() -> void:
	var v := visitor()
	if v:
		sim.visitors.erase(v)
	var t := str(visit["type"])
	var found: Array = visit["found"]
	var rep: Array = visit.get("repeat", [])
	var why := str(visit.get("why", ""))
	var e0 := escort()
	_act_escort = e0.id if e0 else -1
	visit.clear()
	if VISIT_KINDS.has(t):
		_act_escort = -1
		_visit_result(t)
		return
	_act(t, found, rep, why)
	_act_escort = -1


func _desk_audit(t: String) -> void:
	var found: Array = []
	var acc := sim.office.active("accounting")
	var chance := 0.15 if acc else 0.65
	if sim.rng.randf() < chance:
		var sales := 0.0
		for wk: Dictionary in sim.office.weeks.slice(0, 4):
			sales += float(wk["cats"].get("sales", 0.0))
		var fine := maxf(20000.0, sales * 0.03) * (0.4 if acc else 1.0)
		found.append({"key": "books", "text": str(Defs.inspections["texts"]["books"]), "fine": fine, "global": true})
	_act(t, found, [], "камеральная")


## Малый бизнес (до «Малого предприятия» включительно): за первое нарушение — предупреждение
## вместо штрафа, как в ст. 4.1.1 КоАП. Повтор и скрытый несчастный случай — штраф.
func small_business() -> bool:
	return sim.progress.stage <= 3


func first_time(t: String, key: String) -> bool:
	return not (warned.get(t, []) as Array).has(key)


## Акт проверки: штрафы, репутация, предписание.
func _act(t: String, found: Array, repeat: Array, why: String) -> void:
	var fine := 0.0
	var lines: Array[String] = []
	var rep_keys: Array = []
	var worst_cell := Vector2i(-1, -1)
	var warns := 0
	var wl: Array = warned.get(t, [])
	for vi: Dictionary in found:
		if str(vi["key"]) == "n1_unfiled":
			sim.crew.on_hidden_found()
		var f := float(vi["fine"]) * fine_k()
		var vkey := str(vi["key"])
		if small_business() and vkey != "n1_unfiled" and not repeat.has(vkey) and not wl.has(vkey):
			wl.append(vkey)
			warns += 1
			lines.append("• %s — предупреждение" % str(vi["text"]))
			if not rep_keys.has(vkey):
				rep_keys.append(vkey)
			continue
		if not wl.has(vkey):
			wl.append(vkey)
		if repeat.has(str(vi["key"])):
			f *= float(Defs.inspections.get("repeat_k", 2.0))
			var c: Array = vi.get("cell", [-1, -1])
			if int(c[0]) >= 0:
				worst_cell = Vector2i(int(c[0]), int(c[1]))
		fine += f
		lines.append("• %s — %s" % [str(vi["text"]), Defs.money_str(f)])
		if not rep_keys.has(str(vi["key"])):
			rep_keys.append(str(vi["key"]))
	warned[t] = wl
	var name := type_name(t)
	history.push_front({"day": sim.day(), "type": t, "n": found.size(), "fine": fine, "why": why, "warns": warns})
	if history.size() > 30:
		history.resize(30)
	if found.is_empty():
		clean += 1
		sim.stats["clean_inspections"] = int(sim.stats.get("clean_inspections", 0)) + 1
		sim.reputation = minf(100.0, sim.reputation + 3.0)
		for w in sim.workers:
			Mood.add(sim, w, "inspection_ok")
		sim.story.info("Проверка без замечаний", "%s: нарушений не выявлено. Репутация завода растёт." % name, "inspect", Sim.LVL_GOOD, Vector2i(-1, -1), true)
		sim.paper.add("Проверки", "%s: без замечаний" % name, "Инспектор пожал руку и сказал: «Побольше бы таких предприятий». Молодцы!")
		return
	sim.reputation = maxf(0.0, sim.reputation - minf(5.0, float(found.size())))
	var due := sim.day() + int(Defs.inspections.get("prescription_days", 5))
	prescriptions.append({"type": t, "keys": rep_keys, "due": due})
	for m: Dictionary in marks:
		if str(m["type"]) == t:
			m["until"] = float(due) * 1440.0
	var esc := escort()
	var fixes: Array[String] = []
	for vf: Dictionary in found:
		var ft := fix_text(str(vf["key"]))
		if ft != "" and not fixes.has("• " + ft):
			fixes.append("• " + ft)
	var txt := "Выявлено %d %s:\n%s\n\nИтого штраф: %s. Предписание: устранить до %s, потом придут проверить снова. Повторное нарушение — двойной штраф и остановка участка." % [found.size(), Defs.plural(found.size(), "нарушение", "нарушения", "нарушений"), "\n".join(lines), Defs.money_str(fine), sim.season.date_str(due)]
	if fine <= 0.0:
		txt = "Выявлено %d %s:\n%s\n\nШтрафа нет: малому предприятию за впервые выявленное нарушение — предупреждение (ст. 4.1.1 КоАП). Предписание: устранить до %s, потом придут проверить снова. Не исправите — штраф вдвойне и остановка участка." % [found.size(), Defs.plural(found.size(), "нарушение", "нарушения", "нарушений"), "\n".join(lines), sim.season.date_str(due)]
	elif warns > 0:
		txt += "\n\nЗа впервые выявленные нарушения — предупреждение вместо штрафа (ст. 4.1.1 КоАП): малое предприятие."
	if not fixes.is_empty():
		txt += "\n\nКак исправить:\n" + "\n".join(fixes.slice(0, 5))
	if esc:
		txt += "\n\nИнспектора сопровождал%s %s (%s)%s." % ["а" if esc.female else "", esc.full_name(), esc.prof_lc(), " — штраф меньше на 15%" if esc.prof == "safety_engineer" else ""]
	if worst_cell.x >= 0:
		_suspend_room(worst_cell)
		txt += "\n\nНарушения повторились — участок остановлен на сутки."
	if fine <= 0.0:
		sim.story.letter("inspection_act", "Акт проверки: " + name, txt, str(tdef(t).get("icon", "inspect")), Sim.LVL_WARN,
			[{"text": "Понятно, устраним", "hint": ""}], 0, {"fine": 0.0, "type": t})
		sim.paper.add("Проверки", "%s: предупреждение" % name, "Инспектор нашёл %d %s, но на первый раз ограничился предупреждением. Срок исправить — до %s." % [found.size(), Defs.plural(found.size(), "нарушение", "нарушения", "нарушений"), sim.season.date_str(due)])
		return
	var appeal := float(Defs.inspections.get("appeal_cost", 15000))
	var ch: Array = [{"text": "Оплатить штраф (%s)" % Defs.money_str(fine), "hint": ""}]
	if sim.office.active("legal"):
		ch.append({"text": "Обжаловать в суде (%s, шанс %d%%)" % [Defs.money_str(float(appeal)), int(appeal_chance() * 100.0)], "hint": "Проиграете — штраф больше на 20%"})
	else:
		txt += "\n\nОбжаловать штраф может только юрист (Управление → Развитие → Юротдел)."
	sim.story.letter("inspection_act", "Акт проверки: " + name, txt, str(tdef(t).get("icon", "inspect")), Sim.LVL_BAD, ch, 0, {"fine": fine, "type": t})
	sim.paper.add("Проверки", "%s: %d %s" % [name, found.size(), Defs.plural(found.size(), "нарушение", "нарушения", "нарушений")], "Штраф %s. Руководство обещает всё исправить до %s." % [Defs.money_str(fine), sim.season.date_str(due)])


## Шанс выиграть суд: со своим юристом выше (1.10).
func appeal_chance() -> float:
	return 0.6 if sim.office.active("legal") else float(Defs.inspections.get("appeal_chance", 0.4))


func on_act_choice(d: Dictionary, choice: int) -> void:
	var fine := float(d.get("fine", 0.0))
	var name := type_name(str(d.get("type", "")))
	if fine <= 0.0:
		return
	if choice == 0:
		sim.spend(fine, "Штраф: " + name)
		return
	sim.spend(float(Defs.inspections.get("appeal_cost", 15000)), "Юристы: обжалование штрафа")
	if sim.rng.randf() < appeal_chance():
		sim.story.info("Суд отменил штраф", "Юристы нашли ошибки в акте: %s, штраф %s отменён." % [name, Defs.money_str(fine)], "court", Sim.LVL_GOOD)
	else:
		sim.spend(fine * 1.2, "Штраф: %s (с судебными издержками)" % name)
		sim.story.info("Суд проигран", "Суд оставил штраф в силе и добавил издержки: %s." % Defs.money_str(fine * 1.2), "court", Sim.LVL_BAD)


func _suspend_room(c: Vector2i) -> void:
	var r := sim.rooms.room_at(c)
	if r == null:
		return
	for tid in r.things:
		var t: Thing = sim.things.get(tid)
		if t and t.kind() == "machine":
			suspended[t.id] = sim.minute + 1440.0
	for w in sim.workers:
		Mood.add(sim, w, "suspended")


## Губернатор и журналист оценивают порядок на заводе.
func order_score() -> Dictionary:
	var score := 50.0
	var notes: Array[String] = []
	var rooms_n := sim.rooms.list.size()
	var valid := 0
	for r in sim.rooms.list:
		if r.type != "" and r.valid:
			valid += 1
	if rooms_n > 0:
		score += 15.0 * valid / rooms_n
	var ground := sim.ground_items.size()
	if ground > 6:
		score -= minf(20.0, ground * 0.8)
		notes.append("грузы валяются на полу")
	var broken := 0
	for m in sim.things_of("machine"):
		if m.broken:
			broken += 1
	if broken > 0:
		score -= broken * 7.0
		notes.append("стоят сломанные станки")
	var ms := 0.0
	for w in sim.workers:
		ms += w.mood
	var avg := ms / maxf(1.0, sim.workers.size())
	score += (avg - 50.0) * 0.4
	if avg < 35.0:
		notes.append("люди хмурые")
	if not marks.is_empty():
		score -= 8.0
		notes.append("не устранены нарушения")
	if sim.story.strike.get("active", false):
		score -= 30.0
		notes.append("бастуют")
	if sim.season.snow_avg > 80.0:
		score -= 6.0
		notes.append("территория в сугробах")
	if not sim.rooms.of_type("canteen").is_empty():
		score += 5.0
	return {"score": score, "notes": notes, "mood": avg}


func _visit_result(kind: String) -> void:
	var r := order_score()
	var sc := float(r["score"])
	var notes: Array = r["notes"]
	var bad := ", ".join(PackedStringArray(notes))
	if kind == "governor":
		if sc >= 60.0:
			var grant := snappedf(sim.rng.randf_range(100000.0, 200000.0), 10000.0)
			sim.earn(grant, "Оплата: областная субсидия по итогам визита губернатора")
			sim.reputation = minf(100.0, sim.reputation + 5.0)
			for w in sim.workers:
				Mood.add(sim, w, "governor_visit")
			sim.story.info("Губернатор доволен", "«Вот на таких предприятиях держится область!» Выделена субсидия %s, репутация выросла." % Defs.money_str(grant), "goals", Sim.LVL_GOOD, Vector2i(-1, -1), true)
			sim.paper.add("Главное", "Губернатор посетил наш завод", "Глава области осмотрел цеха, пообщался с рабочими и пообещал поддержку. Субсидия уже на счёте!")
		elif sc >= 42.0:
			sim.reputation = minf(100.0, sim.reputation + 1.0)
			sim.story.info("Губернатор уехал", "«Работайте, развивайтесь». Без восторгов, но и без претензий%s." % ((" — заметил, что " + bad) if bad != "" else ""), "goals", Sim.LVL_INFO, Vector2i(-1, -1), true)
		else:
			sim.reputation = maxf(0.0, sim.reputation - 4.0)
			sim.story.info("Губернатор недоволен", "«Бардак!» Губернатор заметил, что %s. Репутация упала." % (bad if bad != "" else "всё не так"), "goals", Sim.LVL_BAD, Vector2i(-1, -1), true)
	else:
		if sc >= 55.0:
			sim.reputation = minf(100.0, sim.reputation + 4.0)
			sim.story.info("Хорошая статья", "В областной газете вышел очерк «Гаражный цех растёт»: о людях, станках и заказах. Репутация выросла, работники охотнее идут к вам.", "press", Sim.LVL_GOOD, Vector2i(-1, -1), true)
			sim.paper.add("Пресса о нас", "О нас написали в области", "Перепечатываем с гордостью: «Здесь работают с огоньком и без брака».")
		else:
			sim.reputation = maxf(0.0, sim.reputation - 3.0)
			sim.story.info("Разгромная статья", "Журналист написал фельетон «Промзона без прикрас»: %s. Репутация упала." % (bad if bad != "" else "порядка нет"), "press", Sim.LVL_BAD, Vector2i(-1, -1), true)


# ================================================================ правила

func _v(t: String, key: String, cell: Vector2i, room: int, fmt_args: Array = [], global := false, fine_mul := 1.0) -> Dictionary:
	var texts: Dictionary = Defs.inspections.get("texts", {})
	var tx := str(texts.get(key, key))
	if not fmt_args.is_empty() and tx.contains("%"):
		tx = tx % fmt_args
	var rules: Dictionary = tdef(t).get("rules", {})
	return {"key": key, "text": tx, "fine": float(rules.get(key, 10000)) * fine_mul, "cell": [cell.x, cell.y], "room": room, "global": global, "fix": fix_text(key)}


## 1.20: что сделать, чтобы нарушение ушло — простыми словами, с путём по меню.
static func fix_text(key: String) -> String:
	return str((Defs.inspections.get("fix", {}) as Dictionary).get(key, ""))


## 1.16: построенные станки передела (печи ТВЧ не дымят — smoke = false).
func _machines(process: String, smoky: bool = false) -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.built and t.kind() == "machine" and t.process() == process:
			if smoky and not bool(t.machine_def().get("smoke", true)):
				continue
			out.append(t)
	return out


func _things(def_id: String) -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.built and t.def_id == def_id:
			out.append(t)
	return out


func _room_count(r: Rooms.Room, def_id: String) -> int:
	var n := 0
	for tid in r.things:
		var t: Thing = sim.things.get(tid)
		if t and t.built and t.def_id == def_id:
			n += 1
	return n


func _cell_of_room(r: Rooms.Room) -> Vector2i:
	var c := _stand_cell(r)
	return c if c.x >= 0 else r.cells[0]


## Все нарушения по типу проверки прямо сейчас.
const WET_ROOMS := ["wc", "shower"]


func violations(t: String) -> Array:
	var out: Array = []
	var none := Vector2i(-1, -1)
	match t:
		"fire":
			var hot := sim.story.hot_machines()
			# огнетушители и выходы — на помещение-постройку целиком (все его зоны)
			var need_ext := 0
			for sp in sim.rooms.spaces:
				if sp.cells.size() < 6:
					continue
				var r := sim.rooms.space_main(sp.id)
				if r == null:
					continue
				if r.type in WET_ROOMS:
					continue   # 1.15: в туалете и душевой огнетушитель не требуют
				need_ext += 1
				var ext := sim.rooms.space_count(sp.id, "extinguisher")
				if ext == 0:
					out.append(_v(t, "no_ext", _cell_of_room(r), r.id, [r.title()]))
				else:
					var has_hot := false
					for m in hot:
						if sim.rooms.space_of_thing(m) == sp.id:
							has_hot = true
							break
					if has_hot and ext < 2:
						out.append(_v(t, "hot_ext", _cell_of_room(r), r.id, [r.title()]))
				if sp.cells.size() >= 60 and sp.doors < 2:
					out.append(_v(t, "one_exit", _cell_of_room(r), r.id, [r.title()]))
			if sim.power.any_tripped():
				out.append(_v(t, "wiring", none, -1, [], true))
			if sim.ground_items.size() >= 12:
				var it: Item = sim.items.get(sim.ground_items[0])
				var c := it.cell if it else none
				var rr := sim.rooms.room_at(c)
				out.append(_v(t, "clutter", c, rr.id if rr else -1))
			if sim.story.has_mod("fire_recent") and _things("extinguisher").size() < maxi(1, need_ext):
				out.append(_v(t, "fire_recent", none, -1, [], true))
		"labor":
			var low: Array[String] = []
			var mw := float(Defs.inspections.get("min_wage_shift", 1900))
			for w in sim.workers:
				if float(w.wage) < mw:
					low.append(w.full_name())
			if not low.is_empty():
				out.append(_v(t, "min_wage", none, -1, [", ".join(PackedStringArray(low.slice(0, 3)))], true, float(mini(low.size(), 3))))
			var rab := 0
			for w2 in sim.workers:
				if not w2.is_itr():
					rab += 1
			if rab >= 2 and (_things("locker").size() + 2 * _things("locker2").size()) * 2 < rab:
				out.append(_v(t, "no_ppe", none, -1, [], true))
			if sim.workers.size() >= 3 and _things("first_aid").is_empty():
				out.append(_v(t, "no_aid", none, -1, [], true))
			if sim.office.rush_on() or sim.office.overtime_on() or sim.story.has_mod("rush"):
				out.append(_v(t, "overwork", none, -1, [], true))
			var inj := sim.story.injuries_month()
			if inj >= 2:
				out.append(_v(t, "injuries", none, -1, [inj], true))
			if sim.rooms.of_type("wc").is_empty():
				out.append(_v(t, "no_wc", none, -1, [], true))
			if rab >= 6 and not sim.training.tb_valid():
				out.append(_v(t, "no_tb", none, -1, [], true))
			var nos := sim.eng.unassessed()
			if rab >= 4 and nos > 0:
				out.append(_v(t, "no_sout", none, -1, [nos], true))
			if sim.eng.entitled_count() > 0 and not sim.eng.milk_on:
				out.append(_v(t, "no_milk", none, -1, [], true))
			if sim.crew.lunch_violation():
				out.append(_v(t, "no_lunch", none, -1, [], true))
			if sim.crew.hidden_cases() > 0:
				out.append(_v(t, "n1_unfiled", none, -1, [], true, float(sim.crew.hidden_cases())))
			var bare := sim.eng.without_ppe()
			if not bare.is_empty():
				var bn: Array[String] = []
				for bw in bare.slice(0, 3):
					bn.append(bw.full_name())
				out.append(_v(t, "ppe_worn", none, -1, [", ".join(PackedStringArray(bn))], true, float(mini(bare.size(), 3))))
		"sanitary":
			var toilets := _things("toilet")
			if toilets.is_empty():
				out.append(_v(t, "no_wc", none, -1, [], true))
			elif _things("sink").is_empty():
				var tc := toilets[0].cell
				var tr := sim.rooms.room_at(tc)
				out.append(_v(t, "no_sink", tc, tr.id if tr else -1))
			if sim.workers.size() >= 8 and sim.rooms.of_type("canteen").is_empty():
				out.append(_v(t, "no_canteen", none, -1, [], true))
			if not toilets.is_empty() and toilets.size() * 12 < sim.workers.size():
				out.append(_v(t, "few_wc", none, -1, [], true))
			var junk := 0
			var jc := none
			for gid in sim.ground_items:
				var it2: Item = sim.items.get(gid)
				if it2 and sim.rooms.room_at(it2.cell) == null:
					junk += 1
					jc = it2.cell
			if junk >= 8:
				out.append(_v(t, "garbage", jc, -1))
			var worst: Rooms.Room = null
			var wd := Upkeep.DIRTY * 1.3
			for r in sim.rooms.list:
				var rd := sim.upkeep.room_dirt(r)
				if r.type != "" and rd > wd:
					wd = rd
					worst = r
			if worst:
				out.append(_v(t, "dirty_room", _cell_of_room(worst), worst.id, [worst.title()]))
			# 1.22: грызуны
			if sim.fauna and not sim.fauna.mice.is_empty():
				var mr := int((sim.fauna.mice[0] as Dictionary)["room"])
				if mr >= 0 and mr < sim.rooms.list.size():
					var mroom: Rooms.Room = sim.rooms.list[mr]
					out.append(_v(t, "mice", _cell_of_room(mroom), mroom.id, [mroom.title()]))
			var smoky: Rooms.Room = null
			var sf := 40.0
			for r2 in sim.rooms.list:
				if not sim.eng.needs_vent(r2):
					continue
				var ef := sim.eng.eq_fumes(r2)
				if ef > sf:
					sf = ef
					smoky = r2
			if smoky:
				out.append(_v(t, "no_vent", _cell_of_room(smoky), smoky.id, [smoky.title()]))
		"tech":
			var worn_n := 0
			for m in sim.things_of("machine"):
				var rm := sim.rooms.room_of_thing(m)
				if m.broken:
					out.append(_v(t, "broken_long", m.cell, rm.id if rm else -1, [m.title()]))
				elif m.enabled and m.condition < 25.0 and worn_n < 3:
					worn_n += 1
					out.append(_v(t, "worn", m.cell, rm.id if rm else -1, [m.title()]))
			var haul_max := 0
			var has_el := false
			for w3 in sim.workers:
				haul_max = maxi(haul_max, w3.skill("haul"))
				if w3.prof == "electrician":
					has_el = true
			for cr in _things("crane"):
				if haul_max < 4:
					var rc := sim.rooms.room_of_thing(cr)
					out.append(_v(t, "crane", cr.cell, rc.id if rc else -1))
					break
			for fl in _things("forklift"):
				if haul_max < 3:
					var rf := sim.rooms.room_of_thing(fl)
					out.append(_v(t, "forklift", fl.cell, rf.id if rf else -1))
					break
			if sim.power.total_kw() > 20.0 and not has_el:
				out.append(_v(t, "no_electrician", none, -1, [], true))
		"ecology":
			var scrap_ground := 0
			for gid2 in sim.ground_items:
				var it3: Item = sim.items.get(gid2)
				if it3 and it3.kind == "part" and it3.q == "scrap":
					scrap_ground += 1
			var full_bin := false
			var bin_cell := none
			for b in _things("scrap_bin"):
				if sim.count_slot(b, 0) >= b.slot_cap(0):
					full_bin = true
					bin_cell = b.cell
			if scrap_ground >= 5 or full_bin:
				var rb := sim.rooms.room_at(bin_cell)
				out.append(_v(t, "scrap_heap", bin_cell, rb.id if rb else -1))
			for pb in _machines("paint"):
				var rp := sim.rooms.room_of_thing(pb)
				var mixed := rp == null
				if rp:
					for tid in rp.things:
						var o: Thing = sim.things.get(tid)
						if o and o.kind() == "machine" and o.process() != "paint":
							mixed = true
							break
				if mixed:
					out.append(_v(t, "paint_room", pb.cell, rp.id if rp else -1))
			for fu in _machines("heat", true):
				var rfu := sim.rooms.room_of_thing(fu)
				if rfu and rfu.windows == 0 and not sim.eng.ventilated(rfu):
					out.append(_v(t, "furnace_smoke", fu.cell, rfu.id))
		"military":
			if not sim.story.has_checkpoint():
				out.append(_v(t, "no_regime", none, -1, [], true))
			if _things("qc_table").is_empty():
				out.append(_v(t, "no_qc", none, -1, [], true))
			if _things("test_stand").is_empty():
				out.append(_v(t, "no_test", none, -1, [], true))
			var hist: Array = sim.progress.history
			if hist.size() >= 2:
				var a0: Dictionary = hist[maxi(0, hist.size() - 14)]
				var b0: Dictionary = hist[-1]
				var made := int(b0["made"]) - int(a0["made"])
				var scr := int(b0["scrap"]) - int(a0["scrap"])
				if made + scr >= 10 and float(scr) / float(made + scr) > 0.08:
					out.append(_v(t, "scrap_rate", none, -1, [int(round(100.0 * scr / float(made + scr)))], true))
	return out


## Список требований по типу проверки — для окна «События» (подготовка).
func checklist(t: String) -> Array:
	match t:
		"fire":
			return ["Огнетушитель в каждом помещении от 6 клеток", "В горячих цехах (печь, покраска, сварка) — два огнетушителя", "В помещениях от 60 клеток — минимум два выхода", "Сеть без выбитых автоматов", "Не больше 12 грузов на полу"]
		"labor":
			return ["Ставка не ниже %s за смену" % Defs.money_str(float(Defs.inspections.get("min_wage_shift", 1900))), "Шкафчики для спецовки (хотя бы один на двоих)", "Аптечка на заводе", "Без авралов и сверхурочных", "Не больше одной травмы за месяц", "Туалет с раковиной", "Инструктаж по охране труда не реже раза в %d дней (если рабочих 6 и больше)" % Training.TB_DAYS,
				"СОУТ на всех рабочих местах (если рабочих 4 и больше)", "Молоко тем, у кого место вредное по СОУТ", "У всех рабочих целые СИЗ (шкаф СИЗ и комплекты)"]
		"sanitary":
			return ["Туалет и раковина", "Столовая, если людей 8 и больше", "Один туалет на 12 человек", "Территория без мусора и брака", "В помещениях убрана стружка (уборщица или разнорабочие)", "Вентиляция там, где сварка, покраска или печь: воздух не хуже 40%"]
		"tech":
			return ["Нет сломанных станков", "Нет станков в работе с износом ниже 25%", "Для кран-балки — стропальщик (погрузка 4+)", "Для погрузчика — водитель (погрузка 3+)", "При своей подстанции или повышенной мощности — электрик в штате"]
		"ecology":
			return ["Брак не копится: тара не переполнена, на полу не больше 5 бракованных деталей", "Покрасочная камера — в отдельном помещении", "У печи — окна или вентиляция"]
		"tax":
			return ["Бухгалтерия (отдел) снижает риск штрафа в 4 раза"]
		"military":
			return ["Режим: проходная с вахтой", "Стол ОТК", "Испытательный стенд", "Брак не больше 8% за две недели"]
	return []


# ================================================================ сохранение

func to_dict() -> Dictionary:
	var vd := {}
	if not visit.is_empty():
		vd = {"type": visit["type"], "why": visit.get("why", ""), "repeat": visit.get("repeat", [])}
	return {"queue": queue, "visit": vd, "marks": marks, "presc": prescriptions, "hist": history,
		"due": next_due, "clean": clean, "total": total, "susp": _str_keys(suspended), "warned": warned}


func _str_keys(d: Dictionary) -> Dictionary:
	var o := {}
	for k in d.keys():
		o[str(k)] = d[k]
	return o


func from_dict(d: Dictionary) -> void:
	queue = d.get("queue", [])
	marks = d.get("marks", [])
	prescriptions = d.get("presc", [])
	history = d.get("hist", [])
	next_due = d.get("due", {})
	for k in next_due.keys():
		next_due[k] = int(next_due[k])
	warned = d.get("warned", {})
	clean = int(d.get("clean", 0))
	total = int(d.get("total", 0))
	suspended.clear()
	var sd: Dictionary = d.get("susp", {})
	for k2 in sd.keys():
		suspended[int(k2)] = float(sd[k2])
	# незаконченный визит начинается заново (инспектор снова приходит через проходную)
	var vd: Dictionary = d.get("visit", {})
	if not vd.is_empty():
		queue.push_front({"type": str(vd["type"]), "at": 0.0, "announced": false, "why": str(vd.get("why", "")), "repeat": vd.get("repeat", [])})
