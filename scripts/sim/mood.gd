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


## 1.15 (РП-8): пять жизненных потребностей — из чего складывается настроение.
const LIFE := [["byt", "Быт"], ["money", "Деньги"], ["work", "Работа"], ["team", "Коллектив"], ["home", "Дом"]]
const LIFE_HINT := {
	"byt": "Столовая с горячим обедом, душ, бытовка со шкафчиками, тепло, свет и чистота в цехах.",
	"money": "Ставка не ниже рыночной, премии, зарплата вовремя, индексация.",
	"work": "Своё рабочее место, толковый мастер, СИЗ, курсы и разряд, порядок на участке.",
	"team": "Бригада, праздники и подарки, профком; поменьше ссор, драк и увольнений.",
	"home": "Отпуск летом, удобная смена, общежитие и детский сад для семейных.",
}


## {группа: {"v": 0–100, "parts": [[текст, значение], ...]}} — для полосок в карточке.
static func life(sim: Sim, w: Worker) -> Dictionary:
	var out := {}
	for g in LIFE:
		out[g[0]] = {"v": 0.0, "parts": []}
	var add := func(grp: String, text: String, v: float) -> void:
		(out[grp]["parts"] as Array).append([text, v])
		out[grp]["v"] = float(out[grp]["v"]) + v
	for th: Dictionary in w.thoughts:
		if float(th["until"]) > sim.minute:
			var td: Dictionary = Defs.thoughts.get(str(th["id"]), {})
			add.call(str(td.get("grp", "work")), thought_text(str(th["id"])), float(th["mood"]))
	if float(w.needs["food"]) < 15.0:
		add.call("byt", L.t("Голоден"), -8.0)
	if float(w.needs["rest"]) < 15.0:
		add.call("byt", L.t("Вымотан"), -6.0)
	var ratio := float(w.wage) / maxf(1.0, float(market_wage(w)))
	var wk := trait_val(w, "wage_k", 1.0)
	if ratio < 0.9:
		add.call("money", L.t("Платят меньше, чем везде"), -7.0 * wk)
	elif ratio >= 1.15:
		add.call("money", L.t("Хорошо платят"), 5.0 * wk)
	else:
		add.call("money", L.t("Платят как везде"), 0.0)
	if w.shift == 1:
		var nm := trait_val(w, "night_mood", 0.0)
		add.call("home", L.t("Вторая смена"), nm if nm != 0.0 else -2.0)
	if sim and sim.training and sim.get_worker(w.id) == w:
		for p in sim.training.mood_parts(w):
			add.call("work", str(p[0]), float(p[1]))
	if sim and sim.town and sim.get_worker(w.id) == w:
		for p2 in sim.town.mood_parts(w):
			add.call("home", str(p2[0]), float(p2[1]))
	if sim and sim.get_worker(w.id) == w and veteran(sim, w):
		add.call("team", L.t("Ветеран завода — уважают"), 3.0)
	for g2 in out.keys():
		out[g2]["v"] = clampf(55.0 + 3.0 * float(out[g2]["v"]), 0.0, 100.0)
	return out


## Самая проседающая потребность: [код, название, подсказка] или [] — если всё в порядке.
static func life_worst(sim: Sim, w: Worker) -> Array:
	var lf := life(sim, w)
	var worst := ""
	var wv := 101.0
	for g in LIFE:
		var v := float(lf[g[0]]["v"])
		if v < wv:
			wv = v
			worst = str(g[0])
	if wv >= 45.0:
		return []
	for g2 in LIFE:
		if g2[0] == worst:
			return [worst, L.t(str(g2[1])), L.t(str(LIFE_HINT[worst]))]
	return []


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
