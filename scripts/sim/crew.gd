class_name Crew
extends RefCounted
## Бригады и порядок (версия 1.7): график смены по 15 минут (планёрка, обед, перерывы, уборка),
## бригады с бригадирами и закреплёнными участками, соцсоревнование, несуны и служба охраны,
## профсоюз и коллективный договор, расследование несчастных случаев (акт Н-1).

const SLOT := 15.0
const SLOTS := 36                     ## 9 часов смены по 15 минут
const CODES := {"w": "work", "l": "lunch", "b": "break", "m": "meet", "c": "clean"}
const LETTERS := {"work": "w", "lunch": "l", "break": "b", "meet": "m", "clean": "c"}
const KIND_NAMES := {"work": "Работа", "lunch": "Обед", "break": "Перерыв", "meet": "Планёрка", "clean": "Уборка"}
const KIND_COLORS := {"work": "#4a5a50", "lunch": "#d9a23a", "break": "#4f9bd6", "meet": "#9a7ad0", "clean": "#6fbf6a"}
const DEFAULT := "wwwwwwwwwwwwwwwwlllwwwwwwwwwwwwwwwww"   ## обед с 4-го часа смены, 45 минут
const LEAD_PAY := 0.10                ## бригадирские к ставке
const MAX_BRIG := 8
const BRIG_COLORS := ["#e0a83a", "#4f9bd6", "#6fbf6a", "#d0607a", "#a07ad8", "#4fc0b0", "#d8803a", "#b0b4b8"]
const PRIZE := 2000.0                 ## премия каждому из бригады-победителя
const N1_DAYS := 3                    ## расследование: рабочих дней
const N1_COMP := 5                    ## компенсация пострадавшему: смен
const N1_FINE := 6000.0               ## штраф трудовой инспекции за причину по вине предприятия
const HIDE_FINE := 60000.0
const LUNCH_COMP := 120.0
const MONTH_BONUS := 1000.0
const HARM_EXTRA := 0.04
const KD_DAYS := 120                  ## срок коллективного договора
const UNION_MIN := 8                  ## рабочих, с которых возникает профсоюз

const CLAUSES := {
	"index": {"name": "Индексация зарплаты на 5%", "desc": "Сразу при подписании: ставки рабочих +5%."},
	"lunch": {"name": "Компенсация обедов — 120 ₽ за смену", "desc": "Каждому рабочему за выход на смену, вместе с зарплатой."},
	"month_bonus": {"name": "Премия по итогам месяца — 1 000 ₽", "desc": "Первого числа каждому рабочему. Нечем заплатить — нарушение."},
	"harm": {"name": "Доплата за вредность +4% сверх закона", "desc": "На местах с классом 3.1 и выше по СОУТ."},
	"ppe": {"name": "Все рабочие — в исправных СИЗ", "desc": "Профком следит за охраной труда: травм на 10% меньше. Кто-то без СИЗ два дня — нарушение."},
	"rest": {"name": "Комната отдыха с чаем", "desc": "Должна быть хотя бы одна комната отдыха."},
	"overtime": {"name": "Сверхурочные — не больше 8 дней в месяц", "desc": "Больше — нарушение договора."},
	"consent": {"name": "Увольнение — по согласованию с профкомом", "desc": "Уволить без нарушения можно только несуна. Остальные увольнения — нарушение."},
}

## Причины несчастного случая: [текст, вина предприятия].
const CAUSES := {
	"no_ppe": ["не выданы средства защиты (СИЗ)", true],
	"no_tb": ["не проведён инструктаж по охране труда", true],
	"worn": ["изношенное оборудование, пропущен ремонт", true],
	"tired": ["переутомление, нет перерывов на отдых", true],
	"rush": ["аврал, работа в спешке", true],
	"overtime": ["сверхурочная работа", true],
	"dark": ["недостаточное освещение", true],
	"dirty": ["захламлённое рабочее место", true],
	"fumes": ["загазованность, нет вентиляции", true],
	"cold": ["низкая температура в цехе", true],
	"ice": ["гололёд на территории, не посыпано", true],
	"fire": ["пожар", true],
	"drunk": ["нахождение пострадавшего в состоянии опьянения", false],
	"careless": ["нарушение инструкции самим пострадавшим", false],
}

var sim: Sim
var scheds: Dictionary = {"0": DEFAULT, "1": DEFAULT}
var brigades: Array = []      ## [{id, name, lead, cells:[[x,y]], strict, sched, wins, col}]
var _next_brig := 1
var comp_on := true           ## соцсоревнование бригад
var comp_prize := false       ## денежная премия победителю
var comp: Dictionary = {}     ## str(id бригады) -> операций за неделю
var pennant := -1             ## бригада с вымпелом
var pennant_day := -1
# охрана
var missing: Array = []       ## кражи, которые не поймали: [{day, what, n, value, wid, cam}]
var shortage_total := 0.0
var caught_total := 0
var history: Array = []       ## журнал службы охраны [{day, text}]
# профсоюз
var union: Dictionary = {}    ## {on, stance, lead, since, clauses{}, signed, offer[], talk, broken{}, worked}
var union_cd := 0
var ot_days: Dictionary = {}  ## номер месяца -> дней со сверхурочными
var ppe_bad := 0
var lunch_comp_paid := 0.0
# Н-1
var cases: Array = []         ## [{id, wid, name, prof, day, until, causes, status, verdict, fine}]
var _next_case := 1
var last_injury_day := 0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ график смены

func sched_str(shift: int, bid: int = -1) -> String:
	if bid >= 0:
		var b := brigade(bid)
		if not b.is_empty() and str(b.get("sched", "")) != "":
			return str(b["sched"])
	var s := str(scheds.get(str(shift), DEFAULT))
	return s if s.length() == SLOTS else DEFAULT


func sched_of(w: Worker) -> String:
	return sched_str(w.shift, w.brigade)


## Что по графику у работника сейчас: work / lunch / break / meet / clean.
func slot(w: Worker, m: float = -1.0) -> String:
	if m < 0.0:
		m = sim.minute
	var win := sim.shift_window(w, m)
	if m < win.x:
		return "work"
	var i := int((m - win.x) / SLOT)
	var s := sched_of(w)
	if i < 0 or i >= s.length():
		return "work"
	return str(CODES.get(s[i], "work"))


## Конец текущего блока графика (абсолютная минута).
func block_end(w: Worker, m: float = -1.0) -> float:
	if m < 0.0:
		m = sim.minute
	var win := sim.shift_window(w, m)
	var s := sched_of(w)
	var i := int((m - win.x) / SLOT)
	if i < 0 or i >= s.length():
		return m + SLOT
	var c := s[i]
	var j := i
	while j < s.length() and s[j] == c:
		j += 1
	return win.x + j * SLOT


## Общий график смены по часам дня (для верхней панели): что сейчас у первой смены.
func shift_slot_now(shift: int = 0) -> String:
	var t := sim.tod()
	var start := Defs.b("shift_start") if shift == 0 else Defs.b("shift2_start")
	var i := int((t - start) / SLOT)
	var s := sched_str(shift)
	if i < 0 or i >= s.length():
		return ""
	return str(CODES.get(s[i], "work"))


## Работнику сейчас нельзя начинать новую операцию на станке.
func stop_work(w: Worker) -> bool:
	var sl := slot(w)
	if sl == "work":
		return false
	if sl == "meet":
		return not met(w)
	return true


func met(w: Worker) -> bool:
	return float(w.get_meta("met", -1.0)) == w.shift_anchor


func set_slot(key: String, i: int, kind: String) -> void:
	var s := get_sched(key)
	if i < 0 or i >= SLOTS:
		return
	s = s.substr(0, i) + str(LETTERS.get(kind, "w")) + s.substr(i + 1)
	put_sched(key, s)


## key: "0", "1" — общий график смены; "b<id>" — свой график бригады.
func get_sched(key: String) -> String:
	if key.begins_with("b"):
		var b := brigade(int(key.substr(1)))
		if b.is_empty():
			return DEFAULT
		var own := str(b.get("sched", ""))
		return own if own != "" else sched_str(_brig_shift(int(b["id"])))
	return sched_str(int(key))


func put_sched(key: String, s: String) -> void:
	if key.begins_with("b"):
		var b := brigade(int(key.substr(1)))
		if not b.is_empty():
			b["sched"] = s
	else:
		scheds[key] = s


func reset_sched(key: String) -> void:
	if key.begins_with("b"):
		var b := brigade(int(key.substr(1)))
		if not b.is_empty():
			b["sched"] = ""
	else:
		scheds[key] = DEFAULT


## Готовые шаблоны графика.
func preset(name: String) -> String:
	match name:
		"classic":
			return DEFAULT
		"order":
			# планёрка, обед, перерыв на чай после обеда, уборка в конце
			return "mwwwwwwwwwwwwwwwllllwwwwwwbwwwwwwwcc"
		"tea":
			# планёрка, два перерыва на чай, обед, уборка
			return "mwwwwwwbwwwwwwwwlllwwwwwwbwwwwwwwwcc"
		"rush":
			# только короткий обед — всё остальное работа
			return "wwwwwwwwwwwwwwwwllwwwwwwwwwwwwwwwwww"
	return DEFAULT


func minutes(s: String, kind: String) -> int:
	return s.count(str(LETTERS.get(kind, "w"))) * int(SLOT)


func sched_problems(s: String) -> Array[String]:
	var out: Array[String] = []
	var lm := minutes(s, "lunch")
	if lm < 30:
		out.append("Обед меньше 30 минут — нарушение трудового кодекса, трудовая инспекция оштрафует")
	elif lm > 120:
		out.append("Обед больше двух часов — так нельзя по трудовому кодексу")
	if minutes(s, "work") < 360:
		out.append("Работы меньше 6 часов — выпуск заметно упадёт")
	return out


## Время слота i для смены: «8:15».
func slot_time(shift: int, i: int) -> String:
	var start := Defs.b("shift_start") if shift == 0 else Defs.b("shift2_start")
	var t := int(fmod(start + i * SLOT, 1440.0))
	return "%d:%02d" % [int(t / 60), t % 60]


## Краткое описание графика: «планёрка 8:00 · обед 12:00–12:45 · перерыв 15:00 · уборка 16:30».
func sched_text(s: String, shift: int) -> String:
	var parts: Array[String] = []
	var i := 0
	while i < s.length():
		var c := s[i]
		var j := i
		while j < s.length() and s[j] == c:
			j += 1
		if c != "w":
			var kind := str(CODES.get(c, "work"))
			parts.append("%s %s–%s" % [str(KIND_NAMES[kind]).to_lower(), slot_time(shift, i), slot_time(shift, j)])
		i = j
	return " · ".join(parts) if not parts.is_empty() else "без перерывов"


## Есть ли у кого-то из работающих график без нормального обеда.
func lunch_violation() -> bool:
	var seen := {}
	for w in sim.workers:
		var s := sched_of(w)
		if seen.has(s):
			continue
		seen[s] = true
		var lm := minutes(s, "lunch")
		if lm < 30 or lm > 120:
			return true
	return false


func on_met(w: Worker, with_lead: bool) -> void:
	w.set_meta("met", w.shift_anchor)
	w.set_meta("met_lead", with_lead)
	if with_lead:
		Mood.add(sim, w, "planerka")


func meet_point(w: Worker) -> Vector2i:
	var ld := lead_of(w.brigade)
	if ld == null or not ld.present or ld.hidden:
		ld = null
		for o in sim.workers:
			if o.present and not o.hidden and o.prof in ["foreman", "chief"]:
				ld = o
				break
	if ld and ld != w:
		return ld.cell()
	var rs := rooms_of(w.brigade)
	if not rs.is_empty():
		var r: Rooms.Room = rs[0]
		return Vector2i(int(r.center.x), int(r.center.y))
	var m: Thing = sim.things.get(w.workplace)
	if m:
		return m.cell
	return w.cell()


func meet_has_lead(w: Worker) -> bool:
	var ld := lead_of(w.brigade)
	if ld and ld.present and not ld.hidden:
		return true
	for o in sim.workers:
		if o.present and not o.hidden and o.prof in ["foreman", "chief"]:
			return true
	return false


# ================================================================ бригады

func brigade(bid: int) -> Dictionary:
	for b: Dictionary in brigades:
		if int(b["id"]) == bid:
			return b
	return {}


func members(bid: int) -> Array[Worker]:
	var out: Array[Worker] = []
	if bid < 0:
		return out
	for w in sim.workers:
		if w.brigade == bid:
			out.append(w)
	return out


func add_brigade(name: String = "") -> Dictionary:
	if brigades.size() >= MAX_BRIG:
		return {}
	var nid := _next_brig
	_next_brig += 1
	var used := {}
	for b0: Dictionary in brigades:
		used[int(b0.get("col", 0))] = true
	var col := 0
	while used.has(col) and col < BRIG_COLORS.size() - 1:
		col += 1
	var b := {"id": nid, "name": name if name != "" else "Бригада №%d" % nid, "lead": -1, "cells": [], "strict": false,
		"sched": "", "wins": 0, "col": col}
	brigades.append(b)
	return b


func remove_brigade(bid: int) -> void:
	var b := brigade(bid)
	if b.is_empty():
		return
	for w in members(bid):
		w.brigade = -1
	brigades.erase(b)
	if pennant == bid:
		pennant = -1
	comp.erase(str(bid))


func color(bid: int) -> Color:
	var b := brigade(bid)
	if b.is_empty():
		return Color("#8a9096")
	return Color(BRIG_COLORS[int(b.get("col", 0)) % BRIG_COLORS.size()])


func set_member(w: Worker, bid: int) -> void:
	if w.brigade == bid:
		return
	var old := w.brigade
	if old >= 0:
		var ob := brigade(old)
		if not ob.is_empty() and int(ob["lead"]) == w.id:
			ob["lead"] = -1
	w.brigade = bid
	if bid >= 0:
		var b := brigade(bid)
		w.add_history(sim.day(), Nicks.gendered("Переведен{|а} в «%s»", w.female) % str(b.get("name", "")))


func set_lead(bid: int, wid: int) -> void:
	var b := brigade(bid)
	if b.is_empty():
		return
	if int(b["lead"]) == wid:
		return
	b["lead"] = wid
	var w := sim.get_worker(wid)
	if w:
		if w.brigade != bid:
			w.brigade = bid
		Mood.add(sim, w, "brigadier")
		w.add_history(sim.day(), Nicks.gendered("Назначен{|а} бригадиром: «%s»", w.female) % str(b["name"]))
		Mood.refresh(sim, w)


func lead_of(bid: int) -> Worker:
	if bid < 0:
		return null
	var b := brigade(bid)
	if b.is_empty():
		return null
	var w := sim.get_worker(int(b["lead"]))
	if w and w.brigade == bid:
		return w
	return null


func is_lead(w: Worker) -> bool:
	return w.brigade >= 0 and lead_of(w.brigade) == w


func _brig_shift(bid: int) -> int:
	var n := [0, 0]
	for w in members(bid):
		n[clampi(w.shift, 0, 1)] += 1
	return 1 if n[1] > n[0] else 0


## Закрепить помещение за бригадой (или снять). Помещение у одной бригады.
func toggle_room(bid: int, r: Rooms.Room) -> void:
	var b := brigade(bid)
	if b.is_empty() or r == null or r.cells.is_empty():
		return
	var owner := room_owner(r)
	for b2: Dictionary in brigades:
		var keep: Array = []
		for cc: Array in b2["cells"]:
			if sim.rooms.room_at(Vector2i(int(cc[0]), int(cc[1]))) != r:
				keep.append(cc)
		b2["cells"] = keep
	if owner != bid:
		var c: Vector2i = r.cells[0]
		(b["cells"] as Array).append([c.x, c.y])


func rooms_of(bid: int) -> Array[Rooms.Room]:
	var out: Array[Rooms.Room] = []
	var b := brigade(bid)
	if b.is_empty():
		return out
	for cc: Array in b["cells"]:
		var r := sim.rooms.room_at(Vector2i(int(cc[0]), int(cc[1])))
		if r and not out.has(r):
			out.append(r)
	return out


func room_owner(r: Rooms.Room) -> int:
	if r == null:
		return -1
	for b: Dictionary in brigades:
		for cc: Array in b["cells"]:
			if sim.rooms.room_at(Vector2i(int(cc[0]), int(cc[1]))) == r:
				return int(b["id"])
	return -1


## 1 — станок на своём участке, -1 — на участке другой бригады, 0 — ничей.
func zone_k(w: Worker, t: Thing) -> int:
	if w.brigade < 0 or t == null:
		return 0
	var r := sim.rooms.room_of_thing(t)
	var own := room_owner(r)
	if own < 0:
		return 0
	return 1 if own == w.brigade else -1


func zone_bonus(w: Worker, t: Thing) -> float:
	if w.brigade < 0:
		return 0.0
	match zone_k(w, t):
		1:
			return 50.0
		-1:
			return -70.0
	return -15.0 if not rooms_of(w.brigade).is_empty() else 0.0


## Строго только свой участок (переключатель бригады).
func allowed(w: Worker, t: Thing) -> bool:
	if w.brigade < 0:
		return true
	var b := brigade(w.brigade)
	if b.is_empty() or not bool(b.get("strict", false)) or (b["cells"] as Array).is_empty():
		return true
	return zone_k(w, t) == 1


## Множитель скорости: бригадир рядом, вымпел, планёрка.
func speed_k(w: Worker) -> float:
	var k := 1.0
	if w.brigade >= 0:
		var ld := lead_of(w.brigade)
		if ld and ld != w and ld.present and ld.shift == w.shift:
			k += 0.02 + 0.01 * clampi(ld.grade() - 2, 0, 4)
		if pennant == w.brigade:
			k += 0.03
	if met(w):
		k += 0.03 if bool(w.get_meta("met_lead", false)) else 0.01
	return k


## Множитель оплаты смены: бригадирские, вредность по колдоговору.
func pay_k(w: Worker) -> float:
	var k := 1.0
	if is_lead(w):
		k += LEAD_PAY
	if clause_on("harm") and sim.eng.worker_class(w) > 0:
		k += HARM_EXTRA
	return k


## Надбавка к оплате смены (компенсация обедов по колдоговору).
func pay_add(w: Worker) -> float:
	if clause_on("lunch") and not w.is_itr():
		lunch_comp_paid += LUNCH_COMP
		return LUNCH_COMP
	return 0.0


func on_op(w: Worker) -> void:
	if w.brigade < 0:
		return
	var key := str(w.brigade)
	comp[key] = int(comp.get(key, 0)) + 1


## Автоматически: бригада на каждый цех со станками, люди — по своим станкам.
func auto_form() -> String:
	var shops: Array = []
	for r in sim.rooms.list:
		var n := 0
		var procs := {}
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.kind() == "machine":
				n += 1
				procs[t.process()] = int(procs.get(t.process(), 0)) + 1
		if n > 0:
			shops.append([r, n, procs])
	shops.sort_custom(func(a: Array, b: Array) -> bool: return int(a[1]) > int(b[1]))
	var staff: Array[Worker] = []
	for w in sim.workers:
		if not w.is_itr() and w.prof not in ["guard", "cleaner"]:
			staff.append(w)
	if staff.size() < 2:
		return "Мало рабочих для бригад: нужно хотя бы двое"
	for b0: Dictionary in brigades.duplicate():
		remove_brigade(int(b0["id"]))
	_next_brig = 1
	if shops.is_empty():
		var b1 := add_brigade()
		for w in staff:
			w.brigade = int(b1["id"])
		_pick_lead(int(b1["id"]))
		return ""
	var made: Array = []
	for sh: Array in shops.slice(0, MAX_BRIG):
		var r: Rooms.Room = sh[0]
		var b := add_brigade("Бригада №%d" % (made.size() + 1))
		toggle_room(int(b["id"]), r)
		made.append([b, sh[2]])
	var rest: Array[Worker] = []
	for w in staff:
		var best := -1
		var bn := 0
		for k in made.size():
			var procs: Dictionary = made[k][1]
			for p in procs.keys():
				if str(Defs.processes.get(p, {}).get("prof", "")) == w.prof and int(procs[p]) > bn:
					bn = int(procs[p])
					best = k
		if best >= 0:
			w.brigade = int((made[best][0] as Dictionary)["id"])
		else:
			rest.append(w)
	for w2 in rest:
		var small: Dictionary = made[0][0]
		for m: Array in made:
			if members(int((m[0] as Dictionary)["id"])).size() < members(int(small["id"])).size():
				small = m[0]
		w2.brigade = int(small["id"])
	for m2: Array in made.duplicate():
		var bid := int((m2[0] as Dictionary)["id"])
		if members(bid).is_empty():
			remove_brigade(bid)
		else:
			_pick_lead(bid)
	sim.notify("Бригады сформированы: %d. Бригадиры получают +10%% к ставке." % brigades.size(), Sim.LVL_GOOD)
	return ""


func _pick_lead(bid: int) -> void:
	var best: Worker = null
	var bs := -INF
	for w in members(bid):
		var s := float(w.grade()) * 2.0 + w.days_worked * 0.02
		if Mood.has_trait(w, "born_mentor") or Mood.has_trait(w, "soul"):
			s += 3.0
		if Mood.has_trait(w, "squabbler") or Mood.has_trait(w, "lazy"):
			s -= 4.0
		if w.practice_until >= 0:
			s -= 10.0
		if s > bs:
			bs = s
			best = w
	if best:
		set_lead(bid, best.id)


## Ежедневно: сплочённость бригад (отношения внутри), мысли.
func _brigade_daily() -> void:
	for b: Dictionary in brigades:
		var ms := members(int(b["id"]))
		if ms.size() < 2:
			continue
		for a in ms:
			var s := 0.0
			var n := 0
			for o in ms:
				if o == a:
					continue
				s += sim.training.rel(a, o)
				n += 1
				if o.id > a.id and o.shift == a.shift and sim.rng.randf() < 0.5:
					var dv := 1.2
					if Mood.has_trait(a, "squabbler") or Mood.has_trait(o, "squabbler"):
						dv = -1.0
					sim.training._add_rel(a, o, dv)
			if n == 0:
				continue
			var avg := s / n
			if avg >= 25.0:
				Mood.add(sim, a, "brigade_friends")
			elif avg <= -25.0:
				Mood.add(sim, a, "brigade_feud")


## Пятница: итоги соцсоревнования, инвентаризация.
func week_end() -> void:
	_competition()
	_inventory()


func _competition() -> void:
	var cands: Array = []
	for b: Dictionary in brigades:
		var n := members(int(b["id"])).size()
		var ops := int(comp.get(str(b["id"]), 0))
		if n >= 2 and ops > 0:
			cands.append([b, float(ops) / n, ops])
	comp.clear()
	if not comp_on or cands.size() < 2:
		return
	cands.sort_custom(func(a: Array, b2: Array) -> bool: return float(a[1]) > float(b2[1]))
	var win: Dictionary = cands[0][0]
	pennant = int(win["id"])
	pennant_day = sim.day()
	win["wins"] = int(win.get("wins", 0)) + 1
	sim.stats["pennants"] = int(sim.stats.get("pennants", 0)) + 1
	var ms := members(pennant)
	var has_banner := false
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "pennant":
			has_banner = true
			break
	for w in ms:
		Mood.add(sim, w, "pennant")
		if has_banner:
			Mood.add(sim, w, "pennant_banner")
	var prize := ""
	if comp_prize:
		var sum := PRIZE * ms.size()
		sim.spend(sum, "Премия бригаде-победителю соцсоревнования")
		for w2 in ms:
			Mood.add(sim, w2, "bonus")
		prize = " Премия по %s каждому." % Defs.money_str(PRIZE)
	var ld := lead_of(pennant)
	sim.notify("Соцсоревнование: вымпел недели у «%s» — %d операций на человека.%s" % [str(win["name"]), int(round(float(cands[0][1]))), prize], Sim.LVL_GOOD)
	sim.paper.add("Соцсоревнование", "Вымпел — «%s»!" % str(win["name"]),
		"По итогам недели лучшая бригада — «%s»%s: %d операций. Отстающим — равняться на передовиков!" % [str(win["name"]),
		(" бригадира %s" % ld.full_name()) if ld else "", int(cands[0][2])])


# ================================================================ охрана и несуны

func guards(present_only: bool = false) -> Array[Worker]:
	var out: Array[Worker] = []
	for w in sim.workers:
		if w.prof == "guard" and (not present_only or (w.present and not w.hidden)):
			out.append(w)
	return out


func post() -> Thing:
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "checkpoint" and not t.demolish:
			return t
	return null


func cams() -> Array[Thing]:
	var out: Array[Thing] = []
	for t in sim.things_of("camera"):
		if not t.demolish:
			out.append(t)
	return out


func cam_ok(t: Thing) -> bool:
	return t.built and sim.power.powered(t)


func cam_in_room(r: Rooms.Room) -> bool:
	if r == null:
		return false
	for t in cams():
		if cam_ok(t) and sim.rooms.space_id_at(t.cell) == r.space:
			return true   # камера видит всё помещение
	return false


func on_watch() -> bool:
	return not guards(true).is_empty()


## Шанс поймать несуна на выходе.
func detect_k() -> float:
	var p := 0.0
	for g in guards(true):
		p = maxf(p, 0.5 + 0.05 * g.skill("security") + (0.1 if post() else 0.0))
	if sim.story.guard and sim.story.has_checkpoint():
		p = maxf(p, 0.85)
	return clampf(p, 0.0, 0.95)


func steal_chance(w: Worker) -> float:
	if w.is_itr() or w.prof == "guard" or w.visitor:
		return 0.0
	var p := Mood.trait_val(w, "steal", 0.0)
	if w.mood < 30.0:
		p += 0.04
	if Mood.has_trait(w, "greedy"):
		p += 0.02
	p *= float(w.get_meta("thief_k", 1.0))
	if p <= 0.0:
		return 0.0
	if sim.story.guard and sim.story.has_checkpoint():
		p *= 0.3
	elif on_watch():
		p *= 0.6
	return p


## Уходя со смены, несун может прихватить металл со склада или расходники.
func try_steal(w: Worker) -> void:
	if w.has_meta("loot") or sim.rng.randf() >= steal_chance(w):
		return
	var mats: Array[Item] = []
	for it: Item in sim.items.values():
		if it.kind == "mat" and it.loc == Item.Loc.THING and it.reserved_by < 0:
			mats.append(it)
	var loot := {}
	if not mats.is_empty():
		var it2: Item = mats[sim.rng.randi_range(0, mats.size() - 1)]
		var holder: Thing = sim.things.get(it2.holder)
		var r := sim.rooms.room_of_thing(holder) if holder else null
		var cam := cam_in_room(r)
		if cam and sim.rng.randf() < 0.5:
			return  # побоялся камеры
		var same: Array[Item] = [it2]
		for o: Item in mats:
			if o != it2 and o.holder == it2.holder and o.def_id == it2.def_id and same.size() < sim.rng.randi_range(1, 3):
				same.append(o)
		var price := float(Defs.materials.get(it2.def_id, {}).get("price", 300))
		loot = {"what": Defs.material_name(it2.def_id), "def": it2.def_id, "kind": "mat", "n": same.size(),
			"value": price * same.size(), "cam": cam}
		for o2 in same:
			sim.delete_item(o2)
	else:
		var keys: Array = []
		for k in Defs.consumables.keys():
			if float(sim.cons.get(k, 0.0)) >= 2.0:
				keys.append(k)
		if keys.is_empty():
			return
		var ck := str(keys[sim.rng.randi_range(0, keys.size() - 1)])
		var cd: Dictionary = Defs.consumables[ck]
		sim.cons[ck] = float(sim.cons[ck]) - 1.0
		loot = {"what": str(cd.get("name", ck)).to_lower(), "def": ck, "kind": "cons", "n": 1,
			"value": float(cd.get("price", 1000)) / maxf(1.0, float(cd.get("units", 1))), "cam": false}
	w.set_meta("loot", loot)


## Человек выходит за проходную: досмотр.
func on_exit(w: Worker) -> void:
	if not w.has_meta("loot"):
		return
	var lt: Dictionary = w.get_meta("loot")
	w.remove_meta("loot")
	if sim.rng.randf() < detect_k():
		_caught(w, lt, false)
		return
	missing.append({"day": sim.day(), "what": str(lt["what"]), "n": int(lt["n"]), "value": float(lt["value"]),
		"wid": w.id, "cam": bool(lt.get("cam", false))})
	shortage_total += float(lt["value"])
	sim.stats["stolen"] = int(sim.stats.get("stolen", 0)) + int(lt["n"])
	Nicks.count(w, "steal")


func _restore(lt: Dictionary) -> void:
	if str(lt.get("kind", "mat")) == "cons":
		var ck := str(lt["def"])
		sim.cons[ck] = float(sim.cons.get(ck, 0.0)) + float(lt["n"])
		return
	for i in int(lt["n"]):
		var it := sim.new_item("mat", str(lt["def"]), "ok")
		var placed := false
		for t: Thing in sim.things.values():
			if t.built and t.kind() == "storage" and not t.demolish and sim.free_space(t, 0, it.stack_key()) > 0:
				sim.put_in_thing(it, t, 0)
				placed = true
				break
		if not placed:
			var cp := post()
			var c := cp.cell + Vector2i(0, -1) if cp else Vector2i(sim.world.plot.get_center())
			sim.put_on_ground(it, c)


func _caught(w: Worker, lt: Dictionary, by_cam: bool) -> void:
	if not by_cam:
		_restore(lt)
	caught_total += 1
	sim.stats["thieves_caught"] = int(sim.stats.get("thieves_caught", 0)) + 1
	var g: Worker = null
	var gs := guards(true)
	if not gs.is_empty():
		g = gs[0]
		g.week_score += 3
	var what := "%s (%d шт.)" % [str(lt["what"]), int(lt["n"])] if str(lt.get("kind", "")) == "mat" else str(lt["what"])
	var text := ""
	if by_cam:
		text = Nicks.gendered("На записи камеры видно, как %s выносит со склада %s. Вещи уже не вернуть, но человек известен.", w.female) % [w.full_name(), what]
	else:
		text = Nicks.gendered("На проходной у %s нашли %s. %s", w.female) % [w.full_name(), what,
			("Задержал охранник %s, металл вернули на склад." % g.full_name()) if g else "Досмотр сделал своё дело, металл вернули на склад."]
	text += "\nЧто будем делать?"
	w.add_history(sim.day(), Nicks.gendered("Пойман{|а} на краже: %s", w.female) % what)
	w.set_meta("caught_theft", int(w.get_meta("caught_theft", 0)) + 1)
	_log(Nicks.gendered("Задержан{|а} %s: %s%s", w.female) % [w.full_name(), what, " (по записи камеры)" if by_cam else ""])
	sim.story.letter("thief", "Задержан несун" if not by_cam else "Камера записала кражу", text, "thief", Sim.LVL_WARN, [
		{"text": "Выговор", "hint": "Запишем в личное дело. Попадётся снова — разговор будет другой"},
		{"text": "Лишить премии (−3 000 ₽)", "hint": "Вычтем из зарплаты за неделю"},
		{"text": "Уволить по статье", "hint": "Честные одобрят, друзья обидятся"},
		{"text": "Простить", "hint": "Станет смелее — украдёт снова"}], 0, {"wid": w.id})


func _res_thief(d: Dictionary, choice: int) -> void:
	var w := sim.get_worker(int(d.get("wid", -1)))
	if w == null:
		return
	match choice:
		0:
			Mood.add(sim, w, "reprimand")
			w.set_meta("thief_k", float(w.get_meta("thief_k", 1.0)) * 0.7)
			w.add_history(sim.day(), "Выговор за кражу")
		1:
			var due := float(w.get_meta("wage_due", 0.0))
			w.set_meta("wage_due", maxf(0.0, due - 3000.0))
			Mood.add(sim, w, "fined")
			w.set_meta("thief_k", float(w.get_meta("thief_k", 1.0)) * 0.5)
			w.add_history(sim.day(), "Лишён премии за кражу" if not w.female else "Лишена премии за кражу")
		2:
			w.set_meta("fire_reason", "theft")
			for o in sim.workers:
				if o == w:
					continue
				if sim.training.rel(o, w) >= 30.0:
					Mood.add(sim, o, "friend_fired_article")
				elif not Mood.has_trait(o, "thief"):
					Mood.add(sim, o, "thief_fired")
			sim.fire(w)
			_log("%s уволен по статье за кражу" % w.full_name())
		3:
			Mood.add(sim, w, "forgiven")
			w.set_meta("thief_k", float(w.get_meta("thief_k", 1.0)) * 1.5)


## Инвентаризация по пятницам: недостача, записи камер.
func _inventory() -> void:
	if missing.is_empty():
		return
	var total := 0.0
	var parts: Array[String] = []
	var seen_cam: Array = []
	for m: Dictionary in missing:
		total += float(m["value"])
		parts.append("%s ×%d" % [str(m["what"]), int(m["n"])])
		if bool(m.get("cam", false)):
			seen_cam.append(m)
	missing.clear()
	_log("Инвентаризация: недостача %s" % Defs.money_str(total))
	var who := ""
	if not seen_cam.is_empty():
		var m0: Dictionary = seen_cam[0]
		var w := sim.get_worker(int(m0["wid"]))
		if w:
			_caught(w, {"what": m0["what"], "n": m0["n"], "kind": "mat"}, true)
			who = " Запись с камеры выдала одного из несунов."
	sim.notify("Инвентаризация: недостача на %s — %s.%s%s" % [Defs.money_str(total), ", ".join(PackedStringArray(parts.slice(0, 4))), who,
		"" if on_watch() or (sim.story.guard and sim.story.has_checkpoint()) else " Наймите охранника на проходную и поставьте камеры на склад."], Sim.LVL_WARN)
	sim.paper.add("Происшествия", "Недостача на складе", "Инвентаризация показала недостачу на %s. Товарищи, металл — не дачный забор!" % Defs.money_str(total))


## Посторонние лезут на склад (событие «кража»): охрана и камеры могут спугнуть.
func stop_outside_theft() -> bool:
	var p := 0.0
	if on_watch():
		p = 0.7
	for t in cams():
		if cam_ok(t):
			var r := sim.rooms.room_at(t.cell)
			if r and r.type == "storage":
				p += 0.2
				break
	if sim.rng.randf() < p:
		sim.story.info("Охрана спугнула вора", "Чужой лез через забор к складу, но охранник%s заметил его вовремя. Металл на месте." % (" по камере" if not on_watch() else ""), "thief", Sim.LVL_GOOD)
		_log("Спугнули постороннего у склада")
		return true
	return false


## Охрана на проходной отбивает охоту проносить спиртное.
func booze_k() -> float:
	if on_watch() or (sim.story.guard and sim.story.has_checkpoint()):
		return 0.5
	return 1.0


func _log(text: String) -> void:
	history.push_front({"day": sim.day(), "date": sim.date_str(), "text": text})
	if history.size() > 30:
		history.resize(30)


# ================================================================ профсоюз

func union_on() -> bool:
	return bool(union.get("on", false))


func union_lead() -> Worker:
	if not union_on():
		return null
	return sim.get_worker(int(union.get("lead", -1)))


func clause_on(k: String) -> bool:
	return union_on() and (union.get("clauses", {}) as Dictionary).has(k) and signed()


func signed() -> bool:
	return union_on() and int(union.get("signed", -1)) >= 0 and sim.day() < int(union.get("signed", -1)) + KD_DAYS


func union_office() -> Rooms.Room:
	var rs := sim.rooms.of_type("union_office")
	return rs[0] if not rs.is_empty() else null


func _staff_n() -> int:
	var n := 0
	for w in sim.workers:
		if not w.is_itr() and w.practice_until < 0:
			n += 1
	return n


func _union_check() -> void:
	if union_on():
		_union_daily()
		return
	if sim.day() < union_cd or _staff_n() < UNION_MIN or sim.day() < 15:
		return
	var p := 0.03
	var lead: Worker = null
	var s := 0.0
	var n := 0
	for w in sim.workers:
		if w.is_itr():
			continue
		s += w.mood
		n += 1
		if Mood.has_trait(w, "activist"):
			p += 0.06
			lead = w
	if n > 0 and s / n < 45.0:
		p += 0.04
	if sim.rng.randf() >= p:
		return
	union_cd = sim.day() + 30
	if lead == null:
		for w2 in sim.workers:
			if not w2.is_itr() and (lead == null or w2.days_worked > lead.days_worked):
				lead = w2
	if lead == null:
		return
	sim.story.letter("union_form", "Рабочие создают профсоюз",
		Nicks.gendered("%s собрал{|а} подписи: коллектив хочет создать первичную профсоюзную организацию. Профком будет вести переговоры о коллективном договоре, следить за охраной труда и заранее предупреждать о забастовках. Нужна комната под профком (стол и доска объявлений).", lead.female) % lead.full_name(),
		"handshake", Sim.LVL_INFO, [
			{"text": "Поддержать", "hint": "Люди оценят. Через пару дней профком предложит колдоговор"},
			{"text": "Не мешать", "hint": "Профсоюз будет, но без особой теплоты"},
			{"text": "Отговорить", "hint": "Обидятся; могут пожаловаться в трудовую инспекцию"}], 0, {"lead": lead.id})


func _res_union_form(d: Dictionary, choice: int) -> void:
	var lead := int(d.get("lead", -1))
	match choice:
		0, 1:
			union = {"on": true, "stance": "support" if choice == 0 else "neutral", "lead": lead, "since": sim.day(),
				"clauses": {}, "signed": -1, "offer": [], "talk": sim.day() + (2 if choice == 0 else 5), "broken": {}, "worked": -1}
			if choice == 0:
				for w in sim.workers:
					if not w.is_itr():
						Mood.add(sim, w, "union_ok")
			var lw := sim.get_worker(lead)
			if lw:
				lw.add_history(sim.day(), Nicks.gendered("Избран{|а} председателем профкома", lw.female))
			sim.notify("Создан профсоюз. Председатель профкома — %s. Вкладка «Бригады → Профсоюз»." % (lw.full_name() if lw else "—"), Sim.LVL_GOOD)
			sim.paper.add("Профсоюзная жизнь", "У нас есть профком!", "Создана первичная профсоюзная организация. Взносы — 1%% от зарплаты, путёвки и материальная помощь — по заявлениям. Председатель — %s." % (lw.full_name() if lw else "—"))
		2:
			union_cd = sim.day() + 45
			for w in sim.workers:
				if not w.is_itr():
					Mood.add(sim, w, "union_denied")
			if sim.rng.randf() < 0.4:
				sim.inspect.schedule("labor", sim.minute + sim.rng.randf_range(2.0, 6.0) * 1440.0, false, "жалоба рабочих")
				sim.notify("Рабочие пожаловались в трудовую инспекцию: препятствуют созданию профсоюза.", Sim.LVL_BAD)


func _union_daily() -> void:
	var lw := union_lead()
	if lw == null or not sim.workers.has(lw):
		_new_union_lead()
	# переговоры о колдоговоре
	if (union.get("offer", []) as Array).is_empty() and not signed() and sim.day() >= int(union.get("talk", 0)):
		var keys: Array = CLAUSES.keys()
		var offer: Array = []
		var pool := keys.duplicate()
		for i in 4:
			if pool.is_empty():
				break
			var k := str(pool[sim.rng.randi_range(0, pool.size() - 1)])
			pool.erase(k)
			offer.append(k)
		union["offer"] = offer
		union["offer_day"] = sim.day()
		var names: Array[String] = []
		for k2 in offer:
			names.append("• " + str(CLAUSES[k2]["name"]))
		sim.story.info("Профком предлагает колдоговор",
			"Профком подготовил проект коллективного договора:\n%s\nОтметьте пункты, на которые согласны, и подпишите во вкладке «Бригады → Профсоюз». Чем больше пунктов — тем довольнее люди." % "\n".join(PackedStringArray(names)),
			"handshake", Sim.LVL_INFO, Vector2i(-1, -1), true)
	elif not (union.get("offer", []) as Array).is_empty() and sim.day() == int(union.get("offer_day", 0)) + 10:
		sim.notify("Профком ждёт подписи колдоговора уже десять дней. Люди начинают роптать.", Sim.LVL_WARN)
		union["stance"] = "angry" if str(union.get("stance", "")) != "support" else "neutral"
	# соблюдение колдоговора
	if signed():
		var bad := ""
		if clause_on("ppe"):
			ppe_bad = ppe_bad + 1 if not sim.eng.without_ppe().is_empty() else 0
			if ppe_bad >= 2:
				bad = "ppe"
				ppe_bad = 0
		if clause_on("rest") and sim.rooms.of_type("restroom").is_empty():
			bad = "rest"
		if clause_on("overtime") and int(ot_days.get(str(sim.season.month_abs()), 0)) > 8 and not (union["broken"] as Dictionary).has("overtime%d" % sim.season.month_abs()):
			bad = "overtime"
			(union["broken"] as Dictionary)["overtime%d" % sim.season.month_abs()] = sim.day()
		if clause_on("month_bonus") and sim.season.dom() == 1:
			var n := _staff_n()
			if sim.money >= MONTH_BONUS * n:
				sim.spend(MONTH_BONUS * n, "Премия по итогам месяца (колдоговор)")
				for w in sim.workers:
					if not w.is_itr():
						Mood.add(sim, w, "bonus")
			else:
				bad = "month_bonus"
		if bad != "":
			_break_clause(bad)
		elif sim.day() - int(union.get("last_broken", -999)) > 14:
			for w2 in sim.workers:
				if not w2.is_itr():
					Mood.add(sim, w2, "kd_kept")
					if clause_on("lunch"):
						Mood.add(sim, w2, "kd_lunch")
	elif int(union.get("signed", -1)) >= 0 and sim.day() == int(union["signed"]) + KD_DAYS:
		union["talk"] = sim.day() + 1
		union["clauses"] = {}
		sim.notify("Срок колдоговора истёк — профком готовит новый.", Sim.LVL_INFO)


func _break_clause(k: String) -> void:
	union["last_broken"] = sim.day()
	(union["broken"] as Dictionary)[k] = sim.day()
	union["stance"] = "angry"
	for w in sim.workers:
		if not w.is_itr():
			Mood.add(sim, w, "kd_broken")
	sim.story.info("Нарушен колдоговор", "Профком фиксирует нарушение: «%s». Люди недовольны, до забастовки теперь ближе." % str(CLAUSES[k]["name"]),
		"strike", Sim.LVL_BAD)


## Профком по инициативе завода (Развитие → «Профком»): сразу «поддержка», председатель — самый опытный.
func found_union() -> void:
	if union_on():
		return
	var best: Worker = null
	for w in sim.workers:
		if w.is_itr():
			continue
		if best == null or (Mood.has_trait(w, "activist") and not Mood.has_trait(best, "activist")) or w.days_worked > best.days_worked:
			best = w
	_res_union_form({"lead": best.id if best else -1}, 0)


func _new_union_lead() -> void:
	var best: Worker = null
	for w in sim.workers:
		if w.is_itr():
			continue
		if best == null or (Mood.has_trait(w, "activist") and not Mood.has_trait(best, "activist")) or w.days_worked > best.days_worked:
			best = w
	union["lead"] = best.id if best else -1
	if best:
		sim.notify("Новый председатель профкома — %s." % best.full_name(), Sim.LVL_INFO)


## Подписать колдоговор с выбранными пунктами.
func sign(selected: Array) -> String:
	if not union_on():
		return "Профсоюза нет"
	var offer: Array = union.get("offer", [])
	if offer.is_empty():
		return "Профком пока не предлагал договор"
	var cl := {}
	for k in selected:
		if offer.has(k):
			cl[str(k)] = true
	union["clauses"] = cl
	union["signed"] = sim.day()
	union["offer"] = []
	union["broken"] = {}
	union["last_broken"] = -999
	if cl.has("index"):
		for w in sim.workers:
			if not w.is_itr():
				sim.change_wage(w, 0.05)
	var happy := cl.size() >= 3
	union["stance"] = "support" if happy else ("neutral" if cl.size() >= 2 else "angry")
	sim.stats["union_deal"] = int(sim.stats.get("union_deal", 0)) + 1
	for w2 in sim.workers:
		if not w2.is_itr():
			Mood.add(sim, w2, "kd_kept" if happy else "kd_broken")
	sim.notify("Коллективный договор подписан: %d %s из %d. %s" % [cl.size(), Defs.plural(cl.size(), "пункт", "пункта", "пунктов"), offer.size(),
		"Профком доволен." if happy else "Профком недоволен: мало пунктов."], Sim.LVL_GOOD if happy else Sim.LVL_WARN)
	sim.paper.add("Профсоюзная жизнь", "Подписан коллективный договор", "Администрация и профком подписали коллективный договор на %d дней: %d %s." % [KD_DAYS, cl.size(), Defs.plural(cl.size(), "пункт", "пункта", "пунктов")])
	return ""


## Дополнительные дни терпения до забастовки, которые даёт профком.
func strike_patience() -> int:
	if not union_on():
		return 0
	var n := 0
	match str(union.get("stance", "")):
		"support":
			n += 1
		"angry":
			n -= 1
	if signed() and sim.day() - int(union.get("last_broken", -999)) > 14:
		n += 1
	if sim.day() - int(union.get("worked", -99)) <= 7:
		n += 1
	return n


## Профком предупреждает о забастовке заранее.
func strike_warning(avg: float) -> bool:
	if not union_on() or str(union.get("stance", "")) == "angry":
		return false
	if sim.day() - int(union.get("warned", -99)) < 5:
		return false
	union["warned"] = sim.day()
	var lw := union_lead()
	sim.story.letter("union_warn", "Профком предупреждает о забастовке",
		"%s от имени профкома: настроение в коллективе %d из 100, люди готовы бросить станки. Профком просит принять меры — иначе через пару дней забастовка." % [lw.full_name() if lw else "Председатель профкома", int(avg)],
		"strike", Sim.LVL_BAD, [
			{"text": "Премия всем", "hint": "%s каждому" % Defs.money_str(Defs.b("bonus_amount"))},
			{"text": "Собрание с профкомом", "hint": "Выслушать людей: отсрочит забастовку на пару дней"},
			{"text": "Ничего не делать", "hint": ""}], 1)
	return true


func _res_union_warn(choice: int) -> void:
	match choice:
		0:
			var err := sim.bonus_all()
			if err != "":
				sim.notify(err, Sim.LVL_WARN)
			sim.story.low_mood_days = 0
		1:
			sim.story.low_mood_days = maxi(0, sim.story.low_mood_days - 2)
			for w in sim.workers:
				if not w.is_itr():
					Mood.add(sim, w, "union_heard")


func wants_union_work(w: Worker) -> bool:
	if not union_on() or int(union.get("lead", -1)) != w.id or union_office() == null:
		return false
	return int(w.get_meta("union_day", -1)) != sim.day() and sim.rng.randf() < 0.08


func union_worked(w: Worker) -> void:
	w.set_meta("union_day", sim.day())
	union["worked"] = sim.day()


## Увольнение: колдоговор «по согласованию с профкомом».
func on_fire(w: Worker, quit: bool) -> void:
	var reason := str(w.get_meta("fire_reason", ""))
	if not quit and reason != "theft" and clause_on("consent") and not w.is_itr():
		_break_clause("consent")


## Работник ушёл: бригада, профком.
func on_leave(w: Worker) -> void:
	if w.brigade >= 0:
		var b := brigade(w.brigade)
		if not b.is_empty() and int(b["lead"]) == w.id:
			b["lead"] = -1
			sim.notify("«%s» осталась без бригадира — назначьте нового." % str(b["name"]), Sim.LVL_WARN)
	if union_on() and int(union.get("lead", -1)) == w.id:
		union["lead"] = -1


# ================================================================ несчастные случаи, акт Н-1

func on_injury(w: Worker, cause: String) -> void:
	last_injury_day = sim.day()
	if cause == "fight":
		return
	var causes := _causes(w, cause)
	var c := {"id": _next_case, "wid": w.id, "name": w.full_name(), "prof": w.prof_name(), "day": sim.day(),
		"until": sim.to_work_time(sim.minute + N1_DAYS * 1440.0), "causes": causes, "status": "open", "verdict": "", "fine": 0.0,
		"cause": cause}
	_next_case += 1
	cases.push_front(c)
	if cases.size() > 30:
		cases.resize(30)
	if union_on():
		Mood.add(sim, w, "union_help")
	sim.notify("Начато расследование несчастного случая с %s: комиссия составит акт Н-1 за %d рабочих дня." % [w.full_name(), N1_DAYS], Sim.LVL_INFO)


func _causes(w: Worker, cause: String) -> Array:
	var out: Array = []
	var m: Thing = sim.things.get(w.workplace)
	if w.ppe <= 0.0:
		out.append("no_ppe")
	if not sim.training.tb_valid():
		out.append("no_tb")
	if m and m.kind() == "machine" and m.condition < 35.0:
		out.append("worn")
	if float(w.needs.get("rest", 100.0)) < 25.0:
		out.append("tired")
	if sim.office.rush_on() or sim.story.has_mod("rush"):
		out.append("rush")
	if sim.office.overtime_on():
		out.append("overtime")
	if not sim.rooms.is_lit(w.cell()):
		out.append("dark")
	var r := sim.rooms.room_at(w.cell())
	if r and sim.upkeep.room_dirt(r) > 60.0:
		out.append("dirty")
	if r and sim.eng.fumes_of(r) >= Eng.SMOKY:
		out.append("fumes")
	if sim.season.work_k(w) < 0.9:
		out.append("cold")
	if cause == "slip":
		out.append("ice")
	if cause == "burn":
		out.append("fire")
	if Mood.has_trait(w, "drinker") and sim.weekday() == 0:
		out.append("drunk")
	if out.is_empty():
		out.append("careless")
	return out


func employer_causes(c: Dictionary) -> int:
	var n := 0
	for k in c["causes"]:
		if bool((CAUSES.get(str(k), ["", false]) as Array)[1]):
			n += 1
	return n


func cause_text(k: String) -> String:
	return str((CAUSES.get(k, [k, false]) as Array)[0])


func _case(id: int) -> Dictionary:
	for c: Dictionary in cases:
		if int(c["id"]) == id:
			return c
	return {}


func _cases_tick() -> void:
	for c: Dictionary in cases:
		if str(c["status"]) == "open" and sim.minute >= float(c["until"]):
			c["status"] = "act"
			_act_letter(c)


func _act_letter(c: Dictionary) -> void:
	var lines: Array[String] = []
	for k in c["causes"]:
		lines.append("• " + cause_text(str(k)))
	var emp := employer_causes(c)
	var who := "директор, мастер"
	if union_on():
		who += ", председатель профкома"
	var comp := 0.0
	var w := sim.get_worker(int(c["wid"]))
	if w and emp > 0:
		comp = float(w.wage) * N1_COMP
	sim.story.letter("n1", "Акт Н-1: %s" % str(c["name"]),
		"Комиссия (%s) расследовала несчастный случай: %s, %s. Причины:\n%s\nПо вине предприятия: %d, по вине пострадавшего: %d." % [who, str(c["name"]), str(c["prof"]).to_lower(),
		"\n".join(PackedStringArray(lines)), emp, c["causes"].size() - emp],
		"injury", Sim.LVL_WARN, [
			{"text": "Подписать акт как есть", "hint": ("Компенсация пострадавшему %s и штраф инспекции %s" % [Defs.money_str(comp), Defs.money_str(N1_FINE * emp)]) if emp > 0 else "Вина самого пострадавшего — без компенсации"},
			{"text": "Записать вину на пострадавшего", "hint": "Дешевле, но люди это запомнят%s" % (", а профком обжалует" if union_on() else "")},
			{"text": "Не оформлять акт", "hint": "Если всплывёт на проверке — штраф %s" % Defs.money_str(HIDE_FINE)}], 0, {"case": int(c["id"])})


func _res_n1(d: Dictionary, choice: int) -> void:
	var c := _case(int(d.get("case", -1)))
	if c.is_empty():
		return
	var w := sim.get_worker(int(c["wid"]))
	var emp := employer_causes(c)
	var fine := 0.0
	match choice:
		0:
			if emp > 0:
				var comp := float(w.wage) * N1_COMP if w else 0.0
				if comp > 0.0:
					sim.spend(comp, "Компенсация пострадавшему по акту Н-1")
					sim.market.claim("accident", comp, "компенсация по акту Н-1")
				fine = N1_FINE * emp * (0.5 if sim.office.active("safety") else 1.0)
				sim.spend(fine, "Штраф трудовой инспекции по акту Н-1")
				if w:
					Mood.add(sim, w, "n1_fair")
				c["verdict"] = "вина предприятия"
			else:
				c["verdict"] = "вина пострадавшего"
				if w:
					Mood.add(sim, w, "reprimand")
		1:
			c["verdict"] = "записали на пострадавшего"
			if emp > 0:
				for o in sim.workers:
					if not o.is_itr():
						Mood.add(sim, o, "n1_blame")
				if union_on() or sim.rng.randf() < 0.35:
					fine = N1_FINE * 2.0 * emp
					sim.spend(fine, "Штраф: акт Н-1 обжалован")
					sim.notify("Акт Н-1 обжалован%s: трудовая инспекция пересмотрела причины и оштрафовала завод на %s." % [" профкомом" if union_on() else " пострадавшим", Defs.money_str(fine)], Sim.LVL_BAD)
					c["verdict"] = "обжалован, вина предприятия"
			elif w:
				Mood.add(sim, w, "reprimand")
		2:
			c["status"] = "hidden"
			c["verdict"] = "не оформлен"
			for o2 in sim.workers:
				if not o2.is_itr():
					Mood.add(sim, o2, "n1_hidden")
			if union_on() and sim.rng.randf() < 0.6:
				sim.inspect.schedule("labor", sim.minute + sim.rng.randf_range(2.0, 5.0) * 1440.0, false, "сигнал профкома о сокрытии травмы")
			return
	c["status"] = "done"
	c["fine"] = fine


## Скрытые несчастные случаи за последние 60 дней (их находит трудовая инспекция).
func hidden_cases() -> int:
	var n := 0
	for c: Dictionary in cases:
		if str(c["status"]) == "hidden" and sim.day() - int(c["day"]) <= 60:
			n += 1
	return n


## Инспекция нашла сокрытие: штраф и пометка.
func on_hidden_found() -> void:
	for c: Dictionary in cases:
		if str(c["status"]) == "hidden":
			c["status"] = "done"
			c["verdict"] = "сокрытие выявлено"
			c["fine"] = HIDE_FINE
	sim.reputation = maxf(0.0, sim.reputation - 5.0)


func open_cases() -> int:
	var n := 0
	for c: Dictionary in cases:
		if str(c["status"]) in ["open", "act"]:
			n += 1
	return n


func safe_days() -> int:
	return sim.day() - maxi(last_injury_day, 0) if last_injury_day > 0 else sim.day() - 1


## Множитель шанса травмы: табло «Дней без травм» в помещении, профком по колдоговору.
func injury_k(w: Worker) -> float:
	var k := 1.0
	var r := sim.rooms.room_at(w.cell())
	if r:
		for tid in r.things:
			var t: Thing = sim.things.get(tid)
			if t and t.def_id == "days_board":
				k *= 0.95
				break
	if clause_on("ppe"):
		k *= 0.9
	return k


# ================================================================ письма, утро, сохранение

func on_letter(ev: String, d: Dictionary, choice: int) -> void:
	match ev:
		"thief":
			_res_thief(d, choice)
		"union_form":
			_res_union_form(d, choice)
		"union_warn":
			_res_union_warn(choice)
		"n1":
			_res_n1(d, choice)


func morning() -> void:
	sim.stats["safe_days"] = maxi(int(sim.stats.get("safe_days", 0)), safe_days())
	_cases_tick()
	if sim.office.overtime_on() and sim.is_workday():
		var mk := str(sim.season.month_abs())
		ot_days[mk] = int(ot_days.get(mk, 0)) + 1
	if not sim.story.enabled:
		return
	_union_check()
	if sim.is_workday():
		_brigade_daily()
		if lunch_violation():
			sim.notify_once("no_lunch_sched", "В графике смены обед меньше 30 минут (или больше двух часов): это нарушение трудового кодекса. Поправьте во вкладке «Бригады → График смены».", Sim.LVL_WARN, Vector2i(-1, -1), 2880.0)
		if pennant >= 0 and sim.day() - pennant_day > 7:
			pennant = -1


## Подсказки о бригадах для подросшего завода.
func hints() -> void:
	var n := 0
	for w in sim.workers:
		if not w.is_itr():
			n += 1
	if n >= 8 and brigades.is_empty():
		sim.notify_once("brig_hint", "Рабочих уже %d. Разбейте их на бригады с бригадирами и закрепите за участками — меньше беготни, бригадир ускоряет работу (раздел «Люди → Бригады», клавиша K)." % n, Sim.LVL_INFO, Vector2i(-1, -1), 10080.0)


func to_dict() -> Dictionary:
	return {"scheds": scheds, "brig": brigades, "nb": _next_brig, "comp_on": comp_on, "comp_prize": comp_prize, "comp": comp,
		"pennant": pennant, "pday": pennant_day, "missing": missing, "short": shortage_total, "caught": caught_total,
		"hist": history, "union": union, "ucd": union_cd, "ot": ot_days, "ppe_bad": ppe_bad, "cases": cases, "nc": _next_case,
		"lid": last_injury_day, "lcomp": lunch_comp_paid}


func from_dict(d: Dictionary) -> void:
	var sc: Dictionary = d.get("scheds", {})
	for k in ["0", "1"]:
		var s := str(sc.get(k, DEFAULT))
		scheds[k] = s if s.length() == SLOTS else DEFAULT
	brigades = d.get("brig", [])
	for b: Dictionary in brigades:
		b["id"] = int(b["id"])
		b["lead"] = int(b.get("lead", -1))
		b["col"] = int(b.get("col", 0))
		b["wins"] = int(b.get("wins", 0))
		if not b.has("cells"):
			b["cells"] = []
	_next_brig = int(d.get("nb", brigades.size() + 1))
	comp_on = bool(d.get("comp_on", true))
	comp_prize = bool(d.get("comp_prize", false))
	comp = d.get("comp", {})
	pennant = int(d.get("pennant", -1))
	pennant_day = int(d.get("pday", -1))
	missing = d.get("missing", [])
	shortage_total = float(d.get("short", 0.0))
	caught_total = int(d.get("caught", 0))
	history = d.get("hist", [])
	union = d.get("union", {})
	if union.has("lead"):
		union["lead"] = int(union["lead"])
	if union.has("signed"):
		union["signed"] = int(union["signed"])
	union_cd = int(d.get("ucd", 0))
	ot_days = d.get("ot", {})
	ppe_bad = int(d.get("ppe_bad", 0))
	cases = d.get("cases", [])
	for c: Dictionary in cases:
		c["id"] = int(c["id"])
		c["wid"] = int(c["wid"])
		c["day"] = int(c["day"])
	_next_case = int(d.get("nc", cases.size() + 1))
	last_injury_day = int(d.get("lid", 0))
	lunch_comp_paid = float(d.get("lcomp", 0.0))
