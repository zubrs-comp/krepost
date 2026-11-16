extends RefCounted
## Процедурная «плейсхолдер»-графика: иконки ресурсов, интерьеры комнат, жители.
## Всё рисуется примитивами, поэтому игра работает без внешних ассетов.
## Позже эти функции можно заменить спрайтами из свободных паков (см. CREDITS.md).

const OUTLINE := Color(0.1, 0.07, 0.08, 1.0)

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


static func stone(ci: CanvasItem, c: Vector2, r: float) -> void:
	var pts := PackedVector2Array([c + Vector2(-r * 0.9, r * 0.5), c + Vector2(-r * 0.6, -r * 0.5),
		c + Vector2(r * 0.1, -r * 0.85), c + Vector2(r * 0.85, -r * 0.3), c + Vector2(r * 0.8, r * 0.55)])
	ci.draw_colored_polygon(_grow(pts, r * 0.14), OUTLINE)
	ci.draw_colored_polygon(pts, Color("#9a9aa2"))
	ci.draw_colored_polygon(PackedVector2Array([c + Vector2(-r * 0.6, -r * 0.5), c + Vector2(r * 0.1, -r * 0.85),
		c + Vector2(r * 0.1, -r * 0.1)]), Color("#c4c4cc"))


static func ore(ci: CanvasItem, c: Vector2, r: float) -> void:
	stone(ci, c, r)
	for o in [Vector2(-0.3, 0.1), Vector2(0.35, 0.05), Vector2(0.0, -0.4)]:
		ci.draw_circle(c + o * r, r * 0.2, Color("#d98b4a"))
		ci.draw_circle(c + o * r + Vector2(-r * 0.05, -r * 0.05), r * 0.08, Color("#ffd9a8"))


static func essence(ci: CanvasItem, c: Vector2, r: float) -> void:
	# Флакон с сиреневой эссенцией
	ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.72, OUTLINE)
	ci.draw_circle(c + Vector2(0, r * 0.2), r * 0.6, Color("#b061e8"))
	ci.draw_circle(c + Vector2(-r * 0.2, r * 0.05), r * 0.2, Color("#e7c3ff"))
	ci.draw_rect(Rect2(c + Vector2(-r * 0.22, -r * 0.85), Vector2(r * 0.44, r * 0.5)), OUTLINE)
	ci.draw_rect(Rect2(c + Vector2(-r * 0.14, -r * 0.8), Vector2(r * 0.28, r * 0.42)), Color("#d8c8e8"))


static func resource_icon(ci: CanvasItem, res_id: String, c: Vector2, r: float) -> void:
	match res_id:
		"gold": coin(ci, c, r)
		"food": food(ci, c, r)
		"people": people(ci, c, r)
		"stone": stone(ci, c, r)
		"ore": ore(ci, c, r)
		"essence": essence(ci, c, r)


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
static func room_interior(ci: CanvasItem, type_id: String, r: Rect2, colors: Dictionary, t: float,
		cave: bool = false) -> void:
	var wall := Color(str(colors.get("wall", "#666666")))
	var floor_c := Color(str(colors.get("floor", "#333333")))
	var accent := Color(str(colors.get("accent", "#ffffff")))
	var base := Vector2(r.position.x, r.end.y - 18)
	if cave:
		# В подземелье стена — пещера (её рисует клетка), только сама обстановка
		_interior_props(ci, type_id, r, base, accent, t)
		return
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
	_interior_props(ci, type_id, r, base, accent, t)


static func _interior_props(ci: CanvasItem, type_id: String, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	match type_id:
		"throne": _throne(ci, r, base, accent, t)
		"kitchen": _kitchen(ci, r, base, accent, t)
		"mint": _mint(ci, r, base, accent, t)
		"storage": _storage(ci, r, base, accent)
		"bedroom": _bedroom(ci, r, base, accent)
		"farm": _farm(ci, r, base, accent, t)
		"mine": _mine(ci, r, base, accent, t)
		"prison": _prison(ci, r, base, accent)
		"alchemy": _alchemy(ci, r, base, accent, t)


static func _bedroom(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color) -> void:
	# Две кровати и окно
	for i in 2:
		var bx := r.position.x + 20 + i * 150
		ci.draw_rect(Rect2(Vector2(bx, base.y - 44), Vector2(110, 30)), Color("#7a4a24"))
		ci.draw_rect(Rect2(Vector2(bx + 4, base.y - 56), Vector2(102, 16)), accent)
		ci.draw_rect(Rect2(Vector2(bx + 4, base.y - 60), Vector2(30, 14)), Color.WHITE)
		ci.draw_rect(Rect2(Vector2(bx, base.y - 70), Vector2(8, 70)), Color("#5c3b1e"))
		ci.draw_rect(Rect2(Vector2(bx + 102, base.y - 50), Vector2(8, 50)), Color("#5c3b1e"))
	var w := Rect2(Vector2(r.get_center().x - 26, r.position.y + 40), Vector2(52, 60))
	ci.draw_rect(w, Color("#3b2a20"))
	ci.draw_rect(w.grow(-5), Color("#9fd0ff"))
	ci.draw_line(Vector2(w.get_center().x, w.position.y), Vector2(w.get_center().x, w.end.y), Color("#3b2a20"), 4)


static func _farm(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	# Грядки светящихся грибов
	ci.draw_rect(Rect2(Vector2(r.position.x + 10, base.y - 16), Vector2(r.size.x - 20, 16)), Color("#3b2a1e"))
	for i in 7:
		var x := r.position.x + 30 + i * 38
		var h := 26.0 + (i % 3) * 12.0
		var glow := 0.5 + sin(t * 2.0 + i) * 0.2
		ci.draw_circle(Vector2(x, base.y - h), 22, Color(accent, 0.15 * glow))
		ci.draw_rect(Rect2(Vector2(x - 4, base.y - h), Vector2(8, h - 6)), Color("#e8e0c8"))
		ci.draw_colored_polygon(PackedVector2Array([Vector2(x - 16, base.y - h + 2), Vector2(x, base.y - h - 16),
			Vector2(x + 16, base.y - h + 2)]), accent.darkened(0.1 * (i % 2)))
		ci.draw_circle(Vector2(x - 4, base.y - h - 4), 2.5, Color.WHITE)


static func _mine(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	# Рельсы, вагонетка с рудой, крепь
	ci.draw_line(Vector2(r.position.x, base.y - 4), Vector2(r.end.x, base.y - 4), Color("#5a5a60"), 4)
	var wood := Color("#7a5230")
	for x in [r.position.x + 20, r.end.x - 28]:
		ci.draw_rect(Rect2(Vector2(x, r.position.y + 30), Vector2(10, base.y - r.position.y - 30)), wood)
	ci.draw_rect(Rect2(Vector2(r.position.x + 14, r.position.y + 30), Vector2(r.size.x - 28, 10)), wood)
	var cx := r.get_center().x + sin(t * 0.6) * 40
	ci.draw_rect(Rect2(Vector2(cx - 40, base.y - 46), Vector2(80, 36)), Color("#4a4a52"))
	ci.draw_rect(Rect2(Vector2(cx - 40, base.y - 46), Vector2(80, 36)), OUTLINE, false, 3)
	for i in 4:
		ci.draw_circle(Vector2(cx - 26 + i * 17, base.y - 50), 10, accent.darkened(0.15 * (i % 2)))
	ci.draw_circle(Vector2(cx - 24, base.y - 8), 8, OUTLINE)
	ci.draw_circle(Vector2(cx + 24, base.y - 8), 8, OUTLINE)


static func _prison(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color) -> void:
	# Решётка камеры
	var cell := Rect2(Vector2(r.position.x + 120, r.position.y + 40), Vector2(r.size.x - 140, base.y - r.position.y - 40))
	ci.draw_rect(cell, Color(0, 0, 0, 0.45))
	var x := cell.position.x + 10
	while x < cell.end.x:
		ci.draw_line(Vector2(x, cell.position.y), Vector2(x, cell.end.y), accent.darkened(0.3), 6)
		x += 22
	ci.draw_rect(Rect2(cell.position, Vector2(cell.size.x, 8)), accent.darkened(0.4))
	# Стол стражника и ключи
	ci.draw_rect(Rect2(Vector2(r.position.x + 20, base.y - 40), Vector2(80, 10)), Color("#6e4a2a"))
	ci.draw_circle(Vector2(r.position.x + 50, r.position.y + 70), 10, Color("#d9b77a"))


static func _alchemy(ci: CanvasItem, r: Rect2, base: Vector2, accent: Color, t: float) -> void:
	# Котёл с бурлящей эссенцией и полки с колбами
	var cx := r.position.x + 90
	ci.draw_circle(Vector2(cx, base.y - 34), 38, Color("#26262c"))
	ci.draw_rect(Rect2(Vector2(cx - 40, base.y - 80), Vector2(80, 30)), Color("#26262c"))
	ci.draw_rect(Rect2(Vector2(cx - 34, base.y - 76), Vector2(68, 10)), accent)
	for i in 3:
		var ph := fmod(t * 0.8 + i * 0.33, 1.0)
		ci.draw_circle(Vector2(cx - 16 + i * 16, base.y - 80 - ph * 50), 5 + ph * 5, Color(accent, 0.6 * (1.0 - ph)))
	for i in 4:
		var px := r.end.x - 140 + i * 34
		ci.draw_rect(Rect2(Vector2(r.end.x - 150, r.position.y + 70), Vector2(140, 6)), Color("#5c3b1e"))
		var c: Color = [accent, Color("#b061e8"), Color("#ff6b6b"), Color("#ffd23f")][i]
		ci.draw_circle(Vector2(px, r.position.y + 56), 11, c)
		ci.draw_rect(Rect2(Vector2(px - 3, r.position.y + 38), Vector2(6, 10)), Color("#d8c8e8"))


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
