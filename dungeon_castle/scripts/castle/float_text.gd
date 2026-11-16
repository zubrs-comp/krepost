extends Node2D
## Всплывающая надпись «+35» над комнатой

const Art = preload("res://scripts/castle/art.gd")

var text: String = ""
var color: Color = Color.WHITE
var res_id: String = ""
var _life: float = 0.0
const LIFE := 1.2


func _process(delta: float) -> void:
	_life += delta
	position.y -= 60.0 * delta
	modulate.a = clampf(1.0 - (_life / LIFE) ** 2, 0.0, 1.0)
	if _life >= LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	if res_id != "":
		Art.resource_icon(self, res_id, Vector2(-40, 0), 16)
	Art.text(self, Vector2(10, 0), text, 34, color, 7)
