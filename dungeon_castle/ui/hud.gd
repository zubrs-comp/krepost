extends CanvasLayer
## Интерфейс поверх замка: ресурсы, нижние кнопки, выдвижные панели, тосты.
## Учитывает safe area (вырез под камеру) на телефоне.

const UITheme = preload("res://ui/ui_theme.gd")
const ResIcon = preload("res://ui/res_icon.gd")
const VERSION := "0.1.0 (MVP)"

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
	_top.offset_left = 16
	_top.offset_right = -16
	_root.add_child(_top)
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	_top.add_child(hb)
	for k in ["gold", "food", "people"]:
		var cell := HBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 6)
		cell.add_child(ResIcon.new(k, 56))
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 30)
		l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		cell.add_child(l)
		hb.add_child(cell)
		_res_labels[k] = l
	var gear := Button.new()
	gear.custom_minimum_size = Vector2(80, 80)
	gear.add_child(ResIcon.new("gear", 56))
	(gear.get_child(0) as Control).position = Vector2(12, 12)
	gear.pressed.connect(open_settings)
	hb.add_child(gear)


func _update_resources() -> void:
	if _res_labels.is_empty():
		return
	for k in ["gold", "food"]:
		var cap := GameState.capacity(k)
		var v := int(GameState.res[k])
		var l: Label = _res_labels[k]
		l.text = "%s/%s" % [_short(v), _short(int(cap))]
		var warn: bool = (k == "food" and GameState.hungry) or v >= int(cap)
		l.add_theme_color_override("font_color", UITheme.BAD if warn else UITheme.TEXT)
	(_res_labels["people"] as Label).text = str(GameState.residents.size())


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
		c.queue_free()
	var items := [
		["BTN_RESIDENTS", open_residents],
		["BTN_COLLECT_ALL", _collect_all],
		["BTN_CENTER", func() -> void: castle.reset_camera()],
	]
	for it in items:
		var b := Button.new()
		b.text = tr(it[0])
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.custom_minimum_size.y = 110
		b.pressed.connect(it[1])
		_bottom.add_child(b)


func _collect_all() -> void:
	var before := {"gold": GameState.res["gold"], "food": GameState.res["food"]}
	GameState.collect_all()
	var g := int(GameState.res["gold"] - before["gold"])
	var f := int(GameState.res["food"] - before["food"])
	if g > 0 or f > 0:
		show_toast(tr("TOAST_COLLECTED") % [g, f])
	else:
		show_toast(tr("TOAST_NOTHING"))


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
	_sep()
	# Работники
	var workers := GameState.workers_in(room.id)
	if room.type == "throne":
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
		if cost < 0:
			_button(tr("MAX_LEVEL"), func() -> void: pass, hb2, false)
		else:
			_button(tr("BTN_UPGRADE") % cost, func() -> void:
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
	_title(tr("BUILD_TITLE"))
	for type_id in DB.buildable_types():
		var d: Dictionary = DB.room(type_id)
		var cost := GameState.build_cost(type_id, 1)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 6)
		_sheet_box.add_child(box)
		_target_box = box
		_label(tr(str(d["name"])), 34, Color("#ffd27a"))
		_label(tr(str(d.get("desc", ""))), 26, UITheme.MUTED, true)
		_target_box = null
		var hb := _hbox(box)
		var info := Label.new()
		info.text = tr("BUILD_INFO") % [cost, _fmt_time(GameState.build_time(type_id, 1))]
		info.add_theme_font_size_override("font_size", 28)
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hb.add_child(info)
		var b := Button.new()
		b.text = tr("BTN_BUILD")
		b.custom_minimum_size = Vector2(260, 88)
		b.disabled = not GameState.can_afford(cost)
		b.pressed.connect(func() -> void:
			if GameState.build(type_id, row, col):
				close_sheet())
		hb.add_child(b)
		_sep()


# ------------------------------------------------------------------ жители

func open_residents() -> void:
	_open_sheet(_build_residents)


func _build_residents() -> void:
	_title(tr("RESIDENTS_TITLE") % GameState.residents.size())
	_label(tr("HINT_DRAG"), 26, UITheme.MUTED, true)
	for r in GameState.residents:
		var room = GameState.get_room(r.room_id)
		var hb := _hbox()
		var info := Label.new()
		info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		info.add_theme_font_size_override("font_size", 28)
		var where: String = tr(str(room.def().get("name", ""))) if room != null else "-"
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
	if room != null:
		_label(tr("WORKS_IN") % tr(str(room.def().get("name", ""))), 30, Color("#ffd27a"))
	_sep()
	_label(tr("EFF_TITLE"), 30)
	for type_id in DB.buildable_types():
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
	lines.append(tr("OFFLINE_GAINS") % [int(gains.get("gold", 0)), int(gains.get("food", 0))])
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
		_dialog.queue_free()
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.5)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(dim)
	_dialog = PanelContainer.new()
	_dialog.anchor_left = 0.08
	_dialog.anchor_right = 0.92
	_dialog.anchor_top = 0.3
	_dialog.anchor_bottom = 0.3
	_root.add_child(_dialog)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 20)
	_dialog.add_child(vb)
	var t := Label.new()
	t.text = title
	t.add_theme_font_size_override("font_size", 42)
	t.add_theme_color_override("font_color", Color("#ffd27a"))
	t.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(t)
	var b := Label.new()
	b.text = body
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	b.add_theme_font_size_override("font_size", 30)
	vb.add_child(b)
	var ok := Button.new()
	ok.text = tr("BTN_OK")
	ok.custom_minimum_size.y = 100
	ok.pressed.connect(func() -> void:
		dim.queue_free()
		_dialog.queue_free()
		_dialog = null)
	vb.add_child(ok)
