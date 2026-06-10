class_name VehicleAudio
extends Node3D
## Runtime-synthesized engine / tire / impact audio for any vehicle body.
## Attach as a child of a RigidBody3D. Reads the parent loosely (rpm and
## engine_force if they exist, wheel skidinfo on VehicleBody3D) so it never
## couples to a specific vehicle script. All streams are generated in _ready
## from VehicleAudioModel — no audio files in the repo.

const SAMPLE_RATE: int = 22050
## Engine cycle frequency at base_rpm. A 4-stroke fires every other rev per
## cylinder; ~Hz = rpm / 60 * 2 for a 4-cylinder reads convincingly.
const BASE_FREQ: float = 50.0

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

var _engine: AudioStreamPlayer3D
var _skid: AudioStreamPlayer3D
var _impact: AudioStreamPlayer3D
var _prev_velocity: Vector3 = Vector3.ZERO


func _ready() -> void:
	_engine = _make_player(VehicleAudioModel.engine_loop_frames(SAMPLE_RATE, BASE_FREQ), true)
	_skid = _make_player(VehicleAudioModel.noise_loop_frames(SAMPLE_RATE, 0.7, 1234), true)
	_impact = _make_player(VehicleAudioModel.noise_loop_frames(SAMPLE_RATE, 0.25, 99), false)
	_engine.volume_db = VehicleAudioModel.SILENT_DB
	_skid.volume_db = VehicleAudioModel.SILENT_DB
	_engine.play()
	_skid.play()


func _physics_process(_delta: float) -> void:
	var body := get_parent() as RigidBody3D
	if body == null:
		return
	_update_engine(body)
	_update_skid(body)
	_update_impact(body)
	_prev_velocity = body.linear_velocity


func _update_engine(body: RigidBody3D) -> void:
	var rpm := _read_float(body, "rpm", idle_rpm)
	var force := _read_float(body, "engine_force", 0.0)
	var throttle := clampf(absf(force) / full_throttle_force, 0.0, 1.0)
	_engine.pitch_scale = VehicleAudioModel.pitch_for_rpm(rpm, base_rpm)
	_engine.volume_db = VehicleAudioModel.engine_volume_db(throttle, rpm, idle_rpm, redline_rpm)


func _update_skid(body: RigidBody3D) -> void:
	var vehicle := body as VehicleBody3D
	if vehicle == null or vehicle.linear_velocity.length() < min_skid_speed:
		_skid.volume_db = VehicleAudioModel.SILENT_DB
		return
	var worst_grip := 1.0
	for child in vehicle.get_children():
		var wheel := child as VehicleWheel3D
		if wheel != null and wheel.is_in_contact():
			worst_grip = minf(worst_grip, wheel.get_skidinfo())
	_skid.volume_db = VehicleAudioModel.skid_volume_db(1.0 - worst_grip)


func _update_impact(body: RigidBody3D) -> void:
	var dv := (body.linear_velocity - _prev_velocity).length()
	var volume := VehicleAudioModel.impact_volume_db(dv, impact_threshold_dv, impact_full_dv)
	if volume > VehicleAudioModel.SILENT_DB and not _impact.playing:
		_impact.volume_db = volume
		_impact.play()


func _read_float(body: RigidBody3D, property: String, fallback: float) -> float:
	var value: Variant = body.get(property)
	return float(value) if value is float else fallback


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
