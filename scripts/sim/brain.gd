class_name Brain
extends RefCounted
## Поведение рабочих: смены, потребности, выбор работы, выполнение шагов задачи.

const SERVICE_AT := 50.0  ## ниже этого состояния станок отправляют на обслуживание

const WORK_KINDS := ["haul", "build", "operate", "inspect", "office", "study"]

var sim: Sim




var _idle: Dictionary = {}   ## 1.23: кто в последний раз не нашёл работы (id → true)


func _init(s: Sim) -> void:
	sim = s


func tick(dt: float) -> void:
	for w in sim.workers.duplicate():
		_tick_worker(w, dt)


# ================================================================ основной цикл

## Где человек, если не на смене: «на больничном» → «На больничном» (away_why хранится по-русски).
static func _away_text(why: String) -> String:
	if not L.is_en():
		return why.capitalize()
	var t := L.t(why)
	return t.left(1).to_upper() + t.substr(1)


func _tick_worker(w: Worker, dt: float) -> void:
	var m := sim.minute
	var win := sim.shift_window(w, m)
	if win.x != w.shift_anchor:
		_new_shift(w, win)
		if sim.get_worker(w.id) != w:
			return  # уволился
	if not w.present:
		if w.sick_until > m:
			w.activity = _away_text(w.away_why) if w.away_why != "" else L.t("Не вышел на работу")
			return
		if w.skip_shift:
			w.activity = L.t("Не вышел на работу")
			if m >= win.x and int(w.get_meta("skip_note", -1)) != int(win.x):
				w.set_meta("skip_note", int(win.x))
				var why := L.t(str(w.get_meta("skip_why", "плохое настроение")))
				sim.notify(Nicks.gendered(L.t("%s не вышел{|а} на смену: %s."), w.female) % [w.full_name(), why], Sim.LVL_WARN)
		else:
			w.activity = L.t("Дома")
		if sim.shift_is_workday(win) and not w.skip_shift and w.gone_anchor != win.x \
				and m >= win.x + w.arrive_off and m < win.y - 30.0:
			_spawn(w)
		return
	_decay(w, dt)
	var mcd := float(w.get_meta("mood_cd", 0.0)) - dt
	if mcd <= 0.0:
		mcd = 5.0
		Mood.refresh(sim, w)
	w.set_meta("mood_cd", mcd)
	var off_shift := m >= win.y or m < win.x - 120.0 or not sim.shift_is_workday(win)
	if off_shift:
		if w.task == null or w.task.kind != "go_home":
			abort(w)
			if not sim.world.reachable(w.cell(), w.exit_cell):
				# заперт в помещении без выхода: ждём двери, потом «уходит через окно»
				var trap := float(w.get_meta("trap", 0.0)) + dt
				w.set_meta("trap", trap)
				w.activity = L.t("Заперт: нет выхода")
				w.anim = "idle"
				sim.notify_once("trap%d" % w.id, L.t("%s не может уйти домой: помещение без выхода. Поставьте дверь!") % w.full_name(), Sim.LVL_BAD, w.cell(), 600.0)
				if trap > 90.0:
					w.set_meta("trap", 0.0)
					w.dressed = false
					_despawn(w)
				return
			w.set_meta("trap", 0.0)
			_go_home(w)
	elif w.task == null or w.task.kind == "wander":
		w.think_cd -= dt
		if w.task == null or w.think_cd <= 0.0:
			w.think_cd = 1.5
			var nt := _choose(w)
			if nt == null:
				# 1.22: работы нет — следующий раз думать чуть позже (раньше каждые 1,5 мин — 90% впустую)
				# 1.23: когда без дела стоят многие, каждый думает ещё реже — работы на всех всё равно нет,
				# а поиск — самое дорогое в ходе (на 300 человек — 9 из 10 мс). На маленьком заводе ничего не меняется.
				_idle[w.id] = true
				if _idle.size() > sim.workers.size():
					for k: int in _idle.keys():
						if sim.get_worker(k) == null:
							_idle.erase(k)
				w.think_cd = 2.5 + float(w.id % 5) * 0.1 + clampf(float(_idle.size() - 8) * 0.06, 0.0, 9.0)
			else:
				_idle.erase(w.id)
			if nt:
				abort(w)
				assign(w, nt)
			elif w.task == null:
				_wander(w)
	elif _emergency(w, dt):
		pass
	elif w.needs["bladder"] < 12.0 and WORK_KINDS.has(w.task.kind) and w.carrying < 0:
		var tt := _toilet_task(w)
		if tt:
			abort(w)
			assign(w, tt)
	elif w.task.kind in ["haul", "operate", "inspect"] and w.carrying < 0 and w.carry_extra.is_empty() \
			and str(w.task.current().get("t", "")) == "goto" \
			and int(w.get_meta("tea", -1)) != int(w.shift_anchor) and sim.crew.slot(w) == "break":
		# перерыв по графику: кто только идёт к работе с пустыми руками — бросает и идёт пить чай
		var bt := _break_task(w)
		if bt:
			abort(w)
			assign(w, bt)
	elif w.mentor >= 0 and w.task.kind != "shadow" and w.carrying < 0 and w.carry_extra.is_empty() \
			and (WORK_KINDS.has(w.task.kind) or SHADOW_KINDS.has(w.task.kind)) and str(w.task.current().get("t", "")) == "goto":
		# 1.40: ученик идёт по своему делу, а наставник работает в стороне — бросает и идёт к нему
		var mt := sim.training.mentor_of(w)
		if mt and mt.present and not mt.hidden and mt.shift == w.shift and _shadowable(mt) and mt.pos.distance_to(w.pos) > 4.0:
			var sht := _shadow_task(w)
			if sht:
				abort(w)
				assign(w, sht)
	if w.task:
		_run(w, dt)


## Пожар или забастовка: бросить текущее дело (проверка не чаще раза в 2 минуты).
func _emergency(w: Worker, dt: float) -> bool:
	var cd := float(w.get_meta("emerg_cd", 0.0)) - dt
	if cd > 0.0:
		w.set_meta("emerg_cd", cd)
		return false
	w.set_meta("emerg_cd", 2.0)
	var k := w.task.kind
	if k == "go_home" or k == "extinguish" or k == "strike" or w.carrying >= 0:
		return false
	if not sim.story.fires.is_empty() and not w.is_itr():
		var ft := _fire_task(w)
		if ft:
			abort(w)
			assign(w, ft)
			return true
	if sim.story.striking(w) and not ["toilet", "eat", "dress"].has(k):
		abort(w)
		assign(w, _strike_task(w))
		return true
	return false


## Начинается новая смена работника: сброс обеда, решение о прогуле, проверка на увольнение.
func _new_shift(w: Worker, win: Vector2) -> void:
	w.shift_anchor = win.x
	w.ate_today = false
	w.skip_shift = false
	if w.sick_until > win.x:
		w.skip_shift = true
		w.set_meta("skip_note", int(win.x))
		if sim.shift_is_workday(win) and w.away_why == "на больничном":
			w.set_meta("wage_due", float(w.get_meta("wage_due", 0.0)) + float(w.wage) * 0.6)
		return
	if w.away_why != "":
		w.away_why = ""
		w.bubble = ""
		w.add_history(sim.day(), Nicks.gendered(L.t("Вернул{ся|ась} на работу"), w.female))
	if Mood.has_trait(w, "early_bird"):
		w.arrive_off = -sim.rng.randf_range(35.0, 70.0)
	else:
		w.arrive_off = -sim.rng.randf_range(5.0, 45.0)
	if sim.town.is_resident(w):
		w.arrive_off = -sim.rng.randf_range(15.0, 30.0)   # живёт рядом: не опаздывает
	if not sim.shift_is_workday(win):
		return
	Mood.refresh(sim, w)
	if w.is_director():
		return   # 1.40: директор не прогуливает и не увольняется
	var weekday := int(win.x / 1440.0) % 7
	var drink := trait_f(w, "absent_monday")
	var abs_k := sim.office.absence_k(w)
	if weekday == 0 and drink > 0.0 and sim.rng.randf() < drink * abs_k:
		w.skip_shift = true
		w.set_meta("skip_why", "«приболел» после выходных")
		w.set_meta("absences", int(w.get_meta("absences", 0)) + 1)
		Mood.add(sim, w, "overtime_drink")
	elif w.mood < Defs.b("absent_mood") and sim.rng.randf() < 0.35 * abs_k:
		w.skip_shift = true
		w.set_meta("skip_why", "«плохо себя чувствую» — на деле плохое настроение")
		w.set_meta("absences", int(w.get_meta("absences", 0)) + 1)
	elif sim.town.kid_absent(w):
		w.skip_shift = true
		w.set_meta("skip_why", "сидит с ребёнком — в садик не взяли")
	if w.mood < Defs.b("quit_mood"):
		w.low_mood_days += 1
	else:
		w.low_mood_days = 0
	if w.low_mood_days >= int(Defs.b("quit_days")):
		sim.fire(w, true)
	elif w.low_mood_days == int(Defs.b("quit_days")) - 1:
		sim.notify(L.t("%s на грани увольнения: настроение %d. Посмотрите его мысли в карточке.") % [w.full_name(), int(w.mood)], Sim.LVL_BAD)


## Числовое значение черты (сумма по всем чертам) — для вероятностей и сдвигов.
func trait_f(w: Worker, key: String) -> float:
	return Mood.trait_val(w, key, 0.0)


func _on_lunch(w: Worker) -> bool:
	return sim.crew.slot(w) == "lunch"


func _lunch_end(w: Worker) -> float:
	return sim.crew.block_end(w)


## Скорость работы: настроение, черты, освещение.
func _speed(w: Worker) -> float:
	var k := Mood.productivity(w) * sim.office.speed_k(w) * sim.season.work_k(w) * sim.training.speed_k(w) * sim.eng.speed_k(w) * sim.crew.speed_k(w)
	if not sim.rooms.is_lit(w.cell()):
		k *= 0.7
		Mood.add(sim, w, "dark")
	return k


func assign(w: Worker, t: Task) -> void:
	w.task = t
	w.activity = t.label
	w.prop = str(t.data.get("prop", ""))
	w.bubble = str(t.data.get("bubble", ""))
	w.path.clear()
	w.path_target = Vector2i(-999, -999)


func _decay(w: Worker, dt: float) -> void:
	w.needs["food"] = maxf(0.0, float(w.needs["food"]) - Defs.b("food_decay") * Mood.trait_val(w, "food_k", 1.0) * dt)
	var bl := maxf(0.0, float(w.needs["bladder"]) - Defs.b("bladder_decay") * dt)
	if bl <= 0.0 and float(w.needs["bladder"]) > 0.0:
		Mood.add(sim, w, "held_it")
	w.needs["bladder"] = bl
	var rd := Defs.b("rest_decay_working") if w.anim == "work" else Defs.b("rest_decay")
	rd *= Mood.trait_val(w, "rest_decay_k", 1.0) * sim.office.rest_k() * (1.3 if sim.office.rush_on() and not w.is_itr() else 1.0)
	if w.anim != "sit":
		rd *= sim.career.rest_k(w)   # 1.15: с возрастом устают быстрее
	if w.anim == "sit":
		rd = -0.9 if bool(w.get_meta("on_sofa", false)) else -0.6
	w.needs["rest"] = clampf(float(w.needs["rest"]) - rd * dt, 0.0, 100.0)


func _spawn(w: Worker) -> void:
	w.present = true
	w.pos = Vector2(w.exit_cell) + Vector2(0.5, 0.5)
	w.needs = {"food": sim.rng.randf_range(80.0, 100.0), "bladder": sim.rng.randf_range(65.0, 100.0), "rest": sim.rng.randf_range(85.0, 100.0)}
	w.task = null
	w.carrying = -1
	w.hidden = false
	w.dressed = w.is_itr()   # ИТР приходят в костюме, спецовка не нужна
	w.activity = L.t("Пришёл на смену")
	w.days_worked += 1
	w.last_smoke = sim.minute - sim.rng.randf_range(0.0, 60.0)
	var pay := float(w.wage) * (1.0 + (Defs.b("night_bonus") if w.shift == 1 else 0.0))
	if sim.office.overtime_on() and not w.is_itr():
		pay *= 1.0 + Defs.b("overtime_min") / 480.0 * Defs.b("overtime_pay")
	pay *= 1.0 + sim.eng.harm_bonus(w)
	pay = pay * sim.crew.pay_k(w) + sim.crew.pay_add(w)
	w.set_meta("wage_due", float(w.get_meta("wage_due", 0.0)) + pay)
	sim.eng.on_spawn(w)
	Mood.refresh(sim, w)


func _go_home(w: Worker) -> void:
	sim.crew.try_steal(w)
	var t := Task.new()
	t.kind = "go_home"
	t.label = L.t("Идёт домой")
	if w.dressed and not w.is_itr():
		# 1.14: после грязной работы — в душ, если он есть
		if DIRTY_PROFS.has(w.prof):
			var sh := _free_shower(w)
			if sh:
				sh.spot_users[0] = w.id
				t.res_spots.append([sh.id, 0])
				t.label = L.t("Моется в душе после смены")
				t.add({"t": "goto", "cell": sh.cell, "face": "down"})
				t.add({"t": "work", "what": "shower", "thing": sh.id, "dur": 6.0, "anim": "hidden"})
			elif sim.progress.stage >= 2 or not sim.things_of("shower").is_empty():
				Mood.add(sim, w, "no_shower")
		var lk := _locker_for(w)
		var acc := _locker_spot(lk, w) if lk else Vector2i(-1, -1)
		if acc.x >= 0:
			if t.label == L.t("Идёт домой"):
				t.label = L.t("Переодевается после смены")
			t.add({"t": "goto", "cell": acc, "face": "up"})
			t.add({"t": "work", "what": "undress", "dur": 4.0, "anim": "work"})
		else:
			t.add({"t": "work", "what": "undress", "dur": 2.0, "anim": "idle"})
	t.add({"t": "goto", "cell": w.exit_cell})
	t.add({"t": "despawn"})
	assign(w, t)


const DIRTY_PROFS := ["turner", "miller", "welder", "heat_treater", "caster", "presser", "painter", "assembler", "fitter", "laborer", "builder", "setter", "electrician"]


## Свободная душевая кабина в душевой, с водой.
func _free_shower(w: Worker) -> Thing:
	var best: Thing = null
	var bd := INF
	for th in sim.usable_of("shower"):
		if th.demolish or th.spot_users.has(0) or not sim.water.has_water(th):
			continue
		var d := _dist(th.cell, w.cell()) + sim.areas.pref(w, th, "shower")
		if d < bd and sim.world.reachable(w.cell(), th.cell):
			bd = d
			best = th
	return best


## Сопровождать инспектора (1.14): идти на шаг позади, пока он на заводе.
func escort_task(w: Worker) -> Task:
	var t := Task.new()
	t.kind = "escort"
	t.label = L.t("Сопровождает инспектора")
	t.data["prop"] = "folder"
	t.add({"t": "follow"})
	return t


## Инструктаж по охране труда (1.14): ведущий стоит у доски лицом к людям и рассказывает.
func _brief_task(w: Worker) -> Task:
	var spot := sim.training.tb_spot()
	if spot.x < 0 or not sim.world.reachable(w.cell(), spot):
		return null
	var t := Task.new()
	t.kind = "brief"
	t.label = L.t("Проводит инструктаж по охране труда")
	t.data["prop"] = "folder"
	t.data["bubble"] = "talk"
	t.add({"t": "goto", "cell": spot, "face": "down"})
	t.add({"t": "work", "what": "brief", "dur": 30.0, "anim": "talk"})
	return t


## Отправить домой посреди смены (травма): без переодевания, сразу к выходу.
func send_home(w: Worker, label: String) -> void:
	abort(w)
	var t := Task.new()
	t.kind = "go_home"
	t.label = label
	t.add({"t": "goto", "cell": w.exit_cell})
	t.add({"t": "despawn"})
	assign(w, t)
	w.set_meta("emerg_cd", 9999.0)


func _despawn(w: Worker) -> void:
	sim.crew.on_exit(w)
	abort(w)
	var win := sim.shift_window(w)
	if sim.minute >= win.x - 120.0 and sim.minute < win.y:
		w.gone_anchor = win.x
	w.present = false
	w.gone_today = true
	w.dressed = false
	w.activity = L.t("Дома")
	w.anim = "idle"
	if w.pending_shift >= 0:
		w.shift = w.pending_shift
		w.pending_shift = -1
		w.shift_anchor = -1.0
		w.gone_anchor = -1.0


## Закреплённый шкафчик (или свободный — закрепляем). Предпочтение — шкафчики в бытовке.
func _locker_for(w: Worker) -> Thing:
	var cur: Thing = sim.things.get(w.locker_id)
	var lr := sim.areas.linked(w, "locker")   # 1.40: бытовка, назначенная цеху
	if cur and cur.built and cur.kind() == "locker" and not cur.demolish and sim.rooms.zone_ok(cur) \
			and (lr == null or sim.rooms.room_of_thing(cur) == lr or _no_free_locker_in(lr, w)):
		return cur
	w.locker_id = -1
	var taken := {}
	for o in sim.workers:
		if o != w and o.locker_id >= 0:
			taken[o.locker_id] = int(taken.get(o.locker_id, 0)) + 1
	var best: Thing = null
	var bs := INF
	for lk in sim.usable_of("locker"):
		if lk.demolish or int(taken.get(lk.id, 0)) >= maxi(1, int(lk.def().get("seats", 1))):
			continue
		var sc := _dist(lk.cell, w.cell()) - (100.0 if sim.rooms.thing_in(lk, "locker") else 0.0) + sim.areas.pref(w, lk, "locker")
		if sc < bs:
			bs = sc
			best = lk
	if best:
		w.locker_id = best.id
	return best


## 1.40: в назначенной бытовке нет свободного шкафчика — остаётся свой прежний.
func _no_free_locker_in(r: Rooms.Room, w: Worker) -> bool:
	var used := {}
	for o in sim.workers:
		if o != w and o.locker_id >= 0:
			used[o.locker_id] = int(used.get(o.locker_id, 0)) + 1
	for tid in r.things:
		var lk: Thing = sim.things.get(tid)
		if lk and lk.built and not lk.demolish and lk.kind() == "locker" and int(used.get(lk.id, 0)) < maxi(1, int(lk.def().get("seats", 1))):
			return false
	return true


func _locker_spot(lk: Thing, w: Worker) -> Vector2i:
	for sp: Dictionary in lk.spots():
		var c: Vector2i = sp["cell"]
		if sim.world.passable(c) and sim.world.reachable(w.cell(), c):
			return c
	var acc := best_access(lk, w.cell())
	if acc.x >= 0 and sim.world.reachable(w.cell(), acc):
		return acc
	return Vector2i(-1, -1)


func _dress_task(w: Worker) -> Task:
	var t := Task.new()
	t.kind = "dress"
	t.label = L.t("Переодевается в спецовку")
	var lk := _locker_for(w)
	var acc := _locker_spot(lk, w) if lk else Vector2i(-1, -1)
	if acc.x >= 0:
		t.data["locker"] = lk.id
		t.add({"t": "goto", "cell": acc, "face": "up"})
		t.add({"t": "work", "what": "dress", "dur": 4.0, "anim": "work"})
	else:
		t.add({"t": "work", "what": "dress", "dur": 3.0, "anim": "idle"})
	return t


## Взять новый комплект СИЗ из шкафа.
func _ppe_task(w: Worker) -> Task:
	var best: Thing = null
	var bd := INF
	var bsp := {}
	for cab in sim.eng.cabinets():
		var sp := _free_spot(cab, w)
		if sp.is_empty() or not sim.world.reachable(w.cell(), sp["cell"]):
			continue
		var d := _dist(cab.cell, w.cell())
		if d < bd:
			bd = d
			best = cab
			bsp = sp
	if best == null:
		return null
	var t := Task.new()
	t.kind = "ppe"
	t.label = L.t("Получает СИЗ")
	best.spot_users[int(bsp["idx"])] = w.id
	t.res_spots.append([best.id, int(bsp["idx"])])
	t.add({"t": "goto", "cell": bsp["cell"], "face": bsp["face"]})
	t.add({"t": "work", "what": "ppe", "dur": 3.0, "anim": "work"})
	return t


func _smoke_task(w: Worker) -> Task:
	var urns := sim.things_of("decor").filter(func(x: Thing) -> bool: return x.def_id == "urn" and not x.demolish)
	var best: Thing = null
	var bd := INF
	for u: Thing in urns:
		var d := _dist(u.cell, w.cell())
		if d < bd:
			bd = d
			best = u
	if best == null:
		return null
	var acc := best_access(best, w.cell())
	if acc.x < 0 or not sim.world.reachable(w.cell(), acc):
		return null
	var t := Task.new()
	t.kind = "smoke"
	t.label = L.t("Перекур")
	t.add({"t": "goto", "cell": acc, "face": _face_to_rect(acc, best.rect())})
	t.add({"t": "work", "what": "smoke", "dur": sim.rng.randf_range(6.0, 9.0), "anim": "smoke"})
	Nicks.count(w, "smoke")
	return t


# ================================================================ выбор задачи

func _choose(w: Worker) -> Task:
	if not sim.story.fires.is_empty() and not w.is_itr():
		var ft := _fire_task(w)
		if ft:
			return ft
	if sim.story.striking(w):
		if float(w.needs["bladder"]) < 30.0:
			var tt0 := _toilet_task(w)
			if tt0:
				return tt0
		if (_on_lunch(w) and not w.ate_today) or float(w.needs["food"]) < 15.0:
			var et0 := _eat_task(w)
			if et0:
				return et0
		return _strike_task(w)
	if not w.dressed:
		return _dress_task(w)
	if sim.eng.wants_ppe(w) and not _cool(w, "ppe"):
		var pt := _ppe_task(w)
		if pt:
			return pt
		_set_cool(w, "ppe", 60.0)
	var lunch := _on_lunch(w)
	if float(w.needs["bladder"]) < 30.0:
		var tt := _toilet_task(w)
		if tt:
			return tt
	if (lunch and not w.ate_today) or float(w.needs["food"]) < 15.0:
		var et := _eat_task(w)
		if et:
			return et
	if lunch:
		return _rest_task(w)
	match sim.crew.slot(w):
		"break":
			var bt := _break_task(w)
			if bt:
				return bt
		"meet":
			if not sim.crew.met(w) and (not w.is_itr() or w.prof in ["foreman", "chief"]):
				var mt := _meet_task(w)
				if mt:
					return mt
		"clean":
			if not w.is_itr():
				var ct := _shift_clean_task(w)
				if ct:
					return ct
	if float(w.needs["rest"]) < 20.0:
		var rt := _rest_task(w)
		if rt:
			return rt
	if sim.training.tb_active() and sim.training.tb_lead() == w:
		var bt2 := _brief_task(w)
		if bt2:
			return bt2
	var every := trait_f(w, "smoke_every")
	if every > 0.0 and sim.minute - w.last_smoke > every:
		w.last_smoke = sim.minute
		var st := _smoke_task(w)
		if st:
			return st
		Mood.add(sim, w, "no_smoke")
	if sim.training.wants_tb(w):
		var tbt := _tb_task(w)
		if tbt:
			return tbt
	if sim.training.in_class(w):
		var stt := _study_task(w)
		if stt:
			return stt
	if not w.order.is_empty():
		var ot := _order_task(w)
		if ot:
			return ot
	if w.controlled:
		# 1.19: под управлением — стоит и ждёт команды игрока
		var hold := Task.new()
		hold.kind = "order"
		hold.label = L.t("Ждёт вашей команды")
		hold.add({"t": "work", "what": "order_wait", "dur": 3.0, "anim": "idle", "finish": false})
		return hold
	var sht := _shadow_task(w)
	if sht:
		return sht
	if w.is_itr():
		return _office_task(w)
	if w.prof == "guard":
		return _guard_task(w)
	if w.prof == "cook":
		var ckt := _cook_task(w)
		if ckt:
			return ckt
	if w.prof == "nurse":
		var nst := _nurse_task(w)
		if nst:
			return nst
	if sim.crew.wants_union_work(w):
		var ut := _union_task(w)
		if ut:
			return ut
	return _find_work(w)


## Повар: у плиты в столовой, пока не наготовит на всех; в обед — на раздаче.
func _cook_task(w: Worker) -> Task:
	var st := sim.town.kitchen()
	if st == null or not sim.town.kitchen_ready():
		sim.notify_once("cook_idle", L.t("Повару негде готовить: в столовой нужны плита (под током) и линия раздачи."), Sim.LVL_INFO, Vector2i(-1, -1), 1440.0)
		return null
	var t := Task.new()
	t.kind = "cook"
	if sim.town.portions < sim.town.portions_needed():
		var acc := best_access(st, w.cell())
		if acc.x < 0 or not sim.world.reachable(w.cell(), acc):
			return null
		t.label = L.t("Готовит обед")
		t.data["bubble"] = "food"
		t.add({"t": "goto", "cell": acc, "face": _face_to_rect(acc, st.rect())})
		t.add({"t": "work", "what": "cook", "dur": 30.0, "anim": "work"})
		return t
	var sv: Thing = null
	for s2 in sim.things_of("serving"):
		if s2.built and sim.rooms.thing_in(s2, "canteen"):
			sv = s2
			break
	var spot := best_access(sv, w.cell()) if sv else Vector2i(-1, -1)
	if spot.x < 0 or not sim.world.reachable(w.cell(), spot):
		return null
	t.label = L.t("На раздаче") if _lunch_now() else L.t("Моет посуду и протирает раздачу")
	t.add({"t": "goto", "cell": spot, "face": _face_to_rect(spot, sv.rect())})
	t.add({"t": "work", "what": "wait", "dur": 20.0, "anim": "work"})
	return t


func _lunch_now() -> bool:
	for o in sim.workers:
		if o.present and o.task and o.task.kind == "eat":
			return true
	return false


## Фельдшер: приём в медпункте у шкафа с лекарствами.
func _nurse_task(w: Worker) -> Task:
	var cab: Thing = null
	for c in sim.things_of("med_cabinet"):
		if c.built and sim.rooms.thing_in(c, "medbay"):
			cab = c
			break
	if cab == null:
		sim.notify_once("nurse_idle", L.t("Фельдшеру негде принимать: оборудуйте медпункт (кушетка, шкаф с лекарствами, раковина)."), Sim.LVL_INFO, Vector2i(-1, -1), 1440.0)
		return null
	var acc := best_access(cab, w.cell())
	if acc.x < 0 or not sim.world.reachable(w.cell(), acc):
		return null
	var t := Task.new()
	t.kind = "nurse"
	t.label = [L.t("Ведёт приём"), L.t("Заполняет журнал медосмотров"), L.t("Меряет давление сменщикам"), L.t("Проверяет аптечки")][sim.rng.randi_range(0, 3)]
	t.add({"t": "goto", "cell": acc, "face": _face_to_rect(acc, cab.rect())})
	t.add({"t": "work", "what": "wait", "dur": 45.0, "anim": "work"})
	return t


## Перерыв по графику: курильщики — в курилку, остальные — чай и посидеть.
func _break_task(w: Worker) -> Task:
	var left := maxf(3.0, sim.crew.block_end(w) - sim.minute)
	if int(w.get_meta("tea", -1)) != int(w.shift_anchor):
		w.set_meta("tea", int(w.shift_anchor))
		Mood.add(sim, w, "tea_break")
	if trait_f(w, "smoke_every") > 0.0 and sim.minute - w.last_smoke > 30.0:
		var st := _smoke_task(w)
		if st:
			w.last_smoke = sim.minute
			Mood.add(sim, w, "smoked")
			return st
	var rt := _rest_task(w)
	if rt:
		(rt.toils[-1] as Dictionary)["dur"] = left
		rt.label = L.t("Перерыв на чай")
		return rt
	var t := Task.new()
	t.kind = "wander"
	t.label = L.t("Перерыв")
	t.add({"t": "work", "what": "wait", "dur": minf(left, 15.0), "anim": "idle"})
	return t


## Планёрка: собраться у бригадира (или мастера), получить задание на смену.
func _meet_task(w: Worker) -> Task:
	var target := sim.crew.meet_point(w)
	var cell := w.cell()
	var best := INF
	for k in 12:
		var c := target + Vector2i(sim.rng.randi_range(-2, 2), sim.rng.randi_range(-2, 2))
		if not sim.world.in_plot(c) or not sim.world.passable(c) or sim.world.occ[sim.world.idx(c)] >= 0:
			continue
		if not sim.world.reachable(w.cell(), c):
			continue
		var d := _dist(c, target)
		if d >= 1.0 and d < best:
			best = d
			cell = c
	var t := Task.new()
	t.kind = "meet"
	var lead := sim.crew.is_lead(w)
	t.label = L.t("Проводит планёрку") if lead or w.prof in ["foreman", "chief"] else L.t("На планёрке")
	if lead or w.prof in ["foreman", "chief"]:
		t.data["prop"] = "folder"
		t.data["bubble"] = "idea"
	t.add({"t": "goto", "cell": cell, "face": _face_to(cell, target) if cell != target else "down"})
	t.add({"t": "work", "what": "meet", "dur": clampf(sim.crew.block_end(w) - sim.minute, 4.0, 15.0), "anim": "idle"})
	return t


## Уборка в конце смены: свой участок, потом протереть станок.
func _shift_clean_task(w: Worker) -> Task:
	var m: Thing = sim.things.get(w.workplace)
	var r := sim.rooms.room_of_thing(m) if m else sim.rooms.room_at(w.cell())
	if r and sim.upkeep.dirt.size() == sim.world.w * sim.world.h:
		var cells: Array[Vector2i] = []
		for c in r.cells:
			if int(sim.upkeep.dirt[sim.world.idx(c)]) >= 8 and sim.world.passable(c) and not _cool(w, "clean"):
				cells.append(c)
		if not cells.is_empty():
			sim.shuffle(cells)
			var ct := _make_task(w, {"k": "clean", "cells": cells.slice(0, 6), "s": 0.0})
			if ct:
				ct.label = L.t("Уборка участка по графику")
				return ct
	if int(w.get_meta("handover", -1)) != int(w.shift_anchor):
		w.set_meta("handover", int(w.shift_anchor))
		Mood.add(sim, w, "clean_handover")
	var t := Task.new()
	t.kind = "wander"
	t.label = L.t("Сдаёт смену: протирает станок")
	var spot := w.cell()
	if m:
		var acc := best_access(m, w.cell())
		if acc.x >= 0 and sim.world.reachable(w.cell(), acc):
			spot = acc
	t.add({"t": "goto", "cell": spot, "face": _face_to_rect(spot, m.rect()) if m else "down"})
	t.add({"t": "work", "what": "wait", "dur": clampf(sim.crew.block_end(w) - sim.minute, 3.0, 15.0), "anim": "work"})
	return t


## Охранник: дежурство на проходной и обходы территории (ночью — чаще).
func _guard_task(w: Worker) -> Task:
	var cp := sim.crew.post()
	var night := w.shift == 1
	var t := Task.new()
	t.kind = "guard"
	if cp and sim.rng.randf() < (0.45 if night else 0.75):
		var taken := false
		for g in sim.crew.guards(true):
			if g != w and g.task and g.task.kind == "guard" and str(g.task.data.get("post", "")) == "1":
				taken = true
				break
		if not taken:
			# 1.30: в будке у турникетов — заходит через турникет рядом и садится за стол
			var seat := cp.seat_cell()
			var door := Vector2i(-1, -1)
			for wc in cp.walk_cells():
				if seat.x >= 0 and absi(wc.x - seat.x) + absi(wc.y - seat.y) == 1 and sim.world.passable(wc):
					door = wc
					break
			if door.x >= 0 and sim.world.reachable(w.cell(), door):
				t.label = L.t("Дежурит в будке на проходной")
				t.data["post"] = "1"
				t.add({"t": "goto", "cell": door})
				t.add({"t": "seat", "thing": cp.id, "back": door, "face": Thing.rot_face("down", cp.rot)})
				t.add({"t": "work", "what": "guard", "dur": sim.rng.randf_range(40.0, 70.0), "anim": "sit"})
				return t
			var acc := best_access(cp, w.cell())
			if acc.x >= 0 and sim.world.reachable(w.cell(), acc):
				t.label = L.t("Дежурит на проходной")
				t.data["post"] = "1"
				t.add({"t": "goto", "cell": acc, "face": _face_to_rect(acc, cp.rect())})
				t.add({"t": "work", "what": "guard", "dur": sim.rng.randf_range(40.0, 70.0), "anim": "idle"})
				return t
	var pts: Array[Vector2i] = []
	for th: Thing in sim.things.values():
		if th.built and (th.kind() == "storage" or th.kind() == "machine" or th.def_id == "checkpoint"):
			var a := best_access(th, w.cell())
			if a.x >= 0:
				pts.append(a)
	if night or pts.is_empty():
		var pr := sim.world.plot
		for k in 6:
			var c := Vector2i(sim.rng.randi_range(pr.position.x + 1, pr.end.x - 2), sim.rng.randi_range(pr.position.y + 1, pr.end.y - 2))
			if sim.world.passable(c):
				pts.append(c)
	if pts.is_empty():
		return null
	var target: Vector2i = pts[sim.rng.randi_range(0, pts.size() - 1)]
	if not sim.world.reachable(w.cell(), target):
		return null
	t.label = L.t("Обход территории")
	t.add({"t": "goto", "cell": target})
	t.add({"t": "work", "what": "guard", "dur": sim.rng.randf_range(2.0, 5.0), "anim": "idle"})
	return t


## Председатель профкома: час за столом в профкоме.
func _union_task(w: Worker) -> Task:
	var r := sim.crew.union_office()
	if r == null:
		return null
	for tid in r.things:
		var desk: Thing = sim.things.get(tid)
		if desk == null or desk.def_id != "office_desk":
			continue
		var sp := _free_spot(desk, w)
		if sp.is_empty() or not sim.world.reachable(w.cell(), sp["cell"]):
			continue
		var t := Task.new()
		t.kind = "office"
		t.label = L.t("Профсоюзная работа")
		t.data["prop"] = "folder"
		desk.spot_users[int(sp["idx"])] = w.id
		t.res_spots.append([desk.id, int(sp["idx"])])
		t.add({"t": "goto", "cell": sp["cell"], "face": sp["face"]})
		t.add({"t": "work", "what": "union", "dur": sim.rng.randf_range(40.0, 60.0), "anim": "desk"})
		return t
	return null


## Курсы в своём учебном классе: за парту на час, потом снова (перерывы — как обычно).
func _study_task(w: Worker) -> Task:
	var c := sim.training.course_of(w)
	for desk in sim.things_of("school_desk"):
		if desk.demolish or not sim.rooms.thing_in(desk, "classroom"):
			continue
		var sp := _free_spot(desk, w)
		if sp.is_empty() or not sim.world.reachable(w.cell(), sp["cell"]):
			continue
		var t := Task.new()
		t.kind = "study"
		t.label = L.t("На курсах: %s") % L.t(str(Worker.SKILL_NAMES.get(str(c.get("skill", "")), ""))).to_lower()
		desk.spot_users[int(sp["idx"])] = w.id
		t.res_spots.append([desk.id, int(sp["idx"])])
		t.data["prop"] = "folder"
		t.add({"t": "goto", "cell": sp["cell"], "face": sp["face"]})
		t.add({"t": "work", "what": "study", "dur": sim.rng.randf_range(50.0, 70.0), "anim": "desk"})
		return t
	return null


## Инструктаж по охране труда: в учебный класс (или к своему месту в цеху), постоять и послушать.
func _tb_task(w: Worker) -> Task:
	# 1.14: слушатели встают полукругом перед ведущим (у доски в классе или в цеху)
	var target := Vector2i(-1, -1)
	var spot := sim.training.tb_spot()
	var face := "up"
	if spot.x >= 0:
		var taken := {}
		for o in sim.workers:
			if o.task and o.task.kind == "study" and o.task.data.has("tb_cell"):
				taken[o.task.data["tb_cell"]] = true
		var best := INF
		for dy in range(-4, 6):
			for dx in range(-5, 6):
				if absi(dx) + absi(dy) < 2:
					continue
				var c := spot + Vector2i(dx, dy)
				if taken.has(c) or not sim.world.passable(c) or sim.world.occ[sim.world.idx(c)] >= 0:
					continue
				if sim.rooms.space_id_at(c) != sim.rooms.space_id_at(spot):
					continue
				# лучше перед ведущим, но если там тесно — сбоку и даже сзади
				var d := Vector2(dx, dy * 1.4).length() + (5.0 if dy < 1 else (1.0 if dy == 1 else 0.0))
				if d < best:
					best = d
					target = c
		if target.x >= 0:
			var off := spot - target
			if absi(off.y) >= absi(off.x):
				face = "up" if off.y < 0 else "down"
			else:
				face = "left" if off.x < 0 else "right"
	if target.x < 0:
		var rooms := sim.training.classrooms()
		if not rooms.is_empty():
			var cells: Array[Vector2i] = []
			for cc in rooms[0].cells:
				if sim.world.passable(cc) and sim.world.occ[sim.world.idx(cc)] < 0:
					cells.append(cc)
			if not cells.is_empty():
				target = cells[sim.rng.randi_range(0, cells.size() - 1)]
	if target.x < 0 or not sim.world.reachable(w.cell(), target):
		target = w.cell()
	var t := Task.new()
	t.kind = "study"
	t.label = L.t("Инструктаж по охране труда")
	t.data["bubble"] = "idea"
	t.data["tb_cell"] = target
	t.add({"t": "goto", "cell": target, "face": face})
	t.add({"t": "work", "what": "tb", "dur": 25.0, "anim": "idle"})
	return t


## Работа ИТР: за своим столом; мастер ещё и обходит участок.
func _office_task(w: Worker) -> Task:
	if w.is_director():
		return _director_task(w)
	if w.prof == "foreman" and sim.rng.randf() < 0.35:
		var pt := _patrol_task(w)
		if pt:
			return pt
	var desk := sim.office.desk_for(w)
	if desk == null:
		Mood.add(sim, w, "no_desk")
		var room := str(Defs.departments.get(w.dept(), {}).get("room", ""))
		sim.notify_once("nodesk_" + w.prof, L.t("%s (%s) без рабочего места: поставьте стол ИТР в помещении «%s» или в общей конторе.") % [w.full_name(), w.prof_lc(), str(Defs.rooms.get(room, {}).get("name", room))], Sim.LVL_WARN, Vector2i(-1, -1), 1440.0)
		return null
	var sp := _free_spot(desk, w)
	if sp.is_empty() or not sim.world.reachable(w.cell(), sp["cell"]):
		return null
	var t := Task.new()
	t.kind = "office"
	t.label = L.t(str(Office.DESK_LABELS.get(w.prof, "Работает с документами")))
	desk.spot_users[int(sp["idx"])] = w.id
	t.res_spots.append([desk.id, int(sp["idx"])])
	t.data["desk"] = desk.id
	t.add({"t": "goto", "cell": sp["cell"], "face": sp["face"]})
	t.add({"t": "work", "what": "office", "dur": sim.rng.randf_range(40.0, 75.0), "anim": "desk"})
	return t


## 1.40: ученик ходит за наставником «хвостиком»: пока тот работает, стоит рядом и смотрит.
## Пока наставник на смене, долгих дел вдали от него ученик не берёт (см. _tick_worker); без кубика.
const SHADOW_KINDS := ["operate", "inspect", "haul", "build_bp", "build_thing", "repair", "fix", "rework", "reset", "lay_net", "load", "haul_cell", "clean", "sweep", "demolish"]


func _shadow_task(w: Worker) -> Task:
	if w.mentor < 0 or w.is_itr() or not sim.story.fires.is_empty():
		return null
	var m := sim.training.mentor_of(w)
	if m == null or not m.present or m.hidden or m.shift != w.shift or not _shadowable(m):
		return null
	if _cool(w, "shadow"):
		return null
	var c := _beside(m.cell(), w)
	if c.x < 0 or not sim.world.reachable(w.cell(), c):
		_set_cool(w, "shadow", 20.0)
		return null
	var t := Task.new()
	t.kind = "shadow"
	t.label = L.t("Учится у наставника: %s") % m.full_name()
	t.data["mentor"] = m.id
	t.add({"t": "shadow", "mentor": m.id, "dur": 25.0, "want": c})
	return t


## Наставник на работе, между делами, на перекуре или в туалете — ученик рядом (ждёт у двери); на обед и отдых — нет.
func _shadowable(m: Worker) -> bool:
	return m.task == null or m.task.kind in ["wander", "smoke", "toilet", "patrol"] or SHADOW_KINDS.has(m.task.kind)


## Свободная клетка рядом с человеком (ближайшая к ученику).
func _beside(mc: Vector2i, w: Worker) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := mc + Vector2i(dx, dy)
			if (dx == 0 and dy == 0) or not sim.world.inb(c) or not sim.world.passable(c) or sim.world.occ[sim.world.idx(c)] >= 0:
				continue
			var dd := _dist(c, w.cell()) * 0.05 + float(maxi(absi(dx), absi(dy))) * 10.0
			if dd < bd:
				bd = dd
				best = c
	return best


func _run_shadow(w: Worker, tl: Dictionary, dt: float) -> void:
	var m := sim.get_worker(int(tl["mentor"]))
	tl["done"] = float(tl.get("done", 0.0)) + dt
	if m == null or not m.present or not _shadowable(m) or float(tl["done"]) >= float(tl["dur"]):
		if m and float(tl["done"]) >= 10.0:
			var sk := w.main_skill()
			if w.skill(sk) < mini(10, m.skill(sk) - 1) and sim.rng.randf() < 0.03 * sim.training.growth_k(w, sk):
				w.skills[sk] = w.skill(sk) + 1
				w.add_history(sim.day(), L.t("Подучился у наставника: %s") % m.full_name())
		w.task.next()
		return
	if m.task and m.task.kind in ["toilet", "smoke"] and float(w.needs["bladder"]) < 75.0:
		var tt := _toilet_task(w)   # наставник отошёл — ученик заодно в туалет, чтобы потом не отлучаться
		if tt:
			abort(w)
			assign(w, tt)
			return
	if w.pos.distance_to(m.pos) <= 1.6 or m.hidden:
		w.anim = "idle"
		_set_dir(w, m.pos - w.pos)
		return
	var want: Vector2i = tl.get("want", Vector2i(-1, -1))
	if want.x < 0 or absi(want.x - m.cell().x) > 1 or absi(want.y - m.cell().y) > 1:
		want = _beside(m.cell(), w)
		tl["want"] = want
	if want.x < 0:
		w.anim = "idle"
		return
	if _move(w, want, dt) == -1:
		tl["want"] = Vector2i(-1, -1)
		w.task.next()


## 1.40: директор — за своим столом (ведёт развитие, договоры, отчёты); раз в смену обходит цех.
func _director_task(w: Worker) -> Task:
	if int(w.get_meta("dir_walk", -1)) != int(w.shift_anchor) and sim.minute - w.shift_anchor > 120.0 and sim.dev.cur == "":
		w.set_meta("dir_walk", int(w.shift_anchor))
		var pt := _patrol_task(w)
		if pt:
			pt.label = L.t("Обходит цех: как идут дела")
			pt.data["prop"] = "folder"
			return pt
	var desk := Director.desk(sim)
	if desk == null:
		sim.notify_once("nodesk_director", L.t("Директору негде работать: нужен кабинет директора со столом директора (Объекты → Офис). Без него не исследуются ступени «Развития»."), Sim.LVL_INFO, Vector2i(-1, -1), 2880.0)
		return null
	var sp := _free_spot(desk, w)
	if sp.is_empty() or not sim.world.reachable(w.cell(), sp["cell"]):
		return null
	var t := Task.new()
	t.kind = "office"
	t.label = Director.desk_label(sim, int(sim.minute / 47.0))
	desk.spot_users[int(sp["idx"])] = w.id
	t.res_spots.append([desk.id, int(sp["idx"])])
	t.data["desk"] = desk.id
	if sim.dev.cur != "":
		t.data["bubble"] = "idea"
		t.data["prop"] = "folder"
	t.add({"t": "goto", "cell": sp["cell"], "face": sp["face"]})
	t.add({"t": "work", "what": "director", "dur": 60.0, "anim": "desk"})
	return t


## Мастер идёт по участку: к работающему станку или в цех.
func _patrol_task(w: Worker) -> Task:
	var cells: Array[Vector2i] = []
	for m in sim.things_of("machine"):
		for c in access_cells(m):
			if sim.world.passable(c):
				cells.append(c)
	if cells.is_empty():
		return null
	var target: Vector2i = cells[sim.rng.randi_range(0, cells.size() - 1)]
	if not sim.world.reachable(w.cell(), target):
		return null
	var t := Task.new()
	t.kind = "patrol"
	t.label = L.t("Обходит участок, раздаёт задания")
	t.add({"t": "goto", "cell": target})
	t.add({"t": "work", "what": "patrol", "dur": sim.rng.randf_range(3.0, 6.0), "anim": "idle"})
	return t


func _cool(w: Worker, key: String) -> bool:
	return w.fail_cool.has(key) and sim.minute < float(w.fail_cool[key])


## 1.23: станки, на которых сейчас вообще можно работать (ток, вода, зона, заготовки, расходники) —
## от человека это не зависит, поэтому считаем раз за ход, а не для каждого из сотен.
var _rm_key := ""
var _rm: Array[Thing] = []


func _ready_machines(machines: Array[Thing]) -> Array[Thing]:
	var key := "%s|%d" % [str(sim.minute), sim.thing_rev]
	if key == _rm_key:
		return _rm
	_rm_key = key
	_rm = []
	var no_zone: Array[Thing] = []
	var no_water: Array[Thing] = []
	for m in machines:
		if m.demolish or m.product == "" or m.broken or m.condition < 15.0:
			continue
		if not m.enabled or not sim.power.powered(m) or sim.inspect.is_suspended(m):
			continue
		if not sim.rooms.zone_ok(m):
			no_zone.append(m)
			continue
		if not sim.water.has_water(m):
			no_water.append(m)
			continue
		if m.is_batch():
			if m.working or not _batch_ready(m):
				continue
		elif not sim.prod.can_start(m) or sim.count_slot(m, 1) >= m.slot_cap(1):
			continue
		if not sim.prod.has_cons(m):
			var cn := str(sim.prod.cons_need(m)[0])
			sim.notify_once("nocons_" + cn, L.t("Станок «%s» стоит: закончился %s — ждём поставку.") % [m.title(), str(Defs.consumables.get(cn, {}).get("short", cn))], Sim.LVL_WARN, m.cell, 480.0)
			continue
		_rm.append(m)
	# 1.26: одно сообщение на всех, а не по штуке на каждый станок
	if not no_zone.is_empty():
		sim.notify_once("zonem_all", L.t("%s вне цеха — на %s не работают. Разметьте зону «Цех» там, где стоят станки (Зоны → Производство). Список — «Производство → Простой».") % [_names(no_zone), L.t("нём") if no_zone.size() == 1 else L.t("них")], Sim.LVL_WARN, no_zone[0].cell, 720.0)
	if not no_water.is_empty():
		sim.notify_once("drym_all", L.t("Нет воды: %s. Протяните трубу от насоса (меню «Сети»).") % _names(no_water), Sim.LVL_WARN, no_water[0].cell, 720.0)
	return _rm


## «Токарный 1К62» / «Токарный 1К62 и ещё 3 станка».
func _names(ms: Array[Thing]) -> String:
	if ms.size() == 1:
		return "«%s»" % ms[0].title()
	var more := ms.size() - 1
	return L.t("«%s» и ещё %d %s") % [ms[0].title(), more, Defs.plural(more, "станок", "станка", "станков")]


## 1.23: то же, но строка ключа собирается, только если у человека вообще есть «отказы» —
## обычно их нет, а проверка идёт по каждому объекту для каждого.
func _coolf(w: Worker, fmt: String, id: int) -> bool:
	if w.fail_cool.is_empty():
		return false
	return _cool(w, fmt % id)


func _set_cool(w: Worker, key: String, minutes: float = 30.0) -> void:
	if key != "":
		for k: Variant in w.fail_cool.keys():
			if float(w.fail_cool[k]) <= sim.minute:
				w.fail_cool.erase(k)   # 1.23: истёкшие не копим
		w.fail_cool[key] = sim.minute + minutes


func _dist(a: Vector2i, b: Vector2i) -> float:
	return Vector2(a - b).length()


## Клетки, с которых можно работать с объектом (соседние проходимые).
func access_cells(t: Thing) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if not t.blocks():
		for c in t.cells():
			if sim.world.passable(c):
				out.append(c)
	var r := t.rect()
	for x in range(r.position.x - 1, r.end.x + 1):
		for y in range(r.position.y - 1, r.end.y + 1):
			var c := Vector2i(x, y)
			if r.has_point(c):
				continue
			var outside_x := x < r.position.x or x >= r.end.x
			var outside_y := y < r.position.y or y >= r.end.y
			if outside_x and outside_y:
				continue
			if sim.world.passable(c):
				out.append(c)
	return out


func best_access(t: Thing, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for c in access_cells(t):
		var d := _dist(c, from)
		if d < bd:
			bd = d
			best = c
	return best


func _adjacent_access(c: Vector2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var n: Vector2i = c + d
		if sim.world.passable(n):
			var dd := _dist(n, from)
			if dd < bd:
				bd = dd
				best = n
	return best


func _free_spot(t: Thing, w: Worker) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for sp: Dictionary in t.spots():
		var idx := int(sp["idx"])
		if t.spot_users.has(idx):
			continue
		var c: Vector2i = sp["cell"]
		if not sim.world.passable(c):
			continue
		var d := _dist(c, w.cell())
		if d < bd:
			bd = d
			best = sp
	return best


func _src_cell(it: Item, from: Vector2i) -> Vector2i:
	match it.loc:
		Item.Loc.GROUND:
			return it.cell if sim.world.passable(it.cell) else sim.world.nearest_passable(it.cell)
		Item.Loc.THING:
			var t: Thing = sim.things.get(it.holder)
			return best_access(t, from) if t else Vector2i(-1, -1)
		Item.Loc.VEHICLE:
			var v := sim.get_vehicle(it.holder)
			return v.access_cell(sim.world.sidewalk_row) if v else Vector2i(-1, -1)
	return Vector2i(-1, -1)


func _in_general_storage(it: Item) -> bool:
	if it.loc == Item.Loc.GROUND:
		return true
	if it.loc == Item.Loc.THING:
		var t: Thing = sim.things.get(it.holder)
		return t != null and t.is_storage()
	return false


func _find_qc_dest(it: Item, near: Vector2i) -> Thing:
	var best: Thing = null
	var bd := INF
	for q in sim.usable_of("qc"):
		if q.demolish:
			continue
		if sim.free_space(q, 0, it.stack_key()) <= 0:
			continue
		var d := _dist(q.cell, near)
		if d < bd:
			bd = d
			best = q
	return best


## 1.15: слесарные верстаки, на которых можно работать.
func fit_benches() -> Array[Thing]:
	var out: Array[Thing] = []
	for t: Thing in sim.things.values():
		if t.def_id == "workbench" and t.built and not t.demolish and sim.rooms.zone_ok(t):
			out.append(t)
	return out


## Ближайший брак, который ещё не пробовали доработать (из тары для брака или с пола).
func _rework_item(w: Worker) -> Item:
	var best: Item = null
	var bd := INF
	var pool: Array = []
	for b in sim.things_of("storage"):
		if b.def_id == "scrap_bin" and b.built:
			pool.append_array(sim.slot_ids(b, 0))
	pool.append_array(sim.ground_items)
	for iid in pool:
		var it: Item = sim.items.get(iid)
		if it == null or it.kind != "part" or it.q != "scrap" or it.rw or it.reserved_by >= 0 or _coolf(w, "item%d", it.id):
			continue
		var d := _dist(sim.item_cell(it), w.cell())
		if d < bd:
			bd = d
			best = it
	return best


## Подобрать работу: собираем кандидатов, сортируем по выгоде, пробуем по очереди.
func _find_work(w: Worker) -> Task:
	var cands: Array = []
	var wc := w.cell()
	var laborer := w.prof == "laborer"
	var builder := w.prof == "builder"
	var machines := sim.things_of("machine")
	# 0. 1.15 (РП-10): экзамен на разряд — пробная деталь на своём или любом подходящем месте
	if sim.career.exam_pending(w) and not _cool(w, "exam"):
		var ep := sim.career.exam_place(w)
		if ep:
			var esp := _free_spot(ep, w)
			if not esp.is_empty():
				cands.append({"s": 400.0, "k": "exam", "t": ep, "spot": esp})

	# 1. работа на станке (у печи — загрузить и запустить партию)
	for m in _ready_machines(machines):
		if m.user >= 0 or not sim.prod.can_operate(w, m):
			continue
		var sp := _free_spot(m, w)
		if sp.is_empty() or _coolf(w, "op%d", m.id):
			continue
		if not sim.crew.allowed(w, m):
			continue
		if not Workplace.may_use(sim, w, m):
			continue   # 1.15: станок закреплён за другим, и тот может работать
		var pdef: Dictionary = Defs.processes.get(m.process(), {})
		var own := w.prof == str(pdef.get("prof", "")) or (w.prof == "cnc_operator" and m.is_cnc())
		var sc := 100.0 + (60.0 if own else 0.0) + w.skill(Production.op_skill(w, m)) * 2.0 - _dist(wc, sp["cell"]) * 0.5 + sim.crew.zone_bonus(w, m) + Workplace.bonus(w, m)
		cands.append({"s": sc, "k": "operate", "t": m, "spot": sp})

	# 2. контроль ОТК
	if w.skill("qc") >= 2:
		for q in _qc_with_parts():
			var sp2 := _free_spot(q, w)
			if sp2.is_empty() or _coolf(w, "qc%d", q.id) or not Workplace.may_use(sim, w, q):
				continue
			var sc2 := 95.0 + (60.0 if w.prof == "qc" else 0.0) + w.skill("qc") - _dist(wc, sp2["cell"]) * 0.5 + Workplace.bonus(w, q)
			cands.append({"s": sc2, "k": "inspect", "t": q, "spot": sp2})

	var haul_bonus := 40.0 if laborer else (15.0 if builder else 0.0)

	# 3. подвезти к станку металл, детали НЗП или комплектующие для сборки
	for m in _hungry_machines(machines):
		var it := _nearest_feed(m, w)
		if it == null:
			continue
		if sim.free_space(m, 0, it.stack_key()) <= 0:
			continue
		var sc3 := 85.0 + haul_bonus + (6.0 if it.q == "wip" else 0.0) - _dist(wc, sim.item_cell(it)) * 0.3 + sim.crew.zone_bonus(w, m) * 0.4
		cands.append({"s": sc3, "k": "haul", "item": it, "dest": m, "slot": 0})

	# 4. забрать детали со станка: готовые — на ОТК, НЗП — на следующий станок или стеллаж НЗП
	for m in machines:
		for iid in sim.slot_ids(m, 1):
			var it2: Item = sim.items.get(iid)
			if it2 == null or it2.reserved_by >= 0 or _coolf(w, "item%d", it2.id):
				continue
			var urgent := 20.0 if sim.count_slot(m, 1) >= m.slot_cap(1) else 0.0
			var dst := _route_dest(it2, m.cell)
			if dst.is_empty():
				if it2.q == "machined" and sim.things_of("qc").is_empty():
					sim.notify_once("noqc", L.t("Детали некуда нести на проверку. Поставьте стол ОТК."), Sim.LVL_WARN, m.cell)
				elif it2.q == "wip":
					sim.notify_once("nowip", L.t("Деталям между операциями некуда деваться: поставьте стеллаж НЗП (меню «Объекты» → «Склад»)."), Sim.LVL_WARN, m.cell, 600.0)
				break
			var sc4 := 80.0 + urgent + haul_bonus - _dist(wc, m.cell) * 0.3
			cands.append({"s": sc4, "k": "haul", "item": it2, "dest": dst[0], "slot": dst[1]})
			break

	# 4б. снять металл с выключенного станка обратно на склад; лишние детали со сборки — тоже
	for m in machines:
		if m.user >= 0 or m.working:
			continue
		var surplus := m.job_step == 0 and m.product != "" and Defs.is_assembly(m.product) and sim.planner.need(m.product) <= 0
		if m.enabled and not surplus:
			continue
		for iid in sim.slot_ids(m, 0):
			var itx: Item = sim.items.get(iid)
			if itx == null or itx.reserved_by >= 0 or _coolf(w, "item%d", itx.id):
				continue
			var destx := sim.find_storage(itx, m.cell)
			if destx.is_empty():
				break
			cands.append({"s": 66.0 + haul_bonus - _dist(wc, m.cell) * 0.3, "k": "haul", "item": itx, "dest": destx[0], "slot": destx[1]})
			break

	# 5. разгрузка фургона (металл и ящики с оборудованием), доставка ящиков к местам установки
	sim.logi.add_jobs(self, w, cands, haul_bonus)

	# 5а. готовые заказы — в зону отгрузки
	sim.logi.add_ship_jobs(self, w, cands, haul_bonus)

	# 6. погрузка заказа в машину клиента
	for v in sim.vehicles:
		if v.state != "parked" or v.kind != "pickup":
			continue
		if v.loaded + v.reserved_load >= v.need:
			continue
		var o := sim.orders.get_order(v.order_id)
		if o.is_empty():
			continue
		var p := str(o["product"])
		# 1.29: грузят только из зоны отгрузки (запасной путь — со склада, см. Logistics.ship_only)
		var only_ship := sim.logi.ship_only(v, p)
		var pred_ok := func(i: Item) -> bool: return i.kind == "part" and i.def_id == p and i.q == "ok" and (i.loc == Item.Loc.GROUND and sim.logi.in_ship(i.cell) if only_ship else _in_general_storage(i))
		var it4 := _nearest_item(pred_ok, v.access_cell(sim.world.sidewalk_row), w)
		if it4 == null:
			continue
		var sc6 := 82.0 + haul_bonus - _dist(wc, sim.item_cell(it4)) * 0.2
		cands.append({"s": sc6, "k": "load", "item": it4, "veh": v})

	# 7. грузы, брошенные на полу
	var reloc := false
	var no_store := {}   ## 1.38.2: «склада нет» не зависит от того, где лежит груз — для того же груза не искать снова
	for gid in sim.ground_items:
		var it5: Item = sim.items.get(gid)
		if it5 == null or it5.reserved_by >= 0 or _coolf(w, "item%d", it5.id):
			continue
		if sim.logi.in_ship(it5.cell) and it5.kind == "part" and sim.logi.ship_wanted(it5.def_id):
			continue   # ждёт машину клиента в зоне отгрузки
		if it5.cat() == "machined" or it5.cat() == "wip":
			var dst5 := _route_dest(it5, it5.cell)
			if not dst5.is_empty():
				cands.append({"s": 62.0 + haul_bonus - _dist(wc, it5.cell) * 0.3, "k": "haul", "item": it5, "dest": dst5[0], "slot": dst5[1]})
		else:
			var nk := it5.cat() + "|" + it5.stack_key()
			var dest2: Array = [] if no_store.has(nk) else sim.find_storage(it5, it5.cell)
			if dest2.is_empty():
				no_store[nk] = true
			if not dest2.is_empty():
				cands.append({"s": 60.0 + haul_bonus - _dist(wc, it5.cell) * 0.3, "k": "haul", "item": it5, "dest": dest2[0], "slot": dest2[1]})
			elif not reloc and it5.kind != "crate" and sim.logi.has_zone() and not sim.logi.in_zone(it5.cell) and not sim.logi.in_ship(it5.cell):
				reloc = true
				# 1.20: зону разгрузки убрали или перенесли — груз несут в новую зону
				var zc5 := sim.logi.free_cell(sim.logi.zone_cells(), it5, it5.cell)
				if zc5.x >= 0:
					cands.append({"s": 46.0 + haul_bonus - _dist(wc, it5.cell) * 0.3, "k": "haul_cell", "item": it5, "cell": zc5})

	# 8. стройка и снос
	var build_bonus := (55.0 if laborer else (95.0 if builder else 0.0)) + (60.0 if sim.build_priority else 0.0)
	var best_bp := -1
	var best_bp_s := -INF
	for i in sim.bp_cells.keys():
		if sim.bp_res.has(i) or _coolf(w, "bp%d", i) or not sim.bp_ready(i) or not sim.bmats.ready(i):
			continue
		var c := sim.world.cell_of(i)
		var sc7 := 50.0 + build_bonus + w.skill("build") - _dist(wc, c) * 0.3
		if sc7 > best_bp_s:
			best_bp_s = sc7
			best_bp = i
	if best_bp >= 0:
		cands.append({"s": best_bp_s, "k": "build_bp", "idx": best_bp})
	# 8а. сети по чертежам (1.13): кабель — электрик (или кто в нём разбирается), трубы и воздуховоды — строители
	var can_cable := w.prof == "electrician" or builder or laborer or w.skill("electric") >= 2
	var can_pipe := builder or laborer or w.skill("build") >= 3
	# 1.18: аварию (обрыв, прорыв) чинит любой рабочий, если некому больше — сеть стоит
	var any_fault := not sim.faults.list.is_empty() and not w.is_itr()
	if can_cable or can_pipe or any_fault:
		var best_n: Array = []
		var best_ns := -INF
		# станок без тока ждёт кабель — тянуть его срочно
		var urgent := 45.0 if sim.power.unconnected_machines() > 0 else 0.0
		for pr: Array in sim.net_plans():
			var lay := str(pr[0])
			var ii := int(pr[1])
			var fault := any_fault and sim.faults.list.has(Faults.key(lay, ii))
			if not fault and ((lay == "cable" and not can_cable) or (lay != "cable" and not can_pipe)):
				continue
			if sim.net_res.has("%s:%d" % [lay, ii]) or _coolf(w, "net%d", ii):
				continue
			var cc := sim.world.cell_of(ii)
			var bonus := (45.0 if w.prof == "electrician" and lay == "cable" else 0.0) + (urgent if lay == "cable" else 0.0) + (80.0 if fault else 0.0)
			var scn := 48.0 + build_bonus + bonus - _dist(wc, cc) * 0.3
			if scn > best_ns:
				best_ns = scn
				best_n = pr
		if not best_n.is_empty():
			cands.append({"s": best_ns, "k": "lay_net", "layer": str(best_n[0]), "idx": int(best_n[1])})
	# 9. сбросить выбитый автомат
	if w.prof == "electrician" or w.skill("electric") >= 2:
		for pair in sim.power.tripped_list():
			var src: Thing = sim.things.get(int(pair[0]))
			if src == null or src.user >= 0 or _coolf(w, "th%d", src.id):
				continue
			var base := 230.0 if w.prof == "electrician" else 150.0
			cands.append({"s": base - _dist(wc, src.cell) * 0.3, "k": "reset", "t": src})
	# 10. ремонт сломанных и обслуживание изношенных станков (наладка, смена резцов, смазка)
	var mechanic := w.prof in ["turner", "miller", "electrician", "assembler", "setter", "fitter"] or w.skill("build") >= 3
	if mechanic:
		var svc := sim.service_at()
		for m2 in machines:
			if m2.demolish or m2.user >= 0 or m2.working or _coolf(w, "th%d", m2.id):
				continue
			if m2.broken:
				cands.append({"s": 120.0 + (20.0 if w.prof == "electrician" else 0.0) + (40.0 if w.prof in ["setter", "fitter"] else 0.0) - _dist(wc, m2.cell) * 0.3, "k": "fix", "t": m2})
			elif m2.condition < svc:
				var urgent2 := 30.0 if m2.condition < 25.0 else 0.0
				cands.append({"s": 78.0 + urgent2 + (15.0 if w.prof in ["turner", "miller"] else 0.0) + (60.0 if w.prof == "setter" else (45.0 if w.prof == "fitter" else 0.0)) - _dist(wc, m2.cell) * 0.3, "k": "repair", "t": m2})
	for t: Thing in _pending_things():
		if (t.built and not t.demolish) or t.user >= 0 or _coolf(w, "th%d", t.id):
			continue
		if not t.built:
			if t.crates_in < t.crates_need:
				continue   # ящики с оборудованием ещё не принесли
			cands.append({"s": 55.0 + build_bonus - _dist(wc, t.cell) * 0.3, "k": "build_thing", "t": t})
		elif t.demolish:
			cands.append({"s": 52.0 + build_bonus - _dist(wc, t.cell) * 0.3, "k": "demolish", "t": t})

	# 11. уборка снега с дорожек (зимой, лопатой)
	if sim.season.snow_avg > 30.0 and (laborer or w.skill("haul") >= 3) and not _cool(w, "sweep"):
		var dirty := sim.season.dirty_paths(60)
		if not dirty.is_empty():
			var ss := Defs.sea("sweep_score") + (25.0 if laborer else 0.0) + sim.season.snow_avg * 0.08
			cands.append({"s": ss, "k": "sweep", "cells": dirty})

	# 12. уборка стружки и грязи в помещениях: уборщица — главное дело, разнорабочий — когда совсем грязно
	var cleaner := w.prof == "cleaner"
	if (cleaner or (laborer and (sim.upkeep.has_hotspot() or sim.upkeep.avg_room_dirt() > 45.0))) and not _cool(w, "clean"):
		var dc := sim.upkeep.dirty_cells(55 if cleaner else 110, 30)
		if not dc.is_empty():
			cands.append({"s": (210.0 if cleaner else 58.0) + w.skill("clean"), "k": "clean", "cells": dc})
	# 13. ленточная пила: нарезать заготовки впрок
	if laborer or w.prof in ["turner", "miller", "setter", "fitter"] or w.skill("haul") >= 4:
		for saw in sim.upkeep.saws():
			if saw.user >= 0 or _coolf(w, "th%d", saw.id) or not Workplace.may_use(sim, w, saw):
				continue
			var mat := sim.upkeep.saw_material()
			if mat == "":
				break
			var spx := _free_spot(saw, w)
			if spx.is_empty():
				continue
			cands.append({"s": 72.0 + (25.0 if laborer else 0.0) + (30.0 if w.prof == "fitter" else 0.0) + Workplace.bonus(w, saw) - _dist(wc, spx["cell"]) * 0.3, "k": "saw", "t": saw, "spot": spx, "mat": mat})
	# 13б. 1.15: слесарь у верстака — дорабатывает брак, а без ленточной пилы режет заготовки ножовкой
	if w.prof == "fitter" or w.skill("fitting") >= 5:
		var scrap_it := _rework_item(w)
		for wb in fit_benches():
			if wb.user >= 0 or _coolf(w, "th%d", wb.id) or not Workplace.may_use(sim, w, wb):
				continue
			var spf := _free_spot(wb, w)
			if spf.is_empty():
				continue
			var fb := (40.0 if w.prof == "fitter" else 0.0) + Workplace.bonus(w, wb) - _dist(wc, spf["cell"]) * 0.3
			if scrap_it:
				cands.append({"s": 96.0 + fb, "k": "rework", "t": wb, "spot": spf, "item": scrap_it})
			elif sim.upkeep.saws().is_empty():
				var hmat := sim.upkeep.saw_material()
				if hmat != "":
					cands.append({"s": 58.0 + fb, "k": "hand_saw", "t": wb, "spot": spf, "mat": hmat})
	# 14. наладчик заранее налаживает станок под следующую операцию — станочник не ждёт
	if w.prof == "setter":
		for m3 in machines:
			if m3.demolish or m3.user >= 0 or m3.working or m3.broken or m3.product == "" or m3.is_batch() or not m3.enabled:
				continue
			var key3 := "%s:%d" % [m3.product, m3.job_step]
			if m3.setup_key == key3 or _coolf(w, "op%d", m3.id):
				continue
			var sp3 := _free_spot(m3, w)
			if sp3.is_empty():
				continue
			cands.append({"s": 240.0 - _dist(wc, sp3["cell"]) * 0.3, "k": "presetup", "t": m3, "spot": sp3, "key": key3})

	if w.has_meta("order_only") or w.has_meta("order_bp"):
		# 1.15: по приказу — только работа на указанном месте
		var oid := int(w.get_meta("order_only", -1))
		var obp := int(w.get_meta("order_bp", -1))
		cands = cands.filter(func(cd: Dictionary) -> bool:
			if obp >= 0:
				return cd.has("idx") and int(cd["idx"]) == obp
			for key in ["t", "dest"]:
				if cd.has(key) and cd[key] is Thing and (cd[key] as Thing).id == oid:
					return true
			return false)

	cands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a["s"]) > float(b["s"]))
	var tries := 0
	for cd: Dictionary in cands:
		var task := _make_task(w, cd)
		if task:
			return task
		tries += 1
		if tries >= 4:
			break
	return null


# ================================================================ 1.15: приказы игрока (1.19: управление)

## Можно ли вообще командовать человеком. Пустая строка — можно.
func order_block(w: Worker) -> String:
	if w.visitor or not w.present:
		return L.t("%s сейчас не на заводе") % w.full_name()
	if w.is_itr():
		return L.t("ИТР работают в кабинетах — управлять можно только рабочими")
	if w.sick_until > sim.minute:
		return L.t("%s на больничном") % w.full_name()
	return ""


## Кто сейчас под управлением (или null).
func controlled_worker() -> Worker:
	for w in sim.workers:
		if w.controlled:
			return w
	return null


## 1.19: взять человека под управление — он бросает своё и ждёт команд. Предыдущего отпускаем.
func take_control(w: Worker) -> String:
	var why := order_block(w)
	if why != "":
		return why
	for o in sim.workers:
		if o.controlled and o != w:
			release_control(o)
	w.controlled = true
	abort(w)
	return Nicks.gendered(L.t("%s под вашим управлением: щёлкните по стройке, станку, грузу или месту — сделает сейчас."), w.female) % w.full_name()


func release_control(w: Worker) -> void:
	if not w.controlled:
		return
	w.controlled = false
	w.order = {}
	abort(w)


## 1.19: что человек может сделать в этой клетке — для меню «Сделать сейчас».
## Каждый вариант: {key, label, ok, why}.
func order_options(w: Worker, c: Vector2i) -> Array:
	var out: Array = []
	if not sim.world.inb(c):
		return out
	var i := sim.world.idx(c)
	# авария и чертежи сетей
	for layer in ["cable", "pipe", "duct", "air"]:
		if sim.world.net_at(layer, c) == 2:
			var nm := L.t(str(Sim.NET_NAMES.get(layer, "сеть")).get_slice(": ", 1))
			var fault := sim.faults.at(layer, c)
			var lab := (L.t("Чинить аварию сейчас: %s") % L.t(str(Faults.LAYERS.get(layer, ""))).to_lower()) if fault else (L.t("Проложить сейчас: %s") % nm)
			var ok := fault or _can_lay(w, layer)
			out.append({"key": "net:" + layer, "label": lab, "ok": ok, "why": "" if ok else L.t("%s не умеет — нужен электрик или строитель") % L.name(w.first)})
	# чертёж стройки
	if sim.bp_cells.has(i):
		var ok2 := sim.bp_ready(i)
		var why2 := ""
		if not ok2:
			why2 = L.t("сначала нужно достроить то, что рядом (пол или соседнюю стену)")
		elif sim.bmats.enabled and not sim.bmats.ready(i):
			ok2 = false
			why2 = L.t("нет стройматериала на участке — закажите в «Стройке»")
		out.append({"key": "bp", "label": L.t("Строить сейчас: %s") % _bp_what(i), "ok": ok2, "why": why2})
	# объект
	var th := sim.thing_at(c)
	if th and th.kind() != "light":
		var lab3 := ""
		var why3 := ""
		if th.demolish:
			lab3 = L.t("Демонтировать сейчас: %s") % th.title()
		elif not th.built:
			lab3 = L.t("Собрать сейчас: %s") % th.title()
			if th.crates_need > 0 and th.crates_in < th.crates_need and th.order_eta >= 0.0:
				why3 = L.t("ящики с оборудованием ещё в пути")
		elif th.broken:
			lab3 = L.t("Чинить сейчас: %s") % th.title()
		elif th.kind() == "machine":
			lab3 = L.t("Встать за станок сейчас: %s") % th.title()
			if th.product == "":
				why3 = L.t("станок без задания — сначала назначьте деталь")
			elif not sim.prod.can_operate(w, th):
				why3 = L.t("%s не умеет работать на этом станке") % L.name(w.first)
		elif not th.spots().is_empty() or th.is_storage():
			lab3 = L.t("Работать здесь: %s") % th.title()
		if lab3 != "":
			out.append({"key": "thing", "label": lab3, "ok": why3 == "", "why": why3})
	# груз на полу
	for it: Item in sim.logi.ground_on(c):
		if it.reserved_by >= 0 and it.reserved_by != w.id:
			continue
		out.append({"key": "item:%d" % it.id, "label": L.t("Отнести сейчас: %s") % it.display_name(), "ok": true, "why": ""})
		break
	if sim.world.passable(c):
		out.append({"key": "go", "label": L.t("Идти сюда"), "ok": true, "why": ""})
	return out


func _can_lay(w: Worker, layer: String) -> bool:
	var builder := w.prof == "builder" or w.prof == "laborer"
	if layer == "cable":
		return w.prof == "electrician" or builder or w.skill("electric") >= 2
	return builder or w.skill("build") >= 3


func _bp_what(i: int) -> String:
	var wv := sim.world.bp_wall[i]
	if wv != World.BP_NONE:
		if wv == 0:
			return L.t("снос стены")
		return L.t("стена") if WallKinds.is_plain(wv) else str(Defs.wall_by_id.get(wv, {}).get("name", L.t("стена"))).to_lower()
	if sim.world.flora[i] != 0:
		return L.t("расчистка")
	return L.t("пол") if sim.world.bp_floor[i] != 0 else L.t("разборка пола")


## Приказ. key — что именно сделать (из order_options); пустой — как раньше: объект, стройка или идти.
func give_order(w: Worker, c: Vector2i, key: String = "") -> String:
	var why := order_block(w)
	if why != "":
		return why
	if not sim.world.inb(c):
		return ""
	if key == "":
		var opts := order_options(w, c)
		for o: Dictionary in opts:
			if bool(o["ok"]):
				key = str(o["key"])
				break
		if key == "":
			if not opts.is_empty():
				return "%s: %s" % [L.name(w.first), str(opts[0]["why"])]
			key = "go"
	var th := sim.thing_at(c) if key == "thing" else null
	var bpi := sim.world.idx(c) if key == "bp" else -1
	var item_id := int(key.get_slice(":", 1)) if key.begins_with("item:") else -1
	var layer := key.get_slice(":", 1) if key.begins_with("net:") else ""
	var goal := c
	if th:
		var acc := best_access(th, w.cell())
		goal = acc if acc.x >= 0 else c
	elif not sim.world.passable(c):
		goal = sim.world.nearest_passable(c, 2)
	if goal.x < 0 or not sim.world.reachable(w.cell(), goal):
		return L.t("Туда %s не пройти") % L.name(w.first)
	abort(w)
	w.order = {"cx": c.x, "cy": c.y, "thing": th.id if th else -1, "bp": bpi, "item": item_id, "net": layer,
		"until": sim.minute + (600.0 if w.controlled else 180.0)}
	var what := L.t("идти сюда")
	if th:
		what = L.t("работать: %s") % th.title()
	elif bpi >= 0:
		what = L.t("строить: %s") % _bp_what(bpi)
	elif item_id >= 0:
		var it0: Item = sim.items.get(item_id)
		what = L.t("отнести: %s") % (it0.display_name() if it0 else L.t("груз"))
	elif layer != "":
		what = L.t(str(NET_LABEL.get(layer, "сеть"))).to_lower()
	if w.controlled:
		return L.t("%s: %s — сейчас.") % [w.full_name(), what]
	return Nicks.gendered(L.t("%s получил{|а} приказ — %s. Потом сам{|а} вернётся к обычной работе."), w.female) % [w.full_name(), what]


func end_order(w: Worker, why: String) -> void:
	if w.order.is_empty():
		return
	w.order = {}
	if w.controlled:
		sim.notify(Nicks.gendered(L.t("%s: %s — ждёт следующей команды."), w.female) % [w.full_name(), why], Sim.LVL_INFO, w.cell())
		return
	sim.notify(Nicks.gendered(L.t("%s вернул{ся|ась} к обычной работе: %s."), w.female) % [w.full_name(), why], Sim.LVL_INFO, w.cell())


## 1.19: задача по приказу — построить конкретный чертёж, проложить конкретную сеть, унести конкретный груз.
func _order_direct(w: Worker, od: Dictionary) -> Task:
	var c := Vector2i(int(od["cx"]), int(od["cy"]))
	var i := sim.world.idx(c)
	var bpi := int(od.get("bp", -1))
	if bpi >= 0:
		if not sim.bp_cells.has(bpi):
			return null
		if sim.bp_res.has(bpi) or not sim.bp_ready(bpi) or not sim.bmats.ready(bpi):
			return null
		return _make_task(w, {"s": 999.0, "k": "build_bp", "idx": bpi})
	var layer := str(od.get("net", ""))
	if layer != "":
		if sim.world.net_at(layer, c) != 2 or sim.net_res.has("%s:%d" % [layer, i]):
			return null
		return _make_task(w, {"s": 999.0, "k": "lay_net", "layer": layer, "idx": i})
	var iid := int(od.get("item", -1))
	if iid >= 0:
		var it: Item = sim.items.get(iid)
		if it == null or it.loc != Item.Loc.GROUND or (it.reserved_by >= 0 and it.reserved_by != w.id):
			return null
		var dst: Array = _route_dest(it, it.cell) if (it.cat() == "machined" or it.cat() == "wip") else []
		if dst.is_empty():
			dst = sim.find_storage(it, it.cell)
		if dst.is_empty():
			return null
		return _make_task(w, {"s": 999.0, "k": "haul", "item": it, "dest": dst[0], "slot": dst[1]})
	return null


func _order_done(od: Dictionary) -> bool:
	var c := Vector2i(int(od["cx"]), int(od["cy"]))
	var bpi := int(od.get("bp", -1))
	if bpi >= 0:
		return not sim.bp_cells.has(bpi)
	var layer := str(od.get("net", ""))
	if layer != "":
		return sim.world.net_at(layer, c) != 2
	var iid := int(od.get("item", -1))
	if iid >= 0:
		var it: Item = sim.items.get(iid)
		return it == null or it.loc != Item.Loc.GROUND
	return false


func _order_task(w: Worker) -> Task:
	var od := w.order
	if sim.minute > float(od.get("until", 0.0)):
		end_order(w, L.t("время приказа вышло"))
		return null
	var c := Vector2i(int(od["cx"]), int(od["cy"]))
	var th: Thing = sim.things.get(int(od.get("thing", -1)))
	var direct := int(od.get("bp", -1)) >= 0 or str(od.get("net", "")) != "" or int(od.get("item", -1)) >= 0
	if direct:
		if _order_done(od):
			end_order(w, L.t("сделано") if bool(od.get("worked", false)) else L.t("уже сделали"))
			return null
		var dt := _order_direct(w, od)
		if dt:
			od["worked"] = true
			dt.label += L.t(" (по приказу)")
			return dt
		if int(od.get("idle", 0)) >= 3:
			end_order(w, L.t("сейчас это сделать нельзя"))
			return null
		od["idle"] = int(od.get("idle", 0)) + 1
		var acc0 := _adjacent_access(c, w.cell())
		return _order_wait(w, acc0 if acc0.x >= 0 else c, L.t("Ждёт по команде у стройки"), 5.0, false)
	if th:
		w.set_meta("order_only", th.id)
		var t := _find_work(w)
		w.remove_meta("order_only")
		if t:
			od["worked"] = true
			t.label += L.t(" (по приказу)")
			return t
		if bool(od.get("worked", false)):
			end_order(w, L.t("работа на месте закончилась"))
			return null
		if int(od.get("idle", 0)) >= 2:
			end_order(w, L.t("там ему делать нечего") if not w.female else L.t("там ей делать нечего"))
			return null
		od["idle"] = int(od.get("idle", 0)) + 1
		var acc := best_access(th, w.cell())
		return _order_wait(w, acc if acc.x >= 0 else c, L.t("Ждёт по команде у «%s»") % th.title(), 8.0, false)
	return _order_wait(w, c if sim.world.passable(c) else sim.world.nearest_passable(c, 2), L.t("Идёт, куда велели"), 30.0 if not w.controlled else 2.0, true)


func _order_wait(w: Worker, cell: Vector2i, label: String, mins: float, finish: bool) -> Task:
	if cell.x < 0 or not sim.world.reachable(w.cell(), cell):
		end_order(w, L.t("туда не пройти"))
		return null
	var t := Task.new()
	t.kind = "order"
	t.label = label
	t.add({"t": "goto", "cell": cell})
	t.add({"t": "work", "what": "order_wait", "dur": mins, "anim": "idle", "finish": finish})
	return t


## Сколько единиц можно унести за раз.
func carry_cap(it: Item) -> int:
	if Production.is_heavy(it):
		return 1   # тяжёлую деталь — по одной (краном или волоком)
	if it.kind == "bmat":
		return BuildMats.carry(it.def_id)   # кирпич — по два поддона на тачке, дверь — одна
	return sim.office.carry_cap()  # пачка или ящик; с канбаном — больше


## Ещё грузы того же типа в том же месте (для переноски пачкой).
func _stack_mates(it: Item, limit: int) -> Array[int]:
	var out: Array[int] = []
	if limit <= 0:
		return out
	var pool: Array = []
	match it.loc:
		Item.Loc.THING:
			var th: Thing = sim.things.get(it.holder)
			if th:
				pool = sim.slot_ids(th, it.slot)
		Item.Loc.VEHICLE:
			pool = sim.veh_items.get(it.holder, [])
		Item.Loc.GROUND:
			pool = sim.ground_items
	var key := it.stack_key()
	for iid in pool:
		if iid == it.id:
			continue
		var o: Item = sim.items.get(iid)
		if o == null or o.reserved_by >= 0 or o.stack_key() != key:
			continue
		if it.loc == Item.Loc.GROUND and o.cell != it.cell:
			continue
		out.append(iid)
		if out.size() >= limit:
			break
	return out


## 1.22: что можно подвезти к станкам — один раз за игровую минуту раскладываем свободные предметы по «ключам»
## (металл такой-то, деталь такая-то на таком-то шаге), а станок смотрит только свой список.
var _feed_min := -1.0
var _feed_idx := {}


static func feed_key(it: Item) -> String:
	if it.kind == "mat":
		return "mat:" + it.def_id
	if it.kind == "part":
		return "part:%s:%s:%d" % [it.def_id, it.q, it.step if it.q == "wip" else 0]
	return ""


func _feed_lists(m: Thing) -> Array:
	var p := m.product
	if m.job_step == 0:
		if Defs.is_assembly(p):
			var out: Array = []
			for c in Defs.components(p).keys():
				out.append("part:%s:ok:0" % str(c))
			return out
		return ["mat:" + str(Defs.products[p].get("material", ""))]
	return ["part:%s:wip:%d" % [p, m.job_step]]


## 1.26: общие для всех списки «доски работ» — считаются раз за игровой шаг, а не для каждого,
## кто ищет работу (на 300 людях поиск работы — 9/10 хода).
var _jb_min := -1.0
var _jb_pending: Array[Thing] = []
var _jb_hungry: Array[Thing] = []
var _jb_qc: Array[Thing] = []


func _job_board() -> void:
	if sim.minute == _jb_min:
		return
	_jb_min = sim.minute
	_jb_pending.clear()
	for t: Thing in sim.things.values():
		if not t.built or t.demolish:
			_jb_pending.append(t)
	_jb_hungry.clear()
	for m in sim.things_of("machine"):
		if m.demolish or m.product == "" or m.broken:
			continue
		m.ensure_incoming()
		var room := m.slot_cap(0) - sim.count_slot(m, 0) - int(m.incoming[0])
		if room > 0 and sim.planner.should_feed(m):
			_jb_hungry.append(m)
	_jb_qc.clear()
	for q in sim.usable_of("qc"):
		if q.demolish or q.user >= 0:
			continue
		for iid in sim.slot_ids(q, 0):
			var it0: Item = sim.items.get(iid)
			if it0 and it0.reserved_by < 0:
				_jb_qc.append(q)
				break


## Недостроенное и то, что сносят.
func _pending_things() -> Array[Thing]:
	_job_board()
	return _jb_pending


## Станки, к которым надо подвезти металл или детали (в пределах шага место могли занять — проверяем ещё раз).
func _hungry_machines(machines: Array[Thing]) -> Array[Thing]:
	_job_board()
	var out: Array[Thing] = []
	for m in _jb_hungry:
		if not machines.has(m) or m.demolish or m.broken:
			continue
		m.ensure_incoming()
		if m.slot_cap(0) - sim.count_slot(m, 0) - int(m.incoming[0]) > 0:
			out.append(m)
	return out


## Столы ОТК, на которых ждёт деталь.
func _qc_with_parts() -> Array[Thing]:
	_job_board()
	return _jb_qc.filter(func(q: Thing) -> bool: return q.user < 0 and not q.demolish)


func _nearest_feed(m: Thing, w: Worker) -> Item:
	if sim.minute != _feed_min:
		_feed_min = sim.minute
		_feed_idx.clear()
		for it0: Item in sim.items.values():
			if it0.reserved_by >= 0:
				continue
			if it0.loc != Item.Loc.GROUND and it0.loc != Item.Loc.THING:
				continue
			var k := feed_key(it0)
			if k == "":
				continue
			if not _feed_idx.has(k):
				_feed_idx[k] = []
			(_feed_idx[k] as Array).append(it0)
	var best: Item = null
	var bd := INF
	var fo := {}
	for key: String in _feed_lists(m):
		for it: Item in _feed_idx.get(key, []):
			if it.reserved_by >= 0 or sim.items.get(it.id) != it:
				continue
			var d := _dist(sim.item_cell(it), m.cell)
			if d >= bd:
				continue
			if not _feed_source_ok(it, m) or not sim.prod.wants(m, it):
				continue
			if it.q == "ok":
				if not fo.has(it.def_id):
					fo[it.def_id] = sim.planner.free_ok(it.def_id)
				if int(fo[it.def_id]) <= 0:
					continue
			if _coolf(w, "item%d", it.id):
				continue
			bd = d
			best = it
	return best


func _nearest_item(pred: Callable, near: Vector2i, w: Worker) -> Item:
	# 1.22: сначала дешёвые проверки, «остывание» (строка) — только для того, кто ближе лучшего
	var best: Item = null
	var bd := INF
	for it: Item in sim.items.values():
		if it.reserved_by >= 0:
			continue
		var d := _dist(sim.item_cell(it), near)
		if d >= bd:
			continue
		if not pred.call(it):
			continue
		if _coolf(w, "item%d", it.id):
			continue
		bd = d
		best = it
	return best


## Превращает кандидата в задачу с резервированием. null — если не дойти.
func _make_task(w: Worker, cd: Dictionary) -> Task:
	var wc := w.cell()
	var t := Task.new()
	t.kind = str(cd["k"])
	match t.kind:
		"sweep":
			var left: Array = (cd["cells"] as Array).duplicate()
			var cur := wc
			var n := 0
			while not left.is_empty() and n < 6:
				var bi := 0
				var bd := INF
				for k in left.size():
					var dd := _dist(left[k], cur)
					if dd < bd:
						bd = dd
						bi = k
				var c: Vector2i = left[bi]
				left.remove_at(bi)
				if n == 0 and not sim.world.reachable(wc, c):
					_set_cool(w, "sweep", 60.0)
					return null
				t.add({"t": "goto", "cell": c})
				t.add({"t": "work", "what": "sweep", "cell": c, "dur": 2.5, "anim": "work"})
				cur = c
				n += 1
			if n == 0:
				return null
			t.label = L.t("Чистит снег")
			t.data["prop"] = "shovel"
			t.data["cool"] = "sweep"
			return t
		"clean":
			var left2: Array = (cd["cells"] as Array).duplicate()
			var cur2 := wc
			var n2 := 0
			while not left2.is_empty() and n2 < 6:
				var bi2 := 0
				var bd2 := INF
				for k2 in left2.size():
					var dd2 := _dist(left2[k2], cur2)
					if dd2 < bd2:
						bd2 = dd2
						bi2 = k2
				var c2: Vector2i = left2[bi2]
				left2.remove_at(bi2)
				if n2 == 0 and not sim.world.reachable(wc, c2):
					_set_cool(w, "clean", 30.0)
					return null
				t.add({"t": "goto", "cell": c2})
				t.add({"t": "work", "what": "clean", "cell": c2, "dur": 2.4, "anim": "work"})
				cur2 = c2
				n2 += 1
			if n2 == 0:
				return null
			t.label = L.t("Убирает стружку и мусор")
			t.data["prop"] = "broom"
			t.data["cool"] = "clean"
			return t
		"saw":
			var sw: Thing = cd["t"]
			var spw: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, spw["cell"]):
				_set_cool(w, "th%d" % sw.id)
				return null
			sw.user = w.id
			t.res_users.append(sw.id)
			t.label = L.t("Режет заготовки: %s") % Defs.material_name(str(cd["mat"]))
			t.add({"t": "goto", "cell": spw["cell"], "face": spw["face"]})
			t.add({"t": "work", "what": "saw", "thing": sw.id, "mat": str(cd["mat"]), "dur": 16.0, "anim": "work"})
			t.data["cool"] = "th%d" % sw.id
			return t
		"exam":
			var et: Thing = cd["t"]
			var esp2: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, esp2["cell"]):
				_set_cool(w, "exam", 30.0)
				return null
			et.user = w.id
			t.res_users.append(et.id)
			t.label = L.t("Сдаёт на %d-й разряд: пробная деталь") % (w.grade() + 1)
			t.add({"t": "goto", "cell": esp2["cell"], "face": esp2["face"]})
			t.add({"t": "work", "what": "exam", "thing": et.id, "dur": Careers.EXAM_TIME, "anim": "work"})
			return t
		"rework", "hand_saw":
			var wb: Thing = cd["t"]
			var spb: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, spb["cell"]):
				_set_cool(w, "th%d" % wb.id)
				return null
			if t.kind == "rework":
				var rit: Item = cd["item"]
				var rsrc := _src_cell(rit, wc)
				if rsrc.x < 0 or not sim.world.reachable(wc, rsrc) or not sim.world.reachable(rsrc, spb["cell"]):
					_set_cool(w, "item%d" % rit.id)
					return null
				rit.reserved_by = w.id
				t.res_items.append(rit.id)
				t.label = L.t("Дорабатывает брак: %s") % Defs.product_name(rit.def_id)
				t.add({"t": "goto", "cell": rsrc})
				t.add({"t": "pickup", "item": rit.id, "extra": []})
				t.add({"t": "goto", "cell": spb["cell"], "face": spb["face"]})
				t.add({"t": "work", "what": "rework", "thing": wb.id, "dur": 22.0 * clampf(1.3 - 0.06 * w.skill("fitting"), 0.6, 1.3), "anim": "work"})
			else:
				t.label = L.t("Режет заготовки ножовкой: %s") % Defs.material_name(str(cd["mat"]))
				t.add({"t": "goto", "cell": spb["cell"], "face": spb["face"]})
				t.add({"t": "work", "what": "hand_saw", "thing": wb.id, "mat": str(cd["mat"]), "dur": 26.0, "anim": "work"})
			wb.user = w.id
			t.res_users.append(wb.id)
			t.data["cool"] = "th%d" % wb.id
			return t
		"presetup":
			var pm: Thing = cd["t"]
			var spp: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, spp["cell"]):
				_set_cool(w, "op%d" % pm.id)
				return null
			pm.user = w.id
			t.res_users.append(pm.id)
			t.label = L.t("Налаживает станок: %s") % Defs.product_name(pm.product)
			t.add({"t": "goto", "cell": spp["cell"], "face": spp["face"]})
			t.add({"t": "work", "what": "setup", "thing": pm.id, "key": str(cd["key"]), "dur": sim.office.setup_time() * clampf(0.85 - w.skill("setup") * 0.04, 0.45, 0.85), "anim": "work"})
			t.data["cool"] = "op%d" % pm.id
			return t
		"operate":
			var m: Thing = cd["t"]
			var sp: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, sp["cell"]):
				_set_cool(w, "op%d" % m.id)
				return null
			m.user = w.id
			t.res_users.append(m.id)
			t.label = _op_label(m)
			t.add({"t": "goto", "cell": sp["cell"], "face": sp["face"]})
			var key := "%s:%d" % [m.product, m.job_step]
			if not m.is_batch() and m.setup_key != key:
				t.label = L.t("Переналадка: %s") % Defs.product_name(m.product)
				t.add({"t": "work", "what": "setup", "thing": m.id, "key": key, "dur": sim.office.setup_time(), "anim": "work"})
			if m.is_batch():
				t.add({"t": "work", "what": "start_batch", "thing": m.id, "dur": 6.0, "anim": "work"})
			else:
				t.add({"t": "work", "what": "operate", "thing": m.id, "dur": 0.0, "anim": "work"})
			t.data["cool"] = "op%d" % m.id
			return t
		"inspect":
			var q: Thing = cd["t"]
			var sp2: Dictionary = cd["spot"]
			if not sim.world.reachable(wc, sp2["cell"]):
				_set_cool(w, "qc%d" % q.id)
				return null
			q.user = w.id
			t.res_users.append(q.id)
			t.data["qc"] = q.id
			t.data["cool"] = "qc%d" % q.id
			t.label = L.t("Проверяет детали (ОТК)")
			t.add({"t": "goto", "cell": sp2["cell"], "face": sp2["face"]})
			t.add({"t": "take_qc", "thing": q.id})
			t.add({"t": "work", "what": "inspect", "thing": q.id, "dur": 0.0, "anim": "work"})
			t.add({"t": "route"})
			return t
		"haul":
			var it: Item = cd["item"]
			var dest: Thing = cd["dest"]
			var slot := int(cd["slot"])
			var src := _src_cell(it, wc)
			var dst := best_access(dest, src)
			if src.x < 0 or dst.x < 0 or not sim.world.reachable(wc, src) or not sim.world.reachable(src, dst):
				_set_cool(w, "item%d" % it.id)
				return null
			var room := sim.free_space(dest, slot, it.stack_key())
			if room <= 0:
				return null
			if dest.kind() == "machine" and slot == 0 and dest.job_step == 0 and Defs.is_assembly(dest.product):
				room = mini(room, maxi(1, int(Defs.components(dest.product).get(it.def_id, 1))))
			var cap := carry_cap(it)
			var avail_n := 1 + _stack_mates(it, 30).size()
			if avail_n >= 7 and room >= 7:
				var veh := _haul_vehicle(w)
				if veh:
					veh.user = w.id
					t.res_users.append(veh.id)
					t.data["veh"] = veh.def_id
					cap = int(Defs.b("forklift_cap")) if veh.def_id == "forklift" else int(Defs.b("cart_cap"))
			var extra := _stack_mates(it, mini(cap - 1, room - 1))
			for iid in [it.id] + extra:
				var ri: Item = sim.items[iid]
				ri.reserved_by = w.id
				t.res_items.append(iid)
				sim.reserve_incoming(dest, slot, it.stack_key())
				t.res_incoming.append([dest.id, slot])
			var n := 1 + extra.size()
			var verb := L.t("Везёт на погрузчике") if t.data.get("veh", "") == "forklift" else (L.t("Везёт на тележке") if t.data.has("veh") else L.t("Несёт"))
			if Production.is_heavy(it) and not t.data.has("veh"):
				# 1.14: тяжёлую деталь в зале с кран-балкой несёт кран, человек ведёт пультом
				var cr := sim.prod.crane_at(src)
				if cr and sim.prod.crane_at(dst) == cr:
					verb = L.t("Ведёт краном")
					t.data["prop"] = "pendant"
					t.data["crane"] = cr.id
				else:
					verb = L.t("Тащит")
			t.label = "%s: %s" % [verb, it.display_name()] + (" ×%d" % n if n > 1 else "")
			t.data["cool"] = "item%d" % it.id
			t.add({"t": "goto", "cell": src})
			t.add({"t": "pickup", "item": it.id, "extra": extra})
			t.add({"t": "goto", "cell": dst})
			t.add({"t": "put", "thing": dest.id, "slot": slot})
			return t
		"load":
			var it2: Item = cd["item"]
			var v: Vehicle = cd["veh"]
			var src2 := _src_cell(it2, wc)
			var dst2 := v.access_cell(sim.world.sidewalk_row)
			if src2.x < 0 or not sim.world.reachable(wc, src2) or not sim.world.reachable(src2, dst2):
				_set_cool(w, "item%d" % it2.id)
				return null
			var left := v.need - v.loaded - v.reserved_load
			var extra2 := _stack_mates(it2, mini(carry_cap(it2) - 1, left - 1))
			for iid2 in [it2.id] + extra2:
				var ri2: Item = sim.items[iid2]
				ri2.reserved_by = w.id
				t.res_items.append(iid2)
			var n2 := 1 + extra2.size()
			v.reserved_load += n2
			t.res_load = v.id
			t.data["load_n"] = n2
			t.label = L.t("Грузит заказ в машину") + (" ×%d" % n2 if n2 > 1 else "")
			t.data["cool"] = "item%d" % it2.id
			t.add({"t": "goto", "cell": src2})
			t.add({"t": "pickup", "item": it2.id, "extra": extra2})
			t.add({"t": "goto", "cell": dst2})
			t.add({"t": "put_vehicle", "veh": v.id})
			return t
		"build_bp":
			var i := int(cd["idx"])
			var c := sim.world.cell_of(i)
			var stand := c
			var wv := sim.world.bp_wall[i]
			var solid_target := wv != World.BP_NONE and (Defs.wall_solid(wv) or Defs.wall_solid(sim.world.wall[i]))
			if solid_target or not sim.world.passable(c):
				stand = _adjacent_access(c, wc)
			if stand.x < 0 or not sim.world.reachable(wc, stand):
				_set_cool(w, "bp%d" % i, 20.0)
				return null
			sim.bp_res[i] = w.id
			t.res_bp.append(i)
			var what := L.t("Строит")
			var nm := ""
			if wv != World.BP_NONE:
				nm = L.t("стену") if WallKinds.is_plain(wv) else str(Defs.wall_by_id.get(wv, {}).get("name", "")).to_lower()
				if wv == 0:
					what = L.t("Сносит")
					nm = L.t("стену")
			else:
				var fv := sim.world.bp_floor[i]
				nm = L.t("пол")
				if fv == 0:
					what = L.t("Разбирает")
				var fl := sim.world.flora[i]
				if fl != 0 and (fv == 0 and sim.world.flr[i] == 0):
					what = L.t("Спиливает") if fl <= 3 else L.t("Выкорчёвывает")
					nm = L.t("дерево") if fl <= 3 else L.t("куст")
				elif fl != 0:
					what = L.t("Расчищает место под")
			t.label = "%s %s" % [what, nm]
			t.data["cool"] = "bp%d" % i
			if what == L.t("Строит"):
				t.data["prop"] = "hammer"   # 1.15: строитель с понятным молотком
			var mat := sim.bmats.mat_for(i) if sim.bmats.enabled else ""
			if mat != "":
				return _build_with_mat(w, t, i, mat, stand)
			t.add({"t": "goto", "cell": stand, "face": _face_to(stand, c)})
			t.add({"t": "work", "what": "build_bp", "idx": i, "dur": sim.bp_work_time(i) * _build_k(w), "anim": "work"})
			return t
		"lay_net":
			return _lay_net_task(w, t, str(cd["layer"]), int(cd["idx"]))
		"haul_cell", "deliver":
			return sim.logi.make_task(self, w, cd)
		"build_thing", "demolish", "repair", "reset", "fix":
			var th: Thing = cd["t"]
			var acc := best_access(th, wc)
			if acc.x < 0 and not th.blocks():
				acc = th.cell
			if acc.x < 0 or not sim.world.reachable(wc, acc):
				_set_cool(w, "th%d" % th.id, 20.0)
				return null
			th.user = w.id
			t.res_users.append(th.id)
			t.data["cool"] = "th%d" % th.id
			var dur := float(th.def().get("build_time", 10)) * _build_k(w)
			var what := "build_thing"
			t.data["prop"] = "hammer" if t.kind == "build_thing" else "toolbox"
			if t.kind == "demolish":
				dur *= 0.5
				what = "demolish_thing"
				t.label = L.t("Демонтирует: %s") % th.title()
			elif t.kind == "repair":
				dur = Defs.b("service_time") * (0.8 if w.prof in ["turner", "electrician"] else (0.7 if w.prof == "fitter" else 1.0)) * _build_k(w)
				if w.prof == "fitter" and sim.office.has_tech("fit_jigs"):
					dur *= 0.8
				what = "repair"
				t.label = L.t("Обслуживает станок")
			elif t.kind == "fix":
				dur = Defs.b("repair_time") * (0.75 if w.prof in ["electrician", "turner", "miller"] else (0.65 if w.prof == "fitter" else 1.0)) * _build_k(w)
				if w.prof == "fitter" and sim.office.has_tech("fit_jigs"):
					dur *= 0.8
				what = "fix"
				t.label = L.t("Ремонтирует станок")
			elif t.kind == "reset":
				dur = Defs.b("breaker_reset_time") * (0.6 if w.prof == "electrician" else 1.0)
				what = "reset"
				t.label = L.t("Сбрасывает автомат на подстанции")
			else:
				t.label = L.t("Монтирует: %s") % th.title()
			t.add({"t": "goto", "cell": acc, "face": _face_to_rect(acc, th.rect())})
			t.add({"t": "work", "what": what, "thing": th.id, "dur": dur, "anim": "work"})
			return t
	return null


## Стройка из материала (1.13): взять со штабеля сколько унесёшь и построить клетки рядом
## по одной. Первая клетка уже забронирована вызывающим.
func _build_with_mat(w: Worker, t: Task, i0: int, mat: String, stand0: Vector2i) -> Task:
	var wc := w.cell()
	var c0 := sim.world.cell_of(i0)
	# ближайший к стройке свободный штабель этого материала
	var pile: Item = null
	var bd := INF
	for gid in sim.ground_items:
		var it: Item = sim.items.get(gid)
		if it == null or it.kind != "bmat" or it.def_id != mat or it.reserved_by >= 0:
			continue
		var d := _dist(it.cell, c0) + _dist(it.cell, wc) * 0.5
		if d < bd:
			bd = d
			pile = it
	if pile == null:
		sim.bp_res.erase(i0)
		t.res_bp.erase(i0)
		_set_cool(w, "bp%d" % i0, 15.0)
		return null
	var src := _src_cell(pile, wc)
	if src.x < 0 or not sim.world.reachable(wc, src) or not sim.world.reachable(src, stand0):
		sim.bp_res.erase(i0)
		t.res_bp.erase(i0)
		_set_cool(w, "item%d" % pile.id)
		_set_cool(w, "bp%d" % i0, 20.0)
		return null
	# ещё клетки того же материала рядом с первой — сколько унесёт за раз
	var cap := BuildMats.carry(mat)
	var cells: Array[int] = [i0]
	if cap > 1:
		var near: Array = []
		for k in sim.bp_cells.keys():
			var ki := int(k)
			if ki == i0 or sim.bp_res.has(ki) or sim.bmats.mat_for(ki) != mat or not sim.bp_ready(ki):
				continue
			var dk := _dist(sim.world.cell_of(ki), c0)
			if dk <= 6.0:
				near.append([dk, ki])
		near.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
		for pr: Array in near:
			if cells.size() >= cap:
				break
			cells.append(int(pr[1]))
	var extra := _stack_mates(pile, cells.size() - 1)
	while cells.size() > 1 + extra.size():
		cells.pop_back()
	pile.reserved_by = w.id
	t.res_items.append(pile.id)
	for eid in extra:
		(sim.items[eid] as Item).reserved_by = w.id
		t.res_items.append(eid)
	t.add({"t": "goto", "cell": src})
	t.add({"t": "pickup", "item": pile.id, "extra": extra})
	var cur := src
	for ci in cells:
		var cc := sim.world.cell_of(ci)
		var wv := sim.world.bp_wall[ci]
		var solid := wv != World.BP_NONE and (Defs.wall_solid(wv) or Defs.wall_solid(sim.world.wall[ci]))
		var st := cc if not solid and sim.world.passable(cc) else _adjacent_access(cc, cur)
		if ci == i0:
			st = stand0
		if st.x < 0:
			continue
		if ci != i0:
			sim.bp_res[ci] = w.id
			t.res_bp.append(ci)
		t.add({"t": "goto", "cell": st, "face": _face_to(st, cc)})
		t.add({"t": "work", "what": "build_bp", "idx": ci, "mat": mat, "dur": sim.bp_work_time(ci) * _build_k(w), "anim": "work"})
		cur = st
	t.add({"t": "drop_left"})
	t.label = L.t("%s · несёт: %s") % [t.label, BuildMats.mat_name(mat).to_lower()]
	return t


const NET_LABEL := {"cable": "Тянет кабель", "pipe": "Прокладывает трубу", "duct": "Монтирует воздуховод", "air": "Тянет пневмомагистраль"}
const NET_TIME := {"cable": 2.5, "pipe": 4.0, "duct": 5.0, "air": 3.0}


## Прокладка сети (1.13): до шести соседних клеток чертежа за один заход — от ближней по цепочке.
func _lay_net_task(w: Worker, t: Task, lay: String, i0: int) -> Task:
	var chain := _net_chain(lay, i0, 6)
	var cur := w.cell()
	var keys: Array = []
	for ii: int in chain:
		var c := sim.world.cell_of(ii)
		var stand := c if sim.world.passable(c) else _adjacent_access(c, cur)
		if stand.x < 0 or not sim.world.reachable(cur, stand):
			if keys.is_empty():
				_set_cool(w, "net%d" % ii, 20.0)
				return null
			break
		var key := "%s:%d" % [lay, ii]
		sim.net_res[key] = w.id
		keys.append(key)
		t.add({"t": "goto", "cell": stand, "face": _face_to(stand, c)})
		t.add({"t": "work", "what": "lay_net", "layer": lay, "idx": ii, "dur": float(NET_TIME.get(lay, 3.0)) * _build_k(w), "anim": "work"})
		cur = stand
	t.data["nets"] = keys
	t.data["cool"] = "net%d" % i0
	t.data["prop"] = "reel" if lay == "cable" else "toolbox"
	t.label = L.t(str(NET_LABEL.get(lay, "Прокладывает сеть")))
	return t


## Цепочка соседних клеток чертежа одного слоя, начиная с i0 (по ширине).
func _net_chain(lay: String, i0: int, n: int) -> Array[int]:
	var w := sim.world
	var arr := w.net_layer(lay)
	var out: Array[int] = []
	var seen := {i0: true}
	var q: Array[int] = [i0]
	while not q.is_empty() and out.size() < n:
		var i: int = q.pop_front()
		out.append(i)
		var c := w.cell_of(i)
		for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nb := c + d
			if not w.inb(nb):
				continue
			var ni := w.idx(nb)
			if seen.has(ni) or arr[ni] != 2 or sim.net_res.has("%s:%d" % [lay, ni]):
				continue
			seen[ni] = true
			q.append(ni)
	return out


## Есть ли в руках материал (consume — израсходовать одну единицу).
func _use_mat(w: Worker, mat: String, consume: bool) -> bool:
	var pool: Array = w.carry_extra.duplicate()
	if w.carrying >= 0:
		pool.append(w.carrying)
	for iid in pool:
		var it: Item = sim.items.get(int(iid))
		if it and it.kind == "bmat" and it.def_id == mat:
			if consume:
				w.task.res_items.erase(it.id)
				sim.delete_item(it)
				if w.carrying < 0 and not w.carry_extra.is_empty():
					w.carrying = w.carry_extra.pop_front()
			return true
	return false


func _build_k(w: Worker) -> float:
	return clampf(1.4 - 0.08 * w.skill("build"), 0.6, 1.4) * Mood.trait_val(w, "build_k", 1.0)


func _face_to(from: Vector2i, to: Vector2i) -> String:
	var d := to - from
	if absi(d.x) > absi(d.y):
		return "right" if d.x > 0 else "left"
	return "down" if d.y > 0 else "up"


func _face_to_rect(from: Vector2i, r: Rect2i) -> String:
	var center := r.position + r.size / 2
	if from.y >= r.end.y:
		return "up"
	if from.y < r.position.y:
		return "down"
	return _face_to(from, center)


# ================================================================ быт: туалет, обед, отдых, безделье

func _toilet_task(w: Worker) -> Task:
	if _coolf(w, "wc%d", 0):
		return null   # 1.26: только что все кабинки были заняты — не перебираем их снова каждую попытку
	var best: Thing = null
	var bd := INF
	var dry := 0
	for th in sim.usable_of("toilet"):
		if th.demolish or th.spot_users.has(0):
			continue
		if not sim.water.has_water(th):
			dry += 1
			continue
		var d := _dist(th.cell, w.cell()) - (20.0 if sim.rooms.thing_in(th, "wc") else 0.0) + sim.areas.pref(w, th, "wc")
		if d < bd and sim.world.reachable(w.cell(), th.cell):
			bd = d
			best = th
	if best == null:
		if sim.things_of("toilet").is_empty():
			sim.notify_once("notoilet", L.t("Людям некуда сходить в туалет! Поставьте туалетную кабинку."), Sim.LVL_WARN, w.cell(), 600.0)
		elif sim.usable_of("toilet").is_empty():
			sim.notify_once("zonetoilet", L.t("Туалетом не пользуются: он стоит вне зоны «Туалет». Разметьте её вокруг кабинки (Зоны → Быт и здоровье)."), Sim.LVL_WARN, w.cell(), 600.0)
		elif dry > 0 and sim.usable_of("toilet").any(func(x: Thing) -> bool: return sim.water.weak(x)):
			sim.notify_once("weaktoilet", L.t("Не хватает воды: один насос тянет %d приборов. Поставьте ещё насос или насосную станцию (Сети → Водопровод).") % Water.CITY_FIXTURES, Sim.LVL_WARN, w.cell(), 600.0)
		elif dry > 0:
			sim.notify_once("drytoilet", L.t("В туалете нет воды — кабинкой пользоваться нельзя. Поставьте насос и протяните от него трубу (меню «Сети», W)."), Sim.LVL_WARN, w.cell(), 600.0)
		_set_cool(w, "wc0", 2.0)
		return null
	var t := Task.new()
	t.kind = "toilet"
	t.label = L.t("В туалете")
	t.data["toilet"] = best.id
	best.spot_users[0] = w.id
	t.res_spots.append([best.id, 0])
	t.add({"t": "goto", "cell": best.cell, "face": "down"})
	t.add({"t": "work", "what": "toilet", "dur": Defs.b("toilet_time"), "anim": "hidden"})
	return t


func _chair_near_table(ch: Thing) -> bool:
	for d in [Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 0), Vector2i(-1, 0)]:
		var th := sim.thing_at(ch.cell + d)
		if th and th.built and th.kind() == "table" and sim.rooms.zone_ok(th):
			return true
	return false


func _eat_task(w: Worker) -> Task:
	var t := Task.new()
	t.kind = "eat"
	# 1.40: кто носит обед из дома — ест на своём месте (за столом, у станка или верстака)
	if Areas.brings_lunch(w) and not sim.story.striking(w):
		var own := _own_lunch(w, t)
		if own:
			return own
	var best: Thing = null
	var bd := INF
	for ch in sim.things_of("chair"):
		if ch.spot_users.has(0) or not _chair_near_table(ch):
			continue
		var cr := sim.rooms.room_of_thing(ch)
		if not sim.areas.canteen_ok(w, cr) or not sim.areas.own_area_ok(w, ch.cell):
			continue   # 1.40: столовая для ИТР — не для рабочих; в чужих кабинетах и цехах не обедают
		var d := _dist(ch.cell, w.cell()) - (40.0 if sim.rooms.thing_in(ch, "canteen") else 0.0) + sim.areas.canteen_pref(w, cr)
		if d < bd and sim.world.reachable(w.cell(), ch.cell):
			bd = d
			best = ch
	if best:
		best.spot_users[0] = w.id
		t.res_spots.append([best.id, 0])
		var in_canteen := sim.rooms.thing_in(best, "canteen")
		t.data["eat"] = "canteen" if in_canteen else "table"
		t.label = L.t("Обедает в столовой") if in_canteen else L.t("Обедает")
		t.add({"t": "goto", "cell": best.cell, "face": "auto"})
		t.add({"t": "work", "what": "eat", "dur": Defs.b("eat_time"), "anim": "sit"})
		return t
	var bench := _free_seat(w, "rest")
	if not bench.is_empty():
		var bt: Thing = bench["t"]
		bt.spot_users[int(bench["idx"])] = w.id
		t.res_spots.append([bt.id, int(bench["idx"])])
		t.label = L.t("Обедает на скамейке")
		t.data["eat"] = "bench"
		t.add({"t": "goto", "cell": bench["cell"], "face": "down"})
		t.add({"t": "work", "what": "eat", "dur": Defs.b("eat_time"), "anim": "sit"})
		return t
	sim.notify_once("notable", L.t("Негде пообедать. Поставьте обеденный стол и стулья вплотную к нему."), Sim.LVL_INFO, Vector2i(-1, -1), 1440.0)
	t.label = L.t("Обедает стоя")
	t.data["eat"] = "standing"
	t.add({"t": "work", "what": "eat", "dur": Defs.b("eat_time") + 5.0, "anim": "idle"})
	return t


## 1.40: обед из дома на рабочем месте. ИТР — за своим столом, рабочие — у своего станка или верстака.
func _own_lunch(w: Worker, t: Task) -> Task:
	var place: Thing = null
	if w.is_director():
		place = Director.desk(sim)
	elif w.is_itr():
		place = sim.office.desk_for(w)
	else:
		place = sim.things.get(w.workplace)
	if place == null or not place.built or place.demolish:
		return null
	var cell := Vector2i(-1, -1)
	var face := "down"
	if w.is_itr():
		var sp := _free_spot(place, w)
		if sp.is_empty():
			return null
		cell = sp["cell"]
		face = str(sp["face"])
		place.spot_users[int(sp["idx"])] = w.id
		t.res_spots.append([place.id, int(sp["idx"])])
	else:
		cell = best_access(place, w.cell())
		if cell.x >= 0:
			face = _face_to_rect(cell, place.rect())
	if cell.x < 0 or not sim.world.reachable(w.cell(), cell):
		t.res_spots.clear()
		place.spot_users.erase(place.spot_users.find_key(w.id))
		return null
	t.data["eat"] = "own"
	t.label = L.t("Обедает за своим столом: еда из дома") if w.is_itr() else L.t("Обедает на рабочем месте: еда из дома")
	t.add({"t": "goto", "cell": cell, "face": face})
	t.add({"t": "work", "what": "eat", "dur": Defs.b("eat_time"), "anim": "sit" if w.is_itr() else "idle"})
	return t


func _free_seat(w: Worker, kind: String) -> Dictionary:
	var best: Dictionary = {}
	var bd := INF
	for th in sim.usable_of(kind):
		if th.demolish:
			continue
		var bonus := (25.0 if sim.rooms.thing_in(th, "restroom") else 0.0) + float(th.def().get("comfort", 0)) * 3.0 - sim.areas.pref(w, th, "restroom")
		for sp: Dictionary in th.spots():
			if th.spot_users.has(int(sp["idx"])):
				continue
			var c: Vector2i = sp["cell"]
			if not sim.areas.own_area_ok(w, c) or not sim.areas.canteen_ok(w, sim.rooms.room_at(c)):
				continue   # 1.40: отдыхают в своей зоне
			var d := _dist(c, w.cell()) - bonus
			if d < bd and sim.world.reachable(w.cell(), c):
				bd = d
				best = {"t": th, "idx": int(sp["idx"]), "cell": c}
	return best


func _rest_task(w: Worker) -> Task:
	var seat := _free_seat(w, "rest")
	if seat.is_empty():
		seat = _free_seat(w, "chair")
	if seat.is_empty():
		return null
	var th: Thing = seat["t"]
	var t := Task.new()
	t.kind = "rest"
	t.label = L.t("Отдыхает")
	th.spot_users[int(seat["idx"])] = w.id
	t.res_spots.append([th.id, int(seat["idx"])])
	var dur := Defs.b("rest_time") * Mood.trait_val(w, "rest_k", 1.0)
	if _on_lunch(w):
		dur = maxf(5.0, _lunch_end(w) - sim.minute)
	t.data["seat"] = th.id
	t.add({"t": "goto", "cell": seat["cell"], "face": "auto" if th.kind() == "chair" else "down"})
	t.add({"t": "work", "what": "rest", "dur": dur, "anim": "sit"})
	return t


func _wander(w: Worker) -> void:
	var t := Task.new()
	t.kind = "wander"
	if Mood.trait_val(w, "work_k", 1.0) > 1.0 and not _on_lunch(w):
		Mood.add(sim, w, "idle_bad")
	var c := w.cell()
	var indoor := sim.world.is_indoor(c)
	var target := c
	for k in 8:
		var cand := c + Vector2i(sim.rng.randi_range(-4, 4), sim.rng.randi_range(-4, 4))
		if not sim.world.in_plot(cand) or not sim.world.passable(cand):
			continue
		if indoor and not sim.world.is_indoor(cand):
			continue
		if not sim.areas.own_area_ok(w, cand) and sim.areas.own_area_ok(w, c):
			continue   # 1.40: без дела в чужие кабинеты (и конторским в цех) не заходят
		if sim.world.reachable(c, cand):
			target = cand
			break
	t.label = L.t("Без дела")
	t.add({"t": "goto", "cell": target})
	t.add({"t": "work", "what": "wait", "dur": sim.rng.randf_range(4.0, 10.0), "anim": "idle"})
	assign(w, t)


# ================================================================ выполнение шагов

func _run(w: Worker, dt: float) -> void:
	var tl := w.task.current()
	if tl.is_empty():
		_finish(w)
		return
	match str(tl["t"]):
		"goto":
			var r := _move(w, tl["cell"], dt)
			if r == 1:
				_face(w, str(tl.get("face", "")))
				w.task.next()
			elif r == -1:
				_fail(w)
		"pickup":
			var it: Item = sim.items.get(int(tl["item"]))
			if it == null or it.reserved_by != w.id or it.loc == Item.Loc.WORKER:
				_fail(w)
				return
			sim.give_worker(it, w)
			for eid in tl.get("extra", []):
				var e: Item = sim.items.get(int(eid))
				if e and e.reserved_by == w.id and e.loc != Item.Loc.WORKER:
					sim.give_worker(e, w, true)
			w.task.next()
		"shadow":
			_run_shadow(w, tl, dt)
		"follow":
			var v := sim.inspect.visitor()
			if v == null:
				w.task.next()
				return
			var vc := v.cell()
			var back := {"down": Vector2i(0, -1), "up": Vector2i(0, 1), "left": Vector2i(1, 0), "right": Vector2i(-1, 0)}
			var want: Vector2i = vc + (back.get(v.dir, Vector2i(0, 1)) as Vector2i)
			if not sim.world.passable(want):
				want = sim.world.nearest_passable(want, 2)
			if w.pos.distance_to(v.pos) > 1.6 and want.x >= 0:
				_move(w, want, dt)
			else:
				w.anim = "idle"
				_set_dir(w, v.pos - w.pos)
		"drop_left":
			# не понадобилось (клетку отменили) — кладём рядом, заберут на другую стройку
			var left: Array = w.carry_extra.duplicate()
			if w.carrying >= 0:
				left.push_front(w.carrying)
			for iid in left:
				var li: Item = sim.items.get(int(iid))
				if li:
					li.reserved_by = -1
					w.task.res_items.erase(li.id)
					sim.put_on_ground(li, _off_wall_bp(w.cell() if sim.world.passable(w.cell()) else sim.world.nearest_passable(w.cell())))
			w.carrying = -1
			w.carry_extra.clear()
			w.task.next()
		"put":
			_put(w, tl)
		"drop", "put_site":
			sim.logi.run_step(self, w, tl)
		"put_vehicle":
			var v := sim.get_vehicle(int(tl["veh"]))
			if v == null or v.state != "parked" or w.carrying < 0:
				_fail(w)
				return
			var load_ids: Array = [w.carrying] + w.carry_extra.duplicate()
			for lid in load_ids:
				var it2: Item = sim.items.get(int(lid))
				if it2 == null:
					continue
				sim.put_in_vehicle(it2, v)
				it2.reserved_by = -1
				w.task.res_items.erase(it2.id)
				v.loaded += 1
				sim.orders.on_loaded(v, it2)
			v.reserved_load = maxi(0, v.reserved_load - int(w.task.data.get("load_n", 1)))
			w.task.res_load = -1
			w.task.next()
		"take_qc":
			var q: Thing = sim.things.get(int(tl["thing"]))
			if q == null:
				_fail(w)
				return
			var got: Item = null
			for iid in sim.slot_ids(q, 0):
				var cand: Item = sim.items.get(iid)
				if cand and cand.reserved_by < 0:
					got = cand
					break
			if got == null:
				_finish(w)
				return
			got.reserved_by = w.id
			w.task.res_items.append(got.id)
			sim.give_worker(got, w)
			w.task.next()
		"work":
			_work(w, tl, dt)
		"route":
			_route_inspected(w)
		"despawn":
			_despawn(w)
		"seat":
			# 1.30: сесть в будку проходной (клетка будки непроходима — переносим внутрь)
			var st: Thing = sim.things.get(int(tl.get("thing", -1)))
			if st == null or not st.built or st.seat_cell().x < 0:
				_fail(w)
				return
			w.pos = Vector2(st.seat_cell()) + BOOTH_SEAT
			w.set_meta("booth", tl["back"])
			w.path.clear()
			w.path_target = Vector2i(-999, -999)
			_face(w, str(tl.get("face", "down")))
			w.task.next()
		_:
			w.task.next()


const BOOTH_SEAT := Vector2(0.5, 0.5)   ## 1.30: где в клетке будки сидит охранник (у окна, перед задней стенкой)


## 1.30: выйти из будки обратно к турникету.
func _unseat(w: Worker) -> void:
	if not w.has_meta("booth"):
		return
	var b: Vector2i = w.get_meta("booth")
	w.remove_meta("booth")
	if sim.world.passable(b):
		w.pos = Vector2(b) + Vector2(0.5, 0.5)


func _put(w: Worker, tl: Dictionary) -> void:
	var t: Thing = sim.things.get(int(tl["thing"]))
	var s := int(tl["slot"])
	if w.carrying < 0:
		_fail(w)
		return
	if t != null:
		for k in range(w.task.res_incoming.size() - 1, -1, -1):
			var pair: Array = w.task.res_incoming[k]
			if int(pair[0]) == t.id and int(pair[1]) == s:
				sim.release_incoming(t, s)
				w.task.res_incoming.remove_at(k)
	var carried: Array = [w.carrying] + w.carry_extra.duplicate()
	for iid in carried:
		var it: Item = sim.items.get(int(iid))
		if it == null:
			continue
		if t != null and t.built and sim.free_space(t, s, it.stack_key()) > 0:
			sim.put_in_thing(it, t, s)
			w.week_score += 1
		else:
			sim.put_on_ground(it, _off_wall_bp(w.cell()))
		it.reserved_by = -1
		w.task.res_items.erase(it.id)
	w.task.next()


func _route_inspected(w: Worker) -> void:
	var q: Thing = sim.things.get(int(w.task.data.get("qc", -1)))
	if q and q.user == w.id:
		q.user = -1
		w.task.res_users.erase(q.id)
	var it: Item = sim.items.get(w.carrying)
	if it == null:
		w.task.next()
		return
	var dest := sim.find_storage(it, w.cell())
	if dest.is_empty():
		var what := L.t("тару для брака") if it.q == "scrap" else L.t("ещё один поддон для готовой продукции")
		sim.notify_once("store_" + it.cat(), L.t("Некуда положить «%s». Поставьте %s.") % [it.display_name(), what], Sim.LVL_WARN, w.cell())
		sim.put_on_ground(it, _off_wall_bp(w.cell()))
		it.reserved_by = -1
		w.task.res_items.erase(it.id)
		w.task.next()
		return
	var t: Thing = dest[0]
	var s := int(dest[1])
	sim.reserve_incoming(t, s, it.stack_key())
	w.task.res_incoming.append([t.id, s])
	var acc := best_access(t, w.cell())
	w.task.label = L.t("Несёт: %s") % it.display_name()
	w.activity = w.task.label
	w.task.insert_next([{"t": "goto", "cell": acc}, {"t": "put", "thing": t.id, "slot": s}])
	w.task.next()


const SPEED_KINDS := ["operate", "inspect", "build_bp", "build_thing", "repair", "demolish_thing", "lay_net", "rework", "hand_saw"]


const INJURY_KINDS := ["operate", "build_bp", "build_thing", "repair", "fix", "demolish_thing", "start_batch"]


func _work(w: Worker, tl: Dictionary, dt: float) -> void:
	var what := str(tl["what"])
	w.anim = str(tl.get("anim", "work"))
	w.work_phase += dt
	if INJURY_KINDS.has(what):
		var mth: Thing = sim.things.get(int(tl.get("thing", -1)))
		if sim.rng.randf() < sim.story.injury_chance(w, mth) * dt:
			if mth and mth.user == w.id:
				mth.working = false
			sim.story.injure(w, "work")
			return
	match what:
		"sweep":
			tl["done"] = float(tl.get("done", 0.0)) + dt
			if float(tl["done"]) >= float(tl.get("dur", 2.5)):
				sim.season.sweep(tl["cell"])
				w.task.next()
			return
		"grab_ext":
			w.prop = "ext"
			w.task.next()
			return
		"extinguish":
			_work_extinguish(w, tl, dt)
			return
		"strike":
			w.prop = "sign"
			w.bubble = "strike"
			tl["done"] = float(tl.get("done", 0.0)) + dt
			if float(tl["done"]) >= float(tl.get("dur", 40.0)) or not sim.story.striking(w):
				w.task.next()
			return
	var k := _speed(w) if SPEED_KINDS.has(what) else 1.0
	tl["done"] = float(tl.get("done", 0.0)) + dt * k
	var done := float(tl["done"])
	var dur := float(tl.get("dur", 1.0))
	match what:
		"operate":
			var m: Thing = sim.things.get(int(tl["thing"]))
			if m == null or m.user != w.id or m.product == "":
				_fail(w)
				return
			if dur <= 0.0:
				dur = _op_time(w, m)
				tl["dur"] = dur
				# деталь, начатую до перерыва, доделывают с того же места
				var pz: Dictionary = m.get_meta("paused", {})
				if str(pz.get("key", "")) == "%s:%d" % [m.product, m.job_step]:
					tl["done"] = float(pz["frac"]) * dur
					done = float(tl["done"])
				m.remove_meta("paused")
			if not sim.prod.can_start(m) or sim.count_slot(m, 1) >= m.slot_cap(1) or m.broken or not sim.prod.has_cons(m):
				m.working = false
				m.progress = 0.0
				w.task.next()
				return
			if sim.crew.stop_work(w) and dur - done > 4.0:
				# перерыв по графику: станок останавливают, деталь доделают после
				m.set_meta("paused", {"key": "%s:%d" % [m.product, m.job_step], "frac": done / dur})
				m.working = false
				w.task.next()
				return
			if not sim.power.powered(m) or not m.enabled:
				m.working = false
				_set_cool(w, "op%d" % m.id, 15.0)
				w.task.next()
				return
			m.working = true
			w.workplace = m.id
			m.progress = clampf(done / dur, 0.0, 1.0)
			m.condition = maxf(0.0, m.condition - Defs.b("machine_wear_per_min") * sim.story.perk("wear_k") * dt)
			if done >= dur:
				_complete_part(w, m)
				m.progress = 0.0
				tl["done"] = 0.0
				tl["dur"] = 0.0
				if not _can_continue_operate(w, m):
					m.working = false
					w.task.next()
		"start_batch":
			var fm: Thing = sim.things.get(int(tl["thing"]))
			if fm == null or fm.user != w.id or fm.product == "" or not sim.power.powered(fm):
				_fail(w)
				return
			fm.progress = clampf(done / dur, 0.0, 1.0) * 0.05
			if done >= dur:
				fm.working = true
				fm.batch_t = 0.0
				fm.user = -1
				w.task.res_users.erase(fm.id)
				w.week_score += 2
				sim.notify(Nicks.gendered(L.t("%s загрузил{|а} печь: %s × %d."), w.female) % [w.full_name(), Defs.product_name(fm.product), sim.count_slot(fm, 0)], Sim.LVL_INFO, fm.cell)
				w.task.next()
		"inspect":
			var it: Item = sim.items.get(w.carrying)
			if it == null:
				_fail(w)
				return
			if dur <= 0.0:
				var qt := float(Defs.products.get(it.def_id, {}).get("qc_time", 6))
				dur = qt * clampf(1.3 - 0.06 * w.skill("qc"), 0.6, 1.3)
				tl["dur"] = dur
			if done >= dur:
				var catch_p := Defs.b("qc_catch_base") + Defs.b("qc_catch_per_skill") * w.skill("qc")
				if it.defect and sim.rng.randf() < catch_p:
					it.q = "scrap"
					sim.stats["scrap"] = int(sim.stats["scrap"]) + 1
				else:
					it.q = "ok"
				sim.item_rev += 1
				w.week_score += 1
				w.task.next()
		"build_bp":
			var i := int(tl["idx"])
			if not sim.bp_cells.has(i) or int(sim.bp_res.get(i, -1)) != w.id:
				if tl.has("mat"):
					w.task.next()   # клетку отменили — материал пойдёт на следующую
					return
				_fail(w)
				return
			if tl.has("mat") and not _use_mat(w, str(tl["mat"]), false):
				_fail(w)
				return
			tl["progress"] = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				if tl.has("mat"):
					_use_mat(w, str(tl["mat"]), true)
				sim.complete_bp(i)
				Nicks.count(w, "build")
				w.task.res_bp.erase(i)
				w.week_score += 1
				if sim.rng.randf() < 0.02:
					w.skills["build"] = mini(10, w.skill("build") + 1)
				w.task.next()
		"lay_net":
			var lay := str(tl["layer"])
			var ii := int(tl["idx"])
			var key := "%s:%d" % [lay, ii]
			if int(sim.net_res.get(key, -1)) != w.id or sim.world.net_layer(lay)[ii] != 2:
				# чертёж отменили или клетку уже проложили — к следующей
				if int(sim.net_res.get(key, -1)) == w.id:
					sim.net_res.erase(key)
				w.task.next()
				return
			tl["progress"] = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				sim.complete_net(lay, ii)
				w.week_score += 1
				if lay == "cable" and sim.rng.randf() < 0.01:
					w.skills["electric"] = mini(10, w.skill("electric") + 1)
				w.task.next()
		"build_thing":
			var th: Thing = sim.things.get(int(tl["thing"]))
			if th == null or th.user != w.id:
				_fail(w)
				return
			th.build_work = done
			th.progress = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				sim.finish_thing(th)
				th.progress = 0.0
				th.user = -1
				w.task.res_users.erase(th.id)
				w.week_score += 3
				w.task.next()
		"fix":
			var th5: Thing = sim.things.get(int(tl["thing"]))
			if th5 == null or th5.user != w.id:
				_fail(w)
				return
			th5.progress = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				th5.broken = false
				th5.condition = 80.0
				th5.progress = 0.0
				th5.user = -1
				w.task.res_users.erase(th5.id)
				sim.spend(Defs.b("repair_cost"), "Ремонт станка: запчасти")
				sim.market.claim("property", Defs.b("repair_cost"), "ремонт станка")
				sim.notify(Nicks.gendered(L.t("%s починил{|а} %s."), w.female) % [w.full_name(), th5.title()], Sim.LVL_GOOD, th5.cell)
				w.week_score += 6
				w.task.next()
		"repair":
			var th3: Thing = sim.things.get(int(tl["thing"]))
			if th3 == null or th3.user != w.id:
				_fail(w)
				return
			th3.progress = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				th3.condition = 100.0
				th3.progress = 0.0
				th3.user = -1
				w.task.res_users.erase(th3.id)
				sim.spend(Defs.b("service_cost"), "Обслуживание станка: резцы, масло, запчасти")
				sim.notify(Nicks.gendered(L.t("%s обслужил{|а} станок — он как новый."), w.female) % w.full_name(), Sim.LVL_INFO, th3.cell)
				w.week_score += 3
				w.task.next()
		"reset":
			var th4: Thing = sim.things.get(int(tl["thing"]))
			if th4 == null or th4.user != w.id:
				_fail(w)
				return
			th4.progress = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				th4.progress = 0.0
				th4.user = -1
				w.task.res_users.erase(th4.id)
				sim.power.reset_source(th4.id)
				Nicks.count(w, "reset")
				sim.notify(Nicks.gendered(L.t("%s сбросил{|а} автомат — свет и станки снова работают."), w.female) % w.full_name(), Sim.LVL_INFO, th4.cell)
				w.week_score += 2
				w.task.next()
		"ppe":
			if done >= dur:
				sim.eng.issue_ppe(w)
				w.task.next()
		"brief":
			if done >= dur or not sim.training.tb_active():
				w.task.next()
		"social":
			var o := sim.get_person(int(tl.get("other", -1)))
			if o:
				_set_dir(w, o.pos - w.pos)
			if done >= dur or o == null:
				if bool(tl.get("breakup", false)):
					sim.social.on_breakup(w)
				w.task.next()
		"shower":
			w.hidden = true
			if done >= dur:
				w.hidden = false
				Mood.add(sim, w, "showered")
				var shw: Thing = sim.things.get(int(tl.get("thing", -1)))
				if shw and int(shw.spot_users.get(0, -1)) == w.id:
					shw.spot_users.erase(0)
				w.task.next()
		"dress", "undress":
			if done >= dur:
				w.dressed = what == "dress"
				if what == "dress":
					var lk: Thing = sim.things.get(int(w.task.data.get("locker", -1)))
					if lk == null:
						Mood.add(sim, w, "changed_corner")
					elif sim.rooms.thing_in(lk, "locker"):
						Mood.add(sim, w, "changed_locker")
					else:
						Mood.add(sim, w, "changed_shop")
				w.task.next()
		"director":
			if not w.task.data.has("thought"):
				w.task.data["thought"] = true
				var dsk: Thing = sim.things.get(int(w.task.data.get("desk", -1)))
				if dsk and sim.rooms.thing_in(dsk, "director_office"):
					Mood.add(sim, w, "office_own")
			if done >= dur:
				w.task.next()
		"office":
			sim.office.add_work(w, dt * Mood.productivity(w))
			if not w.task.data.has("thought"):
				w.task.data["thought"] = true
				var dk := sim.office.desk_k(w)
				if dk >= 1.0:
					Mood.add(sim, w, "office_own")
				elif dk > 0.0:
					Mood.add(sim, w, "office_shared")
			if done >= dur:
				w.week_score += 2
				w.task.next()
		"clean":
			if done >= dur:
				sim.upkeep.clean_cell(tl["cell"], 1.0 + w.skill("clean") * 0.06)
				w.week_score += 1
				w.task.next()
		"saw":
			var swt: Thing = sim.things.get(int(tl["thing"]))
			if swt == null or swt.user != w.id or not sim.power.powered(swt):
				_fail(w)
				return
			swt.working = true
			swt.progress = clampf(done / maxf(dur, 0.1), 0.0, 1.0)
			if done >= dur:
				swt.working = false
				swt.progress = 0.0
				sim.upkeep.add_blanks(str(tl["mat"]), 3 + maxi(int(w.skill("haul") / 3), int(w.skill("fitting") / 2)))
				w.task.next()
		"rework":
			var rwb: Thing = sim.things.get(int(tl["thing"]))
			var rit: Item = sim.items.get(w.carrying)
			if rwb == null or rwb.user != w.id or rit == null:
				_fail(w)
				return
			if done >= dur:
				rwb.user = -1
				w.task.res_users.erase(rwb.id)
				rit.rw = true
				var p_ok := clampf(0.3 + 0.05 * w.skill("fitting") + (0.15 if sim.office.has_tech("rework_cards") else 0.0), 0.2, 0.9)
				if sim.rng.randf() < p_ok:
					rit.q = "machined"     # исправил — снова на ОТК
					rit.defect = false
					sim.stats["reworked"] = int(sim.stats.get("reworked", 0)) + 1
					w.week_score += 2
					var qd := _find_qc_dest(rit, w.cell())
					if qd:
						sim.reserve_incoming(qd, 0, rit.stack_key())
						w.task.res_incoming.append([qd.id, 0])
						w.task.label = L.t("Несёт на ОТК: %s") % rit.display_name()
						w.activity = w.task.label
						w.task.insert_next([{"t": "goto", "cell": best_access(qd, w.cell())}, {"t": "put", "thing": qd.id, "slot": 0}])
						sim.item_rev += 1
						w.task.next()
						return
				sim.item_rev += 1
				# не вышло (или некуда нести) — кладём у верстака, грузчики отнесут
				sim.put_on_ground(rit, _off_wall_bp(w.cell() if sim.world.passable(w.cell()) else sim.world.nearest_passable(w.cell())))
				rit.reserved_by = -1
				w.task.res_items.erase(rit.id)
				w.carrying = -1
				w.task.next()
		"exam":
			var ext: Thing = sim.things.get(int(tl["thing"]))
			if ext == null or ext.user != w.id:
				_fail(w)
				return
			if done >= dur:
				ext.user = -1
				w.task.res_users.erase(ext.id)
				var fm := sim.career.foreman()
				if fm and fm != w and sim.world.reachable(w.cell(), fm.cell()):
					# несёт пробную деталь мастеру
					var near := sim.world.nearest_passable(fm.cell(), 2)
					if near.x < 0:
						sim.career.finish_exam(w)
						w.task.next()
						return
					w.task.label = L.t("Несёт пробную деталь мастеру")
					w.activity = w.task.label
					w.task.insert_next([{"t": "goto", "cell": near}, {"t": "work", "what": "exam_check", "dur": 4.0, "anim": "idle"}])
				else:
					sim.career.finish_exam(w)
				w.task.next()
		"order_wait":
			if w.task.label == L.t("Идёт, куда велели"):
				w.task.label = L.t("Стоит, где велели")
				w.activity = w.task.label
			if done >= dur:
				if bool(tl.get("finish", false)):
					if w.controlled:
						w.order = {}   # 1.19: под управлением — молча ждёт следующей команды
					else:
						end_order(w, Nicks.gendered(L.t("постоял{|а}, где велели"), w.female))
				w.task.next()
		"exam_check":
			if done >= dur:
				sim.career.finish_exam(w)
				w.task.next()
		"hand_saw":
			var hwb: Thing = sim.things.get(int(tl["thing"]))
			if hwb == null or hwb.user != w.id:
				_fail(w)
				return
			if done >= dur:
				hwb.user = -1
				w.task.res_users.erase(hwb.id)
				sim.upkeep.add_blanks(str(tl["mat"]), (1 + int(w.skill("fitting") / 4)) * (2 if sim.office.has_tech("fit_jigs") else 1))
				w.task.next()
		"study":
			sim.training.add_study(w, dt * Mood.productivity(w))
			if not w.task.data.has("thought"):
				w.task.data["thought"] = true
				Mood.add(sim, w, "on_course")
			if done >= dur or not sim.training.in_class(w):
				w.task.next()
		"tb":
			if done >= dur:
				sim.training.tb_done(w)
				w.task.next()
		"setup":
			var sm: Thing = sim.things.get(int(tl["thing"]))
			if sm == null or sm.user != w.id:
				_fail(w)
				return
			sm.progress = clampf(done / maxf(dur, 0.1), 0.0, 1.0)
			if done >= dur:
				sm.setup_key = str(tl["key"])
				sm.progress = 0.0
				w.task.next()
		"smoke":
			if done >= dur:
				Mood.add(sim, w, "smoked")
				w.last_smoke = sim.minute
				w.task.next()
		"demolish_thing":
			var th2: Thing = sim.things.get(int(tl["thing"]))
			if th2 == null or th2.user != w.id:
				_fail(w)
				return
			th2.progress = clampf(done / dur, 0.0, 1.0)
			if done >= dur:
				w.task.res_users.erase(th2.id)
				th2.user = -1
				sim.sfx.emit("demolish", th2.cell)
				sim.logi.on_demolished(th2)
				sim.remove_thing(th2, 0.0)
				w.task.next()
		"eat":
			w.needs["food"] = minf(100.0, float(w.needs["food"]) + 100.0 / maxf(dur, 1.0) * dt)
			if done >= dur:
				w.needs["food"] = 100.0
				w.ate_today = true
				match str(w.task.data.get("eat", "standing")):
					"canteen":
						if sim.town.take_portion():
							Mood.add(sim, w, "ate_hot")
							w.needs["rest"] = minf(100.0, float(w.needs["rest"]) + 6.0)
							sim.stats["hot_meals"] = int(sim.stats.get("hot_meals", 0)) + 1
						else:
							Mood.add(sim, w, "ate_canteen")
					"table":
						Mood.add(sim, w, "ate_table")
					"bench":
						Mood.add(sim, w, "ate_bench")
					"own":
						Mood.add(sim, w, "ate_own")
					_:
						Mood.add(sim, w, "ate_standing")
				w.task.next()
		"toilet":
			w.hidden = true
			if done >= dur:
				w.needs["bladder"] = 100.0
				w.hidden = false
				_toilet_thoughts(w, sim.things.get(int(w.task.data.get("toilet", -1))))
				w.task.next()
		"meet":
			if done >= dur:
				sim.crew.on_met(w, sim.crew.meet_has_lead(w))
				w.task.next()
		"cook":
			if done >= dur:
				sim.town.on_cooked(w)
				w.task.next()
		"union":
			if done >= dur:
				sim.crew.union_worked(w)
				w.task.next()
		"rest":
			var seat: Thing = sim.things.get(int(w.task.data.get("seat", -1)))
			w.set_meta("on_sofa", seat != null and seat.def_id == "sofa")
			if done >= dur or float(w.needs["rest"]) >= 100.0 and done > 5.0:
				w.set_meta("on_sofa", false)
				if seat:
					if sim.rooms.thing_in(seat, "restroom"):
						Mood.add(sim, w, "rested_room")
					if seat.def_id == "sofa":
						Mood.add(sim, w, "sofa")
				w.task.next()
		_:
			if done >= dur:
				w.task.next()


func _toilet_thoughts(w: Worker, toilet: Thing) -> void:
	if toilet == null:
		return
	var r := sim.rooms.room_of_thing(toilet)
	if r == null or r.type != "wc":
		Mood.add(sim, w, "toilet_open")
	var has_sink := false
	if r:
		for tid in r.things:
			var o: Thing = sim.things.get(tid)
			if o and o.def_id == "sink":
				has_sink = true
				break
	if not has_sink:
		Mood.add(sim, w, "toilet_nosink")
	elif r and r.type == "wc" and r.valid and r.tile_share > 0.7:
		Mood.add(sim, w, "toilet_good")


func _op_skill(m: Thing, w: Worker = null) -> String:
	return Production.op_skill(w, m)


func _op_label(m: Thing) -> String:
	var verbs := {"turning": "Точит", "milling": "Фрезерует", "drilling": "Сверлит", "welding": "Варит",
		"heat": "Загружает печь", "paint": "Красит", "assembly": "Собирает", "casting": "Льёт", "stamping": "Штампует"}
	return "%s: %s" % [L.t(str(verbs.get(m.process(), "Работает"))), Defs.product_name(m.product)]


func _op_time(w: Worker, m: Thing) -> float:
	var base := float(Defs.op(m.product, m.job_step).get("time", 30))
	var k := clampf(1.35 - 0.065 * w.skill(_op_skill(m, w)), 0.6, 1.35)
	var wear_k := 1.0 + (100.0 - m.condition) / 300.0
	var mk := float(m.machine_def().get("speed_k", 1.0))
	# первая операция из готовой мерной заготовки (ленточная пила) — не нужно отрезать самому
	if m.job_step == 0 and Defs.products.get(m.product, {}).has("material"):
		if sim.upkeep.take_blank(str(Defs.products[m.product]["material"])):
			mk *= Upkeep.BLANK_K
	return base * k * wear_k * mk * sim.office.op_time_k(m.process()) * sim.eng.air_time_k(m) / sim.prod.crane_k(m)


func _can_continue_operate(w: Worker, m: Thing) -> bool:
	if _on_lunch(w) and not w.ate_today:
		return false
	if Workplace.owner_waiting(sim, m, w):
		return false   # 1.15: хозяин станка освободился — доделал деталь и уступил
	if sim.crew.stop_work(w):
		return false
	if sim.minute >= sim.shift_window(w).y - 5.0:
		return false
	if not sim.power.powered(m) or not m.enabled:
		return false
	if float(w.needs["bladder"]) < 25.0 or float(w.needs["rest"]) < 15.0:
		return false
	if m.product == "" or not sim.prod.can_start(m) or sim.count_slot(m, 1) >= m.slot_cap(1):
		return false
	if m.condition < 25.0 or m.broken or not sim.prod.has_cons(m):
		return false
	return true


func _complete_part(w: Worker, m: Thing) -> void:
	var used := sim.prod.take_inputs(m)
	if used.is_empty():
		return
	sim.crew.on_op(w)
	var carry_defect := false
	for it in used:
		if it.defect:
			carry_defect = true
		sim.delete_item(it)
	var c := sim.prod.cons_need(m)
	sim.use_cons(str(c[0]), float(c[1]))
	var last := m.job_step + 1 >= Defs.route(m.product).size()
	var part := sim.new_item("part", m.product, "machined" if last else "wip")
	part.step = m.job_step + 1
	var sk := w.skill(_op_skill(m, w))
	var chance := (Defs.b("defect_base") - Defs.b("defect_per_skill") * sk + (100.0 - m.condition) / 700.0) * Mood.trait_val(w, "defect_k", 1.0)
	if Defs.route(m.product).size() > 1:
		chance *= 0.6
	chance *= sim.office.defect_k(w) * sim.office.process_defect_k(m.process()) * float(m.machine_def().get("defect_k", 1.0))
	part.defect = carry_defect or sim.rng.randf() < maxf(0.01, chance)
	if part.defect:
		m.defects += 1
	sim.put_in_thing(part, m, 1)
	m.parts_made += 1
	w.parts_made += 1
	w.week_score += 2
	sim.upkeep.on_operation(m, w)
	if last:
		sim.stats["made"] = int(sim.stats["made"]) + 1
	sim.roll_breakdown(m)
	if sim.rng.randf() < 0.015 * sim.office.skill_growth_k() * sim.training.growth_k(w, _op_skill(m, w)) and sk < 10:
		w.skills[_op_skill(m, w)] = sk + 1
		w.add_history(sim.day(), L.t("Набрался опыта: %s") % L.t(str(Worker.SKILL_NAMES.get(_op_skill(m, w), ""))).to_lower())


## Печь можно запускать: полна, или больше ждать нечего, или ждали долго.
func _batch_ready(m: Thing) -> bool:
	var n0 := sim.count_slot(m, 0)
	if n0 == 0:
		m.remove_meta("first_in")
		return false
	if not m.has_meta("first_in"):
		m.set_meta("first_in", sim.minute)
	if sim.count_slot(m, 1) + n0 > m.slot_cap(1):
		return false
	m.ensure_incoming()
	if int(m.incoming[0]) > 0:
		return false
	if n0 >= m.slot_cap(0):
		return true
	if sim.planner.wip_available_live(m.product, m.job_step) == 0:
		return true
	return sim.minute - float(m.get_meta("first_in")) > Defs.b("batch_wait")


## Можно ли брать груз отсюда для подачи на станок: склад, пол или выход другого станка.
func _feed_source_ok(i: Item, m: Thing) -> bool:
	if i.loc == Item.Loc.GROUND:
		return true
	if i.loc != Item.Loc.THING:
		return false
	var t: Thing = sim.things.get(i.holder)
	if t == null or t.id == m.id:
		return false
	return t.is_storage() or (t.kind() == "machine" and i.slot == 1)


## Куда везти деталь после операции: годную на ОТК, НЗП — на ждущий станок, иначе на стеллаж НЗП.
func _route_dest(it: Item, near: Vector2i) -> Array:
	if it.q == "machined":
		var q := _find_qc_dest(it, near)
		return [q, 0] if q else []
	if it.q == "wip":
		var m := sim.prod.machine_for(it)
		if m:
			return [m, 0]
		var st := sim.find_storage(it, near)
		if not st.is_empty():
			return st
	return []


## Свободная тележка или погрузчик для большой ходки.
func _haul_vehicle(w: Worker) -> Thing:
	var best: Thing = null
	for t: Thing in sim.things.values():
		if not t.built or t.demolish or t.user >= 0:
			continue
		if t.def_id == "forklift" and w.skill("haul") >= 6:
			return t
		if t.def_id == "cart" and best == null and (w.prof == "laborer" or w.skill("haul") >= 4):
			best = t
	return best


func _move(w: Worker, target: Vector2i, dt: float) -> int:
	if target.x < 0:
		return -1
	if w.path_target != target or w.path.is_empty():
		var p := sim.crew.gate_path(w.cell(), target)   # 1.30: на смену и домой — через турникет
		if p.is_empty():
			p = sim.world.find_path(w.cell(), target)
		if p.is_empty():
			return -1
		w.path = p
		w.path_i = 1
		w.path_target = target
	var spd := Defs.b("walk_speed") * (Defs.b("carry_speed") * sim.story.perk("haul_k") if w.carrying >= 0 else 1.0)
	if w.carrying >= 0:
		var ci: Item = sim.items.get(w.carrying)
		if ci and ci.kind == "crate":
			spd *= 0.72 if ci.q == "crate" else 0.92   # тяжёлый ящик — медленнее
		elif Production.is_heavy(ci) and w.prop != "pendant":
			spd *= Defs.b("heavy_drag_k") if Defs.b("heavy_drag_k") > 0.0 else 0.6   # без крана — волоком
	if w.task and str(w.task.data.get("veh", "")) == "forklift":
		spd = Defs.b("walk_speed") * Defs.b("forklift_speed")
	var step := spd * dt
	var guard := 0
	while step > 0.0 and guard < 16:
		guard += 1
		var dest: Vector2
		if w.path_i >= w.path.size():
			dest = Vector2(target) + Vector2(0.5, 0.5)
		else:
			var nxt := w.path[w.path_i]
			if not sim.world.passable(nxt) and nxt != target:
				w.path.clear()
				w.path_target = Vector2i(-999, -999)
				return 0
			dest = Vector2(nxt) + Vector2(0.5, 0.5)
		var v := dest - w.pos
		var ln := v.length()
		if ln > 0.001:
			_set_dir(w, v)
		w.anim = "walk"
		if ln <= step:
			w.pos = dest
			step -= ln
			sim.season.on_step(w, Vector2i(floori(dest.x), floori(dest.y)))
			if w.path_i >= w.path.size():
				w.path.clear()
				w.path_target = Vector2i(-999, -999)
				w.anim = "idle"
				return 1
			w.path_i += 1
		else:
			w.pos += v / ln * step
			step = 0.0
	return 0


## Движение для гостей завода (инспекторов): 1 — пришёл, 0 — идёт, −1 — пути нет.
func move_to(w: Worker, target: Vector2i, dt: float) -> int:
	return _move(w, target, dt)


## Тушить ближайший очаг: сначала взять огнетушитель, если он недалеко.
func _fire_task(w: Worker) -> Task:
	var wc := w.cell()
	var best_i := -1
	var bd := INF
	for i: int in sim.story.fires.keys():
		var d := _dist(sim.world.cell_of(i), wc)
		if d < bd:
			bd = d
			best_i = i
	if best_i < 0 or bd > 45.0:
		return null
	var fc := sim.world.cell_of(best_i)
	var stand := _fire_stand(fc, wc)
	if stand.x < 0 or not sim.world.reachable(wc, stand):
		return null
	var t := Task.new()
	t.kind = "extinguish"
	t.label = L.t("Тушит пожар")
	t.data["bubble"] = "fire"
	if w.prop != "ext":
		var ext: Thing = null
		var ed := INF
		for th: Thing in sim.things.values():
			if th.built and th.def_id == "extinguisher":
				var d2 := _dist(th.cell, fc) + _dist(th.cell, wc) * 0.5
				if d2 < ed and _dist(th.cell, fc) < 22.0:
					ed = d2
					ext = th
		if ext:
			var acc := best_access(ext, wc)
			if acc.x >= 0 and sim.world.reachable(wc, acc):
				t.label = L.t("Бежит за огнетушителем")
				t.add({"t": "goto", "cell": acc})
				t.add({"t": "work", "what": "grab_ext", "dur": 0.5, "anim": "work"})
	t.add({"t": "goto", "cell": stand, "face": _face_to(stand, fc)})
	t.add({"t": "work", "what": "extinguish", "fire": best_i, "dur": 9999.0, "anim": "work"})
	return t


func _fire_stand(fc: Vector2i, from: Vector2i) -> Vector2i:
	var best := Vector2i(-1, -1)
	var bd := INF
	for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
		var c: Vector2i = fc + d
		if not sim.world.passable(c) or sim.story.fires.has(sim.world.idx(c)):
			continue
		var dd := _dist(c, from)
		if dd < bd:
			bd = dd
			best = c
	return best


func _work_extinguish(w: Worker, tl: Dictionary, dt: float) -> void:
	var fi := int(tl["fire"])
	if not sim.story.fires.has(fi):
		# соседний очаг — тушить дальше, не сходя с места
		var wc := w.cell()
		var nxt := -1
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)]:
			var c: Vector2i = wc + d
			if sim.world.inb(c) and sim.story.fires.has(sim.world.idx(c)):
				nxt = sim.world.idx(c)
				break
		if nxt < 0:
			w.task.next()
			return
		tl["fire"] = nxt
		fi = nxt
		_face(w, _face_to(wc, sim.world.cell_of(nxt)))
	var rate := Defs.ev("extinguish_rate") if w.prop == "ext" else Defs.ev("extinguish_bare")
	w.activity = L.t("Тушит пожар") if w.prop == "ext" else L.t("Тушит пожар подручными средствами")
	sim.story.extinguish(fi, rate * dt)
	if not sim.story.fires.has(fi):
		Nicks.count(w, "fire")


func _strike_task(w: Worker) -> Task:
	var t := Task.new()
	t.kind = "strike"
	t.label = L.t("Бастует у проходной")
	t.data["prop"] = "sign"
	t.data["bubble"] = "strike"
	t.add({"t": "goto", "cell": sim.story.rally_cell(w), "face": "down"})
	t.add({"t": "work", "what": "strike", "dur": 40.0, "anim": "idle"})
	return t


func _set_dir(w: Worker, v: Vector2) -> void:
	if absf(v.x) > absf(v.y) * 1.1:
		w.dir = "right" if v.x > 0 else "left"
	else:
		w.dir = "down" if v.y > 0 else "up"


func _face(w: Worker, face: String) -> void:
	match face:
		"up", "down", "left", "right":
			w.dir = face
		"auto":
			for d in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
				var th := sim.thing_at(w.cell() + d)
				if th and th.built and th.kind() == "table":
					w.dir = _face_to(w.cell(), w.cell() + d)
					return


func _fail(w: Worker) -> void:
	if w.task:
		_set_cool(w, str(w.task.data.get("cool", "")), 25.0)
	abort(w)


func _finish(w: Worker) -> void:
	abort(w)


## Отмена задачи: снять все резервирования, бросить груз на пол.
func abort(w: Worker) -> void:
	_unseat(w)
	if w.task != null:
		sim.logi.release(w)
		var tk := w.task
		for iid in tk.res_items:
			var it: Item = sim.items.get(iid)
			if it and it.reserved_by == w.id:
				it.reserved_by = -1
		for tid in tk.res_users:
			var t: Thing = sim.things.get(tid)
			if t and t.user == w.id:
				t.user = -1
				t.working = false
				if not t.built:
					t.progress = 0.0
		for pair in tk.res_spots:
			var t2: Thing = sim.things.get(int(pair[0]))
			if t2 and int(t2.spot_users.get(int(pair[1]), -1)) == w.id:
				t2.spot_users.erase(int(pair[1]))
		for pair2 in tk.res_incoming:
			var t3: Thing = sim.things.get(int(pair2[0]))
			if t3:
				sim.release_incoming(t3, int(pair2[1]))
		for i in tk.res_bp:
			if int(sim.bp_res.get(i, -1)) == w.id:
				sim.bp_res.erase(i)
		for key in tk.data.get("nets", []):
			if int(sim.net_res.get(str(key), -1)) == w.id:
				sim.net_res.erase(str(key))
		if tk.res_load >= 0:
			var v := sim.get_vehicle(tk.res_load)
			if v:
				v.reserved_load = maxi(0, v.reserved_load - int(tk.data.get("load_n", 1)))
	if w.carrying >= 0 or not w.carry_extra.is_empty():
		var drop := w.cell()
		if not sim.world.passable(drop):
			drop = sim.world.nearest_passable(drop)
		drop = _off_wall_bp(drop)
		var carried: Array = w.carry_extra.duplicate()
		if w.carrying >= 0:
			carried.push_front(w.carrying)
		for iid in carried:
			var ci: Item = sim.items.get(int(iid))
			if ci:
				ci.reserved_by = -1
				sim.put_on_ground(ci, drop)
		w.carrying = -1
		w.carry_extra.clear()
	w.task = null
	w.prop = ""
	w.bubble = ""
	w.path.clear()
	w.path_target = Vector2i(-999, -999)
	w.hidden = false
	if w.anim != "walk":
		w.anim = "idle"
	w.activity = L.t("На месте")


## 1.26: груз не бросаем на чертёж стены — стену на клетке с грузом не начать, и стройка вставала навсегда
## (строитель, уходя со смены, ронял последний кирпич ровно туда, где его и надо было класть).
func _off_wall_bp(c: Vector2i) -> Vector2i:
	if not _wall_bp_at(c):
		return c
	for r in range(1, 4):
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				var n := c + Vector2i(dx, dy)
				if sim.world.inb(n) and sim.world.passable(n) and not _wall_bp_at(n):
					return n
	return c


func _wall_bp_at(c: Vector2i) -> bool:
	if not sim.world.inb(c):
		return false
	var i := sim.world.idx(c)
	var wv := sim.world.bp_wall[i]
	return sim.bp_cells.has(i) and wv != World.BP_NONE and Defs.wall_solid(wv)
