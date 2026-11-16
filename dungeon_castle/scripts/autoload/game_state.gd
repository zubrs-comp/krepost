extends Node
## Состояние игры и вся экономическая логика замка.
## Время считается по системным часам (unix), поэтому офлайн-прогресс —
## это просто большой шаг симуляции, ограниченный offline_cap_hours.

const RoomData = preload("res://scripts/model/room_data.gd")
const ResidentData = preload("res://scripts/model/resident_data.gd")

signal resources_changed
signal rooms_changed
signal residents_changed
signal room_updated(room_id: int)
signal toast(text: String)
signal offline_report(seconds: float, gains: Dictionary)
signal locale_changed

const RESOURCES := ["gold", "food"]
## Шаг симуляции в реальном времени (сек)
const TICK := 0.25
## Пауза больше этого порога считается офлайном (сек)
const OFFLINE_THRESHOLD := 20.0

var res: Dictionary = {"gold": 0.0, "food": 0.0}
var rooms: Dictionary = {}          # id -> RoomData
var residents: Array = []           # [ResidentData]
var next_room_id: int = 1
var next_resident_id: int = 1
var last_time: float = 0.0
var hungry: bool = false
var settings: Dictionary = {"locale": "", "fps": 60}
var ready_to_play: bool = false

var _accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func now() -> float:
	return Time.get_unix_time_from_system()


# ------------------------------------------------------------------ новая игра

func new_game() -> void:
	var b: Dictionary = DB.balance
	res = {"gold": 0.0, "food": 0.0}
	for k in RESOURCES:
		res[k] = float(b.get("start_resources", {}).get(k, 0))
	rooms.clear()
	residents.clear()
	next_room_id = 1
	next_resident_id = 1
	var tc: Array = b.get("throne_cell", [2, 1])
	var throne := _add_room("throne", int(tc[0]), int(tc[1]))
	for sr in b.get("start_rooms", []):
		_add_room(str(sr["type"]), int(sr["row"]), int(sr["col"]))
	# Стартовые жители со случайными именами и характеристиками
	var pool: Array = range(DB.names.size())
	pool.shuffle()
	for i in int(b.get("start_residents", 5)):
		var r := _make_resident(int(pool[i % pool.size()]))
		r.room_id = throne.id
		residents.append(r)
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


func _make_resident(name_idx: int) -> ResidentData:
	var b: Dictionary = DB.balance
	var r := ResidentData.new()
	r.id = next_resident_id
	next_resident_id += 1
	r.name_idx = name_idx
	r.female = bool(DB.names[name_idx].get("f", false)) if name_idx < DB.names.size() else false
	for k in ResidentData.STATS:
		r.stats[k] = randi_range(int(b.get("stat_min", 2)), int(b.get("stat_max", 9)))
	r.look = randi() % 8
	return r


# ------------------------------------------------------------------ запросы

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
		if r.room_id == room_id:
			out.append(r)
	return out


func worker_slots(room: RoomData) -> int:
	return int(DB.by_level(room.def().get("slots", [0]), room.level))


## Общая ёмкость хранилища ресурса: тронный зал + склады (+ бонус от работников склада)
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
	# Новая постройка: уровень 1 и целевой уровень 1 (а не улучшение 1→2)
	return r.level == 1 and r.target_level == 1


## Эффективность жителя в комнате данного типа: зависит от нужной характеристики
func efficiency(r: ResidentData, room_type: String) -> float:
	var d: Dictionary = DB.room(room_type)
	var st := str(d.get("stat", ""))
	if st == "":
		return 0.0
	var b: Dictionary = DB.balance
	var e := float(b.get("efficiency_base", 0.5)) + float(b.get("efficiency_per_stat", 0.1)) * r.stat(st)
	if hungry:
		e *= float(b.get("hunger_efficiency", 0.5))
	return e


## Выработка комнаты в минуту
func room_rate(room: RoomData) -> float:
	var d: Dictionary = room.def()
	if str(d.get("resource", "")) == "" or room.is_building(now()):
		return 0.0
	var per := float(d.get("rate", 0.0)) * (1.0 + float(d.get("level_bonus", 0.0)) * (room.level - 1))
	var sum_eff := 0.0
	for w in workers_in(room.id):
		sum_eff += efficiency(w, room.type)
	return per * sum_eff


func room_buffer(room: RoomData) -> float:
	return DB.by_level(room.def().get("buffer", [0]), room.level)


func build_cost(type_id: String, level: int) -> int:
	return int(DB.by_level(DB.room(type_id).get("cost", [0]), level))


func build_time(type_id: String, level: int) -> float:
	return DB.by_level(DB.room(type_id).get("build_time", [0]), level)


## Стоимость улучшения до следующего уровня (-1, если максимум)
func upgrade_cost(room: RoomData) -> int:
	var d: Dictionary = room.def()
	if room.level >= int(d.get("max_level", 1)):
		return -1
	return build_cost(room.type, room.level + 1)


func food_consumption_per_min() -> float:
	return residents.size() * float(DB.balance.get("food_per_resident_min", 0.4))


# ------------------------------------------------------------------ действия игрока

func can_assign(r: ResidentData, room: RoomData) -> bool:
	if room == null or r == null:
		return false
	if r.room_id == room.id:
		return true
	return workers_in(room.id).size() < worker_slots(room)


func assign(r: ResidentData, room: RoomData) -> bool:
	if not can_assign(r, room):
		toast.emit(tr("TOAST_ROOM_FULL"))
		return false
	if r.room_id == room.id:
		return true
	r.room_id = room.id
	residents_changed.emit()
	resources_changed.emit()
	room_updated.emit(room.id)
	return true


## Забрать накопленное из комнаты в казну (сколько влезет в склады)
func collect(room: RoomData) -> float:
	var res_id := str(room.def().get("resource", ""))
	if res_id == "" or room.stored < 1.0:
		return 0.0
	var free: float = capacity(res_id) - res[res_id]
	var amount: float = floor(minf(room.stored, maxf(free, 0.0)))
	if amount < 1.0:
		toast.emit(tr("TOAST_STORAGE_FULL"))
		return 0.0
	room.stored -= amount
	res[res_id] += amount
	resources_changed.emit()
	room_updated.emit(room.id)
	return amount


func collect_all() -> void:
	for r in rooms.values():
		collect(r)


func can_afford(gold: int) -> bool:
	return res["gold"] >= gold


func build(type_id: String, row: int, col: int) -> bool:
	if room_at(row, col) != null:
		return false
	var cost := build_cost(type_id, 1)
	if not can_afford(cost):
		toast.emit(tr("TOAST_NO_GOLD"))
		return false
	res["gold"] -= cost
	var r := _add_room(type_id, row, col)
	r.build_finish = now() + build_time(type_id, 1)
	r.target_level = 1
	_emit_all()
	return true


func upgrade(room: RoomData) -> bool:
	var cost := upgrade_cost(room)
	if cost < 0 or room.is_building(now()):
		return false
	if not can_afford(cost):
		toast.emit(tr("TOAST_NO_GOLD"))
		return false
	res["gold"] -= cost
	room.target_level = room.level + 1
	room.build_finish = now() + build_time(room.type, room.target_level)
	_emit_all()
	return true


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


## Продвинуть мир на dt секунд, закончившихся в момент t_end. Возвращает прирост по ресурсам.
## Порядок: стройки → выработка → кухни кормят жителей → излишек в буферы → опыт.
func simulate(dt: float, t_end: float) -> Dictionary:
	var gains := {"gold": 0.0, "food": 0.0, "levelups": 0}
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
	# 3) Еда: жители сначала едят свежее с кухонь, остаток — из казны
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
			if amount > 0.0001:
				# Если буфер заполнился раньше конца интервала — работали только часть времени
				productive *= clampf((r.stored - before) / amount, 0.0, 1.0) if r.stored >= room_buffer(r) else 1.0
			if int(before) != int(r.stored):
				room_updated.emit(r.id)
		if str(d.get("stat", "")) != "" and r.type != "throne":
			for w in workers_in(r.id):
				if _give_xp(w, xp_rate * productive / 60.0, str(d["stat"])):
					gains["levelups"] += 1
	if changed_rooms:
		_emit_all()
	else:
		resources_changed.emit()
	return gains


## Опыт за работу; при повышении уровня растёт рабочая характеристика и одна случайная
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
		"version": 1,
		"saved_at": now(),
		"res": res.duplicate(),
		"rooms": rs,
		"residents": ps,
		"next_room_id": next_room_id,
		"next_resident_id": next_resident_id,
		"hungry": hungry,
		"settings": settings.duplicate(),
	}


func from_dict(d: Dictionary) -> void:
	res = {"gold": 0.0, "food": 0.0}
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
		residents.append(p)
	next_room_id = int(d.get("next_room_id", rooms.size() + 1))
	next_resident_id = int(d.get("next_resident_id", residents.size() + 1))
	hungry = bool(d.get("hungry", false))
	var s: Dictionary = d.get("settings", {})
	for k in s.keys():
		settings[k] = s[k]
	last_time = float(d.get("saved_at", now()))
	ready_to_play = true
	_emit_all()
