class_name L
extends RefCounted
## 1.39: перевод интерфейса. Исходный язык — русский: ключ перевода — сама русская строка
## (assets/i18n/strings.csv, столбцы keys,en; русского столбца нет — без перевода TranslationServer
## возвращает ключ). Статичные надписи Label/Button/CheckBox переводит сам Godot (auto_translate),
## поэтому в коде они остаются русскими; строки с подстановкой — через L.t("…%d…") % x или tr().
## Тексты из data/*.json — через L.dt("scn.garage.desc", русский_текст): у них стабильный ключ.

const LANGS := [["ru", "Русский"], ["en", "English"]]
## Текущий язык. Пока L.apply не звали (тесты -s без автозагрузки Game) — русский, и TranslationServer
## тоже переводим на русский: иначе он взял бы язык системы и tr() в тестах отдавал бы английский.
static var _lang: String = _boot()


static func _boot() -> String:
	TranslationServer.set_locale("ru")
	return "ru"


## Язык по умолчанию: русский, если система на русском, украинском или белорусском, иначе английский.
static func default_lang() -> String:
	var os := OS.get_locale_language()
	return "ru" if os in ["ru", "uk", "be"] else "en"


## Язык из настроек ("" — по системе).
static func lang_of(setting: String) -> String:
	return setting if setting in ["ru", "en"] else default_lang()


static func apply(code: String) -> void:
	_lang = lang_of(code)
	TranslationServer.set_locale(_lang)


static func lang() -> String:
	return _lang


static func is_en() -> bool:
	return lang() == "en"


## Перевести строку (в статических функциях, где нет tr()).
static func t(s: String) -> String:
	return TranslationServer.translate(s) if _lang == "en" else s


## Текст из данных: стабильный ключ (id) — если перевода по нему нет, переводим сам русский текст.
## В английском тексте можно писать {money} — подставится args["money"] и т. п.
static func dt(id: String, ru: String, args: Dictionary = {}) -> String:
	if not is_en():
		return ru
	var s := TranslationServer.translate(id)
	if s == id:
		s = TranslationServer.translate(ru)
	return s.format(args) if not args.is_empty() else s


## Склонение по числу: forms — «день|дня|дней» (ключ перевода), в английском — «day|days».
static func pl(n: int, forms: String) -> String:
	var tf := TranslationServer.translate(forms)
	var p := tf.split("|")
	if is_en() and tf != forms:
		return p[0] if absi(n) == 1 or p.size() < 2 else p[1]
	p = forms.split("|")
	if p.size() < 3:
		return p[0]
	return plural_ru(n, p[0], p[1], p[2])


static func plural_ru(n: int, one: String, few: String, many: String) -> String:
	var n10 := absi(n) % 10
	var n100 := absi(n) % 100
	if n10 == 1 and n100 != 11:
		return one
	if n10 >= 2 and n10 <= 4 and (n100 < 12 or n100 > 14):
		return few
	return many


## Сумма словами для текстов: «300 тыс. ₽», «1,3 млн ₽» / «300,000 rubles», «1.3 million rubles».
static func money_words(v: float) -> String:
	var m := v >= 1000000.0
	var x := v / (1000000.0 if m else 1000.0)
	var num := ("%.1f" % x).trim_suffix(".0") if m else str(int(round(x)))
	if is_en():
		if m:
			return num + " million rubles"
		var d := str(int(round(v)))
		return (d.insert(d.length() - 3, ",") if d.length() > 3 else d) + " rubles"
	return num.replace(".", ",") + (" млн ₽" if m else " тыс. ₽")


const _TR := {"а": "a", "б": "b", "в": "v", "г": "g", "д": "d", "е": "e", "ё": "yo", "ж": "zh", "з": "z", "и": "i",
	"й": "y", "к": "k", "л": "l", "м": "m", "н": "n", "о": "o", "п": "p", "р": "r", "с": "s", "т": "t", "у": "u",
	"ф": "f", "х": "kh", "ц": "ts", "ч": "ch", "ш": "sh", "щ": "shch", "ъ": "", "ы": "y", "ь": "", "э": "e", "ю": "yu", "я": "ya"}


## Латиницей (имена и названия в английском): «Тамбов» → «Tambov», «Юрий» → «Yuriy».
static func translit(s: String) -> String:
	var out := ""
	var n := s.length()
	for i in n:
		var ch := s[i]
		var lo := ch.to_lower()
		if not _TR.has(lo):
			out += ch
			continue
		var t: String = _TR[lo]
		if lo == "ы" and i + 1 < n and s[i + 1].to_lower() == "й":
			continue   # «-ый» → «-y»
		if lo == "й" and i > 0 and s[i - 1].to_lower() == "ы":
			t = "y"
		if ch != lo and t != "":
			var next_up := i + 1 < n and s[i + 1] != s[i + 1].to_lower()
			t = t.to_upper() if next_up else t.left(1).to_upper() + t.substr(1)
		out += t
	return out


## Имя человека на языке игры: в английском — латиницей.
static func name(s: String) -> String:
	if not is_en():
		return s
	var c: Variant = _name_cache.get(s)   # 1.40: имена на карте просят каждый кадр — транслит считаем один раз
	if c == null:
		c = translit(s)
		_name_cache[s] = c
	return c as String


static var _name_cache: Dictionary = {}


## Дата из метки сохранения («Ср, 1-я нед. сентября») — на языке игры.
static func save_date(d: String) -> String:
	if not is_en():
		return d
	var re := RegEx.create_from_string("^(\\S+), (\\d+)-я нед\\. (\\S+)$")
	var m := re.search(d)
	if m == null:
		return d
	var mi := Season.MONTHS_GEN.find(m.get_string(3))
	if mi < 0:
		return d
	return "%s, week %s of %s" % [t(m.get_string(1)), m.get_string(2), Season.MONTHS_EN[mi]]


## Строка о сохранении в списках: «название · завод» и «сохранено … · в игре … · деньги».
static func save_rows(s: Dictionary, slot: String) -> Array[String]:
	var head := t(str(s.get("title", slot))) + ((" · " + Company.retitle(str(s["company"]))) if s.has("company") else "")
	var info := t("Сохранено %s · в игре %s %s · %s") % [_pc_time(str(s.get("saved_at", ""))), save_date(str(s.get("date", ""))), str(s.get("time", "")), Defs.money_str(float(s.get("money", 0)))]
	return [head, info]


## Время сохранения (как Game.pc_time; здесь — без автозагрузки Game: L компилируется и в тестах -s).
static func _pc_time(saved_at: String) -> String:
	var s := saved_at.replace("T", " ")
	if s.length() < 16:
		return s
	return t("%s.%s.%s в %s") % [s.substr(8, 2), s.substr(5, 2), s.substr(0, 4), s.substr(11, 5)]


## Есть ли в строке кириллица (для тестов и запасного «скрыть непереведённое»).
static func has_cyr(s: String) -> bool:
	for i in s.length():
		var c := s.unicode_at(i)
		if c >= 0x0400 and c <= 0x04FF:
			return true
	return false


## В английском — строка без перевода (осталась по-русски) не показывается: вернёт "".
static func or_hide(s: String) -> String:
	var t2 := TranslationServer.translate(s)
	return "" if is_en() and has_cyr(t2) else t2


## 1.39: перевести готовую русскую строку, собранную из шаблона («Покупка: Токарный 1К62», «Оплата: втулки × 12 для …»):
## причины в журнале денег, отказы сбыта и т. п. хранятся по-русски (по ним считает симуляция), а показываются так.
## Сначала точный перевод; иначе ищем шаблон из таблиц перевода (с %s/%d или с хвостом «: »), подставляем
## переведённые куски. Не нашли — строка как есть.
static var _tpl: Array = []   ## [префикс, RegEx, английский шаблон]


static func tx(s: String) -> String:
	if not is_en() or s == "" or not has_cyr(s):
		return s
	var e := TranslationServer.translate(s)
	if e != s:
		return e
	if _tpl.is_empty():
		_build_tpl()
	for row: Array in _tpl:
		var pre := str(row[0])
		if pre != "" and not s.begins_with(pre):
			continue
		var m := (row[1] as RegEx).search(s)
		if m == null:
			continue
		var args: Array = []
		for gi in range(1, m.get_group_count() + 1):
			args.append(_tx_arg(m.get_string(gi)))
		return str(row[2]) % args
	return s


static func _tx_arg(a: String) -> String:
	if not has_cyr(a):
		return a
	var e := TranslationServer.translate(a)
	if e != a:
		return e
	return Company.firm(a)


static func _build_tpl() -> void:
	var spec := RegEx.create_from_string("%[-+0-9.]*[sdf]")
	var rows: Array = []
	for p: String in ProjectSettings.get_setting("internationalization/locale/translations", PackedStringArray()):
		var tr_res := load(p) as Translation
		if tr_res == null or tr_res.locale != "en" or tr_res is OptimizedTranslation:   # сжатая таблица ключей не хранит
			continue
		for k: String in tr_res.get_message_list():
			var en := str(tr_res.get_message(k))
			var key := k
			if not has_cyr(key) or key.contains("|"):
				continue
			if spec.search(key) == null:
				if key.ends_with(": ") and en.ends_with(": "):   # «Покупка: » + название
					key += "%s"
					en += "%s"
				else:
					continue
			if spec.search_all(key).size() != spec.search_all(en.replace("%%", "")).size():
				continue
			var parts := spec.sub(key.replace("%%", "%"), "\u0001", true).split("\u0001")
			var re_s := "^"
			for i in parts.size():
				re_s += _re_esc(parts[i]) + ("(.+?)" if i < parts.size() - 1 else "")
			var re := RegEx.create_from_string(re_s + "$")
			if not re.is_valid():
				continue
			rows.append([parts[0], re, spec.sub(en.replace("%%", "\u0002"), "%s", true).replace("\u0002", "%%"), key.length()])
	rows.sort_custom(func(a: Array, b: Array) -> bool: return int(a[3]) > int(b[3]))
	_tpl = rows


static func _re_esc(s: String) -> String:
	var out := ""
	for ch in s:
		out += ("\\" + ch) if "\\^$.|?*+()[]{}".contains(ch) else ch
	return out
