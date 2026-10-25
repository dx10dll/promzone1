class_name IntroPlayer
extends CanvasLayer
## 1.39: интро-ролик при запуске игры, перед главным меню (assets/video/intro_ru.ogv / intro_en.ogv —
## по языку игры). Чёрный фон, картинка вписана с сохранением пропорций. Любая клавиша, щелчок или Esc —
## пропустить. Звук — через шину «Музыка» (общая громкость и громкость музыки из настроек).
## Показывается один раз за запуск (Game.intro_seen), не в тестах и не в служебных прогонах.

signal done

const FADE_OUT := 0.35
var player: VideoStreamPlayer
var bg: ColorRect
var _ending := false
var _t := 0.0


static func path_for(lang: String) -> String:
	return "res://assets/video/intro_%s.ogv" % ("en" if lang == "en" else "ru")


## Показывать ли интро сейчас: menu — главное меню, которое как раз открылось.
static func should_play(menu: Node) -> bool:
	if Game.intro_seen or not bool(Game.settings.get("intro", true)) or Game.is_test_run():
		return false
	if menu.get_tree().current_scene != menu:
		return false   # меню собрано внутри тестовой сцены
	return ResourceLoader.exists(path_for(L.lang()))


func _init() -> void:
	layer = 100
	process_mode = Node.PROCESS_MODE_ALWAYS


func _ready() -> void:
	bg = ColorRect.new()
	bg.color = Color.BLACK
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP   # щелчки не доходят до меню под роликом
	bg.gui_input.connect(func(e: InputEvent) -> void:
		var mb := e as InputEventMouseButton
		if mb and mb.pressed:
			skip())
	add_child(bg)
	var box := AspectRatioContainer.new()
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	box.ratio = 16.0 / 9.0
	box.stretch_mode = AspectRatioContainer.STRETCH_FIT
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bg.add_child(box)
	player = VideoStreamPlayer.new()
	player.expand = true
	player.bus = "Music"
	player.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var st: Variant = load(path_for(L.lang())) if ResourceLoader.exists(path_for(L.lang())) else null
	if st is VideoStream:
		player.stream = st
	box.add_child(player)
	player.finished.connect(_finish)
	if player.stream == null:
		_finish.call_deferred()
		return
	player.play()
	print_verbose("IntroPlayer: ", player.stream.resource_path)


func _process(delta: float) -> void:
	_t += delta
	if _ending:
		bg.modulate.a = maxf(0.0, bg.modulate.a - delta / FADE_OUT)
		if player:
			player.volume_db = linear_to_db(maxf(0.001, bg.modulate.a))
		if bg.modulate.a <= 0.0:
			queue_free()
	elif player and player.stream and not player.is_playing() and _t > 0.5:
		_finish()   # ролик не пошёл (нет декодера) — не держим чёрный экран


func _input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and not k.echo:
		skip()
		get_viewport().set_input_as_handled()
	elif event is InputEventJoypadButton and (event as InputEventJoypadButton).pressed:
		skip()
		get_viewport().set_input_as_handled()


func skip() -> void:
	_finish()


func _finish() -> void:
	if _ending:
		return
	_ending = true
	done.emit()
