class_name BubbleArt
extends RefCounted
## 1.50d: облачко-мысль в духе Prison Architect: светлое облачко, хвостик из двух кружков к голове,
## тёмная обводка и одна чёткая пиктограмма. Рисуем вектором (SVG) и запекаем в текстуру 2× от физического
## размера: одно облачко — одна текстура, один вызов отрисовки. Обводка по ярусу: спокойная / жёлтая / красная.

const W := 46.0     ## логический размер облачка (с хвостиком), экранных пикселей
const H := 55.5
const VW := 34      ## размер холста SVG
const VH := 41

const INK := "#2c353d"
const COLS := {1: "#4a5560", 2: "#f2b81c", 3: "#e0412f"}
const FILLS := {1: "#fbfaf4", 2: "#fff8dc", 3: "#ffeee9"}

static var _cache: Dictionary = {}


static func tex(kind: String, tier: int) -> Texture2D:
	var sc := _scale()
	var ck := "%s|%d|%.2f" % [kind, tier, sc]
	if _cache.has(ck):
		return _cache[ck]
	var img := Image.new()
	var t: Texture2D = null
	if img.load_svg_from_string(svg(kind, tier), sc) == OK and not img.is_empty():
		t = ImageTexture.create_from_image(img)
	if _cache.size() > 400:
		_cache.clear()
	_cache[ck] = t
	return t


static func _scale() -> float:
	return snappedf(clampf(Tex.px_scale() * 2.0, 1.0, 6.0), 0.25)


const _BODY := [[8.0, 16.0, 6.6], [26.0, 16.0, 6.6], [17.0, 9.6, 8.2], [11.0, 20.0, 6.2], [23.0, 20.0, 6.2], [17.0, 18.0, 7.6]]
const _TAIL := [[15.5, 32.4, 3.2], [17.6, 38.0, 2.0]]


static func svg(kind: String, tier: int) -> String:
	tier = clampi(tier, 1, 3)
	var ring := str(COLS[tier])
	var s := '<svg xmlns="http://www.w3.org/2000/svg" width="%.1f" height="%.1f" viewBox="0 0 %d %d">' % [W, H, VW, VH]
	# тёмное «гало» (читается на любом полу), затем цветное кольцо, затем светлая заливка
	s += '<g fill="#14181c" fill-opacity="0.55">' + _circles(2.9) + '</g>'
	s += '<g fill="%s">' % (INK if tier == 1 else ring) + _circles(1.9) + '</g>'
	if tier > 1:
		s += '<g fill="%s">' % INK + _circles(0.9) + '</g>'
	s += '<g fill="%s">' % FILLS[tier] + _circles(0.0) + '</g>'
	s += '<g transform="translate(17 15.2) scale(1.0)">' + glyph(kind) + '</g>'
	return s + '</svg>'


static func _circles(grow: float) -> String:
	var o := ""
	for c: Array in _BODY + _TAIL:
		o += '<circle cx="%.2f" cy="%.2f" r="%.2f"/>' % [c[0], c[1], float(c[2]) + grow]
	return o


static func _star(n: int, ro: float, ri: float, rot: float = -90.0) -> String:
	var pts := ""
	for i in n * 2:
		var a := deg_to_rad(rot + 180.0 * i / n)
		var r := ro if i % 2 == 0 else ri
		pts += "%.2f,%.2f " % [cos(a) * r, sin(a) * r]
	return pts


## Пиктограмма на сетке 20×20 с центром в нуле.
static func glyph(k: String) -> String:
	var ink := INK
	match k:
		"op_turning":   # токарный: патрон, вал, резец, стружка
			return '<rect x="-10" y="-6" width="4.2" height="12" rx="1" fill="#55606b" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-5.8" y="-3.6" width="13" height="7.2" fill="#aebccb" stroke="%s" stroke-width="1.3"/>' % ink \
				+ '<path d="M-2 -3.6V3.6M1.6 -3.6V3.6" stroke="#7d8c9b" stroke-width="1"/>' \
				+ '<path d="M2 -10 H8 V-6 L5.2 -3.6 H2 Z" fill="#e8842c" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M8.4 2 L10 4 M7 5 L8 8" stroke="#e8842c" stroke-width="1.5" stroke-linecap="round"/>'
		"op_milling":   # фреза над заготовкой
			return '<rect x="-2.6" y="-10" width="5.2" height="5" fill="#55606b" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<path d="M-3.8 -5 H3.8 V3 L0 6 L-3.8 3 Z" fill="#c9d3dd" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-3.4 -2.6 L3.4 -0.4 M-3.4 0.4 L3.4 2.6" stroke="%s" stroke-width="1"/>' % ink \
				+ '<rect x="-9.5" y="6.2" width="19" height="3.8" fill="#8a5a34" stroke="%s" stroke-width="1.2"/>' % ink
		"op_drilling":   # свёрло
			return '<rect x="-3" y="-10" width="6" height="5" fill="#55606b" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<path d="M-3.4 -5 H3.4 L3.4 3 L0 8.2 L-3.4 3 Z" fill="#c9d3dd" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-3.4 -2.5 L3.4 -0.5 M-3.4 0.8 L3.4 2.8" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<path d="M-8 9.6 H8" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % ink
		"op_welding":   # сварочная вспышка и электрод
			return '<path d="M9.5 -9.5 L1.6 -1.6" stroke="%s" stroke-width="3.4" stroke-linecap="round"/>' % ink \
				+ '<polygon points="%s" transform="translate(-1.5 2.5)" fill="#ffd54a" stroke="#e8842c" stroke-width="1.2" stroke-linejoin="round"/>' % _star(8, 8.2, 3.2) \
				+ '<circle cx="-1.5" cy="2.5" r="2.2" fill="#ffffff"/>'
		"op_heat":   # печь с огнём
			return '<path d="M-9 9.5 V-1 Q-9 -8 0 -8 Q9 -8 9 -1 V9.5 Z" fill="#8c6b58" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M-5 9.5 V3 Q-5 -2 0 -2 Q5 -2 5 3 V9.5 Z" fill="#2b2220"/>' \
				+ '<path d="M0 8.6 C-3.4 8.6 -3.6 5 -1.6 2.6 C-1.4 4 -0.6 4.2 -0.4 3 C0.8 4.4 3.6 5.2 3.2 7.2 C3 8.2 1.6 8.6 0 8.6 Z" fill="#ff8a2a"/>' \
				+ '<path d="M0 8.6 C-1.4 8.4 -1.4 7 -0.2 6 C0.8 6.8 1.6 8 0 8.6 Z" fill="#ffd54a"/>'
		"op_paint":   # валик
			return '<rect x="-9.5" y="-8.5" width="15" height="6.6" rx="2" fill="#3f8de0" stroke="%s" stroke-width="1.3"/>' % ink \
				+ '<path d="M5.5 -5.2 H8.4 V0.4 H0 V3.4" fill="none" stroke="%s" stroke-width="1.5" stroke-linejoin="round"/>' % ink \
				+ '<rect x="-1.9" y="3" width="3.8" height="7" rx="1.2" fill="#b4793c" stroke="%s" stroke-width="1.2"/>' % ink
		"op_assembly", "op_gear":   # шестерня
			return '<polygon points="%s" fill="#8393a3" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % [_star(8, 9.6, 7.0, -22.5).replace("  ", " "), ink] \
				+ '<circle r="5.4" fill="#aebccb" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<circle r="2.2" fill="#fbfaf4" stroke="%s" stroke-width="1.1"/>' % ink
		"op_casting":   # ковш с расплавом
			return '<path d="M-9 -7 H1 L-0.6 3 H-7.4 Z" fill="#59626b" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M1 -6 L5.2 -1 L3.2 0" fill="#59626b" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>' % ink \
				+ '<path d="M4.6 -0.4 Q5.6 3 5 5.4" stroke="#ff8a2a" stroke-width="2.2" fill="none" stroke-linecap="round"/>' \
				+ '<rect x="0.4" y="5.6" width="10" height="4.4" fill="#8a96a2" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<ellipse cx="-4" cy="-6.4" rx="4" ry="1.3" fill="#ff8a2a"/>'
		"op_stamping":   # пресс
			return '<rect x="-7" y="-10" width="14" height="4.6" fill="#59626b" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-3" y="-5.4" width="6" height="6.4" fill="#aebccb" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-7" y="3.6" width="14" height="2.4" fill="#e8842c" stroke="%s" stroke-width="1"/>' % ink \
				+ '<rect x="-9.5" y="6" width="19" height="4" fill="#59626b" stroke="%s" stroke-width="1.2"/>' % ink
		"build":   # молоток
			return '<g transform="rotate(35)"><rect x="-1.8" y="-4" width="3.6" height="14.4" rx="1.2" fill="#b4793c" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-7.4" y="-9.4" width="14.8" height="6.4" rx="1.4" fill="#aebccb" stroke="%s" stroke-width="1.3"/></g>' % ink
		"demolish":   # кувалда и обломки
			return '<g transform="rotate(35)"><rect x="-1.6" y="-4" width="3.2" height="14.4" rx="1.1" fill="#8a5a34" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-7.4" y="-9.6" width="14.8" height="7" rx="1.4" fill="#59626b" stroke="%s" stroke-width="1.3"/></g>' % ink \
				+ '<path d="M-9.5 9 L-7 6.2 L-4.6 9 Z M4.6 9.6 L7 6 L9.6 9.6 Z" fill="#b8573a" stroke="%s" stroke-width="1"/>' % ink
		"haul":   # ящик со стрелкой
			return '<rect x="-9" y="-5" width="14" height="12.6" fill="#d9a468" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M-9 -0.6 H5 M-2 -5 V7.6" stroke="#8a5a34" stroke-width="1.4"/>' \
				+ '<path d="M4 -8 H10 M7.4 -10 L10.2 -7.6 L7.4 -5.2" fill="none" stroke="#3f9a4a" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M-9 9.8 H5" stroke="%s" stroke-width="1.6" stroke-linecap="round"/>' % ink
		"clean":   # метла
			return '<path d="M5 -10 L-1.4 0" stroke="#8a5a34" stroke-width="2.4" stroke-linecap="round"/>' \
				+ '<path d="M-3 -1.2 L3.2 1.8 L1.2 9.8 L-9 8.4 Z" fill="#e0b34a" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-4 4.2 L-2 9 M-0.6 3.2 L-1.4 9.4 M2 2.4 L0 9.6" stroke="#9a6f1e" stroke-width="1"/>' \
				+ '<circle cx="7" cy="7" r="1.1" fill="#9aa3ab"/><circle cx="9.4" cy="3.8" r="0.9" fill="#9aa3ab"/>'
		"repair":   # гаечный ключ
			return '<g transform="rotate(-45)"><rect x="-1.9" y="-3" width="3.8" height="14" rx="1.6" fill="#9eacba" stroke="%s" stroke-width="1.3"/>' % ink \
				+ '<path d="M-4.8 -4.4 V-9 H-1.6 V-6 H1.6 V-9 H4.8 V-4.4 Q4.8 -2 0 -2 Q-4.8 -2 -4.8 -4.4 Z" fill="#9eacba" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/></g>' % ink
		"study":   # раскрытая книга
			return '<path d="M0 -5 Q-5 -8 -10 -6.4 V6 Q-5 4.6 0 8 Z" fill="#3f78c8" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M0 -5 Q5 -8 10 -6.4 V6 Q5 4.6 0 8 Z" fill="#5a93e0" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-7.4 -2.6 Q-4 -3.6 -2.4 -2.2 M-7.4 0.6 Q-4 -0.4 -2.4 1 M2.4 -2.2 Q4 -3.6 7.4 -2.6 M2.4 1 Q4 -0.4 7.4 0.6" stroke="#dbe8f7" stroke-width="1" fill="none"/>'
		"exam":   # листок с галочкой
			return '<rect x="-6.6" y="-9" width="13.2" height="18" rx="1.6" fill="#ffffff" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<rect x="-3" y="-10.4" width="6" height="3.2" rx="1" fill="#59626b" stroke="%s" stroke-width="1"/>' % ink \
				+ '<path d="M-3.8 1 L-1 4 L4 -2.6" fill="none" stroke="#3f9a4a" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M-3.8 7 H3" stroke="#aab2b9" stroke-width="1.2"/>'
		"eat":   # миска с паром
			return '<path d="M-9 0 H9 Q9 8.6 0 8.6 Q-9 8.6 -9 0 Z" fill="#e8842c" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-3 -8 Q-5 -5.6 -3 -3.6 Q-1 -1.8 -3 0 M2.6 -8 Q0.6 -5.6 2.6 -3.6 Q4.6 -1.8 2.6 0" fill="none" stroke="#9aa3ab" stroke-width="1.5" stroke-linecap="round"/>'
		"hungry":   # пустая тарелка, вилка и нож
			return '<circle r="5.4" fill="#ffffff" stroke="%s" stroke-width="1.4"/><circle r="2.8" fill="none" stroke="#c9ced3" stroke-width="1"/>' % ink \
				+ '<path d="M-9.8 -8.6 V-3.4 M-8 -8.6 V-3.4 M-6.2 -8.6 V-3.4 M-9.8 -3.4 Q-8 -1.6 -6.2 -3.4 M-8 -2.4 V9" fill="none" stroke="#7d8c9b" stroke-width="1.5" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M8.2 9.4 V-9 Q11 -6.4 10.2 -1 Q9.8 0.6 8.2 0.8" fill="#aebccb" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>' % ink
		"rest":   # кровать
			return '<rect x="-10" y="0" width="20" height="5" rx="1.2" fill="#7a64c8" stroke="%s" stroke-width="1.3"/>' % ink \
				+ '<rect x="-10" y="-6" width="3" height="16" rx="1" fill="#8a5a34" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<rect x="-6" y="-3.4" width="6" height="3.4" rx="1.6" fill="#ffffff" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<path d="M2.4 -9 H7 L2.4 -4 H7" fill="none" stroke="#7a64c8" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
		"tired":   # Zzz
			return '<path d="M-9 -8 H-1 L-9 0 H-1" fill="none" stroke="#7a64c8" stroke-width="2.8" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M1 -1 H6.6 L1 5.4 H6.6" fill="none" stroke="#7a64c8" stroke-width="2.4" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M6 5.8 H9.6 L6 9.8 H9.6" fill="none" stroke="#a89bdc" stroke-width="1.8" stroke-linecap="round" stroke-linejoin="round"/>'
		"smoke":   # сигарета и дымок
			return '<rect x="-10" y="3" width="15" height="4" rx="0.8" fill="#ffffff" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="-10" y="3" width="4.4" height="4" fill="#e8842c" stroke="%s" stroke-width="1.2"/>' % ink \
				+ '<rect x="5" y="3" width="2.6" height="4" fill="#e0412f" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<path d="M6.4 0 Q4 -3 6.4 -5.4 Q8.6 -7.6 6.6 -10 M9.8 0.6 Q8.4 -2 10 -3.6" fill="none" stroke="#9aa3ab" stroke-width="1.5" stroke-linecap="round"/>'
		"wc":   # табличка WC
			return '<rect x="-10" y="-7" width="20" height="14" rx="2.4" fill="#3f8de0" stroke="%s" stroke-width="1.3"/>' % ink \
				+ '<path d="M-7.6 -3.4 L-5.8 3.4 L-4 -1 L-2.2 3.4 L-0.4 -3.4" fill="none" stroke="#ffffff" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round"/>' \
				+ '<path d="M7.6 -2.6 A3.6 3.8 0 1 0 7.6 2.6" fill="none" stroke="#ffffff" stroke-width="1.9" stroke-linecap="round"/>'
		"home":   # домик
			return '<path d="M-10 0 L0 -9 L10 0" fill="#c9503a" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<rect x="-7" y="0" width="14" height="9.6" fill="#ece3cc" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<rect x="-1.8" y="3.4" width="3.6" height="6.2" fill="#8a5a34" stroke="%s" stroke-width="1"/>' % ink
		"idle":   # песочные часы
			return '<path d="M-5.6 -8.4 H5.6 L0 0 Z" fill="#f0c860" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M0 0 L5.6 8.4 H-5.6 Z" fill="#f0c860" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-7.4 -9.4 H7.4 M-7.4 9.4 H7.4" stroke="%s" stroke-width="2" stroke-linecap="round"/>' % ink \
				+ '<path d="M-2.4 6 H2.4" stroke="#b78a1e" stroke-width="1.4"/>'
		"inspect":   # лупа
			return '<circle cx="-2" cy="-2" r="6" fill="#cfe6f5" stroke="%s" stroke-width="2"/>' % ink \
				+ '<path d="M2.4 2.4 L9 9" stroke="%s" stroke-width="3.2" stroke-linecap="round"/>' % ink \
				+ '<path d="M-5 -4.6 Q-3.6 -6.6 -1 -6.6" fill="none" stroke="#ffffff" stroke-width="1.4" stroke-linecap="round"/>'
		"office":   # документ
			return '<path d="M-6.6 -9.4 H2.6 L6.6 -5.4 V9.4 H-6.6 Z" fill="#ffffff" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<path d="M2.6 -9.4 V-5.4 H6.6" fill="#dfe5ea" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-3.6 -1.6 H3.6 M-3.6 1.6 H3.6 M-3.6 4.8 H1" stroke="#7d8c9b" stroke-width="1.3" stroke-linecap="round"/>'
		"guard":   # щит
			return '<path d="M0 -10 L8.6 -6.6 V0 Q8.6 6.6 0 10 Q-8.6 6.6 -8.6 0 V-6.6 Z" fill="#3f78c8" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<polygon points="%s" fill="#ffffff"/>' % _star(5, 4.4, 1.9)
		"nurse":   # аптечка
			return '<rect x="-9" y="-6" width="18" height="14" rx="2.4" fill="#ffffff" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M-3 -8.6 V-6 M3 -8.6 V-6" stroke="%s" stroke-width="1.8"/>' % ink \
				+ '<path d="M0 -3.2 V6.4 M-4.8 1.6 H4.8" stroke="#e0412f" stroke-width="3.2"/>'
		"cook", "food":   # кастрюля
			return '<path d="M-8 -2 H8 V5 Q8 9.6 3 9.6 H-3 Q-8 9.6 -8 5 Z" fill="#9eacba" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-10 -2 H10" stroke="%s" stroke-width="2.2" stroke-linecap="round"/>' % ink \
				+ '<path d="M-3 -9 Q-5 -6.6 -3 -5 M3 -9 Q1 -6.6 3 -5" fill="none" stroke="#9aa3ab" stroke-width="1.5" stroke-linecap="round"/>'
		"dress":   # спецовка
			return '<path d="M-3.4 -9 L-9.4 -5.4 L-6.8 -1 L-4.6 -2.4 V9.4 H4.6 V-2.4 L6.8 -1 L9.4 -5.4 L3.4 -9 Q0 -6 -3.4 -9 Z" fill="#3f78c8" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink
		"helmet":   # каска
			return _helmet()
		"no_ppe":   # каска, перечёркнутая
			return _helmet() + '<circle r="9.4" fill="none" stroke="#e0412f" stroke-width="2.2"/><path d="M-6.6 -6.6 L6.6 6.6" stroke="#e0412f" stroke-width="2.2"/>'
		"chat", "talk":   # речь с тремя точками
			return '<path d="M-9 -7 H9 Q10 -7 10 -6 V3 Q10 4 9 4 H0.4 L-4.4 9 V4 H-9 Q-10 4 -10 3 V-6 Q-10 -7 -9 -7 Z" fill="#7fc48a" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<circle cx="-4.4" cy="-1.4" r="1.4" fill="#ffffff"/><circle cx="0" cy="-1.4" r="1.4" fill="#ffffff"/><circle cx="4.4" cy="-1.4" r="1.4" fill="#ffffff"/>'
		"laugh":   # смайлик
			return '<circle r="9" fill="#ffd54a" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<circle cx="-3.2" cy="-2.6" r="1.3" fill="%s"/><circle cx="3.2" cy="-2.6" r="1.3" fill="%s"/>' % [ink, ink] \
				+ '<path d="M-5.2 1.4 Q0 8.4 5.2 1.4 Z" fill="#ffffff" stroke="%s" stroke-width="1.2" stroke-linejoin="round"/>' % ink
		"idea":   # лампочка
			return '<path d="M0 -9 A6 6 0 0 1 3.6 1.8 V4 H-3.6 V1.8 A6 6 0 0 1 0 -9 Z" fill="#ffd54a" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % ink \
				+ '<path d="M-3 6.4 H3 M-2 9 H2" stroke="%s" stroke-width="1.6" stroke-linecap="round"/>' % ink \
				+ '<path d="M-10 -5 L-8 -4.4 M10 -5 L8 -4.4 M0 -10.6 V-9.6" stroke="#e8842c" stroke-width="1.5" stroke-linecap="round"/>'
		"fire":   # огонь
			return '<path d="M0 -10 C1 -6 6.4 -4 6.4 2.4 C6.4 7 3.6 9.8 0 9.8 C-3.6 9.8 -6.4 7 -6.4 3 C-6.4 0 -4.6 -1 -4 -4 C-2.4 -3 -1.6 -1.8 -1.4 0 C0 -2.6 1.4 -6 0 -10 Z" fill="#ff7a2a" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink \
				+ '<path d="M0 9.6 C-2.8 9.6 -3.4 6.6 -1.6 4.6 C-0.8 5.6 0 5.4 0.2 4.4 C2.6 6 2.8 9.6 0 9.6 Z" fill="#ffd54a"/>'
		"strike":   # плакат
			return '<path d="M0 -1 V10" stroke="#8a5a34" stroke-width="2.4" stroke-linecap="round"/>' \
				+ '<rect x="-9.4" y="-10" width="18.8" height="10.6" rx="1.4" fill="#ffffff" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M0 -8 V-3.2" stroke="#e0412f" stroke-width="2.4" stroke-linecap="round"/><circle cx="0" cy="-0.4" r="1.2" fill="#e0412f" transform="translate(0 -0.2)"/>'
		"argue":   # молния
			return '<polygon points="2,-10 -6.4,1.2 -1.2,1.2 -3,10 6.4,-2.6 0.8,-2.6" fill="#ff9a2a" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % ink
		"fight":   # звезда удара
			return '<polygon points="%s" fill="#e0412f" stroke="%s" stroke-width="1.3" stroke-linejoin="round"/>' % [_star(9, 10.2, 5.0), ink] \
				+ '<path d="M-3.2 -3.2 L3.2 3.2 M3.2 -3.2 L-3.2 3.2" stroke="#ffffff" stroke-width="2.2" stroke-linecap="round"/>'
		"injury":   # пластырь
			return '<g transform="rotate(-40)"><rect x="-10" y="-3.8" width="20" height="7.6" rx="3.8" fill="#e8c28a" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<rect x="-3.6" y="-3.8" width="7.2" height="7.6" fill="#f7e6c8" stroke="%s" stroke-width="1.1"/>' % ink \
				+ '<circle cx="-7" cy="0" r="0.8" fill="#b88a50"/><circle cx="7" cy="0" r="0.8" fill="#b88a50"/></g>' \
				+ '<path d="M5 -9 Q7.2 -6 5 -4.4 Q2.8 -6 5 -9 Z" fill="#e0412f"/>'
		"angry":   # злое лицо
			return '<circle r="9" fill="#ef6b50" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M-6 -5.4 L-1.6 -3 M6 -5.4 L1.6 -3" stroke="%s" stroke-width="1.9" stroke-linecap="round"/>' % ink \
				+ '<circle cx="-3.2" cy="-1" r="1.2" fill="%s"/><circle cx="3.2" cy="-1" r="1.2" fill="%s"/>' % [ink, ink] \
				+ '<path d="M-4 6 Q0 2.4 4 6" fill="none" stroke="%s" stroke-width="1.8" stroke-linecap="round"/>' % ink
		"cold":   # снежинка
			var o := '<g stroke="#4a9ad8" stroke-width="2" stroke-linecap="round" fill="none">'
			for i in 3:
				var a := PI / 3.0 * i
				o += '<path d="M%.2f %.2f L%.2f %.2f"/>' % [cos(a) * 9.4, sin(a) * 9.4, -cos(a) * 9.4, -sin(a) * 9.4]
			o += '<path d="M-2.4 -7.6 L0 -5.6 L2.4 -7.6 M-2.4 7.6 L0 5.6 L2.4 7.6" stroke-width="1.4"/></g>'
			return o
		"hot":   # термометр и солнце
			return '<rect x="-2.6" y="-9.6" width="5.2" height="13" rx="2.6" fill="#ffffff" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<circle cx="0" cy="6" r="4.2" fill="#e0412f" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<rect x="-1" y="-2" width="2" height="8" fill="#e0412f"/>' \
				+ '<path d="M6 -8 H9.6 M6.4 -4.4 H8.8 M6 -1 H9.6" stroke="%s" stroke-width="1.3" stroke-linecap="round"/>' % ink
		"wait_pay":   # монета с рублём
			return '<circle cx="-1" cy="-1" r="8.4" fill="#f2b81c" stroke="%s" stroke-width="1.4"/>' % ink \
				+ '<path d="M-4.4 5 V-6 H-0.4 Q3 -6 3 -3 Q3 0 -0.4 0 H-4.4 M-6.4 2.6 H2" fill="none" stroke="%s" stroke-width="1.7" stroke-linecap="round" stroke-linejoin="round"/>' % ink \
				+ '<circle cx="6.4" cy="6.4" r="3.8" fill="#ffffff" stroke="%s" stroke-width="1.2"/><path d="M6.4 4.2 V6.6 L8 7.6" fill="none" stroke="%s" stroke-width="1.1" stroke-linecap="round"/>' % [ink, ink]
	return '<circle r="3" fill="#7d8c9b"/>'


static func _helmet() -> String:
	return '<path d="M-8.6 3 Q-8.6 -8 0 -8 Q8.6 -8 8.6 3 Z" fill="#ffd54a" stroke="%s" stroke-width="1.4" stroke-linejoin="round"/>' % INK \
		+ '<rect x="-10.4" y="3" width="20.8" height="3.4" rx="1.4" fill="#e8b62a" stroke="%s" stroke-width="1.3"/>' % INK \
		+ '<path d="M-1.4 -8 V3 M1.4 -8 V3" stroke="#e8b62a" stroke-width="1"/>'
