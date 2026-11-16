extends CanvasLayer
## Интерфейс поверх замка: ресурсы, нижние кнопки, выдвижные панели, тосты.
## Учитывает safe area (вырез под камеру) на телефоне.

const UITheme = preload("res://ui/ui_theme.gd")
const ResIcon = preload("res://ui/res_icon.gd")
const BattleView = preload("res://ui/battle_view.gd")
const BattleSim = preload("res://scripts/battle/battle_sim.gd")
const Sprites = preload("res://scripts/castle/sprites.gd")
const Layout = preload("res://scripts/castle/layout.gd")
const VERSION := "0.2.0"
const RES_ORDER := ["gold", "food", "stone", "ore", "essence"]

var castle: Node2D   # CastleView, задаёт main.gd

var _root: Control
var _top: PanelContainer
var _bottom: HBoxContainer
var _sheet: PanelContainer
var _sheet_box: VBoxContainer
var _sheet_scroll: ScrollContainer
var _dialog: PanelContainer
var _toast: Label
var _toast_time: float = 0.0
var _res_labels: Dictionary = {}
## Функция, заново собирающая открытую панель (при изменении данных)
var _sheet_builder: Callable
## Обновления «живых» подписей в открытой панели (таймеры, накопления)
var _dyn: Array = []
var _dyn_accum: float = 0.0
var _reset_armed: bool = false
var _safe_top: float = 0.0
var _safe_bottom: float = 0.0
## Очередь диалогов (находки летописи, офлайн-отчёт и т.п.)
var _dialog_queue: Array = []
var _dialog_dim: ColorRect
var _battle: Control = null
## Выбранные бойцы и эликсир для подготовки к бою
var _squad: Array = []
var _elixir: bool = false


func _ready() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.theme = UITheme.make()
	# Переводим сами через tr(), автоперевод выключен
	_root.auto_translate_mode = Node.AUTO_TRANSLATE_MODE_DISABLED
	add_child(_root)
	_build_top()
	_build_bottom()
	_build_sheet()
	_build_toast()
	GameState.resources_changed.connect(_update_resources)
	GameState.rooms_changed.connect(_rebuild_sheet)
	GameState.residents_changed.connect(_rebuild_sheet)
	GameState.toast.connect(show_toast)
	GameState.offline_report.connect(_on_offline_report)
	GameState.locale_changed.connect(_on_locale_changed)
	GameState.dungeon_changed.connect(_rebuild_sheet_soft)
	GameState.lore_found.connect(_on_lore_found)
	get_viewport().size_changed.connect(_apply_safe_area)
	_apply_safe_area()
	_update_resources()


# ------------------------------------------------------------------ safe area

func _apply_safe_area() -> void:
	_safe_top = 0.0
	_safe_bottom = 0.0
	if OS.has_feature("mobile"):
		var safe := DisplayServer.get_display_safe_area()
		var win := DisplayServer.window_get_size()
		var vp := get_viewport().get_visible_rect().size
		if win.y > 0 and safe.size.y > 0:
			var k := vp.y / float(win.y)
			_safe_top = safe.position.y * k
			_safe_bottom = maxf(win.y - safe.end.y, 0) * k
	_top.offset_top = 12 + _safe_top
	_top.offset_bottom = _top.offset_top + 100
	_bottom.offset_bottom = -20 - _safe_bottom
	_bottom.offset_top = _bottom.offset_bottom - 120
	_sheet.offset_bottom = -20 - _safe_bottom - 130
	_toast.offset_top = _top.offset_bottom + 16
	_toast.offset_bottom = _toast.offset_top + 70


## Проверка для замка: не попал ли тап в интерфейс
func blocks(p: Vector2) -> bool:
	if _dialog != null and is_instance_valid(_dialog):
		return true
	if _battle != null and is_instance_valid(_battle):
		return true
	for c in [_top, _bottom, _sheet]:
		if c.visible and c.get_global_rect().has_point(p):
			return true
	return false


# ------------------------------------------------------------------ верхняя панель

func _build_top() -> void:
	_top = PanelContainer.new()
	_top.add_theme_stylebox_override("panel", UITheme.box(Color(0.16, 0.12, 0.11, 0.92), UITheme.BORDER, 4, 22, 10))
	_top.anchor_left = 0
	_top.anchor_right = 1
	_top.offset_left = 12
	_top.offset_right = -12
	_root.add_child(_top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 4)
	_top.add_child(hb)
	for k in RES_ORDER:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 2)
		cell.add_child(ResIcon.new(k, 48))
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 27)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		hb.add_child(cell)
		_res_labels[k] = l
	# Тап по ресурсам — подробности о лимитах
	var tap := Button.new()
	tap.flat = true
	tap.custom_minimum_size = Vector2(0, 0)
	tap.mouse_filter = Control.MOUSE_FILTER_STOP
	tap.pressed.connect(open_treasury)
	hb.add_child(tap)
	tap.visible = false
	for cell in hb.get_children():
		if cell is HBoxContainer:
			cell.mouse_filter = Control.MOUSE_FILTER_STOP
			cell.gui_input.connect(func(ev: InputEvent) -> void:
				if ev is InputEventMouseButton and not ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
					open_treasury())
	var gear := Button.new()
	gear.custom_minimum_size = Vector2(76, 76)
	gear.add_child(ResIcon.new("gear", 52))
	(gear.get_child(0) as Control).position = Vector2(12, 12)
	gear.pressed.connect(open_settings)
	hb.add_child(gear)

func _update_resources() -> void:
	if _res_labels.is_empty():
		return
	for k in RES_ORDER:
		var cap := GameState.capacity(k)
		var v := int(GameState.res[k])
		var l: Label = _res_labels[k]
		l.text = _short(v)
		var warn: bool = (k == "food" and GameState.hungry) or v >= int(cap)
		l.add_theme_color_override("font_color", UITheme.BAD if warn else UITheme.TEXT)
	if _bottom != null and _bottom.get_child_count() > 0:
		(_bottom.get_child(0) as Button).text = tr("BTN_RESIDENTS") + " %d/%d" % [GameState.residents.size(), GameState.population_cap()]

static func _short(v: int) -> String:
	if v >= 100000:
		return "%dk" % (v / 1000)
	if v >= 10000:
		return "%.1fk" % (v / 1000.0)
	return str(v)


# ------------------------------------------------------------------ нижние кнопки

func _build_bottom() -> void:
	_bottom = HBoxContainer.new()
	_bottom.anchor_top = 1
	_bottom.anchor_bottom = 1
	_bottom.anchor_left = 0
	_bottom.anchor_right = 1
	_bottom.offset_left = 20
	_bottom.offset_right = -20
	_bottom.add_theme_constant_override("separation", 16)
	_root.add_child(_bottom)
	_rebuild_bottom()


func _rebuild_bottom() -> void:
	for c in _bottom.get_children():
		_bottom.remove_child(c)
		c.queue_free()
	var items := [
		["BTN_RESIDENTS", open_residents],
		["BTN_COLLECT_ALL", _collect_all],
		["BTN_LORE", open_lore],
		["BTN_DEEP", _toggle_view],
	]
	for it in items:
		var b := Button.new()
		b.text = tr(it[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 110
		b.add_theme_font_size_override("font_size", 27)
		b.clip_text = true
		b.pressed.connect(it[1])
		_bottom.add_child(b)
	_update_resources()


## Кнопка переключения «Глубь» ↔ «Замок»
func _toggle_view() -> void:
	if castle.is_deep_view():
		castle.reset_camera()
	else:
		castle.focus_deep()


func _update_view_button() -> void:
	if castle != null and _bottom.get_child_count() >= 4:
		(_bottom.get_child(3) as Button).text = tr("BTN_CASTLE") if castle.is_deep_view() else tr("BTN_DEEP")

func _collect_all() -> void:
	var got := GameState.collect_all()
	if got.is_empty():
		show_toast(tr("TOAST_NOTHING"))
	else:
		show_toast(tr("TOAST_COLLECTED") % cost_text(got))


## «120 золота, 40 камня»
func cost_text(cost: Dictionary) -> String:
	var parts: Array = []
	for k in RES_ORDER:
		if cost.has(k) and float(cost[k]) >= 1.0:
			parts.append("%d %s" % [int(cost[k]), tr("RES_" + k.to_upper())])
	return ", ".join(parts)

# ------------------------------------------------------------------ выдвижная панель

func _build_sheet() -> void:
	_sheet = PanelContainer.new()
	_sheet.anchor_left = 0
	_sheet.anchor_right = 1
	_sheet.anchor_top = 1
	_sheet.anchor_bottom = 1
	_sheet.offset_left = 16
	_sheet.offset_right = -16
	_sheet.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_sheet.visible = false
	_root.add_child(_sheet)
	_sheet_scroll = ScrollContainer.new()
	_sheet_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_sheet.add_child(_sheet_scroll)
	_sheet_box = VBoxContainer.new()
	_sheet_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_sheet_scroll.add_child(_sheet_box)


## Открыть панель: builder заполняет _sheet_box, вызывается заново при изменениях
func _open_sheet(builder: Callable) -> void:
	_sheet_builder = builder
	_reset_armed = false
	_rebuild_sheet()
	_sheet.visible = true


func close_sheet() -> void:
	_sheet.visible = false
	_sheet_builder = Callable()
	_dyn.clear()


## Перестройка при изменениях подземелья — не чаще раза в 0.5 с (раскопки шлют сигнал часто)
var _soft_pending: bool = false


func _rebuild_sheet_soft() -> void:
	if _soft_pending or not _sheet_builder.is_valid():
		return
	_soft_pending = true
	get_tree().create_timer(0.5).timeout.connect(func() -> void:
		_soft_pending = false
		_rebuild_sheet())


func _rebuild_sheet() -> void:
	if not _sheet_builder.is_valid():
		return
	for c in _sheet_box.get_children():
		_sheet_box.remove_child(c)
		c.queue_free()
	_dyn.clear()
	_sheet_builder.call()
	_fit_sheet.call_deferred()


## Высота панели — по содержимому, но не больше ~половины экрана
func _fit_sheet() -> void:
	var vp := get_viewport().get_visible_rect().size
	var max_h := vp.y * 0.52
	var want := _sheet_box.get_combined_minimum_size().y + 56
	var h := minf(want, max_h)
	_sheet_scroll.custom_minimum_size.y = h - 56
	_sheet.offset_top = _sheet.offset_bottom - h


func _process(delta: float) -> void:
	if _toast_time > 0.0:
		_toast_time -= delta
		_toast.modulate.a = clampf(_toast_time / 0.4, 0.0, 1.0)
		_toast.visible = _toast_time > 0.0
	_dyn_accum += delta
	if _dyn_accum >= 0.25:
		_dyn_accum = 0.0
		_update_view_button()
		for f in _dyn:
			f.call()


# --- помощники вёрстки

func _label(text: String, size: int = 32, col: Color = UITheme.TEXT, wrap: bool = false) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.custom_minimum_size.x = 200
	_sheet_box_target().add_child(l)
	return l


var _target_box: Control = null


func _sheet_box_target() -> Control:
	return _target_box if _target_box != null else _sheet_box


func _button(text: String, cb: Callable, parent: Control = null, enabled: bool = true) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size.y = 96
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.disabled = not enabled
	b.pressed.connect(cb)
	(parent if parent != null else _sheet_box_target()).add_child(b)
	return b


func _hbox(parent: Control = null) -> HBoxContainer:
	var hb := HBoxContainer.new()
	(parent if parent != null else _sheet_box).add_child(hb)
	return hb


func _sep() -> void:
	var s := HSeparator.new()
	s.add_theme_constant_override("separation", 10)
	_sheet_box.add_child(s)


func _title(text: String) -> void:
	var hb := _hbox()
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 42)
	l.add_theme_color_override("font_color", Color("#ffd27a"))
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hb.add_child(l)
	var x := Button.new()
	x.text = "X"
	x.custom_minimum_size = Vector2(84, 84)
	x.pressed.connect(close_sheet)
	hb.add_child(x)


# ------------------------------------------------------------------ панель комнаты

func open_room(room_id: int) -> void:
	_open_sheet(func() -> void: _build_room(room_id))


func _build_room(room_id: int) -> void:
	var room = GameState.get_room(room_id)
	if room == null:
		close_sheet()
		return
	var d: Dictionary = room.def()
	var title := tr(str(d.get("name", "")))
	if room.type != "throne":
		title += " — " + tr("LVL_LONG") % room.level
	_title(title)
	_label(tr(str(d.get("desc", ""))), 28, UITheme.MUTED, true)
	var res_id := str(d.get("resource", ""))
	# Стройка
	if room.build_finish > 0.0:
		var bl := _label("", 30, Color("#f5b041"))
		var upd := func() -> void:
			var left := maxf(room.build_finish - GameState.now(), 0.0)
			bl.text = tr("BUILDING_LEFT") % _fmt_time(left) if left > 0 else tr("BUILDING_DONE")
		upd.call()
		_dyn.append(upd)
	# Производство
	if res_id != "":
		var rl := _label("", 30)
		var upd2 := func() -> void:
			rl.text = tr("ROOM_RATE") % [GameState.room_rate(room), tr("RES_" + res_id.to_upper())] \
				+ "\n" + tr("ROOM_STORED") % [int(room.stored), int(GameState.room_buffer(room))]
		upd2.call()
		_dyn.append(upd2)
	if d.has("capacity"):
		_label(tr("ROOM_CAPACITY") % [int(GameState.capacity("gold")), int(GameState.capacity("food"))], 30)
	if room.type == "throne":
		_label(tr("FOOD_USE") % GameState.food_consumption_per_min(), 28, UITheme.MUTED)
		_label(tr("POP_LINE") % [GameState.residents.size(), GameState.population_cap()], 28, UITheme.MUTED)
	if d.has("pop_levels"):
		_label(tr("BEDROOM_BEDS") % int(DB.by_level(d["pop_levels"], room.level)), 30)
	if room.type == "prison":
		_label(tr("PRISON_LINE") % [GameState.captives(room), GameState.captive_cap(room)], 30)
	if room.type == "mine" and GameState.is_vein(room.row, room.col):
		_label(tr("MINE_VEIN"), 28, Color("#ffcf8a"))
	_sep()
	# Работники
	var workers := GameState.workers_in(room.id)
	if GameState.worker_slots(room) == 0:
		pass
	elif room.type == "throne":
		_label(tr("THRONE_IDLE") % workers.size(), 30)
	else:
		_label(tr("ROOM_WORKERS") % [workers.size(), GameState.worker_slots(room)]
			+ "   (" + tr("STAT_" + str(d.get("stat", "")).to_upper()) + ")", 30)
	for w in workers:
		var hb := _hbox()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 28)
		if room.type == "throne":
			info.text = "%s  %s" % [w.display_name(), tr("LVL_SHORT") % w.level]
		else:
			var st := str(d.get("stat", ""))
			info.text = "%s  %s  %s %d  •  %d%%" % [w.display_name(), tr("LVL_SHORT") % w.level,
				tr("STAT_" + st.to_upper() + "_SHORT"), w.stat(st), int(GameState.efficiency(w, room.type) * 100)]
		hb.add_child(info)
		var b := Button.new()
		b.custom_minimum_size = Vector2(190, 80)
		if room.type == "throne":
			b.text = tr("BTN_SHOW")
			b.pressed.connect(func() -> void: castle.focus_resident(w.id); close_sheet())
		else:
			b.text = tr("BTN_UNASSIGN")
			b.pressed.connect(func() -> void: GameState.assign(w, GameState.throne()))
		hb.add_child(b)
	if room.type != "throne" and workers.size() < GameState.worker_slots(room):
		_label(tr("HINT_DRAG"), 26, UITheme.MUTED, true)
	_sep()
	# Кнопки действий
	var hb2 := _hbox()
	if res_id != "":
		_button(tr("BTN_COLLECT"), func() -> void:
			var got := GameState.collect(room)
			if got > 0:
				show_toast("+%d %s" % [int(got), tr("RES_" + res_id.to_upper())])
			_rebuild_sheet(), hb2, room.stored >= 1.0)
	if room.type != "throne":
		var cost := GameState.upgrade_cost(room)
		if cost.is_empty():
			_button(tr("MAX_LEVEL"), func() -> void: pass, hb2, false)
		else:
			_button(tr("BTN_UPGRADE") % cost_text(cost), func() -> void:
				if GameState.upgrade(room):
					show_toast(tr("TOAST_UPGRADE_STARTED")), hb2,
				GameState.can_afford(cost) and room.build_finish <= 0.0)


static func _fmt_time(sec: float) -> String:
	var s := int(ceil(sec))
	if s >= 3600:
		return "%d:%02d:%02d" % [s / 3600, (s % 3600) / 60, s % 60]
	return "%d:%02d" % [s / 60, s % 60]


# ------------------------------------------------------------------ стройка

func open_build(row: int, col: int) -> void:
	_open_sheet(func() -> void: _build_build(row, col))


func _build_build(row: int, col: int) -> void:
	if GameState.room_at(row, col) != null:
		close_sheet()
		return
	var dungeon := Layout.is_dungeon_row(row)
	var tier := Layout.tier_of(row) if dungeon else 0
	_title(tr("BUILD_TITLE_DEEP") % tier if dungeon else tr("BUILD_TITLE"))
	if dungeon and GameState.is_vein(row, col):
		_label(tr("VEIN_HERE"), 28, Color("#ffcf8a"), true)
	var types := DB.buildable_types("dungeon" if dungeon else "castle", tier)
	# Ещё не открытые по глубине — показываем серыми с подсказкой
	var locked: Array = []
	if dungeon:
		for k in DB.rooms.keys():
			var dd: Dictionary = DB.rooms[k]
			if str(dd.get("zone", "")) == "dungeon" and not types.has(k):
				locked.append(k)
	for type_id in types + locked:
		var d: Dictionary = DB.room(type_id)
		var cost := GameState.room_cost(type_id, 1)
		var is_locked: bool = locked.has(type_id)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		_sheet_box.add_child(box)
		_target_box = box
		_label(tr(str(d["name"])), 34, Color("#ffd27a") if not is_locked else UITheme.MUTED)
		_label(tr(str(d.get("desc", ""))), 26, UITheme.MUTED, true)
		_target_box = null
		var hb := _hbox(box)
		var info := Label.new()
		if is_locked:
			info.text = tr("NEED_TIER") % int(d.get("min_tier", 1))
		else:
			info.text = "%s • %s" % [cost_text(cost), _fmt_time(GameState.build_time(type_id, 1))]
		info.add_theme_font_size_override("font_size", 26)
		info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		var b := Button.new()
		b.text = tr("BTN_BUILD")
		b.custom_minimum_size = Vector2(240, 88)
		b.disabled = is_locked or not GameState.can_afford(cost)
		b.pressed.connect(func() -> void:
			if GameState.build(type_id, row, col):
				close_sheet())
		hb.add_child(b)
		_sep()

# ------------------------------------------------------------------ жители

func open_residents() -> void:
	_open_sheet(_build_residents)


func _build_residents() -> void:
	_title(tr("RESIDENTS_TITLE") % [GameState.residents.size(), GameState.population_cap()])
	var rc := GameState.recruit_cost()
	var free := GameState.residents.size() < GameState.population_cap()
	_button(tr("BTN_RECRUIT") % cost_text(rc) if free else tr("NO_BEDS"), func() -> void: GameState.recruit(),
		null, free and GameState.can_afford(rc))
	_label(tr("HINT_DRAG"), 26, UITheme.MUTED, true)
	for r in GameState.residents:
		var room = GameState.get_room(r.room_id)
		var hb := _hbox()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 28)
		var where: String = tr(str(room.def().get("name", ""))) if room != null else "-"
		if r.is_digging():
			where = tr("DIGGING_AT") % int(r.dig[0])
		info.text = "%s  %s\n%s %d  %s %d  %s %d  →  %s" % [
			r.display_name(), tr("LVL_SHORT") % r.level,
			tr("STAT_STR_SHORT"), r.stat("str"), tr("STAT_AGI_SHORT"), r.stat("agi"),
			tr("STAT_INT_SHORT"), r.stat("int"), where]
		hb.add_child(info)
		var b := Button.new()
		b.text = tr("BTN_SHOW")
		b.custom_minimum_size = Vector2(190, 88)
		b.pressed.connect(func() -> void: castle.focus_resident(r.id); open_resident(r.id))
		hb.add_child(b)


func open_resident(id: int) -> void:
	_open_sheet(func() -> void: _build_resident(id))


func _build_resident(id: int) -> void:
	var r = GameState.get_resident(id)
	if r == null:
		close_sheet()
		return
	_title("%s — %s" % [r.display_name(), tr("LVL_LONG") % r.level])
	var xl := _label("", 28, UITheme.MUTED)
	var upd := func() -> void:
		xl.text = tr("XP_LINE") % [int(r.xp), int(r.xp_to_next())]
	upd.call()
	_dyn.append(upd)
	for st in ["str", "agi", "int"]:
		_label("%s: %d" % [tr("STAT_" + st.to_upper()), r.stat(st)], 32)
	var room = GameState.get_room(r.room_id)
	if r.is_digging():
		_label(tr("WORKS_IN") % (tr("DIGGING_AT") % int(r.dig[0])), 30, Color("#ffd27a"))
	elif room != null:
		_label(tr("WORKS_IN") % tr(str(room.def().get("name", ""))), 30, Color("#ffd27a"))
	_sep()
	_label(tr("EFF_TITLE"), 30)
	_label("  %s — %d%%" % [tr("DIG_WORD"), int(GameState.stat_efficiency(r, "str") * 100)], 28, UITheme.MUTED)
	for type_id in DB.buildable_types("castle") + DB.buildable_types("dungeon", 99):
		var d: Dictionary = DB.room(type_id)
		if str(d.get("stat", "")) == "":
			continue
		_label("  %s — %d%%" % [tr(str(d["name"])), int(GameState.efficiency(r, type_id) * 100)], 28, UITheme.MUTED)
	_label(tr("HINT_DRAG"), 26, UITheme.MUTED, true)


# ------------------------------------------------------------------ настройки

func open_settings() -> void:
	_open_sheet(_build_settings)


func _build_settings() -> void:
	_title(tr("SETTINGS_TITLE"))
	_label(tr("SET_LANGUAGE"), 30)
	var hb := _hbox()
	_button("Русский", func() -> void: GameState.set_locale("ru"), hb, TranslationServer.get_locale() != "ru")
	_button("English", func() -> void: GameState.set_locale("en"), hb, TranslationServer.get_locale() != "en")
	_label(tr("SET_FPS"), 30)
	var hb2 := _hbox()
	for fps in [60, 120]:
		_button("%d FPS" % fps, func() -> void: GameState.set_fps(fps); _rebuild_sheet(), hb2,
			int(GameState.settings.get("fps", 60)) != fps)
	_sep()
	_button(tr("SET_RESET_CONFIRM") if _reset_armed else tr("SET_RESET"), func() -> void:
		if _reset_armed:
			SaveSystem.delete_save()
			GameState.new_game()
			SaveSystem.save_game()
			castle.reset_camera()
			close_sheet()
			show_toast(tr("TOAST_RESET"))
		else:
			_reset_armed = true
			_rebuild_sheet())
	_label(tr("SET_ABOUT") % VERSION, 24, UITheme.MUTED, true)


func _on_locale_changed() -> void:
	_rebuild_bottom()
	_rebuild_sheet()
	_update_resources()


# ------------------------------------------------------------------ тосты и диалоги

func _build_toast() -> void:
	_toast = Label.new()
	_toast.anchor_left = 0
	_toast.anchor_right = 1
	_toast.offset_left = 40
	_toast.offset_right = -40
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.add_theme_stylebox_override("normal", UITheme.box(Color(0.1, 0.07, 0.06, 0.88), UITheme.BORDER, 3, 20, 14))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.visible = false
	_root.add_child(_toast)


func show_toast(text: String) -> void:
	_toast.text = text
	_toast.visible = true
	_toast.modulate.a = 1.0
	_toast_time = 2.6


func _on_offline_report(seconds: float, gains: Dictionary) -> void:
	if seconds < 60.0:
		return
	var lines: Array = []
	var cap_h := float(DB.balance.get("offline_cap_hours", 8))
	lines.append(tr("OFFLINE_AWAY") % _fmt_duration(seconds))
	if seconds > cap_h * 3600.0:
		lines.append(tr("OFFLINE_CAPPED") % int(cap_h))
	var g := {}
	for k in RES_ORDER:
		if float(gains.get(k, 0)) >= 1.0:
			g[k] = gains[k]
	lines.append(tr("OFFLINE_GAINS") % (cost_text(g) if not g.is_empty() else "0"))
	if int(gains.get("cells", 0)) > 0:
		lines.append(tr("OFFLINE_CELLS") % int(gains["cells"]))
	if int(gains.get("levelups", 0)) > 0:
		lines.append(tr("OFFLINE_LEVELUPS") % int(gains["levelups"]))
	lines.append(tr("OFFLINE_HINT"))
	show_dialog(tr("OFFLINE_TITLE"), "\n".join(lines))


func _fmt_duration(sec: float) -> String:
	var m := int(sec / 60.0)
	if m < 60:
		return tr("DUR_MIN") % m
	return tr("DUR_HM") % [m / 60, m % 60]


func show_dialog(title: String, body: String) -> void:
	if _dialog != null and is_instance_valid(_dialog):
		_dialog_queue.append([title, body])
		return
	_dialog_dim = ColorRect.new()
	_dialog_dim.color = Color(0, 0, 0, 0.5)
	_dialog_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(_dialog_dim)
	_dialog = PanelContainer.new()
	_dialog.anchor_left = 0.08
	_dialog.anchor_right = 0.92
	_dialog.anchor_top = 0.25
	_dialog.anchor_bottom = 0.25
	_root.add_child(_dialog)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	_dialog.add_child(vb)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 42)
	t.add_theme_color_override("font_color", Color("#ffd27a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 30)
	vb.add_child(b)
	var ok := Button.new()
	ok.text = tr("BTN_OK")
	ok.custom_minimum_size.y = 100
	ok.pressed.connect(_close_dialog)
	vb.add_child(ok)


func _close_dialog() -> void:
	if _dialog_dim != null and is_instance_valid(_dialog_dim):
		_dialog_dim.queue_free()
	if _dialog != null and is_instance_valid(_dialog):
		_dialog.queue_free()
	_dialog = null
	if not _dialog_queue.is_empty():
		var nx: Array = _dialog_queue.pop_front()
		show_dialog.call_deferred(nx[0], nx[1])


# ------------------------------------------------------------------ казна

func open_treasury() -> void:
	_open_sheet(_build_treasury)


func _build_treasury() -> void:
	_title(tr("TREASURY_TITLE"))
	for k in RES_ORDER:
		var hb := _hbox()
		hb.add_child(ResIcon.new(k, 52))
		var l := Label.new()
		l.text = "%s: %d / %d" % [tr("RESNAME_" + k.to_upper()), int(GameState.res[k]), int(GameState.capacity(k))]
		l.add_theme_font_size_override("font_size", 30)
		hb.add_child(l)
	_label(tr("TREASURY_HINT"), 26, UITheme.MUTED, true)


# ------------------------------------------------------------------ летопись

func _on_lore_found(id: String) -> void:
	var e: Dictionary = DB.lore.get(id, {})
	show_dialog(tr("LORE_FOUND") + "\n" + DB.loc(e.get("title", {})), DB.loc(e.get("text", {})))


func open_lore() -> void:
	_open_sheet(_build_lore)


func _build_lore() -> void:
	_title(tr("LORE_TITLE") % [GameState.lore.size(), DB.lore.size()])
	if GameState.lore.is_empty():
		_label(tr("LORE_EMPTY"), 28, UITheme.MUTED, true)
	for id in GameState.lore:
		var e: Dictionary = DB.lore.get(id, {})
		_label(DB.loc(e.get("title", {})), 34, Color("#ffd27a"))
		_label(DB.loc(e.get("text", {})), 28, UITheme.TEXT, true)
		_sep()


# ------------------------------------------------------------------ подземелье: клетки

func open_dungeon(tier: int, dc: int) -> void:
	var c := GameState.cell(tier, dc)
	match str(c.get("s", "")):
		"rock": _open_sheet(func() -> void: _build_rock(tier, dc))
		"lair", "boss":
			if GameState.is_reachable(tier, dc):
				_squad = _auto_squad()
				_elixir = false
				_open_sheet(func() -> void: _build_fight(tier, dc))
			else:
				show_toast(tr("TOAST_LAIR_FAR"))
		"stair": show_toast(tr("STAIR_DOWN") % (tier + 1))


func _build_rock(tier: int, dc: int) -> void:
	var c := GameState.cell(tier, dc)
	if str(c.get("s", "")) != "rock":
		close_sheet()
		return
	_title(tr("ROCK_TITLE") % tier)
	_label(tr(str(DB.biome(tier).get("name", ""))), 28, UITheme.MUTED)
	var hl := _label("", 30)
	var upd := func() -> void:
		var cc := GameState.cell(tier, dc)
		var rate := GameState.dig_rate(tier, dc)
		var line := tr("ROCK_HP") % [int(cc.get("hp", 0)), int(cc.get("max", 0))]
		if rate > 0:
			line += "\n" + tr("ROCK_ETA") % _fmt_time(float(cc.get("hp", 0)) / rate * 60.0)
		hl.text = line
	upd.call()
	_dyn.append(upd)
	if not GameState.is_diggable(tier, dc):
		_label(tr("ROCK_BLOCKED"), 28, UITheme.BAD, true)
		return
	var diggers := GameState.diggers_at(tier, dc)
	_label(tr("DIGGERS") % [diggers.size(), GameState.max_diggers()], 30)
	for w in diggers:
		var hb := _hbox()
		var info := Label.new()
		info.text = "%s  %s  %s %d • %d%%" % [w.display_name(), tr("LVL_SHORT") % w.level, tr("STAT_STR_SHORT"),
			w.stat("str"), int(GameState.stat_efficiency(w, "str") * 100)]
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 28)
		hb.add_child(info)
		var b := Button.new()
		b.text = tr("BTN_UNASSIGN")
		b.custom_minimum_size = Vector2(190, 80)
		b.pressed.connect(func() -> void: GameState.assign(w, GameState.throne()))
		hb.add_child(b)
	_label(tr("HINT_DIG"), 26, UITheme.MUTED, true)
	# Быстрое назначение: самый сильный из отдыхающих в тронном зале
	if diggers.size() < GameState.max_diggers():
		_button(tr("BTN_SEND_DIGGER"), func() -> void:
			var best = null
			for r in GameState.residents:
				if r.is_digging() or r.room_id != GameState.throne().id:
					continue
				if best == null or r.stat("str") > best.stat("str"):
					best = r
			if best == null:
				show_toast(tr("TOAST_NO_IDLE"))
			else:
				GameState.assign_dig(best, tier, dc))


# ------------------------------------------------------------------ бой

func _auto_squad() -> Array:
	var list: Array = GameState.residents.duplicate()
	list.sort_custom(func(a, b) -> bool: return a.level * 10 + a.stat("str") > b.level * 10 + b.stat("str"))
	var out: Array = []
	for i in mini(int(DB.balance.get("squad_size", 3)), list.size()):
		out.append(list[i].id)
	return out


func _build_fight(tier: int, dc: int) -> void:
	var c := GameState.cell(tier, dc)
	if not str(c.get("s", "")) in ["lair", "boss"]:
		close_sheet()
		return
	var boss := str(c["s"]) == "boss"
	_title(tr("FIGHT_BOSS") if boss else tr("FIGHT_LAIR") % tier)
	var foes := GameState.enemies_at(tier, dc)
	var names: Array = []
	var foe_units: Array = []
	for e in foes:
		names.append(tr(str(e["name"])))
		foe_units.append(BattleSim.enemy_unit(e))
	_label(tr("FIGHT_ENEMIES") % ", ".join(names), 28, UITheme.BAD, true)
	var size := int(DB.balance.get("squad_size", 3))
	_label(tr("FIGHT_SQUAD") % [_squad.size(), size], 30)
	var heroes: Array = []
	for r in GameState.residents:
		var on: bool = _squad.has(r.id)
		var b := Button.new()
		b.custom_minimum_size.y = 80
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.text = "%s %s   %s %d  %s %d  %s %d" % ["[x]" if on else "[  ]", r.display_name(), tr("STAT_STR_SHORT"),
			r.stat("str"), tr("STAT_AGI_SHORT"), r.stat("agi"), tr("STAT_INT_SHORT"), r.stat("int")]
		b.add_theme_font_size_override("font_size", 26)
		if on:
			b.add_theme_stylebox_override("normal", UITheme.box(Color("#4a6a2a"), Color("#bfe07a"), 4, 16, 14))
		b.pressed.connect(func() -> void:
			if _squad.has(r.id):
				_squad.erase(r.id)
			elif _squad.size() < size:
				_squad.append(r.id)
			_rebuild_sheet())
		_sheet_box.add_child(b)
		if on:
			heroes.append(BattleSim.hero_unit(r, 0.0))
	# Эликсир силы за эссенцию
	var ec := int(DB.balance.get("elixir_cost", 10))
	var bonus := float(DB.balance.get("elixir_bonus", 0.3))
	var eb := Button.new()
	eb.custom_minimum_size.y = 80
	eb.text = ("[x] " if _elixir else "[  ] ") + tr("ELIXIR") % [ec, int(bonus * 100)]
	eb.disabled = GameState.res["essence"] < ec and not _elixir
	eb.add_theme_font_size_override("font_size", 26)
	eb.pressed.connect(func() -> void:
		_elixir = not _elixir
		_rebuild_sheet())
	_sheet_box.add_child(eb)
	var mine := BattleSim.power(heroes) * (1.0 + (bonus if _elixir else 0.0))
	var theirs := BattleSim.power(foe_units)
	var ratio := mine / maxf(theirs, 1.0)
	var verdict := tr("ODDS_GOOD") if ratio > 1.3 else (tr("ODDS_EVEN") if ratio > 0.9 else tr("ODDS_BAD"))
	_label(verdict, 30, UITheme.GOOD if ratio > 1.3 else (UITheme.TEXT if ratio > 0.9 else UITheme.BAD))
	_button(tr("BTN_FIGHT"), func() -> void: _start_battle(tier, dc), null, not _squad.is_empty())


func _start_battle(tier: int, dc: int) -> void:
	var use_elixir := _elixir and GameState.pay({"essence": int(DB.balance.get("elixir_cost", 10))})
	var bonus := float(DB.balance.get("elixir_bonus", 0.3)) if use_elixir else 0.0
	var heroes: Array = []
	for id in _squad:
		var r = GameState.get_resident(id)
		if r != null:
			heroes.append(BattleSim.hero_unit(r, bonus))
	var foes: Array = []
	for e in GameState.enemies_at(tier, dc):
		foes.append(BattleSim.enemy_unit(e))
	var sim := BattleSim.new()
	sim.setup(heroes, foes)
	close_sheet()
	var boss := str(GameState.cell(tier, dc).get("s", "")) == "boss"
	var bv := BattleView.new()
	_battle = bv
	_root.add_child(bv)
	var ids := _squad.duplicate()
	bv.start(sim, tr("FIGHT_BOSS") if boss else tr("FIGHT_LAIR") % tier, DB.biome(tier).get("colors", {}),
		func(won: bool) -> void:
			var rw := GameState.fight_result(tier, dc, won, ids)
			var txt := ""
			if won:
				var g := {}
				for k in RES_ORDER:
					if rw.has(k):
						g[k] = rw[k]
				txt = tr("BATTLE_REWARD") % cost_text(g)
				if rw.has("captive"):
					txt += "\n" + tr("TOAST_CAPTIVE")
				txt += "\n" + tr("BATTLE_XP") % int(rw.get("xp", 0))
			else:
				txt = tr("BATTLE_LOST_HINT")
			bv.show_result(txt))
	bv.closed.connect(func(_w: bool) -> void: _battle = null)

