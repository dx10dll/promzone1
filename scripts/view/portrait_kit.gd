class_name PortraitKit
extends RefCounted
## Портреты людей — слоистый набор (рисунок владельца игры, собран по слоям; assets/portrait2,
## импорт — tools/import_portraits_137.py). Все слои лежат на общем холсте 512×512 и накладываются от (0,0).
## 1.37: набор v5 — 14 изолированных наборов (пол × 7 телосложений, папки assets/portrait2/<телосложение>_<m|f>/).
## ВСЕ детали человека берутся из его набора, без подмен из других. Порядок — как в README/compose.py набора:
##   волосы сзади -> изнанка одежды -> шея/плечи (своя у каждой одежды) -> голова -> перед одежды ->
##   веки, глаза, брови, нос, рот -> веснушки, морщины, борода -> волосы спереди -> очки, серьги, головной убор.
## Кожа, волосы, брови, борода, веки, морщины красятся умножением out = src × цвет / (200/255); губы, глаза,
## серьги, очки — своего цвета. Одежда — цветной рисунок, основная ткань (маска _fab) перекрашивается по его
## яркости (= серая версия набора) в цвет спецовки (как у человечка на карте); кепка, каска, косынка — в цвет убора.
## По облику (look) собирается «рецепт» — слои по группам с цветом и маской; его рисует Portrait (на видеокарте),
## а compose_image() собирает то же самое в Image (тесты, листы для проверки).

const DIR := "res://assets/portrait2/"
const CANVAS := 512.0
const REF := 200.0 / 255.0          ## опорный серый набора (#C8C8C8)
const GRAY_HAIR := Color("#b9b7b1")
const CACHE_MAX := 128
## Группы слоёв в порядке рисования; у каждой своя маска: inner и cloth — основная ткань одежды (перекраска),
## back и hair — волосы под головным убором; body — шея и голова, face — черты, top — очки, серьги, убор.
const GROUPS := ["back", "inner", "body", "cloth", "face", "hair", "top"]
const HEADS_M := ["oval", "square", "round", "long"]
const HEADS_F := ["soft", "oval", "round"]
## ближайшая замена, если в наборе нет такой детали (старые сохранения, смена пола) — только внутри набора
const NEAR := {"soft": "oval", "square": "round", "long": "oval",
	"bob": "side", "bun": "slick", "ponytail": "mullet", "long_h": "mullet", "pixie": "short", "curly_f": "curly", "braid": "mullet", "perm": "curly",
	"short": "pixie", "crew": "pixie", "side": "bob", "slick": "bun", "receding": "bun", "bald": "pixie", "curly": "curly_f", "mullet": "long",
	"kerchief": "shirt"}
## телосложение игры -> посадка основы и одежды набора (body_types.json)
const FIT := {"vthin": "very_thin", "thin": "thin", "normal": "normal", "stout": "strong", "strong": "powerful",
	"fat": "full", "vfat": "very_full"}

static var _ok := -1
static var _bbox: Dictionary = {}       ## слой -> Rect2 непустой части (холст 512)
static var _masks: Dictionary = {}      ## имена масок
static var _sets: Dictionary = {}       ## набор -> {heads, hair, beard, outfits, gain, crown, chin}
static var _alias: Dictionary = {}      ## слой -> файл, одинаковый с ним (лежит один раз)
static var _tex: Dictionary = {}        ## слой -> Texture2D
static var _rec: Dictionary = {}        ## ключ облика -> рецепт (LRU)
static var _rec_order: Array[String] = []
static var _img: Dictionary = {}        ## "слой|px" -> Image (для compose_image)
static var _comp: Dictionary = {}       ## ключ -> ImageTexture (LRU)
static var _comp_order: Array[String] = []
static var compose_count := 0           ## сколько раз реально собирали картинку (для теста кэша)
static var _shader: Shader
static var _mats: Dictionary = {}       ## маска -> ShaderMaterial


## Набор на месте и читается. Если нет — Portrait рисует старый векторный портрет.
static func available() -> bool:
	if _ok < 0:
		_ok = 0
		var f := FileAccess.open(DIR + "layers.json", FileAccess.READ)
		if f != null:
			var d: Variant = JSON.parse_string(f.get_as_text())
			if d is Dictionary and (d as Dictionary).has("layers") and int((d as Dictionary).get("version", 0)) >= 5:
				var k := CANVAS / float((d as Dictionary).get("size", 512))
				var lays: Dictionary = (d as Dictionary)["layers"]
				for n: String in lays.keys():
					var bb: Array = lays[n]
					_bbox[n] = Rect2(float(bb[0]) * k, float(bb[1]) * k, float(int(bb[2]) - int(bb[0])) * k, float(int(bb[3]) - int(bb[1])) * k)
				for m: Variant in (d as Dictionary).get("masks", []):
					_masks[str(m)] = true
				_alias = (d as Dictionary).get("alias", {})
				_sets = (d as Dictionary).get("sets", {})
				if _sets.size() == 14 and tex("normal_m/head_m_oval") != null and tex("normal_f/neck_overall_f") != null:
					_ok = 1
	return _ok == 1


static func names() -> Array:
	available()
	return _bbox.keys()


static func mask_names() -> Array:
	available()
	return _masks.keys()


static func has(n: String) -> bool:
	return _bbox.has(n)


static func has_mask(n: String) -> bool:
	return _masks.has(n)


static func bbox(n: String) -> Rect2:
	return _bbox.get(n, Rect2())


## Во сколько поднять яркость основной ткани одежды набора, чтобы её медиана стала опорным серым.
static func gain(sid: String, outfit: String) -> float:
	return float((set_info(sid).get("gain", {}) as Dictionary).get(outfit, 1.0))


static func set_info(sid: String) -> Dictionary:
	return _sets.get(sid, {})


static func set_ids() -> Array:
	available()
	return _sets.keys()


static func tex(n: String) -> Texture2D:
	if _tex.has(n):
		return _tex[n]
	var p := DIR + str(_alias.get(n, n)) + ".png"
	var t: Texture2D = load(p) as Texture2D if ResourceLoader.exists(p) else null
	_tex[n] = t
	return t


## Шейдер слоёв: цвет вершины — целевой цвет (умножить и разделить на опорный серый), альфа — прозрачность.
## Маска (на том же холсте, что и слой): обычно умножает прозрачность; у одежды (fab = 1) — где основная ткань:
## там цвет = яркость рисунка × gain × цвет спецовки, вне ткани — рисунок как есть.
static func shader() -> Shader:
	if _shader == null:
		_shader = Shader.new()
		_shader.code = """shader_type canvas_item;
uniform sampler2D mask : hint_default_white, filter_linear_mipmap;
uniform float fab = 0.0;
uniform float gain = 1.0;
varying vec4 tint;
void vertex() {
	tint = COLOR;
}
void fragment() {
	vec4 t = texture(TEXTURE, UV);
	float m = texture(mask, UV).r;
	vec3 k = tint.rgb * %.6f;
	vec3 own = clamp(t.rgb * k, 0.0, 1.0);
	vec3 cloth = mix(t.rgb, clamp(vec3(dot(t.rgb, vec3(0.299, 0.587, 0.114)) * gain) * k, 0.0, 1.0), m);
	COLOR = vec4(mix(own, cloth, fab), t.a * tint.a * mix(m, 1.0, fab));
}
""" % (1.0 / REF)
	return _shader


## Материал с маской (общий для всех портретов с той же маской; "" — без маски). Маска mask_<одежда>_fab —
## перекраска основной ткани этой одежды.
static func material(mask_name: String) -> ShaderMaterial:
	if _mats.has(mask_name):
		return _mats[mask_name]
	var m := ShaderMaterial.new()
	m.shader = shader()
	if mask_name != "":
		m.set_shader_parameter("mask", tex(mask_name))
		if mask_name.ends_with("_fab"):
			m.set_shader_parameter("fab", 1.0)
			m.set_shader_parameter("gain", _mask_gain(mask_name))
	_mats[mask_name] = m
	return m


## gain по имени маски ткани "<набор>/mask_<одежда>_fab".
static func _mask_gain(mask_name: String) -> float:
	var sl := mask_name.split("/")
	return gain(sl[0], sl[1].trim_prefix("mask_").trim_suffix("_fab")) if sl.size() == 2 else 1.0


## Набор по телосложению и полу: "<посадка>_<m|f>".
static func fit_of(lk: Dictionary) -> String:
	return str(FIT.get(People.body_key(lk), "normal"))


static func set_of(lk: Dictionary) -> String:
	return "%s_%s" % [fit_of(lk), "f" if bool(lk.get("fem", false)) else "m"]


## Формы лица (у всех наборов одного пола — одни и те же).
static func heads(fem: bool) -> Array:
	return HEADS_F if fem else HEADS_M


## Вариант из списка набора: такой же, иначе ближайший (NEAR), иначе первый. Только внутри набора.
static func pick_in(lst: Array, v: String) -> String:
	if lst.is_empty():
		return ""
	if lst.has(v):
		return v
	var nv := str(NEAR.get("long_h" if v == "long" and not lst.has("soft") and not lst.has("oval") else v, ""))
	if nv != "" and lst.has(nv):
		return nv
	return str(lst[0])


## Форма лица для пола (старые сохранения и смена пола: ближайшая из своих).
static func head_for(fem: bool, h: String) -> String:
	return pick_in(heads(fem), h)


static func _hash(lk: Dictionary) -> int:
	return absi(int(lk.get("fs", 0)) + str(lk.get("hair_col", "")).hash() * 3 + int(lk.get("skin", 0)) * 101)


## Состояние живого человека для портрета (как у человечка на карте): переоделся ли в спецовку, зима, на улице ли.
static func live_info(sim: Sim, w: Worker) -> Dictionary:
	var out := {"age": w.age, "mood": w.mood}
	if sim == null or sim.season == null or sim.rooms == null:
		return out
	out["dressed"] = w.dressed
	out["winter"] = sim.season.season_id() == "winter" or sim.season.temp_day < -2.0
	out["outside"] = w.present and not w.visitor and sim.rooms.room_at(w.cell()) == null
	return out


## Одежда на портрете: по спецовке (outfit) и чуть-чуть разнообразия по зерну лица; своя одежда — куртка.
static func collar_of(lk: Dictionary, info: Dictionary = {}) -> String:
	var fem := bool(lk.get("fem", false))
	var hat := str(lk.get("hat", ""))
	if not bool(info.get("dressed", true)):
		return "kerchief" if fem and hat == "kerchief" else "jacket"
	var outfit := str(lk.get("outfit", "overall"))
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


## Головной убор на портрете — как у человечка на карте: каска, кепка, сварочная маска, косынка;
## не переоделся — без каски и маски, зимой ушанка; в мороз на улице — ушанка.
static func hat_of(lk: Dictionary, info: Dictionary = {}) -> String:
	var hat := str(lk.get("hat", ""))
	var winter := bool(info.get("winter", false))
	if not bool(info.get("dressed", true)):
		if hat == "helmet" or hat == "weldmask":
			hat = ""
		if winter and (hat == "" or hat == "cap"):
			hat = "ushanka"
	elif winter and bool(info.get("outside", false)) and (hat == "" or hat == "cap" or hat == "kerchief"):
		hat = "ushanka"
	match hat:
		"cap", "helmet", "ushanka":
			return hat
		"weldmask":
			return "welder_mask"
		"kerchief":
			return "kerchief" if bool(lk.get("fem", false)) else ""
	return ""


static func _tinted(c: Color, a: float = 1.0) -> Color:
	return Color(c.r, c.g, c.b, a)


static func _plain(a: float = 1.0) -> Color:
	return Color(REF, REF, REF, a)


static func _key(lk: Dictionary, info: Dictionary) -> String:
	return "%s|%d|%d|%s%s%s" % [str(lk.hash()), int(info.get("age", lk.get("age", 35))), _mood_band(float(info.get("mood", 55.0))),
		"d" if bool(info.get("dressed", true)) else "s", "w" if bool(info.get("winter", false)) else "", "o" if bool(info.get("outside", false)) else ""]


static func _mood_band(m: float) -> int:
	return 2 if m >= 70.0 else (0 if m < 28.0 else 1)


## Рецепт портрета: {<группа>: [[слой, цвет], ...] для каждой из GROUPS, "mask_<группа>": маска,
## "set", "collar", "head", "hairdo", "hat", "eye"/"chin" — линия глаз и подбородок (холст 512)}. Детерминирован: тот же облик — тот же рецепт.
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
	var gr := {}
	for gname: String in GROUPS:
		gr[gname] = []
	var fem := bool(lk.get("fem", false))
	var g := "f" if fem else "m"
	var sid := set_of(lk)
	var st := set_info(sid)
	var age := int(info.get("age", lk.get("age", 35)))
	var skin := Color(str(People.SKINS[clampi(int(lk.get("skin", 1)), 0, People.SKINS.size() - 1)]))
	var hair_c := Color(str(lk.get("hair_col", "#4a3020")))
	# седина с возрастом (у кого волосы ещё не седые)
	var gray_k := clampf((age - 46) / 30.0, 0.0, 0.55)
	if hair_c.s > 0.12 or hair_c.v < 0.45:
		hair_c = hair_c.lerp(GRAY_HAIR, gray_k)
	var brow_c := hair_c.darkened(0.12)
	var fc := People.face(lk, age)
	var head := pick_in(st.get("heads", heads(fem)), str(fc["head"]))
	var hair := pick_in(st.get("hair", []), People.hair_style(lk))
	var hat := hat_of(lk, info)
	var outfits: Dictionary = st.get("outfits", {})
	var collar := pick_in(outfits.keys(), collar_of(lk, info))
	var o: Dictionary = outfits.get(collar, {})
	var dressed := bool(info.get("dressed", true))
	var cloth := Color(str(lk.get("outfit_col", "#3d5a7a") if dressed else lk.get("street_col", "#3b3f44")))
	var p := sid + "/"
	# 1. волосы сзади, 2. изнанка одежды (за шеей), 3. шея/плечи этой одежды и голова, 4. перед одежды
	if has(p + "hair_%s_back" % hair):
		(gr["back"] as Array).append([p + "hair_%s_back" % hair, _tinted(hair_c)])
	if o.get("inner", null) != null:
		(gr["inner"] as Array).append([p + str(o["inner"]), _tinted(cloth)])
	(gr["body"] as Array).append([p + str(o.get("neck", "")), _tinted(skin)])
	(gr["body"] as Array).append([p + "head_%s_%s" % [g, head], _tinted(skin)])
	(gr["cloth"] as Array).append([p + str(o.get("outer", "")), _tinted(cloth)])
	# 5. веки, глаза, радужка, брови, нос, рот; веснушки, морщины, борода
	var face: Array = gr["face"]
	var ek := str(fc["eyes"])
	face.append([p + "eyes_" + ek + "_lids", _tinted(skin)])
	face.append([p + "eyes_" + ek, _plain()])
	face.append([p + "eyes_" + ek + "_iris", _tinted(People.eye_color(lk).lightened(0.25))])
	face.append([p + "brows_" + str(fc["brows"]), _tinted(brow_c)])
	face.append([p + "nose_" + str(fc["nose"]), _tinted(skin)])
	var mouth := str(fc["mouth"])
	match _mood_band(float(info.get("mood", 55.0))):
		2:
			mouth = "smile"
		0:
			mouth = "down"
	face.append([p + "mouth_" + mouth, _plain()])
	if bool(fc["freckles"]):
		face.append([p + "freckles", _plain(0.8)])
	var lines := str(fc["lines"])
	if lines != "":
		face.append([p + "lines_" + lines, _tinted(skin, 0.5 if lines == "mid" else 0.75)])
	var beard := str(lk.get("beard", ""))
	if beard != "" and not fem:
		beard = pick_in(st.get("beard", []), beard)
		if has(p + "beard_" + beard):
			face.append([p + "beard_" + beard, _tinted(hair_c)])
	# 6. волосы спереди, 7. очки, серьги, головной убор
	if has(p + "hair_%s_front" % hair):
		(gr["hair"] as Array).append([p + "hair_%s_front" % hair, _tinted(skin if hair == "bald" else hair_c)])
	var top: Array = gr["top"]
	if bool(lk.get("glasses", false)):
		top.append([p + "glasses", _plain()])
	if bool(fc["earrings"]) and hat != "ushanka" and has(p + "earrings"):
		top.append([p + "earrings", _plain()])
	var hat_c := Color(str(lk.get("hat_col", "#8a3e3a")))
	match hat:
		"kerchief":
			top.append([p + "kerchief_f", _tinted(hat_c.lightened(0.15))])
		"cap", "helmet":
			top.append([p + hat, _tinted(hat_c)])
		"welder_mask", "ushanka":
			top.append([p + hat, _plain()])
	var hat_mask := p + "mask_hat_" + hat if has_mask(p + "mask_hat_" + hat) else ""
	var fab := p + "mask_%s_fab" % collar if has_mask(p + "mask_%s_fab" % collar) else ""
	var r := {"set": sid, "collar": collar, "head": head, "hairdo": hair, "hat": hat,
		"eye": bbox(p + "eyes_almond").get_center().y, "chin": float(st.get("chin", 635.0)) * CANVAS / 1024.0,
		"mask_back": hat_mask, "mask_inner": fab, "mask_body": "", "mask_cloth": fab, "mask_face": "", "mask_hair": hat_mask, "mask_top": ""}
	for gname: String in GROUPS:
		r[gname] = gr[gname]
	return r


## Все слои рецепта по порядку (для проверок).
static func layer_names(rec: Dictionary) -> Array:
	var out: Array = []
	for gname: String in GROUPS:
		for l: Array in rec.get(gname, []):
			out.append(str(l[0]))
	return out


## Кадр на холсте 512 для окошка с пропорцией aspect (ширина/высота): обычный — голова и плечи,
## мелкий (в списках) — крупнее лицо. 1.37: в наборах v5 лица разного размера и на разной высоте — кадр
## ставится по глазам и подбородку набора (рецепт: "eye", "chin"), размер — наполовину по размеру лица.
static func frame(aspect: float, small: bool, rec: Dictionary = {}) -> Rect2:
	var eye := float(rec.get("eye", 200.0))
	var d := maxf(40.0, float(rec.get("chin", 317.5)) - eye)
	var h := (300.0 if small else 486.0) * sqrt(d / 117.5)
	var y0 := eye - h * (0.533 if small else 0.358)
	var w := h * aspect
	return Rect2(256.0 - w * 0.5, y0, w, h)


## Нарисовать группу рецепта в прямоугольник dst (кадр src на холсте). У CanvasItem — material(маска группы).
static func draw(ci: CanvasItem, dst: Rect2, src: Rect2, rec: Dictionary, group: String) -> void:
	var k := dst.size.x / maxf(1.0, src.size.x)
	for l: Array in rec.get(group, []):
		var n := str(l[0])
		var t := tex(n)
		if t == null:
			continue
		var bb := bbox(n)
		var tk := t.get_size().x / CANVAS
		ci.draw_texture_rect_region(t, Rect2(dst.position + (bb.position - src.position) * k, bb.size * k), Rect2(bb.position * tk, bb.size * tk), l[1])


# ------------------------------------------------------------------ сборка в Image (тесты, листы, снимки)

static func _layer_img(n: String, px: int) -> Image:
	var key := "%s|%d" % [n, px]
	if _img.has(key):
		return _img[key]
	var im: Image = null
	var abs_p := ProjectSettings.globalize_path(DIR + str(_alias.get(n, n)) + ".png")
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
	im.convert(Image.FORMAT_RGBA8)   # маски (оттенки серого) — тоже в RGBA: берём красный
	if im.get_width() != px:
		im.resize(px, px, Image.INTERPOLATE_LANCZOS)
	if _img.size() > 600:
		_img.clear()
	_img[key] = im
	return im


## Собрать портрет в Image px×px (весь холст). Тот же рецепт, порядок, маски и формулы, что при рисовании.
static func compose_image(lk: Dictionary, info: Dictionary, px: int, bg: Color = Color(0, 0, 0, 0)) -> Image:
	return compose_recipe(recipe(lk, info), px, bg)


static func compose_recipe(rec: Dictionary, px: int, bg: Color = Color(0, 0, 0, 0)) -> Image:
	var out := Image.create_empty(px, px, false, Image.FORMAT_RGBA8)
	out.fill(bg)
	var k := float(px) / CANVAS
	for gname: String in GROUPS:
		var mname := str(rec.get("mask_" + gname, ""))
		var mimg: Image = _layer_img(mname, px) if mname != "" else null
		var fab := mname.ends_with("_fab")
		var gn := _mask_gain(mname) if fab else 1.0
		for l: Array in rec.get(gname, []):
			var n := str(l[0])
			var src := _layer_img(n, px)
			if src == null:
				continue
			var bb := bbox(n)
			var r := Rect2i(Vector2i((bb.position * k).floor()), Vector2i((bb.size * k).ceil()) + Vector2i(1, 1)).intersection(Rect2i(0, 0, px, px))
			var col: Color = l[1]
			if col.r == REF and col.g == REF and col.b == REF and col.a >= 1.0 and mimg == null:
				out.blend_rect(src, r, r.position)
				continue
			var lay := tint_region(src, r, col, mimg, fab, gn)
			out.blend_rect(lay, Rect2i(0, 0, r.size.x, r.size.y), r.position)
	return out


## Окраска области слоя — та же формула, что в шейдере: без маски/с маской прозрачности — src × цвет / опорный;
## fab — основная ткань по маске: яркость × gain × цвет / опорный, вне ткани — рисунок как есть.
static func tint_region(src: Image, r: Rect2i, col: Color, mimg: Image = null, fab: bool = false, gn: float = 1.0) -> Image:
	var w := r.size.x
	var h := r.size.y
	var sd := src.get_data()
	var md := mimg.get_data() if mimg != null else PackedByteArray()
	var use_m := md.size() == sd.size()
	var spx := src.get_width()
	var od := PackedByteArray()
	od.resize(w * h * 4)
	var mr := col.r / REF
	var mg := col.g / REF
	var mb := col.b / REF
	var ma := col.a
	for yy in h:
		var row := (r.position.y + yy) * spx * 4
		var orow := yy * w * 4
		for xx in w:
			var i := row + (r.position.x + xx) * 4
			var a := sd[i + 3]
			if a == 0:
				continue
			var o := orow + xx * 4
			var m := float(md[i]) / 255.0 if use_m else 1.0
			var cr := float(sd[i])
			var cg := float(sd[i + 1])
			var cb := float(sd[i + 2])
			if fab:
				var lv := (cr * 0.299 + cg * 0.587 + cb * 0.114) * gn
				od[o] = int(lerpf(cr, minf(255.0, lv * mr), m) + 0.5)
				od[o + 1] = int(lerpf(cg, minf(255.0, lv * mg), m) + 0.5)
				od[o + 2] = int(lerpf(cb, minf(255.0, lv * mb), m) + 0.5)
				od[o + 3] = int(float(a) * ma + 0.5)
			else:
				od[o] = mini(255, int(cr * mr + 0.5))
				od[o + 1] = mini(255, int(cg * mg + 0.5))
				od[o + 2] = mini(255, int(cb * mb + 0.5))
				od[o + 3] = int(float(a) * ma * m + 0.5)
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
