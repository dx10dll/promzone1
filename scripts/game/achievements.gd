class_name Achievements
extends RefCounted
## Достижения: общие для всех партий, хранятся в user://achievements.cfg.
## В песочнице не засчитываются — там деньги и оборудование даются даром.

const PATH := "user://achievements.cfg"

static var defs: Array = []
static var got: Dictionary = {}     ## id -> дата получения
static var _loaded := false


static func load_all() -> void:
	if _loaded:
		return
	_loaded = true
	var f := FileAccess.open("res://data/achievements.json", FileAccess.READ)
	if f:
		var d: Variant = JSON.parse_string(f.get_as_text())
		if d is Dictionary:
			defs = (d as Dictionary).get("list", [])
	var cf := ConfigFile.new()
	if cf.load(PATH) == OK and cf.has_section("got"):
		for k in cf.get_section_keys("got"):
			got[k] = str(cf.get_value("got", k, ""))


static func save() -> void:
	var cf := ConfigFile.new()
	for k in got.keys():
		cf.set_value("got", str(k), got[k])
	cf.save(PATH)


static func counts(sim: Sim) -> bool:
	return sim != null and sim.scenario != "sandbox"


## Проверить условия. Возвращает только что полученные достижения.
static func check(sim: Sim) -> Array:
	load_all()
	var out: Array = []
	if not counts(sim):
		return out
	for a: Dictionary in defs:
		var id := str(a["id"])
		if got.has(id):
			continue
		if value(sim, a) >= float(a.get("n", 1)):
			got[id] = Time.get_date_string_from_system()
			out.append(a)
	if not out.is_empty():
		save()
	return out


## Текущее значение показателя для достижения (для полосы прогресса).
static func value(sim: Sim, a: Dictionary) -> float:
	match str(a.get("type", "stat")):
		"stat":
			return float(sim.stats.get(str(a.get("stat", "")), 0))
		"money":
			return sim.money
		"stage":
			return float(sim.progress.stage)
		"staff":
			return float(sim.workers.size())
		"stars":
			return float(sim.progress.stars)
		"grants":
			return float(sim.grants.done.size())
		"nicks":
			var n := 0
			for w in sim.workers:
				if w.nick != "":
					n += 1
			return float(n)
		"days":
			return float(sim.day())
		"safe_days":
			var last := 0
			if not sim.story.injuries.is_empty():
				last = int(sim.story.injuries.back())
			return float(sim.day() - last) if sim.day() > 1 else 0.0
		"scenario":
			return 1.0 if sim.progress.scn_done else 0.0
		"night":
			for w2 in sim.workers:
				if w2.shift == 1:
					return 1.0
			return 0.0
	return 0.0


static func got_count() -> int:
	load_all()
	var n := 0
	for a: Dictionary in defs:
		if got.has(str(a["id"])):
			n += 1
	return n
