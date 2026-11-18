extends Node
## EffectsManager: Bullet tracers (using tracer-core/glow), muzzle flashes,
## impact sparks, bullet hole decals, blood hits, smoke clouds, fire, and explosions.

var _tracer_core: Texture2D = null
var _tracer_glow: Texture2D = null
var _active_effects: Array[Dictionary] = []
var _world_root: Node3D = null

func _ready() -> void:
	if ResourceLoader.exists("res://assets/effects/tracer-core.png"):
		_tracer_core = load("res://assets/effects/tracer-core.png")
	if ResourceLoader.exists("res://assets/effects/tracer-glow.png"):
		_tracer_glow = load("res://assets/effects/tracer-glow.png")

func set_world_root(root: Node3D) -> void:
	_world_root = root
	_active_effects.clear()

func _parent_node() -> Node:
	if is_instance_valid(_world_root):
		return _world_root
	return get_tree().current_scene

func _process(delta: float) -> void:
	for i in range(_active_effects.size() - 1, -1, -1):
		var item := _active_effects[i]
		item["t"] += delta
		var node: Node = item["node"]
		if not is_instance_valid(node):
			_active_effects.remove_at(i)
			continue
		if item.has("update"):
			var cb: Callable = item["update"]
			cb.call(item["t"], delta)
		if item["t"] >= item["dur"]:
			node.queue_free()
			_active_effects.remove_at(i)

func spawn_tracer(start_pos: Vector3, end_pos: Vector3, speed_mps: float = 520.0) -> void:
	var dist := start_pos.distance_to(end_pos)
	if dist < 0.4:
		return
	var parent := _parent_node()
	if parent == null:
		return

	var mesh := MeshInstance3D.new()
	var quad := BoxMesh.new()
	var seg_len := clampf(dist * 0.45, 1.2, 18.0)
	quad.size = Vector3(0.018, 0.018, seg_len)
	mesh.mesh = quad
	mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.86, 0.45, 0.92)
	if _tracer_core != null:
		mat.albedo_texture = _tracer_core
	mesh.material_override = mat

	parent.add_child(mesh)
	var dir := (end_pos - start_pos).normalized()
	var travel_time := clampf(dist / maxf(speed_mps, 120.0), 0.04, 0.16)

	mesh.global_position = start_pos + dir * (seg_len * 0.5)
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mesh.look_at(end_pos, Vector3.UP)

	_active_effects.append({
		"node": mesh,
		"t": 0.0,
		"dur": travel_time,
		"update": func(t: float, _dt: float) -> void:
			var prog := clampf(t / travel_time, 0.0, 1.0)
			mesh.global_position = start_pos.lerp(end_pos, prog)
			mat.albedo_color.a = (1.0 - prog) * 0.95
	})

func spawn_muzzle_flash(pos: Vector3) -> void:
	var parent := _parent_node()
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.78, 0.35)
	light.light_energy = 2.6
	light.omni_range = 4.5
	parent.add_child(light)
	light.global_position = pos

	var sprite := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	sprite.mesh = sm
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.82, 0.42, 0.9)
	if _tracer_glow != null:
		mat.albedo_texture = _tracer_glow
	sprite.material_override = mat
	light.add_child(sprite)

	_active_effects.append({
		"node": light,
		"t": 0.0,
		"dur": 0.05,
		"update": func(t: float, _dt: float) -> void:
			var k := 1.0 - clampf(t / 0.05, 0.0, 1.0)
			light.light_energy = 2.6 * k
			mat.albedo_color.a = 0.9 * k
	})

func spawn_impact(pos: Vector3, normal: Vector3, is_blood: bool = false) -> void:
	var parent := _parent_node()
	if parent == null:
		return

	# Bullet hole / blood splat quad
	var decal := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.085, 0.085) if not is_blood else Vector2(0.22, 0.22)
	decal.mesh = qm
	decal.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.05, 0.05, 0.88) if is_blood else Color(0.08, 0.08, 0.08, 0.85)
	decal.material_override = mat
	parent.add_child(decal)

	var n := normal.normalized()
	decal.global_position = pos + n * 0.012
	var up_ref := Vector3.FORWARD if absf(n.dot(Vector3.UP)) > 0.98 else Vector3.UP
	decal.look_at(pos + n * 2.0, up_ref)

	_active_effects.append({
		"node": decal,
		"t": 0.0,
		"dur": 12.0 if not is_blood else 0.55,
		"update": func(t: float, _dt: float) -> void:
			if is_blood:
				mat.albedo_color.a = clampf(1.0 - t / 0.55, 0.0, 0.88)
			elif t > 9.0:
				mat.albedo_color.a = clampf((12.0 - t) / 3.0, 0.0, 0.85)
	})

	# Sparks / particles burst
	var p := GPUParticles3D.new()
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = 10 if is_blood else 8
	p.lifetime = 0.28
	var pm := ParticleProcessMaterial.new()
	pm.direction = n
	pm.spread = 35.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 5.5
	pm.gravity = Vector3(0, -12.0, 0)
	pm.color = Color(0.75, 0.05, 0.05) if is_blood else Color(1.0, 0.82, 0.45)
	p.process_material = pm

	var draw_mesh := BoxMesh.new()
	draw_mesh.size = Vector3(0.02, 0.02, 0.02)
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.albedo_color = pm.color
	draw_mesh.material = dmat
	p.draw_pass_1 = draw_mesh

	parent.add_child(p)
	p.global_position = pos + n * 0.02
	p.emitting = true
	_active_effects.append({"node": p, "t": 0.0, "dur": 0.4})

func spawn_smoke_cloud(pos: Vector3, duration: float = 18.0) -> void:
	var parent := _parent_node()
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos + Vector3.UP * 1.1

	var mats: Array[StandardMaterial3D] = []
	for i in range(6):
		var puff := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = randf_range(1.7, 2.3)
		sm.height = sm.radius * 1.7
		puff.mesh = sm
		puff.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var m := StandardMaterial3D.new()
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.albedo_color = Color(0.74, 0.76, 0.78, 0.88)
		m.roughness = 1.0
		puff.material_override = m
		puff.position = Vector3(randf_range(-1.1, 1.1), randf_range(-0.4, 0.8), randf_range(-1.1, 1.1))
		root.add_child(puff)
		mats.append(m)

	_active_effects.append({
		"node": root,
		"t": 0.0,
		"dur": duration,
		"update": func(t: float, _dt: float) -> void:
			var alpha := 0.88
			if t < 0.8:
				alpha = (t / 0.8) * 0.88
			elif t > duration - 2.5:
				alpha = clampf((duration - t) / 2.5, 0.0, 1.0) * 0.88
			for m in mats:
				m.albedo_color.a = alpha
	})

func spawn_fire_patch(pos: Vector3, duration: float = 7.0) -> void:
	var parent := _parent_node()
	if parent == null:
		return
	var root := Node3D.new()
	parent.add_child(root)
	root.global_position = pos

	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.45, 0.1)
	light.light_energy = 3.5
	light.omni_range = 7.0
	light.position = Vector3.UP * 0.6
	root.add_child(light)

	var p := GPUParticles3D.new()
	p.amount = 48
	p.lifetime = 0.7
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 2.8
	pm.direction = Vector3.UP
	pm.spread = 20.0
	pm.initial_velocity_min = 1.2
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, 2.0, 0)
	pm.color = Color(1.0, 0.42, 0.08, 0.9)
	p.process_material = pm
	var dm := SphereMesh.new()
	dm.radius = 0.22
	dm.height = 0.45
	var dmat := StandardMaterial3D.new()
	dmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	dmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	dmat.albedo_color = Color(1.0, 0.48, 0.1, 0.75)
	dm.material = dmat
	p.draw_pass_1 = dm
	root.add_child(p)
	p.emitting = true

	_active_effects.append({
		"node": root,
		"t": 0.0,
		"dur": duration,
		"update": func(t: float, _dt: float) -> void:
			light.light_energy = 3.0 + sin(t * 25.0) * 0.6
			if t > duration - 0.8:
				p.emitting = false
	})

func spawn_explosion(pos: Vector3) -> void:
	var parent := _parent_node()
	if parent == null:
		return
	var sphere := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.8
	sm.height = 3.6
	sphere.mesh = sm
	sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.albedo_color = Color(1.0, 0.65, 0.2, 0.95)
	sphere.material_override = mat
	parent.add_child(sphere)
	sphere.global_position = pos + Vector3.UP * 0.4

	_active_effects.append({
		"node": sphere,
		"t": 0.0,
		"dur": 0.45,
		"update": func(t: float, _dt: float) -> void:
			var k := clampf(t / 0.45, 0.0, 1.0)
			sphere.scale = Vector3.ONE * (0.5 + k * 2.2)
			mat.albedo_color.a = (1.0 - k) * 0.95
	})

func spawn_flash_burst(pos: Vector3) -> void:
	var parent := _parent_node()
	if parent == null:
		return
	var light := OmniLight3D.new()
	light.light_color = Color(0.95, 0.98, 1.0)
	light.light_energy = 10.0
	light.omni_range = 14.0
	parent.add_child(light)
	light.global_position = pos
	_active_effects.append({
		"node": light,
		"t": 0.0,
		"dur": 0.16,
		"update": func(t: float, _dt: float) -> void:
			light.light_energy = 10.0 * (1.0 - clampf(t / 0.16, 0.0, 1.0))
	})
