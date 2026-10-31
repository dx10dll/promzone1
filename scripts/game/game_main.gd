class_name GameMain
extends Node2D
## Игровая сцена: связывает симуляцию, отображение мира, инструменты, камеру и интерфейс.
## Время течёт кусками не больше полминуты игрового времени за шаг симуляции.

const SPEEDS := [0.0, 1.0, 2.0, 4.0]     ## множители скорости: пауза, ×1, ×2, ×4
const NIGHT_RATE := 240.0                 ## игровых минут в секунду, когда на заводе пусто
const MAX_STEP := 0.5
const MIN_STEP := 0.05
const SIM_HZ := 10.0                     ## 1.26: шагов симуляции в секунду на обычной скорости
var _acc := 0.0

var sim: Sim
var world_root := Node2D.new()
var world_view := WorldView.new()
var zones := ZoneLayer.new()
var ents := EntityLayer.new()
var tool := BuildTool.new()
var cam := GameCamera.new()
var daynight := DayNight.new()
var overlay := OverlayLayer.new()
var bubbles: WorkerBubbles = null   ## 1.50d: облачка над людьми
var badges: MachineBadges = null   ## 1.49: значки проблем над станками
var obj_badges: ObjectBadgesLayer = null   ## 1.50c: значки проблем над остальными объектами
var weather := WeatherLayer.new()
var fx := FxLayer.new()
var sound := SoundLayer.new()
var fps_label: Label = null     ## 1.26: F3 — кадры в секунду и время симуляции
var _fps_acc := 0.0
var _fps_sim := 0.0
var _fps_n := 0
var sim_ms := 0.0               ## 1.23: сколько мс ушло на симуляцию в этом кадре (для замеров)
var city: CityBackdrop          ## 1.23: город за краем карты (поезд и машины слышно)
var cranes := CraneLayer.new()
var hud: Hud
var speed := 1
var _speed_before_pause := 1
var menu_paused := false      ## пауза из-за открытого меню
var skip_target := -1.0       ## 1.44: «пропустить до смены» — до какой минуты крутим
var _skip_call0 := 0
var _skip_bad0 := 0
var fast := false             ## ночь/выходные ускорены
var _want_autosave := false
var _over_shown := false
var _bankrupt_warned := false
var _ach_t := 3.0


func _ready() -> void:
	sim = Game.make_sim()
	sim.auto_supply = true
	add_child(world_root)
	city = CityBackdrop.new()
	city.sim = sim
	world_root.add_child(city)
	world_view.sim = sim
	world_root.add_child(world_view)
	var street := StreetFolk.new()   # 1.30: люди, автобус и деревья на улице за краем карты
	street.sim = sim
	street.backdrop = city
	street.ents = ents
	world_root.add_child(street)
	zones.sim = sim
	world_root.add_child(zones)
	var fmarks := FloorMarks.new()   # 1.58: разметка пола у зон и буферов
	fmarks.sim = sim
	world_root.add_child(fmarks)
	var faults_l := FaultLayer.new()   # 1.18: лужи от прорыва водопровода
	faults_l.sim = sim
	world_root.add_child(faults_l)
	weather.sim = sim
	world_root.add_child(weather)
	daynight.setup(sim, world_root, world_root)
	add_child(daynight)
	var vfx_low := VehicleFx.new()   # 1.30: пожарные рукава — под людьми и машинами
	vfx_low.sim = sim
	world_root.add_child(vfx_low)
	ents.sim = sim
	world_root.add_child(ents)
	var fauna_l := FaunaLayer.new()   # 1.22: голуби и мыши
	fauna_l.sim = sim
	world_root.add_child(fauna_l)
	cranes.sim = sim
	world_root.add_child(cranes)
	var sign := CompanySign.new()   # 1.17: вывеска над воротами
	sign.sim = sim
	world_root.add_child(sign)
	var plan_l := PlanLayer.new()   # 1.17: план-калька
	plan_l.sim = sim
	plan_l.tool = tool
	world_root.add_child(plan_l)
	var net_ghost := NetGhostLayer.new()   # 1.50b: заказанные, но не проложенные сети — призраки
	net_ghost.sim = sim
	world_root.add_child(net_ghost)
	world_root.add_child(fx)
	fx.setup(sim, world_root)
	var vfx_top := VehicleFx.new()   # 1.30: струя воды, мигалки, дорожный указатель
	vfx_top.sim = sim
	vfx_top.top = true
	world_root.add_child(vfx_top)
	var life := AmbientLife.new()   # 1.23: облака, листья, бабочки
	life.sim = sim
	world_root.add_child(life)
	world_root.add_child(sound)
	sound.setup(self)
	Snd.track_started.connect(_on_track)
	Snd.set_playlist(MusicDirector.playlist(sim, int(Game.settings.get("music_mode", 0.0))))
	overlay.sim = sim
	# оверлеи — на своём слое: следуют за камерой, но не темнеют ночью
	var ov_layer := CanvasLayer.new()
	ov_layer.layer = 1
	ov_layer.follow_viewport_enabled = true
	add_child(ov_layer)
	ov_layer.add_child(overlay)
	# предупреждения на зонах — тоже не темнеют ночью
	var marks := ZoneMarks.new()
	marks.sim = sim
	marks.game = self
	ov_layer.add_child(marks)
	# 1.49: значки проблем над станками
	var mbadges := MachineBadges.new()
	mbadges.sim = sim
	mbadges.game = self
	badges = mbadges
	ov_layer.add_child(mbadges)
	var obadges := ObjectBadgesLayer.new()
	obadges.sim = sim
	obadges.game = self
	obj_badges = obadges
	ov_layer.add_child(obadges)
	# фамилии под людьми — поверх построек, не темнеют ночью
	var names := NameLayer.new()
	names.sim = sim
	names.game = self
	ov_layer.add_child(names)
	# 1.50d: облачка-мысли над людьми — поверх имён
	var wbub := WorkerBubbles.new()
	wbub.sim = sim
	wbub.game = self
	bubbles = wbub
	ov_layer.add_child(wbub)
	tool.sim = sim
	tool.game = self
	tool.overlay = overlay
	world_root.add_child(tool)
	world_root.add_child(cam)
	cam.edge_scroll = bool(Game.settings.get("edge_scroll", false))
	cam.make_current()
	cam.focus_cell(Vector2i(22, 15))
	# лёгкая виньетка по краям экрана — глубина и «киношная» картинка
	var vig_layer := CanvasLayer.new()
	vig_layer.layer = 5
	add_child(vig_layer)
	var vig := ColorRect.new()
	vig.set_anchors_preset(Control.PRESET_FULL_RECT)
	vig.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := Shader.new()
	sh.code = """shader_type canvas_item;
void fragment() {
	vec2 d = (UV - vec2(0.5)) * vec2(1.25, 1.0);
	float v = smoothstep(0.42, 0.95, length(d));
	COLOR = vec4(0.02, 0.03, 0.05, v * 0.32);
}"""
	var mat := ShaderMaterial.new()
	mat.shader = sh
	vig.material = mat
	vig_layer.add_child(vig)
	var layer := CanvasLayer.new()
	layer.layer = 10
	add_child(layer)
	hud = Hud.new()
	layer.add_child(hud)
	hud.setup(self)
	sim.notified.connect(hud.on_notified)
	sim.morning.connect(_on_morning)
	tool.message.connect(func(t: String, good: bool) -> void: hud.toast(t, Sim.LVL_GOOD if good else Sim.LVL_WARN, 4.0))
	tool.selection_changed.connect(_on_selection)
	tool.mode_changed.connect(hud.on_mode_changed)
	tool.room_clicked.connect(func(_id: int) -> void:
		hud.info.near_screen = tool.recent_click())
	tool.room_clicked.connect(hud.on_room_clicked)
	tool.control_click.connect(func(c: Vector2i, scr: Vector2) -> void: hud.ctl.on_map_click(c, scr))
	tool.cell_clicked.connect(func(c: Vector2i) -> void:
		var lot := FxLayer.sign_at(sim, fx.get_local_mouse_position())
		if lot >= 0:   # 1.29: щелчок по табличке «Продаётся» — сразу к покупке участка
			open_lot(lot)
			return
		hud.info.near_screen = tool.recent_click()
		hud.info.show_cell(sim, c))
	# уведомления, накопленные до открытия сцены (приветствие сценария)
	var start_events := sim.events.slice(0, 3)
	start_events.reverse()
	for e: Dictionary in start_events:
		hud.on_notified(str(e["text"]), int(e["level"]), Vector2i(-1, -1))
	if Game.pending == "new" and not bool(Game.settings.get("tutorial_done", false)) and sim.progress.tutorial < 0:
		hud.show_help(true)
	# 1.30: камеру можно увести за край карты — к телебашне, Цне и центру Тамбова (юг дальше всего)
	cam.bounds = Rect2(-12 * World.T, -10 * World.T, (sim.world.w + 24) * World.T, (sim.world.h + 34) * World.T)
	DisplayServer.window_set_title(tr("Промзона — %s") % Company.title(sim))
	if sim.scenario != "garage":
		cam.focus_cell(Vector2i(int(sim.world.plot.get_center().x), int(sim.world.plot.end.y / 2) + 4))


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and sim:
		Game.autosave(sim)


func _exit_tree() -> void:
	if sim:
		sim.dispose()


# ---------------------------------------------------------------- время

func set_speed(s: int) -> void:
	speed = clampi(s, 0, SPEEDS.size() - 1)
	if speed == 0:
		skip_target = -1.0
	if speed > 0:
		_speed_before_pause = speed
	hud.on_speed_changed()


func toggle_pause() -> void:
	if speed == 0:
		set_speed(_speed_before_pause)
	else:
		set_speed(0)


func is_running() -> bool:
	return speed > 0 and not menu_paused


func is_skipping() -> bool:
	return skip_target >= 0.0


func start_skip() -> bool:
	if sim == null or not sim.can_skip_idle():
		return false
	skip_target = sim.next_shift_start()
	_skip_call0 = sim.calls.seq
	_skip_bad0 = sim.bad_seq
	if speed == 0:
		set_speed(1)
	return true


func stop_skip(reason: String = "") -> void:
	if skip_target < 0.0:
		return
	skip_target = -1.0
	if reason != "" and hud != null:
		hud.toast(tr("Пропуск времени остановлен: %s") % tr(reason), Sim.LVL_WARN)


## Пропуск: те же шаги симуляции (MAX_STEP), только их много за кадр, пока не выйдет бюджет времени кадра.
func _skip_frame() -> void:
	var t0 := Time.get_ticks_usec()
	fast = true
	while sim.minute < skip_target:
		var why := sim.skip_stop_reason(_skip_call0, _skip_bad0)
		if why != "":
			stop_skip(why)
			return
		for w in sim.workers:
			w.vprev = w.pos
		sim.tick(MAX_STEP)
		if (Time.get_ticks_usec() - t0) > 14000:
			break
	Worker.view_alpha = 1.0
	if sim.minute >= skip_target:
		stop_skip()


func _factory_empty() -> bool:
	if not sim.vehicles.is_empty():
		return false
	for w in sim.workers:
		if w.present:
			return false
	return true


var _music_t := 0.0


func _process(delta: float) -> void:
	Tex.set_people_scale(cam.zoom.x * get_viewport().get_final_transform().get_scale().x * 0.5)
	Tex.ui_scale = get_viewport().get_final_transform().get_scale().x
	if sim == null:
		return
	var sid := tool.sel_id if tool.sel_kind == "worker" else -1
	for id: int in ents.workers.keys():
		(ents.workers[id] as WorkerView).selected = id == sid
	fast = false
	if sim.crisis.is_over() and not _over_shown and hud.letter_box == null:
		_over_shown = true
		hud.show_game_over()
	if fps_label:
		_fps_tick(delta)
	_music_t -= delta
	if _music_t <= 0.0:   # 1.28: музыка под время суток, раз в пару секунд
		_music_t = 2.0
		Snd.set_playlist_soft(MusicDirector.playlist(sim, int(Game.settings.get("music_mode", 0.0))))
		Snd.duck(hud != null and hud.modal_open())   # 1.31: под меню паузы музыка тише
	sim_ms = 0.0
	if not is_running():
		return
	if skip_target >= 0.0:
		_skip_frame()
		return
	var rate: float = float(SPEEDS[speed]) / maxf(0.05, Defs.b("minute_real_seconds") * float(Game.settings.get("hour_len", 1.0)))
	if bool(Game.settings.get("fast_night", true)) and _factory_empty() and not sim.is_work_time():
		rate = maxf(rate, NIGHT_RATE)
		fast = true
	# 1.26: симуляция — ровными шагами (около 10 в секунду на ×1), а не крошечным шагом в каждом кадре:
	# стоимость шага почти не зависит от его длины, и при 144 кадрах она съедала весь кадр.
	# Люди на экране плавно идут между двумя последними шагами (Worker.vpos).
	var step := clampf(rate / SIM_HZ, MIN_STEP, MAX_STEP)
	_acc = minf(_acc + minf(delta, 0.1) * rate, step * 400.0)
	var guard := 0
	var t0 := Time.get_ticks_usec()
	while _acc >= step and guard < 400:
		for w in sim.workers:
			w.vprev = w.pos
		for v in sim.visitors:
			v.vprev = v.pos
		for vh in sim.vehicles:
			vh.px = vh.x
		var ct := sim.town.cat if sim.town else null
		if ct:
			ct.vprev = ct.pos
		sim.tick(step)
		_acc -= step
		guard += 1
	Worker.view_alpha = clampf(_acc / step, 0.0, 1.0)
	sim_ms = (Time.get_ticks_usec() - t0) / 1000.0
	if _want_autosave:
		_want_autosave = false
		var err := Game.autosave(sim)
		if err != "":
			hud.toast(tr("Автосохранение не удалось: %s") % err, Sim.LVL_BAD)
	if sim.progress.stage_up > 0 and not hud.modal_open() and hud.letter_box == null:
		var st := sim.progress.stage_up
		sim.progress.stage_up = -1
		hud.show_stage_up(st)
	elif sim.progress.scn_up and not hud.modal_open() and hud.letter_box == null:
		sim.progress.scn_up = false
		hud.show_scenario_done()
	_ach_t -= delta
	if _ach_t <= 0.0:
		_ach_t = 2.0
		for a: Dictionary in Achievements.check(sim):
			hud.show_achievement(a)
	if sim.money < -150000.0 and not _bankrupt_warned:
		_bankrupt_warned = true
		hud.show_bankrupt()
	elif sim.money > 0.0:
		_bankrupt_warned = false


func _on_morning(_day: int) -> void:
	if bool(Game.settings.get("autosave", true)):
		_want_autosave = true


# ---------------------------------------------------------------- выделение

func _on_selection() -> void:
	# щёлкнули по карте — карточка объекта появится у курсора; выбрали из окна — справа, как раньше
	hud.info.near_screen = tool.recent_click()
	for v: WorkerView in ents.workers.values():
		v.selected = false
	if tool.sel_kind == "worker":
		var w := sim.get_person(tool.sel_id)
		var wv := ents.worker_view(tool.sel_id)
		if wv:
			wv.selected = true
		if w and w.visitor:
			hud.worker_pop.close()
			hud.info.show_visitor(sim, w)
		elif w and hud.info.near_screen.x >= 0.0 and not (hud.info.visible and hud.info.kind == "worker"):
			# 1.21: щелчок по карте — маленькое меню над человеком; карточка — по кнопке
			hud.info.visible = false
			hud.worker_pop.show_for(w)
		elif w:
			hud.worker_pop.close()
			hud.info.show_worker(sim, w)
	elif tool.sel_kind == "thing":
		hud.worker_pop.close()
		var t := sim.get_thing(tool.sel_id)
		if t:
			hud.info.show_thing(sim, t)
	else:
		hud.info.visible = false
		hud.worker_pop.close()


func focus_worker(id: int) -> void:
	var w := sim.get_worker(id)
	if w == null:
		return
	tool.select_worker(id)
	if w.present:
		cam.focus_cell(w.cell())


func focus_thing(id: int) -> void:
	var t := sim.get_thing(id)
	if t == null:
		return
	tool.select_thing(id)
	cam.focus_cell(t.cell)


# ---------------------------------------------------------------- клавиши

func _unhandled_input(e: InputEvent) -> void:
	if not (e is InputEventKey):
		return
	var k := e as InputEventKey
	if not k.pressed or k.echo:
		return
	if hud.modal_open():
		if k.keycode == KEY_ESCAPE:
			hud.close_modal()
			get_viewport().set_input_as_handled()
		return
	if hud.letter_box != null:
		return   # сначала решите событие
	match k.keycode:
		KEY_SPACE:
			toggle_pause()
		KEY_1:
			set_speed(1)
		KEY_2:
			set_speed(2)
		KEY_3:
			set_speed(3)
		KEY_B:
			hud.toggle_sub("build")
		KEY_O:
			hud.toggle_sub("objects")
		KEY_X:
			hud.set_tool("demolish")
		KEY_R:
			if tool.mode == "object":
				tool.rotate_ghost()
			else:
				hud.open_rooms()
		KEY_E:
			hud.toggle_sub("power")
		KEY_V:
			hud.toggle_plan()
		KEY_P:
			hud.open_window("prod")
		KEY_L:
			hud.open_window("people")
		KEY_F:
			hud.open_window("finance")
		KEY_M:
			hud.open_window("office")
		KEY_T:
			hud.open_window("research")
		KEY_C:
			hud.open_window("events")
		KEY_N:
			hud.open_window("paper")
		KEY_G:
			hud.open_window("goals")
		KEY_K:
			hud.open_window("crew")
		KEY_H:
			hud.open_window("town")
		KEY_F1:
			hud.show_help(false)
		KEY_F3:
			_toggle_fps()
		KEY_F5:
			var err := Game.save_sim(sim, "quicksave", "Быстрое сохранение")
			hud.toast(tr("Игра сохранена (F9 — загрузить).") if err == "" else err, Sim.LVL_GOOD if err == "" else Sim.LVL_BAD, 3.0)
		KEY_F9:
			if Game.has_save("quicksave"):
				Game.start_load("quicksave")
		KEY_ESCAPE:
			if hud.ctl and hud.ctl.menu_open():
				hud.ctl.close_menu()
			elif hud.worker_pop and hud.worker_pop.visible:
				hud.worker_pop.close()
				tool.clear_selection()
			elif tool.mode != "select":
				tool.set_mode("select")
				hud.close_sub()
			elif hud.sub_kind != "":
				hud.close_sub()
			elif hud.win:
				hud.close_window()
			elif tool.sel_kind != "":
				tool.clear_selection()
			elif hud.ctl and hud.ctl.active():
				hud.ctl.release()
			else:
				hud.show_pause_menu()
		_:
			return
	get_viewport().set_input_as_handled()


## 1.26: счётчик в углу (F3): кадры в секунду, время кадра и сколько из него ушло на симуляцию.
func _toggle_fps() -> void:
	if fps_label:
		fps_label.get_parent().queue_free()
		fps_label = null
		return
	var cl := CanvasLayer.new()
	cl.layer = 120
	add_child(cl)
	fps_label = UITheme.label("…", 13, Color("#9fe0a8"), UITheme.f_semi)
	fps_label.position = Vector2(8, 52)
	fps_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	fps_label.add_theme_constant_override("outline_size", 4)
	fps_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(fps_label)


## 1.29: окно «Развитие» с выбранной ступенью покупки участка k.
func open_lot(k: int) -> void:
	for b: Dictionary in Develop.branches():
		for st: Dictionary in b.get("steps", []):
			if st.has("lot") and int(st["lot"]) == k:
				DevTree.sel = str(st["id"])
	if hud.win and hud.win.group == "office":
		hud.close_window()   # 1.40: окно уже открыто — не закрыть его повторным щелчком, а показать участок
	hud.open_window("develop")
	Snd.play("n_info", -4.0)


func _on_track(_name: String) -> void:
	pass   # 1.48: владелец просил не показывать название трека при смене музыки


func _fps_tick(delta: float) -> void:
	_fps_acc += delta
	_fps_sim += sim_ms
	_fps_n += 1
	if _fps_acc < 0.5:
		return
	var present := 0
	for w in sim.workers:
		if w.present:
			present += 1
	# 1.29: вторая строка — чем рисуется и что ограничивает кадры (для поиска «потолка» на разных компьютерах)
	var vs := DisplayServer.window_get_vsync_mode()
	fps_label.text = tr("%d кадр/с · кадр %.1f мс · логика %.1f мс · симуляция %.1f мс/кадр · людей на заводе %d\n%s · %s · V-Sync %s · предел %s · вызовов отрисовки %d") % [
		int(Engine.get_frames_per_second()), _fps_acc * 1000.0 / _fps_n, Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0, _fps_sim / _fps_n, present,
		RenderingServer.get_video_adapter_name(), RenderingServer.get_current_rendering_driver_name(),
		tr("выкл.") if vs == DisplayServer.VSYNC_DISABLED else tr("вкл."), str(Engine.max_fps) if Engine.max_fps > 0 else tr("нет"),
		int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))]
	_fps_acc = 0.0
	_fps_sim = 0.0
	_fps_n = 0
