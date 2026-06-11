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

Prerequisites: a C++17 compiler, Python 3, SCons
(`pipx install scons` or `pip install scons`).

The quickest path — `tools/build_engine.sh` autodetects your platform, fetches
the submodule if needed, and builds into `game/bin/`:

```bash
tools/build_engine.sh            # template_debug for your OS (macOS/Linux/Windows)
tools/build_engine.sh release    # template_release (what release builds ship)
```

Or drive SCons directly:

```bash
git submodule update --init --recursive   # pulls godot-cpp (pinned; see engine/README.md)
cd engine
scons platform=macos target=template_debug    # or platform=linux / windows
scons tests && ./bin/test_worldcore           # plain C++ unit tests (optional)
```

The build puts `libworldcore.*` and the `worldcore.gdextension` manifest in
`game/bin/` (both gitignored); Godot picks them up on next start. Verify from
GDScript: `ClassDB.class_exists("WorldCore")`. Known quirk: the *first*
headless import after a native build crashes at exit in the editor's doc
generator — run it once more; see
[../engine/README.md](../engine/README.md) for details, module-authoring
guidance, and the godot-cpp version pin. Layering rules:
[ARCHITECTURE.md](ARCHITECTURE.md). CI builds and tests `engine/` on all
three platforms via `.github/workflows/engine.yml`.

## Release builds

Pushing a tag matching `v*` triggers `.github/workflows/release.yml`, which:

1. builds the native engine (`worldcore`, `template_release`) for Linux,
   Windows, and macOS — each on its own runner, since macOS native libraries
   can't be cross-compiled from Linux — and uploads each as an artifact;
2. collects all three native payloads into `game/bin/` on a Linux runner,
   verifies each platform's library is present (a missing lib fails the build
   rather than silently shipping without the native engine), then exports
   release builds for Linux (x86_64), Windows (x86_64), and macOS (universal)
   using the presets in `game/export_presets.cfg`;
3. attaches the zips to a GitHub Release for that tag.

So every published desktop build bundles the native engine layer — not just a
hand-built macOS one. To export locally, build the native libs first
(`tools/build_engine.sh release`) so `game/bin/` is populated before exporting.

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
