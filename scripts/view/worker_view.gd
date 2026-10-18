class_name WorkerView
extends Node2D
## «Бумажная кукла» рабочего: тень, туловище, детали одежды, руки, голова, лицо, волосы,
## борода, очки, головной убор. Части тонируются цветом кожи/волос/одежды. Без ног.

const T := World.T
const OFF := Vector2(-32, -102)   ## точка стопы в текстуре 64×112

var sim: Sim
var worker: Worker
var doll := Node2D.new()
var body := Node2D.new()
var trunk := Node2D.new()   ## туловище и одежда — масштабируются по телосложению
var headn := Node2D.new()   ## голова, лицо, волосы, головной убор — не масштабируются
var _sx := 1.0
var _shape := "m_norm"
var shadow := Sprite2D.new()
var hand_a := Sprite2D.new()
var hand_b := Sprite2D.new()
var held := Node2D.new()
var bubble := Node2D.new()
var ring := Node2D.new()
var smoke: Array[Sprite2D] = []
var puff := Sprite2D.new()   ## 1.25: выдох дыма на перекуре
var gest := Node2D.new()     ## 1.25: мелочь в руке — ложка, кружка
var _gest := ""
var _gest_at := Vector2.ZERO
var _dir := ""
var _t := 0.0
var _carry_sig := ""
var skin := Color.WHITE
var hair_col := Color.WHITE
var cloth := Color.WHITE
var hat_col := Color.WHITE
var selected := false
var _dressed := true
var _muffs := false
var veh := Sprite2D.new()          ## тележка или погрузчик, на которых сейчас везёт
var veh_load := Node2D.new()
var _veh := ""
var _veh_front := false
var prop_sp := Sprite2D.new()      ## что держит в руке (папка, лопата, плакат, огнетушитель)
var _prop := ""
var _carry_kind := ""   ## 1.14: как несёт — bar (пруток на плече), sheet (лист), tray (лоток), crane (ведёт краном)
var _winter := false
var _outside := false
var _tex_rev := -1   ## ступень разрешения текстур людей, под которую собрана кукла
var _mood_b := 0     ## 1.15: настроение на лице (улыбка / уголки вниз)
## 1.23: видимая часть мира (с запасом) — кто за краем экрана, того не анимируем. Ставит EntityLayer.
static var view := Rect2(-1e9, -1e9, 2e9, 2e9)


func setup(s: Sim, w: Worker) -> void:
	sim = s
	worker = w
	add_to_group("wv")
	_t = randf() * 10.0
	var lk := w.look
	skin = Color(People.SKINS[int(lk.get("skin", 1)) % People.SKINS.size()])
	hair_col = Color(str(lk.get("hair_col", "#4a3020")))
	cloth = Color(str(lk.get("outfit_col", "#3d5a7a")))
	hat_col = Color(str(lk.get("hat_col", "#ffffff")))
	add_child(ring)
	ring.draw.connect(_draw_ring)
	veh.centered = false
	veh.scale = Vector2(0.5, 0.5)
	veh.visible = false
	add_child(veh)
	add_child(doll)
	veh_load.visible = false
	add_child(veh_load)
	shadow.texture = Tex.person("shadow")
	_prep(shadow)
	doll.add_child(shadow)
	doll.add_child(body)
	for h in [hand_a, hand_b]:
		h.texture = Tex.person("hand")
		h.scale = Vector2(0.44, 0.44)   # 1.15: кисти под новую (меньшую) голову
		h.modulate = skin
	prop_sp.scale = Vector2(0.5, 0.5)
	prop_sp.visible = false
	add_child(bubble)
	bubble.draw.connect(_draw_bubble)
	gest.draw.connect(_draw_gest)
	puff.texture = Tex.fx("smoke")
	puff.visible = false
	add_child(puff)
	for i in 3:
		var sp := Sprite2D.new()
		sp.texture = Tex.fx("smoke")
		sp.scale = Vector2(0.25, 0.25)
		sp.visible = false
		add_child(sp)
		smoke.append(sp)
	_update_pos()


func _prep(sp: Sprite2D) -> void:
	sp.centered = false
	sp.offset = OFF
	sp.scale = Vector2(0.5, 0.5)


func _layer(name: String, col: Color = Color.WHITE, parent: Node2D = null) -> void:
	var tex := Tex.person(name)
	if tex == null:
		return
	var sp := Sprite2D.new()
	sp.texture = tex
	_prep(sp)
	sp.modulate = col
	(parent if parent else headn).add_child(sp)


func _rebuild(dir: String) -> void:
	_dir = dir
	if _tex_rev != Tex.people_rev:
		_tex_rev = Tex.people_rev
		shadow.texture = Tex.person("shadow")
		for h in [hand_a, hand_b]:
			h.texture = Tex.person("hand")
		if _prop != "":
			prop_sp.texture = Tex.person("prop_" + _prop)
	for c in body.get_children():
		body.remove_child(c)
	for n in [trunk, headn]:
		for c2 in n.get_children():
			c2.queue_free()
	var lk := worker.look
	var d := "front"
	if dir == "up":
		d = "back"
	elif dir == "left" or dir == "right":
		d = "side"
	doll.scale.x = -1.0 if dir == "left" else 1.0
	var bd := People.body_of(lk)
	_sx = float(bd["wf"])
	var sy := float(bd["sy"])
	_shape = str(bd["shape"])
	trunk.scale = Vector2(1.0, sy)
	headn.position = Vector2(0, -22.5 * (sy - 1.0))
	shadow.scale = Vector2(0.5 * (0.7 + 0.3 * _sx), 0.5)
	_dressed = worker.dressed
	var outfit := str(lk.get("outfit", "overall"))
	var hair := str(lk.get("hair", "short"))
	var beard := str(lk.get("beard", ""))
	var hat := str(lk.get("hat", ""))
	var hcol := hat_col
	cloth = Color(str(lk.get("outfit_col", "#3d5a7a")))
	_winter = _is_winter()
	_outside = _is_outside()
	if not _dressed:
		# своя одежда: куртка или пальто, без каски; зимой — шапка-ушанка
		outfit = str(lk.get("street", "jacket"))
		cloth = Color(str(lk.get("street_col", "#3b3f44")))
		if hat == "helmet" or hat == "weldmask":
			hat = ""
		if _winter and (hat == "" or hat == "cap"):
			hat = "ushanka"
			hcol = _fur_color()
	elif _winter and _outside and not worker.visitor and (hat == "" or hat == "cap" or hat == "kerchief"):
		# выскочил на улицу в мороз — накинул ушанку
		hat = "ushanka"
		hcol = _fur_color()
	var glasses := bool(lk.get("glasses", false))
	_muffs = worker.muffs
	var phones := bool(lk.get("phones", false)) or (_muffs and _dressed and hat != "weldmask")
	var resp := bool(lk.get("resp", false)) and _dressed
	var fc := People.face(lk, worker.age)
	var g := "f" if worker.female else "m"
	hair = People.hair_style(lk)
	_mood_b = _mood_bucket()
	var mouth := str(fc["mouth"])
	if _mood_b == 1:
		mouth = "smile"
	elif _mood_b == -1:
		mouth = "down"
	var masked := hat == "weldmask"
	match d:
		"front":
			_torso("front", outfit)
			body.add_child(trunk)
			body.add_child(held)
			body.add_child(hand_a)
			body.add_child(hand_b)
			body.add_child(prop_sp)
			body.add_child(gest)
			body.add_child(headn)
			_face_layers("front", fc, g, beard, mouth, masked)
			if hair != "bald" or hat == "":
				_layer("hair_%s_front" % hair, hair_col)
			if bool(fc["earrings"]) and hat != "ushanka":
				_layer("earrings_front")
			if resp:
				_layer("resp_front")
			if glasses and not masked:
				_layer("glasses_front")
			if hat != "":
				_layer("hat_%s_front" % hat, hcol)
			if phones:
				_layer("phones_front")
		"back":
			body.add_child(held)
			body.add_child(hand_a)
			body.add_child(hand_b)
			body.add_child(prop_sp)
			_torso("back", outfit)
			body.add_child(trunk)
			body.add_child(headn)
			_layer("head_%s_back" % str(fc["head"]), skin)
			_layer("hair_%s_back" % hair, hair_col)
			if hat != "":
				_layer("hat_%s_back" % hat, hcol)
			if phones:
				_layer("phones_back")
		"side":
			body.add_child(hand_b)
			_torso("side", outfit)
			body.add_child(trunk)
			body.add_child(held)
			body.add_child(hand_a)
			body.add_child(prop_sp)
			body.add_child(gest)
			body.add_child(headn)
			_face_layers("side", fc, g, beard, mouth, false)
			if hair != "bald" or hat == "":
				_layer("hair_%s_side" % hair, hair_col)
			if not People.EAR_HIDDEN.has(hair) and hat not in ["ushanka", "kerchief"]:
				_layer("ear_side", skin)
				if bool(fc["earrings"]):
					_layer("earrings_side")
			if resp:
				_layer("resp_side")
			if glasses:
				_layer("glasses_side")
			if hat != "":
				_layer("hat_%s_side" % hat, hcol)
			if phones:
				_layer("phones_side")
	_carry_sig = ""


## 1.15: лицо из частей — голова своей формы, морщины, веснушки, глаза (белок, радужка цвета глаз, веки),
## брови, нос, борода, рот (по настроению улыбается или опускает уголки).
func _face_layers(d: String, fc: Dictionary, g: String, beard: String, mouth: String, masked: bool) -> void:
	_layer("head_%s_%s" % [str(fc["head"]), d], skin)
	if People.body_key(worker.look) in ["fat", "vfat"]:
		_layer("chin_" + d)
	if masked and d == "front":
		return
	if str(fc["lines"]) != "":
		_layer("lines_%s_%s" % [str(fc["lines"]), d])
	if bool(fc["freckles"]):
		_layer("freckles_" + d)
	var ek := str(fc["eyes"])
	if Tex.people_lod():
		_layer("eyeslod_%s_%s" % [g, d])
	else:
		_layer("eyes_%s_%s_%s" % [ek, g, d])
		_layer("iris_%s_%s" % [ek, d], People.eye_color(worker.look))
		_layer("lids_%s_%s_%s" % [ek, g, d])
	_layer("brows_%s_%s" % [str(fc["brows"]), d], hair_col)
	_layer("nose_%s_%s" % [str(fc["nose"]), d], skin if d == "side" else Color.WHITE)
	if beard != "":
		_layer("beard_%s_%s" % [beard, d], hair_col)
	_layer("mouth_%s_%s_%s" % [mouth, g, d])


## Настроение для выражения лица: 1 — доволен (улыбается), -1 — плохое (уголки вниз), 0 — как обычно.
func _mood_bucket() -> int:
	if worker.mood >= 70.0:
		return 1
	if worker.mood < 28.0:
		return -1
	return 0


## Туловище своего силуэта (мужского или женского, по телосложению); детали одежды — внутри
## силуэта (обрезаются по нему) и растянуты по ширине фигуры.
func _torso(d: String, outfit: String) -> void:
	var tsp := Sprite2D.new()
	tsp.texture = Tex.person("torso_%s_%s" % [d, _shape])
	if tsp.texture == null:
		tsp.texture = Tex.person("torso_" + d)
	_prep(tsp)
	tsp.self_modulate = cloth
	tsp.clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	trunk.add_child(tsp)
	var otex := Tex.person("outfit_%s_%s" % [outfit, d])
	if otex:
		var osp := Sprite2D.new()
		osp.texture = otex
		osp.centered = false
		osp.offset = OFF
		osp.scale = Vector2(_sx if d != "side" else (1.0 + (_sx - 1.0) * 0.6), 1.0)
		tsp.add_child(osp)


## Мех ушанки контрастный к волосам: тёмным — серый кролик, светлым — чёрная цигейка.
func _fur_color() -> Color:
	var furs := [Color("#7d7a78"), Color("#8f8a80"), Color("#6a6d74")] if hair_col.v < 0.45 else [Color("#2e2b2a"), Color("#3a332e")]
	return furs[absi(worker.id) % furs.size()]


func _is_outside() -> bool:
	return sim.rooms.room_at(worker.cell()) == null


func _is_winter() -> bool:
	return sim.season.season_id() == "winter" or sim.season.temp_day < -2.0


func _update_pos() -> void:
	var vp := worker.vpos()
	position = Vector2(vp.x * T, vp.y * T + 6.0)


func _process(delta: float) -> void:
	_t += delta
	visible = worker.present and not worker.hidden
	if not visible:
		return
	_update_pos()
	if not view.has_point(position) and not selected:
		return
	if worker.dir != _dir or worker.dressed != _dressed or worker.muffs != _muffs or _is_winter() != _winter or (_winter and _is_outside() != _outside) \
			or _mood_bucket() != _mood_b:
		_rebuild(worker.dir)
	elif _tex_rev != Tex.people_rev and (Engine.get_process_frames() + absi(worker.id)) % 4 == 0:
		# сменился масштаб — пересобираем куклу в новом разрешении (вразнобой, чтобы не дёргало)
		_rebuild(worker.dir)
	if worker.prop != _prop:
		_prop = worker.prop
		prop_sp.texture = Tex.person("prop_" + _prop) if _prop != "" else null
		prop_sp.visible = _prop != ""
	var vk := ""
	if worker.task:
		vk = str(worker.task.data.get("veh", ""))
	if vk != _veh:
		_set_vehicle(vk)
	_update_carry()
	_animate()
	if _veh != "":
		_place_vehicle()
	bubble.queue_redraw()
	if selected or ring.get_meta("was", false):
		ring.set_meta("was", selected)
		ring.queue_redraw()


func _draw_ring() -> void:
	if not selected:
		return
	var col := Color("#7fe39a")
	var r := 15.0
	var k := 28
	ring.draw_set_transform(Vector2(0, 1), 0.0, Vector2(1.0, 0.42))
	ring.draw_arc(Vector2.ZERO, r + 1.5, 0.0, TAU, 40, Color(0, 0, 0, 0.35), 3.5)
	for i in k:
		if i % 2 == 0:
			var a1 := TAU * i / k + _t * 0.8
			ring.draw_arc(Vector2.ZERO, r, a1, a1 + TAU / k, 4, col, 2.2)
	ring.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _set_vehicle(key: String) -> void:
	_veh = key
	veh.visible = key != ""
	if key == "":
		doll.position = Vector2.ZERO
		veh_load.visible = false
		_carry_sig = ""
		return
	veh.texture = Tex.obj(key)
	var m: Dictionary = Defs.sprites.get(key, {})
	veh.offset = Vector2(0, -float(m.get("oy", 64)))
	_carry_sig = ""


## Тележку толкают перед собой, на погрузчике сидят; груз лежит на платформе или вилах.
func _place_vehicle() -> void:
	var side := _dir == "left" or _dir == "right"
	var front := true
	if _veh == "forklift":
		var fl := _dir == "right"
		veh.flip_h = fl
		veh.position = Vector2(-32.0 - (8.0 if fl else 0.0), 12.0)
		doll.position = Vector2(4.0 if fl else -4.0, -12.0)
		veh_load.position = Vector2(30.0 if fl else -30.0, 0.0)
		front = true
	else:
		var c := Vector2(0, 12)
		if _dir == "up":
			c = Vector2(0, -6)
			front = false
		elif side:
			c = Vector2(20.0 if _dir == "right" else -20.0, 5.0)
		var fl2 := _dir == "right"
		veh.flip_h = fl2
		veh.position = c - Vector2(16.0 + (8.0 if fl2 else 0.0), 0)
		veh_load.position = c + Vector2(0, -19)
	if front != _veh_front or (veh.get_index() < doll.get_index()) == front:
		_veh_front = front
		move_child(veh, get_child_count() - 1 if front else doll.get_index())
		move_child(veh_load, get_child_count() - 1)
	veh_load.visible = worker.carrying >= 0
	held.visible = false
	shadow.visible = _veh != "forklift"
	if _veh == "forklift":
		var k := 1.0 if _dir == "right" else -1.0
		hand_a.position = Vector2(-8.0 * k, -14.0) if doll.scale.x > 0 else Vector2(8.0 * k, -14.0)
		hand_b.position = hand_a.position + Vector2(4.0, 1.0)
		body.position = Vector2(0, sin(_t * 9.0) * 0.4)
	elif side:
		hand_a.position = Vector2(12, -12)
		hand_b.position = Vector2(9, -11)


func _update_carry() -> void:
	var sig := "%d:%d:%s:%s" % [worker.carrying, worker.carry_extra.size(), _veh, worker.prop]
	if sig == _carry_sig:
		return
	_carry_sig = sig
	for c in held.get_children():
		c.queue_free()
	for c2 in veh_load.get_children():
		c2.queue_free()
	_carry_kind = ""
	if worker.carrying < 0:
		return
	if _veh != "":
		var itv: Item = sim.items.get(worker.carrying)
		if itv == null:
			return
		var nv := worker.carry_count()
		var texv := Tex.for_item(itv)
		var crates := clampi(int(ceil(nv / 6.0)), 1, 4)
		for k in crates:
			var cr2 := Sprite2D.new()
			cr2.texture = Tex.item("crate")
			cr2.scale = Vector2(0.45, 0.45)
			cr2.position = Vector2((k % 2) * 13.0 - 6.0, -int(k / 2) * 9.0)
			veh_load.add_child(cr2)
			var ic2 := Sprite2D.new()
			ic2.texture = texv
			ic2.scale = Vector2(0.28, 0.28)
			ic2.position = cr2.position + Vector2(0, -1)
			veh_load.add_child(ic2)
		return
	var it: Item = sim.items.get(worker.carrying)
	if it == null:
		return
	if it.kind == "crate":
		# ящик с оборудованием — перед собой двумя руками; мелочь (стул, цветок) — как есть
		var sp0 := Sprite2D.new()
		if it.q == "loose":
			var key := "chair_down" if it.def_id == "chair" else it.def_id
			sp0.texture = Tex.obj(key)
			if sp0.texture:
				var sz0 := sp0.texture.get_size()
				var fit0 := 26.0 / maxf(sz0.x, sz0.y)
				sp0.scale = Vector2(fit0, fit0)
				sp0.position = Vector2(0, -4)
		else:
			sp0.texture = Tex.item("equip_crate")
			sp0.scale = Vector2(0.4, 0.4)
			sp0.position = Vector2(0, -2)
		held.add_child(sp0)
		return
	var n := worker.carry_count()
	var tex := Tex.for_item(it)
	if worker.prop == "pendant" and Production.is_heavy(it):
		_carry_kind = "crane"   # деталь висит на крюке кран-балки, в руках — пульт
		return
	if it.kind == "mat" and Vec.has("people", "carry_bar_" + it.def_id):
		# пруток на плече: сбоку — во всю длину, спереди и сзади — торцы
		_carry_kind = "bar"
		for k in mini(n, 4):
			var bsp := Sprite2D.new()
			bsp.texture = Tex.person("carry_bar_" + it.def_id)
			bsp.set_meta("side", bsp.texture)
			bsp.set_meta("end", Tex.person("carry_barend_" + it.def_id))
			bsp.scale = Vector2(0.5, 0.5)
			bsp.position = Vector2(0, -float(k) * 2.2)
			held.add_child(bsp)
		return
	if it.kind == "mat" and it.def_id == "plate8":
		_carry_kind = "sheet"
		var ssp := Sprite2D.new()
		ssp.texture = Tex.person("carry_sheet")
		ssp.set_meta("side", Tex.person("carry_sheet_edge"))
		ssp.set_meta("front", ssp.texture)
		ssp.scale = Vector2(0.5, 0.5)
		held.add_child(ssp)
		return
	if n >= 2 and it.kind == "part":
		# мелкие детали — в лотке, сверху видно, что в нём
		_carry_kind = "tray"
		var tr := Sprite2D.new()
		tr.texture = Tex.person("carry_tray")
		tr.scale = Vector2(0.5, 0.5)
		tr.position = Vector2(0, 2)
		held.add_child(tr)
		for k2 in mini(n, 4):
			var ic := Sprite2D.new()
			ic.texture = tex
			ic.scale = Vector2(0.26, 0.26)
			ic.position = Vector2(-5.0 + float(k2 % 2) * 7.0 + float(k2 / 2) * 2.0, -1.0 - float(k2 / 2) * 2.0)
			held.add_child(ic)
	else:
		for k in mini(n, 3):
			var sp := Sprite2D.new()
			sp.texture = tex
			sp.scale = Vector2(0.5, 0.5)
			sp.position = Vector2(0, -k * 2.6)
			held.add_child(sp)


func _animate() -> void:
	var a := worker.anim
	# 1.25: живые мелочи поверх тех же поз — обед с ложкой, чай на отдыхе, потягивания без дела
	var tk := worker.task.kind if worker.task else ""
	if tk == "eat" and (a == "sit" or a == "idle"):
		a = "eat_sit" if a == "sit" else "eat_stand"
	elif tk == "rest" and a == "sit":
		a = "tea"
	elif tk == "wander" and a == "idle" and fmod(_t + float(worker.id) * 3.7, 16.0) < 2.6:
		a = "stretch"
	_gest = ""
	var side := _dir == "left" or _dir == "right"
	var back := _dir == "up"
	var bob := 0.0
	var ha := Vector2(-13, -9)
	var hb := Vector2(13, -9)
	if side:
		ha = Vector2(3, -9)
		hb = Vector2(-3, -10)
	var carrying := worker.carrying >= 0
	shadow.visible = true
	match a:
		"walk":
			var s := sin(_t * 10.0)
			bob = -absf(s) * 1.6
			if side:
				ha += Vector2(s * 3.0, 0)
				hb += Vector2(-s * 3.0, 0)
			else:
				ha += Vector2(0, s * 1.5)
				hb += Vector2(0, -s * 1.5)
		"work":
			var s2 := sin(_t * 7.0 + float(worker.id))
			if back:
				ha = Vector2(-9, -15 + s2 * 1.5)
				hb = Vector2(9, -15 - s2 * 1.5)
			elif side:
				ha = Vector2(9 + s2 * 1.5, -11)
				hb = Vector2(5, -12)
			else:
				ha = Vector2(-7, -11 + s2 * 1.5)
				hb = Vector2(7, -11 - s2 * 1.5)
			bob = sin(_t * 3.0) * 0.4
		"desk":
			bob = 3.0
			var s3 := sin(_t * 13.0 + float(worker.id))
			if back:
				ha = Vector2(-7, -15 + s3 * 0.8)
				hb = Vector2(7, -15 - s3 * 0.8)
			elif side:
				ha = Vector2(9, -10 + s3 * 0.6)
				hb = Vector2(6, -10)
			else:
				ha = Vector2(-7, -9 + s3 * 0.8)
				hb = Vector2(7, -9 - s3 * 0.8)
		"sit":
			bob = 3.0
			ha = Vector2(-11, -7) if not side else Vector2(6, -7)
			hb = Vector2(11, -7) if not side else Vector2(-2, -7)
		"talk":
			# рассказывает: руки жестикулируют
			var s5 := sin(_t * 5.0 + float(worker.id))
			if side:
				ha = Vector2(9, -16 + s5 * 3.0)
				hb = Vector2(4, -11)
			else:
				ha = Vector2(-10, -16 + s5 * 3.0)
				hb = Vector2(10, -13 - s5 * 2.0)
			bob = sin(_t * 2.5) * 0.4
		"fight":
			# потасовка: толкаются, руки машут
			var s6 := sin(_t * 14.0 + float(worker.id))
			ha = Vector2(9 + s6 * 4.0, -16) if side else Vector2(-9, -17 + s6 * 4.0)
			hb = Vector2(5 - s6 * 3.0, -13) if side else Vector2(9, -17 - s6 * 4.0)
			bob = -absf(s6) * 1.5
			body.position.x = s6 * 1.5
		"smoke":
			var ph := fmod(_t, 4.0)
			if ph < 1.2:
				hb = Vector2(4, -22) if not side else Vector2(7, -20)
			elif ph > 3.2:
				# стряхивает пепел
				hb = (Vector2(11, -12) if not side else Vector2(-3, -11)) + Vector2(0, sin(_t * 30.0) * 0.8)
			bob = sin(_t * 2.0) * 0.3
		"eat_sit", "eat_stand":
			# ложка: зачерпнуть — к губам — обратно (раз в 2,6 с, вразнобой)
			var pe := fmod(_t * 0.38 + float(worker.id) * 0.21, 1.0)
			var up := clampf(sin(pe * PI) * 1.6, 0.0, 1.0) if pe < 0.55 else 0.0
			var low := Vector2(8, -6) if not side else Vector2(8, -7)
			var mouth := Vector2(3, -20) if not side else Vector2(7, -19)
			if back:
				low = Vector2(8, -9)
				mouth = Vector2(5, -15)
			hb = low.lerp(mouth, up)
			ha = Vector2(-9, -6) if not side else Vector2(4, -7)
			bob = 3.0 if a == "eat_sit" else sin(_t * 2.0) * 0.3
			if not back:
				_gest = "spoon"
				_gest_at = hb
		"tea":
			# чай: кружка в руке, изредка отпивает
			bob = 3.0
			var pt := fmod(_t * 0.17 + float(worker.id) * 0.13, 1.0)
			var sip := clampf(sin(clampf((pt - 0.7) / 0.3, 0.0, 1.0) * PI) * 1.5, 0.0, 1.0)
			var rest := Vector2(9, -9) if not side else Vector2(8, -9)
			var lip := Vector2(4, -19) if not side else Vector2(8, -18)
			hb = rest.lerp(lip, sip)
			ha = Vector2(-11, -7) if not side else Vector2(6, -7)
			if not back:
				_gest = "mug"
				_gest_at = hb
		"stretch":
			# потягивается: руки вверх, чуть покачивается
			var pk := fmod(_t + float(worker.id) * 3.7, 16.0) / 2.6
			var rise := sin(clampf(pk, 0.0, 1.0) * PI)
			var top := -9.0 - 22.0 * rise
			if side:
				ha = Vector2(3 + rise * 2.0, top)
				hb = Vector2(-3, top + 2.0)
			else:
				ha = Vector2(-13 + rise * 6.0, top)
				hb = Vector2(13 - rise * 6.0, top)
			bob = -rise * 1.2
		_:
			bob = sin(_t * 2.0) * 0.35
	if carrying:
		if side:
			ha = Vector2(9, -11)
			hb = Vector2(5, -11)
			held.position = Vector2(9, -12)
		elif back:
			ha = Vector2(-9, -12)
			hb = Vector2(9, -12)
			held.position = Vector2(0, -19)
		else:
			ha = Vector2(-8, -10)
			hb = Vector2(8, -10)
			held.position = Vector2(0, -11)
		match _carry_kind:
			"bar":
				# на плече: одна рука придерживает пучок у плеча
				for bc in held.get_children():
					if bc is Sprite2D and bc.has_meta("side"):
						(bc as Sprite2D).texture = bc.get_meta("side") if side else bc.get_meta("end")
				held.position = Vector2(2, -20) if side else Vector2(-8 if back else 8, -21)
				held.z_index = 0 if not back else -1
				ha = Vector2(5, -19) if side else Vector2(8, -18)
				hb = Vector2(-3, -12) if side else Vector2(-9, -9)
			"sheet":
				for sc in held.get_children():
					if sc is Sprite2D and sc.has_meta("side"):
						(sc as Sprite2D).texture = sc.get_meta("side") if side else sc.get_meta("front")
				held.position = Vector2(9, -13) if side else Vector2(0, -12 if not back else -16)
				held.z_index = -1 if back else 0
				ha = Vector2(8, -18) if side else Vector2(-9, -16)
				hb = Vector2(6, -8) if side else Vector2(9, -16)
			"crane":
				ha = Vector2(4, -16) if not side else Vector2(7, -16)
			"tray":
				held.z_index = 0
			_:
				held.z_index = 0
	body.position = Vector2(0, bob)
	# руки шире у полных: отодвигаем по ширине туловища
	var hk := Vector2(_sx if not side else (1.0 + (_sx - 1.0) * 0.6), 1.0)
	hand_a.position = ha * hk
	hand_b.position = hb * hk
	held.visible = carrying and _carry_kind != "crane"
	if _prop != "":
		_place_prop(ha, hb, side, back)
	gest.visible = _gest != ""
	if gest.visible:
		gest.queue_redraw()
	# дым сигареты
	var smoking := a == "smoke"
	var pf := fmod(_t, 4.0)
	puff.visible = smoking and pf > 1.3 and pf < 2.9
	if puff.visible:
		var k := (pf - 1.3) / 1.6
		var fwd := Vector2(0, 2) if not side else Vector2(4 * doll.scale.x, 0)
		puff.position = Vector2(2, -22) + fwd * k * 3.0 + Vector2(0, -k * 7.0) if not side else Vector2(7 * doll.scale.x, -21) + fwd * k * 3.0 + Vector2(0, -k * 6.0)
		puff.scale = Vector2.ONE * (0.18 + k * 0.4)
		puff.modulate = Color(1, 1, 1, (1.0 - k) * 0.55)
	for i in smoke.size():
		var sp := smoke[i]
		sp.visible = smoking
		if smoking:
			var ph2 := fmod(_t * 0.5 + i * 0.33, 1.0)
			var base := Vector2(4, -24) if not side else Vector2(8 * doll.scale.x, -22)
			sp.position = base + Vector2(sin(ph2 * 6.0 + i) * 2.0, -ph2 * 16.0)
			sp.modulate = Color(1, 1, 1, (1.0 - ph2) * 0.7)
			sp.scale = Vector2.ONE * (0.15 + ph2 * 0.25)


## 1.25: ложка или кружка у кисти (рисуется поверх руки).
func _draw_gest() -> void:
	var p := _gest_at
	match _gest:
		"spoon":
			gest.draw_line(p + Vector2(-1, 1), p + Vector2(4, -3), Color(0.78, 0.8, 0.82), 1.2)
			gest.draw_circle(p + Vector2(4.6, -3.6), 1.4, Color(0.86, 0.88, 0.9))
		"mug":
			var r := Rect2(p + Vector2(-2.5, -3.5), Vector2(5, 5.5))
			gest.draw_rect(r, Color(0.86, 0.84, 0.78))
			gest.draw_rect(Rect2(r.position, Vector2(5, 1.2)), Color(0.45, 0.28, 0.16))
			gest.draw_arc(p + Vector2(3.2, -0.8), 1.6, -PI * 0.5, PI * 0.5, 6, Color(0.86, 0.84, 0.78), 1.0)


## Реквизит в руке: плакат над головой, лопата и огнетушитель — перед собой, папка — у груди.
func _place_prop(ha: Vector2, hb: Vector2, side: bool, back: bool) -> void:
	prop_sp.rotation = 0.0
	prop_sp.offset = Vector2.ZERO
	prop_sp.z_index = -1 if back else 0
	prop_sp.scale = Vector2(0.75, 0.75) if _prop == "sign" else Vector2(0.5, 0.5)
	match _prop:
		"sign":
			var sway := sin(_t * 2.2 + float(worker.id)) * 0.08
			prop_sp.position = Vector2(0, -44)
			prop_sp.rotation = sway
			hand_a.position = Vector2(-4, -26)
			hand_b.position = Vector2(4, -26)
			prop_sp.z_index = 1
		"shovel":
			var dig := sin(_t * 6.0 + float(worker.id)) * 0.25 if worker.anim == "work" else 0.0
			prop_sp.position = (Vector2(10, -4) if side else Vector2(6, -2))
			prop_sp.rotation = 0.35 + dig
		"ext":
			prop_sp.position = ha + Vector2(2, 2)
			if worker.anim == "work":
				prop_sp.rotation = -0.4
		"camera":
			prop_sp.position = Vector2(0, -30) if worker.anim == "idle" and not back else hb + Vector2(0, 2)
		"flowers":
			prop_sp.position = hb + Vector2(0, -4)
		"toolbox":
			# ящик с инструментом: в руке по дороге, у станка — на полу рядом
			prop_sp.position = (Vector2(11, 1) if worker.anim == "work" else hb + Vector2(0, 5))
			prop_sp.scale = Vector2(0.42, 0.42)
		"reel":
			prop_sp.position = ha + Vector2(-1, 4)
			prop_sp.scale = Vector2(0.42, 0.42)
			prop_sp.rotation = fmod(_t * 2.0, TAU) if worker.anim == "walk" else 0.0
		"trowel":
			prop_sp.position = hb + Vector2(1, -2)
			prop_sp.scale = Vector2(0.4, 0.4)
			prop_sp.rotation = sin(_t * 8.0) * 0.35 if worker.anim == "work" else 0.0
		"hammer":
			# молоток: держат за рукоять (поворот вокруг кисти); за работой — медленный замах и быстрый удар
			prop_sp.scale = Vector2(0.46, 0.46)
			prop_sp.offset = Vector2(-1.5, -11.0)
			var hp := ha if side else hb
			if worker.anim == "work":
				var ph := fmod(_t * 2.4 + float(worker.id) * 0.37, 1.0)
				var rot := lerpf(1.0, -0.9, ph / 0.72) if ph < 0.72 else lerpf(-0.9, 1.0, (ph - 0.72) / 0.28)
				prop_sp.rotation = rot
				var lift := Vector2(0, -3.0 * (1.0 - (rot + 0.9) / 1.9))
				prop_sp.position = hp + lift
				if side:
					hand_a.position = hp + lift
				else:
					hand_b.position = hp + lift
			else:
				prop_sp.rotation = 0.3
				prop_sp.position = hp + Vector2(0, 1.0)
		"pendant":
			prop_sp.position = ha + Vector2(0, 3)
			prop_sp.scale = Vector2(0.36, 0.36)
		_:
			prop_sp.position = hb + Vector2(-3, -2)


## Значки над головой: что человеку сейчас нужно (туалет, еда, отдых, холод, настроение)
## и особые состояния (проверка, забастовка, травма, пожар). Маленькие круглые бейджи.
func _draw_bubble() -> void:
	if worker.bubble != "":
		_chip(Vector2(0, -44), [worker.bubble], [1.0])
		return
	var icons: Array = []   ## [вид, срочность 0..1]
	var n := worker.needs
	var bl := float(n["bladder"])
	var fd := float(n["food"])
	var rs := float(n["rest"])
	if bl < 25.0:
		icons.append(["wc", 1.0 - bl / 25.0])
	if fd < 22.0:
		icons.append(["food", 1.0 - fd / 22.0])
	if rs < 18.0:
		icons.append(["rest", 1.0 - rs / 18.0])
	if worker.present and not worker.visitor and _dressed:
		var tc := sim.season.temp_at(worker.cell())
		if tc < Defs.sea("freezing_below"):
			icons.append(["cold", 0.7])
		elif tc > Defs.sea("hot_above"):
			icons.append(["hot", 0.5])
	if worker.mood < 25.0:
		icons.append(["mood", 1.0 - worker.mood / 25.0])
	if icons.is_empty():
		return
	icons.sort_custom(func(a: Array, b: Array) -> bool: return float(a[1]) > float(b[1]))
	icons = icons.slice(0, 3)
	var kinds: Array = []
	var urgs: Array = []
	for ic: Array in icons:
		kinds.append(str(ic[0]))
		urgs.append(float(ic[1]))
	_chip(Vector2(0, -43), kinds, urgs)


const BADGE_COLS := {"hot": "#d8644e", "wc": "#3f8de0", "food": "#e0883a", "rest": "#7a64c8", "cold": "#5fa8d8", "mood": "#6d747c",
	"inspect": "#7a5236", "strike": "#c9372c", "injury": "#c9372c", "fire": "#e0602c",
	"idea": "#3f8a5a", "talk": "#4a7aa8", "chat": "#5a9a6a", "argue": "#d08a35", "fight": "#c9372c", "laugh": "#d9a13a"}


## 1.15: значки над головой — компактная тёмная «пилюля» с цветными пиктограммами и хвостиком
## к голове. Срочное — пиктограмма пульсирует, под ней светится цветная чёрточка.
const CHIP_STEP := 8.4
const CHIP_H := 8.6
const CHIP_BG := Color(0.11, 0.125, 0.14, 0.9)


func _capsule(r: Rect2, col: Color) -> void:
	var rad := r.size.y * 0.5
	bubble.draw_circle(Vector2(r.position.x + rad, r.position.y + rad), rad, col)
	bubble.draw_circle(Vector2(r.end.x - rad, r.position.y + rad), rad, col)
	if r.size.x > r.size.y:
		bubble.draw_rect(Rect2(r.position.x + rad, r.position.y, r.size.x - 2.0 * rad, r.size.y), col)


func _chip(c: Vector2, kinds: Array, urgs: Array) -> void:
	var n := kinds.size()
	var w := CHIP_STEP * n + 1.4
	var r := Rect2(c - Vector2(w * 0.5, CHIP_H * 0.5), Vector2(w, CHIP_H))
	# 1.19: пилюля и пиктограммы — из вектора под зум камеры (раньше рисовались примитивами и рябили)
	var pill := Tex.emo("chip%d" % clampi(n, 1, 3))
	if pill:
		# в SVG: 1 ед. мира = 4 ед.; поля 3 слева/справа, 2 сверху
		bubble.draw_texture_rect(pill, Rect2(r.position - Vector2(0.75, 0.5), Vector2(pill.get_width(), pill.get_height()) * 0.25), false)
	else:
		_capsule(r, CHIP_BG)
	for i in n:
		var kind := str(kinds[i])
		var urg := float(urgs[i])
		var gc := Vector2(r.position.x + 0.7 + CHIP_STEP * (i + 0.5), c.y)
		var col := Color(str(BADGE_COLS.get(kind, "#9aa3ab"))).lightened(0.22)
		var k := 0.66
		if urg > 0.6:
			k *= 1.0 + 0.07 * sin(_t * 6.0)
			bubble.draw_line(gc + Vector2(-2.2, CHIP_H * 0.5 - 1.3), gc + Vector2(2.2, CHIP_H * 0.5 - 1.3), Color(col, 0.55 + 0.35 * sin(_t * 6.0)), 0.9, true)
		var gt := Tex.emo(kind)
		if gt:
			var gs := 11.0 * k
			bubble.draw_texture_rect(gt, Rect2(gc - Vector2(gs, gs) * 0.5, Vector2(gs, gs)), false)
		else:
			_glyph(gc, kind, k, col, CHIP_BG)


## Старый круглый значок (используют снимки и подсказки): теперь — та же пилюля на одну пиктограмму.
func _badge(c: Vector2, kind: String, urg: float, _r: float) -> void:
	_chip(c, [kind], [urg])


## Пиктограмма значка: fg — цвет рисунка, bg — фон (для вырезов вроде месяца).
func _glyph(c: Vector2, kind: String, k: float, fg: Color, bg: Color) -> void:
	var wht := fg
	var col := bg
	match kind:
		"wc":
			# капля
			var pr := PackedVector2Array()
			pr.append(c + Vector2(0, -4.3) * k)
			for i2 in 17:
				var a2 := -PI * 0.15 + (PI * 1.3) * i2 / 16.0
				pr.append(c + Vector2(cos(a2) * 2.9, 0.8 + sin(a2) * 2.9) * k)
			bubble.draw_colored_polygon(pr, wht)
		"food":
			# вилка и нож
			bubble.draw_line(c + Vector2(-1.8, -3.6) * k, c + Vector2(-1.8, 3.8) * k, wht, 1.2 * k)
			for dx in [-2.8, -1.8, -0.8]:
				bubble.draw_line(c + Vector2(dx, -3.8) * k, c + Vector2(dx, -1.2) * k, wht, 0.7 * k)
			bubble.draw_colored_polygon(PackedVector2Array([c + Vector2(1.4, -3.8) * k, c + Vector2(2.9, -2.6) * k, c + Vector2(2.6, 0.6) * k, c + Vector2(1.6, 0.6) * k]), wht)
			bubble.draw_line(c + Vector2(2.1, 0.4) * k, c + Vector2(2.1, 3.8) * k, wht, 1.2 * k)
		"rest":
			# месяц
			bubble.draw_circle(c + Vector2(-0.3, 0.2) * k, 3.4 * k, wht)
			bubble.draw_circle(c + Vector2(1.3, -1.1) * k, 2.9 * k, col)
		"cold":
			# снежинка
			for i3 in 3:
				var a3 := PI / 3.0 * i3 + PI / 6.0
				var d := Vector2(cos(a3), sin(a3)) * 3.7 * k
				bubble.draw_line(c - d, c + d, wht, 0.9 * k)
		"hot":
			# термометр
			bubble.draw_line(c + Vector2(0, -3.6) * k, c + Vector2(0, 1.2) * k, wht, 1.8 * k)
			bubble.draw_circle(c + Vector2(0, 2.2) * k, 1.9 * k, wht)
			bubble.draw_circle(c + Vector2(0, 2.2) * k, 1.0 * k, Color("#d8644e"))
		"mood":
			# тучка с каплей
			bubble.draw_circle(c + Vector2(-1.6, 0.2) * k, 1.9 * k, wht)
			bubble.draw_circle(c + Vector2(0.6, -0.9) * k, 2.3 * k, wht)
			bubble.draw_circle(c + Vector2(2.3, 0.4) * k, 1.6 * k, wht)
			bubble.draw_rect(Rect2(c + Vector2(-1.6, 0.2) * k, Vector2(3.9, 1.9) * k), wht)
			bubble.draw_line(c + Vector2(-0.5, 2.8) * k, c + Vector2(-1.0, 4.0) * k, Color("#9cc8e8"), 0.9 * k)
		"inspect":
			bubble.draw_rect(Rect2(c + Vector2(-2.8, -3.6) * k, Vector2(5.6, 7.2) * k), wht)
			bubble.draw_line(c + Vector2(-1.6, 0.2) * k, c + Vector2(-0.3, 1.6) * k, Color("#3f9a4a"), 1.0 * k)
			bubble.draw_line(c + Vector2(-0.3, 1.6) * k, c + Vector2(1.9, -1.4) * k, Color("#3f9a4a"), 1.0 * k)
		"strike":
			bubble.draw_rect(Rect2(c + Vector2(-0.8, -3.8) * k, Vector2(1.6, 5.0) * k), wht)
			bubble.draw_circle(c + Vector2(0, 2.9) * k, 0.95 * k, wht)
		"injury":
			bubble.draw_rect(Rect2(c + Vector2(-1.0, -3.4) * k, Vector2(2.0, 6.8) * k), wht)
			bubble.draw_rect(Rect2(c + Vector2(-3.4, -1.0) * k, Vector2(6.8, 2.0) * k), wht)
		"fire":
			bubble.draw_colored_polygon(PackedVector2Array([c + Vector2(0, -4.2) * k, c + Vector2(2.8, 0.6) * k, c + Vector2(1.6, 3.4) * k, c + Vector2(-1.6, 3.4) * k, c + Vector2(-2.8, 0.6) * k]), wht)
			bubble.draw_circle(c + Vector2(0, 1.6) * k, 1.4 * k, Color("#ffd54a"))
		"idea":
			# лампочка
			bubble.draw_circle(c + Vector2(0, -0.9) * k, 2.6 * k, wht)
			bubble.draw_rect(Rect2(c + Vector2(-1.2, 1.4) * k, Vector2(2.4, 2.0) * k), wht)
			bubble.draw_line(c + Vector2(-1.2, 3.8) * k, c + Vector2(1.2, 3.8) * k, wht, 0.8 * k)
		"talk", "chat":
			# облачко речи с тремя точками
			bubble.draw_circle(c + Vector2(0, -0.4) * k, 3.4 * k, wht)
			bubble.draw_colored_polygon(PackedVector2Array([c + Vector2(-2.0, 2.0) * k, c + Vector2(-3.4, 4.2) * k, c + Vector2(0.2, 2.6) * k]), wht)
			for dx2 in [-1.6, 0.0, 1.6]:
				bubble.draw_circle(c + Vector2(dx2, -0.4) * k, 0.6 * k, col)
		"argue":
			# молния
			bubble.draw_colored_polygon(PackedVector2Array([c + Vector2(0.8, -4.2) * k, c + Vector2(-2.4, 0.6) * k, c + Vector2(-0.2, 0.6) * k, c + Vector2(-1.0, 4.2) * k, c + Vector2(2.4, -0.8) * k, c + Vector2(0.2, -0.8) * k]), wht)
		"fight":
			# звёздочка удара
			var pts := PackedVector2Array()
			for i4 in 10:
				var a4 := -PI / 2.0 + TAU * i4 / 10.0
				var rr := (4.0 if i4 % 2 == 0 else 1.8) * k
				pts.append(c + Vector2(cos(a4), sin(a4)) * rr)
			bubble.draw_colored_polygon(pts, wht)
		"laugh":
			bubble.draw_arc(c + Vector2(0, 0.2) * k, 2.6 * k, 0.15, PI - 0.15, 8, wht, 1.1 * k)
			bubble.draw_circle(c + Vector2(-1.4, -1.4) * k, 0.7 * k, wht)
			bubble.draw_circle(c + Vector2(1.4, -1.4) * k, 0.7 * k, wht)
