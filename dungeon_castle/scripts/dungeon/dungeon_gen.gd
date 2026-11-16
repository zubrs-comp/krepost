extends RefCounted
## Генератор ярусов подземелья. Обычные ярусы строятся по seed мира и номеру яруса,
## поэтому один и тот же мир всегда даёт одинаковое подземелье.
## Сюжетные и босс-ярусы берутся из data/dungeon.json → handcrafted.

## Состояния клетки:
##  rock  — порода, её копают;
##  open  — расчищено, можно строить подземную комнату;
##  stair — лестница вниз (средняя колонка), открывает следующий ярус;
##  lair  — логово монстров, нужно победить;
##  boss  — логово босса (лестница 10-го яруса биома).


static func generate(tier: int, world_seed: int) -> Dictionary:
	var dd: Dictionary = DB.dungeon
	var width := int(dd.get("width", 5))
	var stair := int(dd.get("stair_col", 2))
	var biome: Dictionary = DB.biome(tier)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([world_seed, tier])
	var hand: Dictionary = dd.get("handcrafted", {}).get(str(tier), {})
	var cells: Array = []
	for c in width:
		var cell := {"s": "rock", "content": ""}
		if not hand.is_empty():
			var hc: Dictionary = hand["cells"][c]
			cell["s"] = str(hc.get("s", "rock"))
			cell["content"] = str(hc.get("content", ""))
			if hc.has("enemies"):
				cell["enemies"] = (hc["enemies"] as Array).duplicate()
		elif c != stair:
			# Случайное содержимое боковых клеток
			var roll := rng.randf()
			var ch: Dictionary = dd.get("chance", {})
			var acc := 0.0
			for k in ["chest", "vein", "lair"]:
				acc += float(ch.get(k, 0.0))
				if roll < acc:
					cell["content"] = k
					break
		# Каждый 10-й ярус биома — босс на лестнице
		if c == stair and tier == int(biome.get("to", 10)) and hand.is_empty():
			cell["s"] = "boss"
		if cell["s"] == "boss" and not cell.has("enemies"):
			cell["enemies"] = [str(biome.get("boss", "gryzen"))]
		if cell["content"] == "lair" and not cell.has("enemies"):
			cell["enemies"] = _roll_pack(rng, biome, dd)
		# Сюжетная находка на лестнице
		if c == stair and dd.get("lore_tiers", {}).has(str(tier)):
			cell["content"] = "lore"
			cell["lore"] = str(dd["lore_tiers"][str(tier)])
		# Твёрдость породы растёт с глубиной
		var hp := float(dd.get("dig_base", 50.0)) * (1.0 + float(dd.get("dig_per_tier", 0.3)) * (tier - 1))
		if c == stair:
			hp *= float(dd.get("stair_mult", 1.5))
		hp *= rng.randf_range(0.85, 1.15)
		cell["hp"] = roundf(hp) if cell["s"] == "rock" else 0.0
		cell["max"] = roundf(hp)
		cells.append(cell)
	return {"biome": str(biome.get("id", "")), "cells": cells}


static func _roll_pack(rng: RandomNumberGenerator, biome: Dictionary, dd: Dictionary) -> Array:
	var pool: Array = biome.get("enemies", ["slime"])
	var sz: Array = dd.get("lair_size", [1, 3])
	var n := rng.randi_range(int(sz[0]), int(sz[1]))
	var out: Array = []
	for i in n:
		out.append(pool[rng.randi() % pool.size()])
	return out
