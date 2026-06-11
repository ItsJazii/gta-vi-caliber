class_name OceanMath
extends RefCounted
## Pure Gerstner-wave math for the M4 ocean (CPU side).
##
## CONTRACT: the wave table and formulas below are mirrored verbatim in
## game/shaders/ocean.gdshader (GPU side). Edit BOTH files together or
## buoyancy will float boats above/below the rendered surface.
## test_ocean_math.gd parses the shader source and fails if the constants
## drift apart.
##
## Model (GPU Gems ch. 1, "Effective Water Simulation"): each wave displaces
## a grid point horizontally toward the crest and vertically by a sine,
## producing sharp crests and wide troughs. Phase speed follows the deep
## water dispersion relation omega = sqrt(g * k).

const GRAVITY: float = 9.8
const WAVE_COUNT: int = 5

## Direction of travel per wave, radians around +Y (0 == +X).
const WAVE_ANGLES: Array[float] = [0.3, 1.1, -0.6, 2.6, -1.9]
## Crest-to-crest length per wave, metres.
const WAVE_LENGTHS: Array[float] = [42.0, 19.0, 9.0, 5.0, 3.0]
## Half crest-to-trough height per wave, metres.
const WAVE_AMPLITUDES: Array[float] = [0.6, 0.26, 0.12, 0.05, 0.02]
## 0 = pure sine, 1 = sharpest stable crest (keep k*A*Q <= 1 per wave).
const WAVE_STEEPNESS: Array[float] = [0.6, 0.8, 0.9, 1.0, 1.0]

## Fixed-point iterations used to invert the horizontal displacement when
## sampling the surface at a fixed world position (buoyancy queries).
const INVERT_ITERATIONS: int = 3


## Displacement of the grid point that starts (undisplaced) at `param`,
## in metres: x/z lean toward the crest, y is the surface height.
## Mirrors gerstner_offset() in the shader exactly.
static func displacement(param: Vector2, time: float, amp_scale: float = 1.0) -> Vector3:
	var offset := Vector3.ZERO
	for i in WAVE_COUNT:
		var k := TAU / WAVE_LENGTHS[i]
		var amp: float = WAVE_AMPLITUDES[i] * amp_scale
		var direction := Vector2(cos(WAVE_ANGLES[i]), sin(WAVE_ANGLES[i]))
		var omega := sqrt(GRAVITY * k)
		var phase := k * direction.dot(param) - omega * time
		offset.x += WAVE_STEEPNESS[i] * amp * direction.x * cos(phase)
		offset.z += WAVE_STEEPNESS[i] * amp * direction.y * cos(phase)
		offset.y += amp * sin(phase)
	return offset


## Analytic surface normal at grid parameter `param` (GPU Gems eq. 12).
## Mirrors gerstner_normal() in the shader exactly.
static func surface_normal(param: Vector2, time: float, amp_scale: float = 1.0) -> Vector3:
	var normal := Vector3.UP
	for i in WAVE_COUNT:
		var k := TAU / WAVE_LENGTHS[i]
		var amp: float = WAVE_AMPLITUDES[i] * amp_scale
		var direction := Vector2(cos(WAVE_ANGLES[i]), sin(WAVE_ANGLES[i]))
		var omega := sqrt(GRAVITY * k)
		var phase := k * direction.dot(param) - omega * time
		normal.x -= direction.x * k * amp * cos(phase)
		normal.z -= direction.y * k * amp * cos(phase)
		normal.y -= WAVE_STEEPNESS[i] * k * amp * sin(phase)
	return normal.normalized()


## Surface height (relative to the resting plane) at a fixed world-space
## xz position. Gerstner waves displace points horizontally, so the grid
## parameter whose displaced position lands on `world_xz` is found by
## fixed-point iteration before sampling the height there.
static func wave_height_at(world_xz: Vector2, time: float, amp_scale: float = 1.0) -> float:
	var param := world_xz
	for _i in INVERT_ITERATIONS:
		var d := displacement(param, time, amp_scale)
		param = world_xz - Vector2(d.x, d.z)
	return displacement(param, time, amp_scale).y


## Upper bound on |height|: the sum of all amplitudes.
static func max_height(amp_scale: float = 1.0) -> float:
	var total := 0.0
	for amp in WAVE_AMPLITUDES:
		total += amp
	return total * amp_scale
