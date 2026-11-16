extends RefCounted
## Данные жителя: имя, уровень, характеристики, где работает

const STATS := ["str", "agi", "int"]

var id: int = 0
## Индекс имени в data/names.json (имя переводится вместе с языком)
var name_idx: int = 0
var female: bool = false
var level: int = 1
var xp: float = 0.0
## Сила (str), ловкость (agi), интеллект (int)
var stats: Dictionary = {"str": 1, "agi": 1, "int": 1}
## id комнаты, где находится житель
var room_id: int = 0
## Вариант внешности (старое поле, для совместимости сохранений)
var look: int = 0
## Спрайт из assets/sprites (например, m_worker_b)
var sprite: String = ""
## Клетка подземелья, где житель копает: [ярус, колонка] или пусто
var dig: Array = []


func is_digging() -> bool:
	return dig.size() == 2


func display_name() -> String:
	if name_idx < 0 or name_idx >= DB.names.size():
		return "???"
	var n: Dictionary = DB.names[name_idx]
	var lang := TranslationServer.get_locale().substr(0, 2)
	return str(n.get(lang, n.get("en", "???")))


func stat(key: String) -> int:
	return int(stats.get(key, 0))


func xp_to_next() -> float:
	var b: Dictionary = DB.balance
	return float(b.get("xp_base", 60.0)) * pow(level, float(b.get("xp_exp", 1.5)))


func to_dict() -> Dictionary:
	return {
		"id": id, "name_idx": name_idx, "female": female, "level": level, "xp": xp,
		"stats": stats.duplicate(), "room_id": room_id, "look": look,
		"sprite": sprite, "dig": dig.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	id = int(d.get("id", 0))
	name_idx = int(d.get("name_idx", 0))
	female = bool(d.get("female", false))
	level = int(d.get("level", 1))
	xp = float(d.get("xp", 0.0))
	var s: Dictionary = d.get("stats", {})
	for k in STATS:
		stats[k] = int(s.get(k, 1))
	room_id = int(d.get("room_id", 0))
	look = int(d.get("look", 0))
	sprite = str(d.get("sprite", ""))
	dig = []
	for v in d.get("dig", []):
		dig.append(int(v))
