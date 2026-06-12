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

# --- 3. headless import (validates project.godot, scenes, resources) ---------
step "headless import"
"$GODOT_BIN" --headless --path game --import

# --- 4. smoke test (main scene boots, player rig present) --------------------
step "smoke test"
"$GODOT_BIN" --headless --path game --script res://tests/smoke_test.gd

# --- 5. unit tests ------------------------------------------------------------
step "unit tests"
"$GODOT_BIN" --headless --path game --script res://tests/run_tests.gd

# --- 6. playable-map integration probes --------------------------------------
# Frame-stepped runtime checks the one-frame smoke test cannot make: the main
# map's gameplay stack is wired (self-wiring system nodes registered) and the
# GTA core loop fires (crime -> wanted -> police dispatch). These guard against
# a scene edit silently unhooking the simulation.
step "miami wiring probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_wiring_probe.gd
step "miami facade probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_facade_probe.gd
step "miami loop probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_loop_probe.gd
step "miami mission probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_mission_probe.gd
step "miami payspray probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_payspray_probe.gd
step "miami arrest probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_arrest_probe.gd
step "miami helicopter probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_helicopter_probe.gd
step "miami day-night probe"
"$GODOT_BIN" --headless --path game --script res://tests/miami_day_night_probe.gd

printf '\nAll checks passed ✔\n'
