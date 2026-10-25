class_name BuildMenu
extends RefCounted
## Меню «Стройка», «Объекты», «Зоны» и «Сети» (1.12): слева — разделы списком, справа — плитка
## квадратных значков, внизу — описание того, на что навели (цена, размер, что нужно).
## 1.40: поиск по названию, подсветка того, что нужно помещению в центре экрана, меню постоянной
## высоты (плитка в прокрутке), цена и «есть N» всегда внутри плитки; в плане — стройка и объекты разом.

const COLS := 10
const TILE := Vector2(64, 68)       ## 1.40: фиксированная раскладка — значок, подпись в две строки, цена внизу
const CAT_W := 124.0
const ICON_Y := 3.0
const TITLE_Y := 29.0
const TITLE_H := 23.0
const PRICE_H := 13.0
const HEAD_H := 24.0
const FOCUS_ZOOM := 1.25            ## 1.40: «камера приближена» — с этого масштаба подсвечиваем нужное помещению
const NEED_COL := Color("#5fd3c0")  ## подсветка «нужно помещению»
const BUILD_CATS := ["wall", "floor", "open", "yard", "frame"]   ## 1.40: стены, полы, двери, улица, готовые помещения

static var build_cat := "wall"
static var zone_cat := "prod"
static var _info: Label
static var _info_def := ""
static var query := {"build": "", "objects": ""}   ## 1.40: строка поиска каждого меню
static var _q := ""                   ## поиск раздела, который сейчас собираем
static var _search_edit: LineEdit = null
static var focus_type := ""           ## тип помещения в центре экрана (или "")
static var focus_room_id := -1
static var _need := {}                ## id объекта -> true: нужно помещению; false: уже есть
static var _shown := 0                ## сколько плиток прошло фильтр поиска


static func fill(h: Hud) -> void:
	# 1.21: компактнее — разделы строкой-«чипами» сверху, под ними плитка, внизу описание
	var root := h.sub_root
	_info_def = ""
	_info = UITheme.label("", 11, UITheme.MUTED)
	_info.autowrap_mode = TextServer.AUTOWRAP_WORD
	_info.max_lines_visible = 2
	_info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	# под описание — всегда ровно две строки: меню не прыгает, когда наводишь на разные плитки
	var inf_f: Font = UITheme.f_reg if UITheme.f_reg else ThemeDB.fallback_font
	_info.custom_minimum_size = Vector2(width(), ceilf(inf_f.get_height(11)) * 2.0 + 4.0)
	_info.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_update_focus(h)
	if h.g.tool.plan_mode and h.sub_kind in ["build", "objects", "rooms"]:
		# 1.40: план — своё меню стройки (или зон) и меню объектов одновременно
		root.add_child(_plan_row(h))
		_section(h, root, "rooms" if h.sub_kind == "rooms" else "build", 1)
		var sp := ColorRect.new()
		sp.color = Color(0.36, 0.62, 1.0, 0.45)
		sp.custom_minimum_size = Vector2(0, 1)
		root.add_child(sp)
		_section(h, root, "objects", 2)
	else:
		_section(h, root, h.sub_kind, -1)
	root.add_child(_info)
	_info.text = _info_def


## Ширина меню: плитка в COLS столбцов плюс место под полосу прокрутки.
static func width() -> float:
	return float(COLS) * (TILE.x + 4.0) - 4.0 + 12.0


## Один раздел меню: шапка (одна строка, лишнее обрезается), чипы разделов, плитка постоянной высоты.
static func _section(h: Hud, root: Control, kind: String, rows: int) -> void:
	var w := width()
	var right := UITheme.vbox(5)
	right.custom_minimum_size = Vector2(w, 0)
	root.add_child(right)
	# шапка: фиксированная высота и обрезка — длинная строка не раздувает меню
	var hold := Control.new()
	hold.clip_contents = true
	hold.custom_minimum_size = Vector2(w, HEAD_H)
	right.add_child(hold)
	var head := UITheme.hbox(8)
	head.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	head.alignment = BoxContainer.ALIGNMENT_BEGIN
	hold.add_child(head)
	var cats := HFlowContainer.new()
	cats.add_theme_constant_override("h_separation", 3)
	cats.add_theme_constant_override("v_separation", 3)
	cats.custom_minimum_size = Vector2(w, 0)
	right.add_child(cats)
	var sep := ColorRect.new()
	sep.color = UITheme.LINE
	sep.custom_minimum_size = Vector2(0, 1)
	right.add_child(sep)
	# плитка — в прокрутке постоянной высоты: разделы с одним и с тремя рядами одной высоты
	var n_rows := rows if rows > 0 else clampi(max_rows(h, kind), 2, 3)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.custom_minimum_size = Vector2(w, float(n_rows) * (TILE.y + 4.0) - 4.0)
	sc.set_meta("tile_rows", n_rows)
	right.add_child(sc)
	var grid := UITheme.grid(COLS, 4, 4)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	sc.add_child(grid)
	_q = str(query.get(kind, "")).strip_edges()
	_shown = 0
	match kind:
		"build":
			_build(h, cats, head, grid)
		"objects":
			_objects(h, cats, head, grid)
		"rooms":
			_zones(h, cats, head, grid)
		"power":
			_power(h, cats, head, grid)
	# 1.47: если в шапке только поиск — он уходит в строку чипов, а пустая шапка схлопывается
	if head.get_child_count() == 2 and head.get_child(1) is LineEdit:
		var le := head.get_child(1) as LineEdit
		head.remove_child(le)
		hold.visible = false
		var hb := HBoxContainer.new()
		hb.add_theme_constant_override("separation", 6)
		right.remove_child(cats)
		cats.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cats.custom_minimum_size = Vector2(w - 156.0, 0)
		hb.add_child(cats)
		le.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		le.custom_minimum_size = Vector2(150, 24)
		hb.add_child(le)
		right.add_child(hb)
		right.move_child(hb, 0)
	if _q != "" and _shown == 0:
		var nl := UITheme.label(L.t("Ничего не найдено: «%s»") % _q, 12, UITheme.MUTED)
		grid.add_child(nl)
	_q = ""


## Строка плана над меню: что это за режим, переключатель «Стройка / Зоны», ластик.
static func _plan_row(h: Hud) -> Control:
	var hold := Control.new()
	hold.clip_contents = true
	hold.custom_minimum_size = Vector2(width(), HEAD_H)
	var row := UITheme.hbox(6)
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hold.add_child(row)
	for it: Array in [["build", "construction", "Стройка"], ["rooms", "zones", "Зоны"]]:
		var k := str(it[0])
		var on := h.sub_kind == k or (k == "build" and h.sub_kind == "objects")
		_cat(row, UITheme.micon(str(it[1])), str(it[2]), on, func() -> void:
			h.sub_kind = k
			h.g.tool.set_mode("room" if k == "rooms" else "select")
			h._fill_sub())
	_cat(row, UITheme.micon("demolition"), "Ластик", h.g.tool.mode == "demolish", func() -> void:
		h.g.tool.set_mode("select" if h.g.tool.mode == "demolish" else "demolish")
		h._fill_sub())
	(row.get_child(row.get_child_count() - 1) as Button).tooltip_text = "Стереть нарисованное на плане: протяните рамку"
	var pl := UITheme.label("ПЛАН: всё ставится на кальку — бесплатно, рабочие не строят, пока не утвердите", 12, Color(0.62, 0.8, 1.0), UITheme.f_semi)
	pl.clip_text = true
	pl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	pl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pl.tooltip_text = pl.text
	row.add_child(pl)
	return hold


## Сколько рядов плитки в самом длинном разделе меню (без поиска) — под это и держим высоту.
static func max_rows(h: Hud, kind: String) -> int:
	var mx := 1
	match kind:
		"build":
			var nw := 0
			var no := 0
			for k in Defs.walls.keys():
				var wd: Dictionary = Defs.walls[k]
				if bool(wd.get("buildable", false)):
					if str(wd.get("kind", "")) == "wall":
						nw += 1
					else:
						no += 1
			mx = maxi(maxi(nw, no), maxi(Defs.floors.size(), Defs.templates.size()))
		"objects":
			var cnt := {}
			for k2 in Defs.objects.keys():
				var od: Dictionary = Defs.objects[k2]
				if not bool(od.get("legacy", false)):
					var c := str(od.get("cat", ""))
					cnt[c] = int(cnt.get(c, 0)) + 1
			for v: int in cnt.values():
				mx = maxi(mx, v)
		"rooms":
			var cg := {}
			for t in Rooms.ui_order():
				var g := str(Defs.rooms.get(t, {}).get("group", ""))
				cg[g] = int(cg.get(g, 0)) + 1
			for g2: String in cg.keys():
				mx = maxi(mx, int(cg[g2]) + 1 + (3 if g2 == "store" else 0))
		"power":
			mx = h.sim.world.w * 0 + 6   # кабель/труба, «снять» и приборы — один ряд
	return int(ceil(float(mx) / float(COLS)))


## Поле поиска в шапке: фильтр по названию (в английском — по английским названиям).
static func _search(h: Hud, head: Control, kind: String) -> void:
	var sp := Control.new()
	sp.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	head.add_child(sp)
	var le := LineEdit.new()
	le.placeholder_text = "Поиск…"
	le.text = str(query.get(kind, ""))
	le.clear_button_enabled = true
	le.custom_minimum_size = Vector2(150, 0)
	le.add_theme_font_size_override("font_size", 12)
	le.tooltip_text = "Поиск по названию во всех разделах меню"
	le.set_meta("search", kind)
	le.text_changed.connect(func(t: String) -> void:
		query[kind] = t
		h._fill_sub()
		refocus(kind))
	head.add_child(le)


## После пересборки меню вернуть фокус и курсор в поле поиска (пишем дальше, не теряя букв).
static func refocus(kind: String) -> void:
	_search_edit = null
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	for n: Node in tree.root.find_children("*", "LineEdit", true, false):
		var le := n as LineEdit
		if le.has_meta("search") and str(le.get_meta("search")) == kind and not _dying(le):
			le.grab_focus()
			le.caret_column = le.text.length()
			_search_edit = le
			return


## Узел или его предок уже удаляется (старое меню до конца кадра ещё в дереве).
static func _dying(n: Node) -> bool:
	while n != null:
		if n.is_queued_for_deletion():
			return true
		n = n.get_parent()
	return false


static func _norm(s: String) -> String:
	return s.to_lower().replace("ё", "е").replace("\n", " ").replace("-", "")


## Проходит ли название плитки фильтр поиска.
static func matches(title_shown: String, q: String) -> bool:
	if q == "":
		return true
	var t := _norm(title_shown)
	for wd in _norm(q).split(" ", false):
		if not t.contains(wd):
			return false
	return true


# ---------------------------------------------------------------- 1.40: что нужно помещению

## Помещение в центре экрана, если камера к нему приближена (иначе null).
static func focus_room(h: Hud) -> Rooms.Room:
	var cam: Camera2D = h.g.cam
	if cam == null or cam.zoom.x < FOCUS_ZOOM:
		return null
	var p := cam.get_screen_center_position()
	var r := h.sim.rooms.room_at(Vector2i(floori(p.x / World.T), floori(p.y / World.T)))
	if r == null or r.type == "" or not Defs.rooms.has(r.type):
		return null
	return r


## Подпись того, что сейчас в фокусе (меняется — меню пересобирается).
static func focus_sig(h: Hud) -> String:
	var r := focus_room(h)
	return "" if r == null else "%d|%s|%s" % [r.id, r.type, str(r.missing)]


static func _update_focus(h: Hud) -> void:
	_need.clear()
	var r := focus_room(h)
	focus_type = r.type if r else ""
	focus_room_id = r.id if r else -1
	if r == null:
		return
	for need: Dictionary in Defs.rooms[r.type].get("needs", []):
		var miss := r.missing.has(str(need.get("text", "")))
		var ids: Array = need.get("ids", [])
		var kinds: Array = need.get("kinds", [])
		for k in Defs.objects.keys():
			var od: Dictionary = Defs.objects[k]
			if bool(od.get("legacy", false)):
				continue
			if ids.has(str(k)) or (not kinds.is_empty() and kinds.has(str(od.get("kind", "decor")))):
				_need[str(k)] = bool(_need.get(str(k), false)) or miss


## Строка про помещение в фокусе: что ему нужно и чего не хватает.
static func focus_text(h: Hud) -> String:
	if focus_type == "":
		return ""
	var r := focus_room(h)
	var nm := L.dt("room.%s.name" % focus_type, str(Defs.rooms[focus_type].get("name", focus_type)))
	if r == null or r.missing.is_empty():
		return L.t("В центре экрана «%s»: всё нужное есть, подсвечено то, что ему подходит.") % nm
	var ms: Array[String] = []
	for m: String in r.missing:
		ms.append(L.tx(m))
	return L.t("В центре экрана «%s»: подсвечено, что нужно. Не хватает: %s.") % [nm, ", ".join(ms)]


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
	if Tex.is_color(tex):
		# 1.38: цветной значок владельца — без перекраски и чуть крупнее (у PNG прозрачные поля)
		UITheme.micon_colors(b)
		b.add_theme_constant_override("icon_max_width", 18)
	b.pressed.connect(cb)
	cats.add_child(b)


## Текст в рамке шириной w: подбираем кегль (from…to), не влезает — обрезаем с многоточием.
static func fit_line(text: String, w: float, from: int, to: int, f: Font) -> Array:
	for px in range(from, to - 1, -1):
		if f.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x <= w:
			return [px, text]
	var t := text
	while t.length() > 2 and f.get_string_size(t + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, to).x > w:
		t = t.substr(0, t.length() - 1)
	return [to, t + "…"]


## Короткая цена для плитки: «115 000 ₽» → «115 тыс. ₽», если полная не влезает.
static func short_money(cost: String) -> String:
	var digits := ""
	for ch in cost:
		if ch >= "0" and ch <= "9":
			digits += ch
	if digits.length() < 4:
		return cost
	var v := float(digits)
	var tail := cost.substr(cost.rfind(digits.right(1)) + 1)   # «₽», «₽/кл.» и т. п.
	var en := L.is_en()
	var num := ("%.1f" % (v / 1000000.0)).trim_suffix(".0") + ("M" if en else " млн") if v >= 1000000.0 else str(int(round(v / 1000.0))) + ("k" if en else " тыс.")
	var head := cost.substr(0, cost.find(digits.left(1)))   # «лизинг » и т. п.
	return head + num + tail


## Квадратная плитка: значок, название в две строки, цена внизу. Все надписи — в своих рамках,
## за границы плитки ничего не выходит. Наведение — описание внизу меню.
static func _tile(h: Hud, grid: Control, tex: Texture2D, title: String, cost: String, cost_col: Color, desc: String,
		mode: String, arg: Variant, lock: String = "", stripe: Color = Color(0, 0, 0, 0), tint: Color = Color.WHITE, count: int = 0) -> Button:
	title = L.t(title)   # 1.40: названия, цены и описания из данных — ключ перевода сам русский текст
	if not matches(title, _q):
		return null
	_shown += 1
	cost = L.t(cost)
	desc = L.t(desc)
	var need := mode == "object" and _need.has(str(arg))
	var miss := need and bool(_need[str(arg)])
	var b := Button.new()
	b.toggle_mode = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = TILE
	b.clip_contents = true
	b.set_meta("arg", arg)   # 1.17: обучение находит нужную плитку
	if need:
		b.set_meta("need", miss)
	var chosen: bool = h.g.tool.mode == mode and h.g.tool.arg == arg
	b.button_pressed = chosen
	var n := UITheme.sb(Color(1, 1, 1, 0.035), UITheme.LINE, 1, 7, 2, 2)
	var hv := UITheme.sb(Color(1, 1, 1, 0.08), UITheme.LINE2, 1, 7, 2, 2)
	var pr := UITheme.sb(Color(UITheme.ACCENT.r, UITheme.ACCENT.g, UITheme.ACCENT.b, 0.18), UITheme.ACCENT, 2, 7, 2, 2)
	if need:
		# 1.40: нужно помещению в центре экрана — бирюзовая рамка (не хватает — ярче и толще)
		n = UITheme.sb(Color(NEED_COL.r, NEED_COL.g, NEED_COL.b, 0.14 if miss else 0.06), Color(NEED_COL, 1.0 if miss else 0.55), 2 if miss else 1, 7, 2, 2)
		hv = UITheme.sb(Color(NEED_COL.r, NEED_COL.g, NEED_COL.b, 0.22), NEED_COL, 2, 7, 2, 2)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", hv)
	b.add_theme_stylebox_override("pressed", pr)
	b.add_theme_stylebox_override("hover_pressed", pr)
	b.add_theme_stylebox_override("disabled", n)
	var iw := TILE.x - 6.0
	if stripe.a > 0.0:
		var sw := ColorRect.new()
		sw.color = stripe
		sw.set_meta("rect", Rect2(Vector2(6, 2), Vector2(TILE.x - 12.0, 2)))
		sw.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(sw)
	var r := TextureRect.new()
	r.texture = tex
	var ih := 26.0 if Tex.is_color(tex) else 22.0   # 1.38: PNG владельца с полями — крупнее
	r.set_meta("rect", Rect2(Vector2(3, ICON_Y + (26.0 - ih) * 0.5 + 1.0), Vector2(iw, ih)))
	r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	r.modulate = Tex.tint(tex, tint)
	b.add_child(r)
	var fit := fit_title(title, iw)
	var l := UITheme.label(str(fit[1]), int(fit[0]), UITheme.TEXT)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.add_theme_constant_override("line_spacing", -3)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.clip_text = true
	l.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED   # уже переведено и разложено по строкам
	l.set_meta("rect", Rect2(Vector2(3, TITLE_Y), Vector2(iw, TITLE_H if cost != "" else TITLE_H + PRICE_H - 2.0)))
	b.add_child(l)
	if cost != "":
		var pf: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
		var ct := cost
		if pf.get_string_size(ct, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x > iw:
			ct = short_money(ct)
		var pfit := fit_line(ct, iw, 9, 7, pf)
		var c := UITheme.label(str(pfit[1]), int(pfit[0]), cost_col, UITheme.f_semi)
		c.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		c.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		c.mouse_filter = Control.MOUSE_FILTER_IGNORE
		c.clip_text = true
		c.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		c.set_meta("rect", Rect2(Vector2(3, TILE.y - PRICE_H - 3.0), Vector2(iw, PRICE_H)))
		c.set_meta("price", true)
		c.add_theme_stylebox_override("normal", UITheme.sb(Color(0, 0, 0, 0.22), Color(0, 0, 0, 0), 0, 4, 0, 0))
		b.add_child(c)
	if count > 0:
		# 1.40: «есть N» — значок в углу плитки, а не строкой под названием
		var cb := UITheme.label("×%d" % count, 9, Color.WHITE, UITheme.f_semi)
		cb.add_theme_stylebox_override("normal", UITheme.sb(Color(UITheme.GOOD, 0.85), Color(0, 0, 0, 0), 0, 6, 3, 0))
		cb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		cb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		cb.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
		cb.set_meta("count", count)
		var cw := ceilf((UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font).get_string_size(cb.text, HORIZONTAL_ALIGNMENT_LEFT, -1, 9).x) + 6.0
		cb.set_meta("rect", Rect2(Vector2(TILE.x - cw - 3.0, 3.0), Vector2(cw, 13)))
		b.add_child(cb)
	if need:
		var dot := ColorRect.new()
		dot.color = NEED_COL
		dot.set_meta("rect", Rect2(Vector2(4, 4), Vector2(6, 6)))
		dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
		b.add_child(dot)
	var full := "%s — %s" % [title, desc] if desc != "" else title
	if count > 0:
		full = "%s %s" % [full, L.t("Есть: %d.") % count]
	if need:
		full = (L.t("Нужно помещению в центре экрана.") if miss else L.t("Подходит помещению в центре экрана.")) + " " + full
	if lock != "":
		b.disabled = true
		b.modulate = Color(1, 1, 1, 0.42)
		full += L.t(" — закрыто: %s.") % lock
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
	# размеры — уже в дереве: до этого тема ещё не применена и надписи считали бы себя крупнее
	for ch: Node in b.get_children():
		if ch.has_meta("rect"):
			var rc: Rect2 = ch.get_meta("rect")
			(ch as Control).position = rc.position
			(ch as Control).size = rc.size
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
		if r0 in _vow() or r0 in "ьъйЬЪЙ":
			continue
		if lc in _vow() and not (r.length() > 1 and r[1] in _vow()):
			continue
		if not _has_vowel(l) or not _has_vowel(r):
			continue
		var wl := _w(f, l + "-", px)
		var wr := _w(f, r, px)
		if wl <= width and wr <= width and maxf(wl, wr) < best_w:
			best_w = maxf(wl, wr)
			best = i
	return best


## 1.40: в английском переносим и латиницу.
static func _vow() -> String:
	return VOW + "aeiouyAEIOUY" if L.is_en() else VOW


static func _has_vowel(t: String) -> bool:
	for ch in t:
		if ch in _vow():
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
		return L.t("Стройматериалы едут: %s · %s") % [BuildMats.desc(cm), sim._eta_str(eta)]
	var waiting := 0
	for k in need.keys():
		if bm.free_on_ground(str(k)) <= 0:
			waiting += int(need[k])
	if waiting > 0:
		return L.t("Стройка ждёт материал: %d кл. — заказ уйдёт сам") % waiting
	return L.t("Материал на площадке — строят")


static func _money(h: Hud, cost: float, mode: String, arg: Variant) -> Array:
	var lease := mode == "object" and h.sim.market.can_lease(str(arg), cost)
	if lease:
		return [L.t("лизинг %s") % Defs.money_str(roundf(cost * Market.LEASE_ADV)), UITheme.INFO]
	if cost <= 0.0:
		return [L.t("бесплатно"), UITheme.GOOD]
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
	ob.custom_minimum_size = Vector2(120, 0)
	ob.add_item("как задумано", -1)
	var sel := 0
	var n := 1
	for k in items.keys():
		var d: Dictionary = items[k]
		ob.add_item(L.t("%s · %s/кл.") % [L.t(str(d["name"])), Defs.money_str(float(d["cost"]))], int(d["id"]))
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
		_info_def = L.t(text)


# ---------------------------------------------------------------- стройка

static func _build(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	# 1.40: порядок владельца — стены, полы, двери, улица, потом готовые помещения (без «… рамкой»)
	var names := {"wall": ["icon_wall", "Стены"], "floor": ["concrete_0", "Полы"], "open": ["icon_door", "Окна и двери"],
		"yard": ["icon_zone", "Зоны на улице"], "frame": ["icon_room_concrete", "Готовые помещения"]}
	if not BUILD_CATS.has(build_cat):
		build_cat = str(BUILD_CATS[0])
	for k: String in BUILD_CATS:
		var it: Array = names[k]
		_cat(cats, Tex.tile(str(it[0])), str(it[1]), build_cat == k and _q == "", func() -> void:
			build_cat = k
			query["build"] = ""
			h._fill_sub())
	if not h.g.tool.plan_mode:
		head.add_child(_priority(h))
		var ms := mats_status(h.sim)
		if ms != "":
			var ml := UITheme.label(ms, 11, UITheme.INFO)
			ml.clip_text = true
			ml.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			ml.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			ml.tooltip_text = ms
			head.add_child(ml)
	if build_cat == "frame" and _q == "":
		# 1.21: свой пол и свои стены — цена в плитках пересчитывается
		head.add_child(_pick(h, "Пол:", Templates.pick_floor, Defs.floors, func(v: int) -> void: Templates.pick_floor = v))
		var wl := {}
		for wk in Defs.walls.keys():
			if str(Defs.walls[wk].get("kind", "")) == "wall" and bool(Defs.walls[wk].get("buildable", false)):
				wl[wk] = Defs.walls[wk]
		head.add_child(_pick(h, "Стены:", Templates.pick_wall, wl, func(v: int) -> void: Templates.pick_wall = v))
	_search(h, head, "build")
	if _q != "":
		_head_text(head, "Поиск по всем разделам стройки.")
		for c: String in BUILD_CATS:
			_build_tiles(h, head, grid, c)
	else:
		_build_tiles(h, head, grid, build_cat)


static func _build_tiles(h: Hud, head: Control, grid: Control, cat: String) -> void:
	match cat:
		"frame":
			_head_text(head, "Готовые помещения — щёлкните, где поставить: пол, стены, двери, мебель и зона разом. Можно вплотную к готовой стене — она станет общей и не оплачивается.")
			for tk in Defs.templates.keys():
				var td: Dictionary = Defs.templates[tk]
				var tid := str(tk)
				var inn := Templates.inner(tid)
				var tdesc := L.t("%s Внутри %d×%d клеток, снаружи со стенами %d×%d.") % [L.t(str(td.get("desc", ""))), inn.x, inn.y, inn.x + 2, inn.y + 2]
				_tile(h, grid, Tex.ui("zone_" + str(td.get("zone", "workshop"))), str(td["name"]), Defs.money_str(Templates.cost(h.sim, tid)), UITheme.ACCENT, tdesc, "template", tid, Templates.locked(h.sim, tid))
		"floor":
			_head_text(head, "Протяните прямоугольник. Цех — бетон или наливной пол, быт — плитка, кабинеты — линолеум или паркет.")
			for k in Defs.floors.keys():
				var fd: Dictionary = Defs.floors[k]
				var tk := str(fd.get("tex", k))
				_tile(h, grid, Tex.tile("concrete_0" if tk == "concrete" else tk), str(fd["name"]), _per_cell(float(fd["cost"])), UITheme.ACCENT, str(fd.get("desc", "")), "floor", int(fd["id"]))
		"wall", "open":
			_head_text(head, "Стены — контуром прямоугольника. Перегородкой удобно делить большой зал на кабинеты." if cat == "wall" else "Окна, двери и ворота ставят в стену: протяните вдоль неё.")
			var icons := {"brick": "icon_wall", "concrete_wall": "icon_wall_concrete", "sandwich": "icon_wall_sandwich", "partition": "icon_wall_partition",
				"window": "icon_window", "door": "icon_door", "metal_door": "icon_door_metal", "gate": "icon_gate",
				"silicate": "icon_wall_silicate", "gasblock": "icon_wall_gasblock", "glass_door": "icon_door_glass", "gate_warm": "icon_gate_warm"}
			for k2 in Defs.walls.keys():
				var wd: Dictionary = Defs.walls[k2]
				var kind := str(wd.get("kind", ""))
				if not bool(wd.get("buildable", false)):
					continue
				if (cat == "wall") != (kind == "wall"):
					continue
				var mode := "wall" if kind == "wall" else kind
				_tile(h, grid, Tex.tile(str(wd.get("icon", icons.get(k2, "icon_wall")))), str(wd["name"]), _per_cell(float(wd["cost"])), UITheme.ACCENT, str(wd.get("desc", "")), mode, int(wd["id"]))
		"yard":
			_head_text(head, "Зоны на улице рисуют прямоугольником у ворот. Разгрузка и отгрузка обязательны — их можно расширить или перенести, но не убрать. Внутренние зоны — в меню «Зоны».")
			_yard_tiles(h, grid)


## Цена за клетку: «1 200 ₽/кл.».
static func _per_cell(cost: float) -> String:
	return L.t("%s/кл.") % Defs.money_str(cost)


static func _yard_tiles(h: Hud, grid: Control) -> void:
	var stc := Color(str(Defs.rooms.get("_groups", {}).get("store", {}).get("color", "#c9a83a")))
	_tile(h, grid, Tex.ui("zone_unload"), "Разгрузка", "бесплатно", UITheme.GOOD, "Зона разгрузки — сюда фургоны сгружают металл и ящики с оборудованием. Металл кладут на поддоны заготовок (Объекты → Склад), а нет места — на пол зоны; оттуда его разносят к станкам и на стеллажи, ящики — к местам установки. Зона обязательна: последнюю клетку не стереть.", "zone", Logistics.A_UNLOAD, "", stc)
	_tile(h, grid, Tex.ui("zone_ship"), "Отгрузка", "бесплатно", UITheme.GOOD, "Зона отгрузки — сюда приносят готовый заказ, отсюда грузит машина клиента. Готовые детали после ОТК лежат на поддонах готовой продукции; когда заказ готов, рабочие (или погрузчик) переносят их сюда. Зона обязательна: последнюю клетку не стереть.", "zone", Logistics.A_SHIP, "", stc)
	_tile(h, grid, Tex.ui("zone_erase"), "Убрать зону на улице", "", UITheme.MUTED, "выделите область — разгрузка или отгрузка снимется. Обе зоны обязательны: целиком убрать нельзя, только перенести — сначала отметьте новую.", "zone", 0)


# ---------------------------------------------------------------- объекты

static func _objects(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	# 1.40: разделы, где есть нужное помещению в центре экрана, — с бирюзовой рамкой
	var need_cats := {}
	for nk: String in _need.keys():
		need_cats[str(Defs.objects[nk].get("cat", ""))] = true
	for c in Hud.OBJ_CATS:
		var first := ""
		for k in Defs.objects.keys():
			if str(Defs.objects[k].get("cat", "")) == c and not bool(Defs.objects[k].get("legacy", false)):
				first = str(k)
				break
		var cc: String = c
		_cat(cats, Tex.obj(first if first != "chair" else "chair_down") if first != "" else null, c, h.obj_cat == c and _q == "", func() -> void:
			h.obj_cat = cc
			query["objects"] = ""
			h._fill_sub(), NEED_COL if need_cats.has(c) else Color(0, 0, 0, 0))
	if not h.g.tool.plan_mode:
		head.add_child(_priority(h))
	if h.sim.progress.stage >= 2 and not h.g.tool.plan_mode:
		var lz := CheckButton.new()
		lz.text = "Станки в лизинг"
		lz.focus_mode = Control.FOCUS_NONE
		lz.button_pressed = h.sim.market.leasing_on
		lz.add_theme_font_size_override("font_size", 11)
		if not h.sim.dev.on("fin3"):
			lz.disabled = true
			lz.tooltip_text = "Лизинг открывает ступень «Банк и лизинг» (Управление → Развитие), её держит бухгалтер."
		else:
			lz.tooltip_text = L.t("Станки от %s: %d%% сразу, остальное +%d%% платежами %d недель (Финансы → Кредиты и лизинг)") % [Defs.money_str(Market.LEASE_MIN), int(Market.LEASE_ADV * 100.0), int(Market.LEASE_UP * 100.0), Market.LEASE_WEEKS]
		lz.toggled.connect(func(v: bool) -> void:
			h.sim.market.leasing_on = v
			h._fill_sub())
		head.add_child(lz)
	_search(h, head, "objects")
	if focus_type != "" and _info_def == "":
		_info_def = focus_text(h)
	_head_text(head, "Поиск по всем разделам объектов. R — повернуть перед установкой." if _q != "" else "R — повернуть перед установкой.")
	var cnt := {}
	for t0: Thing in h.sim.things.values():
		cnt[t0.def_id] = int(cnt.get(t0.def_id, 0)) + 1
	for k3 in Defs.objects.keys():
		var od: Dictionary = Defs.objects[k3]
		if bool(od.get("legacy", false)):
			continue
		if _q == "" and str(od.get("cat", "")) != h.obj_cat:
			continue
		if _q != "" and not Hud.OBJ_CATS.has(str(od.get("cat", ""))):
			continue
		var sz: Array = od.get("size", [1, 1])
		var desc := L.t("%s Размер %d×%d.") % [L.t(str(od.get("desc", ""))), int(sz[0]), int(sz[1])]
		if od.has("machine") and str(od.get("kind", "")) == "machine":
			desc += " " + Defs.machine_spec(str(k3)) + "."
		if od.has("power"):
			desc += L.t(" Мощность %s кВт.") % str(od["power"])
		var price := h.sim.thing_cost(str(k3))
		var m := _money(h, price, "object", k3)
		_tile(h, grid, Tex.obj(k3 if k3 != "chair" else "chair_down"), str(od["name"]), str(m[0]), m[1], desc, "object", k3, h.sim.progress.locked_reason(str(k3)), Color(0, 0, 0, 0), Color.WHITE, int(cnt.get(str(k3), 0)))


# ---------------------------------------------------------------- зоны

static func _zones(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	var groups: Dictionary = Defs.rooms.get("_groups", {})
	for gk in groups.keys():
		var gd: Dictionary = groups[gk]
		var first := ""
		for t in Rooms.ui_order():
			if str(Defs.rooms.get(t, {}).get("group", "")) == gk:
				first = t
				break
		var gkk: String = gk
		_cat(cats, Tex.ui("zone_" + first), str(gd["name"]), zone_cat == gk, func() -> void:
			zone_cat = gkk
			h._fill_sub(), Color(str(gd["color"])))
	_head_text(head, "Протяните прямоугольник — разметить клетки; щёлкните по помещению — залить его целиком. Соседние клетки одной зоны сливаются.")
	var gc := Color(str(groups.get(zone_cat, {}).get("color", "#888888")))
	for t2 in Rooms.ui_order():
		var d: Dictionary = Defs.rooms.get(t2, {})
		if str(d.get("group", "")) != zone_cat:
			continue
		var lock := ""
		for dk in Defs.departments.keys():
			if str(Defs.departments[dk].get("room", "")) == t2 and not h.sim.progress.dept_open(str(dk)):
				lock = h.sim.progress.dept_lock_text(str(dk))
		var n := h.sim.rooms.of_type(t2, false).size()
		_tile(h, grid, Tex.ui("zone_" + t2), str(d.get("name", t2)), "", UITheme.GOOD, L.t("нужно: %s. %s") % [Rooms.req_text(t2), L.t(str(d.get("desc", "")))], "room", t2, lock, gc, gc.lightened(0.35), n)
	if zone_cat == "store":
		_yard_tiles(h, grid)
	_tile(h, grid, Tex.ui("zone_erase"), "Стереть разметку", "", UITheme.MUTED, "протяните или щёлкните — клетки станут неразмеченными.", "room", "_erase")


# ---------------------------------------------------------------- сети

static func _power(h: Hud, cats: Control, head: Control, grid: Control) -> void:
	var list := [["power", "cable", "Электричество"], ["light", "power", "Освещение"], ["water", "ov_water", "Водопровод и тепло"], ["vent", "ov_vent", "Вентиляция"], ["air", "ov_air", "Сжатый воздух"]]   # 1.38: значки слоёв владельца
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
			_head_text(head, (L.t("Подстанции (%d): %d кВт · нагрузка %.1f кВт. Мало — аккумуляторы вплотную к подстанции.") % [ntr, int(pw.total_kw()), pw.total_load]) if ntr > 0 else "Тока нет: поставьте подстанцию в техпомещении и заведите кабель в её клетку.")
			if h.net_kind == "power":
				_tile(h, grid, Tex.ui("cable"), "Кабель", _per_cell(Defs.b("cable_cost")), UITheme.ACCENT, "протяните мышью — ляжет уголком. Прибор подключён, если кабель заведён прямо в клетку его розетки (жёлтый значок), подстанция — в любую её клетку.", "cable", null)
				_tile(h, grid, Tex.ui("uncable"), "Снять кабель", "", UITheme.MUTED, "выделите область — вернётся 30% стоимости.", "uncable", null)
			for k in Defs.objects.keys():
				var od: Dictionary = Defs.objects[k]
				if str(od.get("cat", "")) != ("Электрика" if h.net_kind == "power" else "Освещение") or bool(od.get("legacy", false)):
					continue
				var desc := L.t(str(od.get("desc", "")))
				if od.has("capacity_kw"):
					desc += L.t(" Мощность %d кВт.") % int(od["capacity_kw"])
				var m := _money(h, h.sim.thing_cost(str(k)), "object", k)
				_tile(h, grid, Tex.obj(k), str(od["name"]), str(m[0]), m[1], desc, "object", k, h.sim.progress.locked_reason(str(k)))
		"water":
			_head_text(head, "Насосная станция — в техпомещении; трубы тяните от неё прямо в клетки туалетов, раковин и котла (синий кружок).")
			_tile(h, grid, Tex.tile("icon_pipe"), "Труба", _per_cell(Defs.b("pipe_cost")), UITheme.ACCENT, "протяните мышью — ляжет уголком.", "pipe", null)
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
			_tile(h, grid, Tex.tile("icon_" + lay), "Воздуховод" if vent else "Пневмомагистраль", _per_cell(Defs.b(lay + "_cost")), UITheme.ACCENT, "протяните мышью — линия ляжет уголком.", lay, null)
			_tile(h, grid, Tex.tile("icon_un" + lay), "Снять", "", UITheme.MUTED, "выделите область — вернётся 30% стоимости.", "un" + lay, null)
			for kv in Defs.objects.keys():
				if str(Defs.objects[kv].get("net", "")) == h.net_kind:
					_net_tile(h, grid, str(kv))


static func _net_tile(h: Hud, grid: Control, k: String) -> void:
	var od: Dictionary = Defs.objects[k]
	var m := _money(h, h.sim.thing_cost(k), "object", k)
	_tile(h, grid, Tex.obj(k), str(od["name"]), str(m[0]), m[1], str(od.get("desc", "")), "object", k, h.sim.progress.locked_reason(k))
