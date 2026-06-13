# Asset pipeline (PROPOSAL)

**Status: PROPOSAL — not yet team policy.** This adapts an asset-pipeline
master plan to this repo's existing contracts (`docs/ASSETS.md` ledger,
`AGENTS.md`, the PR #33 day-night sky). Nothing here overrides
`docs/ASSETS.md`; where this doc says less, the ledger rules say more.
Section 9 (art direction) is an explicit open question for Ziwen and the
team before any bulk production starts.

## 1. The pipeline, one line

ambientCG / Poly Haven (materials) → Blender-OSM layout + Buildify
(building mass) → Sketchfab CC hunting (hero buildings, props, base cars)
→ MB-Lab / MakeHuman bodies + Quaternius UAL animations (NPCs) → AI image
gen for decals/signage/liveries ONLY → Blender driven via MCP for
cleanup/variation/export → Godot 4, judged by in-game screenshot.

## 2. Priorities (foundation first)

1. **Streets / ground textures** — every screenshot stands on them.
2. **Buildings** — procedural mass + real facade materials; hero pieces later.
3. **NPCs / people** — bodies + the UAL animation set already proven in-repo.

Vehicles, props, and vegetation slot in behind these; they multiply an
existing scene, they don't found one.

## 3. Sources by category

All commit-safe: **CC0 or CC-BY 4.0 only** (see section 4 — this is the
whole game for a public repo). Mixamo/Adobe content is **banned** for this
repo: it is not CC-licensed, baked-into-a-GLB or otherwise. The Quaternius
Universal Animation Library (45 CC0 clips, already committed, rig proven in
PR #31) is our animation library.

- **Materials / textures:** ambientCG (primary; public download API,
  scripted via `tools/pull-material.sh`, section 5), Poly Haven, cgbookcase,
  ShareTextures. All CC0. With these, AI texture generation shrinks to
  custom-only work (signage, graffiti, liveries, decals).
- **Buildings:** procedural, not downloaded. Blosm (blender-osm) free tier
  (real street layouts + building footprints; the data is ODbL like our
  existing `game/assets/world/*.json` extracts — same attribution rules
  apply) + Buildify (free geometry-nodes building generator) dressed with
  ambientCG facade materials. Sketchfab CC0/CC-BY for distinctive hero
  buildings — fictional designs only, per the policy below. The Base Mesh
  (CC0) for kitbashing.

  **Building art policy (decided): real footprints, fictional buildings.**
  Real OSM street layouts and building FOOTPRINTS are welcome — that's
  what makes the city feel real — but no building ships as a recreation of
  its real-world counterpart. Every building is a fictionalized
  Buildify/procedural variation on its footprint: different facades,
  heights within reason, details, names. The city should feel like Miami
  without containing Miami. Photogrammetry of real buildings and
  likeness-replication (by any technique, including AI) are out entirely.
  Practically: randomize floor counts, swap facade material sets and
  tints per building, never reuse a real building's name or signage.
- **Vehicles:** Sketchfab CC0/CC-BY base cars. Audition ~10, keep 3–5;
  verify the license per asset on the asset page (CC, not "Standard").
  Multiplier: a few good bases × Blender reskins (colors, AI liveries,
  plates) = a full traffic fleet. Stylized kits (Kenney/Quaternius) only
  if the section 9 call goes against our recommendation.
- **NPCs / people:** MB-Lab or MakeHuman parametric bodies (license-check
  each export — the *tool* being GPL does not make exports GPL, but verify
  the export terms per tool version and record them in the ledger),
  animated with the in-repo Quaternius UAL.
- **Props / vegetation:** Poly Haven models first (photoreal, fits the
  section 9 recommendation), Sketchfab CC, OpenGameArt; Kenney/Quaternius
  prop kits only if section 9 lands stylized. License-verify each asset
  individually.

## 4. Licensing (non-negotiable — public repo = redistribution)

Everything in `docs/ASSETS.md` applies. On top of that:

- **CC0:** commit freely; ledger row required all the same.
- **CC-BY 4.0:** ledger row **plus** a `CREDITS.md` line (author, source
  URL, license).
- **Marketplace "free" licenses** (Fab Standard, BlenderKit, most itch.io
  packs) permit game *use* but **not redistribution**. Never commit them.
- **Sketchfab — mandatory per-asset verification step.** Sketchfab uploads
  are sometimes mislabeled. Before an asset enters the repo: (1) open the
  asset page and confirm the stated license is CC0 or CC-BY 4.0 (not
  "Standard", not "Editorial"); (2) save the asset page URL **and** the
  license deed URL into the asset's `docs/ASSETS.md` ledger row; (3) if the
  uploader plainly isn't the author (rips happen), skip the asset entirely.
  No ledger row with both URLs, no commit.
- **OSM-derived data** (Blender-OSM footprints included) is ODbL 1.0. The
  repo already accepts geodata under ODbL with embedded attribution (see the
  ledger footnote in `docs/ASSETS.md`); meshes we *generate* from footprints
  are our own work, but the extracted data files keep their attribution and
  a credits entry.
- **Watermark/logo audit is part of license verification.** Inbound
  assets (Sketchfab, OpenGameArt, tool-bundled module packs) sometimes
  carry author watermarks, embedded logos, or branded geometry — Buildify
  ships literal Blender-logo sign meshes, which baked straight into the
  first POC export. Audit every inbound asset for them (textures AND
  mesh shapes) before it touches a scene; see the export gate in §10.
- Nothing enters the repo without a confirmed license. One bad asset
  poisons the project.

## 5. Materials tooling: `tools/pull-material.sh`

Pulls a PBR set from ambientCG by asset ID and unpacks it into the repo's
`PbrMaterial.from_set` layout (`docs/ASSETS.md`):

```
tools/pull-material.sh <AmbientCG-ID> <target-name> [resolution]
# e.g. tools/pull-material.sh Asphalt025C asphalt_worn_01 2K
# →  game/assets/materials/asphalt_worn_01/{albedo,normal,roughness,ao}.png
```

It uses the public API (`https://ambientcg.com/api/v2/full_json`) to
resolve the download, renames maps to the repo suffix convention, prints
the provenance line for the ledger, and refuses to overwrite an existing
set. ambientCG is CC0, but every pulled set still gets its ledger row in
the same commit. 2K is the standard; 4K only for hero close-ups.

## 6. Vehicle material recipe (the "rubbery car" fix)

Imported cars arrive with merged materials, metallic 0, roughness 0.5 —
i.e. rubber. Two tiers:

- **Fast fix (traffic cars):** metallic 1.0, roughness 0.2, clearcoat ON,
  opaque tinted glass is fine.
- **Proper fix (hero vehicles only):** separate window faces to a glass
  material (roughness 0.05, metallic 0, transparency, dark grey-blue alpha
  ~0.85); tires roughness 0.8 / metallic 0; flatten any baked-in
  reflections out of the albedo.

**Reflections need an environment to reflect — and the answer here is NOT
an HDRI sky.** This repo has a live day-night physical sky (PR #33,
`sky.gdshader` + SkyController); a static HDRI would regress it and is
off the table. Instead:

- Place **ReflectionProbe** nodes at vehicle-dense spots (streets,
  parking, showcase scenes). Set them to update on demand (re-capture on
  time-of-day changes, not per-frame) so day reflections aren't pasted
  onto night paint.
- Consider **SDFGI** for large-scale ambient bounce; it tracks the dynamic
  sky on its own. Budget it: measure on the night-street scene before
  adopting (the repo has prior art on night-perf cliffs, see PR #33 notes).
- Screen-space reflections can supplement on wet-look streets but never
  replace probes for paint.

## 7. AI image gen — narrow role

Decals, signage, storefront art, graffiti, liveries, plates, and concept
references only. Never bulk textures (ambientCG wins on quality and
license), never meshes. Repo policy in `docs/ASSETS.md` already governs
this: generator terms must permit CC-BY-4.0 redistribution, prompts must
not target a specific artist/game/franchise, ledger row marked
`AI (<tool>)`. Texture prompts must be orthographic with flat lighting (no
baked shadows) or they won't tile or relight; verify 2×2 tiling in Godot
before accepting. Provider/API wiring is a later step — no gen tooling in
the proof-of-concept phase.

## 8. Godot 4 import cheatsheet

- **GLB is the exchange format.**
- Suffix auto-import works: `name_albedo/_normal/_roughness/_ao/
  _metallic/_height.png` — but in-repo materials prefer the
  `PbrMaterial.from_set` folder layout (`docs/ASSETS.md`).
- **Repeat = Enabled** for tileables (Godot defaults to Disabled).
- Normal maps flagged as normal-map type; albedo sRGB, data maps linear.
- Flip the normal-map green channel if bumps invert (Godot expects
  OpenGL-style +Y).
- **Headless imports skip `detect_3d`** — textures imported headless keep
  2D defaults (no mipmaps, no VRAM compression). We hit this on the road
  PBR work. Set import flags explicitly (commit the `.import` files with
  mipmaps + VRAM compression for 3D textures) and eyeball one in-game
  screenshot per new texture set.
- Pack AO+Roughness+Metallic into one ORM texture for perf where the
  material count justifies it.
- 2K standard, 4K hero-closeup only. Triplanar for terrain/roads to dodge
  UV seams (supported by `PbrMaterial.from_set`).

## 9. OPEN QUESTION for Ziwen + team: art direction target

**Flagged, recommended, not decided here.** This choice decides which
sources above we lean on (photoreal scans + Sketchfab realistic cars vs
stylized kits), so it has to land before bulk generation starts.

The project's stated bar is the GTA VI trailer (`docs/QUALITY.md` grades
every playtest against the VISION.md "trailer-fidelity" bar) — i.e.
photorealism.

**Our recommendation: aim realistic, not stylized.** Photoreal scanned
surfaces (ambientCG / Poly Haven), real OSM layouts, PBR lighting — while
accepting consistent, clean mid-poly meshes where $0 photoreal meshes
don't exist (NPCs, vehicles). Consistency reads as quality; patchwork
photorealism reads as asset-flip, so the realism comes from materials and
lighting applied uniformly, not from mixing one photoreal hero into a
stylized street.

Practically: skip the stylized kits (Kenney / Quaternius low-poly) for
world assets going forward; reserve simple meshes for where they're
unavoidable and dress them in realistic materials. (The Quaternius
*animation* library is unaffected — it's motion data, not a look.)

Until Ziwen calls it: foundation work (streets/ground materials, building
massing dressed in scanned facades) is safe — it serves the photoreal
target and survives a stylized call. Hold bulk hero assets, vehicle
fleets, and NPC face/clothing variety until the call.

## 10. Blender via MCP — setup and division of labor

**Setup (verified working 2026-06-12, Blender 5.1.2 / Python 3.13.9):**

1. Blender runs locally with the **blender-mcp addon** enabled and its
   bridge server started (sidebar → BlenderMCP → Connect).
2. The repo's `.mcp.json` registers the MCP server: `uvx blender-mcp`
   (stdio). Claude Code picks it up per-project.
3. Round-trip test: `get_scene_info` should return the live scene;
   `execute_blender_code` with a `print()` should echo output back. If
   either fails, the bridge is down — fix the connection first, never
   work around it blind.

**Division of labor:** live MCP for iterative, watched work (material
tweaks, one-off exports, recipe development); headless
(`blender --background --python script.py`) once a recipe is proven and
batch-applying. Strengths: batch operations, materials, mesh separations,
exports, rig boilerplate. Weakness: creative modeling and topology — don't
ask it to sculpt.

### Blosm + Buildify on Blender 5.1 (verified 2026-06-12)

**Manual steps (once per machine):** only the two Gumroad checkouts/
downloads (Blosm zip, `buildify_1.0.blend`). Everything after that was
driven entirely over the bridge — zero Blender clicks:

- **Blosm install:** `bpy.ops.preferences.addon_install(filepath=zip)` +
  `addon_enable(module="blosm")`, set `preferences.dataDir`. Import via
  `scene.blosm` props (`dataType='osm'`, `mode='3Dsimple'`, extent
  lat/lon) + `bpy.ops.blosm.import_data()`. A downtown test block pulled
  46 buildings from Overpass headlessly. **OSM mode only** — the addon
  has Google/Mapbox/ArcGIS key fields; they stay empty and the
  `3d-tiles` data type is never used (no keys exist for this project).
  The old GitHub release (vvoovv v2.4.21, 2021) does NOT work on 5.x
  (imports the removed `bgl` module); use the current Gumroad build.
- **Buildify:** it's a .blend asset, not an addon — append the
  `building` node group (`bpy.data.libraries.load`); its module
  collections come along as dependencies. Works on 5.1 with quirks:
  (a) instances must be realized before GLB export (the glTF exporter
  silently exports only the base footprint otherwise — add a Realize
  Instances modifier or realize to a mesh); (b) Collection Info nodes
  READ as unbound (`None` defaults) — false alarm, they're fed by links
  from group-node sockets, which survive the version migration; don't
  "fix" them; (c) one muted Frame node — cosmetic, ignore; (d) the roof
  `Set Material` node arrives genuinely unbound — rebind it.
- **Density recipe (REQUIRED before any building ships — Tier C).**
  Buildify output is arch-viz density (the POC tower realized at ~422k
  tris). Budget: **hero/tower < 80k tris, standard building < 40k.** The
  proven two-step reduction (per Tier C, validated on the POC tower
  421k → 72k and applied to all 18 library buildings):
  1. **Limited dissolve** (bmesh `dissolve_limit`, 5°, delimit by
     material+normal): merges coplanar facade faces, ~50% off, lossless
     on flat walls. Follow with `dissolve_degenerate` to clear the
     decimation's non-manifold slivers (else glTF logs "mesh not valid").
  2. **Collapse decimate** to the tri budget. Collapse is imprecise on
     constrained geometry — target ~10-15% under the cap (e.g. 62k to
     land a tower under 80k).
  Result for the library: houses ~4-5k, businesses ~10k, mid-rise
  ~28-37k, towers ~67-70k tris.
- **Textures stay OUT of building GLBs.** Embedding 2K facade maps per
  building blew a single GLB to 51 MB. Instead export geometry-only with
  NAMED slot materials (WALL/TRIM/GLASS/ROOF/DETAIL/ACC*) and apply the
  shared ambientCG sets in Godot via `scripts/props/building_facade.gd`
  (per-building wall set + tint + glass colour). GLBs drop to 0.5-9 MB
  and the textures live once in `game/assets/materials/`.
  - `building_facade` matches slots tolerantly: it strips Godot's `.NNN`
    duplicate suffixes AND maps Buildify's raw `proxy_mat_*` names to
    slots, so it works even when the generator's rename didn't take (a
    real bug — repeated Buildify re-appends duplicate the proxy
    materials, silently defeating an exact-name remap). It uses
    **triplanar** facade projection (UV-independent) and drives its own
    window emission from the day/night clock, so it does not depend on a
    sibling node's `_ready` order.
- **Houses are procedural, NOT Buildify.** Buildify is a flat-roof
  apartment/office generator: no pitched roof, no residential door/porch
  modules — at 1-2 floors it makes a corniced box, not a house. The
  residential set is a small bmesh generator instead: gable roof (eave
  overhang + gable ends), human-scale door, home-sized windows, optional
  porch + chimney. Same named-slot + `building_facade` convention (adds
  ROOF2 terracotta + DOOR wood slots).
- **Branded content warning:** Buildify's detail collections include
  street-sign modules modeled as Blender-logo boards (logo + wordmark as
  GEOMETRY, so no image audit catches them). Delete `street_sign_a/b`
  before generating. Audit any module pack for branded shapes by name and
  by eye before first use.

### Mandatory export gate (no watermarks/logos/placeholders, ever)

Before ANY GLB/texture export, in this order — export-time, not
gauntlet-time:

1. **Missing-image audit** in Blender: every image datablock and every
   image node resolves to a real, intended file on disk — zero
   missing/unpacked/generated stand-ins. Blender silently substitutes a
   placeholder for broken references rather than erroring.
2. **Embedded-image enumeration:** after export, parse the GLB and list
   every embedded image; each must trace to a deliberately sourced,
   ledgered file (`docs/ASSETS.md`). Nothing embeds that we didn't choose.
3. The gauntlet close-up lens (§12) includes "no watermarks, logos, or
   placeholder imagery visible" as an explicit pass criterion — the
   by-eye backstop, never the primary catch.

## 11. What the pipeline delivers: an asset library

**The pipeline's deliverable is shelf stock, not world changes.** Output =
gauntlet-passed assets landing in the `game/assets/` and
`game/scenes/props/` folders, ledgered, unplaced, and unused by the live
game until someone deliberately uses them in their own later PR. Placement
and world integration are explicitly out of scope per asset — every asset
PR ships library stock only, and booting the game after merging one
changes nothing a player sees.

Library lanes, in priority order:

| Lane | What lands on the shelf | Gate |
| --- | --- | --- |
| 1 | `tools/pull-material.sh` + material sets (asphalt, concrete/pavement, facades) | CC0, ledger rows, no scene changes |
| 2 | Buildings: Blosm + Buildify recipe → fictionalized buildings as prop scenes | Gauntlet-passed; **bulk generation waits on section 9** |
| 3 | Vehicles: rubbery-car material recipe applied to base cars | Gauntlet-passed (glass sweep mandatory) |
| 4 | NPCs: MB-Lab/MakeHuman + UAL retarget pilot (one body) | Pilot ships shelf-only; variety batch waits on section 9 |
| 5 | AI decal/signage lane | Waits on section 9 **and** maintainer review of generator terms |

Every lane: `tools/check.sh` green, ledger rows in the same commit as the
binaries, `git lfs status` verified, gauntlet passed (§12) before any PR.

**How this could feed the city later (future team decision, not part of
any asset PR):** once shelves have depth, separate world-integration PRs
could wire material sets into the road/sidewalk/ground shaders
(before/after screenshots per surface) and place buildings, props, and
NPCs in the live scenes. Who does that, when, and with what look is a
team call that starts with section 9 — nothing in this pipeline presumes
it.

## 12. The integration gauntlet (mandatory)

**No asset enters the live scene without a passed gauntlet — automated
checks AND human eyes on the contact sheet.** The gauntlet exists because
assets that look fine in a clean test scene fail under real conditions:
grazing golden-hour sun, the night grade, distance bloom, free-look
motion. (The road-PBR rounds proved each of those failure modes the hard
way.)

The stage is `game/tests/asset_gauntlet.tscn` — a self-contained scene
that replicates the live miami.tscn rendering stack verbatim (PR #33
physical sky + SkyController, the real Environment grade, the WorldQuality
tier script, a ReflectionProbe). It never references miami.tscn. Run:

```
ASSET=res://assets/<path-to>.glb \
SHOT_DIR=session_captures/gauntlet/<asset_name> \
godot --path game --script res://tests/asset_gauntlet_capture.gd
echo $?   # check it directly — never through a pipe
```

The battery, all automated:

- **Time sweep** — noon, golden hour 17.8 (grazing sun, the known worst
  case), night 22.0, deep night 2.0.
- **Distance sweep** — close-up, 50 m, 220 m, at noon AND at night (the
  night-far case is where emissive windows fuse into bloom blobs).
- **Motion pass** — a free-look-style approach arc at walking height with
  sinusoidal view swing (deliberately NOT a fixed dolly), with a
  same-pose consecutive-frame comparison at every arc pose; a flicker
  fraction above `GauntletChecks.FLICKER_MAX_FRACTION` (z-fighting,
  shimmer) is an automatic FAIL.
- **Glass sweep** — when reflective/transparent materials are detected
  (or `GLASS=1` forces it): incidence angles 5° → 85° across the facade,
  with the stage's ReflectionProbe providing something to reflect.
- **Pixel sanity on every shot** — blank and single-tone (uniform)
  detection via `GauntletChecks` (pure logic, unit-tested in
  `tests/unit/test_gauntlet_checks.gd`).
- **Close-up lens pass criteria (by eye):** texture detail resolves, no
  aliasing/shimmer, and **no watermarks, logos, or placeholder imagery
  visible** — the backstop for the §10 export gate. The first gauntlet
  run caught Blender-logo signboards that every automated check missed.

Output: numbered shots plus `contact_sheet.png` under
`session_captures/gauntlet/<asset_name>/`. The verdict protocol: a human
opens every image (or at minimum the contact sheet at full size), judges
each lens, and records pass/fail per lens in the session notes / PR body.
**A FAIL on any lens blocks the asset** — fix and re-run; a failed
gauntlet is a finding, not an embarrassment. Exit code 0 from the script
is necessary but never sufficient.
