class_name FloorGenerator
extends RefCounted

const WALL_H := 3.6
const WALL_T := 0.36
const DOOR_W := 1.44
const DOOR_H := 2.48
const VENT_W := 1.14
const VENT_H := 1.06

const BASEBOARD_H := 0.14
const DADO_TOP_Y := 1.42
const DADO_RAIL_H := 0.08
const PLASTER_BOT_Y := 1.50
const CORNICE_BOT_Y := 3.42

# DESIGN.md color constants for signage & lighting
const COL_PAPER := Color(0.867, 0.839, 0.769)      # #DDD6C4
const COL_SODIUM := Color(0.890, 0.635, 0.231)     # #E3A23B
const COL_SIGNAL := Color(0.800, 0.227, 0.180)     # #CC3A2E
const COL_COLD := Color(0.498, 0.722, 0.784)       # #7FB8C8
const COL_PHOSPHOR := Color(0.557, 0.863, 0.620)   # #8EDC9E
const COL_INK := Color(0.039, 0.047, 0.043)        # #0A0C0B

static var _stencil_font: Font = null


static func _get_stencil_font() -> Font:
	if _stencil_font != null:
		return _stencil_font
	if ResourceLoader.exists("res://assets/fonts/Oswald-Variable.ttf"):
		var base := load("res://assets/fonts/Oswald-Variable.ttf") as Font
		if base != null:
			var fv := FontVariation.new()
			fv.base_font = base
			fv.variation_opentype = {"wght": 650}
			_stencil_font = fv
			return _stencil_font
	return null


static func make_horror_environment(ambient_energy: float = 0.14) -> Environment:
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.012, 0.015, 0.014)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.15, 0.20, 0.19)
	env.ambient_light_energy = ambient_energy
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	env.fog_enabled = true
	env.fog_light_color = Color(0.022, 0.027, 0.025)
	env.fog_density = 0.042
	return env


static func get_sector_at(pos: Vector3, lang: String = "ru") -> String:
	var x := pos.x
	var z := pos.z
	var en := (lang == "en")

	if z >= 16.0:
		if x < -18.0:
			return "B-04 · Awakening Ward" if en else "Б-04 · Палата пробуждения"
		if x < -4.0:
			return "B-05 · Staff Canteen" if en else "Б-05 · Столовая персонала"
		if x < 14.0:
			return "P-01 · South Triage" if en else "П-01 · Приёмный отсек"
		return "S-04 · Hazmat Warehouse" if en else "С-04 · Склад химзащиты"

	if z <= -16.0:
		if x < -12.0:
			return "K-03 · Cryo-Archive" if en else "К-03 · Криоархив"
		if x <= 12.0:
			return "A-00 · Evacuation Airlock" if en else "Ш-00 · Северный шлюз"
		return "E-380 · Power Substation" if en else "Э-380 · Подстанция"

	if x <= -18.0:
		if z >= 2.0:
			return "X-01 · Operating Theater" if en else "Х-01 · Операционная · Изолятор"
		return "M-02 · Autopsy Morgue" if en else "М-02 · Патологоанатомия"

	if x >= 18.0:
		if z < 0.0:
			return "G-01 · Security Command" if en else "О-01 · Пост охраны"
		return "D-02 · Decontamination" if en else "Д-02 · Санпропускник"

	if x >= -10.0 and x <= 10.0 and z >= -9.0 and z <= 9.0:
		if x < 0.0:
			return "C-07 · Bio-Containment Lab" if en else "Ц-07 · Биолаборатория"
		return "C-08 · Observation Archive" if en else "Ц-08 · Архив наблюдений"

	if z < -9.0:
		return "R-N · North Ring Gallery" if en else "Г-С · Северная галерея"
	if z > 9.0:
		return "R-S · South Ring Gallery" if en else "Г-Ю · Южная галерея"
	if x < 0.0:
		return "R-W · West Ring Gallery" if en else "Г-З · Западная галерея"
	return "R-E · East Ring Gallery" if en else "Г-В · Восточная галерея"


static func _add_static_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, meta: Dictionary = {}) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	for k in meta.keys():
		sb.set_meta(k, meta[k])

	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)

	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	sb.add_child(mi)

	parent.add_child(sb)
	return sb


static func _add_collider_box(parent: Node3D, size: Vector3, pos: Vector3) -> StaticBody3D:
	var sb := StaticBody3D.new()
	sb.position = pos
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	cs.shape = shape
	sb.add_child(cs)
	parent.add_child(sb)
	return sb


static func _add_visual_box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.position = pos
	mi.material_override = mat
	parent.add_child(mi)
	return mi


static func _add_wall_bands(
	parent: Node3D,
	center_x: float,
	seg_len: float,
	y_bottom: float,
	y_top: float,
	trim_len: float,
	lower_mat_pos_z: Material,
	lower_mat_neg_z: Material = null
) -> void:
	if seg_len <= 0.01 or y_top <= y_bottom:
		return
	var mat_pos := lower_mat_pos_z if lower_mat_pos_z != null else AssetLibrary.get_world_material("wall_lower_teal")
	var mat_neg := lower_mat_neg_z if lower_mat_neg_z != null else mat_pos
	var m_dado := AssetLibrary.get_world_material("dado_strip")
	var m_upper := AssetLibrary.get_world_material("wall_upper_cream")
	var m_cornice := AssetLibrary.get_world_material("wall_industrial")

	# 1. Dark baseboard skirting (0.00..0.14m)
	var b0 := maxf(y_bottom, 0.0)
	var b1 := minf(y_top, BASEBOARD_H)
	if b1 > b0:
		_add_visual_box(parent, Vector3(trim_len, b1 - b0, WALL_T + 0.018), Vector3(center_x, (b0 + b1) * 0.5, 0.0), m_dado)

	# 2. Lower institutional oil-paint / tile / bunker panel (0.14..1.42m)
	var l0 := maxf(y_bottom, BASEBOARD_H)
	var l1 := minf(y_top, DADO_TOP_Y)
	if l1 > l0:
		var lh := l1 - l0
		var ly := (l0 + l1) * 0.5
		if mat_pos == mat_neg:
			_add_visual_box(parent, Vector3(seg_len, lh, WALL_T), Vector3(center_x, ly, 0.0), mat_pos)
		else:
			_add_visual_box(parent, Vector3(seg_len, lh, WALL_T * 0.5), Vector3(center_x, ly, WALL_T * 0.25), mat_pos)
			_add_visual_box(parent, Vector3(seg_len, lh, WALL_T * 0.5), Vector3(center_x, ly, -WALL_T * 0.25), mat_neg)

	# 3. Projecting dado rail stripe (1.42..1.50m, proud by 0.02m on both sides)
	var d0 := maxf(y_bottom, DADO_TOP_Y)
	var d1 := minf(y_top, PLASTER_BOT_Y)
	if d1 > d0:
		_add_visual_box(parent, Vector3(trim_len, d1 - d0, WALL_T + 0.04), Vector3(center_x, (d0 + d1) * 0.5, 0.0), m_dado)

	# 4. Upper aged plaster cream (1.50..3.42m)
	var u0 := maxf(y_bottom, PLASTER_BOT_Y)
	var u1 := minf(y_top, CORNICE_BOT_Y)
	if u1 > u0:
		_add_visual_box(parent, Vector3(seg_len, u1 - u0, WALL_T), Vector3(center_x, (u0 + u1) * 0.5, 0.0), m_upper)

	# 5. Top concrete cornice / cable-tray beam (3.42..3.60m)
	var c0 := maxf(y_bottom, CORNICE_BOT_Y)
	var c1 := minf(y_top, WALL_H)
	if c1 > c0:
		_add_visual_box(parent, Vector3(trim_len, c1 - c0, WALL_T + 0.028), Vector3(center_x, (c0 + c1) * 0.5, 0.0), m_cornice)


static func _add_solid_wall(
	parent: Node3D,
	p_start: Vector2,
	p_end: Vector2,
	mat: Material,
	wall_segs_out: Array[Dictionary] = [],
	mat_neg_z: Material = null
) -> void:
	var delta := p_end - p_start
	var length := delta.length()
	var mid := (p_start + p_end) * 0.5
	var yaw := atan2(-delta.y, delta.x)
	var visual_len := length + WALL_T * 0.5

	var holder := Node3D.new()
	holder.position = Vector3(mid.x, 0.0, mid.y)
	holder.rotation.y = yaw
	parent.add_child(holder)

	# Single clean collider box matching original dimensions
	_add_collider_box(holder, Vector3(visual_len, WALL_H, WALL_T), Vector3(0.0, WALL_H * 0.5, 0.0))

	# Pull trim back slightly on Z-aligned walls so corners never z-fight
	var is_z_aligned := absf(delta.y) > absf(delta.x)
	var trim_len := maxf(0.08, length - WALL_T * 0.85) if is_z_aligned else visual_len
	_add_wall_bands(holder, 0.0, visual_len, 0.0, WALL_H, trim_len, mat, mat_neg_z)

	wall_segs_out.append({"a": p_start, "b": p_end, "kind": "wall", "id": ""})


static func _add_wall_with_door(
	parent: Node3D,
	p_start: Vector2,
	p_end: Vector2,
	door_ratio: float,
	mat: Material,
	doors_out: Array[Dictionary],
	door_id: String,
	wall_segs_out: Array[Dictionary] = [],
	mat_neg_z: Material = null,
	transom_mat: Material = null
) -> void:
	var delta := p_end - p_start
	var total_len := delta.length()
	var dir := delta / maxf(total_len, 0.001)
	var yaw := atan2(-dir.y, dir.x)

	var door_center_dist := clampf(total_len * door_ratio, DOOR_W * 0.85, total_len - DOOR_W * 0.85)
	var left_len := maxf(0.12, door_center_dist - DOOR_W * 0.5)
	var right_len := maxf(0.12, total_len - (door_center_dist + DOOR_W * 0.5))
	var lintel_h := WALL_H - DOOR_H

	var holder := Node3D.new()
	holder.position = Vector3(p_start.x, 0.0, p_start.y)
	holder.rotation.y = yaw
	parent.add_child(holder)

	# Exact same 3 StaticBody3D colliders as baseline
	_add_collider_box(holder, Vector3(left_len, WALL_H, WALL_T), Vector3(left_len * 0.5, WALL_H * 0.5, 0.0))
	_add_collider_box(holder, Vector3(right_len, WALL_H, WALL_T), Vector3(total_len - right_len * 0.5, WALL_H * 0.5, 0.0))
	_add_collider_box(holder, Vector3(DOOR_W, lintel_h, WALL_T), Vector3(door_center_dist, DOOR_H + lintel_h * 0.5, 0.0))

	# Two-tone wall bands on left jamb, right jamb, and door lintel
	var is_z_aligned := absf(dir.y) > absf(dir.x)
	var end_pull := WALL_T * 0.45 if is_z_aligned else 0.0
	_add_wall_bands(holder, left_len * 0.5, left_len, 0.0, WALL_H, maxf(0.08, left_len - end_pull), mat, mat_neg_z)
	_add_wall_bands(holder, total_len - right_len * 0.5, right_len, 0.0, WALL_H, maxf(0.08, right_len - end_pull), mat, mat_neg_z)
	_add_wall_bands(holder, door_center_dist, DOOR_W, DOOR_H, WALL_H, DOOR_W, mat, mat_neg_z)

	# Heavy steel doorway frame (jambs + header lintel trim + transom status detail, purely visual)
	var m_metal := AssetLibrary.get_world_material("metal")
	var m_dado := AssetLibrary.get_world_material("dado_strip")
	var half_dw := DOOR_W * 0.5
	_add_visual_box(holder, Vector3(0.06, DOOR_H + 0.04, WALL_T + 0.045), Vector3(door_center_dist - half_dw - 0.015, (DOOR_H + 0.04) * 0.5, 0.0), m_metal)
	_add_visual_box(holder, Vector3(0.06, DOOR_H + 0.04, WALL_T + 0.045), Vector3(door_center_dist + half_dw + 0.015, (DOOR_H + 0.04) * 0.5, 0.0), m_metal)
	_add_visual_box(holder, Vector3(DOOR_W + 0.14, 0.09, WALL_T + 0.055), Vector3(door_center_dist, DOOR_H + 0.045, 0.0), m_metal)
	_add_visual_box(holder, Vector3(0.46, 0.09, WALL_T + 0.06), Vector3(door_center_dist, DOOR_H + 0.15, 0.0), m_dado)
	var m_ind := transom_mat if transom_mat != null else AssetLibrary.get_world_material("emissive_amber")
	_add_visual_box(holder, Vector3(0.14, 0.036, WALL_T + 0.072), Vector3(door_center_dist, DOOR_H + 0.15, 0.0), m_ind)

	var door_inst := AssetLibrary.instantiate_model("door_heavy")
	door_inst.position = Vector3(door_center_dist, 0.0, 0.0)
	holder.add_child(door_inst)

	var piv := AssetLibrary.find_child_by_prefix(door_inst, "DoorPivot") as Node3D
	if piv == null:
		piv = door_inst

	var door_sb := StaticBody3D.new()
	door_sb.collision_layer = 16
	door_sb.collision_mask = 0
	door_sb.position = Vector3(DOOR_W * 0.46, DOOR_H * 0.5, 0.0)
	door_sb.set_meta("interact_type", "door")
	door_sb.set_meta("door_id", door_id)
	var dcs := CollisionShape3D.new()
	var dsh := BoxShape3D.new()
	dsh.size = Vector3(DOOR_W * 0.92, DOOR_H * 0.94, 0.14)
	dcs.shape = dsh
	door_sb.add_child(dcs)
	piv.add_child(door_sb)

	var p_d1 := p_start + dir * (door_center_dist - DOOR_W * 0.5)
	var p_d2 := p_start + dir * (door_center_dist + DOOR_W * 0.5)
	wall_segs_out.append({"a": p_start, "b": p_d1, "kind": "wall", "id": ""})
	wall_segs_out.append({"a": p_d1, "b": p_d2, "kind": "door", "id": door_id})
	wall_segs_out.append({"a": p_d2, "b": p_end, "kind": "wall", "id": ""})

	var world_door_pos := p_start + dir * door_center_dist
	doors_out.append({
		"id": door_id,
		"pivot": piv,
		"collider": door_sb,
		"is_open": false,
		"angle": 0.0,
		"target_angle": 0.0,
		"world_pos": Vector3(world_door_pos.x, 0.0, world_door_pos.y),
		"dir": Vector3(dir.x, 0.0, dir.y),
		"normal": Vector3(-dir.y, 0.0, dir.x)
	})


static func _add_wall_with_vent(
	parent: Node3D,
	p_start: Vector2,
	p_end: Vector2,
	vent_ratio: float,
	mat: Material,
	vents_out: Dictionary,
	vent_id: String,
	crawl_boxes_out: Array[AABB],
	wall_segs_out: Array[Dictionary] = [],
	mat_neg_z: Material = null
) -> void:
	var delta := p_end - p_start
	var total_len := delta.length()
	var dir := delta / maxf(total_len, 0.001)
	var yaw := atan2(-dir.y, dir.x)

	var v_dist := clampf(total_len * vent_ratio, VENT_W * 0.9, total_len - VENT_W * 0.9)
	var left_len := maxf(0.12, v_dist - VENT_W * 0.5)
	var right_len := maxf(0.12, total_len - (v_dist + VENT_W * 0.5))
	var lintel_h := WALL_H - VENT_H

	var holder := Node3D.new()
	holder.position = Vector3(p_start.x, 0.0, p_start.y)
	holder.rotation.y = yaw
	parent.add_child(holder)

	# Exact same 3 StaticBody3D colliders as baseline
	_add_collider_box(holder, Vector3(left_len, WALL_H, WALL_T), Vector3(left_len * 0.5, WALL_H * 0.5, 0.0))
	_add_collider_box(holder, Vector3(right_len, WALL_H, WALL_T), Vector3(total_len - right_len * 0.5, WALL_H * 0.5, 0.0))
	_add_collider_box(holder, Vector3(VENT_W, lintel_h, WALL_T), Vector3(v_dist, VENT_H + lintel_h * 0.5, 0.0))

	# Two-tone wall bands across left, right, and above-vent shaft
	var is_z_aligned := absf(dir.y) > absf(dir.x)
	var end_pull := WALL_T * 0.45 if is_z_aligned else 0.0
	_add_wall_bands(holder, left_len * 0.5, left_len, 0.0, WALL_H, maxf(0.08, left_len - end_pull), mat, mat_neg_z)
	_add_wall_bands(holder, total_len - right_len * 0.5, right_len, 0.0, WALL_H, maxf(0.08, right_len - end_pull), mat, mat_neg_z)
	_add_wall_bands(holder, v_dist, VENT_W, VENT_H, WALL_H, VENT_W, mat, mat_neg_z)

	# Metallic crawlspace duct collar (visual only, flush outside prop_vent_hatch flanges)
	var m_metal := AssetLibrary.get_world_material("metal")
	var half_vw := VENT_W * 0.5
	_add_visual_box(holder, Vector3(0.05, VENT_H + 0.08, WALL_T - 0.02), Vector3(v_dist - half_vw - 0.045, (VENT_H + 0.08) * 0.5, 0.0), m_metal)
	_add_visual_box(holder, Vector3(0.05, VENT_H + 0.08, WALL_T - 0.02), Vector3(v_dist + half_vw + 0.045, (VENT_H + 0.08) * 0.5, 0.0), m_metal)
	_add_visual_box(holder, Vector3(VENT_W + 0.14, 0.055, WALL_T + 0.04), Vector3(v_dist, VENT_H + 0.085, 0.0), m_metal)
	_add_visual_box(holder, Vector3(VENT_W + 0.10, 0.016, WALL_T - 0.02), Vector3(v_dist, 0.008, 0.0), m_metal)

	var v_front := AssetLibrary.instantiate_model("prop_vent_hatch")
	v_front.position = Vector3(v_dist, 0.0, 0.14)
	holder.add_child(v_front)

	var v_back := AssetLibrary.instantiate_model("prop_vent_hatch")
	v_back.position = Vector3(v_dist, 0.0, -0.14)
	v_back.rotation.y = PI
	holder.add_child(v_back)

	var vent_sb := StaticBody3D.new()
	vent_sb.position = Vector3(v_dist, VENT_H * 0.5, 0.0)
	vent_sb.set_meta("interact_type", "vent")
	vent_sb.set_meta("vent_id", vent_id)
	var vcs := CollisionShape3D.new()
	var vsh := BoxShape3D.new()
	vsh.size = Vector3(VENT_W * 0.94, VENT_H * 0.96, WALL_T + 0.12)
	vcs.shape = vsh
	vent_sb.add_child(vcs)
	holder.add_child(vent_sb)

	var p_v1 := p_start + dir * (v_dist - VENT_W * 0.5)
	var p_v2 := p_start + dir * (v_dist + VENT_W * 0.5)
	wall_segs_out.append({"a": p_start, "b": p_v1, "kind": "wall", "id": ""})
	wall_segs_out.append({"a": p_v1, "b": p_v2, "kind": "vent", "id": vent_id})
	wall_segs_out.append({"a": p_v2, "b": p_end, "kind": "wall", "id": ""})

	var wpos2 := p_start + dir * v_dist
	var wpos3 := Vector3(wpos2.x, 0.0, wpos2.y)
	crawl_boxes_out.append(AABB(wpos3 - Vector3(0.85, 0.0, 0.85), Vector3(1.70, 1.25, 1.70)))

	vents_out[vent_id] = {
		"id": vent_id,
		"is_open": false,
		"collider": vent_sb,
		"shape": vcs,
		"grate_a": AssetLibrary.find_child_by_prefix(v_front, "GrateCover") as Node3D,
		"grate_b": AssetLibrary.find_child_by_prefix(v_back, "GrateCover") as Node3D,
		"world_pos": wpos3
	}


static func _add_ceiling_lamp(parent: Node3D, pos: Vector3, col: Color, energy: float, rng_range: float, flicker: bool, lights_out: Array[Dictionary], with_fixture: bool = true, distance_fade: bool = true) -> void:
	if with_fixture:
		var m_dado := AssetLibrary.get_world_material("dado_strip")
		_add_visual_box(parent, Vector3(0.46, 0.06, 0.46), Vector3(pos.x, WALL_H - 0.03, pos.z), m_dado)
		var fix := AssetLibrary.instantiate_model("prop_ceiling_lamp")
		fix.position = Vector3(pos.x, WALL_H + 0.04, pos.z)
		parent.add_child(fix)

	var omni := OmniLight3D.new()
	omni.position = Vector3(pos.x, WALL_H - 0.34, pos.z)
	omni.light_color = col
	omni.light_energy = energy
	omni.omni_range = rng_range
	omni.omni_attenuation = 1.28
	omni.shadow_enabled = false
	if distance_fade:
		omni.distance_fade_enabled = true
		omni.distance_fade_begin = 16.0
		omni.distance_fade_length = 6.0
	parent.add_child(omni)

	if flicker:
		lights_out.append({
			"light": omni,
			"base_energy": energy,
			"phase": pos.x * 1.7 + pos.z * 2.3
		})


static func _place_prop(parent: Node3D, model_name: String, pos: Vector3, yaw: float, collider_sz: Vector3 = Vector3.ZERO) -> Node3D:
	var inst := AssetLibrary.instantiate_model(model_name)
	inst.position = pos
	inst.rotation.y = yaw
	parent.add_child(inst)
	if collider_sz != Vector3.ZERO:
		var sb := StaticBody3D.new()
		sb.position = pos + Vector3(0.0, collider_sz.y * 0.5, 0.0)
		sb.rotation.y = yaw
		var cs := CollisionShape3D.new()
		var bx := BoxShape3D.new()
		bx.size = collider_sz
		cs.shape = bx
		sb.add_child(cs)
		parent.add_child(sb)
	return inst


static func _add_wall_sign(
	parent: Node3D,
	pos: Vector3,
	yaw: float,
	text: String,
	tint: Color = COL_PAPER,
	font_px: int = 38,
	plate_size: Vector2 = Vector2(1.45, 0.28),
	with_plate: bool = true
) -> void:
	var holder := Node3D.new()
	holder.position = pos
	holder.rotation.y = yaw
	parent.add_child(holder)

	var max_line_len := 0
	for line in text.split("\n"):
		max_line_len = maxi(max_line_len, line.length())
	var px_sz := 0.0040
	var min_plate_w := float(max_line_len) * float(font_px) * px_sz * 0.48 + 0.22
	var adj_plate := Vector2(maxf(plate_size.x, min_plate_w), plate_size.y)

	if with_plate:
		var m_plate := AssetLibrary.get_world_material("dado_strip")
		_add_visual_box(holder, Vector3(adj_plate.x, adj_plate.y, 0.016), Vector3(0.0, 0.0, 0.0), m_plate)

	var lbl := Label3D.new()
	lbl.text = text.to_upper()
	var fnt := _get_stencil_font()
	if fnt != null:
		lbl.font = fnt
	lbl.font_size = font_px
	lbl.pixel_size = px_sz
	lbl.modulate = tint
	lbl.outline_modulate = Color(COL_INK.r, COL_INK.g, COL_INK.b, 0.88)
	lbl.outline_size = 6
	lbl.shaded = true
	lbl.double_sided = false
	lbl.position = Vector3(0.0, 0.0, 0.012 if with_plate else 0.004)
	holder.add_child(lbl)


static func _add_ceiling_rib(parent: Node3D, pos: Vector3, size: Vector3) -> void:
	_add_visual_box(parent, size, Vector3(pos.x, WALL_H - size.y * 0.5, pos.z), AssetLibrary.get_world_material("wall_industrial"))


static func _add_ceiling_pipe_run(parent: Node3D, p_start: Vector3, p_end: Vector3, radius: float = 0.055) -> void:
	var delta := p_end - p_start
	var length := delta.length()
	if length <= 0.05:
		return
	var mid := (p_start + p_end) * 0.5
	var mi := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = radius
	cm.bottom_radius = radius
	cm.height = length
	cm.radial_segments = 10
	mi.mesh = cm
	mi.position = mid
	mi.material_override = AssetLibrary.get_world_material("metal")
	if absf(delta.x) >= absf(delta.z):
		mi.rotation.z = PI * 0.5
	else:
		mi.rotation.x = PI * 0.5
	parent.add_child(mi)


static func _add_floor_patch(parent: Node3D, pos: Vector3, size: Vector2, yaw: float, mat_key: String, y_offset: float = 0.009) -> void:
	if mat_key == "blood_stain":
		var q_mi := MeshInstance3D.new()
		var qm := PlaneMesh.new()
		qm.size = size
		q_mi.mesh = qm
		q_mi.position = Vector3(pos.x, y_offset, pos.z)
		q_mi.rotation.y = yaw
		q_mi.material_override = AssetLibrary.get_world_material(mat_key)
		parent.add_child(q_mi)
		return
	var mi := _add_visual_box(
		parent,
		Vector3(size.x, 0.014, size.y),
		Vector3(pos.x, y_offset, pos.z),
		AssetLibrary.get_world_material(mat_key)
	)
	mi.rotation.y = yaw


static func _add_floor_drain(parent: Node3D, pos: Vector3, sz: float = 0.70) -> void:
	var m_dark := AssetLibrary.get_world_material("dado_strip")
	var m_metal := AssetLibrary.get_world_material("metal")
	var h := sz * 0.5
	# Dark recessed basin + perimeter steel frame
	_add_visual_box(parent, Vector3(sz - 0.08, 0.004, sz - 0.08), Vector3(pos.x, 0.003, pos.z), m_dark)
	_add_visual_box(parent, Vector3(sz, 0.012, 0.045), Vector3(pos.x, 0.006, pos.z - h + 0.022), m_metal)
	_add_visual_box(parent, Vector3(sz, 0.012, 0.045), Vector3(pos.x, 0.006, pos.z + h - 0.022), m_metal)
	_add_visual_box(parent, Vector3(0.045, 0.012, sz), Vector3(pos.x - h + 0.022, 0.006, pos.z), m_metal)
	_add_visual_box(parent, Vector3(0.045, 0.012, sz), Vector3(pos.x + h - 0.022, 0.006, pos.z), m_metal)
	# Parallel iron grate bars
	for b_i in range(-2, 3):
		var bz := pos.z + float(b_i) * (sz * 0.16)
		_add_visual_box(parent, Vector3(sz - 0.06, 0.011, 0.028), Vector3(pos.x, 0.006, bz), m_metal)


static func _add_bio_cylinder(parent: Node3D, pos: Vector3, with_light: bool = false, add_collider: bool = true) -> void:
	var holder := Node3D.new()
	holder.position = pos
	parent.add_child(holder)

	var m_metal := AssetLibrary.get_world_material("metal")
	var m_dado := AssetLibrary.get_world_material("dado_strip")
	var m_bio := AssetLibrary.get_world_material("emissive_bio")
	var m_glass := AssetLibrary.get_world_material("glass_bio")

	# Base & Cap pedestals
	var base_mi := MeshInstance3D.new()
	var base_cm := CylinderMesh.new()
	base_cm.top_radius = 0.46
	base_cm.bottom_radius = 0.50
	base_cm.height = 0.36
	base_cm.radial_segments = 16
	base_mi.mesh = base_cm
	base_mi.position = Vector3(0.0, 0.18, 0.0)
	base_mi.material_override = m_dado
	holder.add_child(base_mi)

	var top_mi := MeshInstance3D.new()
	var top_cm := CylinderMesh.new()
	top_cm.top_radius = 0.50
	top_cm.bottom_radius = 0.46
	top_cm.height = 0.30
	top_cm.radial_segments = 16
	top_mi.mesh = top_cm
	top_mi.position = Vector3(0.0, 2.45, 0.0)
	top_mi.material_override = m_dado
	holder.add_child(top_mi)

	# Glowing specimen fluid core
	var core_mi := MeshInstance3D.new()
	var core_cm := CylinderMesh.new()
	core_cm.top_radius = 0.24
	core_cm.bottom_radius = 0.27
	core_cm.height = 1.92
	core_cm.radial_segments = 14
	core_mi.mesh = core_cm
	core_mi.position = Vector3(0.0, 1.32, 0.0)
	core_mi.material_override = m_bio
	holder.add_child(core_mi)

	# Outer containment glass sleeve
	var glass_mi := MeshInstance3D.new()
	var glass_cm := CylinderMesh.new()
	glass_cm.top_radius = 0.40
	glass_cm.bottom_radius = 0.40
	glass_cm.height = 1.96
	glass_cm.radial_segments = 16
	glass_mi.mesh = glass_cm
	glass_mi.position = Vector3(0.0, 1.33, 0.0)
	glass_mi.material_override = m_glass
	holder.add_child(glass_mi)

	# 4 vertical steel protection struts
	for ang_idx in range(4):
		var ang := float(ang_idx) * (PI * 0.5) + PI * 0.25
		var strut := _add_visual_box(
			holder,
			Vector3(0.045, 2.02, 0.045),
			Vector3(cos(ang) * 0.43, 1.33, sin(ang) * 0.43),
			m_metal
		)
		strut.rotation.y = -ang

	if with_light:
		var bl := OmniLight3D.new()
		bl.position = Vector3(0.0, 1.35, 0.0)
		bl.light_color = Color(0.36, 0.96, 0.60)
		bl.light_energy = 0.72
		bl.omni_range = 5.4
		bl.omni_attenuation = 1.35
		bl.shadow_enabled = false
		bl.distance_fade_enabled = true
		bl.distance_fade_begin = 16.0
		bl.distance_fade_length = 6.0
		holder.add_child(bl)

	if add_collider:
		_add_collider_box(holder, Vector3(0.88, 2.60, 0.88), Vector3(0.0, 1.30, 0.0))


static func _add_corridor_pillar(parent: Node3D, px: float, pz: float, wall_segs_out: Array[Dictionary]) -> void:
	var m_teal := AssetLibrary.get_world_material("wall_lower_teal")
	var m_cream := AssetLibrary.get_world_material("wall_upper_cream")
	var m_dado := AssetLibrary.get_world_material("dado_strip")
	var m_ind := AssetLibrary.get_world_material("wall_industrial")
	var m_haz := AssetLibrary.get_world_material("hazard")

	_add_collider_box(parent, Vector3(1.1, WALL_H, 1.1), Vector3(px, WALL_H * 0.5, pz))

	_add_visual_box(parent, Vector3(1.16, 0.16, 1.16), Vector3(px, 0.08, pz), m_dado)
	_add_visual_box(parent, Vector3(1.10, 1.06, 1.10), Vector3(px, 0.69, pz), m_teal)
	_add_visual_box(parent, Vector3(1.12, 0.20, 1.12), Vector3(px, 1.32, pz), m_haz)
	_add_visual_box(parent, Vector3(1.16, 0.08, 1.16), Vector3(px, 1.46, pz), m_dado)
	_add_visual_box(parent, Vector3(1.10, 1.92, 1.10), Vector3(px, 2.46, pz), m_cream)
	_add_visual_box(parent, Vector3(1.18, 0.18, 1.18), Vector3(px, 3.51, pz), m_ind)

	var pr := 0.55
	wall_segs_out.append({"a": Vector2(px - pr, pz - pr), "b": Vector2(px + pr, pz - pr), "kind": "wall", "id": ""})
	wall_segs_out.append({"a": Vector2(px + pr, pz - pr), "b": Vector2(px + pr, pz + pr), "kind": "wall", "id": ""})
	wall_segs_out.append({"a": Vector2(px + pr, pz + pr), "b": Vector2(px - pr, pz + pr), "kind": "wall", "id": ""})
	wall_segs_out.append({"a": Vector2(px - pr, pz + pr), "b": Vector2(px - pr, pz - pr), "kind": "wall", "id": ""})


static func _add_scattered_papers(parent: Node3D, center: Vector3, rng: RandomNumberGenerator, count: int = 4) -> void:
	var m_paper := AssetLibrary.get_world_material("wall_upper_cream")
	for _i in range(count):
		var ox := rng.randf_range(-0.55, 0.55)
		var oz := rng.randf_range(-0.55, 0.55)
		var mi := _add_visual_box(
			parent,
			Vector3(0.21, 0.004, 0.29),
			Vector3(center.x + ox, 0.006, center.z + oz),
			m_paper
		)
		mi.rotation.y = rng.randf_range(0.0, TAU)


# ===========================================================================
# LIVE 3D MAIN MENU HORROR DIORAMA
# ===========================================================================
static func build_menu_diorama(parent: Node3D) -> Dictionary:
	var root := Node3D.new()
	root.name = "MenuDiorama"
	parent.add_child(root)

	var we := WorldEnvironment.new()
	we.environment = make_horror_environment(0.11)
	we.environment.fog_density = 0.056
	root.add_child(we)

	var m_floor := AssetLibrary.get_world_material("floor")
	var m_ceil := AssetLibrary.get_world_material("ceiling")
	var m_teal := AssetLibrary.get_world_material("wall_lower_teal")
	var m_ind := AssetLibrary.get_world_material("wall_industrial")
	var m_red_em := AssetLibrary.get_world_material("emissive_red")

	_add_static_box(root, Vector3(5.6, 0.3, 17.6), Vector3(0, -0.15, -2.0), m_floor)
	_add_static_box(root, Vector3(5.6, 0.3, 17.6), Vector3(0, WALL_H + 0.15, -2.0), m_ceil)

	# Two-tone НИИ-07 Corridor Walls (no flat grey slabs!)
	var dummy_segs: Array[Dictionary] = []
	_add_solid_wall(root, Vector2(-2.7, 6.2), Vector2(-2.7, -10.2), m_teal, dummy_segs)
	_add_solid_wall(root, Vector2(2.7, -10.2), Vector2(2.7, 6.2), m_teal, dummy_segs)
	_add_solid_wall(root, Vector2(-2.7, -10.2), Vector2(2.7, -10.2), m_ind, dummy_segs)

	# Overhead concrete ribs & exposed utility pipe runs
	for rz in [-8.6, -6.0, -3.4, -0.8, 1.8]:
		_add_ceiling_rib(root, Vector3(0.0, 0.0, rz), Vector3(5.2, 0.24, 0.32))
	_add_ceiling_pipe_run(root, Vector3(-1.85, 3.36, 4.5), Vector3(-1.85, 3.36, -10.0), 0.055)
	_add_ceiling_pipe_run(root, Vector3(-1.62, 3.40, 4.5), Vector3(-1.62, 3.40, -10.0), 0.042)
	_add_ceiling_pipe_run(root, Vector3(1.85, 3.38, 4.5), Vector3(1.85, 3.38, -10.0), 0.050)

	# Floor hazard apron, blood drag trail & scattered archive sheets
	_add_floor_patch(root, Vector3(0.0, 0.0, -8.85), Vector2(3.4, 1.15), 0.0, "hazard", 0.009)
	_add_floor_patch(root, Vector3(0.85, 0.0, -2.1), Vector2(0.55, 1.45), 0.14, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(0.62, 0.0, -3.9), Vector2(0.42, 1.85), -0.10, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(0.25, 0.0, -5.8), Vector2(0.36, 1.30), 0.08, "blood_stain", 0.010)

	# Stencilled Cyrillic signage on right wall & airlock bulkhead
	_add_wall_sign(root, Vector3(2.51, 2.02, -2.25), -PI * 0.5, "НИИ-07 · КАРАНТИН", COL_PAPER, 40, Vector2(1.70, 0.30))
	_add_wall_sign(root, Vector3(2.51, 1.66, -2.25), -PI * 0.5, "СЕКТОР И-07 · БИОИЗОЛЯТОР", COL_SODIUM, 24, Vector2(1.70, 0.20))
	_add_wall_sign(root, Vector3(0.0, 2.98, -10.01), 0.0, "СЕВЕРНЫЙ ШЛЮЗ · ВЫХОД", COL_SIGNAL, 36, Vector2(2.15, 0.28))

	# Airlock emergency beacons
	_add_visual_box(root, Vector3(0.18, 0.12, 0.12), Vector3(-1.55, 2.75, -9.96), m_red_em)
	_add_visual_box(root, Vector3(0.18, 0.12, 0.12), Vector3(1.55, 2.75, -9.96), m_red_em)

	# Props staged for depth without cluttering bottom-right corner
	_place_prop(root, "exit_airlock", Vector3(0.0, 0.0, -9.9), PI)
	_place_prop(root, "locker_metal", Vector3(-2.12, 0.0, -3.5), -PI * 0.5)
	_place_prop(root, "prop_shelving_rack", Vector3(2.15, 0.0, -6.4), PI * 0.5)
	_place_prop(root, "prop_gurney", Vector3(-1.62, 0.0, -1.5), 0.22)
	_place_prop(root, "prop_iv_drip", Vector3(-2.12, 0.0, -0.6), 0.40)
	_place_prop(root, "prop_medical_curtain", Vector3(-1.80, 0.0, -5.5), 0.32)
	_place_prop(root, "prop_pipes", Vector3(-2.46, 0.0, -7.2), -PI * 0.5)
	_place_prop(root, "prop_pipes", Vector3(2.46, 0.0, -4.4), PI * 0.5)
	_place_prop(root, "prop_barrel", Vector3(2.08, 0.0, -8.3), 0.45)
	_place_prop(root, "prop_wheelchair", Vector3(-1.32, 0.0, -7.2), 0.62)

	# Listener-07 framed cleanly in the unobstructed right-third of the viewport
	var stalker := AssetLibrary.instantiate_model("monster_stalker")
	stalker.position = Vector3(1.48, 0.0, -2.55)
	stalker.rotation.y = PI + 0.34
	root.add_child(stalker)
	var anim := AssetLibrary.find_animation_player(stalker)
	if anim != null:
		for aname in anim.get_animation_list():
			if aname.to_lower().contains("idle"):
				var a := anim.get_animation(aname)
				if a != null:
					a.loop_mode = Animation.LOOP_LINEAR
				anim.play(aname)
				break

	# Dramatic 3-point horror corridor lighting (warm sodium foreground + cold cyan rim + crimson airlock)
	var flicker_lights: Array[Dictionary] = []
	_add_ceiling_lamp(root, Vector3(-0.2, 0.0, -0.35), Color(1.0, 0.68, 0.30), 1.05, 8.2, false, flicker_lights, false, false)
	_add_ceiling_lamp(root, Vector3(0.85, 0.0, -4.45), Color(0.52, 0.86, 0.96), 1.35, 8.0, false, flicker_lights, true, false)
	_add_ceiling_lamp(root, Vector3(0.0, 0.0, -8.45), Color(1.0, 0.18, 0.14), 1.85, 10.5, true, flicker_lights, true, false)

	# Dedicated rim/key SpotLight sculpting Listener-07 silhouette and right-wall stencil
	var key_spot := SpotLight3D.new()
	key_spot.position = Vector3(-0.35, 2.75, -0.65)
	key_spot.light_color = Color(1.0, 0.78, 0.46)
	key_spot.light_energy = 2.45
	key_spot.spot_range = 8.5
	key_spot.spot_angle = 38.0
	key_spot.spot_attenuation = 1.15
	key_spot.look_at_from_position(key_spot.position, Vector3(1.52, 1.35, -2.55), Vector3.UP)
	root.add_child(key_spot)

	var cam := Camera3D.new()
	cam.fov = 58.0
	cam.position = Vector3(-0.15, 1.48, 2.48)
	cam.look_at_from_position(cam.position, Vector3(-0.82, 1.32, -3.40), Vector3.UP)
	root.add_child(cam)
	cam.make_current()

	return {
		"root": root,
		"camera": cam,
		"stalker": stalker,
		"flicker_lights": flicker_lights
	}


# ===========================================================================
# MASSIVE 64m x 56m (3,584 m²) 14-ROOM LIVED-IN UNDERGROUND COMPLEX
# ===========================================================================
static func build_facility_map(parent: Node3D, rng_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = rng_seed

	var root := Node3D.new()
	root.name = "UndergroundFacility"
	parent.add_child(root)

	var we := WorldEnvironment.new()
	we.environment = make_horror_environment(0.14)
	root.add_child(we)

	var m_floor := AssetLibrary.get_world_material("floor")
	var m_ceil := AssetLibrary.get_world_material("ceiling")
	var m_teal := AssetLibrary.get_world_material("wall_lower_teal")
	var m_surg := AssetLibrary.get_world_material("wall_surgical")
	var m_ind := AssetLibrary.get_world_material("wall_industrial")
	var m_em_amber := AssetLibrary.get_world_material("emissive_amber")
	var m_em_red := AssetLibrary.get_world_material("emissive_red")
	var m_em_cyan := AssetLibrary.get_world_material("emissive_cyan")
	var m_em_bio := AssetLibrary.get_world_material("emissive_bio")

	# 64m x 56m Floor & Ceiling (X: -32..+32, Z: -28..+28)
	_add_static_box(root, Vector3(64.8, 0.4, 56.8), Vector3(0, -0.2, 0), m_floor)
	_add_static_box(root, Vector3(64.8, 0.4, 56.8), Vector3(0, WALL_H + 0.2, 0), m_ceil)

	var wall_segs: Array[Dictionary] = []
	var doors: Array[Dictionary] = []
	var vents: Dictionary = {}
	var crawl_boxes: Array[AABB] = []

	# 1. Outer Concrete Perimeter (-32..+32, -28..+28) split by wing sector material
	# North Perimeter (Z = -28): Cryo (surgical), Airlock (industrial), Substation (industrial)
	_add_solid_wall(root, Vector2(-32, -28), Vector2(-12, -28), m_surg, wall_segs)
	_add_solid_wall(root, Vector2(-12, -28), Vector2(32, -28), m_ind, wall_segs)
	# East Perimeter (X = +32): Substation (industrial), Security & Decon (teal), Warehouse (industrial)
	_add_solid_wall(root, Vector2(32, -28), Vector2(32, -16), m_ind, wall_segs)
	_add_solid_wall(root, Vector2(32, -16), Vector2(32, 16), m_teal, wall_segs)
	_add_solid_wall(root, Vector2(32, 16), Vector2(32, 28), m_ind, wall_segs)
	# South Perimeter (Z = +28): Warehouse (industrial), Triage/Canteen/Ward (teal)
	_add_solid_wall(root, Vector2(32, 28), Vector2(14, 28), m_ind, wall_segs)
	_add_solid_wall(root, Vector2(14, 28), Vector2(-32, 28), m_teal, wall_segs)
	# West Perimeter (X = -32): Ward (teal), Surgery & Morgue & Cryo (surgical)
	_add_solid_wall(root, Vector2(-32, 28), Vector2(-32, 16), m_teal, wall_segs)
	_add_solid_wall(root, Vector2(-32, 16), Vector2(-32, -28), m_surg, wall_segs)

	# 2. South Wing (Z = 16..28): Ward B-04, Staff Canteen, Triage Lobby, Hazmat Warehouse
	# Note: for wall from (-32,16) to (-18,16), +Z side is South (inside room), -Z side is North (Ring Corridor)
	_add_wall_with_door(root, Vector2(-32, 16), Vector2(-18, 16), 0.52, m_teal, doors, "door_ward", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(-18, 16), Vector2(-4, 16), 0.50, m_teal, doors, "door_canteen", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(-4, 16), Vector2(14, 16), 0.50, m_teal, doors, "door_triage", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(14, 16), Vector2(32, 16), 0.50, m_ind, doors, "door_warehouse", wall_segs, m_teal, m_em_amber)

	_add_wall_with_vent(root, Vector2(-18, 16), Vector2(-18, 28), 0.55, m_teal, vents, "vent_ward_canteen", crawl_boxes, wall_segs)
	_add_wall_with_door(root, Vector2(-4, 16), Vector2(-4, 28), 0.50, m_teal, doors, "door_canteen_east", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(14, 16), Vector2(14, 28), 0.50, m_teal, doors, "door_storage_west", wall_segs, m_ind, m_em_amber)

	# 3. North Wing (Z = -28..-16): Cryo-Archive, Main Evacuation Airlock, Power Substation
	# For wall along +X at Z=-16, +Z side is South (Ring/Morgue), -Z side is North (Cryo/Airlock/Gen)
	_add_wall_with_vent(root, Vector2(-32, -16), Vector2(-18, -16), 0.50, m_surg, vents, "vent_morgue_cryo", crawl_boxes, wall_segs, m_surg)
	_add_wall_with_door(root, Vector2(-18, -16), Vector2(-12, -16), 0.50, m_teal, doors, "door_cryo", wall_segs, m_surg, m_em_cyan)
	_add_wall_with_door(root, Vector2(-12, -16), Vector2(0, -16), 0.50, m_teal, doors, "door_airlock_w", wall_segs, m_ind, m_em_red)
	_add_wall_with_door(root, Vector2(0, -16), Vector2(12, -16), 0.50, m_teal, doors, "door_airlock_e", wall_segs, m_ind, m_em_red)
	_add_wall_with_door(root, Vector2(12, -16), Vector2(18, -16), 0.50, m_teal, doors, "door_gen_south", wall_segs, m_ind, m_em_amber)
	_add_wall_with_vent(root, Vector2(18, -16), Vector2(32, -16), 0.50, m_teal, vents, "vent_gen_sec", crawl_boxes, wall_segs, m_ind)

	# For wall along +Z (-28 -> -16), +X is West (left? wait: X_local=+Z -> +Z_local=-X), so +Z_local is West, -Z_local is East
	_add_wall_with_door(root, Vector2(-12, -28), Vector2(-12, -16), 0.50, m_surg, doors, "door_cryo_airlock", wall_segs, m_ind, m_em_red)
	_add_wall_with_door(root, Vector2(12, -28), Vector2(12, -16), 0.50, m_ind, doors, "door_airlock_gen", wall_segs, m_ind, m_em_amber)

	# 4. West Wing (X = -32..-18, Z = -16..+16): Operating Theater (Holding Cage) & Autopsy Morgue
	# Wall along +Z at X=-18: +Z_local is -X (West Wing = surgical), -Z_local is +X (Ring Corridor = teal)
	_add_wall_with_door(root, Vector2(-18, -16), Vector2(-18, 2), 0.50, m_surg, doors, "door_morgue", wall_segs, m_teal, m_em_cyan)
	_add_wall_with_door(root, Vector2(-18, 2), Vector2(-18, 16), 0.50, m_surg, doors, "door_surgery", wall_segs, m_teal, m_em_cyan)
	_add_wall_with_door(root, Vector2(-32, 2), Vector2(-18, 2), 0.52, m_surg, doors, "door_surgery_morgue", wall_segs, m_surg, m_em_cyan)

	# 5. East Wing (X = 18..32, Z = -16..+16): Security Command (Safe) & Decontamination Showers
	_add_wall_with_door(root, Vector2(18, -16), Vector2(18, 0), 0.50, m_teal, doors, "door_security", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(18, 0), Vector2(18, 16), 0.50, m_teal, doors, "door_decon", wall_segs, m_teal, m_em_cyan)
	_add_wall_with_door(root, Vector2(18, 0), Vector2(32, 0), 0.50, m_teal, doors, "door_sec_decon", wall_segs, m_teal, m_em_amber)

	# 6. Central Bio-Research Core (X = -10..+10, Z = -9..+9): Bio-Lab & Observation Archive
	_add_wall_with_door(root, Vector2(-10, -9), Vector2(-10, 9), 0.50, m_teal, doors, "door_biolab_w", wall_segs, m_teal, m_em_bio)
	_add_wall_with_door(root, Vector2(-10, -9), Vector2(0, -9), 0.50, m_teal, doors, "door_biolab_n", wall_segs, m_teal, m_em_bio)
	_add_solid_wall(root, Vector2(0, -9), Vector2(10, -9), m_teal, wall_segs)
	_add_wall_with_door(root, Vector2(10, -9), Vector2(10, 9), 0.50, m_teal, doors, "door_obs_e", wall_segs, m_teal, m_em_amber)
	_add_wall_with_door(root, Vector2(0, 9), Vector2(10, 9), 0.50, m_teal, doors, "door_obs_s", wall_segs, m_teal, m_em_amber)
	_add_wall_with_vent(root, Vector2(-10, 9), Vector2(0, 9), 0.50, m_teal, vents, "vent_biolab_s", crawl_boxes, wall_segs)
	_add_wall_with_door(root, Vector2(0, -9), Vector2(0, 9), 0.50, m_teal, doors, "door_core_link", wall_segs, m_teal, m_em_bio)

	# Architectural Pillars along the Grand Ring Corridors (breaks sightlines & adds stealth cover)
	for px in [-14.0, 14.0]:
		for pz in [-12.5, 12.5]:
			_add_corridor_pillar(root, px, pz, wall_segs)

	# --- OVERHEAD CEILING RIBS & EXPOSED PIPE RUNS (visual depth only, zero colliders) ---
	for rx in [-16.0, -8.5, 8.5, 16.0]:
		_add_ceiling_rib(root, Vector3(rx, 0.0, -12.5), Vector3(0.32, 0.24, 6.8))
		_add_ceiling_rib(root, Vector3(rx, 0.0, 12.5), Vector3(0.32, 0.24, 6.8))
	for rz in [-8.0, 8.0]:
		_add_ceiling_rib(root, Vector3(-14.0, 0.0, rz), Vector3(7.6, 0.24, 0.32))
		_add_ceiling_rib(root, Vector3(14.0, 0.0, rz), Vector3(7.6, 0.24, 0.32))
	# Ceiling ribs inside major wings
	for rx_s in [-25.0, -11.0, 5.0, 23.5]:
		_add_ceiling_rib(root, Vector3(rx_s, 0.0, 19.2), Vector3(0.32, 0.22, 11.4))
		_add_ceiling_rib(root, Vector3(rx_s, 0.0, 24.8), Vector3(0.32, 0.22, 11.4))
	for rx_n in [-25.0, -6.0, 6.0, 22.5]:
		_add_ceiling_rib(root, Vector3(rx_n, 0.0, -22.0), Vector3(0.34, 0.24, 11.4))

	# Longitudinal overhead industrial pipe & cable-tray runs along the Ring & North Utility Spine
	_add_ceiling_pipe_run(root, Vector3(-17.2, 3.38, -11.2), Vector3(17.2, 3.38, -11.2), 0.052)
	_add_ceiling_pipe_run(root, Vector3(-17.2, 3.38, 11.2), Vector3(17.2, 3.38, 11.2), 0.052)
	_add_ceiling_pipe_run(root, Vector3(-12.2, 3.38, -15.0), Vector3(-12.2, 3.38, 15.0), 0.048)
	_add_ceiling_pipe_run(root, Vector3(12.2, 3.38, -15.0), Vector3(12.2, 3.38, 15.0), 0.048)
	_add_ceiling_pipe_run(root, Vector3(12.5, 3.34, -25.2), Vector3(31.2, 3.34, -25.2), 0.060)
	_add_ceiling_pipe_run(root, Vector3(-11.4, 3.36, -26.2), Vector3(11.4, 3.36, -26.2), 0.055)

	# --- KEY OBJECTIVE 1: MAIN ESCAPE BLAST GATE (North Airlock Bay: (0, 0, -27.65)) ---
	var exit_gate := AssetLibrary.instantiate_model("exit_airlock")
	exit_gate.position = Vector3(0.0, 0.0, -27.65)
	exit_gate.rotation.y = PI
	root.add_child(exit_gate)

	var gate_sb := StaticBody3D.new()
	gate_sb.position = Vector3(0.0, 1.4, -27.42)
	gate_sb.set_meta("interact_type", "exit_gate")
	var gcs := CollisionShape3D.new()
	var gsh := BoxShape3D.new()
	gsh.size = Vector3(2.6, 2.8, 0.55)
	gcs.shape = gsh
	gate_sb.add_child(gcs)
	root.add_child(gate_sb)

	# Airlock emergency beacons & floor hazard apron
	_add_visual_box(root, Vector3(0.22, 0.14, 0.14), Vector3(-2.1, 2.88, -27.74), m_em_red)
	_add_visual_box(root, Vector3(0.22, 0.14, 0.14), Vector3(2.1, 2.88, -27.74), m_em_red)
	_add_floor_patch(root, Vector3(0.0, 0.0, -26.15), Vector2(3.6, 1.25), 0.0, "hazard", 0.009)

	# --- KEY OBJECTIVE 2: HIGH-VOLTAGE GENERATOR (NE Power Substation: (30.85, 0, -22.0)) ---
	var gen_node := AssetLibrary.instantiate_model("generator_panel")
	gen_node.position = Vector3(30.9, 0.0, -22.0)
	gen_node.rotation.y = PI * 0.5
	root.add_child(gen_node)

	var gen_sb := StaticBody3D.new()
	gen_sb.position = Vector3(30.82, 0.78, -22.0)
	gen_sb.set_meta("interact_type", "generator")
	var gencs := CollisionShape3D.new()
	var gensh := BoxShape3D.new()
	gensh.size = Vector3(0.95, 1.55, 1.25)
	gencs.shape = gensh
	gen_sb.add_child(gencs)
	root.add_child(gen_sb)

	_add_floor_patch(root, Vector3(29.75, 0.0, -22.0), Vector2(1.45, 2.30), 0.0, "hazard", 0.009)

	# --- KEY OBJECTIVE 3: SECURITY WALL SAFE (East Security Command: (31.1, 1.02, -8.0)) ---
	var safe_code := "%d%d%d%d" % [
		rng.randi_range(1, 9),
		rng.randi_range(0, 9),
		rng.randi_range(1, 9),
		rng.randi_range(0, 9)
	]
	_add_static_box(root, Vector3(0.85, 1.02, 0.85), Vector3(31.1, 0.51, -8.0), m_ind)
	var safe_node := AssetLibrary.instantiate_model("safe_wall")
	safe_node.position = Vector3(31.1, 1.02, -8.0)
	safe_node.rotation.y = PI * 0.5
	root.add_child(safe_node)

	var safe_sb := StaticBody3D.new()
	safe_sb.position = Vector3(31.02, 1.34, -8.0)
	safe_sb.set_meta("interact_type", "safe")
	var scs := CollisionShape3D.new()
	var ssh := BoxShape3D.new()
	ssh.size = Vector3(0.68, 0.70, 0.70)
	scs.shape = ssh
	safe_sb.add_child(scs)
	root.add_child(safe_sb)

	# --- SURGICAL HOLDING CAGE (West Operating Theater: (-30.35, 0, 11.8)) ---
	var cage_pos := Vector3(-30.35, 0.0, 11.8)
	var cage_node := AssetLibrary.instantiate_model("prop_holding_cage")
	cage_node.position = cage_pos
	cage_node.rotation.y = -PI * 0.5 # Front door (-Z) faces +X into Operating Theater!
	root.add_child(cage_node)

	_add_floor_patch(root, Vector3(-28.42, 0.0, 11.8), Vector2(0.70, 3.25), 0.0, "hazard", 0.009)

	var m_metal := AssetLibrary.get_world_material("metal")
	# Physical bar colliders on North, South, and Front-Left/Right flanks
	_add_static_box(root, Vector3(3.2, 2.75, 0.14), cage_pos + Vector3(0.0, 1.37, -1.60), m_metal).visible = false
	_add_static_box(root, Vector3(3.2, 2.75, 0.14), cage_pos + Vector3(0.0, 1.37, 1.60), m_metal).visible = false
	_add_static_box(root, Vector3(0.14, 2.75, 0.95), cage_pos + Vector3(1.60, 1.37, -1.12), m_metal).visible = false
	_add_static_box(root, Vector3(0.14, 2.75, 0.95), cage_pos + Vector3(1.60, 1.37, 1.12), m_metal).visible = false

	var cage_door_piv := AssetLibrary.find_child_by_prefix(cage_node, "CageDoorPivot") as Node3D
	if cage_door_piv == null:
		cage_door_piv = cage_node
	var cage_door_sb := StaticBody3D.new()
	cage_door_sb.position = Vector3(0.62, 1.35, 0.0)
	cage_door_sb.set_meta("interact_type", "cage_door")
	var cd_cs := CollisionShape3D.new()
	var cd_bx := BoxShape3D.new()
	cd_bx.size = Vector3(1.26, 2.68, 0.24)
	cd_cs.shape = cd_bx
	cage_door_sb.add_child(cd_cs)
	cage_door_piv.add_child(cage_door_sb)

	var holding_cage_info := {
		"node": cage_node,
		"door_pivot": cage_door_piv,
		"door_shape": cd_cs,
		"inside_pos": Vector3(-30.5, 0.08, 11.8),
		"outside_pos": Vector3(-27.6, 0.08, 11.8),
		"is_locked": false
	}

	# --- 4 WALL PA INTERCOM LURE STATIONS (triggers distant siren in opposite wing!) ---
	var pa_stations: Dictionary = {}
	var pa_specs := [
		["pa_canteen", Vector3(-11.0, 1.25, 27.68), PI, Vector3(25.0, 1.5, -22.0), "Энергоблок / Substation"],
		["pa_morgue", Vector3(-31.68, 1.25, -7.0), -PI * 0.5, Vector3(24.0, 1.5, 22.0), "Склад / Warehouse"],
		["pa_gen", Vector3(24.0, 1.25, -27.68), 0.0, Vector3(-25.0, 1.5, -7.0), "Морг / Morgue"],
		["pa_obs", Vector3(9.68, 1.25, 3.5), PI * 0.5, Vector3(-11.0, 1.5, 22.0), "Столовая / Canteen"],
	]
	for ps in pa_specs:
		var paid: String = ps[0]
		var papos: Vector3 = ps[1]
		var payaw: float = ps[2]
		var painst := AssetLibrary.instantiate_model("prop_pa_intercom")
		painst.position = papos
		painst.rotation.y = payaw
		root.add_child(painst)

		var pasb := StaticBody3D.new()
		pasb.position = papos + Vector3(0, 0.24, 0)
		pasb.rotation.y = payaw
		pasb.set_meta("interact_type", "pa_intercom")
		pasb.set_meta("pa_id", paid)
		var pacs := CollisionShape3D.new()
		var pabx := BoxShape3D.new()
		pabx.size = Vector3(0.48, 0.56, 0.32)
		pacs.shape = pabx
		pasb.add_child(pacs)
		root.add_child(pasb)

		pa_stations[paid] = {
			"id": paid,
			"pos": papos,
			"target_speaker_pos": ps[3],
			"target_sector_name": ps[4],
			"cooldown": 0.0
		}

	# --- 10 METAL HIDING LOCKERS ---
	var lockers: Dictionary = {}
	var locker_specs := [
		["loc_ward", Vector3(-31.2, 0, 23.5), -PI * 0.5],
		["loc_triage", Vector3(13.2, 0, 26.8), PI * 0.5],
		["loc_warehouse", Vector3(31.2, 0, 22.0), PI * 0.5],
		["loc_morgue", Vector3(-31.2, 0, -11.5), -PI * 0.5],
		["loc_cryo", Vector3(-26.0, 0, -27.2), PI],
		["loc_airlock", Vector3(-10.5, 0, -27.2), PI],
		["loc_gen", Vector3(19.5, 0, -27.2), PI],
		["loc_sec", Vector3(31.2, 0, -3.0), PI * 0.5],
		["loc_biolab", Vector3(-1.0, 0, -8.2), PI],
		["loc_ring_s", Vector3(2.5, 0, 15.2), 0.0],
	]
	for sp in locker_specs:
		var lid: String = sp[0]
		var lpos: Vector3 = sp[1]
		var lyaw: float = sp[2]
		var linst := AssetLibrary.instantiate_model("locker_metal")
		linst.position = lpos
		linst.rotation.y = lyaw
		root.add_child(linst)

		var lsb := StaticBody3D.new()
		lsb.position = lpos + Vector3(0, 1.08, 0)
		lsb.rotation.y = lyaw
		lsb.set_meta("interact_type", "locker")
		lsb.set_meta("locker_id", lid)
		var lcs := CollisionShape3D.new()
		var lsh := BoxShape3D.new()
		lsh.size = Vector3(0.95, 2.15, 0.90)
		lcs.shape = lsh
		lsb.add_child(lcs)
		root.add_child(lsb)

		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, lyaw)
		lockers[lid] = {
			"id": lid,
			"node": linst,
			"door_pivot": AssetLibrary.find_child_by_prefix(linst, "DoorPivot") as Node3D,
			"collider": lsb,
			"inside_pos": lpos + fwd * 0.22 + Vector3(0, 0.05, 0),
			"exit_pos": lpos + fwd * 1.18,
			"look_yaw": lyaw,
			"occupied": false
		}

	# --- 8 UNDER-TABLE HIDING DESKS (plus crawl_boxes from vents!) ---
	var hide_desks: Array[AABB] = []
	for cb in crawl_boxes:
		hide_desks.append(cb)

	var desk_specs := [
		[Vector3(-13.2, 0, 22.0), 0.0],       # Canteen dining table
		[Vector3(-8.2, 0, 24.5), PI * 0.5],   # Canteen dining table 2
		[Vector3(24.0, 0, 26.2), 0.0],        # Warehouse workbench
		[Vector3(-24.0, 0, 6.2), 0.0],        # Surgery prep table
		[Vector3(-22.0, 0, -22.0), PI],       # Cryo-Archive desk
		[Vector3(24.5, 0, -13.5), PI],        # Security Command desk
		[Vector3(5.2, 0, -4.5), 0.0],         # Director's Observation desk
		[Vector3(-14.2, 0, -2.5), PI * 0.5],  # West Ring corridor desk
	]
	for ds in desk_specs:
		var dpos: Vector3 = ds[0]
		var dyaw: float = ds[1]
		var dinst := AssetLibrary.instantiate_model("desk_hide")
		dinst.position = dpos
		dinst.rotation.y = dyaw
		root.add_child(dinst)
		var top_sb := _add_static_box(root, Vector3(1.9, 0.08, 0.96), dpos + Vector3(0, 0.98, 0), AssetLibrary.get_world_material("wood"))
		top_sb.rotation.y = dyaw
		hide_desks.append(AABB(dpos - Vector3(1.0, 0.0, 1.0), Vector3(2.0, 1.15, 2.0)))

	# --- SOUND HAZARDS: 6 BROKEN GLASS PATCHES & 5 SQUEAKY WHEELCHAIRS ---
	var glass_hazards: Array[Dictionary] = []
	var glass_positions := [
		Vector3(-11.0, 0.0, 19.2),  # Canteen entrance
		Vector3(-22.5, 0.0, 8.8),   # Operating Theater floor
		Vector3(-14.0, 0.0, 6.5),   # West Ring Gallery
		Vector3(-5.0, 0.0, -2.0),   # Bio-Lab center
		Vector3(23.5, 0.0, 8.0),    # Decontamination Showers
		Vector3(16.0, 0.0, -20.5),  # Power Substation doorway
	]
	for gp in glass_positions:
		_place_prop(root, "prop_glass_shards", gp, rng.randf_range(0.0, TAU))
		glass_hazards.append({"pos": gp, "radius": 1.15, "cooldown": 0.0})

	var wheelchair_hazards: Array[Dictionary] = []
	var wc_specs := [
		[Vector3(4.5, 0.0, 20.5), 0.4],
		[Vector3(-24.5, 0.0, -5.5), -1.1],
		[Vector3(-14.2, 0.0, -11.0), 0.8],
		[Vector3(14.2, 0.0, 4.5), -0.5],
		[Vector3(25.5, 0.0, 11.5), 2.1],
	]
	for ws in wc_specs:
		var wnode := _place_prop(root, "prop_wheelchair", ws[0], ws[1])
		wheelchair_hazards.append({"node": wnode, "pos": ws[0], "radius": 0.92, "cooldown": 0.0})

	# --- ENVIRONMENTAL STORYTELLING: BIO-SPECIMEN TANKS, FLOOR DRAINS, BLOOD TRAILS & SCATTERED ARCHIVE SHEETS ---
	# Glowing Bio-Containment Glass Specimen Cylinders in Central Bio-Lab (clear of nav_nodes & doors)
	_add_bio_cylinder(root, Vector3(-8.6, 0.0, -4.5), true, true)
	_add_bio_cylinder(root, Vector3(-8.6, 0.0, 4.5), false, true)
	_add_bio_cylinder(root, Vector3(-1.4, 0.0, 6.8), true, true)

	# Floor drain grates
	_add_floor_drain(root, Vector3(-25.0, 0.0, -6.0), 0.72)
	_add_floor_drain(root, Vector3(-25.5, 0.0, 11.8), 0.72)
	_add_floor_drain(root, Vector3(25.0, 0.0, 5.5), 0.72)
	_add_floor_drain(root, Vector3(25.0, 0.0, 10.5), 0.72)
	_add_floor_drain(root, Vector3(-5.0, 0.0, 0.0), 0.76)

	# Dried dark blood drag trails & spill marks (Morgue, Operating Theater, Bio-Lab, West Ring)
	_add_floor_patch(root, Vector3(-26.2, 0.0, -4.2), Vector2(0.65, 1.75), 0.42, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-23.6, 0.0, -9.8), Vector2(0.45, 2.20), -0.35, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-21.2, 0.0, -7.2), Vector2(0.40, 1.55), 1.38, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-23.0, 0.0, 11.8), Vector2(1.10, 1.45), 0.15, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-27.2, 0.0, 11.8), Vector2(2.15, 0.48), 0.06, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-3.4, 0.0, 1.5), Vector2(1.15, 1.30), -0.25, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-5.2, 0.0, -1.8), Vector2(0.75, 0.90), 0.65, "blood_stain", 0.010)
	_add_floor_patch(root, Vector3(-14.2, 0.0, -10.5), Vector2(0.42, 1.40), 0.25, "blood_stain", 0.010)

	# Scattered research papers near desks & archives
	_add_scattered_papers(root, Vector3(2.2, 0.0, 23.2), rng, 5)
	_add_scattered_papers(root, Vector3(5.2, 0.0, -3.2), rng, 6)
	_add_scattered_papers(root, Vector3(-22.2, 0.0, -23.4), rng, 4)
	_add_scattered_papers(root, Vector3(24.5, 0.0, -12.0), rng, 5)
	_add_scattered_papers(root, Vector3(-4.2, 0.0, -3.8), rng, 4)

	# --- STENCILLED CYRILLIC SECTOR SIGNAGE & CORRIDOR WAYFINDING ---
	# Room Entry Plates above doorways (y = 2.86m, bolted flush onto wall faces at +-0.19m)
	_add_wall_sign(root, Vector3(-24.72, 2.86, 15.81), PI, "БЛОК Б-04 · ПАЛАТА", COL_PAPER, 38, Vector2(1.68, 0.28))
	_add_wall_sign(root, Vector3(-24.72, 2.86, 16.19), 0.0, "Х-01 · ОПЕРАЦИОННАЯ · ВЫХОД ↑", COL_SODIUM, 32, Vector2(2.24, 0.28))
	_add_wall_sign(root, Vector3(-11.00, 2.86, 15.81), PI, "Б-05 · СТОЛОВАЯ ПЕРСОНАЛА", COL_PAPER, 34, Vector2(1.88, 0.28))
	_add_wall_sign(root, Vector3(5.00, 2.86, 15.81), PI, "П-01 · ПРИЁМНЫЙ ОТСЕК", COL_PAPER, 36, Vector2(1.76, 0.28))
	_add_wall_sign(root, Vector3(13.81, 2.86, 22.00), -PI * 0.5, "С-04 · СКЛАД ХИМЗАЩИТЫ →", COL_SODIUM, 32, Vector2(1.88, 0.28))
	_add_wall_sign(root, Vector3(23.00, 2.86, 15.81), PI, "С-04 · СКЛАД ХИМЗАЩИТЫ", COL_SODIUM, 36, Vector2(1.86, 0.28))

	_add_wall_sign(root, Vector3(-17.81, 2.86, 9.00), PI * 0.5, "Х-01 · ОПЕРАЦИОННАЯ · ИЗОЛЯТОР", COL_COLD, 30, Vector2(2.24, 0.28))
	_add_wall_sign(root, Vector3(-17.81, 2.86, -7.00), PI * 0.5, "М-02 · ПАТОЛОГОАНАТОМИЯ", COL_COLD, 34, Vector2(1.94, 0.28))
	_add_wall_sign(root, Vector3(-15.00, 2.86, -15.81), 0.0, "К-03 · КРИОАРХИВ", COL_COLD, 38, Vector2(1.56, 0.28))

	_add_wall_sign(root, Vector3(-6.00, 2.86, -15.81), 0.0, "Ш-00 · СЕВЕРНЫЙ ШЛЮЗ · ВЫХОД", COL_SIGNAL, 32, Vector2(2.20, 0.30))
	_add_wall_sign(root, Vector3(6.00, 2.86, -15.81), 0.0, "Ш-00 · СЕВЕРНЫЙ ШЛЮЗ · ВЫХОД", COL_SIGNAL, 32, Vector2(2.20, 0.30))
	_add_wall_sign(root, Vector3(15.00, 2.86, -15.81), 0.0, "Э-380 · ПОДСТАНЦИЯ 380В", COL_SODIUM, 34, Vector2(1.90, 0.28))
	_add_wall_sign(root, Vector3(11.81, 2.86, -22.00), -PI * 0.5, "ПОДСТАНЦИЯ 380В →", COL_SODIUM, 32, Vector2(1.75, 0.28))

	_add_wall_sign(root, Vector3(17.81, 2.86, -8.00), -PI * 0.5, "О-01 · ПОСТ ОХРАНЫ · СЕЙФ", COL_SODIUM, 34, Vector2(1.98, 0.28))
	_add_wall_sign(root, Vector3(17.81, 2.86, 8.00), -PI * 0.5, "Д-02 · САНПРОПУСКНИК", COL_COLD, 36, Vector2(1.80, 0.28))

	_add_wall_sign(root, Vector3(-10.19, 2.86, 0.00), -PI * 0.5, "Ц-07 · БИОЛАБОРАТОРИЯ · СЛУХАЧ-07", COL_PHOSPHOR, 30, Vector2(2.30, 0.28))
	_add_wall_sign(root, Vector3(-5.00, 2.86, -9.19), PI, "Ц-07 · БИОЛАБОРАТОРИЯ", COL_PHOSPHOR, 36, Vector2(1.82, 0.28))
	_add_wall_sign(root, Vector3(10.19, 2.86, 0.00), PI * 0.5, "Ц-08 · НАБЛЮДАТЕЛЬНЫЙ АРХИВ", COL_PAPER, 30, Vector2(2.16, 0.28))
	_add_wall_sign(root, Vector3(5.00, 2.86, 9.19), 0.0, "Ц-08 · АРХИВ НАБЛЮДЕНИЙ", COL_PAPER, 34, Vector2(1.92, 0.28))

	# Airlock interior warning stencil above Blast Gate (exit_airlock top is y=2.8m)
	_add_wall_sign(root, Vector3(0.0, 3.12, -27.80), 0.0, "СЕВЕРНЫЙ ШЛЮЗ ЭВАКУАЦИИ · 4 БЛОКИРОВКИ", COL_SIGNAL, 28, Vector2(2.75, 0.26))

	# Eye-level Corridor Wayfinding Arrows (y = 1.82m on 1.1m pillars & corridor walls)
	_add_wall_sign(root, Vector3(-14.0, 1.82, 13.06), 0.0, "← ОПЕРАЦИОННАЯ\n↑ ШЛЮЗ ВЫХОДА", COL_SODIUM, 22, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(-14.56, 1.82, 12.5), -PI * 0.5, "↑ СТОЛОВАЯ · ПРИЁМНАЯ\n← МОРГ · КРИОАРХИВ", COL_PAPER, 18, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(14.0, 1.82, 13.06), 0.0, "↑ ОХРАНА · ЭНЕРГОБЛОК\nСКЛАД · САНБЛОК →", COL_SODIUM, 18, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(14.56, 1.82, 12.5), PI * 0.5, "ОХРАНА · ЭНЕРГОБЛОК →\n← ПРИЁМНАЯ · СКЛАД", COL_PAPER, 18, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(-14.0, 1.82, -13.06), PI, "← ШЛЮЗ · БИОЛАБ\n↑ ОПЕРАЦИОННАЯ  МОРГ →", COL_COLD, 18, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(-14.56, 1.82, -12.5), -PI * 0.5, "← КРИО · ШЛЮЗ ВЫХОДА\n↑ БИОЛАБ · ОХРАНА", COL_SIGNAL, 18, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(14.0, 1.82, -13.06), PI, "← ЭНЕРГОБЛОК 380В\n↑ ОХРАНА · АРХИВ", COL_SODIUM, 20, Vector2(1.04, 0.34))
	_add_wall_sign(root, Vector3(14.56, 1.82, -12.5), PI * 0.5, "СЕВЕРНЫЙ ШЛЮЗ →\n← ПОСТ ОХРАНЫ · СЕЙФ", COL_SODIUM, 18, Vector2(1.04, 0.34))

	_add_wall_sign(root, Vector3(5.0, 1.84, -9.19), PI, "← ПОДСТАНЦИЯ 380В   |   МОРГ · КРИОАРХИВ →", COL_SODIUM, 28, Vector2(3.15, 0.26))
	_add_wall_sign(root, Vector3(-10.19, 1.84, -4.5), -PI * 0.5, "← СЕВЕРНЫЙ ШЛЮЗ · КРИО   |   ПАЛАТА Б-04 →", COL_PAPER, 26, Vector2(2.75, 0.24))
	_add_wall_sign(root, Vector3(10.19, 1.84, 4.5), PI * 0.5, "← СКЛАД · ПРИЁМНАЯ   |   ОХРАНА · ЭНЕРГОБЛОК →", COL_PAPER, 26, Vector2(3.15, 0.24))
	_add_wall_sign(root, Vector3(-24.72, 1.84, 27.81), PI, "НИИ-07 · ПАЛАТА Б-04 · КАРАНТИН", COL_PAPER, 28, Vector2(2.05, 0.24))

	# --- RICH LIVED-IN ENVIRONMENTAL FURNISHING ACROSS ALL 14 ROOMS ---
	var rich_props := [
		# Room 1: Awakening Ward B-04
		["prop_gurney", Vector3(-28.5, 0, 25.5), 0.18, Vector3(0.9, 0.85, 1.85)],
		["prop_gurney", Vector3(-22.0, 0, 25.2), -0.12, Vector3(0.9, 0.85, 1.85)],
		["prop_medical_curtain", Vector3(-25.2, 0, 25.0), PI * 0.5, Vector3(0.2, 1.8, 1.6)],
		["prop_iv_drip", Vector3(-29.8, 0, 24.5), 0.0, Vector3.ZERO],
		["prop_iv_drip", Vector3(-20.8, 0, 26.0), 0.5, Vector3.ZERO],
		["prop_shelving_rack", Vector3(-28.8, 0, 16.8), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_pipes", Vector3(-31.65, 0, 19.5), -PI * 0.5, Vector3.ZERO],

		# Room 2: Staff Canteen
		["prop_shelving_rack", Vector3(-15.5, 0, 27.2), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_shelving_rack", Vector3(-6.5, 0, 27.2), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_barrel", Vector3(-16.8, 0, 18.0), 0.2, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(-15.9, 0, 17.6), 0.9, Vector3(0.62, 0.95, 0.62)],

		# Room 3: South Triage & Reception
		["prop_computer_terminal", Vector3(2.2, 0, 24.5), PI, Vector3(1.4, 1.0, 0.8)],
		["prop_filing_tall", Vector3(-2.8, 0, 27.2), PI, Vector3(0.6, 1.7, 0.65)],
		["prop_filing_tall", Vector3(-1.9, 0, 27.2), PI, Vector3(0.6, 1.7, 0.65)],
		["prop_gurney", Vector3(9.5, 0, 24.2), 0.35, Vector3(0.9, 0.85, 1.85)],
		["prop_medical_curtain", Vector3(8.5, 0, 21.8), 0.2, Vector3(1.6, 1.8, 0.2)],
		["prop_iv_drip", Vector3(10.8, 0, 24.8), 0.0, Vector3.ZERO],

		# Room 4: Hazmat & Tool Warehouse (Dense industrial shelf aisles!)
		["prop_shelving_rack", Vector3(19.5, 0, 20.5), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_shelving_rack", Vector3(23.5, 0, 20.5), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_shelving_rack", Vector3(19.5, 0, 24.2), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_shelving_rack", Vector3(28.5, 0, 27.2), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_barrel", Vector3(30.5, 0, 18.0), 0.0, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(29.6, 0, 17.6), 0.5, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(30.6, 0, 19.0), 1.1, Vector3(0.62, 0.95, 0.62)],
		["prop_pipes", Vector3(31.65, 0, 25.5), PI * 0.5, Vector3.ZERO],

		# Room 5: Operating Theater (around Holding Cage)
		["prop_gurney", Vector3(-23.0, 0, 11.8), 0.0, Vector3(0.9, 0.85, 1.85)],
		["prop_lab_bench", Vector3(-21.5, 0, 15.2), 0.0, Vector3(2.1, 0.95, 0.82)],
		["prop_medical_curtain", Vector3(-25.2, 0, 8.2), 0.15, Vector3(1.6, 1.8, 0.2)],
		["prop_iv_drip", Vector3(-22.0, 0, 12.8), 0.0, Vector3.ZERO],
		["prop_iv_drip", Vector3(-24.2, 0, 11.0), 0.0, Vector3.ZERO],

		# Room 6: Autopsy Morgue
		["prop_gurney", Vector3(-27.5, 0, -3.5), PI * 0.5, Vector3(1.85, 0.85, 0.9)],
		["prop_corpse_bag", Vector3(-27.5, 0.82, -3.5), PI * 0.5, Vector3.ZERO],
		["prop_gurney", Vector3(-27.5, 0, -8.5), PI * 0.5, Vector3(1.85, 0.85, 0.9)],
		["prop_corpse_bag", Vector3(-27.5, 0.82, -8.5), PI * 0.5, Vector3.ZERO],
		["prop_corpse_bag", Vector3(-22.0, 0.0, -13.8), 0.35, Vector3.ZERO],
		["prop_lab_bench", Vector3(-21.5, 0, -1.2), PI, Vector3(2.1, 0.95, 0.82)],
		["prop_shelving_rack", Vector3(-29.0, 0, -15.2), 0.0, Vector3(1.85, 2.1, 0.65)],

		# Room 7: Cryo-Archive & Server Vault
		["prop_computer_terminal", Vector3(-28.5, 0, -21.5), -PI * 0.5, Vector3(0.8, 1.0, 1.4)],
		["prop_computer_terminal", Vector3(-28.5, 0, -24.5), -PI * 0.5, Vector3(0.8, 1.0, 1.4)],
		["prop_filing_tall", Vector3(-21.0, 0, -27.2), 0.0, Vector3(0.6, 1.7, 0.65)],
		["prop_filing_tall", Vector3(-20.1, 0, -27.2), 0.0, Vector3(0.6, 1.7, 0.65)],
		["prop_filing_tall", Vector3(-19.2, 0, -27.2), 0.0, Vector3(0.6, 1.7, 0.65)],
		["prop_shelving_rack", Vector3(-15.5, 0, -23.0), PI * 0.5, Vector3(0.65, 2.1, 1.85)],

		# Room 8: Main Evacuation Airlock Bay
		["prop_medical_curtain", Vector3(-5.5, 0, -22.5), 0.0, Vector3(1.6, 1.8, 0.2)],
		["prop_medical_curtain", Vector3(5.5, 0, -22.5), 0.0, Vector3(1.6, 1.8, 0.2)],
		["prop_barrel", Vector3(-10.5, 0, -18.0), 0.3, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(10.5, 0, -18.0), 0.8, Vector3(0.62, 0.95, 0.62)],
		["prop_pipes", Vector3(6.5, 0, -27.65), PI, Vector3.ZERO],
		["prop_pipes", Vector3(-6.5, 0, -27.65), PI, Vector3.ZERO],

		# Room 9: High-Voltage Power Substation
		["prop_shelving_rack", Vector3(22.5, 0, -21.5), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_barrel", Vector3(29.8, 0, -26.2), 0.0, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(28.8, 0, -26.5), 0.7, Vector3(0.62, 0.95, 0.62)],
		["prop_pipes", Vector3(31.65, 0, -18.5), PI * 0.5, Vector3.ZERO],
		["prop_pipes", Vector3(15.0, 0, -27.65), PI, Vector3.ZERO],

		# Room 10: Security Command & Safe Room
		["prop_computer_terminal", Vector3(22.5, 0, -4.5), 0.0, Vector3(1.4, 1.0, 0.8)],
		["prop_computer_terminal", Vector3(25.5, 0, -4.5), 0.0, Vector3(1.4, 1.0, 0.8)],
		["prop_filing_tall", Vector3(31.2, 0, -12.5), PI * 0.5, Vector3(0.65, 1.7, 0.6)],
		["prop_filing_tall", Vector3(31.2, 0, -13.4), PI * 0.5, Vector3(0.65, 1.7, 0.6)],
		["prop_shelving_rack", Vector3(21.5, 0, -15.2), 0.0, Vector3(1.85, 2.1, 0.65)],

		# Room 11: Decontamination Showers
		["prop_medical_curtain", Vector3(23.0, 0, 4.5), 0.0, Vector3(1.6, 1.8, 0.2)],
		["prop_medical_curtain", Vector3(27.5, 0, 4.5), 0.0, Vector3(1.6, 1.8, 0.2)],
		["prop_medical_curtain", Vector3(23.0, 0, 11.5), 0.0, Vector3(1.6, 1.8, 0.2)],
		["prop_pipes", Vector3(31.65, 0, 4.5), PI * 0.5, Vector3.ZERO],
		["prop_pipes", Vector3(31.65, 0, 11.5), PI * 0.5, Vector3.ZERO],
		["prop_shelving_rack", Vector3(28.5, 0, 15.2), 0.0, Vector3(1.85, 2.1, 0.65)],

		# Room 12: Central Bio-Containment Lab
		["prop_lab_bench", Vector3(-6.2, 0, -4.5), 0.0, Vector3(2.1, 0.95, 0.82)],
		["prop_lab_bench", Vector3(-6.2, 0, 4.5), 0.0, Vector3(2.1, 0.95, 0.82)],
		["prop_gurney", Vector3(-3.0, 0, 1.5), 0.25, Vector3(0.9, 0.85, 1.85)],
		["prop_corpse_bag", Vector3(-3.0, 0.82, 1.5), 0.25, Vector3.ZERO],
		["prop_iv_drip", Vector3(-2.1, 0, 2.2), 0.0, Vector3.ZERO],

		# Room 13: Observation & Project Archive
		["prop_computer_terminal", Vector3(5.2, 0, 3.8), PI, Vector3(1.4, 1.0, 0.8)],
		["prop_lab_bench", Vector3(6.2, 0, -7.8), PI, Vector3(2.1, 0.95, 0.82)],
		["prop_filing_tall", Vector3(9.2, 0, -6.2), PI * 0.5, Vector3(0.65, 1.7, 0.6)],
		["prop_filing_tall", Vector3(9.2, 0, -5.2), PI * 0.5, Vector3(0.65, 1.7, 0.6)],
		["prop_shelving_rack", Vector3(3.0, 0, -8.2), 0.0, Vector3(1.85, 2.1, 0.65)],

		# Room 14: Grand Ring Galleries (lived-in hallway clutter!)
		["prop_gurney", Vector3(-6.0, 0, -13.2), 0.12, Vector3(0.9, 0.85, 1.85)],
		["prop_shelving_rack", Vector3(8.0, 0, -10.0), 0.0, Vector3(1.85, 2.1, 0.65)],
		["prop_barrel", Vector3(-16.8, 0, 12.8), 0.0, Vector3(0.62, 0.95, 0.62)],
		["prop_barrel", Vector3(16.8, 0, -12.8), 0.4, Vector3(0.62, 0.95, 0.62)],
		["prop_gurney", Vector3(9.0, 0, 12.8), -0.22, Vector3(0.9, 0.85, 1.85)],
	]
	for rp in rich_props:
		_place_prop(root, rp[0], rp[1], rp[2], rp[3])

	# --- ATMOSPHERIC CEILING LIGHTING ACROSS ALL 14 SECTORS ---
	var flicker_lights: Array[Dictionary] = []
	_add_ceiling_lamp(root, Vector3(-25.0, 0, 22.0), Color(0.96, 0.68, 0.32), 0.95, 12.5, false, flicker_lights) # Ward B-04 (sodium)
	_add_ceiling_lamp(root, Vector3(-11.0, 0, 22.0), Color(0.92, 0.64, 0.28), 0.85, 12.5, true, flicker_lights)  # Canteen (flickering sodium)
	_add_ceiling_lamp(root, Vector3(5.0, 0, 22.0), Color(0.76, 0.88, 0.92), 0.92, 13.5, false, flicker_lights)   # Triage (sterile)
	_add_ceiling_lamp(root, Vector3(23.5, 0, 22.0), Color(1.0, 0.62, 0.20), 1.02, 13.5, false, flicker_lights)  # Warehouse (amber)
	_add_ceiling_lamp(root, Vector3(-24.5, 0, 9.5), Color(0.56, 0.90, 0.98), 1.12, 12.8, true, flicker_lights)   # Operating Theater (cold surgical)
	_add_ceiling_lamp(root, Vector3(-25.0, 0, -7.0), Color(0.48, 0.82, 0.92), 0.92, 13.0, true, flicker_lights)  # Autopsy Morgue (cold cyan)
	_add_ceiling_lamp(root, Vector3(-22.0, 0, -22.0), Color(0.52, 0.88, 0.86), 0.95, 13.5, false, flicker_lights)# Cryo-Archive (cryo cyan)
	_add_ceiling_lamp(root, Vector3(0.0, 0, -22.5), Color(1.0, 0.18, 0.14), 1.65, 15.5, true, flicker_lights)    # Evacuation Airlock (crimson beacon)
	_add_ceiling_lamp(root, Vector3(22.5, 0, -22.0), Color(1.0, 0.56, 0.18), 1.15, 13.5, true, flicker_lights)   # Power Substation (sodium arc)
	_add_ceiling_lamp(root, Vector3(25.0, 0, -8.0), Color(0.95, 0.76, 0.42), 0.95, 12.5, false, flicker_lights)  # Security Command (amber)
	_add_ceiling_lamp(root, Vector3(25.0, 0, 8.0), Color(0.58, 0.86, 0.86), 0.88, 12.5, true, flicker_lights)    # Decontamination (damp fluorescent)
	_add_ceiling_lamp(root, Vector3(-5.0, 0, 0.0), Color(0.42, 0.96, 0.62), 1.02, 11.5, false, flicker_lights)   # Bio-Lab (bio-green)
	_add_ceiling_lamp(root, Vector3(5.0, 0, 0.0), Color(0.96, 0.72, 0.36), 0.95, 11.5, false, flicker_lights)    # Observation (amber)
	# Ring Corridor Lamps (warm sodium corridor pools)
	_add_ceiling_lamp(root, Vector3(-14.0, 0, 0.0), Color(0.94, 0.62, 0.24), 0.82, 13.5, false, flicker_lights)
	_add_ceiling_lamp(root, Vector3(14.0, 0, 0.0), Color(0.94, 0.62, 0.24), 0.82, 13.5, false, flicker_lights)
	_add_ceiling_lamp(root, Vector3(0.0, 0, -12.5), Color(0.94, 0.62, 0.24), 0.82, 13.5, false, flicker_lights)
	_add_ceiling_lamp(root, Vector3(0.0, 0, 12.5), Color(0.94, 0.62, 0.24), 0.82, 13.5, false, flicker_lights)

	# --- 16 SEARCHABLE DRAWER CABINETS ACROSS ALL WINGS ---
	var cab_specs := [
		["cab_ward", Vector3(-31.2, 0, 18.2), -PI * 0.5],
		["cab_canteen", Vector3(-5.0, 0, 27.2), PI],
		["cab_triage", Vector3(13.2, 0, 18.5), PI * 0.5],
		["cab_ware_1", Vector3(31.2, 0, 26.5), PI * 0.5],
		["cab_ware_2", Vector3(15.2, 0, 27.2), PI],
		["cab_surgery", Vector3(-31.2, 0, 5.2), -PI * 0.5],
		["cab_morgue", Vector3(-31.2, 0, -14.2), -PI * 0.5],
		["cab_cryo", Vector3(-31.2, 0, -26.5), -PI * 0.5],
		["cab_airlock", Vector3(10.8, 0, -27.2), PI],
		["cab_gen", Vector3(31.2, 0, -17.8), PI * 0.5],
		["cab_sec_1", Vector3(31.2, 0, -14.8), PI * 0.5],
		["cab_sec_2", Vector3(19.2, 0, -15.2), 0.0],
		["cab_decon", Vector3(31.2, 0, 14.5), PI * 0.5],
		["cab_biolab", Vector3(-9.2, 0, -8.2), 0.0],
		["cab_obs", Vector3(9.2, 0, 8.2), PI],
		["cab_ring_e", Vector3(17.2, 0, 12.5), PI * 0.5],
	]

	var loot_pool: Array[String] = [
		"crowbar",
		"cutters",
		"fuse",
		"code_note",
		"screwdriver",
		"screwdriver",
		"flare",
		"flare",
		"medkit",
		"medkit",
		"syringe",
		"syringe",
		"bottle",
		"bottle",
		"battery",
		"battery"
	]
	for i in range(loot_pool.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := loot_pool[i]
		loot_pool[i] = loot_pool[j]
		loot_pool[j] = tmp

	var cabinets: Dictionary = {}
	for idx in range(cab_specs.size()):
		var cs_entry: Array = cab_specs[idx]
		var cid: String = cs_entry[0]
		var cpos: Vector3 = cs_entry[1]
		var cyaw: float = cs_entry[2]

		var cinst := AssetLibrary.instantiate_model("cabinet_search")
		cinst.position = cpos
		cinst.rotation.y = cyaw
		root.add_child(cinst)

		var csb := StaticBody3D.new()
		csb.position = cpos + Vector3(0, 0.48, 0)
		csb.rotation.y = cyaw
		csb.set_meta("interact_type", "cabinet")
		csb.set_meta("cabinet_id", cid)
		var cshape := CollisionShape3D.new()
		var cbox := BoxShape3D.new()
		cbox.size = Vector3(0.90, 0.96, 0.68)
		cshape.shape = cbox
		csb.add_child(cshape)
		root.add_child(csb)

		var fwd := Vector3(0, 0, -1).rotated(Vector3.UP, cyaw)
		cabinets[cid] = {
			"id": cid,
			"node": cinst,
			"drawer_pivot": AssetLibrary.find_child_by_prefix(cinst, "DrawerPivot") as Node3D,
			"is_open": false,
			"loot_item": loot_pool[idx],
			"item_spawn_pos": cpos + Vector3(0, 0.96, 0) + fwd * 0.12
		}

	# Guaranteed starter tactical items in Ward B-04 & Surgery so players test mechanics immediately
	var initial_spawns: Array[Dictionary] = [
		{"item_id": "bottle", "pos": Vector3(-22.5, 0.05, 19.5)},
		{"item_id": "screwdriver", "pos": Vector3(-20.2, 0.05, 22.2)},
		{"item_id": "flare", "pos": Vector3(-26.5, 0.05, 19.8)},
		{"item_id": "medkit", "pos": Vector3(-21.2, 0.05, 5.2)},
	]

	# --- 33-NODE DOORWAY-ALIGNED WAYPOINT GRAPH COVERING ALL 14 ROOMS & RING GALLERIES ---
	var nav_nodes: Array[Vector3] = [
		Vector3(-24.72, 0, 21.5),  # 0: Ward B-04
		Vector3(-24.72, 0, 9.0),   # 1: Operating Theater
		Vector3(-24.72, 0, -7.0),  # 2: Autopsy Morgue
		Vector3(-15.6, 0, 9.0),    # 3: West Ring South
		Vector3(-15.6, 0, 0.0),    # 4: West Ring Center
		Vector3(-15.6, 0, -7.0),   # 5: West Ring North
		Vector3(-15.6, 0, -14.2),  # 6: NW Ring Outer
		Vector3(-15.0, 0, -22.0),  # 7: Cryo-Archive
		Vector3(-6.0, 0, -22.0),   # 8: Evacuation Airlock West
		Vector3(6.0, 0, -22.0),    # 9: Evacuation Airlock East
		Vector3(15.0, 0, -22.0),   # 10: Power Substation Entry
		Vector3(22.5, 0, -21.5),   # 11: Power Substation Deep
		Vector3(-6.0, 0, -14.2),   # 12: North Ring West
		Vector3(-5.0, 0, -11.5),   # 13: Bio-Lab North Approach
		Vector3(6.0, 0, -14.2),    # 14: North Ring East
		Vector3(15.6, 0, -14.2),   # 15: NE Ring Outer
		Vector3(15.6, 0, -8.0),    # 16: East Ring North
		Vector3(15.6, 0, 0.0),     # 17: East Ring Center
		Vector3(15.6, 0, 8.0),     # 18: East Ring South
		Vector3(25.0, 0, -8.0),    # 19: Security Command
		Vector3(25.0, 0, 8.0),     # 20: Decontamination Showers
		Vector3(23.0, 0, 16.0),    # 21: Warehouse North Door
		Vector3(23.0, 0, 22.0),    # 22: Hazmat Warehouse
		Vector3(5.0, 0, 22.0),     # 23: South Triage
		Vector3(-11.0, 0, 22.0),   # 24: Staff Canteen
		Vector3(-11.0, 0, 14.2),   # 25: South Ring West
		Vector3(5.0, 0, 14.2),     # 26: South Ring East
		Vector3(-5.0, 0, 0.0),     # 27: Bio-Containment Lab
		Vector3(5.0, 0, 0.0),      # 28: Observation Archive
		Vector3(11.8, 0, 10.5),    # 29: SE Ring Inner
		Vector3(-11.8, 0, 10.5),   # 30: SW Ring Inner
		Vector3(11.8, 0, -10.5),   # 31: NE Ring Inner
		Vector3(-11.8, 0, -10.5),  # 32: NW Ring Inner
	]
	var nav_edges := [
		[0, 1], [1, 2],
		[1, 3], [3, 4], [4, 5], [2, 5],
		[5, 6], [6, 7],
		[7, 8], [8, 9], [9, 10], [10, 11],
		[5, 32], [32, 12], [12, 8],
		[12, 13], [13, 27],
		[12, 14], [14, 9],
		[14, 31], [31, 16], [15, 10], [16, 15],
		[16, 17], [17, 18],
		[16, 19], [19, 20], [18, 20],
		[20, 21], [21, 22],
		[22, 23], [23, 24],
		[24, 25], [23, 26], [25, 26],
		[25, 30], [30, 3],
		[26, 29], [29, 18],
		[4, 27], [27, 28], [28, 17], [28, 26],
	]
	var nav_adj: Array = []
	for _i in range(nav_nodes.size()):
		nav_adj.append([])
	for e in nav_edges:
		nav_adj[e[0]].append(e[1])
		nav_adj[e[1]].append(e[0])

	return {
		"root": root,
		"player_spawns": [
			Vector3(-26.5, 0.08, 22.5),
			Vector3(-23.5, 0.08, 22.5),
			Vector3(-26.5, 0.08, 20.0),
			Vector3(-23.5, 0.08, 20.0),
		],
		"monster_spawn": Vector3(22.5, 0.0, -21.5),
		"exit_gate": exit_gate,
		"generator_node": gen_node,
		"safe_node": safe_node,
		"safe_code": safe_code,
		"safe_key_pos": Vector3(30.92, 1.12, -8.0),
		"holding_cage": holding_cage_info,
		"doors": doors,
		"vents": vents,
		"pa_stations": pa_stations,
		"glass_hazards": glass_hazards,
		"wheelchair_hazards": wheelchair_hazards,
		"wall_segments": wall_segs,
		"lockers": lockers,
		"hide_desks": hide_desks,
		"cabinets": cabinets,
		"initial_spawns": initial_spawns,
		"flicker_lights": flicker_lights,
		"nav_nodes": nav_nodes,
		"nav_adj": nav_adj
	}
