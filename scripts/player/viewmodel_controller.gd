class_name ViewmodelController
extends Node3D
## CS2GO First-Person Viewmodel Rig:
## Loads view-hands.glb + gloves + weapon viewmodel .glb + animation clips
## (idle, draw, reload, shoot1, lookat01 inspect, etc.) and binds Source bones
## via the exact 0.0254 Source->glTF basis matrix and 'wpn' attachment bone.

const WEAPON_ANIMATION_RATE := 0.9
const CROSSFADE_SEC := 0.08

# Source inches (X forward, Y left, Z up) -> Godot meters (X right, Y up, -Z forward)
const SOURCE_BASIS := Transform3D(
	Basis(
		Vector3(0.0, 0.0, -0.0254),
		Vector3(-0.0254, 0.0, 0.0),
		Vector3(0.0, 0.0254, 0.0)
	),
	Vector3.ZERO
)

var _hands_root: Node3D = null
var _hands_skel: Skeleton3D = null
var _weapon_root: Node3D = null
var _weapon_skel: Skeleton3D = null
var _source_root: Node3D = null
var _source_skel: Skeleton3D = null
var _source_anim: AnimationPlayer = null
var _fallback_mesh: MeshInstance3D = null

var _arms_bindings: Array[Dictionary] = [] # {dst: int, src: int}
var _weapon_bindings: Array[Dictionary] = []
var _wpn_src_bone: int = -1
var _muzzle_src_bone: int = -1

var _clip_cache: Dictionary = {} # weapon_name -> {clips, source_scene, model_scene}
var _current_weapon_name: String = ""
var _current_motion: String = "idle"
var _motion_time: float = 0.0
var _motion_duration: float = 1.0
var _motion_loop: bool = true

var _bob_phase: float = 0.0
var _sway_offset: Vector2 = Vector2.ZERO
var _last_muzzle_world: Vector3 = Vector3.ZERO
var _suppressed: bool = true

func _ready() -> void:
	position = Vector3(0.05, -0.025, -0.025)
	_ensure_hands_loaded()
	_build_fallback_mesh()

func _build_fallback_mesh() -> void:
	_fallback_mesh = MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.06, 0.08, 0.42)
	_fallback_mesh.mesh = bm
	_fallback_mesh.position = Vector3(0.16, -0.18, -0.35)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.2, 0.23)
	mat.metallic = 0.6
	mat.roughness = 0.35
	_fallback_mesh.material_override = mat
	_fallback_mesh.visible = false
	add_child(_fallback_mesh)

func _find_first_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node as Skeleton3D
	for c in node.get_children():
		var found := _find_first_skeleton(c)
		if found != null:
			return found
	return null

func _find_first_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var found := _find_first_anim_player(c)
		if found != null:
			return found
	return null

func _disable_frustum_culling(node: Node) -> void:
	if node is GeometryInstance3D:
		(node as GeometryInstance3D).extra_cull_margin = 4.0
	for c in node.get_children():
		_disable_frustum_culling(c)

func _ensure_hands_loaded() -> void:
	if _hands_root != null:
		return
	var path := "res://assets/models/agents/view-hands.glb"
	var inst := ModelLoader.instantiate_model(path)
	if inst == null:
		return
	_hands_root = inst
	_disable_frustum_culling(_hands_root)
	add_child(_hands_root)
	_hands_skel = _find_first_skeleton(_hands_root)

func load_weapon(weapon_id: int, is_c4: bool = false) -> void:
	var wname := "c4" if is_c4 else WeaponDB.get_viewmodel_name(weapon_id)
	if wname == _current_weapon_name and _weapon_root != null:
		return
	_current_weapon_name = wname

	if _weapon_root != null:
		_weapon_root.queue_free()
		_weapon_root = null
		_weapon_skel = null
	if _source_root != null:
		_source_root.queue_free()
		_source_root = null
		_source_skel = null
		_source_anim = null
	_arms_bindings.clear()
	_weapon_bindings.clear()
	_wpn_src_bone = -1
	_muzzle_src_bone = -1

	var is_knife := (not is_c4) and WeaponDB.is_knife(weapon_id)
	var model_path := "res://assets/models/c4.glb" if is_c4 else (
		"res://assets/models/bayonet.glb" if is_knife else ("res://assets/models/viewmodels/%s.glb" % wname)
	)

	if not ModelLoader.model_exists(model_path):
		_fallback_mesh.visible = true
		if _hands_root:
			_hands_root.visible = false
		return

	_ensure_hands_loaded()
	if _hands_root:
		_hands_root.visible = true
	_fallback_mesh.visible = false

	_weapon_root = ModelLoader.instantiate_model(model_path)
	if _weapon_root != null:
		_disable_frustum_culling(_weapon_root)
		add_child(_weapon_root)
		_weapon_skel = _find_first_skeleton(_weapon_root)

	# Load source rig and merge all motion clips (supports firearms, bayonet, and c4)
	var clip_entries: Array[Array] = [] # [motion_key, clip_glb_path]
	if is_c4:
		clip_entries = [
			["idle", "res://assets/models/animations/c4/idle.glb"],
			["draw", "res://assets/models/animations/c4/draw.glb"],
			["plant", "res://assets/models/animations/c4/plant.glb"],
		]
	elif is_knife:
		clip_entries = [
			["idle", "res://assets/models/animations/bayonet/idle1.glb"],
			["draw", "res://assets/models/animations/bayonet/draw.glb"],
			["shoot1", "res://assets/models/animations/bayonet/light_miss1.glb"],
			["shoot2", "res://assets/models/animations/bayonet/heavy_miss1.glb"],
			["lookat01", "res://assets/models/animations/bayonet/lookat01.glb"],
		]
	else:
		var clip_dir := "res://assets/models/viewmodels/%s" % wname
		for m in ["idle", "draw", "reload", "shoot1", "lookat01", "shoot2", "shoot_empty", "reload_empty", "prepare", "silencer_attach", "silencer_detach"]:
			clip_entries.append([m, "%s/%s.glb" % [clip_dir, m]])

	var lib := AnimationLibrary.new()
	for entry in clip_entries:
		var m_key: String = entry[0]
		var clip_path: String = entry[1]
		var inst := ModelLoader.instantiate_model(clip_path)
		if inst == null:
			continue
		if _source_root == null:
			_source_root = inst
			_source_root.visible = false
			add_child(_source_root)
			_source_skel = _find_first_skeleton(_source_root)
			_source_anim = _find_first_anim_player(_source_root)
			if _source_anim == null:
				_source_anim = AnimationPlayer.new()
				_source_root.add_child(_source_anim)
			var ap := _find_first_anim_player(inst)
			if ap != null:
				var anim_names := ap.get_animation_list()
				if anim_names.size() > 0:
					var anim := ap.get_animation(anim_names[0]).duplicate()
					lib.add_animation(m_key, anim)
		else:
			var ap2 := _find_first_anim_player(inst)
			if ap2 != null:
				var anim_names2 := ap2.get_animation_list()
				if anim_names2.size() > 0:
					var anim2 := ap2.get_animation(anim_names2[0]).duplicate()
					lib.add_animation(m_key, anim2)
			inst.queue_free()

	if _source_anim != null:
		if _source_anim.has_animation_library("cs"):
			_source_anim.remove_animation_library("cs")
		_source_anim.add_animation_library("cs", lib)

	_build_bone_bindings()
	play_motion("draw", 1.0, false)

func _build_bone_bindings() -> void:
	_arms_bindings.clear()
	_weapon_bindings.clear()
	if _source_skel == null:
		return

	_wpn_src_bone = _source_skel.find_bone("wpn")
	_muzzle_src_bone = _source_skel.find_bone("muzzle")
	if _muzzle_src_bone < 0:
		_muzzle_src_bone = _source_skel.find_bone("muzzle_l")

	if _hands_skel != null:
		for i in range(_hands_skel.get_bone_count()):
			var bname := _hands_skel.get_bone_name(i)
			if bname.begins_with("arm_upper_") or bname.begins_with("arm_lower_") or bname.begins_with("hand_") or bname.begins_with("finger_"):
				var src_idx := _source_skel.find_bone(bname)
				if src_idx >= 0:
					_arms_bindings.append({"dst": i, "src": src_idx})

	if _weapon_skel != null:
		for i in range(_weapon_skel.get_bone_count()):
			var bname := _weapon_skel.get_bone_name(i)
			var src_idx := _source_skel.find_bone(bname)
			if src_idx >= 0:
				_weapon_bindings.append({"dst": i, "src": src_idx})

func has_motion(motion_name: String) -> bool:
	return _source_anim != null and _source_anim.has_animation("cs/" + motion_name)

func get_motion_duration(motion_name: String) -> float:
	if not has_motion(motion_name):
		return 0.0
	var anim := _source_anim.get_animation("cs/" + motion_name)
	return anim.length / WEAPON_ANIMATION_RATE

func play_motion(motion_name: String, speed_scale: float = 1.0, loop: bool = false) -> void:
	_current_motion = motion_name
	_motion_time = 0.0
	_motion_loop = loop
	if has_motion(motion_name):
		var anim := _source_anim.get_animation("cs/" + motion_name)
		_motion_duration = maxf(0.05, anim.length / WEAPON_ANIMATION_RATE)
		_source_anim.play("cs/" + motion_name, CROSSFADE_SEC, WEAPON_ANIMATION_RATE * speed_scale)
	else:
		_motion_duration = 0.35

func set_suppressed(sup: bool) -> void:
	_suppressed = sup

func add_sway(look_delta: Vector2) -> void:
	_sway_offset.x = clampf(_sway_offset.x - look_delta.x * 0.00018, -0.025, 0.025)
	_sway_offset.y = clampf(_sway_offset.y + look_delta.y * 0.00018, -0.025, 0.025)

func update_viewmodel(dt: float, move_speed: float, grounded: bool) -> void:
	_motion_time += dt
	if not _motion_loop and _motion_time >= _motion_duration and _current_motion != "idle":
		play_motion("idle", 1.0, true)

	# Bob & sway
	if grounded and move_speed > 0.3:
		_bob_phase += dt * minf(move_speed * 2.2, 14.0)
	else:
		_bob_phase += dt * 1.5
	var bob_x := sin(_bob_phase) * 0.006 * clampf(move_speed / 5.0, 0.05, 1.0)
	var bob_y := absf(cos(_bob_phase)) * -0.008 * clampf(move_speed / 5.0, 0.05, 1.0)
	_sway_offset = _sway_offset.lerp(Vector2.ZERO, 1.0 - exp(-12.0 * dt))
	position = Vector3(0.05 + _sway_offset.x + bob_x, -0.025 + _sway_offset.y + bob_y, -0.025)

	# Fallback procedural recoil/inspect motion if GLB not synced yet
	if _fallback_mesh.visible:
		var kick_z := 0.0
		var inspect_rot := Vector3.ZERO
		if _current_motion == "shoot1" or _current_motion == "shoot2":
			var k := 1.0 - clampf(_motion_time / 0.14, 0.0, 1.0)
			kick_z = 0.045 * k
		elif _current_motion == "lookat01":
			var p := clampf(_motion_time / maxf(_motion_duration, 1.0), 0.0, 1.0)
			inspect_rot = Vector3(0.2 * sin(p * PI), 0.85 * sin(p * PI), -0.45 * sin(p * PI))
		elif _current_motion == "reload":
			var p2 := clampf(_motion_time / maxf(_motion_duration, 1.0), 0.0, 1.0)
			inspect_rot = Vector3(-0.45 * sin(p2 * PI), 0.0, 0.25 * sin(p2 * PI))
		_fallback_mesh.position = Vector3(0.16, -0.18, -0.35 + kick_z)
		_fallback_mesh.rotation = inspect_rot
		return

	_apply_source_retargeting()

func _apply_source_retargeting() -> void:
	if _source_skel == null:
		return

	if _hands_skel != null:
		for b in _arms_bindings:
			var sp := _source_skel.get_bone_global_pose(b["src"])
			_hands_skel.set_bone_global_pose_override(b["dst"], SOURCE_BASIS * sp, 1.0, true)

	if _weapon_skel != null:
		var wpn_pose := _source_skel.get_bone_global_pose(_wpn_src_bone) if _wpn_src_bone >= 0 else Transform3D.IDENTITY
		var attach_xform := SOURCE_BASIS * wpn_pose
		for b in _weapon_bindings:
			var sp := _source_skel.get_bone_global_pose(b["src"])
			var target_pose := attach_xform * sp
			if not _suppressed and _weapon_skel.get_bone_name(b["dst"]) == "silencer":
				target_pose = target_pose.scaled_local(Vector3(0.0001, 0.0001, 0.0001))
			_weapon_skel.set_bone_global_pose_override(b["dst"], target_pose, 1.0, true)

		if _muzzle_src_bone >= 0:
			var mp := attach_xform * _source_skel.get_bone_global_pose(_muzzle_src_bone)
			_last_muzzle_world = global_transform * mp.origin

func get_muzzle_world_position(cam: Camera3D) -> Vector3:
	if _muzzle_src_bone >= 0 and not _fallback_mesh.visible:
		return _last_muzzle_world
	if cam != null:
		return cam.global_position + (-cam.global_transform.basis.z * 0.55) + (cam.global_transform.basis.x * 0.14) - (cam.global_transform.basis.y * 0.12)
	return global_position
