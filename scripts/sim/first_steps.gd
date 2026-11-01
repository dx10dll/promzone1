class_name FirstSteps
extends RefCounted
## 1.66: «Первые шаги» — цепочка из семи заданий первого часа с небольшими наградами (карточка в списке «Что делать»)
## и показ экрана «Ваша задача» перед первой игрой. Цепочка идёт по состоянию завода (не по событиям), поэтому
## старое сохранение сразу отмечает уже пройденное. Включается только из игровой сцены (begin / adopt_old):
## завод, созданный в тестах и замерах, цепочки не имеет и деньги не получает.

const MODE_NONE := ""        ## не решено — цепочка молчит
const MODE_ON := "on"
const MODE_DONE := "done"    ## пройдена, песочница или выключена совсем
const OLD_ROOMS := 6         ## сколько помещений у гаража и поля на старте (цех, кабинет, столовая, техпомещение, туалет, бытовка)

## id, текст, подсказка, где открыть, награда [вид, сумма], реплика главного инженера.
const STEPS := [
	{"id": "order", "text": "Взять новый заказ", "tip": "Откройте «Заказы» и примите свежую заявку клиента.", "go": "orders",
		"reward": ["money", 3000], "say": "Первый новый заказ взят: так держать! Следите, чтобы хватало металла и станок не простаивал."},
	{"id": "qc", "text": "Сделать деталь и сдать её ОТК", "tip": "Станочник точит деталь, контролёр проверяет её: годная идёт на поддон, брак — в тару.", "go": "orders",
		"reward": ["money", 5000], "say": "Первая годная деталь прошла ОТК. Цех работает, теперь главное — держать качество."},
	{"id": "ship", "text": "Отгрузить заказ клиенту", "tip": "Готовую партию несут в зону отгрузки, приезжает машина — после погрузки приходят деньги.", "go": "orders",
		"reward": ["money", 10000], "say": "Заказ ушёл к клиенту, деньги на счёте. Так и живёт завод: заказ, деталь, отгрузка, деньги."},
	{"id": "hire", "text": "Нанять человека", "tip": "«Люди» → «Найм»: выберите профессию, потом человека — и «Нанять».", "go": "people",
		"reward": ["rep", 1], "say": "Новый человек в команде. Не забудьте про зарплату по пятницам: задержка быстро бьёт по настроению."},
	{"id": "build", "text": "Построить новое помещение", "tip": "«Стройка» → «Готовые помещения»: склад, кабинет или раздевалка. Строители всё сделают сами.", "go": "build",
		"reward": ["money", 5000], "say": "Завод растёт вширь. Следите, чтобы в новом помещении хватало тока и всего нужного."},
	{"id": "orders3", "text": "Выполнить три заказа", "tip": "Каждый отгруженный заказ приносит деньги и репутацию. Срок сорвёте — клиент снизит оплату.", "go": "orders",
		"reward": ["rep", 2], "say": "Три заказа выполнено. Это уже не случайность, а производство."},
	{"id": "week", "text": "Закончить неделю в плюсе", "tip": "Выручка за неделю должна быть больше расходов: зарплаты, металл, налоги, энергия. Итоги — «Финансы».", "go": "finance",
		"reward": ["money", 20000], "say": "Неделя в плюсе. Это главный признак, что дело пойдёт. Теперь цели этапа — «Цели» вверху."},
]

var sim: Sim
var mode := MODE_NONE
var enabled := true                   ## выставляет игровая сцена из настроек
var done: Array = []                  ## id выполненных заданий
var base_orders := 0                  ## сколько заказов было принято к началу (стартовые не считаются)
var base_rooms := OLD_ROOMS
var slides_seen := false              ## экран «Ваша задача» уже показывали в этой игре
var _t := 0.0


func _init(s: Sim) -> void:
	sim = s


# ================================================================ запуск

## Новая игра (не песочница): цепочка включается, уже выполненное при старте не засчитывается.
func begin() -> void:
	mode = MODE_ON
	done.clear()
	base_orders = taken_orders()
	base_rooms = valid_rooms()


## Новая игра в песочнице: цепочки нет.
func skip() -> void:
	mode = MODE_DONE


## Сохранение без цепочки: пройденное отмечается без наград; после второго этапа цепочка не нужна.
func adopt_old() -> void:
	if mode != MODE_NONE:
		return
	base_orders = 0
	base_rooms = OLD_ROOMS
	done.clear()
	for st: Dictionary in STEPS:
		if reached(str(st["id"])):
			done.append(st["id"])
	mode = MODE_DONE if sim.progress.stage >= 2 or done.size() >= STEPS.size() else MODE_ON


func active() -> bool:
	return mode == MODE_ON and enabled and not sim.progress.all_open


# ================================================================ состояние завода

func taken_orders() -> int:
	return sim.orders.by_status(["active", "ready", "shipping", "done", "failed"]).size()


func valid_rooms() -> int:
	var n := 0
	for r in sim.rooms.list:
		if r.type != "" and r.valid:
			n += 1
	return n


## Задание выполнено сейчас (по состоянию завода).
func reached(id: String) -> bool:
	match id:
		"order":
			return taken_orders() > base_orders
		"qc":
			if int(sim.stats.get("made", 0)) < 1:
				return false
			if not sim.orders.by_status(["ready", "shipping", "done"]).is_empty():
				return true
			for o: Dictionary in sim.orders.by_status(["active"]):
				if sim.ok_in_storage(str(o["product"])) > 0:
					return true
			return false
		"ship":
			return int(sim.stats.get("orders_done", 0)) >= 1
		"hire":
			return int(sim.stats.get("hired", 0)) >= 1 or sim.workers.size() > sim.progress.start_staff
		"build":
			return valid_rooms() > base_rooms
		"orders3":
			return int(sim.stats.get("orders_done", 0)) >= 3
		"week":
			return week_in_profit()
	return false


## Есть закрытая неделя, в которой выручка больше расходов (без стройки и кредитов).
func week_in_profit() -> bool:
	var cur := sim.office.week_no()
	for wd: Dictionary in sim.office.weeks:
		if int(wd["week"]) < cur and sim.office.week_total(wd) > 0.0:
			return true
	return false


# ================================================================ ход

func tick(dt: float) -> void:
	if mode != MODE_ON:
		return
	_t -= dt
	if _t > 0.0:
		return
	_t = 4.0
	update()


## Пересчёт: новые выполненные задания получают награду (один раз) и реплику советника.
func update() -> void:
	if not active():
		return
	for st: Dictionary in STEPS:
		var id := str(st["id"])
		if done.has(id) or not reached(id):
			continue
		done.append(id)
		_reward(st)
	if done.size() >= STEPS.size():
		mode = MODE_DONE
		sim.notify(L.t("Первые шаги пройдены! Дальше — цели этапа: кнопка «Цели» вверху."), Sim.LVL_GOOD)


func _reward(st: Dictionary) -> void:
	var rw: Array = st["reward"]
	var amount := int(rw[1])
	var txt := ""
	if str(rw[0]) == "money":
		sim.money += float(amount)
		# мимо office.book: награда не выручка, неделю в плюсе она не делает
		sim.ledger.push_front({"day": sim.day(), "time": sim.time_str(), "text": L.t("Награда за задание"), "v": float(amount)})
		txt = Defs.money_str(float(amount))
	else:
		sim.reputation = minf(100.0, sim.reputation + float(amount))
		txt = L.t("репутация +%d") % amount
	sim.notify(L.t("Задание выполнено: %s. Награда: %s.") % [L.t(str(st["text"])), txt], Sim.LVL_GOOD)
	sim.calls.chain_comment("first_" + str(st["id"]), str(st["say"]))


# ================================================================ для интерфейса

func count_done() -> int:
	return done.size()


## Первое невыполненное задание ({} — всё готово).
func current() -> Dictionary:
	for st: Dictionary in STEPS:
		if not done.has(str(st["id"])):
			return st
	return {}


func reward_text(st: Dictionary) -> String:
	var rw: Array = st["reward"]
	return "+" + Defs.money_str(float(rw[1])) if str(rw[0]) == "money" else L.t("репутация +%d") % int(rw[1])


# ================================================================ сохранение

func to_dict() -> Dictionary:
	return {"mode": mode, "done": done.duplicate(), "bo": base_orders, "br": base_rooms, "seen": slides_seen}


func from_dict(d: Dictionary) -> void:
	mode = str(d.get("mode", MODE_NONE))
	done = (d.get("done", []) as Array).duplicate()
	base_orders = int(d.get("bo", 0))
	base_rooms = int(d.get("br", OLD_ROOMS))
	slides_seen = bool(d.get("seen", false))
