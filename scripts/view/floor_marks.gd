class_name FloorMarks
extends Node2D
## 1.58: разметка пола краской — жёлто-чёрная «зебра» по краю зон разгрузки и отгрузки и пунктирные рамки
## на буферных клетках у станков. Едва заметно (низкая альфа), рисуется один раз и перерисовывается только
## когда меняются зоны, объекты или буферы. Под грузами и людьми.

const T := World.T
const STRIPE := 5.0          ## длина одной полоски зебры, пиксели мира
const EDGE_W := 3.0          ## толщина полосы по краю зоны
const YELLOW := Color(0.96, 0.78, 0.18, 0.5)
const BLACK := Color(0.1, 0.1, 0.1, 0.45)
const TEAL := Color(0.35, 0.8, 0.78, 0.55)

var sim: Sim
var _sig := ""
var _t := 0.0


## Данные разметки: {unload: [клетки], ship: [клетки], buffer: [клетки]}.
static func data(s: Sim) -> Dictionary:
	var buf: Array[Vector2i] = []
	for m: Thing in s.things_of("machine"):
		var c := s.logi.buffer_cell_of(m)
		if c.x >= 0 and m.buffer > 0:
			buf.append(c)
	return {"unload": s.logi.zone_cells(), "ship": s.logi.ship_cells(), "buffer": buf}


func _ready() -> void:
	z_index = 0


func _process(d: float) -> void:
	if sim == null:
		return
	_t -= d
	if _t > 0.0:
		return
	_t = 0.5
	var dt := data(sim)
	var sg := "%d|%d|%d" % [sim.world.area_rev, (dt["buffer"] as Array).size(), sim.thing_rev]
	if sg != _sig:
		_sig = sg
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var dt := data(sim)
	_zone(dt["unload"], Logistics.A_UNLOAD, false)
	_zone(dt["ship"], Logistics.A_SHIP, true)
	for c: Vector2i in dt["buffer"]:
		_buffer(c)


## Зебра по внутренней стороне границы зоны (где сосед не из этой зоны).
func _zone(cells: Array, area: int, ship: bool) -> void:
	var w := sim.world
	for c: Vector2i in cells:
		var p := Vector2(c) * T
		for d: Vector2i in Rooms.DIRS:
			var n: Vector2i = c + d
			if w.inb(n) and w.area[w.idx(n)] == area:
				continue
			var a: Vector2
			var dir: Vector2
			var inward := Vector2(-d.x, -d.y)
			match d:
				Vector2i(0, -1):
					a = p
					dir = Vector2(1, 0)
				Vector2i(0, 1):
					a = p + Vector2(0, T)
					dir = Vector2(1, 0)
				Vector2i(-1, 0):
					a = p
					dir = Vector2(0, 1)
				_:
					a = p + Vector2(T, 0)
					dir = Vector2(0, 1)
			a += inward * EDGE_W * 0.5
			var k := 0
			var pos := 0.0
			while pos < T - 0.01:
				var ln := minf(STRIPE, T - pos)
				var col := YELLOW if k % 2 == 0 else (TEAL if ship else BLACK)
				draw_line(a + dir * pos, a + dir * (pos + ln), col, EDGE_W)
				pos += ln
				k += 1


## Буферная клетка у станка: пунктирная жёлтая рамка и угловые скобки.
func _buffer(c: Vector2i) -> void:
	var p := Vector2(c) * T
	var r := Rect2(p + Vector2(3, 3), Vector2(T - 6, T - 6))
	var col := Color(YELLOW.r, YELLOW.g, YELLOW.b, 0.55)
	var seg := 4.0
	for side in 4:
		var a: Vector2
		var dir: Vector2
		match side:
			0:
				a = r.position
				dir = Vector2(1, 0)
			1:
				a = r.position + Vector2(r.size.x, 0)
				dir = Vector2(0, 1)
			2:
				a = r.end
				dir = Vector2(-1, 0)
			_:
				a = r.position + Vector2(0, r.size.y)
				dir = Vector2(0, -1)
		var ln := r.size.x
		var pos := 0.0
		while pos < ln - 0.01:
			draw_line(a + dir * pos, a + dir * minf(ln, pos + seg), col, 1.5)
			pos += seg * 2.0
