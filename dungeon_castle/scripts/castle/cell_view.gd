extends Node2D
## Клетка замка: либо построенная комната, либо пустое место под стройку.
## Позиция узла — левый верхний угол клетки.

const Art = preload("res://scripts/castle/art.gd")

const W := 320.0
const H := 240.0
const WALL := 16.0

var row: int = 0
var col: int = 0
var room_id: int = -1
## Подсветка при перетаскивании жителя: 0 — нет, 1 — можно, 2 — нельзя
var highlight: int = 0
var _t: float = 0.0


func inner_rect() -> Rect2:
	return Rect2(Vector2(WALL, WALL), Vector2(W - WALL * 2, H - WALL * 2))


## Уровень пола в локальных координатах (там ходят жители)
func floor_y() -> float:
	return H - WALL - 18.0


func _process(delta: float) -> void:
	_t += delta
	# Анимации (огонь, пресс) и таймеры стройки — перерисовываем, только когда клетка видна
	if room_id >= 0:
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
	if r == null:
		_draw_empty(ir)
	else:
		var d: Dictionary = r.def()
		Art.room_interior(self, r.type, ir, d.get("colors", {}), _t)
		var now := GameState.now()
		if r.is_building(now):
			_draw_construction(ir, r, now)
		# Табличка с названием
		var title := tr(str(d.get("name", "")))
		if r.type != "throne":
			title += "  " + tr("LVL_SHORT") % r.level
		var plate := Rect2(Vector2(W / 2 - 110, WALL + 2), Vector2(220, 34))
		draw_rect(plate, Color(0.1, 0.07, 0.08, 0.72))
		Art.text(self, plate.get_center(), title, 24, Color("#ffe9b0"), 0)
		# Счётчик работников
		if r.type != "throne":
			var n := GameState.workers_in(r.id).size()
			var slots := GameState.worker_slots(r)
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
	# Подсветка при перетаскивании
	if highlight == 1:
		draw_rect(ir, Color(0.3, 1.0, 0.4, 0.22))
		draw_rect(ir, Color(0.3, 1.0, 0.4, 0.9), false, 6.0)
	elif highlight == 2:
		draw_rect(ir, Color(1.0, 0.25, 0.2, 0.2))
		draw_rect(ir, Color(1.0, 0.25, 0.2, 0.9), false, 6.0)


func _draw_empty(ir: Rect2) -> void:
	draw_rect(ir, Color("#2b2730"))
	# Пунктирная рамка
	var step := 24.0
	var x := ir.position.x
	while x < ir.end.x:
		draw_line(Vector2(x, ir.position.y + 6), Vector2(minf(x + 12, ir.end.x), ir.position.y + 6), Color("#6d6578"), 3)
		draw_line(Vector2(x, ir.end.y - 6), Vector2(minf(x + 12, ir.end.x), ir.end.y - 6), Color("#6d6578"), 3)
		x += step
	var c := ir.get_center()
	draw_circle(c + Vector2(0, -14), 30, Color("#3d3745"))
	draw_rect(Rect2(c + Vector2(-4, -36), Vector2(8, 44)), Color("#a99fb8"))
	draw_rect(Rect2(c + Vector2(-22, -18), Vector2(44, 8)), Color("#a99fb8"))
	Art.text(self, c + Vector2(0, 44), tr("CELL_BUILD"), 24, Color("#a99fb8"), 0)


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
