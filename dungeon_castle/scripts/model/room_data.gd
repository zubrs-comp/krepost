extends RefCounted
## Данные одной комнаты замка (без логики отображения)

var id: int = 0
var type: String = ""
var level: int = 1
var row: int = 0
var col: int = 0
## Накопленная в комнате продукция (собирается тапом)
var stored: float = 0.0
## Unix-время окончания стройки/улучшения; 0 — комната готова
var build_finish: float = 0.0
## Уровень, который комната получит после окончания стройки
var target_level: int = 1


func is_building(now: float) -> bool:
	return build_finish > now


func def() -> Dictionary:
	return DB.room(type)


func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "level": level, "row": row, "col": col,
		"stored": stored, "build_finish": build_finish, "target_level": target_level,
	}


func from_dict(d: Dictionary) -> void:
	id = int(d.get("id", 0))
	type = str(d.get("type", ""))
	level = int(d.get("level", 1))
	row = int(d.get("row", 0))
	col = int(d.get("col", 0))
	stored = float(d.get("stored", 0.0))
	build_finish = float(d.get("build_finish", 0.0))
	target_level = int(d.get("target_level", level))
