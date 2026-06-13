# LOOP_HANDOFF — requests for the project.godot owner

Notes from a systems/physics agent for whoever owns the DO-NOT-TOUCH shared
config (`game/project.godot`). Action an item, then delete it from this file.

## Offer (world/content agent → world-lighting / env owner): a day/night cycle

I've shipped a lot of NIGHT-optimized world content this session — neon signage
(`NeonSign`, `NeonStrip`, `NeonPylon`), sweeping `Searchlights`, head/tail-lit
`CausewayTraffic` — that only pays off after dark. But a live-scene QA pass
(`coast_scene_capture.gd`, docs/QUALITY.md 2026-06-12 cont.17) confirmed
**miami.tscn is locked to a fixed warm-dusk grade — there is no day/night clock
in the scene** (sky_controller.gd exists but isn't instanced). So all that night
work only reads in isolation captures; in-game it's emissive accents against dusk.

**Offer:** I can add a tasteful day/night cycle that drives the existing scene
Sun + WorldEnvironment at runtime (no new scene nodes, no .tscn edit — a
self-wiring node like `PaySprayShop`, or via FloridaBackdrop) and publishes
`world_night_amount` (which `facade.gdshader` already reads). It would KEEP your
warm-dusk as the golden-hour phase and add dawn/day/night around it.

**Why it's your call, not mine:** the cycle moves the sun angle, which changes
the shadows + the SSR/SSIL bounce you deliberately tuned around the static dusk
("sky-sourced ambient + SSR/SSIL carry the bounce"). I won't override that
autonomously. **Say the word here and I'll build it (behind a default-off flag,
profiled for the 60-FPS target) — it's the single highest-value lighting unlock
left, and it makes the whole night-content layer above actually show in-game.**

**Precise diagnosis (I probed it 2026-06-12 cont.20 so you don't have to):**
the fixed dusk is enforced by THREE independent static pieces in
`miami.tscn`'s WorldEnvironment, none on a clock — a tod cycle must drive ALL
three or the scene stays orange:
  1. **Sun** (`DirectionalLight3D "Sun"`) — `SkyController` already handles this
     (rotation/energy/colour via `SkyModel`) and auto-resolves the node.
  2. **Sky** — it's a `ProceduralSkyMaterial` (`sky_top_color`,
     `sky_horizon_color`, `sky_energy_multiplier`). **`SkyController` does NOT
     drive this** — it drives `sky.gdshader` uniforms, which miami doesn't use.
     So `SkyController` alone leaves the sky bright. Either switch miami's sky to
     `sky.gdshader`, or have the driver also lerp the ProceduralSky colours/energy.
  3. **Fog** — `fog_light_color ≈ (1.0,0.72,0.5)` + `fog_density` + the volumetric
     fog. Over distance/aerial-perspective this orange fog dominates the frame
     (it's what makes far shots read solid orange); it must be driven to a dark
     night tint too.
  Also FWIW: I could not reliably verify night via HEADLESS capture — the dense
  paged scene + fog + FloatingOrigin make framing unreliable (every shot came
  back orange). This is genuinely an in-EDITOR task for you, which is the other
  reason it's yours, not mine.

## Open: a tested systems layer is ready to wire into `miami.tscn`

The loop (gameplay-systems agent) has shipped a deep, fully unit-tested simulation
layer (2386 tests green) that is **reachable in code but not in the live scene**,
because `miami.tscn` + the UI suite (`main_menu.tscn`, `pause_menu.tscn`,
`pause_map_panel.gd`, `ui_palette.gd`) has carried an uncommitted working-tree
integration all session — per the process rule I won't path-commit a shared scene
holding someone else's uncommitted work. **Please commit or revert that UI
integration** and I'll wire the below + add `miami_*_probe`s myself. All catalogued
in `docs/SYSTEMS.md`.

**Trivial wins — 4 self-wiring nodes, each one line in `miami.tscn`, each already
CI-probed (no other change needed):**

| Node | Add to miami.tscn | Effect | Probe |
|---|---|---|---|
| `MarketEventCoordinator` | `[node name="StockMarket" type="Node"]` + script | wanted spike rallies defense stocks; `apply_hit_effect` for hits | `market_event_probe.gd` |
| `CrimeReactionDirector` | one Node | crime → reactive `NewsBulletin` headline + `DistrictEconomy` heat (cools over time) | `crime_reaction_probe.gd` |
| `CharacterSwitcher` | one Node | dual-protagonist wallet sync through `player_stats` | `character_switch_probe.gd` |
| `AmbientEventDirector` | one Node | timer-rolled freeroam encounters (mugging/race/heist) by stars+district | `ambient_event_probe.gd` |

**Models needing a trigger/UI to surface (logic + tests done):** `HitContract`
(assassination board → moves `StockMarket`), `PlayerSkills`, `Disguise` (feeds
`WantedEvasion` speedup), `WeaponLoadout` (around `WeaponBallistics`), `StuntScore`,
`ChopShop` (vehicle resale), `ContactServices` (phone favours), `CharacterRoster`.

I can do all the miami.tscn wiring the moment the scene is clean — commit/revert the
in-flight UI work and delete this note.

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

### Update (a systems agent took these):
- **Finding 2 (fog) — DONE** `27aaa18`: `volumetric_fog_density` 0.012 → 0.002.
- **Finding 1 (route premium lighting to gameplay) — ATTEMPTED, REVERTED on
  perf.** Added a `CinematicEnvironment.enhance(env, include_gi)` that upgrades
  a scene's *own* env in place (keeps its custom day/night sky) and wired
  sandbox via a SkyController `enhance_environment` flag. Screenshot-verified:
  it looked richer (ACES grade + SSAO contact-AO), **but FPS dropped 120 → ~54.
  Isolated it: SDFGI + SSIL are the expensive pair, yet even SSAO+glow+grade
  alone held ~55 FPS** — a ~2× hit for marginal gain on the open sandbox (AO has
  little to bite on flat ground), below the M6 60-FPS target. Reverted rather
  than ship the regression. Recommendation for the lighting owner: this is worth
  it **only in dense scenes (the district)** and **with a measured perf budget**
  — try SSAO-only there, profile, and gate SDFGI/SSIL behind a quality setting.
  The `enhance()` split is the clean hook for it when you do.
