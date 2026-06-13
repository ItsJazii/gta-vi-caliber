# GTA-VI-caliber

**A community-driven, fully open-source open-world game.** Our quality bar is the
fidelity shown in modern AAA open-world trailers: a dense, living coastal city
with seamless streaming, vehicles, crowds, water, and weather. Built on
[Godot 4](https://godotengine.org) with custom C++ engine modules where the
engine needs to be pushed further.

> ⚠️ This is an original, unaffiliated community project. It is **not**
> associated with Rockstar Games or Take-Two Interactive, and contains no
> assets, code, or content from any Grand Theft Auto product. "GTA-VI-caliber"
> describes our *quality benchmark*, nothing more.

## Quickstart (60 seconds)

```bash
# 1. Install Godot 4.6+ and git-lfs
brew install --cask godot && brew install git-lfs && git lfs install
#    (Linux/Windows: download Godot 4.6 from https://godotengine.org/download)

# 2. Clone
git clone https://github.com/duolahypercho/gta-vi-caliber.git
cd gta-vi-caliber

# 3. Play — boots straight into the one map, no editor needed:
godot --path game
#    — or open it in the Godot editor and press F5:
godot --path game --editor
```

There is **one map** and it boots straight into play — no menus, no scene
picker. The command above (or pressing F5 in the editor) drops you into the
streaming Vice City world, ready to walk, drive, and trigger the wanted system.

### Controls

| Input | Action |
| --- | --- |
| `WASD` | Move |
| `Shift` | Sprint |
| `Space` | Jump / brake |
| `Ctrl` | Dive |
| `E` | Enter / exit nearest car |
| `C` | Look behind |
| Mouse | Look around |
| `LMB` / `RMB` | Fire / aim |
| `R` | Reload |
| `Q` / `V` | Next weapon / weapon wheel |
| `X` | Holster |
| `F` | Melee (unarmed) |
| `Tab` or `P` | Phone |
| `F5` / `F9` | Quick-save / quick-load |
| `Esc` | Pause / release mouse cursor |

A gamepad works too: left stick moves, right trigger fires, left trigger
aims, `A` jumps, `B` dives, `X` interacts, `Y` reloads, shoulders holster
(`LB`) and melee (`RB`), stick clicks sprint (`L3`) and look behind (`R3`).

More detail in [docs/BUILDING.md](docs/BUILDING.md).

## Project status

🟢 **Playable.** Launching the game drops you straight into a single streaming
Vice City map: a third-person character, drivable vehicles, traffic and crowds,
and the core GTA loop wired end to end (commit crimes → wanted stars → police
dispatch → evade or get busted), plus missions and a property/economy layer.
See [docs/ROADMAP.md](docs/ROADMAP.md) for what's next.

## Support the project

GTA-VI-caliber is free, open source, and built by the community. If you'd like
to help fund development, you can support the project on Solana. Contract
address (CA):

```text
DY2ZAaZrt27b3PpXjxH8qqDBZwrEoFoSqb83t7VNpump
```

[Donate / view on Phantom »](https://phantom.com/tokens/solana/DY2ZAaZrt27b3PpXjxH8qqDBZwrEoFoSqb83t7VNpump)

Every bit goes back into the game — tooling, assets, and contributor time.

> Always verify the full address character-for-character before sending
> anything. Support is voluntary and non-refundable; this is community-run, not
> a promise of returns, and nothing here is financial advice.

## Contributing

**Everyone is welcome — programmers, 3D artists, sound designers, writers,
playtesters.** Start here:

1. Read [CONTRIBUTING.md](CONTRIBUTING.md) (5 minutes).
2. Pick a [good first issue](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
   or any unchecked task in [docs/ROADMAP.md](docs/ROADMAP.md).
3. Open a PR. CI validates everything headlessly — if `tools/check.sh` passes
   locally, you're good.

AI agents are welcome contributors too: the repo contract for agents lives in
[AGENTS.md](AGENTS.md).

## Repository layout

| Path | What it is |
| --- | --- |
| `game/` | The Godot 4.6 project — scenes, scripts, assets, tests |
| `engine/` | Custom C++ engine modules (GDExtension) for performance-critical systems |
| `docs/` | Roadmap, architecture, asset policy + pipeline, vision, build guide |
| `tools/` | `check.sh` (the local CI gate) and helper scripts |
| `reference/` | Local-only art-direction study footage — never committed |

## License

- **Code:** [MIT](LICENSE)
- **Assets:** [CC BY 4.0](LICENSE-ASSETS)
