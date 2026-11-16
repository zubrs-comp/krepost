extends Node
## Сохранение в user://save.json: автосейв каждые N секунд,
## а также при сворачивании/закрытии приложения.

const SAVE_PATH := "user://save.json"
const TMP_PATH := "user://save.tmp"

var _timer: Timer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_timer = Timer.new()
	_timer.wait_time = float(DB.balance.get("autosave_seconds", 30))
	_timer.autostart = true
	_timer.timeout.connect(save_game)
	add_child(_timer)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func save_game() -> void:
	if not GameState.ready_to_play:
		return
	# Пишем во временный файл и переименовываем: сейв не побьётся при обрыве записи
	var f := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if f == null:
		push_error("Не удалось записать сохранение: %s" % FileAccess.get_open_error())
		return
	f.store_string(JSON.stringify(GameState.to_dict(), "\t"))
	f.close()
	var dir := DirAccess.open("user://")
	if dir.file_exists("save.json"):
		dir.remove("save.json")
	dir.rename("save.tmp", "save.json")


func load_game() -> bool:
	if not has_save():
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var data: Variant = JSON.parse_string(f.get_as_text())
	if typeof(data) != TYPE_DICTIONARY:
		push_error("Сохранение повреждено, начинаем новую игру")
		return false
	GameState.from_dict(data)
	return true


func delete_save() -> void:
	if has_save():
		DirAccess.remove_absolute(ProjectSettings.globalize_path(SAVE_PATH))


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_CLOSE_REQUEST:
			save_game()
