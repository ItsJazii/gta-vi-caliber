class_name VehicleAudio
extends Node3D
## Runtime-synthesized engine / exhaust / tire / impact audio for any vehicle body.
## Attach as a child of a RigidBody3D. Reads the parent loosely (rpm, gear, and
## engine_force if they exist, drift_amount for the handbrake screech, wheel
## skidinfo on a VehicleBody3D) so it never couples to a specific vehicle script.
## All streams are generated in _ready from VehicleAudioModel — no audio files in
## the repo.

const SAMPLE_RATE: int = 22050
## Engine cycle frequency at base_rpm. A 4-stroke fires every other rev per
## cylinder; ~Hz = rpm / 60 * 2 for a 4-cylinder reads convincingly.
const BASE_FREQ: float = 50.0
## No active gear-shift dip while the timer sits above shift_recover_sec.
const NO_SHIFT: float = 999.0

## RPM the synthesized loop represents; playback pitch scales from here.
@export var base_rpm: float = 1500.0
@export var idle_rpm: float = 850.0
@export var redline_rpm: float = 6500.0
## engine_force magnitude treated as full throttle when inferring loudness.
@export var full_throttle_force: float = 3000.0
## Velocity jump (m/s) where impact sound starts / saturates.
@export var impact_threshold_dv: float = 6.0
@export var impact_full_dv: float = 20.0
## Tire noise needs some road speed — no screech while bogged at a standstill.
@export var min_skid_speed: float = 3.0
## Engine/exhaust volume cut (dB) at a gear change, easing back over the recover.
@export var shift_dip_db: float = -9.0
@export var shift_recover_sec: float = 0.28

var _engine: AudioStreamPlayer3D
var _exhaust: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _prev_velocity: Vector3 = Vector3.ZERO
var _prev_gear: int = 1
## Seconds since the last gear change; NO_SHIFT means no dip is in progress.
var _shift_time: float = NO_SHIFT


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		set_physics_process(false)
		return
	_engine = _make_player(VehicleAudioModel.engine_loop_frames(SAMPLE_RATE, BASE_FREQ), true)
	_exhaust = _make_player(VehicleAudioModel.exhaust_loop_frames(SAMPLE_RATE, BASE_FREQ), true)
	_skid = _make_player(VehicleAudioModel.noise_loop_frames(SAMPLE_RATE, 0.7, 1234), true)
	_impact = _make_player(VehicleAudioModel.crash_loop_frames(SAMPLE_RATE, 0.3, 99), false)
	_engine.volume_db = VehicleAudioModel.SILENT_DB
	_exhaust.volume_db = VehicleAudioModel.SILENT_DB
	_skid.volume_db = VehicleAudioModel.SILENT_DB
	_engine.play()
	_exhaust.play()
	_skid.play()


func _exit_tree() -> void:
	for player in [_engine, _exhaust, _skid, _impact]:
		if player != null:
			player.stop()
			player.stream = null


func _physics_process(delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	_update_engine(body, delta)
	_update_skid(body)
	_update_impact(body)
	_prev_velocity = body.linear_velocity


func _update_engine(body: RigidBody3D, delta: float) -> void:
	var rpm := _read_float(body, "rpm", idle_rpm)
	var gear := _read_int(body, "gear", _prev_gear)
	var force := _read_float(body, "engine_force", 0.0)
	var throttle := clampf(absf(force) / full_throttle_force, 0.0, 1.0)
	if gear != _prev_gear:
		_shift_time = 0.0
		_prev_gear = gear
	var dip := 0.0
	if _shift_time < shift_recover_sec:
		dip = VehicleAudioModel.shift_dip_db(_shift_time, shift_dip_db, shift_recover_sec)
		_shift_time += delta
	var pitch := VehicleAudioModel.pitch_for_rpm(rpm, base_rpm)
	_engine.pitch_scale = pitch
	_engine.volume_db = (
		VehicleAudioModel.engine_volume_db(throttle, rpm, idle_rpm, redline_rpm) + dip
	)
	_exhaust.pitch_scale = pitch
	_exhaust.volume_db = (
		VehicleAudioModel.exhaust_volume_db(throttle, rpm, idle_rpm, redline_rpm) + dip
	)


func _update_skid(body: RigidBody3D) -> void:
	if body.linear_velocity.length() < min_skid_speed:
		_skid.volume_db = VehicleAudioModel.SILENT_DB
		return
	var slip := _worst_wheel_slip(body as VehicleBody3D)
	var drift := clampf(_read_float(body, "drift_amount", 0.0), 0.0, 1.0)
	_skid.volume_db = VehicleAudioModel.tire_mix_db(slip, drift)
	_skid.pitch_scale = VehicleAudioModel.skid_pitch_scale(maxf(slip, drift))


func _update_impact(body: RigidBody3D) -> void:
	var dv := (body.linear_velocity - _prev_velocity).length()
	var volume := VehicleAudioModel.impact_volume_db(dv, impact_threshold_dv, impact_full_dv)
	if volume > VehicleAudioModel.SILENT_DB and not _impact.playing:
		_impact.volume_db = volume
		_impact.pitch_scale = VehicleAudioModel.impact_pitch_scale(
			dv, impact_threshold_dv, impact_full_dv
		)
		_impact.play()


## Worst (1 - skidinfo) across the body's grounded wheels, 0 when not a
## VehicleBody3D or no wheel is in contact.
func _worst_wheel_slip(vehicle: VehicleBody3D) -> float:
	if vehicle == null:
		return 0.0
	var worst_grip := 1.0
	for child in vehicle.get_children():
		var wheel := child as VehicleWheel3D
		if wheel != null and wheel.is_in_contact():
			worst_grip = minf(worst_grip, wheel.get_skidinfo())
	return 1.0 - worst_grip


func _read_float(body: RigidBody3D, property: String, fallback: float) -> float:
	var value: Variant = body.get(property)
	return float(value) if (value is float or value is int) else fallback


func _read_int(body: RigidBody3D, property: String, fallback: int) -> int:
	var value: Variant = body.get(property)
	return int(value) if (value is int or value is float) else fallback


func _make_player(frames: PackedFloat32Array, looped: bool) -> AudioStreamPlayer3D:
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = SAMPLE_RATE
	wav.stereo = false
	wav.data = VehicleAudioModel.frames_to_wav16(frames)
	if looped:
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_end = frames.size()
	var player := AudioStreamPlayer3D.new()
	player.stream = wav
	player.unit_size = 8.0
	add_child(player)
	return player
