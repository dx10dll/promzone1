extends SceneTree
## Галерея портретов: godot --path . -s res://tests/portrait_gallery.gd -- out.png [масштаб]

var frames := 0
var out := "/tmp/portraits.png"


func _init() -> void:
	Defs.load_all()
	var a := OS.get_cmdline_user_args()
	out = a[0] if a.size() > 0 else out
	var z := float(a[1]) if a.size() > 1 else 2.4
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#1d2024")
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 8
	grid.position = Vector2(12, 12)
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	root.add_child(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var profs := ["turner", "qc", "electrician", "miller", "welder", "heat_treater", "painter", "assembler", "laborer", "builder", "foreman", "accountant", "turner", "laborer", "chief", "hr"]
	for i in 16:
		var w := People.make(rng, str(profs[i % profs.size()]))
		if i % 3 == 1:
			w.age = 56
		var p := Portrait.new()
		p.set_look(w.look, z, {"age": w.age, "mood": [80.0, 50.0, 20.0][i % 3]})
		grid.add_child(p)
	root.size = Vector2(1600, 900)
	get_root().add_child(root)
	process_frame.connect(_frame)


func _frame() -> void:
	frames += 1
	if frames == 8:
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		quit(0)
