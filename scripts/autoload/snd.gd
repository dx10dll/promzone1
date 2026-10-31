extends Node
## Звук: шины «Музыка», «Звуки», «Окружение»; короткие эффекты (в том числе в точке мира),
## музыка с плейлистом и плавной сменой (1.31: два плеера, перекрёстное затухание), фоновые петли с плавной громкостью.
## Все звуки синтезированы tools/gen_sounds.py и лежат в assets/sound.

const BUSES := ["Music", "SFX", "Ambient", "People", "City", "UI"]
## 1.25: громкость по категориям — шина и ключ настройки.
const BUS_VOL := {"Music": "vol_music", "SFX": "vol_sfx", "Ambient": "vol_env", "People": "vol_env", "City": "vol_env", "UI": "vol_ui"}   ## 1.29: окружение — одним ползунком
const CITY := ["train_horn", "car_horn", "van_horn", "factory_horn", "bark", "meow", "pigeon_coo", "pigeon_flap", "squeak",
	"amb_city", "amb_train", "amb_day", "amb_night", "amb_wind", "amb_rain"]
const PEOPLE := ["cough", "dishes", "door", "doorbell", "kettle", "phone", "injury", "amb_crowd"]
## 1.55: шина цеха с лёгкой реверберацией (шлёт в «Звуки»): станки и удары по металлу.
const SHOP_BUS := "Shop"
const SHOP_SND := ["grinder", "clank1", "clank2", "anvil", "hiss", "hammer"]
const LOOPS := ["m_", "amb_", "v_crowd"]

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool2d: Array[AudioStreamPlayer2D] = []
## 1.31: музыка — два плеера на шине «Музыка», смена перекрёстным затуханием равной мощности (MusicFade).
const MUSIC_DB := -6.0
var _mp: Array[AudioStreamPlayer] = []
var _ma := 0                      ## активный (входящий) плеер
var _mg: Array[float] = [0.0, 0.0]   ## громкость 0–1 каждого плеера
var _from_g := 0.0                ## громкость уходящего в начале смены
var _xf := MusicFade.new()
var _duck := 1.0                  ## приглушение (пауза, меню)
var _duck_t := 1.0
var _pending := ""                ## новый трек вступит на границе фразы текущего
var _pending_at := 0.0            ## …когда текущий дойдёт до этой секунды
var _prefer := ""                 ## «лицо» нового списка — сыграет следующим
var _gap_after := -1.0            ## тишина после трека с естественным концом (−1 — без тишины, сразу смена)
var _gap := 0.0
var _history: Array = []          ## последние сыгранные — без повторов подряд
var _mrng := RandomNumberGenerator.new()
var playlist: Array = []
signal track_started(name: String)   ## 1.28: заиграл новый трек
var _amb: Dictionary = {}        ## имя -> {player, target}
var _last: Dictionary = {}       ## имя -> время последнего проигрывания (чтобы не частить)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for b in BUSES:
		if AudioServer.get_bus_index(b) < 0:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, b)
			AudioServer.set_bus_send(i, "Master")
	if AudioServer.get_bus_index(SHOP_BUS) < 0:
		AudioServer.add_bus()
		var si := AudioServer.bus_count - 1
		AudioServer.set_bus_name(si, SHOP_BUS)
		AudioServer.set_bus_send(si, "SFX")
		var rv := AudioEffectReverb.new()
		rv.room_size = 0.42
		rv.damping = 0.65
		rv.spread = 0.8
		rv.hipass = 0.15
		rv.dry = 1.0
		rv.wet = 0.0
		AudioServer.add_bus_effect(si, rv)
	for i in 10:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_pool.append(p)
	for i2 in 10:
		var p2 := AudioStreamPlayer2D.new()
		p2.bus = "SFX"
		p2.max_distance = 1400.0
		p2.attenuation = 1.4
		add_child(p2)
		_pool2d.append(p2)
	for i3 in 2:
		var mp := AudioStreamPlayer.new()
		mp.bus = "Music"
		mp.volume_db = -80.0
		add_child(mp)
		_mp.append(mp)
	_mrng.randomize()
	apply_volumes()


## 1.25: на какую шину идёт звук: интерфейс, город, люди, остальное (станки и инструмент) — «Звуки».
static func bus_for(name: String) -> String:
	if name.begins_with("ui_") or name.begins_with("n_") or name in ["letter", "fanfare", "cash", "place"]:
		return "UI"
	if name in CITY:
		return "City"
	if name in PEOPLE or name.begins_with("v_"):   # 1.29: голоса
		return "People"
	if name.begins_with("amb_"):
		return "Ambient"
	if name in SHOP_SND or name.begins_with("m_"):
		return SHOP_BUS
	return "SFX"


func stream(name: String) -> AudioStream:
	if _cache.has(name):
		return _cache[name]
	var path := "res://assets/sound/%s.ogg" % name
	var s: AudioStream = null
	if ResourceLoader.exists(path):
		s = load(path)
		if s is AudioStreamOggVorbis:
			var loop := false
			for pre in LOOPS:
				if name.begins_with(pre):
					loop = true
			(s as AudioStreamOggVorbis).loop = loop
	_cache[name] = s
	return s


static func lin_db(v: float) -> float:
	return linear_to_db(maxf(0.0001, v))


func apply_volumes() -> void:
	var st: Dictionary = Game.settings
	AudioServer.set_bus_volume_db(0, lin_db(float(st.get("vol_master", 0.8))))
	AudioServer.set_bus_mute(0, float(st.get("vol_master", 0.8)) <= 0.001)
	for b in BUS_VOL.keys():
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			var v := float(st.get(BUS_VOL[b], 0.7))
			AudioServer.set_bus_volume_db(i, lin_db(v))
			AudioServer.set_bus_mute(i, v <= 0.001)


func _throttled(name: String, gap: float) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if now - float(_last.get(name, -99.0)) < gap:
		return true
	_last[name] = now
	return false


## Короткий звук без позиции (интерфейс, уведомления).
func play(name: String, vol_db: float = 0.0, pitch_var: float = 0.0, gap: float = 0.05) -> void:
	if _throttled(name, gap):
		return
	var s := stream(name)
	if s == null:
		return
	for p in _pool:
		if not p.playing:
			p.stream = s
			p.bus = bus_for(name)
			p.volume_db = vol_db
			p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
			p.play()
			return


## Звук в точке мира (стройка, поломка, фургон).
func play_at(name: String, pos: Vector2, vol_db: float = 0.0, gap: float = 0.08) -> void:
	if _throttled(name + str(int(pos.x / 64)) + str(int(pos.y / 64)), gap):
		return
	var s := stream(name)
	if s == null:
		return
	for p in _pool2d:
		if not p.playing:
			p.stream = s
			p.bus = bus_for(name)
			p.global_position = pos
			p.volume_db = vol_db
			p.pitch_scale = randf_range(0.93, 1.07)
			p.play()
			return


# ---------------------------------------------------------------- музыка

## Новый список сразу: текущий трек плавно уступает первому из списка (меню ↔ игра).
## Если текущий трек есть и в новом списке — он доигрывает.
func set_playlist(names: Array, fade: float = MusicFade.XFADE_MENU) -> void:
	playlist = names
	_pending = ""
	_prefer = ""
	_duck_t = 1.0
	if names.is_empty():
		music("", fade)
		return
	var cur := now_playing()
	if cur != "" and names.has(cur):
		return
	music(MusicDirector.first_of(names, _history, _mrng.randf()), fade)


## 1.28: мягкая смена списка — текущий трек доигрывает, если подходит; если нет — новый вступает
## на ближайшей границе музыкальной фразы (1.31), плавно.
func set_playlist_soft(names: Array) -> void:
	if names == playlist:
		return
	var old_head := "" if playlist.is_empty() else str(playlist[0])
	playlist = names
	if names.is_empty():
		return
	var cur := now_playing()
	if cur == "":
		if not _xf.active and _gap <= 0.0:
			music(MusicDirector.first_of(names, _history, _mrng.randf()))
		return
	if names.has(cur):
		if str(names[0]) != old_head and str(names[0]) != cur:
			_prefer = str(names[0])   # дождь, зима: следующим сыграет «лицо» списка
		return
	_pending = MusicDirector.first_of(names, _history, _mrng.randf())
	_pending_at = MusicFade.next_boundary(_mp[_ma].get_playback_position(), MusicDirector.phrase(cur))


func now_playing() -> String:
	if _mp.is_empty():
		return ""
	var p: AudioStreamPlayer = _mp[_ma]
	if p.stream == null or not p.playing:
		return ""
	return p.stream.resource_path.get_file().get_basename()


## 1.31: приглушить музыку (открыто меню паузы) — плавно.
func duck(on: bool) -> void:
	_duck_t = 0.4 if on else 1.0


## Сменить трек сейчас: перекрёстное затухание за fade секунд («» — затухнуть в тишину).
func music(name: String, fade: float = MusicFade.XFADE) -> void:
	if name != "" and name == now_playing() and not _xf.active:
		return
	_pending = ""
	var old := _ma
	var nw := 1 - _ma
	var old_on := _mp[old].playing and _mg[old] > 0.01
	_mp[nw].stop()
	_mg[nw] = 0.0
	_from_g = _mg[old] if _mp[old].playing else 0.0
	_ma = nw
	_gap = 0.0
	_xf.start(fade if old_on else MusicFade.FADE_IN)
	if name == "":
		_mp[nw].stream = null
		return
	_mp[nw].stream = stream(name)
	_mp[nw].volume_db = -80.0
	_mp[nw].play()
	_history.append(name)
	if _history.size() > 4:
		_history.pop_front()
	if name == _prefer:
		_prefer = ""
	_gap_after = _mrng.randf_range(2.0, 7.0) if MusicDirector.soft_end(name) and _mrng.randf() < 0.4 else -1.0
	track_started.emit(name)


func _next_name() -> String:
	if _prefer != "" and playlist.has(_prefer) and _prefer != now_playing():
		return _prefer
	return MusicDirector.pick_next(playlist, _history, _mrng.randf())


func _music_tick(delta: float) -> void:
	if _mp.is_empty():
		return
	_xf.step(delta)
	var pr := _xf.progress()
	_mg[_ma] = MusicFade.gain_in(pr)
	_mg[1 - _ma] = _from_g * MusicFade.gain_out(pr)
	if not _xf.active and _mp[1 - _ma].playing:
		_mp[1 - _ma].stop()
	_duck = move_toward(_duck, _duck_t, delta * 0.6)
	for i in 2:
		_mp[i].volume_db = MUSIC_DB + lin_db(_mg[i] * _duck) if _mg[i] > 0.0005 else -80.0
	var cur := _mp[_ma]
	if playlist.is_empty():
		return
	if _pending != "":
		if not cur.playing or cur.get_playback_position() >= _pending_at:
			music(_pending)
		return
	if _xf.active:
		return
	if cur.playing and cur.stream != null:
		var nm := now_playing()
		var left := cur.stream.get_length() - cur.get_playback_position()
		if _gap_after < 0.0 and left <= MusicDirector.overlap(nm):
			music(_next_name(), MusicDirector.overlap(nm))
		return
	# трек кончился сам — короткая тишина, потом следующий
	if _gap <= 0.0:
		_gap = maxf(0.05, _gap_after)
		_gap_after = -1.0
		return
	_gap -= delta
	if _gap <= 0.0:
		music(_next_name())


# ---------------------------------------------------------------- фоновые петли

## Целевая громкость фоновой петли (0 — выключить), меняется плавно.
func ambient(name: String, target: float) -> void:
	if not _amb.has(name):
		if target <= 0.001:
			return
		var p := AudioStreamPlayer.new()
		p.bus = bus_for(name)
		p.stream = stream(name)
		p.volume_db = -60.0
		add_child(p)
		p.play()
		_amb[name] = {"p": p, "t": target, "v": 0.0}
	_amb[name]["t"] = target


func stop_ambient() -> void:
	for k in _amb.keys():
		_amb[k]["t"] = 0.0


func _process(delta: float) -> void:
	_music_tick(delta)
	for k in _amb.keys():
		var a: Dictionary = _amb[k]
		var v := move_toward(float(a["v"]), float(a["t"]), delta * 0.5)
		a["v"] = v
		var p: AudioStreamPlayer = a["p"]
		p.volume_db = lin_db(v)
		if v <= 0.001 and float(a["t"]) <= 0.001:
			p.stream_paused = true
		elif p.stream_paused:
			p.stream_paused = false
