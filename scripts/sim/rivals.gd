class_name Rivals
extends RefCounted
## 1.53: директора соседних заводов — у каждого конкурента есть человек с именем, характером и отношением к игроку
## (−100…100). Характер определяет, что он делает: «акула» переманивает людей и перебивает клиентов, «старой закалки»
## предлагает сделки и просит помощи по-соседски, «осторожный» редко лезет и чаще просит помощи, «новатор» зовёт к себе
## толковых людей, предлагает станки и (на поздних этапах) слияние. Отношение меняется от решений игрока.
## Все имена и компании вымышленные. Случайность — отдельный генератор от дня, чтобы не сдвигать sim.rng.

const CHARS := {
	"shark": {"name": "Акула", "desc": "Жёсткий, берёт своё. Переманивает людей, перебивает клиентов, на уступки не идёт.",
		"w": {"poach": 3.0, "steal": 3.0, "deal": 0.7, "help": 0.3}},
	"old": {"name": "Старой закалки", "desc": "Работает по-соседски: предлагает сделки, просит одолжить металл или станок и помнит добро.",
		"w": {"poach": 0.3, "steal": 0.4, "deal": 2.6, "help": 2.4}},
	"careful": {"name": "Осторожный", "desc": "Не рискует и редко лезет первым. Охотнее просит помощи, чем воюет.",
		"w": {"poach": 0.5, "steal": 0.3, "deal": 1.6, "help": 2.2}},
	"novator": {"name": "Новатор", "desc": "Любит новые станки и толковых людей: зовёт к себе мастеров, предлагает сделки и слияние.",
		"w": {"poach": 2.0, "steal": 0.6, "deal": 2.8, "help": 0.5}},
}
const KINDS := ["poach", "steal", "deal", "help"]
## Характеры заводов региона (по id из Market.POOL).
const CHAR_OF := {"tehmash": "old", "zarechny": "shark", "promdetal": "careful", "stankoagr": "novator",
	"kovalchuk": "old", "metallist": "shark", "vektor": "novator"}
const FIRST_M := ["Аркадий", "Виктор", "Геннадий", "Эдуард", "Лев", "Назар", "Руслан", "Тимур", "Ростислав", "Игнат", "Савелий", "Борис"]
const PATR_M := ["Семёнович", "Борисович", "Аркадьевич", "Львович", "Игоревич", "Павлович", "Ильич", "Романович", "Захарович"]
const SURN_M := ["Гордеев", "Лужин", "Тарасевич", "Кравцов", "Мельгунов", "Северин", "Охрименко", "Бородин", "Вересаев", "Ладыгин", "Нестеров", "Сухарев"]
const FIRST_F := ["Инесса", "Алла", "Зоя", "Тамара", "Регина", "Ираида"]
const PATR_F := ["Марковна", "Аркадьевна", "Львовна", "Игоревна", "Павловна"]
const SURN_F := ["Шелестова", "Ладынина", "Верещагина", "Остроухова", "Корнилова", "Беляева"]
const LOG_MAX := 8


static func char_name(ch: String) -> String:
	return L.t(str(CHARS.get(ch, CHARS["careful"])["name"]))


## Новый директор для завода. Детерминированно от id: один и тот же завод — один и тот же человек.
static func make_dir(comp_id: String) -> Dictionary:
	var h := absi(comp_id.hash())
	var fem := h % 7 == 3
	var ch: String = CHAR_OF.get(comp_id, ["shark", "old", "careful", "novator"][h % 4])
	var name := ""
	if fem:
		name = "%s %s %s" % [FIRST_F[h % FIRST_F.size()], PATR_F[(h / 7) % PATR_F.size()], SURN_F[(h / 49) % SURN_F.size()]]
	else:
		name = "%s %s %s" % [FIRST_M[h % FIRST_M.size()], PATR_M[(h / 7) % PATR_M.size()], SURN_M[(h / 49) % SURN_M.size()]]
	return {"name": name, "fem": fem, "char": ch, "rel": 0, "log": [], "seed": h % 100000, "last": -100}


static func dir_of(c: Dictionary) -> Dictionary:
	if not c.has("dir"):
		c["dir"] = make_dir(str(c.get("id", "")))
	return c["dir"]


static func dname(c: Dictionary) -> String:
	var n := str(dir_of(c)["name"])
	return L.translit(n) if L.is_en() else n


## Фамилия и инициалы — для писем: «Гордеев А. С.».
static func short_name(c: Dictionary) -> String:
	var p := str(dir_of(c)["name"]).split(" ")
	var s := "%s %s. %s." % [p[2], p[0].substr(0, 1), p[1].substr(0, 1)] if p.size() >= 3 else str(dir_of(c)["name"])
	return L.translit(s) if L.is_en() else s


static func rel_of(c: Dictionary) -> int:
	return int(dir_of(c)["rel"])


static func rel_word(r: int) -> String:
	if r <= -60:
		return L.t("враждебное")
	if r <= -25:
		return L.t("холодное")
	if r < 25:
		return L.t("нейтральное")
	if r < 60:
		return L.t("доброе")
	return L.t("союзник")


## Внешность портрета (PortraitKit): по характеру и зерну директора, без внешней графики.
static func look(c: Dictionary) -> Dictionary:
	var d := dir_of(c)
	var sd := int(d["seed"])
	var fem := bool(d["fem"])
	var ch := str(d["char"])
	var lk := {"skin": 0 if sd % 5 < 3 else 1, "hair": "", "hair_col": "", "beard": "", "glasses": false, "phones": false,
		"body": "normal", "bulk": 1.0, "fem": fem, "h": 1.0, "outfit": "jacket", "outfit_col": "#2c3440", "hat": "", "hat_col": "#f2f2ee",
		"age": 50, "fs": sd * 31 + 7}
	var grey := ["#9a9a94", "#c8c8c2", "#7d7a74"]
	var dark := ["#2a2420", "#33261e", "#4a3020"]
	match ch:
		"shark":
			lk["hair"] = "slick" if not fem else "bob"
			lk["hair_col"] = dark[sd % 3]
			lk["beard"] = "" if fem else ("goatee" if sd % 2 == 0 else "")
			lk["outfit"] = "jacket"
			lk["outfit_col"] = "#1f2630"
			lk["body"] = "strong"
			lk["age"] = 46
		"old":
			lk["hair"] = "receding" if not fem else "perm"
			lk["hair_col"] = grey[sd % 3]
			lk["beard"] = "" if fem else "mustache"
			lk["outfit"] = "coat"
			lk["outfit_col"] = "#8a7c62"
			lk["hat"] = "cap" if not fem else ""
			lk["body"] = "stout"
			lk["age"] = 63
		"careful":
			lk["hair"] = "side" if not fem else "bun"
			lk["hair_col"] = grey[(sd + 1) % 3]
			lk["glasses"] = true
			lk["outfit"] = "coat"
			lk["outfit_col"] = "#6d7480"
			lk["body"] = "thin"
			lk["age"] = 55
		_:
			lk["hair"] = "crew" if not fem else "pixie"
			lk["hair_col"] = dark[(sd + 2) % 3]
			lk["beard"] = "" if fem else "stubble"
			lk["outfit"] = "vest"
			lk["outfit_col"] = "#3f8fb0"
			lk["body"] = "normal"
			lk["age"] = 38
	return lk


# ================================================================ отношение и журнал

static func log_add(c: Dictionary, sim: Sim, text: String) -> void:
	var d := dir_of(c)
	var lg: Array = d["log"]
	lg.push_front({"d": sim.day(), "t": text})
	if lg.size() > LOG_MAX:
		lg.resize(LOG_MAX)


## Отношение директора к игроку изменилось. why — короткая запись в журнал карточки.
static func shift(c: Dictionary, sim: Sim, delta: int, why: String) -> void:
	var d := dir_of(c)
	d["rel"] = clampi(int(d["rel"]) + delta, -100, 100)
	if why != "":
		log_add(c, sim, "%s (%s%d)" % [why, "+" if delta > 0 else "−", absi(delta)])


## Вес действий директора: характер × отношение. Враги чаще бьют, друзья — чаще предлагают.
static func weights(c: Dictionary, stage: int) -> Dictionary:
	var d := dir_of(c)
	var base: Dictionary = CHARS[str(d["char"])]["w"]
	var rel := float(d["rel"])
	var w := {}
	for k in KINDS:
		w[k] = float(base[k])
	var hostile := clampf(-rel / 100.0, 0.0, 1.0)
	var friendly := clampf(rel / 100.0, 0.0, 1.0)
	w["poach"] = float(w["poach"]) * (1.0 + hostile * 1.5) * (1.0 - friendly * 0.8)
	w["steal"] = float(w["steal"]) * (1.0 + hostile * 1.5) * (1.0 - friendly * 0.9)
	w["deal"] = float(w["deal"]) * (1.0 + friendly * 1.2) * (1.0 - hostile * 0.6)
	w["help"] = float(w["help"]) * (1.0 + friendly * 1.0) * (1.0 - hostile * 0.5)
	if stage < 2:
		w["steal"] = 0.0
	return w


static func pick(c: Dictionary, rng: RandomNumberGenerator, stage: int) -> String:
	var w := weights(c, stage)
	var tot := 0.0
	for k in KINDS:
		tot += float(w[k])
	var r := rng.randf() * tot
	for k in KINDS:
		r -= float(w[k])
		if r <= 0.0:
			return k
	return "deal"


# ================================================================ неделя

## Понедельник: один из директоров делает ход. Возвращает {comp, kind} или {}.
static func week(mk: Market) -> Dictionary:
	var sim := mk.sim
	var rng := RandomNumberGenerator.new()
	rng.seed = 153 * 100003 + sim.day() * 7919
	# отношение: политика цен давит на соседей, остальное тянется к нулю
	for c: Dictionary in mk.alive_comps():
		var d := dir_of(c)
		if mk.policy == "dump":
			shift(c, sim, -4 if str(d["char"]) == "shark" else -2, L.t("Наш демпинг бьёт по их ценам"))
		elif mk.policy == "premium" and str(d["char"]) in ["old", "careful"]:
			shift(c, sim, 1, L.t("Мы не сбиваем цены"))
		var r := int(d["rel"])
		if absi(r) > 20:
			d["rel"] = r - signi(r)
	var al := mk.alive_comps()
	if al.is_empty():
		return {}
	# ход делает не каждую неделю и не один и тот же завод подряд
	var cands: Array = []
	for c2: Dictionary in al:
		if sim.day() - int(dir_of(c2)["last"]) >= 6:
			cands.append(c2)
	if cands.is_empty() or rng.randf() > 0.7:
		return {}
	var c3: Dictionary = cands[rng.randi_range(0, cands.size() - 1)]
	var kinds: Array = []
	for i in 4:
		kinds.append(pick(c3, rng, sim.progress.stage))
	for kind in kinds:
		if act(mk, c3, str(kind), rng):
			dir_of(c3)["last"] = sim.day()
			return {"comp": str(c3["id"]), "kind": str(kind)}
	return {}


## Выполнить ход директора. false — сейчас невозможно (нет подходящего человека, металла и т. п.).
static func act(mk: Market, c: Dictionary, kind: String, rng: RandomNumberGenerator = null) -> bool:
	if rng == null:
		rng = RandomNumberGenerator.new()
		rng.seed = 153 * 100003 + mk.sim.day() * 7919 + 1
	match kind:
		"poach":
			return mk._poach(c)
		"steal":
			return _steal(mk, c)
		"deal":
			return _deal(mk, c, rng)
		"help":
			return _help(mk, c, rng)
	return false


static func _steal(mk: Market, c: Dictionary) -> bool:
	var sim := mk.sim
	if sim.reputation <= 0.0:
		return false
	var cn := Company.firm(str(c["name"]))
	var cost := 15000.0
	sim.story.add_mod("rival_steal", 0.85, 7.0 * 1440.0, L.t("Конкурент перебивает клиентов"))
	shift(c, sim, -3, L.t("Перебивал наших клиентов"))
	sim.story.letter("rival_steal", L.t("%s перебивает клиентов") % cn,
		L.t("Директор %s (%s) обзванивает наших заказчиков и сулит им скидки. Если ничего не делать, заявок будет на 15%% меньше неделю.") % [short_name(c), char_name(str(dir_of(c)["char"])).to_lower()],
		"thief", Sim.LVL_WARN,
		[{"text": L.t("Обзвонить клиентов самим (%s)") % Defs.money_str(cost), "hint": L.t("Скидки и звонки: заявки вернутся сразу")},
		{"text": L.t("Не реагировать"), "hint": L.t("Заявок −15% неделю")}],
		1, {"comp": str(c["id"]), "cost": cost})
	return true


static func _deal(mk: Market, c: Dictionary, rng: RandomNumberGenerator) -> bool:
	var sim := mk.sim
	var cn := Company.firm(str(c["name"]))
	var d := dir_of(c)
	var subs: Array = ["order", "machine"]
	if sim.progress.stage >= 5 and int(d["rel"]) >= 30 and str(d["char"]) != "shark":
		subs.append("merger")
		subs.append("merger")
	var sub: String = subs[rng.randi_range(0, subs.size() - 1)]
	if sub == "order":
		var avail := sim.prod.processes_available()
		var pool: Array = []
		for k in sim.progress.products():
			var ks := str(k)
			if Defs.products.has(ks) and sim.office.unlocked(Defs.products[ks]) and sim.prod.can_make(ks, avail):
				pool.append(ks)
		if pool.is_empty():
			sub = "machine"
		else:
			var p := str(pool[rng.randi_range(0, pool.size() - 1)])
			sim.story.letter("rival_deal", L.t("%s делится заказом") % cn,
				L.t("Директор %s: «Мы не успеваем — возьмёте часть нашего заказа на %s? Заплатим на 10%% выше рынка». Заказ появится на доске заявок.") % [short_name(c), Defs.product_name(p).to_lower()],
				"handshake", Sim.LVL_INFO,
				[{"text": L.t("Взять часть заказа"), "hint": L.t("Заявка на доске, цена +10%; отношение растёт")}, {"text": L.t("Отказаться"), "hint": L.t("Без обид")}],
				1, {"comp": str(c["id"]), "sub": "order", "product": p})
			return true
	if sub == "machine":
		var cand: Array = []
		for m in ["lathe", "mill", "drill", "weld_post", "furnace", "press"]:
			if Defs.objects.has(m) and sim.progress.locked_reason(m) == "":
				cand.append(m)
		if cand.is_empty():
			return false
		var def := str(cand[rng.randi_range(0, cand.size() - 1)])
		sim.story.letter("rival_deal", L.t("%s продаёт станок") % cn,
			L.t("Директор %s обновляет парк и отдаёт б/у станок «%s» за 60%% цены — только вам, по-соседски.") % [short_name(c), Defs.obj_name(def)],
			"handshake", Sim.LVL_INFO,
			[{"text": L.t("Купить"), "hint": L.t("Следующий такой станок обойдётся в 60% цены (две недели)")}, {"text": L.t("Не нужно"), "hint": ""}],
			1, {"comp": str(c["id"]), "sub": "machine", "def": def})
		return true
	# слияние: пока только предложение с выбором
	sim.story.letter("rival_deal", L.t("%s предлагает слияние") % cn,
		L.t("Директор %s (%s) всерьёз предлагает объединить заводы: общие заказы, станки и клиенты. Пока это только разговор — сделка потребует месяцев.") % [short_name(c), char_name(str(d["char"])).to_lower()],
		"handshake", Sim.LVL_INFO,
		[{"text": L.t("Начать переговоры"), "hint": L.t("Репутация +2, отношение растёт; решение о слиянии — позже")}, {"text": L.t("Вежливо отказаться"), "hint": L.t("Отношение немного упадёт")}],
		1, {"comp": str(c["id"]), "sub": "merger"})
	return true


static func _help(mk: Market, c: Dictionary, rng: RandomNumberGenerator) -> bool:
	var sim := mk.sim
	var cn := Company.firm(str(c["name"]))
	# металл: у нас есть что одолжить?
	var best := ""
	var best_n := 0
	for k in Defs.materials.keys():
		var n := sim.free_material(str(k))
		if n > best_n:
			best_n = n
			best = str(k)
	if best_n >= 6 and rng.randf() < 0.6:
		var qty := mini(10, best_n / 2)
		var price := roundf(float(Defs.materials[best].get("price", 100)) * qty * 1.35 / 10.0) * 10.0
		sim.story.letter("rival_help", L.t("%s просит металл") % cn,
			L.t("Директор %s просит одолжить %d × %s: сорвалась поставка. Вернёт деньгами с наценкой — %s.") % [short_name(c), qty, Defs.material_name(best), Defs.money_str(price)],
			"handshake", Sim.LVL_INFO,
			[{"text": L.t("Одолжить за плату"), "hint": L.t("+%s, отношение растёт; металл уйдёт со склада") % Defs.money_str(price)}, {"text": L.t("Отказать"), "hint": L.t("Отношение упадёт")}],
			1, {"comp": str(c["id"]), "sub": "metal", "mat": best, "qty": qty, "price": price})
		return true
	# станок на ночь
	var ms: Array = sim.things_of("machine").filter(func(t: Thing) -> bool: return t.built and t.enabled and not t.broken and not t.demolish)
	if ms.is_empty():
		return false
	var m: Thing = ms[rng.randi_range(0, ms.size() - 1)]
	var fee := 8000.0
	sim.story.letter("rival_help", L.t("%s просит станок") % cn,
		L.t("Директор %s: «Выручайте — у нас встал станок, а заказ горит. Одолжите на ночь ваш %s?» Заплатят %s, но станок поизносится.") % [short_name(c), m.title().to_lower(), Defs.money_str(fee)],
		"handshake", Sim.LVL_INFO,
		[{"text": L.t("Одолжить за плату"), "hint": L.t("+%s, износ станка −10%%, отношение растёт") % Defs.money_str(fee)}, {"text": L.t("Отказать"), "hint": L.t("Отношение упадёт")}],
		1, {"comp": str(c["id"]), "sub": "machine", "thing": m.id, "price": fee})
	return true


# ================================================================ решения игрока

## Решение по письму «rival_*». Вызывается из Market.on_letter.
static func on_letter(mk: Market, ev: String, d: Dictionary, choice: int) -> void:
	var sim := mk.sim
	var c := mk.comp(str(d.get("comp", "")))
	if c.is_empty():
		return
	var cn := Company.firm(str(c["name"]))
	match ev:
		"rival_steal":
			if choice == 0:
				var cost := float(d.get("cost", 15000.0))
				if sim.money < cost:
					sim.notify(L.t("Денег на обзвон нет — переживём неделю с меньшим потоком заявок."), Sim.LVL_WARN)
					return
				sim.spend(cost, "Реклама в обзвоне клиентов")
				sim.story.remove_mod("rival_steal")
				shift(c, sim, -1, L.t("Мы отбили клиентов"))
				sim.notify(L.t("Клиентам позвонили первыми — заявки вернулись."), Sim.LVL_GOOD)
			else:
				log_add(c, sim, L.t("Клиенты ушли к ним на неделю"))
		"rival_deal":
			match str(d.get("sub", "")):
				"order":
					if choice == 0:
						var o := sim.orders.make_offer(str(d.get("product", "")))
						o["price"] = int(round(float(o["price"]) * 1.1 / 10.0) * 10)
						o["client"] = cn
						o["status"] = "offer"
						o["expires"] = sim.minute + 3.0 * 1440.0
						sim.orders.list.append(o)
						shift(c, sim, 5, L.t("Взяли часть их заказа"))
						sim.notify(L.t("Часть заказа %s — на доске заявок: цена выше рынка, срок принятия три дня.") % cn, Sim.LVL_GOOD)
					else:
						shift(c, sim, -1, L.t("Отказались от их заказа"))
				"machine":
					if choice == 0:
						var def := str(d.get("def", ""))
						sim.story.add_mod("voucher:" + def, 0.6, 14.0 * 1440.0, L.t("Станок у соседа"))
						shift(c, sim, 4, L.t("Купили у них станок"))
						sim.notify(L.t("Договорились: «%s» у %s — за 60%% цены, ставьте в течение двух недель.") % [Defs.obj_name(def), cn], Sim.LVL_GOOD)
					else:
						shift(c, sim, -1, L.t("Отказались от станка"))
				"merger":
					if choice == 0:
						sim.reputation = minf(100.0, sim.reputation + 2.0)
						shift(c, sim, 10, L.t("Согласились на переговоры о слиянии"))
						sim.notify(L.t("Переговоры о слиянии с %s начались — пока это только разговоры, ничего не обязывает.") % cn, Sim.LVL_INFO)
					else:
						shift(c, sim, -3, L.t("Отказали в слиянии"))
		"rival_help":
			match str(d.get("sub", "")):
				"metal":
					if choice == 0:
						var mat := str(d.get("mat", ""))
						var qty := int(d.get("qty", 0))
						if _take_metal(sim, mat, qty) < qty:
							sim.notify(L.t("Металла на складе уже не хватает — отказали."), Sim.LVL_WARN)
							shift(c, sim, -2, L.t("Не смогли одолжить металл"))
							return
						sim.earn(float(d.get("price", 0.0)), "Оплата: металл соседнему заводу")
						shift(c, sim, 8, L.t("Одолжили металл"))
						sim.notify(L.t("%s получил металл и расплатился с наценкой.") % cn, Sim.LVL_GOOD)
					else:
						shift(c, sim, -3, L.t("Отказали в металле"))
				"machine":
					if choice == 0:
						var t: Thing = sim.things.get(int(d.get("thing", -1)))
						if t != null:
							t.condition = maxf(0.0, t.condition - 10.0)
						sim.earn(float(d.get("price", 8000.0)), "Оплата: аренда станка соседом")
						shift(c, sim, 6, L.t("Одолжили станок на ночь"))
						sim.notify(L.t("Станок вернулся от %s с оплатой, но немного изношенный.") % cn, Sim.LVL_INFO)
					else:
						shift(c, sim, -3, L.t("Отказали в станке"))


## Убрать со склада qty единиц металла. Возвращает, сколько убрали.
static func _take_metal(sim: Sim, mat: String, qty: int) -> int:
	var n := 0
	for it: Item in sim.items.values().duplicate():
		if n >= qty:
			break
		if it.kind != "mat" or it.def_id != mat or it.reserved_by >= 0:
			continue
		var ok := it.loc == Item.Loc.GROUND
		if it.loc == Item.Loc.THING:
			var t: Thing = sim.things.get(it.holder)
			ok = t != null and t.is_storage()
		if ok:
			sim.delete_item(it)
			n += 1
	return n
