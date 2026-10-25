class_name Calls
extends RefCounted
## 1.41: телефонные звонки. Событие кладёт звонок в очередь, интерфейс (PhoneCall) показывает кнопку-телефон,
## по нажатию — диалог с портретом. Никаких случайных чисел и влияния на экономику: очередь лишь «читается» окном.
## Тексты хранятся русскими ключами и переводятся при показе (L.t).

const DIR := "res://assets/calls/"
## id звонящего -> папка с картинками, название роли, набор эмоций.
const CHARS := {
	"engineer": {"dir": "00_chief_engineer", "name": "Главный инженер",
		"emo": ["neutral", "explaining", "angry", "pleased", "surprised", "worried", "tired", "thinking", "ironic"]},
	"fire": {"dir": "01_fire_inspector", "name": "Инспектор пожарного надзора", "emo": ["neutral", "strict", "pleased"]},
	"sanitary": {"dir": "02_sanitary_inspector", "name": "Санитарный врач", "emo": ["neutral", "strict", "pleased"]},
	"ecology": {"dir": "03_environmental_inspector", "name": "Инспектор-эколог", "emo": ["neutral", "strict", "pleased"]},
	"labor": {"dir": "04_labor_inspector", "name": "Государственный инспектор труда", "emo": ["neutral", "strict", "pleased"]},
	"tech": {"dir": "05_technical_inspector", "name": "Инспектор технадзора", "emo": ["neutral", "strict", "pleased"]},
	"tax": {"dir": "06_tax_inspector", "name": "Налоговый инспектор", "emo": ["neutral", "strict", "pleased"]},
	"deputy": {"dir": "07_deputy", "name": "Депутат", "emo": ["neutral", "strict", "pleased"]},
	"procurement": {"dir": "09_procurement_manager", "name": "Заказчик — начальник снабжения", "emo": ["neutral", "strict", "pleased"]},
	"technologist": {"dir": "10_chief_technologist", "name": "Заказчик — главный технолог", "emo": ["neutral", "strict", "pleased"]},
}
## Вид проверки (data/inspections.json) -> звонящий. Военной приёмки среди персонажей нет — она без звонка.
const INSPECTORS := {"fire": "fire", "sanitary": "sanitary", "ecology": "ecology", "labor": "labor", "tech": "tech", "tax": "tax"}

const MAX_QUEUE := 4
const EXPIRE_MIN := 600.0        ## звонок, на который не ответили, тихо гаснет через 10 игровых часов
const ENG_PER_DAY := 1           ## 1.44: советник: не больше одного звонка в сутки…
const ENG_URGENT_DAY := 2        ## …и ещё один — только срочный (пожар, несчастный случай)
const ENG_GAP := 150.0           ## минут между его звонками
const TAG_DAYS := 5.0            ## 1.44: одна и та же тема — не чаще, чем раз в 5 суток

var sim: Sim
var queue: Array = []            ## [{id, caller, emotion, key, args, action, label, born, tag}]
var seq := 0
var total := 0
var eng_day := -1
var eng_cnt := 0
var eng_last := -99999.0
var tag_at: Dictionary = {}
var debt_n := 0
var tips_done: Array = []



func _init(s: Sim) -> void:
	sim = s


static func info(caller: String) -> Dictionary:
	return CHARS.get(caller, {})


static func role_name(caller: String) -> String:
	return str(info(caller).get("name", ""))


## Эмоция, которой нет у персонажа, заменяется на neutral.
static func emotion_of(caller: String, emotion: String) -> String:
	var emo: Array = info(caller).get("emo", [])
	return emotion if emo.has(emotion) else "neutral"


static func portrait_path(caller: String, emotion: String) -> String:
	return "%s%s/%s.png" % [DIR, str(info(caller).get("dir", "")), emotion_of(caller, emotion)]


static func office_path(caller: String) -> String:
	return "%s%s/office.jpg" % [DIR, str(info(caller).get("dir", ""))]


## Текст реплики для показа (на языке интерфейса).
## Аргументы-метки: «insp.fire.name» — название проверки, «date:N» — дата (день N), «money:N» — сумма.
static func text_of(c: Dictionary, sm: Sim = null) -> String:
	var a: Array = []
	for x in (c.get("args", []) as Array):
		var v: Variant = x
		if x is String:
			var xs := str(x)
			if xs.begins_with("insp.") and xs.ends_with(".name"):
				var tp := xs.split(".")[1]
				v = L.dt(xs, str((Defs.inspections.get("types", {}) as Dictionary).get(tp, {}).get("name", tp)))
			elif xs.begins_with("date:") and sm != null:
				v = sm.season.date_str(int(xs.substr(5)))
			elif xs.begins_with("money:"):
				v = Defs.money_str(float(xs.substr(6)))
			else:
				v = L.tx(xs)
		a.append(v)
	var s := L.t(str(c.get("key", "")))
	return (s % a) if not a.is_empty() else s


## Положить звонок в очередь. cd — сколько суток не повторять тот же совет (tag).
func push(caller: String, emotion: String, key: String, args: Array = [], tag: String = "", action: String = "", label: String = "", urgent: bool = false, cd: float = TAG_DAYS) -> bool:
	if not CHARS.has(caller):
		return false
	var tg := tag if tag != "" else key
	if tag_at.has(tg) and sim.minute - float(tag_at[tg]) < cd * 1440.0:
		return false
	if queue.size() >= MAX_QUEUE:
		return false
	for q: Dictionary in queue:
		if str(q["tag"]) == tg:
			return false
	if caller == "engineer":
		var d := sim.day()
		if d != eng_day:
			eng_day = d
			eng_cnt = 0
		if eng_cnt >= (ENG_URGENT_DAY if urgent else ENG_PER_DAY):
			return false
		if sim.minute - eng_last < (30.0 if urgent else ENG_GAP):
			return false
		eng_cnt += 1
		eng_last = sim.minute
	tag_at[tg] = sim.minute
	seq += 1
	total += 1
	queue.append({"id": seq, "caller": caller, "emotion": emotion_of(caller, emotion), "key": key, "args": args.duplicate(),
		"action": action, "label": label, "born": sim.minute, "tag": tg})
	return true


## Первый живой звонок (протухшие тихо удаляются). Не убирает его из очереди.
func peek() -> Dictionary:
	while not queue.is_empty() and sim.minute - float((queue[0] as Dictionary)["born"]) > EXPIRE_MIN:
		queue.pop_front()
	return queue[0] if not queue.is_empty() else {}


func pop() -> Dictionary:
	var c := peek()
	if not c.is_empty():
		queue.pop_front()
	return c


func has_call() -> bool:
	return not peek().is_empty()


# ---------------------------------------------------------------- проверки и визиты

func on_inspection(t: String, n: int, fine: float, due_day: int) -> void:
	if not INSPECTORS.has(t):
		return
	var who: String = str(INSPECTORS[t])
	if n <= 0:
		return   # 1.44: «всё чисто» — не повод для звонка
	elif fine <= 0.0:
		push(who, "strict", "Нарушений: %d. На первый раз ограничусь предупреждением. Устраните до %s — иначе будет штраф.", [n, "date:%d" % due_day], "res_" + t, "events:insp", "Открыть проверки", false, 0.0)
	else:
		push(who, "strict", "Составлен акт: нарушений %d, штраф %s. Устраните до %s, повторное нарушение обойдётся дороже.",
			[n, "money:%d" % int(fine), "date:%d" % due_day], "res_" + t, "events:insp", "Открыть проверки", false, 0.0)


func on_visit_notice(kind: String) -> void:
	if kind == "governor":
		push("deputy", "neutral", "Добрый день. Через два дня завод посетит губернатор области. Наведите порядок: от этого зависит поддержка.", [], "visit_gov", "events:insp", "Открыть календарь", false, 1.0)


# ---------------------------------------------------------------- заказчики

func on_reclamation(product: String, bad: int) -> void:
	push("procurement", "strict", "В партии «%s» нашли %d шт. с браком. Рассмотрите рекламацию и дайте ответ: заменить или компенсировать.",
		[product, bad], "recl", "events:now", "Открыть события", false, 1.0)


func on_contract_offer(firm: String) -> void:
	push("procurement", "neutral", "Добрый день. %s готов подписать контракт на регулярные поставки. Условия — во вкладке «Контракты».",
		[firm], "offer", "orders", "Открыть заказы", false, 1.0)


func on_tender() -> void:
	push("technologist", "neutral", "Объявлен тендер. Требования строгие, зато и оплата достойная. Решение — во вкладке «Контракты».", [], "tender", "orders", "Открыть заказы", false, 1.0)


# ---------------------------------------------------------------- главный инженер (советник)

func on_breakdown(title: String) -> void:
	push("engineer", "worried", "%s сломался. Нужны запчасти, и чем скорее, тем лучше. А ППР в «Производство → Станки» не даст такому повториться.",
		[title], "broken", "prod:machines", "Открыть станки")


func on_metal_low(need: int, mat: String) -> void:
	push("engineer", "thinking", "Металла «%s» не хватает на заказы: нужно ещё %d шт. Давайте решим, где взять деньги, пока цех не встал.",
		[mat, need], "metal", "prod:supply", "Открыть снабжение")


func on_fire() -> void:
	push("engineer", "surprised", "Пожар! Людей от огня, огнетушители в руки. Потом ждите пожарных — проверка будет.", [], "fire", "", "", true)


func on_injury() -> void:
	push("engineer", "surprised", "В цеху несчастный случай. Проверьте охрану труда и аптечки, пока не пришла трудовая инспекция.", [], "injury", "people:safety", "Охрана труда", true)


func morning() -> void:
	# проверка уже завтра
	for q: Dictionary in sim.inspect.queue:
		var dt := float(q["at"]) - sim.minute
		if bool(q.get("announced", false)) and dt > 0.0 and dt < 1440.0 and INSPECTORS.has(str(q["type"])):
			push("engineer", "explaining", "Завтра проверка: %s. Загляните в «События → Проверки» — там список требований. Лучше исправить всё заранее.",
				["insp.%s.name" % str(q["type"])], "soon_" + str(q["type"]), "events:insp", "Открыть проверки", false)
			break
	# касса
	if sim.money < 0.0:
		debt_n += 1
		if debt_n >= 3:
			push("engineer", "angry", "Опять кассовый разрыв! Так нельзя: сократите расходы или берите заказы с предоплатой.", [], "debt", "finance:summary", "Открыть финансы", false)
		else:
			push("engineer", "worried", "В кассе минус. Пока не вернёте деньги, закупки и зарплата под угрозой. Выполняйте заказы и не берите лишнего.", [], "debt", "finance:summary", "Открыть финансы", false)
	else:
		debt_n = 0


func to_dict() -> Dictionary:
	return {"queue": queue.duplicate(true), "seq": seq, "total": total, "eng_day": eng_day, "eng_cnt": eng_cnt, "eng_last": eng_last,
		"tag_at": tag_at.duplicate(), "debt_n": debt_n, "tips": tips_done.duplicate()}


func from_dict(d: Dictionary) -> void:
	queue = (d.get("queue", []) as Array).duplicate(true)
	seq = int(d.get("seq", 0))
	total = int(d.get("total", 0))
	eng_day = int(d.get("eng_day", -1))
	eng_cnt = int(d.get("eng_cnt", 0))
	eng_last = float(d.get("eng_last", -99999.0))
	tag_at = (d.get("tag_at", {}) as Dictionary).duplicate()
	debt_n = int(d.get("debt_n", 0))
	tips_done = (d.get("tips", []) as Array).duplicate()
