extends Node
## Снимок экрана для проверки графики: godot --path . res://tests/shot.tscn -- <сцена> <минута> <файл> [зум] [x] [y] [окно]

var args: PackedStringArray
var frames := 0
var target: Node
var wait := 40


func _ready() -> void:
	args = OS.get_cmdline_user_args()
	var scene := args[0] if args.size() > 0 else "game"
	if scene == "menu":
		target = load("res://scenes/main_menu.tscn").instantiate()
		add_child(target)
		wait = 60
		if args.size() > 6 and args[6] == "newgame":
			target.call_deferred("_show_new_game")
		if args.size() > 6 and args[6].begins_with("scene:"):
			var mm2: Node = target
			var si := int(args[6].substr(6))
			(func() -> void:
				mm2.set("scene_i", si)
				mm2.call("_show_scene")
				mm2.set("scene_t", 6.0)).call_deferred()
		if args.size() > 6 and args[6] == "newgame2":
			var mm: Node = target
			(func() -> void:
				mm.call("_show_new_game")
				mm.get("ng")["page"] = 2
				mm.call("_fill_new_game")).call_deferred()
		return
	Game.pending = "new"
	Game.pending_scn = "garage"
	Game.pending_profile = "mech"
	Game.pending_opts = {}
	Game.pending_seed = 4242
	Game.settings["tutorial_done"] = true
	if args.size() > 7 and args[7].begins_with("scn:"):
		var parts := args[7].split(":")
		Game.pending_scn = parts[1]
		Game.pending_profile = parts[2] if parts.size() > 2 else "mech"
		Game.pending_opts = {"tutorial": parts.size() > 3 and parts[3] == "tut"}
	if args.size() > 7 and args[7].begins_with("v113"):
		Game.pending_opts["flora"] = true
	if args.size() > 7 and args[7] == "v113L":
		Game.pending_opts["lots"] = true
	if args.size() > 7 and args[7] == "v118L":
		Game.pending_opts = {"lots": true, "flora": true}
	if args.size() > 7 and args[7] == "v115b":
		Game.pending_scn = "field"
		Game.pending_opts = {"flora": true}
	if args.size() > 7 and args[7].begins_with("v117"):
		Game.pending_scn = "field"
		Game.pending_opts = {"flora": true, "company": {"name": "Красный станочник", "emblem": {"shape": "shield", "symbol": "gear_hammer", "bg": "#7a1f1f", "fg": "#e2b73a", "rim": "#e2b73a", "text": ""}}}
	if args.size() > 7 and args[7] == "v116":
		Game.pending_scn = "sandbox"
		Game.pending_opts = {}
		TodoPanel.collapsed = true
	target = load("res://scenes/game.tscn").instantiate()
	add_child(target)
	var gm := target as GameMain
	if args.size() > 7 and args[7] == "expand":
		gm.sim.money += 400000.0
		var t := gm.tool
		t.set_mode("floor", 1)
		t._apply_floor(Rect2i(30, 9, 9, 10))
		t.set_mode("wall", 1)
		t._apply_wall(Rect2i(29, 8, 11, 12))
		t.set_mode("door", 3)
		t._apply_openings(Rect2i(29, 13, 1, 1))
		t.set_mode("window", 2)
		t._apply_openings(Rect2i(33, 8, 3, 1))
		t.set_mode("object", "lathe")
		t._place_object(Vector2i(32, 10))
		t.set_mode("object", "toilet")
		t._place_object(Vector2i(37, 17))
		t.set_mode("select")
		for o: Dictionary in gm.sim.orders.list:
			if str(o["status"]) == "offer":
				gm.sim.orders.accept(int(o["id"]), true)
				break
	if args.size() > 7 and args[7] == "s2":
		_setup_s2(gm.sim)
	if args.size() > 7 and args[7] == "s4":
		var S4 := preload("res://tests/setups.gd")
		S4.big_shop(gm.sim)
		S4.offices(gm.sim)
		for p in [["foreman", "manage", 6], ["chief", "manage", 7], ["accountant", "office", 5], ["buyer", "office", 5], ["dispatcher", "office", 5], ["hr", "office", 5], ["technologist", "engineering", 6]]:
			S4.hire(gm.sim, str(p[0]), str(p[1]), int(p[2]))
		S4.complex_orders(gm.sim, 10, {"bracket": 8, "housing": 3, "shaft": 6})
		gm.sim.office.policies["auto_accept"] = true
	if args.size() > 7 and args[7] == "s3":
		var S := preload("res://tests/setups.gd")
		S.big_shop(gm.sim)
		S.complex_orders(gm.sim, 12)
	var setup := args[7] if args.size() > 7 else ""
	if setup == "fauna":
		# 1.22: кот, голуби во дворе и в цеху, мыши в грязном помещении
		var fs := gm.sim
		if fs.town.cat == null:
			fs.town.cat = Cat.new(fs)
		var ct := fs.town.cat
		ct.pos = Vector2(15.5, 24.5)
		ct.state = "pounce"
		ct.until = fs.minute + 999.0
		ct.dir = 1
		var spots := [Vector2(17.6, 24.4), Vector2(18.4, 25.2), Vector2(19.3, 24.1), Vector2(20.1, 25.6), Vector2(21.6, 24.8)]
		for k3 in spots.size():
			fs.fauna.pigeons.append({"pos": spots[k3], "to": spots[k3], "st": "peck" if k3 % 2 == 0 else "walk", "until": fs.minute + 999.0, "dir": 1 if k3 % 2 == 0 else -1, "fly_t": 0.0, "inside": false})
		fs.fauna.pigeons.append({"pos": Vector2(19.5, 22.4), "to": Vector2(24.0, 20.0), "from": Vector2(16.0, 25.0), "st": "fly", "until": 0.0, "dir": 1, "fly_t": 0.0, "inside": false})
		fs.fauna.mice.append({"pos": Vector2(13.4, 22.7), "to": Vector2(13.4, 22.7), "room": 0, "st": "sit", "until": fs.minute + 999.0, "dir": -1})
		fs.fauna.mice.append({"pos": Vector2(10.6, 21.4), "to": Vector2(10.6, 21.4), "room": 0, "st": "sit", "until": fs.minute + 999.0, "dir": 1})
		fs.fauna.rng.seed = 1
		fs.fauna._t = 9999.0
	if setup == "bodies":
		# 1.22: все телосложения в ряд — спереди и сбоку
		var bs := gm.sim
		var brng := RandomNumberGenerator.new()
		brng.seed = 22
		var kinds := ["vthin", "thin", "normal", "stout", "strong", "fat", "vfat"]
		for row in 2:
			for k in kinds.size():
				for sx in 2:
					var bw := People.make(brng, "turner" if (k + sx) % 2 == 0 else "laborer")
					bw.id = bs.new_id()
					bw.female = sx == 1
					bw.look["fem"] = bw.female
					bw.look["body"] = kinds[k]
					bw.look["h"] = 1.0
					bw.present = true
					bw.pos = Vector2(12.5 + k * 2.0 + sx * 0.9, 22.5 + row * 2.6)
					bw.dir = "down" if row == 0 else "right"
					bw.controlled = true
					bw.activity = "Ждёт вашей команды"
					bs.workers.append(bw)
	if setup == "crisis":

		# 1.20: беды — долг по зарплате, касса в минусе, просроченный заказ
		var cs := gm.sim
		for wc in cs.workers:
			if not wc.visitor:
				wc.set_meta("arrears", 9000.0)
		cs.crisis.unpaid_since = cs.day() - 2
		cs.crisis.wage_credit_day = cs.day() - 20
		cs.crisis.arrears_quits = [cs.day() - 1]
		cs.crisis.debt_days = 3
		cs.money = -48000.0
	if setup == "upkeep":
		var SU := preload("res://tests/setups.gd")
		var su := gm.sim
		su.money += 500000.0
		su.progress.stage = maxi(su.progress.stage, 2)
		SU._box(su, Rect2i(2, 3, 9, 7), 3, Vector2i(10, 6))
		su.world.wall[su.world.idx(Vector2i(5, 3))] = World.W_WINDOW
		su.world.wall[su.world.idx(Vector2i(6, 3))] = World.W_WINDOW
		su.world.refresh_all()
		su.place_thing("sofa", Vector2i(3, 4), true, false)
		su.place_thing("aquarium", Vector2i(7, 4), true, false)
		su.place_thing("rug", Vector2i(4, 6), true, false)
		su.place_thing("palm", Vector2i(3, 8), true, false)
		su.place_thing("tv", Vector2i(9, 4), true, false)
		su.place_thing("bookcase", Vector2i(9, 8), true, false)
		su.place_thing("pennant", Vector2i(6, 8), true, false)
		su.place_thing("cooler", Vector2i(3, 6), true, false)
		su.place_thing("lamp_tube", Vector2i(6, 6), true, false)
		su.rooms.update()
		su.rooms.assign(su.rooms.room_at(Vector2i(5, 6)), "restroom")
		su.place_thing("chip_bin", Vector2i(25, 10), true, false)
		su.place_thing("band_saw", Vector2i(16, 16), true, false)
		su.place_thing("safety_stand", Vector2i(26, 14), true, false)
		Scenario.autowire(su)
		su.rooms.update()
		var shop := su.rooms.room_at(Vector2i(20, 12))
		if shop:
			for c in shop.cells:
				su.upkeep.add_dirt(c, float((c.x * 37 + c.y * 91) % 180))
		su.upkeep.bin_kg[su.things_of("chip_bin")[0].id] = 160.0
		SU.hire(su, "cleaner", "clean", 6)
		SU.hire(su, "laborer", "haul", 5)
	if setup == "crew":
		var SC2 := preload("res://tests/setups.gd")
		var sc := gm.sim
		SC2.big_shop(sc)
		SC2.complex_orders(sc, 20)
		# профком
		SC2._box(sc, Rect2i(2, 3, 6, 5), 3, Vector2i(7, 5))
		sc.world.wall[sc.world.idx(Vector2i(4, 3))] = World.W_WINDOW
		sc.world.refresh_all()
		sc.place_thing("office_desk", Vector2i(3, 5), true, false)
		sc.place_thing("union_board", Vector2i(6, 4), true, false)
		sc.place_thing("plant", Vector2i(3, 4), true, false)
		sc.rooms.update()
		sc.rooms.assign(sc.rooms.room_at(Vector2i(4, 5)), "union_office")
		sc.rooms.update()
		var cp2 := sc.place_thing("checkpoint", Vector2i(37, 22), true, false)
		sc.place_thing("camera", Vector2i(43, 12), true, false)
		sc.place_thing("camera", Vector2i(33, 11), true, false)
		sc.place_thing("days_board", Vector2i(30, 17), true, false)
		Scenario.autowire(sc)
		var gd := SC2.hire(sc, "guard", "security", 6)
		SC2.hire(sc, "laborer", "haul", 5)
		SC2.hire(sc, "turner", "turning", 4)
		sc.crew.put_sched("0", sc.crew.preset("order"))
		sc.crew.auto_form()
		for i in 25:
			sc.crew.on_op(sc.workers[i % sc.workers.size()])
		sc.crew._res_union_form({"lead": sc.workers[2].id}, 0)
		sc.crew.union["talk"] = sc.day()
		sc.crew._union_daily()
		sc.story.letters.clear()
		sc.crew.last_injury_day = 0
		sc.crew.cases = [{"id": 1, "wid": sc.workers[1].id, "name": sc.workers[1].full_name(), "prof": sc.workers[1].prof_name(), "day": 3,
			"until": 0.0, "causes": ["no_ppe", "worn"], "status": "done", "verdict": "вина предприятия", "fine": 12000.0, "cause": "work"}]
		sc.crew._log("Задержан Сергей Белов: Круг Ст45 (2 шт.)")
		sc.crew.caught_total = 1
		gd.shift = 0
	if setup == "town":
		var ST := preload("res://tests/setups.gd")
		var st := gm.sim
		ST.big_shop(st)
		ST.complex_orders(st, 20)
		var tile := int(Defs.floors["tile"]["id"])
		var lino := int(Defs.floors["lino"]["id"])
		ST._box(st, Rect2i(2, 14, 7, 6), tile, Vector2i(4, 14))
		ST._box(st, Rect2i(8, 14, 6, 6), lino, Vector2i(11, 14))
		ST._box(st, Rect2i(2, 20, 7, 6), tile, Vector2i(8, 22))
		st.world.wall[st.world.idx(Vector2i(2, 16))] = World.W_WINDOW
		st.world.wall[st.world.idx(Vector2i(13, 16))] = World.W_WINDOW
		st.world.refresh_all()
		st.place_thing("dining_table", Vector2i(3, 17), true, false)
		st.place_thing("chair", Vector2i(3, 18), true, false)
		st.place_thing("chair", Vector2i(4, 18), true, false)
		st.place_thing("chair", Vector2i(4, 16), true, false)
		st.place_thing("fridge", Vector2i(7, 15), true, false)
		st.place_thing("stove", Vector2i(5, 15), true, false)
		st.place_thing("serving_line", Vector2i(5, 17), true, false)
		st.place_thing("bunk_bed", Vector2i(9, 15), true, false)
		st.place_thing("bunk_bed", Vector2i(9, 17), true, false)
		st.place_thing("locker", Vector2i(12, 17), true, false)
		st.place_thing("plant", Vector2i(12, 15), true, false)
		st.place_thing("med_couch", Vector2i(3, 21), true, false)
		st.place_thing("med_cabinet", Vector2i(6, 21), true, false)
		st.place_thing("sink", Vector2i(7, 21), true, false)
		st.place_thing("radio_station", Vector2i(3, 15), true, false)
		st.place_thing("loudspeaker", Vector2i(6, 16), true, false)
		st.place_thing("cat_bowl", Vector2i(7, 18), true, false)
		Scenario.autowire(st)
		Scenario.autolight(st, false)
		Scenario.autopipe(st)
		st.world.cable_rev += 1
		st.rooms.update()
		st.rooms.assign(st.rooms.room_at(Vector2i(4, 16)), "canteen")
		st.rooms.assign(st.rooms.room_at(Vector2i(10, 16)), "dorm")
		st.rooms.assign(st.rooms.room_at(Vector2i(4, 22)), "medbay")
		st.rooms.update()
		ST.hire(st, "cook", "cook", 6)
		ST.hire(st, "nurse", "medicine", 6)
		for k in 3:
			var wa := People.make(st.rng, "laborer")
			wa.from_away = true
			st.add_worker(wa)
		st.town.assign_beds()
		st.town.kg_level = 1
		st.town.rel = 58.0
		st.town.on_letter("cat", {"name": "Шпиндель", "fur": "ginger", "female": false}, 0)
		st.town.cat.pos = Vector2(6.5, 17.5)
		st.story.letters.clear()
		st.power.tick(0.1)
	if setup == "v191":
		var S1 := preload("res://tests/setups.gd")
		var sv := gm.sim
		sv.money = maxf(sv.money, 900000.0)
		S1.offices(sv)
		S1.hire(sv, "accountant", "office", 5)
		sv.office.weeks.clear()
		# неделя назад и текущая — с новыми статьями
		for e: Array in [[180000.0, "Оплата: Вал × 12"], [-42000.0, "Металл: круг 40Х"], [-61000.0, "Зарплата за неделю"], [-10800.0, "Налог УСН 6% с выручки недели"],
				[-15000.0, "Штраф: Пожарный надзор"], [-4200.0, "Штраф: компенсация по рекламации"], [-8400.0, "Аренда"]]:
			sv.office.book(str(e[1]), float(e[0]))
		for e2: Array in [[96000.0, "Оплата: Палец × 30"], [-30500.0, "Зарплата за неделю"], [-5760.0, "Налог УСН 6% с выручки недели"], [-2500.0, "Электроэнергия"]]:
			sv.office.book(str(e2[1]), float(e2[0]))
		# заказы: пробная партия, срок сегодня (можно перенести), уже перенесённый
		var tr := sv.orders._maybe_trial(sv.orders.make_offer("bracket"))
		sv.orders.list.append(tr)
		sv.orders.accept(int(tr["id"]), false)
		var hot := sv.orders.make_offer("pin")
		hot["qty"] = 24
		sv.orders.list.append(hot)
		sv.orders.accept(int(hot["id"]), false)
		hot["deadline"] = sv.minute + 300.0
		var mv := sv.orders.make_offer("shaft")
		mv["qty"] = 8
		sv.orders.list.append(mv)
		sv.orders.accept(int(mv["id"]), false)
		sv.orders.postpone(int(mv["id"]))
		sv.story.letters.clear()
	if setup == "v112":
		var sz := gm.sim
		sz.money = maxf(sz.money, 900000.0)
		sz.rooms.update()
		sz.rooms.paint(Rect2i(24, 9, 5, 5), "storage")
		sz.rooms.paint(Rect2i(15, 15, 4, 3), "canteen")
		var gy := sz.world.plot.end.y - 3
		sz.set_area(Rect2i(sz.gate_x - 4, gy - 1, 3, 3), Logistics.A_UNLOAD)
		sz.set_area(Rect2i(sz.gate_x + 2, gy - 1, 3, 3), Logistics.A_SHIP)
		for k in 4:
			var it := sz.new_item("part", "pin", "ok")
			sz.put_on_ground(it, Vector2i(sz.gate_x + 2 + k % 2, gy))
		sz.story.letters.clear()
	if setup.begins_with("v113") and setup != "v113L":
		var s3 := gm.sim
		s3.money = maxf(s3.money, 3000000.0)
		s3.story.letters.clear()
		var gy3 := s3.world.plot.end.y - 3
		s3.set_area(Rect2i(s3.gate_x - 6, gy3 - 2, 4, 4), Logistics.A_UNLOAD)
		# чертёж кирпичной пристройки справа от бокса и штабели материала в зоне разгрузки
		for y in (range(9, 16) if setup != "v113p" else []):
			s3.place_wall_bp(Vector2i(34, y), World.W_BRICK)
		for x in (range(34, 41) if setup != "v113p" else []):
			s3.place_wall_bp(Vector2i(x, 8), World.W_BRICK)
		for y2 in (range(9, 15) if setup != "v113p" else []):
			for x2 in range(35, 40):
				s3.place_floor_bp(Vector2i(x2, y2), 1)
		var mats := [["bm_brick", 4], ["bm_brick", 3], ["bm_cement", 8], ["bm_cement", 5], ["bm_tile", 4], ["bm_window", 2], ["bm_door", 1], ["bm_panel", 6]]
		for k in mats.size():
			var cc := Vector2i(s3.gate_x - 6 + k % 4, gy3 - 2 + int(k / 4))
			for n in int(mats[k][1]):
				s3.put_on_ground(s3.new_item("bmat", str(mats[k][0]), "bmat"), cc)
		# кабель по чертежу от щита к пристройке
		for x3 in range(29, 34):
			s3.place_cable(Vector2i(x3, 17))
		# бортовой грузовик у ворот
		var vt := s3.spawn_vehicle("delivery")
		vt.body = "flatbed"
		vt.state = "parked"
		vt.x = vt.park_x
		for n2 in 6:
			s3.put_in_vehicle(s3.new_item("bmat", "bm_brick", "bmat"), vt)
		# дерево под спил
		for i in s3.world.w * s3.world.h:
			if s3.world.flora[i] != 0 and s3.world.in_plot(s3.world.cell_of(i)):
				s3.place_demolish(s3.world.cell_of(i))
				break
		if setup == "v113p":
			# техпомещение: подстанция, девять аккумуляторов, насосная
			var SP := preload("res://tests/setups.gd")
			SP._box(s3, Rect2i(36, 2, 9, 7), 4, Vector2i(40, 8))
			s3.rooms.update()
			s3.progress.all_open = true
			var kt := s3.place_thing("ktp", Vector2i(38, 4), true, false)
			for bc in [Vector2i(37, 3), Vector2i(38, 3), Vector2i(39, 3), Vector2i(40, 3), Vector2i(37, 4), Vector2i(40, 4), Vector2i(37, 5), Vector2i(40, 5), Vector2i(37, 6)]:
				var bt := s3.place_thing("battery", bc, true, false)
				bt.charge = 18.0 + float(bc.x % 3) * 5.0
			s3.place_thing("pump_station", Vector2i(42, 3), true, false)
			s3.rooms.fill(Vector2i(41, 6), "tech_room")
			for y in range(6, 12):
				s3.world.cable[s3.world.idx(Vector2i(39, y))] = 1
			s3.world.cable_rev += 1
			s3.world.refresh_all()
			s3.rooms.update()
			kt.enabled = true
		if setup == "v113z":
			# станок вне цеха (в зоне склада) и неполная столовая
			s3.rooms.paint(Rect2i(24, 9, 5, 5), "storage")
			s3.place_thing("drill", Vector2i(26, 11), true, false)
			s3.rooms.update()
	if setup == "v110" or setup == "v110a" or setup == "v111":
		var SA := preload("res://tests/setups.gd")
		var sa := gm.sim
		sa.money = maxf(sa.money, 1500000.0)
		SA.offices(sa)
		# новые кабинеты под заводоуправлением: три в ряд (двери в проход сверху) и юротдел под ними
		var cabs := [["sales_office", ["phone_stand"], Vector2i(1, 14), true], ["safety_office", ["safety_stand"], Vector2i(5, 14), true],
			["engineer_office", ["drawing_board", "doc_cabinet"], Vector2i(9, 14), true], ["legal_office", ["law_shelf", "plant"], Vector2i(1, 18), false]]
		for cb: Array in cabs:
			var o0: Vector2i = cb[2]
			var top: bool = cb[3]
			SA._box(sa, Rect2i(o0.x, o0.y, 5, 5), 3, Vector2i(o0.x + 3, o0.y if top else o0.y + 4))
		sa.world.refresh_all()
		for cb2: Array in cabs:
			var o1: Vector2i = cb2[2]
			sa.place_thing("office_desk", o1 + Vector2i(1, 1), true, false)
			var extra: Array = cb2[1]
			for j in extra.size():
				sa.place_thing(str(extra[j]), o1 + Vector2i(1 + j, 3), true, false)
		sa.rooms.update()
		for cb3: Array in cabs:
			sa.rooms.assign(sa.rooms.room_at((cb3[2] as Vector2i) + Vector2i(2, 2)), str(cb3[0]))
		sa.rooms.update()
		if setup == "v111":
			# кабинет директора справа от юротдела, ступени развития
			sa.money = maxf(sa.money, 2500000.0)
			SA._box(sa, Rect2i(5, 18, 5, 5), 3, Vector2i(7, 22))
			sa.world.refresh_all()
			sa.place_thing("director_desk", Vector2i(6, 19), true, false)
			sa.place_thing("plant", Vector2i(8, 21), true, false)
			sa.rooms.update()
			sa.rooms.assign(sa.rooms.room_at(Vector2i(7, 20)), "director_office")
			sa.rooms.update()
			for p1 in [["accountant", "office", 5], ["dispatcher", "office", 5], ["sales_manager", "office", 5], ["lawyer", "office", 6], ["hr", "office", 5]]:
				SA.hire(sa, str(p1[0]), str(p1[1]), int(p1[2]))
			sa.dev.done.assign(["city1", "city2", "fin2", "mkt3"])
			sa.dev.cur = "law3"
			sa.dev.cur_start = sa.minute - 2.0 * 1440.0
			sa.dev.cur_end = sa.minute + 4.6 * 1440.0
			if not sa.grants.offers().is_empty():
				sa.grants.take(str(sa.grants.offers()[0]["id"]))
			if OS.has_environment("SHOT_SEL"):
				DevTree.sel = OS.get_environment("SHOT_SEL")
		if setup == "v110":
			for p in [["accountant", "office", 5], ["dispatcher", "office", 5], ["sales_manager", "office", 5], ["safety_engineer", "engineering", 5], ["chief_engineer", "engineering", 6], ["lawyer", "office", 6]]:
				SA.hire(sa, str(p[0]), str(p[1]), int(p[2]))
			sa.office.all_depts = true
			sa.office.weeks.clear()
			for e: Array in [[210000.0, "Оплата: Вал × 14"], [-52000.0, "Металл: круг 40Х"], [-88000.0, "Зарплата за неделю"], [-12600.0, "Налог УСН 6% с выручки недели"], [-8400.0, "Аренда"]]:
				sa.office.book(str(e[1]), float(e[0]))
			for e2: Array in [[64000.0, "Оплата: Палец × 20"], [-44000.0, "Зарплата за неделю"], [-3840.0, "Налог УСН 6% с выручки недели"]]:
				sa.office.book(str(e2[1]), float(e2[0]))
		sa.story.letters.clear()
	if setup == "eng":
		var SE := preload("res://tests/setups.gd")
		var se := gm.sim
		se.money += 3000000.0
		se.progress.stage = maxi(se.progress.stage, 3)
		var ww := se.world
		# сварочный участок
		SE._box(se, Rect2i(30, 3, 10, 8), 1, Vector2i(34, 10))
		for wx in [33, 34]:
			ww.wall[ww.idx(Vector2i(wx, 3))] = World.W_WINDOW
		# покрасочная
		SE._box(se, Rect2i(30, 11, 10, 7), 1, Vector2i(39, 14))
		# компрессорная и котельная
		SE._box(se, Rect2i(40, 3, 6, 5), 1, Vector2i(42, 7))
		SE._box(se, Rect2i(40, 9, 6, 6), 1, Vector2i(42, 14))
		ww.refresh_all()
		var w1 := se.place_thing("weld_post", Vector2i(32, 5), true, false)
		se.place_thing("weld_post", Vector2i(32, 8), true, false)
		se.place_thing("assembly_table", Vector2i(35, 5), true, false)
		se.place_thing("extinguisher", Vector2i(38, 9), true, false)
		var fan := se.place_thing("vent_fan", Vector2i(38, 4), true, false)
		var h1 := se.place_thing("vent_hood", Vector2i(32, 5), true, false)
		var pbx := se.place_thing("paint_booth", Vector2i(32, 13), true, false)
		var h2 := se.place_thing("vent_hood", Vector2i(34, 13), true, false)
		se.place_thing("radiator", Vector2i(38, 6), true, false)
		se.place_thing("radiator", Vector2i(38, 16), true, false)
		var cp := se.place_thing("compressor", Vector2i(41, 4), true, false)
		var bl := se.place_thing("boiler", Vector2i(41, 10), true, false)
		se.place_thing("ppe_cabinet", Vector2i(25, 17), true, false)
		se.cons["ppe"] = 8.0
		se.rooms.update()
		se.rooms.assign(se.rooms.room_at(Vector2i(35, 7)), "workshop")
		se.rooms.assign(se.rooms.room_at(Vector2i(35, 15)), "workshop")
		se.rooms.assign(se.rooms.room_at(Vector2i(42, 5)), "compressor_room")
		se.rooms.assign(se.rooms.room_at(Vector2i(42, 12)), "boiler_room")
		Scenario.autolight(se, false)
		Scenario.autowire(se)
		Scenario.autopipe(se)
		for rad in se.things_of("radiator"):
			Scenario._route_layer(se, "pipe", [rad.cell])
		ww.pipe_rev += 1
		Scenario.autoline(se, "duct", fan.cell, [h1.cell, h2.cell])
		Scenario.autoline(se, "air", cp.cell, [pbx.inlet_cell(), se.things_of("machine").filter(func(m: Thing) -> bool: return m.def_id == "assembly_table")[0].inlet_cell()])
		se.rooms.update()
		SE.hire(se, "welder", "welding", 6)
		SE.hire(se, "welder", "welding", 4)
		SE.hire(se, "painter", "paint", 5)
		SE.hire(se, "assembler", "assembly", 5)
		se.season.start_month = 10
		se.season.temp_day = -6.0
		se.eng.milk_on = true
		w1.product = ""
		se.power.tick(0.1)
		se.eng._vent_update()
		se.eng._air_update()
		for mm in se.eng.workplaces():
			se.eng.sout_ids.append(mm.id)
		se.eng._finish_sout()
	if setup == "class":
		var SC := preload("res://tests/setups.gd")
		var sm := gm.sim
		sm.money += 300000.0
		SC._box(sm, Rect2i(2, 3, 8, 6), 3, Vector2i(9, 5))
		sm.world.wall[sm.world.idx(Vector2i(5, 3))] = World.W_WINDOW
		sm.world.wall[sm.world.idx(Vector2i(6, 3))] = World.W_WINDOW
		sm.world.refresh_all()
		sm.place_thing("school_desk", Vector2i(3, 6), true, false)
		sm.place_thing("school_desk", Vector2i(6, 6), true, false)
		sm.place_thing("chalkboard", Vector2i(4, 4), true, false)
		sm.place_thing("plant", Vector2i(8, 4), true, false)
		sm.place_thing("lamp_tube", Vector2i(5, 5), true, false)
		sm.rooms.update()
		sm.rooms.assign(sm.rooms.room_at(Vector2i(5, 6)), "classroom")
		sm.rooms.update()
		for i in 3:
			var nw := SC.hire(sm, ["turner", "laborer", "qc"][i], ["turning", "haul", "qc"][i], 2)
			sm.training.start_course(nw, ["turning", "milling", "qc"][i], "class")
		sm.training.ptu_sign()
		sm.training._add_rel(sm.workers[0], sm.workers[1], 50.0)
	if setup == "winter" or setup == "drama":
		_setup_s2(gm.sim)
		_winter(gm.sim, setup == "winter")
	if setup == "v115f":
		# 1.15: слесарь у верстака дорабатывает брак
		var SF := preload("res://tests/setups.gd")
		var ff := SF.hire(gm.sim, "fitter", "fitting", 7)
		ff.wage = People.wage_for(ff)
		for t5: Thing in gm.sim.things_of("storage"):
			if t5.def_id == "scrap_bin":
				for k6 in 4:
					var it6 := gm.sim.new_item("part", "bushing", "scrap")
					it6.step = 1
					gm.sim.put_in_thing(it6, t5, 0)
		Workplace.auto_assign(gm.sim)
	if setup == "v115b":
		# 1.15: строители с молотками — пол и стены будущего цеха рядом с бытовками
		var sb := gm.sim
		sb.money += 600000.0
		for y in range(17, 24):
			for x in range(22, 30):
				var cc := Vector2i(x, y)
				if x == 22 or x == 29 or y == 17 or y == 23:
					sb.place_wall_bp(cc, World.W_BRICK)
				else:
					sb.place_floor_bp(cc, 1)
	if setup == "v116":
		_setup_v116(gm.sim)
	if setup == "v117t":
		# готовые помещения: цех и склад заказаны с утра — к обеду строители уже поднимают стены
		gm.sim.money += 2000000.0
		for e7 in [["workshop", Vector2i(22, 12)], ["storage", Vector2i(35, 14)], ["locker", Vector2i(22, 22)]]:
			var er7 := Templates.place(gm.sim, str(e7[0]), e7[1])
			if er7 != "":
				print("v117t: ", e7[0], " ", er7)
		Scenario.hire_builders(gm.sim, 3)
	if setup == "v117p":
		# план будущего цеха: стены с воротами и окнами, пол, зоны цеха и склада, станки
		var pl := gm.sim.plan
		var hall := Rect2i(22, 10, 18, 12)
		for y in range(hall.position.y, hall.end.y):
			for x in range(hall.position.x, hall.end.x):
				var c := Vector2i(x, y)
				var edge := x == hall.position.x or x == hall.end.x - 1 or y == hall.position.y or y == hall.end.y - 1
				if edge:
					pl.add_wall(c, World.W_BRICK)
				else:
					pl.add_floor(c, 1)
		for x in [29, 30, 31]:
			pl.add_wall(Vector2i(x, 21), World.W_GATE)
		for x in [25, 26, 34, 35]:
			pl.add_wall(Vector2i(x, 10), World.W_WINDOW)
		pl.add_wall(Vector2i(22, 15), World.W_DOOR)
		pl.paint_zone(Rect2i(23, 11, 11, 10), "workshop")
		pl.paint_zone(Rect2i(34, 11, 5, 10), "storage")
		pl.add_obj("lathe", Vector2i(24, 12), 0)
		pl.add_obj("lathe_16k20", Vector2i(28, 12), 0)
		pl.add_obj("mill", Vector2i(24, 16), 0)
		pl.add_obj("drill", Vector2i(27, 16), 0)
		pl.add_obj("rack", Vector2i(35, 12), 0)
		pl.add_obj("rack", Vector2i(35, 14), 0)
		pl.add_obj("pallet", Vector2i(36, 18), 0)
		pl.add_obj("qc_table", Vector2i(30, 16), 0)
	var until := float(args[1]) if args.size() > 1 else 630.0
	var guard := 0
	while gm.sim.minute < until and guard < 200000:
		gm.sim.tick(0.5)
		guard += 1
	if setup == "drama":
		_drama(gm.sim)
	if setup == "winter":
		gm.sim.inspect.schedule("fire", gm.sim.minute, false, "")
		for e in 260:
			gm.sim.tick(0.5)
			if gm.sim.inspect.busy() and int(gm.sim.inspect.visit["i"]) >= 2:
				break
	if setup == "v115b":
		# значки над головой: кому-то в туалет и поесть, кому-то ещё и тоскливо
		var ws := gm.sim.workers
		if ws.size() > 0:
			ws[0].needs["bladder"] = 8.0
			ws[0].needs["food"] = 14.0
			ws[0].mood = 18.0
		if ws.size() > 1:
			ws[1].needs["rest"] = 10.0
		# крупно: двое строителей с молотками — лицом к нам и боком
		for q in [[2, Vector2(25.5, 25.6), "down"], [1, Vector2(27.5, 25.6), "right"]]:
			if ws.size() > int(q[0]):
				var wq: Worker = ws[int(q[0])]
				wq.pos = q[1]
				wq.dir = str(q[2])
				wq.prop = "hammer"
				wq.anim = "work"
				wq.carrying = -1
	if setup == "v116":
		# станки с ЧПУ и печи работают сами — на снимке показываем их в деле
		for m6 in gm.sim.things_of("machine"):
			if (m6.is_cnc() or m6.is_batch()) and not m6.working:
				for p6 in ["pin", "bushing", "shaft", "housing", "axle", "gear", "spline_shaft"]:
					if m6.fits_part(p6) and Defs.route(p6).any(func(o6: Dictionary) -> bool: return str(o6["op"]) == m6.process()):
						m6.product = p6
						break
				m6.working = m6.product != ""
				m6.progress = 0.3 + 0.1 * (m6.id % 5)
				m6.batch_t = m6.progress if m6.is_batch() else 0.0
	if setup.begins_with("v118"):
		# 1.18: авария на сетях у техпомещения и большая поставка кирпича — штабелями у ворот
		var s8 := gm.sim
		for lay in ["cable", "pipe"]:
			var best := Vector2i(-1, -1)
			var bd := INF
			for c8 in s8.faults.candidates(lay):
				var dd := Vector2(c8 - Vector2i(12, 17)).length() + (0.0 if lay == "cable" else Vector2(c8 - Vector2i(14, 13)).length())
				if dd < bd and not s8.faults.at("cable", c8):
					bd = dd
					best = c8
			if best.x >= 0:
				s8.faults.make(lay, best)
				print("v118 fault ", lay, " ", best)
		var v8 := s8.spawn_vehicle("delivery")
		for k8 in 70:
			s8.put_in_vehicle(s8.new_item("bmat", "bm_brick", "bmat"), v8)
		for k9 in 30:
			s8.put_in_vehicle(s8.new_item("bmat", "bm_block", "bmat"), v8)
		for k10 in 14:
			s8.put_in_vehicle(s8.new_item("mat", "bar45", "raw"), v8)
		s8._dump_cargo(v8)
		s8.vehicles.erase(v8)
		if not s8.ground_items.is_empty():
			print("v118 pile ", (s8.items[s8.ground_items[0]] as Item).cell)
		s8.power.tick(0.0)
	if setup == "v115o":
		# приказ: Громов идёт в правый угол бокса — флажок и пунктир
		var gw := gm.sim.workers[0]
		gm.sim.brain.give_order(gw, Vector2i(26, 16))
		for k5 in 6:
			gm.sim.tick(0.5)
		gm.tool.select_worker(gw.id)
	gm.set_speed(0)
	for c in gm.hud.toasts.get_children():
		c.queue_free()
	if args.size() > 3:
		var z := float(args[3])
		gm.cam.zoom = Vector2(z, z)
	if args.size() > 5:
		gm.cam.position = Vector2(float(args[4]), float(args[5])) * World.T
	if args.size() > 6 and args[6] == "planmode":
		gm.hud.toggle_plan()
		gm.tool.set_mode("object", "lathe_1a616")
		gm.hud._refresh_plan_panel()
	if args.size() > 6 and args[6].begins_with("tut:"):
		var parts6 := args[6].split(":")
		gm.sim.progress.tutorial = int(parts6[1])
		if parts6.size() > 2:
			gm.hud.toggle_sub(parts6[2])
	if args.size() > 6 and args[6] == "tpl":
		BuildMenu.build_cat = "frame"
		gm.hud.toggle_sub("build")
		gm.tool.set_mode("template", "canteen")
	if args.size() > 6 and args[6] == "early":
		gm.hud.confirm_start_early()
	if args.size() > 6 and args[6] == "passport":
		gm.hud.show_passport()
	if args.size() > 6 and args[6].begins_with("obj:"):
		gm.hud.obj_cat = args[6].substr(4)
		gm.hud.toggle_sub("objects")
	if args.size() > 6 and args[6].begins_with("sel:"):
		for t7: Thing in gm.sim.things.values():
			if t7.def_id == args[6].substr(4):
				gm.tool.select_thing(t7.id)
				break
	if args.size() > 6:
		match args[6]:
			"orders", "supply", "staff", "finance", "log", "shop", "office", "research":
				gm.hud.open_window(args[6])
			"weeks", "loans", "plan":
				gm.hud.open_window("finance" if args[6] != "plan" else "orders")
				gm.hud.win.tab = args[6]
				gm.hud.win.rebuild(true)
			"hire":
				gm.hud.open_window("staff")
				gm.hud.win.tab = "hire"
				gm.hud.win.rebuild(true)
			"mill", "furnace", "weld_post", "paint_booth":
				for t: Thing in gm.sim.things.values():
					if t.def_id == args[6]:
						gm.tool.select_thing(t.id)
			"veh":
				var fl := gm.sim.place_thing("forklift", Vector2i(39, 15), true, false)
				var specs := [["cart", "right", Vector2(33.5, 16.5)], ["forklift", "left", Vector2(39.5, 17.5)], ["cart", "down", Vector2(36.5, 16.2)]]
				var k := 0
				for wk in gm.sim.workers:
					if k >= specs.size() or not wk.present:
						continue
					var sp: Array = specs[k]
					k += 1
					gm.sim.brain.abort(wk)
					wk.task = Task.new()
					wk.task.data["veh"] = sp[0]
					wk.dir = sp[1]
					wk.pos = sp[2]
					wk.anim = "walk"
					var it := gm.sim.new_item("part", "bracket", "wip")
					gm.sim.give_worker(it, wk)
				fl.user = 999
			"logistics":
				gm.hud.obj_cat = "Логистика"
				gm.hud.toggle_sub("objects")
			"build", "objects":
				gm.hud.toggle_sub(args[6])
			"worker":
				gm.tool.select_worker(gm.sim.workers[0].id)
			"wheel":
				gm.tool.select_worker(gm.sim.workers[0].id)
				_wheel_test.call_deferred(gm)
			"lathe":
				for t: Thing in gm.sim.things.values():
					if t.def_id == "lathe":
						gm.tool.select_thing(t.id)
			"pause":
				gm.hud.show_pause_menu()
			"none":
				pass
			"rooms":
				gm.hud.open_rooms()
			"roomsel":
				gm.hud.open_rooms()
				gm.tool.set_mode("room", "canteen")
				gm.hud._fill_sub()
			"ghost":
				gm.sim.money += 400000.0
				var tg := gm.tool
				tg.set_mode("floor", 1)
				tg._apply_floor(Rect2i(31, 9, 9, 8))
				tg.set_mode("wall", 1)
				tg._apply_wall(Rect2i(30, 8, 11, 10))
				tg.set_mode("door", 3)
				tg._apply_openings(Rect2i(30, 12, 1, 1))
				tg.set_mode("door", 3)
				tg._apply_openings(Rect2i(36, 17, 1, 1))
				tg.set_mode("window", 2)
				tg._apply_openings(Rect2i(33, 8, 3, 1))
				tg.set_mode("window", 2)
				tg._apply_openings(Rect2i(40, 11, 1, 2))
				tg.set_mode("gate", 4)
				tg._apply_openings(Rect2i(32, 17, 3, 1))
				tg.set_mode("select")
			"bodies":
				# выстроить в ряд людей всех телосложений, мужчин и женщин
				var kinds := ["thin", "normal", "stout", "fat", "vfat"]
				var k2 := 0
				for fem in [false, true]:
					for kb in kinds:
						var nw := People.make(gm.sim.rng, "turner" if k2 % 3 != 1 else "qc", 1.0 if fem else 0.0)
						nw.female = fem
						nw.look["fem"] = fem
						nw.look["body"] = kb
						nw.look["h"] = 1.0
						nw.look["hair"] = "long" if fem else "short"
						gm.sim.add_worker(nw)
						nw.present = true
						nw.dressed = true
						nw.pos = Vector2(17.5 + (k2 % 5) * 1.6, 11.5 + int(k2 / 5) * 2.2)
						nw.dir = "down"
						nw.task = Task.new()
						nw.task.add({"t": "work", "what": "idle", "dur": 9999.0, "anim": "idle"})
						k2 += 1
				for n in gm.get_tree().get_nodes_in_group("wv"):
					(n as WorkerView)._dir = "?"
				pass
			"power":
				gm.hud.toggle_sub("power")
			"roomcard":
				gm.hud.set_tool("room")
				gm.hud.on_room_clicked(gm.sim.rooms.room_at(Vector2i(20, 12)).id)
			"roomcard2":
				gm.hud.set_tool("room")
				var rr := gm.sim.rooms.room_at(Vector2i(31, 15))
				gm.hud.on_room_clicked(rr.id if rr else -1)
			"engfx":
				# дым во втором сварочном посту без зонта, работа на постах
				var sm3 := gm.sim
				sm3.eng._vent_update()
				for m3 in sm3.things_of("machine"):
					if m3.process() in ["welding", "paint", "assembly"]:
						m3.working = true
				var wr := sm3.rooms.room_at(Vector2i(35, 7))
				if wr:
					sm3.eng.fumes[wr.id] = 46.0
				# люди на местах: сварщики, маляр, сборщик
				var posts: Array = []
				for m4 in sm3.things_of("machine"):
					if m4.process() in ["welding", "paint", "assembly"] and sm3.rooms.room_of_thing(m4) and sm3.rooms.room_of_thing(m4).rect.position.x >= 30:
						posts.append(m4)
				var pk := 0
				for wk2 in sm3.workers:
					if pk >= posts.size():
						break
					if not (wk2.prof in ["welder", "painter", "assembler"]):
						continue
					var mm2: Thing = posts[pk]
					pk += 1
					var sp2: Dictionary = mm2.spots()[0]
					sm3.brain.abort(wk2)
					wk2.present = true
					wk2.dressed = true
					wk2.ppe = 100.0
					wk2.muffs = sm3.season.noise_at(sp2["cell"]) >= 80.0
					wk2.pos = Vector2(sp2["cell"]) + Vector2(0.5, 0.5)
					wk2.dir = str(sp2["face"])
					wk2.task = Task.new()
					wk2.task.add({"t": "work", "what": "idle", "dur": 9999.0, "anim": "work"})
					mm2.user = wk2.id
			"safety":
				gm.hud.open_window("staff")
				gm.hud.win.select_tab("safety")
			"engcard":
				for t: Thing in gm.sim.things.values():
					if t.def_id == "weld_post":
						gm.tool.select_thing(t.id)
						break
			"boilercard":
				for t: Thing in gm.sim.things.values():
					if t.def_id == "boiler":
						gm.tool.select_thing(t.id)
			"roomcardat":
				gm.hud.set_tool("room")
				var rr2 := gm.sim.rooms.room_at(Vector2i(int(args[4]), int(args[5])))
				gm.hud.on_room_clicked(rr2.id if rr2 else -1)
			"help":
				gm.hud.show_help(true)
			"events", "paper":
				if args[6] == "paper":
					gm.sim.paper.add("Происшествия", "Пожар в цеху потушили сами", "Загорелась проводка у станка. Коллектив справился за 12 минут, огнетушители не подвели.")
					gm.sim.paper.add("Проверки", "Пожарный надзор: без замечаний", "Инспектор пожал руку и сказал: «Побольше бы таких предприятий».")
					for wk in gm.sim.workers:
						wk.week_score = 20 + wk.id % 7
					gm.sim.paper.publish(true)
				gm.hud.open_window(args[6])
			"insp":
				gm.hud.open_window("events")
				gm.hud.win.tab = "insp"
				gm.hud.win.rebuild(true)
			"cal":
				gm.hud.open_window("events")
				gm.hud.win.tab = "cal"
				gm.hud.win.rebuild(true)
			"letter":
				gm.sim.story._ev_rational()
				gm.hud.show_letter(gm.sim.story.letters[-1])
			"insp_warn":
				gm.sim.story.letters.clear()
				gm.sim.inspect._act("labor", [{"key": "no_aid", "text": "Нет аптечки на участке", "fine": 10000.0, "cell": [-1, -1]},
					{"key": "no_ppe", "text": "Рабочие без спецодежды и очков", "fine": 15000.0, "cell": [-1, -1]}], [], "плановая")
				gm.hud.show_letter(gm.sim.story.letters[-1])
			"opendoors":
				pass
			"veh114":
				var sv := gm.sim
				var specs := [["van", 1.0], ["flatbed", 6.0], ["truck", 12.0], ["semi", 19.0]]
				for sp4: Array in specs:
					var vv := sv.spawn_vehicle("visit")
					vv.body = str(sp4[0])
					vv.state = "parked"
					vv.x = float(sp4[1])
					vv.park_x = vv.x
					vv.parked_time = -9999.0
					if vv.body != "van":
						sv.put_in_vehicle(sv.new_item("mat", "bar45", "raw"), vv)
			"brief114", "fight114", "shower114", "escort114", "chat114":
				# 1.14: живые сцены — по-настоящему через симуляцию, потом пауза
				var sl := gm.sim
				var SL := preload("res://tests/setups.gd")
				var fm2: Worker = null
				if args[6] in ["brief114", "fight114", "escort114"]:
					fm2 = Scenario.hire_prof(sl, "foreman", 5, 6)
					fm2.present = true
					fm2.dressed = true
					fm2.pos = Vector2(40.5, 17.5)
				for wk in sl.workers:
					wk.present = true
					wk.dressed = true
					wk.hidden = false
				var focus := Vector2.ZERO
				match args[6]:
					"brief114":
						sl.place_thing("safety_stand", Vector2i(25, 9), true, false)
						sl.rooms.update()
						sl.training.start_tb()
						for k in 56:
							sl.tick(0.5)
						focus = Vector2(sl.training.tb_spot()) + Vector2(0.5, 3.0)
					"fight114":
						var fa: Worker = sl.workers[0]
						var fb: Worker = sl.workers[1]
						for wk in sl.workers:
							sl.brain.abort(wk)
						fa.pos = Vector2(37.5, 17.5)
						fb.pos = Vector2(39.5, 17.5)
						for k in sl.workers.size():
							var wk2: Worker = sl.workers[k]
							if wk2 != fa and wk2 != fb and wk2 != fm2:
								wk2.pos = Vector2(32.5 + (k % 6) * 2.0, 16.5 + (k % 2))
						sl.social.last_fight = -99999.0
						sl.social.start(fa, fb, "fight")
						for e: Dictionary in sl.social.events:
							e["end"] = sl.minute + 30.0
						for wk3: Worker in sl.workers:
							if wk3.task == null or wk3.task.kind != "social":
								continue
							for st: Dictionary in wk3.task.toils:
								if st.has("dur"):
									st["dur"] = 30.0
						for k in 9:
							sl.tick(0.5)
						focus = Vector2(38.5, 16.5)
					"chat114":
						for wk in sl.workers:
							sl.brain.abort(wk)
						var pairs := [[0, 1, 33.5, 17.5], [2, 3, 39.5, 17.5], [4, 5, 36.5, 11.5]]
						for pr: Array in pairs:
							var ca: Worker = sl.workers[int(pr[0])]
							var cb: Worker = sl.workers[int(pr[1])]
							ca.pos = Vector2(float(pr[2]), float(pr[3]))
							cb.pos = ca.pos + Vector2(2.0, 0.0)
							sl.social.start(ca, cb, "chat" if pr[0] != 2 else "argue")
						for k in 6:
							sl.tick(0.5)
						focus = Vector2(37.0, 15.5)
					"shower114":
						SL._box(sl, Rect2i(2, 3, 9, 7), 2, Vector2i(10, 6))
						sl.world.refresh_all()
						for xx in [3, 4, 5, 6]:
							sl.place_thing("shower", Vector2i(xx, 4), true, false)
						sl.place_thing("sink", Vector2i(8, 4), true, false)
						sl.place_thing("sink", Vector2i(9, 4), true, false)
						sl.place_thing("bench", Vector2i(4, 7), true, false)
						sl.place_thing("lamp_tube", Vector2i(6, 6), true, false)
						sl.rooms.update()
						sl.rooms.fill(Vector2i(5, 6), "shower")
						Scenario.autopipe(sl)
						Scenario.autowire(sl)
						sl.rooms.update()
						var ws2: Array = sl.workers.duplicate()
						for k in mini(6, ws2.size()):
							var wk4: Worker = ws2[k]
							sl.brain.abort(wk4)
							wk4.pos = Vector2(12.5 + k * 1.5, 7.5 + (k % 2))
							sl.brain._go_home(wk4)
						for k in 22:
							sl.tick(0.5)
						focus = Vector2(6.5, 6.5)
					"escort114":
						sl.inspect.schedule("fire", sl.minute, true)
						for k in 600:
							sl.tick(0.5)
							if sl.inspect.busy() and int(sl.inspect.visit.get("i", 0)) >= 2:
								break
						var vis := sl.inspect.visitor()
						if vis:
							focus = vis.pos
				if focus != Vector2.ZERO:
					gm.cam.position = focus * World.T
			"people115c":
				# телосложения: мужчины и женщины — худой, средний, крепкий, полный, очень полный
				var sb := gm.sim
				for wk in sb.workers:
					wk.present = false
				var br := RandomNumberGenerator.new()
				br.seed = 31
				var bodies := ["thin", "normal", "stout", "fat", "vfat"]
				for k in 10:
					var fem := k >= 5
					var bw := People.make(br, ["turner", "assembler", "laborer", "miller", "electrician", "turner", "laborer", "miller", "assembler", "welder"][k], 1.0 if fem else 0.0)
					bw.look["body"] = bodies[k % 5]
					sb.add_worker(bw)
					bw.present = true
					bw.dressed = true
					bw.mood = 55.0
					bw.pos = Vector2(3.5 + (k % 5) * 1.7, 4.6 + int(k / 5) * 2.0)
					bw.dir = "down"
					bw.anim = "idle"
			"people115d":
				# женские причёски крупно: кудри, «химия», каре, коса, хвост, пучок, длинные, короткая
				var sd := gm.sim
				for wk in sd.workers:
					wk.present = false
				var dr := RandomNumberGenerator.new()
				dr.seed = 5
				var hs := ["curly_f", "perm", "bob", "braid", "ponytail", "bun", "long", "pixie"]
				for k in 16:
					var dw := People.make(dr, "turner", 1.0)
					dw.look["hair"] = hs[k % 8]
					dw.look["hat"] = ""
					sd.add_worker(dw)
					dw.present = true
					dw.dressed = true
					dw.mood = 55.0
					dw.pos = Vector2(3.5 + (k % 8) * 1.5, 4.6 + int(k / 8) * 2.0)
					dw.dir = "down" if k < 8 else "up"
					dw.anim = "idle"
			"people115", "people115b":
				# 1.15: новый облик людей — разные лица, причёски, телосложения, все повороты
				var sp := gm.sim
				for wk in sp.workers:
					wk.present = false
				var pr := RandomNumberGenerator.new()
				pr.seed = 77 if args[6] == "people115" else 912
				var profs := ["turner", "welder", "foreman", "qc", "laborer", "cleaner", "miller", "painter", "electrician", "guard", "cook", "accountant", "assembler", "nurse"]
				var made: Array[Worker] = []
				for k in 14:
					var nw := People.make(pr, profs[k], 0.45)
					sp.add_worker(nw)
					made.append(nw)
				var rows := [[0, "down"], [7, "down"], [0, "right"], [0, "up"]]
				var cx0 := 3.5
				for ri in rows.size():
					for k2 in 7:
						var src: Worker = made[int(rows[ri][0]) + k2]
						var wv: Worker = src
						if ri >= 2:
							wv = People.make(pr, src.prof, 0.0)
							wv.first = src.first
							wv.last = src.last
							wv.female = src.female
							wv.age = src.age
							wv.look = src.look.duplicate()
							sp.add_worker(wv)
						wv.present = true
						wv.dressed = true
						wv.hidden = false
						wv.mood = [55.0, 80.0, 50.0, 20.0, 60.0, 50.0, 75.0][k2]
						wv.pos = Vector2(cx0 + k2 * 1.6, 4.4 + ri * 1.9)
						wv.dir = str(rows[ri][1])
						wv.anim = "idle"
						wv.task = null
			"carry114":
				# 1.14: кто что несёт — пруток, лист, лоток, инструмент, катушка, кран с тяжёлой деталью
				var sc := gm.sim
				var row := [["mat", "bar45", 3, "", "right"], ["mat", "bar45", 2, "", "down"], ["mat", "plate8", 1, "", "right"], ["mat", "plate8", 1, "", "down"],
					["part", "pin", 4, "", "down"], ["", "", 0, "toolbox", "down"], ["", "", 0, "reel", "right"], ["part", "frame", 1, "pendant", "right"]]
				var ws: Array = sc.workers.duplicate()
				for k in mini(row.size(), ws.size()):
					var wk: Worker = ws[k]
					var spec: Array = row[k]
					sc.brain.abort(wk)
					wk.present = true
					wk.dressed = true
					wk.hidden = false
					wk.pos = Vector2(31.5 + k * 1.6, 17.5)
					if k == 7:
						wk.pos = Vector2(40.5, 8.5)
					wk.dir = str(spec[4])
					wk.anim = "walk" if k != 5 else "work"
					if str(spec[0]) != "":
						for n in int(spec[2]):
							var it := sc.new_item(str(spec[0]), str(spec[1]), "raw" if str(spec[0]) == "mat" else "ok")
							sc.give_worker(it, wk, n > 0)
					wk.prop = str(spec[3])
			"mat112":
				# новые полы и стены (1.12)
				var sm4 := gm.sim
				var ww4 := sm4.world
				var fids := [1, 4, 2, 5, 3, 6]
				for fi in fids.size():
					for yy in range(2, 8):
						for xx in range(31 + fi * 2, 33 + fi * 2):
							ww4.flr[ww4.idx(Vector2i(xx, yy))] = fids[fi]
				var kinds := [World.W_BRICK, World.W_CONCRETE, World.W_SANDWICH, World.W_PARTITION]
				for ki in kinds.size():
					for xx in range(31 + ki * 3, 34 + ki * 3):
						ww4.wall[ww4.idx(Vector2i(xx, 10))] = kinds[ki]
					ww4.wall[ww4.idx(Vector2i(31 + ki * 3, 11))] = kinds[ki]
					ww4.wall[ww4.idx(Vector2i(31 + ki * 3, 12))] = kinds[ki]
				ww4.wall[ww4.idx(Vector2i(44, 10))] = World.W_METAL_DOOR
				ww4.wall[ww4.idx(Vector2i(45, 10))] = World.W_DOOR
				for yy in range(11, 14):
					for xx in range(31, 46):
						if ww4.wall[ww4.idx(Vector2i(xx, yy))] == World.W_NONE:
							ww4.flr[ww4.idx(Vector2i(xx, yy))] = 1
				ww4.refresh_all()
				ww4.rev += 1
			"machrot":
				# все станки во всех поворотах: проверка боковых и задних видов
				var sm3 := gm.sim
				sm3.progress.all_open = true
				var ww3 := sm3.world
				for yy in range(1, 34):
					for xx in range(30, 47):
						ww3.flr[ww3.idx(Vector2i(xx, yy))] = 1
				ww3.refresh_all()
				var defs := ["mill", "lathe", "cnc_lathe", "weld_post", "assembly_table", "test_stand", "band_saw", "workbench"]
				var y0 := 2
				for di in defs.size():
					var dd: String = defs[di]
					var bs: Array = Defs.objects[dd].get("size", [1, 1])
					var x0 := 31
					for r in 4:
						var sz := Thing.rot_size(Vector2i(int(bs[0]), int(bs[1])), r)
						sm3.place_thing(dd, Vector2i(x0, y0), true, false, r)
						x0 += sz.x + 1
					y0 += maxi(int(bs[0]), int(bs[1])) + 1
					if y0 > 30:
						break
			"rots":
				var sm2 := gm.sim
				sm2.money += 2000000.0
				var SC2 := preload("res://tests/setups.gd")
				SC2._box(sm2, Rect2i(1, 2, 13, 14), 1, Vector2i(13, 8))
				var ids := ["locker", "sink", "fridge", "toilet", "office_desk", "drill"]
				for i in ids.size():
					for r in 4:
						var cc := Vector2i(2 + r * 3, 3 + i * 2)
						if ids[i] == "office_desk" and r % 2 == 1:
							cc.y -= 1
						sm2.place_thing(ids[i], cc, true, false, r)
			"train":
				gm.hud.open_window("staff")
				gm.hud.win.select_tab("train")
			"market", "contracts":
				if args[6] == "contracts":
					var ct := gm.sim.sales._new_contract()
					if not ct.is_empty():
						gm.sim.sales.contracts.append(ct)
				gm.hud.open_window("orders")
				gm.hud.win.select_tab(args[6])
			"bpwalls":
				var bw := gm.sim.world
				for x in range(6, 14):
					gm.sim.place_wall_bp(Vector2i(x, 27), World.W_BRICK)
				gm.sim.place_wall_bp(Vector2i(14, 27), World.W_BRICK)
				for x2 in [8, 9]:
					gm.sim.place_wall_bp(Vector2i(x2, 27), World.W_WINDOW)
				gm.sim.place_wall_bp(Vector2i(11, 27), World.W_DOOR)
				for y in range(28, 32):
					gm.sim.place_wall_bp(Vector2i(6, y), World.W_WINDOW if y == 29 or y == 30 else World.W_BRICK)
				gm.sim.place_wall_bp(Vector2i(14, 28), World.W_GATE)
				gm.sim.place_wall_bp(Vector2i(14, 29), World.W_GATE)
				gm.sim.place_wall_bp(Vector2i(14, 30), World.W_BRICK)
				bw.rev += 0
			"temp", "light", "noise", "traffic", "load", "dirt", "vent", "air", "crew", "nets":
				gm.hud.forced_overlay = args[6]
			"over":
				gm.sim.crisis.close("labor", "Трудовая инспекция закрыла завод", "За две недели 3 человека уволились, потому что им не платили зарплату. Они написали жалобу — трудовая инспекция проверила ведомости, наложила арест на счёт и приостановила деятельность предприятия. Завод закрыт.")
			_ when args[6].begins_with("tpl:"):
				# 1.21: призрак готового помещения у стены цеха (общая стена)
				var tp := args[6].split(":")
				var tid := tp[1]
				gm.sim.money += 2000000.0
				gm.hud.toggle_sub("build")
				gm.tool.set_mode("template", tid)
				var wr: Rooms.Room = null
				for rr2 in gm.sim.rooms.list:
					if rr2.type == "workshop":
						wr = rr2
				var orr := Vector2i(int(tp[2]), int(tp[3])) if tp.size() > 3 else Vector2i(wr.srect.end.x, wr.srect.position.y - 1)
				var hc := orr + Templates.size(tid) / 2
				gm.cam.focus_cell(hc)
				await get_tree().process_frame
				var scr2 := get_viewport().get_canvas_transform() * ((Vector2(hc) + Vector2(0.5, 0.5)) * World.T)
				Input.warp_mouse(scr2)
			"wpop":
				for w6: Worker in gm.sim.workers:
					if w6.present and not w6.visitor:
						gm.tool.select_worker(w6.id)
						gm.hud.info.visible = false
						gm.hud.worker_pop.show_for(w6)
						gm.cam.focus_cell(w6.cell())
						break
			"fire":
				var fw: Worker = null
				for w5: Worker in gm.sim.workers:
					if not w5.visitor and fw == null:
						fw = w5
				fw.set_meta("absences", 2)
				gm.hud.show_fire_dialog(fw)
			"fix":
				gm.hud.open_window("events:insp")
				gm.hud.show_fix("Захламлены проходы: грузы на полу", Inspections.fix_text("clutter"), Vector2i(12, 24))
				gm.hud.fix_box.position = Vector2(560, 300)
			_ when args[6].begins_with("wcard:"):
				InfoPanel.w_tab = args[6].substr(6)
				var pick: Worker = gm.sim.workers[0]
				for w: Worker in gm.sim.workers:
					if w.present and not w.is_itr() and w.history.size() >= pick.history.size():
						pick = w
				gm.tool.select_worker(pick.id)
			_ when args[6].begins_with("win:"):
				# win:<окно>[:<вкладка>]
				var wp := args[6].split(":")
				gm.hud.open_window(wp[1])
				if wp.size() > 2 and gm.hud.win:
					gm.hud.win.select_tab(wp[2])
			_ when args[6].begins_with("ctl"):
				# 1.19: человек под управлением; ctl — карточка, ctlmenu:x:y — меню «Сделать сейчас» у клетки
				var cpick: Worker = null
				for w2: Worker in gm.sim.workers:
					if w2.present and not w2.is_itr() and (cpick == null or w2.prof == "laborer"):
						cpick = w2
				if cpick:
					gm.sim.money += 200000.0
					for xx2 in range(14, 18):
						gm.sim.place_floor_bp(Vector2i(xx2, 26), 1)
					gm.hud.ctl.take(cpick)
					if args[6] == "ctl":
						gm.tool.select_worker(cpick.id)
						gm.hud.info.show_worker(gm.sim, cpick)
					else:
						var cp := args[6].split(":")
						var cc2 := Vector2i(int(cp[1]), int(cp[2]))
						var scr := get_viewport().get_canvas_transform() * ((Vector2(cc2) + Vector2(0.5, 0.5)) * World.T)
						gm.hud.ctl.on_map_click(cc2, scr)
			_ when args[6].begins_with("near:"):
				# карточка у места щелчка: объект, стена или пол в клетке x:y
				var np := args[6].split(":")
				var nc := Vector2i(int(np[1]), int(np[2]))
				var sp_pos := get_viewport().get_canvas_transform() * ((Vector2(nc) + Vector2(0.5, 0.5)) * World.T)
				var nt := gm.sim.thing_at(nc)
				gm.hud.info.near_screen = sp_pos
				if nt:
					gm.tool.select_thing(nt.id)
					gm.hud.info.near_screen = sp_pos
					gm.hud.info.show_thing(gm.sim, nt)
				else:
					gm.hud.info.show_cell(gm.sim, nc)
			_ when args[6].begins_with("cell:"):
				var cp := args[6].split(":")
				gm.hud.info.show_cell(gm.sim, Vector2i(int(cp[1]), int(cp[2])))
			_ when args[6].begins_with("sub:"):
				var sp := args[6].split(":")
				var kind := sp[1]
				if sp.size() > 2:
					match kind:
						"build":
							BuildMenu.build_cat = sp[2]
						"rooms":
							BuildMenu.zone_cat = sp[2]
						"objects":
							gm.hud.obj_cat = sp[2]
						"power":
							gm.hud.net_kind = sp[2]
				if kind == "rooms":
					gm.hud.open_rooms()
				else:
					gm.hud.toggle_sub(kind)
				if sp.size() > 3:
					gm.tool.set_mode("room" if kind == "rooms" else "object", sp[3])
					gm.hud._fill_sub()
			_ when args[6].begins_with("win:"):
				var wp := args[6].split(":")
				gm.hud.open_window(wp[1])
				if wp.size() > 2 and gm.hud.win:
					gm.hud.win.select_tab(wp[2])
			"crew_brig", "crew_sched", "crew_sec", "crew_union":
				gm.hud.open_window("crew")
				gm.hud.win.select_tab(args[6].substr(5))
			"drawing":
				var prod := args[8] if args.size() > 8 else "shaft"
				gm.hud.show_drawing({"product": prod, "id": 4217, "qty": 12, "client": "ООО «Агротех»"})
			"water":
				gm.hud.net_kind = "water"
				gm.hud.toggle_sub("power")
			"ventsub", "airsub":
				gm.hud.net_kind = "vent" if args[6] == "ventsub" else "air"
				gm.hud.toggle_sub("power")
			"logi":
				# зона разгрузки, заказанное оборудование, повёрнутые станки
				var sm := gm.sim
				sm.money += 3000000.0
				sm.set_area(Rect2i(15, 22, 7, 3), 1)
				sm.place_thing("lathe", Vector2i(27, 10), true, false, 1)
				sm.place_thing("rack", Vector2i(24, 9), true, false, 3)
				var lk := sm.place_thing("locker", Vector2i(26, 15), false, true)
				sm.place_thing("workbench", Vector2i(21, 15), false, true, 1)
				sm.place_thing("plant", Vector2i(24, 17), false, true)
				for e in 4:
					var it := sm.new_item("crate", "lathe", "crate")
					it.step = e % 3
					sm.put_on_ground(it, Vector2i(15 + e, 23))
				var it2 := sm.new_item("crate", "plant", "loose")
				sm.put_on_ground(it2, Vector2i(19, 22))
				lk.crates_in = 0
			"goals", "rating", "scn", "ach":
				gm.hud.open_window("goals")
				gm.hud.win.tab = "stage" if args[6] == "goals" else args[6]
				gm.hud.win.rebuild(true)
			"stageup":
				gm.sim.progress.stage = 2
				gm.hud.show_stage_up(2)


## Колесо над карточкой не должно менять масштаб карты, над картой — должно.
func _wheel_test(gm: GameMain) -> void:
	for i in 6:
		await get_tree().process_frame
	var vp := get_viewport()
	var card := gm.hud.info
	var over := card.get_global_rect().get_center()
	var map_pt := Vector2(300, 400)
	for pt in [over, map_pt]:
		var mm := InputEventMouseMotion.new()
		mm.position = pt
		mm.global_position = pt
		Input.parse_input_event(mm)
		await get_tree().process_frame
		await get_tree().process_frame
		var z0 := gm.cam.zoom.x
		for k in 3:
			var wb := InputEventMouseButton.new()
			wb.button_index = MOUSE_BUTTON_WHEEL_DOWN
			wb.pressed = true
			wb.position = pt
			wb.global_position = pt
			Input.parse_input_event(wb)
			var wr := wb.duplicate() as InputEventMouseButton
			wr.pressed = false
			Input.parse_input_event(wr)
			await get_tree().process_frame
		var hc := vp.gui_get_hovered_control()
		print("WHEEL at ", pt, " hovered=", hc.get_class() if hc else "null", " zoom ", z0, " -> ", gm.cam.zoom.x)


func _process(_d: float) -> void:
	frames += 1
	if OS.get_environment("SHOT_MOUSE_CELL") != "" and frames >= wait - 12:
		var mcs := OS.get_environment("SHOT_MOUSE_CELL").split(",")
		var wpos := Vector2(float(mcs[0]), float(mcs[1])) * World.T + Vector2(9, 9)
		get_viewport().warp_mouse(get_viewport().get_canvas_transform() * wpos)
	if OS.get_environment("SHOT_INFO") != "" and BuildMenu._info and is_instance_valid(BuildMenu._info):
		if frames == wait - 8:
			BuildMenu._info.text = OS.get_environment("SHOT_INFO")
		if frames == wait - 2:
			var gmx := target as GameMain
			print("SUBPANEL ", gmx.hud.sub_panel.size, " info ", BuildMenu._info.size)
	if frames == wait - 1 and OS.has_environment("SHOT_DEBUG"):
		for n in get_tree().get_nodes_in_group("wv"):
			var wv := n as WorkerView
			var texs: Array[String] = []
			for ch in wv.body.get_children():
				if ch is Sprite2D and (ch as Sprite2D).texture:
					texs.append((ch as Sprite2D).texture.resource_path.get_file())
			print("   ", texs)
			print(wv.worker.first, " dressed=", wv.worker.dressed, " out=", wv._outside, " win=", wv._winter, " hat=", wv.worker.look.get("hat", ""), " cell=", wv.worker.cell(), " act=", wv.worker.activity)
	if frames == wait - 3 and args.size() > 6 and args[6] == "opendoors":
		for n in get_tree().root.find_children("*", "EntityLayer", true, false):
			var el := n as EntityLayer
			el.hold_doors = true
			for dp: WallPiece in el.doors:
				dp._open_goal = 0.55 if (dp.cell.x + dp.cell.y) % 3 == 0 else 1.0
				dp._open_t = dp._open_goal
				dp.queue_redraw()
	if frames == wait - 6 and OS.has_environment("SHOT_SCROLL"):
		var gm2 := target as GameMain
		if gm2 and gm2.hud.win:
			gm2.hud.win.scroll.scroll_vertical = int(OS.get_environment("SHOT_SCROLL"))
	if frames == wait:
		var img := get_viewport().get_texture().get_image()
		var out := args[2] if args.size() > 2 else "/tmp/shot.png"
		img.save_png(out)
		print("saved ", out, " ", img.get_size())
		get_tree().quit()


func _box(sim: Sim, r: Rect2i, floor_id: int, door: Vector2i) -> void:
	var w := sim.world
	for y in range(r.position.y, r.end.y):
		for x in range(r.position.x, r.end.x):
			var c := Vector2i(x, y)
			var i := w.idx(c)
			w.flr[i] = floor_id
			var edge := x == r.position.x or x == r.end.x - 1 or y == r.position.y or y == r.end.y - 1
			if edge and w.wall[i] == World.W_NONE:
				w.wall[i] = World.W_BRICK
	w.wall[w.idx(door)] = World.W_DOOR
	w.refresh_all()


## Пристройка из теста этапа 2: бытовка, столовая, туалет, кабели.
## 1.16: большой цех в песочнице — все станки по переделам рядами, ряд ЧПУ, люди и заказы всех размеров.
func _setup_v116(sim: Sim) -> void:
	var SV := preload("res://tests/setups.gd")
	sim.money = 20000000.0
	sim.progress.stage = 4
	for rk in ["fast_cutting", "cnc_lathe", "cnc_mill"]:
		sim.office.research_done.append(rk)
	var w := sim.world
	var hall := Rect2i(2, 2, 48, 26)
	SV._box(sim, hall, 1, Vector2i(2, 14))
	for x in [24, 25, 26]:
		w.wall[w.idx(Vector2i(x, 27))] = World.W_GATE
	for x2 in [6, 7, 14, 15, 22, 23, 30, 31, 38, 39, 44, 45]:
		w.wall[w.idx(Vector2i(x2, 2))] = World.W_WINDOW
	w.refresh_all()
	var rows := [
		[4, ["lathe_tv4", 4], ["lathe_1a616", 7], ["lathe", 10], ["lathe_16k20", 14], ["lathe_1m63", 18], ["mill_6t80", 23], ["mill_6r10", 26], ["mill", 29], ["mill_6r82", 32], ["mill_6r13", 35], ["drill_ns12", 39], ["drill_2n118", 41], ["drill", 43], ["drill_2n150", 45]],
		[8, ["drill_2m55", 4], ["weld_vd306", 7], ["weld_pdg251", 10], ["weld_spot", 13], ["weld_post", 15], ["weld_stand", 18], ["asm_bench", 22], ["asm_press", 24], ["assembly_table", 27], ["asm_stand", 30], ["asm_line", 34], ["test_stand", 39], ["compressor", 43]],
		[12, ["heat_snol", 4], ["heat_tvch", 6], ["furnace", 9], ["heat_shaft", 12], ["heat_bogie", 15], ["paint_table", 19], ["paint_small", 22], ["paint_powder", 25], ["paint_booth", 28], ["paint_line", 31]],
		[17, ["cnc_lathe", 4], ["cnc_65a60", 8], ["cnc_sidway", 12], ["cnc_panther", 15], ["cnc_hangan", 19], ["cnc_hartwood", 24], ["cnc_minger", 28], ["cnc_maiday", 31]],
	]
	for row: Array in rows:
		var base_y := int(row[0])
		for j in range(1, row.size()):
			var e: Array = row[j]
			var sz: Array = Defs.objects[str(e[0])]["size"]
			var yy := base_y - (int(sz[1]) - 1)   # низ всех станков ряда на одной линии
			var th := sim.place_thing(str(e[0]), Vector2i(int(e[1]), yy), true, false)
			if th == null:
				print("v116: не встал ", e[0], " ", sim.can_place(str(e[0]), Vector2i(int(e[1]), yy)))
	for c in [Vector2i(36, 20), Vector2i(36, 22)]:
		sim.place_thing("qc_table", c, true, false)
	for c2 in [Vector2i(40, 20), Vector2i(40, 22), Vector2i(43, 20), Vector2i(43, 22)]:
		sim.place_thing("rack", c2, true, false)
	for c3 in [Vector2i(46, 20), Vector2i(46, 22)]:
		sim.place_thing("wip_rack", c3, true, false)
	for x3 in range(40, 48):
		sim.place_thing("pallet", Vector2i(x3, 25), true, false)
	var ktps: Array[Thing] = []
	for k in 3:
		var kt := sim.place_thing("ktp", Vector2i(53, 3 + k * 4), true, false)
		if kt:
			sim.rooms.legacy[kt.id] = true
			ktps.append(kt)
	sim.rooms.update()
	var r := sim.rooms.room_at(Vector2i(26, 20))
	if r:
		sim.rooms.assign(r, "workshop")
	Scenario.autolight(sim, false)
	Scenario.autowire(sim)
	for kt2 in ktps:
		Scenario._route(sim, kt2.cells())
	sim.world.cable_rev += 1
	sim.rooms.update()
	for hp in [["turner", "turning", 7], ["turner", "turning", 6], ["turner", "turning", 5], ["miller", "milling", 7], ["miller", "milling", 6],
			["miller", "milling", 5], ["welder", "welding", 6], ["welder", "welding", 5], ["assembler", "assembly", 6], ["heat_treater", "heat", 6],
			["painter", "paint", 6], ["painter", "paint", 5], ["laborer", "haul", 7], ["laborer", "haul", 6], ["laborer", "haul", 6], ["qc", "qc", 6], ["qc", "qc", 5], ["technologist", "engineering", 6]]:
		var wk := SV.hire(sim, str(hp[0]), str(hp[1]), int(hp[2]))
		wk.present = true
		wk.pos = Vector2(20.5 + (sim.workers.size() % 10), 22.5 + (sim.workers.size() % 3))
	for k2 in sim.cons.keys():
		sim.cons[k2] = 200.0
	var want := {"pin": 12, "bushing": 10, "shaft": 6, "housing": 4, "bracket": 8, "axle": 4, "frame": 3, "beam": 2, "gear": 4, "spline_shaft": 4, "disc": 6}
	SV.complex_orders(sim, 14, want)
	var mats := ["bar45", "bar40x", "forging", "hex27", "plate8", "profile40"]
	var n := 0
	for mt in mats:
		for q in 6:
			var it := sim.new_item("mat", mt, "raw")
			sim.put_on_ground(it, Vector2i(38 + n % 10, 24 - (n / 10) % 2))
			n += 1
	Workplace.auto_assign(sim)
	sim.power.update_topology()
	sim.power.tick(0.1)
	print("v116: мощность %.0f кВт, станков %d" % [sim.power.total_kw(), sim.things_of("machine").size()])


func _setup_s2(sim: Sim) -> void:
	_box(sim, Rect2i(29, 8, 6, 5), 3, Vector2i(29, 10))
	_box(sim, Rect2i(29, 12, 6, 5), 3, Vector2i(29, 14))
	_box(sim, Rect2i(34, 8, 4, 4), 2, Vector2i(34, 9))
	sim.world.wall[sim.world.idx(Vector2i(31, 8))] = World.W_WINDOW
	sim.world.wall[sim.world.idx(Vector2i(32, 16))] = World.W_WINDOW
	sim.world.refresh_all()
	for c in [Vector2i(30, 9), Vector2i(31, 9), Vector2i(32, 9)]:
		sim.place_thing("locker", c, true, false)
	sim.place_thing("bench", Vector2i(31, 11), true, false)
	sim.place_thing("dining_table", Vector2i(31, 14), true, false)
	sim.place_thing("chair", Vector2i(31, 13), true, false)
	sim.place_thing("chair", Vector2i(32, 13), true, false)
	sim.place_thing("chair", Vector2i(31, 15), true, false)
	sim.place_thing("fridge", Vector2i(33, 13), true, false)
	sim.place_thing("microwave", Vector2i(30, 13), true, false)
	sim.place_thing("toilet", Vector2i(35, 9), true, false)
	sim.place_thing("sink", Vector2i(36, 9), true, false)
	sim.place_thing("plant", Vector2i(33, 15), true, false)
	sim.place_thing("honor_board", Vector2i(24, 15), true, false)
	sim.rooms.update()
	sim.rooms.assign(sim.rooms.room_at(Vector2i(31, 10)), "locker")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(31, 15)), "canteen")
	sim.rooms.assign(sim.rooms.room_at(Vector2i(35, 10)), "wc")
	for x in range(28, 33):
		sim.place_cable(Vector2i(x, 10), true)
	for y in range(10, 15):
		sim.place_cable(Vector2i(32, y), true)
	sim.place_cable(Vector2i(33, 12), true)
	sim.place_cable(Vector2i(34, 10), true)
	sim.place_cable(Vector2i(35, 10), true)



## Зима: декабрь, мороз, снегопад; батареи в гараже, проходная у ворот, огнетушители.
func _winter(sim: Sim, heat: bool) -> void:
	sim.season.start_month = 11
	sim.season.temp_day = -14.0
	sim.season.snow_from = 0.0
	sim.season.snow_until = 1440.0 * 3.0
	if heat:
		for c in [Vector2i(28, 10), Vector2i(28, 11), Vector2i(15, 16), Vector2i(28, 17), Vector2i(20, 18), Vector2i(33, 9)]:
			if sim.can_place("radiator", c) == "":
				sim.place_thing("radiator", c, true, false)
	if sim.can_place("checkpoint", Vector2i(18, 27)) == "":
		sim.place_thing("checkpoint", Vector2i(18, 27), true, false)
	if sim.can_place("first_aid", Vector2i(28, 15)) == "":
		sim.place_thing("first_aid", Vector2i(28, 15), true, false)


## Пожар в цеху и забастовка у проходной одновременно.
func _drama(sim: Sim) -> void:
	sim.story._start_strike(false)
	for i in 60:
		sim.tick(0.5)
	sim.story.ignite(Vector2i(17, 11), "Загорелась проводка")
	for i2 in 50:
		sim.tick(0.5)
	sim.story.ignite(Vector2i(18, 12), "Загорелась проводка")
	for i3 in 10:
		sim.tick(0.5)
	sim.story.letters.clear()
