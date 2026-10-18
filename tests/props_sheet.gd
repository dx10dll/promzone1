extends Node2D
## 1.29: сводный лист — что люди держат в руках, во всех четырёх направлениях и позах.
## xvfb-run godot --path . res://tests/props_sheet.tscn -- <файл.png> [страница 0|1]

const S := preload("res://tests/setups.gd")
const PROPS := ["broom", "shovel", "ext", "folder", "trowel", "reel", "camera", "flowers", "toolbox", "pendant", "sign", "hammer", "@part", "@bar45", "@plate8", "@parts"]
const DIRS := ["down", "left", "right", "up"]
const ANIMS := ["idle", "walk", "work"]
const CW := 52.0
const RH := 62.0

var frames := 0
var out := "/tmp/props.png"
var page := 0


func _ready() -> void:
	var a := OS.get_cmdline_user_args()
	if a.size() > 0:
		out = a[0]
	if a.size() > 1:
		page = int(a[1])
	RenderingServer.set_default_clear_color(Color("#c9c3b4"))
	var g := Scenario.new_garage(129)
	var cam := Camera2D.new()
	cam.zoom = Vector2(2.0, 2.0)
	add_child(cam)
	var rows := PROPS.slice(page * 7, page * 7 + 7)
	cam.position = Vector2(CW * 5.5 - 20.0, RH * (rows.size() - 1) * 0.5 - 18.0)
	for r in rows.size():
		var pr: String = rows[r]
		var lb := Label.new()
		lb.text = pr
		lb.position = Vector2(-CW * 1.1, r * RH - 24.0)
		lb.add_theme_font_size_override("font_size", 8)
		lb.add_theme_color_override("font_color", Color.BLACK)
		add_child(lb)
		for c in DIRS.size() * ANIMS.size():
			var w := S.hire(g, "laborer", "haul", 4)
			w.present = true
			w.dressed = true
			w.dir = DIRS[c / ANIMS.size()]
			w.anim = ANIMS[c % ANIMS.size()]
			w.pos = Vector2((c * CW) / World.T, (r * RH - 6.0) / World.T)
			if pr.begins_with("@"):
				var it: Item
				match pr:
					"@part":
						it = g.new_item("part", "bushing", "ok")
					"@parts":
						it = g.new_item("part", "bushing", "ok")
						var it2 := g.new_item("part", "bushing", "ok")
						w.carry_extra.append(it2.id)
					"@bar45":
						it = g.new_item("mat", "bar45", "raw")
					_:
						it = g.new_item("mat", "plate8", "raw")
				w.carrying = it.id
			else:
				w.prop = pr
			var v := WorkerView.new()
			add_child(v)
			v.setup(g, w)


func _process(_d: float) -> void:
	frames += 1
	if frames == 30:
		var img := get_viewport().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		get_tree().quit()
