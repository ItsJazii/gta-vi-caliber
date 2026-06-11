#!/usr/bin/env bash
# Give an autonomous (/loop) agent its own isolated git worktree + branch so
# concurrent agents never collide in one working tree (which corrupts the shared
# game/.godot import cache and races file edits — see why this exists below).
#
# Usage:
#   tools/worktrees/new_agent_worktree.sh <lane> "<owned paths>" "<keep-out paths>"
#
# Example:
#   tools/worktrees/new_agent_worktree.sh weapons \
#       "game/scripts/weapons game/scenes/weapons" \
#       "game/scripts/world game/scripts/vehicles"
#
# Then, in a NEW terminal:
#   cd ../GTA6-weapons && claude       # start that agent's /loop here
set -euo pipefail
cd "$(dirname "$0")/../.."
REPO_ROOT="$(pwd)"
REPO_NAME="$(basename "$REPO_ROOT")"

LANE="${1:?usage: new_agent_worktree.sh <lane> \"<owned paths>\" \"<keep-out paths>\"}"
OWNED="${2:-}"
KEEPOUT="${3:-}"
BASE_BRANCH="${BASE_BRANCH:-main}"

WT_DIR="$REPO_ROOT/../${REPO_NAME}-${LANE}"
BRANCH="agent/${LANE}"

if git show-ref --quiet "refs/heads/${BRANCH}"; then
    echo "branch ${BRANCH} already exists — reusing it" >&2
    git worktree add "$WT_DIR" "$BRANCH"
else
    git worktree add -b "$BRANCH" "$WT_DIR" "$BASE_BRANCH"
fi

cat > "$WT_DIR/LANE.md" <<EOF
# Agent lane: ${LANE}

You are an autonomous agent in an **isolated git worktree**. Other agents work
in parallel worktrees on the same repo. Stay in your lane — collisions corrupt
the shared Godot import cache and race file edits.

- Worktree: \`${WT_DIR}\`
- Branch: \`${BRANCH}\` — commit freely here; NEVER \`git checkout ${BASE_BRANCH}\`.
- Merge to ${BASE_BRANCH} happens via review, not by you switching branches.

## You OWN (create/edit freely)
${OWNED:-(define owned paths)}

## DO NOT TOUCH (another agent owns these — extend via new files, or leave a note)
${KEEPOUT:-(define keep-out paths)}

## Before every commit
- Run \`tools/check.sh\` (format, lint, headless import, smoke, unit tests).
- Do not commit on red. Keep commits small and lane-scoped for clean merges.
EOF

echo
echo "✓ worktree ready: $WT_DIR  (branch $BRANCH)"
echo "  lane brief:    $WT_DIR/LANE.md"
echo
echo "  Start this agent in a new terminal:"
echo "      cd \"$WT_DIR\" && claude"
