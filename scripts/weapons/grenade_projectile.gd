class_name GrenadeProjectile
extends CharacterBody3D
## CS2/CS:GO Grenade projectile supporting HE, Flashbang, Smoke, Molotov/Incendiary, and Decoy.

enum Kind { HE, FLASH, SMOKE, MOLOTOV, INCENDIARY, DECOY }

@export var kind: Kind = Kind.HE
var owner_player: Node = null
var owner_team: String = "t"
var fuse_time: float = 1.6
var _age: float = 0.0
var _detonated: bool = false
var _bounces: int = 0
var _smoke_active: bool = false
var _fire_active: bool = false
var _fire_tick: float = 0.0

const GRAVITY := 800.0 * 0.0254 # ~20.32 m/s^2 (or 16m/s^2 for Source grenades)
const GRENADE_GRAVITY := 15.5

func _ready() -> void:
	collision_layer = 4
	collision_mask = 1
	_build_visual()
	match kind:
		Kind.HE:
			fuse_time = 1.6
		Kind.FLASH:
			fuse_time = 1.4
		Kind.SMOKE:
			fuse_time = 2.5
		Kind.MOLOTOV, Kind.INCENDIARY:
			fuse_time = 2.0
		Kind.DECOY:
			fuse_time = 12.0

func _build_visual() -> void:
	var col := CollisionShape3D.new()
	var sph := SphereShape3D.new()
	sph.radius = 0.06
	col.shape = sph
	add_child(col)

	var model_map := {
		Kind.HE: "res://assets/models/grenades/he.glb",
		Kind.FLASH: "res://assets/models/grenades/flash.glb",
		Kind.SMOKE: "res://assets/models/grenades/smoke.glb",
		Kind.MOLOTOV: "res://assets/models/grenades/molotov.glb",
		Kind.INCENDIARY: "res://assets/models/grenades/incendiary.glb",
		Kind.DECOY: "res://assets/models/grenades/decoy.glb",
	}
	var path: String = model_map.get(kind, "")
	if not path.is_empty():
		var inst := ModelLoader.instantiate_model(path)
		if inst != null:
			add_child(inst)
			return

	var mesh := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.055
	sm.height = 0.11
	mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	match kind:
		Kind.HE: mat.albedo_color = Color(0.25, 0.35, 0.22)
		Kind.FLASH: mat.albedo_color = Color(0.75, 0.78, 0.85)
		Kind.SMOKE: mat.albedo_color = Color(0.55, 0.58, 0.6)
		Kind.MOLOTOV, Kind.INCENDIARY: mat.albedo_color = Color(0.85, 0.38, 0.12)
		_: mat.albedo_color = Color(0.4, 0.4, 0.4)
	mesh.material_override = mat
	add_child(mesh)

func _physics_process(delta: float) -> void:
	_age += delta
	if _detonated:
		_process_active_effect(delta)
		return

	velocity.y -= GRENADE_GRAVITY * delta
	var col := move_and_collide(velocity * delta)
	if col:
		var normal := col.get_normal()
		# Molotov/Incendiary detonates on flat-ish ground (<30 deg slope)
		if (kind == Kind.MOLOTOV or kind == Kind.INCENDIARY) and normal.y >= 0.866:
			global_position = col.get_position() + Vector3.UP * 0.05
			_detonate()
			return
		# Smoke rests when slow on floor
		if kind == Kind.SMOKE and normal.y > 0.7 and velocity.length() < 1.2:
			velocity = Vector3.ZERO
		else:
			velocity = velocity.bounce(normal) * 0.45
			if _bounces < 4:
				_play_bounce()
			_bounces += 1

	if _age >= fuse_time:
		_detonate()

func _play_bounce() -> void:
	var sound_map := {
		Kind.HE: "utility-he-bounce",
		Kind.FLASH: "utility-flash-bounce",
		Kind.SMOKE: "utility-smoke-bounce",
		Kind.MOLOTOV: "utility-molotov-bounce",
		Kind.INCENDIARY: "utility-incendiary-bounce",
		Kind.DECOY: "utility-decoy-bounce",
	}
	AudioManager.play_3d(sound_map.get(kind, "utility-he-bounce"), global_position, -6.0)

func _detonate() -> void:
	_detonated = true
	velocity = Vector3.ZERO
	match kind:
		Kind.HE:
			AudioManager.play_3d("utility-he-explode", global_position, 2.0)
			EffectsManager.spawn_explosion(global_position)
			_apply_he_damage()
			queue_free()
		Kind.FLASH:
			AudioManager.play_3d("utility-flash-explode", global_position, 2.0)
			EffectsManager.spawn_flash_burst(global_position)
			_apply_flash_blind()
			queue_free()
		Kind.SMOKE:
			AudioManager.play_3d("utility-smoke-explode", global_position, 0.0)
			_smoke_active = true
			_age = 0.0
			EffectsManager.spawn_smoke_cloud(global_position, 18.0)
			queue_free()
		Kind.MOLOTOV, Kind.INCENDIARY:
			var s := "utility-molotov-explode" if kind == Kind.MOLOTOV else "utility-incendiary-explode"
			AudioManager.play_3d(s, global_position, 1.0)
			_fire_active = true
			_age = 0.0
			EffectsManager.spawn_fire_patch(global_position, 7.0 if kind == Kind.MOLOTOV else 5.5)
		Kind.DECOY:
			AudioManager.play_3d("utility-decoy-explode", global_position, -2.0)
			queue_free()

func _process_active_effect(delta: float) -> void:
	if _fire_active:
		var dur := 7.0 if kind == Kind.MOLOTOV else 5.5
		if _age >= dur:
			queue_free()
			return
		_fire_tick += delta
		if _fire_tick >= 0.2:
			_fire_tick -= 0.2
			for actor in GameManager.get_all_actors():
				if not is_instance_valid(actor) or actor.get("health") <= 0:
					continue
				if actor.global_position.distance_to(global_position) <= 3.6:
					if actor.has_method("apply_damage"):
						actor.apply_damage(8, owner_player, "Molotov" if kind == Kind.MOLOTOV else "Incendiary", false)

func _apply_he_damage() -> void:
	for actor in GameManager.get_all_actors():
		if not is_instance_valid(actor) or actor.get("health") <= 0:
			continue
		var d: float = actor.global_position.distance_to(global_position)
		if d > 8.5:
			continue
		var raw := 98.0 * clampf(1.0 - d / 8.5, 0.0, 1.0)
		var dmg := int(maxf(1.0, raw * 0.65))
		if actor.has_method("apply_damage"):
			actor.apply_damage(dmg, owner_player, "HE Grenade", false)

func _apply_flash_blind() -> void:
	var player := GameManager.local_player
	if not is_instance_valid(player) or player.health <= 0:
		return
	var cam := player.get_camera()
	if not cam:
		return
	var to_flash := global_position - cam.global_position
	var dist := to_flash.length()
	if dist > 45.0:
		return
	# LOS check
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(cam.global_position, global_position)
	q.collision_mask = 1
	var res := space.intersect_ray(q)
	if not res.is_empty():
		return
	var look_dir := -cam.global_transform.basis.z
	var facing := clampf(look_dir.dot(to_flash.normalized()), -1.0, 1.0)
	var angle_factor := clampf((facing + 0.5) / 1.5, 0.15, 1.0)
	var dist_factor := clampf(1.0 - dist / 45.0, 0.2, 1.0)
	var blind_dur := 3.8 * angle_factor * dist_factor
	if player.has_method("apply_flash"):
		player.apply_flash(blind_dur)
