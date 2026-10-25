class_name Nicks
extends RefCounted
## Прозвища рабочих. Часть людей приходит со своим прозвищем «с прошлой работы» (за внешность
## и характер), остальные зарабатывают его на заводе — за поступки: потушил пожар, выточил
## больше всех, вечно сбрасывает автоматы. О новом прозвище пишут в многотиражке.

## Правила: cond — условие, m/f — прозвище для мужчин/женщин, hire — может прийти с прошлой работы,
## why — почему так прозвали (несколько вариантов; %s — имя).
const RULES := [
	{"cond": "old", "m": ["Батя", "Дед"], "f": ["Мама", "Тётя Шура"], "hire": true,
		"why": ["%s старше всех в цеху: молодых учит, всех угощает бутербродами — вот и {прозвали|прозвали}.",
			"Как-то %s полдня {объяснял|объясняла} молодым, как правильно заточить резец, — с тех пор иначе и не зовут."]},
	{"cond": "young", "m": ["Малой", "Студент"], "f": ["Малая", "Студентка"], "hire": true,
		"why": ["%s — {самый молодой|самая молодая} на участке, ещё и в общаге живёт. Прозвище прилипло с первого дня.",
			"%s {пришёл|пришла} с учебником под мышкой, а на перекуре {спросил|спросила}, что такое «НЗП»."]},
	{"cond": "thin", "m": ["Шпала", "Кощей"], "f": ["Тростинка", "Стрекоза"], "hire": true,
		"why": ["%s {высокий и худой|высокая и худая} — в проход между стеллажами проходит боком, не задевая.",
			"Спецовку для %s пришлось ушивать дважды — отсюда и прозвище."]},
	{"cond": "fat", "m": ["Колобок", "Пончик", "Медведь"], "f": ["Пышка", "Ватрушка"], "hire": true,
		"why": ["%s {первым|первой} приходит в столовую и {последним|последней} уходит. Никто не обижается — и сам{|а} %s тоже.",
			"На спор %s {съел|съела} три порции котлет и после этого {перевыполнил|перевыполнила} норму."]},
	{"cond": "stout", "m": ["Бульдозер", "Шкаф"], "f": ["Богатырша"], "hire": true,
		"why": ["%s однажды в одиночку {передвинул|передвинула} верстак, который двое не могли сдвинуть.",
			"Когда сломалась тележка, %s {донёс|донесла} поддон с металлом на руках."]},
	{"cond": "glasses", "m": ["Профессор", "Очкарик"], "f": ["Профессорша", "Отличница"], "hire": true,
		"why": ["%s замечает брак, который не видят даже штангенциркулем. Профессор, не иначе.",
			"%s читает техпроцессы, как романы, и цитирует ГОСТы наизусть."]},
	{"cond": "phones", "m": ["Диджей"], "f": ["Диджейка"], "hire": true,
		"why": ["%s даже у станка в наушниках. Мастер спросил, что играет, — получил плейлист на час."]},
	{"cond": "smoker", "m": ["Паровоз"], "f": ["Дымка"], "hire": false,
		"why": ["За неделю %s {сбегал|сбегала} на перекур больше, чем остальные за месяц. Мастер считал.",
			"Из курилки %s выходит в облаке дыма, как паровоз из депо."]},
	{"cond": "night", "m": ["Филин"], "f": ["Сова"], "hire": false,
		"why": ["%s ночью работает бодрее, чем днём, и уходит со смены {довольный|довольная}, когда все зевают."]},
	{"cond": "neat", "m": ["Чистюля", "Аккуратист"], "f": ["Чистюля", "Хозяюшка"], "hire": false,
		"why": ["%s протирает станок после каждой детали и раскладывает ключи по размеру. Все смеются, но завидуют."]},
	{"cond": "fire", "m": ["Пожарный", "Брандмейстер"], "f": ["Пожарная"], "hire": false, "event": true,
		"why": ["Когда загорелось, %s {первым|первой} {схватил|схватила} огнетушитель и {потушил|потушила} огонь, пока остальные звонили 01.",
			"%s {тушил|тушила} пожар так уверенно, будто всю жизнь {служил|служила} в пожарной части. С тех пор только так и зовут."]},
	{"cond": "injured", "m": ["Везунчик", "Заговорённый"], "f": ["Везучая"], "hire": false, "event": true,
		"why": ["После травмы %s {вернулся|вернулась} раньше срока и {пошутил|пошутила}: «Меня станком не возьмёшь». Прозвище не заставило себя ждать."]},
	{"cond": "reset", "m": ["Искра", "Ампер"], "f": ["Искорка"], "hire": false, "event": true,
		"why": ["%s {сбрасывал|сбрасывала} автомат на щите уже столько раз, что открывает щит с закрытыми глазами."]},
	{"cond": "golden", "m": ["Золотые руки", "Ювелир"], "f": ["Золотые руки", "Ювелирша"], "hire": true,
		"why": ["Деталь от %s ОТК даже не меряет — бесполезно, всё в допуске.",
			"%s {выточил|выточила} резьбу, на которую главный технолог полчаса смотрел в лупу."]},
	{"cond": "stakhanov", "m": ["Стахановец", "Метеор"], "f": ["Стахановка", "Ракета"], "hire": false, "event": true,
		"why": ["За неделю %s {сделал|сделала} больше всех на заводе — мастер в шутку назвал так, и прилипло.",
			"%s {закончил|закончила} недельный план к четвергу и {пошёл|пошла} помогать соседу."]},
	{"cond": "builder", "m": ["Прораб", "Кирпич"], "f": ["Прорабша"], "hire": false, "event": true,
		"why": ["%s {выложил|выложила} стену ровнее, чем по отвесу. Начальник проверил уровнем и только присвистнул.",
			"Полцеха {построил|построила} %s — и всё по линеечке."]},
	{"cond": "welder", "m": ["Сварог", "Электрод"], "f": ["Искра"], "hire": false,
		"why": ["Шов у %s такой ровный, что заказчик сфотографировал его на память."]},
	{"cond": "heat", "m": ["Кочегар"], "f": ["Кочегарка"], "hire": false,
		"why": ["%s по цвету металла определяет температуру точнее пирометра."]},
	{"cond": "bonus", "m": ["Премиальный"], "f": ["Премиальная"], "hire": false, "event": true,
		"why": ["%s {получил|получила} уже третью премию. Бухгалтерия завела отдельную папку."]},
	{"cond": "oldtimer", "m": ["Старожил"], "f": ["Старожилка"], "hire": false,
		"why": ["%s работает на заводе дольше всех нынешних и помнит, где раньше стоял туалет."]},
]


## При приёме на работу: с шансом приходит со своим прозвищем «с прошлой работы».
static func on_hire(sim: Sim, w: Worker) -> void:
	if w.nick != "" or w.is_itr() or sim.rng.randf() > float(Defs.b("nick_hire_chance")):
		return
	var opts: Array = []
	for r: Dictionary in RULES:
		if bool(r.get("hire", false)) and _cond(sim, w, str(r["cond"])):
			opts.append(r)
	if opts.is_empty():
		return
	var rule: Dictionary = opts[sim.rng.randi_range(0, opts.size() - 1)]
	_give(sim, w, rule, false)


## Раз в день после смены: кто-то из коллектива может заработать прозвище за свои дела.
static func daily(sim: Sim) -> void:
	var last := int(sim.stats.get("nick_day", -99))
	if sim.day() - last < int(Defs.b("nick_cooldown_days")):
		return
	var cands: Array = []
	for w in sim.workers:
		if w.nick != "" or w.days_worked < 2:
			continue
		for r: Dictionary in RULES:
			if _cond(sim, w, str(r["cond"])):
				# событийные прозвища (пожар, травма, рекорд) — в приоритете
				cands.append([w, r, 3.0 if bool(r.get("event", false)) else 1.0])
	if cands.is_empty():
		return
	var total := 0.0
	for c: Array in cands:
		total += float(c[2])
	if sim.rng.randf() > float(Defs.b("nick_daily_chance")) * minf(2.0, 0.6 + total * 0.15):
		return
	var pick := sim.rng.randf() * total
	for c2: Array in cands:
		pick -= float(c2[2])
		if pick <= 0.0:
			_give(sim, c2[0], c2[1], true)
			sim.stats["nick_day"] = sim.day()
			return


static func _give(sim: Sim, w: Worker, rule: Dictionary, on_factory: bool) -> void:
	var pool: Array = rule["f"] if w.female else rule["m"]
	var nick := L.t(str(pool[sim.rng.randi_range(0, pool.size() - 1)]))   # 1.39: в английском — английское прозвище
	# не дублируем прозвища в одном коллективе
	for o in sim.workers:
		if o != w and o.nick == nick:
			return
	var whys: Array = rule["why"]
	var why := gendered(L.t(str(whys[sim.rng.randi_range(0, whys.size() - 1)])), w.female)
	why = why.replace("%s", L.name(w.first))
	w.nick = nick
	w.nick_why = why
	if not on_factory:
		w.add_history(sim.day(), L.t("Ещё на прошлой работе прозвали «%s». %s") % [nick, why])
		return
	w.add_history(sim.day(), gendered(L.t("{Получил|Получила} прозвище «%s». %s"), w.female) % [nick, why])
	Mood.add(sim, w, "nickname")
	sim.story.info(L.t("Новое прозвище: «%s»") % nick, L.t("%s %s теперь на заводе — «%s». %s") % [L.name(w.first), L.name(w.last), nick, why], "staff", Sim.LVL_INFO, w.cell() if w.present else Vector2i(-1, -1))
	sim.paper.add(L.t("Люди завода"), L.t("Почему %s %s теперь «%s»") % [L.name(w.first), L.name(w.last), nick], why)


## «{пришёл|пришла}» → нужная форма по полу.
static func gendered(text: String, female: bool) -> String:
	var re := RegEx.new()
	re.compile("\\{([^{}|]*)\\|([^{}|]*)\\}")
	var out := text
	for m in re.search_all(text):
		out = out.replace(m.get_string(0), m.get_string(2) if female else m.get_string(1))
	return out


static func _main_skill_high(w: Worker) -> bool:
	return w.skill(w.main_skill()) >= 9 and not w.is_itr() and w.prof not in ["laborer", "builder", "qc"]


static func _cond(sim: Sim, w: Worker, c: String) -> bool:
	var body := str(w.look.get("body", "normal"))
	var t: Dictionary = w.tally
	match c:
		"old":
			return w.age >= 56 and (w.traits.has("veteran") or w.skill(w.main_skill()) >= 6)
		"young":
			return w.age <= 22
		"thin":
			return body == "thin" or body == "vthin"
		"fat":
			return body == "fat" or body == "vfat"
		"stout":
			return (body == "stout" and not w.female) or body == "strong"
		"glasses":
			return bool(w.look.get("glasses", false)) and w.prof in ["qc", "technologist"]
		"phones":
			return bool(w.look.get("phones", false))
		"smoker":
			return w.traits.has("smoker") and int(t.get("smoke", 0)) >= 12
		"night":
			return w.traits.has("night_owl") and w.shift == 1 and w.days_worked >= 4
		"neat":
			return w.traits.has("neat") and w.days_worked >= 5
		"fire":
			return int(t.get("fire", 0)) >= 1
		"injured":
			return int(t.get("injury", 0)) >= 1 and w.sick_until < sim.minute
		"reset":
			return int(t.get("reset", 0)) >= 3
		"golden":
			return _main_skill_high(w)
		"stakhanov":
			if w.days_worked < 6 or w.parts_made < 60:
				return false
			for o in sim.workers:
				if o != w and o.parts_made > w.parts_made:
					return false
			return true
		"builder":
			return int(t.get("build", 0)) >= 60
		"welder":
			return w.prof == "welder" and w.days_worked >= 6
		"heat":
			return w.prof == "heat_treater" and w.days_worked >= 6
		"bonus":
			return int(t.get("bonus", 0)) >= 3
		"oldtimer":
			return w.days_worked >= 80
	return false


## Счётчик поступков (пожар, травма, автомат, перекур, стройка, премия).
static func count(w: Worker, key: String, n: int = 1) -> void:
	w.tally[key] = int(w.tally.get(key, 0)) + n
