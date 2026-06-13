# Contributing

Thanks for being here. This project only works because people like you show up.
**You do not need to be an expert.** There is meaningful work for programmers,
3D artists, sound designers, writers, and playtesters.

## Setup

```bash
brew install --cask godot          # Godot 4.6+ (or download from godotengine.org)
brew install git-lfs && git lfs install
pipx install "gdtoolkit==4.*"      # gdformat + gdlint (only needed for code PRs)
git clone https://github.com/duolahypercho/gta-vi-caliber.git
```

Open `game/` in the Godot editor and press F5. If the sandbox runs, your setup
works. Full details (including C++ engine work): [docs/BUILDING.md](docs/BUILDING.md).

## Finding work

- **Good first issues:** [filtered list](../../issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22)
- **The roadmap:** any unchecked box in [docs/ROADMAP.md](docs/ROADMAP.md) is
  fair game — comment on/open an issue first so two people don't duplicate work.
- **Art & audio:** issues labeled `art` and `audio` are requests from gameplay
  work that's blocked on placeholder assets.

## Pull request flow

1. Fork, branch from `main` (`feat/vehicle-suspension`, `fix/camera-jitter`, …).
2. Make your change. Keep PRs scoped to **one thing**.
3. Run `tools/check.sh` — it mirrors CI exactly (format, lint, headless import,
   scene smoke test, unit tests). Green locally means green in CI.
4. Open the PR; the template walks you through the checklist.

### Code style (GDScript)

- **Typed GDScript always** (`var speed: float = 5.0`, typed function signatures).
- Tabs for indentation (Godot default), `snake_case` files/dirs, `PascalCase` for `class_name`.
- Signals up, calls down: children emit signals, parents call methods.
- Autoloads only for true global services.
- Logic that can be tested gets a [gdUnit4](https://github.com/MikeSchulze/gdUnit4) test in `game/tests/`.
- Don't edit `game/addons/**` — addons are vendored; upgrades replace the whole folder.

### C++ (engine modules)

Performance-critical systems live in `engine/` as GDExtension modules — see
[engine/README.md](engine/README.md) and [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for what belongs there and the build instructions.

## Asset contributions

Assets are licensed CC BY 4.0 (see [LICENSE-ASSETS](LICENSE-ASSETS)). Hard rules:

- **Only original work or CC0/CC-BY-sourced work.** Every asset's provenance is
  recorded in [docs/ASSETS.md](docs/ASSETS.md). No exceptions — one bad asset
  can poison the whole project.
- Binary assets go through Git LFS automatically (`.gitattributes` handles it).
  Nothing over 50 MB in-repo; see [docs/ASSETS.md](docs/ASSETS.md) for the size policy.
- Use the **Asset submission** issue template — it captures the license
  attestation we need.
- **Sourcing, tooling, and the test battery** live in
  [docs/ASSET_PIPELINE.md](docs/ASSET_PIPELINE.md). Every asset must pass
  the integration gauntlet (§12 there) before it ships; CC-BY attribution
  goes in [CREDITS.md](CREDITS.md).

## AI agents

Human and AI contributors follow the same rules. The machine-readable repo
contract is [AGENTS.md](AGENTS.md). Maintainers run autonomous build loops
against [docs/ROADMAP.md](docs/ROADMAP.md); roadmap edits by humans are the
steering wheel for those loops.

## Governance notes

- Direct pushes to `main` are currently allowed for maintainers (early-stage
  velocity, including autonomous agent loops). Required PR review will be
  enabled once contributor volume justifies it.
- Be excellent to each other: [CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).
