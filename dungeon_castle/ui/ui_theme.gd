extends RefCounted
## Тема интерфейса, собранная в коде: тёплое дерево и золото

const BG := Color("#2a1f1d")
const BG2 := Color("#3a2b27")
const BORDER := Color("#c99a4b")
const TEXT := Color("#f6e7c8")
const MUTED := Color("#bfa98a")
const GOOD := Color("#8fd36b")
const BAD := Color("#ff7a6b")


static func box(bg: Color, border: Color, bw: int = 4, radius: int = 18, pad: int = 16) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(bw)
	s.set_corner_radius_all(radius)
	s.set_content_margin_all(pad)
	s.shadow_color = Color(0, 0, 0, 0.35)
	s.shadow_size = 6
	s.anti_aliasing = true
	return s


static func make() -> Theme:
	var t := Theme.new()
	t.default_font_size = 34
	t.set_color("font_color", "Label", TEXT)
	t.set_color("font_outline_color", "Label", Color(0, 0, 0, 0.8))
	t.set_constant("outline_size", "Label", 0)
	# Кнопки
	var normal := box(Color("#7a4a24"), Color("#e0b060"), 4, 16, 14)
	var hover := box(Color("#8d5a2e"), Color("#ffd27a"), 4, 16, 14)
	var pressed := box(Color("#5c3519"), Color("#e0b060"), 4, 16, 14)
	var disabled := box(Color("#4a3a33"), Color("#7a6a5a"), 4, 16, 14)
	for st in [["normal", normal], ["hover", hover], ["pressed", pressed], ["disabled", disabled], ["focus", StyleBoxEmpty.new()]]:
		t.set_stylebox(st[0], "Button", st[1])
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color("#9a8a7a"))
	t.set_font_size("font_size", "Button", 32)
	# Панели
	t.set_stylebox("panel", "PanelContainer", box(BG, BORDER, 5, 26, 24))
	t.set_stylebox("panel", "Panel", box(BG, BORDER, 5, 26, 0))
	# Прокрутка: тонкая полоса
	var grab := box(Color("#c99a4b"), Color("#c99a4b"), 0, 6, 0)
	t.set_stylebox("grabber", "VScrollBar", grab)
	t.set_stylebox("grabber_highlight", "VScrollBar", grab)
	t.set_stylebox("grabber_pressed", "VScrollBar", grab)
	t.set_stylebox("scroll", "VScrollBar", box(Color(0, 0, 0, 0.2), Color(0, 0, 0, 0), 0, 6, 0))
	t.set_constant("separation", "VBoxContainer", 12)
	t.set_constant("separation", "HBoxContainer", 14)
	return t
