extends Node
## Глобальное состояние: настройки, переход между меню и игрой, сохранения.

const SAVE_DIR := "user://saves"
const SETTINGS_PATH := "user://settings.cfg"
const AUTOSAVE := "autosave"

var settings: Dictionary = {
	"auto_buy": true,        ## при принятии заказа докупать металл
	"autosave": true,        ## автосохранение каждое утро
	"edge_scroll": false,    ## прокрутка камеры у края экрана
	"names_on_map": true,    ## фамилии под людьми на карте
	"fast_night": true,      ## ускорять ночь и выходные, когда на заводе никого нет
	"fullscreen": false,
	"pause_on_event": true,  ## ставить паузу, когда приходит событие с выбором
	"vol_master": 0.8,       ## громкость: общая, музыка, звуки, окружение (0–1)
	"vol_music": 0.45,
	"music_mode": 0.0,       ## 1.28: 0 — музыка по времени суток, 1 — всё подряд, 2 — только старые вальсы
	"vol_sfx": 0.8,
	"vol_env": 0.65,         ## 1.29: звуки окружения — цех, столовая, быт, голоса, город (один ползунок вместо трёх)
	"vol_amb": 0.6,
	"vol_people": 0.75,      ## 1.25: голоса и быт (кашель, посуда, двери, телефон)
	"vol_city": 0.6,         ## 1.25: город, поезд, гудки, животные
	"vol_ui": 0.75,          ## 1.25: интерфейс и уведомления
	"vsync": 0.0,            ## 1.26: вертикальная синхронизация (1 — вкл.; по умолчанию выкл., кадры не ограничены частотой монитора)
	"fps_cap": 0.0,          ## 1.26: предел кадров в секунду, 0 — без предела
	"quality": 2,            ## 1.25: качество эффектов: 0 — низкое, 1 — среднее, 2 — высокое
	"hour_len": 1.0,         ## длительность игрового часа: множитель (0.5 — вдвое быстрее)
	"ui_scale": 1.0,         ## масштаб интерфейса
	"tutorial_done": false,
	"lang": "",              ## 1.39: язык интерфейса: "ru", "en" или "" — по языку системы (L.default_lang)
	"calls_on": true,        ## 1.41: звонки (советник, инспекторы, заказчики)
	"reduce_motion": false,  ## 1.41: меньше анимации (статичный значок звонка, без растворений)
	"intro": true,           ## 1.39: показывать интро-ролик при запуске
}
var intro_seen := false      ## 1.39: интро уже показали в этом запуске (в меню из игры — без ролика)
var pending := "new"         ## что делать при входе в игровую сцену: new | load
var pending_slot := ""
var pending_seed := 0
var pending_story := "market"   ## режим рассказчика для новой игры
var pending_scn := "garage"      ## сценарий
var pending_profile := "mech"    ## профиль завода
var pending_opts: Dictionary = {"tutorial": true}  ## обучение, параметры песочницы
var pending_sim: Sim = null      ## 1.40: готовый завод для игровой сцены (замер --bench-game), берётся один раз


func _ready() -> void:
	Defs.load_all()
	DirAccess.make_dir_recursive_absolute(SAVE_DIR)
	_load_settings()
	L.apply(start_lang())
	get_tree().root.theme = UITheme.build()
	apply_window()
	apply_ui_scale()
	_handle_cmdline()


## 1.39: запуск из тестов (сцена или скрипт из res://tests/) и служебные прогоны (--bench/--soak/--shot):
## в них нет интро, а язык — русский (тесты сверяют русские строки), если не задан ключом `-- --lang=en`.
static func is_test_run() -> bool:
	for a: String in OS.get_cmdline_args():
		if a.contains("tests/"):
			return true
	for a2: String in OS.get_cmdline_user_args():
		if a2.begins_with("--bench") or a2.begins_with("--soak") or a2.begins_with("--shot") or a2 == "--newgame":
			return true
	return false


func start_lang() -> String:
	for a: String in OS.get_cmdline_user_args():
		if a.begins_with("--lang="):
			return a.get_slice("=", 1)
	return "ru" if is_test_run() else str(settings.get("lang", ""))


## Сменить язык (из настроек): сохранить и применить сразу.
func set_lang(code: String) -> void:
	settings["lang"] = code
	save_settings()
	L.apply(code)


## Служебные ключи для проверки сборки: -- --newgame --shot=путь.png
func _handle_cmdline() -> void:
	var shot := ""
	var newgame := false
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			shot = a.substr(7)
		elif a == "--newgame":
			newgame = true
		elif a.begins_with("--bench-game="):
			add_child(GameBench.new())   # 1.40: замер кадров в игре на большом заводе
	if newgame:
		settings["tutorial_done"] = true
		start_new_game.call_deferred(4242)
	if shot != "":
		_take_shot(shot)


func _take_shot(path: String) -> void:
	for i in 90:
		await get_tree().process_frame
	var img := get_viewport().get_texture().get_image()
	img.save_png(path)
	print("Снимок сохранён: ", path)
	get_tree().quit()


func apply_ui_scale() -> void:
	get_tree().root.content_scale_factor = clampf(float(settings.get("ui_scale", 1.0)), 0.75, 1.5)
	if not get_tree().root.size_changed.is_connected(Tex.invalidate_crisp):
		get_tree().root.size_changed.connect(Tex.invalidate_crisp)   # 1.46: значки запекаются под масштаб окна
	Tex.invalidate_crisp()
	apply_cursor()


var _cursor_set := false

## 1.42: свой курсор — оранжевая стрелка с тёмным кантом, над кнопками — светлая.
## На крупном интерфейсе (масштаб от 1,25) — версия 48 px.
func apply_cursor() -> void:
	var big := float(settings.get("ui_scale", 1.0)) >= 1.25 or DisplayServer.screen_get_scale() >= 1.5
	var suf := "_48" if big else ""
	var arrow := load("res://assets/ui/cursor/arrow%s.png" % suf) as Texture2D
	var hand := load("res://assets/ui/cursor/pointer%s.png" % suf) as Texture2D
	if arrow == null or hand == null:
		return
	Input.set_custom_mouse_cursor(arrow, Input.CURSOR_ARROW, Vector2(1, 1))
	Input.set_custom_mouse_cursor(hand, Input.CURSOR_POINTING_HAND, Vector2(1, 1))
	_cursor_set = true


func cursor_ok() -> bool:
	return _cursor_set


func apply_window() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if float(settings.get("vsync", 0.0)) > 0.5 else DisplayServer.VSYNC_DISABLED)
	Engine.max_fps = int(settings.get("fps_cap", 0.0))
	if bool(settings.get("fullscreen", false)):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	elif DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_MAXIMIZED)


func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings.keys():
		settings[k] = cf.get_value("game", k, settings[k])


func save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings.keys():
		cf.set_value("game", k, settings[k])
	cf.save(SETTINGS_PATH)


# ---------------------------------------------------------------- переходы

func start_new_game(seed_value: int = 0, story_mode: String = "", scn: String = "", profile: String = "", opts: Dictionary = {}) -> void:
	pending = "new"
	if story_mode != "":
		pending_story = story_mode
	if scn != "":
		pending_scn = scn
		pending_profile = profile if profile != "" else "mech"
		pending_opts = opts
	pending_seed = seed_value if seed_value != 0 else int(Time.get_unix_time_from_system()) % 1000000 + 1
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func start_load(slot: String) -> void:
	pending = "load"
	pending_slot = slot
	get_tree().change_scene_to_file("res://scenes/game.tscn")


func to_menu() -> void:
	get_tree().change_scene_to_file("res://scenes/main_menu.tscn")


## Создаёт симуляцию для игровой сцены согласно pending. Возвращает null при ошибке загрузки.
func make_sim() -> Sim:
	if pending_sim != null:
		var ps := pending_sim
		pending_sim = null
		return ps
	if pending == "load":
		var s := load_sim(pending_slot)
		if s:
			return s
		push_warning("Не удалось загрузить сохранение %s, начинаем новую игру" % pending_slot)
	# 1.32: свои рабочие из главного меню едут в новую игру (дальше — в её сохранении)
	var opts := pending_opts.duplicate(true)
	if not opts.has("customs"):
		opts.merge(CustomWorkers.game_opts())
	return Scenario.new_game(pending_scn, pending_profile, pending_story, pending_seed if pending_seed != 0 else 1, opts)


# ---------------------------------------------------------------- сохранения

func _slot_path(slot: String) -> String:
	return "%s/%s.json" % [SAVE_DIR, slot]


## 1.20: автосохранение — своё у каждого завода (раньше было одно на всех).
func autosave_slot(sim: Sim) -> String:
	return AUTOSAVE + "_" + Company.uid_of(sim)


func autosave(sim: Sim) -> String:
	if sim.crisis.is_over():
		return ""   # закрытый завод не перезаписывает последнее живое автосохранение
	return save_sim(sim, autosave_slot(sim), "Автосохранение")


## «2026-10-17 14:32:05» -> «17.10.2026 в 14:32» — время компьютера, когда сохранили.
static func pc_time(saved_at: String) -> String:
	var s := saved_at.replace("T", " ")
	if s.length() < 16:
		return s
	return L.t("%s.%s.%s в %s") % [s.substr(8, 2), s.substr(5, 2), s.substr(0, 4), s.substr(11, 5)]


func save_sim(sim: Sim, slot: String, title: String = "") -> String:
	var d := sim.to_dict()
	d["meta"] = {
		"title": title if title != "" else slot,
		"date": sim.date_str(), "time": sim.time_str(), "money": sim.money,
		"workers": sim.workers.size(), "saved_at": Time.get_datetime_string_from_system(false, true),
		"company": Company.title(sim), "emblem": Company.emblem_of(sim),
		"unix": Time.get_unix_time_from_system(), "auto": slot.begins_with(AUTOSAVE),
	}
	var f := FileAccess.open(_slot_path(slot), FileAccess.WRITE)
	if f == null:
		return "Не удалось записать файл: " + error_string(FileAccess.get_open_error())
	f.store_string(JSON.stringify(d))
	f.close()
	return ""


func load_sim(slot: String) -> Sim:
	var p := _slot_path(slot)
	if not FileAccess.file_exists(p):
		return null
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	if typeof(data) != TYPE_DICTIONARY:
		return null
	var d: Dictionary = data
	if int(d.get("version", 0)) > Sim.VERSION:
		return null
	return Sim.from_dict(d)


func has_save(slot: String) -> bool:
	return FileAccess.file_exists(_slot_path(slot))


func delete_save(slot: String) -> void:
	DirAccess.remove_absolute(_slot_path(slot))


## Список сохранений, свежие сверху: [{slot, title, date, time, money, saved_at, unix}]
func list_saves() -> Array:
	var out: Array = []
	var da := DirAccess.open(SAVE_DIR)
	if da == null:
		return out
	for fn in da.get_files():
		if not fn.ends_with(".json"):
			continue
		var slot := fn.get_basename()
		var meta := _read_meta(_slot_path(slot))
		meta["slot"] = slot
		out.append(meta)
	out.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return float(a.get("unix", 0)) > float(b.get("unix", 0)))
	return out


func _read_meta(path: String) -> Dictionary:
	# мета-данные лежат внутри большого JSON; файлы маленькие (десятки КБ), читаем целиком
	var data: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if typeof(data) != TYPE_DICTIONARY:
		return {"title": "(повреждено)", "date": "", "time": "", "money": 0, "saved_at": "", "unix": 0, "broken": true}
	var m: Dictionary = (data as Dictionary).get("meta", {})
	return m.duplicate()


func new_slot_name() -> String:
	var t := Time.get_datetime_dict_from_system()
	return "save_%04d%02d%02d_%02d%02d%02d" % [t["year"], t["month"], t["day"], t["hour"], t["minute"], t["second"]]
