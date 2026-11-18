class_name PlayerController
extends CharacterBody3D
## Local FPS Player Controller:
## Source movement, CS2 ballistics/recoil/accuracy, viewmodel + inspect (F),
## zoom scopes, silencer toggle, reload, buy zones, C4 plant/defuse, and grenades.

signal hud_updated()

@export var mouse_sensitivity: float = 0.0022
@export var base_fov: float = 90.0

var actor_name: String = "Player"
var team: String = "ct"
var health: int = 100
var armor: int = 100
var has_helmet: bool = true
var has_defuse_kit: bool = false
var money: int = 800
var kills: int = 0
var deaths: int = 0
var alive: bool = true

# Inventory slots: 1=primary, 2=pistol, 3=knife, 4=c4, 5+=grenades
var primary_weapon: int = -1
var pistol_weapon: int = 2 # USP-S for CT, Glock for T
var knife_weapon: int = 4 # Bayonet
var has_c4: bool = false
var grenades: Dictionary = {"he": 0, "flash": 0, "smoke": 0, "molotov": 0}
var active_slot: int = 2 # 1, 2, 3, 4 (c4), 5 (he), 6 (flash), 7 (smoke), 8 (molotov)

# Per-slot ammo state: slot_key -> {clip, reserve, suppressed}
var ammo_state: Dictionary = {}

var _yaw: float = 0.0
var _pitch: float = 0.0
var _scope_level: int = 0
var _fire_cooldown: float = 0.0
var _fire_released: bool = true
var _reloading: bool = false
var _reload_timer: float = 0.0
var _reload_duration: float = 2.0
var _reload_added: bool = false
var _inspecting: bool = false
var _deploy_timer: float = 0.0
var _flash_alpha: float = 0.0
var _planting: bool = false
var _plant_progress: float = 0.0
var _defusing: bool = false
var _defuse_progress: float = 0.0
var _is_frozen: bool = false
var _in_buy_zone: bool = false
var _current_callout: String = ""

var _movement := SourceMovement.new()
var _recoil := RecoilSystem.new()
var _accuracy := AccuracySystem.new()

var _head_pivot: Node3D
var _camera: Camera3D
var _viewmodel: ViewmodelController
var _world_col: CollisionShape3D

func _ready() -> void:
	collision_layer = 8
	collision_mask = 1
	floor_max_angle = deg_to_rad(45.5)
	floor_snap_length = 0.12

	_world_col = CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = SourceMovement.HULL_RADIUS
	cap.height = SourceMovement.STANDING_HEIGHT
	_world_col.shape = cap
	_world_col.position = Vector3(0, SourceMovement.STANDING_HEIGHT * 0.5, 0)
	add_child(_world_col)

	_head_pivot = Node3D.new()
	_head_pivot.position = Vector3(0, SourceMovement.STANDING_EYE, 0)
	add_child(_head_pivot)

	_camera = Camera3D.new()
	_camera.fov = base_fov
	_camera.near = 0.04
	_camera.far = 500.0
	_head_pivot.add_child(_camera)

	_viewmodel = ViewmodelController.new()
	_camera.add_child(_viewmodel)

func get_camera() -> Camera3D:
	return _camera

func get_exclude_rids() -> Array[RID]:
	return [get_rid()]

func spawn_for_round(pos: Vector3, yaw_deg: float, p_team: String, give_c4: bool = false) -> void:
	team = p_team
	alive = true
	health = 100
	has_c4 = give_c4
	velocity = Vector3.ZERO
	_movement.reset()
	_recoil.reset()
	_accuracy.reset()
	_scope_level = 0
	_reloading = false
	_inspecting = false
	_planting = false
	_plant_progress = 0.0
	_defusing = false
	_defuse_progress = 0.0
	_flash_alpha = 0.0

	global_position = pos
	_yaw = deg_to_rad(yaw_deg)
	_pitch = 0.0
	_apply_camera_rotation()

	if pistol_weapon < 0:
		pistol_weapon = 2 if team == "ct" else 7
	_init_weapon_ammo(pistol_weapon)
	if primary_weapon >= 0:
		_init_weapon_ammo(primary_weapon)
		_equip_slot(1)
	else:
		_equip_slot(2)

func reset_full_loadout(p_team: String) -> void:
	team = p_team
	money = 800
	armor = 0
	has_helmet = false
	has_defuse_kit = false
	primary_weapon = -1
	pistol_weapon = 2 if team == "ct" else 7
	grenades = {"he": 0, "flash": 0, "smoke": 0, "molotov": 0}
	ammo_state.clear()
	_init_weapon_ammo(pistol_weapon)

func _init_weapon_ammo(wid: int) -> void:
	var w := WeaponDB.get_weapon(wid)
	if w.is_empty():
		return
	var mag := int(w.get("mag", 30))
	var res_cnt := int(w.get("reserveCount", 3))
	var res_total := mag * res_cnt if bool(w.get("reserveAsClips", true)) else res_cnt
	ammo_state[wid] = {
		"clip": mag,
		"reserve": res_total,
		"suppressed": true,
	}

func give_weapon(wid: int) -> void:
	var slot := WeaponDB.weapon_slot(wid)
	_init_weapon_ammo(wid)
	if slot == 1:
		primary_weapon = wid
		_equip_slot(1)
	elif slot == 2:
		pistol_weapon = wid
		_equip_slot(2)
	elif slot == 3:
		knife_weapon = wid
		_equip_slot(3)

func give_grenade(kind_key: String) -> bool:
	var cur := int(grenades.get(kind_key, 0))
	var max_amt := 2 if kind_key == "flash" else 1
	if cur >= max_amt:
		return false
	grenades[kind_key] = cur + 1
	return true

func get_active_weapon_id() -> int:
	match active_slot:
		1: return primary_weapon
		2: return pistol_weapon
		3: return knife_weapon
		_: return -1

func is_c4_equipped() -> bool:
	return active_slot == 4 and has_c4

func is_grenade_equipped() -> bool:
	return active_slot >= 5 and active_slot <= 8

func _active_grenade_key() -> String:
	match active_slot:
		5: return "he"
		6: return "flash"
		7: return "smoke"
		8: return "molotov"
		_: return ""

func _equip_slot(slot: int) -> void:
	if slot == 1 and primary_weapon < 0:
		return
	if slot == 2 and pistol_weapon < 0:
		return
	if slot == 4 and not has_c4:
		return
	if slot >= 5:
		var k := _slot_to_grenade_key(slot)
		if int(grenades.get(k, 0)) <= 0:
			return

	active_slot = slot
	_scope_level = 0
	_reloading = false
	_inspecting = false
	_planting = false
	_recoil.reset_weapon_index()

	if slot == 4:
		_viewmodel.load_weapon(-1, true)
		_deploy_timer = 0.65
		AudioManager.play_2d("bomb-draw", -4.0)
	elif slot >= 5:
		_viewmodel.load_weapon(knife_weapon, false)
		_deploy_timer = 0.4
	else:
		var wid := get_active_weapon_id()
		var w := WeaponDB.get_weapon(wid)
		_deploy_timer = float(w.get("deploy", 1.0)) * 0.75
		_viewmodel.load_weapon(wid, false)
		if ammo_state.has(wid):
			_viewmodel.set_suppressed(bool(ammo_state[wid].get("suppressed", true)))
		AudioManager.play_weapon_cue(wid, "draw", global_position, true)
		_viewmodel.play_motion("draw", 1.0, false)

func _slot_to_grenade_key(slot: int) -> String:
	match slot:
		5: return "he"
		6: return "flash"
		7: return "smoke"
		8: return "molotov"
		_: return ""

func _unhandled_input(event: InputEvent) -> void:
	if not alive or Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		return
	if event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		var zoom_scale := 1.0
		if _scope_level == 1:
			zoom_scale = 0.5
		elif _scope_level == 2:
			zoom_scale = 0.25
		_yaw -= mm.relative.x * mouse_sensitivity * zoom_scale
		_pitch = clampf(_pitch - mm.relative.y * mouse_sensitivity * zoom_scale, deg_to_rad(-89.0), deg_to_rad(89.0))
		_viewmodel.add_sway(mm.relative)

func _physics_process(delta: float) -> void:
	if _flash_alpha > 0.0:
		_flash_alpha = maxf(0.0, _flash_alpha - delta * 0.85)

	if not alive:
		return

	_is_frozen = GameManager.is_freeze_time()
	var can_act := Input.mouse_mode == Input.MOUSE_MODE_CAPTURED

	# Buy zone & callout updates
	var map_node := GameManager.dust2_map
	if is_instance_valid(map_node):
		_in_buy_zone = map_node.is_in_buy_zone(global_position, team)
		_current_callout = map_node.get_callout_at(global_position)

	# Weapon switching
	if can_act:
		if Input.is_action_just_pressed("slot_1"): _equip_slot(1)
		elif Input.is_action_just_pressed("slot_2"): _equip_slot(2)
		elif Input.is_action_just_pressed("slot_3"): _equip_slot(3)
		elif Input.is_action_just_pressed("slot_4"): _equip_slot(4)
		elif Input.is_action_just_pressed("slot_he"): _equip_slot(5)
		elif Input.is_action_just_pressed("slot_flash"): _equip_slot(6)
		elif Input.is_action_just_pressed("slot_smoke"): _equip_slot(7)
		elif Input.is_action_just_pressed("slot_molotov"): _equip_slot(8)
		elif Input.is_action_just_pressed("drop_weapon"):
			_drop_active_weapon()

	# Movement
	var wish_dir := Vector3.ZERO
	var want_jump := false
	var want_walk := false
	var want_duck := false
	if not _is_frozen and can_act:
		var fwd := -Vector3(sin(_yaw), 0.0, cos(_yaw))
		var right := Vector3(cos(_yaw), 0.0, -sin(_yaw))
		if Input.is_action_pressed("move_forward"): wish_dir += fwd
		if Input.is_action_pressed("move_back"): wish_dir -= fwd
		if Input.is_action_pressed("move_right"): wish_dir += right
		if Input.is_action_pressed("move_left"): wish_dir -= right
		want_jump = Input.is_action_pressed("jump")
		want_walk = Input.is_action_pressed("walk")
		want_duck = Input.is_action_pressed("duck")

	var wid := get_active_weapon_id()
	var wdata := WeaponDB.get_weapon(wid) if wid >= 0 else {}
	var max_su := float(wdata.get("maxSpeed", [250.0, 250.0])[1 if _scope_level > 0 else 0]) if not wdata.is_empty() else 250.0

	var move_res := _movement.step_player(self, wish_dir, max_su, delta, want_jump, want_walk, want_duck)
	if move_res["jumped"]:
		AudioManager.play_2d("jump", -8.0)
	if move_res["landed_speed"] > 0.0:
		AudioManager.play_2d("land", -7.0)
		if wid >= 0:
			_accuracy.apply_landing(wid, 1 if _scope_level > 0 else 0, move_res["landed_speed"])
	if move_res["footstep"]:
		AudioManager.play_footstep(global_position, "sand", true)

	# Adjust capsule height & eye position
	var cap := _world_col.shape as CapsuleShape3D
	var cur_h := lerpf(SourceMovement.STANDING_HEIGHT, SourceMovement.DUCK_HEIGHT, _movement.crouch_amount)
	cap.height = cur_h
	_world_col.position.y = cur_h * 0.5
	_head_pivot.position.y = _movement.eye_height

	# Step recoil & accuracy
	if wid >= 0:
		_recoil.step(delta, wid, want_duck)
		_accuracy.advance(delta, wid, _recoil.shot_index, 1 if _scope_level > 0 else 0, move_res["speed"], move_res["crouch"], move_res["grounded"], _reloading)
	else:
		_recoil.step(delta, 4, want_duck)

	# Camera FOV & recoil punch
	var target_fov := base_fov
	if _scope_level == 1:
		target_fov = float(wdata.get("zoomFov1", 40.0))
	elif _scope_level == 2:
		target_fov = float(wdata.get("zoomFov2", 15.0))
	_camera.fov = lerpf(_camera.fov, target_fov, 1.0 - exp(-22.0 * delta))
	_apply_camera_rotation()

	# Weapon actions
	if _deploy_timer > 0.0:
		_deploy_timer = maxf(0.0, _deploy_timer - delta)
	if _fire_cooldown > 0.0:
		_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	_process_reload(delta, wid, wdata)
	_process_bomb_actions(delta, can_act)

	if can_act and not _is_frozen:
		_process_combat_input(delta, wid, wdata)

	_viewmodel.update_viewmodel(delta, move_res["speed"], move_res["grounded"])

func _apply_camera_rotation() -> void:
	var vp := clampf(_pitch + _recoil.get_view_pitch(), deg_to_rad(-89.5), deg_to_rad(89.5))
	var vy := _yaw + _recoil.get_view_yaw()
	_head_pivot.rotation = Vector3(vp, vy, 0.0)

func _process_reload(delta: float, wid: int, wdata: Dictionary) -> void:
	if not _reloading or wid < 0:
		return
	_reload_timer += delta
	if not _reload_added and _reload_timer >= _reload_duration * 0.55:
		_reload_added = true
		var mag := int(wdata.get("mag", 30))
		var st: Dictionary = ammo_state[wid]
		var needed := mag - int(st["clip"])
		var take := mini(needed, int(st["reserve"]))
		st["clip"] = int(st["clip"]) + take
		st["reserve"] = int(st["reserve"]) - take
		AudioManager.play_weapon_cue(wid, "reloadIn", global_position, true)
	if _reload_timer >= _reload_duration:
		_reloading = false

func _process_bomb_actions(delta: float, can_act: bool) -> void:
	var map_node := GameManager.dust2_map
	if not is_instance_valid(map_node):
		return

	# Planting (T with C4 in Site A or B holding fire or E)
	if can_act and not _is_frozen and team == "t" and has_c4 and map_node.get_bombsite_at(global_position) >= 0:
		var want_plant := Input.is_action_pressed("use") or (is_c4_equipped() and Input.is_action_pressed("fire"))
		if want_plant and not GameManager.bomb_planted:
			if not _planting:
				_planting = true
				_plant_progress = 0.0
				_equip_slot(4)
				AudioManager.play_2d("bomb-initiate", -3.0)
				_viewmodel.play_motion("plant", 1.0, false)
			_plant_progress += delta / 3.2
			if _plant_progress >= 1.0:
				_planting = false
				_plant_progress = 0.0
				has_c4 = false
				GameManager.plant_bomb(global_position, map_node.get_bombsite_at(global_position), self)
				_equip_slot(1 if primary_weapon >= 0 else 2)
			return
	_planting = false
	_plant_progress = 0.0

	# Defusing (CT near planted bomb holding E)
	if can_act and not _is_frozen and team == "ct" and GameManager.bomb_planted and GameManager.planted_bomb_pos.distance_to(global_position) <= 2.3:
		if Input.is_action_pressed("use"):
			if not _defusing:
				_defusing = true
				_defuse_progress = 0.0
				AudioManager.play_2d("bomb-defuse-start", -3.0)
			var defuse_time := 5.0 if has_defuse_kit else 10.0
			_defuse_progress += delta / defuse_time
			if _defuse_progress >= 1.0:
				_defusing = false
				_defuse_progress = 0.0
				GameManager.defuse_bomb(self)
			return
	_defusing = false
	_defuse_progress = 0.0

func _process_combat_input(_delta: float, wid: int, wdata: Dictionary) -> void:
	# Inspect weapon (F key -> lookat01)
	if Input.is_action_just_pressed("inspect") and not _reloading and _deploy_timer <= 0.0 and wid >= 0:
		_inspecting = true
		_viewmodel.play_motion("lookat01", 1.0, false)

	# Alt-fire: Zoom or Silencer toggle or Knife heavy stab
	if Input.is_action_just_pressed("alt_fire") and wid >= 0 and _deploy_timer <= 0.0:
		var z_levels := int(wdata.get("zoomLevels", 0))
		if z_levels > 0:
			_scope_level = (_scope_level + 1) % (z_levels + 1)
			AudioManager.play_weapon_cue(wid, "scope", global_position, true)
			if _scope_level == 0:
				_camera.fov = base_fov
		elif wid == 1 or wid == 2:
			# Toggle suppressor on M4A1-S / USP-S
			var cur_sup := bool(ammo_state[wid].get("suppressed", true))
			ammo_state[wid]["suppressed"] = not cur_sup
			_viewmodel.set_suppressed(not cur_sup)
			_viewmodel.play_motion("silencer_detach" if cur_sup else "silencer_attach", 1.0, false)
			_deploy_timer = 1.6
		elif WeaponDB.is_knife(wid):
			_perform_knife_attack(true)
			return

	# Reload (R key)
	if Input.is_action_just_pressed("reload") and wid >= 0 and not WeaponDB.is_knife(wid) and not _reloading and _deploy_timer <= 0.0:
		_start_reload(wid, wdata)

	# Fire
	var fire_pressed := Input.is_action_pressed("fire")
	if not fire_pressed:
		_fire_released = true
		return

	if _deploy_timer > 0.0 or _fire_cooldown > 0.0 or _reloading:
		return

	# Throw grenade
	if is_grenade_equipped():
		if _fire_released:
			_fire_released = false
			_throw_active_grenade()
		return

	if wid < 0:
		return

	if WeaponDB.is_knife(wid):
		if _fire_released:
			_fire_released = false
			_perform_knife_attack(false)
		return

	var is_auto := bool(wdata.get("auto", false))
	if not is_auto and not _fire_released:
		return
	_fire_released = false

	var st: Dictionary = ammo_state.get(wid, {})
	if int(st.get("clip", 0)) <= 0:
		AudioManager.play_2d("click", -4.0)
		_fire_cooldown = 0.2
		_start_reload(wid, wdata)
		return

	_fire_gun(wid, wdata, st)

func _start_reload(wid: int, wdata: Dictionary) -> void:
	var mag := int(wdata.get("mag", 30))
	var st: Dictionary = ammo_state.get(wid, {})
	if int(st.get("clip", 0)) >= mag or int(st.get("reserve", 0)) <= 0:
		return
	_reloading = true
	_reload_timer = 0.0
	_reload_added = false
	_scope_level = 0
	_inspecting = false
	_reload_duration = float(wdata.get("reload", 2.4))
	var is_empty := int(st.get("clip", 0)) == 0
	if is_empty and _viewmodel.has_motion("reload_empty"):
		_viewmodel.play_motion("reload_empty", 1.0, false)
	else:
		_viewmodel.play_motion("reload", 1.0, false)
	AudioManager.play_weapon_cue(wid, "reload", global_position, true)

func _fire_gun(wid: int, wdata: Dictionary, st: Dictionary) -> void:
	_inspecting = false
	st["clip"] = int(st["clip"]) - 1
	_fire_cooldown = float(wdata.get("delay", 0.1))

	var fire_mode := 1 if _scope_level > 0 else 0
	var suppressed := bool(st.get("suppressed", true))

	AudioManager.play_weapon_fire(wid, global_position, true, suppressed)
	if int(st["clip"]) == 0 and _viewmodel.has_motion("shoot_empty"):
		_viewmodel.play_motion("shoot_empty", 1.0, false)
	else:
		_viewmodel.play_motion("shoot1", 1.0, false)

	var muzzle_pos := _viewmodel.get_muzzle_world_position(_camera)
	if not suppressed or (wid != 1 and wid != 2 and wid != 28):
		EffectsManager.spawn_muzzle_flash(muzzle_pos)

	# Compute shot basis including ballistic recoil
	var shot_basis := Basis.from_euler(Vector3(
		_pitch + _recoil.get_ballistic_pitch(),
		_yaw + _recoil.get_ballistic_yaw(),
		0.0
	))
	var fwd := -shot_basis.z
	var right := shot_basis.x
	var up := shot_basis.y
	var total_spread := _accuracy.get_total_inaccuracy(wid, fire_mode)

	var pellets := int(wdata.get("pellets", 1))
	var space := get_world_3d().direct_space_state
	var excl := get_exclude_rids()

	for _p in range(pellets):
		var dir := Ballistics.sample_spread_direction(fwd, up, right, total_spread)
		var res := Ballistics.fire_raycast(space, _camera.global_position, dir, wdata, self, excl)
		EffectsManager.spawn_tracer(muzzle_pos, res["end_point"], 520.0)

		for imp in res["impacts"]:
			EffectsManager.spawn_impact(imp["position"], imp["normal"], false)

		for h in res["hits"]:
			var target: Node = h["target"]
			EffectsManager.spawn_impact(h["position"], h["normal"], true)
			if is_instance_valid(target) and target.has_method("apply_bullet_hit"):
				target.apply_bullet_hit(wdata, h["zone"], h["distance"], h["pen_factor"], self)

	_recoil.apply_shot(wid, fire_mode)
	_accuracy.apply_fire(wid, fire_mode)

	if bool(wdata.get("unzoomsAfterShot", false)):
		_scope_level = 0
		_camera.fov = base_fov

func _perform_knife_attack(heavy: bool) -> void:
	_fire_cooldown = 1.0 if heavy else 0.42
	_viewmodel.play_motion("shoot2" if heavy else "shoot1", 1.0, false)
	AudioManager.play_2d("knife-swing1", -4.0)

	var space := get_world_3d().direct_space_state
	var fwd := -_camera.global_transform.basis.z
	var q := PhysicsRayQueryParameters3D.create(_camera.global_position, _camera.global_position + fwd * 1.9)
	q.exclude = get_exclude_rids()
	q.collide_with_areas = true
	q.collide_with_bodies = true
	var res := space.intersect_ray(q)
	if res.is_empty():
		return
	var col: Object = res["collider"]
	if col is Node and (col as Node).has_meta("hitbox_owner"):
		var target: Node = (col as Node).get_meta("hitbox_owner")
		if target != self and target.has_method("apply_damage"):
			AudioManager.play_2d("knife-stab" if heavy else "knife-hit", -2.0)
			EffectsManager.spawn_impact(res["position"], res["normal"], true)
			target.apply_damage(55 if heavy else 34, self, "Bayonet", false)
			return
	AudioManager.play_2d("knife-wall", -4.0)
	EffectsManager.spawn_impact(res["position"], res["normal"], false)

func _throw_active_grenade() -> void:
	var key := _active_grenade_key()
	if key.is_empty() or int(grenades.get(key, 0)) <= 0:
		return
	grenades[key] = int(grenades[key]) - 1
	_fire_cooldown = 0.55

	var g := GrenadeProjectile.new()
	match key:
		"he": g.kind = GrenadeProjectile.Kind.HE
		"flash": g.kind = GrenadeProjectile.Kind.FLASH
		"smoke": g.kind = GrenadeProjectile.Kind.SMOKE
		"molotov": g.kind = GrenadeProjectile.Kind.INCENDIARY if team == "ct" else GrenadeProjectile.Kind.MOLOTOV
	g.owner_player = self
	g.owner_team = team
	get_tree().current_scene.add_child(g)
	var fwd := -_camera.global_transform.basis.z
	g.global_position = _camera.global_position + fwd * 0.55
	g.velocity = fwd * 17.5 + Vector3.UP * 3.5 + velocity * 0.35
	AudioManager.play_2d("utility-%s-throw" % key, -4.0)

	# Switch back to weapon
	_equip_slot(1 if primary_weapon >= 0 else 2)

func _drop_active_weapon() -> void:
	if active_slot == 1 and primary_weapon >= 0:
		primary_weapon = -1
		_equip_slot(2)
	elif active_slot == 2 and pistol_weapon >= 0:
		pistol_weapon = -1
		_equip_slot(3)

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
	AudioManager.play_2d("head" if headshot else "damage-%d" % randi_range(1, 3), -4.0)
	if health <= 0:
		health = 0
		alive = false
		deaths += 1
		AudioManager.play_2d("death-%d" % randi_range(1, 3), -2.0)
		GameManager.on_actor_killed(self, attacker, weapon_name, headshot)

func apply_flash(duration: float) -> void:
	_flash_alpha = clampf(maxf(_flash_alpha, duration * 0.6), 0.0, 1.35)

func get_current_crosshair_spread() -> float:
	var wid := get_active_weapon_id()
	if wid < 0 or WeaponDB.is_knife(wid):
		return 0.005
	return _accuracy.get_total_inaccuracy(wid, 1 if _scope_level > 0 else 0)

func get_hud_snapshot() -> Dictionary:
	var wid := get_active_weapon_id()
	var wdata := WeaponDB.get_weapon(wid) if wid >= 0 else {}
	var st: Dictionary = ammo_state.get(wid, {"clip": 0, "reserve": 0})
	return {
		"health": health,
		"armor": armor,
		"helmet": has_helmet,
		"kit": has_defuse_kit,
		"money": money,
		"team": team,
		"alive": alive,
		"weapon_name": "C4" if is_c4_equipped() else (_active_grenade_key().to_upper() if is_grenade_equipped() else str(wdata.get("name", "Knife"))),
		"clip": int(st.get("clip", 0)),
		"reserve": int(st.get("reserve", 0)),
		"has_ammo": wid >= 0 and not WeaponDB.is_knife(wid) and not is_c4_equipped() and not is_grenade_equipped(),
		"scope_level": _scope_level,
		"spread": get_current_crosshair_spread(),
		"flash_alpha": clampf(_flash_alpha, 0.0, 1.0),
		"in_buy_zone": _in_buy_zone,
		"callout": _current_callout,
		"has_c4": has_c4,
		"grenades": grenades,
		"planting": _planting,
		"plant_progress": _plant_progress,
		"defusing": _defusing,
		"defuse_progress": _defuse_progress,
		"reloading": _reloading,
	}
