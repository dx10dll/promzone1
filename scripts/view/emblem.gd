class_name Emblem
extends RefCounted
## 1.17: эмблема завода. Собирается как SVG (форма + знак + цвета), растеризуется в текстуру нужного
## размера и кэшируется — чётко и в шапке, и на вывеске. Буквы рисуются шрифтом поверх (draw).

static var _cache := {}


static func _shade(hex: String, k: float) -> String:
	var c := Color(hex)
	if k >= 0.0:
		c = c.lerp(Color.WHITE, k)
	else:
		c = c.lerp(Color.BLACK, -k)
	return "#" + c.to_html(false)


static func _poly(pts: Array) -> String:
	var s: Array[String] = []
	for p: Vector2 in pts:
		s.append("%.2f,%.2f" % [p.x, p.y])
	return " ".join(s)


static func _gear_pts(cx: float, cy: float, ro: float, ri: float, n: int, tw: float, bw: float) -> Array:
	var out: Array = []
	for k in n:
		var b := TAU * k / n - PI / 2.0
		out.append(Vector2(cx, cy) + Vector2.from_angle(b - bw) * ri)
		out.append(Vector2(cx, cy) + Vector2.from_angle(b - tw) * ro)
		out.append(Vector2(cx, cy) + Vector2.from_angle(b + tw) * ro)
		out.append(Vector2(cx, cy) + Vector2.from_angle(b + bw) * ri)
	return out


static func _star_pts(cx: float, cy: float, ro: float, ri: float) -> Array:
	var out: Array = []
	for k in 10:
		var a := -PI / 2.0 + PI * k / 5.0
		out.append(Vector2(cx, cy) + Vector2.from_angle(a) * (ro if k % 2 == 0 else ri))
	return out


static func _circle_path(cx: float, cy: float, r: float) -> String:
	return "M%.2f %.2f A%.2f %.2f 0 1 0 %.2f %.2f A%.2f %.2f 0 1 0 %.2f %.2f Z" % [cx + r, cy, r, r, cx - r, cy, r, r, cx + r, cy]


## Контур формы (path d) в квадрате 100×100 с отступом inset.
static func _shape_path(shape: String, inset: float) -> String:
	var i := inset
	match shape:
		"shield":
			return "M50 %.1f L%.1f %.1f V48 C%.1f %.1f %.1f %.1f 50 %.1f C%.1f %.1f %.1f %.1f %.1f 48 V%.1f Z" % [
				4 + i, 92 - i, 16 + i * 0.6, 92 - i, 72 - i * 0.3, 74 - i * 0.6, 89 - i * 0.6, 97 - i * 1.2,
				28 + i * 0.6, 89 - i * 0.6, 8 + i, 72 - i * 0.3, 8 + i, 16 + i * 0.6]
		"hex":
			var pts: Array = []
			for k in 6:
				pts.append(Vector2(50, 50) + Vector2.from_angle(-PI / 2.0 + TAU * k / 6.0) * (48.0 - i))
			return "M" + _poly(pts).replace(" ", " L") + " Z"
		"diamond":
			var r := 48.0 - i
			return "M50 %.1f L%.1f 50 L50 %.1f L%.1f 50 Z" % [50 - r, 50 + r, 50 + r, 50 - r]
		"square":
			var a := 6.0 + i
			var b := 94.0 - i
			var rr := maxf(4.0, 16.0 - i * 0.5)
			return "M%.1f %.1f H%.1f A%.1f %.1f 0 0 1 %.1f %.1f V%.1f A%.1f %.1f 0 0 1 %.1f %.1f H%.1f A%.1f %.1f 0 0 1 %.1f %.1f V%.1f A%.1f %.1f 0 0 1 %.1f %.1f Z" % [
				a + rr, a, b - rr, rr, rr, b, a + rr, b - rr, rr, rr, b - rr, b, a + rr, rr, rr, a, b - rr, a + rr, rr, rr, a + rr, a]
		"gear":
			var gp := _gear_pts(50, 50, 49.0 - i, 43.0 - i, 14, 0.13, 0.19)
			return "M" + _poly(gp).replace(" ", " L") + " Z"
	return _circle_path(50, 50, 47.0 - i)


static func _symbol(sym: String, fg: String, bg: String) -> String:
	var s := ""
	match sym:
		"gear":
			s = '<path fill="%s" fill-rule="evenodd" d="M%s Z %s"/>' % [fg, _poly(_gear_pts(50, 50, 27, 20, 9, 0.17, 0.26)).replace(" ", " L"), _circle_path(50, 50, 8)]
		"hammer":
			s = '<g transform="rotate(-38 50 50)"><rect x="45" y="36" width="10" height="44" rx="3" fill="%s"/><rect x="29" y="22" width="42" height="16" rx="3" fill="%s"/><rect x="29" y="22" width="8" height="16" rx="2" fill="%s" opacity="0.35"/></g>' % [fg, fg, bg]
		"wrench":
			s = '<g transform="rotate(42 50 50)"><rect x="45" y="40" width="10" height="40" rx="4" fill="%s"/><circle cx="50" cy="31" r="14" fill="%s"/><rect x="45.5" y="15" width="9" height="15" rx="1.5" fill="%s"/></g>' % [fg, fg, bg]
		"gear_hammer":
			s = '<path fill="%s" fill-rule="evenodd" d="M%s Z %s"/>' % [fg, _poly(_gear_pts(50, 50, 28, 21, 10, 0.15, 0.24)).replace(" ", " L"), _circle_path(50, 50, 14)]
			s += '<g transform="rotate(-40 50 50)"><rect x="46.5" y="38" width="7" height="34" rx="2.5" fill="%s" stroke="%s" stroke-width="2"/><rect x="36" y="27" width="28" height="12" rx="2.5" fill="%s" stroke="%s" stroke-width="2"/></g>' % [fg, bg, fg, bg]
		"bolt":
			s = '<polygon fill="%s" points="57,16 33,54 48,54 41,84 68,43 53,43 62,16"/>' % fg
		"anvil":
			s = '<path fill="%s" d="M30 34 H74 C74 44 66 48 60 50 V58 H68 V68 H32 V58 H40 V50 C34 48 30 44 30 40 C24 40 18 38 15 33 C20 34 26 34 30 34 Z"/>' % fg
		"star":
			s = '<polygon fill="%s" points="%s"/>' % [fg, _poly(_star_pts(50, 52, 28, 11.5))]
		"wheat":
			s = '<path d="M50 80 V30" stroke="%s" stroke-width="3.5" stroke-linecap="round"/>' % fg
			for k in 5:
				var y := 34 + k * 9
				s += '<ellipse cx="42" cy="%d" rx="4.6" ry="8" transform="rotate(-32 42 %d)" fill="%s"/>' % [y, y, fg]
				s += '<ellipse cx="58" cy="%d" rx="4.6" ry="8" transform="rotate(32 58 %d)" fill="%s"/>' % [y, y, fg]
			s += '<ellipse cx="50" cy="24" rx="4.4" ry="8" fill="%s"/>' % fg
		"wheel":
			s = '<circle cx="50" cy="50" r="24" fill="none" stroke="%s" stroke-width="6"/><circle cx="50" cy="50" r="29" fill="none" stroke="%s" stroke-width="2.5"/><circle cx="50" cy="50" r="7" fill="%s"/>' % [fg, fg, fg]
			for k2 in 6:
				var a := TAU * k2 / 6.0
				var p1 := Vector2(50, 50) + Vector2.from_angle(a) * 7.0
				var p2 := Vector2(50, 50) + Vector2.from_angle(a) * 22.0
				s += '<line x1="%.1f" y1="%.1f" x2="%.1f" y2="%.1f" stroke="%s" stroke-width="4" stroke-linecap="round"/>' % [p1.x, p1.y, p2.x, p2.y, fg]
		"drop":
			s = '<path fill="%s" d="M50 18 C50 18 29 45 29 58 A21 21 0 0 0 71 58 C71 45 50 18 50 18 Z"/><path fill="none" stroke="%s" stroke-width="3" stroke-linecap="round" opacity="0.45" d="M39 58 A11 11 0 0 0 46 68"/>' % [fg, bg]
		"truss":
			s = '<g fill="none" stroke="%s" stroke-width="4.5" stroke-linejoin="round" stroke-linecap="round"><path d="M20 66 L50 32 L80 66 Z"/><path d="M35 49 L35 66 M50 32 L50 66 M65 49 L65 66 M35 49 L50 66 L65 49"/></g>' % fg
	return s


## SVG эмблемы 100×100.
static func svg(spec: Dictionary) -> String:
	var shape := str(spec.get("shape", "circle"))
	var bg := str(spec.get("bg", Company.BG[0]))
	var fg := str(spec.get("fg", Company.FG[1]))
	var rim := str(spec.get("rim", Company.FG[0]))
	var sym := str(spec.get("symbol", "gear"))
	var out := '<svg xmlns="http://www.w3.org/2000/svg" width="100" height="100" viewBox="0 0 100 100">'
	out += '<defs><linearGradient id="g" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="%s"/><stop offset="1" stop-color="%s"/></linearGradient></defs>' % [_shade(bg, 0.18), _shade(bg, -0.22)]
	out += '<path d="%s" fill="#000" opacity="0.28" transform="translate(1.5 2.5)"/>' % _shape_path(shape, 1.0)
	out += '<path d="%s" fill="url(#g)" stroke="%s" stroke-width="4.5" stroke-linejoin="round"/>' % [_shape_path(shape, 2.5), rim]
	out += '<path d="%s" fill="none" stroke="%s" stroke-width="1.4" opacity="0.55" stroke-linejoin="round"/>' % [_shape_path(shape, 9.0), rim]
	if sym != "letters":
		var sc := 0.78 if shape == "diamond" else (0.9 if shape in ["hex", "shield"] else 1.0)
		var tr := "translate(50 %.1f) scale(%.2f) translate(-50 -50)" % [50.0 if shape != "shield" else 48.0, sc]
		out += '<g transform="%s"><g transform="translate(0.8 1.2)" opacity="0.35">%s</g>%s</g>' % [tr, _symbol(sym, "#000000", "#000000"), _symbol(sym, fg, bg)]
	out += "</svg>"
	return out


## Текстура эмблемы стороной px (кэш).
static func texture(spec: Dictionary, px: int) -> Texture2D:
	var key := JSON.stringify(spec) + "@" + str(px)
	if _cache.has(key):
		return _cache[key]
	var img := Image.new()
	var err := img.load_svg_from_string(svg(spec), float(px) / 100.0)
	if err != OK:
		return null
	var tex := ImageTexture.create_from_image(img)
	if _cache.size() > 400:
		_cache.clear()
	_cache[key] = tex
	return tex


## Нарисовать эмблему в прямоугольник (с буквами, если знак — «Буквы»).
static func draw(ci: CanvasItem, r: Rect2, spec: Dictionary, alpha: float = 1.0, world: bool = false) -> void:
	# 1.48: в мире (вывеска у проходной) разрешение берём по зуму камеры, а не «×2» — иначе вблизи пиксели
	var px := int(clampf(ceilf(maxf(r.size.x, r.size.y) * (Tex.wscale() if world else 2.0)), 16.0, 1024.0))
	var tex := texture(spec, px)
	if tex:
		ci.draw_texture_rect(tex, r, false, Color(1, 1, 1, alpha))
	if str(spec.get("symbol", "")) == "letters":
		var t := str(spec.get("text", "")).left(3)
		if t == "":
			return
		var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
		var fs := int(r.size.y * (0.42 if t.length() <= 1 else (0.34 if t.length() == 2 else 0.27)))
		var base := r.position + Vector2(0, r.size.y * 0.5 + fs * 0.36)
		var col := Color(str(spec.get("fg", "#f2efe6")), alpha)
		if world:
			Tex.world_string(ci, f, base + Vector2(1, 1.5), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(0, 0, 0, 0.35 * alpha))
			Tex.world_string(ci, f, base, t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)
			return
		ci.draw_string(f, base + Vector2(1, 1.5), t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, Color(0, 0, 0, 0.35 * alpha))
		ci.draw_string(f, base, t, HORIZONTAL_ALIGNMENT_CENTER, r.size.x, fs, col)


## Табличка: эмблема слева, название справа (шрифт ужимается под ширину), сверху мелко — форма (ООО).
static func draw_sign_plate(ci: CanvasItem, r: Rect2, spec: Dictionary, name: String, sub: String, text_col: Color = Color("#f2efe6"), world: bool = false) -> void:
	var pad := r.size.y * 0.1
	var es := r.size.y - pad * 2.0
	draw(ci, Rect2(r.position + Vector2(pad, pad), Vector2(es, es)), spec, 1.0, world)
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var tx := r.position.x + pad * 2.0 + es
	var tw := r.end.x - tx - pad
	var fs := int(r.size.y * 0.36)
	while fs > 5 and f.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x > tw:
		fs -= 1
	var sfs := maxi(4, int(r.size.y * 0.17))
	var top := r.position.y + r.size.y * 0.5
	if world:
		if sub != "":
			Tex.world_string(ci, f, Vector2(tx, top - fs * 0.55), sub, HORIZONTAL_ALIGNMENT_LEFT, tw, sfs, Color(text_col, 0.6))
		Tex.world_string(ci, f, Vector2(tx, top + fs * 0.62), name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, text_col)
		return
	if sub != "":
		ci.draw_string(f, Vector2(tx, top - fs * 0.55), sub, HORIZONTAL_ALIGNMENT_LEFT, tw, sfs, Color(text_col, 0.6))
	ci.draw_string(f, Vector2(tx, top + fs * 0.62), name, HORIZONTAL_ALIGNMENT_LEFT, tw, fs, text_col)


## Элемент интерфейса с эмблемой.
class View:
	extends Control
	var spec: Dictionary = {}

	func _init(s: Dictionary = {}, px: float = 48.0) -> void:
		spec = s
		custom_minimum_size = Vector2(px, px)
		mouse_filter = Control.MOUSE_FILTER_PASS

	func set_spec(s: Dictionary) -> void:
		spec = s
		queue_redraw()

	func _draw() -> void:
		var side := minf(size.x, size.y)
		Emblem.draw(self, Rect2((size - Vector2(side, side)) * 0.5, Vector2(side, side)), spec)
