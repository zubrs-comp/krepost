extends Node
## Состояние игры и вся экономическая логика: замок, жители, подземелье.
## Время считается по системным часам (unix), поэтому офлайн-прогресс —
## это просто большой шаг симуляции, ограниченный offline_cap_hours.

const RoomData = preload("res://scripts/model/room_data.gd")
const ResidentData = preload("res://scripts/model/resident_data.gd")
const DungeonGen = preload("res://scripts/dungeon/dungeon_gen.gd")
const Layout = preload("res://scripts/castle/layout.gd")
const Sprites = preload("res://scripts/castle/sprites.gd")

signal resources_changed
signal rooms_changed
signal residents_changed
signal room_updated(room_id: int)
signal dungeon_changed
signal cell_cleared(tier: int, dc: int, rewards: Dictionary)
signal lore_found(lore_id: String)
signal toast(text: String)
signal offline_report(seconds: float, gains: Dictionary)
signal locale_changed

const RESOURCES := ["gold", "food", "stone", "ore", "essence"]
const SAVE_VERSION := 2
## Шаг симуляции в реальном времени (сек)
const TICK := 0.25
## Пауза больше этого порога считается офлайном (сек)
const OFFLINE_THRESHOLD := 20.0

var res: Dictionary = {}
var rooms: Dictionary = {}          # id -> RoomData
var residents: Array = []           # [ResidentData]
var next_room_id: int = 1
var next_resident_id: int = 1
var last_time: float = 0.0
var hungry: bool = false
var settings: Dictionary = {"locale": "", "fps": 60}
var ready_to_play: bool = false
## Подземелье: seed мира, сгенерированные ярусы, найденная летопись, побеждённые боссы
var world_seed: int = 0
var tiers: Array = []               # [{biome, cells:[{s, hp, max, content, ...}]}]
var lore: Array = []                # id найденных страниц
var bosses: Array = []              # номера ярусов с побеждёнными боссами

var _accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_reset_res()


func now() -> float:
	return Time.get_unix_time_from_system()


func _reset_res() -> void:
	res = {}
	for k in RESOURCES:
		res[k] = 0.0


# ------------------------------------------------------------------ новая игра

func new_game() -> void:
	var b: Dictionary = DB.balance
	_reset_res()
	for k in RESOURCES:
		res[k] = float(b.get("start_resources", {}).get(k, 0))
	rooms.clear()
	residents.clear()
	tiers.clear()
	lore.clear()
	bosses.clear()
	next_room_id = 1
	next_resident_id = 1
	world_seed = randi()
	var tc: Array = b.get("throne_cell", [2, 1])
	var th := _add_room("throne", int(tc[0]), int(tc[1]))
	for sr in b.get("start_rooms", []):
		_add_room(str(sr["type"]), int(sr["row"]), int(sr["col"]))
	# Стартовые жители со случайными именами и характеристиками
	for i in int(b.get("start_residents", 5)):
		var r := _make_resident()
		r.room_id = th.id
		residents.append(r)
	reveal_tier(1)
	last_time = now()
	ready_to_play = true
	_emit_all()


func _add_room(type_id: String, row: int, col: int) -> RoomData:
	var r := RoomData.new()
	r.id = next_room_id
	next_room_id += 1
	r.type = type_id
	r.row = row
	r.col = col
	r.level = 1
	r.target_level = 1
	rooms[r.id] = r
	return r


## Новый житель: имя, которого ещё нет в замке, случайные характеристики и внешность
func _make_resident() -> ResidentData:
	var b: Dictionary = DB.balance
	var used := {}
	for p in residents:
		used[p.name_idx] = true
	var pool: Array = []
	for i in DB.names.size():
		if not used.has(i):
			pool.append(i)
	if pool.is_empty():
		pool = range(DB.names.size())
	var name_idx: int = pool[randi() % pool.size()]
	var r := ResidentData.new()
	r.id = next_resident_id
	next_resident_id += 1
	r.name_idx = name_idx
	r.female = bool(DB.names[name_idx].get("f", false)) if name_idx < DB.names.size() else false
	for k in ResidentData.STATS:
		r.stats[k] = randi_range(int(b.get("stat_min", 2)), int(b.get("stat_max", 9)))
	r.look = randi() % 8
	_pick_sprite(r)
	return r


func _pick_sprite(r: ResidentData) -> void:
	var ids := Sprites.resident_ids(r.female)
	if not ids.is_empty():
		r.sprite = ids[(r.look + r.id) % ids.size()]


# ------------------------------------------------------------------ запросы: комнаты и жители

func throne() -> RoomData:
	for r in rooms.values():
		if r.type == "throne":
			return r
	return null


func room_at(row: int, col: int) -> RoomData:
	for r in rooms.values():
		if r.row == row and r.col == col:
			return r
	return null


func get_room(id: int) -> RoomData:
	return rooms.get(id, null)


func get_resident(id: int) -> ResidentData:
	for r in residents:
		if r.id == id:
			return r
	return null


func workers_in(room_id: int) -> Array:
	var out: Array = []
	for r in residents:
		if r.room_id == room_id and not r.is_digging():
			out.append(r)
	return out


func worker_slots(room: RoomData) -> int:
	return int(DB.by_level(room.def().get("slots", [0]), room.level))


## Ёмкость казны по ресурсу: тронный зал + склады (+ бонус от работников склада)
func capacity(res_id: String) -> float:
	var total := 0.0
	var t := now()
	for r in rooms.values():
		var d: Dictionary = r.def()
		if not d.has("capacity"):
			continue
		# Строящийся с нуля склад ещё ничего не хранит
		if r.is_building(t) and _is_new_build(r):
			continue
		var base := float(d["capacity"].get(res_id, 0))
		var mult: float = 1.0 + float(d.get("capacity_level_mult", 0.0)) * (r.level - 1)
		var bonus := 0.0
		if r.type != "throne":
			for w in workers_in(r.id):
				bonus += float(d.get("worker_bonus", 0.0)) * efficiency(w, r.type)
		total += base * mult * (1.0 + bonus)
	return floor(total)


func _is_new_build(r: RoomData) -> bool:
	return r.level == 1 and r.target_level == 1


## Лимит жителей: тронный зал + спальни
func population_cap() -> int:
	var total := 0
	var t := now()
	for r in rooms.values():
		var d: Dictionary = r.def()
		if d.has("pop"):
			total += int(d["pop"])
		elif d.has("pop_levels") and not (r.is_building(t) and _is_new_build(r)):
			total += int(DB.by_level(d["pop_levels"], r.level))
	return total


func recruit_cost() -> Dictionary:
	var b: Dictionary = DB.balance
	var extra := maxi(residents.size() - int(b.get("start_residents", 5)), 0)
	return {"gold": int(float(b.get("recruit_gold", 80)) * pow(float(b.get("recruit_mult", 1.4)), extra)),
		"food": int(b.get("recruit_food", 30))}


## Эффективность жителя по характеристике: 0.5 + 0.1 × стат (×0.5 при голоде)
func stat_efficiency(r: ResidentData, st: String) -> float:
	if st == "":
		return 0.0
	var b: Dictionary = DB.balance
	var e := float(b.get("efficiency_base", 0.5)) + float(b.get("efficiency_per_stat", 0.1)) * r.stat(st)
	if hungry:
		e *= float(b.get("hunger_efficiency", 0.5))
	return e


func efficiency(r: ResidentData, room_type: String) -> float:
	return stat_efficiency(r, str(DB.room(room_type).get("stat", "")))


## Выработка комнаты в минуту
func room_rate(room: RoomData) -> float:
	var d: Dictionary = room.def()
	if str(d.get("resource", "")) == "" or room.is_building(now()):
		return 0.0
	var per := float(d.get("rate", 0.0)) * (1.0 + float(d.get("level_bonus", 0.0)) * (room.level - 1))
	var sum_eff := 0.0
	for w in workers_in(room.id):
		sum_eff += efficiency(w, room.type)
	if str(d.get("rate_mode", "")) == "captives":
		# Тюрьма: эссенцию дают пленники, стража лишь нужна (хватает одного с эффективностью 1)
		return per * captives(room) * minf(sum_eff, 1.0)
	if room.type == "mine" and is_vein(room.row, room.col):
		per *= 1.0 + float(d.get("vein_bonus", 0.5))
	return per * sum_eff


func room_buffer(room: RoomData) -> float:
	return DB.by_level(room.def().get("buffer", [0]), room.level)


func captives(room: RoomData) -> int:
	return int(room.extra.get("captives", 0))


func captive_cap(room: RoomData) -> int:
	return int(DB.by_level(room.def().get("captives", [0]), room.level))


# ------------------------------------------------------------------ цены

## Цена постройки/улучшения до уровня level: словарь {ресурс: количество}
func room_cost(type_id: String, level: int) -> Dictionary:
	var arr: Array = DB.room(type_id).get("cost", [])
	if arr.is_empty():
		return {}
	var c: Variant = arr[clampi(level - 1, 0, arr.size() - 1)]
	if typeof(c) == TYPE_DICTIONARY:
		return c
	return {"gold": int(c)}


func build_time(type_id: String, level: int) -> float:
	return DB.by_level(DB.room(type_id).get("build_time", [0]), level)


## Цена улучшения до следующего уровня; пусто — если максимум
func upgrade_cost(room: RoomData) -> Dictionary:
	if room.level >= int(room.def().get("max_level", 1)):
		return {}
	return room_cost(room.type, room.level + 1)


func can_afford(cost: Dictionary) -> bool:
	for k in cost.keys():
		if float(res.get(k, 0.0)) < float(cost[k]):
			return false
	return true


func pay(cost: Dictionary) -> bool:
	if not can_afford(cost):
		toast.emit(tr("TOAST_NO_RES"))
		return false
	for k in cost.keys():
		res[k] = float(res.get(k, 0.0)) - float(cost[k])
	return true


## Добавить ресурс в казну с учётом лимита; возвращает, сколько реально влезло
func add_res(res_id: String, amount: float) -> float:
	var free := maxf(capacity(res_id) - float(res.get(res_id, 0.0)), 0.0)
	var got := minf(amount, free)
	res[res_id] = float(res.get(res_id, 0.0)) + got
	return got


func food_consumption_per_min() -> float:
	return residents.size() * float(DB.balance.get("food_per_resident_min", 0.4))


# ------------------------------------------------------------------ подземелье: запросы

func tier_data(tier: int) -> Dictionary:
	if tier < 1 or tier > tiers.size():
		return {}
	return tiers[tier - 1]


func cell(tier: int, dc: int) -> Dictionary:
	var td := tier_data(tier)
	if td.is_empty():
		return {}
	var cells: Array = td["cells"]
	if dc < 0 or dc >= cells.size():
		return {}
	return cells[dc]


func deepest_tier() -> int:
	return tiers.size()


func stair_col() -> int:
	return int(DB.dungeon.get("stair_col", 2))


## Открыть ярус (сгенерировать, если ещё не было)
func reveal_tier(tier: int) -> void:
	while tiers.size() < tier:
		tiers.append(DungeonGen.generate(tiers.size() + 1, world_seed))
	dungeon_changed.emit()


func _passable(c: Dictionary) -> bool:
	return str(c.get("s", "")) in ["open", "stair"]


## Можно ли копать клетку: порода, к которой есть проход
func is_diggable(tier: int, dc: int) -> bool:
	var c := cell(tier, dc)
	if c.is_empty() or str(c["s"]) != "rock":
		return false
	if dc == stair_col():
		# Лестницу копаем сверху: с поверхности (ярус 1) или из лестницы над ней
		return tier == 1 or str(cell(tier - 1, dc).get("s", "")) == "stair"
	return _passable(cell(tier, dc - 1)) or _passable(cell(tier, dc + 1))


## Можно ли дойти до логова (сражаться): соседняя клетка проходима или это лестница с проходом сверху
func is_reachable(tier: int, dc: int) -> bool:
	if dc == stair_col():
		return tier == 1 or str(cell(tier - 1, dc).get("s", "")) == "stair"
	return _passable(cell(tier, dc - 1)) or _passable(cell(tier, dc + 1))


func diggers_at(tier: int, dc: int) -> Array:
	var out: Array = []
	for r in residents:
		if r.is_digging() and r.dig[0] == tier and r.dig[1] == dc:
			out.append(r)
	return out


func max_diggers() -> int:
	return int(DB.dungeon.get("max_diggers", 2))


## Скорость раскопок клетки (единиц твёрдости в минуту)
func dig_rate(tier: int, dc: int) -> float:
	var sum := 0.0
	for w in diggers_at(tier, dc):
		sum += stat_efficiency(w, "str")
	return float(DB.dungeon.get("dig_rate_per_min", 12.0)) * sum


func is_vein(row: int, col: int) -> bool:
	if not Layout.is_dungeon_row(row):
		return false
	return bool(cell(Layout.tier_of(row), Layout.dcol(col)).get("vein", false))


# ------------------------------------------------------------------ действия игрока

func can_assign(r: ResidentData, room: RoomData) -> bool:
	if room == null or r == null:
		return false
	if r.room_id == room.id and not r.is_digging():
		return true
	return workers_in(room.id).size() < worker_slots(room)


func assign(r: ResidentData, room: RoomData) -> bool:
	if not can_assign(r, room):
		toast.emit(tr("TOAST_ROOM_FULL"))
		return false
	if r.room_id == room.id and not r.is_digging():
		return true
	r.room_id = room.id
	r.dig = []
	residents_changed.emit()
	resources_changed.emit()
	room_updated.emit(room.id)
	dungeon_changed.emit()
	return true


func can_dig(r: ResidentData, tier: int, dc: int) -> bool:
	if r == null or not is_diggable(tier, dc):
		return false
	if r.is_digging() and r.dig[0] == tier and r.dig[1] == dc:
		return true
	return diggers_at(tier, dc).size() < max_diggers()


func assign_dig(r: ResidentData, tier: int, dc: int) -> bool:
	if not is_diggable(tier, dc):
		toast.emit(tr("TOAST_CANT_DIG"))
		return false
	if not can_dig(r, tier, dc):
		toast.emit(tr("TOAST_DIG_FULL"))
		return false
	r.dig = [tier, dc]
	var th := throne()
	r.room_id = th.id if th != null else 0
	residents_changed.emit()
	dungeon_changed.emit()
	return true


## Забрать накопленное из комнаты в казну (сколько влезет)
func collect(room: RoomData) -> float:
	var res_id := str(room.def().get("resource", ""))
	if res_id == "" or room.stored < 1.0:
		return 0.0
	var free := capacity(res_id) - float(res[res_id])
	var amount: float = floor(minf(room.stored, maxf(free, 0.0)))
	if amount < 1.0:
		toast.emit(tr("TOAST_STORAGE_FULL"))
		return 0.0
	room.stored -= amount
	res[res_id] += amount
	resources_changed.emit()
	room_updated.emit(room.id)
	return amount


func collect_all() -> Dictionary:
	var got := {}
	for r in rooms.values():
		var res_id := str(r.def().get("resource", ""))
		var a := collect(r)
		if a > 0:
			got[res_id] = float(got.get(res_id, 0.0)) + a
	return got


## Можно ли строить тип комнаты в клетке
func can_build_here(type_id: String, row: int, col: int) -> bool:
	if room_at(row, col) != null:
		return false
	var d: Dictionary = DB.room(type_id)
	var zone := str(d.get("zone", "castle"))
	if Layout.is_dungeon_row(row):
		var t := Layout.tier_of(row)
		return zone == "dungeon" and str(cell(t, Layout.dcol(col)).get("s", "")) == "open" \
			and t >= int(d.get("min_tier", 1))
	return zone == "castle" and row >= 0 and col >= 0 and col < int(DB.balance.get("grid_cols", 3))


func build(type_id: String, row: int, col: int) -> bool:
	if not can_build_here(type_id, row, col):
		return false
	if not pay(room_cost(type_id, 1)):
		return false
	var r := _add_room(type_id, row, col)
	r.build_finish = now() + build_time(type_id, 1)
	r.target_level = 1
	_emit_all()
	return true


func upgrade(room: RoomData) -> bool:
	var cost := upgrade_cost(room)
	if cost.is_empty() or room.is_building(now()):
		return false
	if not pay(cost):
		return false
	room.target_level = room.level + 1
	room.build_finish = now() + build_time(room.type, room.target_level)
	_emit_all()
	return true


func recruit() -> bool:
	if residents.size() >= population_cap():
		toast.emit(tr("TOAST_NO_BEDS"))
		return false
	if not pay(recruit_cost()):
		return false
	var r := _make_resident()
	var th := throne()
	r.room_id = th.id if th != null else 0
	residents.append(r)
	toast.emit(tr("TOAST_RECRUITED") % r.display_name())
	_emit_all()
	return true


# ------------------------------------------------------------------ подземелье: раскопки и бои

## Порода расчищена: награды, находки, открытие следующего яруса
func _clear_cell(tier: int, dc: int) -> void:
	var c := cell(tier, dc)
	var dd: Dictionary = DB.dungeon
	var rewards := {}
	var stone := float(dd.get("stone_base", 12)) + float(dd.get("stone_per_tier", 4)) * tier
	rewards["stone"] = add_res("stone", stone)
	var content := str(c.get("content", ""))
	c["hp"] = 0.0
	c["s"] = "stair" if dc == stair_col() else "open"
	match content:
		"chest":
			var g: Array = dd.get("chest_gold", [30, 12])
			var s: Array = dd.get("chest_stone", [10, 5])
			rewards["gold"] = add_res("gold", float(g[0]) + float(g[1]) * tier)
			rewards["stone"] = float(rewards["stone"]) + add_res("stone", float(s[0]) + float(s[1]) * tier)
			toast.emit(tr("TOAST_CHEST"))
		"vein":
			c["vein"] = true
			var o: Array = dd.get("vein_ore", [8, 3])
			rewards["ore"] = add_res("ore", float(o[0]) + float(o[1]) * tier)
			toast.emit(tr("TOAST_VEIN"))
		"lair":
			c["s"] = "lair"
			toast.emit(tr("TOAST_LAIR"))
		"lore":
			_find_lore(str(c.get("lore", "")))
	c["content"] = "" if content != "lair" else "lair"
	# Копатели возвращаются в тронный зал
	var th := throne()
	for w in diggers_at(tier, dc):
		w.dig = []
		w.room_id = th.id if th != null else 0
	if c["s"] == "stair":
		reveal_tier(tier + 1)
		toast.emit(tr("TOAST_TIER_OPEN") % (tier + 1))
	cell_cleared.emit(tier, dc, rewards)
	residents_changed.emit()
	dungeon_changed.emit()


func _find_lore(id: String) -> void:
	if id == "" or lore.has(id) or not DB.lore.has(id):
		return
	lore.append(id)
	lore_found.emit(id)


## Враги логова/босса с учётом глубины
func enemies_at(tier: int, dc: int) -> Array:
	var c := cell(tier, dc)
	var out: Array = []
	var scale := 1.0 + float(DB.enemies.get("tier_scale", 0.18)) * (tier - 1)
	for eid in c.get("enemies", []):
		var e: Dictionary = DB.enemies.get(str(eid), {})
		if e.is_empty():
			continue
		var u := e.duplicate(true)
		u["id"] = eid
		# Босс уже рассчитан на свой ярус, растёт только в следующих биомах
		var k: float = scale if not bool(e.get("boss", false)) else 1.0 + 0.6 * floor((tier - 1) / 10.0)
		u["hp"] = roundf(float(e["hp"]) * k)
		u["atk"] = roundf(float(e["atk"]) * k)
		out.append(u)
	return out


## Итог боя у логова/босса
func fight_result(tier: int, dc: int, won: bool, hero_ids: Array) -> Dictionary:
	var c := cell(tier, dc)
	var rewards := {}
	if not won or c.is_empty():
		return rewards
	var dd: Dictionary = DB.dungeon
	var was_boss := str(c["s"]) == "boss"
	var n := (c.get("enemies", []) as Array).size()
	if was_boss:
		# Трофеи босса кладём даже сверх лимита казны — чтобы награда не сгорела
		for k in dd.get("boss_reward", {}).keys():
			var amount: float = float(dd["boss_reward"][k]) * (1.0 + 0.5 * floor((tier - 1) / 10.0))
			res[k] = float(res.get(k, 0.0)) + amount
			rewards[k] = amount
		c["s"] = "stair"
		if not bosses.has(tier):
			bosses.append(tier)
		var boss_id := str((c.get("enemies", [""]) as Array)[0])
		_find_lore(boss_id)
		reveal_tier(tier + 1)
		toast.emit(tr("TOAST_BOSS_DOWN"))
	else:
		var g: Array = dd.get("lair_gold", [25, 10])
		rewards["gold"] = add_res("gold", (float(g[0]) + float(g[1]) * tier) * n)
		rewards["essence"] = add_res("essence", 2.0 * n)
		c["s"] = "stair" if dc == stair_col() else "open"
		# Пленник — если есть тюрьма со свободным местом
		if randf() < float(dd.get("capture_chance", 0.6)):
			for r in rooms.values():
				if r.type == "prison" and not r.is_building(now()) and captives(r) < captive_cap(r):
					r.extra["captives"] = captives(r) + 1
					rewards["captive"] = 1
					toast.emit(tr("TOAST_CAPTIVE"))
					break
		if c["s"] == "stair":
			reveal_tier(tier + 1)
	c["content"] = ""
	c.erase("enemies")
	# Опыт бойцам: сила и ловкость
	var xp := (40.0 if not was_boss else 200.0) * (1.0 + 0.2 * tier)
	for id in hero_ids:
		var h := get_resident(int(id))
		if h != null:
			_give_xp(h, xp, "str" if randf() < 0.5 else "agi")
	rewards["xp"] = xp
	_emit_all()
	dungeon_changed.emit()
	return rewards


# ------------------------------------------------------------------ симуляция

func _process(delta: float) -> void:
	if not ready_to_play:
		return
	_accum += delta
	if _accum < TICK:
		return
	_accum = 0.0
	var t := now()
	var dt := t - last_time
	if dt <= 0.0:
		last_time = t
		return
	if dt > OFFLINE_THRESHOLD:
		apply_offline(dt)
	else:
		simulate(dt, t)
	last_time = t


## Шаг офлайна: ограничиваем по лимиту и сообщаем игроку, что накопилось
func apply_offline(seconds: float) -> void:
	var cap := float(DB.balance.get("offline_cap_hours", 8)) * 3600.0
	var dt := minf(seconds, cap)
	var gains := simulate(dt, now())
	last_time = now()
	offline_report.emit(seconds, gains)


## Продвинуть мир на dt секунд, закончившихся в момент t_end. Возвращает прирост.
## Порядок: стройки → выработка → кухни кормят жителей → излишек в буферы → опыт → раскопки.
func simulate(dt: float, t_end: float) -> Dictionary:
	var gains := {"levelups": 0, "cells": 0}
	for k in RESOURCES:
		gains[k] = 0.0
	var t_start := t_end - dt
	var changed_rooms := false
	# 1) Завершение строек; запоминаем момент окончания — работать комната начинает с него
	var started_at := {}
	for r in rooms.values():
		if r.build_finish > 0.0 and r.build_finish <= t_end:
			started_at[r.id] = r.build_finish
			r.level = r.target_level
			r.build_finish = 0.0
			changed_rooms = true
			toast.emit(tr("TOAST_BUILT") % tr(str(r.def().get("name", ""))))
	# 2) Сырая выработка каждой комнаты за интервал
	var raw := {}        # id -> количество
	var work_time := {}  # id -> секунды работы
	var food_raw := 0.0
	for r in rooms.values():
		if r.is_building(t_end):
			continue
		var from_t: float = maxf(t_start, float(started_at.get(r.id, t_start)))
		var wdt := clampf(t_end - from_t, 0.0, dt)
		work_time[r.id] = wdt
		var res_id := str(r.def().get("resource", ""))
		if res_id != "":
			raw[r.id] = room_rate(r) * wdt / 60.0
			if res_id == "food":
				food_raw += raw[r.id]
	# 3) Еда: жители сначала едят свежее с кухонь и ферм, остаток — из казны
	var need := food_consumption_per_min() * dt / 60.0
	var from_kitchens := minf(need, food_raw)
	var share := (from_kitchens / food_raw) if food_raw > 0.0 else 0.0
	need -= from_kitchens
	var was_hungry := hungry
	if res["food"] >= need:
		res["food"] -= need
		hungry = false
	else:
		res["food"] = 0.0
		hungry = true
	if hungry and not was_hungry:
		toast.emit(tr("TOAST_HUNGRY"))
	# 4) Излишек — в буфер комнаты; опыт идёт только пока комната реально работает
	var xp_rate := float(DB.balance.get("xp_per_min", 4.0))
	for r in rooms.values():
		if not work_time.has(r.id):
			continue
		var d: Dictionary = r.def()
		var res_id := str(d.get("resource", ""))
		var productive: float = work_time[r.id]
		if res_id != "":
			var amount: float = raw[r.id]
			if res_id == "food":
				amount *= 1.0 - share
			var before: float = r.stored
			r.stored = minf(r.stored + amount, room_buffer(r))
			gains[res_id] += r.stored - before
			if amount > 0.0001 and r.stored >= room_buffer(r):
				# Буфер заполнился раньше конца интервала — работали только часть времени
				productive *= clampf((r.stored - before) / amount, 0.0, 1.0)
			if int(before) != int(r.stored):
				room_updated.emit(r.id)
		if str(d.get("stat", "")) != "" and r.type != "throne":
			for w in workers_in(r.id):
				if _give_xp(w, xp_rate * productive / 60.0, str(d["stat"])):
					gains["levelups"] += 1
	# 5) Раскопки: копатели сбивают твёрдость породы (в том числе офлайн)
	for ti in tiers.size():
		var cells: Array = tiers[ti]["cells"]
		for dc in cells.size():
			var c: Dictionary = cells[dc]
			if str(c["s"]) != "rock":
				continue
			var diggers := diggers_at(ti + 1, dc)
			if diggers.is_empty():
				continue
			var rate := dig_rate(ti + 1, dc)
			var hp_before := float(c["hp"])
			var spent := minf(rate * dt / 60.0, hp_before)
			c["hp"] = hp_before - spent
			var dig_time := (spent / rate * 60.0) if rate > 0.0 else 0.0
			for w in diggers:
				if _give_xp(w, xp_rate * dig_time / 60.0, "str"):
					gains["levelups"] += 1
			if float(c["hp"]) <= 0.001:
				_clear_cell(ti + 1, dc)
				gains["cells"] += 1
			elif int(hp_before) != int(c["hp"]):
				dungeon_changed.emit()
	if changed_rooms:
		_emit_all()
	else:
		resources_changed.emit()
	return gains


## Опыт; при повышении уровня растёт нужная характеристика и одна случайная
func _give_xp(w: ResidentData, amount: float, work_stat: String) -> bool:
	var max_lvl := int(DB.balance.get("max_resident_level", 10))
	if w.level >= max_lvl:
		return false
	w.xp += amount
	var leveled := false
	while w.level < max_lvl and w.xp >= w.xp_to_next():
		w.xp -= w.xp_to_next()
		w.level += 1
		w.stats[work_stat] = w.stat(work_stat) + 1
		var rnd: String = ResidentData.STATS[randi() % ResidentData.STATS.size()]
		w.stats[rnd] = w.stat(rnd) + 1
		leveled = true
		toast.emit(tr("TOAST_LEVELUP") % [w.display_name(), w.level])
	if leveled:
		residents_changed.emit()
	return leveled


func _emit_all() -> void:
	rooms_changed.emit()
	residents_changed.emit()
	resources_changed.emit()


# ------------------------------------------------------------------ настройки

func set_locale(loc: String) -> void:
	settings["locale"] = loc
	TranslationServer.set_locale(loc)
	locale_changed.emit()


func set_fps(fps: int) -> void:
	settings["fps"] = fps
	Engine.max_fps = fps


# ------------------------------------------------------------------ сохранение

func to_dict() -> Dictionary:
	var rs: Array = []
	for r in rooms.values():
		rs.append(r.to_dict())
	var ps: Array = []
	for p in residents:
		ps.append(p.to_dict())
	return {
		"version": SAVE_VERSION,
		"saved_at": now(),
		"res": res.duplicate(),
		"rooms": rs,
		"residents": ps,
		"next_room_id": next_room_id,
		"next_resident_id": next_resident_id,
		"hungry": hungry,
		"settings": settings.duplicate(),
		"world_seed": world_seed,
		"tiers": tiers.duplicate(true),
		"lore": lore.duplicate(),
		"bosses": bosses.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	_reset_res()
	var dr: Dictionary = d.get("res", {})
	for k in RESOURCES:
		res[k] = float(dr.get(k, 0.0))
	rooms.clear()
	for rd in d.get("rooms", []):
		var r := RoomData.new()
		r.from_dict(rd)
		rooms[r.id] = r
	residents.clear()
	for pd in d.get("residents", []):
		var p := ResidentData.new()
		p.from_dict(pd)
		if not rooms.has(p.room_id) and throne() != null:
			p.room_id = throne().id
		# Сохранения версии 1: внешности-спрайта ещё не было
		if p.sprite == "" or Sprites.meta(p.sprite).is_empty():
			_pick_sprite(p)
		residents.append(p)
	next_room_id = int(d.get("next_room_id", rooms.size() + 1))
	next_resident_id = int(d.get("next_resident_id", residents.size() + 1))
	hungry = bool(d.get("hungry", false))
	var s: Dictionary = d.get("settings", {})
	for k in s.keys():
		settings[k] = s[k]
	world_seed = int(d.get("world_seed", randi()))
	tiers = d.get("tiers", [])
	# JSON отдаёт числа как float — приводим индексы копателей и т.п. уже в моделях
	lore = d.get("lore", [])
	bosses = []
	for b in d.get("bosses", []):
		bosses.append(int(b))
	if tiers.is_empty():
		reveal_tier(1)
	last_time = float(d.get("saved_at", now()))
	ready_to_play = true
	_emit_all()
	dungeon_changed.emit()
