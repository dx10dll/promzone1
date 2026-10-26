class_name BubbleLogic
extends RefCounted
## 1.50d: что показывать в облачке-мысли над человеком. Чистая логика без отрисовки (её проверяет тест):
## по состоянию симуляции (потребности, настроение, мысли, задача) выбирается ОДИН значок —
## проблема или желание важнее действия; среди проблем побеждает та, что серьёзнее.
## Ярус: 0 — нет значка, 1 — действие (спокойная обводка), 2 — хочет (жёлтая), 3 — плохо (красная).

const HOLD := 2.0   ## минимум секунд, сколько держится значок, прежде чем смениться на другой действием

const T_NONE := 0
const T_ACT := 1
const T_WANT := 2
const T_BAD := 3

## Событийные значки, которые ставит симуляция (Worker.bubble), и их ярус.
const EVENT_TIER := {"injury": 3, "fight": 3, "strike": 3, "fire": 3, "argue": 2,
	"talk": 1, "chat": 1, "laugh": 1, "idea": 1, "food": 1, "inspect": 1}

## Задача -> значок. Станочная работа уточняется по типу станка (op_<процесс>).
const TASK_KIND := {"haul": "haul", "haul_cell": "haul", "load": "haul", "delivery": "haul", "crate": "haul",
	"build_bp": "build", "build_thing": "build", "lay_net": "build", "demolish": "demolish",
	"sweep": "clean", "clean": "clean", "repair": "repair", "fix": "repair", "reset": "repair", "rework": "repair",
	"study": "study", "exam": "exam", "shadow": "study", "brief": "chat", "meet": "chat", "social": "chat", "escort": "chat",
	"eat": "eat", "rest": "rest", "smoke": "smoke", "toilet": "wc", "go_home": "home", "inspect": "inspect",
	"office": "office", "guard": "guard", "patrol": "guard", "nurse": "nurse", "cook": "cook", "dress": "dress",
	"ppe": "helmet", "extinguish": "fire", "strike": "strike", "wander": "idle", "presetup": "op_gear",
	"saw": "op_gear", "hand_saw": "op_gear"}


## Нужен ли значок вообще у этого человека (на смене, не уличный прохожий).
static func relevant(w: Worker) -> bool:
	return w != null and w.present and not w.hidden


static func has_thought(sim: Sim, w: Worker, id: String) -> bool:
	for th: Dictionary in w.thoughts:
		if str(th.get("id", "")) == id and float(th.get("until", 0.0)) > sim.minute:
			return true
	return false


## Выбор значка: {k: вид, t: ярус, u: срочность 0..1}. k == "" — значка нет.
static func pick(sim: Sim, w: Worker) -> Dictionary:
	if not relevant(w):
		return {"k": "", "t": T_NONE, "u": 0.0}
	var tk := w.task.kind if w.task else ""
	var best := {"k": "", "t": T_NONE, "u": 0.0}
	# 1. события от симуляции (травма, драка, забастовка, пожар)
	var ev := w.bubble
	if ev != "" and int(EVENT_TIER.get(ev, 0)) >= T_WANT:
		best = {"k": ev, "t": int(EVENT_TIER[ev]), "u": 1.0}
	if w.visitor:
		if best["k"] == "" and ev != "":
			return {"k": ev, "t": T_ACT, "u": 0.0}
		return best if best["k"] != "" else {"k": "", "t": T_NONE, "u": 0.0}
	# 2. потребности и самочувствие
	var n := w.needs
	var cands: Array = []
	var bl := float(n.get("bladder", 100.0))
	var fd := float(n.get("food", 100.0))
	var rs := float(n.get("rest", 100.0))
	if bl < 25.0 and tk != "toilet":
		cands.append({"k": "wc", "t": T_BAD if bl < 10.0 else T_WANT, "u": 1.0 - bl / 25.0})
	if fd < 22.0 and tk != "eat":
		cands.append({"k": "hungry", "t": T_BAD if fd < 8.0 else T_WANT, "u": 1.0 - fd / 22.0})
	if rs < 18.0 and tk != "rest":
		cands.append({"k": "tired", "t": T_BAD if rs < 6.0 else T_WANT, "u": 1.0 - rs / 18.0})
	if w.dressed:
		var tc := sim.season.temp_at(w.cell())
		if tc < Defs.sea("freezing_below"):
			cands.append({"k": "cold", "t": T_BAD if has_thought(sim, w, "freezing") else T_WANT, "u": 0.7})
		elif tc > Defs.sea("hot_above"):
			cands.append({"k": "hot", "t": T_BAD if tc > Defs.sea("hot_above") + 8.0 else T_WANT, "u": 0.5})
	if w.mood < 25.0:
		cands.append({"k": "angry", "t": T_BAD if w.mood < 12.0 else T_WANT, "u": 1.0 - w.mood / 25.0})
	if not w.is_itr() and w.ppe <= 0.0 and w.days_worked > 0 and w.dressed:
		cands.append({"k": "no_ppe", "t": T_WANT, "u": 0.4})
	if has_thought(sim, w, "arrears"):
		cands.append({"k": "wait_pay", "t": T_BAD, "u": 0.9})
	elif float(w.get_meta("wage_due", 0.0)) > 0.0 and sim.crisis != null and sim.crisis.unpaid_since >= 0:
		cands.append({"k": "wait_pay", "t": T_WANT, "u": 0.5})
	for c: Dictionary in cands:
		if _better(c, best):
			best = c
	if best["t"] >= T_WANT:
		return best
	# 3. действие
	if ev != "" and EVENT_TIER.has(ev):
		return {"k": ev, "t": T_ACT, "u": 0.0}
	return {"k": action_kind(sim, w), "t": T_ACT, "u": 0.0} if action_kind(sim, w) != "" else {"k": "", "t": T_NONE, "u": 0.0}


static func _better(a: Dictionary, b: Dictionary) -> bool:
	if int(a["t"]) != int(b["t"]):
		return int(a["t"]) > int(b["t"])
	return float(a["u"]) > float(b["u"])


## Что человек делает сейчас: вид значка действия.
static func action_kind(sim: Sim, w: Worker) -> String:
	if w.task == null:
		return "idle"
	var tk := w.task.kind
	if tk == "operate":
		var m: Thing = null
		if not w.task.res_users.is_empty():
			m = sim.things.get(int(w.task.res_users[0]))
		return "op_" + m.process() if m != null and m.process() != "" else "op_gear"
	if TASK_KIND.has(tk):
		return str(TASK_KIND[tk])
	if w.carrying >= 0:
		return "haul"
	return "idle" if w.anim != "work" else "op_gear"


## Менять ли значок: возвращает новое состояние st {k, t, since, a}. Правила анти-мигания:
## проблема сразу перебивает действие; всё остальное меняется не раньше, чем через HOLD секунд.
static func step(st: Dictionary, cand: Dictionary, now: float) -> Dictionary:
	var ck := str(cand["k"])
	var ct := int(cand["t"])
	if str(st.get("k", "")) == ck:
		st["t"] = ct
		return st
	var cur_t := int(st.get("t", 0))
	var swap := false
	if str(st.get("k", "")) == "" and ck != "":
		swap = true   # значка не было — появляется сразу
	elif ct >= T_WANT and cur_t < T_WANT:
		swap = true   # проблема перебивает действие
	elif ct >= T_WANT and cur_t >= T_WANT and (ct > cur_t) and now - float(st.get("since", -99.0)) >= 0.3:
		swap = true   # стало хуже (жёлтое -> красное)
	elif now - float(st.get("since", -99.0)) >= HOLD:
		swap = true
	if swap:
		st["k"] = ck
		st["t"] = ct
		st["since"] = now
	return st


## Видно ли облачко с таким ярусом: проблемы всегда, действия — у выбранного, под мышью и когда людей мало.
static func shown(tier: int, selected: bool, hovered: bool, crowd: int, mode: String) -> bool:
	if tier >= T_WANT:
		return true
	if tier <= T_NONE or mode == "off":
		return false
	return mode == "all" or selected or hovered or crowd <= 8


const TITLES := {
	"op_turning": "Работает на токарном", "op_milling": "Работает на фрезерном", "op_drilling": "Работает на сверлильном",
	"op_welding": "Сваривает", "op_heat": "Работает с печью", "op_paint": "Красит", "op_assembly": "Собирает",
	"op_casting": "Работает с литьём", "op_stamping": "Работает на прессе", "op_gear": "Работает",
	"build": "Строит", "demolish": "Сносит", "haul": "Носит груз", "clean": "Убирает", "repair": "Чинит",
	"study": "Учится", "exam": "Сдаёт экзамен", "eat": "Ест", "rest": "Отдыхает", "smoke": "Курит",
	"wc": "В туалете", "home": "Идёт домой", "idle": "Ждёт работы", "inspect": "Проверяет", "office": "Работает с бумагами",
	"food": "Готовит", "guard": "Охраняет", "nurse": "Лечит", "cook": "Готовит", "dress": "Переодевается", "helmet": "Получает СИЗ",
	"chat": "Разговаривает", "laugh": "Смеётся", "idea": "Придумал идею", "fire": "Тушит пожар", "strike": "Бастует",
	"talk": "Разговаривает", "argue": "Спорит", "fight": "Драка", "injury": "Травма",
	"hungry": "Хочет есть", "tired": "Устал", "cold": "Мёрзнет", "hot": "Жарко", "angry": "Недоволен",
	"no_ppe": "Нет СИЗ", "wait_pay": "Ждёт зарплату"}


## Подпись для подсказки: одна строка вида «Хочет есть — нет столовой» или «Точит: Втулка — Токарный станок».
static func tip(sim: Sim, w: Worker, k: String, t: int) -> Dictionary:
	var head := L.t(str(TITLES.get(k, "Работает")))
	var why := ""
	match k:
		"hungry":
			why = L.t("нет столовой") if sim.rooms.of_type("canteen").is_empty() else L.t("пора обедать")
		"wc":
			why = L.t("нет туалета") if sim.rooms.of_type("wc").is_empty() else L.t("терпит")
			head = L.t("Хочет в туалет") if t >= T_WANT else head
		"tired":
			why = L.t("нет комнаты отдыха") if sim.rooms.of_type("restroom").is_empty() else L.t("нужен перерыв")
		"cold":
			why = L.t("замерзает") if t >= T_BAD else L.t("в цеху холодно")
		"hot":
			why = L.t("нечем дышать") if t >= T_BAD else L.t("в цеху жарко")
		"angry":
			why = L.t("настроение %d из 100") % int(w.mood)
		"no_ppe":
			why = L.t("СИЗ изношены, нужен шкаф СИЗ")
		"wait_pay":
			why = L.t("зарплату задерживают")
		"injury":
			why = L.t("нужна аптечка")
		"fight":
			why = L.t("разнимите, пока не покалечились")
		"strike":
			why = L.t("требуют уступок")
		"fire":
			why = L.t("горит")
		"argue":
			why = L.t("ссора с коллегой")
		_:
			if k.begins_with("op_") or t == T_ACT:
				why = w.activity
	if k.begins_with("op_") and w.task and not w.task.res_users.is_empty():
		var m: Thing = sim.things.get(int(w.task.res_users[0]))
		if m != null:
			why = "%s — %s" % [w.activity, m.title()]
	return {"head": head, "why": why}
