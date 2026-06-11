#!/usr/bin/env bash
# Build the native engine modules (engine/worldcore) into game/bin/ so the
# game picks them up on next start. Works on macOS, Linux, and Windows
# (Git Bash / MSYS). The game runs fine WITHOUT this — native modules are
# accelerators — but a build that ships engine/ systems needs them present.
#
# Usage:
#   tools/build_engine.sh                 # detect platform, build template_debug
#   tools/build_engine.sh release         # build template_release (for exports)
#   tools/build_engine.sh debug release   # build both targets
#   PLATFORM=linux tools/build_engine.sh  # override autodetected platform
set -euo pipefail
cd "$(dirname "$0")/.."

# --- locate the godot-cpp submodule ------------------------------------------
if [[ ! -d engine/godot-cpp ]]; then
    echo "==> godot-cpp submodule missing; fetching..."
    git submodule update --init --recursive
fi

# --- require scons -----------------------------------------------------------
if ! command -v scons >/dev/null 2>&1; then
    echo "error: 'scons' not found. Install it:  pipx install scons  (or pip install scons)" >&2
    exit 1
fi

# --- detect platform (godot-cpp names: macos | linux | windows) --------------
PLATFORM="${PLATFORM:-}"
if [[ -z "$PLATFORM" ]]; then
    case "$(uname -s)" in
        Darwin) PLATFORM=macos ;;
        Linux) PLATFORM=linux ;;
        MINGW* | MSYS* | CYGWIN*) PLATFORM=windows ;;
        *)
            echo "error: could not detect platform from '$(uname -s)'. Set PLATFORM=macos|linux|windows." >&2
            exit 1
            ;;
    esac
fi

# --- which targets: args map debug/release -> godot-cpp target names ---------
TARGETS=()
if [[ $# -eq 0 ]]; then
    TARGETS=(template_debug)
else
    for arg in "$@"; do
        case "$arg" in
            debug | template_debug) TARGETS+=(template_debug) ;;
            release | template_release) TARGETS+=(template_release) ;;
            *)
                echo "error: unknown target '$arg' (expected: debug | release)" >&2
                exit 1
                ;;
        esac
    done
fi

for target in "${TARGETS[@]}"; do
    echo "==> scons platform=$PLATFORM target=$target"
    scons -C engine "platform=$PLATFORM" "target=$target"
done

echo "==> done. Native libs + worldcore.gdextension are in game/bin/"
echo "    Verify from GDScript:  ClassDB.class_exists(\"WorldCore\")"
