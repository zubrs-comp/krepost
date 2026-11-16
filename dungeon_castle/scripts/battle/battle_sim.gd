extends RefCounted
## Автобой «стенка на стенку»: отряд жителей слева, монстры справа.
## Чистая логика без графики. step(dt) двигает бой и возвращает события для отрисовки.
## На этапе 3 сюда добавятся ручные навыки героев и экипировка.

const TIMEOUT := 120.0

var units: Array = []      # [{side, name, sprite, hp, max, atk, interval, timer, crit, alive, ...}]
var time: float = 0.0
var finished: bool = false
var won: bool = false


## Характеристики бойца из жителя (elixir — бонус к атаке от эликсира)
static func hero_unit(r, elixir: float) -> Dictionary:
	var lvl: int = r.level
	var hp: float = 70.0 + 18.0 * lvl + 9.0 * r.stat("str")
	return {
		"side": 0, "id": r.id, "name": r.display_name(), "sprite": r.sprite, "scale": 1.0,
		"hp": hp, "max": hp,
		"atk": (5.0 + 2.2 * r.stat("str") + lvl) * (1.0 + elixir),
		"interval": clampf(1.7 - 0.06 * r.stat("agi"), 0.7, 1.7),
		"crit": 0.03 * r.stat("int"),
	}


static func enemy_unit(e: Dictionary) -> Dictionary:
	return {
		"side": 1, "id": str(e.get("id", "")), "name": TranslationServer.translate(str(e.get("name", ""))),
		"sprite": str(e.get("sprite", "")), "scale": float(e.get("scale", 1.0)),
		"hp": float(e["hp"]), "max": float(e["hp"]), "atk": float(e["atk"]),
		"interval": float(e.get("interval", 1.5)), "crit": 0.0,
		"boss": bool(e.get("boss", false)), "ability": e.get("ability", {}),
	}


func setup(heroes: Array, enemies: Array) -> void:
	units.clear()
	for h in heroes:
		units.append(h)
	for e in enemies:
		units.append(e)
	for i in units.size():
		var u: Dictionary = units[i]
		u["alive"] = true
		u["idx"] = i
		u["attacks"] = 0
		# Разнесём первые удары, чтобы все не били одновременно
		u["timer"] = float(u["interval"]) * (0.4 + 0.15 * i)


func side_units(side: int, alive_only: bool = true) -> Array:
	var out: Array = []
	for u in units:
		if int(u["side"]) == side and (not alive_only or bool(u["alive"])):
			out.append(u)
	return out


## Цель — передний живой боец противника (первый в строю)
func _target(side: int) -> Dictionary:
	var foes := side_units(1 - side)
	return foes[0] if not foes.is_empty() else {}


func step(dt: float) -> Array:
	var events: Array = []
	if finished:
		return events
	time += dt
	for u in units:
		if not bool(u["alive"]):
			continue
		u["timer"] = float(u["timer"]) - dt
		if float(u["timer"]) > 0.0:
			continue
		u["timer"] = float(u["interval"])
		u["attacks"] = int(u["attacks"]) + 1
		var ab: Dictionary = u.get("ability", {})
		# Особый удар босса: «Обвал» по всему отряду
		if str(ab.get("type", "")) == "quake" and int(u["attacks"]) % int(ab.get("every", 4)) == 0:
			events.append({"type": "ability", "src": u["idx"], "name": "quake"})
			for f in side_units(1 - int(u["side"])):
				_hit(u, f, float(u["atk"]) * float(ab.get("mult", 0.6)), false, events)
			continue
		var tgt := _target(int(u["side"]))
		if tgt.is_empty():
			continue
		var crit := randf() < float(u["crit"])
		var dmg := float(u["atk"]) * randf_range(0.85, 1.15) * (2.0 if crit else 1.0)
		events.append({"type": "attack", "src": u["idx"], "dst": tgt["idx"]})
		_hit(u, tgt, dmg, crit, events)
	# Итог
	if side_units(1).is_empty():
		finished = true
		won = true
	elif side_units(0).is_empty() or time >= TIMEOUT:
		finished = true
		won = false
	if finished:
		events.append({"type": "end", "won": won})
	return events


func _hit(src: Dictionary, dst: Dictionary, dmg: float, crit: bool, events: Array) -> void:
	dmg = roundf(dmg)
	dst["hp"] = maxf(float(dst["hp"]) - dmg, 0.0)
	events.append({"type": "damage", "src": src["idx"], "dst": dst["idx"], "dmg": dmg, "crit": crit})
	if float(dst["hp"]) <= 0.0 and bool(dst["alive"]):
		dst["alive"] = false
		events.append({"type": "death", "dst": dst["idx"]})


## Оценка силы стороны для подсказки перед боем
static func power(list: Array) -> float:
	var p := 0.0
	for u in list:
		p += float(u["hp"]) * float(u["atk"]) / float(u["interval"])
	return sqrt(p)
