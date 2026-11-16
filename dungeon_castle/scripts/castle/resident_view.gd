extends Node2D
## Житель в замке: бродит по своей комнате, его можно перетащить в другую.

const Art = preload("res://scripts/castle/art.gd")

var resident_id: int = -1
## Границы прогулки по X (в координатах замка) и уровень пола
var min_x: float = 0.0
var max_x: float = 100.0
var floor_y: float = 0.0
var dragging: bool = false

var _target_x: float = 0.0
var _wait: float = 0.0
var _t: float = 0.0
var _walking: bool = false
var _facing: float = 1.0
var _speed: float = 55.0


func _ready() -> void:
	_t = randf() * 10.0
	_speed = randf_range(40.0, 70.0)
	_wait = randf_range(0.5, 3.0)


## Поставить жителя в комнату (bounds по X, пол); teleport — сразу, без прогулки
func place(minx: float, maxx: float, fy: float, teleport: bool) -> void:
	min_x = minx
	max_x = maxx
	floor_y = fy
	if teleport:
		position = Vector2(randf_range(min_x, max_x), floor_y)
	else:
		position.y = floor_y
		position.x = clampf(position.x, min_x, max_x)
	_target_x = position.x


func hit_rect() -> Rect2:
	return Rect2(position + Vector2(-28, -92), Vector2(56, 98))


func begin_drag() -> void:
	dragging = true
	z_index = 50
	scale = Vector2(1.2, 1.2)


func drag_to(world_pos: Vector2) -> void:
	position = world_pos + Vector2(0, 40)


func end_drag() -> void:
	dragging = false
	z_index = 0
	scale = Vector2.ONE


func _process(delta: float) -> void:
	_t += delta
	if dragging:
		queue_redraw()
		return
	if _wait > 0.0:
		_wait -= delta
		_walking = false
	else:
		var dx := _target_x - position.x
		if absf(dx) < 3.0:
			_wait = randf_range(1.5, 5.0)
			_target_x = randf_range(min_x, max_x)
			_walking = false
		else:
			_walking = true
			_facing = signf(dx)
			position.x += signf(dx) * minf(_speed * delta, absf(dx))
	queue_redraw()


func _draw() -> void:
	var r = GameState.get_resident(resident_id)
	if r == null:
		return
	var room = GameState.get_room(r.room_id)
	var working: bool = room != null and room.type != "throne"
	Art.resident(self, Vector2.ZERO, r.look, r.female, _facing, _walking or dragging, _t, working)
	# Имена соседей разносим по высоте, чтобы не слипались
	Art.text(self, Vector2(0, 14 + (resident_id % 2) * 18), r.display_name(), 20, Color.WHITE, 5)
	if dragging:
		# Над перетаскиваемым — эффективность в комнатах-кандидатах рисует замок
		pass
