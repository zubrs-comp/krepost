extends Node2D
## Вид мира в разрезе: замок наверху, ярусы подземелья ниже, жители, камера.
## Обрабатывает тапы, панорамирование, pinch-zoom и drag&drop жителей (в комнаты и на раскопки).

const Art = preload("res://scripts/castle/art.gd")
const Layout = preload("res://scripts/castle/layout.gd")
const CellView = preload("res://scripts/castle/cell_view.gd")
const ResidentView = preload("res://scripts/castle/resident_view.gd")
const FloatText = preload("res://scripts/castle/float_text.gd")

signal room_tapped(room_id: int)
signal empty_tapped(row: int, col: int)
signal dungeon_tapped(tier: int, dc: int)
signal resident_tapped(resident_id: int)

const W := Layout.W
const H := Layout.H
const ZOOM_MIN := 0.4
const ZOOM_MAX := 2.2
const DRAG_THRESHOLD := 14.0

## Функция-проверка «точка над интерфейсом» (задаёт HUD), чтобы тапы не проходили сквозь панели
var ui_blocks: Callable = func(_p: Vector2) -> bool: return false

var cam: Camera2D
var _cells_layer: Node2D
var _light_layer: Node2D
var _res_layer: Node2D
var _fx_layer: Node2D
var _cells: Dictionary = {}       # Vector2i(row,col) -> CellView
var _res_views: Dictionary = {}   # resident id -> ResidentView
var _lights: Array = []           # [PointLight2D]
var _light_tex: Texture2D

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
var _cols: int = 3
var _t: float = 0.0


func _ready() -> void:
	_cols = int(DB.balance.get("grid_cols", 3))
	_cells_layer = Node2D.new()
	add_child(_cells_layer)
	_light_layer = Node2D.new()
	add_child(_light_layer)
	_res_layer = Node2D.new()
	add_child(_res_layer)
	_fx_layer = Node2D.new()
	_fx_layer.z_index = 60
	add_child(_fx_layer)
	cam = Camera2D.new()
	add_child(cam)
	cam.make_current()
	_light_tex = _make_light_texture()
	GameState.rooms_changed.connect(_rebuild_cells)
	GameState.dungeon_changed.connect(_rebuild_cells)
	GameState.residents_changed.connect(_sync_residents)
	GameState.room_updated.connect(func(_id: int) -> void: pass)
	GameState.locale_changed.connect(queue_redraw)
	GameState.cell_cleared.connect(_on_cell_cleared)
	_rebuild_cells()
	_sync_residents()
	reset_camera()


func reset_camera() -> void:
	var vp := get_viewport_rect().size
	var z := clampf(vp.x / (_cols * W + 120.0), ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	cam.position = Vector2(_cols * W / 2.0, Layout.CASTLE_ROWS * H / 2.0 + 40.0)
	_clamp_camera()


## Камера к самому глубокому открытому ярусу
func focus_deep() -> void:
	var vp := get_viewport_rect().size
	var z := clampf(vp.x / (5 * W + 60.0), ZOOM_MIN, ZOOM_MAX)
	cam.zoom = Vector2(z, z)
	var t := GameState.deepest_tier()
	var p := Layout.cell_pos(Layout.row_of_tier(t), 1)
	cam.position = Vector2(_cols * W / 2.0, p.y - H * 0.5)
	_clamp_camera()


func is_deep_view() -> bool:
	return cam.position.y > Layout.ground_y() + H * 0.5


# ------------------------------------------------------------------ клетки и жители

func _rebuild_cells() -> void:
	var wanted := {}
	for r in Layout.CASTLE_ROWS:
		for c in _cols:
			wanted[Vector2i(r, c)] = true
	var width := int(DB.dungeon.get("width", 5))
	for t in range(1, GameState.deepest_tier() + 1):
		for dc in width:
			wanted[Vector2i(Layout.row_of_tier(t), Layout.col_of(dc))] = true
	for key in wanted.keys():
		var cv: CellView = _cells.get(key)
		if cv == null:
			cv = CellView.new()
			cv.row = key.x
			cv.col = key.y
			cv.position = Layout.cell_pos(key.x, key.y)
			_cells_layer.add_child(cv)
			_cells[key] = cv
		var room = GameState.room_at(key.x, key.y)
		cv.room_id = room.id if room != null else -1
		cv.queue_redraw()
	for key in _cells.keys():
		if not wanted.has(key):
			_cells[key].queue_free()
			_cells.erase(key)
	_rebuild_lights()
	_sync_residents()
	queue_redraw()


## Факелы в подземелье — настоящие 2D-источники света с мерцанием
func _rebuild_lights() -> void:
	for l in _lights:
		l.queue_free()
	_lights.clear()
	for cv in _cells.values():
		if not cv.is_dungeon():
			continue
		var st: String = cv.state()
		if st in ["open", "stair"] or cv.room_id >= 0:
			var light := PointLight2D.new()
			light.texture = _light_tex
			light.texture_scale = 2.4
			light.energy = 0.9
			light.color = Color(str(cv.biome_colors().get("light", "#ffb35c")))
			light.position = cv.position + Vector2(40, 70)
			light.set_meta("phase", randf() * TAU)
			_light_layer.add_child(light)
			_lights.append(light)


func _make_light_texture() -> Texture2D:
	var g := Gradient.new()
	g.set_color(0, Color(1, 1, 1, 1))
	g.set_color(1, Color(1, 1, 1, 0))
	g.add_point(0.35, Color(1, 1, 1, 0.45))
	var tex := GradientTexture2D.new()
	tex.gradient = g
	tex.fill = GradientTexture2D.FILL_RADIAL
	tex.fill_from = Vector2(0.5, 0.5)
	tex.fill_to = Vector2(1.0, 0.5)
	tex.width = 128
	tex.height = 128
	return tex


func _cell_of_room(room) -> CellView:
	return _cells.get(Vector2i(room.row, room.col))


func _sync_residents() -> void:
	var alive := {}
	var dig_slot := {}
	for r in GameState.residents:
		alive[r.id] = true
		var v: ResidentView = _res_views.get(r.id)
		if v == null:
			v = ResidentView.new()
			v.resident_id = r.id
			_res_layer.add_child(v)
			_res_views[r.id] = v
		if v.dragging:
			continue
		if r.is_digging():
			# Копатель стоит у края породы со стороны прохода
			var t: int = r.dig[0]
			var dc: int = r.dig[1]
			var cv: CellView = _cells.get(Vector2i(Layout.row_of_tier(t), Layout.col_of(dc)))
			if cv == null:
				continue
			var key := "%d_%d" % [t, dc]
			var k: int = dig_slot.get(key, 0)
			dig_slot[key] = k + 1
			var left_open := str(GameState.cell(t, dc - 1).get("s", "")) in ["open", "stair"]
			var x: float
			if dc == GameState.stair_col():
				x = cv.position.x + W / 2.0 - 40 + k * 80
				v.dig_face_left = k == 1
			elif left_open:
				x = cv.position.x + 50 + k * 40
				v.dig_face_left = false
			else:
				x = cv.position.x + W - 50 - k * 40
				v.dig_face_left = true
			v.digging = true
			v.place(x, x, cv.position.y + cv.floor_y() + 2, true)
			v.position.x = x
			continue
		v.digging = false
		var room = GameState.get_room(r.room_id)
		if room == null:
			continue
		var cell := _cell_of_room(room)
		if cell == null:
			continue
		var minx := cell.position.x + CellView.WALL + 34
		var maxx := cell.position.x + W - CellView.WALL - 34
		var fy := cell.position.y + cell.floor_y() + 2
		if absf(v.floor_y - fy) > 1.0 or v.min_x != minx:
			v.place(minx, maxx, fy, true)
	for id in _res_views.keys():
		if not alive.has(id):
			_res_views[id].queue_free()
			_res_views.erase(id)


func cell_at_world(p: Vector2) -> CellView:
	var k := Layout.cell_at(p)
	return _cells.get(k)


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
		cam.position = v.position + Vector2(0, -60)
		_clamp_camera()


# ------------------------------------------------------------------ координаты и камера

func screen_to_world(p: Vector2) -> Vector2:
	var vp := get_viewport_rect().size
	return cam.position + (p - vp / 2.0) / cam.zoom.x


func _clamp_camera() -> void:
	var margin := 500.0
	var bottom := Layout.cell_pos(Layout.row_of_tier(GameState.deepest_tier()), 0).y + H * 1.2
	var minp := Vector2(-margin, -H * 1.5)
	var maxp := Vector2(_cols * W + margin, bottom)
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
		_set_zoom_at(_pinch_zoom * a.distance_to(b) / _pinch_dist, (a + b) / 2.0)
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
	if cell.room_id >= 0:
		var room = GameState.get_room(cell.room_id)
		if cell.bubble_visible():
			var res_id := str(room.def().get("resource", ""))
			var got := GameState.collect(room)
			if got > 0:
				spawn_float(cell.position + cell.bubble_center(), "+%d" % int(got), res_id)
				return
		room_tapped.emit(cell.room_id)
		return
	if cell.is_dungeon():
		if cell.state() == "open":
			empty_tapped.emit(cell.row, cell.col)
		else:
			dungeon_tapped.emit(cell.tier(), cell.dc())
		return
	empty_tapped.emit(cell.row, cell.col)


## Можно ли бросить жителя в клетку: 1 — да, 2 — нет, 0 — клетка не принимает жителей
func _drop_state(r, cv: CellView) -> int:
	if r == null or cv == null:
		return 0
	if cv.room_id >= 0:
		var room = GameState.get_room(cv.room_id)
		if room.id == r.room_id and not r.is_digging():
			return 0
		if GameState.worker_slots(room) == 0:
			return 0
		return 1 if GameState.can_assign(r, room) else 2
	if cv.is_dungeon() and cv.state() == "rock":
		if not GameState.is_diggable(cv.tier(), cv.dc()):
			return 0
		return 1 if GameState.can_dig(r, cv.tier(), cv.dc()) else 2
	return 0


func _drop(screen_pos: Vector2) -> void:
	var v := _drag_candidate
	var r = GameState.get_resident(v.resident_id)
	var wp := screen_to_world(screen_pos)
	var cell := cell_at_world(wp)
	v.end_drag()
	_clear_highlights()
	if cell != null and r != null:
		if cell.room_id >= 0:
			var room = GameState.get_room(cell.room_id)
			if (room.id != r.room_id or r.is_digging()) and GameState.assign(r, room):
				if room.type != "throne":
					spawn_float(wp + Vector2(0, -60), "%d%%" % int(GameState.efficiency(r, room.type) * 100), "")
		elif cell.is_dungeon() and cell.state() == "rock":
			if GameState.assign_dig(r, cell.tier(), cell.dc()):
				spawn_float(wp + Vector2(0, -60), "%d%%" % int(GameState.stat_efficiency(r, "str") * 100), "")
	# Вернуть жителя на место (в новую комнату или к породе)
	v.min_x = -99999.0
	_sync_residents()
	if r != null and not r.is_digging():
		v.position.x = clampf(wp.x, v.min_x, v.max_x)


func _cancel_drag() -> void:
	if _dragging and _drag_candidate != null:
		_drag_candidate.end_drag()
		_clear_highlights()
		_drag_candidate.min_x = -99999.0
		_sync_residents()
	_dragging = false
	_drag_candidate = null


func _update_highlights() -> void:
	var r = GameState.get_resident(_drag_candidate.resident_id)
	for cv in _cells.values():
		var h := _drop_state(r, cv)
		if cv.highlight != h:
			cv.highlight = h


func _clear_highlights() -> void:
	for cv in _cells.values():
		cv.highlight = 0


func _on_cell_cleared(tier: int, dc: int, rewards: Dictionary) -> void:
	var cv: CellView = _cells.get(Vector2i(Layout.row_of_tier(tier), Layout.col_of(dc)))
	if cv == null:
		return
	var y := 0.0
	for k in rewards.keys():
		if float(rewards[k]) >= 1.0:
			spawn_float(cv.position + Vector2(W / 2.0 + 20, H / 2.0 - y), "+%d" % int(rewards[k]), k)
			y += 44.0


func spawn_float(world_pos: Vector2, text: String, res_id: String) -> void:
	var f := FloatText.new()
	f.text = text
	f.res_id = res_id
	f.position = world_pos
	_fx_layer.add_child(f)


func _process(delta: float) -> void:
	_t += delta
	# Мерцание факелов
	for l in _lights:
		var ph: float = l.get_meta("phase")
		l.energy = 0.85 + sin(_t * 9.0 + ph) * 0.08 + sin(_t * 5.3 + ph * 2.0) * 0.07
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
			cam.position += v * 600.0 * delta / cam.zoom.x
			_clamp_camera()
			_drag_candidate.drag_to(screen_to_world(_drag_screen_pos))
			_update_highlights()
	queue_redraw()


# ------------------------------------------------------------------ фон и каркас замка

func _draw() -> void:
	var gw := _cols * W
	var ground := Layout.ground_y()
	var big := 8000.0
	# Небо (градиент)
	var sky_top := Color("#5aa7e8")
	var sky_bot := Color("#cfe9ff")
	draw_polygon(PackedVector2Array([
		Vector2(-big, -big), Vector2(big, -big), Vector2(big, ground), Vector2(-big, ground)]),
		PackedColorArray([sky_top, sky_top, sky_bot, sky_bot]))
	draw_circle(Vector2(gw + 160, -260), 90, Color(1, 0.95, 0.7, 0.35))
	draw_circle(Vector2(gw + 160, -260), 64, Color("#fff3b0"))
	for i in 5:
		var cx := fmod(i * 520.0 + _t * (10.0 + i * 3.0), 3200.0) - 1200.0
		var cy := -420.0 + i * 70.0
		for k in 4:
			draw_circle(Vector2(cx + k * 40, cy + (k % 2) * 12), 38 - (k % 2) * 6, Color(1, 1, 1, 0.85))
	_hill(Vector2(-900, ground), 1300, 260, Color("#7fb069"))
	_hill(Vector2(gw - 200, ground), 1500, 320, Color("#6a9f58"))
	_hill(Vector2(-300, ground), 900, 170, Color("#8cc272"))
	# Земля и толща породы
	draw_rect(Rect2(Vector2(-big, ground), Vector2(big * 2, 30)), Color("#5fa043"))
	draw_rect(Rect2(Vector2(-big, ground + 30), Vector2(big * 2, big)), Color("#4a3428"))
	# Ярусы: фон и подписи
	var deepest := GameState.deepest_tier()
	for t in range(1, deepest + 1):
		var y := Layout.cell_pos(Layout.row_of_tier(t), 0).y
		var b: Dictionary = DB.biome(t)
		var bc: Dictionary = b.get("colors", {})
		draw_rect(Rect2(Vector2(-big, y), Vector2(big * 2, H)), Color(str(bc.get("rock_dark", "#3f2f24"))).darkened(0.35))
	# Неизведанное ниже
	var bottom := Layout.cell_pos(Layout.row_of_tier(deepest + 1), 0).y
	draw_rect(Rect2(Vector2(-big, bottom), Vector2(big * 2, big)), Color("#140e0c"))
	Art.text(self, Vector2(gw / 2.0, bottom + 80), tr("DEEP_UNKNOWN"), 28, Color(1, 1, 1, 0.35), 6)
	# Каркас замка: каменная кладка вокруг клеток
	var gh := Layout.CASTLE_ROWS * H
	var frame := Rect2(Vector2(-24, -24), Vector2(gw + 48, gh + 24))
	draw_rect(frame, Color("#8a8492"))
	var stone := Color("#7a7482")
	var yy := frame.position.y
	var row := 0
	while yy < frame.end.y:
		var off := 0.0 if row % 2 == 0 else 30.0
		var x := frame.position.x - off
		while x < frame.end.x:
			var b := Rect2(Vector2(maxf(x, frame.position.x) + 2, yy + 2),
				Vector2(minf(x + 58, frame.end.x) - maxf(x, frame.position.x) - 4, 26))
			if b.size.x > 2:
				draw_rect(b, stone)
			x += 60
		yy += 30
		row += 1
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
