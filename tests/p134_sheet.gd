extends SceneTree
## 1.34: листы для проверки портретов (нужна видеокарта: xvfb-run … --rendering-driver opengl3 --resolution WxH).
##   godot --path . -s res://tests/p134_sheet.gd -- sheet <out.png> [зерно]  — 40 случайных людей, все 7 телосложений, оба пола
##   godot --path . -s res://tests/p134_sheet.gd -- ref <out.png> <папка набора> — 4 основные сборки набора: наша / эталон
##   … -- necks_m | necks_f | collars | heads | hats <out.png> <папка набора> — листы шей, одежды, голов, уборов: наша / эталон
##   godot --path . -s res://tests/p134_sheet.gd -- sizes <out.png>          — один человек в разных размерах

var frames := 0
var out := "/tmp/p134.png"
const GRAYBG := Color("#77786f")


class Group extends Control:
	## Группа рецепта на весь холст 512 (с маской группы) — так же, как рисует Portrait.
	var rec: Dictionary = {}
	var group := ""

	func _draw() -> void:
		PortraitKit.draw(self, Rect2(Vector2.ZERO, size), Rect2(0, 0, 512, 512), rec, group)


func _init() -> void:
	Defs.load_all()
	PortraitKit.available()
	process_frame.connect(_frame)


## Раскладка — на первом кадре, когда окно уже знает свой размер.
func _build() -> void:
	var a := OS.get_cmdline_user_args()
	var mode := a[0] if a.size() > 0 else "sheet"
	out = a[1] if a.size() > 1 else out
	var root := Control.new()
	root.size = get_root().get_visible_rect().size
	var bg := ColorRect.new()
	bg.color = Color("#1d2024")
	bg.size = root.size
	root.add_child(bg)
	match mode:
		"ref":
			_ref(root, a[2])
		"necks_m", "necks_f", "collars", "heads", "hats":
			_grid(root, mode, a[2])
		"sizes":
			_sizes(root)
		_:
			_sheet(root, int(a[2]) if a.size() > 2 else 134)
	get_root().add_child(root)


func _label(t: String, sz: int = 11) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return l


## Рецепт по схеме compose_example.py набора (те же группы и маски, что в PortraitKit._build).
func _mk(head: String, collar: String, neck: String, feats: Array, skin: Color, hair: Color, hat: String = "") -> Dictionary:
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	var back: Array = []
	var body: Array = []
	var face: Array = []
	var hair_l: Array = []
	var top: Array = []
	var g := head.split("_")[1]
	var fat := neck.begins_with("chin_double")
	for n: Variant in feats:
		if str(n).begins_with("cheeks_full"):
			fat = true
	if fat:
		head = "head_%s_round" % g
	if PortraitKit.has(collar + "_inner"):
		back.append([collar + "_inner", plain, false])
	for n: String in feats:
		if n.ends_with("_back"):
			back.append([n, hair, false])
	if neck.begins_with("neck_"):
		body.append([neck, skin, false])
	body.append([head + "_cut" if neck != "" else head, skin, false])
	if neck.begins_with("chin_double"):
		body.append([neck, skin, false])
	for n: String in feats:
		if n.begins_with("eyes_"):
			face.append([n + "_lids", skin, false])
	for n: String in feats:
		if n.ends_with("_back") or n.ends_with("_front") or n in ["glasses", "earrings", "kerchief_f"]:
			continue
		var c := plain
		if n.begins_with("cheeks") or n.begins_with("nose"):
			c = skin
		elif n.begins_with("brows") or n.begins_with("beard"):
			c = hair
		face.append([n, c, false])
	face.append([collar, plain, false])
	if PortraitKit.has(collar + "_skinpart"):
		face.append([collar + "_skinpart", skin, false])
	for n: String in feats:
		if n.ends_with("_front"):
			hair_l.append([n, hair, false])
		elif n in ["glasses", "earrings", "kerchief_f"]:
			top.append([n, plain, false])
	if hat != "":
		top.append([hat, plain, false])
	var hm := "mask_hat_" + hat if PortraitKit.has_mask("mask_hat_" + hat) else ""
	var bm := "mask_%s_keep" % collar if PortraitKit.has_mask("mask_%s_keep" % collar) else ""
	return {"back": back, "body": body, "face": face, "hair": hair_l, "top": top, "sx": 1.0,
		"mask_back": hm, "mask_hair": hm, "mask_body": bm}


func _stack(root: Control, rec: Dictionary, pos: Vector2, sz: float) -> void:
	var b := ColorRect.new()
	b.color = GRAYBG
	b.position = pos
	b.size = Vector2(sz, sz)
	root.add_child(b)
	for gname: String in PortraitKit.GROUPS:
		var c := Group.new()
		c.rec = rec
		c.group = gname
		c.material = PortraitKit.material(str(rec.get("mask_" + gname, "")))
		c.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
		c.position = pos
		c.size = Vector2(sz, sz)
		root.add_child(c)


func _img(root: Control, path: String, r: Rect2) -> void:
	var im := Image.load_from_file(path)
	var b := ColorRect.new()
	b.color = GRAYBG
	b.position = r.position
	b.size = r.size
	root.add_child(b)
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(im)
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tr.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT
	tr.position = r.position
	tr.size = r.size
	root.add_child(tr)


func _ref(root: Control, kit: String) -> void:
	var f := FileAccess.open(kit.path_join("preview_layers.json"), FileAccess.READ)
	var d: Array = JSON.parse_string(f.get_as_text())
	var x := 8.0
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	for i in d.size():
		var e: Dictionary = d[i]
		var rec := _mk(str(e["head"]), str(e["clothing"]), str(e.get("neck", "")), e["features"], plain, plain)
		_stack(root, rec, Vector2(x, 30), 390.0)
		_img(root, kit.path_join("previews/preview_%d.png" % (i + 1)), Rect2(x, 450, 390, 390))
		var l := _label("preview_%d: сверху — наша сборка, снизу — эталон набора" % (i + 1), 12)
		l.position = Vector2(x, 6)
		root.add_child(l)
		x += 398.0


const FEATS := ["eyes_narrow", "brows_straight", "nose_straight", "mouth_neutral"]


func _grid(root: Control, mode: String, kit: String) -> void:
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	var cells: Array = []   # [рецепт, подпись]
	var cols := 3
	var refimg := ""
	match mode:
		"necks_m", "necks_f":
			var g := mode.right(1)
			refimg = "neck_fit_%s.jpg" % g
			for nk: String in ["neck_thin", "neck_strong", "chin_double"]:
				for c: String in ["shirt", "suit", "sweater"]:
					cells.append([_mk("head_%s_oval" % g, "collar_%s_%s" % [c, g], "%s_%s" % [nk, g], FEATS, plain, plain), "%s_%s + %s" % [nk, g, c]])
		"collars":
			refimg = "collar_fit_all.jpg"
			cols = 5
			for c: String in ["firefighter_f", "firefighter_m", "jacket_f", "jacket_m", "kerchief_f", "overall_f", "overall_m", "robe_f", "robe_m", "shirt_f", "shirt_m", "suit_f", "suit_m", "sweater_f", "sweater_m", "vest_f", "vest_m"]:
				var g := c.right(1)
				cells.append([_mk("head_%s_oval" % g, "collar_" + c, "neck_thin_" + g, FEATS, plain, plain), "collar_" + c])
		"heads":
			refimg = "all_heads_neck_fit.jpg"
			cols = 7
			for nk: String in ["thin", "strong"]:
				for h: String in ["head_f_oval", "head_f_round", "head_f_soft", "head_m_long", "head_m_oval", "head_m_round", "head_m_square"]:
					var g := h.split("_")[1]
					cells.append([_mk(h, "collar_shirt_" + g, "neck_%s_%s" % [nk, g], FEATS, plain, plain), "%s / %s" % [h, nk]])
		"hats":
			refimg = "headwear_fit.jpg"
			cols = 4
			for h: String in ["cap", "helmet", "welder_mask", "ushanka"]:
				var feats := ["hair_short_back", "eyes_narrow", "brows_straight", "nose_straight", "mouth_neutral", "hair_short_front"]
				cells.append([_mk("head_m_round", "collar_jacket_m", "chin_double_m", feats, Color("#d2b08a"), Color("#5a3624"), h), h])
	var rows := ceili(cells.size() / float(cols))
	var half := root.size.x * 0.5 - 12.0
	var sz := minf(half / cols - 6.0, (root.size.y - 40.0) / rows - 18.0)
	for i in cells.size():
		var p := Vector2(8 + (i % cols) * (sz + 6.0), 30 + int(i / float(cols)) * (sz + 18.0))
		var cell: Array = cells[i]
		_stack(root, cell[0], p, sz)
		var l := _label(str(cell[1]), 10)
		l.position = p + Vector2(0, sz)
		root.add_child(l)
	_img(root, kit.path_join("previews/" + refimg), Rect2(root.size.x * 0.5 + 4, 30, half, root.size.y - 40))
	var t := _label("%s: слева — наша сборка (те же слои и маски), справа — эталон набора previews/%s" % [mode, refimg], 12)
	t.position = Vector2(8, 6)
	root.add_child(t)


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
		# пары: мужчина и женщина с одним телосложением; все 7 телосложений встречаются у обоих полов
		var w := People.make(rng, str(profs[i % profs.size()]), 0.0 if i % 2 == 0 else 1.0)
		w.look["skin"] = (i * 5) % People.SKINS.size()
		w.look["body"] = bodies[int(i / 2.0) % bodies.size()]
		if i % 4 == 1:
			w.age = 58
			w.look["age"] = 58
		elif i % 4 == 2:
			w.age = 22
			w.look["age"] = 22
		if i == 37:
			w.look["outfit"] = "fireman"
		var info := {"age": w.age, "mood": [80.0, 50.0, 20.0][i % 3]}
		if i == 30 or i == 31:
			info["dressed"] = false
			info["winter"] = true   # не переоделся, зима — своя куртка и ушанка
		if i == 33:
			info["dressed"] = true
			info["winter"] = true
			info["outside"] = true  # в спецовке на морозе — ушанка
		w.look.erase("_face")
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 0)
		var p := Portrait.new()
		p.set_look(w.look, 1.95, info)
		v.add_child(p)
		var rec := PortraitKit.recipe(w.look, info)
		v.add_child(_label("%s %s %s %d" % [w.prof.left(7), "ж" if w.female else "м", str(w.look["body"]), w.age], 10))
		v.add_child(_label("%s %s" % [str(rec["collar"]).trim_prefix("collar_"), str(rec["hat"])], 10))
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
		for z: float in [0.42, 0.6, 1.12, 1.25, 1.7, 3.3]:
			var p := Portrait.new()
			p.set_look(w.look, z, {"age": w.age, "mood": 55.0, "wide": z > 1.0 and z < 3.0, "doc": z > 1.0})
			h.add_child(p)


func _frame() -> void:
	frames += 1
	if frames == 2:
		_build()
	if frames == 12:
		var img := get_root().get_texture().get_image()
		img.save_png(out)
		print("saved ", out)
		quit(0)
