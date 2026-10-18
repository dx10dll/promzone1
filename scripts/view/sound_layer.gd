class_name SoundLayer
extends Node2D
## Звук игрового мира: петли работающих станков рядом с камерой (не больше шести),
## удары молотков на стройке, фон (день, ночь, ветер, дождь, огонь, гул забастовки),
## эффекты от событий симуляции.
## 1.23: звук зависит от того, куда и насколько близко смотрит камера. У каждого вида помещений свой фон
## (столовая — гомон и посуда, бытовка — вода и шкафчики, контора — машинка, цех — гул, котельная — рокот);
## слышно ближайшее живое помещение, и тем громче, чем сильнее приближение. Рядом с камерой — случайные звуки
## по месту: болгарка, лязг, удары по металлу в цеху, посуда и чайник в столовой, телефон в конторе,
## хлопают двери, кашляют, скрипит тележка; голуби, кот, мыши. При отдалении слышен город, поезд.

const T := World.T
const MAX_MACHINES := 6
const PROC_SND := {"turning": "m_lathe", "milling": "m_mill", "drilling": "m_drill", "welding": "m_weld",
	"heat": "m_furnace", "paint": "m_paint", "assembly": "m_assembly", "test": "m_test", "casting": "m_casting", "stamping": "m_stamp"}

var game: GameMain
var sim: Sim
var players: Array[AudioStreamPlayer2D] = []
var _t := 0.0
var _h := 0.0
var _bark := 0.0
var zone_players: Dictionary = {}    ## петля -> AudioStreamPlayer2D
var _fx := 2.0
var _coo := 8.0
var _meow := 25.0
var _squeak := 6.0
var _train: AudioStreamPlayer2D

const ZONE_SND := {"canteen": "amb_canteen", "restroom": "amb_canteen", "locker": "amb_locker", "shower": "amb_locker",
	"wc": "amb_locker", "dorm": "amb_locker", "workshop": "amb_shop", "storage": "amb_shop", "toolroom": "amb_shop",
	"boiler_room": "amb_boiler", "compressor_room": "amb_boiler", "tech_room": "amb_boiler"}
const ZONE_LOOPS := ["amb_canteen", "amb_locker", "amb_office", "amb_shop", "amb_boiler"]


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
	for nm: String in ZONE_LOOPS:
		var zp := AudioStreamPlayer2D.new()
		zp.bus = "Ambient"
		zp.stream = Snd.stream(nm)
		zp.max_distance = 1000.0
		zp.attenuation = 1.2
		zp.volume_db = -60.0
		add_child(zp)
		zone_players[nm] = zp
	_train = AudioStreamPlayer2D.new()
	_train.bus = "City"
	_train.stream = Snd.stream("amb_train")
	_train.max_distance = 2600.0
	_train.attenuation = 1.0
	add_child(_train)
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
	_zones(running, center, z)
	_city(center, z)
	if not running:
		_ambience(false)
		return
	_spot_fx(center, z, base_db)
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


## Петля помещения по назначению (1.23).
static func zone_loop(type: String) -> String:
	if ZONE_SND.has(type):
		return str(ZONE_SND[type])
	if type.ends_with("office") or type in ["accounting", "pdo", "classroom", "medbay"]:
		return "amb_office"
	return ""


## Насколько приближена камера: 0 — далеко, 1 — вплотную.
static func zoom_k(z: float) -> float:
	return clampf((z - 0.45) / 1.6, 0.0, 1.0)


## Фон помещений: для каждого вида — самое «живое» помещение рядом с камерой.
func _zones(running: bool, center: Vector2, z: float) -> void:
	var occ := {}
	if running:
		for w in sim.workers:
			if not w.present:
				continue
			var r := sim.rooms.room_at(w.cell())
			if r:
				occ[r.id] = int(occ.get(r.id, 0)) + 1
	var best := {}          ## петля -> [оценка, точка, живость]
	if running:
		for r in sim.rooms.list:
			var nm := zone_loop(r.type)
			if nm == "":
				continue
			var live := float(occ.get(r.id, 0))
			if nm == "amb_shop":
				for ti: int in r.things:
					var t: Thing = sim.things.get(ti)
					if t and t.kind() == "machine" and t.working:
						live += 1.5
			if live <= 0.0:
				continue
			var rr := Rect2(Vector2(r.rect.position) * T, Vector2(r.rect.size) * T)
			var p := Vector2(clampf(center.x, rr.position.x, rr.end.x), clampf(center.y, rr.position.y, rr.end.y))
			var sc := minf(live, 5.0) / (1.0 + p.distance_to(center) / 250.0)
			if sc > float(best.get(nm, [0.0])[0]):
				best[nm] = [sc, p, live]
	var zk := zoom_k(z)
	for nm2: String in ZONE_LOOPS:
		var pl: AudioStreamPlayer2D = zone_players[nm2]
		if best.has(nm2):
			var b: Array = best[nm2]
			pl.global_position = b[1]
			var target := lerpf(-30.0, -5.0, zk) + lerpf(-10.0, 0.0, clampf(float(b[2]) / 5.0, 0.0, 1.0))
			if not pl.playing:
				pl.volume_db = -50.0
				pl.play(randf() * 4.0)
			pl.volume_db = move_toward(pl.volume_db, target, 3.0)
		elif pl.playing:
			pl.volume_db -= 4.0
			if pl.volume_db < -48.0:
				pl.stop()


## Город при отдалении и поезд на ветке.
func _city(center: Vector2, z: float) -> void:
	var zk := zoom_k(z)
	Snd.ambient("amb_city", lerpf(0.55, 0.08, zk))
	var cb := game.city
	if cb == null or cb.life == null:
		return
	var tp := cb.life.train_pos()
	if tp == Vector2.INF:
		if _train.playing:
			_train.stop()
		return
	_train.global_position = Vector2(clampf(center.x, tp.x - 300.0, tp.x + 300.0), tp.y)
	if not _train.playing:
		_train.play()
	_train.volume_db = lerpf(-8.0, -16.0, zk)
	if cb.life.horn and absf(tp.x - center.x) < 1400.0:
		cb.life.horn = false
		Snd.play_at("train_horn", tp, lerpf(-4.0, -12.0, zk), 2.0)


## Случайные звуки рядом с камерой — только когда приблизились.
func _spot_fx(center: Vector2, z: float, base_db: float) -> void:
	if z < 0.75:
		return
	var view := 380.0 / maxf(z, 0.5) + 200.0
	_fx -= 0.25
	if _fx <= 0.0:
		_fx = randf_range(1.0, 3.0) / clampf(z, 0.8, 2.0)
		var near: Array[Worker] = []
		var tries := mini(sim.workers.size(), 40)
		for i in tries:
			var w: Worker = sim.workers[randi() % sim.workers.size()]
			if w.present and (w.pos * T).distance_to(center) < view:
				near.append(w)
				if near.size() >= 4:
					break
		if not near.is_empty():
			var w2: Worker = near[randi() % near.size()]
			var snd := _spot_sound(w2)
			if snd != "":
				Snd.play_at(snd, w2.pos * T, base_db - 3.0, 0.6)
	# голуби: взлетают — хлопают крыльями, сидят — воркуют
	var pg_near := 0
	for pg: Dictionary in sim.fauna.pigeons:
		var pp := (pg["pos"] as Vector2) * T
		if pp.distance_to(center) > view:
			continue
		pg_near += 1
		if str(pg.get("st", "")) == "fly":
			if not bool(pg.get("snd", false)):
				pg["snd"] = true
				Snd.play_at("pigeon_flap", pp, base_db - 2.0, 0.4)
		else:
			pg["snd"] = false
	_coo -= 0.25
	if _coo <= 0.0:
		_coo = randf_range(6.0, 16.0)
		if pg_near > 0:
			var any: Dictionary = sim.fauna.pigeons[randi() % sim.fauna.pigeons.size()]
			Snd.play_at("pigeon_coo", (any["pos"] as Vector2) * T, base_db - 6.0, 2.0)
	var cat := sim.town.cat
	_meow -= 0.25
	if _meow <= 0.0:
		_meow = randf_range(25.0, 60.0)
		if cat and (cat.pos * T).distance_to(center) < view:
			Snd.play_at("meow", cat.pos * T, base_db - 3.0, 5.0)
	_squeak -= 0.25
	if _squeak <= 0.0:
		_squeak = randf_range(4.0, 10.0)
		for ms: Dictionary in sim.fauna.mice:
			var mp := (ms["pos"] as Vector2) * T
			if mp.distance_to(center) < view:
				Snd.play_at("squeak", mp, base_db - 6.0, 2.0)
				break


## Какой звук издаёт место, где стоит человек.
func _spot_sound(w: Worker) -> String:
	var r := sim.rooms.room_at(w.cell())
	var tp := r.type if r else ""
	var x := randf()
	var carry := w.carrying >= 0
	match zone_loop(tp):
		"amb_shop":
			if w.anim == "work":
				return ["grinder", "clank1", "anvil", "clank2", "hiss", "grinder"][randi() % 6]
			return "clank2" if carry else ("cart" if x < 0.3 else "")
		"amb_canteen":
			return "dishes" if x < 0.7 else ("kettle" if x < 0.8 else "cough")
		"amb_office":
			return "phone" if x < 0.35 else ("door" if x < 0.6 else "")
		"amb_locker":
			return "door" if x < 0.6 else ""
		"amb_boiler":
			return "hiss" if x < 0.5 else "clank1"
	return "cough" if x < 0.15 else ("cart" if carry and x < 0.5 else "")
