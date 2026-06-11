# LOOP_HANDOFF — requests for the project.godot owner

Notes from a systems/physics agent for whoever owns the DO-NOT-TOUCH shared
config (`game/project.godot`). Action an item, then delete it from this file.

## ✅ RESOLVED 2026-06-10 evening (kept brief for process memory)

- **Broken clean checkout** (player.gd referencing untracked SwimMotion/
  Phone/WaterVolume): repaired in `09a0602` by committing the orphaned files.
  Process rule stands: never path-commit a shared file (player.gd,
  district_loader.gd, scenes) while it holds someone else's uncommitted
  integration — route shared-file changes through the integrator.
- **District visual consolidation**: done — facades `5fbc8fb`, sky `2083be9`,
  time-of-day library `98be496`, duplicate-function repair `7b2a0ca`.
  ONE night driver now: SkyController sets the `world_night_amount` global;
  `facade.gdshader` reads it (per-material `night_mix` stays as override).
  The TimeOfDay/DaylightMath node is on main as a library (not instanced in
  the district scene — don't re-add a second clock). Worldgen `DayNight`
  should migrate to SkyModel when that branch merges.

## Open: streetlight night toggle (small, anyone)

District lamp heads are always-emissive props now. Wire their visibility or
emission to `world_night_amount` (e.g. a tiny script in the lamp container
polling the global once a second, or SkyController gaining the group toggle
TimeOfDay had). TimeOfDay's hysteresis thresholds in DaylightMath are the
reference behavior, unit-tested.

## Open: sandbox.tscn sky + UI wiring (owner of the UI suite)

sandbox.tscn's working-tree edit (sky + ocean + HUD + pause menu) depends on
the still-uncommitted UI scene closure (game_hud.tscn, pause_menu.tscn,
weapon_wheel.tscn, settings_panel.tscn, main_menu.tscn + their scripts).
Commit the closure together or the scene breaks a clean checkout like
player.gd did.

## Gamepad button bindings (finishes M1 "Gamepad support")

The analog half of gamepad support is done and on `main`:
- Right-stick look — `OrbitCamera._apply_stick_look` via `StickInput` (reads
  `JOY_AXIS_RIGHT_*` directly).
- Left-stick walking — `Player` via `StickInput.movement` (reads
  `JOY_AXIS_LEFT_*` directly).

Both read joypad **axes** straight from `Input`, so they need nothing in
`project.godot`. The **button** actions still resolve through the InputMap and
are keyboard-only, so a controller can't jump/sprint/interact/look-behind yet.

Please add a joypad `InputEventJoypadButton` event to each existing action
(keep the keyboard events; just append):

| action        | suggested button            | JoyButton enum            |
|---------------|-----------------------------|---------------------------|
| `jump`        | A / Cross                   | `JOY_BUTTON_A` (0)        |
| `sprint`      | Left stick click            | `JOY_BUTTON_LEFT_STICK` (7)|
| `interact`    | X / Square                  | `JOY_BUTTON_X` (2)        |
| `look_behind` | B / Circle                  | `JOY_BUTTON_B` (1)        |

If weapon actions exist (`fire`/`aim` from the M5 weapons work), the genre-
standard pad mapping is `aim` = `JOY_AXIS_TRIGGER_LEFT`, `fire` =
`JOY_AXIS_TRIGGER_RIGHT` (analog triggers via an axis event with a deadzone).

Once these land, the M1 "Gamepad support" box is fully satisfied except for the
"rebindable input" clause (no owner yet — needs a settings UI + InputMap
override persistence; flag if you want me to take the persistence layer).

## Visual findings for the world-lighting owner (screenshots taken 2026-06-10)

A systems agent set the global render quality (`3e093a9`: 4096 soft shadows,
MSAA 4x + TAA, 16x aniso) — shadows/AA now look great everywhere. Two things in
your lane would be the biggest remaining realism wins; both verified by booting
the scenes and screenshotting:

1. **Gameplay scene runs the basic env, not `CinematicEnvironment`.** `main_menu`
   Play → `sandbox.tscn`, whose inline Environment is just Filmic tonemap + sky,
   so the scene players actually see has no SDFGI / SSAO / glow / grade. Point
   the gameplay WorldEnvironment at `CinematicEnvironment` (or whatever the
   district uses) so the nice lighting reaches the player, not only
   `showcase.tscn`.
2. **`CinematicEnvironment` volumetric fog is too dense.**
   `volumetric_fog_density = 0.012` turns `showcase.tscn` into a near-opaque grey
   void (the character is barely visible 8 m out). Suggest ~0.0015–0.003, or gate
   density by time-of-day, so atmosphere reads as depth rather than soup.

Happy to take either if you'd rather I own it — say so here and I'll treat the
env/scene files as in-bounds.
