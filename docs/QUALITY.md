# Quality ledger — state vs the trailer bar

Dated, honest assessments of where the build stands against the VISION.md
bar (trailer-fidelity coastal open world). Updated by whoever runs a
playtest/capture pass; newest entry first. Captures referenced live in
`/tmp/gta6_playtest/` locally — judge from a fresh run, not memory.

## 2026-06-11 — Venice dolly: dusk sprawl achieved, beach framing open

beauty_capture now takes BEAUTY_CENTER (world recenters via FloatingOrigin
when spawning 21 km out — Venice lands at ≈(-58,-12), so default center
films it). Dusk stills: dense low-rise sprawl to the horizon, thousands of
hashed lit windows, heavy sunset cloud deck — striking, but the postcard
needs a west-facing shoreline frame (ocean+sand are behind the dolly) and
less cloud. M3 streaming landed fleet-side (b3d633c), so the 18-district
world pages around the player now.

## 2026-06-10 (night) — coastal district lands; world goes multi-district

Venice Beach scene on main: real-shoreline sand + Ocean v1 + golden-hour
sky over 1332 footprints (M4 coastal box ticked). The worldgen merge made
the world 18 districts / 24,846 buildings on one shared projection origin;
npc-life brought citizens; gate now runs 955 tests over 5 smoke scenes.
Probe shot at dusk reads warm and inhabited (lit windows, sidewalk streets).
Postcard remaining: a Venice beauty dolly (beauty_capture waypoints are
downtown-hardcoded), ocean foam (v2), and the district-scoped GI pass the
lighting owner has under measurement.

## 2026-06-10 (evening) — district visual integration

Integrated in one pass: procedural façades (window grids, per-building
worn-stucco palette), asphalt/lane-line road shader, physically-shaded sky
(rayleigh/mie/clouds/stars), rooftop props, street trees + furniture,
ambient traffic, crowds. Beauty stills now show a believable hazy downtown
with varied towers and marked streets. One night driver consolidated:
SkyController's `world_night_amount` global feeds the façade `night_mix`.

Verified end-to-end after integration (740 unit tests; playtest OK; 5 km
origin shift drift 0.00 m). Two incidents worth remembering: a cherry-pick
textually merged a duplicate function and the district silently built
nothing while smoke stayed green (smoke now asserts the Roads node); and
main shipped references to never-committed files (repaired, see
LOOP_HANDOFF process note).

Updated verdicts: **Materials Far → Mid-High** (washed-out highlights at
noon remain), **City geometry Mid → Mid-High** (sidewalk bands, props,
trees landed), **Lighting Mid** (golden-hour pass still pending GI).
Next leverage: street-level polish + GI/volumetrics at golden hour, then
the coastal district to combine with Ocean v1 for the postcard shot.

## 2026-06-10 — first full-loop assessment

Verified playable end-to-end by automated headed playtest
(`game/tests/playtest_capture.gd`): walk → enter car → drive 20 m/s with
rising engine note → exit → district load → 5 km floating-origin shift with
0.00 m drift. 439 unit tests green; native WorldCore module loading.

| Dimension | State | Bar | Verdict |
| --- | --- | --- | --- |
| Locomotion/feel | Coyote time, jump buffer, analog gait, camera probe | Fluid traversal | **Near** (no anims for jump/land yet) |
| Vehicles | Torque-curve powertrain, traction circle, weight transfer, damage, audio | Convincing handling | **Near** (greybox bodies) |
| Character | Procedural humanoid v2: tapered limbs, hair, palette variety | Trailer humans | **Far** (no faces, no real anim set) |
| City geometry | 199 real-footprint towers, 901 road ribbons | Dense believable city | **Mid** (no sidewalks/props/foliage) |
| Materials | Untextured slabs; façade shader in flight | Worn stucco/concrete/glass | **Far → Mid** once façades land |
| Lighting/time | ToD cycle in flight: dusk + lit-window night shots already read | Golden hour money shots | **Mid** |
| Water | Gerstner ocean v1: turquoise shallows, sun glitter, sandbars | Postcard coast | **Mid** (no foam/SSR — v2) |
| Life | ~20 wandering pedestrians, police pursuit, wanted stars | Crowded streets, traffic | **Far** (no vehicles traffic, thin density) |
| Audio | Procedural engine/tire/impact/footsteps | Full soundscape | **Mid** (no ambience/music/radio) |
| Play | Weapons loop, health/armor, wanted, missions WIP | "It's a game" | **Mid** |

**Highest-leverage gaps, in order** (each maps to a roadmap box):
1. **Traffic + parked cars** (M4 road graph) — empty streets break the
   fantasy harder than any material does.
2. **Street furniture + foliage pass** — palms, signs, awnings; the OSM data
   has road classes to seed placement. (M4 blockout box.)
3. **Coastal district** — the bar is a *coast*: the ocean v1 + a shoreline
   district together produce the postcard shot. (M4 blockout box.)
4. **Character animation set** — run/idle/jump on the procedural rig (M1).
5. **GI/volumetrics pass at golden hour** (M6 lighting) — cheap to try with
   SDFGI now that ToD exists; do after materials so bounce has color to work
   with.

**Process note:** all three sun/clock systems being built in parallel
(SkyController in sandbox, DaylightMath/TimeOfDay in the district, DayNight
on feat/osm-worldgen) need consolidation into one — see ROADMAP M4 box;
don't add a fourth.
