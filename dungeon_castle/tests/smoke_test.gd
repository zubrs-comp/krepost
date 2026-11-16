extends Node
## Дымовой тест: запускает игру, делает действия и скриншоты.
## Запуск: godot --path . res://tests/smoke_test.tscn  (с xvfb-run для картинок)

const Layout = preload("res://scripts/castle/layout.gd")

var out_dir := "user://shots"
var main: Node
var failed := false


func _ready() -> void:
	SaveSystem.delete_save()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	main = load("res://scenes/main.tscn").instantiate()
	add_child(main)
	await _frames(10)
	await _shot("01_start")
	main.hud._close_dialog()
	await _frames(5)
	# --- Этап 1: работа в комнатах
	var k = GameState.room_at(2, 0)
	var m = GameState.room_at(2, 2)
	GameState.assign(GameState.residents[0], k)
	GameState.assign(GameState.residents[1], m)
	GameState.simulate(600.0, GameState.now())
	var g0: float = GameState.res["gold"]
	GameState.collect(m)
	_check(GameState.res["gold"] > g0, "золото должно собраться")
	await _frames(10)
	await _shot("02_castle")
	# --- Drag&drop пальцем: из тронного зала на лестницу 1-го яруса (копать)
	var castle = main.castle
	castle.cam.zoom = Vector2(0.62, 0.62)
	castle.cam.position = Vector2(480, 640)
	await _frames(3)
	var digger = GameState.residents[2]
	var v = castle._res_views[digger.id]
	var start: Vector2 = _to_screen(v.position + Vector2(0, -50))
	var stair_pos := Layout.cell_pos(Layout.row_of_tier(1), 1) + Vector2(160, 150)
	var end: Vector2 = _to_screen(stair_pos)
	await _drag(start, end, "03_drag_to_rock")
	_check(digger.is_digging() and digger.dig[0] == 1 and digger.dig[1] == 2, "житель должен копать лестницу 1-го яруса")
	await _frames(10)
	await _shot("04_digging")
	# Через 10 минут лестница расчищена, открыт 2-й ярус, получен камень
	GameState.simulate(600.0, GameState.now())
	_check(GameState.cell(1, 2)["s"] == "stair", "лестница 1-го яруса расчищена")
	_check(GameState.deepest_tier() >= 2, "открыт 2-й ярус")
	_check(GameState.res["stone"] > 0, "раскопки дают камень")
	# Расчищаем боковую клетку и строим грибную ферму
	GameState.cell(1, 1)["content"] = ""   # чтобы случайно не выпало логово
	GameState._clear_cell(1, 1)
	GameState.res["gold"] = 300.0
	GameState.res["stone"] = 100.0
	_check(GameState.build("farm", Layout.row_of_tier(1), 0), "ферма строится на расчищенной клетке")
	# Быстро проходим ярусы до 9-го (лестницы)
	for t in range(2, 10):
		if GameState.cell(t, 2)["s"] == "rock":
			GameState._clear_cell(t, 2)
	main.hud._close_dialog()
	main.hud._dialog_queue.clear()
	main.hud._close_dialog()
	_check(GameState.lore.size() >= 4, "летопись: найдено 4 страницы, а не %d" % GameState.lore.size())
	_check(GameState.deepest_tier() == 10, "открыт 10-й ярус")
	castle.focus_deep()
	await _frames(15)
	await _shot("05_deep")
	castle.cam.position.y = Layout.cell_pos(Layout.row_of_tier(5), 0).y + 120
	await _frames(5)
	await _shot("06_tier5_lair")
	# --- Бой с логовом на 5-м ярусе (ручной ярус: логово в колонке 1)
	_check(GameState.cell(5, 1)["s"] == "rock", "логово 5-го яруса ещё скрыто породой")
	GameState._clear_cell(5, 1)
	_check(GameState.cell(5, 1)["s"] == "lair", "в породе — логово")
	for r in GameState.residents:
		r.level = 5
		r.stats = {"str": 10, "agi": 9, "int": 8}
	main.hud.open_dungeon(5, 1)
	await _frames(5)
	await _shot("07_fight_prep")
	main.hud._start_battle(5, 1)
	var bv = main.hud._battle
	await _frames(40)
	await _shot("08_battle")
	bv.speed = 6.0
	while not bv.sim.finished:
		await _frames(5)
	await _frames(100)
	await _shot("09_battle_result")
	_check(bv.sim.won, "логово должно быть побеждено")
	_check(GameState.cell(5, 1)["s"] == "open", "после победы клетка расчищена")
	bv.closed.emit(true)
	bv.queue_free()
	main.hud._battle = null
	# --- Босс Грызень на 10-м ярусе
	_check(GameState.cell(10, 2)["s"] == "boss", "на 10-м ярусе — логово босса")
	for r in GameState.residents:
		r.level = 9
		r.stats = {"str": 16, "agi": 13, "int": 10}
	main.hud._squad = main.hud._auto_squad()
	main.hud._elixir = false
	main.hud._start_battle(10, 2)
	bv = main.hud._battle
	await _frames(60)
	await _shot("10_boss")
	bv.speed = 8.0
	while not bv.sim.finished:
		await _frames(5)
	await _frames(100)
	_check(bv.sim.won, "босс должен быть побеждён прокачанным отрядом")
	_check(GameState.bosses.has(10) and GameState.deepest_tier() == 11, "после босса открыт 11-й ярус")
	await _shot("11_boss_result")
	bv.closed.emit(true)
	bv.queue_free()
	main.hud._battle = null
	main.hud._dialog_queue.clear()
	main.hud._close_dialog()
	# --- Сохранение/загрузка
	SaveSystem.save_game()
	var saved_stone: float = GameState.res["stone"]
	var saved_tiers := GameState.deepest_tier()
	GameState.res["stone"] = 0.0
	SaveSystem.load_game()
	_check(absf(GameState.res["stone"] - saved_stone) < 1.0, "камень восстановился")
	_check(GameState.deepest_tier() == saved_tiers, "ярусы восстановились")
	_check(GameState.residents[2].sprite != "", "у жителя есть спрайт")
	# Офлайн 3 часа
	GameState.last_time -= 3 * 3600
	await _frames(20)
	await _shot("12_offline")
	main.hud._close_dialog()
	main.hud.open_lore()
	await _frames(5)
	await _shot("13_lore")
	main.hud.close_sheet()
	GameState.set_locale("ru")
	main.hud.open_residents()
	await _frames(5)
	await _shot("14_residents_ru")
	print("SMOKE TEST FAILED" if failed else "SMOKE TEST OK")
	get_tree().quit(1 if failed else 0)


func _to_screen(w: Vector2) -> Vector2:
	# Input.parse_input_event ждёт координаты окна, а не вьюпорта
	var cam: Camera2D = main.castle.cam
	var vp := get_viewport().get_visible_rect().size
	var win_k := float(DisplayServer.window_get_size().x) / vp.x
	return ((w - cam.position) * cam.zoom.x + vp / 2.0) * win_k


func _drag(start: Vector2, end: Vector2, shot_name: String) -> void:
	_touch(start, true)
	for i in 14:
		var e := InputEventScreenDrag.new()
		e.position = start.lerp(end, (i + 1) / 14.0)
		e.relative = (end - start) / 14.0
		Input.parse_input_event(e)
		await _frames(1)
	await _shot(shot_name)
	_touch(end, false)
	await _frames(3)


func _check(cond: bool, msg: String) -> void:
	if not cond:
		failed = true
		printerr("FAIL: " + msg)


func _touch(p: Vector2, pressed: bool) -> void:
	var e := InputEventScreenTouch.new()
	e.position = p
	e.pressed = pressed
	Input.parse_input_event(e)


func _frames(n: int) -> void:
	for i in n:
		await get_tree().process_frame


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null:
		return
	img.save_png(out_dir + "/" + shot_name + ".png")
