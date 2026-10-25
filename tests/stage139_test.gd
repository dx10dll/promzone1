extends SceneTree
## Тест версии 1.39 «Баланс начала игры»: на стандартной сложности («Рыночная экономика») в каждом
## сценарии игрок ставит цех 10×6, раздевалку и туалет (в гараже ещё склад 6×4 из обучения), обставляет
## цех станком и верстаком, нанимает людей — и деньги не уходят в минус до конца 7-го дня.
## Сложность меняет стартовый капитал; аванс первых двух недель возвращается при срыве.
## godot --headless --path . --audio-driver Dummy -s res://tests/stage139_test.gd

const P := preload("res://tests/econ_probe.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _initialize() -> void:
	Defs.load_all()
	# сложность: спокойная — больше денег, лихие — меньше, песочница — как выбрано в меню
	var g := {}
	for m: String in ["calm", "market", "wild"]:
		g[m] = Scenario.new_game("garage", "mech", m, 3).money
	check(float(g["calm"]) > float(g["market"]) and float(g["market"]) > float(g["wild"]), "гараж: спокойная %d > рыночная %d > лихие %d" % [int(g["calm"]), int(g["market"]), int(g["wild"])])
	check(float(g["wild"]) >= 400000.0, "даже в «Лихих девяностых» в гараже не меньше 400 тыс. ₽")
	var sb := Scenario.new_game("sandbox", "mech", "wild", 3, {"money": 1000000})
	check(is_equal_approx(sb.money, 1000000.0), "песочница: деньги из меню, без множителя сложности")
	# сметы: два помещения больше не съедают стартовый капитал гаража
	var gs := Scenario.new_game("garage", "mech", "market", 3)
	var two := Templates.cost(gs, "storage") + Templates.cost(gs, "workshop")
	check(two < gs.money * 0.5, "склад 6×4 + цех 10×6 = %d — меньше половины старта гаража" % int(two))
	# сценарии: 3 помещения + обстановка, неделя без минуса
	for scn: String in ["garage", "field", "sandbox"]:
		var r: Dictionary = P.run(scn, "market", 3, 7)
		var placed := 0
		var short := false
		for l: String in r["log"]:
			if l.contains("(ok)"):
				placed += 1
			if l.contains("Не хватает") or l.contains("не хватает"):
				short = true
		var need := 4 if scn == "garage" else 3
		check(placed == need and not short, "%s: поставлено помещений %d из %d, на всё хватило денег" % [scn, placed, need])
		check(float(r["min"]) >= 0.0, "%s: деньги до конца 7-го дня не уходили в минус (минимум %d ₽)" % [scn, int(r["min"])])
	# хардкор: после трёх помещений и станка — тоже без долгов в первые дни
	var rw: Dictionary = P.run("garage", "wild", 3, 3)
	check(float(rw["min"]) >= 0.0, "гараж, лихие девяностые: первые 3 дня без минуса (минимум %d ₽)" % int(rw["min"]))
	# аванс первых двух недель: берётся при приёме заказа и возвращается при срыве
	var s := Scenario.new_game("garage", "mech", "market", 3)
	for o0: Dictionary in s.orders.list.duplicate():
		if str(o0["status"]) == "active":
			s.orders.list.erase(o0)   # место под новый заказ
	var offer: Dictionary = s.orders.make_offer("bushing")
	s.orders.list.append(offer)
	check(not offer.is_empty(), "есть обычное предложение заказа")
	if not offer.is_empty():
		var m0 := s.money
		var err := s.orders.accept(int(offer["id"]), false)
		var adv := float(offer.get("early_adv", 0.0))
		var sum := float(offer["price"]) * int(offer["qty"])
		check(err == "" and absf(adv - sum * 0.3) <= 10.0 and is_equal_approx(s.money - m0, adv), "аванс 30%% при приёме: %d из %d ₽ %s" % [int(adv), int(sum), err])
		var m1 := s.money
		s.orders.fail(offer, "тест")
		check(is_equal_approx(m1 - s.money, adv), "срыв заказа: аванс возвращён (%d ₽)" % int(m1 - s.money))
	print("РЕЗУЛЬТАТ: ", "OK" if fails.is_empty() else "ОШИБКИ: %s" % str(fails))
	quit(0 if fails.is_empty() else 1)
