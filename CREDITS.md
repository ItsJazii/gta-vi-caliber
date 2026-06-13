# Credits

Attribution for everything in this repo that isn't original project work.
This file is the source for the in-game credits screen. It mirrors the
provenance ledger in `docs/ASSETS.md` — every CC-BY asset and every
attribution-bearing dataset gets a line here in the same change that adds
it. CC0 work needs no attribution; we list it anyway as a courtesy.

## Required attribution (CC-BY 4.0)

Format: `Asset — Author — Source URL — CC BY 4.0`

*(none from third parties yet; project-original CC-BY work is credited
collectively to the project contributors)*

## Courtesy credits (CC0)

Format: `Asset — Author — Source URL — CC0 1.0`

- PBR material scans (asphalt, concrete, pavers, facades; per-asset URLs
  in the `docs/ASSETS.md` ledger) — ambientCG / Lennart Demes —
  https://ambientcg.com — CC0 1.0
- Universal Base Characters (player + NPC base meshes) — Quaternius —
  https://quaternius.com/packs/universalbasecharacters.html — CC0 1.0
- Universal Animation Library (45 humanoid clips) — Quaternius —
  https://quaternius.com/packs/universalanimationlibrary.html — CC0 1.0

## Required attribution (CC-BY 4.0) — character library

- NPC + main-character-candidate wardrobe skins (`game/assets/characters/
  npc_variants/`) — recolored by project contributors from Tripo Studio
  base character textures (CC BY 4.0) and Quaternius UBC textures (CC0) —
  CC BY 4.0. Note: the base Tripo coastal-resident characters they derive
  from (`coastal_residents/`, added in PR #34) are themselves CC BY 4.0
  but are not yet listed here — a pre-existing CREDITS gap to close.

## Data

- Map data © OpenStreetMap contributors —
  https://www.openstreetmap.org/copyright — ODbL 1.0 (district footprints
  and road centerlines in `game/assets/world/`)
- Florida state boundary geometry — U.S. Census Bureau —
  https://www2.census.gov/geo/tiger/GENZ2024/shp/cb_2024_us_state_500k.zip —
  U.S. public domain

## Tools and libraries

Engine and vendored addon licenses live with their sources (`LICENSE`,
`game/addons/*/LICENSE*`); they are not duplicated here.

Content-generation tools used in the asset pipeline (not redistributed in
this repo):

- Blosm (blender-osm) — prochitecture — https://prochitecture.gumroad.com
- Buildify — Pavel Oliva — https://paveloliva.gumroad.com/l/buildify
