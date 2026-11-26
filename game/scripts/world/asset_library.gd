class_name AssetLibrary
extends RefCounted

static var _models: Dictionary = {}
static var _icons: Dictionary = {}
static var _materials: Dictionary = {}


static func get_model_scene(model_name: String) -> PackedScene:
	if _models.has(model_name):
		return _models[model_name]
	var path := "res://assets/models/%s.glb" % model_name
	var scn := load(path) as PackedScene
	if scn != null:
		_models[model_name] = scn
	return scn


static func instantiate_model(model_name: String) -> Node3D:
	var scn := get_model_scene(model_name)
	if scn == null:
		return Node3D.new()
	var inst := scn.instantiate() as Node3D
	return inst if inst != null else Node3D.new()


static func get_icon(icon_name: String) -> Texture2D:
	if _icons.has(icon_name):
		return _icons[icon_name]
	var path := "res://assets/icons/%s.png" % icon_name
	var tex := load(path) as Texture2D
	if tex != null:
		_icons[icon_name] = tex
	return tex


static func get_item_icon(item_id: String) -> Texture2D:
	return get_icon("item_" + item_id)


static func get_world_material(mat_key: String) -> StandardMaterial3D:
	if _materials.has(mat_key):
		return _materials[mat_key]

	var mat := StandardMaterial3D.new()
	mat.uv1_triplanar = true
	mat.uv1_world_triplanar = true
	mat.uv1_triplanar_sharpness = 4.0

	match mat_key:
		"wall":
			mat.albedo_texture = load("res://assets/textures/concrete_wall.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 1.15
			mat.roughness = 0.88
			mat.uv1_scale = Vector3(0.36, 0.36, 0.36)
		"wall_lower_teal":
			# Soviet НИИ-07 institutional teal-green dado oil paint (#2E4743) over concrete texture
			mat.albedo_texture = load("res://assets/textures/concrete_wall.png") as Texture2D
			mat.albedo_color = Color(0.46, 0.76, 0.70)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 0.72
			mat.roughness = 0.62
			mat.metallic = 0.04
			mat.uv1_scale = Vector3(0.38, 0.38, 0.38)
		"wall_upper_cream":
			# Aged dirty Soviet plaster cream (#B9B09A) over concrete texture
			mat.albedo_texture = load("res://assets/textures/concrete_wall.png") as Texture2D
			mat.albedo_color = Color(1.56, 1.48, 1.26)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 0.80
			mat.roughness = 0.90
			mat.uv1_scale = Vector3(0.36, 0.36, 0.36)
		"wall_surgical":
			# Cold clinical blue-grey hospital ceramic tile for Surgery, Morgue & Cryo
			mat.albedo_texture = load("res://assets/textures/tile_floor.png") as Texture2D
			mat.albedo_color = Color(0.84, 1.12, 1.20)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/tile_floor_n.png") as Texture2D
			mat.normal_scale = 0.95
			mat.roughness = 0.46
			mat.metallic = 0.05
			mat.uv1_scale = Vector3(0.56, 0.56, 0.56)
		"wall_industrial":
			# Dark bunker grime concrete for Substation, Warehouse, Airlock & Cornices
			mat.albedo_texture = load("res://assets/textures/concrete_wall.png") as Texture2D
			mat.albedo_color = Color(0.52, 0.54, 0.50)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 0.85
			mat.roughness = 0.92
			mat.uv1_scale = Vector3(0.34, 0.34, 0.34)
		"dado_strip":
			# Dark oxidized iron / rubber molding (#171D1B)
			mat.albedo_texture = load("res://assets/textures/rusted_metal.png") as Texture2D
			mat.albedo_color = Color(0.22, 0.27, 0.25)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/rusted_metal_n.png") as Texture2D
			mat.normal_scale = 0.85
			mat.roughness = 0.54
			mat.metallic = 0.42
			mat.uv1_scale = Vector3(0.65, 0.65, 0.65)
		"hazard":
			mat.albedo_texture = load("res://assets/textures/hazard_stripes.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 0.45
			mat.roughness = 0.72
			mat.metallic = 0.08
			mat.uv1_scale = Vector3(0.68, 0.68, 0.68)
		"blood_stain":
			# Organic feathered dried coagulated crimson floor splatter decal
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_texture = _make_blood_decal_texture()
			mat.albedo_color = Color(0.88, 0.88, 0.88, 0.92)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.28
			mat.metallic = 0.06
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		"glass_bio":
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_color = Color(0.45, 0.82, 0.72, 0.24)
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.roughness = 0.12
			mat.metallic = 0.14
			mat.emission_enabled = true
			mat.emission = Color(0.16, 0.54, 0.36)
			mat.emission_energy_multiplier = 0.32
		"emissive_amber":
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_color = Color(0.89, 0.635, 0.231) # SODIUM #E3A23B
			mat.emission_enabled = true
			mat.emission = Color(0.89, 0.635, 0.231)
			mat.emission_energy_multiplier = 2.2
		"emissive_red":
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_color = Color(0.80, 0.227, 0.180) # SIGNAL #CC3A2E
			mat.emission_enabled = true
			mat.emission = Color(0.80, 0.227, 0.180)
			mat.emission_energy_multiplier = 2.6
		"emissive_cyan":
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_color = Color(0.498, 0.722, 0.784) # COLD #7FB8C8
			mat.emission_enabled = true
			mat.emission = Color(0.498, 0.722, 0.784)
			mat.emission_energy_multiplier = 2.0
		"emissive_bio":
			mat.uv1_triplanar = false
			mat.uv1_world_triplanar = false
			mat.albedo_color = Color(0.32, 0.78, 0.50)
			mat.emission_enabled = true
			mat.emission = Color(0.24, 0.76, 0.45)
			mat.emission_energy_multiplier = 1.18
		"floor":
			mat.albedo_texture = load("res://assets/textures/tile_floor.png") as Texture2D
			mat.albedo_color = Color(1.22, 1.22, 1.18)
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/tile_floor_n.png") as Texture2D
			mat.normal_scale = 1.12
			mat.roughness = 0.56
			mat.metallic = 0.06
			mat.uv1_scale = Vector3(0.42, 0.42, 0.42)
		"ceiling":
			mat.albedo_texture = load("res://assets/textures/ceiling_concrete.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/ceiling_concrete_n.png") as Texture2D
			mat.roughness = 0.92
			mat.uv1_scale = Vector3(0.32, 0.32, 0.32)
		"metal":
			mat.albedo_texture = load("res://assets/textures/rusted_metal.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/rusted_metal_n.png") as Texture2D
			mat.roughness = 0.56
			mat.metallic = 0.72
			mat.uv1_scale = Vector3(0.55, 0.55, 0.55)
		"wood":
			mat.albedo_texture = load("res://assets/textures/dirty_wood.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/dirty_wood_n.png") as Texture2D
			mat.roughness = 0.84
			mat.uv1_scale = Vector3(0.5, 0.5, 0.5)
		_:
			mat.albedo_texture = load("res://assets/textures/concrete_wall.png") as Texture2D
			mat.normal_enabled = true
			mat.normal_texture = load("res://assets/textures/concrete_wall_n.png") as Texture2D
			mat.normal_scale = 1.1
			mat.roughness = 0.88
			mat.uv1_scale = Vector3(0.36, 0.36, 0.36)

	if mat.albedo_texture != null or mat.normal_texture != null:
		mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC

	_materials[mat_key] = mat
	return mat


static func _make_blood_decal_texture() -> ImageTexture:
	var sz := 96
	var img := Image.create(sz, sz, false, Image.FORMAT_RGBA8)
	for y in range(sz):
		var ny := (float(y) / float(sz - 1)) * 2.0 - 1.0
		for x in range(sz):
			var nx := (float(x) / float(sz - 1)) * 2.0 - 1.0
			var ang := atan2(ny, nx)
			var r := sqrt(nx * nx + ny * ny)
			var wob := 0.16 * sin(ang * 3.0 + 0.7) + 0.11 * cos(ang * 5.0 - 1.2) + 0.07 * sin(ang * 9.0)
			var smear := 0.12 * sin(nx * 7.5 + ny * 4.2) * cos(ny * 6.0 - nx * 3.0)
			var dist := r + wob + smear
			var alpha := clampf((0.84 - dist) / 0.24, 0.0, 1.0)
			alpha = alpha * alpha * (3.0 - 2.0 * alpha)
			# Small outlying droplets
			var drop_a := clampf(1.0 - Vector2(nx - 0.56, ny + 0.42).length() / 0.14, 0.0, 1.0)
			var drop_b := clampf(1.0 - Vector2(nx + 0.48, ny - 0.46).length() / 0.11, 0.0, 1.0)
			alpha = clampf(maxf(alpha, maxf(drop_a, drop_b) * 0.85), 0.0, 1.0)
			var core := clampf(1.0 - r * 0.72, 0.0, 1.0)
			var col := Color(0.24 + 0.14 * core, 0.025 + 0.015 * core, 0.025, alpha * 0.90)
			img.set_pixel(x, y, col)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func find_child_by_prefix(root: Node, prefix: String) -> Node:
	if root == null:
		return null
	if root.name.begins_with(prefix):
		return root
	for ch in root.get_children():
		var res := find_child_by_prefix(ch, prefix)
		if res != null:
			return res
	return null


static func find_animation_player(root: Node) -> AnimationPlayer:
	if root is AnimationPlayer:
		return root as AnimationPlayer
	for ch in root.get_children():
		var res := find_animation_player(ch)
		if res != null:
			return res
	return null
