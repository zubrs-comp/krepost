extends Node2D
## Клетка мира: комната замка, пустое место под стройку или клетка яруса подземелья
## (порода, расчищено, лестница, логово, босс). Позиция узла — левый верхний угол клетки.

const Art = preload("res://scripts/castle/art.gd")
const Layout = preload("res://scripts/castle/layout.gd")

const W := Layout.W
const H := Layout.H
const WALL := 16.0

var row: int = 0
var col: int = 0
var room_id: int = -1
## Подсветка при перетаскивании жителя: 0 — нет, 1 — можно, 2 — нельзя
var highlight: int = 0
var _t: float = 0.0


func is_dungeon() -> bool:
	return Layout.is_dungeon_row(row)


func tier() -> int:
	return Layout.tier_of(row)


func dc() -> int:
	return Layout.dcol(col)


func cell_data() -> Dictionary:
	return GameState.cell(tier(), dc()) if is_dungeon() else {}


func state() -> String:
	return str(cell_data().get("s", "")) if is_dungeon() else ""


func inner_rect() -> Rect2:
	return Rect2(Vector2(WALL, WALL), Vector2(W - WALL * 2, H - WALL * 2))


## Уровень пола в локальных координатах (там ходят жители)
func floor_y() -> float:
	return H - WALL - 18.0


func biome_colors() -> Dictionary:
	return DB.biome(tier()).get("colors", {})


func _process(delta: float) -> void:
	_t += delta
	# Анимации (огонь, пресс, факелы) и таймеры — перерисовываем постоянно, только видимые
	queue_redraw()


func bubble_visible() -> bool:
	var r = GameState.get_room(room_id)
	if r == null or r.is_building(GameState.now()):
		return false
	return str(r.def().get("resource", "")) != "" and r.stored >= 1.0


func bubble_center() -> Vector2:
	return Vector2(W - 54, WALL + 40)


func _draw() -> void:
	var ir := inner_rect()
	var r = GameState.get_room(room_id) if room_id >= 0 else null
	if r != null:
		_draw_room(ir, r)
	elif is_dungeon():
		_draw_dungeon_cell(ir)
	else:
		_draw_empty(ir)
	# Подпись яруса и биома в левой клетке
	if is_dungeon() and dc() == 0:
		var b: Dictionary = DB.biome(tier())
		Art.text(self, Vector2(12, 30), tr("TIER_N") % tier(), 24, Color("#f0e0c8"), 6,
			HORIZONTAL_ALIGNMENT_LEFT, 300)
		if tier() == int(b.get("from", 1)):
			Art.text(self, Vector2(12, -18), tr(str(b.get("name", ""))).to_upper(), 30,
				Color(str(b.get("colors", {}).get("accent", "#fff"))), 7, HORIZONTAL_ALIGNMENT_LEFT, 600)
	# Подсветка при перетаскивании
	if highlight == 1:
		draw_rect(ir, Color(0.3, 1.0, 0.4, 0.22))
		draw_rect(ir, Color(0.3, 1.0, 0.4, 0.9), false, 6.0)
	elif highlight == 2:
		draw_rect(ir, Color(1.0, 0.25, 0.2, 0.2))
		draw_rect(ir, Color(1.0, 0.25, 0.2, 0.9), false, 6.0)


func _draw_room(ir: Rect2, r) -> void:
	var d: Dictionary = r.def()
	var cols: Dictionary = d.get("colors", {})
	if is_dungeon():
		_draw_cave_back(ir)
	Art.room_interior(self, r.type, ir, cols, _t, is_dungeon())
	if r.type == "prison":
		Art.text(self, ir.get_center() + Vector2(0, 30), "%d/%d" % [GameState.captives(r), GameState.captive_cap(r)],
			26, Color("#ffb3b3"), 6)
	if r.type == "mine" and GameState.is_vein(row, col):
		Art.text(self, Vector2(W - 60, H - 46), tr("VEIN_SHORT"), 20, Color("#ffcf8a"), 5)
	var now := GameState.now()
	if r.is_building(now):
		_draw_construction(ir, r, now)
	# Табличка с названием
	var title := tr(str(d.get("name", "")))
	if r.type != "throne":
		title += "  " + tr("LVL_SHORT") % r.level
	var plate := Rect2(Vector2(W / 2 - 120, WALL + 2), Vector2(240, 34))
	draw_rect(plate, Color(0.1, 0.07, 0.08, 0.72))
	Art.text(self, plate.get_center(), title, 23, Color("#ffe9b0"), 0)
	# Счётчик работников
	var slots := GameState.worker_slots(r)
	if r.type != "throne" and slots > 0:
		var n := GameState.workers_in(r.id).size()
		Art.people(self, Vector2(WALL + 26, WALL + 56), 14)
		Art.text(self, Vector2(WALL + 62, WALL + 56), "%d/%d" % [n, slots], 22, Color.WHITE, 5)
	# Пузырь с готовой продукцией
	if bubble_visible():
		var c := bubble_center()
		var full: bool = r.stored >= GameState.room_buffer(r) - 0.5
		var pulse := 1.0 + (sin(_t * 6.0) * 0.08 if full else 0.0)
		draw_circle(c, 34 * pulse, Art.OUTLINE)
		draw_circle(c, 30 * pulse, Color("#fff7e0") if not full else Color("#ffe08a"))
		Art.resource_icon(self, str(d["resource"]), c + Vector2(0, -6), 16)
		Art.text(self, c + Vector2(0, 18), str(int(r.stored)), 20, Color.WHITE, 5)


func _draw_empty(ir: Rect2) -> void:
	draw_rect(ir, Color("#2b2730"))
	_dashed(ir, Color("#6d6578"))
	var c := ir.get_center()
	_plus(c + Vector2(0, -14), Color("#a99fb8"))
	Art.text(self, c + Vector2(0, 44), tr("CELL_BUILD"), 24, Color("#a99fb8"), 0)


func _dashed(ir: Rect2, col_: Color) -> void:
	var x := ir.position.x
	while x < ir.end.x:
		draw_line(Vector2(x, ir.position.y + 6), Vector2(minf(x + 12, ir.end.x), ir.position.y + 6), col_, 3)
		draw_line(Vector2(x, ir.end.y - 6), Vector2(minf(x + 12, ir.end.x), ir.end.y - 6), col_, 3)
		x += 24.0


func _plus(c: Vector2, col_: Color) -> void:
	draw_circle(c, 30, Color(0, 0, 0, 0.3))
	draw_rect(Rect2(c + Vector2(-4, -22), Vector2(8, 44)), col_)
	draw_rect(Rect2(c + Vector2(-22, -4), Vector2(44, 8)), col_)


# ------------------------------------------------------------------ подземелье

## Задняя стена пещеры (неровный камень)
func _draw_cave_back(ir: Rect2) -> void:
	var bc := biome_colors()
	var cave := Color(str(bc.get("cave", "#2f241d")))
	var rock := Color(str(bc.get("rock", "#6b5240")))
	draw_rect(ir, cave)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([row, col, 3])
	for i in 14:
		var p := Vector2(rng.randf_range(ir.position.x, ir.end.x), rng.randf_range(ir.position.y, ir.end.y - 30))
		draw_circle(p, rng.randf_range(10, 30), rock.darkened(rng.randf_range(0.35, 0.6)))
	var fl := Color(str(bc.get("floor", "#4a3a2c")))
	draw_rect(Rect2(Vector2(ir.position.x, ir.end.y - 18), Vector2(ir.size.x, 18)), fl)
	draw_line(Vector2(ir.position.x, ir.end.y - 18), Vector2(ir.end.x, ir.end.y - 18), fl.lightened(0.2), 3)


func _draw_dungeon_cell(ir: Rect2) -> void:
	var c := cell_data()
	if c.is_empty():
		return
	match str(c["s"]):
		"rock": _draw_rock(ir, c)
		"open":
			_draw_cave_back(ir)
			_torch(Vector2(ir.position.x + 30, ir.position.y + 70))
			if bool(c.get("vein", false)):
				_vein_marks(ir)
			_plus(ir.get_center() + Vector2(0, -10), Color(1, 1, 1, 0.35))
			Art.text(self, ir.get_center() + Vector2(0, 44), tr("CELL_BUILD"), 22, Color(1, 1, 1, 0.5), 0)
		"stair": _draw_stair(ir)
		"lair": _draw_lair(ir, c, false)
		"boss": _draw_lair(ir, c, true)


func _draw_rock(ir: Rect2, c: Dictionary) -> void:
	var bc := biome_colors()
	var rock := Color(str(bc.get("rock", "#6b5240")))
	var dark := Color(str(bc.get("rock_dark", "#3f2f24")))
	var diggable := GameState.is_diggable(tier(), dc())
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), dark)
	# Каменные глыбы (стабильный узор по координатам)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([row, col])
	for i in 9:
		var p := Vector2(rng.randf_range(20, W - 20), rng.randf_range(20, H - 20))
		var rr := rng.randf_range(34, 64)
		var pts := PackedVector2Array()
		var n := 7
		for k in n:
			var a := TAU * k / n + rng.randf_range(-0.2, 0.2)
			pts.append(p + Vector2(cos(a), sin(a)) * rr * rng.randf_range(0.75, 1.1))
		draw_colored_polygon(pts, rock.darkened(rng.randf_range(0.0, 0.25)))
		draw_polyline(pts + PackedVector2Array([pts[0]]), dark.darkened(0.3), 3)
	# Блёстки содержимого (подсказка, что внутри может быть что-то)
	var content := str(c.get("content", ""))
	if content == "vein":
		_vein_marks(ir)
	var hp := float(c.get("hp", 0))
	var mx := maxf(float(c.get("max", 1)), 1.0)
	var k := 1.0 - hp / mx
	# Трещины по мере раскопок
	if k > 0.02:
		var crng := RandomNumberGenerator.new()
		crng.seed = hash([row, col, 7])
		var cracks := int(k * 8) + 1
		for i in cracks:
			var a := Vector2(crng.randf_range(40, W - 40), crng.randf_range(40, H - 40))
			var b := a + Vector2(crng.randf_range(-60, 60), crng.randf_range(-50, 50))
			var m := (a + b) / 2 + Vector2(crng.randf_range(-15, 15), crng.randf_range(-15, 15))
			draw_polyline(PackedVector2Array([a, m, b]), Color(0, 0, 0, 0.6), 4)
	var diggers := GameState.diggers_at(tier(), dc())
	if diggable:
		# Подсветка доступной породы и подсказка
		var pulse := 0.5 + sin(_t * 3.0) * 0.2
		draw_rect(Rect2(Vector2(6, 6), Vector2(W - 12, H - 12)), Color(1, 0.85, 0.5, 0.35 * pulse), false, 4)
		var bar := Rect2(Vector2(40, H - 46), Vector2(W - 80, 18))
		draw_rect(bar, Art.OUTLINE)
		draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * k, 14)), Color("#f5b041"))
		if diggers.is_empty():
			_pickaxe(Vector2(W / 2, H / 2 - 16))
			Art.text(self, Vector2(W / 2, H / 2 + 34), tr("CELL_DIG"), 24, Color("#ffe9b0"), 6)
		else:
			var rate := GameState.dig_rate(tier(), dc())
			var left := hp / maxf(rate, 0.01) * 60.0
			Art.text(self, Vector2(W / 2, H - 66), "%s  %s" % [_fmt_time(left), "%d/%d" % [diggers.size(), GameState.max_diggers()]],
				22, Color.WHITE, 5)
	else:
		draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), Color(0, 0, 0, 0.35))


func _draw_stair(ir: Rect2) -> void:
	_draw_cave_back(ir)
	var cx := ir.get_center().x
	# Колодец с деревянной лестницей вниз
	draw_rect(Rect2(Vector2(cx - 60, ir.position.y + 30), Vector2(120, ir.size.y - 30)), Color(0.05, 0.04, 0.04))
	draw_rect(Rect2(Vector2(cx - 60, H - 30), Vector2(120, 30)), Color(0.05, 0.04, 0.04))
	var wood := Color("#8a5a2e")
	draw_line(Vector2(cx - 40, ir.position.y + 20), Vector2(cx - 40, H), wood, 8)
	draw_line(Vector2(cx + 40, ir.position.y + 20), Vector2(cx + 40, H), wood, 8)
	var y := ir.position.y + 40
	while y < H:
		draw_line(Vector2(cx - 40, y), Vector2(cx + 40, y), wood.lightened(0.1), 6)
		y += 30
	_torch(Vector2(ir.position.x + 30, ir.position.y + 70))
	_torch(Vector2(ir.end.x - 30, ir.position.y + 70))
	if tier() < GameState.deepest_tier():
		Art.text(self, Vector2(cx, ir.position.y + 18), tr("STAIR_DOWN") % (tier() + 1), 20, Color("#e8d8c8"), 5)


func _draw_lair(ir: Rect2, c: Dictionary, boss: bool) -> void:
	var bc := biome_colors()
	var dark := Color(str(bc.get("rock_dark", "#3f2f24")))
	draw_rect(Rect2(Vector2.ZERO, Vector2(W, H)), dark)
	var cx := ir.get_center()
	# Чёрный провал с глазами
	var r := 92.0 if boss else 70.0
	draw_circle(cx + Vector2(0, 10), r + 10, dark.darkened(0.4))
	draw_circle(cx + Vector2(0, 10), r, Color(0.03, 0.02, 0.02))
	var blink := 1.0 if fmod(_t + row * 0.7, 4.0) > 0.15 else 0.1
	var eye := Color("#ff3b2e") if boss else Color("#ffd23f")
	for ex in [-22, 22]:
		draw_set_transform(cx + Vector2(ex, 0), 0, Vector2(1, blink))
		draw_circle(Vector2.ZERO, 9 if boss else 7, eye)
		draw_set_transform(Vector2.ZERO, 0, Vector2.ONE)
	if boss:
		# Череп над входом
		draw_circle(cx + Vector2(0, -r + 4), 26, Color("#e8dcc0"))
		draw_circle(cx + Vector2(-9, -r + 2), 6, Art.OUTLINE)
		draw_circle(cx + Vector2(9, -r + 2), 6, Art.OUTLINE)
	var reachable := GameState.is_reachable(tier(), dc())
	var label := tr("CELL_BOSS") if boss else tr("CELL_LAIR")
	Art.text(self, Vector2(W / 2, H - 44), label, 24, Color("#ffb3a8") if reachable else Color(1, 1, 1, 0.5), 6)
	if reachable:
		var pulse := 0.5 + sin(_t * 4.0) * 0.3
		draw_rect(Rect2(Vector2(6, 6), Vector2(W - 12, H - 12)), Color(1, 0.3, 0.2, 0.5 * pulse), false, 5)


func _torch(p: Vector2) -> void:
	var fl := 0.85 + sin(_t * 11.0 + p.x) * 0.08 + sin(_t * 7.3 + row) * 0.07
	draw_rect(Rect2(p + Vector2(-5, 6), Vector2(10, 34)), Color("#5c3b1e"))
	draw_circle(p, 13 * fl, Color("#ff9a2e"))
	draw_circle(p + Vector2(0, 3), 7 * fl, Color("#ffe066"))


func _vein_marks(ir: Rect2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([row, col, 5])
	for i in 7:
		var p := Vector2(rng.randf_range(ir.position.x + 20, ir.end.x - 20), rng.randf_range(ir.position.y + 30, ir.end.y - 40))
		draw_colored_polygon(PackedVector2Array([p + Vector2(-8, 0), p + Vector2(0, -10), p + Vector2(9, -2), p + Vector2(3, 8)]),
			Color("#d98b4a"))
		draw_circle(p + Vector2(-1, -3), 2.5, Color("#ffd9a8"))


func _pickaxe(c: Vector2) -> void:
	draw_line(c + Vector2(-22, 26), c + Vector2(18, -18), Art.OUTLINE, 10)
	draw_line(c + Vector2(-22, 26), c + Vector2(18, -18), Color("#a0703c"), 6)
	draw_arc(c + Vector2(22, -10), 30, PI * 1.05, PI * 1.85, 12, Art.OUTLINE, 11)
	draw_arc(c + Vector2(22, -10), 30, PI * 1.05, PI * 1.85, 12, Color("#c8ccd2"), 6)


func _draw_construction(ir: Rect2, r, now: float) -> void:
	draw_rect(ir, Color(0.12, 0.1, 0.08, 0.55))
	# Строительные леса
	var wood := Color("#c8964f")
	for i in 4:
		var x := ir.position.x + 20 + i * (ir.size.x - 40) / 3.0
		draw_line(Vector2(x, ir.position.y), Vector2(x, ir.end.y), wood, 6)
	for j in 3:
		var y := ir.position.y + 40 + j * 55
		draw_line(Vector2(ir.position.x, y), Vector2(ir.end.x, y), wood, 6)
		draw_line(Vector2(ir.position.x, y), Vector2(ir.end.x, y + 55), wood.darkened(0.2), 3)
	var total := GameState.build_time(r.type, r.target_level)
	var left := maxf(r.build_finish - now, 0.0)
	var k := 1.0 - (left / maxf(total, 0.01))
	var bar := Rect2(Vector2(ir.position.x + 30, ir.get_center().y + 20), Vector2(ir.size.x - 60, 22))
	draw_rect(bar, Art.OUTLINE)
	draw_rect(Rect2(bar.position + Vector2(3, 3), Vector2((bar.size.x - 6) * k, bar.size.y - 6)), Color("#f5b041"))
	Art.text(self, bar.get_center() + Vector2(0, -30), tr("BUILDING_LEFT") % _fmt_time(left), 22, Color.WHITE, 5)


static func _fmt_time(sec: float) -> String:
	var s := int(ceil(sec))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]
