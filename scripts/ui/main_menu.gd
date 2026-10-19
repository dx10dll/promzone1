extends Node2D
## Главное меню. 1.24: новый вид — слева тёмная панель с логотипом и пунктами со значками,
## справа внизу подпись к фону («Механический цех · 10:00») и полоса смены видов,
## справа вверху — что нового в версии. Фон — показательный завод в течение дня (MenuScenes).

const VERSION_TEXT := "Версия 1.36"
const WHATS_NEW := ["Новые портреты: цельные фигуры без стыков шеи", "Новые иконки меню снова в игре", "«Создать рабочего» больше не тормозит"]

var sim: Sim
var cam := Camera2D.new()
var ui := Control.new()
var menu_box: VBoxContainer
var sub: PanelContainer = null
var _t := 0.0

const SCENE_TIME := 12.0
const FADE := 0.55
var worlds: Array[Sim] = []     ## два одинаковых завода: один показываем, второй проматываем к следующему виду
var cur := 0                    ## какой из двух сейчас на экране
var scene_i := 0
var scene_t := 0.0
var scene_root: Node2D = null
var city: CityBackdrop = null
var fade_rect: ColorRect
var _fading := 0                ## 0 — показ, 1 — затемняем, 2 — проявляем
var _fade_t := 0.0
var _next_target := 0.0         ## к какой минуте проматываем второй завод
var cap_title: Label
var cap_time: Label
var cap_bar: SceneBar
var ng_dim: ColorRect           ## затемнение под окном «Новая игра»
var _cards: Array[Control] = [] ## карточки «Сейчас на заводе» и «Что нового» — прячем под окнами


func _ready() -> void:
	for i in 2:
		worlds.append(MenuScenes.build())
	var w0 := worlds[0]
	MenuScenes.advance_to(w0, MenuScenes.next_minute(w0.minute, MenuScenes.tod_of(0)), 2000)
	_next_target = MenuScenes.next_minute(w0.minute + 1.0, MenuScenes.tod_of(1))
	add_child(cam)
	cam.make_current()
	_show_scene()
	Snd.stop_ambient()
	Snd.set_playlist(MusicDirector.MENU)   # 1.31: плавно, из игры — перекрёстным затуханием
	var vl := CanvasLayer.new()
	vl.layer = 1
	add_child(vl)
	vl.add_child(_vignette())
	fade_rect = ColorRect.new()
	fade_rect.color = Color(0.03, 0.035, 0.04, 0.0)
	fade_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vl.add_child(fade_rect)
	var layer := CanvasLayer.new()
	layer.layer = 2
	add_child(layer)
	ui.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	ui.theme = UITheme.build()
	ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(ui)
	_build_ui()


func _exit_tree() -> void:
	for s in worlds:
		s.dispose()
	worlds.clear()


func _vignette() -> ColorRect:
	var vig := ColorRect.new()
	vig.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 d = (UV - vec2(0.55, 0.5)) * vec2(1.3, 1.0);
	float v = smoothstep(0.35, 0.95, length(d));
	COLOR = vec4(0.02, 0.025, 0.035, v * 0.55);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	return vig


## Собрать картинку текущего вида на заводе worlds[cur].
func _show_scene() -> void:
	sim = worlds[cur]
	if scene_root:
		scene_root.queue_free()
	scene_root = Node2D.new()
	add_child(scene_root)
	move_child(scene_root, 0)
	var root := Node2D.new()
	scene_root.add_child(root)
	city = CityBackdrop.new()
	city.sim = sim
	root.add_child(city)
	var wv := WorldView.new()
	wv.sim = sim
	root.add_child(wv)
	var dn := DayNight.new()
	dn.setup(sim, root, root)
	scene_root.add_child(dn)
	var ents := EntityLayer.new()
	ents.sim = sim
	root.add_child(ents)
	var fauna := FaunaLayer.new()
	fauna.sim = sim
	root.add_child(fauna)
	var cranes := CraneLayer.new()
	cranes.sim = sim
	root.add_child(cranes)
	var sign := CompanySign.new()
	sign.sim = sim
	root.add_child(sign)
	var fx := FxLayer.new()
	root.add_child(fx)
	fx.setup(sim, root)
	var life := AmbientLife.new()
	life.sim = sim
	root.add_child(life)
	if MenuScenes.key(scene_i) == "overview" and city.life:
		city.life.soon()   # с высоты — пусть по ветке как раз идёт поезд
	scene_t = 0.0
	_place_cam(0.0)
	_update_caption()


func _place_cam(k: float) -> void:
	var cd := MenuScenes.cam(scene_i)
	var e := k * k * (3.0 - 2.0 * k)
	var z := float(cd[2]) * (1.0 + 0.06 * e)
	cam.zoom = Vector2(z, z)
	var vw := get_viewport().get_visible_rect().size.x
	# предмет вида — правее центра: слева панель меню
	cam.position = (cd[0] as Vector2).lerp(cd[1] as Vector2, e) * World.T - Vector2(vw * 0.16 / z, 0.0)
	var pe := z * get_viewport().get_final_transform().get_scale().x * 0.5
	if ng_root is CustomWorkersUI and is_instance_valid(ng_root):
		pe = maxf(pe, CustomWorkersUI.DOLL_Z * get_viewport().get_final_transform().get_scale().x * 0.5)   # человечек в редакторе — чёткий
	Tex.set_people_scale(pe)
	Tex.ui_scale = get_viewport().get_final_transform().get_scale().x


func _process(delta: float) -> void:
	_t += delta
	scene_t += delta
	sim.tick(minf(delta, 0.1) * 1.2)
	_place_cam(clampf(scene_t / SCENE_TIME, 0.0, 1.0))
	# второй завод тем временем проматывается к времени следующего вида
	var other := worlds[1 - cur]
	var ready := MenuScenes.advance_to(other, _next_target, 6)
	if cap_bar:
		cap_bar.k = clampf(scene_t / SCENE_TIME, 0.0, 1.0)
		cap_bar.queue_redraw()
	if cap_time and int(_t * 2.0) % 2 == 0:
		cap_time.text = _time_text()
	var big := ng_root != null and is_instance_valid(ng_root)
	if ng_dim:
		ng_dim.visible = big
	var any := big or (sub != null and is_instance_valid(sub))
	for c in _cards:
		c.modulate.a = move_toward(c.modulate.a, 0.0 if any else 1.0, delta * 5.0)
	match _fading:
		0:
			if scene_t > SCENE_TIME - FADE and ready:
				_fading = 1
				_fade_t = 0.0
		1:
			_fade_t += delta
			fade_rect.color.a = clampf(_fade_t / FADE, 0.0, 1.0)
			if _fade_t >= FADE:
				scene_i = (scene_i + 1) % MenuScenes.count()
				cur = 1 - cur
				_show_scene()
				var shown := worlds[cur]
				_next_target = MenuScenes.next_minute(shown.minute + 1.0, MenuScenes.tod_of(scene_i + 1))
				_fading = 2
				_fade_t = 0.0
		2:
			_fade_t += delta
			fade_rect.color.a = 1.0 - clampf(_fade_t / (FADE * 1.4), 0.0, 1.0)
			if _fade_t >= FADE * 1.4:
				_fading = 0


## Для снимков и тестов: сразу показать вид i (завод проматывается к его времени).
func jump(i: int) -> void:
	scene_i = i % MenuScenes.count()
	var w := worlds[cur]
	MenuScenes.advance_to(w, MenuScenes.next_minute(w.minute, MenuScenes.tod_of(scene_i)), 4000)
	_show_scene()
	scene_t = 4.0
	_next_target = MenuScenes.next_minute(w.minute + 1.0, MenuScenes.tod_of(scene_i + 1))


func _time_text() -> String:
	var tod := int(sim.tod())
	var days := ["понедельник", "вторник", "среда", "четверг", "пятница", "суббота", "воскресенье"]
	return "%02d:%02d · %s" % [tod / 60, tod % 60, days[(sim.day() - 1) % 7]]


func _update_caption() -> void:
	if cap_title == null:
		return
	cap_title.text = MenuScenes.caption(scene_i)
	cap_time.text = _time_text()
	cap_bar.i = scene_i
	cap_bar.k = 0.0
	cap_bar.queue_redraw()


func _build_ui() -> void:
	var back := SidePanel.new()
	back.anchor_bottom = 1.0
	back.offset_right = 860
	ui.add_child(back)
	var col := UITheme.vbox(0)
	col.anchor_bottom = 1.0
	col.offset_left = 72
	col.offset_right = 470
	col.offset_top = 0
	ui.add_child(col)
	var top := Control.new()
	top.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top.custom_minimum_size = Vector2(0, 60)
	col.add_child(top)
	col.add_child(Logo.new())
	var g1 := Control.new()
	g1.custom_minimum_size = Vector2(0, 12)
	col.add_child(g1)
	var line := FactoryUI.Hazard.new()
	line.custom_minimum_size = Vector2(150, 6)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(line)
	var g2 := Control.new()
	g2.custom_minimum_size = Vector2(0, 14)
	col.add_child(g2)
	var tag := UITheme.label("Симулятор российского завода — от гаража до гиганта", 16, Color(0.93, 0.9, 0.84, 0.78))
	col.add_child(tag)
	var g3 := Control.new()
	g3.custom_minimum_size = Vector2(0, 40)
	col.add_child(g3)
	menu_box = UITheme.vbox(6)
	menu_box.custom_minimum_size = Vector2(380, 0)
	menu_box.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	col.add_child(menu_box)
	_fill_menu()
	var bottom := Control.new()
	bottom.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom.custom_minimum_size = Vector2(0, 60)
	col.add_child(bottom)
	var ver := UITheme.label(VERSION_TEXT + "  ·  шрифты IBM Plex Sans (SIL OFL) и DejaVu Sans", 12, Color(1, 1, 1, 0.38))
	ver.anchor_top = 1.0
	ver.anchor_bottom = 1.0
	ver.offset_left = 72
	ver.offset_top = -40
	ui.add_child(ver)
	_build_caption()
	_build_news()
	ng_dim = ColorRect.new()
	ng_dim.color = Color(0.03, 0.035, 0.04, 0.62)
	ng_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	ng_dim.visible = false
	ui.add_child(ng_dim)


## Подпись к фону справа внизу: что показываем, время на заводе, полоса смены видов.
func _build_caption() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.sb(Color(0.07, 0.08, 0.09, 0.72), Color(1, 1, 1, 0.07), 1, 10, 18, 12))
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.anchor_top = 1.0
	box.anchor_bottom = 1.0
	box.offset_left = -340
	box.offset_right = -36
	box.offset_top = -132
	box.offset_bottom = -36
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(box)
	_cards.append(box)
	var v := UITheme.vbox(4)
	box.add_child(v)
	v.add_child(UITheme.label("СЕЙЧАС НА ЗАВОДЕ", 11, Color(0.88, 0.66, 0.23, 0.9), UITheme.f_caps if UITheme.f_caps else UITheme.f_semi))
	cap_title = UITheme.label("", 21, UITheme.TEXT, UITheme.f_semi)
	v.add_child(cap_title)
	cap_time = UITheme.label("", 13, UITheme.MUTED)
	v.add_child(cap_time)
	cap_bar = SceneBar.new()
	cap_bar.n = MenuScenes.count()
	cap_bar.custom_minimum_size = Vector2(0, 8)
	v.add_child(cap_bar)
	_update_caption()


## Что нового в версии — маленькая карточка справа вверху.
func _build_news() -> void:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UITheme.sb(Color(0.07, 0.08, 0.09, 0.72), Color(1, 1, 1, 0.07), 1, 10, 16, 12))
	box.anchor_left = 1.0
	box.anchor_right = 1.0
	box.offset_left = -340
	box.offset_right = -36
	box.offset_top = 36
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(box)
	_cards.append(box)
	var v := UITheme.vbox(5)
	box.add_child(v)
	v.add_child(UITheme.label("ЧТО НОВОГО · " + VERSION_TEXT.replace("Версия ", ""), 11, Color(0.88, 0.66, 0.23, 0.9), UITheme.f_caps if UITheme.f_caps else UITheme.f_semi))
	for s in WHATS_NEW:
		var h := UITheme.hbox(8)
		var dot := ColorRect.new()
		dot.color = UITheme.ACCENT
		dot.custom_minimum_size = Vector2(5, 5)
		dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(dot)
		h.add_child(UITheme.label(str(s), 13, Color(0.93, 0.9, 0.84, 0.86)))
		v.add_child(h)


## Пункт меню: значок, надпись, при наведении — янтарная планка слева и сдвиг вправо.
func _big(text: String, cb: Callable, sub_text: String = "", icon: String = "") -> MenuItem:
	var b := MenuItem.new()
	b.title = text
	b.hint = sub_text
	b.icon_tex = Tex.ui(icon) if icon != "" else null
	b.pressed.connect(cb)
	menu_box.add_child(b)
	return b


func _fill_menu() -> void:
	UITheme.clear(menu_box)
	var saves := Game.list_saves()
	if not saves.is_empty() and not bool((saves[0] as Dictionary).get("broken", false)):
		var s: Dictionary = saves[0]
		var b := _big("Продолжить", func() -> void: Game.start_load(str(s["slot"])),
			"%s%s · %s" % [(str(s["company"]) + " · ") if s.has("company") else "", Defs.money_str(float(s.get("money", 0))), Game.pc_time(str(s.get("saved_at", "")))], "play1")
		b.primary = true
	_big("Новая игра", _show_new_game, "Профиль, сценарий, сложность", "factory")
	var lb := _big("Загрузить", _show_load, "", "log")
	lb.disabled = saves.is_empty()
	var cw := CustomWorkers.load_data()
	var n_cw := (cw["workers"] as Array).filter(func(e: Dictionary) -> bool: return bool(e.get("enabled", true))).size()
	var cb := _big("Создать рабочего", _show_custom, ("В списке: %d · шанс %d%%" % [n_cw, roundi(float(cw["chance"]) * 100.0)]) if n_cw > 0 else "Придумайте людей для своего завода", "")
	cb.icon_tex = UITheme.micon("people")
	cb.icon_raw = true
	_big("Достижения", _show_achievements, "", "medal")
	_big("Настройки", _show_settings, "", "control")
	_big("Выход", func() -> void: get_tree().quit(), "", "cancel")


## Полупрозрачная панель слева с мягким краем и тонкой янтарной линией.
class SidePanel:
	extends Control
	var _fade: GradientTexture2D

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		var g := Gradient.new()
		var base := Color(0.055, 0.062, 0.072)
		g.offsets = PackedFloat32Array([0.0, 0.35, 1.0])
		g.colors = PackedColorArray([Color(base, 0.9), Color(base, 0.45), Color(base, 0.0)])
		_fade = GradientTexture2D.new()
		_fade.gradient = g
		_fade.width = 256
		_fade.height = 4
		_fade.fill_to = Vector2(1, 0)

	func _draw() -> void:
		var h := size.y
		draw_rect(Rect2(0, 0, 500, h), Color(0.055, 0.062, 0.072, 0.9))
		draw_texture_rect(_fade, Rect2(500, 0, 360, h), false)
		draw_rect(Rect2(0, 0, 4, h), Color(0.88, 0.66, 0.23, 0.85))


## Полоска смены видов: n отрезков, текущий заполняется по времени показа.
class SceneBar:
	extends Control
	var n := 5
	var i := 0
	var k := 0.0

	func _draw() -> void:
		var gap := 5.0
		var w := (size.x - gap * (n - 1)) / float(n)
		for j in n:
			var r := Rect2(j * (w + gap), size.y * 0.5 - 1.5, w, 3)
			draw_rect(r, Color(1, 1, 1, 0.14))
			var f := 1.0 if j < i % n else (k if j == i % n else 0.0)
			if f > 0.0:
				draw_rect(Rect2(r.position, Vector2(r.size.x * f, r.size.y)), Color(0.88, 0.66, 0.23, 0.95))


## Пункт главного меню.
class MenuItem:
	extends Button
	var title := ""
	var hint := ""
	var icon_tex: Texture2D = null
	var icon_raw := false   ## 1.32: цветной значок меню (assets/ui/icons) — без перекраски
	var primary := false
	var _h := 0.0

	func _init() -> void:
		custom_minimum_size = Vector2(380, 54)
		focus_mode = Control.FOCUS_NONE
		flat = true
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)

	func _process(delta: float) -> void:
		var want := 1.0 if is_hovered() and not disabled else 0.0
		var nh := move_toward(_h, want, delta * 7.0)
		if nh != _h:
			_h = nh
			queue_redraw()

	func _draw() -> void:
		var e := _h * _h * (3.0 - 2.0 * _h)
		var r := Rect2(Vector2.ZERO, size)
		if primary:
			draw_rect(r, Color(0.88, 0.66, 0.23, 0.92 + 0.08 * e))
		else:
			draw_rect(r, Color(1, 1, 1, 0.035 + 0.06 * e))
			draw_rect(Rect2(0, 0, 3.0 + 3.0 * e, size.y), Color(0.88, 0.66, 0.23, 0.35 + 0.65 * e))
		var dx := 18.0 + 6.0 * e
		var tc := UITheme.ACCENT_T if primary else (Color(0.93, 0.9, 0.84, 0.35) if disabled else UITheme.TEXT)
		if icon_tex:
			var isz := 22.0
			var icol := (Color(1, 1, 1, 0.4 if disabled else 1.0) if icon_raw else tc) if not primary else UITheme.ACCENT_T
			if icon_raw:
				isz = 28.0
				dx -= 3.0
			draw_texture_rect(icon_tex, Rect2(dx, (size.y - isz) * 0.5, isz, isz), false, icol)
			if icon_raw:
				dx -= 3.0
			dx += isz + 14.0
		var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
		var fs := 19
		var hf: Font = UITheme.f_reg if UITheme.f_reg else ThemeDB.fallback_font
		if hint != "":
			draw_string(f, Vector2(dx, size.y * 0.5 - 2.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
			var hc := Color(0.1, 0.1, 0.1, 0.75) if primary else Color(0.66, 0.69, 0.72, 0.9 if not disabled else 0.35)
			draw_string(hf, Vector2(dx, size.y * 0.5 + 16.0), hint, HORIZONTAL_ALIGNMENT_LEFT, size.x - dx - 12.0, 12, hc)
		else:
			draw_string(f, Vector2(dx, size.y * 0.5 + 7.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, tc)
		if e > 0.01 and not disabled:
			var ac := UITheme.ACCENT_T if primary else Color(0.88, 0.66, 0.23, e)
			var ax := size.x - 26.0 + 4.0 * e
			draw_line(Vector2(ax, size.y * 0.5 - 5), Vector2(ax + 5, size.y * 0.5), ac, 2.0, true)
			draw_line(Vector2(ax + 5, size.y * 0.5), Vector2(ax, size.y * 0.5 + 5), ac, 2.0, true)


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
	sub.offset_left = 500
	sub.offset_top = -220
	sub.offset_right = 1100
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


## 1.32: «Создать рабочего» (свои рабочие) — редактор на весь экран (как окно новой игры).
func _show_custom() -> void:
	if sub:
		sub.queue_free()
		sub = null
	if ng_root:
		ng_root.queue_free()
	var ed := CustomWorkersUI.new(sim)
	ng_root = ed
	ui.add_child(ed)
	ed.closed.connect(func() -> void:
		ed.queue_free()
		if ng_root == ed:
			ng_root = null
		_fill_menu())


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
	c3.add_child(UITheme.label("3. Сложность", 17, UITheme.TEXT, UITheme.f_semi))
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
	var sum := UITheme.label("%s · «%s» · сложность: %s" % [str(pd["name"]), str(sd["name"]), str(Defs.events.get("modes", {}).get(str(ng["story"]), {}).get("name", ng["story"]))], 14, UITheme.MUTED)
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
	var top := _panel("Настройки")
	sub.offset_top = -330
	sub.offset_bottom = 330
	# 1.29: настройки длиннее экрана — листаются внутри окна, окно не уползает вниз
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.custom_minimum_size = Vector2(0, 560)
	top.add_child(sc)
	var v := UITheme.vbox(10)
	v.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.add_child(v)
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



## Главная кнопка в окнах: янтарная, тёмный текст (читается лучше светлого на жёлтом).
func _amber(b: Button) -> void:
	b.add_theme_stylebox_override("normal", UITheme.sb(UITheme.ACCENT, UITheme.ACCENT, 1, 7, 16, 6))
	b.add_theme_stylebox_override("hover", UITheme.sb(Color("#ecb84c"), Color("#ecb84c"), 1, 7, 16, 6))
	b.add_theme_color_override("font_color", UITheme.ACCENT_T)
	b.add_theme_color_override("font_hover_color", UITheme.ACCENT_T)
	b.add_theme_font_override("font", UITheme.f_semi)
