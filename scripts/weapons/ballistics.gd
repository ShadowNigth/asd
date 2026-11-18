class_name Ballistics
extends RefCounted
## Hitscan ballistics, spread sampling, armor penetration, hitbox multipliers,
## and multi-surface wallbang penetration matching CS2/CS:GO rules.

const SOURCE_UNIT := 0.0254
const MAX_PENETRATIONS := 4

static func sample_spread_direction(forward: Vector3, up: Vector3, right: Vector3, spread_rad: float) -> Vector3:
	if spread_rad <= 1e-7:
		return forward.normalized()
	var angle := randf() * TAU
	var radius := sqrt(randf()) * spread_rad
	var offset := right * (cos(angle) * radius) + up * (sin(angle) * radius)
	return (forward + offset).normalized()

static func compute_damage(weapon_data: Dictionary, hitbox_zone: String, distance_m: float, has_armor: bool, has_helmet: bool, pen_factor: float = 1.0) -> Dictionary:
	var base_dmg := float(weapon_data.get("damage", 30.0))
	var modifier := float(weapon_data.get("modifier", 0.98))
	var dist_su := distance_m / SOURCE_UNIT
	var falloff := pow(modifier, dist_su / 500.0)
	var dmg := base_dmg * falloff * pen_factor

	var zone_mult := 1.0
	var armored_hit := false
	match hitbox_zone:
		"head":
			zone_mult = float(weapon_data.get("head", 4.0))
			armored_hit = has_helmet
		"stomach":
			zone_mult = 1.25
			armored_hit = has_armor
		"leg":
			zone_mult = 0.75
			armored_hit = false
		_: # chest / arm
			zone_mult = 1.0
			armored_hit = has_armor

	dmg *= zone_mult
	var armor_dmg := 0.0
	if armored_hit:
		var ratio := float(weapon_data.get("armorRatio", 1.4)) * 0.5
		var reduced := dmg * ratio
		armor_dmg = maxf(1.0, (dmg - reduced) * 0.5)
		dmg = reduced

	return {
		"damage": int(maxf(1.0, floorf(dmg))),
		"armor_damage": int(floorf(armor_dmg)),
		"headshot": hitbox_zone == "head",
	}

static func fire_raycast(
	space_state: PhysicsDirectSpaceState3D,
	origin: Vector3,
	dir: Vector3,
	weapon_data: Dictionary,
	shooter: Node,
	exclude_rids: Array[RID]
) -> Dictionary:
	var max_range_m := float(weapon_data.get("range", 8192.0)) * SOURCE_UNIT
	var power := float(weapon_data.get("power", 1.0))
	var cur_origin := origin
	var cur_dir := dir.normalized()
	var traveled := 0.0
	var pen_power := power
	var pen_factor := 1.0
	var hits: Array = []
	var impacts: Array = []
	var local_exclude := exclude_rids.duplicate()
	var end_point := origin + cur_dir * max_range_m

	for _step in range(MAX_PENETRATIONS + 1):
		var rem := max_range_m - traveled
		if rem <= 0.05:
			break
		var query := PhysicsRayQueryParameters3D.create(cur_origin, cur_origin + cur_dir * rem)
		query.exclude = local_exclude
		query.collide_with_areas = true
		query.collide_with_bodies = true
		query.collision_mask = 0xFFFFFFFF

		var res := space_state.intersect_ray(query)
		if res.is_empty():
			break

		var hit_pos: Vector3 = res["position"]
		var hit_normal: Vector3 = res["normal"]
		var collider: Object = res["collider"]
		traveled += cur_origin.distance_to(hit_pos)
		end_point = hit_pos

		if collider is Node:
			var node := collider as Node
			if node.has_meta("hitbox_owner"):
				var owner_node: Node = node.get_meta("hitbox_owner")
				if owner_node == shooter:
					local_exclude.append(res["rid"])
					cur_origin = hit_pos + cur_dir * 0.01
					continue
				var zone := str(node.get_meta("hitbox_zone", "chest"))
				hits.append({
					"target": owner_node,
					"zone": zone,
					"position": hit_pos,
					"normal": hit_normal,
					"distance": traveled,
					"pen_factor": pen_factor,
				})
				# Bullet can penetrate soft body with reduced power
				pen_power -= 0.45
				pen_factor *= 0.72
				local_exclude.append(res["rid"])
				cur_origin = hit_pos + cur_dir * 0.05
				if pen_power <= 0.0:
					break
				continue

		# World surface impact
		impacts.append({"position": hit_pos, "normal": hit_normal, "collider": collider})

		# Attempt wallbang penetration
		if pen_power <= 0.25:
			break
		var max_thick := pen_power * 0.35
		var exit_query := PhysicsRayQueryParameters3D.create(hit_pos + cur_dir * max_thick, hit_pos + cur_dir * 0.01)
		exit_query.collide_with_bodies = true
		exit_query.collide_with_areas = false
		var exit_res := space_state.intersect_ray(exit_query)
		if exit_res.is_empty():
			break
		var thickness := hit_pos.distance_to(exit_res["position"])
		if thickness <= 0.005 or thickness > max_thick:
			break
		pen_power -= thickness / 0.35
		pen_factor *= clampf(1.0 - (thickness / (max_thick + 0.05)) * 0.65, 0.2, 0.9)
		if pen_power <= 0.0:
			break
		cur_origin = exit_res["position"] + cur_dir * 0.02

	return {
		"end_point": end_point,
		"hits": hits,
		"impacts": impacts,
	}
