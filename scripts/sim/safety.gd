class_name Safety
extends RefCounted
## 1.61 «Охрана труда»: одна карточка с тремя уровнями вместо СОУТ, СИЗ, молока, инструктажа и профкомовского пункта о СИЗ.
## Уровень сам включает старые флаги и значения (milk_on, действующий инструктаж, СОУТ на всех местах, комплекты СИЗ),
## поэтому проверки, настроение и травмы работают как раньше. Платим одной строкой: ставка в месяц (игровой месяц — 14 дней) делится на дни.

const MIN := 0
const LAW := 1
const MODEL := 2
const IDS := ["min", "law", "model"]
const NAMES := ["Минимум", "По закону", "Образцово"]
const BASE := [0.0, 3000.0, 9000.0]               ## ₽ в месяц на весь завод
const PER_WORKER := [0.0, 2000.0, 4000.0]          ## ₽ в месяц на рабочего
const INJURY_K := [1.0, 1.0, 0.85]                 ## комиссия по охране труда с профкомом (сверх инструктажа −30%)
const TB_EVERY := [0, 50, 28]                      ## как часто обновляют журнал инструктажа, дней
const REMEASURE_DAYS := 112                        ## «Образцово»: СОУТ заново на всех местах раз в 8 месяцев
## Нарушения проверок, которые закрывает уровень «По закону» и выше.
const KEYS := ["no_tb", "no_sout", "no_milk", "ppe_worn"]

var sim: Sim
var level := 0
var paid_total := 0.0           ## сколько уже заплачено за охрану труда
var last_remeasure := 0


func _init(s: Sim) -> void:
	sim = s


static func level_name(l: int) -> String:
	return L.t(str(NAMES[clampi(l, 0, 2)]))


## Рабочих (без ИТР и гостей) — с них считается стоимость.
func staff_n() -> int:
	var n := 0
	for w in sim.workers:
		if not w.is_itr() and not w.visitor:
			n += 1
	return n


## Стоимость уровня в месяц при нынешнем числе рабочих.
func monthly_cost(l: int = -1, workers: int = -1) -> float:
	var lv := clampi(level if l < 0 else l, 0, 2)
	var n := staff_n() if workers < 0 else workers
	return float(BASE[lv]) + float(PER_WORKER[lv]) * float(n)


func cost_per_day(l: int = -1) -> float:
	return monthly_cost(l) / float(sim.season.dpm())


## Что уровень делает — строки для карточки: [значок, текст].
static func effects(l: int) -> Array:
	match l:
		0:
			return [
				["warn", L.t("СОУТ, молоко, СИЗ и инструктаж — на вас: проверки штрафуют за каждый пункт")],
				["mood", L.t("На вредных местах люди обижаются, что молока нет")],
				["injury", L.t("Травм как есть; без СИЗ — в полтора раза больше")]]
		1:
			return [
				["check", L.t("Все пункты трудовой инспекции закрыты сами: СОУТ, молоко, СИЗ, журнал инструктажа")],
				["mood", L.t("Молоко и доплата за вредность — люди довольны")],
				["injury", L.t("Инструктаж каждые 50 дней: травм на 30% меньше")]]
		_:
			return [
				["check", L.t("Всё из «По закону» плюс СОУТ заново раз в 8 месяцев и свежие СИЗ у всех")],
				["mood", L.t("Люди видят заботу: настроение выше")],
				["injury", L.t("Инструктаж каждые 28 дней и комиссия с профкомом: травм на 40% меньше")]]


## Старый сейв или правка вручную: по каким пунктам завод уже в порядке.
func derive() -> int:
	var places := sim.eng.workplaces()
	var sout_ok := not places.is_empty() and sim.eng.unassessed() == 0
	var items := int(sim.eng.milk_on) + int(sout_ok) + int(sim.training.tb_valid())
	var ppe_ok := not sim.eng.cabinets().is_empty() and sim.eng.without_ppe().is_empty()
	if items >= 3 and ppe_ok:
		return MODEL
	if items >= 2:
		return LAW
	return MIN


## Уровень, выведенный из старых флагов, если сейв его не знает.
func ensure() -> void:
	if level < 0:
		level = derive()
		last_remeasure = sim.day()


func set_level(l: int) -> void:
	ensure()
	var nl := clampi(l, 0, 2)
	if nl == level:
		return
	var old := level
	level = nl
	if nl < old and nl == MIN:
		sim.eng.milk_on = false   # ниже «По закону» молоко выдавать перестают
	apply()
	sim.notify(L.t("Охрана труда: уровень «%s». Расходы — %s в месяц.") % [level_name(level), Defs.money_str(monthly_cost())], Sim.LVL_INFO)


## Уровень включает старые флаги. Минимум ничего не отнимает сам: вручную выставленное (тесты, старые сейвы) остаётся.
func apply() -> void:
	ensure()
	if level < LAW:
		return
	sim.eng.milk_on = true
	var tr := sim.training
	if sim.day() - tr.tb_day >= int(TB_EVERY[level]) and not tr.tb_active():
		tr.tb_day = sim.day()
	if not sim.eng.sout_busy():
		if sim.eng.unassessed() > 0:
			sim.eng.auto_sout(false)
		elif level >= MODEL and sim.day() - last_remeasure >= REMEASURE_DAYS and not sim.eng.workplaces().is_empty():
			last_remeasure = sim.day()
			sim.eng.auto_sout(true)


## Утро: поддерживаем флаги и списываем дневную долю месячной ставки.
func morning() -> void:
	ensure()
	apply()
	if level <= MIN:
		return
	var fee := roundf(cost_per_day())
	if fee > 0.0:
		sim.spend(fee, "Охрана труда: «%s»" % level_name(level))
		paid_total += fee


func to_dict() -> Dictionary:
	return {"level": level, "paid": paid_total, "rem": last_remeasure}


func from_dict(d: Dictionary) -> void:
	level = int(d.get("level", -1))
	paid_total = float(d.get("paid", 0.0))
	last_remeasure = int(d.get("rem", sim.day()))
