#!/usr/bin/env python3
"""Asset budget & provenance gate.

Enforces the docs/ASSETS.md rules automatically so a flood of AI-generated and
contributed assets stays disciplined instead of becoming slop:

  1. No binary asset over the 50 MB per-file cap (ASSETS.md rule 4).
  2. Every binary under game/assets/ has a provenance ledger row in
     docs/ASSETS.md (rule 2) — referenced by its repo-relative path.
  3. (warn) Textures over a generous resolution-proxy size, so nobody ships a
     16k master where a 2k tile belongs.

Read-only. Exit 0 = clean, 1 = violations. Run from anywhere:
    python3 tools/asset_budget.py
"""
from __future__ import annotations

import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ASSETS_DIR = REPO / "game" / "assets"
LEDGER = REPO / "docs" / "ASSETS.md"

# Binary asset extensions that must be ledgered (source/text files are exempt).
BINARY_EXTS = {
    ".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr", ".hdr",
    ".glb", ".gltf", ".obj", ".fbx", ".blend",
    ".ogg", ".wav", ".mp3",
    ".ttf", ".otf", ".woff", ".woff2",
}
MAX_FILE_BYTES = 50 * 1024 * 1024  # 50 MB hard cap (ASSETS.md rule 4)
WARN_TEXTURE_BYTES = 12 * 1024 * 1024  # ~over-budget master texture proxy


def ledger_paths() -> set[str]:
    """Repo-relative paths mentioned in the ASSETS.md ledger (any `path` cell)."""
    if not LEDGER.exists():
        return set()
    text = LEDGER.read_text(encoding="utf-8")
    # Ledger cells wrap paths in inline backticks: `game/assets/textures/denim.png`.
    # Exclude newlines so triple-backtick code fences elsewhere in the doc don't
    # merge real path tokens into one giant multi-line match.
    return set(re.findall(r"`([^`\n]+)`", text))


def iter_binary_assets():
    if not ASSETS_DIR.is_dir():
        return
    for p in sorted(ASSETS_DIR.rglob("*")):
        if p.is_file() and p.suffix.lower() in BINARY_EXTS:
            yield p


def main() -> int:
    ledgered = ledger_paths()
    oversize: list[str] = []
    unledgered: list[str] = []
    warn_big: list[str] = []
    total = 0
    count = 0

    for p in iter_binary_assets():
        count += 1
        size = p.stat().st_size
        total += size
        rel = p.relative_to(REPO).as_posix()
        if size > MAX_FILE_BYTES:
            oversize.append(f"{rel} ({size / 1024 / 1024:.1f} MB > 50 MB cap)")
        if rel not in ledgered:
            unledgered.append(rel)
        if p.suffix.lower() in {".png", ".jpg", ".jpeg", ".webp", ".tga", ".exr"} \
                and size > WARN_TEXTURE_BYTES:
            warn_big.append(f"{rel} ({size / 1024 / 1024:.1f} MB)")

    print(f"asset-budget: scanned {count} binary assets, "
          f"{total / 1024 / 1024:.1f} MB total")

    if warn_big:
        print("\n  warning — large textures (consider downscaling/tiling):")
        for w in warn_big:
            print(f"    · {w}")

    failed = False
    if oversize:
        failed = True
        print("\n  FAIL — over the 50 MB per-file cap:")
        for o in oversize:
            print(f"    ✗ {o}")
    if unledgered:
        failed = True
        print(f"\n  FAIL — {len(unledgered)} asset(s) missing a docs/ASSETS.md "
              "ledger row:")
        for u in unledgered:
            print(f"    ✗ {u}")

    if failed:
        print("\nasset-budget: violations found (see docs/ASSETS.md rules).")
        return 1
    print("asset-budget: all assets ledgered and within budget ✔")
    return 0


if __name__ == "__main__":
    sys.exit(main())
