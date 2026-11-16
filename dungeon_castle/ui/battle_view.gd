extends Control
## Экран автобоя: отрисовка BattleSim спрайтами, полоски здоровья, числа урона.

const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const Sprites = preload("res://scripts/castle/sprites.gd")
const Art = preload("res://scripts/castle/art.gd")
const UITheme = preload("res://ui/ui_theme.gd")

signal closed(won: bool)

var sim: BattleSim
var title: String = ""
var colors: Dictionary = {}
var speed: float = 1.0
## Крупность бойцов на экране боя и линия земли (доля высоты экрана)
const UNIT_SCALE := 1.7
const GROUND_K := 0.6

var _vis: Array = []          # по индексу бойца: {anim, t, lunge, flash, pos}
var _floats: Array = []       # {pos, text, color, life}
var _shake: float = 0.0
var _t: float = 0.0
var _end_timer: float = -1.0
var _result_shown: bool = false
var _speed_btn: Button
var _rewards_text: String = ""
var _on_finish: Callable


func start(s: BattleSim, ttl: String, biome_colors: Dictionary, on_finish: Callable) -> void:
	sim = s
	title = ttl
	colors = biome_colors
	_on_finish = on_finish
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_vis.clear()
	for u in sim.units:
		_vis.append({"anim": "idle", "t": randf(), "lunge": 0.0, "flash": 0.0})
	_layout()
	_speed_btn = Button.new()
	_speed_btn.text = "x1"
	_speed_btn.custom_minimum_size = Vector2(140, 90)
	_speed_btn.anchor_left = 1
	_speed_btn.anchor_right = 1
	_speed_btn.offset_left = -170
	_speed_btn.offset_right = -30
	_speed_btn.offset_top = 330
	_speed_btn.offset_bottom = 420
	_speed_btn.pressed.connect(func() -> void:
		speed = 2.0 if speed < 1.5 else 1.0
		_speed_btn.text = "x%d" % int(speed))
	add_child(_speed_btn)


## Позиции бойцов: герои слева смотрят вправо, враги справа
func _layout() -> void:
	var vp := get_viewport_rect().size
	var ground := vp.y * GROUND_K
	var heroes := sim.side_units(0, false)
	var foes := sim.side_units(1, false)
	for i in heroes.size():
		_vis[int(heroes[i]["idx"])]["pos"] = Vector2(vp.x * 0.40 - i * 165, ground + (i % 2) * 50)
	var x := vp.x * 0.62
	for i in foes.size():
		var big := bool(foes[i].get("boss", false))
		if big:
			x += 40
		_vis[int(foes[i]["idx"])]["pos"] = Vector2(x, ground + (i % 2) * 50)
		x += 230 if big else 150


func _process(delta: float) -> void:
	_t += delta
	var dt := delta * speed
	if not sim.finished:
		for e in sim.step(dt):
			_on_event(e)
	elif _end_timer >= 0.0:
		_end_timer -= delta
		if _end_timer < 0.0 and not _result_shown:
			_show_result()
	for i in _vis.size():
		var v: Dictionary = _vis[i]
		v["t"] = float(v["t"]) + dt
		v["lunge"] = maxf(float(v["lunge"]) - dt * 3.0, 0.0)
		v["flash"] = maxf(float(v["flash"]) - dt * 4.0, 0.0)
		var u: Dictionary = sim.units[i]
		var a := str(v["anim"])
		# Анимация удара/урона закончилась — назад в стойку
		if a in ["attack", "hit"] and float(v["t"]) >= Sprites.anim_length(str(u["sprite"]), a) and bool(u["alive"]):
			v["anim"] = "idle"
			v["t"] = 0.0
	for f in _floats:
		f["life"] = float(f["life"]) - delta
		f["pos"] = (f["pos"] as Vector2) + Vector2(0, -70 * delta)
	_floats = _floats.filter(func(f: Dictionary) -> bool: return float(f["life"]) > 0.0)
	_shake = maxf(_shake - delta * 2.0, 0.0)
	queue_redraw()


func _on_event(e: Dictionary) -> void:
	match str(e["type"]):
		"attack":
			var v: Dictionary = _vis[int(e["src"])]
			v["anim"] = "attack"
			v["t"] = 0.0
			v["lunge"] = 1.0
		"ability":
			_shake = 1.0
			var v2: Dictionary = _vis[int(e["src"])]
			v2["anim"] = "attack"
			v2["t"] = 0.0
			_floats.append({"pos": (v2["pos"] as Vector2) + Vector2(0, -360), "text": tr("ABILITY_QUAKE"),
				"color": Color("#ffb347"), "life": 1.6, "size": 46})
		"damage":
			var dv: Dictionary = _vis[int(e["dst"])]
			dv["flash"] = 1.0
			if str(dv["anim"]) != "death":
				dv["anim"] = "hit"
				dv["t"] = 0.0
			var crit := bool(e["crit"])
			_floats.append({"pos": (dv["pos"] as Vector2) + Vector2(randf_range(-30, 30), -200),
				"text": ("%d!" if crit else "%d") % int(e["dmg"]),
				"color": Color("#ffd23f") if crit else Color.WHITE, "life": 1.0, "size": 46 if crit else 36})
		"death":
			var xv: Dictionary = _vis[int(e["dst"])]
			xv["anim"] = "death"
			xv["t"] = 0.0
		"end":
			_end_timer = 1.4


func _show_result() -> void:
	_result_shown = true
	_on_finish.call(sim.won)


## Показать итог боя (вызывает HUD после начисления наград)
func show_result(text: String) -> void:
	_rewards_text = text
	var panel := PanelContainer.new()
	panel.anchor_left = 0.08
	panel.anchor_right = 0.92
	panel.anchor_top = 0.66
	panel.anchor_bottom = 0.66
	add_child(panel)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 18)
	panel.add_child(vb)
	var t := Label.new()
	t.text = tr("BATTLE_WON") if sim.won else tr("BATTLE_LOST")
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.add_theme_font_size_override("font_size", 48)
	t.add_theme_color_override("font_color", UITheme.GOOD if sim.won else UITheme.BAD)
	vb.add_child(t)
	var b := Label.new()
	b.text = text
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 30)
	vb.add_child(b)
	var ok := Button.new()
	ok.text = tr("BTN_CONTINUE")
	ok.custom_minimum_size.y = 100
	ok.pressed.connect(func() -> void:
		closed.emit(sim.won)
		queue_free())
	vb.add_child(ok)
	_speed_btn.visible = false


func _draw() -> void:
	var vp := get_viewport_rect().size
	var off := Vector2(randf_range(-8, 8), randf_range(-8, 8)) * _shake
	draw_set_transform(off, 0.0, Vector2.ONE)
	# Пещера: стены, свод, пол
	var cave := Color(str(colors.get("cave", "#2f241d")))
	var rock := Color(str(colors.get("rock", "#6b5240")))
	var floor_c := Color(str(colors.get("floor", "#4a3a2c")))
	var light := Color(str(colors.get("light", "#ffb35c")))
	draw_rect(Rect2(Vector2(-20, -20), vp + Vector2(40, 40)), Color(0.04, 0.03, 0.03))
	var ground := vp.y * GROUND_K
	draw_polygon(PackedVector2Array([Vector2(0, 0), Vector2(vp.x, 0),
		Vector2(vp.x, ground + 80), Vector2(0, ground + 80)]),
		PackedColorArray([cave.darkened(0.5), cave.darkened(0.5), cave, cave]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 26:
		var p := Vector2(rng.randf_range(0, vp.x), rng.randf_range(vp.y * 0.05, ground))
		draw_circle(p, rng.randf_range(20, 60), rock.darkened(rng.randf_range(0.3, 0.6)))
	# Сталактиты
	for i in 12:
		var x := i * vp.x / 11.0 + rng.randf_range(-20, 20)
		var h := rng.randf_range(60, 160)
		draw_colored_polygon(PackedVector2Array([Vector2(x - 34, 0), Vector2(x + 34, 0),
			Vector2(x, h + 60)]), rock.darkened(0.35))
	draw_rect(Rect2(Vector2(0, ground + 60), Vector2(vp.x, vp.y - ground)), floor_c.darkened(0.2))
	draw_rect(Rect2(Vector2(0, ground + 60), Vector2(vp.x, 10)), floor_c.lightened(0.15))
	# Факелы с мерцанием
	for tx in [vp.x * 0.08, vp.x * 0.92]:
		var fl := 0.85 + sin(_t * 11.0 + tx) * 0.08 + sin(_t * 7.0) * 0.07
		draw_circle(Vector2(tx, ground - 200), 220 * fl, Color(light, 0.08))
		draw_circle(Vector2(tx, ground - 200), 120 * fl, Color(light, 0.12))
		draw_rect(Rect2(Vector2(tx - 7, ground - 190), Vector2(14, 60)), Color("#5c3b1e"))
		draw_circle(Vector2(tx, ground - 200), 18 * fl, Color("#ff9a2e"))
		draw_circle(Vector2(tx, ground - 197), 9 * fl, Color("#ffe066"))
	# Заголовок
	Art.text(self, Vector2(vp.x / 2, vp.y * 0.1), title, 52, Color("#ffd27a"), 8)
	Art.text(self, Vector2(vp.x / 2, vp.y * 0.1 + 64), tr("BATTLE_TIME") % int(sim.time), 30, Color("#e0cfae"), 6)
	# Бойцы: сначала дальние ряды
	var order: Array = range(sim.units.size())
	order.sort_custom(func(a: int, b: int) -> bool: return (_vis[a]["pos"] as Vector2).y < (_vis[b]["pos"] as Vector2).y)
	for i in order:
		var u: Dictionary = sim.units[i]
		var v: Dictionary = _vis[i]
		var side := int(u["side"])
		var dir := 1.0 if side == 0 else -1.0
		var lunge := sin(float(v["lunge"]) * PI) * 50.0 * dir
		var pos: Vector2 = (v["pos"] as Vector2) + Vector2(lunge, 0)
		var sc := float(u.get("scale", 1.0)) * UNIT_SCALE
		var mod := Color(1, 1, 1).lerp(Color(1, 0.4, 0.4), float(v["flash"]))
		if not bool(u["alive"]) and float(v["t"]) > 1.2:
			mod.a = clampf(1.0 - (float(v["t"]) - 1.2), 0.25, 1.0)
		Sprites.draw(self, str(u["sprite"]), str(v["anim"]), float(v["t"]), pos, side == 1, sc, mod)
		if bool(u["alive"]):
			var m := Sprites.meta(str(u["sprite"]))
			var h := float(m.get("feet", 190)) * sc
			var bar := Rect2(pos + Vector2(-60, -h - 4), Vector2(120, 16))
			draw_rect(bar, Art.OUTLINE)
			var k := float(u["hp"]) / float(u["max"])
			draw_rect(Rect2(bar.position + Vector2(2, 2), Vector2((bar.size.x - 4) * k, 12)),
				UITheme.GOOD if side == 0 else UITheme.BAD)
			Art.text(self, pos + Vector2(0, -h - 30), str(u["name"]), 24, Color.WHITE, 5)
	for f in _floats:
		Art.text(self, f["pos"], str(f["text"]), int(f.get("size", 36)), f["color"], 8)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
