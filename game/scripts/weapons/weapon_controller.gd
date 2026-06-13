class_name WeaponController
extends Node3D
## Owns the player's carried weapons and turns input into shots.
##
## The firing *rules* live in Weapon and Ballistics (pure, unit-tested); this
## node is the scene glue: camera-aligned hitscan with per-shot spread, tracer /
## muzzle / impact FX, recoil fed back to the camera, and ammo + loadout signals
## the HUD listens to. Holstering hides the gun and frees aim; entering a vehicle
## force-holsters via force_holster().

signal ammo_changed(ammo: int, reserve: int, armed: bool)
signal weapon_changed(display_name: String, armed: bool)
## Emitted the moment a shot damages something; killed is true if that hit
## dropped the target. The HUD turns this into a hit-marker.
signal hit_confirmed(killed: bool)
## Emitted only when the thing shot was a person (pedestrian/police). The
## WantedTracker witness-checks the crime position and turns it into heat.
## killed distinguishes a wounding from a kill so murders escalate harder.
signal crime_committed(killed: bool, crime_pos: Vector3)

## Tighter cone while aiming down sights (fraction of the hipfire spread).
const AIM_SPREAD_SCALE: float = 0.4

## Generated once and shared by every bullet hole; a soft round scorch decal.
static var _decal_texture: Texture2D = null

@export var camera_path: NodePath
@export var muzzle_path: NodePath
@export var gun_mount_path: NodePath
## What a bullet may strike: world, vehicles, props/hittables.
@export_flags_3d_physics var hit_mask: int = 0xFFFFFFFF
## Visible rearward kick (m) of the held gun on each shot, eased back each frame.
@export var recoil_gun_kick: float = 0.10
@export var recoil_recover: float = 1.4
## Camera-shake trauma added per shot (on top of the directed recoil kick) via
## the shared CameraShake system, for a punchier muzzle feel.
@export_range(0.0, 1.0) var fire_shake_trauma: float = 0.12
## Impact hitstop: a brief real-time clock freeze when a shot connects, for that
## meaty crunch. A kill freezes a little longer/harder than a wounding.
@export var hitstop_hit_seconds: float = 0.045
@export_range(0.0, 1.0) var hitstop_hit_scale: float = 0.08
@export var hitstop_kill_seconds: float = 0.10
@export_range(0.0, 1.0) var hitstop_kill_scale: float = 0.02

var _weapons: Array[Weapon] = []
var _index: int = 0
var _armed: bool = false
var _aiming: bool = false
var _gun_recoil: float = 0.0
var _gun_rest_z: float = 0.0
var _player_rid: RID
var _rng := RandomNumberGenerator.new()
var _hitstop: Hitstop = null

@onready var _camera: Camera3D = get_node_or_null(camera_path)
@onready var _muzzle: Node3D = get_node_or_null(muzzle_path)
@onready var _gun_mount: Node3D = get_node_or_null(gun_mount_path)
@onready var _camera_rig: OrbitCamera = _resolve_camera_rig()


func _ready() -> void:
	_rng.randomize()
	add_to_group("weapon_controller")
	# Hitstop is code-spawned so the punch-on-impact feature stays self-contained.
	_hitstop = Hitstop.new()
	add_child(_hitstop)
	for stats in [
		WeaponStats.pistol(), WeaponStats.smg(), WeaponStats.rifle(), WeaponStats.shotgun()
	]:
		_weapons.append(Weapon.new(stats))
	if _gun_mount != null:
		_gun_rest_z = _gun_mount.position.z
	var body := get_parent() as CollisionObject3D
	if body != null:
		_player_rid = body.get_rid()
	_apply_armed_visual()
	_emit_state()


## Camera yaw to face while armed (so the character aims where you look), or NAN
## to let the animator keep facing the travel direction. Read by Player.
func facing_override() -> float:
	if not _armed or _camera == null:
		return NAN
	var fwd := -_camera.global_transform.basis.z
	# The rig's forward (face) is local -Z, so point -Z along the camera forward
	# by negating both components — matching CharacterAnimator's travel-facing.
	return atan2(-fwd.x, -fwd.z)


func is_armed() -> bool:
	return _armed


## Effective aim-cone half-angle right now (0 when holstered) — the HUD scales
## the crosshair gap from this so bloom and aim are visible.
func current_spread() -> float:
	var weapon := _current()
	if weapon == null or not _armed:
		return 0.0
	return weapon.spread * (AIM_SPREAD_SCALE if _aiming else 1.0)


## One-call snapshot for the HUD to poll, avoiding any signal-ordering coupling.
func hud_state() -> Dictionary:
	var weapon := _current()
	if weapon == null:
		return {"armed": false, "name": "", "ammo": 0, "reserve": 0, "spread": 0.0}
	return {
		"armed": _armed,
		"name": weapon.stats.display_name,
		"ammo": weapon.ammo,
		"reserve": weapon.reserve,
		"spread": current_spread(),
	}


## Full loadout snapshot for the weapon wheel: one entry per carried weapon in
## carry order, each {name, ammo, reserve, automatic}. The wheel highlights
## current_index() and calls equip() when the player picks a slot.
func loadout() -> Array:
	var out: Array = []
	for weapon in _weapons:
		(
			out
			. append(
				{
					"name": weapon.stats.display_name,
					"ammo": weapon.ammo,
					"reserve": weapon.reserve,
					"automatic": weapon.stats.automatic,
				}
			)
		)
	return out


## Index of the currently selected weapon within loadout().
func current_index() -> int:
	return _index


## Equip the weapon at `index` and raise it. Out-of-range indices are ignored,
## so the wheel can pass a "no change" -1 safely.
func equip(index: int) -> void:
	if index < 0 or index >= _weapons.size():
		return
	_index = index
	if not _armed:
		_set_armed(true)
	else:
		_emit_state()


## Put the weapon away (called when entering a vehicle, etc.).
func force_holster() -> void:
	if _armed:
		_set_armed(false)


func _process(delta: float) -> void:
	# Frozen while the player is hidden (e.g. riding in a vehicle).
	if not _is_active():
		return
	var weapon := _current()
	if weapon != null:
		weapon.tick(delta)
	_update_gun_recoil(delta)

	if Input.is_action_just_pressed("holster"):
		_set_armed(not _armed)
	if Input.is_action_just_pressed("weapon_next"):
		_cycle_weapon()

	if not _armed or weapon == null:
		_set_camera_aim(false)
		return

	_aiming = Input.is_action_pressed("aim")
	_set_camera_aim(_aiming)

	if Input.is_action_just_pressed("reload") and weapon.start_reload():
		_emit_state()

	var trigger := (
		Input.is_action_pressed("fire")
		if weapon.stats.automatic
		else Input.is_action_just_pressed("fire")
	)
	if trigger:
		_try_fire(weapon)


func _try_fire(weapon: Weapon) -> void:
	if not weapon.fire():
		return
	var space := get_world_3d().direct_space_state
	var cam := _camera.global_transform
	var origin := cam.origin
	var basis := cam.basis
	var spread := weapon.spread * (AIM_SPREAD_SCALE if _aiming else 1.0)
	var muzzle_pos := _muzzle.global_position if _muzzle != null else origin

	for _pellet in maxi(1, weapon.stats.pellets):
		var sample := Ballistics.disk_sample(_rng.randf(), _rng.randf())
		var dir := Ballistics.spread_direction(-basis.z, basis.x, basis.y, sample, spread)
		var target := origin + dir * weapon.stats.range
		var query := PhysicsRayQueryParameters3D.create(origin, target, hit_mask)
		query.exclude = [_player_rid]
		var hit := space.intersect_ray(query)
		if hit.is_empty():
			_spawn_tracer(muzzle_pos, target)
		else:
			_spawn_tracer(muzzle_pos, hit.position)
			# Bullet holes only mark static world geometry — decaling a moving
			# pedestrian or car would smear and strand the hole in mid-air.
			_spawn_impact(hit.position, hit.normal, not _is_actor(hit.get("collider")))
			_apply_damage(weapon, origin, hit)

	_spawn_muzzle_flash(muzzle_pos, -basis.z)
	_gun_recoil = recoil_gun_kick
	if _camera_rig != null:
		_camera_rig.add_recoil(weapon.stats.recoil_kick)
		_camera_rig.add_shake(fire_shake_trauma)
	_emit_state()


func _apply_damage(weapon: Weapon, origin: Vector3, hit: Dictionary) -> void:
	var collider: Object = hit.get("collider")
	if collider == null or not collider.has_method("take_damage"):
		return
	var distance := origin.distance_to(hit.position)
	var damage := Ballistics.damage_at_range(
		weapon.stats.damage,
		distance,
		weapon.stats.damage_falloff_start,
		weapon.stats.damage_falloff_end,
		weapon.stats.min_damage_fraction
	)
	collider.take_damage(damage, hit.position, hit.normal)
	var killed: bool = collider.has_method("is_dead") and collider.is_dead()
	# Punch the moment: stagger the target and jam the clock briefly (harder on a
	# kill) so a connecting shot lands with weight instead of passing through.
	if collider.has_method("flinch"):
		var shot_dir: Vector3 = hit.position - origin
		if shot_dir.length() > 0.001:
			collider.flinch(shot_dir.normalized())
	if _hitstop != null:
		if killed:
			_hitstop.hit(hitstop_kill_seconds, hitstop_kill_scale)
		else:
			_hitstop.hit(hitstop_hit_seconds, hitstop_hit_scale)
	hit_confirmed.emit(killed)
	for text in get_tree().get_nodes_in_group("combat_text"):
		if text.has_method("popup"):
			text.popup(damage, hit.position, killed)
	var node := collider as Node
	if node != null and (node.is_in_group("pedestrians") or node.is_in_group("police")):
		crime_committed.emit(killed, hit.position)


func _cycle_weapon() -> void:
	if _weapons.is_empty():
		return
	_index = (_index + 1) % _weapons.size()
	if not _armed:
		_set_armed(true)
	else:
		_emit_state()


func _set_armed(value: bool) -> void:
	_armed = value
	if not _armed:
		_aiming = false
		_set_camera_aim(false)
	_apply_armed_visual()
	_emit_state()


func _apply_armed_visual() -> void:
	if _gun_mount != null:
		_gun_mount.visible = _armed


func _update_gun_recoil(delta: float) -> void:
	_gun_recoil = move_toward(_gun_recoil, 0.0, recoil_recover * delta)
	if _gun_mount != null:
		_gun_mount.position.z = _gun_rest_z + _gun_recoil


func _set_camera_aim(value: bool) -> void:
	if _camera_rig != null:
		_camera_rig.set_aiming(value)


func _is_active() -> bool:
	var parent := get_parent() as Node3D
	return parent != null and parent.visible


func _current() -> Weapon:
	return _weapons[_index] if _index < _weapons.size() else null


func _emit_state() -> void:
	var weapon := _current()
	if weapon == null:
		return
	ammo_changed.emit(weapon.ammo, weapon.reserve, _armed)
	weapon_changed.emit(weapon.stats.display_name, _armed)


func _resolve_camera_rig() -> OrbitCamera:
	if _camera == null:
		return null
	var node := _camera.get_parent()
	while node != null:
		if node is OrbitCamera:
			return node
		node = node.get_parent()
	return null


# --- procedural FX: short-lived nodes, freed by a one-shot timer ----------


func _spawn_tracer(from: Vector3, to: Vector3) -> void:
	var length := from.distance_to(to)
	if length < 0.05:
		return
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.03, 0.03, length)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.85, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.3)
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mesh.material = mat
	var inst := MeshInstance3D.new()
	inst.mesh = mesh
	_fx_parent().add_child(inst)
	inst.global_position = (from + to) * 0.5
	inst.look_at(to, Vector3.UP)
	_free_after(inst, 0.04)


func _spawn_impact(point: Vector3, normal: Vector3, decal: bool) -> void:
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.7, 0.3)
	flash.light_energy = 2.5
	flash.omni_range = 2.5
	flash.shadow_enabled = false
	_fx_parent().add_child(flash)
	flash.global_position = point + normal * 0.05
	_free_after(flash, 0.06)
	if decal:
		_spawn_bullet_hole(point, normal)


## A lingering scorched bullet hole projected onto the surface that was hit. The
## decal is oriented so its projection axis drives into the surface along -normal.
func _spawn_bullet_hole(point: Vector3, normal: Vector3) -> void:
	var n := normal.normalized()
	if n.length() < 0.5:
		return
	var decal := Decal.new()
	decal.texture_albedo = _bullet_hole_texture()
	decal.size = Vector3(0.32, 0.4, 0.32)
	decal.albedo_mix = 1.0
	# Build an orthonormal basis whose +Y is the surface normal, so the decal's
	# downward projection (-Y) sinks into the surface.
	var tangent := n.cross(Vector3.RIGHT)
	if tangent.length() < 0.01:
		tangent = n.cross(Vector3.FORWARD)
	tangent = tangent.normalized()
	var bitangent := tangent.cross(n).normalized()
	_fx_parent().add_child(decal)
	decal.global_transform = Transform3D(Basis(tangent, n, bitangent), point + n * 0.02)
	_free_after(decal, 6.0)


func _spawn_muzzle_flash(at: Vector3, dir: Vector3) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.85, 0.5)
	light.light_energy = 3.5
	light.omni_range = 3.5
	light.shadow_enabled = false
	_fx_parent().add_child(light)
	light.global_position = at + dir * 0.1
	_free_after(light, 0.05)
	var card := MeshInstance3D.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.34, 0.34)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.9, 0.55)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.8, 0.4)
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.material = mat
	card.mesh = quad
	_fx_parent().add_child(card)
	card.global_position = at + dir * 0.12
	_free_after(card, 0.04)


## True when the hit thing is a moving actor (pedestrian/police/vehicle), which
## must not receive a world-space bullet-hole decal.
func _is_actor(collider: Object) -> bool:
	var node := collider as Node
	if node == null:
		return false
	return (
		node.is_in_group("pedestrians")
		or node.is_in_group("police")
		or node.is_in_group("vehicles")
	)


## Lazily bake the shared bullet-hole texture: a soft round dark scorch that fades
## to transparent at the rim, so holes read as round marks not hard squares.
static func _bullet_hole_texture() -> Texture2D:
	if _decal_texture != null:
		return _decal_texture
	var size := 32
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var center := (float(size) - 1.0) * 0.5
	for y in size:
		for x in size:
			var d := Vector2(float(x) - center, float(y) - center).length() / center
			var alpha := clampf(1.0 - smoothstep(0.35, 1.0, d), 0.0, 1.0)
			img.set_pixel(x, y, Color(0.04, 0.035, 0.03, alpha))
	_decal_texture = ImageTexture.create_from_image(img)
	return _decal_texture


# World-space parent for transient FX; falls back to the tree root in headless
# harnesses where current_scene is unset.
func _fx_parent() -> Node:
	var scene := get_tree().current_scene
	return scene if scene != null else get_tree().root


func _free_after(node: Node, seconds: float) -> void:
	var timer := get_tree().create_timer(seconds)
	timer.timeout.connect(node.queue_free)
