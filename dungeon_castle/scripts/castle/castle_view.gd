extends Node2D
## Вид замка в разрезе: фон, клетки-комнаты, жители, камера.
## Обрабатывает тапы, панорамирование, pinch-zoom и drag&drop жителей.

const Art = preload("res://scripts/castle/art.gd")
const CellView = preload("res://scripts/castle/cell_view.gd")
const ResidentView = preload("res://scripts/castle/resident_view.gd")
const FloatText = preload("res://scripts/castle/float_text.gd")

signal room_tapped(room_id: int)
signal empty_tapped(row: int, col: int)
signal resident_tapped(resident_id: int)

const W := CellView.W
const H := CellView.H
const ZOOM_MIN := 0.45
const ZOOM_MAX := 2.2
const DRAG_THRESHOLD := 14.0

## Функция-проверка «точка над интерфейсом» (задаёт HUD), чтобы тапы не проходили сквозь панели
var ui_blocks: Callable = func(_p: Vector2) -> bool: return false

var cam: Camera2D
var _cells_layer: Node2D
var _res_layer: Node2D
var _fx_layer: Node2D
var _cells: Dictionary = {}       # Vector2i(row,col) -> CellView
var _res_views: Dictionary = {}   # resident id -> ResidentView

# Состояние ввода
var _touches: Dictionary = {}     # index -> экранная позиция
var _press_pos: Vector2
var _press_index: int = -1
var _moved: bool = false
var _drag_candidate: ResidentView = null
var _dragging: bool = false
var _drag_screen_pos: Vector2
var _pinch_dist: float = 0.0
var _pinch_zoom: float = 1.0
var _rows: int = 3
var _cols: int = 3
var _t: float = 0.0


func _ready() -> void:
	_rows = int(DB.balance.get("grid_rows", 3))
	_cols = int(DB.balance.get("grid_cols", 3))
	_cells_layer = Node2D.new()
	add_child(_cells_layer)
	_res_layer = Node2D.new()
	add_child(_res_layer)
	_fx_layer = Node2D.new()
	_fx_layer.z_index = 60
	add_child(_fx_layer)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	GameState.rooms_changed.connect(_rebuild_cells)
	GameState.residents_changed.connect(_sync_residents)
	GameState.room_updated.connect(func(id: int) -> void: _redraw_room(id))
	GameState.locale_changed.connect(_redraw_all)
	_rebuild_cells()
	_sync_residents()
	reset_camera()


func reset_camera() -> void:
	var vp := get_viewport_rect().size
	var z := clampf(vp.x / (_cols * W + 120.0), ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position = Vector2(_cols * W / 2.0, _rows * H / 2.0 + 40.0)
	_clamp_camera()


# ------------------------------------------------------------------ клетки и жители

func _rebuild_cells() -> void:
	for r in _rows:
		for c in _cols:
			var key := Vector2i(r, c)
			var cv: CellView = _cells.get(key)
			if cv == null:
				cv = CellView.new()
				cv.row = r
				cv.col = c
				cv.position = Vector2(c * W, r * H)
				_cells_layer.add_child(cv)
				_cells[key] = cv
			var room = GameState.room_at(r, c)
			cv.room_id = room.id if room != null else -1
			cv.queue_redraw()
	_sync_residents()


func _redraw_room(room_id: int) -> void:
	var room = GameState.get_room(room_id)
	if room != null:
		var cv: CellView = _cells.get(Vector2i(room.row, room.col))
		if cv != null:
			cv.queue_redraw()


func _redraw_all() -> void:
	for cv in _cells.values():
		cv.queue_redraw()
	queue_redraw()


func _sync_residents() -> void:
	var alive := {}
	for r in GameState.residents:
		alive[r.id] = true
		var v: ResidentView = _res_views.get(r.id)
		var room = GameState.get_room(r.room_id)
		if room == null:
			continue
		var cell: CellView = _cells.get(Vector2i(room.row, room.col))
		if cell == null:
			continue
		var minx := cell.position.x + CellView.WALL + 34
		var maxx := cell.position.x + W - CellView.WALL - 34
		var fy := cell.position.y + cell.floor_y() + 2
		if v == null:
			v = ResidentView.new()
			v.resident_id = r.id
			_res_layer.add_child(v)
			_res_views[r.id] = v
			v.place(minx, maxx, fy, true)
		elif not v.dragging and (absf(v.floor_y - fy) > 1.0 or v.min_x != minx):
			v.place(minx, maxx, fy, true)
	for id in _res_views.keys():
		if not alive.has(id):
			_res_views[id].queue_free()
			_res_views.erase(id)


func cell_at_world(p: Vector2) -> CellView:
	if p.x < 0 or p.y < 0:
		return null
	var c := int(p.x / W)
	var r := int(p.y / H)
	return _cells.get(Vector2i(r, c))


func resident_at_world(p: Vector2) -> ResidentView:
	var best: ResidentView = null
	for v in _res_views.values():
		if v.hit_rect().has_point(p):
			if best == null or v.position.y > best.position.y:
				best = v
	return best


func focus_resident(id: int) -> void:
	var v: ResidentView = _res_views.get(id)
	if v != null:
		cam.position = v.position + Vector2(0, -40)
		_clamp_camera()


# ------------------------------------------------------------------ координаты и камера

func screen_to_world(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return cam.position + (p - vp / 2.0) / cam.zoom.x


func _clamp_camera() -> void:
	var margin := 300.0
	var minp := Vector2(-margin, -H * 1.5)
	var maxp := Vector2(_cols * W + margin, _rows * H + H * 1.5)
	cam.position = cam.position.clamp(minp, maxp)


func _set_zoom_at(z: float, screen_anchor: Vector2) -> void:
	var before := screen_to_world(screen_anchor)
	z = clampf(z, ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	var after := screen_to_world(screen_anchor)
	cam.position += before - after
	_clamp_camera()


# ------------------------------------------------------------------ ввод

func _unhandled_input(e: InputEvent) -> void:
	if e is InputEventScreenTouch:
		_on_touch(e)
	elif e is InputEventScreenDrag:
		_on_drag(e)
	elif e is InputEventMouseButton and e.pressed:
		# Колесо мыши — зум (для отладки на ПК)
		if e.button_index == MOUSE_BUTTON_WHEEL_UP:
			_set_zoom_at(cam.zoom.x * 1.1, e.position)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_set_zoom_at(cam.zoom.x / 1.1, e.position)
	elif e is InputEventMagnifyGesture:
		_set_zoom_at(cam.zoom.x * e.factor, e.position)


func _on_touch(e: InputEventScreenTouch) -> void:
	if e.pressed:
		if _touches.is_empty() and ui_blocks.call(e.position):
			return
		_touches[e.index] = e.position
		if _touches.size() == 1:
			_press_index = e.index
			_press_pos = e.position
			_moved = false
			_drag_candidate = resident_at_world(screen_to_world(e.position))
		elif _touches.size() == 2:
			# Второй палец: отменяем перетаскивание и начинаем pinch
			_cancel_drag()
			var pts: Array = _touches.values()
			_pinch_dist = maxf((pts[0] as Vector2).distance_to(pts[1]), 1.0)
			_pinch_zoom = cam.zoom.x
		get_viewport().set_input_as_handled()
	else:
		if not _touches.has(e.index):
			return
		if _touches.size() == 1 and e.index == _press_index:
			if _dragging:
				_drop(e.position)
			elif not _moved:
				_tap(e.position)
		_touches.erase(e.index)
		if _touches.is_empty():
			_drag_candidate = null
			_dragging = false
		get_viewport().set_input_as_handled()


func _on_drag(e: InputEventScreenDrag) -> void:
	if not _touches.has(e.index):
		return
	_touches[e.index] = e.position
	if _touches.size() >= 2:
		var pts: Array = _touches.values()
		var a: Vector2 = pts[0]
		var b: Vector2 = pts[1]
		var mid := (a + b) / 2.0
		_set_zoom_at(_pinch_zoom * a.distance_to(b) / _pinch_dist, mid)
		# Двумя пальцами можно и двигать карту
		cam.position -= e.relative / 2.0 / cam.zoom.x
		_clamp_camera()
		return
	if not _moved and e.position.distance_to(_press_pos) > DRAG_THRESHOLD:
		_moved = true
		if _drag_candidate != null:
			_dragging = true
			_drag_candidate.begin_drag()
	if _dragging:
		_drag_screen_pos = e.position
		_drag_candidate.drag_to(screen_to_world(e.position))
		_update_highlights()
	elif _moved:
		cam.position -= e.relative / cam.zoom.x
		_clamp_camera()
	get_viewport().set_input_as_handled()


func _tap(screen_pos: Vector2) -> void:
	var w := screen_to_world(screen_pos)
	var rv := resident_at_world(w)
	if rv != null:
		resident_tapped.emit(rv.resident_id)
		return
	var cell := cell_at_world(w)
	if cell == null:
		return
	if cell.room_id < 0:
		empty_tapped.emit(cell.row, cell.col)
		return
	var room = GameState.get_room(cell.room_id)
	if cell.bubble_visible():
		var res_id := str(room.def().get("resource", ""))
		var got := GameState.collect(room)
		if got > 0:
			spawn_float(cell.position + cell.bubble_center(), "+%d" % int(got), res_id)
			return
	room_tapped.emit(cell.room_id)


func _drop(screen_pos: Vector2) -> void:
	var v := _drag_candidate
	var r = GameState.get_resident(v.resident_id)
	var cell := cell_at_world(screen_to_world(screen_pos))
	v.end_drag()
	_clear_highlights()
	if cell != null and cell.room_id >= 0 and r != null:
		var room = GameState.get_room(cell.room_id)
		if room.id != r.room_id and GameState.assign(r, room):
			if room.type != "throne":
				var eff := GameState.efficiency(r, room.type)
				spawn_float(screen_to_world(screen_pos) + Vector2(0, -60), "%d%%" % int(eff * 100), "")
	# Вернуть жителя на пол его (возможно, новой) комнаты
	_sync_residents()
	var room_now = GameState.get_room(r.room_id) if r != null else null
	if room_now != null:
		var cv: CellView = _cells.get(Vector2i(room_now.row, room_now.col))
		v.place(cv.position.x + CellView.WALL + 34, cv.position.x + W - CellView.WALL - 34,
			cv.position.y + cv.floor_y() + 2, false)
		v.position.x = clampf(screen_to_world(screen_pos).x, v.min_x, v.max_x)


func _cancel_drag() -> void:
	if _dragging and _drag_candidate != null:
		_drag_candidate.end_drag()
		_clear_highlights()
		_sync_residents()
		var r = GameState.get_resident(_drag_candidate.resident_id)
		var room = GameState.get_room(r.room_id) if r != null else null
		if room != null:
			var cv: CellView = _cells.get(Vector2i(room.row, room.col))
			_drag_candidate.place(cv.position.x + CellView.WALL + 34, cv.position.x + W - CellView.WALL - 34,
				cv.position.y + cv.floor_y() + 2, true)
	_dragging = false
	_drag_candidate = null


func _update_highlights() -> void:
	var r = GameState.get_resident(_drag_candidate.resident_id)
	var over := cell_at_world(screen_to_world(_drag_screen_pos))
	for cv in _cells.values():
		var h := 0
		if cv.room_id >= 0 and r != null:
			var room = GameState.get_room(cv.room_id)
			if room.id != r.room_id:
				h = 1 if GameState.can_assign(r, room) else 2
			if cv != over and h == 1:
				h = 1
		if cv.highlight != h:
			cv.highlight = h
			cv.queue_redraw()


func _clear_highlights() -> void:
	for cv in _cells.values():
		if cv.highlight != 0:
			cv.highlight = 0
			cv.queue_redraw()


func spawn_float(world_pos: Vector2, text: String, res_id: String) -> void:
	var f := FloatText.new()
	f.text = text
	f.res_id = res_id
	f.position = world_pos
	_fx_layer.add_child(f)


func _process(delta: float) -> void:
	_t += delta
	# Автопрокрутка у края экрана при перетаскивании жителя
	if _dragging:
		var vp := get_viewport_rect().size
		var edge := 120.0
		var v := Vector2.ZERO
		if _drag_screen_pos.y < edge + 200:
			v.y = -1
		elif _drag_screen_pos.y > vp.y - edge - 200:
			v.y = 1
		if _drag_screen_pos.x < edge:
			v.x = -1
		elif _drag_screen_pos.x > vp.x - edge:
			v.x = 1
		if v != Vector2.ZERO:
			cam.position += v * 500.0 * delta / cam.zoom.x
			_clamp_camera()
			_drag_candidate.drag_to(screen_to_world(_drag_screen_pos))
	# Облака плывут
	queue_redraw()


# ------------------------------------------------------------------ фон и каркас замка

func _draw() -> void:
	var gw := _cols * W
	var gh := _rows * H
	var ground := gh
	var big := 6000.0
	# Небо (градиент)
	var sky_top := Color("#5aa7e8")
	var sky_bot := Color("#cfe9ff")
	draw_polygon(PackedVector2Array([
		Vector2(-big, -big), Vector2(big, -big), Vector2(big, ground), Vector2(-big, ground)]),
		PackedColorArray([sky_top, sky_top, sky_bot, sky_bot]))
	# Солнце
	draw_circle(Vector2(gw + 160, -260), 90, Color(1, 0.95, 0.7, 0.35))
	draw_circle(Vector2(gw + 160, -260), 64, Color("#fff3b0"))
	# Облака
	for i in 5:
		var cx := fmod(i * 520.0 + _t * (10.0 + i * 3.0), 3200.0) - 1200.0
		var cy := -420.0 + i * 70.0
		for k in 4:
			draw_circle(Vector2(cx + k * 40, cy + (k % 2) * 12), 38 - (k % 2) * 6, Color(1, 1, 1, 0.85))
	# Дальние холмы
	_hill(Vector2(-900, ground), 1300, 260, Color("#7fb069"))
	_hill(Vector2(gw - 200, ground), 1500, 320, Color("#6a9f58"))
	_hill(Vector2(-300, ground), 900, 170, Color("#8cc272"))
	# Земля с травой
	draw_rect(Rect2(Vector2(-big, ground), Vector2(big * 2, 30)), Color("#5fa043"))
	draw_rect(Rect2(Vector2(-big, ground + 30), Vector2(big * 2, big)), Color("#5b4030"))
	draw_rect(Rect2(Vector2(-big, ground + 220), Vector2(big * 2, big)), Color("#46302a"))
	draw_rect(Rect2(Vector2(-big, ground + 480), Vector2(big * 2, big)), Color("#33231f"))
	# Камни в земле
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		var p := Vector2(rng.randf_range(-900, gw + 900), ground + rng.randf_range(60, 700))
		draw_circle(p, rng.randf_range(6, 18), Color(0, 0, 0, 0.18))
	# Вход в подземелье (будет на этапе 2)
	var dx := gw / 2.0
	var dy := ground + 120.0
	draw_rect(Rect2(Vector2(dx - 110, dy), Vector2(220, 170)), Color("#1b1416"))
	draw_circle(Vector2(dx, dy), 110, Color("#1b1416"))
	draw_arc(Vector2(dx, dy), 110, PI, TAU, 24, Color("#6b5a52"), 14)
	draw_line(Vector2(dx - 110, dy), Vector2(dx - 110, dy + 170), Color("#6b5a52"), 14)
	draw_line(Vector2(dx + 110, dy), Vector2(dx + 110, dy + 170), Color("#6b5a52"), 14)
	for i in 3:
		draw_line(Vector2(dx - 90, dy - 40 + i * 60), Vector2(dx + 90, dy + i * 60), Color("#7d7068"), 8)
	var flick := 0.8 + sin(_t * 11.0) * 0.1 + sin(_t * 7.3) * 0.1
	for sx in [-140, 140]:
		draw_circle(Vector2(dx + sx, dy - 20), 60 * flick, Color(1, 0.6, 0.2, 0.12))
		draw_rect(Rect2(Vector2(dx + sx - 5, dy - 10), Vector2(10, 40)), Color("#5c3b1e"))
		draw_circle(Vector2(dx + sx, dy - 18), 12 * flick, Color("#ff9a2e"))
		draw_circle(Vector2(dx + sx, dy - 16), 6 * flick, Color("#ffe066"))
	Art.text(self, Vector2(dx, dy + 210), tr("DUNGEON_SOON"), 28, Color("#e8d8c8"), 6)
	# Каркас замка: каменная кладка вокруг клеток
	var frame := Rect2(Vector2(-24, -24), Vector2(gw + 48, gh + 24))
	draw_rect(frame, Color("#8a8492"))
	var stone := Color("#7a7482")
	var y := frame.position.y
	var row := 0
	while y < frame.end.y:
		var off := 0.0 if row % 2 == 0 else 30.0
		var x := frame.position.x - off
		while x < frame.end.x:
			var b := Rect2(Vector2(maxf(x, frame.position.x) + 2, y + 2),
				Vector2(minf(x + 58, frame.end.x) - maxf(x, frame.position.x) - 4, 26))
			if b.size.x > 2:
				draw_rect(b, stone)
			x += 60
		y += 30
		row += 1
	# Зубцы на крыше и башенки по краям
	var top := frame.position.y
	var bx := frame.position.x
	while bx < frame.end.x - 10:
		draw_rect(Rect2(Vector2(bx, top - 40), Vector2(44, 42)), Color("#8a8492"))
		draw_rect(Rect2(Vector2(bx + 4, top - 36), Vector2(36, 34)), stone)
		bx += 72
	for tx in [frame.position.x - 30, frame.end.x - 50]:
		draw_rect(Rect2(Vector2(tx, top - 160), Vector2(80, 160)), Color("#8a8492"))
		draw_colored_polygon(PackedVector2Array([
			Vector2(tx - 14, top - 160), Vector2(tx + 94, top - 160), Vector2(tx + 40, top - 260)]),
			Color("#4f6fa8"))
		draw_rect(Rect2(Vector2(tx + 28, top - 130), Vector2(24, 40)), Color("#2b2730"))
	# Флаг наследника
	var fx := gw / 2.0
	draw_line(Vector2(fx, top - 40), Vector2(fx, top - 220), Color("#4a3426"), 8)
	var wave := sin(_t * 3.0) * 8.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(fx + 4, top - 220), Vector2(fx + 110, top - 200 + wave),
		Vector2(fx + 4, top - 165)]), Color("#c0392b"))
	draw_circle(Vector2(fx + 40, top - 195), 12, Color("#f5c518"))


func _hill(base: Vector2, width: float, height: float, col: Color) -> void:
	var pts := PackedVector2Array()
	var n := 24
	for i in n + 1:
		var k := float(i) / n
		pts.append(base + Vector2(k * width, -sin(k * PI) * height))
	draw_colored_polygon(pts, col)
