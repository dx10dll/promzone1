extends SceneTree
## Тест версии 1.29 «Справочник F1»: разделы и статьи книги, ссылки «См. также», поиск.
## godot --headless --path . -s res://tests/stage129b_test.gd

var fails: Array[String] = []


func check(cond: bool, what: String) -> void:
	print(("  ✓ " if cond else "  ✗ ") + what)
	if not cond:
		fails.append(what)


func _init() -> void:
	print("— разделы и статьи")
	check(HelpBook.section_count() >= 12, "разделов: %d (≥12)" % HelpBook.section_count())
	check(HelpBook.article_count() >= 50, "статей: %d (≥50)" % HelpBook.article_count())
	var ids := HelpBook.article_ids()
	var uniq: Dictionary = {}
	var empty := 0
	for id in ids:
		uniq[id] = true
		var a := HelpBook.article(id)
		if str(a.get("title", "")) == "" or HelpBook.plain_text(str(a.get("text", ""))).length() < 60:
			empty += 1
	check(uniq.size() == ids.size(), "id статей не повторяются")
	check(empty == 0, "у каждой статьи есть заголовок и текст (пустых: %d)" % empty)
	for s: Dictionary in HelpBook.SECTIONS:
		check((s["arts"] as Array).size() >= 3, "раздел «%s»: %d статей" % [str(s["title"]), (s["arts"] as Array).size()])

	print("— ссылки")
	var bad := HelpBook.broken_links()
	check(bad.is_empty(), "все «См. также» ведут на статьи %s" % (", ".join(bad) if not bad.is_empty() else ""))

	print("— поиск")
	var r := HelpBook.search("поддон")
	check(not r.is_empty(), "«поддон»: %d статей" % r.size())
	check(r.has("unload_zone") and r.has("ship_zone"), "«поддон» находит зоны разгрузки и отгрузки")
	check(not HelpBook.search("ПОДДОН").is_empty(), "поиск без учёта регистра")
	check(not HelpBook.search("аккумулятор").is_empty(), "«аккумулятор» находится в тексте")
	check(HelpBook.search("кредит")[0] == "loans", "совпадение в заголовке — первым (%s)" % HelpBook.search("кредит")[0])
	check(HelpBook.search("абракадабра").is_empty(), "нет совпадений — пусто")
	check(HelpBook.search("  ").is_empty(), "пустой запрос — пусто")
	check(HelpBook.plain_text("[b]Цех[/b] и [color=#fff]склад[/color]") == "Цех и склад", "BBCode убирается из текста поиска")

	print("— 1.29: факты")
	check(HelpBook.plain_text(str(HelpBook.article("stall").get("text", ""))).contains("Простой"), "вкладка называется «Простой»")
	check(HelpBook.plain_text(str(HelpBook.article("land").get("text", ""))).contains("Продаётся"), "табличка «Продаётся» в статье о земле")
	check(HelpBook.plain_text(str(HelpBook.article("settings").get("text", ""))).contains("Подбор музыки"), "«Подбор музыки» в настройках")
	check(HelpBook.plain_text(str(HelpBook.article("unload_zone").get("text", ""))).contains("Поддон заготовок"), "«Поддон заготовок» у разгрузки")

	print("")
	if fails.is_empty():
		print("РЕЗУЛЬТАТ: всё прошло")
	else:
		print("РЕЗУЛЬТАТ: провалено %d" % fails.size())
	quit(0 if fails.is_empty() else 1)
