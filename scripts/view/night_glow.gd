class_name NightGlow
extends Node2D
## 1.55: тёплый свет ночью — дешёвые пятна-спрайты вместо PointLight2D: лампы в цехах, уличные фонари у дороги и забора,
## оранжевое зарево аварийных ламп над сломанными станками. Один узел, аддитивное смешивание, рисуется только то, что в кадре,
## и не чаще 8 раз в секунду (камера не нужна: слой следует за ней сам). Днём не рисует ничего.

const T := World.T
const REDRAW := 0.12

var dn: DayNight
var sim: Sim
var _acc := 0.0
var _last_night := -1.0
var count := 0   ## сколько пятен нарисовано в последний раз (для теста и диагностики)


func _ready() -> void:
	var m := CanvasItemMaterial.new()
	m.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = m


func _process(delta: float) -> void:
	if dn == null:
		return
	var n := dn.night
	if n < 0.04:
		if _last_night >= 0.04 or count > 0:
			count = 0
			queue_redraw()
		_last_night = n
		return
	_acc += delta
	if _acc >= REDRAW or absf(n - _last_night) > 0.05:
		_acc = 0.0
		_last_night = n
		queue_redraw()


func _draw() -> void:
	count = 0
	if dn == null or sim == null or dn.night < 0.04:
		return
	var g := Tex.fx("glow")
	if g == null:
		return
	var view := WorkerView.view.grow(260.0)
	var n := dn.night
	for sp: Dictionary in dn.spots:
		var a := dn.spot_alpha(sp)
		if a <= 0.02:
			continue
		var p: Vector2 = sp["pos"]
		if not view.has_point(p):
			continue
		var d := clampf(float(sp["r"]), 2.0, 7.0) * T * 1.5
		var col: Color = sp["col"]
		# широкое мягкое пятно и яркая серединка
		draw_texture_rect(g, Rect2(p - Vector2(d, d) * 0.5, Vector2(d, d)), false, Color(col.r, col.g, col.b, a * 0.55))
		draw_texture_rect(g, Rect2(p - Vector2(d, d) * 0.2, Vector2(d, d) * 0.4), false, Color(1.0, 0.96, 0.82, a * 0.5))
		count += 1
	for sp2 in dn.street:
		if not view.has_point(sp2):
			continue
		var ds := 4.6 * T
		var c2 := sp2 + Vector2(0, -6.0)
		draw_texture_rect(g, Rect2(c2 - Vector2(ds, ds) * 0.5, Vector2(ds, ds)), false, Color(1.0, 0.82, 0.45, n * 0.62))
		draw_texture_rect(g, Rect2(c2 - Vector2(ds, ds) * 0.14, Vector2(ds, ds) * 0.28), false, Color(1.0, 0.95, 0.75, n * 0.7))
		count += 1
	# аварийные лампы над сломанными станками
	var tt := Time.get_ticks_msec() / 1000.0
	var calm := ShopFx.calm()
	for t: Thing in sim.things_of("machine"):
		if not t.built or not t.broken:
			continue
		var top := Vector2((float(t.cell.x) + float(t.size().x) * 0.5) * T, float(t.cell.y) * T - 8.0)
		if not view.has_point(top):
			continue
		var k := ShopFx.beacon_k(tt + float(t.id) * 0.23, calm)
		var da := 3.2 * T
		draw_texture_rect(g, Rect2(top - Vector2(da, da) * 0.5, Vector2(da, da)), false, Color(1.0, 0.45, 0.08, 0.5 * k * maxf(n, 0.35)))
		count += 1
