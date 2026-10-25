class_name Links
extends RefCounted
## 1.20: куда ведёт уведомление — окно (и раздел), где с этим разбираться. Любое уведомление кликабельно:
## если подходящего окна нет — открывается журнал событий.
static func target(text: String, fallback: String = "events:log") -> String:
	var t := text.to_lower()
	var rules: Array = [
		[["зарплат", "трудовая инспекц", "не платят", "salar", "wage", "labor inspect", "unpaid"], "finance:summary"],
		[["кредит", "налог", "касс", "в долгах", "долг ", "неустойк", "банк", "loan", "tax", "cash", "in debt", "debt ", "penalt", "bank"], "finance:summary"],
		[["грант", "grant"], "finance:grants"],
		[["страхов", "insur"], "finance:insurance"],
		[["снабжени", "металл", "расходник", "инструмент", "поставщик", "supply", "metal", "consumable", "tool", "supplier"], "prod:supply"],
		[["ппр", "сломал", "станок", "наладк", "переналад", "maintenance", "broke", "machine", "setup", "changeover"], "prod:machines"],
		[["некому точить", " принят", "найм", "кандидат", "уволил", "уволен", "ушёл с завода", "ушла с завода", "nobody to sharpen", " hired", "hiring", "candidate", "quit", "fired", "left the plant"], "people:staff"],
		[["обучени", "курсы", "разряд", "training", "course", "grade"], "people:train"],
		[["травм", "охрана труда", "инструктаж", "сиз", "injur", "safety", "briefing", "ppe"], "people:safety"],
		[["профсоюз", "забастовк", "union", "strike"], "events:now"],
		[["проверк", "инспектор", "пожарн", "санэпид", "штраф", "inspection", "inspector", "fire", "sanitary", "fine"], "events:insp"],
		[["контракт", "тендер", "contract", "tender"], "orders:contracts"],
		[["предложени", "сбыт", "заказ", "заказчик", "клиент", "отгруз", "просроч", "offer", "sales", "order", "customer", "client", "shipp", "overdue"], "orders:active"],
		[["техотдел", "разработк", "чертёж", "engineering office", "development", "drawing"], "office:research"],
		[["без мастера", "без рабочего места", "аврал", "отдел", "without a foreman", "without a workplace", "rush job", "department"], "office:develop"],
		[["многотиражк", "газет", "newspaper", "paper"], "events:paper"],
		[["гололёд", "отопител", "холодно", "мороз", "письм", "icy", "black ice", "heater", "cold", "frost", "letter"], "events:now"],
		[["кот ", "кошк", "котён", "cat ", "kitten"], "town:cat"],
		[["этап", "цель", "рейтинг", "достижени", "stage", "goal", "rating", "achievement"], "goals:stage"],
	]
	for r: Array in rules:
		for k: String in r[0]:
			if t.contains(k):
				return str(r[1])
	return fallback
