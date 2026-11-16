extends RefCounted
## Процедурная «плейсхолдер»-графика: иконки ресурсов, интерьеры комнат, жители.
## Всё рисуется примитивами, поэтому игра работает без внешних ассетов.
## Позже эти функции можно заменить спрайтами из свободных паков (см. CREDITS.md).

const OUTLINE := Color(0.1, 0.07, 0.08, 1.0)

# Палитры внешности жителей
const TUNICS := [
	Color("#c0392b"), Color("#2e86c1"), Color("#27ae60"), Color("#8e44ad"),
	Color("#d68910"), Color("#16a085"), Color("#cb4335"), Color("#5d6d7e"),
]
const HAIRS := [
	Color("#3b2414"), Color("#d4a017"), Color("#7b3f00"), Color("#1c1c1c"),
	Color("#a0522d"), Color("#e5c07b"), Color("#8b2500"), Color("#5a5a5a"),
]
const SKINS := [Color("#f2c9a0"), Color("#e0ac80"), Color("#c68642"), Color("#8d5524")]


static func font() -> Font:
	return ThemeDB.fallback_font


## Текст с обводкой по центру точки
static func text(ci: CanvasItem, pos: Vector2, s: String, size: int, col: Color = Color.WHITE,
		outline: int = 6, align := HORIZONTAL_ALIGNMENT_CENTER, width: float = 600.0) -> void:
	var f := font()
	var x := pos.x - width / 2.0 if align == HORIZONTAL_ALIGNMENT_CENTER else pos.x
	var p := Vector2(x, pos.y + size * 0.35)
	if outline > 0:
		ci.draw_string_outline(f, p, s, align, width, size, outline, OUTLINE)
	ci.draw_string(f, p, s, align, width, size, col)


# ------------------------------------------------------------------ иконки ресурсов

static func coin(ci: CanvasItem, c: Vector2, r: float) -> void:
	ci.draw_circle(c, r, OUTLINE)
	ci.draw_circle(c, r * 0.86, Color("#f5c518"))
	ci.draw_circle(c + Vector2(-r * 0.15, -r * 0.15), r * 0.55, Color("#ffe066"))
	ci.draw_rect(Rect2(c - Vector2(r * 0.12, r * 0.4), Vector2(r * 0.24, r * 0.8)), Color("#c79100"))


static func food(ci: CanvasItem, c: Vector2, r: float) -> void:
	# Окорок: мясо + косточка
	ci.draw_line(c + Vector2(r * 0.2, r * 0.2), c + Vector2(r * 0.85, r * 0.85), OUTLINE, r * 0.42)
	ci.draw_line(c + Vector2(r * 0.2, r * 0.2), c + Vector2(r * 0.85, r * 0.85), Color("#f4ecd8"), r * 0.26)
	ci.draw_circle(c + Vector2(r * 0.85, r * 0.85), r * 0.2, Color("#f4ecd8"))
	ci.draw_circle(c + Vector2(-r * 0.1, -r * 0.1), r * 0.78, OUTLINE)
	ci.draw_circle(c + Vector2(-r * 0.1, -r * 0.1), r * 0.66, Color("#c0392b"))
	ci.draw_circle(c + Vector2(-r * 0.3, -r * 0.3), r * 0.28, Color("#e8735f"))


static func people(ci: CanvasItem, c: Vector2, r: float) -> void:
	for dx in [-0.45, 0.45]:
		var p := c + Vector2(dx * r, 0)
		ci.draw_circle(p + Vector2(0, -r * 0.35), r * 0.32, OUTLINE)
		ci.draw_circle(p + Vector2(0, -r * 0.35), r * 0.24, Color("#f2c9a0"))
		ci.draw_rect(Rect2(p + Vector2(-r * 0.32, -r * 0.05), Vector2(r * 0.64, r * 0.7)), OUTLINE)
		ci.draw_rect(Rect2(p + Vector2(-r * 0.24, 0.0), Vector2(r * 0.48, r * 0.58)), Color("#2e86c1"))


static func resource_icon(ci: CanvasItem, res_id: String, c: Vector2, r: float) -> void:
	match res_id:
		"gold": coin(ci, c, r)
		"food": food(ci, c, r)
		"people": people(ci, c, r)


# ------------------------------------------------------------------ житель

## Рисует жителя: ноги в точке origin, рост ~84 px. t — время для анимации.
static func resident(ci: CanvasItem, origin: Vector2, look: int, female: bool, facing: float,
		walking: bool, t: float, working: bool) -> void:
	var tunic: Color = TUNICS[look % TUNICS.size()]
	var hair: Color = HAIRS[(look * 3 + 1) % HAIRS.size()]
	var skin: Color = SKINS[(look * 5 + 2) % SKINS.size()]
	var bob := -absf(sin(t * 9.0)) * 4.0 if walking else 0.0
	var leg := sin(t * 9.0) * 6.0 if walking else 0.0
	var o := origin + Vector2(0, bob)
	# Тень
	ci.draw_set_transform(origin + Vector2(0, 2), 0.0, Vector2(1.0, 0.3))
	ci.draw_circle(Vector2.ZERO, 20.0, Color(0, 0, 0, 0.25))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	# Ноги
	ci.draw_line(o + Vector2(-7, -24), o + Vector2(-7 + leg, -2), OUTLINE, 8.0)
	ci.draw_line(o + Vector2(7, -24), o + Vector2(7 - leg, -2), OUTLINE, 8.0)
	ci.draw_line(o + Vector2(-7, -24), o + Vector2(-7 + leg, -4), Color("#4a3426"), 5.0)
	ci.draw_line(o + Vector2(7, -24), o + Vector2(7 - leg, -4), Color("#4a3426"), 5.0)
	# Длинные волосы за спиной
	if female:
		ci.draw_rect(Rect2(o + Vector2(-15, -74), Vector2(30, 34)), OUTLINE)
		ci.draw_rect(Rect2(o + Vector2(-13, -72), Vector2(26, 32)), hair)
	# Туника (у женщин — платье пошире)
	var w := 34.0 if female else 30.0
	var body := PackedVector2Array([
		o + Vector2(-w * 0.4, -56), o + Vector2(w * 0.4, -56),
		o + Vector2(w * 0.55, -20), o + Vector2(-w * 0.55, -20),
	])
	ci.draw_colored_polygon(_grow(body, 2.5), OUTLINE)
	ci.draw_colored_polygon(body, tunic)
	ci.draw_line(o + Vector2(-w * 0.45, -34), o + Vector2(w * 0.45, -34), tunic.darkened(0.35), 4.0)
	# Руки: при работе машут
	var arm := sin(t * 6.0) * 10.0 if working and not walking else 0.0
	ci.draw_line(o + Vector2(-w * 0.42, -52), o + Vector2(-w * 0.62, -32 - arm), OUTLINE, 8.0)
	ci.draw_line(o + Vector2(w * 0.42, -52), o + Vector2(w * 0.62, -32 + arm), OUTLINE, 8.0)
	ci.draw_line(o + Vector2(-w * 0.42, -52), o + Vector2(-w * 0.62, -32 - arm), skin, 5.0)
	ci.draw_line(o + Vector2(w * 0.42, -52), o + Vector2(w * 0.62, -32 + arm), skin, 5.0)
	# Голова
	var h := o + Vector2(0, -68)
	ci.draw_circle(h, 15.0, OUTLINE)
	ci.draw_circle(h, 13.0, skin)
	# Причёска
	ci.draw_circle(h + Vector2(0, -5), 13.0, hair)
	ci.draw_rect(Rect2(h + Vector2(-13, -6), Vector2(26, 4)), hair)
	# Глаза смотрят в сторону движения
	var ex := 4.0 * facing
	ci.draw_circle(h + Vector2(ex - 4, 2), 2.2, OUTLINE)
	ci.draw_circle(h + Vector2(ex + 4, 2), 2.2, OUTLINE)


static func _grow(poly: PackedVector2Array, d: float) -> PackedVector2Array:
	var c := Vector2.ZERO
	for p in poly:
		c += p
	c /= poly.size()
	var out := PackedVector2Array()
	for p in poly:
		out.append(p + (p - c).normalized() * d)
	return out


# ------------------------------------------------------------------ интерьеры комнат

## Рисует интерьер комнаты в прямоугольнике r (r — внутреннее пространство)
static func room_interior(ci: CanvasItem, type_id: String, r: Rect2, colors: Dictionary, t: float) -> void:
	var wall := Color(str(colors.get("wall", "#666666")))
	var floor_c := Color(str(colors.get("floor", "#333333")))
	var accent := Color(str(colors.get("accent", "#ffffff")))
	# Задняя стена с кладкой
	ci.draw_rect(r, wall)
	var brick := wall.darkened(0.12)
	var bh := 22.0
	var y := r.position.y
	var row := 0
	while y < r.end.y - 20:
		var off := 0.0 if row % 2 == 0 else 24.0
		var x := r.position.x - off
		while x < r.end.x:
			var br := Rect2(Vector2(maxf(x, r.position.x) + 2, y + 2),
				Vector2(minf(x + 46, r.end.x) - maxf(x, r.position.x) - 4, bh - 4))
			if br.size.x > 2:
				ci.draw_rect(br, brick)
			x += 48
		y += bh
		row += 1
	# Пол
	var fl := Rect2(Vector2(r.position.x, r.end.y - 18), Vector2(r.size.x, 18))
	ci.draw_rect(fl, floor_c)
	ci.draw_line(fl.position, fl.position + Vector2(r.size.x, 0), floor_c.lightened(0.25), 3.0)
	var base := Vector2(r.position.x, r.end.y - 18)
	match type_id:
		"throne": _throne(ci, r, base, accent, t)
		"kitchen": _kitchen(ci, r, base, accent, t)
		"mint": _mint(ci, r, base, accent, t)
		"storage": _storage(ci, r, base, accent)


static func _throne(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, _t: float) -> void:
	var cx := r.get_center().x
	# Ковёр
	ci.draw_rect(Rect2(Vector2(cx - 90, base.y - 4), Vector2(180, 8)), Color("#a3222a"))
	# Знамёна
	for bx in [r.position.x + 40, r.end.x - 40]:
		var top := r.position.y + 14
		ci.draw_rect(Rect2(Vector2(bx - 18, top), Vector2(36, 70)), Color("#a3222a"))
		ci.draw_colored_polygon(PackedVector2Array([
			Vector2(bx - 18, top + 70), Vector2(bx + 18, top + 70), Vector2(bx, top + 88)]), Color("#a3222a"))
		ci.draw_circle(Vector2(bx, top + 34), 9, accent)
	# Трон
	var tb := Vector2(cx, base.y)
	ci.draw_rect(Rect2(tb + Vector2(-30, -100), Vector2(60, 100)), Color("#3d1f0f"))
	ci.draw_rect(Rect2(tb + Vector2(-26, -96), Vector2(52, 92)), accent.darkened(0.15))
	ci.draw_rect(Rect2(tb + Vector2(-18, -86), Vector2(36, 50)), Color("#7a1a22"))
	ci.draw_rect(Rect2(tb + Vector2(-36, -40), Vector2(72, 14)), accent)
	for k in [-26, 0, 26]:
		ci.draw_circle(tb + Vector2(k, -104), 6, accent)


static func _kitchen(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	# Очаг с огнём и котлом
	var hx := r.position.x + 70
	ci.draw_rect(Rect2(Vector2(hx - 50, base.y - 110), Vector2(100, 110)), Color("#5a4a42"))
	ci.draw_rect(Rect2(Vector2(hx - 36, base.y - 70), Vector2(72, 70)), Color("#1a1010"))
	for i in 3:
		var fl := sin(t * 8.0 + i * 2.0) * 5.0
		ci.draw_circle(Vector2(hx - 16 + i * 16, base.y - 14 - fl * 0.5), 12 + fl * 0.4, Color("#ff7b00"))
		ci.draw_circle(Vector2(hx - 16 + i * 16, base.y - 10), 7, Color("#ffd23f"))
	ci.draw_circle(Vector2(hx, base.y - 46), 22, Color("#222222"))
	ci.draw_rect(Rect2(Vector2(hx - 24, base.y - 70), Vector2(48, 22)), Color("#333333"))
	# Пар из котла
	for i in 2:
		var ph := fmod(t * 0.7 + i * 0.5, 1.0)
		ci.draw_circle(Vector2(hx + sin(t * 2 + i) * 6, base.y - 75 - ph * 40), 6 + ph * 6, Color(1, 1, 1, 0.35 * (1.0 - ph)))
	# Полка с горшками
	var sx := r.end.x - 120
	ci.draw_rect(Rect2(Vector2(sx, r.position.y + 40), Vector2(100, 8)), Color("#5c3b1e"))
	for i in 3:
		ci.draw_circle(Vector2(sx + 18 + i * 32, r.position.y + 28), 12, [Color("#b03a2e"), accent, Color("#5d8233")][i])
	# Стол с хлебом
	ci.draw_rect(Rect2(Vector2(sx - 10, base.y - 40), Vector2(120, 10)), Color("#7a4a24"))
	ci.draw_rect(Rect2(Vector2(sx, base.y - 30), Vector2(8, 30)), Color("#5c3b1e"))
	ci.draw_rect(Rect2(Vector2(sx + 92, base.y - 30), Vector2(8, 30)), Color("#5c3b1e"))
	ci.draw_circle(Vector2(sx + 30, base.y - 48), 12, Color("#d9a35b"))
	ci.draw_circle(Vector2(sx + 62, base.y - 46), 10, Color("#c0392b"))


static func _mint(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	# Чеканный пресс
	var px := r.position.x + 80
	var press := sin(t * 3.0) * 0.5 + 0.5
	ci.draw_rect(Rect2(Vector2(px - 40, base.y - 20), Vector2(80, 20)), Color("#444b52"))
	ci.draw_rect(Rect2(Vector2(px - 34, base.y - 120), Vector2(10, 100)), Color("#5d6d7e"))
	ci.draw_rect(Rect2(Vector2(px + 24, base.y - 120), Vector2(10, 100)), Color("#5d6d7e"))
	ci.draw_rect(Rect2(Vector2(px - 40, base.y - 130), Vector2(80, 14)), Color("#34495e"))
	ci.draw_rect(Rect2(Vector2(px - 18, base.y - 116 + press * 70), Vector2(36, 22)), Color("#7f8c8d"))
	ci.draw_circle(Vector2(px, base.y - 24), 10, accent)
	# Стопки монет
	for s in 3:
		var sx := r.end.x - 140 + s * 40
		for k in 3 + s:
			ci.draw_rect(Rect2(Vector2(sx - 14, base.y - 8 - k * 7), Vector2(28, 6)), accent.darkened(0.1 * (k % 2)))
	# Сундук
	var cx := r.get_center().x + 10
	ci.draw_rect(Rect2(Vector2(cx - 34, base.y - 40), Vector2(68, 40)), Color("#6e3b1a"))
	ci.draw_rect(Rect2(Vector2(cx - 36, base.y - 48), Vector2(72, 12)), Color("#8a4b22"))
	ci.draw_rect(Rect2(Vector2(cx - 6, base.y - 36), Vector2(12, 14)), accent)


static func _storage(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color) -> void:
	# Ящики
	for i in 3:
		var bx := r.position.x + 20 + i * 62
		var size := 56.0 if i != 1 else 50.0
		var top := base.y - size - (50.0 if i == 1 else 0.0)
		_crate(ci, Rect2(Vector2(bx, top), Vector2(size, size)))
	_crate(ci, Rect2(Vector2(r.position.x + 82, base.y - 50), Vector2(50, 50)))
	# Бочки
	for i in 2:
		var bx := r.end.x - 60 - i * 54
		ci.draw_rect(Rect2(Vector2(bx - 22, base.y - 66), Vector2(44, 66)), Color("#7b4a26"))
		ci.draw_rect(Rect2(Vector2(bx - 22, base.y - 56), Vector2(44, 5)), Color("#3b3b3b"))
		ci.draw_rect(Rect2(Vector2(bx - 22, base.y - 16), Vector2(44, 5)), Color("#3b3b3b"))
	# Мешок
	ci.draw_circle(Vector2(r.end.x - 160, base.y - 20), 22, accent)
	ci.draw_circle(Vector2(r.end.x - 160, base.y - 44), 8, accent.darkened(0.2))


static func _crate(ci: CanvasItem, b: Rect2) -> void:
	ci.draw_rect(b, Color("#a0703c"))
	ci.draw_rect(b, Color("#5c3b1e"), false, 4.0)
	ci.draw_line(b.position, b.end, Color("#5c3b1e"), 3.0)
	ci.draw_line(Vector2(b.end.x, b.position.y), Vector2(b.position.x, b.end.y), Color("#5c3b1e"), 3.0)
