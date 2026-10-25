class_name Company
extends RefCounted
## 1.17: завод игрока — название и эмблема. Хранится в sim.company: {"name": "...", "emblem": {...}}.
## Эмблема собирается из формы, знака, цветов и (по желанию) букв. Рисует её Emblem (scripts/view/emblem.gd).

const SHAPES := [["circle", "Круг"], ["shield", "Щит"], ["gear", "Шестерня"], ["hex", "Шестигранник"], ["diamond", "Ромб"], ["square", "Квадрат"]]
const SYMBOLS := [["gear", "Шестерня"], ["hammer", "Молот"], ["wrench", "Ключ"], ["gear_hammer", "Молот и шестерня"], ["bolt", "Молния"],
	["anvil", "Наковальня"], ["star", "Звезда"], ["wheat", "Колос"], ["wheel", "Колесо"], ["drop", "Капля"], ["truss", "Ферма"], ["letters", "Буквы"]]
const BG := ["#1f3a5f", "#7a1f1f", "#2f5d3a", "#2b2f33", "#3b6fb0", "#b5502b", "#5a4a8a", "#c8a13a", "#e9e4d6", "#9aa3a8"]
const FG := ["#f2efe6", "#e2b73a", "#1d2329", "#c94a3a", "#9fc5e8", "#6fbf86", "#c9ced2", "#f08a3c"]
const NAMES := ["Прогресс", "Восход", "Сталевар", "Импульс", "Вектор", "Заря", "Стрела", "Гранит", "Рубин", "Сокол",
	"Горизонт", "Темп", "Луч", "Искра", "Рассвет", "Опора", "Резец", "Механик", "Точмаш", "Прибой",
	"Стальной узел", "Красный токарь", "Северный вал", "Уральская шестерня", "Кедр", "Сигнал", "Мастер", "Ось",
	"Полюс", "Станкодеталь", "Орбита", "Буревестник", "Гвоздика", "Кристалл", "Красный станочник"]
const MAX_NAME := 24
## Знак по профилю завода — для случайной эмблемы.
const PROFILE_SYMBOL := {"mech": ["gear", "wrench", "gear_hammer"], "agri": ["wheat", "gear"], "steel": ["truss", "hammer", "anvil"],
	"pumps": ["drop", "gear"], "rail": ["wheel", "star"], "tools": ["gear_hammer", "wrench"]}


## Эмблема по умолчанию (старые сохранения): синий круг с шестерней.
static func default_emblem() -> Dictionary:
	return {"shape": "circle", "symbol": "gear", "bg": BG[0], "fg": FG[1], "rim": FG[0], "text": ""}


static func default_data() -> Dictionary:
	return {"name": "Прогресс", "emblem": default_emblem()}


static func random_name(rng: RandomNumberGenerator) -> String:
	return L.t(str(NAMES[rng.randi_range(0, NAMES.size() - 1)]))   # 1.39: в английском — латиницей (Voskhod, Zarya…)


static func random_emblem(rng: RandomNumberGenerator, profile: String = "") -> Dictionary:
	var syms: Array = PROFILE_SYMBOL.get(profile, [])
	var sym: String = str(syms[rng.randi_range(0, syms.size() - 1)]) if not syms.is_empty() and rng.randf() < 0.7 else str(SYMBOLS[rng.randi_range(0, SYMBOLS.size() - 2)][0])
	var bg: String = BG[rng.randi_range(0, BG.size() - 1)]
	var fg: String = FG[rng.randi_range(0, FG.size() - 1)]
	var guard := 0
	while _too_close(bg, fg) and guard < 20:
		fg = FG[rng.randi_range(0, FG.size() - 1)]
		guard += 1
	var rim: String = FG[rng.randi_range(0, FG.size() - 1)]
	return {"shape": str(SHAPES[rng.randi_range(0, SHAPES.size() - 1)][0]), "symbol": sym, "bg": bg, "fg": fg, "rim": rim, "text": ""}


## Цвета знака и фона сливаются — знак не будет видно.
static func _too_close(a: String, b: String) -> bool:
	var ca := Color(a)
	var cb := Color(b)
	return absf(ca.get_luminance() - cb.get_luminance()) < 0.22


## Буквы для эмблемы из названия: «Красный токарь» → «КТ», «Прогресс» → «П».
static func initials(name: String) -> String:
	var out := ""
	for part in name.replace("-", " ").split(" ", false):
		out += part.left(1).to_upper()
		if out.length() >= 3:
			break
	return out


## Название без лишних пробелов и кавычек, не длиннее MAX_NAME.
static func clean_name(s: String) -> String:
	var t := s.strip_edges().replace("«", "").replace("»", "").replace("\"", "")
	while t.contains("  "):
		t = t.replace("  ", " ")
	return t.left(MAX_NAME)


static func name_of(sim: Sim) -> String:
	var n := str(sim.company.get("name", ""))
	if n == "":
		n = "Прогресс"
	# 1.39: в английском — перевод из списка названий (Voskhod…) или латиницей (своё название игрока)
	return L.translit(L.t(n)) if L.is_en() else n


static func emblem_of(sim: Sim) -> Dictionary:
	var e: Variant = sim.company.get("emblem", {})
	return e if e is Dictionary and not (e as Dictionary).is_empty() else default_emblem()


## Полное название: до регистрации ООО — «Мастерская «…»», потом ООО «…».
static func title(sim: Sim) -> String:
	return L.t("ООО «%s»" if sim.progress.ooo else "Мастерская «%s»") % name_of(sim)


## 1.39: название из старых данных (метка сохранения) — на текущем языке: «ООО «Прогресс»» → «Progress LLC».
static func retitle(t: String) -> String:
	if not L.is_en():
		return t
	for f: String in ["ООО «%s»", "Мастерская «%s»"]:
		var pre := f.get_slice("%s", 0)
		if t.begins_with(pre) and t.ends_with("»"):
			var nm := t.substr(pre.length(), t.length() - pre.length() - 1)
			return L.t(f) % L.translit(L.t(nm))
	return t


## 1.39: название чужой фирмы (конкурент, заказчик, поставщик) для показа: в русском — как есть,
## в английском — «ООО «Техмаш-Регион»» → «Tekhmash-Region LLC», «ИП Гарипов» → «IE Garipov». Хранится по-русски.
static func firm(t: String) -> String:
	if not L.is_en() or t == "":
		return t
	var tail := ""
	var core := t
	var m := RegEx.create_from_string("^(.*) \\(([^()]+)\\)$").search(t)
	if m != null:
		core = m.get_string(1)
		tail = " (%s)" % L.translit(L.t(m.get_string(2)))
	var m2 := RegEx.create_from_string("^(\\S+) «(.+)»$").search(core)
	if m2 != null:
		var nm := L.t(m2.get_string(2))
		nm = L.translit(nm)
		var f := L.t(m2.get_string(1) + " «%s»")
		return (f if not L.has_cyr(f) else L.translit(m2.get_string(1)) + " %s") % nm + tail
	if core.begins_with("ИП "):
		return L.t("ИП %s") % L.translit(core.substr(3)) + tail
	return L.translit(L.t(core)) + tail


## Короткое: «Прогресс» в кавычках.
static func quoted(sim: Sim) -> String:
	return "«%s»" % name_of(sim)


static func set_data(sim: Sim, name: String, emblem: Dictionary) -> void:
	var n := clean_name(name)
	var uid := str(sim.company.get("uid", ""))
	sim.company = {"name": n if n != "" else name_of(sim), "emblem": emblem.duplicate()}
	if uid != "":
		sim.company["uid"] = uid
	sim.company_rev += 1


## 1.20: свой номер у каждого завода — у каждого своё автосохранение. Не трогает sim.rng.
static func uid_of(sim: Sim) -> String:
	var u := str(sim.company.get("uid", ""))
	if u == "":
		u = "%d%04d" % [int(Time.get_unix_time_from_system()), randi() % 10000]
		sim.company["uid"] = u
	return u
