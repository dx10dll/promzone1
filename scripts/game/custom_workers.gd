class_name CustomWorkers
extends RefCounted
## 1.32: «Создать рабочего» (свои рабочие) — список людей, собранных игроком в главном меню. Хранится отдельно от
## сохранений (user://custom_workers.json) и в начале каждой новой игры уходит в симуляцию
## (Scenario.new_game, opts.customs) — дальше игра от файла не зависит.

const VERSION := 1
const MAX := CustomPeople.MAX
const NAME_MIN := 2
const NAME_MAX := 24
const DEFAULT_CHANCE := 0.25
const AGE_MIN := 18
const AGE_MAX := 65

static var path := "user://custom_workers.json"   ## тесты подменяют на свой файл


## {"chance": 0–1, "workers": [запись, ...]}. Нет файла или он испорчен — пустой список.
static func load_data() -> Dictionary:
	var out := {"chance": DEFAULT_CHANCE, "workers": []}
	if not FileAccess.file_exists(path):
		return out
	var js := JSON.new()
	if js.parse(FileAccess.get_file_as_string(path)) != OK:
		return out   # испорчен — пустой список (файл не трогаем, пока игрок не сохранит)
	var d: Variant = js.data
	if not d is Dictionary:
		return out
	out["chance"] = clampf(float((d as Dictionary).get("chance", DEFAULT_CHANCE)), 0.0, 1.0)
	var ws: Variant = (d as Dictionary).get("workers", [])
	if ws is Array:
		for e: Variant in ws:
			if e is Dictionary and (out["workers"] as Array).size() < MAX:
				(out["workers"] as Array).append(normalize(e))
	return out


static func save_data(d: Dictionary) -> bool:
	var ws: Array = (d.get("workers", []) as Array).slice(0, MAX)
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"version": VERSION, "chance": clampf(float(d.get("chance", DEFAULT_CHANCE)), 0.0, 1.0), "workers": ws}, "\t"))
	f.close()
	return true


## Что положить в opts новой игры: включённые записи и шанс.
static func game_opts() -> Dictionary:
	var d := load_data()
	var on: Array = (d["workers"] as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("enabled", true)) and validate(e).is_empty())
	if on.is_empty():
		return {}
	return {"customs": on, "custom_chance": float(d["chance"])}


## Числа из JSON приходят дробными — приводим запись к нужным типам.
static func normalize(e: Dictionary) -> Dictionary:
	var o := e.duplicate(true)
	o["id"] = str(o.get("id", ""))
	if str(o["id"]) == "":
		o["id"] = new_id()
	for k in ["last", "first", "patr", "prof"]:
		o[k] = str(o.get(k, ""))
	o["female"] = bool(o.get("female", false))
	o["enabled"] = bool(o.get("enabled", true))
	o["age"] = clampi(int(o.get("age", 30)), AGE_MIN, AGE_MAX)
	var tr: Array = []
	for t: Variant in (o.get("traits", []) as Array if o.get("traits", []) is Array else []):
		tr.append(str(t))
	o["traits"] = tr
	var lk: Dictionary = o.get("look", {}) if o.get("look", {}) is Dictionary else {}
	if lk.has("skin"):
		lk["skin"] = int(lk["skin"])
	if lk.has("h"):
		lk["h"] = float(lk["h"])
	o["look"] = lk
	return o


static func new_id() -> String:
	return "cw%d_%05d" % [int(Time.get_unix_time_from_system()), randi() % 100000]


# ---------------------------------------------------------------- имя

## Проверка части ФИО: "" — всё хорошо, иначе — что не так. Отчество можно не писать.
static func check_part(s: String, required: bool = true) -> String:
	var t := s.strip_edges()
	if t == "":
		return "нужно заполнить" if required else ""
	var re := RegEx.new()
	re.compile("^[А-Яа-яЁё]+(-[А-Яа-яЁё]+)*$")
	if re.search(t) == null:
		if t.contains(" "):
			return "без пробелов (двойное — через дефис)"
		if t.begins_with("-") or t.ends_with("-") or t.contains("--"):
			return "дефис — только между частями"
		return "только русские буквы и дефис"
	var letters := t.replace("-", "").length()
	if letters < NAME_MIN:
		return "слишком коротко"
	if t.length() > NAME_MAX:
		return L.t("слишком длинно (до %d букв)") % NAME_MAX
	return ""


## Ошибки всей записи: {поле: текст}. Пустой словарь — запись правильная.
static func validate(e: Dictionary) -> Dictionary:
	var err := {}
	for k: String in ["last", "first", "patr"]:
		var m := check_part(str(e.get(k, "")), k != "patr")
		if m != "":
			err[k] = m
	return err


## «иВАНОВ-петров » → «Иванов-Петров».
static func nice(s: String) -> String:
	var parts := s.strip_edges().to_lower().split("-")
	for i in parts.size():
		if parts[i] != "":
			parts[i] = parts[i].left(1).to_upper() + parts[i].substr(1)
	return "-".join(parts)


static func random_name(e: Dictionary, r: RandomNumberGenerator) -> void:
	var fem := bool(e.get("female", false))
	var firsts: Array = Defs.names.get("female" if fem else "male", ["Анна" if fem else "Иван"])
	var males: Array = Defs.names.get("male", ["Иван"])
	var sur := str(People.pick(r, Defs.names.get("surnames", ["Иванов"])))
	e["first"] = str(People.pick(r, firsts))
	e["last"] = People.female_surname(sur) if fem else sur
	e["patr"] = People.patronymic(str(People.pick(r, males)), fem)


## Пол поменяли — фамилия и отчество меняют окончание (Иванов → Иванова, Петрович → Петровна).
static func regender(e: Dictionary) -> void:
	var fem := bool(e.get("female", false))
	var last := str(e.get("last", ""))
	var patr := str(e.get("patr", ""))
	if fem:
		e["last"] = People.female_surname(last)
		if patr.ends_with("ович") or patr.ends_with("евич"):
			e["patr"] = patr.substr(0, patr.length() - 2) + "на"
		elif patr.ends_with("ич"):
			e["patr"] = patr.substr(0, patr.length() - 2) + "инична"
	else:
		if last.ends_with("ская"):
			e["last"] = last.substr(0, last.length() - 4) + "ский"
		else:
			for suf in ["ова", "ева", "ёва", "ина", "ына"]:
				if last.ends_with(suf):
					e["last"] = last.substr(0, last.length() - 1)
					break
		if patr.ends_with("овна") or patr.ends_with("евна"):
			e["patr"] = patr.substr(0, patr.length() - 2) + "ич"
		elif patr.ends_with("инична"):
			e["patr"] = patr.substr(0, patr.length() - 6) + "ич"
		elif patr.ends_with("ична"):
			e["patr"] = patr.substr(0, patr.length() - 4) + "ич"
	var lk: Dictionary = e.get("look", {})
	var hs: Array = People.HAIR_F if fem else People.HAIR_M
	if not hs.has(str(lk.get("hair", ""))):
		lk["hair"] = str(People.pick(RandomNumberGenerator.new(), hs))
	if fem:
		lk["beard"] = ""
	e["look"] = lk


# ---------------------------------------------------------------- внешность

## Профессии в выпадающем списке редактора — группами, как в окне найма.
const PROF_GROUPS := [["У станков", ["turner", "miller", "cnc_operator", "setter", "qc"]],
	["Рабочие", ["laborer", "builder", "electrician", "welder", "fitter", "assembler", "painter", "heat_treater", "caster", "presser", "cleaner"]],
	["Быт и охрана", ["guard", "cook", "nurse"]],
	["ИТР и офис", ["foreman", "chief", "technologist", "dispatcher", "accountant", "buyer", "hr", "sales_manager", "safety_engineer", "chief_engineer", "lawyer"]]]

const HAIR_NAMES := {"short": "Короткая", "crew": "Ёжик", "side": "На пробор", "slick": "Зачёс назад", "receding": "Залысины",
	"bald": "Лысый", "curly": "Кудри", "mullet": "Длинная сзади", "bob": "Каре", "bun": "Пучок", "ponytail": "Хвост",
	"long": "Длинные", "pixie": "Короткая", "curly_f": "Кудри", "braid": "Коса", "perm": "Химзавивка"}
const BEARDS := ["", "stubble", "mustache", "chevron", "goatee", "short", "full"]
const BEARD_NAMES := {"": "Нет", "stubble": "Щетина", "mustache": "Усы", "chevron": "Пышные усы", "goatee": "Эспаньолка", "short": "Короткая борода", "full": "Борода"}
const HAIR_COLS := ["#2a2420", "#4a3020", "#6b4428", "#9a6a3a", "#c9a45a", "#b5562e", "#7d7a74", "#9a9a94", "#c8c8c2"]
const HAIR_COL_NAMES := ["Чёрные", "Тёмно-каштановые", "Каштановые", "Русые", "Светлые", "Рыжие", "Тёмно-седые", "Седые", "Белые"]
const SKIN_NAMES := ["Очень светлая", "Светлая", "Смуглая", "Загорелая", "Тёмная", "Очень тёмная"]
const EYE_NAMES := ["Карие", "Тёмно-карие", "Серо-голубые", "Зелёные", "Ореховые", "Голубые", "Чёрные"]
const STREET_NAMES := ["Графит", "Коричневая", "Тёмно-синяя", "Хаки", "Бордовая", "Серая", "Бежевая", "Чёрная"]
const HEAD_NAMES := {"oval": "Овальное", "square": "Квадратное", "round": "Круглое", "long": "Вытянутое", "soft": "Мягкое"}
const EYE_KIND_NAMES := {"almond": "Миндалевидные", "narrow": "Узкие", "round": "Круглые", "heavy": "Тяжёлые веки", "deep": "Глубоко посажены"}
const BROW_NAMES := {"straight": "Прямые", "arched": "Дугой", "thick": "Густые", "thin": "Тонкие", "angled": "С изломом", "bushy": "Кустистые"}
const NOSE_NAMES := {"small": "Маленький", "straight": "Прямой", "long": "Длинный", "wide": "Широкий", "hooked": "С горбинкой"}
const MOUTH_NAMES := {"neutral": "Обычный", "smile": "Улыбчивый", "thin": "Тонкие губы", "full": "Полные губы", "down": "Уголки вниз"}
const BODY_ORDER := ["vthin", "thin", "normal", "stout", "strong", "fat", "vfat"]
const HEIGHTS := [0.94, 1.0, 1.06]
const HEIGHT_NAMES := ["Невысокий", "Средний", "Высокий"]


static func random_look(e: Dictionary, r: RandomNumberGenerator) -> void:
	var fem := bool(e.get("female", false))
	var age := int(e.get("age", 30))
	var lk := {}
	var sk := r.randi_range(0, 99)
	lk["skin"] = 0 if sk < 40 else (1 if sk < 80 else (2 if sk < 92 else (3 if sk < 97 else (4 if sk < 99 else 5))))
	lk["hair"] = str(People.pick(r, People.HAIR_F if fem else People.HAIR_M))
	lk["hair_col"] = str(People.pick(r, People.GRAY_HAIR if (age >= 50 and r.randf() < 0.6) else People.HAIR_COLORS))
	lk["beard"] = "" if fem or r.randf() < 0.45 else str(People.pick(r, BEARDS.slice(1)))
	lk["glasses"] = r.randf() < 0.25
	lk["body"] = People.random_body(r, age)
	lk["h"] = float(HEIGHTS[r.randi_range(0, 2)])
	lk["street"] = "coat" if (fem and r.randf() < 0.5) else "jacket"
	lk["street_col"] = str(People.pick(r, People.STREET_COLS))
	lk["eye_col"] = str(People.pick(r, People.EYE_COLS))
	lk["face_ovr"] = {
		"head": str(People.pick(r, ["soft", "oval", "round"] if fem else ["oval", "square", "round", "long"])),
		"eyes": str(People.pick(r, People.EYE_KINDS)),
		"brows": str(People.pick(r, ["thin", "arched", "straight"] if fem else People.BROW_KINDS)),
		"nose": str(People.pick(r, ["small", "straight", "wide"] if fem else People.NOSE_KINDS)),
		"mouth": str(People.pick(r, People.MOUTH_KINDS)),
		"freckles": int(lk["skin"]) <= 1 and r.randf() < 0.2,
		"earrings": fem and r.randf() < 0.5,
	}
	e["look"] = lk


## Новая запись: случайный пол, имя и внешность.
static func new_entry(r: RandomNumberGenerator) -> Dictionary:
	var e := {"id": new_id(), "enabled": true, "female": r.randf() < 0.3, "age": r.randi_range(22, 55), "prof": "", "traits": []}
	random_name(e, r)
	random_look(e, r)
	return e


## Подпись в списке: «Токарь · 34 года» (или «Любая профессия»).
static func subtitle(e: Dictionary) -> String:
	var pf := str(e.get("prof", ""))
	var age := int(e.get("age", 30))
	return "%s · %d %s" % [L.t(str(Worker.PROF_NAMES.get(pf, "Любая профессия"))), age, L.pl(age, "год|года|лет")]


static func fio(e: Dictionary) -> String:
	var parts := PackedStringArray()
	for k in ["last", "first", "patr"]:
		if str(e.get(k, "")).strip_edges() != "":
			parts.append(str(e[k]).strip_edges())
	return " ".join(parts) if not parts.is_empty() else "Без имени"
