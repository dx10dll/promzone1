class_name Tex
extends RefCounted
## Кэш текстур. Все SVG грузятся один раз.
## SVG импортируются в K раз крупнее (tools/set_import_scale.py), а текстуре возвращается «логический»
## размер исходного SVG: код рисует в прежних единицах, а на экран идут пиксели высокого разрешения —
## картинка чёткая при любом приближении и на больших мониторах.

const K := 3.0
const HI_DIRS := ["/objects/", "/people/", "/items/", "/tiles/", "/vehicles/", "/ui/", "/fx/", "/portrait/"]
const KEEP := ["glow.svg"]

static var _cache: Dictionary = {}

## Люди при сильном приближении: растеризуются из вектора под текущий масштаб экрана
## (ступени через √2), без мип-карт — чётко и без мыла. 0 — обычные импортированные текстуры.
static var people_k := 1.0   ## 1.14.2: люди всегда из вектора (импортированные SVG людей в сборку не входят)
static var people_rev := 0
static var _people_hi: Dictionary = {}
static var _people_t: Dictionary = {}      ## 1.38.2: ключ -> когда последний раз нужен (счётчик)
static var _people_clock := 0
const PEOPLE_KEEP := 1600
static var _people_lv: Array[String] = []   ## 1.38.2: последние ступени масштаба людей ("@k"), не больше 4


static func get_tex(path: String) -> Texture2D:
	if _cache.has(path):
		return _cache[path]
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		t = _logical(load(path), path)
	_cache[path] = t
	return t


## Текстура высокого разрешения с размером исходного SVG.
static func _logical(src: Texture2D, path: String) -> Texture2D:
	if src == null or not path.ends_with(".svg") or KEEP.has(path.get_file()):
		return src
	var hi := false
	for d: String in HI_DIRS:
		if path.contains(d):
			hi = true
			break
	if not hi:
		return src
	var img := src.get_image()
	if img == null:
		return src
	if img.is_compressed():
		img.decompress()
	if not img.has_mipmaps():
		img.generate_mipmaps()
	var it := ImageTexture.create_from_image(img)
	it.set_size_override(Vector2i(maxi(1, roundi(img.get_width() / K)), maxi(1, roundi(img.get_height() / K))))
	return it


static func tile(name: String) -> Texture2D:
	# 1.48: трава и грунт — растровые тайлы 256 px с мип-уровнями (гладко при любом масштабе)
	var png := "res://assets/tiles/%s.png" % name
	if _cache.has(png):
		return _cache[png]
	if ResourceLoader.exists(png):
		var t: Texture2D = load(png)
		_cache[png] = t
		return t
	return get_tex("res://assets/tiles/%s.svg" % name)


static func item(def_id: String) -> Texture2D:
	return get_tex("res://assets/items/%s.svg" % def_id)


static func person(name: String) -> Texture2D:
	var key := "%s@%.3f" % [name, people_k]
	_people_clock += 1
	if _people_hi.has(key):
		_people_t[key] = _people_clock
		return _people_hi[key]
	var t: Texture2D = null
	var it := Vec.raster_one("people", name, people_k)
	if it:
		it.set_size_override(Vector2i(maxi(1, roundi(it.get_width() / people_k)), maxi(1, roundi(it.get_height() / people_k))))
		t = it
	_people_hi[key] = t
	_people_t[key] = _people_clock
	if _people_hi.size() > PEOPLE_KEEP:
		_evict_people()
	return t


## 1.38.2: растры людей — не больше PEOPLE_KEEP: давние (дольше всех не нужные) вытесняются до 3/4 предела.
## Раньше держались все (до 6000): каждая новая внешность в «Создать рабочего» (человечек крупно, ~3×) и каждая
## новая одёжка/поза людей фона добавляли растры навсегда — память текстур росла с каждой минутой.
static func _evict_people() -> void:
	var ks := _people_hi.keys()
	ks.sort_custom(func(x: String, y: String) -> bool: return int(_people_t.get(x, 0)) < int(_people_t.get(y, 0)))
	for i in ks.size() - PEOPLE_KEEP * 3 / 4:
		_people_hi.erase(ks[i])
		_people_t.erase(ks[i])


## e — сколько пикселей экрана приходится на единицу SVG человека (зум камеры × масштаб окна × 0,5).
## 1.14.2: людей всегда растеризуем из вектора под ступень масштаба (через 2^⅛, не меньше нужной):
## импортированные текстуры с мип-картами при уменьшении мылили контуры.
static var people_e := 1.0


static func set_people_scale(e: float) -> void:
	people_e = e
	var k := 0.25
	while k < e - 0.001 and k < 16.0:
		k *= 1.09050773   # 2^⅛: при растеризации не больше 9 % лишнего — контур не мылится
	k = snappedf(k, 0.001)
	if k == people_k:
		return
	if _people_lv.is_empty():
		_people_lv.append("@%.3f" % people_k)
	people_k = k
	people_rev += 1
	# 1.38.2: растры людей держим только для 4 последних ступеней масштаба (зум туда-обратно — без перерисовки).
	# Раньше копилось до 6000 растров всех ступеней всех видов меню — память текстур росла минутами.
	var tag := "@%.3f" % k
	_people_lv.erase(tag)
	_people_lv.append(tag)
	if _people_lv.size() > 4:
		var drop: String = _people_lv.pop_front()
		for key: String in _people_hi.keys():
			if key.ends_with(drop):
				_people_hi.erase(key)
				_people_t.erase(key)


## 1.48: во сколько раз экран «плотнее» мировых единиц (зум камеры × масштаб окна), ступенями ×√2 вверх.
## Надписи и эмблемы в мире рисуем с таким множителем кегля/разрешения и обратным масштабом — без «пикселей».
static func wscale() -> float:
	var e := maxf(people_e * 2.0, 1.0)
	return pow(2.0, ceilf(log(e) / log(2.0) * 2.0 - 0.001) / 2.0)


## Строка в мировых координатах чётко при любом зуме: кегль × wscale, холст ÷ wscale.
static func world_string(ci: CanvasItem, f: Font, base: Vector2, text: String, align: HorizontalAlignment, width: float, fs: float, col: Color) -> void:
	var k := wscale()
	ci.draw_set_transform(base, 0.0, Vector2(1.0 / k, 1.0 / k))
	ci.draw_string(f, Vector2.ZERO, text, align, width * k if width > 0.0 else -1.0, maxi(4, roundi(fs * k)), col)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Мелкий масштаб: лица попроще (глаза — тёмные овалы), чтобы не превращались в кашу.
static func people_lod() -> bool:
	return people_e < 1.3


static func portrait(name: String) -> Texture2D:
	return get_tex("res://assets/portrait/%s.svg" % name)


## 1.19: значки интерфейса — из вектора точно под размер на экране (VecIcon), без мыла.
static var ui_scale := 1.0
static var _ui_vec: Dictionary = {}


static func ui(name: String) -> Texture2D:
	return _vec_icon(name, false)


## Значок интерфейса, нарисованный в мире (на станке, на зоне): чёткий при любом зуме камеры.
static func ui_world(name: String) -> Texture2D:
	return _vec_icon(name, true)


static func _vec_icon(name: String, world: bool) -> Texture2D:
	var ck := ("w:" if world else "u:") + name
	if _ui_vec.has(ck):
		return _ui_vec[ck]
	# 1.38: цветной значок владельца (assets/ui/icons/<name>.png) важнее прежнего векторного
	var t: Texture2D = png(str(PNG_ALIAS.get(name, name)), 48)
	if t != null:
		_ui_vec[ck] = t
		return t
	t = VecIcon.make("ui", name, world)
	if t == null:
		t = get_tex("res://assets/ui/%s.svg" % name)
	_ui_vec[ck] = t
	return t


## Значок над человеком (эмоции, нужды) — из вектора под зум камеры.
static func emo(name: String) -> Texture2D:
	var ck := "e:" + name
	if _ui_vec.has(ck):
		return _ui_vec[ck]
	var t: Texture2D = png("emo_" + name, 32)
	if t == null:
		t = VecIcon.make("emo", name, true)
	_ui_vec[ck] = t
	return t


## 1.38: цветные значки владельца из assets/ui/icons (PNG 128×128 с прозрачными полями ~12%).
## Логический размер — как у прежнего векторного значка (sz), пиксели — полные 128 с мип-картами:
## места, где значок рисуется «в родном размере», не раздуваются, а при приближении он чёткий.
## Такие текстуры помечены мета-флагом COLOR_META — их не перекрашивают (см. is_color).
const COLOR_META := &"pz_color_icon"
## Зоны, которым нового значка не досталось, — значки меню владельца из набора 1.30.
const PNG_ALIAS := {"zone_accounting": "accounting", "zone_union_office": "union"}
static var _png: Dictionary = {}


static func png(id: String, sz: int = 48) -> Texture2D:
	return crisp(id, sz)


## 1.46: чёткий значок. Причина «мыла»: 128-px PNG показывался в 24-40 px (×0,2-0,3) через мип-карты GPU
## (трилинейное смешение двух уровней) да ещё в окне 1920×1080 (экран 1600×900 ×1,2). Теперь значок заранее
## уменьшается Lanczos-ом до точного числа физических пикселей (логический размер × масштаб окна), без мип-карт:
## на экране он рисуется 1:1. Логический размер текстуры — sz.
const MAX_PX := 128
static var _crisp: Dictionary = {}


## Сколько физических пикселей в одном логическом пикселе интерфейса (stretch canvas_items + масштаб интерфейса).
static func px_scale() -> float:
	var ml := Engine.get_main_loop()
	var tree := ml as SceneTree
	if tree == null or tree.root == null:
		return 1.0
	var w: Window = tree.root
	var base := Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width", 1600)),
		float(ProjectSettings.get_setting("display/window/size/viewport_height", 900)))
	var sc := minf(float(w.size.x) / base.x, float(w.size.y) / base.y)
	return clampf(sc * w.content_scale_factor, 0.5, 4.0)


## Сбросить запечённые значки (сменился размер окна / масштаб интерфейса): новые окна получат точный размер.
static func invalidate_crisp() -> void:
	_crisp.clear()
	_png.clear()
	_ui_vec.clear()


static func crisp(id: String, sz: int = 48) -> Texture2D:
	# 1.47: запекаем в 2× физического размера (потолок — исходник) с мип-картами: дальше GPU уменьшает билинейно-трилинейно,
	# края гладкие, но не «пиксельные» и не мыльные
	var phys := clampi(roundi(float(sz) * px_scale() * 2.0), 16, MAX_PX)
	var ck := "%s@%d@%d" % [id, sz, phys]
	if _crisp.has(ck):
		return _crisp[ck]
	var path := "res://assets/ui/icons/%s.png" % id
	var t: Texture2D = null
	if ResourceLoader.exists(path):
		var src: Texture2D = load(path)
		var img: Image = src.get_image() if src else null
		if img != null:
			if img.is_compressed():
				img.decompress()
			if img.has_mipmaps():
				img.clear_mipmaps()
			if img.get_width() > phys:
				while img.get_width() / 2 >= phys:   # пошагово вдвое (билинейно), финал — кубически
					img.resize(img.get_width() / 2, img.get_height() / 2, Image.INTERPOLATE_BILINEAR)
				if img.get_width() != phys:
					img.resize(phys, phys, Image.INTERPOLATE_CUBIC)
			img.generate_mipmaps()
			var it := ImageTexture.create_from_image(img)
			it.set_size_override(Vector2i(sz, sz))
			it.set_meta(COLOR_META, true)
			it.set_meta(&"pz_icon_id", id)
			t = it
		elif src != null:
			# без видеокарты (headless) картинку не достать — отдаём импортированную как есть
			src.set_meta(COLOR_META, true)
			t = src
	_crisp[ck] = t
	return t


## Тот же значок владельца, но запечённый под другой логический размер показа (если это значок из assets/ui/icons).
static func at(t: Texture2D, sz: float) -> Texture2D:
	if t != null and t.has_meta(&"pz_icon_id"):
		return crisp(str(t.get_meta(&"pz_icon_id")), roundi(sz))
	return t


## Цветной значок владельца — рисовать белым (без перекраски), меняя только прозрачность.
static func is_color(t: Texture2D) -> bool:
	return t != null and t.has_meta(COLOR_META)


## Цвет модуляции для значка: цветной — белый с той же прозрачностью, векторный — как просили.
static func tint(t: Texture2D, col: Color) -> Color:
	return Color(1, 1, 1, col.a) if is_color(t) else col


static func fx(name: String) -> Texture2D:
	return get_tex("res://assets/fx/%s.svg" % name)


static func obj(key: String) -> Texture2D:
	return get_tex("res://assets/objects/%s.svg" % key)


## Иконка груза: материал по коду, деталь по коду или брак.
static func for_item(it: Item) -> Texture2D:
	if it.kind == "part" and it.q == "scrap":
		return item("scrap")
	return item(it.def_id)
