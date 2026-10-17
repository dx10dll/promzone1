class_name DayNight
extends Node
## Смена дня и ночи: затемнение мира, лампы в помещениях, полосы света из окон.

const T := World.T
const KEYS := [
	[0.0, Color(0.36, 0.40, 0.56)],
	[300.0, Color(0.36, 0.40, 0.56)],
	[390.0, Color(0.93, 0.80, 0.72)],
	[480.0, Color(1, 1, 1)],
	[1020.0, Color(1, 1, 1)],
	[1110.0, Color(1.0, 0.86, 0.72)],
	[1230.0, Color(0.36, 0.40, 0.56)],
	[1440.0, Color(0.36, 0.40, 0.56)],
]

var sim: Sim
var world_root: Node2D
var tint := CanvasModulate.new()
var beams := BeamLayer.new()
var lamps: Array[PointLight2D] = []
var _rev := -1
var night := 0.0


func setup(s: Sim, root: Node2D, beam_parent: Node2D) -> void:
	sim = s
	world_root = root
	root.add_child(tint)
	beams.sim = s
	beam_parent.add_child(beams)


static func sky(t: float) -> Color:
	return sky_keys(t, KEYS)


## Цвет неба по времени суток с учётом восхода и заката (зимой день короче).
static func sky_season(t: float, sunrise: float, sunset: float) -> Color:
	var night := Color(0.36, 0.40, 0.56)
	var keys := [
		[0.0, night],
		[sunrise - 90.0, night],
		[sunrise, Color(0.93, 0.80, 0.72)],
		[sunrise + 90.0, Color(1, 1, 1)],
		[sunset - 90.0, Color(1, 1, 1)],
		[sunset, Color(1.0, 0.86, 0.72)],
		[sunset + 120.0, night],
		[1440.0, night],
	]
	return sky_keys(t, keys)


static func sky_keys(t: float, keys: Array) -> Color:
	for i in range(keys.size() - 1):
		var a: Array = keys[i]
		var b: Array = keys[i + 1]
		if t >= float(a[0]) and t <= float(b[0]):
			var k := (t - float(a[0])) / maxf(1.0, float(b[0]) - float(a[0]))
			return (a[1] as Color).lerp(b[1] as Color, k)
	return Color.WHITE


func _process(_d: float) -> void:
	if sim == null:
		return
	var t := sim.tod()
	var sr := sim.season.sunrise()
	var ss := sim.season.sunset()
	var c := sky_season(t, sr, ss)
	night = clampf((1.0 - c.v) / (1.0 - 0.56), 0.0, 1.0)
	if sim.season.season_id() == "winter":
		c = c * Color(0.95, 0.97, 1.04)
	if sim.season.is_snowing():
		c = c * Color(0.9, 0.92, 0.96)
	tint.color = c
	if sim.thing_rev != _rev:
		_rev = sim.thing_rev
		_rebuild_lamps()
	for l in lamps:
		var on := true
		if l.has_meta("lamp"):
			on = bool(sim.power.lamp_on.get(int(l.get_meta("lamp")), false))
		var e := (night * 0.95 + (0.35 if l.has_meta("dark_room") else 0.0)) if on else 0.0
		l.energy = e
		l.visible = e > 0.02
	beams.set_alpha((1.0 - night) * (1.0 if t > sr + 30.0 and t < ss + 30.0 else 0.0) * (0.5 if sim.season.is_snowing() else 1.0))


## Свет от светильников (горят, если подключены и темно) и городские фонари вдоль улицы.
func _rebuild_lamps() -> void:
	for l in lamps:
		l.queue_free()
	lamps.clear()
	var glow := Tex.fx("glow")
	for t: Thing in sim.things.values():
		if not t.built or t.kind() != "light":
			continue
		var l := PointLight2D.new()
		l.texture = glow
		var rr := float(t.def().get("light_r", 3.0))
		l.texture_scale = rr * 0.62
		l.color = Color("#e8f2ff") if t.def_id == "lamp_tube" else (Color("#dfe8ff") if t.def_id == "lamp_drl" else Color("#ffe2a8"))
		l.position = (Vector2(t.cell) + Vector2(0.5, 0.5)) * T
		l.energy = 0.0
		l.set_meta("lamp", t.id)
		var r := sim.rooms.room_at(t.cell)
		if r and r.windows == 0:
			l.set_meta("dark_room", true)
		world_root.add_child(l)
		lamps.append(l)
	# уличные фонари вдоль тротуара
	var w := sim.world
	for x in range(2, w.w, 9):
		var l2 := PointLight2D.new()
		l2.texture = glow
		l2.texture_scale = 2.6
		l2.color = Color("#ffd98a")
		l2.position = Vector2(x * T, w.sidewalk_row * T + 10.0)
		world_root.add_child(l2)
		lamps.append(l2)
	beams.queue_redraw()
