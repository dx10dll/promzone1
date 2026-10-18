extends SceneTree
## Тест версии 1.29 «Голоса»: файлы бубнежа на месте и загружаются, длина в пределах,
## выбор голоса по полу, возрасту и беседе, громкость растёт с приближением.
## godot --headless --path . -s res://tests/stage129c_test.gd

const CLIPS := ["v_talk_m1", "v_talk_m2", "v_talk_m3", "v_talk_m4", "v_talk_f1", "v_talk_f2", "v_talk_f3", "v_talk_f4",
	"v_talk_mo1", "v_talk_fo1", "v_argue_m1", "v_argue_m2", "v_argue_f1", "v_laugh_m1", "v_laugh_f1"]

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _len(n: String) -> float:
	var path := "res://assets/sound/%s.ogg" % n
	if not ResourceLoader.exists(path):
		return -1.0
	var st := load(path) as AudioStream
	return st.get_length() if st else -1.0


func _init() -> void:
	Defs.load_all()
	print("— файлы голосов")
	for n: String in CLIPS:
		var ln := _len(n)
		check(ln >= 1.4 and ln <= 4.2, "%s: %.2f с" % [n, ln])
	var lc := _len(Voices.CROWD)
	check(lc >= 5.0 and lc <= 8.0, "v_crowd (петля гомона): %.2f с" % lc)
	# все наборы реплик из Voices есть среди файлов
	for pl: Array in Voices.ALL:
		for c: String in pl:
			check(CLIPS.has(c), "реплика %s в списке файлов" % c)

	print("— выбор голоса")
	var w := Worker.new()
	w.id = 5
	w.present = true
	w.age = 30
	w.bubble = "chat"
	check(Voices.is_talking(w), "болтает — говорит")
	check(Voices.pool(w) == Voices.TALK_M, "мужчина — мужские реплики")
	w.female = true
	check(Voices.pool(w) == Voices.TALK_F, "женщина — женские реплики")
	w.age = 58
	check(Voices.pool(w) == Voices.OLD_F, "пожилая — пожилой голос")
	w.bubble = "argue"
	check(Voices.pool(w) == Voices.ARGUE_F, "ругается — крик")
	w.bubble = "laugh"
	check(Voices.pool(w) == Voices.LAUGH_F, "смеётся — смех")
	w.bubble = "food"
	check(not Voices.is_talking(w), "значок еды — молчит")
	w.bubble = "chat"
	w.present = false
	check(not Voices.is_talking(w), "ушёл с завода — молчит")
	var p1 := Voices.pitch(w)
	check(p1 == Voices.pitch(w) and p1 >= 0.9 and p1 <= 1.1, "свой постоянный тон голоса: %.3f" % p1)
	var w2 := Worker.new()
	w2.id = 6
	check(absf(Voices.pitch(w2) - p1) > 0.01, "у соседа тон другой")

	print("— громкость")
	check(Voices.db(2.4, 0.0, false) > Voices.db(1.1, 0.0, false), "ближе камера — громче")
	check(Voices.db(1.5, 0.0, false) > Voices.db(1.5, 1.0, false), "в середине экрана громче, чем с краю")
	check(Voices.db(1.5, 0.3, true) > Voices.db(1.5, 0.3, false), "ругань громче болтовни")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: OK")
	else:
		print("РЕЗУЛЬТАТ: ОШИБКИ (%d)" % fails.size())
		for ff in fails:
			print("  - " + ff)
	quit(0 if fails.is_empty() else 1)
