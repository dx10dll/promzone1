class_name Worker
extends RefCounted
## Рабочий: личные данные, навыки, внешность, потребности и текущее состояние.
## Логика принятия решений — в brain.gd.

const PROF_NAMES := {
	"turner": "Токарь",
	"qc": "Контролёр ОТК",
	"laborer": "Разнорабочий",
	"builder": "Строитель",
	"electrician": "Электрик",
	"miller": "Фрезеровщик",
	"welder": "Сварщик",
	"heat_treater": "Термист",
	"caster": "Литейщик",
	"presser": "Штамповщик",
	"painter": "Маляр",
	"assembler": "Слесарь-сборщик",
	"fitter": "Слесарь",
	"foreman": "Мастер участка",
	"chief": "Начальник цеха",
	"accountant": "Бухгалтер",
	"buyer": "Снабженец",
	"dispatcher": "Диспетчер ПДО",
	"hr": "Кадровик",
	"technologist": "Технолог",
	"cleaner": "Уборщик",
	"setter": "Наладчик",
	"cnc_operator": "Оператор станков с ЧПУ",
	"guard": "Охранник",
	"cook": "Повар",
	"nurse": "Фельдшер",
	"sales_manager": "Менеджер по сбыту",
	"safety_engineer": "Инженер по ОТ",
	"chief_engineer": "Главный инженер",
	"lawyer": "Юрист",
}
## Инженерно-технические работники: сидят в кабинетах, на станках не работают.
const ITR := ["foreman", "chief", "accountant", "buyer", "dispatcher", "hr", "technologist",
	"sales_manager", "safety_engineer", "chief_engineer", "lawyer"]
## Отдел, в котором работает специалист.
const PROF_DEPT := {"foreman": "foreman", "chief": "chief", "accountant": "accounting", "buyer": "supply",
	"dispatcher": "pdo", "hr": "hr", "technologist": "tech",
	"sales_manager": "sales", "safety_engineer": "safety", "chief_engineer": "engineer", "lawyer": "legal"}
## Основной навык профессии.
const PROF_SKILL := {
	"turner": "turning", "qc": "qc", "laborer": "haul", "builder": "build", "electrician": "electric",
	"miller": "milling", "welder": "welding", "heat_treater": "heat", "caster": "casting", "presser": "stamping", "painter": "paint", "assembler": "assembly", "fitter": "fitting",
	"foreman": "manage", "chief": "manage", "accountant": "office", "buyer": "office", "dispatcher": "office",
	"hr": "office", "technologist": "engineering", "cleaner": "clean", "setter": "setup", "cnc_operator": "cnc", "guard": "security",
	"cook": "cook", "nurse": "medicine",
	"sales_manager": "office", "safety_engineer": "engineering", "chief_engineer": "engineering", "lawyer": "office",
}
const SKILL_NAMES := {
	"turning": "Токарное дело",
	"qc": "Контроль качества",
	"build": "Стройка",
	"haul": "Погрузка",
	"electric": "Электрика",
	"milling": "Фрезерное дело",
	"welding": "Сварка",
	"heat": "Термообработка",
	"casting": "Литьё",
	"stamping": "Штамповка",
	"paint": "Покраска",
	"assembly": "Сборка",
	"fitting": "Слесарное дело",
	"manage": "Руководство",
	"office": "Работа с документами",
	"engineering": "Инженерное дело",
	"clean": "Уборка",
	"setup": "Наладка станков",
	"cnc": "Работа на ЧПУ",
	"security": "Охрана",
	"cook": "Кулинария",
	"medicine": "Медицина",
}
const SHIFT_NAMES := ["1-я смена (8:00–17:00)", "2-я смена (17:00–02:00, +20%)"]

var id := 0
var first := ""
var last := ""
var patronymic := ""      ## больше не показывается (оставлено для старых сохранений)
var custom_id := ""        ## 1.32: свой рабочий из редактора главного меню (id записи), "" — обычный
var nick := ""             ## прозвище: «Батя», «Шпала», «Пожарный»
var nick_why := ""         ## за что прозвали
var tally: Dictionary = {} ## счётчики поступков для прозвищ: пожары, травмы, автоматы, перекуры
var female := false
var age := 30
var prof := "laborer"
var skills: Dictionary = {"turning": 0, "qc": 0, "build": 3, "haul": 4}
var wage := 2600            ## ставка за смену, ₽
var look: Dictionary = {}
var needs: Dictionary = {"food": 100.0, "bladder": 100.0, "rest": 100.0}
var present := false
var pos := Vector2.ZERO     ## в тайлах; центр клетки = клетка + 0.5
var vprev := Vector2(-1e9, 0.0)   ## 1.26: где был до последнего шага симуляции — экран рисует между ними
static var view_alpha := 1.0      ## 1.26: доля пути от vprev к pos (ставит игровая сцена каждый кадр)
var dir := "down"
var anim := "idle"
var path: Array[Vector2i] = []
var path_i := 0
var path_target := Vector2i(-999, -999)
var task: Task = null
var carrying := -1
var carry_extra: Array[int] = [] ## дополнительные единицы в пачке
var activity := "Дома"
var ate_today := false
var arrive_at := 470.0
var gone_today := false
var hidden := false
var fail_cool: Dictionary = {}
var history: Array = []
var hired_day := 1
var think_cd := 0.0
var stuck_time := 0.0
var work_phase := 0.0       ## для анимации работы
var days_worked := 0
var parts_made := 0
var exit_cell := Vector2i(0, 30)
var traits: Array = []           ## коды черт характера (data/traits.json)
var thoughts: Array = []         ## [{id, until, mood}]
var mood := 50.0                 ## кэш настроения 0–100
var shift := 0                   ## 0 — первая смена, 1 — вторая
var pending_shift := -1          ## перевод в другую смену после ухода домой
var dressed := false             ## в спецовке
var locker_id := -1              ## закреплённый шкафчик
var shift_anchor := -1.0         ## начало текущей/ближайшей смены (абсолютная минута)
var gone_anchor := -1.0          ## смена, с которой уже ушёл домой
var skip_shift := false          ## прогуливает эту смену
var desk_id := -1                ## закреплённый стол ИТР
var arrive_off := -20.0          ## приходит за столько минут до начала смены
var last_smoke := 0.0
var low_mood_days := 0
var week_score := 0              ## вклад за неделю (для доски почёта)
var visitor := false             ## посетитель (инспектор, гость), а не сотрудник
var prop := ""                   ## что держит в руке: папка, лопата, плакат, огнетушитель
var bubble := ""                 ## значок над головой от задачи или события
var sick_until := -1.0           ## на больничном или в отпуске до этой минуты
var away_why := ""               ## «на больничном» / «в отпуске» / «на курсах»
var mentor := -1                 ## id наставника (этот человек — ученик)
var rel: Dictionary = {}         ## отношения: id другого (строкой) -> -100…100
var practice_until := -1         ## практикант из ПТУ: до какого дня практика (-1 — в штате)
var ppe := 100.0                 ## износ выданных СИЗ: 100 — новый комплект, 0 — нет СИЗ
var workplace := -1              ## id станка, на котором работает (для СОУТ)
var muffs := false               ## в противошумных наушниках (не сохраняется, пересчитывается)
var brigade := -1                ## id бригады (-1 — вне бригад)
var kids := 0                    ## дети дошкольного возраста (для заводского детсада)
var from_away := false           ## иногородний: живёт в заводском общежитии
var grade_n := 0                 ## 1.15: сданный разряд (0 — ещё не закреплён, считать по навыку)
var exam_cd := -1                ## 1.15: день, раньше которого не пересдаёт
var order: Dictionary = {}       ## 1.15: приказ игрока {cx, cy, thing, bp, until}; выполнил — сам вернётся к обычной работе
var controlled := false          ## 1.19: «под управлением» игрока — сам работу не ищет, ждёт команд


## «В. Громов» — коротко, для подписей (1.14).
func short_name() -> String:
	return "%s. %s" % [first.left(1), last] if first != "" else last


func full_name() -> String:
	return first + " " + last


## Имя с прозвищем для карточек и списков: «Виктор „Батя“ Громов». Отчества не используем.
func formal_name() -> String:
	if nick == "":
		return full_name()
	return "%s «%s» %s" % [first, nick, last]


## Как зовут в цеху: прозвище, если есть, иначе по имени.
func call_name() -> String:
	return nick if nick != "" else first


func carry_count() -> int:
	return (1 if carrying >= 0 else 0) + carry_extra.size()


func cell() -> Vector2i:
	return Vector2i(floori(pos.x), floori(pos.y))


func prof_name() -> String:
	if visitor:
		return activity
	if female and prof == "turner":
		return "Токарь"
	if female and prof == "cleaner":
		return "Уборщица"
	return str(PROF_NAMES.get(prof, prof))


## Название с маленькой буквы, но аббревиатуры остаются («инженер по ОТ»).
static func lc(t: String) -> String:
	return t.left(1).to_lower() + t.substr(1) if t != "" else t


func prof_lc() -> String:
	return lc(prof_name())



## 1.24: на смене, но без дела (нет задачи или бродит).
func idle_now() -> bool:
	return present and (task == null or task.kind == "wander")


## 1.24: строка для поиска в окне «Люди»: имя, профессия, разряд, занятие, черты.
func search_key() -> String:
	var parts: Array[String] = [formal_name(), prof_name(), rank_text(), activity]
	for t in traits:
		parts.append(str(Defs.traits.get(t, {}).get("name", t)))
	return " ".join(parts).to_lower()


func is_itr() -> bool:
	return ITR.has(prof)


func dept() -> String:
	return str(PROF_DEPT.get(prof, ""))


func main_skill() -> String:
	return str(PROF_SKILL.get(prof, "haul"))


func skill(s: String) -> int:
	return int(skills.get(s, 0))


## 1.15: разряд есть только у квалифицированных рабочих, у ИТР — категория, у руководителей — должность.
const NO_GRADE := ["laborer", "cleaner", "guard"]
const MANAGERS := ["foreman", "chief", "chief_engineer"]
const CAT_ROMAN := ["", "II", "I", ""]


## Разряд, на который тянут руки (по основному навыку).
func pot_grade() -> int:
	return clampi(1 + int(skill(main_skill()) / 2), 1, 6)


## Разряд 1–6. У рабочих — сданный на экзамене; у остальных — уровень для расчётов (ставка, вес).
func grade() -> int:
	if grade_n > 0 and has_grade():
		return grade_n
	return pot_grade()


## "grade" — разряд, "category" — категория ИТР (у фельдшера — медицинская), "position" — только должность,
## "none" — простая работа без разрядов.
func rank_kind() -> String:
	if MANAGERS.has(prof):
		return "position"
	if is_itr() or prof == "nurse":
		return "category"
	if NO_GRADE.has(prof):
		return "none"
	return "grade"


func has_grade() -> bool:
	return rank_kind() == "grade"


## Категория ИТР: 0 — без категории, 1 — II, 2 — I, 3 — ведущий (у фельдшера — вторая, первая, высшая).
func category() -> int:
	var s := skill(main_skill())
	if s >= 8:
		return 3
	if s >= 6:
		return 2
	if s >= 4:
		return 1
	return 0


## «4-й разряд», «I категория», «ведущий», «высшая категория» или пусто.
func rank_text() -> String:
	match rank_kind():
		"grade":
			return "%d-й разряд" % grade()
		"category":
			var c := category()
			if prof == "nurse":
				return ["", "вторая категория", "первая категория", "высшая категория"][c]
			if c == 3:
				return "ведущий"
			return ("%s категория" % CAT_ROMAN[c]) if c > 0 else ""
	return ""


## Полное звание: «Токарь 4-го разряда», «Технолог I категории», «Ведущий технолог», «Мастер участка».
func title() -> String:
	var pn := prof_name()
	match rank_kind():
		"grade":
			return "%s %d-го разряда" % [pn, grade()]
		"category":
			var c := category()
			if prof == "nurse":
				return pn + ["", " второй категории", " первой категории", " высшей категории"][c]
			if c == 3:
				return "Ведущий " + lc(pn)
			return pn + ((" %s категории" % CAT_ROMAN[c]) if c > 0 else "")
	return pn


func title_lc() -> String:
	return lc(title())


## «токарь, 4-й разряд» — профессия и разряд через запятую (без разряда — только профессия).
func prof_rank() -> String:
	var r := rank_text()
	return prof_name() + (", " + r if r != "" else "")


func trait_names() -> Array[String]:
	var out: Array[String] = []
	for t in traits:
		out.append(str(Defs.traits.get(t, {}).get("name", t)))
	return out


func add_history(day: int, text: String) -> void:
	history.push_front("День %d: %s" % [day, text])
	if history.size() > 30:
		history.resize(30)


func to_dict() -> Dictionary:
	return {
		"id": id, "first": first, "last": last, "patr": patronymic, "female": female,
		"age": age, "prof": prof, "skills": skills, "wage": wage, "look": look,
		"needs": needs, "present": present, "px": pos.x, "py": pos.y, "dir": dir,
		"ate": ate_today, "arrive": arrive_at, "gone": gone_today, "history": history,
		"hired": hired_day, "days": days_worked, "made": parts_made,
		"exit_x": exit_cell.x, "exit_y": exit_cell.y,
		"traits": traits, "thoughts": thoughts, "mood": mood, "shift": shift, "pshift": pending_shift,
		"dressed": dressed, "locker": locker_id, "anchor": shift_anchor, "gone_a": gone_anchor,
		"skip": skip_shift, "arr_off": arrive_off, "smoke": last_smoke, "lowd": low_mood_days, "week": week_score, "desk": desk_id,
		"sick": sick_until, "away": away_why, "nick": nick, "nick_why": nick_why, "tally": tally,
		"mentor": mentor, "rel": rel, "practice": practice_until, "ppe": ppe, "wp": workplace, "brig": brigade,
		"kids": kids, "faraway": from_away, "grade": grade_n, "exam_cd": exam_cd, "ord": order, "ctl": controlled,
		"cust": custom_id,
	}


static func from_dict(d: Dictionary) -> Worker:
	var w := Worker.new()
	w.id = int(d["id"])
	w.first = str(d["first"])
	w.last = str(d["last"])
	w.patronymic = str(d.get("patr", ""))
	w.custom_id = str(d.get("cust", ""))
	w.female = bool(d["female"])
	w.age = int(d["age"])
	w.prof = str(d["prof"])
	w.skills = d["skills"]
	for k in w.skills.keys():
		w.skills[k] = int(w.skills[k])
	w.wage = int(d["wage"])
	w.look = d["look"]
	if not w.look.has("fem"):
		w.look["fem"] = bool(d["female"])
	if not w.look.has("fs"):
		w.look["fs"] = absi((w.first + w.last).hash() + w.age * 131)   # 1.15: зерно черт лица
	w.needs = d["needs"]
	w.present = bool(d["present"])
	w.pos = Vector2(float(d["px"]), float(d["py"]))
	w.dir = str(d.get("dir", "down"))
	w.ate_today = bool(d.get("ate", false))
	w.arrive_at = float(d.get("arrive", 470.0))
	w.gone_today = bool(d.get("gone", false))
	w.history = d.get("history", [])
	w.hired_day = int(d.get("hired", 1))
	w.days_worked = int(d.get("days", 0))
	w.parts_made = int(d.get("made", 0))
	w.exit_cell = Vector2i(int(d.get("exit_x", 0)), int(d.get("exit_y", 30)))
	w.traits = d.get("traits", [])
	w.thoughts = d.get("thoughts", [])
	w.mood = float(d.get("mood", 50.0))
	w.shift = int(d.get("shift", 0))
	w.pending_shift = int(d.get("pshift", -1))
	w.dressed = bool(d.get("dressed", w.present))
	w.locker_id = int(d.get("locker", -1))
	w.shift_anchor = float(d.get("anchor", -1.0))
	w.gone_anchor = float(d.get("gone_a", -1.0))
	w.skip_shift = bool(d.get("skip", false))
	w.arrive_off = float(d.get("arr_off", -20.0))
	w.last_smoke = float(d.get("smoke", 0.0))
	w.low_mood_days = int(d.get("lowd", 0))
	w.week_score = int(d.get("week", 0))
	w.desk_id = int(d.get("desk", -1))
	w.sick_until = float(d.get("sick", -1.0))
	w.away_why = str(d.get("away", ""))
	w.nick = str(d.get("nick", ""))
	w.nick_why = str(d.get("nick_why", ""))
	w.tally = d.get("tally", {})
	w.mentor = int(d.get("mentor", -1))
	w.rel = d.get("rel", {})
	w.practice_until = int(d.get("practice", -1))
	w.ppe = float(d.get("ppe", 100.0))
	w.kids = int(d.get("kids", 0))
	w.from_away = bool(d.get("faraway", false))
	w.workplace = int(d.get("wp", -1))
	w.brigade = int(d.get("brig", -1))
	w.grade_n = int(d.get("grade", 0))
	if w.grade_n <= 0 and w.has_grade():
		w.grade_n = w.pot_grade()   # старые сохранения: разряд по навыку
	w.exam_cd = int(d.get("exam_cd", -1))
	w.order = d.get("ord", {})
	w.controlled = bool(d.get("ctl", false))
	w.activity = "На месте" if w.present else "Дома"
	return w


## 1.26: где рисовать человека: симуляция идёт крупными шагами, экран — плавно между ними.
func vpos() -> Vector2:
	if vprev.x < -1e8 or vprev.distance_squared_to(pos) > 4.0:
		return pos
	return vprev.lerp(pos, view_alpha)
