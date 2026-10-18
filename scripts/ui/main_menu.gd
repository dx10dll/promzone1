extends Node2D
## Главное меню. На фоне идёт живая симуляция гаража, камера медленно плывёт.

const VERSION_TEXT := "Версия 1.23"

var sim: Sim
var cam := Camera2D.new()
var ui := Control.new()
var menu_box: VBoxContainer
var sub: PanelContainer = null
var _t := 0.0

## 1.17: сменяющиеся виды завода (MenuScenes) с плавным переходом через затемнение.
const SCENE_TIME := 13.0
const FADE := 0.7
var sims := {}             ## ключ вида -> Sim (готовые и готовящиеся)
var scene_i := 0
var scene_t := 0.0
var scene_root: Node2D = null
var fade_rect: ColorRect
var _fading := 0           ## 0 — показ, 1 — затемняем, 2 — проявляем
var _fade_t := 0.0


func _ready() -> void:
	sims["garage"] = MenuScenes.build("garage")
	MenuScenes.advance(sims["garage"], "garage", 4000)
	add_child(cam)
	cam.make_current()
	_show_scene()
	Snd.stop_ambient()
	Snd.set_playlist(["music_waltz"])
	var fl := CanvasLayer.new()
	fl.layer = 1
	add_child(fl)
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.03, 0.035, 0.04, 0.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fl.add_child(fade_rect)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UITheme.build()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_build_ui()


func _exit_tree() -> void:
	for k in sims.keys():
		(sims[k] as Sim).dispose()
	sims.clear()


func _scene_name() -> String:
	return str(MenuScenes.ORDER[scene_i % MenuScenes.ORDER.size()])


## Собрать мир для текущего вида (вид «cnc» — тот же цех, другая камера).
func _show_scene() -> void:
	var key := MenuScenes.sim_key(_scene_name())
	if not sims.has(key):
		sims[key] = MenuScenes.build(key)
	MenuScenes.advance(sims[key], key, 4000)
	sim = sims[key]
	if scene_root:
		scene_root.queue_free()
	scene_root = Node2D.new()
	add_child(scene_root)
	move_child(scene_root, 0)
	var root := Node2D.new()
	scene_root.add_child(root)
	var wv := WorldView.new()
	wv.sim = sim
	root.add_child(wv)
	var dn := DayNight.new()
	dn.setup(sim, root, root)
	scene_root.add_child(dn)
	var ents := EntityLayer.new()
	ents.sim = sim
	root.add_child(ents)
	var sign := CompanySign.new()
	sign.sim = sim
	root.add_child(sign)
	scene_t = 0.0
	_place_cam(0.0)


func _place_cam(k: float) -> void:
	var cd: Array = MenuScenes.CAMS[_scene_name()]
	var e := k * k * (3.0 - 2.0 * k)
	var z := float(cd[2]) * (1.0 + 0.05 * e)
	cam.zoom = Vector2(z, z)
	var vw := get_viewport().get_visible_rect().size.x
	cam.position = (cd[0] as Vector2).lerp(cd[1] as Vector2, e) * World.T - Vector2(vw * 0.17 / z, 0.0)
	# люди — из вектора под текущий масштаб: без этого в меню они расплывались
	Tex.set_people_scale(z * get_viewport().get_final_transform().get_scale().x * 0.5)
	Tex.ui_scale = get_viewport().get_final_transform().get_scale().x


func _process(delta: float) -> void:
	_t += delta
	scene_t += delta
	sim.tick(minf(delta, 0.1) * 1.6)
	_place_cam(clampf(scene_t / SCENE_TIME, 0.0, 1.0))
	# следующий вид готовится заранее, понемногу каждый кадр
	var nk := MenuScenes.sim_key(str(MenuScenes.ORDER[(scene_i + 1) % MenuScenes.ORDER.size()]))
	if sims.has(nk) and nk != MenuScenes.sim_key(_scene_name()):
		MenuScenes.advance(sims[nk], nk, 3)
	elif not sims.has(nk) and scene_t > 2.0:
		sims[nk] = MenuScenes.build(nk)
	match _fading:
		0:
			if scene_t > SCENE_TIME - FADE:
				_fading = 1
				_fade_t = 0.0
		1:
			_fade_t += delta
			fade_rect.color.a = clampf(_fade_t / FADE, 0.0, 1.0)
			if _fade_t >= FADE:
				scene_i += 1
				_show_scene()
				_fading = 2
				_fade_t = 0.0
		2:
			_fade_t += delta
			fade_rect.color.a = 1.0 - clampf(_fade_t / (FADE * 1.3), 0.0, 1.0)
			if _fade_t >= FADE * 1.3:
				_fading = 0


func _build_ui() -> void:
	var shade := TextureRect.new()
	var grad := Gradient.new()
	grad.set_color(0, Color(0.07, 0.08, 0.09, 0.96))
	grad.set_color(1, Color(0.07, 0.08, 0.09, 0.0))
	grad.add_point(0.6, Color(0.07, 0.08, 0.09, 0.9))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0, 0)
	gt.fill_to = Vector2(1, 0)
	gt.width = 256
	gt.height = 8
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.stretch_mode = TextureRect.STRETCH_SCALE
	shade.anchor_bottom = 1.0
	shade.offset_right = 820
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(shade)
	var col := UITheme.vbox(14)
	col.anchor_top = 0.5
	col.anchor_bottom = 0.5
	col.offset_left = 90
	col.offset_top = -260
	col.offset_right = 520
	col.offset_bottom = 260
	ui.add_child(col)
	# 1.17: заголовок — векторный логотип, растеризуется под точный размер экрана (чётко на любом мониторе)
	var t := Logo.new()
	col.add_child(t)
	# предупредительная полоса вместо простой черты — как на кромке станка
	var line := FactoryUI.Hazard.new()
	line.custom_minimum_size = Vector2(200, 7)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(line)
	col.add_child(UITheme.label("Симулятор российского завода — от гаража до гиганта", 18, UITheme.MUTED))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 18)
	col.add_child(gap)
	menu_box = UITheme.vbox(10)
	menu_box.custom_minimum_size = Vector2(340, 0)
	menu_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu_box)
	_fill_menu()
	var ver := UITheme.label(VERSION_TEXT + " · шрифт IBM Plex Sans (SIL OFL)", 12, Color(1, 1, 1, 0.45))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 24
	ver.offset_top = -34
	ui.add_child(ver)


func _big(text: String, cb: Callable, sub_text: String = "") -> Button:
	var b := UITheme.button(text, cb)
	b.custom_minimum_size = Vector2(340, 50)
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 19)
	b.add_theme_font_override("font", UITheme.f_med)
	if sub_text != "":
		b.tooltip_text = sub_text
	menu_box.add_child(b)
	return b


## Главная кнопка: янтарная, тёмный текст (читается лучше светлого на жёлтом).
func _amber(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.sb(UITheme.ACCENT, UITheme.ACCENT, 1, 7, 16, 6))
	b.add_theme_stylebox_override("hover", UITheme.sb(Color("#ecb84c"), Color("#ecb84c"), 1, 7, 16, 6))
	b.add_theme_color_override("font_color", UITheme.ACCENT_T)
	b.add_theme_color_override("font_hover_color", UITheme.ACCENT_T)
	b.add_theme_font_override("font", UITheme.f_semi)


func _fill_menu() -> void:
	UITheme.clear(menu_box)
	var saves := Game.list_saves()
	if not saves.is_empty() and not bool((saves[0] as Dictionary).get("broken", false)):
		var s: Dictionary = saves[0]
		var b := _big("Продолжить", func() -> void: Game.start_load(str(s["slot"])))
		var hint := UITheme.label("   %s%s · сохранено %s" % [(str(s["company"]) + " · ") if s.has("company") else "", Defs.money_str(float(s.get("money", 0))), Game.pc_time(str(s.get("saved_at", "")))], 13, UITheme.MUTED)
		menu_box.add_child(hint)
		_amber(b)
	_big("Новая игра", _show_new_game, "Выбор профиля завода, сценария и рассказчика.")
	var lb := _big("Загрузить", _show_load)
	lb.disabled = saves.is_empty()
	_big("Достижения", _show_achievements)
	_big("Настройки", _show_settings)
	_big("Выход", func() -> void: get_tree().quit())


func _panel(title: String) -> VBoxContainer:
	if ng_root:
		ng_root.queue_free()
		ng_root = null
	if sub:
		sub.queue_free()
	sub = PanelContainer.new()
	sub.add_theme_stylebox_override("panel", UITheme.sb(UITheme.BG, UITheme.LINE, 1, 10, 20, 16))
	sub.anchor_top = 0.5
	sub.anchor_bottom = 0.5
	sub.offset_left = 520
	sub.offset_top = -220
	sub.offset_right = 1120
	sub.offset_bottom = 220
	ui.add_child(sub)
	var v := UITheme.vbox(10)
	sub.add_child(v)
	var h := UITheme.hbox(8)
	h.add_child(UITheme.title(title, 22))
	h.add_child(UITheme.spacer())
	h.add_child(UITheme.button("×", func() -> void:
		sub.queue_free()
		sub = null))
	v.add_child(h)
	return v


## Новая игра: профиль завода, сценарий, рассказчик (и параметры песочницы).
var ng := {"profile": "mech", "scn": "garage", "story": "market", "tutorial": true, "money": 1000000, "map": "large", "start": "garage", "all_open": true, "page": 1, "company": {}}
var ng_root: PanelContainer = null


func _show_new_game() -> void:
	ng["page"] = 1
	if sub:
		sub.queue_free()
		sub = null
	if ng_root:
		ng_root.queue_free()
	ng_root = PanelContainer.new()
	ng_root.add_theme_stylebox_override("panel", UITheme.sb(Color(0.11, 0.12, 0.135, 0.98), UITheme.LINE, 1, 12, 22, 18))
	ng_root.anchor_left = 0.5
	ng_root.anchor_right = 0.5
	ng_root.anchor_top = 0.5
	ng_root.anchor_bottom = 0.5
	ng_root.offset_left = -640
	ng_root.offset_right = 640
	ng_root.offset_top = -385
	ng_root.offset_bottom = 385
	ui.add_child(ng_root)
	_fill_new_game()


func _fill_new_game() -> void:
	UITheme.clear(ng_root)
	if int(ng["page"]) == 2:
		_fill_company()
		return
	var root := UITheme.vbox(12)
	ng_root.add_child(root)
	var head := UITheme.hbox(10)
	head.add_child(UITheme.title("Новая игра", 26))
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.button("×", func() -> void:
		ng_root.queue_free()
		ng_root = null))
	root.add_child(head)
	var cols := UITheme.hbox(16)
	cols.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(cols)
	# 1. профиль
	var c1 := UITheme.vbox(6)
	c1.custom_minimum_size = Vector2(390, 0)
	c1.add_child(UITheme.label("1. Что производим", 17, UITheme.TEXT, UITheme.f_semi))
	var allowed: Array = Defs.scenarios.get(str(ng["scn"]), {}).get("profiles", [])
	for k in Defs.profiles.keys():
		var pd: Dictionary = Defs.profiles[k]
		var key := str(k)
		var locked := bool(pd.get("locked", false))
		var off := locked or (not allowed.is_empty() and not allowed.has(key))
		var b := Button.new()
		b.toggle_mode = true
		b.button_pressed = key == str(ng["profile"])
		b.focus_mode = Control.FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.custom_minimum_size = Vector2(380, 54)
		b.text = "%s   %s\n%s" % [str(pd["name"]), "★".repeat(int(pd.get("difficulty", 1))) + "☆".repeat(5 - int(pd.get("difficulty", 1))), str(pd.get("prod", ""))]
		b.add_theme_font_size_override("font_size", 14)
		var prods: Array = pd.get("products", [])
		if not prods.is_empty():
			b.icon = Tex.item(str(prods[mini(prods.size() - 1, 4)]))
			b.expand_icon = false
		b.disabled = off
		if locked:
			b.tooltip_text = "Появится в следующих версиях"
		elif off:
			b.tooltip_text = "В сценарии «%s» доступны: %s" % [str(Defs.scenarios[str(ng["scn"])]["name"]), ", ".join(PackedStringArray(allowed.map(func(x: Variant) -> String: return str(Defs.profiles[str(x)]["name"]))))]
		b.pressed.connect(func() -> void:
			ng["profile"] = key
			_fill_new_game())
		c1.add_child(b)
	cols.add_child(c1)
	# 2. сценарий
	var c2 := UITheme.vbox(6)
	c2.custom_minimum_size = Vector2(330, 0)
	c2.add_child(UITheme.label("2. С чего начинаем", 17, UITheme.TEXT, UITheme.f_semi))
	for k2 in Defs.scenarios.keys():
		var sd: Dictionary = Defs.scenarios[k2]
		var key2 := str(k2)
		var b2 := Button.new()
		b2.toggle_mode = true
		b2.button_pressed = key2 == str(ng["scn"])
		b2.focus_mode = Control.FOCUS_NONE
		b2.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b2.custom_minimum_size = Vector2(320, 62)
		b2.icon = Tex.ui("scn_" + key2)
		b2.expand_icon = false
		b2.add_theme_constant_override("icon_max_width", 36)
		b2.text = "%s\n%s" % [str(sd["name"]), str(sd.get("tag", ""))]
		b2.add_theme_font_size_override("font_size", 15)
		b2.pressed.connect(func() -> void:
			ng["scn"] = key2
			var al: Array = sd.get("profiles", [])
			if not al.is_empty() and not al.has(str(ng["profile"])):
				ng["profile"] = str(al[0])
			_fill_new_game())
		c2.add_child(b2)
	cols.add_child(c2)
	# 3. детали и рассказчик
	var c3 := UITheme.vbox(8)
	c3.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var pd2: Dictionary = Defs.profiles[str(ng["profile"])]
	var sd2: Dictionary = Defs.scenarios[str(ng["scn"])]
	c3.add_child(UITheme.label("%s · «%s»" % [str(pd2["name"]), str(sd2["name"])], 18, UITheme.TEXT, UITheme.f_semi))
	c3.add_child(_wrapped(str(sd2.get("desc", "")), 14, UITheme.TEXT))
	c3.add_child(_wrapped(str(pd2.get("desc", "")), 14, UITheme.MUTED))
	c3.add_child(_wrapped("Цеха: %s. %s" % [str(pd2.get("shops", "")), str(pd2.get("mechanic", ""))], 13, UITheme.INFO))
	var goals: Array = sd2.get("goals", [])
	if not goals.is_empty():
		c3.add_child(_wrapped("Цели: " + "; ".join(PackedStringArray(goals.map(func(g: Dictionary) -> String: return str(g.get("text", ""))))) + ".", 13, UITheme.GOOD))
	c3.add_child(HSeparator.new())
	c3.add_child(UITheme.label("3. Рассказчик", 17, UITheme.TEXT, UITheme.f_semi))
	var srow := UITheme.hbox(6)
	for m in Story.MODES:
		var md: Dictionary = Defs.events.get("modes", {}).get(m, {})
		var cb := Button.new()
		cb.toggle_mode = true
		cb.text = str(md.get("name", m))
		cb.tooltip_text = str(md.get("desc", ""))
		cb.button_pressed = m == str(ng["story"])
		cb.focus_mode = Control.FOCUS_NONE
		cb.add_theme_font_size_override("font_size", 13)
		var mm: String = m
		cb.pressed.connect(func() -> void:
			ng["story"] = mm
			_fill_new_game())
		srow.add_child(cb)
	c3.add_child(srow)
	c3.add_child(_wrapped(str(Defs.events.get("modes", {}).get(str(ng["story"]), {}).get("desc", "")), 13, UITheme.MUTED))
	if str(ng["scn"]) == "garage":
		var tut := CheckBox.new()
		tut.text = "Обучение по шагам"
		tut.button_pressed = bool(ng["tutorial"])
		tut.focus_mode = Control.FOCUS_NONE
		tut.toggled.connect(func(v: bool) -> void: ng["tutorial"] = v)
		c3.add_child(tut)
	if str(ng["scn"]) == "sandbox":
		c3.add_child(HSeparator.new())
		c3.add_child(UITheme.label("Песочница", 15, UITheme.TEXT, UITheme.f_semi))
		c3.add_child(_option("Деньги", [[300000, "300 тыс."], [1000000, "1 млн"], [5000000, "5 млн"], [50000000, "50 млн"]], "money"))
		c3.add_child(_option("Участок", [["small", "Малый (48×36)"], ["large", "Большой (64×44)"]], "map"))
		var ao := CheckBox.new()
		ao.text = "Всё открыто сразу"
		ao.button_pressed = bool(ng["all_open"])
		ao.focus_mode = Control.FOCUS_NONE
		ao.toggled.connect(func(v: bool) -> void: ng["all_open"] = v)
		c3.add_child(ao)
	var sp := Control.new()
	sp.size_flags_vertical = Control.SIZE_EXPAND_FILL
	c3.add_child(sp)
	var go := UITheme.button("Далее: ваш завод  →", func() -> void:
		ng["page"] = 2
		_fill_new_game())
	go.custom_minimum_size = Vector2(0, 50)
	go.add_theme_font_size_override("font_size", 20)
	_amber(go)
	c3.add_child(go)
	cols.add_child(c3)


## 1.17: шаг 2 — название и эмблема завода.
func _fill_company() -> void:
	var root := UITheme.vbox(14)
	ng_root.add_child(root)
	var head := UITheme.hbox(10)
	head.add_child(UITheme.title("Новая игра · ваш завод", 26))
	head.add_child(UITheme.spacer())
	head.add_child(UITheme.button("×", func() -> void:
		ng_root.queue_free()
		ng_root = null))
	root.add_child(head)
	root.add_child(_wrapped("Придумайте название и соберите эмблему: они будут в шапке игры, на вывеске у ворот, в заводской многотиражке и на табличках в цехе. Поменять можно потом — щелчком по эмблеме в шапке.", 14, UITheme.MUTED))
	var ed := EmblemEditor.new(ng["company"], str(ng["scn"]) != "garage", str(ng["profile"]))
	ed.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root.add_child(ed)
	var bh := UITheme.hbox(10)
	var back := UITheme.button("←  Назад", func() -> void:
		ng["page"] = 1
		_fill_new_game())
	back.custom_minimum_size = Vector2(160, 50)
	bh.add_child(back)
	var sd: Dictionary = Defs.scenarios[str(ng["scn"])]
	var pd: Dictionary = Defs.profiles[str(ng["profile"])]
	var sum := UITheme.label("%s · «%s» · рассказчик: %s" % [str(pd["name"]), str(sd["name"]), str(Defs.events.get("modes", {}).get(str(ng["story"]), {}).get("name", ng["story"]))], 14, UITheme.MUTED)
	sum.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sum.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	bh.add_child(sum)
	var go := UITheme.button("Начать", func() -> void:
		var cd: Dictionary = ng["company"]
		var nm := Company.clean_name(str(cd.get("name", "")))
		var opts := {"tutorial": bool(ng["tutorial"]) and str(ng["scn"]) == "garage", "money": ng["money"], "map": ng["map"], "start": ng["start"], "all_open": ng["all_open"], "flora": true, "lots": true,
			"company": {"name": nm if nm != "" else "Прогресс", "emblem": (cd.get("emblem", {}) as Dictionary).duplicate()}}
		Game.start_new_game(0, str(ng["story"]), str(ng["scn"]), str(ng["profile"]), opts))
	go.custom_minimum_size = Vector2(240, 50)
	go.add_theme_font_size_override("font_size", 20)
	_amber(go)
	bh.add_child(go)
	root.add_child(bh)


func _wrapped(t: String, size: int, col: Color) -> Label:
	var l := UITheme.label(t, size, col)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(440, 0)
	return l


func _option(title: String, items: Array, key: String) -> HBoxContainer:
	var h := UITheme.hbox(8)
	var l := UITheme.label(title, 14)
	l.custom_minimum_size = Vector2(80, 0)
	h.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	for i in items.size():
		ob.add_item(str(items[i][1]))
		if items[i][0] == ng[key]:
			ob.select(i)
	ob.item_selected.connect(func(i: int) -> void: ng[key] = items[i][0])
	h.add_child(ob)
	return h


func _show_load() -> void:
	var v := _panel("Загрузить игру")
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lv := UITheme.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	v.add_child(sc)
	for s: Dictionary in Game.list_saves():
		var slot := str(s["slot"])
		var row := UITheme.panel(UITheme.BG2)
		var h := UITheme.hbox(10)
		row.add_child(h)
		var em: Variant = s.get("emblem", {})
		if em is Dictionary and not (em as Dictionary).is_empty():
			h.add_child(Emblem.View.new(em, 40.0))
		var iv := UITheme.vbox(0)
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(UITheme.label(str(s.get("title", slot)) + ((" · " + str(s["company"])) if s.has("company") else ""), 15, UITheme.TEXT, UITheme.f_med))
		iv.add_child(UITheme.label("Сохранено %s · в игре %s %s · %s" % [Game.pc_time(str(s.get("saved_at", ""))), str(s.get("date", "")), str(s.get("time", "")), Defs.money_str(float(s.get("money", 0)))], 12, UITheme.MUTED))
		h.add_child(iv)
		var b := UITheme.button("Загрузить", func() -> void: Game.start_load(slot))
		b.disabled = bool(s.get("broken", false))
		h.add_child(b)
		var del := func() -> void:
			Game.delete_save(slot)
			_fill_menu()
			_show_load()
		h.add_child(UITheme.button("×", del, "Удалить"))
		lv.add_child(row)


func _show_achievements() -> void:
	Achievements.load_all()
	var v := _panel("Достижения · %d из %d" % [Achievements.got_count(), Achievements.defs.size()])
	sub.offset_top = -330
	sub.offset_bottom = 330
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var lv := UITheme.vbox(6)
	lv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(lv)
	v.add_child(sc)
	for a: Dictionary in Achievements.defs:
		var has := Achievements.got.has(str(a["id"]))
		var row := UITheme.panel(UITheme.BG2)
		var h := UITheme.hbox(10)
		row.add_child(h)
		var ic := TextureRect.new()
		ic.texture = Tex.ui("medal" if has else "medal_off")
		ic.custom_minimum_size = Vector2(34, 34)
		ic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		ic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		h.add_child(ic)
		var iv := UITheme.vbox(0)
		iv.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		iv.add_child(UITheme.label(str(a["name"]), 15, UITheme.TEXT if has else UITheme.MUTED, UITheme.f_med))
		iv.add_child(UITheme.label(str(a["desc"]), 12, UITheme.MUTED))
		h.add_child(iv)
		if has:
			h.add_child(UITheme.label(str(Achievements.got[str(a["id"])]), 12, UITheme.GOOD))
		lv.add_child(row)


func _show_settings() -> void:
	var v := _panel("Настройки")
	sub.offset_top = -330
	sub.offset_bottom = 330
	SettingsUI.build(v)
	v.add_child(UITheme.label("Сохранения и настройки лежат в папке пользователя:\n" + ProjectSettings.globalize_path("user://"), 12, UITheme.MUTED))


## Векторный логотип «ПРОМЗОНА» (assets/vec/logo.json, tools/gen_logo.py).
class Logo:
	extends Control
	var _svg := ""
	var _ratio := 8.0
	var _w := 608.0
	var _tex: Texture2D = null
	var _px := 0

	func _init() -> void:
		var f := FileAccess.get_file_as_string("res://assets/vec/logo.json")
		var d: Variant = JSON.parse_string(f)
		if d is Dictionary:
			_svg = str(d.get("svg", ""))
			_w = float(d.get("w", 608))
			_ratio = _w / maxf(1.0, float(d.get("h", 76)))
		custom_minimum_size = Vector2(430, 430 / _ratio)
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if _svg == "":
			return
		var sc := get_viewport().get_final_transform().get_scale().x
		var want := int(ceilf(size.x * sc))
		if want != _px:
			_px = want
			var img := Image.new()
			if img.load_svg_from_string(_svg, float(want) / _w) == OK:
				_tex = ImageTexture.create_from_image(img)
		if _tex:
			draw_texture_rect(_tex, Rect2(Vector2.ZERO, Vector2(size.x, size.x / _ratio)), false)

