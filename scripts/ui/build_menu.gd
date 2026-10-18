class_name BuildMenu
extends RefCounted
## Меню «Стройка», «Объекты», «Зоны» и «Сети» (1.12): слева — разделы списком, справа — плитка
## квадратных значков, внизу — описание того, на что навели (цена, размер, что нужно).

const COLS := 9
const TILE := Vector2(62, 66)       ## компактная плитка (1.21: меньше и шире ряд — меню ниже и уже)
const CAT_W := 124.0

static var build_cat := "frame"
static var zone_cat := "prod"
static var _info: Label
static var _info_def := ""


static func fill(h: Hud) -> void:
	# 1.21: компактнее — разделы строкой-«чипами» сверху, под ними плитка в 9 столбцов, внизу описание
	var root := h.sub_root
	var right := UITheme.vbox(5)
	var rw := float(COLS) * (TILE.x + 4.0) - 4.0
	right.custom_minimum_size = Vector2(rw, 0)
	root.add_child(right)
	var head := UITheme.hbox(8)
	right.add_child(head)
	if h.g.tool.plan_mode and h.sub_kind in ["build", "objects", "rooms"]:
		var pl := UITheme.label("ПЛАН: всё ставится на кальку — бесплатно, рабочие не строят, пока не утвердите", 12, Color(0.62, 0.8, 1.0), UITheme.f_semi)
		head.add_child(pl)
	var cats := HFlowContainer.new()
	cats.add_theme_constant_override("h_separation", 3)
	cats.add_theme_constant_override("v_separation", 3)
	cats.custom_minimum_size = Vector2(rw, 0)
	right.add_child(cats)
	var sep := ColorRect.new()
	sep.color = UITheme.LINE
	sep.custom_minimum_size = Vector2(0, 1)
	right.add_child(sep)
	var grid := UITheme.grid(COLS, 4, 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	right.add_child(grid)
	_info = UITheme.label("", 11, UITheme.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.max_lines_visible = 2
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# под описание — всегда ровно две строки: меню не прыгает, когда наводишь на разные плитки
	var inf_f: Font = UITheme.f_reg if UITheme.f_reg else ThemeDB.fallback_font
	var inf_h := ceilf(inf_f.get_height(11)) * 2.0 + 4.0
	_info.custom_minimum_size = Vector2(rw, inf_h)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_info_def = ""
	right.add_child(_info)
	match h.sub_kind:
		"build":
			_build(h, cats, head, grid)
		"objects":
			_objects(h, cats, head, grid)
		"rooms":
			_zones(h, cats, head, grid)
		"power":
			_power(h, cats, head, grid)
	_info.text = _info_def


# ---------------------------------------------------------------- общие кусочки

static func _cat(cats: Control, tex: Texture2D, text: String, on: bool, cb: Callable, col: Color = Color(0, 0, 0, 0)) -> void:
	var b := Button.new()
	b.text = text
	b.set_meta("cat", text)
	b.icon = tex
	b.expand_icon = false
	b.add_theme_constant_override("icon_max_width", 15)
	b.add_theme_constant_override("h_separation", 4)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.toggle_mode = true
	b.button_pressed = on
	b.focus_mode = Control.FOCUS_NONE
	b.clip_text = true
	b.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	b.tooltip_text = text
	b.clip_text = false
	b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	b.custom_minimum_size = Vector2(0, 23)
	b.add_theme_font_size_override("font_size", 11)
	var n := UITheme.sb(Color(1, 1, 1, 0.03), UITheme.LINE, 1, 11, 7, 1)
	var hv := UITheme.sb(Color(1, 1, 1, 0.08), UITheme.LINE2, 1, 11, 7, 1)
	var pr := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.2), UITheme.ACCENT, 1, 11, 7, 1)
	if col.a > 0.0:
		n.border_color = Color(col, 0.55)
		hv.border_color = col
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_color_override("font_color", UITheme.MUTED)
	b.add_theme_color_override("font_hover_color", UITheme.TEXT)
	b.add_theme_color_override("font_pressed_color", UITheme.TEXT)
	b.add_theme_color_override("font_hover_pressed_color", UITheme.TEXT)
	b.add_theme_color_override("icon_normal_color", Color("#c9c5ba"))
	b.add_theme_color_override("icon_pressed_color", UITheme.ACCENT)
	b.pressed.connect(cb)
	cats.add_child(b)


## Квадратная плитка: значок, название в две строки, цена. Наведение — описание внизу меню.
static func _tile(h: Hud, grid: Control, tex: Texture2D, title: String, cost: String, cost_col: Color, desc: String,
		mode: String, arg: Variant, lock: String = "", stripe: Color = Color(0, 0, 0, 0), tint: Color = Color.WHITE) -> Button:
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = TILE
	b.set_meta("arg", arg)   # 1.17: обучение находит нужную плитку
	var chosen: bool = h.g.tool.mode == mode and h.g.tool.arg == arg
	b.button_pressed = chosen
	var n := UITheme.sb(Color(1, 1, 1, 0.035), UITheme.LINE, 1, 7, 2, 2)
	var hv := UITheme.sb(Color(1, 1, 1, 0.08), UITheme.LINE2, 1, 7, 2, 2)
	var pr := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.18), UITheme.ACCENT, 2, 7, 2, 2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", n)
	var v := UITheme.vbox(0)
	v.mouse_filter = Control.MOUSE_FILTER_IGNORE
	v.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	v.offset_top = 3
	v.offset_bottom = -2
	v.offset_left = 2
	v.offset_right = -2
	if stripe.a > 0.0:
		var sw := ColorRect.new()
		sw.color = stripe
		sw.custom_minimum_size = Vector2(0, 2)
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(sw)
	var r := TextureRect.new()
	r.texture = tex
	r.custom_minimum_size = Vector2(0, 28)
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = tint
	v.add_child(r)
	var fit := fit_title(title, TILE.x - 6.0)
	var l := UITheme.label(str(fit[1]), int(fit[0]), UITheme.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", -3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.size_flags_vertical = Control.SIZE_EXPAND_FILL
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.clip_text = true
	v.add_child(l)
	if cost != "":
		var c := UITheme.label(cost, 9, cost_col, UITheme.f_semi)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		v.add_child(c)
	b.add_child(v)
	var full := "%s — %s" % [title, desc] if desc != "" else title
	if lock != "":
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.42)
		full += " — закрыто: " + lock + "."
	b.mouse_entered.connect(func() -> void:
		if _info:
			_info.text = full
			_info.add_theme_color_override("font_color", UITheme.WARN if lock != "" else UITheme.TEXT))
	b.mouse_exited.connect(func() -> void:
		if _info:
			_info.text = _info_def
			_info.add_theme_color_override("font_color", UITheme.MUTED))
	b.pressed.connect(func() -> void:
		h.g.tool.set_mode(mode, arg)
		h._fill_sub())
	if chosen:
		_info_def = full
	grid.add_child(b)
	return b


## Подпись плитки: подбираем кегль (10…8) и сами раскладываем слова по строкам (до двух,
## при 8 px — до трёх) как можно ровнее. Сначала — без переносов; длинное слово
## («Инструментальная», «Ленточнопильный») переносим по слогам с дефисом, составное — по дефису.
static func fit_title(title: String, width: float) -> Array:
	var f: Font = UITheme.f_reg if UITheme.f_reg else ThemeDB.fallback_font
	for opt in [[10, false], [9, false], [10, true], [9, true], [8, false], [8, true]]:
		var px := int(opt[0])
		var atoms := _atoms(title, f, px, width, bool(opt[1]))
		if atoms.is_empty():
			continue
		var best := _lay(atoms, f, px, width, 3 if px == 8 else 2)
		if best != "":
			return [px, best]
	# не влезает даже так — сокращаем с многоточием
	var t := title
	while t.length() > 3 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > width:
		t = t.substr(0, t.length() - 1)
	return [8, t + "…"]


const VOW := "аеёиоуыэюяАЕЁИОУЫЭЮЯ"


static func _w(f: Font, t: String, px: int) -> float:
	return f.get_string_size(t, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x


## Слова подписи как кусочки: {t, sp — пробел перед ним в строке, soft — слог, после которого нужен дефис}.
## Пусто, если какое-то слово не помещается даже по частям.
static func _atoms(title: String, f: Font, px: int, width: float, hyph: bool) -> Array:
	var out: Array = []
	for wd in title.split(" ", false):
		var parts: PackedStringArray = [wd]
		if "-" in wd and _w(f, wd, px) > width:
			parts = []
			var segs := wd.split("-")
			for i in segs.size():
				parts.append(segs[i] + ("-" if i < segs.size() - 1 else ""))
		for j in parts.size():
			var pt := parts[j]
			var sp := j == 0 and not out.is_empty()
			if _w(f, pt, px) <= width:
				out.append({"t": pt, "sp": sp, "soft": false})
				continue
			if not hyph:
				return []
			var cut := _hyph_cut(pt, f, px, width)
			if cut < 0:
				return []
			out.append({"t": pt.substr(0, cut), "sp": sp, "soft": true})
			out.append({"t": pt.substr(cut), "sp": false, "soft": false})
	return out


## Место переноса в слове по слогам: справа — согласная; после гласной — согласная и гласная.
## Из подходящих — где длинная часть короче.
static func _hyph_cut(wd: String, f: Font, px: int, width: float) -> int:
	var best := -1
	var best_w := INF
	for i in range(2, wd.length() - 2):
		var l := wd.substr(0, i)
		var r := wd.substr(i)
		var lc := l[l.length() - 1]
		var r0 := r[0]
		if r0 in VOW or r0 in "ьъйЬЪЙ":
			continue
		if lc in VOW and not (r.length() > 1 and r[1] in VOW):
			continue
		if not _has_vowel(l) or not _has_vowel(r):
			continue
		var wl := _w(f, l + "-", px)
		var wr := _w(f, r, px)
		if wl <= width and wr <= width and maxf(wl, wr) < best_w:
			best_w = maxf(wl, wr)
			best = i
	return best


static func _has_vowel(t: String) -> bool:
	for ch in t:
		if ch in VOW:
			return true
	return false


## Раскладка кусочков по строкам (не больше max_lines): меньше строк, потом — ровнее.
static func _lay(atoms: Array, f: Font, px: int, width: float, max_lines: int) -> String:
	var n := atoms.size()
	var best := ""
	var best_key := INF
	# разрывы перед кусочком i (1..n-1): ни одного, один или два
	var combos: Array = [[]]
	for i in range(1, n):
		combos.append([i])
		if max_lines >= 3:
			for k in range(i + 1, n):
				combos.append([i, k])
	for cb: Array in combos:
		var lines: Array[String] = []
		var starts: Array = [0] + cb
		var ok := true
		var mx := 0.0
		for li in starts.size():
			var s0 := int(starts[li])
			var e0 := int(starts[li + 1]) if li + 1 < starts.size() else n
			var t := ""
			for ai in range(s0, e0):
				var at: Dictionary = atoms[ai]
				if ai > s0 and bool(at["sp"]):
					t += " "
				t += str(at["t"])
			if bool(atoms[e0 - 1]["soft"]):
				if e0 == n:
					ok = false
				t += "-"
			# слог с дефисом не может остаться внутри строки: такое слово влезло бы целиком
			for ai2 in range(s0, e0 - 1):
				if bool(atoms[ai2]["soft"]):
					ok = false
			var wl := _w(f, t, px)
			if wl > width:
				ok = false
			mx = maxf(mx, wl)
			lines.append(t)
		if not ok:
			continue
		var key := float(lines.size()) * 10000.0 + mx
		if key < best_key:
			best_key = key
			best = "\n".join(lines)
	return best


## Строка о стройматериалах (1.13): что едет и когда, чего ждёт стройка.
static func mats_status(sim: Sim) -> String:
	var bm := sim.bmats
	if not bm.enabled or sim.bp_cells.is_empty():
		return ""
	var need := bm.needed()
	if need.is_empty():
		return ""
	var cm := bm.coming()
	if not cm.is_empty():
		var eta := INF
		for o: Dictionary in bm.orders:
			eta = minf(eta, float(o["eta"]))
		return "Стройматериалы едут: %s · %s" % [BuildMats.desc(cm), sim._eta_str(eta)]
	var waiting := 0
	for k in need.keys():
		if bm.free_on_ground(str(k)) <= 0:
			waiting += int(need[k])
	if waiting > 0:
		return "Стройка ждёт материал: %d кл. — заказ уйдёт сам" % waiting
	return "Материал на площадке — строят"


static func _money(h: Hud, cost: float, mode: String, arg: Variant) -> Array:
	var lease := mode == "object" and h.sim.market.can_lease(str(arg), cost)
	if lease:
		return ["лизинг " + Defs.money_str(roundf(cost * Market.LEASE_ADV)), UITheme.INFO]
	if cost <= 0.0:
		return ["бесплатно", UITheme.GOOD]
	return [Defs.money_str(cost), UITheme.ACCENT]


static func _priority(h: Hud) -> CheckButton:
	var pr := CheckButton.new()
	pr.text = "Стройка в приоритете"
	pr.focus_mode = Control.FOCUS_NONE
	pr.button_pressed = h.sim.build_priority
	pr.tooltip_text = "Все, кто не стоит у станка и не на ОТК, бросают переноску и строят.\nПроизводство может просесть — включайте на время."
	pr.add_theme_font_size_override("font_size", 11)
	pr.toggled.connect(func(v: bool) -> void: h.sim.build_priority = v)
	return pr


## Выпадающий список «как в шаблоне / материал · цена за клетку».
static func _pick(h: Hud, cap: String, cur: int, items: Dictionary, cb: Callable) -> Control:
	var box := UITheme.hbox(4)
	box.add_child(UITheme.label(cap, 11, UITheme.MUTED))
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	ob.add_theme_font_size_override("font_size", 11)
	ob.fit_to_longest_item = false
	ob.clip_text = true
	ob.custom_minimum_size = Vector2(150, 0)
	ob.add_item("как задумано", -1)
	var sel := 0
	var n := 1
	for k in items.keys():
		var d: Dictionary = items[k]
		ob.add_item("%s · %s/кл." % [str(d["name"]), Defs.money_str(float(d["cost"]))], int(d["id"]))
		if int(d["id"]) == cur:
			sel = n
		n += 1
	ob.select(sel)
	ob.tooltip_text = "Из чего строить готовое помещение. Цена в плитках пересчитается."
	ob.item_selected.connect(func(i: int) -> void:
		cb.call(ob.get_item_id(i))
		h._fill_sub())
	box.add_child(ob)
	return box


static func _head_text(_head: Control, text: String) -> void:
	if _info_def == "":
		_info_def = text


# ---------------------------------------------------------------- стройка

static func _build(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	var list := [["frame", "icon_room_concrete", "Помещения"], ["floor", "concrete_0", "Полы"], ["wall", "icon_wall", "Стены"],
		["open", "icon_door", "Окна и двери"], ["yard", "icon_zone", "Зоны на улице"]]
	for it: Array in list:
		var k := str(it[0])
		_cat(cats, Tex.tile(str(it[1])), str(it[2]), build_cat == k, func() -> void:
			build_cat = k
			h._fill_sub())
	head.add_child(_priority(h))
	var ms := mats_status(h.sim)
	if ms != "":
		var ml := UITheme.label(ms, 11, UITheme.INFO)
		ml.clip_text = true
		ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ml.tooltip_text = ms
		head.add_child(ml)
	match build_cat:
		"frame":
			_head_text(head, "Готовые помещения — щёлкните, где поставить: пол, стены, двери, мебель и зона разом. Можно вплотную к готовой стене — она станет общей и не оплачивается.")
			# 1.21: свой пол и свои стены — цена в плитках пересчитывается
			head.add_child(_pick(h, "Пол:", Templates.pick_floor, Defs.floors, func(v: int) -> void: Templates.pick_floor = v))
			var wl := {}
			for wk in Defs.walls.keys():
				if str(Defs.walls[wk].get("kind", "")) == "wall" and bool(Defs.walls[wk].get("buildable", false)):
					wl[wk] = Defs.walls[wk]
			head.add_child(_pick(h, "Стены:", Templates.pick_wall, wl, func(v: int) -> void: Templates.pick_wall = v))
			for tk in Defs.templates.keys():
				var td: Dictionary = Defs.templates[tk]
				var tid := str(tk)
				var inn := Templates.inner(tid)
				var tdesc := "%s Внутри %d×%d клеток, снаружи со стенами %d×%d." % [str(td.get("desc", "")), inn.x, inn.y, inn.x + 2, inn.y + 2]
				_tile(h, grid, Tex.ui("zone_" + str(td.get("zone", "workshop"))), str(td["name"]), Defs.money_str(Templates.cost(h.sim, tid)), UITheme.ACCENT, tdesc, "template", tid, Templates.locked(h.sim, tid))
			for k0 in [["concrete", "Цех рамкой"], ["tile", "Бытовка рамкой"], ["lino", "Кабинет рамкой"]]:
				var fd0: Dictionary = Defs.floors[str(k0[0])]
				_tile(h, grid, Tex.tile("icon_room_" + str(k0[0])), str(k0[1]), Defs.money_str(float(fd0["cost"])) + "/кл.", UITheme.ACCENT,
					"пол «%s» по всей площади, стены по контуру (общие с соседями не дублируются) и дверь посередине нижней стены. Цена — за клетку пола, плюс стены и дверь." % str(fd0["name"]).to_lower(), "roomframe", int(fd0["id"]))
		"floor":
			_head_text(head, "Протяните прямоугольник. Цех — бетон или наливной пол, быт — плитка, кабинеты — линолеум или паркет.")
			for k in Defs.floors.keys():
				var fd: Dictionary = Defs.floors[k]
				var tk := str(fd.get("tex", k))
				_tile(h, grid, Tex.tile("concrete_0" if tk == "concrete" else tk), str(fd["name"]), Defs.money_str(float(fd["cost"])) + "/кл.", UITheme.ACCENT, str(fd.get("desc", "")), "floor", int(fd["id"]))
		"wall", "open":
			_head_text(head, "Стены — контуром прямоугольника. Перегородкой удобно делить большой зал на кабинеты." if build_cat == "wall" else "Окна, двери и ворота ставят в стену: протяните вдоль неё.")
			var icons := {"brick": "icon_wall", "concrete_wall": "icon_wall_concrete", "sandwich": "icon_wall_sandwich", "partition": "icon_wall_partition",
				"window": "icon_window", "door": "icon_door", "metal_door": "icon_door_metal", "gate": "icon_gate",
				"silicate": "icon_wall_silicate", "gasblock": "icon_wall_gasblock", "glass_door": "icon_door_glass", "gate_warm": "icon_gate_warm"}
			for k2 in Defs.walls.keys():
				var wd: Dictionary = Defs.walls[k2]
				var kind := str(wd.get("kind", ""))
				if not bool(wd.get("buildable", false)):
					continue
				if (build_cat == "wall") != (kind == "wall"):
					continue
				var mode := "wall" if kind == "wall" else kind
				_tile(h, grid, Tex.tile(str(icons.get(k2, "icon_wall"))), str(wd["name"]), Defs.money_str(float(wd["cost"])) + "/кл.", UITheme.ACCENT, str(wd.get("desc", "")), mode, int(wd["id"]))
		"yard":
			_head_text(head, "Зоны на улице рисуют прямоугольником у ворот. Разгрузка и отгрузка обязательны — их можно расширить или перенести, но не убрать. Внутренние зоны — в меню «Зоны».")
			_yard_tiles(h, grid)


static func _yard_tiles(h: Hud, grid: Control) -> void:
	var stc := Color(str(Defs.rooms.get("_groups", {}).get("store", {}).get("color", "#c9a83a")))
	_tile(h, grid, Tex.ui("zone_unload"), "Разгрузка", "бесплатно", UITheme.GOOD, "Зона разгрузки — сюда фургоны сгружают металл и ящики с оборудованием. Металл кладут на поддоны заготовок (Объекты → Склад), а нет места — на пол зоны; оттуда его разносят к станкам и на стеллажи, ящики — к местам установки. Зона обязательна: последнюю клетку не стереть.", "zone", Logistics.A_UNLOAD, "", stc)
	_tile(h, grid, Tex.ui("zone_ship"), "Отгрузка", "бесплатно", UITheme.GOOD, "Зона отгрузки — сюда приносят готовый заказ, отсюда грузит машина клиента. Готовые детали после ОТК лежат на поддонах готовой продукции; когда заказ готов, рабочие (или погрузчик) переносят их сюда. Зона обязательна: последнюю клетку не стереть.", "zone", Logistics.A_SHIP, "", stc)
	_tile(h, grid, Tex.ui("zone_erase"), "Убрать зону на улице", "", UITheme.MUTED, "выделите область — разгрузка или отгрузка снимется. Обе зоны обязательны: целиком убрать нельзя, только перенести — сначала отметьте новую.", "zone", 0)


# ---------------------------------------------------------------- объекты

static func _objects(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	for c in Hud.OBJ_CATS:
		var first := ""
		for k in Defs.objects.keys():
			if str(Defs.objects[k].get("cat", "")) == c and not bool(Defs.objects[k].get("legacy", false)):
				first = str(k)
				break
		var cc: String = c
		_cat(cats, Tex.obj(first if first != "chair" else "chair_down") if first != "" else null, c, h.obj_cat == c, func() -> void:
			h.obj_cat = cc
			h._fill_sub())
	head.add_child(_priority(h))
	if h.sim.progress.stage >= 2:
		var lz := CheckButton.new()
		lz.text = "Станки в лизинг"
		lz.focus_mode = Control.FOCUS_NONE
		lz.button_pressed = h.sim.market.leasing_on
		lz.add_theme_font_size_override("font_size", 11)
		if not h.sim.dev.on("fin3"):
			lz.disabled = true
			lz.tooltip_text = "Лизинг открывает ступень «Банк и лизинг» (Управление → Развитие), её держит бухгалтер."
		else:
			lz.tooltip_text = "Станки от %s: %d%% сразу, остальное +%d%% платежами %d недель (Финансы → Кредиты и лизинг)" % [Defs.money_str(Market.LEASE_MIN), int(Market.LEASE_ADV * 100.0), int(Market.LEASE_UP * 100.0), Market.LEASE_WEEKS]
		lz.toggled.connect(func(v: bool) -> void:
			h.sim.market.leasing_on = v
			h._fill_sub())
		head.add_child(lz)
	_head_text(head, "R — повернуть перед установкой.")
	for k3 in Defs.objects.keys():
		var od: Dictionary = Defs.objects[k3]
		if str(od.get("cat", "")) != h.obj_cat or bool(od.get("legacy", false)):
			continue
		var sz: Array = od.get("size", [1, 1])
		var desc := "%s Размер %d×%d." % [str(od.get("desc", "")), int(sz[0]), int(sz[1])]
		if od.has("machine") and str(od.get("kind", "")) == "machine":
			desc += " " + Defs.machine_spec(str(k3)) + "."
		if od.has("power"):
			desc += " Мощность %s кВт." % str(od["power"])
		var price := h.sim.thing_cost(str(k3))
		var m := _money(h, price, "object", k3)
		_tile(h, grid, Tex.obj(k3 if k3 != "chair" else "chair_down"), str(od["name"]), str(m[0]), m[1], desc, "object", k3, h.sim.progress.locked_reason(str(k3)))


# ---------------------------------------------------------------- зоны

static func _zones(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	var groups: Dictionary = Defs.rooms.get("_groups", {})
	for gk in groups.keys():
		var gd: Dictionary = groups[gk]
		var first := ""
		for t in Rooms.UI_ORDER:
			if str(Defs.rooms.get(t, {}).get("group", "")) == gk:
				first = t
				break
		var gkk: String = gk
		_cat(cats, Tex.ui("zone_" + first), str(gd["name"]), zone_cat == gk, func() -> void:
			zone_cat = gkk
			h._fill_sub(), Color(str(gd["color"])))
	_head_text(head, "Протяните прямоугольник — разметить клетки; щёлкните по помещению — залить его целиком. Соседние клетки одной зоны сливаются.")
	var gc := Color(str(groups.get(zone_cat, {}).get("color", "#888888")))
	for t2 in Rooms.UI_ORDER:
		var d: Dictionary = Defs.rooms.get(t2, {})
		if str(d.get("group", "")) != zone_cat:
			continue
		var lock := ""
		for dk in Defs.departments.keys():
			if str(Defs.departments[dk].get("room", "")) == t2 and not h.sim.progress.dept_open(str(dk)):
				lock = h.sim.progress.dept_lock_text(str(dk))
		var n := h.sim.rooms.of_type(t2, false).size()
		_tile(h, grid, Tex.ui("zone_" + t2), str(d.get("name", t2)), ("есть: %d" % n) if n > 0 else "", UITheme.GOOD, "нужно: %s. %s" % [Rooms.req_text(t2), str(d.get("desc", ""))], "room", t2, lock, gc, gc.lightened(0.35))
	if zone_cat == "store":
		_yard_tiles(h, grid)
	_tile(h, grid, Tex.ui("zone_erase"), "Стереть разметку", "", UITheme.MUTED, "протяните или щёлкните — клетки станут неразмеченными.", "room", "_erase")


# ---------------------------------------------------------------- сети

static func _power(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	var list := [["power", "cable", "Электричество"], ["light", "power", "Освещение"], ["water", "", "Водопровод и тепло"], ["vent", "", "Вентиляция"], ["air", "", "Сжатый воздух"]]
	var tile_icons := {"water": "icon_pipe", "vent": "icon_duct", "air": "icon_air"}
	for it: Array in list:
		var k := str(it[0])
		var tex: Texture2D = Tex.ui(str(it[1])) if str(it[1]) != "" else Tex.tile(str(tile_icons[k]))
		_cat(cats, tex, str(it[2]), h.net_kind == k, func() -> void:
			h.net_kind = k
			h.g.tool.set_mode("select")
			h._fill_sub())
	var pw := h.sim.power
	match h.net_kind:
		"power", "light":
			var ntr := 0
			for t0: Thing in h.sim.things.values():
				if t0.built and str(t0.def().get("power_source", "")) != "":
					ntr += 1
			_head_text(head, ("Подстанции (%d): %d кВт · нагрузка %.1f кВт. Мало — аккумуляторы вплотную к подстанции." % [ntr, int(pw.total_kw()), pw.total_load]) if ntr > 0 else "Тока нет: поставьте подстанцию в техпомещении и заведите кабель в её клетку.")
			if h.net_kind == "power":
				_tile(h, grid, Tex.ui("cable"), "Кабель", Defs.money_str(Defs.b("cable_cost")) + "/кл.", UITheme.ACCENT, "протяните мышью — ляжет уголком. Прибор подключён, если кабель заведён прямо в клетку его розетки (жёлтый значок), подстанция — в любую её клетку.", "cable", null)
				_tile(h, grid, Tex.ui("uncable"), "Снять кабель", "", UITheme.MUTED, "выделите область — вернётся 30% стоимости.", "uncable", null)
			for k in Defs.objects.keys():
				var od: Dictionary = Defs.objects[k]
				if str(od.get("cat", "")) != ("Электрика" if h.net_kind == "power" else "Освещение") or bool(od.get("legacy", false)):
					continue
				var desc := str(od.get("desc", ""))
				if od.has("capacity_kw"):
					desc += " Мощность %d кВт." % int(od["capacity_kw"])
				var m := _money(h, h.sim.thing_cost(str(k)), "object", k)
				_tile(h, grid, Tex.obj(k), str(od["name"]), str(m[0]), m[1], desc, "object", k, h.sim.progress.locked_reason(str(k)))
		"water":
			_head_text(head, "Насосная станция — в техпомещении; трубы тяните от неё прямо в клетки туалетов, раковин и котла (синий кружок).")
			_tile(h, grid, Tex.tile("icon_pipe"), "Труба", Defs.money_str(Defs.b("pipe_cost")) + "/кл.", UITheme.ACCENT, "протяните мышью — ляжет уголком.", "pipe", null)
			_tile(h, grid, Tex.tile("icon_unpipe"), "Снять трубу", "", UITheme.MUTED, "выделите область — вернётся 30% стоимости.", "unpipe", null)
			for kw in Defs.objects.keys():
				if bool(Defs.objects[kw].get("legacy", false)):
					continue
				if str(Defs.objects[kw].get("cat", "")) == "Водопровод" or str(Defs.objects[kw].get("net", "")) == "water" or kw == "radiator":
					_net_tile(h, grid, str(kw))
		"vent", "air":
			var vent := h.net_kind == "vent"
			_head_text(head, "Воздуховод — от вытяжного вентилятора по помещениям со сваркой, покраской и печью." if vent else "Пневмомагистраль — от компрессора к покрасочной камере и сборочным столам.")
			var lay := "duct" if vent else "air"
			_tile(h, grid, Tex.tile("icon_" + lay), "Воздуховод" if vent else "Пневмомагистраль", Defs.money_str(Defs.b(lay + "_cost")) + "/кл.", UITheme.ACCENT, "протяните мышью — линия ляжет уголком.", lay, null)
			_tile(h, grid, Tex.tile("icon_un" + lay), "Снять", "", UITheme.MUTED, "выделите область — вернётся 30% стоимости.", "un" + lay, null)
			for kv in Defs.objects.keys():
				if str(Defs.objects[kv].get("net", "")) == h.net_kind:
					_net_tile(h, grid, str(kv))


static func _net_tile(h: Hud, grid: Control, k: String) -> void:
	var od: Dictionary = Defs.objects[k]
	var m := _money(h, h.sim.thing_cost(k), "object", k)
	_tile(h, grid, Tex.obj(k), str(od["name"]), str(m[0]), m[1], str(od.get("desc", "")), "object", k, h.sim.progress.locked_reason(k))
