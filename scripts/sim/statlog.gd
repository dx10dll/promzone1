class_name StatLog
extends RefCounted
## 1.54: дневная история для окна «Финансы → Статистика». Кольцевой буфер на 60 суток.
## Запись раз в сутки (на смене даты): {d, money, profit, made, scrap, defect, mood, staff, kwh}.

const CAP := 60

var sim: Sim
var days: Array = []         ## от старых к новым
var _made0 := 0
var _scrap0 := 0
var _earn0 := 0.0
var _spent0 := 0.0
var _last := -1              ## номер последних записанных суток


func _init(s: Sim) -> void:
	sim = s


## Закрыть сутки: вызывается после power.close_day() (киловатт-часы уже в power.hist).
func record() -> void:
	var d := sim.day() - 1
	if d <= _last:
		return
	_last = d
	var made := int(sim.stats.get("made", 0))
	var scrap := int(sim.stats.get("scrap", 0))
	var earned := float(sim.stats.get("earned", 0.0))
	var spent := float(sim.stats.get("spent", 0.0))
	var dm := maxi(0, made - _made0)
	var ds := maxi(0, scrap - _scrap0)
	var mood := 0.0
	for w in sim.workers:
		mood += w.mood
	mood = mood / float(sim.workers.size()) if not sim.workers.is_empty() else 0.0
	var kwh := 0.0
	if not sim.power.hist.is_empty():
		var h: Dictionary = sim.power.hist[0]
		kwh = float(h.get("kd", 0.0)) + float(h.get("kn", 0.0))
	days.append({"d": d, "money": sim.money, "profit": (earned - _earn0) - (spent - _spent0), "made": dm, "scrap": ds,
		"defect": float(ds) / float(maxi(1, dm + ds)), "mood": mood, "staff": sim.workers.size(), "kwh": kwh})
	_made0 = made
	_scrap0 = scrap
	_earn0 = earned
	_spent0 = spent
	while days.size() > CAP:
		days.pop_front()


## Последние n суток (0 — все).
func last(n: int) -> Array:
	if n <= 0 or days.size() <= n:
		return days
	return days.slice(days.size() - n)


## Значения одного поля за последние n суток.
func series(key: String, n: int) -> Array:
	return last(n).map(func(e: Dictionary) -> float: return float(e.get(key, 0.0)))


func to_dict() -> Dictionary:
	return {"days": days, "made0": _made0, "scrap0": _scrap0, "earn0": _earn0, "spent0": _spent0, "last": _last}


## Старый сейв без записи: пустая история, отсчёт дельт — от текущих счётчиков.
func from_dict(d: Dictionary) -> void:
	days = d.get("days", [])
	_made0 = int(d.get("made0", sim.stats.get("made", 0)))
	_scrap0 = int(d.get("scrap0", sim.stats.get("scrap", 0)))
	_earn0 = float(d.get("earn0", sim.stats.get("earned", 0.0)))
	_spent0 = float(d.get("spent0", sim.stats.get("spent", 0.0)))
	_last = int(d.get("last", sim.day() - 1))
	while days.size() > CAP:
		days.pop_front()
