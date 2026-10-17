class_name GameCamera
extends Camera2D
## Камера: WASD/стрелки — движение, колесо — масштаб к курсору, средняя кнопка — перетаскивание.

const T := World.T

var min_zoom := 0.55
var max_zoom := 3.2
var pan_speed := 900.0
var bounds := Rect2(-6 * T, -6 * T, 60 * T, 48 * T)
var _drag := false
var _drag_from := Vector2.ZERO
var edge_scroll := false


func _ready() -> void:
	zoom = Vector2(1.6, 1.6)


func _process(delta: float) -> void:
	var v := Vector2.ZERO
	if not _text_focus():
		if Input.is_key_pressed(KEY_A) or Input.is_key_pressed(KEY_LEFT):
			v.x -= 1
		if Input.is_key_pressed(KEY_D) or Input.is_key_pressed(KEY_RIGHT):
			v.x += 1
		if Input.is_key_pressed(KEY_W) or Input.is_key_pressed(KEY_UP):
			v.y -= 1
		if Input.is_key_pressed(KEY_S) or Input.is_key_pressed(KEY_DOWN):
			v.y += 1
	if edge_scroll and not _drag:
		var mp := get_viewport().get_mouse_position()
		var vs := get_viewport().get_visible_rect().size
		if mp.x < 6:
			v.x -= 1
		elif mp.x > vs.x - 6:
			v.x += 1
		if mp.y < 6:
			v.y -= 1
		elif mp.y > vs.y - 6:
			v.y += 1
	if v != Vector2.ZERO:
		position += v.normalized() * pan_speed * delta / zoom.x
	_clamp()


func _text_focus() -> bool:
	var f := get_viewport().gui_get_focus_owner()
	return f is LineEdit or f is TextEdit or f is SpinBox


func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventMouseButton:
		var mb := e as InputEventMouseButton
		var wheel := mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN
		if wheel and _over_ui():
			return  # колесо над окном или карточкой — это прокрутка окна, а не масштаб карты
		if mb.button_index == MOUSE_BUTTON_WHEEL_UP and mb.pressed:
			_zoom_at(1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN and mb.pressed:
			_zoom_at(1.0 / 1.12, mb.position)
		elif mb.button_index == MOUSE_BUTTON_MIDDLE:
			_drag = mb.pressed
			_drag_from = mb.position
	elif e is InputEventMouseMotion and _drag:
		var mm := e as InputEventMouseMotion
		position -= (mm.position - _drag_from) / zoom.x
		_drag_from = mm.position
		_clamp()
	elif e is InputEventMagnifyGesture and not _over_ui():
		_zoom_at((e as InputEventMagnifyGesture).factor, get_viewport().get_mouse_position())
	elif e is InputEventPanGesture and not _over_ui():
		position += (e as InputEventPanGesture).delta * 12.0 / zoom.x


## Курсор над элементом интерфейса (окно, карточка, панель), который ловит мышь.
func _over_ui() -> bool:
	var c := get_viewport().gui_get_hovered_control()
	return c != null and c.mouse_filter != Control.MOUSE_FILTER_IGNORE


func _zoom_at(factor: float, screen_pos: Vector2) -> void:
	var before := get_global_mouse_position()
	var z := clampf(zoom.x * factor, min_zoom, max_zoom)
	zoom = Vector2(z, z)
	force_update_scroll()
	var after := get_global_mouse_position()
	position += before - after
	_clamp()


func _clamp() -> void:
	position.x = clampf(position.x, bounds.position.x, bounds.end.x)
	position.y = clampf(position.y, bounds.position.y, bounds.end.y)


func focus_cell(c: Vector2i) -> void:
	position = Vector2(c) * T + Vector2(T, T) * 0.5
	_clamp()
