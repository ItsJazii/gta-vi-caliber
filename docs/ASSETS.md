# Asset policy & provenance ledger

One illegitimate asset can poison the entire project. These rules are strict
because they have to be.

## The rules

1. **Original work, CC0, or CC-BY only.** No exceptions, no "temporary"
   rips, no AI generations prompted to imitate a specific copyrighted work.
   Content from any Grand Theft Auto product (or any other commercial game)
   is banned outright — models, textures, audio, fonts, logos, map layouts.
2. **Every asset has a ledger row** (below) added in the same PR that adds
   the file. PRs with unledgered binaries are closed.
3. **CC-BY attribution** is collected in this file and shipped in the game's
   credits screen.
4. **Size:** nothing over 50 MB per file. Source files (.blend, .psd) stay
   out of the repo unless they are the canonical editable original and under
   the cap; prefer linking a source archive in the ledger.
5. Binary formats route through **Git LFS** automatically via
   `.gitattributes` — verify with `git lfs status` before pushing.
6. Use the **Asset submission** issue template before producing large work,
   so style direction is agreed first (see style notes below).

## Style direction (short version)

Sun-bleached contemporary coastal city: saturated daylight, neon-wet nights,
worn concrete + stucco + palms. Realistic proportions; the stylization budget
is spent on lighting and color rather than shapes. Study reference goes in
`reference/` (gitignored — **never** commit study footage; see
`reference/README.md`).

## AI-generated assets

Allowed only if: the generator's terms permit redistribution under CC BY 4.0,
the prompt did not target a specific artist/game/franchise, and the ledger
row marks it `AI (<tool>)`. Maintainers may reject anything that looks too
close to existing commercial work regardless of provenance.

## Provenance ledger

| Path | Description | Author | Source | License |
| --- | --- | --- | --- | --- |
| `game/icon.svg` | Project icon (sun over road) | project contributors | original | CC BY 4.0 |
| `game/assets/world/downtown_la.json` | Building footprints/heights + road centerlines for the downtown district, extracted via `tools/osm/fetch_district.py` | © OpenStreetMap contributors | https://www.openstreetmap.org/copyright | ODbL 1.0 (data only; attribution embedded in file and credits) |

*(Append one row per asset. Path relative to repo root. "Source" is `original`
or a URL. License must be CC0, CC-BY-4.0, or CC-BY-4.0-compatible. Exception:
**geodata** — factual map data such as OpenStreetMap extracts is accepted under
ODbL 1.0; it must keep its attribution embedded in the file, get a credits-screen
entry, and stay in `game/assets/world/`. ODbL share-alike applies to the data
files themselves, not to the game's code or rendered output.)*
