class_name OverlayLayer
extends Node2D
## Оверлеи поверх мира: помещения (цвет по назначению, подписи, требования)
## и электросеть (кабели, источники, нагрузка, потребители без питания).

const T := World.T

var sim: Sim
var mode := ""            ## "" | "rooms" | "power" | "temp" | "water" | "light" | "noise" | "traffic" | "load"
var hover_room := -1
var legend: Array = []    ## [[текст, цвет]] — пояснение для карточки легенды в интерфейсе
var _t := 0.0


func _ready() -> void:
	z_index = 40


func set_mode(m: String) -> void:
	if m == mode:
		return
	mode = m
	queue_redraw()


func _process(delta: float) -> void:
	if mode == "":
		return
	_t -= delta
	if _t <= 0.0:
		_t = 0.25
		queue_redraw()


func _zoom() -> float:
	return get_viewport().get_canvas_transform().get_scale().x


## Подпись на карте: размер следует за масштабом, но в разумных пределах, на тёмной плашке —
## читается на любом полу.
func _text(pos: Vector2, s: String, size: float, col: Color, center: bool = true, outline: bool = true) -> void:
	var z := maxf(0.3, _zoom())
	var px := clampi(int(round(size * z * 0.75)), 9, 12)
	_text_px(pos, s, px, col, true)


## Текст фиксированного экранного размера (px) — не раздувается при приближении и не мельчит при отдалении.
## 1.23: подписи мельче (×0,75), а налезающие друг на друга — сдвигаются вниз или не рисуются.
func _text_px(pos: Vector2, s: String, px0: int, col: Color, bg: bool = false, always: bool = false) -> void:
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	var z := maxf(0.3, _zoom())
	var px := maxi(9, int(round(px0 * 0.78)))
	var w := f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, px).x / z
	var p := pos - Vector2(w * 0.5, 0)
	var hgt := px * 1.25 / z
	var box := Rect2(p + Vector2(-3.0 / z, -hgt * 0.8), Vector2(w + 6.0 / z, hgt))
	if not always:
		var tries := 0
		while _hits(box) and tries < 2:
			box.position.y += hgt + 1.0 / z
			p.y += hgt + 1.0 / z
			tries += 1
		if _hits(box):
			return
	_placed.append(box)
	if bg:
		draw_rect(box, Color(0.07, 0.08, 0.09, 0.78))
	draw_set_transform(p, 0.0, Vector2(1.0 / z, 1.0 / z))
	if not bg:
		draw_string_outline(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, 3, Color(0.08, 0.09, 0.1, 0.9))
	draw_string(f, Vector2.ZERO, s, HORIZONTAL_ALIGNMENT_LEFT, -1, px, col)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


var _placed: Array[Rect2] = []


func _hits(r: Rect2) -> bool:
	for q in _placed:
		if q.intersects(r):
			return true
	return false


func _text_w(s: String, px: int) -> float:
	var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
	return f.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, maxi(9, int(round(px * 0.78)))).x / maxf(0.3, _zoom())


func _draw() -> void:
	if sim == null:
		return
	legend = []
	_placed.clear()
	match mode:
		"rooms":
			_draw_rooms()
		"power":
			_draw_power()
		"temp":
			_draw_temp()
		"water":
			_draw_water()
		"light":
			_draw_light()
		"noise":
			_draw_noise()
		"traffic":
			_draw_traffic()
		"load":
			_draw_load()
		"dirt":
			_draw_dirt()
		"vent":
			_draw_vent()
		"air":
			_draw_air()
		"nets":
			_draw_nets()
		"crew":
			_draw_crew()


## Пояснение к оверлею (1.12): строки уходят в карточку легенды справа, у панели оверлеев.
func _legend(lines: Array) -> void:
	legend = lines


# ---------------------------------------------------------------- освещение

func _draw_light() -> void:
	var w := sim.world
	var n := w.w * w.h
	var cover := PackedByteArray()
	cover.resize(n)
	var lamps: Array[Thing] = []
	for t: Thing in sim.things.values():
		if not t.built or t.kind() != "light":
			continue
		lamps.append(t)
		var on := sim.power.powered(t)
		var rr := float(t.def().get("light_r", 3.0))
		var home := sim.rooms.space_id_at(t.cell)
		var ri := int(ceil(rr))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				if Vector2(dx, dy).length() > rr:
					continue
				var c := t.cell + Vector2i(dx, dy)
				if not w.inb(c) or sim.rooms.space_id_at(c) != home:
					continue
				var i := w.idx(c)
				cover[i] = maxi(cover[i], 2 if on else 1)
	var day := sim.is_daylight()
	for r in sim.rooms.list:
		var good := 0
		for c in r.cells:
			var v := cover[w.idx(c)]
			var col: Color
			if v == 2:
				col = Color(1.0, 0.84, 0.36, 0.30)
				good += 1
			elif v == 1:
				col = Color(0.6, 0.6, 0.6, 0.25)
			elif r.windows > 0:
				col = Color(0.62, 0.8, 1.0, 0.16)
			else:
				col = Color(0.05, 0.08, 0.3, 0.5)
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), col)
		if r.type == "" and r.area() < 4:
			continue
		var pct := int(round(100.0 * good / maxf(1.0, float(r.area()))))
		var ok := pct >= 60
		var tail := "" if r.windows > 0 else L.t(" · без окон")
		_text(r.center * T + Vector2(0, 26), L.t("лампы %d%%%s") % [pct, tail], 14, UITheme.GOOD if ok else (UITheme.WARN if r.windows > 0 else UITheme.BAD))
	for t in lamps:
		var rr2 := float(t.def().get("light_r", 3.0)) * T
		var cc := (Vector2(t.cell) + Vector2(0.5, 0.5)) * T
		var on2 := sim.power.powered(t)
		var lc := Color("#ffd257") if on2 else Color("#9a9a9a")
		draw_arc(cc, rr2, 0.0, TAU, 40, Color(lc.r, lc.g, lc.b, 0.22), 1.0)
		draw_circle(cc, 4.0, lc)
		if not on2:
			_text(cc + Vector2(0, -8), L.t("нет тока"), 12, UITheme.BAD)
	_legend([[L.t("Освещение: жёлтым — светят лампы, голубым — свет из окон днём, синим — темно"), UITheme.TEXT],
		[L.t("Ночью и в помещениях без окон лампы должны покрывать 60%% площади. %s") % (L.t("Сейчас день.") if day else L.t("Сейчас темно — работают только лампы.")), UITheme.MUTED]])


# ---------------------------------------------------------------- шум

func _draw_noise() -> void:
	var w := sim.world
	var n := w.w * w.h
	var lvl := PackedFloat32Array()
	lvl.resize(n)
	var labels: Array = []
	for m in sim.things_of("machine"):
		if not m.built:
			continue
		var base := float(Season.NOISE.get(m.process(), 75.0)) - (6.0 if m.is_cnc() else 0.0)
		if not m.working:
			labels.append([m, base, false])
			continue
		labels.append([m, base, true])
		var mc := m.cell + m.size() / 2
		var home := sim.rooms.space_of_thing(m)
		var ri := int(ceil((base - 58.0) / 2.2))
		for dy in range(-ri, ri + 1):
			for dx in range(-ri, ri + 1):
				var c := mc + Vector2i(dx, dy)
				if not w.inb(c):
					continue
				var v := base - 2.2 * Vector2(dx, dy).length()
				if sim.rooms.space_id_at(c) != home:
					v -= 18.0
				var i := w.idx(c)
				if v > lvl[i]:
					lvl[i] = v
	for i in n:
		var v2 := lvl[i]
		if v2 < 60.0:
			continue
		var c2 := Vector2i(i % w.w, i / w.w)
		var col := Color("#d8c84a") if v2 < 70.0 else (Color("#e0883a") if v2 < 80.0 else Color("#d9483b"))
		draw_rect(Rect2(Vector2(c2) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.18 + clampf((v2 - 60.0) / 30.0, 0.0, 1.0) * 0.25))
	for lb: Array in labels:
		var m2: Thing = lb[0]
		var mc2 := (Vector2(m2.cell) + Vector2(m2.size()) * 0.5) * T
		if bool(lb[2]):
			_text(mc2, L.t("%d дБ") % int(lb[1]), 14, Color("#ffb0a0") if float(lb[1]) >= 80.0 else Color("#ffd8a0"))
		else:
			_text(mc2, L.t("стоит"), 12, UITheme.MUTED)
	_legend([[L.t("Шум работающих станков: жёлтым — до 70 дБ, оранжевым — до 80, красным — выше 80 дБ"), UITheme.TEXT],
		[L.t("Стены гасят шум. Рядом с шумными станками не ставьте столовую, контору и комнату отдыха"), UITheme.MUTED]])


# ---------------------------------------------------------------- потоки людей

## Чистота: где лежит стружка и грязь, уровень обустройства и чистота каждого помещения.
func _draw_dirt() -> void:
	var w := sim.world
	var up := sim.upkeep
	if up.dirt.size() != w.w * w.h:
		return
	for r in sim.rooms.list:
		for c in r.cells:
			var v := int(up.dirt[w.idx(c)])
			if v < 25:
				continue
			var k := clampf(float(v) / 200.0, 0.0, 1.0)
			var col := Color(0.85, 0.75, 0.3).lerp(Color(0.75, 0.35, 0.15), k)
			col.a = 0.18 + 0.5 * k
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), col)
	for r2 in sim.rooms.list:
		if r2.type == "":
			continue
		var lv := up.level(r2)
		var cl := up.cleanliness(r2)
		_text(r2.center * T, L.t("%s · чисто %d%%") % ["★".repeat(lv) + "☆".repeat(5 - lv), cl], 12, UITheme.GOOD if cl >= 70 else (UITheme.WARN if cl >= 40 else UITheme.BAD))
	_legend([[L.t("Чистота и обустройство: стружка и грязь на полу, звёзды — уровень помещения"), UITheme.TEXT],
		[L.t("Стружку сметают уборщицы (Люди → Найм) в контейнеры для стружки; лом сдают по пятницам"), UITheme.MUTED],
		[L.t("Уровень поднимают окна, хороший пол, свет, растения и декор; грязь его снижает"), UITheme.MUTED]])


func _draw_traffic() -> void:
	var w := sim.world
	if sim.traffic.size() != w.w * w.h:
		_legend([[L.t("Потоки людей: данных пока нет — пусть поработают"), UITheme.MUTED]])
		return
	var mx := 1.0
	for v in sim.traffic:
		mx = maxf(mx, v)
	for i in sim.traffic.size():
		var v2 := sim.traffic[i]
		if v2 < mx * 0.03:
			continue
		var k := clampf(sqrt(v2 / mx), 0.0, 1.0)
		var col := Color("#3d7fd0").lerp(Color("#e6c23a"), clampf(k * 2.0, 0.0, 1.0)) if k < 0.5 else Color("#e6c23a").lerp(Color("#e0483a"), (k - 0.5) * 2.0)
		var c := Vector2i(i % w.w, i / w.w)
		draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.22 + k * 0.4))
	_legend([[L.t("Потоки людей: где чаще ходят (синим — редко, красным — тропа)"), UITheme.TEXT],
		[L.t("Длинные красные дорожки — лишние шаги: ставьте склады, шкафчики и туалет ближе к рабочим местам"), UITheme.MUTED]])


# ---------------------------------------------------------------- загрузка станков

func _draw_load() -> void:
	var ms := sim.things_of("machine")
	for m in ms:
		if not m.built:
			continue
		var r := Rect2(Vector2(m.cell) * T, Vector2(m.size()) * T)
		var u := m.util
		var col := Color("#d9483b") if u < 0.25 else (Color("#e6c23a") if u < 0.6 else Color("#5fbf6a"))
		if m.broken:
			col = Color("#8a2a2a")
		elif not m.enabled:
			col = Color("#777777")
		draw_rect(r, Color(col.r, col.g, col.b, 0.32))
		draw_rect(r.grow(-1), col, false, 2.0)
		var st := "%d%%" % int(round(u * 100.0))
		if m.broken:
			st = L.t("сломан")
		elif not m.enabled:
			st = L.t("выключен")
		_text(r.get_center() + Vector2(0, -2), st, 15, col.lightened(0.3))
		var sub := ""
		if m.parts_made > 0:
			sub = L.t("%d шт.") % m.parts_made
			if m.defects > 0:
				sub += L.t(" · брак %d%%") % int(round(100.0 * m.defects / maxf(1.0, float(m.parts_made))))
		if sub != "":
			_text(r.get_center() + Vector2(0, 18.0 / maxf(0.3, _zoom())), sub, 12, Color("#ffb0a0") if m.defects > 0 and float(m.defects) / maxf(1.0, float(m.parts_made)) > 0.05 else UITheme.MUTED)
	var li := sim.office.load_info()
	var tail := ""
	if float(li[0]) > 0.3 and str(li[1]) != "":
		tail = L.t("Заказы: ~%.1f раб. дн., проблемный участок — %s") % [float(li[0]), Defs.process_name(str(li[1])).to_lower()]
	_legend([[L.t("Загрузка станков в рабочее время: зелёным — от 60%, жёлтым — 25–60%, красным — простаивает"), UITheme.TEXT],
		[tail if tail != "" else L.t("Принятых заказов нет — станки ждут работы"), UITheme.WARN if tail != "" else UITheme.MUTED]])


func _draw_rooms() -> void:
	var w := sim.world
	for r in sim.rooms.list:
		var col := Color("#9aa3ab")
		if r.type != "":
			col = Color(str(Defs.rooms.get(r.type, {}).get("color", "#9aa3ab")))
		var a := 0.32 if r.id == hover_room else 0.2
		for c in r.cells:
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), Color(col.r, col.g, col.b, a))
		# граница помещения
		for c in r.cells:
			for d in Rooms.DIRS:
				var n: Vector2i = c + d
				if sim.rooms.room_at(n) == r:
					continue
				var p0 := Vector2(c) * T
				var seg: Array
				match d:
					Vector2i(1, 0):
						seg = [p0 + Vector2(T, 0), p0 + Vector2(T, T)]
					Vector2i(-1, 0):
						seg = [p0, p0 + Vector2(0, T)]
					Vector2i(0, 1):
						seg = [p0 + Vector2(0, T), p0 + Vector2(T, T)]
					_:
						seg = [p0, p0 + Vector2(T, 0)]
				draw_line(seg[0], seg[1], Color(col.r, col.g, col.b, 0.9), 2.0)
		var center := r.center * T
		# название зоны уже написано на полу — подпись крупно только у той, на которую навели
		if r.id == hover_room or r.type == "":
			_text(center + Vector2(0, -2), r.title(), 12.0, col.lightened(0.35))
		var sub := L.t("%d кл.") % r.area()
		var sub_col := Color("#c9c5b8")
		if r.type != "":
			if r.valid:
				sub = L.t("✓ оборудовано · %s") % "★".repeat(sim.upkeep.level(r))
				sub_col = Color("#8fcf78")
			else:
				sub = ""    # чего не хватает — уже на жёлтой метке в углу зоны
		if not r.lit and not sim.is_daylight():
			sub = L.t("темно") if sub == "" else sub + L.t(" · темно")
		if sub != "":
			_text(center + Vector2(0, 12), sub, 9.5, sub_col)
	if sim.rooms.list.is_empty():
		_text(Vector2(w.w * T * 0.5, 4 * T), L.t("Помещений пока нет: обнесите пол стенами с дверью"), 13.0, Color("#e0aa48"))
	var lg: Array = [[L.t("Цвет — группа зон: оранжевый — производство, жёлтый — склад, зелёный — быт, синий — кабинеты, фиолетовый — учёба и профком."), UITheme.TEXT],
		[L.t("Пунктир — граница двух зон в одном зале. Серым — помещение без разметки."), UITheme.MUTED]]
	var bad := 0
	for r2 in sim.rooms.list:
		if r2.type != "" and not r2.valid:
			bad += 1
	if bad > 0:
		lg.append([L.t("Зон, которым чего-то не хватает: %d — жёлтый треугольник в углу зоны.") % bad, UITheme.WARN])
	_legend(lg)


func _draw_power() -> void:
	var w := sim.world
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.05, 0.07, 0.12, 0.35))
	var pw := sim.power
	# кабели
	for i in w.w * w.h:
		if w.cable[i] != 1:
			continue
		var c := w.cell_of(i)
		var ni := pw.net_of[i] if i < pw.net_of.size() else -1
		var col := Color("#8a8f94")
		if ni >= 0 and ni < pw.nets.size():
			var net: Power.Net = pw.nets[ni]
			if net.tripped:
				col = Color("#d8644e")
			elif net.capacity > 0.0:
				col = Color("#f2c84b") if net.load <= net.capacity else Color("#ff8a3a")
		var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * T
		var linked := false
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if w.has_cable(c + d):
				draw_line(ctr, ctr + Vector2(d) * T, col, 4.0)
				linked = true
		if not linked:
			draw_circle(ctr, 3.0, col)
		draw_circle(ctr, 2.5, col.darkened(0.3))
	draw_plans("cable", Color("#f2c84b"))
	# комнаты: свет
	for r in sim.rooms.list:
		var ctr2 := r.center * T
		if r.powered:
			_text_px(ctr2, L.t("свет есть"), 12, Color("#f2c84b"))
		else:
			_text_px(ctr2, L.t("нет подключения"), 12, Color("#9aa3ab"))
	var hover := Vector2i(floori(get_global_mouse_position().x / T), floori(get_global_mouse_position().y / T))
	var hover_txt := ""
	var hover_pos := Vector2.ZERO
	var hover_col := Color.WHITE
	# объекты
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var src := str(t.def().get("power_source", "")) != ""
		var draws := t.kind() == "machine" or float(t.def().get("power_kw", 0.0)) > 0.0
		if not src and not draws:
			continue
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		var top := rr.position + Vector2(rr.size.x * 0.5, -4)
		var hovered := Rect2i(t.cell, t.size()).has_point(hover)
		if t.kind() == "light":
			# светильник: тонкий провод до кабеля (или пунктирный круг — до какого кабеля дотянется)
			var lc := (Vector2(t.cell) + Vector2(0.5, 0.5)) * T
			if pw.light_link.has(t.id):
				var cc: Vector2i = pw.light_link[t.id]
				var col_l := Color("#f2c84b") if pw.powered(t) else Color("#9aa3ab")
				draw_line(lc, (Vector2(cc) + Vector2(0.5, 0.5)) * T, Color(0.05, 0.05, 0.05, 0.6), 2.4)
				draw_line(lc, (Vector2(cc) + Vector2(0.5, 0.5)) * T, col_l, 1.2)
				draw_circle(lc, 4.0, col_l)
			else:
				draw_arc(lc, (Defs.b("light_link_r") + 0.5) * T, 0.0, TAU, 48, Color(0.85, 0.4, 0.35, 0.55), 1.5)
				draw_circle(lc, 4.0, Color("#d8644e"))
				if hovered:
					hover_txt = L.t("%s · нет кабеля ближе %d клеток") % [t.title(), int(Defs.b("light_link_r"))]
					hover_pos = top
					hover_col = Color("#d8644e")
			continue
		if src:
			var net := pw.net_of_thing(t)
			var cap := pw.source_capacity(t)
			draw_rect(rr.grow(2), Color("#f2c84b"), false, 2.5)
			var txt := L.t("%d кВт · не подключён") % int(cap)
			var col := Color("#9aa3ab")
			if net:
				txt = L.t("%.1f / %d кВт") % [net.load, int(net.capacity)]
				col = Color("#d8644e") if net.tripped or net.load > net.capacity else Color("#f2c84b")
				if net.tripped:
					txt = L.t("ВЫБИТ АВТОМАТ")
			_text_px(top, txt, 13, col, true)
		else:
			# потребитель: рамка цвета состояния, мощность — маленькой цифрой внутри,
			# если помещается; полная подпись — при наведении мыши
			var ok := pw.powered(t)
			var kw := float(t.machine_def().get("power_kw", 0.0)) if t.kind() == "machine" else float(t.def().get("power_kw", 0.0))
			var col2 := Color("#8fcf78") if ok else Color("#d8644e")
			draw_rect(rr.grow(-1), col2, false, 2.0)
			var num := ("%.1f" % kw).trim_suffix(".0")
			var px := 11
			if _text_w(num, px) < rr.size.x - 4.0:
				_text_px(Vector2(rr.get_center().x, rr.end.y - 4.0), num, px, col2, true)
			# розетка: клетка, к которой подводят последний кусок кабеля
			var ic := t.inlet_cell()
			var conn := pw.connected(t)
			_socket((Vector2(ic) + Vector2(0.5, 0.5)) * T, Color("#8fcf78") if conn else Color("#f2c84b"), not conn)
			if not conn:
				# куда можно подвести: сама розетка и соседние клетки
				var a := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
				for d in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
					var tc: Vector2i = ic + d
					if sim.world.in_plot(tc) and not Defs.wall_solid(sim.world.get_wall(tc)):
						draw_rect(Rect2(Vector2(tc) * T, Vector2(T, T)).grow(-3), Color(0.95, 0.78, 0.3, a), false, 1.5)
			if hovered:
				hover_txt = L.t("%s · %s кВт") % [t.title(), num]
				if not pw.connected(t):
					hover_txt += L.t(" · нет кабеля")
				elif not ok:
					hover_txt += L.t(" · без тока")
				hover_pos = top
				hover_col = col2
	if hover_txt != "":
		_text_px(hover_pos, hover_txt, 13, hover_col, true, true)



## Значок розетки: кружок с двумя штырьками.
func _socket(c: Vector2, col: Color, pulse: bool) -> void:
	var r := 6.0 + (0.8 * sin(Time.get_ticks_msec() / 200.0) if pulse else 0.0)
	draw_circle(c, r + 1.5, Color(0.07, 0.08, 0.09, 0.85))
	draw_circle(c, r, col)
	draw_rect(Rect2(c + Vector2(-3.0, -2.5), Vector2(1.6, 5.0)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(c + Vector2(1.4, -2.5), Vector2(1.6, 5.0)), Color(0.1, 0.1, 0.1))


## Водопровод: трубы синим, насосы, приборы с водой и без, клетки подключения.
func _draw_water() -> void:
	var w := sim.world
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.04, 0.07, 0.12, 0.35))
	sim.water.update()
	for i in w.w * w.h:
		if w.pipe[i] != 1:
			continue
		var c := w.cell_of(i)
		var k := sim.water.net_of[i] if i < sim.water.net_of.size() else -1
		var col := Color("#4a8fd0") if k >= 0 and k < sim.water.net_src.size() and sim.water.net_src[k] else Color("#6d7a86")
		var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * T
		var linked := false
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if w.has_pipe(c + d):
				draw_line(ctr, ctr + Vector2(d) * T, col.darkened(0.35), 6.0)
				draw_line(ctr, ctr + Vector2(d) * T, col, 3.5)
				linked = true
		if not linked:
			draw_circle(ctr, 4.0, col)
	draw_plans("pipe", Color("#4a8fd0"))
	var hover := Vector2i(floori(get_global_mouse_position().x / T), floori(get_global_mouse_position().y / T))
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		if t.kind() == "water_source":
			draw_rect(rr.grow(2), Color("#4a8fd0"), false, 2.5)
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 4.0), L.t("насос"), 12, Color("#9cc8f0"), true)
			continue
		if t.def_id == "radiator":
			var onb := sim.eng.boiler_rads.has(t.id)
			draw_rect(rr.grow(-3), Color("#e0883a") if onb else Color("#8a949c"), false, 2.0)
			if Rect2i(t.cell, Vector2i.ONE).has_point(hover):
				_text_px(rr.get_center() + Vector2(0, -20.0), L.t("батарея · ") + (L.t("от своего котла") if onb else L.t("от городской теплосети")), 12, Color("#f0b080") if onb else Color("#c8d0d6"), true)
			continue
		if not t.needs_water():
			continue
		if t.kind() == "boiler":
			var bp := sim.eng.boiler_problem(t)
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 18.0), L.t("котёл · ") + (L.t("греет %d из %d батарей") % [sim.eng.boiler_load(t), int(t.def().get("boiler_cap", 16))] if bp == "" else bp), 12, Color("#f0b080") if bp == "" else Color("#e08a6a"), true)
		var ok := sim.water.has_water(t)
		var col2 := Color("#8fcf78") if ok else Color("#d8644e")
		draw_rect(rr.grow(-1), col2, false, 2.0)
		var ic := t.inlet_cell()
		var cp := (Vector2(ic) + Vector2(0.5, 0.5)) * T
		draw_circle(cp, 7.0, Color(0.07, 0.08, 0.09, 0.85))
		draw_circle(cp, 5.5, Color("#4a8fd0") if ok else Color("#9cc8f0"))
		if not ok:
			var a := 0.35 + 0.25 * sin(Time.get_ticks_msec() / 250.0)
			for d2 in [Vector2i.ZERO, Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var tc: Vector2i = ic + d2
				if w.in_plot(tc) and not Defs.wall_solid(w.get_wall(tc)):
					draw_rect(Rect2(Vector2(tc) * T, Vector2(T, T)).grow(-3), Color(0.4, 0.7, 1.0, a), false, 1.5)
		if Rect2i(t.cell, t.size()).has_point(hover):
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 4.0), "%s · %s" % [t.title(), L.t("вода есть") if ok else (L.t("в сети нет насоса") if sim.water.connected(t) else L.t("труба не подведена"))], 13, col2, true)
	if not sim.water.has_source():
		_text(Vector2(w.w * T * 0.5, 4 * T), L.t("Нет насоса: поставьте его (Сети → Водопровод) и тяните от него трубы"), 13.0, Color("#9cc8f0"))


## Цвет температуры: синий — холодно, зелёный — комфорт, оранжевый — жарко.
static func temp_color(t: float) -> Color:
	if t < 0.0:
		return Color("#4a7fd0")
	if t < Defs.sea("freezing_below"):
		return Color("#6fa0e0")
	if t < Defs.sea("cold_below"):
		return Color("#9cc8e8")
	if t <= Defs.sea("hot_above"):
		return Color("#7fcf7a")
	return Color("#e0883a")


func _draw_temp() -> void:
	var w := sim.world
	var t_out := sim.season.outside_temp()
	# улица — лёгкий тон
	var oc := temp_color(t_out)
	draw_rect(Rect2(Vector2(w.plot.position) * T, Vector2(w.plot.size) * T), Color(oc.r, oc.g, oc.b, 0.08))
	for r in sim.rooms.list:
		var tc := float(sim.season.room_temp.get(r.id, t_out))
		var col := temp_color(tc)
		for c in r.cells:
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.3))
		_text(r.center * T + Vector2(0, 6), "%+d °C" % int(round(tc)), 15, col.lightened(0.35))
	for t: Thing in sim.things.values():
		if t.built and t.def_id == "radiator":
			var rr := Rect2(Vector2(t.cell) * T, Vector2(T, T)).grow(-3)
			draw_rect(rr, Color("#e0883a"), false, 2.0)
			draw_circle(rr.get_center(), 3.0, Color("#e0883a"))
	_text(Vector2(w.plot.position.x * T + 8, w.plot.position.y * T + 20), L.t("Улица: %+d °C") % int(round(t_out)), 15, oc.lightened(0.3), false)


# ---------------------------------------------------------------- вентиляция

## Цвет воздуха в помещении: зелёный — чисто, жёлтый — душно, бурый — дым.
static func fumes_color(f: float) -> Color:
	if f < 15.0:
		return Color("#7fcf7a")
	if f < Eng.STUFFY:
		return Color("#c9cf6a")
	if f < Eng.SMOKY:
		return Color("#e0a83a")
	return Color("#c8643a")


## Чертежи сети (1.13): пунктир к соседним клеткам и мигающая точка — их ещё проложат рабочие.
## Тот, кто тянет сеть сейчас, — оранжевым квадратом.
func draw_plans(layer: String, col: Color) -> void:
	var w := sim.world
	var arr := w.net_layer(layer)
	if arr.size() != w.w * w.h:
		return
	var a := 0.55 + 0.25 * sin(Time.get_ticks_msec() / 300.0)
	for i in w.w * w.h:
		if arr[i] != 2:
			continue
		var c := w.cell_of(i)
		var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * T
		for d in [Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(0, -1)]:
			var nv := w.net_at(layer, c + d)
			if nv == 0 or (nv == 2 and (d.x < 0 or d.y < 0)):
				continue
			var e := ctr + Vector2(d) * T * (1.0 if nv == 2 else 0.5)
			var n := 4
			for k in n:
				var t0 := float(k) / float(n)
				draw_line(ctr.lerp(e, t0), ctr.lerp(e, t0 + 0.55 / float(n)), Color(col, 0.9), 2.4)
		draw_circle(ctr, 3.2, Color(col, a))
		if sim.net_res.has("%s:%d" % [layer, i]):
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)).grow(-3), Color(1.0, 0.6, 0.2, 0.9), false, 2.0)


func _line_net(arr: PackedByteArray, col: Color, wide: float, has: Callable) -> void:
	var w := sim.world
	if arr.size() != w.w * w.h:
		return
	for i in w.w * w.h:
		if arr[i] != 1:
			continue
		var c := w.cell_of(i)
		var ctr := (Vector2(c) + Vector2(0.5, 0.5)) * T
		var linked := false
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			if has.call(c + d):
				draw_line(ctr, ctr + Vector2(d) * T, col.darkened(0.45), wide + 3.0)
				draw_line(ctr, ctr + Vector2(d) * T, col, wide)
				linked = true
		if not linked:
			draw_rect(Rect2(ctr - Vector2(wide, wide) * 0.6, Vector2(wide, wide) * 1.2), col)


func _draw_vent() -> void:
	var w := sim.world
	var eng := sim.eng
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.05, 0.06, 0.08, 0.35))
	for r in sim.rooms.list:
		var f0 := eng.fumes_of(r)
		var col0 := fumes_color(f0)
		var a := 0.16 + clampf(f0 / 100.0, 0.0, 1.0) * 0.3
		for c in r.cells:
			draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), Color(col0.r, col0.g, col0.b, a))
	_line_net(w.duct, Color("#9aa6ae"), 7.0, func(c: Vector2i) -> bool: return w.has_duct(c))
	draw_plans("duct", Color("#9aa6ae"))
	for r in sim.rooms.list:
		var f := eng.fumes_of(r)
		var col := fumes_color(f)
		var vk := eng.vent_k(r)
		var need := eng.needs_vent(r)
		if f >= 3.0 or vk > 0.0 or need:
			var t1 := L.t("воздух: %s") % (L.t("чисто") if f < 15.0 else (L.t("душно %d%%") % int(f) if f < Eng.SMOKY else L.t("дым %d%%") % int(f)))
			_text(r.center * T + Vector2(0, -2), t1, 14, col.lightened(0.3))
			var t2 := L.t("вентиляция ×%.1f") % vk if vk > 0.0 else (L.t("нужна вентиляция") if need else L.t("без вентиляции"))
			_text(r.center * T + Vector2(0, 16), t2, 12, Color("#9cc8e8") if vk > 0.0 else (Color("#e08a6a") if need else Color("#a8b0b6")))
	var hover := Vector2i(floori(get_global_mouse_position().x / T), floori(get_global_mouse_position().y / T))
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var k := t.kind()
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		if k == "vent_fan":
			var ok := eng.fan_ok(t)
			var col2 := Color("#8fcf78") if ok else Color("#d8644e")
			draw_rect(rr.grow(2), col2, false, 2.5)
			var why := L.t("работает") if ok else (L.t("нет тока") if not sim.power.powered(t) else L.t("выключен"))
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 4.0), L.t("вентилятор · ") + why, 12, col2, true)
		elif k == "vent_hood":
			var ok2 := eng.hood_ok(t)
			var col3 := Color("#8fcf78") if ok2 else Color("#e0a83a")
			draw_circle(rr.get_center(), 9.0, Color(0.07, 0.08, 0.09, 0.8))
			draw_arc(rr.get_center(), 9.0, 0.0, TAU, 20, col3, 2.2)
			if Rect2i(t.cell, Vector2i.ONE).has_point(hover) or not ok2:
				_text_px(rr.get_center() + Vector2(0, -14.0), L.t("зонт · ") + (L.t("тянет") if ok2 else L.t("не подключён к вентилятору")), 12, col3, true)
		elif k == "machine" and FUMES_SHOW.has(t.process()):
			var hd := bool(eng.hooded.get(t.id, false))
			draw_rect(rr.grow(-1), Color("#8fcf78") if hd else Color("#e0a83a"), false, 1.5)
	_legend([[L.t("Вентиляция: зелёный — чистый воздух, жёлтый — душно, бурый — дым"), Color("#e7e4d8")],
		[L.t("Вытяжной вентилятор (под током) тянет воздух из помещений по своему воздуховоду"), Color("#9cc8e8")],
		[L.t("Зонт над сварочным постом, камерой или печью — три четверти дыма уходит сразу"), Color("#8fcf78")]])


const FUMES_SHOW := ["welding", "paint", "heat", "casting"]


## Бригады и охрана: участки бригад цветом, люди по бригадам, камеры и проходная.
func _draw_crew() -> void:
	var w := sim.world
	var cr := sim.crew
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.05, 0.06, 0.08, 0.35))
	for r in sim.rooms.list:
		var bid := cr.room_owner(r)
		var cam := cr.cam_in_room(r)
		if bid >= 0:
			var col := cr.color(bid)
			for c in r.cells:
				draw_rect(Rect2(Vector2(c) * T, Vector2(T, T)), Color(col.r, col.g, col.b, 0.28))
			var b := cr.brigade(bid)
			var ld := cr.lead_of(bid)
			_text(r.center * T + Vector2(0, -2), str(b["name"]), 14, col.lightened(0.35))
			_text(r.center * T + Vector2(0, 16), L.t("%d чел.%s") % [cr.members(bid).size(), (L.t(" · бригадир ") + ld.call_name()) if ld else L.t(" · нет бригадира")], 12, Color("#d8d4c8"))
		if cam:
			var p := Vector2(r.rect.position) * T + Vector2(10, 10)
			draw_rect(Rect2(Vector2(r.rect.position) * T, Vector2(r.rect.size) * T).grow(-3), Color("#8fb3c8"), false, 1.5)
			_text_px(p + Vector2(40, 12), L.t("под камерой"), 11, Color("#8fb3c8"), true)
	for wk in sim.workers:
		if not wk.present or wk.hidden:
			continue
		var pc := wk.pos * T + Vector2(0, -4)
		if wk.brigade >= 0:
			var col2 := cr.color(wk.brigade)
			draw_circle(pc, 7.0 if cr.is_lead(wk) else 5.0, col2)
			draw_arc(pc, 7.0 if cr.is_lead(wk) else 5.0, 0.0, TAU, 16, Color(0.08, 0.09, 0.1, 0.9), 1.5)
			if cr.is_lead(wk):
				draw_arc(pc, 10.0, 0.0, TAU, 20, Color("#f2e6b0"), 1.5)
		elif wk.prof == "guard":
			draw_circle(pc, 6.0, Color("#30363a"))
			draw_arc(pc, 6.0, 0.0, TAU, 16, Color("#e0aa48"), 2.0)
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		if t.kind() == "camera":
			var ok := cr.cam_ok(t)
			var cc := Color("#8fcf78") if ok else Color("#d8644e")
			draw_circle(rr.get_center(), 8.0, Color(0.07, 0.08, 0.09, 0.85))
			draw_arc(rr.get_center(), 8.0, 0.0, TAU, 18, cc, 2.0)
			draw_circle(rr.get_center(), 3.0, cc)
			if not ok:
				_text_px(rr.get_center() + Vector2(0, -14.0), L.t("камера · нет тока"), 12, cc, true)
		elif t.def_id == "checkpoint":
			var on := cr.on_watch() or cr.search_on()
			var c3 := Color("#8fcf78") if on else Color("#e0a83a")
			draw_rect(rr.grow(3), c3, false, 2.5)
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 6.0), L.t("проходная · ") + (L.t("охрана на посту") if on else L.t("без охраны")), 12, c3, true)
	_legend([[L.t("Бригады: участки и люди цветом бригады, бригадир — с ободком"), Color("#e7e4d8")],
		[L.t("Охрана: камеры (зелёные — пишут), проходная, охранники — жёлтый ободок"), Color("#8fb3c8")],
		[L.t("Шанс поймать несуна на выходе: %d%%") % int(round(cr.detect_k() * 100.0)), Color("#e0aa48")]])


# ---------------------------------------------------------------- сжатый воздух

func _draw_air() -> void:
	var w := sim.world
	var eng := sim.eng
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.05, 0.06, 0.08, 0.4))
	_line_net(w.air, Color("#e2843a"), 3.5, func(c: Vector2i) -> bool: return w.has_air(c))
	draw_plans("air", Color("#e2843a"))
	var hover := Vector2i(floori(get_global_mouse_position().x / T), floori(get_global_mouse_position().y / T))
	var any_comp := false
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		if t.kind() == "compressor":
			any_comp = true
			var net := eng.anet_of_thing(t)
			var ok := sim.power.powered(t) and t.enabled
			var col := Color("#e2843a") if ok else Color("#d8644e")
			draw_rect(rr.grow(2), col, false, 2.5)
			var txt := L.t("компрессор")
			if not ok:
				txt += L.t(" · нет тока") if not sim.power.powered(t) else L.t(" · выключен")
			elif net:
				txt += " · %d/%d" % [int(net.demand), int(net.cap)]
			else:
				txt += L.t(" · магистраль не подведена")
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 4.0), txt, 12, col.lightened(0.2), true)
			continue
		var mode2 := eng.air_mode(t)
		if mode2 == "":
			continue
		var p := eng.pressure(t)
		var col2 := Color("#8fcf78") if p >= 0.99 else (Color("#e0c23a") if p > 0.0 else Color("#d8644e"))
		draw_rect(rr.grow(-1), col2, false, 2.0)
		var ic := t.inlet_cell()
		var cp := (Vector2(ic) + Vector2(0.5, 0.5)) * T
		draw_circle(cp, 7.0, Color(0.07, 0.08, 0.09, 0.85))
		draw_circle(cp, 5.5, Color("#e2843a") if p > 0.0 else Color("#f0c8a0"))
		if Rect2i(t.cell, t.size()).has_point(hover) or p <= 0.0:
			var st := L.t("воздух есть") if p >= 0.99 else (L.t("давления не хватает") if p > 0.0 else (L.t("компрессор не работает") if eng.anet_of_thing(t) else L.t("магистраль не подведена")))
			if mode2 == "need" and p <= 0.0:
				st += L.t(" — красят кистью, в 1,5 раза дольше")
			_text_px(rr.get_center() + Vector2(0, -rr.size.y * 0.5 - 4.0), "%s · %s" % [t.title(), st], 12, col2, true)
	if not any_comp:
		_text(Vector2(w.w * T * 0.5, 4 * T), L.t("Нет компрессора: поставьте его (Сети → Сжатый воздух) и тяните пневмомагистраль"), 13.0, Color("#f0c8a0"))


# ================================================================ 1.15: все коммуникации на одном слое

## Свои «полосы» в клетке у каждой сети, чтобы в одной клетке были видны все: кабель, водопровод,
## пневмомагистраль, воздуховод. Свой вид у каждой: кабель — тонкий жёлтый, вода — синяя труба с бликом,
## сжатый воздух — оранжевый пунктир, воздуховод — широкий серый короб с рёбрами.
const LANE := {"cable": -9.0, "pipe": -3.0, "air": 3.0, "duct": 9.0}


func _lane_pt(c: Vector2i, o: float) -> Vector2:
	return (Vector2(c) + Vector2(0.5, 0.5)) * T + Vector2(o, o)


func _net_lines(arr: PackedByteArray, o: float, style: String, col_of: Callable) -> void:
	var w := sim.world
	if arr.size() != w.w * w.h:
		return
	for i in w.w * w.h:
		if arr[i] != 1:
			continue
		var c := w.cell_of(i)
		var col: Color = col_of.call(i)
		var a := _lane_pt(c, o)
		var linked := false
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var nc: Vector2i = c + d
			if not w.inb(nc) or arr[w.idx(nc)] != 1:
				continue
			linked = true
			var b := _lane_pt(nc, o)
			match style:
				"cable":
					draw_line(a, b, Color(0.06, 0.06, 0.06, 0.85), 4.6)
					draw_line(a, b, col, 2.6)
				"pipe":
					draw_line(a, b, col.darkened(0.45), 7.0)
					draw_line(a, b, col, 4.8)
					draw_line(a + Vector2(-0.8, -0.8), b + Vector2(-0.8, -0.8), col.lightened(0.45), 1.2)
				"air":
					draw_line(a, b, Color(0.06, 0.06, 0.06, 0.8), 5.0)
					draw_line(a, b, col, 3.0)
					for k in 3:
						var t0 := (float(k) + 0.25) / 3.0
						draw_line(a.lerp(b, t0), a.lerp(b, t0 + 0.14), Color("#fff3e0"), 1.6)
				"duct":
					draw_line(a, b, col.darkened(0.5), 10.0)
					draw_line(a, b, col, 7.6)
					var mid := a.lerp(b, 0.5)
					var nrm := Vector2(-(b - a).y, (b - a).x).normalized() * 3.6
					draw_line(mid - nrm, mid + nrm, col.darkened(0.35), 1.4)
		if not linked:
			draw_circle(a, 3.5, col)
		elif style == "pipe" or style == "duct":
			draw_circle(a, (3.4 if style == "pipe" else 4.8), col)


## Значок сети: молния — ток, капля — вода, кружок со стрелкой — воздух.
func _net_badge(c: Vector2, kind: String, ok: bool) -> void:
	var bg := Color(0.07, 0.08, 0.09, 0.9)
	var col := {"power": Color("#f2c84b"), "water": Color("#4a9fe0"), "air": Color("#e2843a")}[kind] as Color
	if not ok:
		col = Color("#d8644e")
	draw_circle(c, 6.4, bg)
	draw_circle(c, 5.2, col)
	var k := 0.9
	match kind:
		"power":
			draw_colored_polygon(PackedVector2Array([c + Vector2(0.8, -4.0) * k, c + Vector2(-2.4, 0.6) * k, c + Vector2(-0.2, 0.6) * k,
				c + Vector2(-0.9, 4.0) * k, c + Vector2(2.4, -0.8) * k, c + Vector2(0.2, -0.8) * k]), bg)
		"water":
			var pr := PackedVector2Array([c + Vector2(0, -3.8) * k])
			for i2 in 13:
				var a2 := -PI * 0.15 + (PI * 1.3) * i2 / 12.0
				pr.append(c + Vector2(cos(a2) * 2.5, 0.9 + sin(a2) * 2.5) * k)
			draw_colored_polygon(pr, bg)
		"air":
			draw_arc(c, 2.8, 0.0, TAU, 14, bg, 1.4)
			draw_line(c, c + Vector2(2.2, -2.2), bg, 1.4)
	if not ok:
		draw_line(c + Vector2(-4.4, 4.4), c + Vector2(4.4, -4.4), Color(0.07, 0.08, 0.09), 1.6)


func _draw_nets() -> void:
	var w := sim.world
	var pw := sim.power
	var eng := sim.eng
	draw_rect(Rect2(Vector2.ZERO, Vector2(w.w, w.h) * T), Color(0.05, 0.06, 0.09, 0.42))
	sim.water.update()
	_net_lines(w.duct, LANE["duct"], "duct", func(_i: int) -> Color: return Color("#a3adb4"))
	_net_lines(w.pipe, LANE["pipe"], "pipe", func(i: int) -> Color:
		var k := sim.water.net_of[i] if i < sim.water.net_of.size() else -1
		return Color("#4a9fe0") if k >= 0 and k < sim.water.net_src.size() and sim.water.net_src[k] else Color("#7d8a96"))
	_net_lines(w.air, LANE["air"], "air", func(_i: int) -> Color: return Color("#e2843a"))
	_net_lines(w.cable, LANE["cable"], "cable", func(i: int) -> Color:
		var ni := pw.net_of[i] if i < pw.net_of.size() else -1
		if ni >= 0 and ni < pw.nets.size():
			var net: Power.Net = pw.nets[ni]
			if net.tripped:
				return Color("#d8644e")
			if net.capacity > 0.0:
				return Color("#f2c84b") if net.load <= net.capacity else Color("#ff8a3a")
		return Color("#9aa0a6"))
	draw_plans("cable", Color("#f2c84b"))
	draw_plans("pipe", Color("#4a9fe0"))
	draw_plans("duct", Color("#a3adb4"))
	draw_plans("air", Color("#e2843a"))
	# помещения: где нет света и где дымно
	for r in sim.rooms.list:
		var ctr2 := r.center * T
		var line := ""
		if not r.powered and r.type != "":
			line = L.t("свет не подключён")
		var f := eng.fumes_of(r)
		if f >= 15.0:
			line += (" · " if line != "" else "") + (L.t("душно %d%%") % int(f) if f < Eng.SMOKY else L.t("дым %d%%") % int(f))
		if line != "":
			_text_px(ctr2, line, 12, Color("#c8ccd0"))
	var hover := Vector2i(floori(get_global_mouse_position().x / T), floori(get_global_mouse_position().y / T))
	var hover_txt := ""
	var hover_pos := Vector2.ZERO
	var hover_col := Color.WHITE
	for t: Thing in sim.things.values():
		if not t.built:
			continue
		var rr := Rect2(Vector2(t.cell) * T, Vector2(t.size()) * T)
		var top := rr.position + Vector2(rr.size.x * 0.5, -4)
		var hovered := Rect2i(t.cell, t.size()).has_point(hover)
		var k := t.kind()
		# источники: трансформаторы и подстанция, насосы, компрессор, вентилятор
		if str(t.def().get("power_source", "")) != "":
			var net := pw.net_of_thing(t)
			var txt := L.t("%d кВт · кабель не проложен") % int(pw.source_capacity(t))
			var col := Color("#9aa3ab")
			if net:
				txt = L.t("ВЫБИТ АВТОМАТ") if net.tripped else L.t("%.1f / %d кВт") % [net.load, int(net.capacity)]
				col = Color("#d8644e") if net.tripped or net.load > net.capacity else Color("#f2c84b")
			draw_rect(rr.grow(2), Color("#f2c84b"), false, 2.5)
			_text_px(top, txt, 13, col, true)
			continue
		if k == "water_source" or k == "pump":
			draw_rect(rr.grow(2), Color("#4a9fe0"), false, 2.5)
			_text_px(top, L.t("насос") if k == "water_source" else L.t("насосная"), 12, Color("#9cc8f0"), true)
			continue
		if k == "compressor":
			var an := eng.anet_of_thing(t)
			var okc := pw.powered(t) and t.enabled
			draw_rect(rr.grow(2), Color("#e2843a") if okc else Color("#d8644e"), false, 2.5)
			_text_px(top, L.t("компрессор") + ((" · %d/%d" % [int(an.demand), int(an.cap)]) if an and okc else (L.t(" · нет тока") if not okc else L.t(" · не подключён"))), 12, Color("#f0b080"), true)
			continue
		if k == "vent_fan":
			var okf := eng.fan_ok(t)
			draw_rect(rr.grow(2), Color("#a3adb4") if okf else Color("#d8644e"), false, 2.5)
			continue
		if t.kind() == "light":
			if not pw.light_link.has(t.id):
				draw_circle((Vector2(t.cell) + Vector2(0.5, 0.5)) * T, 4.0, Color("#d8644e"))
			continue
		# потребители: значки нужных сетей в углу, красные — если сети нет
		var needs: Array = []
		var draws := t.kind() == "machine" or float(t.def().get("power_kw", 0.0)) > 0.0
		if draws:
			needs.append(["power", pw.powered(t)])
		if t.needs_water():
			needs.append(["water", sim.water.has_water(t)])
		var am := eng.air_mode(t)
		if am != "":
			needs.append(["air", eng.pressure(t) > 0.0])
		if needs.is_empty():
			continue
		var all_ok := true
		for n2: Array in needs:
			if not bool(n2[1]):
				all_ok = false
		draw_rect(rr.grow(-1), Color("#8fcf78") if all_ok else Color("#d8644e"), false, 2.0)
		for j in needs.size():
			_net_badge(rr.position + Vector2(8.0 + j * 13.0, 8.0), str(needs[j][0]), bool(needs[j][1]))
		if not all_ok:
			var ic := t.inlet_cell()
			_socket((Vector2(ic) + Vector2(0.5, 0.5)) * T, Color("#f2c84b"), true)
		if hovered:
			var parts: Array[String] = []
			for n3: Array in needs:
				var nm := {"power": L.t("ток"), "water": L.t("вода"), "air": L.t("воздух")}[str(n3[0])] as String
				parts.append(nm + (L.t(" есть") if bool(n3[1]) else L.t(" — нет")))
			hover_txt = "%s · %s" % [t.title(), ", ".join(parts)]
			hover_pos = top
			hover_col = Color("#8fcf78") if all_ok else Color("#d8644e")
	if hover_txt != "":
		_text_px(hover_pos, hover_txt, 13, hover_col, true, true)
	_legend([[L.t("Жёлтый — кабель (оранжевый — перегруз, красный — выбит автомат)"), Color("#f2c84b")],
		[L.t("Синий — водопровод (серый — нет воды в трубе)"), Color("#7fb8e8")],
		[L.t("Оранжевый пунктир — сжатый воздух"), Color("#f0b080")],
		[L.t("Широкий серый — воздуховод вентиляции"), Color("#c4ccd2")],
		[L.t("Значки в углу объекта — что ему нужно; красный — этого нет"), Color("#e7e4d8")]])
