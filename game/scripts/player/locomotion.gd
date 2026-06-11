class_name Locomotion
extends RefCounted
## Pure locomotion-animation math for the character.
##
## Static functions only, no scene access (docs/ARCHITECTURE.md). Turns raw
## motion (planar speed, grounded flag, vertical velocity) into an animation
## state plus the procedural parameters a greybox rig needs to *look* like it
## is walking: a 1D move blend, a stride phase that advances with distance, and
## the limb-swing / vertical-bob / lean derived from it. Covered by
## tests/unit/test_locomotion.gd.

enum State { IDLE, WALK, RUN, JUMP, FALL, CLIMB }

## Below this planar speed (m/s) the character is considered standing still.
const IDLE_SPEED_EPSILON: float = 0.15
## Stride cycles per metre travelled at a walk; scaled up toward a run so feet
## visibly quicken with speed rather than sliding. Tuned for a 1.8 m capsule.
const STRIDE_CYCLES_PER_METRE: float = 0.45


## Classify the current motion. Climbing and airborne states take priority over
## ground locomotion; on the ground the planar speed picks idle/walk/run with a
## small tolerance band around walk_speed so a steady walk doesn't flicker into
## run on minor overshoot.
static func state_for(
	planar_speed: float,
	on_floor: bool,
	vertical_velocity: float,
	is_climbing: bool,
	walk_speed: float,
	run_speed: float
) -> State:
	if is_climbing:
		return State.CLIMB
	if not on_floor:
		return State.JUMP if vertical_velocity > 0.0 else State.FALL
	if planar_speed < IDLE_SPEED_EPSILON:
		return State.IDLE
	var run_gate: float = lerpf(walk_speed, run_speed, 0.5)
	return State.RUN if planar_speed > run_gate else State.WALK


## Position on a 1D idle→walk→run blend axis: 0.0 standing, 0.5 at walk_speed,
## 1.0 at run_speed, linear and clamped between. This is the value you feed a
## Godot AnimationTree BlendSpace1D once real clips exist; today it also scales
## the procedural swing amplitude.
static func move_blend(planar_speed: float, walk_speed: float, run_speed: float) -> float:
	if planar_speed <= 0.0:
		return 0.0
	if planar_speed <= walk_speed:
		return 0.5 * (planar_speed / walk_speed)
	if planar_speed >= run_speed:
		return 1.0
	var t: float = (planar_speed - walk_speed) / (run_speed - walk_speed)
	return 0.5 + 0.5 * t


## Advance the stride phase (radians, wrapped to TAU). Phase accumulates with
## distance travelled — not raw time — so steps stay locked to the ground at any
## speed and the character never moonwalks. One full TAU cycle = a left+right
## stride pair.
static func advance_phase(phase: float, planar_speed: float, delta: float) -> float:
	var advance: float = planar_speed * delta * STRIDE_CYCLES_PER_METRE * TAU
	return fposmod(phase + advance, TAU)


## Swing angle (radians) for a limb at the given stride phase. The opposite
## limb in a pair passes phase + PI so arms/legs counter-swing. Amplitude is
## the peak angle; pass it pre-scaled by move_blend so a slow walk swings less
## than a sprint.
static func limb_swing(phase: float, amplitude: float) -> float:
	return sin(phase) * amplitude


## Vertical bob (metres) of the torso. The body rises on each foot plant, so it
## oscillates at twice the stride frequency; abs() keeps it a downward dip from
## the rest pose rather than sinking below the feet.
static func vertical_bob(phase: float, amplitude: float) -> float:
	return -absf(sin(phase)) * amplitude


## Small side-to-side pelvis travel that follows the planted foot. This is not
## root motion; it is only a visual offset on the rig so the upper body carries
## weight over each step instead of moving like a sliding capsule.
static func lateral_sway(phase: float, amplitude: float) -> float:
	return sin(phase) * amplitude


## Roll the pelvis opposite the planted side. Kept subtle: this sells weight
## transfer without turning the character into a cartoon walk cycle.
static func pelvis_roll(phase: float, amplitude: float) -> float:
	return -sin(phase) * amplitude


## Counter-roll shoulders against the pelvis so fast movement has athletic
## compression instead of a rigid upright torso.
static func shoulder_counter_roll(phase: float, amplitude: float) -> float:
	return sin(phase) * amplitude


## Yaw the upper body against the stepping leg. This gives a procedural rig the
## cross-body twist of a real gait instead of a rigid shoulders-square walk.
static func torso_twist(phase: float, amplitude: float) -> float:
	return -sin(phase) * amplitude


## Tiny head pitch on each step: the neck absorbs body bob so the face stays
## alive without nodding like a metronome.
static func head_step_pitch(phase: float, amplitude: float) -> float:
	return -absf(sin(phase)) * amplitude


## Counter-roll the head against the pelvis/shoulders. This keeps the eyeline
## calmer while the torso carries weight from side to side.
static func head_counter_roll(phase: float, amplitude: float) -> float:
	return -sin(phase) * amplitude


## Forward lean (radians) into acceleration: lean grows with how hard speed is
## changing, clamped to max_lean, so the body pitches forward when breaking into
## a run and rocks back when braking. accel is signed planar acceleration.
static func lean_angle(accel: float, accel_reference: float, max_lean: float) -> float:
	if accel_reference <= 0.0:
		return 0.0
	return clampf(accel / accel_reference, -1.0, 1.0) * max_lean


# --- Articulated gait: two-bone limb flexion ---------------------------------
# These turn the single-segment swing into a believable two-bone limb. All
# angles are radians on a normalised walk cycle where a leg's hip swing is
# sin(phase): the foot is planted through stance (phase 0..PI) and swings
# through the air (phase PI..TAU), so the knee flexes mainly during swing. The
# animator scales amplitudes by the move blend so a slow walk bends less than a
# sprint. Covered by tests/unit/test_gait_kinematics.gd.


## Knee flexion magnitude (always >= 0 — a knee only folds one way). One dominant
## bend as the leg lifts and swings through, peaking near phase = 3*PI/2, plus a
## small constant load-bearing flex so a planted leg never locks robotically.
static func knee_flex(phase: float, amplitude: float, stance_flex: float = 0.12) -> float:
	var swing: float = maxf(0.0, -sin(phase))  # positive only through swing
	return stance_flex + amplitude * pow(swing, 1.3)


## Ankle pitch (signed): toe lifts (dorsiflexion) approaching heel-strike and
## points (plantarflexion) through toe-off, a quarter-cycle ahead of the hip, so
## the sole stays roughly level across the step instead of skating flat.
static func ankle_pitch(phase: float, amplitude: float) -> float:
	return sin(phase + PI * 0.5) * amplitude


## Elbow flexion for a swinging arm (always >= 0). Arms carry a relaxed constant
## bend that deepens a touch as the arm drives forward, so they read as arms and
## not straight planks. arm_phase is the arm's stride phase (the legs' + PI).
static func elbow_flex(arm_phase: float, amplitude: float, base_bend: float = 0.35) -> float:
	return base_bend + amplitude * maxf(0.0, sin(arm_phase))


## Knee flex from the thigh's current normalised swing (hip_angle / hip_amp)
## instead of the phase clock. Identical to knee_flex because -sin(phase) is just
## the normalised backward swing, but it lets an articulation driver read the
## live hip rotation and stay perfectly in lockstep with the hip — no second
## phase to drift out of sync. swing_norm is clamped to [-1, 1] by the caller.
static func knee_flex_from_swing(
	swing_norm: float, amplitude: float, stance_flex: float = 0.12
) -> float:
	return stance_flex + amplitude * pow(maxf(0.0, -swing_norm), 1.3)


## Elbow flex from the upper arm's current normalised swing (shoulder_angle /
## arm_amp), the arm counterpart of knee_flex_from_swing. Forward drive
## (swing_norm > 0) deepens the bend; never straightens past base_bend.
static func elbow_flex_from_swing(
	swing_norm: float, amplitude: float, base_bend: float = 0.35
) -> float:
	return base_bend + amplitude * maxf(0.0, swing_norm)
