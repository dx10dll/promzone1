extends Node2D
## Проверка поворотов: для каждого объекта — 4 положения, как в игре (основной, лицом влево,
## лицом вверх, лицом вправо), с клетками футпринта и местом работника.
## godot --path . res://tests/rot_gallery.tscn -- <файл.png> <объекты через запятую>

var frames := 0
var out := "/tmp/rot.png"


func _ready() -> void:
	Defs.load_all()
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	var ids: Array = (a[1] if a.size() > 1 else "locker,sink,fridge").split(",")
	RenderingServer.set_default_clear_color(Color("#c9c3b5"))
	scale = Vector2(2, 2)
	var y := 70.0
	for id in ids:
		var x := 150.0
		var row_h := 0.0
		var l := Label.new()
		l.text = str(id)
		l.position = Vector2(8, y)
		l.add_theme_color_override("font_color", Color.BLACK)
		add_child(l)
		for r in 4:
			var sk := Thing.sprite_for(str(id), r)
			var meta: Dictionary = Defs.sprites.get(str(sk[0]), {})
			var bs: Array = Defs.objects[id].get("size", [1, 1])
			var s := Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), r)
			var T := 32.0
			var base := Vector2(x, y + 140.0)
			var grid := ColorRect.new()
			grid.color = Color(0.2, 0.5, 0.2, 0.25)
			grid.position = base - Vector2(0, s.y * T)
			grid.size = Vector2(s.x * T, s.y * T)
			add_child(grid)
			var sp := Sprite2D.new()
			sp.texture = Tex.obj(str(sk[0]))
			sp.centered = false
			sp.scale = Vector2(0.5, 0.5)
			sp.flip_h = bool(sk[1])
			var sh := 0.0
			if sp.flip_h:
				sh = maxf(0.0, float(meta.get("w", 64)) - s.x * 64.0)
			sp.offset = Vector2(-sh, -float(meta.get("oy", 64)))
			sp.position = base
			add_child(sp)
			# место работника
			var t := Thing.new()
			t.def_id = str(id)
			t.rot = r
			t.cell = Vector2i(0, 0)
			for spd: Dictionary in t.spots():
				var c: Vector2i = spd["cell"]
				var dot := ColorRect.new()
				dot.color = Color(0.85, 0.2, 0.2, 0.6)
				dot.position = base - Vector2(0, s.y * T) + Vector2(c) * T + Vector2(10, 10)
				dot.size = Vector2(12, 12)
				add_child(dot)
			x += maxf(s.x * T, float(meta.get("w", 64)) * 0.5) + 60.0
			row_h = maxf(row_h, 150.0)
		y += row_h + 20.0


func _process(_d: float) -> void:
	frames += 1
	if frames == 8:
		get_viewport().get_texture().get_image().save_png(out)
		get_tree().quit()
