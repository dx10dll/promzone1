class_name FaultLayer
extends Node2D
## 1.18: лужи от прорыва водопровода — на полу, под людьми и станками.
## Искры от обрыва провода рисует FxLayer (поверх всего).

const T := World.T

var sim: Sim
var _t := 0.0
var _had := false


func _process(delta: float) -> void:
	if sim == null:
		return
	_t += delta
	var has := sim.faults.count("pipe") > 0
	if has or _had:
		queue_redraw()
	_had = has


func _draw() -> void:
	if sim == null:
		return
	for f: Dictionary in sim.faults.list.values():
		if str(f["layer"]) != "pipe":
			continue
		var i := int(f["i"])
		var c := _puddle_cell(sim.world.cell_of(i))
		var age := clampf((sim.minute - float(f["at"])) / 120.0, 0.0, 1.0)
		draw_puddle(self, (Vector2(c) + Vector2(0.5, 0.55)) * T, 0.45 + 0.75 * age, i, _t)


## Труба лопнула под стеной или прибором — вода растекается по соседней открытой клетке.
func _puddle_cell(c: Vector2i) -> Vector2i:
	var w := sim.world
	if w.wall[w.idx(c)] == World.W_NONE and w.occ[w.idx(c)] < 0:
		return c
	for d: Vector2i in [Vector2i(0, 1), Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
		var n := c + d
		if w.inb(n) and w.wall[w.idx(n)] == World.W_NONE and w.occ[w.idx(n)] < 0:
			return n
	return c


## Лужа неправильной формы: несколько кругов, блик и расходящиеся круги от капель.
static func draw_puddle(ci: CanvasItem, center: Vector2, size_k: float, seed_i: int, t: float) -> void:
	var r := T * 0.62 * size_k
	var base := Color(0.18, 0.36, 0.58, 0.50)
	var h := absi(seed_i * 2654435761)
	for k in 6:
		var a := TAU * k / 6.0 + float((h >> (k * 3)) % 7) * 0.3
		var off := Vector2(cos(a), sin(a) * 0.7) * r * 0.55
		var rr := r * (0.45 + float((h >> (k * 4)) % 5) * 0.07)
		ci.draw_set_transform(center + off, 0.0, Vector2(1.0, 0.72))
		ci.draw_circle(Vector2.ZERO, rr, base)
	ci.draw_set_transform(center, 0.0, Vector2(1.0, 0.72))
	ci.draw_circle(Vector2.ZERO, r * 0.7, Color(0.30, 0.52, 0.78, 0.35))
	# блик
	ci.draw_arc(Vector2(-r * 0.2, -r * 0.25), r * 0.35, PI * 1.05, PI * 1.55, 10, Color(1, 1, 1, 0.55), 2.2)
	ci.draw_arc(Vector2(r * 0.25, r * 0.1), r * 0.22, PI * 0.1, PI * 0.5, 8, Color(1, 1, 1, 0.35), 1.6)
	# круги от капель
	for k2 in 2:
		var ph := fmod(t * 0.55 + k2 * 0.5 + float(h % 100) / 100.0, 1.0)
		var p := Vector2(sin(float(h % 13) + k2 * 2.1), cos(float(h % 7) + k2 * 1.3)) * r * 0.3
		ci.draw_arc(p, 3.0 + ph * r * 0.45, 0.0, TAU, 20, Color(0.85, 0.94, 1.0, 0.45 * (1.0 - ph)), 1.4)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
