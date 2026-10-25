class_name DiagLine
extends CanvasLayer
## 1.38.2: F3 в главном меню и в «Создать рабочего» — строка диагностики поверх всего: кадры в секунду, время кадра
## (среднее и худшее за полсекунды), узлы, узлы-сироты, объекты, память текстур и видеопамять, статическая память
## (в сборке её счётчик есть не везде — тогда «—»). Если меню снова начнёт тормозить, снимок экрана со строкой
## покажет, что выросло.

var label: Label
var _acc := 0.0
var _n := 0
var _max := 0.0
var _last_us := 0


func _init() -> void:
	layer = 120
	label = UITheme.label("…", 13, Color("#9fe0a8"), UITheme.f_semi)
	label.position = Vector2(8, 8)
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	label.add_theme_constant_override("outline_size", 4)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)


func _process(_d: float) -> void:
	var now := Time.get_ticks_usec()
	if _last_us > 0:
		var ms := (now - _last_us) / 1000.0
		_acc += ms
		_n += 1
		_max = maxf(_max, ms)
	_last_us = now
	if _acc >= 500.0:
		label.text = line(_acc / maxf(1.0, float(_n)), _max)
		_acc = 0.0
		_n = 0
		_max = 0.0


static func line(avg_ms: float, max_ms: float) -> String:
	var st := Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0
	return L.t("%d FPS · кадр %.1f мс (макс %.0f) · узлов %d · сирот %d · объектов %d · текстуры %.0f МБ · видео %.0f МБ · ОЗУ %s") % [
		int(Performance.get_monitor(Performance.TIME_FPS)), avg_ms, max_ms,
		int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)),
		int(Performance.get_monitor(Performance.OBJECT_COUNT)), Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0,
		Performance.get_monitor(Performance.RENDER_VIDEO_MEM_USED) / 1048576.0, (L.t("%.0f МБ") % st) if st > 0.0 else "—"]
