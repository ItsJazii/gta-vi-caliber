# Building & running

## TL;DR (game only — most contributors)

You need **Godot 4.6+** and **git-lfs**. No compiler, no build step.

```bash
# macOS
brew install --cask godot && brew install git-lfs && git lfs install

# Linux: grab Godot from https://godotengine.org/download or your package
# manager; git-lfs from your package manager.

# Windows: https://godotengine.org/download + https://git-lfs.com
```

```bash
git clone https://github.com/duolahypercho/gta-vi-caliber.git
cd gta-vi-caliber
```

Then either open `game/project.godot` in the Godot editor and press **F5**,
or from the terminal:

```bash
godot --path game        # run the game
godot -e --path game     # open the editor
```

You should be standing on a sunlit ground plane, able to walk (WASD), sprint
(Shift), jump (Space), and look around (mouse; Esc releases the cursor).

## The local CI gate

Code PRs must pass:

```bash
pipx install "gdtoolkit==4.*"   # gdformat + gdlint, one-time
tools/check.sh
```

`tools/check.sh` runs exactly what CI runs: format check → lint → headless
project import → scene smoke test → unit tests. Green locally means green in
CI. `tools/check.sh --fix` auto-formats before checking.

## Building the native engine modules (optional)

The game runs fully without them — native modules are accelerators, and the
sandbox currently uses none. You only need this if you're working in
`engine/`.

Prerequisites: a C++17 compiler, Python 3, SCons (`pipx install scons`).

```bash
cd engine
git submodule update --init --recursive   # pulls godot-cpp
scons platform=macos target=template_debug    # or platform=linux / windows
```

Output lands in `game/bin/` and the matching `.gdextension` manifest makes
Godot pick it up on next editor start. Details and module-authoring guidance:
[../engine/README.md](../engine/README.md) and
[ARCHITECTURE.md](ARCHITECTURE.md).

## Release builds

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`, which
exports release builds for Linux (x86_64), Windows (x86_64), and macOS
(universal) using the presets in `game/export_presets.cfg`, then attaches the
zips to a GitHub Release for that tag.

To export locally instead, install the matching export templates
(Editor → **Manage Export Templates**, version must match your editor), then:

```bash
mkdir -p dist
godot --headless --path game --export-release "Linux"           ../dist/gta-vi-caliber-linux.x86_64
godot --headless --path game --export-release "Windows Desktop" ../dist/gta-vi-caliber-windows.exe
godot --headless --path game --export-release "macOS"           ../dist/gta-vi-caliber-macos.zip
```

Builds are unsigned (macOS is ad-hoc signed); the `dist/` directory is
git-ignored.

## Headless / CI reference

What CI does, should you need to reproduce it exactly:

```bash
gdformat --check game/scripts game/tests
gdlint game/scripts game/tests
godot --headless --path game --import        # validates project + resources
godot --headless --path game --script tests/smoke_test.gd
godot --headless --path game --script tests/run_tests.gd
```

## Troubleshooting

- **Textures/models missing after clone** → you cloned without LFS. Run
  `git lfs install && git lfs pull`.
- **`godot: command not found` (macOS)** → the cask installs the app bundle;
  add an alias: `alias godot="/Applications/Godot.app/Contents/MacOS/Godot"`.
- **Editor shows broken dependencies on first open** → let the import finish
  (bottom progress bar), then `Project → Reload Current Project`.
- **`tools/check.sh` says gdformat missing** → `pipx install "gdtoolkit==4.*"`
  (and `pipx ensurepath` if `pipx` is new on your machine).
