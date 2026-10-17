class_name VecIcon
extends Texture2D
## 1.19: значок, который всегда чёткий. Хранит исходный SVG (из assets/vec/*.json) и при каждой отрисовке
## берёт растр ровно под размер на экране — без мыла от мип-карт и без «лесенки». Для интерфейса
## масштаб — масштаб окна (Tex.ui_scale), для значков над людьми — масштаб камеры (Tex.people_e).
## Логический размер — как у исходного SVG, поэтому кнопки и TextureRect работают как раньше.

const STEP := 1.09050773   ## растры кэшируются ступенями через 2^⅛ — при зуме не плодим сотни копий

var pack := ""
var key := ""
var world := false         ## значок в мире (над людьми): масштаб берём от камеры
var w := 48
var h := 48

static var _ras: Dictionary = {}


static func make(p: String, k: String, is_world: bool = false) -> VecIcon:
	var s := Vec.source(p, k)
	if s == "":
		return null
	var v := VecIcon.new()
	v.pack = p
	v.key = k
	v.world = is_world
	var a := s.find("width=\"")
	var b := s.find("height=\"")
	if a >= 0 and b >= 0:
		v.w = maxi(1, int(float(s.substr(a + 7, s.find("\"", a + 7) - a - 7))))
		v.h = maxi(1, int(float(s.substr(b + 8, s.find("\"", b + 8) - b - 8))))
	return v


func _get_width() -> int:
	return w


func _get_height() -> int:
	return h


func _has_alpha() -> bool:
	return true


func _is_pixel_opaque(_x: int, _y: int) -> bool:
	return true


## Растр под размер sz (в единицах холста).
func raster_for(sz: Vector2) -> ImageTexture:
	var e := (Tex.people_e * 2.0) if world else Tex.ui_scale
	var want := maxf(absf(sz.x) / float(w), absf(sz.y) / float(h)) * maxf(0.25, e)
	var k := 0.0625
	while k < want - 0.001 and k < 64.0:
		k *= STEP
	var ck := "%s/%s@%.3f" % [pack, key, k]
	if _ras.has(ck):
		return _ras[ck]
	var t := Vec.raster(Vec.source(pack, key), k)
	if _ras.size() > 3000:
		_ras.clear()
	_ras[ck] = t
	return t


func _draw(ci: RID, pos: Vector2, modulate: Color, transpose: bool) -> void:
	_draw_rect(ci, Rect2(pos, Vector2(w, h)), false, modulate, transpose)


func _draw_rect(ci: RID, rect: Rect2, _tile: bool, modulate: Color, transpose: bool) -> void:
	var t := raster_for(rect.size)
	if t:
		RenderingServer.canvas_item_add_texture_rect(ci, rect, t.get_rid(), false, modulate, transpose)


func _draw_rect_region(ci: RID, rect: Rect2, src: Rect2, modulate: Color, transpose: bool, clip_uv: bool) -> void:
	var t := raster_for(rect.size * Vector2(float(w), float(h)) / src.size.max(Vector2(0.001, 0.001)))
	if t:
		var sk := Vector2(t.get_width(), t.get_height()) / Vector2(float(w), float(h))
		RenderingServer.canvas_item_add_texture_rect_region(ci, rect, t.get_rid(), Rect2(src.position * sk, src.size * sk), modulate, transpose, clip_uv)
