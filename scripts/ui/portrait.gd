class_name Portrait
extends Control
## Портрет человека для интерфейса: отдельная детальная графика (assets/portrait, tools/gen_portraits.py),
## собранная из слоёв. С 1.14.2 черты те же, что у человечка на карте: форма головы, разрез глаз, брови,
## нос, рот, причёска, борода и телосложение. Тонируемые слои умножаются на цвет кожи, волос, глаз,
## одежды и головного убора. Выражение лица — по настроению, морщины — по возрасту.
## Все слои склеиваются в один SVG и растеризуются ровно под размер портрета в пикселях экрана
## (с учётом масштаба интерфейса) — пиксель в пиксель, без мыла и лесенки.

const W := 128.0
const H := 148.0
const WIDE_K := 1.15

static var _cache: Dictionary = {}
static var _order: Array[String] = []

var look: Dictionary = {}
var zoom := 1.0
var age := 35
var mood := 55.0
var wide := false   ## кадр чуть шире (больше плеч и фона) — для личной карточки
var doc := false    ## светлый фон, как на фото для пропуска
var _tex: Texture2D
var _tex_key := ""


## info: необязательные {"age": лет, "mood": настроение 0–100, "wide": шире кадр, "doc": фон как на пропуске}.
func set_look(lk: Dictionary, z: float = 1.0, info: Dictionary = {}) -> void:
	look = lk
	zoom = z
	age = int(info.get("age", lk.get("age", age)))
	mood = float(info.get("mood", mood))
	wide = bool(info.get("wide", false))
	doc = bool(info.get("doc", false))
	clip_contents = true
	custom_minimum_size = (Vector2(64.0 * (WIDE_K if wide else 1.0), 74) * z).round()
	texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR
	_tex_key = ""
	queue_redraw()


func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()


## Слои снизу вверх: [имя слоя портрета, цвет]. Черты те же, что у человечка на карте (People.face):
## форма головы, разрез глаз, брови, нос, рот, морщины, веснушки, серьги, причёска, борода, телосложение.
const HAIR_BACK := ["long", "ponytail", "curly_f", "perm", "mullet"]


func layers() -> Array:
	var out: Array = []
	out.append(["bg", Color.WHITE])   # 1.20: фон один для всех — светлая стена с силуэтом завода
	var skin := Color(People.SKINS[int(look.get("skin", 1)) % People.SKINS.size()])
	var hair_c := Color(str(look.get("hair_col", "#4a3020")))
	var cloth := Color(str(look.get("outfit_col", "#3d5a7a")))
	var hat_c := Color(str(look.get("hat_col", "#ffffff")))
	var fem := bool(look.get("fem", false))
	var g := "f" if fem else "m"
	var shape := str(People.body_of(look)["shape"])
	var fat := People.body_key(look) in ["fat", "vfat"]
	var hat := str(look.get("hat", ""))
	var outfit := str(look.get("outfit", "overall"))
	var fc := People.face(look, age)
	var hair := People.hair_style(look)
	var beard := str(look.get("beard", ""))
	if HAIR_BACK.has(hair) and hat not in ["ushanka", "helmet", "weldmask"]:
		out.append(["hairback_" + hair, hair_c])
	out.append(["body_" + shape, cloth])
	out.append(["body_fx_" + shape, Color.WHITE])
	out.append(["neck_wide" if fat else "neck", skin])
	out.append(["neck_fx", Color.WHITE])
	out.append(["outfit_%s_%s" % [outfit, shape], Color.WHITE])
	if bool(look.get("resp", false)):
		out.append(["resp", Color.WHITE])
	var hs := str(fc["head"])
	out.append(["head_" + hs, skin])
	out.append(["head_fx_" + hs, Color.WHITE])
	if fat:
		out.append(["chin", skin])
	var ek := str(fc["eyes"])
	out.append(["eyes_%s_%s" % [ek, g], Color.WHITE])
	out.append(["iris_%s_%s" % [ek, g], People.eye_color(look)])
	out.append(["eyes_top_%s_%s" % [ek, g], Color.WHITE])
	out.append(["nose_" + str(fc["nose"]), Color.WHITE])
	var mouth := str(fc["mouth"])
	if mood >= 70.0:
		mouth = "smile"
	elif mood < 28.0:
		mouth = "down"
	out.append(["mouth_%s_%s" % [mouth, g], Color.WHITE])
	if str(fc["lines"]) != "":
		out.append(["lines_" + str(fc["lines"]), Color.WHITE])
	if bool(fc["freckles"]):
		out.append(["freckles", Color.WHITE])
	if beard != "":
		out.append(["beard_" + beard, hair_c])
	out.append(["brows_" + str(fc["brows"]), hair_c])
	if hair != "bald" or hat == "":
		out.append(["hair_" + hair, hair_c])
	if hair == "bald" and hat == "":
		out.append(["bald_fx", Color.WHITE])
	if bool(fc["earrings"]) and hat not in ["ushanka", "kerchief"]:
		out.append(["earrings", Color.WHITE])
	if bool(look.get("glasses", false)):
		out.append(["glasses", Color.WHITE])
	if hat != "":
		out.append(["hat_" + hat, hat_c])
		out.append(["hat_%s_fx" % hat, Color.WHITE])
	if bool(look.get("phones", false)):
		out.append(["phones", Color.WHITE])
	return out


## Сколько пикселей экрана приходится на единицу интерфейса здесь.
func _screen_k() -> float:
	if not is_inside_tree():
		return 1.0
	var k := get_global_transform_with_canvas().get_scale().x * get_viewport().get_final_transform().get_scale().x
	return maxf(k, 0.25)


static func build_texture(lays: Array, px_w: int, is_wide: bool = false) -> Texture2D:
	var sig := PackedStringArray()
	for l: Array in lays:
		sig.append("%s:%s" % [l[0], (l[1] as Color).to_html(false)])
	var key := "%d|%s|%s" % [px_w, str(is_wide), ",".join(sig)]
	if _cache.has(key):
		return _cache[key]
	var vw := W * (WIDE_K if is_wide else 1.0)
	var vx := -(vw - W) * 0.5
	var parts := PackedStringArray()
	parts.append("<svg xmlns=\"http://www.w3.org/2000/svg\" xmlns:xlink=\"http://www.w3.org/1999/xlink\" width=\"%.1f\" height=\"148\" viewBox=\"%.1f 0 %.1f 148\">" % [vw, vx, vw])
	var n := 0
	for l: Array in lays:
		var nm := str(l[0])
		if nm == "@docbg":
			# фон «как на пропуск»: светлый, с мягкой виньеткой
			parts.append("<defs><radialGradient id=\"docbg\" cx=\"0.5\" cy=\"0.38\" r=\"0.8\"><stop offset=\"0\" stop-color=\"#e9edf0\"/><stop offset=\"0.6\" stop-color=\"#cfd6dc\"/><stop offset=\"1\" stop-color=\"#a9b3bc\"/></radialGradient></defs>")
			parts.append("<rect x=\"%.1f\" y=\"0\" width=\"%.1f\" height=\"148\" fill=\"url(#docbg)\"/>" % [vx, vw])
			continue
		if is_wide and nm == "bg":
			parts.append("<rect x=\"%.1f\" y=\"0\" width=\"%.1f\" height=\"98\" fill=\"#c9c3bb\"/><rect x=\"%.1f\" y=\"98\" width=\"%.1f\" height=\"50\" fill=\"#e9e5e0\"/>" % [vx, vw, vx, vw])
		if Vec.has("portrait", nm):
			parts.append(Vec.inner("portrait", nm, l[1]))
			n += 1
	parts.append("</svg>")
	var tex: Texture2D = Vec.raster("".join(parts), float(px_w) / vw) if n > 0 else null
	_cache[key] = tex
	_order.append(key)
	if _order.size() > 240:
		_cache.erase(_order.pop_front())
	return tex


func _draw() -> void:
	if look.is_empty():
		return
	var px := maxi(16, roundi(size.x * _screen_k()))
	var lays := layers()
	var key := "%d|%s|%s" % [px, str(wide), str(lays)]
	if key != _tex_key:
		_tex_key = key
		_tex = build_texture(lays, px, wide)
	if _tex:
		draw_texture_rect(_tex, Rect2(Vector2.ZERO, size), false)
	draw_rect(Rect2(Vector2.ZERO, size), Color("#8a949d") if doc else Color("#5a636c"), false, 1.0)
