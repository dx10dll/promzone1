class_name Walls167View
extends Node2D
## 1.67: учебная раскладка стен для снимков и теста: рисует клетки тем же WallPiece.paint, что и мир.

## Раскладка: строки текста; символ -> вид стены. B — кирпич и т.д. (материал задаётся при построении).
const LAYOUT := [
	"###############",
	"#.....#...#...#",
	"#.....D.......#",
	"#.....#.......#",
	"###D#####W#####",
	"#.....#.......#",
	"#.....#.......#",
	"###############",
]

var mat := World.W_BRICK
var scale_k := 3.0


static func kind_of(ch: String, m: int) -> int:
	match ch:
		"#":
			return m
		"D":
			return World.W_DOOR
		"W":
			return World.W_WINDOW
	return World.W_NONE


## Сетка клеток раскладки для материала m.
static func grid(m: int) -> Dictionary:
	var g := {}
	for y in LAYOUT.size():
		var row: String = LAYOUT[y]
		for x in row.length():
			var k := kind_of(row[x], m)
			if k != World.W_NONE:
				g[Vector2i(x, y)] = k
	return g


## Мир с раскладкой для материала m.
static func world_of(m: int) -> World:
	var w := World.new()
	w.setup(LAYOUT[0].length() + 2, LAYOUT.size() + 2)
	for c: Vector2i in grid(m).keys():
		w.wall[w.idx(c + Vector2i(1, 1))] = grid(m)[c]
	return w


func _draw() -> void:
	var w := world_of(mat)
	draw_rect(Rect2(-8, -8, 15 * World.T + 16, LAYOUT.size() * World.T + 16), Color("#8a8f86"))
	for c: Vector2i in grid(mat).keys():
		var k: int = grid(mat)[c]
		var cc := c + Vector2i(1, 1)
		WallPiece.paint(self, k, Vector2(c) * World.T, WallPiece.neighbors(w, cc, k, false), 0.0, 1.0, false)
