#!/usr/bin/env bash
# Local CI gate — runs exactly what .github/workflows/ci.yml runs.
# Usage:
#   tools/check.sh          # check everything
#   tools/check.sh --fix    # auto-format first, then check everything
set -euo pipefail
cd "$(dirname "$0")/.."

FIX=0
if [[ "${1:-}" == "--fix" ]]; then
    FIX=1
fi

# --- locate godot ------------------------------------------------------------
GODOT_BIN="${GODOT:-godot}"
if ! command -v "$GODOT_BIN" >/dev/null 2>&1; then
    if [[ -x "/Applications/Godot.app/Contents/MacOS/Godot" ]]; then
        GODOT_BIN="/Applications/Godot.app/Contents/MacOS/Godot"
    else
        echo "error: Godot not found. Install Godot 4.6+ (docs/BUILDING.md) or set GODOT=/path/to/godot" >&2
        exit 1
    fi
fi

require() {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo "error: '$1' not found. Install gdtoolkit:  pipx install \"gdtoolkit==4.*\"" >&2
        exit 1
    fi
}

step() { printf '\n==> %s\n' "$1"; }

GD_DIRS=(game/scripts game/tests)
LOG_DIR="$(mktemp -d "${TMPDIR:-/tmp}/gta-caliber-check.XXXXXX")"
trap 'rm -rf "$LOG_DIR"' EXIT

run_godot_checked() {
    local label="$1"
    shift
    local log_file="$LOG_DIR/${label// /_}.log"
    local status=0

    set +e
    "$@" 2>&1 | tee "$log_file"
    status=${PIPESTATUS[0]}
    set -e

    if [[ "$status" -ne 0 ]]; then
        echo "error: $label exited with status $status" >&2
        return "$status"
    fi
    if grep -q 'SCRIPT ERROR:' "$log_file"; then
        echo "error: $label emitted an unexpected SCRIPT ERROR" >&2
        return 1
    fi
    if grep -q 'ObjectDB instances leaked at exit' "$log_file"; then
        echo "error: $label leaked ObjectDB instances" >&2
        return 1
    fi
}

# `python3 -m pip install --user gdtoolkit` puts gdformat/gdlint in the
# Python user script directory, which is not always on PATH in non-login shells.
if ! command -v gdformat >/dev/null 2>&1 && command -v python3 >/dev/null 2>&1; then
    PY_USER_BIN="$(python3 -m site --user-base 2>/dev/null)/bin"
    if [[ -d "$PY_USER_BIN" ]]; then
        PATH="$PY_USER_BIN:$PATH"
    fi
fi

# --- 1. format ---------------------------------------------------------------
require gdformat
if [[ "$FIX" == 1 ]]; then
    step "gdformat (fixing)"
    gdformat "${GD_DIRS[@]}"
else
    step "gdformat --check"
    gdformat --check "${GD_DIRS[@]}"
fi

# --- 2. lint -----------------------------------------------------------------
require gdlint
step "gdlint"
gdlint "${GD_DIRS[@]}"

# --- 2.5 git-lfs materialization guard ---------------------------------------
# Binary assets (*.png, *.glb, ...) are stored via git-lfs. On a checkout where
# the LFS objects were never pulled, each asset is a ~130-byte text *pointer*.
# Importing a pointer makes Godot rewrite the committed *.import sidecars to
# describe a broken asset, which then surfaces downstream as a cascade of
# confusing "Failed loading resource" unit-test failures — and the corrupted
# sidecars survive a `.godot/` cache wipe. Fail fast here with the real fix.
step "git-lfs materialization"
if [[ -f .gitattributes ]] && grep -q 'filter=lfs' .gitattributes; then
    LFS_POINTER=""
    while IFS= read -r asset; do
        [[ -f "$asset" ]] || continue
        IFS= read -r first_line <"$asset" || true
        if [[ "$first_line" == "version https://git-lfs.github.com/spec/v1" ]]; then
            LFS_POINTER="$asset"
            break
        fi
    done < <(git ls-files game/assets | grep -iE '\.(png|jpg|jpeg|webp|glb|gltf|fbx|exr|hdr|ktx2|ogg|wav|mp3|ttf|otf)$' | head -60)
    if [[ -n "$LFS_POINTER" ]]; then
        echo "error: git-lfs assets are not materialized (e.g. '$LFS_POINTER' is still a pointer)." >&2
        echo "       Run:  git lfs install && git lfs pull   then re-run this gate." >&2
        echo "       (Importing un-pulled pointers corrupts the committed *.import sidecars;" >&2
        echo "        if you already ran an import, also: git checkout -- game/assets && rm -rf game/.godot)" >&2
        exit 1
    fi
fi

# --- 3. headless import (validates project.godot, scenes, resources) ---------
step "headless import"
run_godot_checked "headless import" "$GODOT_BIN" --headless --path game --import

# --- 4. smoke test (main scene boots, player rig present) --------------------
step "smoke test"
run_godot_checked "smoke test" "$GODOT_BIN" --headless --path game --script res://tests/smoke_test.gd
step "menu startup probe"
run_godot_checked "menu startup probe" "$GODOT_BIN" --headless --path game --script res://tests/menu_startup_probe.gd

# --- 5. gdUnit4 unit tests ----------------------------------------------------
step "gdUnit4 unit tests"
run_godot_checked "gdUnit4 unit tests" "$GODOT_BIN" --headless --path game --script res://tests/run_tests.gd

# --- 6. playable-map integration probes --------------------------------------
# Frame-stepped runtime checks the one-frame smoke test cannot make: the main
# map's gameplay stack is wired (self-wiring system nodes registered) and the
# GTA core loop fires (crime -> wanted -> police dispatch). These guard against
# a scene edit silently unhooking the simulation.
step "miami wiring probe"
run_godot_checked "miami wiring probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_wiring_probe.gd
step "miami facade probe"
run_godot_checked "miami facade probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_facade_probe.gd
step "streaming route probe"
run_godot_checked "streaming route probe" "$GODOT_BIN" --headless --path game --script res://tests/streaming_route_probe.gd
step "vehicle visual probe"
run_godot_checked "vehicle visual probe" "$GODOT_BIN" --headless --path game --script res://tests/vehicle_visual_probe.gd
step "player ground probe"
run_godot_checked "player ground probe" "$GODOT_BIN" --headless --path game --script res://tests/player_ground_probe.gd
step "coastal asset probe"
run_godot_checked "coastal asset probe" "$GODOT_BIN" --headless --path game --script res://tests/coastal_asset_probe.gd
step "miami loop probe"
run_godot_checked "miami loop probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_loop_probe.gd
step "miami mission probe"
run_godot_checked "miami mission probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_mission_probe.gd
step "miami payspray probe"
run_godot_checked "miami payspray probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_payspray_probe.gd
step "miami arrest probe"
run_godot_checked "miami arrest probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_arrest_probe.gd
step "miami helicopter probe"
run_godot_checked "miami helicopter probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_helicopter_probe.gd
step "miami day-night probe"
run_godot_checked "miami day-night probe" "$GODOT_BIN" --headless --path game --script res://tests/miami_day_night_probe.gd

# --- 7. systems wiring probes (scene-free: self-wiring nodes in a mock tree) --
step "market event probe"
run_godot_checked "market event probe" "$GODOT_BIN" --headless --path game --script res://tests/market_event_probe.gd
step "crime reaction probe"
run_godot_checked "crime reaction probe" "$GODOT_BIN" --headless --path game --script res://tests/crime_reaction_probe.gd
step "character switch probe"
run_godot_checked "character switch probe" "$GODOT_BIN" --headless --path game --script res://tests/character_switch_probe.gd
step "ambient event probe"
run_godot_checked "ambient event probe" "$GODOT_BIN" --headless --path game --script res://tests/ambient_event_probe.gd
step "systems integration probe"
run_godot_checked "systems integration probe" "$GODOT_BIN" --headless --path game --script res://tests/systems_integration_probe.gd

printf '\nAll checks passed ✔\n'
