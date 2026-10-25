extends SceneTree
## Тест версии 1.31 «Музыка»: десять новых пьес (есть, импортированы, длина, громкость), списки по настроению,
## зима и дождь, без повторов подряд, математика перекрёстного затухания и смена на границе фразы.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage131_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	_tracks()
	_moods()
	_no_repeats()
	_fade_math()
	await _live()
	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)


func _tracks() -> void:
	print("— пьесы")
	check(MusicDirector.NEW_131.size() >= 6, "новых пьес: %d" % MusicDirector.NEW_131.size())
	var total := 0
	for n: String in MusicDirector.NEW_131:
		var path := "res://assets/sound/%s.ogg" % n
		var imported := FileAccess.file_exists(path + ".import") and ResourceLoader.exists(path)
		var st: AudioStreamOggVorbis = load(path) as AudioStreamOggVorbis if imported else null
		var len_s := st.get_length() if st else 0.0
		check(st != null, "%s импортирована" % n)
		check(len_s >= 115.0 and len_s <= 215.0, "%s %s: %d:%02d" % [n, MusicDirector.TITLES.get(n, "?"), int(len_s / 60.0), int(len_s) % 60])
		check(st != null and not st.loop, "  %s не зациклена — кончается сама" % n)
		total += FileAccess.get_file_as_bytes(path).size()
	check(total < 20 * 1024 * 1024, "вес новых пьес %.1f МБ < 20 МБ" % (total / 1048576.0))
	for n2: String in MusicDirector.TITLES.keys():
		check(ResourceLoader.exists("res://assets/sound/%s.ogg" % n2), "%s есть" % n2)
		check(MusicDirector.PHRASE.has(n2), "  у %s задана длина фразы" % n2)
	for n3: String in MusicDirector.ALL + MusicDirector.MENU:
		check(MusicDirector.TITLES.has(n3), "у %s есть название" % n3)
	print("— громкость (ffmpeg volumedetect)")
	var means: Array[float] = []
	for n4: String in MusicDirector.TITLES.keys():
		var out: Array = []
		var code := OS.execute("ffmpeg", ["-hide_banner", "-i", ProjectSettings.globalize_path("res://assets/sound/%s.ogg" % n4),
			"-af", "volumedetect", "-f", "null", "-"], out, true)
		var txt := "" if out.is_empty() else str(out[0])
		if code != 0 or not txt.contains("mean_volume:"):
			print("  (ffmpeg недоступен — громкость не проверяем)")
			return
		var mean := txt.split("mean_volume:")[1].split("dB")[0].strip_edges().to_float()
		means.append(mean)
		check(absf(mean + 17.5) <= 1.5, "%s: средняя %.1f дБ (−17,5 ± 1,5)" % [n4, mean])
	var lo: float = means.min()
	var hi: float = means.max()
	check(hi - lo <= 3.0, "разброс громкости %.1f дБ ≤ 3" % (hi - lo))


func _moods() -> void:
	print("— списки по настроению")
	for m: String in MusicDirector.MOODS.keys():
		for w: bool in [false, true]:
			for r: bool in [false, true]:
				var pl := MusicDirector.for_mood(m, w, r)
				var ok := pl.size() >= 3
				for n: Variant in pl:
					ok = ok and ResourceLoader.exists("res://assets/sound/%s.ogg" % n)
				var dup := false
				for i in pl.size():
					dup = dup or pl.find(pl[i]) != i
				check(ok and not dup, "%s%s%s: %s" % [m, " зима" if w else "", " дождь" if r else "", ", ".join(pl)])
	check(MusicDirector.for_mood("evening", true, false)[0] == "music_winter", "зимой вечером первым — «Первый снег»")
	check(MusicDirector.for_mood("day", false, true)[0] == "music_rain", "в дождь первым — «Дождь над крышей цеха»")
	check(MusicDirector.for_mood("rush", true, true)[0] == "music_march", "в аврал — марш, хоть зима, хоть дождь")
	check(not MusicDirector.for_mood("night", true, false).has("music_winter"), "ночью зимняя тема не лезет")
	var reach := {}
	for m2: String in MusicDirector.MOODS.keys():
		for w2: bool in [false, true]:
			for r2: bool in [false, true]:
				for n2: Variant in MusicDirector.for_mood(m2, w2, r2):
					reach[n2] = true
	for n3: String in MusicDirector.NEW_131:
		check(reach.has(n3), "  %s звучит в игре" % n3)
	var g := Scenario.new_garage(131)
	g.story.enabled = false
	g.orders.list.clear()
	g.minute = float(g.day() - 1) * 1440.0 + 13.0 * 60.0
	check(MusicDirector.playlist(g, 0) == MusicDirector.for_mood("day", MusicDirector.is_winter(g), MusicDirector.is_rain(g)), "игра: днём — дневной список")
	g.season.rain_from = g.minute - 10.0
	g.season.rain_until = g.minute + 100.0
	check(MusicDirector.is_rain(g) and MusicDirector.playlist(g, 0)[0] == "music_rain", "игра: пошёл дождь — рояль первым")
	g.orders.list.append({"status": "active", "deadline": g.minute + 600.0, "product": "x"})
	check(MusicDirector.playlist(g, 0)[0] == "music_march", "игра: аврал — «Встречный план»")
	check(MusicDirector.playlist(g, 1) == MusicDirector.ALL, "«всё подряд»")
	check(MusicDirector.playlist(g, 2) == MusicDirector.CLASSIC and MusicDirector.CLASSIC.has("music_accwaltz"), "«только вальсы» — с новым вальсом")


func _no_repeats() -> void:
	print("— без повторов подряд")
	var rng := RandomNumberGenerator.new()
	rng.seed = 131
	var lists: Array = [MusicDirector.ALL, MusicDirector.CLASSIC, MusicDirector.MENU]
	for m: String in MusicDirector.MOODS.keys():
		lists.append(MusicDirector.for_mood(m, false, false))
		lists.append(MusicDirector.for_mood(m, true, true))
	var bad := 0
	var bad2 := 0
	for pl: Array in lists:
		var hist: Array = []
		for i in 300:
			var n := MusicDirector.pick_next(pl, hist, rng.randf())
			if not hist.is_empty() and n == hist.back():
				bad += 1
			if pl.size() >= 3 and hist.size() >= 2 and n == hist[hist.size() - 2]:
				bad2 += 1
			hist.append(n)
	check(bad == 0, "ни разу один трек дважды подряд (%d)" % bad)
	check(bad2 == 0, "и не через один, если есть из чего выбрать (%d)" % bad2)
	# смена настроения: «лицо» нового списка, но не то, что только что играло
	var moods: Array = MusicDirector.MOODS.keys()
	var hist2: Array = []
	var rep := 0
	for i2 in 400:
		var pl2 := MusicDirector.for_mood(str(moods[rng.randi() % moods.size()]), rng.randf() < 0.3, rng.randf() < 0.2)
		var n2 := MusicDirector.first_of(pl2, hist2, rng.randf()) if rng.randf() < 0.5 else MusicDirector.pick_next(pl2, hist2, rng.randf())
		if not hist2.is_empty() and n2 == hist2.back():
			rep += 1
		hist2.append(n2)
	check(rep == 0, "смены настроения тоже без повтора подряд (%d)" % rep)
	check(MusicDirector.first_of(["music_night", "music_calm", "music_calm"], [], 0.5) == "music_night", "первым — «лицо» списка")
	check(MusicDirector.first_of(["music_night", "music_calm", "music_calm"], ["music_night"], 0.0) != "music_night", "…если оно не звучало только что")
	check(MusicDirector.pick_next(["music_rain"], ["music_rain"], 0.3) == "music_rain", "из одного трека — он сам")


func _fade_math() -> void:
	print("— перекрёстное затухание")
	check(is_zero_approx(MusicFade.gain_in(0.0)) and is_equal_approx(MusicFade.gain_in(1.0), 1.0), "вход: 0 → 1")
	check(is_equal_approx(MusicFade.gain_out(0.0), 1.0) and is_zero_approx(MusicFade.gain_out(1.0)), "выход: 1 → 0")
	var pw_ok := true
	var mono := true
	var prev := -1.0
	for i in 101:
		var p := i / 100.0
		var a := MusicFade.gain_in(p)
		var b := MusicFade.gain_out(p)
		pw_ok = pw_ok and absf(a * a + b * b - 1.0) < 1e-5
		mono = mono and a >= prev
		prev = a
	check(pw_ok, "равная мощность: in² + out² = 1 на всём пути")
	check(mono, "громкость входящего только растёт")
	check(is_equal_approx(MusicFade.gain_in(0.5), MusicFade.gain_out(0.5)) and absf(MusicFade.gain_in(0.5) - 0.7071) < 0.001, "в середине оба по −3 дБ")
	check(is_zero_approx(MusicFade.gain_in(-1.0)) and is_equal_approx(MusicFade.gain_in(2.0), 1.0), "за пределами 0..1 — по краям")
	var f := MusicFade.new()
	check(not f.active and is_equal_approx(f.progress(), 1.0), "без смены — как после неё")
	f.start(7.0)
	check(f.active and is_zero_approx(f.progress()), "смена началась")
	for k in 35:
		f.step(0.1)
	check(f.active and absf(f.progress() - 0.5) < 0.01, "через 3,5 с — половина (%.2f)" % f.progress())
	for k2 in 40:
		f.step(0.1)
	check(not f.active and is_equal_approx(f.progress(), 1.0), "через 7 с — готово")
	check(MusicFade.XFADE >= 6.0 and MusicFade.XFADE <= 8.0, "обычная смена %.1f с (6–8)" % MusicFade.XFADE)
	print("— граница фразы")
	check(is_equal_approx(MusicFade.next_boundary(5.0, 8.0), 8.0), "5 с при фразе 8 с → 8 с")
	check(is_equal_approx(MusicFade.next_boundary(7.8, 8.0), 16.0), "7,8 с → 16 с (не впритык)")
	check(is_equal_approx(MusicFade.next_boundary(16.0, 8.0), 24.0), "ровно на границе → следующая")
	check(is_equal_approx(MusicFade.next_boundary(3.0, 0.0), 3.4), "без фразы — почти сразу")
	check(is_equal_approx(MusicFade.next_boundary(1.0, 40.0), 1.4), "фраза длиннее предела — не ждём")
	var worst := 0.0
	for n: String in MusicDirector.PHRASE.keys():
		for s in 50:
			var pos := s * 3.7
			var b2 := MusicFade.next_boundary(pos, MusicDirector.phrase(n))
			worst = maxf(worst, b2 - pos)
	check(worst <= MusicFade.MAX_WAIT, "смена настроения ждёт не дольше %.1f с (%.1f)" % [MusicFade.MAX_WAIT, worst])
	check(MusicDirector.LOOPED.is_empty(), "1.45: петель нет — все пьесы кончаются сами")
	check(MusicDirector.overlap("music_shop") < MusicFade.XFADE and MusicDirector.soft_end("music_shop"), "новая кончается сама — короткий стык")


## Живая проверка автозагрузки Snd (если она есть в режиме -s): два плеера, смена, громкость, приглушение.
func _live() -> void:
	print("— Snd: два плеера")
	await process_frame
	var snd := root.get_node_or_null("Snd")
	if snd == null:
		print("  (автозагрузки нет в режиме -s — пропуск)")
		return
	var mp: Array = snd.get("_mp")
	check(mp.size() == 2, "два плеера")
	var both_music := true
	for p: AudioStreamPlayer in mp:
		both_music = both_music and p.bus == "Music"
	check(both_music, "оба на шине «Музыка» — ползунок громкости действует на оба")
	var started: Array = []
	snd.connect("track_started", func(nm: String) -> void: started.append(nm))
	snd.call("set_playlist", ["music_rain", "music_calm"], 0.6)
	await process_frame
	check(str(snd.call("now_playing")) == "music_rain", "заиграл первый трек списка (%s)" % snd.call("now_playing"))
	check(started.has("music_rain"), "сигнал track_started — для надписи «Музыка: …»")
	snd.call("music", "music_calm", 0.6)
	await process_frame
	var both := (mp[0] as AudioStreamPlayer).playing and (mp[1] as AudioStreamPlayer).playing
	check(both, "во время смены звучат оба")
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 2200:
		await process_frame
	check(str(snd.call("now_playing")) == "music_calm", "после смены — новый трек")
	var n_on := 0
	for p2: AudioStreamPlayer in mp:
		n_on += 1 if p2.playing else 0
	check(n_on == 1, "старый плеер остановлен")
	snd.call("duck", true)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 1500:
		await process_frame
	check(float(snd.get("_duck")) < 0.5, "под паузой тише (%.2f)" % float(snd.get("_duck")))
	snd.call("set_playlist", [], 0.3)
	t0 = Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 700:
		await process_frame
	check(str(snd.call("now_playing")) == "", "пустой список — тишина")
