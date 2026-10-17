class_name SoundLayer
extends Node2D
## Звук игрового мира: петли работающих станков рядом с камерой (не больше шести),
## удары молотков на стройке, фон (день, ночь, ветер, дождь, огонь, гул забастовки),
## эффекты от событий симуляции.

const T := World.T
const MAX_MACHINES := 6
const PROC_SND := {"turning": "m_lathe", "milling": "m_mill", "drilling": "m_drill", "welding": "m_weld",
	"heat": "m_furnace", "paint": "m_paint", "assembly": "m_assembly", "test": "m_test"}

var game: GameMain
var sim: Sim
var players: Array[AudioStreamPlayer2D] = []
var _t := 0.0
var _h := 0.0
var _bark := 0.0


func setup(g: GameMain) -> void:
	game = g
	sim = g.sim
	for i in MAX_MACHINES:
		var p := AudioStreamPlayer2D.new()
		p.bus = "SFX"
		p.max_distance = 1100.0
		p.attenuation = 1.6
		add_child(p)
		players.append(p)
	sim.sfx.connect(_on_sfx)


func _on_sfx(name: String, cell: Vector2i) -> void:
	if cell.x >= 0:
		Snd.play_at(name, (Vector2(cell) + Vector2(0.5, 0.5)) * T, 0.0, 0.3)
	else:
		Snd.play(name, -2.0, 0.0, 0.3)


func _process(delta: float) -> void:
	_t -= delta
	if _t > 0.0:
		return
	_t = 0.25
	var running := game.is_running()
	var center := game.cam.get_screen_center_position()
	var z := game.cam.zoom.x
	var base_db := lerpf(-17.0, -5.0, clampf((z - 0.55) / 1.8, 0.0, 1.0))
	# станки рядом с центром экрана
	var cands: Array = []
	if running:
		for m in sim.things_of("machine"):
			if not m.working:
				continue
			var pos := (Vector2(m.cell) + Vector2(m.size()) * 0.5) * T
			var d := pos.distance_to(center)
			if d < 1100.0:
				cands.append([d, m, pos])
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for i in MAX_MACHINES:
		var p := players[i]
		if i < cands.size():
			var m: Thing = cands[i][1]
			var snd := "m_cnc" if m.is_cnc() else str(PROC_SND.get(m.process(), "m_lathe"))
			var s := Snd.stream(snd)
			if p.stream != s:
				p.stream = s
				p.play(randf() * 2.0)
			elif not p.playing:
				p.play(randf() * 2.0)
			p.global_position = cands[i][2]
			p.volume_db = base_db - (4.0 if snd == "m_lathe" else 0.0)
		elif p.playing:
			p.stop()
	if not running:
		_ambience(false)
		return
	# стройка: стук молотков у тех, кто строит в кадре
	_h -= 0.25 * game.speed
	if _h <= 0.0:
		_h = 1.1
		for w in sim.workers:
			if w.present and w.anim == "work" and w.task and w.task.kind in ["build_bp", "build_thing", "demolish", "repair", "fix", "lay_net"]:
				var wp := w.pos * T
				if wp.distance_to(center) < 700.0:
					Snd.play_at("hammer", wp, base_db + 2.0, 0.4)
					break
	# собаки иногда лают
	if not sim.progress.dogs.is_empty():
		_bark -= 0.25
		if _bark <= 0.0:
			_bark = randf_range(20.0, 60.0)
			var d0: Dictionary = sim.progress.dogs[randi() % sim.progress.dogs.size()]
			Snd.play_at("bark", Vector2(float(d0["x"]), float(d0["y"])) * T, base_db, 1.0)
	_ambience(true)


func _ambience(running: bool) -> void:
	var se := sim.season
	var day := sim.is_daylight()
	var winter := se.season_id() == "winter"
	Snd.ambient("amb_day", 0.5 if day and not winter else 0.0)
	Snd.ambient("amb_night", 0.45 if not day and se.season_id() != "winter" else 0.0)
	Snd.ambient("amb_wind", (0.55 if se.is_snowing() else 0.3) if winter else 0.0)
	Snd.ambient("amb_rain", 0.6 if se.is_raining() else 0.0)
	Snd.ambient("amb_fire", minf(0.9, 0.3 + sim.story.fires.size() * 0.08) if not sim.story.fires.is_empty() else 0.0)
	Snd.ambient("amb_crowd", 0.45 if bool(sim.story.strike.get("active", false)) and running else 0.0)


func _exit_tree() -> void:
	Snd.stop_ambient()
