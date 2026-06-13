#!/usr/bin/env bash
# Pull a CC0 PBR material set from ambientCG into the repo's
# PbrMaterial.from_set layout (docs/ASSETS.md, docs/ASSET_PIPELINE.md §5).
#
# Usage:
#   tools/pull-material.sh <AmbientCG-ID> <target-name> [resolution]
#   tools/pull-material.sh Asphalt031 asphalt_street_01 2K
#
# Produces game/assets/materials/<target-name>/{albedo,normal,roughness,...}.png
# and prints the provenance row to append to docs/ASSETS.md in the SAME commit.
set -euo pipefail
cd "$(dirname "$0")/.."

if [[ $# -lt 2 || $# -gt 3 ]]; then
    echo "usage: tools/pull-material.sh <AmbientCG-ID> <target-name> [resolution=2K]" >&2
    exit 2
fi

ASSET_ID="$1"
TARGET_NAME="$2"
RES="${3:-2K}"
TARGET_DIR="game/assets/materials/${TARGET_NAME}"
API_URL="https://ambientcg.com/api/v2/full_json?id=${ASSET_ID}&include=downloadData"

if [[ -e "$TARGET_DIR" ]]; then
    echo "error: ${TARGET_DIR} already exists — refusing to overwrite" >&2
    exit 1
fi

step() { printf '==> %s\n' "$1"; }

step "querying ambientCG API for ${ASSET_ID}"
API_JSON="$(curl -fsS "$API_URL")"

ZIP_URL="$(printf '%s' "$API_JSON" | python3 -c "
import json, sys
res = sys.argv[1]
data = json.load(sys.stdin)
assets = data.get('foundAssets', [])
if not assets:
    sys.exit('error: asset not found on ambientCG')
downloads = (
    assets[0]
    .get('downloadFolders', {})
    .get('default', {})
    .get('downloadFiletypeCategories', {})
    .get('zip', {})
    .get('downloads', [])
)
want = res + '-PNG'
for d in downloads:
    if d.get('attribute') == want:
        print(d['downloadLink'])
        break
else:
    have = ', '.join(d.get('attribute', '?') for d in downloads)
    sys.exit('error: no ' + want + ' zip for this asset (available: ' + have + ')')
" "$RES")"

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

step "downloading ${ZIP_URL}"
curl -fsSL -o "$TMP_DIR/material.zip" "$ZIP_URL"
unzip -q "$TMP_DIR/material.zip" -d "$TMP_DIR/unpacked"

# ambientCG map name -> repo from_set name. NormalGL (OpenGL +Y) is what
# Godot expects; NormalDX and Displacement are deliberately skipped.
declare -a MAP_PAIRS=(
    "Color:albedo"
    "NormalGL:normal"
    "Roughness:roughness"
    "Metalness:metallic"
    "AmbientOcclusion:ao"
    "Emission:emission"
)

mkdir -p "$TARGET_DIR"
COPIED=0
for pair in "${MAP_PAIRS[@]}"; do
    src_suffix="${pair%%:*}"
    dst_name="${pair##*:}"
    src="$(find "$TMP_DIR/unpacked" -name "*_${src_suffix}.png" | head -n1)"
    [[ -z "$src" ]] && continue
    size_mb=$(( $(stat -f%z "$src" 2>/dev/null || stat -c%s "$src") / 1024 / 1024 ))
    if (( size_mb >= 50 )); then
        echo "error: ${src##*/} is ${size_mb} MB (repo cap is 50 MB/file) — try a lower resolution" >&2
        rm -rf "$TARGET_DIR"
        exit 1
    fi
    cp "$src" "$TARGET_DIR/${dst_name}.png"
    COPIED=$((COPIED + 1))
    echo "    ${src##*/} -> ${TARGET_DIR}/${dst_name}.png (${size_mb} MB)"
done

if (( COPIED == 0 )); then
    echo "error: zip contained no recognized PBR maps" >&2
    rm -rf "$TARGET_DIR"
    exit 1
fi

step "done: ${COPIED} maps in ${TARGET_DIR}"
cat <<LEDGER

Append to the docs/ASSETS.md ledger IN THE SAME COMMIT as the binaries:

| \`${TARGET_DIR}/\` (${COPIED} maps) | <describe the surface> — ${RES} PBR set, PbrMaterial.from_set layout | ambientCG | https://ambientcg.com/a/${ASSET_ID} | CC0 1.0 (https://docs.ambientcg.com/license/) |

Then verify LFS picked the files up:  git lfs status
LEDGER
