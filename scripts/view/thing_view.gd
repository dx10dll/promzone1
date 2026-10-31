class_name ThingView
extends Node2D
## Отображение объекта: спрайт + живой слой поверх (содержимое складов, анимация станка, прогресс).

const T := World.T
const MAT_COL := {"bar45": Color("#9aa1a5"), "hex27": Color("#8e9a92"), "bar40x": Color("#7d848a"), "forging": Color("#6e6460"), "profile40": Color("#8a9196"), "plate8": Color("#a9b2b8")}

var sim: Sim
var thing: Thing
var sprite := Sprite2D.new()
var over := Node2D.new()
var meta: Dictionary = {}
var tex_key := ""
var flip := false
var _fshift := 0.0   ## сдвиг отражённого спрайта: тело объекта остаётся на своих клетках, а не уезжает на поле тени
var _t := 0.0
var _ov_t := 0.0                ## 1.40: до следующей перерисовки эффектов и подписей
var _check := 0.0
## 1.30: проходная — внутренний слой будки (позади сидящего охранника) и планки турникетов
var inner: Sprite2D = null
var _spin: Array[float] = [0.0, 0.0]
var _spin_goal: Array[float] = [0.0, 0.0]
var _occ: Array[bool] = [false, false]


func setup(s: Sim, t: Thing) -> void:
	sim = s
	thing = t
	sprite.centered = false
	sprite.scale = Vector2(0.5, 0.5)
	add_child(sprite)
	add_child(over)
	over.draw.connect(_draw_over)
	if t.is_ceiling():
		z_index = 6   # светильники под потолком — поверх людей и станков
	if t.def_id == "checkpoint":
		# будка: «нутро» (задняя стенка, стул), охранник, стены с окном — сортируются вместе с людьми
		y_sort_enabled = true
		inner = Sprite2D.new()
		inner.centered = false
		inner.scale = Vector2(0.5, 0.5)
		add_child(inner)
	_refresh_texture(true)


func _refresh_texture(force: bool = false) -> void:
	var sk := Thing.sprite_for(thing.def_id, thing.rot)
	var key := str(sk[0])
	var fl := bool(sk[1])
	if thing.def_id == "chair":
		var r := _chair_key()
		key = r[0]
		fl = r[1]
	if key == tex_key and fl == flip and not force:
		return
	tex_key = key
	flip = fl
	meta = Defs.sprites.get(key, {})
	sprite.texture = Tex.obj(key)
	sprite.flip_h = flip
	_fshift = 0.0
	if flip:
		_fshift = maxf(0.0, float(meta.get("w", 64)) - float(thing.size().x * 64))
	sprite.offset = Vector2(-float(meta.get("ox", 0)) - _fshift, -float(meta.get("oy", 64)))
	if inner:
		inner.texture = Tex.obj(key + "_in")
		inner.flip_h = flip
	_place()


func _place() -> void:
	var s := thing.size()
	var bottom := Vector2(thing.cell.x * T, (thing.cell.y + s.y) * T)
	var sort_y := bottom.y
	# скамейка и стул спинкой назад рисуются ПОЗАДИ сидящего человека
	if thing.def_id == "bench" or tex_key == "chair_down":
		sort_y = thing.cell.y * T + 6.0
	elif tex_key == "chair_side":
		sort_y = thing.cell.y * T + 10.0
	position = Vector2(bottom.x, sort_y)
	sprite.position = Vector2(0, bottom.y - sort_y)
	_spr_base = sprite.position
	over.position = sprite.position
	if inner:
		# 1.30: проходная сортируется по низу будки (а не всего футпринта): люди в проходах сбоку — перед
		# тумбами турникетов. «Нутро» будки — по верху клетки охранника: он сидит перед ним, стены с окном — впереди.
		var base := sprite.position
		var off0 := sprite.offset
		var st := thing.seat_cell()
		sprite.position = Vector2(0, float(st.y + 1) * T - sort_y)
		sprite.offset = off0 + (base - sprite.position) * 2.0
		_spr_base = sprite.position
		inner.position = Vector2(0, float(st.y) * T + 4.0 - sort_y)
		inner.offset = off0 + (base - inner.position) * 2.0


func _chair_key() -> Array:
	var dirs := [[Vector2i(0, 1), "chair_down", false], [Vector2i(0, -1), "chair_up", false],
		[Vector2i(1, 0), "chair_side", false], [Vector2i(-1, 0), "chair_side", true]]
	for d in dirs:
		var th := sim.thing_at(thing.cell + d[0])
		if th and th.kind() == "table":
			return [d[1], d[2]]
	return ["chair_down", false]


var _spr_base := Vector2.ZERO


func _process(delta: float) -> void:
	_t += delta
	# 1.23: работающий станок чуть дрожит
	if thing.built and thing.working and thing.kind() == "machine":
		sprite.position = _spr_base + Vector2(sin(_t * 53.0) * 0.22, cos(_t * 41.0) * 0.12)
	elif sprite.position != _spr_base:
		sprite.position = _spr_base
	_check -= delta
	if _check <= 0.0:
		_check = 0.5
		_refresh_texture()
	if thing.built and (thing.def_id == "cart" or thing.def_id == "forklift"):
		visible = thing.user < 0   # уехала с рабочим — рисуется у него
	# призрак ещё не собранного объекта — только сам спрайт, подписи остаются чёткими
	if not thing.built:
		sprite.modulate = Color(0.55, 0.78, 1.0, 0.45)   # призрак: тут встанет объект
	elif thing.demolish:
		sprite.modulate = Color(1.0, 0.6, 0.55, 0.95)
	else:
		sprite.modulate = Color(1, 1, 1, 0.94) if thing.is_ceiling() else Color.WHITE
	if inner:
		inner.modulate = sprite.modulate
		_turnstiles(delta)
	# 1.29: эффекты и подписи перерисовываем только у объектов на экране — за краем их всё равно не видно
	# 1.40: и не чаще 30 раз в секунду (на 100+ к/с лишнюю перерисовку анимаций глаз не видит)
	_ov_t -= delta
	if _ov_t <= 0.0 and (WorkerView.view.size.x <= 0.0 or WorkerView.view.has_point(position)):
		_ov_t = 0.033
		over.queue_redraw()


## 1.30: турникет: человек вошёл в проход — планки проворачиваются на треть оборота, щелчок.
func _turnstiles(delta: float) -> void:
	if not thing.built:
		return
	var wc := thing.walk_cells()
	for i in mini(2, wc.size()):
		var here := false
		for w in sim.workers:
			if w.present and not w.hidden and w.cell() == wc[i]:
				here = true
				break
		if here and not _occ[i]:
			_spin_goal[i] += TAU / 3.0
			Snd.play_at("turnstile", (Vector2(wc[i]) + Vector2(0.5, 0.5)) * T, -4.0, 0.12)
		_occ[i] = here
		_spin[i] = move_toward(_spin[i], _spin_goal[i], delta * 5.0)


func _draw_turnstile_arms() -> void:
	for i in 2:
		var hb := _anchor("hub%d" % (i + 1))
		if hb.size() < 4:
			continue
		var c := tp(hb[0], hb[1])
		var rx := float(hb[2]) * 0.5 * (-1.0 if flip else 1.0)
		var ry := float(hb[3]) * 0.5
		for k in 3:
			var a := _spin[i] + float(k) * TAU / 3.0
			var e := c + Vector2(cos(a) * rx, sin(a) * ry)
			over.draw_line(c, e, Color("#23262a"), 3.4, true)
			over.draw_line(c, e, Color("#cfd6da"), 2.0, true)
			over.draw_circle(e, 1.5, Color("#23262a"))
		over.draw_circle(c, 2.2, Color("#5a6064"))
		over.draw_circle(c, 1.1, Color("#9aa3a8"))


## Пиксель текстуры -> локальные координаты слоя.
func tp(px: float, py: float) -> Vector2:
	var x := px
	if flip:
		x = float(meta.get("w", 64)) - px - _fshift   # отражённый спрайт — отражаем и точки привязки
	return Vector2((x - float(meta.get("ox", 0))) * 0.5, (py - float(meta.get("oy", 64))) * 0.5)


func _anchor(name: String) -> Array:
	var a: Dictionary = meta.get("anchors", {})
	return a.get(name, [])


func _draw_item(tex: Texture2D, center: Vector2, sz: float = 14.0) -> void:
	if tex:
		over.draw_texture_rect(tex, Rect2(center - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false)


## 1.19: светильник под потолком — не прибор на карте, а неяркая жёлтая точка света.
func _is_dot_lamp() -> bool:
	return thing.kind() == "light" and thing.is_ceiling()


func _draw_lamp_dot() -> void:
	var c := Vector2(T * 0.5, -T * 0.5)
	var on := bool(sim.power.lamp_on.get(thing.id, false))
	var big := 1.4 if thing.def_id == "lamp_drl" else (1.15 if thing.def_id == "lamp_tube" else 1.0)
	var col := Color("#ffd86a")
	if not thing.built:
		col = Color(0.55, 0.78, 1.0)
	elif thing.demolish:
		col = Color(1.0, 0.5, 0.45)
	var g := Tex.fx("glow")
	if on and g:
		var gs := 30.0 * big
		over.draw_texture_rect(g, Rect2(c - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false, Color(col.r, col.g, col.b, 0.55))
	var a := 0.75 if on else 0.35
	over.draw_circle(c, 3.6 * big, Color(col.r, col.g, col.b, a * 0.35), true, -1.0, true)
	over.draw_circle(c, 2.0 * big, Color(col.r, col.g, col.b, a), true, -1.0, true)
	if on:
		over.draw_circle(c, 0.9 * big, Color(1, 0.98, 0.88, 0.9), true, -1.0, true)


func _draw_over() -> void:
	if _is_dot_lamp():
		sprite.visible = false
		_draw_lamp_dot()
		return
	if not thing.built:
		# ящики, которые уже принесли к месту установки
		if thing.crates_need > 0 and thing.crates_in < thing.crates_need:
			var ct := Tex.item("equip_crate")
			var w := float(meta.get("w", 64)) * 0.5
			for k in thing.crates_in:
				over.draw_texture_rect(ct, Rect2(Vector2(4.0 + k * 13.0, -26.0 - (k % 2) * 4.0), Vector2(20, 20)), false, Color(1, 1, 1, 1.4))
			# вместо надписи — маленький значок: машина едет или сколько ящиков уже принесли
			var top := -float(meta.get("oy", 64)) * 0.5 - 4.0
			var wait := thing.order_eta >= 0.0
			var txt := "" if wait else "%d/%d" % [thing.crates_in, thing.crates_need]
			var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
			var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x if txt != "" else 0.0
			var bw := 14.0 + (tw + 3.0 if txt != "" else 0.0)
			var bx := w * 0.5 - bw * 0.5
			var sb := StyleBoxFlat.new()
			sb.bg_color = Color(0.07, 0.08, 0.09, 0.62)
			sb.set_corner_radius_all(6)
			over.draw_style_box(sb, Rect2(Vector2(bx, top - 10.0), Vector2(bw, 12.0)))
			var ic := Tex.ui_world("supply") if wait else Tex.item("equip_crate")
			if ic:
				over.draw_texture_rect(ic, Rect2(Vector2(bx + 2.0, top - 9.0), Vector2(10, 10)), false, Tex.tint(ic, Color(0.85, 0.9, 1.0, 0.9)))
			if txt != "":
				over.draw_string(f, Vector2(bx + 13.0, top - 1.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 8, Color(0.88, 0.9, 0.95, 0.9))
		if thing.progress > 0.0:
			_bar(thing.progress, Color("#6fbf86"))
		return
	match thing.kind():
		"checkpoint":
			_draw_turnstile_arms()
		"machine":
			_draw_machine()
		"storage":
			_draw_storage()
		"qc":
			_draw_qc()
		"toilet":
			var b := _anchor("busy")
			if not b.is_empty():
				var busy := not thing.spot_users.is_empty()
				over.draw_circle(tp(b[0], b[1]), 2.6, Color("#d9493a") if busy else Color("#6fbf86"))
		"chip_bin":
			_draw_chip_bin()
		"vent_fan":
			_draw_fan()
		"compressor":
			_draw_compressor()
		"boiler":
			_draw_boiler()
		"saw":
			_draw_saw()
		"camera":
			var led := _anchor("led")
			if not led.is_empty() and sim.crew.cam_ok(thing) and fmod(_t, 2.0) < 1.0:
				over.draw_circle(tp(led[0], led[1]), 1.6, Color("#ff4a3a"))
		"decor":
			if thing.def_id == "company_board":
				var pl := _anchor("plate")
				if not pl.is_empty():
					var r0 := Rect2(tp(pl[0], pl[1]), Vector2(pl[2], pl[3]) * 0.5)
					Emblem.draw_sign_plate(over, r0, Company.emblem_of(sim), Company.name_of(sim), L.t("ООО") if sim.progress.ooo else L.t("МАСТЕРСКАЯ"), Color("#f2efe6"), true)
			if thing.def_id == "days_board":
				var dg := _anchor("digits")
				if not dg.is_empty():
					var f: Font = UITheme.f_semi if UITheme.f_semi else ThemeDB.fallback_font
					var txt := str(mini(sim.crew.safe_days(), 999))
					var fs := 12
					var tw := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
					var c := tp(dg[0], dg[1])
					over.draw_string(f, c + Vector2(-tw * 0.5, fs * 0.38), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color("#ffcf4a"))
			_draw_decor_anim()
		"appliance":
			if thing.def_id == "aquarium" and sim.power.powered(thing):
				var bb := _anchor("bubbles")
				if not bb.is_empty():
					for k2 in 3:
						var ph := fmod(_t * 0.6 + k2 * 0.33, 1.0)
						over.draw_circle(tp(bb[0], bb[1] - ph * 40.0), 1.0 + ph, Color(1, 1, 1, 0.7 * (1.0 - ph)))
			elif thing.def_id == "tv" and sim.power.powered(thing):
				var sc := _anchor("screen")
				if not sc.is_empty():
					var flick := 0.08 + 0.06 * sin(_t * 9.0) + 0.05 * sin(_t * 23.0)
					over.draw_rect(Rect2(tp(sc[0] - 20, sc[1] - 13), Vector2(20, 13)), Color(0.7, 0.85, 1.0, flick))
	if thing.progress > 0.0 and thing.demolish:
		_bar(thing.progress, Color("#d99a6a"))
	_draw_power_state()


## 1.23: живой декор — стрелки часов по игровому времени, маятник, флаг на ветру, огоньки ёлки,
## пар над самоваром, пузырьки в кулере, светящаяся шкала радио.
func _draw_decor_anim() -> void:
	match thing.def_id:
		"floor_clock":
			var fc := _anchor("face")
			if fc.is_empty():
				return
			var c := tp(fc[0], fc[1])
			var mins := fmod(sim.minute, 1440.0)
			var ah := (mins / 720.0) * TAU - PI * 0.5
			var am := fmod(mins, 60.0) / 60.0 * TAU - PI * 0.5
			over.draw_line(c, c + Vector2(cos(ah), sin(ah)) * 3.2, Color("#2a1e14"), 1.2, true)
			over.draw_line(c, c + Vector2(cos(am), sin(am)) * 4.6, Color("#2a1e14"), 0.8, true)
			var pd := _anchor("pend")
			if not pd.is_empty():
				var top := tp(pd[0], pd[1])
				var a := sin(_t * 3.2) * 0.35
				var tip := top + Vector2(sin(a), cos(a)) * 14.0
				over.draw_line(top, tip, Color("#b8943a"), 0.8, true)
				over.draw_circle(tip, 2.2, Color("#d9b13b"))
		"flagpole":
			var fl := _anchor("flag")
			if fl.is_empty():
				return
			var o := tp(fl[0], fl[1])
			var pts := PackedVector2Array()
			var low := PackedVector2Array()
			for i in 9:
				var x := i * 2.4
				var wv := sin(_t * 4.0 - i * 0.7) * (0.4 + i * 0.22)
				pts.append(o + Vector2(x, wv))
				low.append(o + Vector2(x, 11.0 + wv))
			var poly := PackedVector2Array(pts)
			for j in range(low.size() - 1, -1, -1):
				poly.append(low[j])
			over.draw_colored_polygon(poly, Color("#3a7a4a"))   # флаг завода: зелёный с белой полосой
			var mid := PackedVector2Array()
			for i2 in pts.size():
				mid.append(pts[i2].lerp(low[i2], 0.5))
			over.draw_polyline(mid, Color("#f2f0e8"), 1.8, true)
			over.draw_polyline(pts, Color(0.1, 0.12, 0.15, 0.6), 0.6, true)
		"ny_tree":
			var ls: Array = meta.get("anchors", {}).get("lights", [])
			var cols := [Color("#ff4a3a"), Color("#ffd24a"), Color("#4ab0ff"), Color("#6fe07a"), Color("#ff7ad0")]
			for i3 in ls.size():
				var on := fmod(_t * 1.4 + i3 * 0.37, 1.0) < 0.6
				var lp: Array = ls[i3]
				var col: Color = cols[i3 % cols.size()]
				over.draw_circle(tp(lp[0], lp[1]), 1.4, col if on else col.darkened(0.6))
				if on:
					over.draw_circle(tp(lp[0], lp[1]), 3.0, Color(col.r, col.g, col.b, 0.25))
		"samovar":
			var st := _anchor("steam")
			if st.is_empty():
				return
			for k in 4:
				var ph := fmod(_t * 0.35 + k * 0.25, 1.0)
				var p := tp(st[0], st[1]) + Vector2(sin(_t * 1.5 + k) * 2.0 + ph * 3.0, -ph * 14.0)
				over.draw_circle(p, 1.5 + ph * 2.5, Color(1, 1, 1, 0.35 * (1.0 - ph)))
		"water_cooler":
			var bo := _anchor("bottle")
			if bo.is_empty():
				return
			var ph2 := fmod(_t * 0.25, 1.0)
			if ph2 < 0.5:
				var q := ph2 / 0.5
				over.draw_circle(tp(bo[0], bo[1] - q * 26.0), 0.8 + q * 1.4, Color(1, 1, 1, 0.75 * (1.0 - q)))
		"radio":
			var dl := _anchor("dial")
			if dl.is_empty():
				return
			var g := 0.25 + 0.12 * sin(_t * 2.0)
			over.draw_circle(tp(dl[0], dl[1]), 4.5, Color(1.0, 0.85, 0.4, g))


## Контейнер для стружки: горка стружки растёт по мере заполнения.
func _draw_chip_bin() -> void:
	var f := _anchor("fill")
	if f.is_empty():
		return
	var k := clampf(float(sim.upkeep.bin_kg.get(thing.id, 0.0)) / Upkeep.BIN_CAP, 0.0, 1.0)
	if k <= 0.02:
		return
	var p0 := tp(float(f[0]), float(f[1]) + float(f[3]))
	var w := float(f[2]) * 0.5
	var h := (float(f[3]) * 0.5) * (0.3 + k * 1.4)
	var cols := [Color("#c9ccce"), Color("#aab1b5"), Color("#c7a46a"), Color("#9aa1a5")]
	var n := int(4 + k * 14)
	for i in n:
		var x := p0.x + fmod(i * 7.3, w)
		var y := p0.y - fmod(i * 3.7, h)
		over.draw_arc(Vector2(x, y), 1.6 + fmod(i * 0.7, 1.4), 0.3, 4.4, 6, cols[i % cols.size()], 1.1)


## Вентилятор: крыльчатка крутится, пока есть ток.
func _draw_fan() -> void:
	var ro := _anchor("rotor")
	if ro.is_empty():
		return
	var on := thing.enabled and sim.power.powered(thing)
	var c := tp(ro[0], ro[1])
	var r := float(ro[2]) * 0.5
	var ang := _t * 14.0 if on else 0.6
	for k in 5:
		var a := ang + k * TAU / 5.0
		var p1 := c + Vector2(cos(a), sin(a)) * r
		var p2 := c + Vector2(cos(a + 0.55), sin(a + 0.55)) * r * 0.85
		over.draw_colored_polygon(PackedVector2Array([c, p1, p2]), Color(0.62, 0.68, 0.72, 0.55 if on else 0.9))
	over.draw_circle(c, 2.2, Color("#3a3f43"))
	var lamp := _anchor("lamp")
	if not lamp.is_empty():
		over.draw_circle(tp(lamp[0], lamp[1]), 1.8, Color("#6fbf86") if on else Color("#5a2a22"))


## Компрессор: дрожит стрелка манометра, горит лампа, когда качает.
func _draw_compressor() -> void:
	var run := sim.eng.compressor_running(thing)
	var gg := _anchor("gauge")
	if not gg.is_empty():
		var c := tp(gg[0], gg[1])
		var a := -2.4 + (1.8 + 0.12 * sin(_t * 17.0) if run else (0.6 if sim.power.powered(thing) else 0.0))
		over.draw_line(c, c + Vector2(cos(a), sin(a)) * 2.8, Color("#c9372c"), 0.9)
	var lamp := _anchor("lamp")
	if not lamp.is_empty():
		over.draw_circle(tp(lamp[0], lamp[1]), 1.8, Color("#6fe08a") if run else Color("#2a4a32"))


## Котёл: в окошке горит пламя, пока греет; из трубы — лёгкий дымок.
func _draw_boiler() -> void:
	var fl := _anchor("flame")
	var burning := sim.season.heating_season() and sim.eng.boiler_problem(thing) == ""
	if not fl.is_empty() and burning:
		var p := tp(fl[0], fl[1])
		var w := float(fl[2]) * 0.5
		var h := float(fl[3]) * 0.5
		for k in 5:
			var x := p.x - w * 0.4 + k * w * 0.2
			var fh := h * (0.5 + 0.3 * sin(_t * 9.0 + k * 1.7))
			over.draw_colored_polygon(PackedVector2Array([Vector2(x - 2.0, p.y + h * 0.45), Vector2(x + 2.0, p.y + h * 0.45), Vector2(x, p.y + h * 0.45 - fh)]),
				Color(0.35, 0.6, 1.0, 0.9) if k % 2 == 0 else Color(1.0, 0.7, 0.3, 0.85))
	var lamp := _anchor("lamp")
	if not lamp.is_empty():
		over.draw_circle(tp(lamp[0], lamp[1]), 1.8, Color("#6fe08a") if burning else Color("#d9493a"))
	var sm := _anchor("smoke")
	if not sm.is_empty() and burning:
		var base := tp(sm[0], sm[1])
		for k2 in 3:
			var ph := fmod(_t * 0.25 + k2 * 0.33, 1.0)
			over.draw_circle(base + Vector2(sin(ph * 4.0 + k2) * 3.0, -ph * 26.0), 3.0 + ph * 6.0, Color(0.85, 0.86, 0.88, (1.0 - ph) * 0.35))


## Ленточная пила: полотно бежит, пока режет, из-под него летят искорки и опилки.
func _draw_saw() -> void:
	var bl := _anchor("blade")
	var lamp := _anchor("lamp")
	if not lamp.is_empty() and sim.power.powered(thing):
		over.draw_circle(tp(lamp[0], lamp[1]), 2.2, Color("#6fbf86") if thing.working else Color("#d9b13b"))
	if bl.is_empty() or not thing.working:
		return
	var a := tp(bl[0], bl[1])
	var b := tp(bl[2], bl[3])
	for k in 6:
		var ph := fmod(_t * 3.0 + k / 6.0, 1.0)
		over.draw_circle(a.lerp(b, ph), 0.8, Color(1, 1, 1, 0.8))
	for k2 in 4:
		var ph2 := fmod(_t * 2.2 + k2 * 0.25, 1.0)
		over.draw_circle(b + Vector2(-3.0 + k2 * 2.0, -1.0 + ph2 * 5.0), 0.9, Color(0.85, 0.8, 0.7, 1.0 - ph2))


func _draw_power_state() -> void:
	var k := thing.kind()
	var src := str(thing.def().get("power_source", "")) != ""
	var draws := k == "machine" or float(thing.def().get("power_kw", 0.0)) > 0.0
	if not src and not draws:
		return
	var w := float(meta.get("w", 64)) * 0.5
	var top := -float(meta.get("oy", 64)) * 0.5
	var pos := Vector2(w * 0.5 - 7.0, top - 18.0)
	if k == "machine" and not thing.enabled:
		over.draw_texture_rect(Tex.ui_world("power_off"), Rect2(pos, Vector2(14, 14)), false)
		return
	if src:
		var net := sim.power.net_of_thing(thing)
		if net and net.tripped and fmod(_t, 1.0) < 0.6:
			over.draw_texture_rect(Tex.ui_world("bolt_off"), Rect2(pos, Vector2(14, 14)), false)
		return
	if not sim.power.powered(thing) and fmod(_t, 1.2) < 0.8:
		over.draw_texture_rect(Tex.ui_world("bolt_off"), Rect2(pos, Vector2(14, 14)), false)


func _bar(v: float, col: Color) -> void:
	var w := float(meta.get("w", 64)) * 0.5
	var top := -float(meta.get("oy", 64)) * 0.5 - 4.0
	var r := Rect2(w * 0.2, top, w * 0.6, 4)
	over.draw_rect(r.grow(1), Color("#1d2024"))
	over.draw_rect(Rect2(r.position, Vector2(r.size.x * clampf(v, 0, 1), r.size.y)), col)


func _draw_machine() -> void:
	var lamp := _anchor("lamp")
	var col := Color("#8a9196")
	if thing.broken:
		col = Color("#ff4a3a") if fmod(_t, 0.6) < 0.35 else Color("#6a1d16")
	elif thing.working:
		col = Color("#6fe08a") if fmod(_t, 1.0) < 0.75 else Color("#3e9a5a")
	elif thing.product != "":
		col = Color("#e8c547")
	if not lamp.is_empty():
		var lp := tp(lamp[0], lamp[1])
		if thing.working or thing.broken:
			over.draw_circle(lp, 5.0, Color(col.r, col.g, col.b, 0.25))
		over.draw_circle(lp, 2.6, col)
	var pr := thing.process()
	var lathe_fx := pr == "turning" and not _anchor("chuck").is_empty()
	# 1.55: какие частицы показывать (по качеству, «Меньше анимации» и масштабу)
	_far = _zoom_now() < ShopFx.ZOOM_MIN
	var fxs := ShopFx.effects(pr, thing.working, thing.broken, FxLayer.quality, _zoom_now())
	if lathe_fx:
		_fx_lathe(fxs.has("chips"))
	elif thing.working:
		match pr:
			"milling", "drilling", "turning":
				_fx_cutting(pr == "milling", fxs.has("chips"))   # станки ЧПУ: шпиндель за окном кожуха
			"welding":
				_fx_welding()
			"paint":
				_fx_paint(fxs.has("mist"))
			"assembly":
				_fx_assembly()
	if pr == "heat":
		_fx_furnace()
		_fx_steam()
	elif pr == "casting":
		_fx_casting()
		_fx_steam()
	elif pr == "stamping":
		_fx_stamping()
	if thing.working:
		_bar(thing.progress, Color("#6fbf86") if not thing.is_batch() else Color("#e8853a"))
	# входы и выходы
	if not lathe_fx:
		var a_in := _anchor("in")
		if not a_in.is_empty():
			_draw_slot_items(0, tp(a_in[0], a_in[1]), 4)
	var out := _anchor("out")
	if not out.is_empty():
		_draw_slot_items(1, tp(out[0], out[1]), 4)
	if thing.broken:
		_fx_broken()
	elif thing.condition < Defs.b("breakdown_below") and fmod(_t, 2.0) < 1.0:
		var w := float(meta.get("w", 64)) * 0.5
		var top := -float(meta.get("oy", 64)) * 0.5
		_wrench(Vector2(w * 0.5 + 9.0, top - 11.0), Color("#e8a23a"))


## Грузы в слоте станка стопкой; полуфабрикаты (НЗП) — приглушённые.
func _draw_slot_items(slot: int, base: Vector2, maxn: int) -> void:
	var ids := sim.slot_ids(thing, slot)
	for k in mini(ids.size(), maxn):
		var it: Item = sim.items.get(ids[k])
		if it == null:
			continue
		var c := base + Vector2(-k * 4.5, -4.0 - k * 1.5)
		var tex := Tex.for_item(it)
		if tex:
			var m := Color(0.78, 0.8, 0.86) if it.q == "wip" else Color.WHITE
			over.draw_texture_rect(tex, Rect2(c - Vector2(5, 5), Vector2(10, 10)), false, m)


func _fx_lathe(chips: bool = true) -> void:
	var ch := _anchor("chuck")
	if thing.working and not ch.is_empty():
		var r := Rect2(tp(ch[0], ch[1]), Vector2(ch[2], ch[3]) * 0.5)
		var ph := fmod(_t * 22.0, 3.5)
		var y := r.position.y + ph
		while y < r.end.y:
			over.draw_line(Vector2(r.position.x + 0.8, y), Vector2(r.end.x - 0.8, y), Color("#4a5156"), 1.2)
			y += 3.5
		var tool := _anchor("tool")
		if chips and not tool.is_empty():
			var tpnt := tp(tool[0], tool[1])
			for k in 4:
				var ph2 := fmod(_t * 1.7 + k * 0.27, 1.0)
				var p := tpnt + Vector2(-2.0 - ph2 * 6.0 + sin(k * 2.3) * 2.0, ph2 * 14.0)
				over.draw_circle(p, 0.9, Color("#c7a46a") if k % 2 == 0 else Color("#cfd6db"))
	var bar := _anchor("bar")
	var n_in := sim.count_slot(thing, 0)
	if not bar.is_empty() and n_in > 0:
		var base := tp(bar[0], bar[1])
		var ids := sim.slot_ids(thing, 0)
		for k in mini(n_in, 4):
			var it: Item = sim.items.get(ids[k])
			if it and it.kind == "part":
				_draw_item(Tex.for_item(it), base + Vector2(k * 6.0, -4.0), 10.0)
				continue
			var c: Color = MAT_COL.get(it.def_id if it else "bar45", Color("#9aa1a5"))
			var rr := Rect2(base + Vector2(-4, -2.4 * k - 3), Vector2(26, 2.6))
			over.draw_rect(rr, c)
			over.draw_rect(rr, Color("#23262a"), false, 0.6)


func _fx_cutting(mill: bool, chips: bool = true) -> void:
	var a := _anchor("work")
	if a.is_empty():
		return
	var p := tp(a[0], a[1])
	# вращение инструмента
	var ang := _t * 18.0
	var r := 5.0 if mill else 2.5
	for k in 3:
		var aa := ang + k * TAU / 3.0
		over.draw_line(p + Vector2(cos(aa), sin(aa) * 0.35) * r, p - Vector2(cos(aa), sin(aa) * 0.35) * r, Color("#e8eef2", 0.7), 1.0)
	if not chips:
		return
	# стружка
	for k in 6:
		var ph := fmod(_t * 1.9 + k * 0.17, 1.0)
		var dir := -1.0 if k % 2 == 0 else 1.0
		var q := p + Vector2(dir * (2.0 + ph * 9.0) + sin(k * 1.7) * 1.5, -ph * 5.0 + ph * ph * 12.0)
		over.draw_circle(q, 0.8, Color("#c7a46a") if k % 3 == 0 else Color("#cfd6db"))
	# эмульсия
	if mill:
		for k in 3:
			var ph2 := fmod(_t * 2.5 + k * 0.33, 1.0)
			over.draw_circle(p + Vector2(-3.0 + k * 3.0, ph2 * 6.0), 0.9, Color(0.6, 0.85, 0.95, 0.6 * (1.0 - ph2)))


func _fx_welding() -> void:
	var a := _anchor("flash")
	if a.is_empty():
		a = _anchor("work")
	if a.is_empty():
		return
	var p := tp(a[0], a[1])
	var on := fmod(_t * 7.3, 1.0) < 0.7 and fmod(_t, 3.1) < 2.6
	if on:
		var fl := 0.75 + 0.25 * sin(_t * 61.0)
		over.draw_circle(p, 26.0 * fl, Color(0.55, 0.75, 1.0, 0.10))
		over.draw_circle(p, 12.0 * fl, Color(0.75, 0.88, 1.0, 0.22))
		over.draw_circle(p, 3.5, Color(1, 1, 1, 0.95))
		for k in (7 if FxLayer.quality > 0 and not _far else 0):
			var ph := fmod(_t * 2.3 + k * 0.143, 1.0)
			var ang := k * 0.9 + 0.4
			var q := p + Vector2(cos(ang) * ph * 14.0, -absf(sin(ang)) * ph * 10.0 + ph * ph * 16.0)
			over.draw_line(q, q + Vector2(cos(ang), 0.6) * 1.6, Color(1.0, 0.82, 0.35, 1.0 - ph), 1.7)
		if FxLayer.quality >= 2:
			# 1.25: брызги металла падают на пол и гаснут там красными точками
			_sparks(p, 12, Color(1.0, 0.78, 0.38), 1.0, Vector2.ZERO, 22.0)
	# дымок сварки
	var sm := Tex.fx("smoke")
	if sm:
		for k in 2:
			var ph2 := fmod(_t * 0.35 + k * 0.5, 1.0)
			var c := p + Vector2(sin(ph2 * 5.0 + k) * 3.0, -6.0 - ph2 * 22.0)
			var sz := 6.0 + ph2 * 12.0
			over.draw_texture_rect(sm, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, 0.35 * (1.0 - ph2)))


func _fx_paint(mist: bool = true) -> void:
	var a := _anchor("mist")
	if a.is_empty() or not mist:
		return
	var p := tp(a[0], a[1])
	var col := Color("#5a8f4e")
	if thing.product != "":
		col = Color(str(Defs.products.get(thing.product, {}).get("paint_col", "#5a8f4e")))
	for k in 10:
		var ph := fmod(_t * 0.8 + k * 0.1, 1.0)
		var q := p + Vector2(-14.0 + ph * 28.0 + sin(k * 2.1 + _t) * 3.0, sin(k * 1.3) * 6.0 - ph * 4.0)
		over.draw_circle(q, 2.0 + ph * 3.0, Color(col.r, col.g, col.b, 0.28 * (1.0 - ph)))
	# пистолет-распылитель
	var gx := p.x + sin(_t * 2.0) * 10.0
	over.draw_line(Vector2(gx, p.y + 6.0), Vector2(gx + 4.0, p.y + 2.0), Color("#2a2e31"), 2.0)


func _fx_assembly() -> void:
	var a := _anchor("work")
	if a.is_empty():
		return
	var p := tp(a[0], a[1])
	# 1.25: слесарь зачищает болгаркой — короткими очередями сноп оранжевых искр в сторону
	if FxLayer.quality > 0 and fmod(_t * 0.33 + float(thing.id) * 0.17, 1.0) < 0.42:
		_sparks(p + Vector2(4, -2), 14 if FxLayer.quality >= 2 else 6, Color(1.0, 0.6, 0.2), 1.5, Vector2(1.0, -0.35), 18.0)
	if fmod(_t, 1.4) < 0.5:
		var r := 2.0 + fmod(_t, 0.5) * 8.0
		over.draw_arc(p, r, 0.0, TAU, 12, Color(1, 1, 1, 0.5 - fmod(_t, 0.5)), 1.0)
	var it_id := ""
	if thing.product != "":
		it_id = thing.product
	if it_id != "" and thing.progress > 0.3:
		_draw_item(Tex.item(it_id), p + Vector2(0, -3), 11.0)


## 1.25: сноп искр — разлетаются дугой и падают; dir — куда летят (ноль — во все стороны), floor — где пол.
func _sparks(at: Vector2, n: int, col: Color, spd: float, dir: Vector2, floor_y: float) -> void:
	if _far or FxLayer.quality <= 0:
		return
	for k in n:
		var sd := float(k) * 1.618 + float(thing.id) * 0.73
		var life := 0.5 + fmod(sd * 0.37, 0.35)
		var ph := fmod(_t / life + fmod(sd, 1.0), 1.0)
		var ang := fmod(sd * 2.399, TAU)
		var v := Vector2(cos(ang), sin(ang) * 0.6 - 0.7)
		if dir != Vector2.ZERO:
			v = dir.normalized() + Vector2(cos(ang), sin(ang)) * 0.45
		v *= 20.0 * spd
		var q := at + v * ph + Vector2(0, 30.0 * ph * ph)
		if q.y > at.y + floor_y:
			# упала: тлеет на полу
			q.y = at.y + floor_y
			over.draw_circle(q, 0.9, Color(1.0, 0.35, 0.1, 0.8 * (1.0 - ph)))
			continue
		var pq := maxf(0.0, ph - 0.1)
		var tail := at + v * pq + Vector2(0, 30.0 * pq * pq)
		over.draw_line(tail, q, Color(col.r, col.g, col.b, 1.0 - ph * 0.6), 1.6)


func _fx_furnace() -> void:
	var g := _anchor("glow")
	if g.is_empty():
		return
	var r := Rect2(tp(g[0], g[1]), Vector2(g[2], g[3]) * 0.5)
	var k := 0.0
	if thing.working:
		k = 0.75 + 0.25 * sin(_t * 3.0)
	elif thing.batch_t > 0.0 or sim.count_slot(thing, 1) > 0:
		k = 0.25
	if k <= 0.0:
		return
	over.draw_rect(r, Color(1.0, 0.45 + 0.2 * k, 0.12, 0.85 * k))
	over.draw_rect(r.grow(-3), Color(1.0, 0.85, 0.4, 0.6 * k))
	var gl := Tex.fx("glow")
	if gl and thing.working:
		var c := r.get_center()
		over.draw_texture_rect(gl, Rect2(c - Vector2(40, 40), Vector2(80, 80)), false, Color(1.0, 0.55, 0.2, 0.35 * k))
	# марево над печью
	if thing.working:
		var w := float(meta.get("w", 64)) * 0.5
		var top := -float(meta.get("oy", 64)) * 0.5
		for j in 3:
			var ph := fmod(_t * 0.5 + j * 0.33, 1.0)
			var x := w * 0.42 + sin(ph * 7.0 + j) * 4.0
			over.draw_line(Vector2(x - 4, top + 4 - ph * 14.0), Vector2(x + 4, top + 2 - ph * 14.0), Color(1, 0.9, 0.8, 0.25 * (1.0 - ph)), 1.5)


var _was_work := false
var _steam_until := -1.0
var _far := false   ## 1.55: слишком далеко — частицы не рисуем


func _zoom_now() -> float:
	return get_viewport().get_canvas_transform().get_scale().x if is_inside_tree() else 1.0


func _fx_steam() -> void:
	# 1.25: пар — над работающей печью понемногу, а когда садка вышла (закалка) — густые клубы
	if _was_work and not thing.working:
		_steam_until = _t + 4.0
	_was_work = thing.working
	if FxLayer.quality > 0 and not _far and (thing.working or _t < _steam_until):
		var w2 := float(meta.get("w", 64)) * 0.5
		var top2 := -float(meta.get("oy", 64)) * 0.5
		var burst := _t < _steam_until
		var n := (9 if burst else 4) if FxLayer.quality >= 2 else 3
		var sm := Tex.fx("smoke")
		for j2 in n:
			var ph3 := fmod(_t * (0.32 if burst else 0.2) + float(j2) / float(n), 1.0)
			var c3 := Vector2(w2 * (0.3 + float(j2 % 3) * 0.2) + sin(_t * 0.9 + j2 * 1.7) * 5.0, top2 + 6.0 - ph3 * (46.0 if burst else 30.0))
			var sz := (10.0 + ph3 * (26.0 if burst else 16.0))
			var al := (1.0 - ph3) * (0.6 if burst else 0.42)
			if sm:
				over.draw_texture_rect(sm, Rect2(c3 - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(1, 1, 1, al))


func _fx_broken() -> void:
	var w := float(meta.get("w", 64)) * 0.5
	var top := -float(meta.get("oy", 64)) * 0.5
	var sm := Tex.fx("smoke")
	if sm and FxLayer.quality > 0 and not _far:
		for k in 3:
			var ph := fmod(_t * 0.3 + k * 0.33, 1.0)
			var c := Vector2(w * 0.5 + sin(ph * 6.0 + k) * 5.0, top + 14.0 - ph * 26.0)
			var sz := 8.0 + ph * 16.0
			over.draw_texture_rect(sm, Rect2(c - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.35, 0.35, 0.37, 0.6 * (1.0 - ph)))
	_wrench(Vector2(w * 0.5 + 9.0, top - 11.0), Color("#ff5a45"))
	_beacon(Vector2(w * 0.5 - 8.0, top - 6.0))


## 1.55: аварийная оранжевая лампа над сломанным станком: мигает и крутит луч («Меньше анимации» — горит ровно).
func _beacon(c: Vector2) -> void:
	var calm := ShopFx.calm()
	var k := ShopFx.beacon_k(_t + float(thing.id) * 0.23, calm)
	var g := Tex.fx("glow")
	if g:
		over.draw_texture_rect(g, Rect2(c - Vector2(24, 24), Vector2(48, 48)), false, Color(1.0, 0.5, 0.1, 0.8 * k))
	over.draw_rect(Rect2(c + Vector2(-3.0, 1.0), Vector2(6.0, 2.5)), Color("#3a3d41"))
	over.draw_circle(c, 3.6, Color(1.0, 0.42 + 0.25 * k, 0.08, 0.4 + 0.6 * k))
	over.draw_circle(c + Vector2(-1.0, -1.0), 1.2, Color(1, 0.95, 0.8, 0.8 * k))
	if not calm and k > 0.5:
		var a := _t * 7.0
		over.draw_line(c, c + Vector2(cos(a), sin(a) * 0.6) * 15.0, Color(1.0, 0.6, 0.15, 0.55), 2.0)


## Значок «гаечный ключ» в кружке.
func _wrench(c: Vector2, col: Color) -> void:
	over.draw_circle(c, 7.0, Color("#1d2024"))
	over.draw_arc(c, 7.0, 0.0, TAU, 20, col, 1.4)
	over.draw_line(c + Vector2(-3.2, 3.2), c + Vector2(2.2, -2.2), col, 2.0)
	over.draw_arc(c + Vector2(2.6, -2.6), 2.2, -2.4, 1.6, 8, col, 1.6)


func _slot_rect(i: int) -> Rect2:
	var sl: Array = meta.get("slots", [])
	if i >= sl.size():
		return Rect2()
	var s: Array = sl[i]
	var x0 := float(s[0]) + (float(s[2]) if flip else 0.0)
	return Rect2(tp(x0, s[1]), Vector2(s[2], s[3]) * 0.5)


func _draw_storage() -> void:
	match thing.def_id:
		"rack":
			for s in thing.slot_count():
				var r := _slot_rect(s)
				var ids := sim.slot_ids(thing, s)
				for k in ids.size():
					var it: Item = sim.items.get(ids[k])
					if it == null:
						continue
					var row := int(k / 2)
					var colm := k % 2
					var rw := r.size.x * 0.5 - 1.0
					var rod := Rect2(r.position.x + colm * (rw + 2.0), r.end.y - 2.6 * (row + 1), rw, 2.3)
					if r.size.y > r.size.x * 1.2:
						# стеллаж повёрнут вдоль: прутки лежат вертикально
						var rh := r.size.y * 0.5 - 1.0
						rod = Rect2(r.position.x + 2.6 * row, r.position.y + colm * (rh + 2.0), 2.3, rh)
					var c: Color = MAT_COL.get(it.def_id, Color("#9aa1a5"))
					over.draw_rect(rod, c)
					over.draw_rect(rod, Color("#23262a"), false, 0.5)
					if it.def_id == "bar40x":
						over.draw_rect(Rect2(rod.end.x - 2.5, rod.position.y, 2.5, rod.size.y), Color("#3d6fb0"))
		"pallet_raw":
			# 1.29: поддон заготовок — пачка прутков между стойками, сколько лежит, столько и видно
			var rp := _slot_rect(0)
			var idsp := sim.slot_ids(thing, 0)
			var rwp := rp.size.x * 0.5 - 1.0
			for k5 in mini(idsp.size(), 12):
				var it5: Item = sim.items.get(idsp[k5])
				if it5 == null:
					continue
				var rod5 := Rect2(rp.position.x + (k5 % 2) * (rwp + 2.0), rp.end.y - 2.6 * (int(k5 / 2) + 1), rwp, 2.3)
				over.draw_rect(rod5, MAT_COL.get(it5.def_id, Color("#9aa1a5")))
				over.draw_rect(rod5, Color("#23262a"), false, 0.5)
			if not idsp.is_empty():
				var top := rp.end.y - 2.6 * ceilf(mini(idsp.size(), 12) / 2.0)
				for bx in [0.3, 0.7]:
					over.draw_rect(Rect2(rp.position.x + rp.size.x * bx - 0.8, top, 1.6, rp.end.y - top), Color("#3d6fb0"))
		"pallet":
			var r2 := _slot_rect(0)
			var ids2 := sim.slot_ids(thing, 0)
			var crates := int(ceil(ids2.size() / 4.0))
			var crate_tex := Tex.item("crate")
			for k in mini(crates, 4):
				var cx := r2.position.x + (k % 2) * r2.size.x * 0.5 + 1.0
				var cy := r2.position.y + (1 - int(k / 2)) * r2.size.y * 0.42 + 1.0
				var cr := Rect2(cx, cy, r2.size.x * 0.48, r2.size.y * 0.5)
				over.draw_texture_rect(crate_tex, cr, false)
				var it3: Item = sim.items.get(ids2[k * 4])
				if it3:
					_draw_item(Tex.for_item(it3), cr.get_center() + Vector2(0, -1), 8.0)
		"wip_rack":
			for s2 in thing.slot_count():
				var rr := _slot_rect(s2)
				var ids4 := sim.slot_ids(thing, s2)
				for k in mini(ids4.size(), 9):
					var it4: Item = sim.items.get(ids4[k])
					if it4 == null:
						continue
					var cx2 := rr.position.x + 8.0 + (k % 3) * (rr.size.x / 3.0)
					var cy2 := rr.position.y + 5.0 - int(k / 3) * 2.0
					_draw_item(Tex.for_item(it4), Vector2(cx2, cy2), 9.0)
		"scrap_bin":
			var r3 := _slot_rect(0)
			var n := sim.count_slot(thing, 0)
			var tex := Tex.item("scrap")
			for k in mini(n, 8):
				var p := r3.position + Vector2(4.0 + (k * 7) % int(maxf(1.0, r3.size.x - 8.0)), r3.size.y - 4.0 - int(k / 3) * 2.0)
				_draw_item(tex, p, 8.0)


func _draw_qc() -> void:
	var r := _slot_rect(0)
	var ids := sim.slot_ids(thing, 0)
	for k in mini(ids.size(), 6):
		var it: Item = sim.items.get(ids[k])
		if it:
			_draw_item(Tex.for_item(it), r.position + Vector2(5.0 + (k % 3) * 7.5, 4.0 + int(k / 3) * 6.0), 9.0)


## 1.27: литьё — зеркало расплава в тигле светится; на середине цикла ковш наклоняют, струя металла
## бьёт в опоку, летят искры, над залитой опокой — дымок.
func _fx_casting() -> void:
	var g := _anchor("glow")
	if g.is_empty():
		return
	var r := Rect2(tp(g[0], g[1]), Vector2(g[2], g[3]) * 0.5)
	var k := 0.0
	if thing.working:
		k = 0.8 + 0.2 * sin(_t * 4.0 + sin(_t * 1.7))
	elif thing.product != "" and sim.count_slot(thing, 0) > 0:
		k = 0.3
	if k > 0.0:
		var c := r.get_center()
		over.draw_set_transform(c, 0.0, Vector2(1.0, r.size.y / maxf(1.0, r.size.x)))
		over.draw_circle(Vector2.ZERO, r.size.x * 0.5, Color(1.0, 0.42, 0.1, 0.9 * k))
		over.draw_circle(Vector2.ZERO, r.size.x * 0.32, Color(1.0, 0.82, 0.35, 0.8 * k))
		over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		var gl := Tex.fx("glow")
		if gl and thing.working:
			over.draw_texture_rect(gl, Rect2(c - Vector2(36, 36), Vector2(72, 72)), false, Color(1.0, 0.5, 0.18, 0.3 * k))
	if not thing.working:
		return
	var pour := _anchor("pour")
	if pour.is_empty():
		return
	var ph := thing.progress
	var p0 := tp(pour[0], pour[1])
	var p1 := p0 + Vector2(1.5, 15.0)   # струя падает почти отвесно в опоку под носиком
	if ph > 0.55 and ph < 0.85:
		# струя: волнистая, толще в начале
		var n := 8
		var prev := p0
		for j in range(1, n + 1):
			var f := float(j) / n
			var q := p0.lerp(p1, f) + Vector2(sin(_t * 22.0 + f * 9.0) * 0.6 * f, 0)
			over.draw_line(prev, q, Color(1.0, 0.62 + 0.2 * (1.0 - f), 0.18, 0.95), 2.4 - f * 0.9)
			prev = q
		over.draw_circle(p1, 2.4, Color(1.0, 0.85, 0.4, 0.9))
		if FxLayer.quality > 0:
			_sparks(p1, 10 if FxLayer.quality >= 2 else 4, Color(1.0, 0.75, 0.3), 1.1, Vector2.ZERO, 6.0)
	if ph > 0.7 and FxLayer.quality > 0:
		var sm := Tex.fx("smoke")
		if sm:
			for j2 in 3:
				var q2 := fmod(_t * 0.35 + j2 * 0.33, 1.0)
				var c2 := p1 + Vector2(sin(_t + j2 * 2.1) * 4.0, -q2 * 26.0)
				var sz := 8.0 + q2 * 14.0
				over.draw_texture_rect(sm, Rect2(c2 - Vector2(sz, sz) * 0.5, Vector2(sz, sz)), false, Color(0.75, 0.72, 0.7, 0.4 * (1.0 - q2)))


## 1.27: штамповка — ползун ходит вниз-вверх раз в 0,9 с (резко вниз, плавно вверх), в момент удара —
## вспышка металла и пыль, станок вздрагивает.
const STAMP_T := 0.9


func _fx_stamping() -> void:
	var ram := _anchor("ram")
	if ram.is_empty():
		return
	var r := Rect2(tp(ram[0], ram[1]), Vector2(ram[2], 6.0) * 0.5)
	var stroke := float(ram[3]) * 0.5
	var y := 0.0
	var hit := false
	if thing.working:
		var ph := fmod(_t + float(thing.id) * 0.13, STAMP_T) / STAMP_T
		if ph < 0.18:
			y = stroke * ph / 0.18
		elif ph < 0.26:
			y = stroke
			hit = true
		else:
			y = stroke * (1.0 - (ph - 0.26) / 0.74)
		if hit:
			sprite.position = _spr_base + Vector2(0, 0.6)
	var rr := Rect2(r.position + Vector2(0, y), r.size)
	over.draw_rect(Rect2(Vector2(rr.position.x + rr.size.x * 0.5 - 1.5, r.position.y - 2.0), Vector2(3.0, y + 2.0)), Color("#9aa3a8"))
	over.draw_rect(rr, Color("#7b8286"))
	over.draw_rect(Rect2(rr.position, Vector2(rr.size.x, 1.2)), Color("#cdd3d7"))
	if hit and FxLayer.quality > 0:
		var w := _anchor("work")
		var at := tp(w[0], w[1]) if not w.is_empty() else rr.get_center() + Vector2(0, 6)
		_sparks(at, 5 if FxLayer.quality >= 2 else 2, Color(1.0, 0.9, 0.6), 0.6, Vector2.ZERO, 4.0)
		over.draw_circle(at, 5.0, Color(1, 1, 1, 0.18))
