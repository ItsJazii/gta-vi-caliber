class_name WeaponStats
extends Resource
## Tunable data for one weapon archetype.
##
## A Resource so designers can author `.tres` variants in the editor, but the
## firing logic that consumes it (Weapon, Ballistics) stays pure and unit-
## tested. Distances are metres, angles radians, times seconds, rates per
## second. The preset factories below are the source of truth for the four
## launch archetypes until balance .tres files exist.

@export var display_name: String = "Weapon"
## Audio class -> assets/audio/weapons/<sound_key>.wav, picked by WeaponAudio.
## Decoupled from display_name so renaming/branding a weapon never mutes it.
@export var sound_key: String = "pistol"
## Held down to keep firing (true) vs one shot per trigger pull (false).
@export var automatic: bool = false
## Rounds per second; the inverse is the per-shot cooldown.
@export var fire_rate: float = 6.0
@export var mag_size: int = 12
## Maximum spare rounds carried outside the magazine.
@export var reserve_max: int = 60
@export var reload_time: float = 1.6
## Damage at or inside damage_falloff_start.
@export var damage: float = 18.0
## Hitscan reach; beyond this a shot hits nothing.
@export var range: float = 120.0
## Damage stays full up to _start, then lerps to damage * min_fraction by _end.
@export var damage_falloff_start: float = 25.0
@export var damage_falloff_end: float = 90.0
@export_range(0.0, 1.0) var min_damage_fraction: float = 0.45
## Cone half-angle (rad) when calm/aiming — the tightest the weapon ever is.
@export var base_spread: float = 0.012
## Added to the cone on each shot (bloom), clamped to max_spread.
@export var spread_per_shot: float = 0.02
@export var max_spread: float = 0.16
## Bloom recovery toward base_spread (rad/s) while not firing.
@export var spread_recovery: float = 0.22
## Projectiles per trigger pull (>1 = shotgun); each gets its own spread sample.
@export var pellets: int = 1
## Upward camera kick (rad) applied per shot.
@export var recoil_kick: float = 0.018


static func pistol() -> WeaponStats:
	var s := WeaponStats.new()
	s.display_name = "Pistol"
	s.sound_key = "pistol"
	s.automatic = false
	s.fire_rate = 5.0
	s.mag_size = 12
	s.reserve_max = 72
	s.reload_time = 1.3
	s.damage = 22.0
	s.range = 90.0
	s.base_spread = 0.010
	s.spread_per_shot = 0.022
	s.max_spread = 0.12
	s.spread_recovery = 0.30
	s.recoil_kick = 0.020
	return s


static func smg() -> WeaponStats:
	var s := WeaponStats.new()
	s.display_name = "SMG"
	s.sound_key = "smg"
	s.automatic = true
	s.fire_rate = 13.0
	s.mag_size = 30
	s.reserve_max = 180
	s.reload_time = 1.8
	s.damage = 14.0
	s.range = 80.0
	s.base_spread = 0.018
	s.spread_per_shot = 0.016
	s.max_spread = 0.17
	s.spread_recovery = 0.22
	s.recoil_kick = 0.012
	return s


static func rifle() -> WeaponStats:
	var s := WeaponStats.new()
	s.display_name = "Rifle"
	s.sound_key = "rifle"
	s.automatic = true
	s.fire_rate = 9.0
	s.mag_size = 30
	s.reserve_max = 150
	s.reload_time = 2.1
	s.damage = 26.0
	s.range = 160.0
	s.base_spread = 0.008
	s.spread_per_shot = 0.018
	s.max_spread = 0.15
	s.spread_recovery = 0.26
	s.recoil_kick = 0.022
	return s


static func shotgun() -> WeaponStats:
	var s := WeaponStats.new()
	s.display_name = "Shotgun"
	s.sound_key = "shotgun"
	s.automatic = false
	s.fire_rate = 1.6
	s.mag_size = 6
	s.reserve_max = 36
	s.reload_time = 2.6
	s.damage = 9.0
	s.range = 45.0
	s.damage_falloff_start = 8.0
	s.damage_falloff_end = 30.0
	s.min_damage_fraction = 0.2
	s.base_spread = 0.08
	s.spread_per_shot = 0.0
	s.max_spread = 0.08
	s.spread_recovery = 0.5
	s.pellets = 9
	s.recoil_kick = 0.045
	return s
