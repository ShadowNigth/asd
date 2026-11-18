class_name Dust2Map
extends Node3D
## Loads Dust II (dust2.glb + dust2-physics.glb + dust2-cables.glb + dust2-sky.hdr),
## generates StaticBody3D colliders from the physics proxy, and exposes spawns,
## buy zones, bombsites A & B, and callout names.

var buy_zones: Array = []
var bombsites: Array = []
var callouts: Array = []
var spawns_t: Array = []
var spawns_ct: Array = []
var spawn_angles_t: Array = []
var spawn_angles_ct: Array = []

var _world_env: WorldEnvironment
var _sun: DirectionalLight3D

func _ready() -> void:
	_load_metadata()
	_setup_sky_and_sun()
	_load_map_geometry()

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	var txt := f.get_as_text()
	f.close()
	return JSON.parse_string(txt)

func _load_metadata() -> void:
	var bz = _read_json("res://assets/data/dust2-buy-zones.json")
	if bz is Dictionary:
		buy_zones = bz.get("zones", [])
		bombsites = bz.get("sites", [])

	var pl = _read_json("res://assets/data/dust2-places.json")
	if pl is Dictionary:
		callouts = pl.get("locations", [])

	var sp = _read_json("res://assets/data/dust2-spawns.json")
	if sp is Dictionary:
		var s: Dictionary = sp.get("spawns", {})
		spawns_t = s.get("t", [])
		spawns_ct = s.get("ct", [])
		var sa: Dictionary = sp.get("spawnAngles", {})
		spawn_angles_t = sa.get("t", [])
		spawn_angles_ct = sa.get("ct", [])

func _setup_sky_and_sun() -> void:
	_world_env = WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var hdr_path := "res://assets/models/maps/dust2-sky.hdr"
	if ResourceLoader.exists(hdr_path):
		var pan := PanoramaSkyMaterial.new()
		pan.panorama = load(hdr_path)
		sky.sky_material = pan
	else:
		var proc := ProceduralSkyMaterial.new()
		proc.sky_top_color = Color(0.36, 0.56, 0.82)
		proc.sky_horizon_color = Color(0.84, 0.82, 0.74)
		proc.ground_bottom_color = Color(0.35, 0.30, 0.24)
		sky.sky_material = proc
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.75
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.glow_enabled = true
	env.glow_intensity = 0.3
	_world_env.environment = env
	add_child(_world_env)

	# Sun matching Dust II Source pitch=50, yaw=43
	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(1.0, 0.95, 0.86)
	_sun.light_energy = 1.65
	_sun.shadow_enabled = true
	_sun.directional_shadow_max_distance = 160.0
	_sun.rotation_degrees = Vector3(-50.0, 43.0, 0.0)
	add_child(_sun)

func _load_map_geometry() -> void:
	var visual_path := "res://assets/models/maps/dust2.glb"
	var phys_path := "res://assets/models/maps/dust2-physics.glb"
	var cables_path := "res://assets/models/maps/dust2-cables.glb"

	var loaded_visual := false
	var map_root := ModelLoader.instantiate_model(visual_path)
	if map_root != null:
		add_child(map_root)
		loaded_visual = true

	var cables_root := ModelLoader.instantiate_model(cables_path)
	if cables_root != null:
		add_child(cables_root)

	var loaded_phys := false
	var phys_root := ModelLoader.instantiate_model(phys_path)
	if phys_root != null:
		phys_root.visible = false
		add_child(phys_root)
		_create_colliders_from_meshes(phys_root, true)
		loaded_phys = true

	if not loaded_visual and not loaded_phys:
		_build_fallback_blockout()

func _create_colliders_from_meshes(node: Node, include_player_clips: bool) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		if mi.mesh != null:
			var nname := mi.name.to_lower()
			if not ("grenadeclip" in nname or "sky" in nname):
				var sb := StaticBody3D.new()
				sb.collision_layer = 1
				sb.collision_mask = 0
				var cs := CollisionShape3D.new()
				cs.shape = mi.mesh.create_trimesh_shape()
				sb.add_child(cs)
				mi.add_child(sb)
	for c in node.get_children():
		_create_colliders_from_meshes(c, include_player_clips)

func _build_fallback_blockout() -> void:
	# Playable Dust II-proportioned sandbox arena when GLBs aren't synced yet
	var ground := StaticBody3D.new()
	var gcs := CollisionShape3D.new()
	var gbox := BoxShape3D.new()
	gbox.size = Vector3(140.0, 1.0, 140.0)
	gcs.shape = gbox
	ground.position = Vector3(-5.0, -3.5, -25.0)
	ground.add_child(gcs)
	var gm := MeshInstance3D.new()
	var gmesh := BoxMesh.new()
	gmesh.size = gbox.size
	gm.mesh = gmesh
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.76, 0.67, 0.50)
	gm.material_override = gmat
	ground.add_child(gm)
	add_child(ground)

	# Cover crates around Site A, Site B, Mid, and Spawns
	var blocks := [
		[Vector3(27.0, -1.5, -63.0), Vector3(2.4, 2.2, 2.4)],
		[Vector3(-39.0, -1.5, -67.0), Vector3(2.6, 2.2, 2.6)],
		[Vector3(-12.0, -1.2, -48.0), Vector3(1.8, 3.6, 5.0)],
		[Vector3(8.0, -1.2, -25.0), Vector3(8.0, 3.6, 2.5)],
		[Vector3(-24.0, -1.2, -15.0), Vector3(6.0, 3.6, 3.0)],
	]
	for b in blocks:
		var sb := StaticBody3D.new()
		sb.position = b[0]
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = b[1]
		cs.shape = bs
		sb.add_child(cs)
		var mi := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = b[1]
		mi.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.45, 0.32)
		mi.material_override = mat
		sb.add_child(mi)
		add_child(sb)

func get_spawn(team: String, index: int) -> Dictionary:
	var arr := spawns_ct if team == "ct" else spawns_t
	var ang := spawn_angles_ct if team == "ct" else spawn_angles_t
	if arr.is_empty():
		var fallback := Vector3(6.0, -2.5, -58.0) if team == "ct" else Vector3(-20.0, 3.8, 20.0)
		return {"pos": fallback, "yaw": 0.0 if team == "ct" else 180.0}
	var idx := index % arr.size()
	var p: Array = arr[idx]
	var yaw := float(ang[idx]) if idx < ang.size() else 0.0
	return {
		"pos": Vector3(float(p[0]), float(p[1]) + 0.08, float(p[2])),
		"yaw": rad_to_deg(yaw) if absf(yaw) <= TAU else yaw,
	}

func _point_in_box(pos: Vector3, box: Dictionary) -> bool:
	var mn: Array = box.get("min", [0, 0, 0])
	var mx: Array = box.get("max", [0, 0, 0])
	return pos.x >= float(mn[0]) and pos.x <= float(mx[0]) and \
		   pos.y >= float(mn[1]) - 0.5 and pos.y <= float(mx[1]) + 1.5 and \
		   pos.z >= float(mn[2]) and pos.z <= float(mx[2])

func is_in_buy_zone(pos: Vector3, team: String) -> bool:
	for z in buy_zones:
		if str(z.get("team", "")) == team and _point_in_box(pos, z):
			return true
	return false

func get_bombsite_at(pos: Vector3) -> int:
	for s in bombsites:
		var site_id := int(s.get("site", -1))
		for h in s.get("hulls", []):
			if _point_in_box(pos, h):
				return site_id
	return -1

func get_callout_at(pos: Vector3) -> String:
	for loc in callouts:
		for h in loc.get("hulls", []):
			if _point_in_box(pos, h):
				return str(loc.get("name", ""))
	return ""
