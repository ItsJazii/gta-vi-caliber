# Roadmap

The path from empty repo to trailer-grade open world, as shippable milestones.
**Every unchecked box is an invitation** — comment on or open an issue before
starting so work isn't duplicated. Boxes only get checked when the feature is
on `main`, passing CI, and playable.

Maintainers also point autonomous agent loops at this file: editing it is how
humans steer the machines. Keep tasks small, concrete, and verifiable.

---

## M0 — Bootstrap ✅ (current)

Goal: every clone runs instantly; contribution pipeline works end to end.

- [x] Repo structure, licenses, contribution docs, agent contract
- [x] Godot 4.6 project with playable sandbox (ground, sky, sun)
- [x] Third-person character: walk, sprint, jump, mouse-look camera
- [x] `tools/check.sh` local gate = CI (format, lint, import, smoke, unit tests)
- [x] GitHub Actions CI, issue templates, PR template
- [ ] Vendor [gdUnit4](https://github.com/MikeSchulze/gdUnit4) into `game/addons/` and port the unit-test runner to it
- [x] First exported build artifacts (Linux/Windows/macOS) uploaded by CI on tag

## M1 — Locomotion & camera feel

Goal: moving around is *fun* before there is anything to do.

- [ ] Character model + run/walk/idle/jump animations (original or CC0; see `art` issues)
- [x] Acceleration/deceleration curves, air control, coyote time (+ jump buffering)
- [x] Camera: collision probe, shoulder offset, FOV kick on sprint
- [x] Footstep audio hooked to surface type
- [x] Greybox "movement playground" scene with stairs, slopes, gaps, ladders
- [ ] Gamepad support + rebindable input

## M2 — Vehicles

Goal: get in a car, drive it, crash it, get out.

- [x] `VehicleBody3D`-based car with tuned suspension (greybox body)
- [x] Seamless enter/exit interaction
- [x] Chase camera with speed-based FOV and look-behind
- [x] Engine/tire/impact audio loops
- [x] Damage model v1 (visual deformation can wait; mechanical state first)
- [x] Motorbike + boat prototypes

## M3 — Streaming world foundation *(engine track begins)*

Goal: walk or drive 4 km in any direction with no loading screen.

- [ ] World partitioned into tiles with seam-free LOD terrain
- [ ] **`engine/`: async tile streamer GDExtension** (load/unload around camera, priority by velocity vector)
- [ ] **`engine/`: runtime impostor baker** for distant buildings
- [x] Floating-origin shift to dodge float precision at distance
- [ ] Streaming debug HUD (tiles resident, VRAM, frame budget)
- [ ] Benchmark scene + captured profile checked into `docs/profiles/`

## M4 — A living district

Goal: one city district that feels inhabited.

- [ ] Blockout of a coastal district: streets, sidewalks, shore, 30+ building footprints
- [ ] Road network graph + traffic system (**`engine/` candidate after profiling**)
- [ ] Pedestrian crowds: navmesh flows, reactions (flee/gawk), spawn/despawn invisible to player
- [ ] Time-of-day cycle driving sun, streetlights, building windows
- [ ] Weather fronts: clear → overcast → rain, wet-surface materials
- [ ] Ocean v1: Gerstner/FFT water with shoreline blend (**`engine/` candidate**)

## M5 — Play

Goal: it is a *game* now.

- [ ] Mission framework (triggers, objectives, fail/retry) + 3 sample missions
- [ ] Wanted/heat system with police response escalation
- [ ] Minimap + full map UI
- [ ] Radio: streaming music channels in vehicles (CC-licensed tracks)
- [ ] Save/load of world + player state
- [ ] NPC dialogue barks

## M6 — Trailer-grade polish

Goal: the acceptance test — a 90-second in-engine trailer from a release build.

- [ ] Lighting pass: GI (SDFGI/HDDAGI tuning or `engine/` solution), volumetrics
- [ ] Ocean v2: foam, wakes, buoyancy
- [ ] Crowd density pass (**`engine/`: GPU-driven crowd rendering**)
- [ ] Cinematic camera tooling for capture
- [ ] Performance lockdown: 60 FPS @ 1080p mid-range GPU, captured profiles
- [ ] Cut, score, and publish the trailer

---

## Engine track (parallel, ongoing)

Lives in `engine/`; rules in [ARCHITECTURE.md](ARCHITECTURE.md). Anything
generically useful is offered upstream to Godot.

- [ ] godot-cpp vendored as submodule + first compiled module on all 3 platforms
- [ ] CI job building `engine/` and running its C++ tests
- [ ] Streaming module (M3)
- [ ] Impostor baker (M3)
- [ ] Crowd/traffic simulation core (M4+, only with profile evidence)
- [ ] Ocean simulation (M4+)
- [ ] Upstream PR log in `docs/UPSTREAM.md` (create with first PR)
