extends Node
## Дымовой тест: запускает игру, делает действия и скриншоты.
## Запуск: godot --path . res://tests/smoke_test.tscn  (с xvfb-run для картинок)

var out_dir := "user://shots"


func _ready() -> void:
	SaveSystem.delete_save()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var main: Node = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	await _shot("01_start")
	# Закрыть приветствие
	main.hud._dialog.get_child(0).get_child(2).emit_signal("pressed")
	await _frames(5)
	# Назначить жителей: двое на кухню, двое на монетный двор
	var k = GameState.room_at(2, 0)
	var m = GameState.room_at(2, 2)
	GameState.assign(GameState.residents[0], k)
	GameState.assign(GameState.residents[1], k)
	GameState.assign(GameState.residents[2], m)
	GameState.assign(GameState.residents[3], m)
	# Промотать 10 минут
	GameState.simulate(600.0, GameState.now())
	await _frames(10)
	await _shot("02_working")
	var g0: float = GameState.res["gold"]
	GameState.collect(m)
	_check(GameState.res["gold"] > g0, "золото должно собраться")
	# Стройка склада
	var ok := GameState.build("storage", 1, 0)
	_check(ok, "склад должен строиться")
	await _frames(5)
	main.hud.open_room(k.id)
	await _frames(5)
	await _shot("03_room_panel")
	main.hud.open_build(0, 1)
	await _frames(5)
	await _shot("04_build_panel")
	main.hud.close_sheet()
	# Перетаскивание жителя пальцем: из тронного зала в склад
	var castle = main.castle
	var r = GameState.residents[4]
	var v = castle._res_views[r.id]
	var cam: Camera2D = castle.cam
	var vp := get_viewport().get_visible_rect().size
	# Input.parse_input_event ждёт координаты окна, а не вьюпорта
	var win_k := float(DisplayServer.window_get_size().x) / vp.x
	var to_screen := func(w: Vector2) -> Vector2: return ((w - cam.position) * cam.zoom.x + vp / 2.0) * win_k
	var start: Vector2 = to_screen.call(v.position + Vector2(0, -40))
	var target_room = GameState.room_at(1, 0)
	var end: Vector2 = to_screen.call(Vector2(160, 240 + 150))
	_touch(start, true)
	for i in 12:
		var p := start.lerp(end, (i + 1) / 12.0)
		var e := InputEventScreenDrag.new()
		e.position = p
		e.relative = (end - start) / 12.0
		Input.parse_input_event(e)
		await _frames(1)
	await _shot("05_dragging")
	_touch(end, false)
	await _frames(3)
	_check(r.room_id == target_room.id, "житель должен переехать в склад")
	# Сохранение и загрузка
	SaveSystem.save_game()
	var saved_gold: float = GameState.res["gold"]
	GameState.res["gold"] = 0.0
	SaveSystem.load_game()
	_check(absf(GameState.res["gold"] - saved_gold) < 1.0, "золото должно восстановиться")
	# Офлайн: сдвигаем время сохранения на 3 часа назад
	GameState.last_time -= 3 * 3600
	await _frames(20)
	await _shot("06_offline")
	GameState.set_locale("en")
	await _frames(5)
	await _shot("07_english")
	print("SMOKE TEST OK")
	get_tree().quit()


func _check(cond: bool, msg: String) -> void:
	if not cond:
		printerr("FAIL: " + msg)
		get_tree().quit(1)


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = p
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(out_dir + "/" + name + ".png")
