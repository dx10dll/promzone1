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
var lamps: Array[PointLight2D] = []   ## 1.55: больше не используется — свет ламп рисует NightGlow дешёвыми пятнами (без PointLight2D)
var spots: Array[Dictionary] = []     ## светильники: {id, pos, r, col, dark}
var street: PackedVector2Array = []   ## уличные фонари
var glow := NightGlow.new()
var glow_layer := CanvasLayer.new()
var _rev := -1
var night := 0.0


func setup(s: Sim, root: Node2D, beam_parent: Node2D) -> void:
	sim = s
	world_root = root
	root.add_child(tint)
	beams.sim = s
	beam_parent.add_child(beams)
	# 1.55: пятна света — на своём слое, который следует за камерой, но не темнеет вместе с миром
	glow_layer.layer = 1
	glow_layer.follow_viewport_enabled = true
	add_child(glow_layer)
	glow.dn = self
	glow.sim = s
	glow_layer.add_child(glow)


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
	beams.set_alpha((1.0 - night) * (1.0 if t > sr + 30.0 and t < ss + 30.0 else 0.0) * (0.5 if sim.season.is_snowing() else 1.0))


## Положения уличных фонарей: вдоль тротуара у дороги и вдоль боковых заборов участка.
static func street_lamp_points(w: World) -> PackedVector2Array:
	var out := PackedVector2Array()
	for x in range(2, w.w, 9):
		out.append(Vector2(x * T, w.sidewalk_row * T + 10.0))
	for y in range(w.plot.position.y + 4, w.plot.end.y - 2, 9):
		out.append(Vector2((w.plot.position.x - 0.5) * T, y * T))
		out.append(Vector2((w.plot.end.x + 0.5) * T, y * T))
	return out


## Горит ли светильник сейчас (подключён и включён).
func lamp_lit(sp: Dictionary) -> bool:
	return bool(sim.power.lamp_on.get(int(sp["id"]), false))


## Яркость пятна света 0–1 при текущей ночи (для теста и NightGlow).
func spot_alpha(sp: Dictionary) -> float:
	if not lamp_lit(sp):
		return 0.0
	return clampf(night * 0.62 + (0.2 if bool(sp["dark"]) else 0.0), 0.0, 0.9)


## Список светильников (горят, если подключены и темно) и уличных фонарей — данные для NightGlow.
func _rebuild_lamps() -> void:
	spots.clear()
	for t: Thing in sim.things.values():
		if not t.built or t.kind() != "light":
			continue
		var col := Color("#ffe2a8")
		if t.def_id == "lamp_tube":
			col = Color("#e8f2ff")
		elif t.def_id == "lamp_drl":
			col = Color("#dfe8ff")
		var r := sim.rooms.room_at(t.cell)
		spots.append({"id": t.id, "pos": (Vector2(t.cell) + Vector2(0.5, 0.5)) * T, "r": float(t.def().get("light_r", 3.0)),
			"col": col, "dark": r != null and r.windows == 0})
	street = street_lamp_points(sim.world)
	glow.queue_redraw()
	beams.queue_redraw()
