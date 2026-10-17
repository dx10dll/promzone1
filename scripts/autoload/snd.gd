extends Node
## Звук: шины «Музыка», «Звуки», «Окружение»; короткие эффекты (в том числе в точке мира),
## музыка с плейлистом и плавной сменой, фоновые петли с плавной громкостью.
## Все звуки синтезированы tools/gen_sounds.py и лежат в assets/sound.

const BUSES := ["Music", "SFX", "Ambient"]
const LOOPS := ["m_", "amb_"]

var _cache: Dictionary = {}
var _pool: Array[AudioStreamPlayer] = []
var _pool2d: Array[AudioStreamPlayer2D] = []
var _music := AudioStreamPlayer.new()
var _music_next := ""
var _music_fade := 0.0
var playlist: Array = []
var _pl_i := 0
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
	_music.bus = "Music"
	add_child(_music)
	_music.finished.connect(_on_music_end)
	apply_volumes()


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
	var map := {"Music": "vol_music", "SFX": "vol_sfx", "Ambient": "vol_amb"}
	for b in map.keys():
		var i := AudioServer.get_bus_index(b)
		if i >= 0:
			var v := float(st.get(map[b], 0.7))
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
			p.global_position = pos
			p.volume_db = vol_db
			p.pitch_scale = randf_range(0.93, 1.07)
			p.play()
			return


# ---------------------------------------------------------------- музыка

func set_playlist(names: Array) -> void:
	playlist = names
	_pl_i = 0
	if names.is_empty():
		music("")
	else:
		music(str(names[0]))


func music(name: String) -> void:
	if name == _current_music():
		return
	_music_next = name
	_music_fade = 1.0 if _music.playing else 0.0


func _current_music() -> String:
	if _music.stream == null or not _music.playing:
		return ""
	return _music.stream.resource_path.get_file().get_basename()


func _on_music_end() -> void:
	if playlist.size() > 1:
		_pl_i = (_pl_i + 1) % playlist.size()
		get_tree().create_timer(12.0).timeout.connect(func() -> void:
			if not _music.playing and not playlist.is_empty():
				_start_music(str(playlist[_pl_i])))
	elif playlist.size() == 1:
		get_tree().create_timer(8.0).timeout.connect(func() -> void:
			if not _music.playing and not playlist.is_empty():
				_start_music(str(playlist[0])))


func _start_music(name: String) -> void:
	if name == "":
		_music.stop()
		return
	_music.stream = stream(name)
	_music.volume_db = -6.0
	_music.play()


# ---------------------------------------------------------------- фоновые петли

## Целевая громкость фоновой петли (0 — выключить), меняется плавно.
func ambient(name: String, target: float) -> void:
	if not _amb.has(name):
		if target <= 0.001:
			return
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
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
	# смена музыки: затухание старой, затем новая
	if _music_next != "" or (_music_fade > 0.0 and _music_next == ""):
		if _music.playing and _music_fade > 0.0:
			_music_fade -= delta * 0.7
			_music.volume_db = lerpf(-40.0, -6.0, clampf(_music_fade, 0.0, 1.0))
			if _music_fade <= 0.0:
				_music.stop()
		if not _music.playing or _music_fade <= 0.0:
			var nx := _music_next
			_music_next = ""
			_music_fade = 0.0
			if nx != "":
				_start_music(nx)
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
