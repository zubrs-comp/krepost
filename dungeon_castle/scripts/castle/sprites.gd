extends RefCounted
## Библиотека запечённых спрайтов (assets/sprites, см. tools/sprite_baker).
## Хранит описание атласов и рисует нужный кадр анимации.

const DIR := "res://assets/sprites/"

static var _meta: Dictionary = {}
static var _tex: Dictionary = {}


static func meta_all() -> Dictionary:
	if _meta.is_empty():
		var txt := FileAccess.get_file_as_string(DIR + "sprites.json")
		var d: Variant = JSON.parse_string(txt)
		if typeof(d) == TYPE_DICTIONARY:
			_meta = d
	return _meta


static func meta(id: String) -> Dictionary:
	return meta_all().get(id, {})


static func texture(id: String) -> Texture2D:
	if not _tex.has(id):
		var m := meta(id)
		_tex[id] = load(DIR + str(m.get("file", ""))) if not m.is_empty() else null
	return _tex[id]


## Список спрайтов жителей: женские или мужские (без правителя)
static func resident_ids(female: bool) -> Array:
	var out: Array = []
	for id in meta_all().keys():
		var m: Dictionary = _meta[id]
		if str(m.get("kind", "")) == "human" and bool(m.get("female", false)) == female and not bool(m.get("ruler", false)):
			out.append(id)
	out.sort()
	return out


static func anim_length(id: String, anim: String) -> float:
	var a: Dictionary = meta(id).get("anims", {}).get(anim, {})
	if a.is_empty():
		return 0.0
	return float(a["frames"]) / float(a["fps"])


static func has_anim(id: String, anim: String) -> bool:
	return meta(id).get("anims", {}).has(anim)


## Нарисовать кадр: feet — точка ступней, flip — смотреть влево, t — время с начала анимации
static func draw(ci: CanvasItem, id: String, anim: String, t: float, feet: Vector2,
		flip: bool = false, scale: float = 1.0, mod: Color = Color.WHITE) -> void:
	var m := meta(id)
	var tex := texture(id)
	if m.is_empty() or tex == null:
		return
	var anims: Dictionary = m["anims"]
	var a: Dictionary = anims.get(anim, anims.get("idle", {}))
	if a.is_empty():
		return
	var n := int(a["frames"])
	var f := int(t * float(a["fps"]))
	f = f % n if bool(a["loop"]) else mini(f, n - 1)
	var fw := float(m["fw"])
	var fh := float(m["fh"])
	var src := Rect2(f * fw, int(a["row"]) * fh, fw, fh)
	var dst := Rect2(Vector2(-fw / 2.0, -float(m["feet"])) * scale, Vector2(fw, fh) * scale)
	ci.draw_set_transform(feet, 0.0, Vector2(-1.0 if flip else 1.0, 1.0))
	ci.draw_texture_rect_region(tex, dst, src, mod)
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
