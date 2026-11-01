extends Node
## 1.67: перерисовка значков стен для меню «Стройка» из нынешней отрисовки мира (WallPiece.paint): угол из двух плеч, гребень и скаты.
## xvfb-run -a -s "-screen 0 1920x1080x24" godot --path . --audio-driver Dummy res://tests/wall_icons167_gen.tscn
## Результат: assets/ui/icons/icon_wall*.png, 128×128, прозрачный фон (в меню их запекает Tex.crisp).

const MATS := {"icon_wall": World.W_BRICK, "icon_wall_concrete": World.W_CONCRETE, "icon_wall_sandwich": World.W_SANDWICH,
	"icon_wall_partition": World.W_PARTITION, "icon_wall_silicate": World.W_SILICATE, "icon_wall_gasblock": World.W_GASBLOCK}


class IconArt extends Node2D:
	var mat := World.W_BRICK

	func _draw() -> void:
		var w := World.new()
		w.setup(6, 6)
		var cells: Array[Vector2i] = [Vector2i(0, 1), Vector2i(1, 1), Vector2i(1, 0)]
		for c in cells:
			w.wall[w.idx(c + Vector2i(1, 1))] = mat
		for c in cells:
			var cc := c + Vector2i(1, 1)
			WallPiece.paint(self, mat, Vector2(c) * World.T, WallPiece.neighbors(w, cc, mat, false), 0.0, 1.0, false)


func _ready() -> void:
	Defs.load_all()
	for id: String in MATS.keys():
		var vp := SubViewport.new()
		vp.size = Vector2i(128, 128)
		vp.transparent_bg = true
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		add_child(vp)
		var art := IconArt.new()
		art.mat = int(MATS[id])
		art.scale = Vector2(2, 2)
		vp.add_child(art)
		await get_tree().process_frame
		await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		var path := "res://assets/ui/icons/%s.png" % id
		img.save_png(ProjectSettings.globalize_path(path))
		print("saved ", path, " ", img.get_size())
		vp.queue_free()
	get_tree().quit(0)
