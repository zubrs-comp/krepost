extends Node
## Точка входа: загружает сейв (или начинает новую игру), собирает замок и интерфейс.

const CastleView = preload("res://scripts/castle/castle_view.gd")
const HUD = preload("res://ui/hud.gd")

var castle: Node2D
var hud: CanvasLayer


func _ready() -> void:
	var loaded := SaveSystem.load_game()
	_apply_settings()
	if not loaded:
		GameState.new_game()
		SaveSystem.save_game()
	castle = CastleView.new()
	add_child(castle)
	hud = HUD.new()
	hud.castle = castle
	add_child(hud)
	castle.ui_blocks = hud.blocks
	castle.room_tapped.connect(hud.open_room)
	castle.empty_tapped.connect(hud.open_build)
	castle.resident_tapped.connect(hud.open_resident)
	castle.dungeon_tapped.connect(hud.open_dungeon)
	if not loaded:
		hud.show_dialog(tr("WELCOME_TITLE"), tr("WELCOME_BODY"))


## Язык: из настроек, иначе — язык системы (русский для ru/uk/be, иначе английский)
func _apply_settings() -> void:
	var loc := str(GameState.settings.get("locale", ""))
	if loc == "":
		var sys := OS.get_locale_language()
		loc = "ru" if sys in ["ru", "uk", "be", "kk"] else "en"
	GameState.settings["locale"] = loc
	TranslationServer.set_locale(loc)
	GameState.set_fps(int(GameState.settings.get("fps", 60)))
