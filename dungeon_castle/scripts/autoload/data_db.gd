extends Node
## Загрузка игровых данных из JSON. Логика игры только читает эти словари,
## поэтому баланс правится в /data без изменения кода.

var rooms: Dictionary = {}
var balance: Dictionary = {}
var names: Array = []
var biomes: Array = []
var enemies: Dictionary = {}
var dungeon: Dictionary = {}
var lore: Dictionary = {}


func _ready() -> void:
	rooms = _load_json("res://data/rooms.json")
	rooms.erase("_comment")
	balance = _load_json("res://data/balance.json")
	names = _load_json("res://data/names.json").get("names", [])
	biomes = _load_json("res://data/biomes.json").get("list", [])
	enemies = _load_json("res://data/enemies.json")
	dungeon = _load_json("res://data/dungeon.json")
	lore = _load_json("res://data/lore.json")
	lore.erase("_comment")


func _load_json(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		push_error("Не удалось открыть " + path)
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Ошибка JSON в " + path)
		return {}
	return parsed


func room(type_id: String) -> Dictionary:
	return rooms.get(type_id, {})


## Значение из массива «по уровням» (уровень 1 → индекс 0), с защитой от выхода за край
func by_level(arr: Variant, level: int, fallback: float = 0.0) -> float:
	if typeof(arr) != TYPE_ARRAY or (arr as Array).is_empty():
		return fallback
	var a: Array = arr
	return float(a[clampi(level - 1, 0, a.size() - 1)])


## Типы комнат, которые можно строить в зоне (castle/dungeon) на данном ярусе (0 — замок)
func buildable_types(zone: String = "castle", tier: int = 0) -> Array:
	var out: Array = []
	for k in rooms.keys():
		var d: Dictionary = rooms[k]
		if bool(d.get("buildable", false)) and str(d.get("zone", "castle")) == zone \
				and tier >= int(d.get("min_tier", 0)):
			out.append(k)
	return out


## Биом по номеру яруса
func biome(tier: int) -> Dictionary:
	for b in biomes:
		if tier >= int(b["from"]) and tier <= int(b["to"]):
			return b
	return biomes[biomes.size() - 1] if not biomes.is_empty() else {}


## Значение из словаря с переводами {"ru": ..., "en": ...}
func loc(d: Variant) -> String:
	if typeof(d) != TYPE_DICTIONARY:
		return str(d)
	var lang := TranslationServer.get_locale().substr(0, 2)
	return str(d.get(lang, d.get("en", "")))
