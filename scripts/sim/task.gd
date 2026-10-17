class_name Task
extends RefCounted
## Задача рабочего: последовательность шагов (идти, взять, положить, работать).
## Все резервирования задачи снимаются при её отмене.

var kind := ""
var label := ""
var toils: Array = []
var i := 0
var res_items: Array[int] = []
var res_users: Array[int] = []     ## объекты, на которых рабочий «занял» место оператора
var res_spots: Array = []          ## [thing_id, spot_idx]
var res_incoming: Array = []       ## [thing_id, slot]
var res_bp: Array[int] = []        ## индексы клеток чертежей
var res_load: int = -1             ## фургон, под погрузку в который зарезервировано место
var data: Dictionary = {}


func current() -> Dictionary:
	if i < toils.size():
		return toils[i]
	return {}


func next() -> void:
	i += 1


func add(t: Dictionary) -> void:
	toils.append(t)


func insert_next(arr: Array) -> void:
	for k in range(arr.size() - 1, -1, -1):
		toils.insert(i + 1, arr[k])
