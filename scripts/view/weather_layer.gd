class_name WeatherLayer
extends Node2D
## Слой погоды поверх земли и полов, под людьми и объектами: снег на улице (с протоптанными
## дорожками), гололёд, следы пожара (копоть).

const T := World.T

var sim: Sim
var _snow_rev := -1
var _soot_n := -1
var _ice := false
var _rain := false
var _dirt_rev := -1
var _t := 0.0


func _process(delta: float) -> void:
	if sim == null:
		return
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.4
	var s := sim.season
	var rain := sim.progress.roof_leak and s.is_raining()
	var drev := sim.upkeep.dirt_rev / 8
	if s.snow_rev != _snow_rev or sim.story.soot.size() != _soot_n or s.ice != _ice or rain != _rain or drev != _dirt_rev:
		_dirt_rev = drev
		_rain = rain
		_snow_rev = s.snow_rev
		_soot_n = sim.story.soot.size()
		_ice = s.ice
		queue_redraw()


func _draw() -> void:
	if sim == null:
		return
	var w := sim.world
	var s := sim.season
	# копоть после пожара
	var soot := Tex.fx("soot")
	for i: int in sim.story.soot.keys():
		var c := w.cell_of(i)
		draw_texture_rect(soot, Rect2(Vector2(c) * T - Vector2(4, 4), Vector2(T + 8, T + 8)), false, Color(1, 1, 1, 0.7))
	# стружка и грязь на полу в помещениях
	var up := sim.upkeep
	if up.dirt.size() == w.w * w.h:
		var chips: Array[Texture2D] = [Tex.fx("chips_0"), Tex.fx("chips_1"), Tex.fx("chips_2")]
		var dust := Tex.fx("dust")
		for r in sim.rooms.list:
			for c in r.cells:
				var v := int(up.dirt[w.idx(c)])
				if v < 18:
					continue
				var rr := Rect2(Vector2(c) * T, Vector2(T, T))
				var hsh := WorldView.vhash(c.x, c.y)
				if v >= 40:
					draw_texture_rect(dust, rr.grow(4.0), false, Color(1, 1, 1, clampf(float(v - 30) / 220.0, 0.0, 0.55)))
				draw_texture_rect(chips[hsh % 3], rr, false, Color(1, 1, 1, clampf(float(v) / 110.0, 0.15, 1.0)))
				if v >= 140:
					draw_texture_rect(chips[(hsh + 1) % 3], rr.grow(-3.0), false, Color(1, 1, 1, clampf(float(v - 120) / 100.0, 0.0, 1.0)))
	# лужи под дырявой крышей в дождь
	if _rain:
		var puddle := Tex.fx("puddle")
		for r in sim.rooms.list:
			if r.type != "workshop" and r.area() < 60:
				continue
			for c in r.cells:
				if (c.x * 7 + c.y * 13) % 11 == 0:
					draw_texture_rect(puddle, Rect2(Vector2(c) * T - Vector2(4, 2), Vector2(T + 8, T + 4)), false)
	if s.snow.size() != w.w * w.h:
		return
	var tex: Array[Texture2D] = []
	for k in 4:
		tex.append(Tex.tile("snow_%d" % k))
	var ice_t := Tex.tile("ice")
	var blob := Tex.fx("snow_blob")
	var blobs: Array = []
	for y in w.h:
		for x in w.w:
			var i := y * w.w + x
			if s.outdoor.size() == w.w * w.h and s.outdoor[i] == 0:
				continue
			# сглаживание: половина своей клетки + половина среднего по соседям
			var sum := 0
			var n := 0
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w.w and ny < w.h:
					var ni := ny * w.w + nx
					if s.outdoor.size() != w.w * w.h or s.outdoor[ni] == 1:
						sum += int(s.snow[ni])
						n += 1
			var v := int(s.snow[i])
			if n > 0:
				v = int(v * 0.6 + float(sum) / n * 0.4)
			var r := Rect2(x * T, y * T, T, T)
			if v >= 170:
				# сплошной снег — фактурная клетка
				draw_texture_rect(tex[WorldView.vhash(x, y) % 4], r, false)
			elif v > 6:
				# тонкий слой или край протоптанной дорожки — мягкое пятно
				var a := clampf(float(v) / 170.0, 0.12, 1.0)
				blobs.append([r.get_center(), a])
			elif _ice and s.outdoor.size() == w.w * w.h and s.outdoor[i] == 1 and w.ground[i] != World.Ground.GRASS:
				draw_texture_rect(ice_t, r, false, Color(1, 1, 1, 0.45))
	var bs := T * 1.7
	for bl in blobs:
		draw_texture_rect(blob, Rect2(bl[0] - Vector2(bs, bs) * 0.5, Vector2(bs, bs)), false, Color(1, 1, 1, float(bl[1])))
	# сугробы по краю участка зимой
	if s.snow_avg > 60.0:
		var pr := w.plot
		for x2 in range(pr.position.x, pr.end.x):
			for yy in [pr.position.y, pr.end.y - 1]:
				var i2 := w.idx(Vector2i(x2, yy))
				if s.snow[i2] > 120:
					draw_circle(Vector2(x2 * T + T * 0.5, yy * T + T * 0.6), T * 0.45, Color(0.95, 0.97, 1.0, 0.85))
