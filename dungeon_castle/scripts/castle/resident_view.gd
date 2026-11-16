extends Node2D
## Житель в замке: бродит по своей комнате или копает породу в подземелье.
## Рисуется запечённым спрайтом 3D-модели (assets/sprites).

const Art = preload("res://scripts/castle/art.gd")
const Sprites = preload("res://scripts/castle/sprites.gd")

## Масштаб спрайта в замке: человек ~120 px при комнате 240 px
const SCALE := 0.62

var resident_id: int = -1
## Границы прогулки по X (в координатах замка) и уровень пола
var min_x: float = 0.0
var max_x: float = 100.0
var floor_y: float = 0.0
var dragging: bool = false
## Копает: стоит у породы и бьёт киркой (анимация работы)
var digging: bool = false
var dig_face_left: bool = false

var _target_x: float = 0.0
var _wait: float = 0.0
var _t: float = 0.0
var _anim_t: float = 0.0
var _anim: String = "idle"
var _facing_left: bool = false
var _speed: float = 55.0


func _ready() -> void:
	_t = randf() * 10.0
	_anim_t = randf() * 2.0
	_speed = randf_range(45.0, 70.0)
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
	return Rect2(position + Vector2(-30, -125), Vector2(60, 130))


func begin_drag() -> void:
	dragging = true
	z_index = 50


func drag_to(world_pos: Vector2) -> void:
	position = world_pos + Vector2(0, 60)


func end_drag() -> void:
	dragging = false
	z_index = 0


func _set_anim(a: String) -> void:
	if a != _anim:
		_anim = a
		_anim_t = 0.0


func _process(delta: float) -> void:
	_t += delta
	_anim_t += delta
	if dragging:
		_set_anim("walk")
		queue_redraw()
		return
	var r = GameState.get_resident(resident_id)
	if digging:
		_set_anim("work")
		_facing_left = dig_face_left
		queue_redraw()
		return
	var room = GameState.get_room(r.room_id) if r != null else null
	var works: bool = room != null and room.type != "throne" and not room.is_building(GameState.now())
	if _wait > 0.0:
		_wait -= delta
		_set_anim("work" if works else "idle")
	else:
		var dx := _target_x - position.x
		if absf(dx) < 3.0:
			# Работники дольше стоят у дела, отдыхающие чаще бродят
			_wait = randf_range(4.0, 9.0) if works else randf_range(1.5, 5.0)
			_target_x = randf_range(min_x, max_x)
		else:
			_set_anim("walk")
			_facing_left = dx < 0.0
			position.x += signf(dx) * minf(_speed * delta, absf(dx))
	queue_redraw()


func _draw() -> void:
	var r = GameState.get_resident(resident_id)
	if r == null:
		return
	var sc := SCALE * (1.12 if dragging else 1.0)
	Sprites.draw(self, r.sprite, _anim, _anim_t, Vector2.ZERO, _facing_left, sc)
	# Кирка в руках у копателя
	if digging:
		var swing := sin(_anim_t * 8.0) * 0.6
		var dir := -1.0 if _facing_left else 1.0
		var hand := Vector2(18 * dir, -70)
		var tip := hand + Vector2(cos(-1.0 + swing) * 40 * dir, sin(-1.0 + swing) * 40)
		draw_line(hand, tip, Color("#6b4a2a"), 5)
		draw_line(tip + Vector2(-14 * dir, -4), tip + Vector2(14 * dir, 6), Color("#9aa0a8"), 6)
	# Имена соседей разносим по высоте, чтобы не слипались
	Art.text(self, Vector2(0, 14 + (resident_id % 2) * 18), r.display_name(), 20, Color.WHITE, 5)
