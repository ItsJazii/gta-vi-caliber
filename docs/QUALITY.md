# Quality ledger — state vs the trailer bar

Dated, honest assessments of where the build stands against the VISION.md
bar (trailer-fidelity coastal open world). Updated by whoever runs a
playtest/capture pass; newest entry first. Captures referenced live in
`/tmp/gta6_playtest/` locally — judge from a fresh run, not memory.

## 2026-06-12 (cont. 12) — neon: the Vice City night signature

Track Q (lighting/atmosphere — finally a *night* pass, reached without touching
the shared env). Added `NeonSign`: a glowing gateway at the pier approach — a
dark hoarding on posts, framed by emissive "neon tube" borders, hot-pink
"VICE BEACH" headline over a cyan "· THE PIER ·" tagline. Pure emissive, so it
carries itself at night and blooms where glow is on — no dependency on the
locked WorldEnvironment. The best-looking element yet (`/tmp/neon.png` — reads
exactly as a real neon sign). Added via FloridaBackdrop near the pier; verified
in a NIGHT isolation capture (dark env + glow) + 4 unit tests. This is the first
toe into the iconic Vice City neon-night aesthetic; a full night pass (neon
storefronts, boardwalk strips, reflections) is the natural follow-on — most of
it still wants the env owner for the grade/glow, but standalone emissive signage
like this is reachable in-lane.

## 2026-06-12 (cont. 11) — pastel lifeguard stands: the Vice City motif

Track Q (detail/landmark). Added `LifeguardTowers`: a row of the candy-coloured
Art-Deco lifeguard stands of Miami Beach — one of Vice City's most photographed
motifs. Each is a stilted hut (four timber legs, white-trim deck, open-front
booth in a cycled pastel — flamingo pink / teal / sun yellow / coral / mint /
sky blue, peaked red-stripe roof, red flag, back ladder) facing the water. Reads
exactly as the real thing (`/tmp/towers.png`). 8 stands; added along the shore
via FloridaBackdrop, verified in isolation + 4 unit tests (count, full-structure,
spread, idempotent). Honest limit: box-built (no rounded Deco curves), and
placed on a curated shore line rather than tied to the actual sand-vs-water edge.

## 2026-06-12 (cont. 10) — the fishing pier: the postcard's other half

Track Q (detail/landmark) — closes the rest of the ledger's "palms/pier" note
(palms shipped in cont. 6). Added `Pier`: a recreational fishing pier reaching
off the bay-facing shore over the water — weathered boardwalk deck on regular
pilings (which drop below the waterline), railings with posts down both sides,
warm self-lit lamp posts, and a widened observation platform at the sea end.
A *built landmark*, distinct from all the scattered ambient work, and the
strongest single coastal foreground yet (`/tmp/pier.png`). Added via
FloridaBackdrop; verified in isolation over the real Ocean + 4 unit tests.
Process note: detached duplicate-named nodes auto-rename to the `@Name@N` form
(not `Name2`), so `==`/`begins_with` name-matching in tests is unreliable —
grouped pilings/lamps under container nodes instead (cleaner tree too). Honest
limit: one curated pier; a denser coast would want a few marinas/docks tied to
the road graph.

## 2026-06-12 (cont. 9) — satirical billboards: the city gets an opinion

Track Q (humor/tone + detail/density), extending the satire axis the banner
plane opened. Added `Billboards`: a row of posted, framed roadside hoardings
along the bay-facing shore, each a real billboard structure (two posts + frame +
a faintly self-illuminated panel so it reads lit day or night) carrying original
parody copy ("LIBERTY LOANS / 0% APR* (*NOT REAL)", "COUGAR ENERGY DRINK /
LEGALLY A BEVERAGE", "VICE BEACH CONDOS / NOW WITH FLOORS", …). Reads exactly as
a GTA hoarding (`/tmp/billboard.png` — structure + legible two-line ad). 9
boards, alternating facing so both bay and shore sides get ads; added via
FloridaBackdrop, verified in isolation + 4 unit tests (count, every-board-has-an-
ad, spread, idempotent). Honest limit: a fixed 8-ad pool on a curated shore line
— a full tone pass (Track N) would scatter ads across districts and tie copy to
the economy/news.

## 2026-06-12 (cont. 8) — the beach banner plane (life + the first joke)

Track Q on TWO axes at once — ambient life *and* humor/tone (the satire axis,
previously untouched). Added `AirBanner`: the iconic Miami banner-tow plane,
a light aircraft circling the beach dragging a satirical ad banner (white
Label3D text on a hot-pink sheet, swaying on its tow point). Original parody
copy, rotated per plane ("SUNBURN INSURANCE — CLAIM BY DUSK", "VICE BEACH P.D.:
SMILE, YOU'RE ON CAMERA", …) — nothing lifted from any real product. Pure
time-driven circular flight; built in populate() for headless tests. Reads
exactly as intended (`/tmp/banner_close.png` — the ad is legible and correctly
oriented). Added over South Beach via FloridaBackdrop; verified in isolation +
4 unit tests (count, circling, tows-a-banner, carries-an-ad). Process note: the
PlaneMesh banner needed a z-only 90° rotation (an extra x-rotation first made it
edge-on), and radius-0 still leaves a random heading, so the isolation cam pins
the plane transform to read the banner broadside. Honest limit: it's one
decorative orbit, and the ad pool is 5 lines — a real tone pass would tie ads to
districts/events with Track N.

## 2026-06-12 (cont. 7) — gulls in the sky: ambient life, not just scenery

Track Q (detail/life), a deliberate diversification — the backdrop had grown
rich in *static* scenery (water, ground, trees, clouds, boats, palms) but the
only motion was the drifting boats. Added `SeabirdFlock`: ~26 gulls that each
circle a slowly drifting flock centre at their own radius/altitude/phase, bank
into the turn, and flap (a hinged wing pivot driven by a sine). Pure time-math
motion, no per-frame allocation. Reads as real gulls — swept silhouettes up
close, specks at distance (`/tmp/birds.png`). Added over the bay via
FloridaBackdrop; verified in isolation + 4 functional unit tests (count,
altitude band, drift, wing-flap). Honest limit: box-built wings (fine at gull
scale/distance, not a hero close-up bird), and the flight is decorative orbits,
not true boids flocking.

## 2026-06-12 (cont. 6) — the shore gets its palms (named ledger gap)

Track Q (detail/set-dressing) — closes a gap the ledger named outright back in
the postcard work: "needs boardwalk-scale foreground props (palms/pier)." The
miami coastline was bare tan sand; the only palm row (`BeachProps`) belonged to
the unused Venice scene. Added `CoastalPalms`: walks FloridaMapModel's coast
outline at 27 m spacing, offsets each palm inland of the waterline, and renders
trunk + frond MultiMeshes (reusing the proven `PalmMesh`). 444 palms now fringe
the playable bay/beach span — the iconic Vice City shore silhouette that frames
the establishing shots (`/tmp/palms.png`). 2 draw calls; added via FloridaBackdrop.

Verified in isolation + 4 unit tests. Method note: backdrop children CANNOT be
framed in the live map by raw coords — FloatingOrigin recentres the world on
spawn, so the bay_capture camera's world coords don't match the pre-recentre
local placement (point-blank shots showed nothing). Isolation capture (no
recentre) is the reliable way to review them. Also: MultiMesh
`get_instance_transform` reads back identity for a detached (non-rendered)
MultiMesh in headless — verify placement via the source positions, not the
read-back.

## 2026-06-12 (cont. 5) — boat hulls get a prow; capture myth busted

Two small things. (1) The BayBoats hulls were blunt boxes; added a pointed bow
wedge (a prism rotated apex-forward) so the fleet reads as real hulls up close
(`/tmp/bow.png`). (2) Capture-method correction worth recording: the "flat tan
ground" I kept seeing in every hand-framed miami shot (hero_capture / a pinned
street cam) was NOT a material or render bug — it was the free camera clipping
into nearby geometry (a building, the car body — see playtest sandbox_driving:
the tan mass is the CAR). The city renders fine (beauty_capture waypoints prove
dense lit sprawl). Lesson: judge the real map only from the tuned beauty/bay
waypoints or from isolated element captures, never an ad-hoc street free-cam.

Deferred: boat **wakes** (the last M6 "Ocean v2: wakes" piece). A naive flat
trail quad at a fixed low y is occluded by the Gerstner crests (±0.6 m) and
camouflaged by the whitecaps; doing it right needs a world-space,
wave-conforming wake mesh decoupled from the boat's tilt — a real task, parked
rather than shipped half-working.

## 2026-06-12 (cont. 4) — the bay comes alive: ambient boat fleet

Track Q (detail/life). The open bay was an empty plane — only crude box boats
moored at the marina docks, nothing on the water. Added `BayBoats`: a fleet of
sailboats (mast + triangular mainsail) and motor yachts (cabin) that bob AND
tilt on the Gerstner ocean and drift slowly along their heading, wrapping inside
the bay rectangle. Motion rides on `OceanMath` (the pure CPU twin of the water
shader), so the fleet rocks in agreement with the rendered waves, needs no Ocean
node reference, and is fully headless-testable. 30 boats reading as a living
waterway with the whitecaps (`/tmp/boats.png`). Added via FloridaBackdrop.

Verified in isolation (`bay_boats_capture.gd`) + 4 functional unit tests
(`test_bay_boats.gd`: count, sit-on-surface, drift, stay-in-bounds). Process
note: the tests first passed *vacuously* over an empty fleet because `_ready`
doesn't fire synchronously in headless run_tests before the first frame —
extracted a public `populate()` so the build is driven explicitly, not on engine
lifecycle timing. Honest limit: simple box hulls (fine at bay distance, not a
close-up dock model) and no wakes yet (the remaining M6 "Ocean v2: wakes" item).

## 2026-06-12 (cont. 3) — sky gets clouds: flat gradient → broken cumulus

Track Q (lighting/atmosphere — the biggest perceived lever). The playable map's
sky is a bare `ProceduralSkyMaterial` gradient baked into miami.tscn's
WorldEnvironment — and that scene is parallel-owned, so the env itself is
off-limits. Reached the sky a different way: a `CloudLayer` mesh + cloud_plane
shader added at runtime *via FloridaBackdrop* (a script I own), so the world
gets a real sky without editing the shared scene. The shader carves drifting
broken cumulus from fbm coverage, shades billow cores darker with a warm sun-rim,
and dissolves only the plane's far rim so clouds persist to the horizon where
they read densest. Dusk capture now has a dramatic textured sky over the skyline
(`/tmp/miami_clouds2.png`) vs the old flat wash; isolation `/tmp/clouds3.png`.

Perf: negligible. The ~30 ms frame at the 5-district aerial vantage is the
streamed city, not the sheet — dropping the shader from 5→4 fbm octaves + a
cheap single-octave billow moved frame time only ~0.1 ms, so the cloud cost is
sub-millisecond even as near-fullscreen transparent overdraw. Guarded by
`test_cloud_layer.gd`; reviewable via `cloud_layer_capture.gd`. Honest limit:
it's a single flat sheet (no true volumetric parallax/godrays), tuned for the
warm dusk grade — a daytime/overcast pass would want coverage driven by
time-of-day, which belongs with the env owner when miami.tscn frees up.

## 2026-06-12 (cont. 2) — wetland vegetation: 150 lollipops → lush tree stands

Track Q (detail/set-dressing), compounding the brighter ground below. The state
wetland scattered exactly 150 cylinder+sphere "lollipop" trees across a ~12 km
landmass — effectively bare, and crude in form. Extracted the vegetation into a
testable `WetlandFlora` builder and made it cluster each FloridaMapModel seed
point into a jittered stand of cypress (trunk + two stacked columnar crowns with
per-instance olive→green tone variation) over a denser palmetto shrub understory.
150 seeds now yield ~650 trees / ~1300 crowns / ~1000 shrubs — still just 3
MultiMesh draw calls, so perf-safe. Reads as believable Leonida scrubland
(`/tmp/wetland_flora.png`) instead of sparse dots. Verified in isolation
(`wetland_flora_capture.gd`) + 4 unit tests (`test_wetland_flora.gd`). Honest
limit: sphere-crown trees read well at backdrop/aerial distance but aren't
close-up foliage; this is state backdrop, not the walkable district streets.

## 2026-06-12 (cont.) — state-ground material: dark sheet → sunlit wetland

Track Q (texture/material). Judged in isolation (`land_material_capture.gd`,
neutral light, no HUD/grade) after the gameplay shots proved misleading — the
"flat orange ground" in aerials was the golden-hour grade + warm sand backdrop,
NOT the land material. The real fault: `florida_land.gdshader` albedos maxed at
0.18 — a near-black green that read as a dark void at eye level
(`/tmp/land_ground.png`) and a uniform sheet from altitude
(`/tmp/land_aerial.png`).

Fix: lifted the greens into a real sunlit range and added a fourth tonal zone —
a large-scale independent "field" band that breaks the wet canopy into lighter
sun-bleached clearings, layered canopy → field → dry palmetto-scrub → marsh
(marsh darkened last so basins stay wet inside a field). Now reads as varied
Leonida wetland at both scales (`/tmp/land_aerial_after.png`,
`/tmp/land_ground_after.png`). Crucially preserved the hard-won distance
specular-AA discipline (normals fade flat + roughness→1.0 past ~180 m) — only
albedo/zone mixing changed, so no return of the far-ground sparkle. Honest
limit: this is the *state backdrop*, not the walkable district streets; it lifts
aerial/approach/beauty-capture shots more than street-level play.

## 2026-06-12 — open-water whitecaps: the bay stops reading as plastic

Track Q (texture/material axis), in-lane water pass. The named gap "shore is a
tidal-flat lagoon rather than a breaking surf line" had a hidden cause: the
miami StateOcean ran `foam_strength 0.18`, and in the old shader that single
knob scaled BOTH the shoreline band AND the crest foam together. It was crushed
to 0.18 to stop the flat 12 km seabed painting white at the sand — which also
killed every whitecap on the open swell, leaving the bay flat and plasticky
(verified: `/tmp/ocean_before.png`).

Fix: decoupled the two. Whitecaps now key off the Gerstner **Jacobian** (foam
where the wave field folds — the breaking leeward face of a crest, physically
where caps form) on their own `u_whitecap_strength`/`u_whitecap_coverage` knobs,
independent of the shoreline `u_foam_depth`/`u_foam_strength` band. Miami keeps
its thin shore (no white flats) but the bay now froths on the swell
(`/tmp/ocean.png`, `/tmp/ocean_crisp.png`). Contract-guarded by
`test_ocean_foam.gd` (the foam is GPU-only, so it parses the shader + ocean.gd
to keep the two bands from silently re-merging). Honest limits: near-field foam
is still slightly blobby (low-freq streak noise), and this is open-sea chop, not
a true breaking-surf shoreline (that needs bathymetry, not a flat seabed).
Verdict Water: Mid-High → High on the open bay; shoreline surf still open.

## 2026-06-11 (later) — postcard v1 achieved

Palm row + boardwalk props landed (PalmMesh: parabolic-spine trunks,
drooping frond crowns, 10 tests; 965 total green, 8 smoke scenes). The
shoreline still now genuinely reads sun-bleached coastal postcard: bent
palms over pale sand, turquoise tidal channels, lamp posts, golden haze.
Honest gaps to the trailer frame: city reads as a fog sliver (needs either
taller shoreline blocks or per-shot fog), and the shore is a tidal-flat
lagoon rather than a breaking surf line (Ocean v2 foam/wave-break work).
Verdicts: Water High, Coast Mid-High (was n/a), Materials Mid-High.

## 2026-06-11 (cont.) — golden-hour ocean lands; postcard limits identified

Scene clock moved to 17.4 (rust dusk washed everything monochrome at 18.6+).
Over-water stills now read genuinely golden: pale gold sky, calm rippled
sea, warm horizon. Found+fixed: spawn re-anchor ordering (children _ready
first → district_built fired pre-connect), absolute-coordinate re-anchors
breaking across origin shifts. Remaining for the single composed postcard:
Venice is low-rise, so the skyline across 950 m of aerial fog reads as a
sliver — needs boardwalk-scale foreground props (palms/pier, world lane) or
per-shot fog tuning. Ledger verdict Water: Mid → High at golden hour.

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
