class_name Mood
extends RefCounted
## Настроение рабочих: черты характера, мысли с таймером и состояния.
## Настроение 0–100 влияет на скорость работы, прогулы и увольнения.


## Добавить или обновить мысль. Бытовые мысли ослабляются/усиливаются чертами.
static func add(sim: Sim, w: Worker, id: String) -> void:
	var def: Dictionary = Defs.thoughts.get(id, {})
	if def.is_empty():
		return
	var v := float(def.get("mood", 0))
	if bool(def.get("comfort", false)):
		v *= trait_val(w, "comfort_k", 1.0)
	if bool(def.get("wage", false)):
		v *= trait_val(w, "wage_k", 1.0)
	var until := sim.minute + float(def.get("dur", 240))
	for th: Dictionary in w.thoughts:
		if str(th["id"]) == id:
			th["until"] = until
			th["mood"] = v
			return
	w.thoughts.append({"id": id, "until": until, "mood": v})


## Текст мысли на языке игры (data/thoughts.json, ключ thought.<id>.text).
static func thought_text(id: String) -> String:
	return L.dt("thought.%s.text" % id, str(Defs.thoughts.get(id, {}).get("text", id)))


static func has_trait(w: Worker, t: String) -> bool:
	return w.traits.has(t)


## Числовой параметр черты: множители перемножаются, сдвиги складываются.
static func trait_val(w: Worker, key: String, default: float) -> float:
	var mult := key.ends_with("_k")
	var v := default
	for t in w.traits:
		var d: Dictionary = Defs.traits.get(t, {})
		if d.has(key):
			if mult:
				v *= float(d[key])
			else:
				v += float(d[key])
	return v


## Рыночная ставка для такого работника.
static func market_wage(w: Worker) -> int:
	return People.wage_for(w)


## Список слагаемых настроения: [[текст, значение], ...]
static func breakdown(sim: Sim, w: Worker) -> Array:
	var out: Array = []
	for t in w.traits:
		var d: Dictionary = Defs.traits.get(t, {})
		if d.has("mood"):
			out.append([L.dt("trait.%s.name" % t, str(d["name"])), float(d["mood"])])
	for th: Dictionary in w.thoughts:
		if float(th["until"]) > sim.minute:
			out.append([thought_text(str(th["id"])), float(th["mood"])])
	if float(w.needs["food"]) < 15.0:
		out.append([L.t("Голоден"), -8.0])
	if float(w.needs["rest"]) < 15.0:
		out.append([L.t("Вымотан"), -6.0])
	if float(w.needs["bladder"]) < 10.0:
		out.append([L.t("Очень хочет в туалет"), -4.0])
	var market := float(market_wage(w))
	var ratio := float(w.wage) / maxf(1.0, market)
	if w.is_director():
		ratio = 1.0   # 1.40: директор — хозяин завода, оклада у него нет
	var wk := trait_val(w, "wage_k", 1.0)
	if ratio < 0.9:
		out.append([L.t("Платят меньше, чем везде"), -7.0 * wk])
	elif ratio >= 1.15:
		out.append([L.t("Хорошо платят"), 5.0 * wk])
	if w.shift == 1:
		var nm := trait_val(w, "night_mood", 0.0)
		if nm < 0.0:
			out.append([L.t("Вторая смена — мука"), nm])
		elif nm > 0.0:
			out.append([L.t("Сова: вечером работается лучше"), nm])
	else:
		var dm := trait_val(w, "day_mood", 0.0)
		if dm != 0.0:
			out.append([L.t("Рано вставать"), dm])
	if sim and sim.training and sim.get_worker(w.id) == w:
		out.append_array(sim.training.mood_parts(w))
	if sim and sim.town and sim.get_worker(w.id) == w:
		out.append_array(sim.town.mood_parts(w))
	return out


## 1.50: настроение — пять крупных шкал (в 1.15 это были «потребности жизни» быт/деньги/работа/коллектив/дом).
## Деньги — ставка, премии, долги; Условия — быт, цех, безопасность и порядок; Коллектив — люди, праздники, профком;
## Перспектива — рост, курсы, разряд, будущее завода; Отдых — перекуры, отпуск, смена, сон, дом.
## Сохранения не затронуты: шкалы считаются на лету из тех же мыслей и состояний (grp в thoughts.json остался как был).
const LIFE := [["money", "Деньги"], ["cond", "Условия"], ["team", "Коллектив"], ["future", "Перспектива"], ["rest", "Отдых"]]
const LIFE_HINT := {
	"money": "Ставка не ниже рыночной, премии, зарплата вовремя, индексация.",
	"cond": "Столовая с горячим обедом, душ, бытовка, тепло, свет и чистота; свой станок, мастер, СИЗ, порядок на участке.",
	"team": "Бригада, праздники и подарки, профком; поменьше ссор, драк и увольнений; друзья на одной смене.",
	"future": "Курсы и разряд, наставник, бригадирство, рацпредложения, рост завода и уверенность в завтрашнем дне.",
	"rest": "Комната отдыха с кулером и диваном, перекуры и чай, отпуск летом, удобная смена, общежитие и садик.",
}
const LIFE_ICON := {"money": "money", "cond": "wrench", "team": "team", "future": "research", "rest": "bed"}
## Мысли, у которых шкала не совпадает со старой группой grp (byt/work → «Условия», home → «Отдых»).
const THOUGHT_SCALE := {
	"new_machine": "future", "honor_board": "future", "stage_up": "future", "on_course": "future", "course_done": "future",
	"mentor_proud": "future", "practice_kept": "future", "brigadier": "future", "grade_up": "future", "exam_failed": "future",
	"plan_done": "future", "rational_paid": "future", "rational_ignored": "future", "layoff_rumor": "future",
	"rumor_cleared": "future", "idle_bad": "future",
	"reprimand": "team", "n1_fair": "team", "n1_blame": "team", "n1_hidden": "team",
	"rested_room": "rest", "sofa": "rest", "smoked": "rest", "no_smoke": "rest", "tea_break": "rest", "radio_music": "rest",
	"cat_pet": "rest", "no_lunch_break": "rest", "radio_gym": "rest",
}
## Слагаемые без мысли (их id — третий элемент слагаемого): шкала.
const CID_SCALE := {
	"wage_low": "money", "wage_high": "money", "wage_ok": "money",
	"hungry": "cond", "wc": "cond", "tired": "rest", "night": "rest", "early": "rest",
	"veteran": "team", "trait": "team", "friend": "team", "foe": "team",
	"mentor": "future", "teach": "future", "practice": "future",
	"dorm_cozy": "rest", "dorm": "rest", "dorm_bare": "rest", "nohome": "rest", "kg": "rest", "nokg": "rest",
}
const NEED_BAR := 45.0   ## ниже этого значения шкала считается проседающей


## Шкала мысли по её id.
static func thought_scale(id: String) -> String:
	if THOUGHT_SCALE.has(id):
		return str(THOUGHT_SCALE[id])
	match str(Defs.thoughts.get(id, {}).get("grp", "work")):
		"money":
			return "money"
		"team":
			return "team"
		"home":
			return "rest"
	return "cond"


## Шкала слагаемого [текст, значение, id]: id мысли — "t:<мысль>", остальные — из CID_SCALE.
static func scale_of(cid: String) -> String:
	if cid.begins_with("t:"):
		return thought_scale(cid.substr(2))
	return str(CID_SCALE.get(cid, "cond"))


## Все слагаемые настроения с кодом шкалы: [[текст, значение, id, шкала], ...] — то же, что breakdown().
static func parts_all(sim: Sim, w: Worker) -> Array:
	var out: Array = []
	for t in w.traits:
		var d: Dictionary = Defs.traits.get(t, {})
		if d.has("mood"):
			out.append([L.dt("trait.%s.name" % t, str(d["name"])), float(d["mood"]), "trait"])
	for th: Dictionary in w.thoughts:
		if float(th["until"]) > sim.minute:
			out.append([thought_text(str(th["id"])), float(th["mood"]), "t:" + str(th["id"])])
	if float(w.needs["food"]) < 15.0:
		out.append([L.t("Голоден"), -8.0, "hungry"])
	if float(w.needs["rest"]) < 15.0:
		out.append([L.t("Вымотан"), -6.0, "tired"])
	if float(w.needs["bladder"]) < 10.0:
		out.append([L.t("Очень хочет в туалет"), -4.0, "wc"])
	var ratio := float(w.wage) / maxf(1.0, float(market_wage(w)))
	if w.is_director():
		ratio = 1.0
	var wk := trait_val(w, "wage_k", 1.0)
	if ratio < 0.9:
		out.append([L.t("Платят меньше, чем везде"), -7.0 * wk, "wage_low"])
	elif ratio >= 1.15:
		out.append([L.t("Хорошо платят"), 5.0 * wk, "wage_high"])
	if w.shift == 1:
		var nm := trait_val(w, "night_mood", 0.0)
		if nm < 0.0:
			out.append([L.t("Вторая смена — мука"), nm, "night"])
		elif nm > 0.0:
			out.append([L.t("Сова: вечером работается лучше"), nm, "night"])
	else:
		var dm := trait_val(w, "day_mood", 0.0)
		if dm != 0.0:
			out.append([L.t("Рано вставать"), dm, "early"])
	if sim and sim.training and sim.get_worker(w.id) == w:
		out.append_array(sim.training.mood_parts(w))
	if sim and sim.town and sim.get_worker(w.id) == w:
		out.append_array(sim.town.mood_parts(w))
	for p: Array in out:
		p.resize(3)
		p.append(scale_of(str(p[2])))
	return out


## {шкала: {"v": 0–100, "parts": [[текст, значение, id], ...]}} — для полосок в карточке.
## Итог настроения (value) по-прежнему считается из breakdown(); шкалы — те же слагаемые, разложенные по пяти полкам.
static func life(sim: Sim, w: Worker) -> Dictionary:
	var out := {}
	for g in LIFE:
		out[g[0]] = {"v": 0.0, "parts": []}
	for p: Array in parts_all(sim, w):
		var o: Dictionary = out[str(p[3])]
		(o["parts"] as Array).append([p[0], p[1], p[2]])
		o["v"] = float(o["v"]) + float(p[1])
	if sim and sim.get_worker(w.id) == w and veteran(sim, w):
		(out["team"]["parts"] as Array).append([L.t("Ветеран завода — уважают"), 3.0, "veteran"])
		out["team"]["v"] = float(out["team"]["v"]) + 3.0
	for g2 in out.keys():
		out[g2]["v"] = clampf(55.0 + 3.0 * float(out[g2]["v"]), 0.0, 100.0)
	return out


## Самая проседающая шкала: [код, название, подсказка] или [] — если всё в порядке.
static func life_worst(sim: Sim, w: Worker) -> Array:
	var lf := life(sim, w)
	var worst := ""
	var wv := 101.0
	for g in LIFE:
		var v := float(lf[g[0]]["v"])
		if v < wv:
			wv = v
			worst = str(g[0])
	if wv >= NEED_BAR:
		return []
	for g2 in LIFE:
		if g2[0] == worst:
			return [worst, L.t(str(g2[1])), L.t(str(LIFE_HINT[worst]))]
	return []


## «Чем недоволен»: самая проседающая шкала и самая тяжёлая её причина.
## {} — всё в порядке; иначе {"scale", "name", "reason", "cid", "text"}.
static func complaint(sim: Sim, w: Worker, lf: Dictionary = {}) -> Dictionary:
	if lf.is_empty():
		lf = life(sim, w)
	var order: Array = LIFE.duplicate()
	order.sort_custom(func(a: Array, b: Array) -> bool: return float(lf[a[0]]["v"]) < float(lf[b[0]]["v"]))
	for g: Array in order:
		if float(lf[g[0]]["v"]) >= NEED_BAR:
			break
		var top: Array = []
		for p: Array in lf[g[0]]["parts"]:
			if float(p[1]) <= -0.5 and (top.is_empty() or float(p[1]) < float(top[1])):
				top = p
		if top.is_empty():
			continue
		var nm := L.t(str(g[1]))
		return {"scale": str(g[0]), "name": nm, "reason": str(top[0]), "cid": str(top[2]), "text": "%s: %s" % [nm, str(top[0]).to_lower()]}
	return {}


## Рыночная ставка, округлённая вверх до 50 ₽ — до неё и советуем поднять.
static func wage_target(w: Worker) -> int:
	return int(ceil(float(market_wage(w)) / 50.0) * 50.0)


## Есть ли в комнатах отдыха нужный предмет (def_id из списка).
static func _rest_has(sim: Sim, ids: Array) -> bool:
	for r in sim.rooms.list:
		if r.type == "restroom":
			for tid: int in r.things:
				var t: Thing = sim.things.get(tid)
				if t != null and ids.has(t.def_id):
					return true
	return false


static func _has_restroom(sim: Sim) -> bool:
	for r in sim.rooms.list:
		if r.type == "restroom":
			return true
	return false


## Совет на причину: короткая конкретная фраза.
static func advice_for(sim: Sim, w: Worker, scale: String, cid: String) -> String:
	var tid := cid.substr(2) if cid.begins_with("t:") else ""
	# деньги
	if cid == "wage_low" or tid in ["wage_cut", "raise_refused", "no_index", "raise"]:
		if w.wage < int(market_wage(w) * 0.97):
			return L.t("Поднять ставку до %s") % Defs.money_str(wage_target(w))
		return L.t("Выдать премию: деньги сразу поднимают настроение")
	if tid in ["arrears", "wage_late", "fined"]:
		return L.t("Платить вовремя: держите на счёте запас на зарплату")
	# усталость и отдых
	if cid == "tired" or tid in ["overtime_drink", "overtime"]:
		if not _has_restroom(sim):
			return L.t("Построить комнату отдыха: диван и кулер")
		if not _rest_has(sim, ["cooler", "water_cooler"]):
			return L.t("Поставить кулер в комнату отдыха")
		if not _rest_has(sim, ["sofa"]):
			return L.t("Поставить диван в комнату отдыха")
		return L.t("Дать выспаться: перевести в удобную смену")
	if tid == "no_vacation":
		return L.t("Отпустить в отпуск летом")
	if tid == "no_smoke":
		return L.t("Сделать место для перекура")
	if tid == "no_lunch_break":
		return L.t("Вернуть обеденный перерыв в график")
	if cid in ["night", "early"]:
		return L.t("Перевести в другую смену")
	if cid == "nohome":
		return L.t("Построить общежитие: нужна койка")
	if cid in ["nokg", "dorm_bare"]:
		return L.t("Обустроить общежитие и садик для семейных")
	# коллектив
	if cid == "foe" or tid in ["fight", "argued", "saw_fight", "brigade_feud", "friend_left"]:
		var foes := sim.training.foes(w)
		for f in foes:
			if w.brigade >= 0 and f.brigade == w.brigade:
				return L.t("Перевести в другую бригаду")
		for f2 in foes:
			if f2.shift == w.shift:
				return L.t("Развести с недругом по разным сменам")
		return L.t("Устроить праздник или корпоратив: помирить людей")
	if tid in ["no_party", "holiday_forgot", "gift_none", "coworker_fired", "friend_fired_article", "coworker_injured"]:
		return L.t("Устроить праздник или корпоратив")
	if tid in ["union_denied", "kd_broken", "strike_lost", "strike_crushed", "union_heard"]:
		return L.t("Услышать людей: договориться с профкомом")
	if tid == "reprimand":
		return L.t("Не злоупотреблять выговорами: лучше премия")
	if cid == "trait":
		return L.t("Такой характер: поддержать премией или праздником")
	# условия
	var cond := {
		"dark": "Поставить лампы: человек работает в темноте",
		"cold": "Включить отопление в цеху", "freezing": "Включить отопление в цеху",
		"hot": "Поставить вентилятор или вытяжку",
		"stuffy": "Поставить вентиляцию", "fumes": "Поставить вытяжной зонт у станка",
		"noisy": "Выдать наушники (СИЗ)",
		"dirty": "Навести чистоту: нанять уборщика", "very_dirty": "Навести чистоту: нанять уборщика",
		"mice": "Навести чистоту и убрать мусор", "rats": "Навести чистоту на складе",
		"ate_bench": "Поставить столовую с обедом", "ate_standing": "Поставить столовую с обедом", "ate_table": "Поставить столовую с обедом",
		"toilet_open": "Построить туалет со стенами", "toilet_nosink": "Поставить раковину у туалета", "held_it": "Построить ещё один туалет",
		"changed_corner": "Поставить шкафчики в бытовке", "changed_shop": "Поставить шкафчики в бытовке",
		"no_shower": "Построить душевую", "no_milk": "Включить молоко за вредность",
		"no_ppe": "Выдать СИЗ: каску и очки", "no_tools": "Купить инструмент",
		"no_desk": "Дать рабочее место: стол в кабинете", "no_master": "Поставить мастера на смену",
		"shift_mess": "Навести порядок и поставить мастера на смену", "chaos": "Навести порядок на заводе",
		"rush": "Не гнать план: брать меньше заказов", "injured": "Поставить аптечку и провести инструктаж",
		"fire_scare": "Поставить огнетушители и сигнализацию", "breaker": "Разгрузить сеть: поставить автомат",
		"roof_leak": "Починить крышу", "suspended": "Устранить нарушения по предписанию",
		"n1_blame": "Признать вину завода и выплатить компенсацию", "n1_hidden": "Признать вину завода и выплатить компенсацию",
		"office_shared": "Дать отдельный кабинет", "searched": "Сократить обыски на проходной",
		"dogs": "Убрать бродячих собак с территории", "room_l1": "Обустроить помещение: окна, растения, плитка",
	}
	if cond.has(tid):
		return L.t(str(cond[tid]))
	if cid == "hungry":
		return L.t("Накормить: столовая или буфет рядом с цехом")
	if cid == "wc":
		return L.t("Построить туалет поближе к цеху")
	# перспектива
	if tid in ["layoff_rumor"]:
		return L.t("Развеять слухи: собрание и премия")
	if tid in ["exam_failed", "idle_bad", "rational_ignored"]:
		return L.t("Отправить на курсы или дать интересное задание")
	# общее по шкале
	var gen := {
		"money": "Поднять ставку или выдать премию",
		"cond": "Улучшить условия в цеху: быт, свет, тепло, чистота",
		"team": "Устроить праздник или развести конфликтующих",
		"future": "Отправить на курсы или назначить бригадиром",
		"rest": "Дать отдохнуть: комната отдыха, перекуры, отпуск",
	}
	return L.t(str(gen.get(scale, "Улучшить условия")))


## «Что сделать»: {"text"} — конкретный совет по главной жалобе; без жалоб — пояснение, что всё хорошо.
static func advice(sim: Sim, w: Worker, lf: Dictionary = {}) -> String:
	var c := complaint(sim, w, lf)
	if c.is_empty():
		return L.t("Ничего: человеку хорошо, пусть работает")
	return advice_for(sim, w, str(c["scale"]), str(c["cid"]))


## «Сейчас делает» понятными словами.
static func doing(sim: Sim, w: Worker) -> String:
	var act := w.activity if w.present else (L.t("Не вышел на работу") if w.skip_shift else L.t("Дома · %s") % L.t(Worker.SHIFT_NAMES[w.shift]))
	if w.sick_until > sim.minute and w.away_why != "":
		act = L.t("%s до %s") % [L.t(w.away_why).capitalize(), sim.season.date_str(int(w.sick_until / 1440.0) + 1)]
	if not w.order.is_empty() and w.present:
		act += L.t(" · ⚑ приказ до %02d:%02d") % [int(fmod(float(w.order.get("until", 0.0)), 1440.0) / 60.0), int(fmod(float(w.order.get("until", 0.0)), 60.0))]
	return act


## РП-11: ветеран завода — проработал здесь год и больше.
static func veteran(sim: Sim, w: Worker) -> bool:
	return sim.career != null and sim.career.is_veteran(w)


static func value(sim: Sim, w: Worker) -> float:
	var v := Defs.b("mood_base")
	for p in breakdown(sim, w):
		v += float(p[1])
	return clampf(v, 0.0, 100.0)


## Убрать истёкшие мысли и пересчитать кэш настроения.
static func refresh(sim: Sim, w: Worker) -> void:
	for i in range(w.thoughts.size() - 1, -1, -1):
		if float(w.thoughts[i]["until"]) <= sim.minute:
			w.thoughts.remove_at(i)
	w.mood = value(sim, w)


static func label(m: float) -> String:
	if m >= 75.0:
		return L.t("Отличное")
	if m >= 60.0:
		return L.t("Хорошее")
	if m >= 35.0:
		return L.t("Нормальное")
	if m >= 20.0:
		return L.t("Плохое")
	return L.t("Ужасное")


static func color(m: float) -> Color:
	if m >= 60.0:
		return Color("#8fcf78")
	if m >= 35.0:
		return Color("#c9c58a")
	if m >= 20.0:
		return Color("#e0aa48")
	return Color("#d8644e")


## Множитель скорости работы от настроения и черт.
static func productivity(w: Worker) -> float:
	var k := 1.0
	if w.mood >= 75.0:
		k = 1.15
	elif w.mood >= 60.0:
		k = 1.05
	elif w.mood >= 35.0:
		k = 1.0
	elif w.mood >= 20.0:
		k = 0.85
	else:
		k = 0.7
	return k * trait_val(w, "work_k", 1.0)
