extends Node
## Проверка баланса боёв: доля побед отряда из 3 жителей разных уровней.
const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const ResidentData = preload("res://scripts/model/resident_data.gd")

func _ready() -> void:
	GameState.new_game()
	var setups := {
		"слизь+тролль, ярус 3": [3, ["slime", "troll"]],
		"3 тролля, ярус 8": [8, ["troll", "troll", "troll"]],
		"Грызень+2 слизи, ярус 10": [10, ["gryzen", "slime", "slime"]],
	}
	for lvl in [1, 3, 5, 7, 9]:
		var line := "ур.%d (статы ~%d): " % [lvl, 5 + lvl]
		for name in setups.keys():
			var tier: int = setups[name][0]
			var wins := 0
			var time := 0.0
			for n in 200:
				var heroes: Array = []
				for i in 3:
					var r := ResidentData.new()
					r.level = lvl
					r.stats = {"str": 4 + lvl + randi() % 3, "agi": 4 + lvl + randi() % 3, "int": 3 + lvl}
					heroes.append(BattleSim.hero_unit(r, 0.0))
				var foes: Array = []
				var scale := 1.0 + 0.18 * (tier - 1)
				for eid in setups[name][1]:
					var e: Dictionary = DB.enemies[eid].duplicate(true)
					if not e.get("boss", false):
						e["hp"] = e["hp"] * scale
						e["atk"] = e["atk"] * scale
					foes.append(BattleSim.enemy_unit(e))
				var sim := BattleSim.new()
				sim.setup(heroes, foes)
				while not sim.finished:
					sim.step(0.1)
				if sim.won:
					wins += 1
				time += sim.time
			line += "%s %d%% (%.0fс) | " % [name, wins / 2, time / 200.0]
		print(line)
	get_tree().quit()
