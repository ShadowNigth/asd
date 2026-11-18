class_name BotController
extends CharacterBody3D
## Tactical Bot AI using 1 agent per team (ctm-sas.glb / tm-phoenix.glb)
## with line-of-sight combat, hitbox damage, and Dust II lane patrol.

var actor_name: String = "Bot"
var team: String = "t"
var health: int = 100
var armor: int = 100
var has_helmet: bool = true
var money: int = 2700
var kills: int = 0
var deaths: int = 0
var alive: bool = true
var weapon_id: int = 0 # AK-47 for T, M4A4/M4A1-S for CT

var _visual: AgentVisual
var _body_col: CollisionShape3D
var _movement := SourceMovement.new()
var _fire_cd: float = 0.0
var _waypoint: Vector3 = Vector3.ZERO
var _repath_timer: float = 0.0
var _burst_left: int = 0

const DUST2_POIS: Array[Vector3] = [
	Vector3(27.0, 2.8, -63.0),   # Site A
	Vector3(-39.0, 0.5, -67.0),  # Site B
	Vector3(-12.0, -2.5, -48.0), # Mid Doors
	Vector3(38.0, 0.4, -36.0),   # Long A
	Vector3(-42.0, 1.2, -31.0),  # Upper Tunnels
	Vector3(2.0, 0.4, -36.0),    # Catwalk
]

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	floor_max_angle = deg_to_rad(45.5)

	_body_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = SourceMovement.HULL_RADIUS
	cap.height = SourceMovement.STANDING_HEIGHT
	_body_col.shape = cap
	_body_col.position = Vector3(0, SourceMovement.STANDING_HEIGHT * 0.5, 0)
	add_child(_body_col)

	_visual = AgentVisual.new()
	add_child(_visual)
	_visual.setup(team, self)

func spawn_for_round(pos: Vector3, yaw_deg: float, p_team: String) -> void:
	if team != p_team and _visual != null:
		team = p_team
		_visual.setup(team, self)
	else:
		team = p_team

	alive = true
	health = 100
	armor = 100
	has_helmet = true
	velocity = Vector3.ZERO
	_movement.reset()
	_body_col.set_deferred("disabled", false)
	if _visual:
		_visual.set_dead(false)

	weapon_id = 0 if team == "t" else 9
	global_position = pos
	rotation.y = deg_to_rad(yaw_deg)
	_pick_new_waypoint()

func _pick_new_waypoint() -> void:
	if GameManager.bomb_planted:
		_waypoint = GameManager.planted_bomb_pos + Vector3(randf_range(-4.0, 4.0), 0.0, randf_range(-4.0, 4.0))
	else:
		_waypoint = DUST2_POIS[randi() % DUST2_POIS.size()]
	_repath_timer = randf_range(3.5, 7.0)

func _physics_process(delta: float) -> void:
	if not alive:
		return
	if GameManager.is_freeze_time():
		return

	_fire_cd = maxf(0.0, _fire_cd - delta)
	_repath_timer -= delta

	var target := _find_visible_enemy()
	var wish_dir := Vector3.ZERO
	var want_walk := false

	if target != null:
		var eye_pos := global_position + Vector3.UP * 1.62
		var target_eye := target.global_position + Vector3.UP * 1.48
		var to_enemy := target_eye - eye_pos
		var flat := Vector3(to_enemy.x, 0.0, to_enemy.z)
		if flat.length() > 0.1:
			var target_yaw := atan2(-flat.x, -flat.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-10.0 * delta))

		# Strafe slightly when engaging
		var dist := flat.length()
		if dist > 22.0:
			wish_dir = flat.normalized()
		elif dist < 8.0:
			wish_dir = -flat.normalized()
		else:
			wish_dir = Vector3(-flat.z, 0.0, flat.x).normalized() * (1.0 if (int(Time.get_ticks_msec() / 900) % 2 == 0) else -1.0)
			want_walk = true

		if _fire_cd <= 0.0:
			_shoot_at(target_eye)
	else:
		if _repath_timer <= 0.0 or global_position.distance_to(_waypoint) < 2.2:
			_pick_new_waypoint()
		var to_wp := _waypoint - global_position
		var flat_wp := Vector3(to_wp.x, 0.0, to_wp.z)
		if flat_wp.length() > 0.4:
			wish_dir = flat_wp.normalized()
			var target_yaw := atan2(-wish_dir.x, -wish_dir.z)
			rotation.y = lerp_angle(rotation.y, target_yaw, 1.0 - exp(-6.0 * delta))

	var move_res := _movement.step_player(self, wish_dir, 215.0, delta, false, want_walk, false)
	if move_res["footstep"]:
		AudioManager.play_footstep(global_position, "sand", false)

func _find_visible_enemy() -> Node3D:
	var eye := global_position + Vector3.UP * 1.62
	var space := get_world_3d().direct_space_state
	var best: Node3D = null
	var best_dist := 60.0
	var excl := [get_rid()]
	if _visual:
		excl.append_array(_visual.get_hitbox_rids())

	for actor in GameManager.get_all_actors():
		if not is_instance_valid(actor) or actor == self:
			continue
		if not actor.get("alive") or str(actor.get("team")) == team:
			continue
		var t_pos: Vector3 = actor.global_position + Vector3.UP * 1.45
		var d := eye.distance_to(t_pos)
		if d > best_dist:
			continue
		var q := PhysicsRayQueryParameters3D.create(eye, t_pos)
		q.exclude = excl
		q.collision_mask = 1
		q.collide_with_areas = false
		var res := space.intersect_ray(q)
		if res.is_empty():
			best = actor
			best_dist = d
	return best

func _shoot_at(target_pos: Vector3) -> void:
	var wdata := WeaponDB.get_weapon(weapon_id)
	var delay := float(wdata.get("delay", 0.12))
	_fire_cd = delay * randf_range(1.4, 2.6)

	var eye := global_position + Vector3.UP * 1.55
	var dir := (target_pos - eye).normalized()
	var spread := 0.042 # Fair bot accuracy
	var right := dir.cross(Vector3.UP).normalized()
	var up := right.cross(dir).normalized()
	var shot_dir := Ballistics.sample_spread_direction(dir, up, right, spread)

	AudioManager.play_weapon_fire(weapon_id, eye, false, true)
	EffectsManager.spawn_muzzle_flash(eye + dir * 0.45)

	var space := get_world_3d().direct_space_state
	var excl := [get_rid()]
	if _visual:
		excl.append_array(_visual.get_hitbox_rids())

	var res := Ballistics.fire_raycast(space, eye, shot_dir, wdata, self, excl)
	EffectsManager.spawn_tracer(eye + dir * 0.45, res["end_point"], 520.0)
	for imp in res["impacts"]:
		EffectsManager.spawn_impact(imp["position"], imp["normal"], false)
	for h in res["hits"]:
		var target: Node = h["target"]
		EffectsManager.spawn_impact(h["position"], h["normal"], true)
		if is_instance_valid(target) and target.has_method("apply_bullet_hit"):
			target.apply_bullet_hit(wdata, h["zone"], h["distance"], h["pen_factor"], self)

func apply_bullet_hit(wdata: Dictionary, zone: String, dist: float, pen_factor: float, attacker: Node) -> void:
	if not alive:
		return
	var dmg_info := Ballistics.compute_damage(wdata, zone, dist, armor > 0, has_helmet, pen_factor)
	armor = maxi(0, armor - int(dmg_info["armor_damage"]))
	apply_damage(int(dmg_info["damage"]), attacker, str(wdata.get("name", "Weapon")), bool(dmg_info["headshot"]))

func apply_damage(amount: int, attacker: Node, weapon_name: String, headshot: bool) -> void:
	if not alive:
		return
	health -= amount
	if health <= 0:
		health = 0
		alive = false
		deaths += 1
		_body_col.set_deferred("disabled", true)
		if _visual:
			_visual.set_dead(true)
		AudioManager.play_3d("death-%d" % randi_range(1, 3), global_position, 0.0)
		GameManager.on_actor_killed(self, attacker, weapon_name, headshot)
