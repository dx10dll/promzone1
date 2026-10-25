class_name PhoneCall
extends Control
## 1.41: входящие звонки. Скрыт → звонит (кнопка-телефон, звук раз в 2 с) → диалог (кабинет, портрет, текст ниже) → скрыт.
## Очередь лежит в sim.calls; здесь только показ. Ничего не трогает в симуляции, кроме чтения очереди.

const PHONE_DIR := "res://assets/calls/phone/"
const SEQ := [1, 2, 3, 2, 1, 2, 3, 2, 0]      ## кадры звонка (promzona_phone/manifest.json)
const DUR := [100, 100, 100, 100, 100, 100, 100, 100, 1200]   ## мс
const CYCLE_MS := 2000.0
const BTN := 80.0                              ## кнопка 64–96 px
const FADE := 0.15

var hud: Hud = null
var sim: Sim = null
var state := "hidden"                           ## hidden | ringing | dialogue
var current: Dictionary = {}
var phone_btn: Button
var phone_icon: TextureRect
var phone_cap: Label
var ring_player: AudioStreamPlayer
var panel: PanelContainer
var bg_rect: TextureRect
var portrait: TextureRect
var role_l: Label
var text_l: Label
var act_btn: Button
var close_btn: Button
var ring_t := 0.0                               ## мс внутри цикла
var answered := 0
var _frames: Array[Texture2D] = []
var _cache: Dictionary = {}
var _fade: Tween = null
var _img: Control


func setup(h: Hud, s: Sim) -> void:
	hud = h
	sim = s
	name = "PhoneCall"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	for i in 4:
		_frames.append(load("%sphone_0%d.png" % [PHONE_DIR, i]) as Texture2D)
	ring_player = AudioStreamPlayer.new()
	ring_player.name = "Ring"
	ring_player.stream = load(PHONE_DIR + "ring.wav") as AudioStream
	ring_player.bus = "UI" if AudioServer.get_bus_index("UI") >= 0 else "Master"
	add_child(ring_player)
	_build_button()
	_build_panel()
	set_state("hidden")


func _build_button() -> void:
	phone_btn = Button.new()
	phone_btn.name = "PhoneButton"
	phone_btn.flat = true
	phone_btn.focus_mode = Control.FOCUS_ALL
	phone_btn.tooltip_text = L.t("Входящий звонок")
	phone_btn.set("accessibility_name", L.t("Ответить на звонок"))
	phone_btn.anchor_left = 0.0
	phone_btn.anchor_right = 0.0
	phone_btn.anchor_top = 0.5
	phone_btn.anchor_bottom = 0.5
	phone_btn.offset_left = 12.0
	phone_btn.offset_right = 12.0 + BTN
	phone_btn.offset_top = 40.0
	phone_btn.offset_bottom = 40.0 + BTN + 22.0
	phone_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	phone_btn.pressed.connect(answer)
	phone_icon = TextureRect.new()
	phone_icon.texture = _frames[0]
	phone_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	phone_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	phone_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_icon.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	phone_icon.offset_bottom = BTN
	phone_btn.add_child(phone_icon)
	phone_cap = UITheme.label("Звонок", 12, UITheme.ACCENT, UITheme.f_semi)
	phone_cap.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	phone_cap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	phone_cap.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	phone_cap.offset_top = -20.0
	phone_btn.add_child(phone_cap)
	add_child(phone_btn)


func _build_panel() -> void:
	panel = PanelContainer.new()
	panel.name = "CallPanel"
	panel.add_theme_stylebox_override("panel", UITheme.sbs(Color(0.106, 0.108, 0.112, 0.98), UITheme.LINE, 1, 10, 12, 12, 14, 0.5, 4))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var v := UITheme.vbox(8)
	panel.add_child(v)
	_img = Control.new()
	_img.clip_contents = true
	_img.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg_rect = TextureRect.new()
	bg_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	bg_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	bg_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.add_child(bg_rect)
	portrait = TextureRect.new()
	portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_img.add_child(portrait)
	v.add_child(_img)
	role_l = UITheme.label("", 15, UITheme.ACCENT, UITheme.f_semi)
	v.add_child(role_l)
	text_l = UITheme.label("", 15)
	text_l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text_l.custom_minimum_size = Vector2(300, 64)
	v.add_child(text_l)
	var hb := UITheme.hbox(10)
	hb.alignment = BoxContainer.ALIGNMENT_END
	act_btn = UITheme.ghost("", func() -> void: act())
	hb.add_child(act_btn)
	close_btn = UITheme.primary("Понятно", func() -> void: close())
	hb.add_child(close_btn)
	v.add_child(hb)
	panel.visible = false
	add_child(panel)


func reduced() -> bool:
	return bool(Game.settings.get("reduce_motion", false))


func enabled() -> bool:
	return bool(Game.settings.get("calls_on", true))


func set_state(st: String) -> void:
	state = st
	phone_btn.visible = st == "ringing"
	panel.visible = st == "dialogue"
	if st != "ringing":
		ring_player.stop()
		ring_t = 0.0
	set_process(true)


## Заранее грузим все картинки звонящего — смена эмоции без мигания.
func preload_caller(caller: String) -> void:
	for e: String in (Calls.info(caller).get("emo", []) as Array):
		tex(Calls.portrait_path(caller, e))
	tex(Calls.office_path(caller))


func tex(path: String) -> Texture2D:
	if not _cache.has(path):
		_cache[path] = load(path) if ResourceLoader.exists(path) else null
	return _cache[path]


func _process(delta: float) -> void:
	if sim == null:
		return
	if not enabled():
		if state == "ringing":
			set_state("hidden")
			current = {}
		sim.calls.queue.clear()
		return
	match state:
		"hidden":
			if hud != null and (hud.modal_open() or hud.letter_box != null):
				return   # письмо или меню открыты — телефон зазвонит, когда игрок освободится
			var c := sim.calls.peek()
			if not c.is_empty():
				current = c
				preload_caller(str(c["caller"]))
				ring_t = 0.0
				set_state("ringing")
				_ring_step(0.0, true)
		"ringing":
			var h := sim.calls.peek()   # заодно убирает протухшие
			if h.is_empty() or int(h["id"]) != int(current.get("id", -1)):
				current = {}
				set_state("hidden")
				return
			_ring_step(delta * 1000.0, false)


func _ring_step(ms: float, first: bool) -> void:
	var prev := ring_t
	ring_t = fmod(ring_t + ms, CYCLE_MS)
	if first or ring_t < prev:
		_play_ring()
	var f := 0
	if not reduced():
		var acc := 0.0
		for i in SEQ.size():
			acc += float(DUR[i])
			if ring_t < acc:
				f = int(SEQ[i])
				break
	phone_icon.texture = _frames[f]
	phone_cap.visible = reduced()


func _play_ring() -> void:
	var st: Dictionary = Game.settings
	if float(st.get("vol_master", 0.8)) <= 0.001 or float(st.get("vol_ui", 0.75)) <= 0.001:
		return
	if ring_player.stream != null:
		ring_player.play()


## Ответить: стоп звук и анимация, показать диалог.
func answer() -> void:
	if state != "ringing":
		return
	var c := sim.calls.pop()
	if c.is_empty():
		set_state("hidden")
		return
	current = c
	answered += 1
	set_state("dialogue")
	show_call(c)


func show_call(c: Dictionary) -> void:
	var who := str(c["caller"])
	var emo := Calls.emotion_of(who, str(c["emotion"]))
	preload_caller(who)
	bg_rect.texture = tex(Calls.office_path(who))
	portrait.texture = tex(Calls.portrait_path(who, emo))
	role_l.text = L.t(Calls.role_name(who))
	text_l.text = Calls.text_of(c, sim)
	var lbl := str(c.get("label", ""))
	act_btn.visible = lbl != "" and str(c.get("action", "")) != ""
	act_btn.text = L.t(lbl)
	_layout()
	if _fade:
		_fade.kill()
	if not reduced():
		portrait.modulate.a = 0.0
		_fade = create_tween()
		_fade.tween_property(portrait, "modulate:a", 1.0, FADE)
	else:
		portrait.modulate.a = 1.0


func _layout() -> void:
	var vp := get_viewport_rect().size
	var w := clampf(minf(vp.x - 40.0, (vp.y - 250.0) * 1.5), 280.0, 640.0)
	var h := w * 2.0 / 3.0
	_img.custom_minimum_size = Vector2(w, h)
	text_l.custom_minimum_size = Vector2(w, 64)
	# портрет — по центру внизу, квадрат одного размера, чуть опущен (в PNG снизу прозрачный отступ)
	var ps := h * 1.02
	portrait.size = Vector2(ps, ps)
	portrait.position = Vector2((w - ps) * 0.5, h - ps + h * 0.03)
	panel.reset_size()
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = 0.5
	panel.anchor_bottom = 0.5
	panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	panel.offset_left = 0.0
	panel.offset_right = 0.0
	panel.offset_top = 0.0
	panel.offset_bottom = 0.0


func close() -> void:
	if state != "dialogue":
		return
	current = {}
	if _fade:
		_fade.kill()
	set_state("hidden")


func act() -> void:
	var a := str(current.get("action", ""))
	close()
	if a != "" and hud:
		hud.call_action(a)


func _unhandled_key_input(e: InputEvent) -> void:
	var k := e as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if state == "ringing" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER):
		answer()
		get_viewport().set_input_as_handled()
	elif state == "dialogue" and (k.keycode == KEY_ENTER or k.keycode == KEY_KP_ENTER or k.keycode == KEY_ESCAPE):
		close()
		get_viewport().set_input_as_handled()
