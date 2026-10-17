class_name CraneLayer
extends Node2D
## Кран-балки: подкрановые пути вдоль стен помещения, мост от стены до стены, тележка с талью.
## Мост ездит вдоль помещения, тележка — вдоль моста к станку, где обрабатывают тяжёлую деталь,
## крюк опускается к детали. Без работы кран уезжает к стене (на стоянку).

const T := World.T
const BEAM := Color("#e2b73a")
const BEAM_D := Color("#b8932c")
const RAIL := Color("#6a7176")

var sim: Sim
var state: Dictionary = {}   ## id крана -> {y, x, hook}


func _ready() -> void:
	z_index = 7


func _process(delta: float) -> void:
	if sim == null:
		return
	var any := false
	for t: Thing in sim.things.values():
		if t.def_id != "crane":
			continue
		any = true
		var r := sim.rooms.room_at(t.cell)
		if r == null:
			continue
		var rr := r.srect
		var st: Dictionary = state.get(t.id, {})
		if st.is_empty():
			st = {"y": float(rr.position.y) + 0.5, "x": float(rr.position.x) + 1.0, "hook": 0.0}
			state[t.id] = st
		var ty := float(rr.position.y) + 0.5
		var tx := float(rr.position.x) + 1.0
		var work := false
		st["load"] = -1
		# 1.14: человек ведёт краном тяжёлую деталь — мост и тележка над ним, деталь на крюке
		if t.built:
			for wk in sim.workers:
				if not wk.present or wk.prop != "pendant" or wk.carrying < 0:
					continue
				if sim.rooms.space_id_at(wk.cell()) != r.space:
					continue
				ty = wk.pos.y - 0.15
				tx = wk.pos.x + (-0.55 if wk.dir == "left" else 0.55)
				st["load"] = wk.carrying
				work = true
				break
		if t.built and int(st["load"]) < 0:
			var best: Thing = null
			for m in sim.things_of("machine"):
				if not m.working or m.product == "" or not bool(Defs.products.get(m.product, {}).get("heavy", false)):
					continue
				if sim.rooms.space_of_thing(m) != r.space:
					continue
				best = m
				break
			if best:
				var c := Vector2(best.cell) + Vector2(best.size()) * 0.5
				ty = c.y
				tx = c.x
				work = true
		var sp := (6.0 if int(st["load"]) >= 0 else 3.0) * delta   # клеток в секунду; с грузом едет за человеком
		var y := float(st["y"])
		var x := float(st["x"])
		y = move_toward(y, ty, sp)
		x = move_toward(x, tx, sp * 1.4) if absf(y - ty) < 0.05 or not work else x
		var arrived := absf(y - ty) < 0.05 and absf(x - tx) < 0.05
		st["y"] = y
		st["x"] = x
		st["hook"] = move_toward(float(st["hook"]), 1.0 if (work and arrived) else 0.0, delta * 1.2)
	if any:
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	for t: Thing in sim.things.values():
		if t.def_id != "crane":
			continue
		var r := sim.rooms.room_at(t.cell)
		if r == null:
			continue
		var st: Dictionary = state.get(t.id, {})
		if st.is_empty():
			continue
		var ghost := not t.built
		var a := 0.45 if ghost else 1.0
		var rr := r.srect
		var x0 := rr.position.x * T + 3.0
		var x1 := rr.end.x * T - 3.0
		var y0 := rr.position.y * T
		var y1 := rr.end.y * T
		# подкрановые пути вдоль левой и правой стены
		for xx in [x0, x1]:
			draw_line(Vector2(xx, y0 + 2.0), Vector2(xx, y1 - 2.0), Color(0, 0, 0, 0.25 * a), 6.0)
			draw_line(Vector2(xx, y0 + 2.0), Vector2(xx, y1 - 2.0), Color(RAIL, a), 4.0)
			draw_line(Vector2(xx, y0 + 2.0), Vector2(xx, y1 - 2.0), Color(1, 1, 1, 0.25 * a), 1.0)
		# мост
		var by := float(st["y"]) * T
		draw_rect(Rect2(x0 - 2.0, by - 5.0 + 9.0, x1 - x0 + 4.0, 10.0), Color(0, 0, 0, 0.16 * a))   # тень на полу
		var beam := Rect2(x0 - 4.0, by - 5.0, x1 - x0 + 8.0, 10.0)
		draw_rect(beam, Color(BEAM, a))
		draw_rect(beam, Color(0.12, 0.13, 0.14, a), false, 1.5)
		var k := 0.0
		while k < beam.size.x - 6.0:
			draw_line(Vector2(beam.position.x + k + 2.0, beam.end.y - 1.0), Vector2(beam.position.x + k + 7.0, beam.position.y + 1.0), Color(BEAM_D, a), 1.6)
			k += 9.0
		# торцевые тележки на путях
		for xx2 in [x0, x1]:
			draw_rect(Rect2(xx2 - 5.0, by - 8.0, 10.0, 16.0), Color(0.35, 0.38, 0.4, a))
			draw_rect(Rect2(xx2 - 5.0, by - 8.0, 10.0, 16.0), Color(0.12, 0.13, 0.14, a), false, 1.2)
		# тележка с талью
		var tx := clampf(float(st["x"]) * T, x0 + 10.0, x1 - 10.0)
		var trolley := Rect2(tx - 9.0, by - 8.0, 18.0, 16.0)
		draw_rect(trolley, Color(0.36, 0.39, 0.42, a))
		draw_rect(trolley, Color(0.12, 0.13, 0.14, a), false, 1.4)
		draw_circle(Vector2(tx, by), 4.5, Color(0.22, 0.24, 0.26, a))
		# трос и крюк
		var hook := float(st["hook"])
		var hy := by + 8.0 + 6.0 + hook * 14.0
		draw_line(Vector2(tx, by + 4.0), Vector2(tx, hy), Color(0.15, 0.15, 0.15, a), 1.4)
		draw_arc(Vector2(tx + 1.5, hy + 3.0), 3.0, 0.0, PI * 1.2, 8, Color("#d9b13b", a), 2.2)
		# деталь на стропах под крюком
		var li := int(st.get("load", -1))
		if li >= 0:
			var it: Item = sim.items.get(li)
			if it:
				var tex := Tex.for_item(it)
				var ip := Vector2(tx, hy + 15.0)
				draw_line(Vector2(tx, hy + 4.0), ip + Vector2(-6, -4), Color(0.2, 0.2, 0.2, a), 1.0)
				draw_line(Vector2(tx, hy + 4.0), ip + Vector2(6, -4), Color(0.2, 0.2, 0.2, a), 1.0)
				draw_circle(ip + Vector2(0, 22), 7.0, Color(0, 0, 0, 0.18))   # тень на полу
				if tex:
					draw_texture_rect(tex, Rect2(ip - Vector2(12, 10), Vector2(24, 24)), false)
