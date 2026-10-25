class_name Item
extends RefCounted
## Одна единица груза: пруток металла или деталь.

enum Loc { GROUND, THING, WORKER, VEHICLE }

var id := 0
var kind := "mat"      ## "mat" — материал, "part" — деталь, "crate" — ящик с оборудованием, "bmat" — стройматериал
var def_id := ""
var q := "raw"         ## материал: "raw"; деталь: "wip" | "machined" | "ok" | "scrap"
var step := 0          ## сколько операций маршрута уже пройдено
var defect := false    ## скрытый дефект (ловит ОТК)
var loc: int = Loc.GROUND
var cell := Vector2i.ZERO
var holder := -1       ## id объекта / рабочего / машины
var slot := 0
var reserved_by := -1
var rw := false        ## 1.15: брак уже пробовали доработать у слесарного верстака
var dest := -1         ## ящик с оборудованием: для какого объекта (-1 — запасной, на склад)


## Категория для правил хранения: "mat", "wip", "machined", "ok", "scrap".
func cat() -> String:
	return "mat" if kind == "mat" else q


func stack_key() -> String:
	return kind + ":" + def_id + ":" + q + ":" + str(step)


func display_name() -> String:
	if kind == "mat":
		return Defs.material_name(def_id)
	if kind == "crate":
		return Logistics.crate_name(self)
	if kind == "bmat":
		return BuildMats.mat_name(def_id)
	var n := Defs.product_name(def_id)
	match q:
		"wip":
			var o := Defs.op(def_id, step)
			return n + L.t(" (ждёт: %s)") % Defs.process_name(str(o.get("op", ""))).to_lower()
		"machined":
			return n + L.t(" (ждёт ОТК)")
		"scrap":
			return n + L.t(" (брак)")
	return n


func to_dict() -> Dictionary:
	return {
		"id": id, "kind": kind, "def": def_id, "q": q, "defect": defect, "step": step,
		"loc": loc, "cx": cell.x, "cy": cell.y, "holder": holder, "slot": slot, "dest": dest, "rw": rw,
	}


static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.id = int(d["id"])
	it.kind = str(d["kind"])
	it.def_id = str(d["def"])
	it.q = str(d["q"])
	it.defect = bool(d.get("defect", false))
	it.step = int(d.get("step", 0))
	it.loc = int(d["loc"])
	it.cell = Vector2i(int(d["cx"]), int(d["cy"]))
	it.holder = int(d["holder"])
	it.slot = int(d["slot"])
	it.dest = int(d.get("dest", -1))
	it.rw = bool(d.get("rw", false))
	return it
