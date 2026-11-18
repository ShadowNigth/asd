class_name AgentVisual
extends Node3D
## Third-person CS2 Agent visual (1 CT: ctm-sas.glb, 1 T: tm-phoenix.glb)
## with hitbox Area3D capsules for Head / Chest / Stomach / Legs.

var team: String = "ct"
var owner_actor: Node = null
var _model_root: Node3D = null
var _anim_player: AnimationPlayer = null
var _fallback_mesh: Node3D = null
var _hitbox_areas: Array[Area3D] = []

func setup(p_team: String, p_owner: Node) -> void:
	team = p_team
	owner_actor = p_owner
	_load_agent_model()
	_build_hitboxes()

func _load_agent_model() -> void:
	if _model_root != null:
		_model_root.queue_free()
		_model_root = null
	if _fallback_mesh != null:
		_fallback_mesh.queue_free()
		_fallback_mesh = null

	var path := "res://assets/models/agents/ctm-sas.glb" if team == "ct" else "res://assets/models/agents/tm-phoenix.glb"
	var inst := ModelLoader.instantiate_model(path)
	if inst != null:
		_model_root = inst
		_model_root.rotation.y = PI # glTF faces +Z, Godot forward is -Z
		add_child(_model_root)
		_anim_player = _find_anim_player(_model_root)
		return

	# Clean procedural fallback capsule when GLBs aren't synced yet
	_fallback_mesh = Node3D.new()
	add_child(_fallback_mesh)

	var body := MeshInstance3D.new()
	var cap := CapsuleMesh.new()
	cap.radius = 0.28
	cap.height = 1.45
	body.mesh = cap
	body.position = Vector3(0, 0.78, 0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.18, 0.34, 0.56) if team == "ct" else Color(0.58, 0.38, 0.20)
	body.material_override = mat
	_fallback_mesh.add_child(body)

	var head := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.14
	sm.height = 0.28
	head.mesh = sm
	head.position = Vector3(0, 1.64, 0)
	var hmat := StandardMaterial3D.new()
	hmat.albedo_color = Color(0.22, 0.28, 0.35) if team == "ct" else Color(0.75, 0.62, 0.48)
	head.material_override = hmat
	_fallback_mesh.add_child(head)

func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node as AnimationPlayer
	for c in node.get_children():
		var f := _find_anim_player(c)
		if f != null:
			return f
	return null

func _build_hitboxes() -> void:
	for a in _hitbox_areas:
		if is_instance_valid(a):
			a.queue_free()
	_hitbox_areas.clear()

	# Hitboxes aligned to standing Source hull (1.82m tall)
	_add_hitbox("head", Vector3(0, 1.64, 0), 0.14, 0.28)
	_add_hitbox("chest", Vector3(0, 1.24, 0), 0.24, 0.50)
	_add_hitbox("stomach", Vector3(0, 0.92, 0), 0.22, 0.38)
	_add_hitbox("leg", Vector3(0, 0.44, 0), 0.20, 0.84)

func _add_hitbox(zone: String, pos: Vector3, radius: float, height: float) -> void:
	var area := Area3D.new()
	area.collision_layer = 2
	area.collision_mask = 0
	area.monitorable = true
	area.monitoring = false
	area.position = pos
	area.set_meta("hitbox_owner", owner_actor)
	area.set_meta("hitbox_zone", zone)

	var col := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = radius
	cap.height = height
	col.shape = cap
	area.add_child(col)
	add_child(area)
	_hitbox_areas.append(area)

func get_hitbox_rids() -> Array[RID]:
	var rids: Array[RID] = []
	for a in _hitbox_areas:
		if is_instance_valid(a):
			rids.append(a.get_rid())
	return rids

func set_crouch(crouched: bool) -> void:
	scale.y = 0.74 if crouched else 1.0

func set_dead(dead: bool) -> void:
	for a in _hitbox_areas:
		if is_instance_valid(a):
			a.set_deferred("monitorable", not dead)
	if dead:
		rotation.x = deg_to_rad(86.0)
		position.y = 0.18
	else:
		rotation.x = 0.0
		position.y = 0.0
