class_name Vehicle
extends RefCounted
## Грузовой фургон: привозит металл или забирает готовые заказы.
## 1.30: ещё ломовоз (kind "scrap": забирает стружку и брак) и пожарная машина (kind "fire").

var id := 0
var kind := "delivery"   ## "delivery" — поставка металла, "pickup" — забирает заказ
var x := -5.0            ## координата задней части фургона (в тайлах)
var px := -1e9           ## 1.29: где был до последнего шага симуляции — экран рисует между px и x
var state := "queued"    ## queued, arriving, parked, leaving, gone
var park_x := 22.0
var order_id := -1
var supply_id := -1
var need := 0            ## сколько единиц нужно загрузить (pickup)
var loaded := 0
var reserved_load := 0
var parked_time := 0.0
var color := 0
var cargo_desc := ""
var equip: Array = []      ## заказы оборудования в кузове (id из Logistics.equip)
var bmat_order := -1       ## 1.13: заказ стройматериалов в кузове
var body := "van"          ## van — фургон, flatbed — бортовой грузовик, truck, semi, fire — пожарная машина
var lane := 0              ## 1.30: 0 — ближняя полоса (едет вправо), 1 — дальняя (встречная, едет влево)
var hold := false          ## 1.30: стоит, пока её не отпустит своя служба (пожарные, ломовоз)


func access_cell(sidewalk_row: int) -> Vector2i:
	return Vector2i(int(park_x), sidewalk_row)


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "x": x, "state": state, "park_x": park_x,
		"order": order_id, "supply": supply_id, "need": need, "loaded": loaded,
		"color": color, "desc": cargo_desc, "parked": parked_time, "equip": equip,
		"bmat": bmat_order, "body": body, "lane": lane, "hold": hold,
	}


static func from_dict(d: Dictionary) -> Vehicle:
	var v := Vehicle.new()
	v.id = int(d["id"])
	v.kind = str(d["kind"])
	v.x = float(d["x"])
	v.state = str(d["state"])
	v.park_x = float(d["park_x"])
	v.order_id = int(d["order"])
	v.supply_id = int(d["supply"])
	v.need = int(d["need"])
	v.loaded = int(d["loaded"])
	v.color = int(d.get("color", 0))
	v.cargo_desc = str(d.get("desc", ""))
	v.parked_time = float(d.get("parked", 0.0))
	v.equip = d.get("equip", [])
	v.bmat_order = int(d.get("bmat", -1))
	v.body = str(d.get("body", "van"))
	v.lane = int(d.get("lane", 0))
	v.hold = bool(d.get("hold", false))
	return v


## 1.30: в какую сторону едет: ближняя полоса — вправо, встречная — влево.
func dir() -> float:
	return 1.0 if lane == 0 else -1.0
