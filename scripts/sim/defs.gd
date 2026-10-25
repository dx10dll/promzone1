class_name Defs
extends RefCounted
## Справочные данные игры: объекты, конструкции, изделия, материалы, баланс.
## Загружаются из JSON-файлов в папке data/, чтобы баланс можно было править без кода.

static var objects: Dictionary = {}
static var floors: Dictionary = {}
static var walls: Dictionary = {}
static var products: Dictionary = {}
static var materials: Dictionary = {}
static var balance: Dictionary = {}
static var names: Dictionary = {}
static var rooms: Dictionary = {}
static var traits: Dictionary = {}
static var thoughts: Dictionary = {}
static var processes: Dictionary = {}
static var consumables: Dictionary = {}
static var sprites: Dictionary = {}
static var departments: Dictionary = {}
static var suppliers: Dictionary = {}
static var research: Dictionary = {}
static var seasons: Dictionary = {}
static var inspections: Dictionary = {}
static var events: Dictionary = {}
static var paper: Dictionary = {}
static var profiles: Dictionary = {}
static var scenarios: Dictionary = {}
static var grants: Array = []
static var stages: Dictionary = {}
static var develop: Dictionary = {}
static var build_mats: Dictionary = {}   ## 1.13: стройматериалы
static var templates: Dictionary = {}    ## 1.17: готовые помещения
static var floor_by_id: Dictionary = {}
static var wall_by_id: Dictionary = {}
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	objects = _load_dict("res://data/objects.json")
	var st: Dictionary = _load_dict("res://data/structures.json")
	floors = st.get("floors", {})
	walls = st.get("walls", {})
	products = _load_dict("res://data/products.json")
	materials = _load_dict("res://data/materials.json")
	balance = _load_dict("res://data/balance.json")
	names = _load_dict("res://data/names.json")
	rooms = _load_dict("res://data/rooms.json")
	traits = _load_dict("res://data/traits.json")
	thoughts = _load_dict("res://data/thoughts.json")
	processes = _load_dict("res://data/processes.json")
	consumables = _load_dict("res://data/consumables.json")
	sprites = _load_dict("res://data/sprite_meta.json")
	departments = _load_dict("res://data/departments.json")
	suppliers = _load_dict("res://data/suppliers.json")
	research = _load_dict("res://data/research.json")
	templates = _load_dict("res://data/templates.json")
	seasons = _load_dict("res://data/seasons.json")
	inspections = _load_dict("res://data/inspections.json")
	events = _load_dict("res://data/events.json")
	paper = _load_dict("res://data/paper.json")
	profiles = _load_dict("res://data/profiles.json")
	scenarios = _load_dict("res://data/scenarios.json")
	grants = _load_dict("res://data/grants.json").get("list", [])
	stages = _load_dict("res://data/stages.json")
	develop = _load_dict("res://data/develop.json")
	build_mats = _load_dict("res://data/build_mats.json").get("list", {})
	for k in floors.keys():
		floors[k]["key"] = k
		floor_by_id[int(floors[k]["id"])] = floors[k]
	for k in walls.keys():
		walls[k]["key"] = k
		wall_by_id[int(walls[k]["id"])] = walls[k]
	for k in objects.keys():
		objects[k]["key"] = k
	for k in products.keys():
		products[k]["key"] = k
	for k in materials.keys():
		materials[k]["key"] = k
	_loaded = true


static func _load_dict(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Нет файла данных: " + path)
		return {}
	var txt := FileAccess.get_file_as_string(path)
	var data: Variant = JSON.parse_string(txt)
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Ошибка разбора JSON: " + path)
		return {}
	return data


## Маршрут изделия: список операций {op, time, skill, cons?}.
static func route(p: String) -> Array:
	var d: Dictionary = products.get(p, {})
	if d.has("route"):
		return d["route"]
	return [{"op": "turning", "time": float(d.get("time", 30)), "skill": int(d.get("min_skill", 1))}]


static func op(p: String, step: int) -> Dictionary:
	var r := route(p)
	if step < 0 or step >= r.size():
		return {}
	return r[step]


static func process_name(pr: String) -> String:
	if pr == "qc":
		return L.t("ОТК")
	return L.dt("process.%s.name" % pr, str(processes.get(pr, {}).get("name", pr)))   # 1.39: на языке игры


static func route_text(p: String) -> String:
	var names: Array[String] = []
	for o: Dictionary in route(p):
		names.append(process_name(str(o["op"])))
	return " → ".join(names)


## 1.16: размер деталей. Изделие — «size», станок — machine.part_size (берёт детали до своего размера).
const SIZES := ["s", "m", "l"]
const SIZE_PL := ["мелкие", "средние", "крупные"]
const SIZE_ONE := ["мелкая", "средняя", "крупная"]
const SIZE_GEN := ["мелких", "средних", "крупных"]


static func size_rank(code: String) -> int:
	var i := SIZES.find(code)
	return i if i >= 0 else 1


## Размер изделия: 0 — мелкое, 1 — среднее, 2 — крупное.
static func product_rank(p: String) -> int:
	return size_rank(str(products.get(p, {}).get("size", "m")))


## До какого размера деталей берёт станок (по описанию объекта). Без пометки — любые.
static func machine_rank(def_id: String) -> int:
	var md: Dictionary = objects.get(def_id, {}).get("machine", {})
	return size_rank(str(md.get("part_size", "l")))


## «мелкие и средние детали» — подпись для станка.
static func machine_parts_text(def_id: String) -> String:
	var r := machine_rank(def_id)
	match r:
		0:
			return L.t("только мелкие детали")
		1:
			return L.t("мелкие и средние детали")
	return L.t("детали любого размера")


## Короткий паспорт станка: «детали: мелкие и средние · быстрее на 18% · брака −50%».
static func machine_spec(def_id: String) -> String:
	var md: Dictionary = objects.get(def_id, {}).get("machine", {})
	if md.is_empty():
		return ""
	var parts: Array[String] = [L.t("детали: ") + [L.t("только мелкие"), L.t("мелкие и средние"), L.t("любого размера")][machine_rank(def_id)]]
	var sp := float(md.get("speed_k", 1.0))
	if absf(sp - 1.0) > 0.01:
		var pct := int(round((1.0 / sp - 1.0) * 100.0))
		if 1.0 / sp >= 1.5:
			var fs := L.t("быстрее в %.1f раза") % (1.0 / sp)
			parts.append(fs if L.is_en() else fs.replace(".", ","))
		else:
			parts.append((L.t("быстрее на %d%%") % pct) if pct > 0 else (L.t("медленнее на %d%%") % -pct))
	var dk := float(md.get("defect_k", 1.0))
	if absf(dk - 1.0) > 0.01:
		parts.append(L.t("брака %s%d%%") % ["−" if dk < 1.0 else "+", int(round(absf(dk - 1.0) * 100.0))])
	if bool(md.get("batch", false)):
		parts.append(L.t("партия до %d") % int(md.get("in_cap", 6)))
	if md.has("cons_k"):
		parts.append(L.t("расход −%d%%") % int(round((1.0 - float(md["cons_k"])) * 100.0)))
	if int(md.get("min_skill", 1)) > 1:
		parts.append(L.t("разряд от %d") % int(md["min_skill"]))
	var txt := " · ".join(parts)
	return txt.left(1).to_upper() + txt.substr(1)


static func is_assembly(p: String) -> bool:
	return products.get(p, {}).has("components")


static func components(p: String) -> Dictionary:
	return products.get(p, {}).get("components", {})


static func mat_qty(p: String) -> int:
	return int(products.get(p, {}).get("mat_qty", 1))


## Массив из balance.json.
static func barr(key: String) -> Array:
	return balance.get(key, [])


## Число из balance.json.
static func b(key: String) -> float:
	return float(balance.get(key, 0.0))


## Число из seasons.json.
static func sea(key: String) -> float:
	return float(seasons.get(key, 0.0))


## Число из events.json.
static func ev(key: String) -> float:
	return float(events.get(key, 0.0))


## 1.39: название объекта на языке игры.
static func obj_name(id: String) -> String:
	return L.dt("object.%s.name" % id, str(objects.get(id, {}).get("name", id)))


static func room_name(id: String) -> String:
	return L.dt("room.%s.name" % id, str(rooms.get(id, {}).get("name", id)))


static func dept_name(id: String) -> String:
	return L.dt("department.%s.name" % id, str(departments.get(id, {}).get("name", id)))


static func research_name(id: String) -> String:
	return L.dt("research.%s.name" % id, str(research.get(id, {}).get("name", "")))


static func research_desc(id: String) -> String:
	return L.dt("research.%s.desc" % id, str(research.get(id, {}).get("desc", "")))


static func product_name(p: String) -> String:
	return L.dt("product.%s.name" % p, str(products.get(p, {}).get("name", p)))


static func material_name(m: String) -> String:
	return L.dt("material.%s.name" % m, str(materials.get(m, {}).get("name", m)))


static func wall_solid(wid: int) -> bool:
	if wid == 0:
		return false
	return bool(wall_by_id.get(wid, {}).get("solid", true))


## Русское склонение: plural(3, "день", "дня", "дней") -> "дня".
## 1.39: в английском — по строке перевода «одна|две|пять» → «one|many» (L.pl), если она есть.
static func plural(n: int, one: String, few: String, many: String) -> String:
	if L.is_en():
		return L.pl(n, one + "|" + few + "|" + many)
	var n10 := absi(n) % 10
	var n100 := absi(n) % 100
	if n10 == 1 and n100 != 11:
		return one
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return few
	return many


static func money_str(v: float) -> String:
	var neg := v < 0.0
	var n := int(round(absf(v)))
	var s := str(n)
	var out := ""
	var cnt := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		cnt += 1
		if cnt % 3 == 0 and i > 0:
			out = " " + out
	return ("−" if neg else "") + out + " ₽"
