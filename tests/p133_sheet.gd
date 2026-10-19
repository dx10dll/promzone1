extends SceneTree
## 1.33: листы для проверки новых портретов (нужна видеокарта: xvfb-run … --rendering-driver opengl3).
##   godot --path . -s res://tests/p133_sheet.gd -- sheet <out.png> [зерно]   — 40 случайных людей
##   godot --path . -s res://tests/p133_sheet.gd -- ref <out.png> <папка previews> <preview_layers.json>
##   godot --path . -s res://tests/p133_sheet.gd -- sizes <out.png>           — один человек в разных размерах

var frames := 0
var out := "/tmp/p133.png"


class Raw extends Control:
	## Рецепт целиком на весь холст 512 — для сравнения с эталонными сборками набора.
	var rec: Dictionary = {}

	func _draw() -> void:
		PortraitKit.draw(self, Rect2(Vector2.ZERO, size), Rect2(0, 0, 512, 512), rec)


func _init() -> void:
	Defs.load_all()
	PortraitKit.available()
	var a := OS.get_cmdline_user_args()
	var mode := a[0] if a.size() > 0 else "sheet"
	out = a[1] if a.size() > 1 else out
	var root := Control.new()
	root.size = Vector2(1600, 900)
	var bg := ColorRect.new()
	bg.color = Color("#1d2024")
	bg.size = root.size
	root.add_child(bg)
	match mode:
		"ref":
			_ref(root, a[2], a[3])
		"sizes":
			_sizes(root)
		_:
			_sheet(root, int(a[2]) if a.size() > 2 else 133)
	get_root().add_child(root)
	process_frame.connect(_frame)


func _label(t: String, sz: int = 11) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	return l


func _sheet(root: Control, seed_v: int) -> void:
	var grid := GridContainer.new()
	grid.columns = 10
	grid.position = Vector2(8, 6)
	grid.add_theme_constant_override("h_separation", 6)
	grid.add_theme_constant_override("v_separation", 2)
	root.add_child(grid)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_v
	var profs := ["turner", "qc", "electrician", "miller", "welder", "caster", "painter", "assembler", "laborer", "builder", "foreman", "accountant", "cook", "nurse", "guard", "chief", "hr", "cleaner", "cnc_operator", "lawyer"]
	var bodies := ["vthin", "thin", "normal", "stout", "strong", "fat", "vfat"]
	for i in 40:
		var w := People.make(rng, str(profs[i % profs.size()]), 0.45)
		w.look["skin"] = i % People.SKINS.size()
		w.look["body"] = bodies[(i * 3) % bodies.size()]
		if i % 4 == 1:
			w.age = 58
			w.look["age"] = 58
		elif i % 4 == 2:
			w.age = 22
			w.look["age"] = 22
		if i == 37:
			w.look["outfit"] = "fireman"
		w.look.erase("_face")
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var p := Portrait.new()
		p.set_look(w.look, 1.95, {"age": w.age, "mood": [80.0, 50.0, 20.0][i % 3]})
		v.add_child(p)
		v.add_child(_label("%s %s %d %s" % [w.prof.left(8), str(w.look["body"]), w.age, PortraitKit.collar_of(w.look)], 10))
		grid.add_child(v)


func _sizes(root: Control) -> void:
	var h := HBoxContainer.new()
	h.position = Vector2(10, 10)
	h.add_theme_constant_override("separation", 12)
	root.add_child(h)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for prof: String in ["turner", "accountant", "cook"]:
		var w := People.make(rng, prof, 0.5)
		for z: float in [0.6, 0.62, 1.12, 1.25, 1.7, 3.3]:
			var p := Portrait.new()
			p.set_look(w.look, z, {"age": w.age, "mood": 55.0, "wide": z > 1.0 and z < 3.0, "doc": z > 1.0})
			h.add_child(p)


func _ref(root: Control, prev_dir: String, json_path: String) -> void:
	var f := FileAccess.open(json_path, FileAccess.READ)
	var d: Dictionary = JSON.parse_string(f.get_as_text())
	var x := 8.0
	for k: String in ["preview_1", "preview_2", "preview_3", "preview_4"]:
		var lays: Array = []
		for n: Variant in d[k]:
			var nm := str(n)
			if nm.begins_with("eyes_"):
				lays.append([nm + "_lid", Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF), false])
			if nm.begins_with("collar_") and PortraitKit.has(nm + "_back"):
				lays.push_front([nm + "_back", Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF), false])
			if nm.begins_with("collar_") and PortraitKit.has(nm + "_skin"):
				lays.push_front([nm + "_skin", Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF), false])
			lays.append([("kerchief_f" if nm == "kerchief_f" else nm), Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF), false])
		var r := Raw.new()
		r.rec = {"layers": lays, "sx": 1.0}
		r.material = ShaderMaterial.new()
		(r.material as ShaderMaterial).shader = PortraitKit.shader()
		r.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		r.position = Vector2(x, 30)
		r.size = Vector2(390, 390)
		var bgr := ColorRect.new()
		bgr.color = Color("#77786f")
		bgr.position = r.position
		bgr.size = r.size
		root.add_child(bgr)
		root.add_child(r)
		var im := Image.load_from_file(prev_dir.path_join(k + ".png"))
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(im)
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tr.position = Vector2(x, 450)
		tr.size = Vector2(390, 390)
		var bg2 := ColorRect.new()
		bg2.color = Color("#77786f")
		bg2.position = tr.position
		bg2.size = tr.size
		root.add_child(bg2)
		root.add_child(tr)
		var l := _label(k + ": сверху — наша сборка, снизу — эталон набора", 12)
		l.position = Vector2(x, 6)
		root.add_child(l)
		x += 398.0


func _frame() -> void:
	frames += 1
	if frames == 10:
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		quit(0)
