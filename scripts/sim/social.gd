class_name Social
extends RefCounted
## Люди общаются (1.14). Кто рядом и свободен — болтает (на перекуре, в обед, без дела):
## друзья чаще, весельчаки охотнее, молчуны реже. Кто не ладит — ругается: склочники и злые
## чаще. Ругань иногда перерастает в драку: дерутся пару минут, остальные сбегаются смотреть,
## охранник или мастер разнимает. После драки — синяки, иногда травма, и решение директора.

const FOE := -30.0
const FREE := ["rest", "smoke", "wander", "break", ""]
const BUSY := ["operate", "inspect", "build_bp", "build_thing", "toilet", "shower", "dress", "undress", "go_home",
	"escort", "brief", "study", "social", "fix", "repair", "demolish", "lay_net", "extinguish", "strike", "eat",
	"despawn", "deliver", "load", "reset", "cook", "nurse", "guard", "union", "meet", "office"]

var sim: Sim
var events: Array = []          ## [{kind, a, b, end, watchers, breaker}]
var _t := 0.0
var last_fight := -99999.0
var rng := RandomNumberGenerator.new()   ## свой генератор: разговоры не сдвигают остальные случайности


func _init(s: Sim) -> void:
	sim = s
	rng.seed = s.rng.seed + 7177


func _free(w: Worker) -> bool:
	if not w.present or w.hidden or w.visitor or w.carrying >= 0 or w.is_itr():
		return false
	if sim.story.striking(w):
		return false
	var k := w.task.kind if w.task else ""
	return not BUSY.has(k)


## Сидит в столовой или курит — можно болтать, не вставая.
func _sitting(w: Worker) -> bool:
	return w.present and not w.hidden and not w.visitor and w.task != null and w.task.kind in ["eat", "smoke"] \
		and w.task.current().get("t", "") == "work"


func _chatty(w: Worker) -> bool:
	return w.task == null or FREE.has(w.task.kind)


func busy_with(w: Worker) -> Dictionary:
	for e: Dictionary in events:
		if int(e["a"]) == w.id or int(e["b"]) == w.id:
			return e
	return {}


func tick(dt: float) -> void:
	_check_events()
	_t -= dt
	if _t > 0.0:
		return
	_t = 4.0
	if events.size() >= 3:
		return
	var people: Array[Worker] = []
	for w in sim.workers:
		if (_free(w) or _sitting(w)) and busy_with(w).is_empty() and not near_fight(w.pos):
			people.append(w)
	if people.size() < 2:
		return
	for i in range(people.size() - 1, 0, -1):   # перемешать своим генератором — повторяемо
		var j := rng.randi_range(0, i)
		var tmp := people[i]
		people[i] = people[j]
		people[j] = tmp
	for i in people.size():
		var a: Worker = people[i]
		for j in range(i + 1, people.size()):
			var b: Worker = people[j]
			if a.pos.distance_to(b.pos) > 3.5:
				continue
			if sim.rooms.space_id_at(a.cell()) != sim.rooms.space_id_at(b.cell()):
				continue
			var rel := sim.training.rel(a, b)
			if rel <= FOE:
				var pa := 0.05 + (0.06 if Mood.has_trait(a, "squabbler") or Mood.has_trait(b, "squabbler") else 0.0) \
					+ (0.04 if Mood.has_trait(a, "grumpy") or Mood.has_trait(b, "grumpy") else 0.0) \
					+ (0.05 if minf(a.mood, b.mood) < 30.0 else 0.0)
				if rng.randf() < pa:
					start(a, b, "argue")
					return
			elif _chatty(a) and _chatty(b):
				var pc := 0.10 + (0.08 if rel >= 30.0 else 0.0) + (0.05 if Mood.has_trait(a, "cheerful") or Mood.has_trait(b, "cheerful") else 0.0) \
					- (0.06 if Mood.has_trait(a, "quiet") and Mood.has_trait(b, "quiet") else 0.0)
				if rng.randf() < pc:
					start(a, b, "chat")
					return


## Рядом дерутся — не до болтовни.
func near_fight(p: Vector2) -> bool:
	for e: Dictionary in events:
		if str(e["kind"]) != "fight":
			continue
		var a := sim.get_worker(int(e["a"]))
		if a and a.pos.distance_to(p) < 9.0:
			return true
	return false


## Где сейчас клубок драки (для облака пыли), или пусто.
func fight_spots() -> Array[Vector2]:
	var out: Array[Vector2] = []
	for e: Dictionary in events:
		if str(e["kind"]) != "fight":
			continue
		var a := sim.get_worker(int(e["a"]))
		var b := sim.get_worker(int(e["b"]))
		if a == null or b == null or a.task == null or b.task == null:
			continue
		if str(a.task.current().get("t", "")) != "work" or str(b.task.current().get("t", "")) != "work":
			continue
		out.append((a.pos + b.pos) * 0.5)
	return out


## Начать разговор, ругань или драку: второй подходит к первому, оба стоят лицом друг к другу.
func start(a: Worker, b: Worker, kind: String) -> void:
	var dur: float = float({"chat": rng.randf_range(3.0, 6.0), "argue": rng.randf_range(2.0, 4.0), "fight": rng.randf_range(1.5, 3.0)}[kind])
	sim.brain.abort(a)
	sim.brain.abort(b)
	var meet := _beside(a.cell(), b.cell())
	var e := {"kind": kind, "a": a.id, "b": b.id, "end": sim.minute + float(dur) + 2.0, "watchers": [], "breaker": -1}
	events.append(e)
	sim.brain.assign(a, _task(a, b, kind, a.cell(), float(dur) + 1.0))
	sim.brain.assign(b, _task(b, a, kind, meet, float(dur)))
	if kind == "fight":
		_gather(e, a)


## Болтают, не бросая еду или сигарету: только значки над головой.
func chat_in_place(a: Worker, b: Worker) -> void:
	var e := {"kind": "chat", "a": a.id, "b": b.id, "end": sim.minute + rng.randf_range(3.0, 6.0), "watchers": [], "breaker": -1, "inplace": true}
	events.append(e)
	for p: Worker in [a, b]:
		p.bubble = "laugh" if Mood.has_trait(p, "cheerful") or rng.randf() < 0.3 else "chat"


func _task(w: Worker, o: Worker, kind: String, cell: Vector2i, dur: float) -> Task:
	var t := Task.new()
	t.kind = "social"
	t.data["other"] = o.id
	match kind:
		"chat":
			t.label = L.t("Болтает: %s") % o.short_name()
			t.data["bubble"] = "laugh" if Mood.has_trait(w, "cheerful") or rng.randf() < 0.3 else "chat"
		"argue":
			t.label = L.t("Ругается: %s") % o.short_name()
			t.data["bubble"] = "argue"
		_:
			t.label = L.t("Дерётся: %s") % o.short_name()
			t.data["bubble"] = "fight"
	t.add({"t": "goto", "cell": cell})
	t.add({"t": "work", "what": "social", "other": o.id, "dur": dur, "anim": "fight" if kind == "fight" else ("talk" if kind == "argue" else "idle")})
	return t


## Свободная клетка рядом с a (ближе к b).
func _beside(a: Vector2i, b: Vector2i) -> Vector2i:
	var best := b
	var bd := INF
	for d: Vector2i in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var c := a + d
		if not sim.world.passable(c):
			continue
		var dd := Vector2(c - b).length()
		if dd < bd:
			bd = dd
			best = c
	return best


## Драка: зеваки сбегаются, охранник или мастер бежит разнимать.
func _gather(e: Dictionary, a: Worker) -> void:
	var n := 0
	# разнимать бежит ближайший охранник, мастер или начальник — даже если зевак уже набралось
	var brk: Worker = null
	for w in sim.workers:
		if w.prof in ["guard", "foreman", "chief"] and w.present and not w.hidden and w.pos.distance_to(a.pos) <= 14.0 \
				and busy_with(w).is_empty() and (brk == null or w.pos.distance_to(a.pos) < brk.pos.distance_to(a.pos)):
			brk = w
	for w in ([brk] if brk else []) + sim.workers:
		if int(e["a"]) == w.id or int(e["b"]) == w.id or int(e["breaker"]) == w.id:
			continue
		if not w.present or w.hidden or (w.pos.distance_to(a.pos) > 8.0 and w != brk) or not busy_with(w).is_empty():
			continue
		if w == brk and int(e["breaker"]) < 0:
			e["breaker"] = w.id
			sim.brain.abort(w)
			var t := Task.new()
			t.kind = "social"
			t.label = L.t("Разнимает драку")
			t.data["bubble"] = "argue"
			t.add({"t": "goto", "cell": _beside(a.cell(), w.cell())})
			t.add({"t": "work", "what": "social", "other": a.id, "dur": 2.0, "anim": "talk", "breakup": true})
			sim.brain.assign(w, t)
			continue
		if n >= 6 or w.is_itr() and w.prof != "foreman":
			continue
		if not _free(w) and not (w.task and w.task.kind in ["operate", "haul"]):
			continue
		if (e["watchers"] as Array).has(w.id):
			continue
		sim.brain.abort(w)
		(e["watchers"] as Array).append(w.id)
		var spot := a.cell()
		for k in 6:
			var c := a.cell() + Vector2i(rng.randi_range(-3, 3), rng.randi_range(-3, 3))
			if sim.world.passable(c) and Vector2(c - a.cell()).length() >= 2.0:
				spot = c
				break
		var tw := Task.new()
		tw.kind = "social"
		tw.label = L.t("Смотрит на драку")
		tw.add({"t": "goto", "cell": spot})
		tw.add({"t": "work", "what": "social", "other": a.id, "dur": float(e["end"]) - sim.minute, "anim": "idle"})
		sim.brain.assign(w, tw)
		n += 1


## Разняли — драка кончается раньше.
func on_breakup(w: Worker) -> void:
	for e: Dictionary in events:
		if str(e["kind"]) == "fight" and int(e["breaker"]) == w.id:
			e["end"] = minf(float(e["end"]), sim.minute + 0.5)
			for id in [e["a"], e["b"]]:
				var p := sim.get_worker(int(id))
				if p and p.task and p.task.kind == "social":
					sim.brain.abort(p)


func _check_events() -> void:
	for i in range(events.size() - 1, -1, -1):
		var e: Dictionary = events[i]
		var a := sim.get_worker(int(e["a"]))
		var b := sim.get_worker(int(e["b"]))
		var gone := a == null or b == null or not a.present or not b.present
		if not gone and sim.minute < float(e["end"]):
			continue
		events.remove_at(i)
		if bool(e.get("inplace", false)):
			for p: Worker in [a, b]:
				if p and p.bubble in ["chat", "laugh"]:
					p.bubble = str(p.task.data.get("bubble", "")) if p.task else ""
		if gone:
			continue
		match str(e["kind"]):
			"chat":
				sim.training._add_rel(a, b, 3.0)
				Mood.add(sim, a, "chatted")
				Mood.add(sim, b, "chatted")
			"argue":
				sim.training._add_rel(a, b, -5.0)
				Mood.add(sim, a, "argued")
				Mood.add(sim, b, "argued")
				var pf := 0.12 + (0.2 if minf(a.mood, b.mood) < 25.0 else 0.0) \
					+ (0.15 if Mood.has_trait(a, "drinker") or Mood.has_trait(b, "drinker") else 0.0) \
					+ (0.1 if Mood.has_trait(a, "squabbler") or Mood.has_trait(b, "squabbler") else 0.0)
				if sim.minute - last_fight < 1440.0:
					pf *= 0.3
				if rng.randf() < pf:
					start(a, b, "fight")
			"fight":
				_after_fight(e, a, b)


func _after_fight(e: Dictionary, a: Worker, b: Worker) -> void:
	last_fight = sim.minute
	sim.stats["fights"] = int(sim.stats.get("fights", 0)) + 1
	sim.training._add_rel(a, b, -20.0)
	Mood.add(sim, a, "fight")
	Mood.add(sim, b, "fight")
	for wid in e["watchers"]:
		var wt := sim.get_worker(int(wid))
		if wt:
			Mood.add(sim, wt, "saw_fight")
			if wt.task and wt.task.kind == "social":
				sim.brain.abort(wt)
	var hurt: Worker = null
	if rng.randf() < 0.25:
		hurt = b if rng.randf() < 0.5 else a
		sim.story.injure(hurt, "fight")
	for p in [a, b]:
		p.add_history(sim.day(), Nicks.gendered(L.t("Подрал{ся|ась} с %s"), p.female) % (b if p == a else a).full_name())
	var breaker := sim.get_worker(int(e["breaker"]))
	var txt := L.t("%s и %s сначала ругались, а потом сцепились прямо в цеху. Остальные бросили работу и смотрели.") % [a.full_name(), b.full_name()]
	if breaker:
		txt += " " + Nicks.gendered(L.t("Разнял{|а} %s."), breaker.female) % breaker.full_name()
	if hurt:
		txt += Nicks.gendered(L.t(" %s пострадал{|а}."), hurt.female) % hurt.full_name()
	sim.story.letter("fight", L.t("Драка в цеху"), txt, "staff", Sim.LVL_WARN,
		[{"text": L.t("Объявить выговор обоим"), "hint": L.t("Настроение у них упадёт, но порядок будет")},
		 {"text": L.t("Уволить зачинщика (%s)") % a.full_name(), "hint": L.t("Остальные запомнят")},
		 {"text": L.t("Развести по разным сменам"), "hint": L.t("Не будут видеться — не будут драться")}], 0, {"a": a.id, "b": b.id})
	sim.paper.add(L.t("Происшествия"), L.t("Кулаки вместо слов"), L.t("В цеху подрались двое. Товарищи, споры решают на собрании, а не кулаками!"))
