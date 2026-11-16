extends Node
## Запекатель спрайтов: грузит glTF-модели, ставит их боком (вид 3/4),
## проигрывает анимации и сохраняет кадры в атласы PNG + описание в sprites.json.
##
## Запуск: godot --path tools/sprite_baker -- <папка_с_моделями>
## (на сервере без экрана — через xvfb-run). Модели качает fetch_models.sh.

const PX_PER_M := 100.0       # масштаб: 1 метр модели = 100 px
const FEET_MARGIN := 8.0      # отступ ступней от нижнего края кадра (px)
const HUMAN_FRAME := Vector2i(128, 200)
const HUMAN_HEIGHT := 1.8
const YAW := 68.0             # поворот к камере: смотрит вправо, лицо видно чуть-чуть
const OUTLINE := Color(0.08, 0.05, 0.06)

var cfg: Dictionary
var models_dir: String
var out_dir: String
var vp: SubViewport
var cam: Camera3D
var meta: Dictionary = {}


func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	models_dir = args[0] if args.size() > 0 else "models_src"
	var only: String = args[1] if args.size() > 1 else ""
	cfg = JSON.parse_string(FileAccess.get_file_as_string("res://bake_config.json"))
	out_dir = ProjectSettings.globalize_path("res://").path_join(cfg["out_dir"]).simplify_path()
	DirAccess.make_dir_recursive_absolute(out_dir)
	var old := out_dir.path_join("sprites.json")
	if FileAccess.file_exists(old):
		meta = JSON.parse_string(FileAccess.get_file_as_string(old))
	_setup_stage()
	for h in cfg["humans"]:
		for v in cfg["human_variants"]:
			var id: String = h["id"] + "_" + v["suffix"]
			if only != "" and not id.begins_with(only):
				continue
			var colors: Dictionary = (h.get("colors", {}) as Dictionary).duplicate()
			colors.merge(v["colors"], true)
			await _bake(id, h["src"], HUMAN_FRAME, HUMAN_HEIGHT, cfg["human_anims"], colors,
				h.get("hide", []), {"kind": "human", "female": h.get("female", false), "ruler": h.get("ruler", false)})
	for m in cfg["monsters"]:
		if only != "" and not str(m["id"]).begins_with(only):
			continue
		var fr: Array = m["frame"]
		await _bake(m["id"], m["src"], Vector2i(fr[0], fr[1]), float(m["height"]), cfg["monster_anims"],
			m.get("colors", {}), m.get("hide", []), {"kind": "monster"})
	var f := FileAccess.open(out_dir.path_join("sprites.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "\t", true))
	f.close()
	print("BAKE DONE: ", meta.size(), " sprites")
	get_tree().quit()


func _setup_stage() -> void:
	vp = SubViewport.new()
	vp.transparent_bg = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.own_world_3d = true
	add_child(vp)
	cam = Camera3D.new()
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	vp.add_child(cam)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, -30, 0)
	key.light_energy = 1.25
	vp.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-20, 150, 0)
	rim.light_energy = 0.5
	vp.add_child(rim)
	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.75, 0.72, 0.74)
	env.ambient_light_energy = 1.0
	env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	we.environment = env
	vp.add_child(we)


func _bake(id: String, src: String, frame: Vector2i, height_m: float, anims_cfg: Dictionary,
		colors: Dictionary, hide: Array, extra: Dictionary) -> void:
	var path := models_dir.path_join(src)
	var doc := GLTFDocument.new()
	var st := GLTFState.new()
	if doc.append_from_file(path, st) != OK:
		push_error("Не загрузилась модель " + path)
		return
	var model: Node3D = doc.generate_scene(st)
	var holder := Node3D.new()
	vp.add_child(holder)
	holder.add_child(model)
	for n in hide:
		var hn := model.find_child(n, true, false)
		if hn is Node3D:
			(hn as Node3D).visible = false
	# Масштаб: приводим высоту модели к height_m
	var aabb := _model_aabb(model)
	var k := height_m / maxf(aabb.size.y, 0.01)
	model.scale = Vector3.ONE * k
	model.position.y = -aabb.position.y * k
	holder.rotation_degrees.y = YAW
	_apply_materials(model, colors, 0.018 / k)
	# Камера: 100 px на метр, ступни у нижнего края
	vp.size = frame
	cam.size = frame.y / PX_PER_M
	cam.position = Vector3(0, frame.y / PX_PER_M / 2.0 - FEET_MARGIN / PX_PER_M, 10)
	var ap: AnimationPlayer = model.find_child("AnimationPlayer", true, false)
	var names: Array = []
	var cols := 0
	for a in anims_cfg.keys():
		cols = maxi(cols, int(anims_cfg[a]["frames"]))
	var atlas := Image.create(frame.x * cols, frame.y * anims_cfg.size(), false, Image.FORMAT_RGBA8)
	var info := {"file": id + ".png", "fw": frame.x, "fh": frame.y, "feet": frame.y - FEET_MARGIN, "anims": {}}
	info.merge(extra)
	var row := 0
	for a in anims_cfg.keys():
		var ac: Dictionary = anims_cfg[a]
		var clip := _find_clip(ap, ac["src"])
		var n := int(ac["frames"])
		# Для смерти разворачиваем модель к камере, чтобы падение не вылетало за кадр
		holder.rotation_degrees.y = float(ac.get("yaw", YAW))
		for i in n:
			if clip != "":
				var length := ap.get_animation(clip).length
				var t := (length * i / n) if bool(ac["loop"]) else (length * i / maxf(n - 1, 1))
				ap.play(clip)
				ap.seek(minf(t, length - 0.001), true)
				ap.pause()
			await RenderingServer.frame_post_draw
			await RenderingServer.frame_post_draw
			var img := vp.get_texture().get_image()
			img.convert(Image.FORMAT_RGBA8)
			atlas.blit_rect(img, Rect2i(Vector2i.ZERO, frame), Vector2i(i * frame.x, row * frame.y))
		info["anims"][a] = {"row": row, "frames": n, "fps": ac["fps"], "loop": ac["loop"]}
		names.append(clip)
		row += 1
	atlas.save_png(out_dir.path_join(id + ".png"))
	meta[id] = info
	print("baked ", id, " clips=", names)
	holder.queue_free()
	await get_tree().process_frame


func _find_clip(ap: AnimationPlayer, wanted: Array) -> String:
	if ap == null:
		return ""
	for w in wanted:
		for c in ap.get_animation_list():
			if c == w or c.ends_with("|" + w):
				return c
	return ""


func _model_aabb(n: Node) -> AABB:
	var out := AABB()
	var first := true
	for mi in n.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		if not m.is_visible_in_tree():
			continue
		var b: AABB = m.global_transform * m.get_aabb()
		if first:
			out = b
			first = false
		else:
			out = out.merge(b)
	return out


## Перекраска материалов по имени + чёрный контур (инвертированная оболочка)
func _apply_materials(model: Node, colors: Dictionary, grow: float) -> void:
	var outline := StandardMaterial3D.new()
	outline.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline.albedo_color = OUTLINE
	outline.cull_mode = BaseMaterial3D.CULL_FRONT
	outline.grow = true
	outline.grow_amount = grow
	for mi in model.find_children("*", "MeshInstance3D", true, false):
		var m := mi as MeshInstance3D
		for s in m.mesh.get_surface_count():
			var mat := m.get_active_material(s)
			if mat == null:
				continue
			mat = mat.duplicate()
			if mat is BaseMaterial3D:
				var bm := mat as BaseMaterial3D
				if colors.has(bm.resource_name):
					# Цвета в конфиге — в sRGB, как видит художник
					bm.albedo_color = Color(str(colors[bm.resource_name]))
				bm.roughness = 0.85
				bm.metallic = 0.0
			mat.next_pass = outline
			m.set_surface_override_material(s, mat)
