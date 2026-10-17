class_name People
extends RefCounted
## Генерация людей: имена, возраст, навыки, внешность.

const SKINS := ["#f0cdb0", "#e8bc94", "#d8a47c", "#c98d63", "#9c6a48", "#6e4430"]
const HAIR_COLORS := ["#2a2420", "#4a3020", "#6b4428", "#9a6a3a", "#c9a45a", "#b5562e"]
const GRAY_HAIR := ["#9a9a94", "#c8c8c2", "#7d7a74"]
const OVERALL_COLS := ["#3d5a7a", "#2f4a68", "#5d6b5f", "#4a5d48", "#55606e"]
const SHIRT_COLS := ["#8a3e3a", "#4a6a8a", "#5d6b4a", "#6e4a7a", "#7a5a3a"]
const JACKET_COLS := ["#5a6068", "#2e3236", "#6b6a4a", "#4a4f5a"]
const CAP_COLS := ["#26324a", "#8a3e3a", "#2a2a2a", "#3a5a3a", "#5a5a60"]
const HELMET_COLS := ["#d9b13b", "#efefe9", "#e2752c"]
const KERCHIEF_COLS := ["#3d5a7a", "#8a3e3a", "#c9a45a", "#5d6b4a"]
const SUIT_COLS := ["#2e3440", "#3b4252", "#4a4f5a", "#3d4a5c", "#5a4e44", "#44475a"]
const STREET_COLS := ["#3b3f44", "#5a4636", "#2f3a4a", "#4a5240", "#6a3a3a", "#55504a", "#7a6a52", "#2a2c30"]


## Телосложение: свой силуэт туловища (мужской и женский), ширина деталей одежды (wf)
## и рост (sy — к росту человека ещё добавляется личный множитель look["h"]).
const BODIES := {
	"vthin": {"wf": 0.56, "wf_f": 0.54, "sy": 1.08, "name": ["очень худой", "очень худая"]},
	"thin": {"wf": 0.7, "wf_f": 0.66, "sy": 1.06, "name": ["худощавый", "худощавая"]},
	"strong": {"wf": 1.34, "wf_f": 1.08, "sy": 1.03, "name": ["могучий", "очень сильная"]},
	"normal": {"wf": 1.0, "wf_f": 0.82, "sy": 1.0, "name": ["среднего телосложения", "среднего телосложения"]},
	"stout": {"wf": 1.18, "wf_f": 0.98, "sy": 1.0, "name": ["крепкий", "крепкая"]},
	"fat": {"wf": 1.12, "wf_f": 1.02, "sy": 0.98, "name": ["полный", "полная"]},
	"vfat": {"wf": 1.32, "wf_f": 1.2, "sy": 0.96, "name": ["очень полный", "очень полная"]},
}
const SHAPE_KEY := {"vthin": "vthin", "thin": "thin", "normal": "norm", "stout": "stout", "strong": "strong", "fat": "fat", "vfat": "vfat"}


static func body_key(look: Dictionary) -> String:
	var k := str(look.get("body", ""))
	if k == "" or not BODIES.has(k):
		k = "stout" if float(look.get("bulk", 1.0)) > 1.05 else "normal"
	return k


## Параметры фигуры: {shape — суффикс текстуры туловища, wf — ширина одежды, sy — рост}.
static func body_of(look: Dictionary) -> Dictionary:
	var k := body_key(look)
	var bd: Dictionary = BODIES[k]
	var fem := bool(look.get("fem", false))
	return {"shape": ("f_" if fem else "m_") + str(SHAPE_KEY[k]), "wf": float(bd["wf_f"] if fem else bd["wf"]),
		"sy": float(bd["sy"]) * float(look.get("h", 1.0)), "name": bd["name"]}


static func body_name(w: Worker) -> String:
	var names: Array = body_of(w.look)["name"]
	return str(names[1 if w.female else 0])


static func random_body(rng: RandomNumberGenerator, age: int) -> String:
	var r := rng.randf()
	var older := clampf((age - 30) / 30.0, 0.0, 1.0) * 0.12
	# 1.22: шире разброс — очень худые, могучие и очень полные (одна случайная величина, как раньше)
	if r < 0.06 - older * 0.3:
		return "vthin"
	if r < 0.22 - older:
		return "thin"
	if r < 0.58 - older:
		return "normal"
	if r < 0.74:
		return "stout"
	if r < 0.82:
		return "strong"
	if r < 0.93:
		return "fat"
	return "vfat"


static func pick(rng: RandomNumberGenerator, arr: Array) -> Variant:
	return arr[rng.randi_range(0, arr.size() - 1)]


static func female_surname(s: String) -> String:
	if s.ends_with("ский"):
		return s.substr(0, s.length() - 4) + "ская"
	for suf in ["ов", "ев", "ёв", "ин", "ын"]:
		if s.ends_with(suf):
			return s + "а"
	return s


static func patronymic(father: String, female: bool) -> String:
	var special := {
		"Илья": ["Ильич", "Ильинична"], "Никита": ["Никитич", "Никитична"],
		"Пётр": ["Петрович", "Петровна"], "Павел": ["Павлович", "Павловна"],
		"Фёдор": ["Фёдорович", "Фёдоровна"], "Лев": ["Львович", "Львовна"],
	}
	if special.has(father):
		return special[father][1 if female else 0]
	if father.ends_with("й") or father.ends_with("ь"):
		var root := father.substr(0, father.length() - 1)
		return root + ("евна" if female else "евич")
	return father + ("овна" if female else "ович")


static func make(rng: RandomNumberGenerator, prof: String, female_chance: float = 0.25) -> Worker:
	var w := Worker.new()
	w.prof = prof
	var fchance := female_chance
	match prof:
		"qc", "accountant", "hr", "dispatcher":
			fchance = 0.65
		"buyer", "technologist", "sales_manager", "lawyer":
			fchance = 0.4
		"safety_engineer":
			fchance = 0.35
		"chief_engineer":
			fchance = 0.15
		"cleaner":
			fchance = 0.8
		"cook":
			fchance = 0.65
		"nurse":
			fchance = 0.8
		"setter":
			fchance = 0.1
		"cnc_operator":
			fchance = 0.25
		"guard":
			fchance = 0.2
		"foreman", "chief":
			fchance = 0.12
	w.female = rng.randf() < fchance
	var male_names: Array = Defs.names.get("male", ["Иван"])
	var fem_names: Array = Defs.names.get("female", ["Анна"])
	var surnames: Array = Defs.names.get("surnames", ["Иванов"])
	# 1.15: примерно каждый пятый — из Средней Азии (имя, фамилия, черты лица); бросков кубика столько же
	var own: Array = fem_names if w.female else male_names
	var far: Array = Defs.names.get("asia_female" if w.female else "asia_male", [])
	var ni := rng.randi_range(0, own.size() + far.size() - 1)
	var asia := ni >= own.size()
	w.first = str(far[ni - own.size()] if asia else own[ni])
	var sur: String = str(pick(rng, Defs.names.get("asia_surnames", surnames) if asia else surnames))
	w.last = female_surname(sur) if w.female else sur
	w.set_meta("eth", "asia" if asia else "slav")
	w.patronymic = ""
	w.age = rng.randi_range(20, 62)
	if Worker.ITR.has(prof):
		w.age = rng.randi_range(36 if prof in ["chief", "chief_engineer"] else 27, 62)
	var xp := clampi(int((w.age - 20) / 6.0), 0, 6)
	match prof:
		"turner":
			w.skills = {"turning": clampi(rng.randi_range(2, 6) + xp, 1, 10), "qc": rng.randi_range(2, 4),
				"build": rng.randi_range(1, 4), "haul": rng.randi_range(3, 5)}
		"qc":
			w.skills = {"turning": rng.randi_range(0, 3), "qc": clampi(rng.randi_range(3, 6) + xp, 2, 10),
				"build": rng.randi_range(1, 3), "haul": rng.randi_range(2, 4)}
		"electrician":
			w.skills = {"turning": rng.randi_range(0, 2), "qc": rng.randi_range(0, 2),
				"build": rng.randi_range(3, 6), "haul": rng.randi_range(2, 5), "electric": clampi(rng.randi_range(3, 6) + xp, 3, 10)}
		"cleaner":
			w.skills = {"turning": 0, "qc": rng.randi_range(0, 1), "build": rng.randi_range(0, 2), "haul": rng.randi_range(2, 4),
				"clean": clampi(rng.randi_range(3, 6) + int(xp / 2), 3, 10)}
		"setter":
			w.skills = {"turning": rng.randi_range(4, 7), "qc": rng.randi_range(2, 5), "build": rng.randi_range(2, 4),
				"haul": rng.randi_range(2, 4), "milling": rng.randi_range(3, 6), "setup": clampi(rng.randi_range(3, 6) + xp, 3, 10)}
		"cnc_operator":
			# 1.22: оператор ЧПУ — ставит заготовку, запускает программу, меряет; на ручных станках работает слабо
			w.skills = {"turning": rng.randi_range(1, 3), "milling": rng.randi_range(1, 3), "qc": rng.randi_range(2, 4), "build": rng.randi_range(0, 2),
				"haul": rng.randi_range(2, 4), "cnc": clampi(rng.randi_range(3, 6) + xp, 3, 10)}
		"guard":
			w.skills = {"turning": 0, "qc": rng.randi_range(0, 2), "build": rng.randi_range(0, 3), "haul": rng.randi_range(2, 5),
				"security": clampi(rng.randi_range(3, 6) + int(xp / 2), 3, 10)}
		"cook":
			w.skills = {"turning": 0, "qc": rng.randi_range(0, 1), "build": rng.randi_range(0, 2), "haul": rng.randi_range(2, 4),
				"cook": clampi(rng.randi_range(3, 6) + int(xp / 2), 3, 10)}
		"nurse":
			w.skills = {"turning": 0, "qc": rng.randi_range(0, 2), "build": rng.randi_range(0, 1), "haul": rng.randi_range(1, 3),
				"medicine": clampi(rng.randi_range(3, 6) + int(xp / 2), 3, 10)}
		"fitter":
			# 1.15: слесарь — доработка брака, заготовки, ремонт станков, может и собирать
			w.skills = {"turning": rng.randi_range(1, 3), "qc": rng.randi_range(2, 4), "build": rng.randi_range(2, 5),
				"haul": rng.randi_range(3, 5), "fitting": clampi(rng.randi_range(3, 6) + xp, 3, 10), "assembly": rng.randi_range(2, 4)}
		"builder":
			w.skills = {"turning": rng.randi_range(0, 1), "qc": rng.randi_range(0, 2),
				"build": clampi(rng.randi_range(4, 7) + int(xp / 2), 3, 10), "haul": rng.randi_range(4, 7), "electric": rng.randi_range(1, 3)}
		_:
			w.skills = {"turning": rng.randi_range(0, 2), "qc": rng.randi_range(0, 2),
				"build": rng.randi_range(3, 7), "haul": rng.randi_range(5, 9)}
	if not w.skills.has("electric"):
		w.skills["electric"] = rng.randi_range(0, 3)
	# прочие навыки — понемногу у всех, основной — по профессии
	for sk in ["milling", "welding", "heat", "paint", "assembly"]:
		if not w.skills.has(sk):
			w.skills[sk] = rng.randi_range(0, 2)
	var main := str(Worker.PROF_SKILL.get(prof, ""))
	if main in ["milling", "welding", "heat", "paint", "assembly"]:
		w.skills[main] = clampi(rng.randi_range(3, 6) + xp, 3, 10)
		w.skills["build"] = rng.randi_range(2, 5)
		w.skills["haul"] = rng.randi_range(2, 5)
		if main == "milling":
			w.skills["turning"] = rng.randi_range(1, 4)
		if main == "assembly":
			w.skills["qc"] = rng.randi_range(2, 4)
	if Worker.ITR.has(prof):
		var msk := str(Worker.PROF_SKILL[prof])
		w.skills["build"] = rng.randi_range(0, 3)
		w.skills["haul"] = rng.randi_range(1, 3)
		w.skills[msk] = clampi(rng.randi_range(3, 6) + int(xp / 2), 3, 10)
		if prof == "chief" or prof == "chief_engineer":
			w.skills[msk] = clampi(rng.randi_range(5, 7) + int(xp / 2), 5, 10)
		if prof == "chief_engineer":
			w.skills["electric"] = rng.randi_range(3, 6)
		if prof == "foreman" or prof == "chief":
			w.skills["turning"] = rng.randi_range(3, 6)
			w.skills["qc"] = rng.randi_range(2, 5)
		if prof == "technologist":
			w.skills["turning"] = rng.randi_range(2, 4)
			w.skills["milling"] = rng.randi_range(1, 4)
	w.wage = wage_for(w)
	w.look = random_look(rng, w)
	# дети дошкольного возраста: по имени и возрасту, без лишних бросков кубика
	if w.age >= 23 and w.age <= 44:
		var hk := absi((w.first + w.last).hash() + w.age * 31) % 100
		w.kids = 2 if hk < 12 else (1 if hk < 45 else 0)
	w.traits = random_traits(rng, w)
	return w


## 1–2 черты характера, без взаимоисключающих.
static func random_traits(rng: RandomNumberGenerator, w: Worker) -> Array:
	var keys: Array = Defs.traits.keys()
	var out: Array = []
	var n := 1 if rng.randf() < 0.55 else 2
	var guard := 0
	while out.size() < n and guard < 30:
		guard += 1
		var k: String = str(pick(rng, keys))
		if out.has(k) or not bool(Defs.traits[k].get("gen", true)):
			continue
		var opp := str(Defs.traits[k].get("opp", ""))
		if opp != "" and out.has(opp):
			continue
		if k == "veteran" and w.age < 45:
			continue
		out.append(k)
	return out


## 1.15 (РП-9): рыночные ставки растут с ценами — раз в квартал (Careers).
static var wage_index := 1.0


static func wage_for(w: Worker) -> int:
	var base := 2400.0
	match w.prof:
		"turner":
			base = 2900.0 + w.grade() * 230.0
		"qc":
			base = 2700.0 + w.grade() * 160.0
		"electrician":
			base = 2800.0 + w.grade() * 200.0
		"miller", "welder":
			base = 2900.0 + w.grade() * 230.0
		"heat_treater", "assembler", "fitter":
			base = 2750.0 + w.grade() * 190.0
		"painter":
			base = 2500.0 + w.grade() * 150.0
		"foreman":
			base = 4200.0 + w.grade() * 250.0
		"chief":
			base = 5600.0 + w.grade() * 300.0
		"accountant", "buyer":
			base = 3500.0 + w.grade() * 200.0
		"dispatcher", "hr":
			base = 3300.0 + w.grade() * 180.0
		"technologist":
			base = 4000.0 + w.grade() * 250.0
		"sales_manager":
			base = 3600.0 + w.grade() * 220.0
		"safety_engineer":
			base = 3400.0 + w.grade() * 200.0
		"chief_engineer":
			base = 5200.0 + w.grade() * 300.0
		"lawyer":
			base = 4200.0 + w.grade() * 260.0
		"builder":
			base = 2350.0 + w.skill("build") * 70.0
		"cleaner":
			base = 2050.0 + w.skill("clean") * 30.0
		"setter":
			base = 3300.0 + w.grade() * 260.0
		"cnc_operator":
			base = 3100.0 + w.grade() * 240.0
		"guard":
			base = 2200.0 + w.skill("security") * 60.0
		"cook":
			base = 2300.0 + w.skill("cook") * 70.0
		"nurse":
			base = 2700.0 + w.skill("medicine") * 90.0
		_:
			base = 2300.0 + w.skill("haul") * 35.0 + w.skill("build") * 25.0
	return int(round(base * Defs.b("wage_k") * wage_index / 50.0) * 50.0)


# ---------------------------------------------------------------- лицо (1.15)

const HEADS := ["oval", "square", "round", "long", "soft"]
const EYE_KINDS := ["almond", "narrow", "round", "heavy", "deep"]
const BROW_KINDS := ["straight", "arched", "thick", "thin", "angled", "bushy"]
const NOSE_KINDS := ["small", "straight", "long", "wide", "hooked"]
const MOUTH_KINDS := ["neutral", "smile", "thin", "full", "down"]
const HAIR_M := ["short", "crew", "side", "slick", "receding", "bald", "curly", "mullet"]
const HAIR_F := ["bob", "bun", "ponytail", "long", "pixie", "curly_f", "braid", "perm"]
const EAR_HIDDEN := ["bob", "long", "curly_f", "perm"]
const EYE_COLS := ["#6b4428", "#4a3020", "#4f7090", "#5d7a4a", "#7a6236", "#3f6a8a", "#3a2a20"]


static func _wpick(r: RandomNumberGenerator, opts: Array) -> String:
	## opts: [[значение, вес], ...]
	var tot := 0.0
	for o: Array in opts:
		tot += float(o[1])
	var x := r.randf() * tot
	for o: Array in opts:
		x -= float(o[1])
		if x <= 0.0:
			return str(o[0])
	return str(opts[-1][0])


## Причёска с учётом старых названий (до 1.15).
static func hair_style(lk: Dictionary) -> String:
	var st := str(lk.get("hair", "short"))
	var fem := bool(lk.get("fem", false))
	if st == "buzz":
		return "crew"
	if fem and st == "short":
		return "pixie"
	if fem and st == "curly":
		return "curly_f"
	return st


## Цвет глаз — один и тот же в кукле и на портрете.
static func eye_color(lk: Dictionary) -> Color:
	if str(lk.get("eth", "")) == "asia":
		return Color(EYE_COLS[6 if int(lk.get("fs", 0)) % 3 == 0 else 1])
	return Color(EYE_COLS[absi(int(lk.get("skin", 0)) * 7 + str(lk.get("hair_col", "")).hash()) % EYE_COLS.size()])


## Черты лица: форма головы, разрез глаз, брови, нос, рот, веснушки, серьги, морщины.
## Хранятся только зерно и происхождение — черты выводятся из них одинаково везде (кукла, портрет).
static func face(lk: Dictionary, age: int = -1) -> Dictionary:
	if lk.has("_face") and age < 0:
		return lk["_face"]
	var r := RandomNumberGenerator.new()
	r.seed = int(lk.get("fs", absi(str(lk.get("hair_col", "")).hash() + int(lk.get("skin", 0)) * 7919 + str(lk.get("outfit_col", "")).hash())))
	var fem := bool(lk.get("fem", false))
	var asia := str(lk.get("eth", "")) == "asia"
	var a := age if age >= 0 else int(lk.get("age", 35))
	var body := body_key(lk)
	var f := {}
	if fem:
		f["head"] = _wpick(r, [["soft", 55], ["oval", 25], ["round", 20 + (25 if body in ["fat", "vfat"] else 0)]])
	else:
		f["head"] = _wpick(r, [["oval", 35], ["square", 28], ["round", 14 + (40 if body in ["fat", "vfat"] else 0)], ["long", 14 + (30 if body == "thin" else 0)]])
	if asia:
		f["eyes"] = _wpick(r, [["narrow", 85], ["almond", 15]])
	else:
		f["eyes"] = _wpick(r, [["almond", 45], ["round", 18 + (10 if fem else 0)], ["deep", 15], ["heavy", 8 + (30 if a >= 45 else 0)]])
	if fem:
		f["brows"] = _wpick(r, [["thin", 45], ["arched", 45], ["straight", 10]])
	else:
		f["brows"] = _wpick(r, [["straight", 35], ["thick", 25 + (15 if asia else 0)], ["angled", 12], ["arched", 10], ["bushy", 3 + (40 if a >= 50 else 0)]])
	if fem:
		f["nose"] = _wpick(r, [["small", 55], ["straight", 35], ["wide", 10 + (15 if asia else 0)]])
	elif asia:
		f["nose"] = _wpick(r, [["small", 50], ["wide", 35], ["straight", 15]])
	else:
		f["nose"] = _wpick(r, [["straight", 35], ["small", 22], ["long", 18], ["wide", 14], ["hooked", 11]])
	if fem:
		f["mouth"] = _wpick(r, [["full", 55], ["neutral", 30], ["smile", 15]])
	else:
		f["mouth"] = _wpick(r, [["neutral", 55], ["thin", 22], ["smile", 12], ["down", 4 + (18 if a >= 45 else 0)]])
	var hc := Color(str(lk.get("hair_col", "#4a3020")))
	f["freckles"] = not asia and int(lk.get("skin", 0)) <= 1 and (hc.r > hc.b * 1.6 or hc.v > 0.6) and r.randf() < 0.4
	f["earrings"] = fem and r.randf() < 0.55
	f["lines"] = "old" if a >= 52 else ("mid" if a >= 38 else "")
	return f


static func random_look(rng: RandomNumberGenerator, w: Worker) -> Dictionary:
	var lk := {}
	var eth := str(w.get_meta("eth", "slav"))
	lk["eth"] = eth
	lk["fs"] = absi((w.first + w.last).hash() + w.age * 131)   # зерно черт лица (без бросков кубика)
	lk["age"] = w.age
	var sk := rng.randi_range(0, 99)
	if eth == "asia":
		lk["skin"] = 1 if sk < 30 else (2 if sk < 75 else 3)
	else:
		# 1.15: смуглых и тёмных меньше
		lk["skin"] = 0 if sk < 44 else (1 if sk < 86 else (2 if sk < 97 else (3 if sk < 99 else 4)))
	var old := w.age >= 50
	var hc: Array = GRAY_HAIR if (old and rng.randf() < 0.7) else (["#2a2420", "#2a2420", "#33261e", "#3d2a1e", "#2a2420", "#4a3020"] if eth == "asia" else HAIR_COLORS)
	var hair_col: String = str(pick(rng, hc))
	lk["hair_col"] = hair_col
	if w.female:
		lk["hair"] = pick(rng, (["perm", "bun", "bob", "perm", "short_f"] if w.age >= 45 else ["ponytail", "bun", "long", "bob", "pixie", "braid", "curly_f", "ponytail"]))
		if str(lk["hair"]) == "short_f":
			lk["hair"] = "pixie"
		lk["beard"] = ""
	else:
		var bald_chance := 0.05 + maxf(0.0, (w.age - 35) * 0.015)
		if rng.randf() < bald_chance:
			lk["hair"] = "bald" if w.age >= 50 else "receding"
		else:
			lk["hair"] = pick(rng, ["short", "side", "crew", "curly", "short", "slick", "mullet", "side", "crew"])
		lk["beard"] = pick(rng, ["", "", "", "mustache", "full", "goatee", "stubble", "chevron", "short"]) if w.age > 22 else pick(rng, ["", "", "stubble"])
	lk["glasses"] = rng.randf() < (0.15 + (0.25 if old else 0.0))
	lk["phones"] = false
	lk["body"] = random_body(rng, w.age)
	lk["bulk"] = 1.0
	lk["fem"] = w.female
	lk["h"] = snappedf(rng.randf_range(0.93, 1.07) - (0.03 if w.female else 0.0), 0.01)
	match w.prof:
		"turner":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, OVERALL_COLS)
			lk["hat"] = pick(rng, ["", "cap", "", "kerchief"]) if not w.female else pick(rng, ["kerchief", ""])
		"qc":
			lk["outfit"] = "coat"
			lk["outfit_col"] = "#e9ecec"
			lk["hat"] = ""
		"electrician":
			lk["outfit"] = "vest"
			lk["outfit_col"] = "#e2752c"
			lk["hat"] = "helmet"
		"miller":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, OVERALL_COLS)
			lk["hat"] = pick(rng, ["cap", "", "cap"]) if not w.female else "kerchief"
		"welder":
			lk["outfit"] = "jacket"
			lk["outfit_col"] = pick(rng, ["#6e5a3e", "#5d5038", "#7a6446"])
			lk["hat"] = "weldmask"
		"heat_treater":
			lk["outfit"] = "apron"
			lk["outfit_col"] = pick(rng, ["#4a5d48", "#55606e"])
			lk["hat"] = "cap"
		"painter":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, ["#d6d9d4", "#c9cfd2"])
			lk["hat"] = "kerchief"
			lk["resp"] = true
		"assembler":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, ["#2f4a68", "#3d5a7a", "#5d6b5f"])
			lk["hat"] = pick(rng, ["cap", ""])
		"fitter":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, ["#4a5568", "#3f4d5c", "#55504a"])
			lk["hat"] = pick(rng, ["cap", "cap", ""])
		"cleaner":
			lk["outfit"] = "coat"
			lk["outfit_col"] = pick(rng, ["#4a7fa8", "#5a8fb0", "#b0607a", "#6a8a5a"])
			lk["hat"] = "kerchief" if w.female else "cap"
		"setter":
			lk["outfit"] = "overall"
			lk["outfit_col"] = pick(rng, ["#2f4a68", "#3d5a7a", "#4a4f5a"])
			lk["hat"] = "cap"
		"cnc_operator":
			lk["outfit"] = "jacket"
			lk["outfit_col"] = pick(rng, ["#3a5f8a", "#2f5a6e", "#4a5a6a"])
			lk["hat"] = pick(rng, ["", "cap", ""]) if not w.female else pick(rng, ["kerchief", ""])
		"guard":
			lk["outfit"] = "jacket"
			lk["outfit_col"] = pick(rng, ["#262b33", "#2c3340", "#30363a"])
			lk["hat"] = "cap"
		"cook":
			lk["outfit"] = "coat"
			lk["outfit_col"] = "#f2f2ee"
			lk["hat"] = "kerchief"
		"nurse":
			lk["outfit"] = "coat"
			lk["outfit_col"] = "#e6eef2"
			lk["hat"] = ""
		"builder":
			lk["outfit"] = pick(rng, ["jacket", "overall", "vest"])
			lk["outfit_col"] = "#e2752c" if lk["outfit"] == "vest" else pick(rng, JACKET_COLS if lk["outfit"] == "jacket" else OVERALL_COLS)
			lk["hat"] = "helmet"
		"foreman", "chief", "accountant", "buyer", "dispatcher", "hr", "technologist", "sales_manager", "safety_engineer", "chief_engineer", "lawyer":
			lk["outfit"] = "suit"
			lk["outfit_col"] = pick(rng, SUIT_COLS)
			lk["hat"] = "helmet" if w.prof in ["foreman", "safety_engineer"] else ""
			lk["glasses"] = rng.randf() < 0.4
		_:
			lk["outfit"] = pick(rng, ["shirt", "jacket", "overall"])
			lk["outfit_col"] = pick(rng, SHIRT_COLS if lk["outfit"] == "shirt" else (JACKET_COLS if lk["outfit"] == "jacket" else OVERALL_COLS))
			lk["hat"] = pick(rng, ["cap", "", "helmet", "cap"])
			lk["phones"] = (not w.female) and w.age < 35 and rng.randf() < 0.35
	lk["street"] = "coat" if (w.female and rng.randf() < 0.5) else "jacket"
	lk["street_col"] = pick(rng, STREET_COLS)
	match lk["hat"]:
		"cap":
			lk["hat_col"] = pick(rng, CAP_COLS)
		"helmet":
			lk["hat_col"] = "#efefe9" if w.prof == "foreman" else pick(rng, HELMET_COLS)
		"weldmask":
			lk["hat_col"] = pick(rng, ["#3a3f43", "#2a2e31", "#4a4f55"])
		"kerchief":
			lk["hat_col"] = pick(rng, KERCHIEF_COLS)
		_:
			lk["hat_col"] = "#ffffff"
	return lk
