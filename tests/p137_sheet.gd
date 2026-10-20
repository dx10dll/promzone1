extends SceneTree
## 1.37: листы для проверки портретов v5 (нужна видеокарта: xvfb-run … --rendering-driver opengl3 --resolution WxH).
##   godot --path . -s res://tests/p137_sheet.gd -- sheet <out.png> [зерно]  — 40 людей, все 7 телосложений, оба пола
##   godot --path . -s res://tests/p137_sheet.gd -- ref <out.png> <папка набора> — 4 контрольные сборки набора
##     (previews/preview_recipes.json): сверху наша сборка, снизу эталон previews/preview_*.png
##   godot --path . -s res://tests/p137_sheet.gd -- fits <out.png>          — 7 наборов × 2 пола в разной одежде
##   godot --path . -s res://tests/p137_sheet.gd -- sizes <out.png>         — один человек в разных размерах

var frames := 0
var out := "/tmp/p137.png"
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
		"fits":
			_fits(root)
		"sizes":
			_sizes(root)
		_:
			_sheet(root, int(a[2]) if a.size() > 2 else 137)
	get_root().add_child(root)


func _label(t: String, sz: int = 11) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", sz)
	l.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	return l


## Рецепт по compose.py набора (те же умолчания: первая голова и причёска набора, кожа #c9b49b, волосы #514d46,
## цветная одежда без перекраски).
func _mk(e: Dictionary) -> Dictionary:
	var plain := Color(PortraitKit.REF, PortraitKit.REF, PortraitKit.REF)
	var g := str(e["gender"])
	var sid := "%s_%s" % [e["body_type"], g]
	var st: Dictionary = PortraitKit.set_info(sid)
	var p := sid + "/"
	var skin := Color(str(e.get("skin", "#c9b49b")))
	var hc := Color(str(e.get("hair_color", "#514d46")))
	var hair := str(e.get("hair", (st["hair"] as Array)[0]))
	var head := str(e.get("head", (st["heads"] as Array)[0]))
	var eyes := str(e.get("eyes", "almond"))
	var o: Dictionary = (st["outfits"] as Dictionary)[str(e.get("outfit", "overall"))]
	var rec := {}
	for gname: String in PortraitKit.GROUPS:
		rec[gname] = []
	(rec["back"] as Array).append([p + "hair_%s_back" % hair, hc])
	if o.get("inner", null) != null:
		(rec["inner"] as Array).append([p + str(o["inner"]), plain])
	(rec["body"] as Array).append([p + str(o["neck"]), skin])
	(rec["body"] as Array).append([p + "head_%s_%s" % [g, head], skin])
	(rec["cloth"] as Array).append([p + str(o["outer"]), plain])
	var face: Array = rec["face"]
	face.append([p + "eyes_%s_lids" % eyes, skin])
	face.append([p + "eyes_" + eyes, plain])
	face.append([p + "brows_" + str(e.get("brows", "straight")), hc])
	face.append([p + "nose_" + str(e.get("nose", "straight")), skin])
	face.append([p + "mouth_" + str(e.get("mouth", "neutral")), plain])
	var acc: Array = e.get("accessories", [])
	for n: Variant in acc:
		if str(n) in ["freckles"]:
			face.append([p + str(n), plain])
		elif str(n) in ["lines_mid", "lines_old"]:
			face.append([p + str(n), skin])
	if e.has("beard"):
		face.append([p + "beard_" + str(e["beard"]), hc])
	(rec["hair"] as Array).append([p + "hair_%s_front" % hair, hc])
	for n: Variant in acc:
		if not str(n) in ["freckles", "lines_mid", "lines_old"]:
			# косынка в игре — серая, красится в цвет убора: здесь — в красный, как на эталоне
			(rec["top"] as Array).append([p + str(n), Color("#b03a26") if str(n) == "kerchief_f" else plain])
	rec["set"] = sid
	return rec


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
	var f := FileAccess.open(kit.path_join("previews/preview_recipes.json"), FileAccess.READ)
	var d: Array = JSON.parse_string(f.get_as_text())
	var x := 8.0
	for i in d.size():
		var e: Dictionary = d[i]
		_stack(root, _mk(e), Vector2(x, 30), 390.0)
		_img(root, kit.path_join("previews/preview_%d.png" % (i + 1)), Rect2(x, 450, 390, 390))
		var l := _label("preview_%d (%s %s %s): сверху — наша, снизу — эталон" % [i + 1, e["gender"], e["body_type"], e["outfit"]], 12)
		l.position = Vector2(x, 6)
		root.add_child(l)
		x += 398.0


## 7 посадок × 2 пола, одежда по кругу (через рецепт игры: кожа, волосы, одежда в цвет).
func _fits(root: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.position = Vector2(8, 6)
	root.add_child(grid)
	var bodies := ["vthin", "thin", "normal", "stout", "strong", "fat", "vfat"]
	var outfits := ["overall", "suit", "coat", "fireman", "shirt", "jacket", "apron"]
	for fem: bool in [false, true]:
		for i in 7:
			var lk := {"fem": fem, "skin": i % People.SKINS.size(), "hair": "bob" if fem else "short", "hair_col": "#4a3020", "outfit": outfits[i],
				"outfit_col": ["#3d5a7a", "#33363a", "#e8e8e8", "#3a3f2a", "#6a7a8a", "#4a5240", "#7a3a3a"][i], "fs": i, "age": 35, "body": bodies[i], "hat": ""}
			var v := VBoxContainer.new()
			var p := Portrait.new()
			p.set_look(lk, 2.9, {"age": 35, "mood": 50.0})
			v.add_child(p)
			var rr := PortraitKit.recipe(lk, {"age": 35, "mood": 50.0})
			v.add_child(_label("%s %s %s" % [rr["set"], rr["head"], rr["collar"]], 10))
			grid.add_child(v)


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
		v.add_child(_label("%s %s %s %s" % [str(rec["collar"]), str(rec["head"]), str(rec["hairdo"]), str(rec["hat"])], 10))
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
