extends Node
## Загрузка игровых данных из JSON. Логика игры только читает эти словари,
## поэтому баланс правится в /data без изменения кода.

var rooms: Dictionary = {}
var balance: Dictionary = {}
var names: Array = []


func _ready() -> void:
	rooms = _load_json("res://data/rooms.json")
	rooms.erase("_comment")
	balance = _load_json("res://data/balance.json")
	names = _load_json("res://data/names.json").get("names", [])


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


func buildable_types() -> Array:
	var out: Array = []
	for k in rooms.keys():
		if bool(rooms[k].get("buildable", false)):
			out.append(k)
	return out
