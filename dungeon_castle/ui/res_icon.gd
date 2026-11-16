extends Control
## Иконка ресурса для интерфейса (рисуется процедурно)

const Art = preload("res://scripts/castle/art.gd")

var kind: String = "gold"


func _init(k: String = "gold", size_px: float = 48.0) -> void:
	kind = k
	custom_minimum_size = Vector2(size_px, size_px)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _draw() -> void:
	var r := minf(size.x, size.y) / 2.0
	match kind:
		"gear":
			var c := size / 2.0
			for i in 8:
				var a := i * TAU / 8.0
				draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.95, Art.OUTLINE, r * 0.38)
				draw_line(c, c + Vector2(cos(a), sin(a)) * r * 0.9, Color("#d8c39a"), r * 0.24)
			draw_circle(c, r * 0.68, Art.OUTLINE)
			draw_circle(c, r * 0.58, Color("#d8c39a"))
			draw_circle(c, r * 0.24, Art.OUTLINE)
		_:
			Art.resource_icon(self, kind, size / 2.0, r * 0.9)
