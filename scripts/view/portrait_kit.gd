class_name PortraitKit
extends RefCounted
## 1.33: новые портреты людей — слоистый набор (рисунок владельца игры, собран по слоям; assets/portrait2,
## импорт — tools/import_portraits_133.py). Все слои лежат на общем холсте 512×512 и накладываются от (0,0).
## Кожа, волосы, брови, борода, нос — нейтрально-серые: красятся умножением out = src × цвет / (200/255).
## Одежда, губы, белки глаз, оправа, серьги — свои цвета. По облику (look) собирается «рецепт» —
## список слоёв с цветом и прозрачностью; его рисует Portrait (на видеокарте, без пересборки картинки),
## а compose_image() собирает то же самое в Image (тесты, листы для проверки, снимки).

const DIR := "res://assets/portrait2/"
const CANVAS := 512.0
const REF := 200.0 / 255.0          ## опорный серый набора (#C8C8C8)
const LIP_SKIN := Color("#e8bc94")   ## губы нарисованы под светлую кожу; на смуглой — темнее
const GRAY_HAIR := Color("#b9b7b1")
const WARP_Y0 := 300.0               ## с этой высоты (холст 512) плечи и низ шеи расширяются по телосложению
const WARP_Y1 := 372.0               ## отсюда — полностью
const WARP_STRIP := 8.0
const CACHE_MAX := 128

const HEADS_M := ["oval", "square", "round", "long"]
const HEADS_F := ["soft", "oval", "round"]
## телосложение -> [ширина плеч (м), (ж), шея, щёки, второй подбородок, голова (м), голова (ж), прозрачность шеи]
const BODY := {
	"vthin": [0.88, 0.9, "thin", false, false, "long", "oval", 1.0],
	"thin": [0.94, 0.95, "thin", false, false, "", "", 0.6],
	"normal": [1.0, 1.0, "", false, false, "", "", 1.0],
	"stout": [1.06, 1.04, "strong", false, false, "", "", 1.0],
	"strong": [1.14, 1.08, "strong", false, false, "", "", 1.0],
	"fat": [1.06, 1.05, "", true, false, "round", "round", 1.0],
	"vfat": [1.12, 1.1, "", true, true, "round", "round", 1.0],
}

static var _ok := -1
static var _bbox: Dictionary = {}       ## слой -> Rect2 непустой части (холст 512)
static var _tex: Dictionary = {}        ## слой -> Texture2D
static var _rec: Dictionary = {}        ## ключ облика -> рецепт (LRU)
static var _rec_order: Array[String] = []
static var _img: Dictionary = {}        ## "слой|px" -> Image (для compose_image)
static var _comp: Dictionary = {}       ## ключ -> ImageTexture (LRU)
static var _comp_order: Array[String] = []
static var compose_count := 0           ## сколько раз реально собирали картинку (для теста кэша)
static var _shader: Shader


## Набор на месте и читается. Если нет — Portrait рисует старый векторный портрет.
static func available() -> bool:
	if _ok < 0:
		_ok = 0
		var f := FileAccess.open(DIR + "layers.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary and (d as Dictionary).has("layers"):
				var k := CANVAS / float((d as Dictionary).get("size", 512))
				var lays: Dictionary = (d as Dictionary)["layers"]
				for n: String in lays.keys():
					var bb: Array = lays[n]
					_bbox[n] = Rect2(float(bb[0]) * k, float(bb[1]) * k, float(int(bb[2]) - int(bb[0])) * k, float(int(bb[3]) - int(bb[1])) * k)
				if tex("head_m_oval") != null and tex("collar_overall_m") != null:
					_ok = 1
	return _ok == 1


static func names() -> Array:
	available()
	return _bbox.keys()


static func has(n: String) -> bool:
	return _bbox.has(n)


static func bbox(n: String) -> Rect2:
	return _bbox.get(n, Rect2())


static func tex(n: String) -> Texture2D:
	if _tex.has(n):
		return _tex[n]
	var p := DIR + n + ".png"
	var t: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
	_tex[n] = t
	return t


## Шейдер слоёв: цвет вершины — целевой цвет (как в наборе: умножить и разделить на опорный серый), альфа — прозрачность.
static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	COLOR = vec4(clamp(t.rgb * tint.rgb * %.6f, 0.0, 1.0), t.a * tint.a);
}
""" % (1.0 / REF)
	return _shader


static func heads(fem: bool) -> Array:
	return HEADS_F if fem else HEADS_M


static func head_for(fem: bool, h: String) -> String:
	if fem:
		match h:
			"soft", "oval", "round":
				return h
			"square":
				return "round"
		return "oval"
	match h:
		"oval", "square", "round", "long":
			return h
	return "oval"


static func _hash(lk: Dictionary) -> int:
	return absi(int(lk.get("fs", 0)) + str(lk.get("hair_col", "")).hash() * 3 + int(lk.get("skin", 0)) * 101)


## Одежда на портрете: по спецовке (outfit) и чуть-чуть разнообразия по зерну лица.
static func collar_of(lk: Dictionary) -> String:
	var fem := bool(lk.get("fem", false))
	var outfit := str(lk.get("outfit", "overall"))
	var hat := str(lk.get("hat", ""))
	var r := _hash(lk) % 10
	match outfit:
		"overall":
			if fem and hat == "kerchief":
				return "kerchief"
			return "overall"
		"coat":
			return "robe"
		"vest":
			return "jacket"   # оранжевый жилет электрика и строителя — поверх рабочей куртки
		"jacket":
			return "jacket"
		"apron":
			return "sweater" if r < 5 else "overall"
		"suit":
			if hat == "helmet":
				return "jacket"   # мастер, инженер по ТБ — в цеху в куртке
			if r == 0:
				return "vest"
			if r == 1:
				return "sweater"
			return "suit"
		"shirt":
			return "vest" if r == 0 else "shirt"
		"fireman":
			return "firefighter"
	return "shirt"


static func _tinted(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _plain(a: float = 1.0) -> Color:
	return Color(REF, REF, REF, a)


static func _key(lk: Dictionary, info: Dictionary) -> String:
	return "%s|%d|%d" % [str(lk.hash()), int(info.get("age", lk.get("age", 35))), _mood_band(float(info.get("mood", 55.0)))]


static func _mood_band(m: float) -> int:
	return 2 if m >= 70.0 else (0 if m < 28.0 else 1)


## Рецепт портрета: {"layers": [[слой, цвет, плечи?], ...], "sx": ширина плеч}. Детерминирован: тот же облик — тот же рецепт.
static func recipe(lk: Dictionary, info: Dictionary = {}) -> Dictionary:
	var key := _key(lk, info)
	if _rec.has(key):
		return _rec[key]
	var r := _build(lk, info)
	_rec[key] = r
	_rec_order.append(key)
	if _rec_order.size() > CACHE_MAX:
		_rec.erase(_rec_order.pop_front())
	return r


static func _build(lk: Dictionary, info: Dictionary) -> Dictionary:
	var out: Array = []
	var fem := bool(lk.get("fem", false))
	var g := "f" if fem else "m"
	var age := int(info.get("age", lk.get("age", 35)))
	var skin := Color(str(People.SKINS[clampi(int(lk.get("skin", 1)), 0, People.SKINS.size() - 1)]))
	var hair_c := Color(str(lk.get("hair_col", "#4a3020")))
	# седина с возрастом (у кого волосы ещё не седые): виски и пряди
	var gray_k := clampf((age - 46) / 30.0, 0.0, 0.55)
	if hair_c.s > 0.12 or hair_c.v < 0.45:
		hair_c = hair_c.lerp(GRAY_HAIR, gray_k)
	var brow_c := hair_c.darkened(0.12)
	var fc := People.face(lk, age)
	var bk := People.body_key(lk)
	var bd: Array = BODY.get(bk, BODY["normal"])
	var ovr: Dictionary = lk.get("face_ovr", {}) if lk.get("face_ovr", null) is Dictionary else {}
	var head := head_for(fem, str(fc["head"]))
	var body_head := str(bd[6] if fem else bd[5])
	if body_head != "" and not ovr.has("head"):
		head = body_head
	var hair := People.hair_style(lk)
	var hat := str(lk.get("hat", ""))
	var kerchief := fem and hat == "kerchief"
	var collar := collar_of(lk)
	var cn := "collar_%s_%s" % [collar, g] if collar != "kerchief" else "collar_kerchief_f"
	var sx := float(bd[1] if fem else bd[0])
	# сзади: изнанка воротника, волосы за спиной, грудь в вырезе
	if has(cn + "_back"):
		out.append([cn + "_back", _plain(), true])
	if has("hair_%s_back" % hair):
		out.append(["hair_%s_back" % hair, _tinted(hair_c), true])
	if has(cn + "_skin"):
		out.append([cn + "_skin", _tinted(skin), true])
	out.append(["head_%s_%s" % [g, head], _tinted(skin), true])
	var neck := str(bd[2])
	if neck != "" and not bool(bd[4]):
		out.append(["neck_%s_%s" % [neck, g], _tinted(skin, float(bd[7])), true])
	if bool(bd[3]):
		out.append(["cheeks_full_" + g, _tinted(skin), false])
	if bool(bd[4]):
		out.append(["chin_double_" + g, _tinted(skin), true])
	var ek := str(fc["eyes"])
	out.append(["eyes_" + ek + "_lid", _tinted(skin), false])
	out.append(["eyes_" + ek, _plain(), false])
	out.append(["eyes_" + ek + "_iris", _tinted(People.eye_color(lk).lightened(0.25)), false])
	out.append(["brows_" + str(fc["brows"]), _tinted(brow_c), false])
	out.append(["nose_" + str(fc["nose"]), _tinted(skin), false])
	var mouth := str(fc["mouth"])
	match _mood_band(float(info.get("mood", 55.0))):
		2:
			mouth = "smile"
		0:
			mouth = "down"
	var lip := Color(REF * minf(1.0, lerpf(1.0, skin.r / LIP_SKIN.r, 0.6)), REF * minf(1.0, lerpf(1.0, skin.g / LIP_SKIN.g, 0.6)), REF * minf(1.0, lerpf(1.0, skin.b / LIP_SKIN.b, 0.6)))
	out.append(["mouth_" + mouth, lip, false])
	if bool(fc["freckles"]):
		out.append(["freckles", _plain(0.8), false])
	var lines := str(fc["lines"])
	if lines != "":
		out.append(["lines_" + lines, _plain(0.42 if lines == "mid" else 0.62), false])
	var beard := str(lk.get("beard", ""))
	if beard != "" and not fem and has("beard_" + beard):
		out.append(["beard_" + beard, _tinted(hair_c), false])
	out.append([cn, _plain(), true])
	if has("hair_%s_front" % hair):
		out.append(["hair_%s_front" % hair, _tinted(skin if hair == "bald" else hair_c), false])
	if bool(lk.get("glasses", false)):
		out.append(["glasses", _plain(), false])
	if bool(fc["earrings"]):
		out.append(["earrings", _plain(), false])
	if kerchief:
		var kc := Color(str(lk.get("hat_col", "#8a3e3a")))
		out.append(["kerchief_f_g", _tinted(kc.lightened(0.15)), false])
	return {"layers": out, "sx": sx, "collar": collar, "head": head}


## Кадр на холсте 512 для окошка с пропорцией aspect (ширина/высота): обычный — голова и плечи,
## мелкий (в списках) — крупнее лицо.
static func frame(aspect: float, small: bool) -> Rect2:
	var h := 300.0 if small else 486.0
	var y0 := 40.0 if small else 26.0
	var w := h * aspect
	return Rect2(256.0 - w * 0.5, y0, w, h)


## Нарисовать рецепт в прямоугольник dst (кадр src на холсте). Рисуется на CanvasItem с материалом shader().
## warp = false — плечи не расширять (мелкий портрет в списке: там видно только лицо).
static func draw(ci: CanvasItem, dst: Rect2, src: Rect2, rec: Dictionary, warp: bool = true) -> void:
	var k := dst.size.x / maxf(1.0, src.size.x)
	var sx := float(rec.get("sx", 1.0)) if warp else 1.0
	for l: Array in rec["layers"]:
		var n := str(l[0])
		var t := tex(n)
		if t == null:
			continue
		var bb := bbox(n)
		var col: Color = l[1]
		var tk := t.get_size().x / CANVAS
		if not bool(l[2]) or absf(sx - 1.0) < 0.005 or bb.end.y <= WARP_Y0:
			ci.draw_texture_rect_region(t, Rect2(dst.position + (bb.position - src.position) * k, bb.size * k), Rect2(bb.position * tk, bb.size * tk), col)
			continue
		# верх — как есть, ниже WARP_Y0 — полосами, всё шире к плечам (по горизонтали от середины)
		var y := bb.position.y
		if y < WARP_Y0:
			var top := Rect2(bb.position.x, y, bb.size.x, WARP_Y0 - y)
			ci.draw_texture_rect_region(t, Rect2(dst.position + (top.position - src.position) * k, top.size * k), Rect2(top.position * tk, top.size * tk), col)
			y = WARP_Y0
		while y < bb.end.y:
			var y2 := minf(bb.end.y, y + (WARP_STRIP if y < WARP_Y1 else bb.end.y - y))
			var f := smoothstep(WARP_Y0, WARP_Y1, (y + y2) * 0.5)
			var s := lerpf(1.0, sx, f)
			var x0 := 256.0 + (bb.position.x - 256.0) * s
			var strip := Rect2(x0, y, bb.size.x * s, y2 - y)
			ci.draw_texture_rect_region(t, Rect2(dst.position + (strip.position - src.position) * k, strip.size * k), Rect2(Vector2(bb.position.x, y) * tk, Vector2(bb.size.x, y2 - y) * tk), col)
			y = y2


# ------------------------------------------------------------------ сборка в Image (тесты, листы, снимки)

static func _layer_img(n: String, px: int) -> Image:
	var key := "%s|%d" % [n, px]
	if _img.has(key):
		return _img[key]
	var im: Image = null
	var p := DIR + n + ".png"
	var abs_p := ProjectSettings.globalize_path(p)
	if FileAccess.file_exists(abs_p):
		im = Image.load_from_file(abs_p)
	if im == null:
		var t := tex(n)
		if t != null:
			im = t.get_image()
			if im != null and im.has_mipmaps():
				im.clear_mipmaps()
	if im == null:
		_img[key] = null
		return null
	if im.is_compressed():
		im.decompress()
	im.convert(Image.FORMAT_RGBA8)
	if im.get_width() != px:
		im.resize(px, px, Image.INTERPOLATE_LANCZOS)
	_img[key] = im
	if _img.size() > 600:
		_img.clear()
	return im


## Собрать портрет в Image px×px (весь холст). Тот же рецепт и те же формулы, что при рисовании.
static func compose_image(lk: Dictionary, info: Dictionary, px: int, bg: Color = Color(0, 0, 0, 0)) -> Image:
	var rec := recipe(lk, info)
	var out := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	out.fill(bg)
	var k := float(px) / CANVAS
	var sx := float(rec.get("sx", 1.0))
	for l: Array in rec["layers"]:
		var n := str(l[0])
		var src := _layer_img(n, px)
		if src == null:
			continue
		var bb := bbox(n)
		var r := Rect2i(Vector2i((bb.position * k).floor()), Vector2i((bb.size * k).ceil()) + Vector2i(1, 1)).intersection(Rect2i(0, 0, px, px))
		var col: Color = l[1]
		var warp := bool(l[2]) and absf(sx - 1.0) >= 0.005 and bb.end.y > WARP_Y0
		var plain := col.r == REF and col.g == REF and col.b == REF and col.a >= 1.0
		if plain and not warp:
			out.blend_rect(src, r, r.position)
			continue
		var wr := r
		if warp:
			# по ширине плечи могут выйти за рамку слоя
			var ext := int(ceilf(absf(sx - 1.0) * 256.0 * k)) + 2
			wr = Rect2i(r.position.x - ext, r.position.y, r.size.x + ext * 2, r.size.y).intersection(Rect2i(0, 0, px, px))
		var lay := _tint_region(src, wr, col, warp, sx, k)
		out.blend_rect(lay, Rect2i(0, 0, wr.size.x, wr.size.y), wr.position)
	return out


static func _tint_region(src: Image, r: Rect2i, col: Color, warp: bool, sx: float, k: float) -> Image:
	var w := r.size.x
	var h := r.size.y
	var sd := src.get_data()
	var spx := src.get_width()
	var od := PackedByteArray()
	od.resize(w * h * 4)
	var mr := col.r / REF
	var mg := col.g / REF
	var mb := col.b / REF
	var ma := col.a
	var cx := 256.0 * k
	for yy in h:
		var y := r.position.y + yy
		var s := 1.0
		if warp:
			s = lerpf(1.0, sx, smoothstep(WARP_Y0, WARP_Y1, (float(y) + 0.5) / k))
		var row := y * spx * 4
		var orow := yy * w * 4
		for xx in w:
			var x := r.position.x + xx
			var sxp := x
			if s != 1.0:
				sxp = int(floorf(cx + (float(x) + 0.5 - cx) / s))
				if sxp < 0 or sxp >= spx:
					continue
			var i := row + sxp * 4
			var a := sd[i + 3]
			if a == 0:
				continue
			var o := orow + xx * 4
			od[o] = mini(255, int(float(sd[i]) * mr + 0.5))
			od[o + 1] = mini(255, int(float(sd[i + 1]) * mg + 0.5))
			od[o + 2] = mini(255, int(float(sd[i + 2]) * mb + 0.5))
			od[o + 3] = int(float(a) * ma + 0.5)
	return Image.create_from_data(w, h, false, Image.FORMAT_RGBA8, od)


## Готовая текстура портрета (весь холст px×px) с кэшем по облику — для мест, где нужна одна картинка.
static func compose_texture(lk: Dictionary, info: Dictionary, px: int) -> ImageTexture:
	var key := "%s|%d" % [_key(lk, info), px]
	if _comp.has(key):
		return _comp[key]
	compose_count += 1
	var t := ImageTexture.create_from_image(compose_image(lk, info, px))
	_comp[key] = t
	_comp_order.append(key)
	if _comp_order.size() > CACHE_MAX:
		_comp.erase(_comp_order.pop_front())
	return t
