class_name SettingsUI
extends RefCounted
## Страница настроек (общая для главного меню и паузы): игра, звук, экран.

const TOGGLES := [
	["autosave", "Автосохранение каждое утро"],
	["fast_night", "Ускорять ночь и выходные, когда на заводе пусто"],
	["pause_on_event", "Ставить паузу, когда приходит событие с выбором"],
	["edge_scroll", "Двигать камеру, когда курсор у края экрана"],
	["names_on_map", "Фамилии под людьми на карте"],
	["fullscreen", "Полноэкранный режим"],
]
const VOLUMES := [["vol_master", "Общая громкость"], ["vol_music", "Музыка"], ["vol_sfx", "Станки и инструмент"],
	["vol_env", "Звуки окружения"], ["vol_ui", "Интерфейс"]]   # 1.29: цех, быт, голоса и город — одним ползунком


## on_toggle(key, value) — для того, что нужно применить в текущей сцене (камера, снабжение).
static func build(v: VBoxContainer, on_toggle: Callable = Callable()) -> void:
	v.add_child(UITheme.label("Игра", 16, UITheme.TEXT, UITheme.f_semi))
	for o in TOGGLES:
		var key := str(o[0])
		var cb := CheckBox.new()
		cb.text = str(o[1])
		cb.focus_mode = Control.FOCUS_NONE
		cb.button_pressed = bool(Game.settings.get(key, false))
		cb.toggled.connect(func(val: bool) -> void:
			Game.settings[key] = val
			Game.save_settings()
			if key == "fullscreen":
				Game.apply_window()
			if on_toggle.is_valid():
				on_toggle.call(key, val))
		v.add_child(cb)
	v.add_child(_choice("Игровой час", [[1.5, "медленно (45 с)"], [1.0, "обычно (30 с)"], [0.66, "быстро (20 с)"], [0.4, "очень быстро (12 с)"]], "hour_len",
		"Сколько реальных секунд длится игровой час на обычной скорости"))
	# 1.38: заголовок «Звук» — со значком владельца «музыка»
	var sh := UITheme.hbox(8)
	var mt := Tex.ui("music")
	if Tex.is_color(mt):
		var mi := TextureRect.new()
		mi.texture = mt
		mi.custom_minimum_size = Vector2(26, 26)
		mi.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		mi.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		mi.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		sh.add_child(mi)
	sh.add_child(UITheme.label("Звук", 16, UITheme.TEXT, UITheme.f_semi))
	v.add_child(sh)
	for vo in VOLUMES:
		var key2 := str(vo[0])
		var h := UITheme.hbox(10)
		var l := UITheme.label(str(vo[1]), 14)
		l.custom_minimum_size = Vector2(200, 0)
		h.add_child(l)
		var sl := HSlider.new()
		sl.min_value = 0.0
		sl.max_value = 1.0
		sl.step = 0.05
		sl.value = float(Game.settings.get(key2, 0.7))
		sl.custom_minimum_size = Vector2(260, 24)
		sl.focus_mode = Control.FOCUS_NONE
		var pct := UITheme.label("%d%%" % int(round(sl.value * 100.0)), 13, UITheme.MUTED)
		sl.value_changed.connect(func(val: float) -> void:
			Game.settings[key2] = val
			pct.text = "%d%%" % int(round(val * 100.0))
			Snd.apply_volumes())
		sl.drag_ended.connect(func(_c: bool) -> void:
			Game.save_settings()
			Snd.play("n_info", -4.0))
		h.add_child(sl)
		h.add_child(pct)
		v.add_child(h)
	v.add_child(_choice("Подбор музыки", [[0.0, "по времени суток"], [1.0, "всё подряд"], [2.0, "только вальсы"]], "music_mode",
		"По времени суток: утром — бодрее, днём — рабочий ритм, в аврал — марш, ночью — тихо"))
	v.add_child(UITheme.label("Экран", 16, UITheme.TEXT, UITheme.f_semi))
	v.add_child(_choice("Качество эффектов", [[0.0, "низкое — без искр и дыма"], [1.0, "среднее"], [2.0, "высокое"]], "quality",
		"Искры, стружка, пар, дым, листья и облака. На слабых компьютерах поставьте пониже"))
	v.add_child(_choice("Предел кадров", [[0.0, "без предела"], [60.0, "60"], [120.0, "120"], [144.0, "144"], [240.0, "240"]], "fps_cap",
		"Сколько кадров в секунду рисовать. Без предела — сколько потянет компьютер", func() -> void: Game.apply_window()))
	v.add_child(_choice("Синхронизация (V-Sync)", [[0.0, "выкл."], [1.0, "вкл. — по частоте монитора"]], "vsync",
		"Включите, если картинка «рвётся» по горизонтали. Тогда кадров не больше, чем герц у монитора", func() -> void: Game.apply_window()))
	v.add_child(_choice("Масштаб интерфейса", [[0.85, "85%"], [1.0, "100%"], [1.15, "115%"], [1.3, "130%"]], "ui_scale", "Размер кнопок и текста", func() -> void: Game.apply_ui_scale()))


static func _choice(title: String, items: Array, key: String, tip: String, after: Callable = Callable()) -> HBoxContainer:
	var h := UITheme.hbox(10)
	var l := UITheme.label(title, 14)
	l.custom_minimum_size = Vector2(150, 0)
	l.tooltip_text = tip
	l.mouse_filter = Control.MOUSE_FILTER_STOP
	h.add_child(l)
	var ob := OptionButton.new()
	ob.focus_mode = Control.FOCUS_NONE
	var cur := float(Game.settings.get(key, 1.0))
	var best := 0
	for i in items.size():
		ob.add_item(str(items[i][1]))
		if absf(float(items[i][0]) - cur) < absf(float(items[best][0]) - cur):
			best = i
	ob.select(best)
	ob.item_selected.connect(func(i: int) -> void:
		Game.settings[key] = float(items[i][0])
		Game.save_settings()
		if after.is_valid():
			after.call())
	h.add_child(ob)
	return h
