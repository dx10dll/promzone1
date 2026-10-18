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
## 1.29: голоса — при сильном приближении слышно, как люди в кадре болтают, ругаются, смеются
## (неразборчивый «бубнёж», по очереди, не больше трёх голосов сразу); у людной столовой и курилки — гомон.

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

## 1.29: голоса
const MAX_VOICES := 3
const CROWD_ROOMS := ["canteen", "restroom"]
var voices: Array[AudioStreamPlayer2D] = []
var _voice_who: Array[int] = []      ## кто сейчас говорит в каждом плеере (-1 — никто)
var _vnext: Dictionary = {}          ## id человека -> когда ему можно заговорить снова (часы _vclock)
var _vlast: Dictionary = {}          ## id -> последняя реплика (чтобы не повторяться)
var _vclock := 0.0
var _vrng := RandomNumberGenerator.new()
var _crowd: AudioStreamPlayer2D

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
	_vrng.randomize()
	for i2 in MAX_VOICES:
		var vp := AudioStreamPlayer2D.new()
		vp.bus = "People"
		vp.max_distance = 2200.0
		vp.attenuation = 1.0
		add_child(vp)
		voices.append(vp)
		_voice_who.append(-1)
	_crowd = AudioStreamPlayer2D.new()
	_crowd.bus = "People"
	_crowd.stream = Snd.stream("v_crowd")
	_crowd.max_distance = 1800.0
	_crowd.attenuation = 1.2
	_crowd.volume_db = -60.0
	add_child(_crowd)
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
	_voices(running, center, z)
	_crowd_murmur(running, center, z)
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


# ---------------------------------------------------------------- 1.29: голоса

## Часть мира, видимая на экране.
func _view_rect(center: Vector2, z: float) -> Rect2:
	var sz := get_viewport_rect().size / maxf(z, 0.05)
	return Rect2(center - sz * 0.5, sz)


## С кем человек разговаривает (-1 — ни с кем, например ведёт инструктаж).
func _partner(w: Worker) -> int:
	if w.task and w.task.kind == "social":
		return int(w.task.data.get("other", -1))
	for e: Dictionary in sim.social.events:
		if int(e["a"]) == w.id:
			return int(e["b"])
		if int(e["b"]) == w.id:
			return int(e["a"])
	return -1


func _voice_clip(w: Worker) -> String:
	var pool := Voices.pool(w)
	if (w.bubble == "laugh" and _vrng.randf() < 0.45) or ((pool == Voices.OLD_M or pool == Voices.OLD_F) and _vrng.randf() < 0.35):
		pool = Voices.TALK_F if w.female else Voices.TALK_M      # смеются, но и говорят; у пожилых — и обычный голос
	# «свои» две реплики из набора, чередуются; изредка — любая другая
	var k := (w.id * 7 + 3) % pool.size()
	var pick := str(pool[k])
	if pool.size() > 1:
		var alt := str(pool[(k + 1 + w.id % maxi(1, pool.size() - 1)) % pool.size()])
		if pick == str(_vlast.get(w.id, "")) or _vrng.randf() < 0.4:
			pick = alt
		if _vrng.randf() < 0.15:
			pick = str(pool[_vrng.randi() % pool.size()])
	_vlast[w.id] = pick
	return pick


func _voices(running: bool, center: Vector2, z: float) -> void:
	_vclock += 0.25
	var on := running and z >= Voices.ZOOM
	var speaking := {}
	for i in MAX_VOICES:
		var vp := voices[i]
		if not vp.playing:
			_voice_who[i] = -1
		elif not on:
			vp.volume_db -= 5.0
			if vp.volume_db < -40.0:
				vp.stop()
				_voice_who[i] = -1
		if _voice_who[i] >= 0:
			speaking[_voice_who[i]] = true
			var ws := sim.get_worker(_voice_who[i])
			if ws:
				vp.global_position = ws.pos * T + Vector2(0, -20)
	if not on:
		return
	var view := _view_rect(center, z).grow(-16.0)
	var half := view.size.length() * 0.5
	var cands: Array = []
	for w in sim.workers:
		if not Voices.is_talking(w):
			continue
		var wp := w.pos * T
		if not view.has_point(wp):
			continue
		cands.append([wp.distance_to(center), w])
	if cands.is_empty():
		return
	cands.sort_custom(func(a: Array, b: Array) -> bool: return float(a[0]) < float(b[0]))
	for c: Array in cands:
		var free := _voice_who.find(-1)
		if free < 0:
			break
		var w2: Worker = c[1]
		if speaking.has(w2.id):
			continue
		if not _vnext.has(w2.id):            # только начали — заговорят не сразу
			_vnext[w2.id] = _vclock + _vrng.randf_range(0.0, 1.2)
			continue
		if float(_vnext[w2.id]) > _vclock:
			continue
		var mate := _partner(w2)
		var loud := w2.bubble in ["argue", "fight"]
		if mate >= 0 and speaking.has(mate) and not loud:
			continue                          # собеседник ещё говорит — ждём
		var clip := _voice_clip(w2)
		var st := Snd.stream(clip)
		if st == null:
			continue
		var vp2 := voices[free]
		vp2.stream = st
		vp2.pitch_scale = Voices.pitch(w2) * _vrng.randf_range(0.97, 1.03)
		vp2.global_position = w2.pos * T + Vector2(0, -20)
		vp2.volume_db = Voices.db(z, float(c[0]) / maxf(half, 1.0), loud)
		vp2.play()
		_voice_who[free] = w2.id
		speaking[w2.id] = true
		var ln := st.get_length() / vp2.pitch_scale
		# по очереди: собеседник отвечает после короткой паузы, в ссоре — перебивает
		_vnext[w2.id] = _vclock + ln + _vrng.randf_range(1.0, 3.0)
		if mate >= 0 and not speaking.has(mate):
			var reply := _vclock + (ln * _vrng.randf_range(0.45, 0.8) if loud else ln + _vrng.randf_range(0.15, 0.6))
			_vnext[mate] = reply
	if _vnext.size() > 200:                  # забыть тех, кто давно молчит
		for id: int in _vnext.keys():
			if float(_vnext[id]) < _vclock - 60.0:
				_vnext.erase(id)
				_vlast.erase(id)


## Где сейчас людная компания: столовая или комната отдыха с четырьмя и больше людьми,
## или курилка, где курят четверо. Возвращает [точка, сколько людей] или пусто.
func crowd_spot(center: Vector2) -> Array:
	var occ := {}
	var smokers: Array[Worker] = []
	for w in sim.workers:
		if not w.present:
			continue
		if w.anim == "smoke":
			smokers.append(w)
		var r := sim.rooms.room_at(w.cell())
		if r and r.type in CROWD_ROOMS:
			occ[r.id] = int(occ.get(r.id, 0)) + 1
	var best: Array = []
	var bd := INF
	for r2 in sim.rooms.list:
		var cnt := int(occ.get(r2.id, 0))
		if cnt < 4:
			continue
		var rr := Rect2(Vector2(r2.rect.position) * T, Vector2(r2.rect.size) * T)
		var p := Vector2(clampf(center.x, rr.position.x, rr.end.x), clampf(center.y, rr.position.y, rr.end.y))
		if p.distance_to(center) < bd:
			bd = p.distance_to(center)
			best = [p, cnt]
	for s0: Worker in smokers:
		var near := 0
		for s1: Worker in smokers:
			if s0.pos.distance_to(s1.pos) < 4.0:
				near += 1
		var sp := s0.pos * T
		if near >= 4 and sp.distance_to(center) < bd:
			bd = sp.distance_to(center)
			best = [sp, near]
	return best


func _crowd_murmur(running: bool, center: Vector2, z: float) -> void:
	var spot: Array = crowd_spot(center) if running and z >= 0.85 else []
	if not spot.is_empty() and _view_rect(center, z).grow(300.0).has_point(spot[0]):
		_crowd.global_position = spot[0]
		var target := lerpf(-24.0, -11.0, clampf((z - 0.85) / 1.4, 0.0, 1.0)) + minf(4.0, float(int(spot[1]) - 4))
		if not _crowd.playing:
			_crowd.volume_db = -45.0
			_crowd.play(_vrng.randf() * 5.0)
		_crowd.volume_db = move_toward(_crowd.volume_db, target, 2.0)
	elif _crowd.playing:
		_crowd.volume_db -= 3.0
		if _crowd.volume_db < -45.0:
			_crowd.stop()
