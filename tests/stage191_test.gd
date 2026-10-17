extends SceneTree
## Тест версии 1.9.1 «Обрыв»: раздельные статьи «налоги / штрафы / неустойки», перенос срока,
## пробная партия, потолок неустойки, поправка на пролёживание между переделами,
## предупреждение вместо штрафа малому бизнесу за первое нарушение.
## godot --headless --path . -s res://tests/stage191_test.gd

const S := preload("res://tests/setups.gd")

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _order(sim: Sim, p: String, qty: int, kind: String = "") -> Dictionary:
	var o := sim.orders.make_offer(p)
	o["qty"] = qty
	o["kind"] = kind
	o["trial"] = false
	o["penalty"] = Defs.b("late_penalty_per_day")
	sim.orders.list.append(o)
	sim.orders.accept(int(o["id"]), false)
	return o


func _init() -> void:
	Defs.load_all()
	var sim := Scenario.new_game("garage", "mech", "calm", 191)
	sim.story.enabled = false
	sim.progress.tutorial = -1

	print("— статьи расходов")
	check(Office.cat_of("Налог УСН 6% с выручки недели") == "taxes", "налог — в «Налоги»")
	check(Office.cat_of("Пени и штраф налоговой: учёт «на коленке»") == "fines", "пени налоговой — в «Штрафы проверок»")
	check(Office.cat_of("Штраф: Трудовая инспекция") == "fines", "штраф инспекции — в «Штрафы проверок»")
	check(Office.cat_of("Штраф трудовой инспекции по акту Н-1") == "fines", "штраф по акту Н-1 — в «Штрафы проверок»")
	check(Office.cat_of("Штраф: компенсация по рекламации") == "claims", "рекламация — в «Неустойки заказчикам»")
	check(Office.cat_of("Штраф: срыв госзаказа (возврат аванса и неустойка)") == "claims", "срыв госзаказа — в неустойки")
	check(Office.cat_of("Штраф: срыв партии по контракту, АО «Гидроузел»") == "claims", "срыв контракта — в неустойки")
	check(Office.CAT_ORDER.has("fines") and Office.CAT_ORDER.has("claims"), "новые статьи есть в отчёте")
	sim.spend(1000.0, "Штраф: Пожарный надзор")
	sim.spend(500.0, "Налог УСН 6% с выручки недели")
	var cats: Dictionary = sim.office.weeks[0]["cats"]
	check(float(cats.get("fines", 0.0)) <= -1000.0 and float(cats.get("taxes", 0.0)) <= -500.0, "в недельном отчёте штраф и налог — отдельно")

	print("— перенос срока")
	var o := _order(sim, "pin", 10)
	var dl0 := float(o["deadline"])
	var pr0 := int(o["price"])
	var rep0 := sim.reputation
	check(sim.orders.postpone_block(o) == "", "срок можно перенести")
	var err := sim.orders.postpone(int(o["id"]))
	check(err == "", "перенос: " + (err if err != "" else "ок"))
	check(float(o["deadline"]) >= dl0 + 2.0 * 1440.0, "срок сдвинулся минимум на 2 дня (%.1f дн.)" % ((float(o["deadline"]) - dl0) / 1440.0))
	var dday := int(float(o["deadline"]) / 1440.0) + 1
	check(sim.is_workday(dday), "новый срок — рабочий день")
	check(int(o["price"]) < pr0 and int(o["price"]) >= int(pr0 * 0.85), "скидка заказчику: %d → %d ₽" % [pr0, int(o["price"])])
	check(sim.reputation < rep0, "репутация чуть ниже")
	check(sim.orders.postpone(int(o["id"])) != "", "второй раз не переносится")
	var so := _order(sim, "pin", 4, "state")
	check(sim.orders.postpone_block(so) != "", "госзаказ не переносится")

	print("— пробная партия")
	check(not sim.orders.tried("bracket"), "кронштейн ещё не делали")
	var t := sim.orders.make_offer("bracket")
	var q0 := int(t["qty"])
	var l0 := int(t["lead"])
	t = sim.orders._maybe_trial(t)
	check(bool(t.get("trial", false)), "первый заказ на многооперационное изделие — пробный")
	check(int(t["qty"]) <= maxi(2, int(ceil(q0 * 0.4))) and int(t["lead"]) == l0 * 2, "малая партия (%d вместо %d) и двойной срок (%d дн.)" % [int(t["qty"]), q0, int(t["lead"])])
	check(float(t["penalty"]) == 0.0, "без неустойки")
	var simple := sim.orders._maybe_trial(sim.orders.make_offer("pin"))
	check(not bool(simple.get("trial", false)), "простые изделия — без пробной партии")
	sim.orders.list.append(t)
	sim.orders.accept(int(t["id"]), false)
	check(sim.orders.tried("bracket"), "после приёма изделие считается освоенным")
	var t2 := sim.orders._maybe_trial(sim.orders.make_offer("bracket"))
	check(not bool(t2.get("trial", false)), "второй заказ — обычный")
	# срыв пробной партии бьёт по репутации мягче
	sim.reputation = 50.0
	t["deadline"] = sim.minute - 10.0 * 1440.0
	sim.orders._t = 0.0
	sim.orders.tick(0.5)
	check(str(t["status"]) == "failed" and sim.reputation >= 46.0, "сорванная пробная партия: репутация %d (обычно −8)" % int(sim.reputation))

	print("— потолок неустойки")
	check(OrderBook.MAX_LATE_CUT == 0.3, "неустойка за просрочку — не больше 30%")
	so["deadline"] = sim.minute - 10.0 * 1440.0
	var m0 := sim.money
	var paid := float(so.get("paid_part", 0.0))
	sim.orders._t = 0.0
	sim.orders.tick(0.5)
	var fine := m0 - sim.money
	var expect := float(so["price"]) * int(so["qty"]) * 0.3 + paid
	check(str(so["status"]) == "failed" and absf(fine - expect) < 1.0, "срыв госзаказа: возврат аванса и 30%% неустойки (%d ₽)" % int(fine))

	print("— пролёживание между переделами")
	check(sim.office.route_latency("pin") == 0.0, "у пальца одна операция — без поправки")
	check(sim.office.route_latency("bracket") > 0.5, "у кронштейна (3 операции, покраска) поправка %.1f дн." % sim.office.route_latency("bracket"))
	check(sim.office.route_latency("drive_unit") > sim.office.route_latency("housing"), "у узла поправка больше, чем у его деталей")
	S.big_shop(sim)
	var base := float(sim.office.load_info()[0])
	var with_b := float(sim.office.load_info("bracket", 1)[0])
	check(with_b >= base + sim.office.route_latency("bracket") - 0.01, "оценка срока учитывает пролёживание (%.2f → %.2f дн.)" % [base, with_b])

	print("— предупреждение вместо штрафа")
	var sim2 := Scenario.new_game("garage", "mech", "calm", 192)
	sim2.story.enabled = false
	var ins := sim2.inspect
	check(ins.small_business(), "гараж — малый бизнес")
	var vio := {"key": "no_aid", "text": "Нет аптечки", "fine": 10000.0, "cell": [-1, -1]}
	var mm := sim2.money
	ins._act("labor", [vio], [], "")
	check(float(ins.history[0]["fine"]) == 0.0 and int(ins.history[0]["warns"]) == 1, "первое нарушение — предупреждение без штрафа")
	var l := sim2.story.get_letter_by_ev("inspection_act")
	check(not l.is_empty() and str(l["text"]).contains("4.1.1"), "в акте — ссылка на ст. 4.1.1 КоАП")
	sim2.story.resolve(int(l["id"]), 0)
	check(absf(sim2.money - mm) < 0.01, "денег не списали")
	ins._act("labor", [vio], [], "")
	check(float(ins.history[0]["fine"]) > 0.0, "повторно то же нарушение — уже штраф")
	var vio2 := {"key": "no_ppe", "text": "Нет СИЗ", "fine": 15000.0, "cell": [-1, -1]}
	sim2.progress.stage = 4
	check(not ins.small_business(), "среднее предприятие — уже не малый бизнес")
	ins._act("labor", [vio2], [], "")
	check(float(ins.history[0]["fine"]) > 0.0, "среднему предприятию штраф сразу")
	var d := ins.to_dict()
	var ins2 := Inspections.new(sim2)
	ins2.from_dict(JSON.parse_string(JSON.stringify(d)))
	check(not ins2.first_time("labor", "no_aid"), "предупреждения сохраняются")

	print("— сохранение заказов")
	var dd: Dictionary = JSON.parse_string(JSON.stringify(sim.to_dict()))
	var sim3 := Sim.from_dict(dd)
	var o3 := sim3.orders.get_order(int(o["id"]))
	check(bool(o3.get("moved", false)), "перенесённый срок сохраняется")

	print("РЕЗУЛЬТАТ: " + ("OK" if fails.is_empty() else "ОШИБКИ: " + ", ".join(fails)))
	quit(0 if fails.is_empty() else 1)
