class_name Vec
extends RefCounted
## Векторная графика «на лету»: исходные SVG людей и портретов (assets/vec/*.json, собирает
## tools/pack_vec.py) растеризуются точно под нужный размер в пикселях экрана. Так портреты
## в карточках и люди при сильном приближении остаются чёткими без мыла и «лесенки»
## на любом мониторе и при любом масштабе интерфейса.

static var _packs: Dictionary = {}
static var _inner: Dictionary = {}
static var _re_hex: RegEx
static var _re_id: RegEx
static var _re_url: RegEx
static var _re_href: RegEx


static func _pack(pack: String) -> Dictionary:
	if _packs.has(pack):
		return _packs[pack]
	var d: Dictionary = {}
	var f := FileAccess.open("res://assets/vec/%s.json" % pack, FileAccess.READ)
	if f:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			d = parsed
	_packs[pack] = d
	return d


static func has(pack: String, name: String) -> bool:
	return _pack(pack).has(name)


static func source(pack: String, name: String) -> String:
	return str(_pack(pack).get(name, ""))


static func _init_re() -> void:
	if _re_hex:
		return
	_re_hex = RegEx.create_from_string("#([0-9a-fA-F]{6}|[0-9a-fA-F]{3})(?![0-9a-zA-Z_])")
	_re_id = RegEx.create_from_string("id=\"([^\"]+)\"")
	_re_url = RegEx.create_from_string("url\\(#([^)]+)\\)")
	_re_href = RegEx.create_from_string("href=\"#([^\"]+)\"")


## Содержимое SVG без обёртки <svg>, с уникальными id и цветами, умноженными на col
## (как modulate у спрайта: белая основа превращается в цвет кожи, волос, одежды).
static func inner(pack: String, name: String, col: Color = Color.WHITE) -> String:
	var key := "%s/%s/%s" % [pack, name, col.to_html(false)]
	if _inner.has(key):
		return _inner[key]
	var s := source(pack, name)
	var res := ""
	if s != "":
		_init_re()
		var a := s.find(">", s.find("<svg"))
		var b := s.rfind("</svg>")
		var body := s.substr(a + 1, b - a - 1) if a >= 0 and b > a else s
		var p := name.replace(".", "_") + "_"
		body = _re_id.sub(body, "id=\"%s$1\"" % p, true)
		body = _re_url.sub(body, "url(#%s$1)" % p, true)
		body = _re_href.sub(body, "href=\"#%s$1\"" % p, true)
		if col != Color.WHITE:
			body = tint(body, col)
		res = "<g>" + body + "</g>"
	_inner[key] = res
	return res


## Умножить все цвета #rgb/#rrggbb в тексте SVG на цвет.
static func tint(svg: String, col: Color) -> String:
	_init_re()
	var out := ""
	var last := 0
	for m in _re_hex.search_all(svg):
		out += svg.substr(last, m.get_start() - last)
		var hx := m.get_string(1)
		if hx.length() == 3:
			hx = hx[0] + hx[0] + hx[1] + hx[1] + hx[2] + hx[2]
		var c := Color("#" + hx)
		out += "#" + Color(c.r * col.r, c.g * col.g, c.b * col.b).to_html(false)
		last = m.get_end()
	out += svg.substr(last)
	return out


## Растеризовать готовый SVG-текст в масштабе k (пикселей на единицу SVG).
static func raster(svg: String, k: float, mipmaps: bool = false) -> ImageTexture:
	var img := Image.new()
	if img.load_svg_from_string(svg, k) != OK or img.is_empty():
		return null
	if mipmaps:
		img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Один слой целиком (без тонировки) в масштабе k.
static func raster_one(pack: String, name: String, k: float, mipmaps: bool = false) -> ImageTexture:
	var s := source(pack, name)
	if s == "":
		return null
	return raster(s, k, mipmaps)
