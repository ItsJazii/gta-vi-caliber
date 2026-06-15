# Audio asset credits

All audio in this folder is **CC0 1.0 (public domain, no rights reserved)**.
No attribution is legally required; it is recorded here for provenance.

## Footsteps — `footsteps/`

- **Source:** "Fantozzi's Footsteps (Grass/Sand & Stone)" by *Fantozzi*
- **License:** CC0 1.0 — <https://creativecommons.org/publicdomain/zero/1.0/>
- **Page:** <https://opengameart.org/content/fantozzis-footsteps-grasssand-stone>
  (originally from the Freesound pack <https://freesound.org/people/Fantozzi/packs/10338/>)
- **Files:**
  - `footsteps/concrete/concrete_1..6.ogg` — the pack's *Stone* L1–L3 / R1–R3
    ("Stone" reads as most hard surfaces; used as the concrete/default surface).
  - `footsteps/sand/sand_1..6.ogg` — the pack's *Sand* L1–L3 / R1–R3
    ("Sand" also reads as grass; used for both the `sand` and `grass` surfaces).
- **Processing:** none — original CC0 Ogg Vorbis files, only renamed.

## Weapons — `weapons/`

- **Source:** "SSE Library: GUNS" (Craig Smith / USC sound-effects collection)
- **License:** CC0 1.0 Universal — <https://creativecommons.org/publicdomain/zero/1.0/>
- **Page:** <https://archive.org/details/SSE_Library_GUNS>
- **Files (origin → repo):**
  - `PISTOL/GUNPis_Exterior pistol shots with no reverb_CS_USC.wav` → `weapons/pistol.wav`
  - `AUTOMATIC/GUNAuto_M16 automatic rifle shots_CS_USC.wav` → `weapons/smg.wav`
  - `RIFLE/GUNRif_Very sharp small rifle fire_CS_USC.wav` → `weapons/rifle.wav`
  - `SHOTGUN/GUNShotg_Shotgun_CS_USC.wav` → `weapons/shotgun.wav`
- **Processing:** isolated a single shot from the source recording (transient-aligned
  trim), downmixed to mono, peak-normalized, and tail-faded; re-encoded as 16-bit PCM
  WAV (the source files are 24-bit, which the Godot WAV importer does not support).
  CC0 permits modification.
