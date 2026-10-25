class_name CustomPeople
extends RefCounted
## 1.32: свои рабочие — люди, которых игрок собрал в главном меню («Создать рабочего»: ФИО, внешность,
## черты). Список приходит в симуляцию при начале игры (Sim.customs, хранится в сохранении — загрузка
## детерминирована) и дальше от файла в user:// не зависит. При каждом обновлении кандидатов каждый,
## кого ещё нет в этой игре, может прийти кандидатом с шансом Sim.custom_chance (броски — sim.rng).
## Пришёл, но его не наняли — может прийти снова; работает на заводе — второй раз не придёт;
## уволился или уволен — снова может прийти, как обычный кандидат.

const MAX := 50
const MAX_TRAITS := 2
## Части внешности, которые задаются в редакторе (остальное — по профессии: спецовка, каска).
const LOOK_KEYS := ["skin", "hair", "hair_col", "beard", "glasses", "body", "h", "street", "street_col", "eye_col", "face_ovr"]


## Подключить список к новой игре: только включённые и правильные записи, не больше MAX.
static func attach(sim: Sim, entries: Array, chance: float) -> void:
	sim.customs = []
	for e: Variant in entries:
		if sim.customs.size() >= MAX:
			break
		if e is Dictionary and bool((e as Dictionary).get("enabled", true)) and valid(e):
			sim.customs.append((e as Dictionary).duplicate(true))
	sim.custom_chance = clampf(chance, 0.0, 1.0)


## Минимальная проверка записи (подробная — в редакторе, CustomWorkers.validate).
static func valid(e: Dictionary) -> bool:
	return str(e.get("id", "")) != "" and str(e.get("first", "")).strip_edges() != "" and str(e.get("last", "")).strip_edges() != ""


## Есть ли этот свой рабочий в игре сейчас: работает или уже среди кандидатов.
static func in_game(sim: Sim, cid: String) -> bool:
	for w in sim.workers:
		if w.custom_id == cid:
			return true
	for c: Dictionary in sim.candidates:
		if str(c.get("cust", "")) == cid:
			return true
	return false


## Вызывается в конце Sim.refresh_candidates: может добавить одного своего рабочего к кандидатам.
## profs — перемешанный список профессий этого обновления (для записей с профессией «любая»).
static func roll(sim: Sim, profs: Array, only_prof: String = "") -> Worker:
	if sim.customs.is_empty() or sim.custom_chance <= 0.0:
		return null
	var pool: Array = []
	for e: Dictionary in sim.customs:
		var pf := str(e.get("prof", ""))
		if only_prof != "" and pf != "" and pf != only_prof:
			continue
		if not in_game(sim, str(e["id"])):
			pool.append(e)
	if pool.is_empty():
		return null
	sim.shuffle(pool)
	for e2: Dictionary in pool:
		if sim.rng.randf() >= sim.custom_chance:
			continue
		var prof := str(e2.get("prof", ""))
		if prof == "" or not Worker.PROF_NAMES.has(prof):
			prof = only_prof if only_prof != "" else (str(profs[sim.rng.randi_range(0, profs.size() - 1)]) if not profs.is_empty() else "laborer")
		var w := make(sim.rng, e2, prof)
		sim.candidates.append(w.to_dict())
		sim.notify(Nicks.gendered(L.t("★ %s приш{ёл|ла} наниматься (%s) — {он|она} среди кандидатов."), w.female) % [w.full_name(), w.prof_lc() if L.is_en() else w.prof_name().to_lower()], Sim.LVL_INFO)
		return w
	return null


## Человек по записи: навыки и ставка — как у обычного кандидата этой профессии (кубик), всё остальное —
## ровно как в редакторе: ФИО, пол, возраст, черты, внешность.
static func make(rng: RandomNumberGenerator, e: Dictionary, prof: String) -> Worker:
	var fem := bool(e.get("female", false))
	var w := People.make(rng, prof, 0.25, {"female": fem, "first": str(e["first"]), "last": str(e["last"]),
		"age": clampi(int(e.get("age", 30)), 18, 70)})
	w.patronymic = str(e.get("patr", ""))
	w.custom_id = str(e["id"])
	apply_look(w.look, e)
	w.traits = clean_traits(e.get("traits", []), w.age)
	return w


## Поверх внешности по профессии — то, что выбрано в редакторе.
static func apply_look(lk: Dictionary, e: Dictionary) -> void:
	var src: Variant = e.get("look", {})
	if not src is Dictionary:
		return
	var fem := bool(e.get("female", false))
	for k: String in LOOK_KEYS:
		if (src as Dictionary).has(k):
			var v: Variant = (src as Dictionary)[k]
			lk[k] = (v as Dictionary).duplicate() if v is Dictionary else v
	lk["skin"] = clampi(int(lk.get("skin", 0)), 0, People.SKINS.size() - 1)
	lk["glasses"] = bool(lk.get("glasses", false))
	lk["h"] = clampf(float(lk.get("h", 1.0)), 0.9, 1.1)
	lk["fem"] = fem
	lk["eth"] = "slav"
	if fem:
		lk["beard"] = ""
		if not People.HAIR_F.has(str(lk.get("hair", ""))):
			lk["hair"] = "bob"
	elif not People.HAIR_M.has(str(lk.get("hair", ""))):
		lk["hair"] = "short"
	if not People.BODIES.has(str(lk.get("body", ""))):
		lk["body"] = "normal"
	lk["age"] = int(e.get("age", lk.get("age", 30)))


## Черты: только известные, без «Практиканта», без взаимоисключающих, не больше двух.
static func clean_traits(src: Variant, age: int) -> Array:
	var out: Array = []
	if not src is Array:
		return out
	for t: Variant in src:
		var k := str(t)
		if out.size() >= MAX_TRAITS or out.has(k) or not Defs.traits.has(k):
			continue
		var d: Dictionary = Defs.traits[k]
		if not bool(d.get("gen", true)):
			continue
		if str(d.get("opp", "")) != "" and out.has(str(d["opp"])):
			continue
		if k == "veteran" and age < 45:
			continue
		out.append(k)
	return out


## Внешность для предпросмотра в редакторе: как в игре, но кубик — свой, от id записи.
static func preview_worker(e: Dictionary) -> Worker:
	var r := RandomNumberGenerator.new()
	r.seed = absi(str(e.get("id", "x")).hash()) + 17
	var prof := str(e.get("prof", ""))
	if prof == "" or not Worker.PROF_NAMES.has(prof):
		prof = "laborer"
	var ee := e.duplicate(true)
	if str(ee.get("first", "")) == "":
		ee["first"] = "Иван"
	if str(ee.get("last", "")) == "":
		ee["last"] = "Иванов"
	if str(ee.get("id", "")) == "":
		ee["id"] = "preview"
	var w := make(r, ee, prof)
	if prof == "laborer":
		w.look["hat"] = ""   # «любая профессия» — без каски и кепки, чтобы видно причёску
		w.look["phones"] = false
	return w
