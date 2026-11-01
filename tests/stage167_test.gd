extends SceneTree
## Тест 1.67: стены — гребень (светлая полоса вдоль стены) одной ширины на концах, углах, Т-стыках и у дверных проёмов;
## проёмы (дверь, окно, ворота) той же ширины, что стена; значки стен в меню перерисованы из нынешней отрисовки.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage167_test.gd

var fails: Array[String] = []

const MATS := [World.W_BRICK, World.W_CONCRETE, World.W_SANDWICH, World.W_PARTITION, World.W_SILICATE, World.W_GASBLOCK]


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	Defs.load_all()
	L.apply("ru")
	_ridge()
	_openings()
	_icons()
	print("РЕЗУЛЬТАТ: ", "ВСЕ ПРОШЛИ" if fails.is_empty() else "ПРОВАЛЕНО %d: %s" % [fails.size(), str(fails)])
	quit(0 if fails.is_empty() else 1)


func _ridge() -> void:
	print("— гребень одной ширины")
	var T := World.T
	for m: int in MATS:
		var w := Walls167View.world_of(m)
		var r := WallPiece.ridge_half(m)
		var bad_w := 0
		var bad_edge := 0
		var bad_join := 0
		var ends := 0
		var corners := 0
		var tees := 0
		var gaps := 0
		var n := 0
		for c: Vector2i in Walls167View.grid(m).keys():
			if Walls167View.grid(m)[c] != m:
				continue
			var cc := c + Vector2i(1, 1)
			var d := WallPiece.neighbors(w, cc, m, false)
			var rr := WallPiece.ridge_rects(d, r)
			var conn := 0
			for sd: String in ["up", "rt", "dn", "lf"]:
				if bool(d[sd]):
					conn += 1
			if conn == 0:
				continue
			n += 1
			var sq: Rect2 = rr["sq"]
			if not (is_equal_approx(sq.size.x, r * 2.0) and is_equal_approx(sq.size.y, r * 2.0)):
				bad_w += 1
			for sd: String in ["up", "dn"]:
				var a: Rect2 = rr[sd]
				if not is_equal_approx(a.size.x, r * 2.0) or not is_equal_approx(a.position.x, sq.position.x):
					bad_w += 1
			for sd: String in ["lf", "rt"]:
				var a2: Rect2 = rr[sd]
				if not is_equal_approx(a2.size.y, r * 2.0) or not is_equal_approx(a2.position.y, sq.position.y):
					bad_w += 1
			if not (is_zero_approx((rr["up"] as Rect2).position.y) and is_equal_approx((rr["dn"] as Rect2).end.y, T)
					and is_zero_approx((rr["lf"] as Rect2).position.x) and is_equal_approx((rr["rt"] as Rect2).end.x, T)):
				bad_edge += 1
			if conn == 1:
				ends += 1
			elif conn == 2 and ((bool(d["up"]) and bool(d["dn"])) or (bool(d["lf"]) and bool(d["rt"]))):
				gaps += 1
			elif conn == 2:
				corners += 1
			else:
				tees += 1
			# стык с соседом справа и снизу: полосы совпадают
			for dd: Vector2i in [Vector2i(1, 0), Vector2i(0, 1)]:
				var nb := cc + dd
				if w.get_wall(nb) == m:
					var d2 := WallPiece.neighbors(w, nb, m, false)
					var r2 := WallPiece.ridge_rects(d2, r)
					if dd.x == 1:
						var a3: Rect2 = rr["rt"]
						var b3: Rect2 = r2["lf"]
						if not is_equal_approx(a3.position.y, b3.position.y) or not is_equal_approx(a3.size.y, b3.size.y):
							bad_join += 1
					else:
						var a4: Rect2 = rr["dn"]
						var b4: Rect2 = r2["up"]
						if not is_equal_approx(a4.position.x, b4.position.x) or not is_equal_approx(a4.size.x, b4.size.x):
							bad_join += 1
		var nm := "материал %d" % m
		check(n > 20 and bad_w == 0, "%s: ширина гребня %.0f у всех %d клеток (концы %d, углы %d, Т %d)" % [nm, r * 2.0, n, ends, corners, tees])
		check(bad_edge == 0 and bad_join == 0, "%s: рукава доходят до краёв клетки и совпадают на стыках клеток" % nm)
		check(ends > 0 and corners > 0 and tees > 0, "%s: в раскладке есть концы, углы и Т-стыки" % nm)


func _openings() -> void:
	print("— проёмы той же ширины, что стена")
	for m: int in MATS:
		var w := Walls167View.world_of(m)
		var r := WallPiece.ridge_half(m)
		var cnt := 0
		var bad := 0
		for c: Vector2i in Walls167View.grid(m).keys():
			var k: int = Walls167View.grid(m)[c]
			if WallKinds.is_plain(k):
				continue
			var cc := c + Vector2i(1, 1)
			var d := WallPiece.neighbors(w, cc, k, false)
			var band := WallPiece.opening_band(Vector2.ZERO, d)
			cnt += 1
			if not (is_equal_approx(band.size.x, r * 2.0) and is_equal_approx(band.get_center().x, World.T * 0.5)):
				bad += 1
			# гребень соседней стены вдоль проёма — той же ширины
			var vert: bool = d["vert"]
			var nbc := cc + (Vector2i(0, -1) if vert else Vector2i(-1, 0))
			if w.get_wall(nbc) == m:
				var rr := WallPiece.ridge_rects(WallPiece.neighbors(w, nbc, m, false), r)
				var arm: Rect2 = rr["dn"] if vert else rr["rt"]
				if not is_equal_approx(arm.size.x if vert else arm.size.y, band.size.x):
					bad += 1
		check(cnt >= 3 and bad == 0, "материал %d: у %d проёмов полоса = гребень (%.0f), соосно" % [m, cnt, r * 2.0])
	# ворота между стенами: тоже по ширине гребня
	var w2 := World.new()
	w2.setup(10, 5)
	for x in 10:
		w2.wall[w2.idx(Vector2i(x, 2))] = World.W_PARTITION
	for x in [4, 5]:
		w2.wall[w2.idx(Vector2i(x, 2))] = World.W_GATE
	var dg := WallPiece.neighbors(w2, Vector2i(4, 2), World.W_GATE, false)
	check(is_equal_approx(WallPiece.opening_band(Vector2.ZERO, dg).size.x, 6.0), "ворота в перегородке — полоса 6, как гребень перегородки")
	check(not bool(dg["same_a"]) and bool(dg["same_b"]), "ворота на две клетки: край и продолжение")


func _icons() -> void:
	print("— значки стен в меню")
	var ids := ["icon_wall", "icon_wall_concrete", "icon_wall_sandwich", "icon_wall_partition", "icon_wall_silicate", "icon_wall_gasblock"]
	var seen := {}
	for id: String in ids:
		var path := "res://assets/ui/icons/%s.png" % id
		check(FileAccess.file_exists(path), "%s: PNG есть" % id)
		var img := Image.load_from_file(ProjectSettings.globalize_path(path))
		check(img != null and img.get_width() == 128 and img.get_height() == 128, "%s: 128×128" % id)
		if img == null:
			continue
		var ridge := 0
		var opaque := 0
		for y in 128:
			for x in 128:
				var px := img.get_pixel(x, y)
				if px.a > 0.9:
					opaque += 1
					if absf(px.r - 0.847) < 0.03 and absf(px.g - 0.82) < 0.03 and absf(px.b - 0.749) < 0.03:
						ridge += 1
		# перерисован из нынешнего мира: светлый гребень на месте, угол из двух плеч, часть холста прозрачна
		check(ridge > 300 and opaque > 6000 and img.get_pixel(3, 3).a < 0.1, "%s: гребень и скаты на месте (гребень %d px)" % [id, ridge])
		var hsh := hash(img.get_data())
		check(not seen.has(hsh), "%s: значок не повторяет другой" % id)
		seen[hsh] = true
		var t: Texture2D = Tex.crisp(id, 48)
		check(t != null, "%s: меню получает текстуру" % id)
