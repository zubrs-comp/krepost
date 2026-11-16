extends RefCounted
## Геометрия мира: клетки замка (ряды 0..2) и ярусов подземелья (ряд = 2 + ярус).
## Колонки замка 0..2; подземелье шире: колонки -1..3 (индекс в ярусе = колонка + 1).

const W := 320.0
const H := 240.0
const CASTLE_ROWS := 3
## Прослойка земли между полом замка и первым ярусом
const GAP := 50.0


static func is_dungeon_row(row: int) -> bool:
	return row >= CASTLE_ROWS


static func tier_of(row: int) -> int:
	return row - CASTLE_ROWS + 1


static func row_of_tier(tier: int) -> int:
	return CASTLE_ROWS + tier - 1


static func dcol(col: int) -> int:
	return col + 1


static func col_of(dc: int) -> int:
	return dc - 1


static func ground_y() -> float:
	return CASTLE_ROWS * H


static func cell_pos(row: int, col: int) -> Vector2:
	if row < CASTLE_ROWS:
		return Vector2(col * W, row * H)
	return Vector2(col * W, ground_y() + GAP + (row - CASTLE_ROWS) * H)


## Клетка под точкой мира (без проверки, существует ли она)
static func cell_at(p: Vector2) -> Vector2i:
	var col := int(floor(p.x / W))
	if p.y < ground_y():
		if p.y < 0:
			return Vector2i(-99, -99)
		return Vector2i(int(p.y / H), col)
	var y := p.y - ground_y() - GAP
	if y < 0:
		return Vector2i(-99, -99)
	return Vector2i(CASTLE_ROWS + int(y / H), col)
