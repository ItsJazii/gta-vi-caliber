#!/usr/bin/env bash
#
# GTA-VI-caliber — one-command installer & launcher.
#
#   curl -fsSL https://raw.githubusercontent.com/duolahypercho/gta-vi-caliber/main/install.sh | bash
#
# Downloads the Godot 4.6 engine and git-lfs locally (no sudo, no Homebrew),
# clones the game with its art assets, and launches straight into play.
# Re-running updates an existing copy instead of re-cloning.
#
set -euo pipefail

# --- config (override via env) ----------------------------------------------
REPO_URL="${GTA6_REPO:-https://github.com/duolahypercho/gta-vi-caliber.git}"
REPO_BRANCH="${GTA6_BRANCH:-main}"
GODOT_VERSION="${GTA6_GODOT_VERSION:-4.6}"          # base stable; opens config/features "4.6"
GIT_LFS_VERSION="${GTA6_GIT_LFS_VERSION:-3.5.1}"
INSTALL_DIR="${GTA6_HOME:-$HOME/gta-vi-caliber}"
CACHE_DIR="${GTA6_CACHE:-$HOME/.cache/gta-vi-caliber}"

bold() { printf '\033[1m%s\033[0m\n' "$1"; }
info() { printf '\033[1;36m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33mwarn:\033[0m %s\n' "$1" >&2; }
die()  { printf '\033[1;31merror:\033[0m %s\n' "$1" >&2; exit 1; }

bold "GTA-VI-caliber installer"
mkdir -p "$CACHE_DIR"

# --- detect platform --------------------------------------------------------
OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
  Darwin) PLATFORM="macos" ;;
  Linux)  PLATFORM="linux" ;;
  MINGW*|MSYS*|CYGWIN*)
    die "Windows isn't supported by this one-liner. In PowerShell run:
       iwr https://raw.githubusercontent.com/duolahypercho/gta-vi-caliber/main/install.ps1 | iex
     ...or install via WSL (Ubuntu) and re-run this same command." ;;
  *) die "Unsupported OS: $OS" ;;
esac
info "Platform: $PLATFORM ($ARCH)"

# --- prerequisites we can't bootstrap: git ----------------------------------
if ! command -v git >/dev/null 2>&1; then
  if [ "$PLATFORM" = "macos" ]; then
    warn "git is missing. macOS will now prompt to install the Command Line Tools."
    xcode-select --install || true
    die "Re-run this command once the Command Line Tools finish installing."
  else
    die "git is missing. Install it first, e.g.:  sudo apt-get install -y git   (or your distro's equivalent)"
  fi
fi

# --- download helper --------------------------------------------------------
fetch() { # fetch <url> <out>
  curl -fL --retry 3 --progress-bar "$1" -o "$2" \
    || die "download failed: $1"
}

# --- ensure git-lfs (local, no sudo) ---------------------------------------
ensure_git_lfs() {
  if git lfs version >/dev/null 2>&1; then
    info "git-lfs: present ($(git lfs version | head -n1))"
    return
  fi
  info "git-lfs: not found, fetching a local copy"
  local lfs_dir="$CACHE_DIR/git-lfs"
  local lfs_bin="$lfs_dir/git-lfs"
  if [ ! -x "$lfs_bin" ]; then
    local asset url tmp
    case "$PLATFORM-$ARCH" in
      macos-arm64)        asset="git-lfs-darwin-arm64-v${GIT_LFS_VERSION}.zip" ;;
      macos-x86_64)       asset="git-lfs-darwin-amd64-v${GIT_LFS_VERSION}.zip" ;;
      linux-x86_64)       asset="git-lfs-linux-amd64-v${GIT_LFS_VERSION}.tar.gz" ;;
      linux-aarch64|linux-arm64) asset="git-lfs-linux-arm64-v${GIT_LFS_VERSION}.tar.gz" ;;
      *) die "no git-lfs build for $PLATFORM-$ARCH; please install git-lfs manually" ;;
    esac
    url="https://github.com/git-lfs/git-lfs/releases/download/v${GIT_LFS_VERSION}/${asset}"
    tmp="$CACHE_DIR/$asset"
    fetch "$url" "$tmp"
    rm -rf "$lfs_dir" && mkdir -p "$lfs_dir"
    case "$asset" in
      *.zip)    unzip -qo "$tmp" -d "$lfs_dir" ;;
      *.tar.gz) tar -xzf "$tmp" -C "$lfs_dir" ;;
    esac
    # archive may nest the binary one directory deep
    if [ ! -f "$lfs_bin" ]; then
      local found
      found="$(find "$lfs_dir" -name git-lfs -type f | head -n1)"
      [ -n "$found" ] && cp "$found" "$lfs_bin"
    fi
    chmod +x "$lfs_bin" 2>/dev/null || true
  fi
  export PATH="$lfs_dir:$PATH"
  git lfs version >/dev/null 2>&1 || die "git-lfs install failed"
  git lfs install --skip-repo >/dev/null 2>&1 || true
  info "git-lfs: ready (local)"
}

# --- ensure Godot engine (local, no install) -------------------------------
GODOT_BIN=""
ensure_godot() {
  if command -v godot >/dev/null 2>&1 && godot --version 2>/dev/null | grep -q "^4\.6"; then
    GODOT_BIN="$(command -v godot)"
    info "Godot: using system install ($(godot --version | head -n1))"
    return
  fi
  local gdir="$CACHE_DIR/godot-$GODOT_VERSION"
  if [ "$PLATFORM" = "macos" ]; then
    GODOT_BIN="$gdir/Godot.app/Contents/MacOS/Godot"
  else
    case "$ARCH" in
      x86_64)        GODOT_BIN="$gdir/Godot_v${GODOT_VERSION}-stable_linux.x86_64" ;;
      aarch64|arm64) GODOT_BIN="$gdir/Godot_v${GODOT_VERSION}-stable_linux.arm64" ;;
      *) die "no Godot build for linux-$ARCH" ;;
    esac
  fi
  if [ -x "$GODOT_BIN" ]; then
    info "Godot: cached ($GODOT_VERSION)"
    return
  fi
  info "Godot: downloading engine $GODOT_VERSION (~120 MB, one time)"
  local asset
  if [ "$PLATFORM" = "macos" ]; then
    asset="Godot_v${GODOT_VERSION}-stable_macos.universal.zip"
  else
    case "$ARCH" in
      x86_64)        asset="Godot_v${GODOT_VERSION}-stable_linux.x86_64.zip" ;;
      aarch64|arm64) asset="Godot_v${GODOT_VERSION}-stable_linux.arm64.zip" ;;
    esac
  fi
  local tmp="$CACHE_DIR/$asset"
  # Godot publishes binaries from the godot-builds repo; fall back to the main repo.
  fetch "https://github.com/godotengine/godot-builds/releases/download/${GODOT_VERSION}-stable/${asset}" "$tmp" \
    || fetch "https://github.com/godotengine/godot/releases/download/${GODOT_VERSION}-stable/${asset}" "$tmp"
  rm -rf "$gdir" && mkdir -p "$gdir"
  unzip -qo "$tmp" -d "$gdir"
  [ "$PLATFORM" = "linux" ] && chmod +x "$GODOT_BIN" 2>/dev/null || true
  [ -x "$GODOT_BIN" ] || die "Godot extraction failed (missing $GODOT_BIN)"
  info "Godot: ready ($GODOT_VERSION)"
}

# --- clone or update the game ----------------------------------------------
sync_repo() {
  if [ -d "$INSTALL_DIR/.git" ]; then
    info "Updating existing copy in $INSTALL_DIR"
    git -C "$INSTALL_DIR" fetch --depth 1 origin "$REPO_BRANCH"
    git -C "$INSTALL_DIR" reset --hard "origin/$REPO_BRANCH"
  else
    info "Cloning into $INSTALL_DIR"
    # Skip the smudge filter during clone; we pull LFS objects explicitly below
    # so a missing global git-lfs config can't leave assets as pointer files.
    GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "$REPO_BRANCH" "$REPO_URL" "$INSTALL_DIR"
  fi
  # Register git-lfs for THIS repo, then fetch the real art assets. Without the
  # local registration, `git lfs pull` silently no-ops on a fresh clone.
  info "Fetching art assets via git-lfs"
  git -C "$INSTALL_DIR" lfs install --local >/dev/null 2>&1 || true
  git -C "$INSTALL_DIR" lfs pull
}

# A fresh clone has no Godot import cache, so the first game run can't resolve
# global class_name lookups (e.g. SettingsPanel) and fails to parse. One
# headless editor pass builds the cache; --quit-after guarantees it exits. A
# background watchdog kills it if it ever overruns.
warm_cache() {
  [ -d "$INSTALL_DIR/game/.godot" ] && return
  info "First-run setup: importing assets (one time, ~1-2 min)..."
  "$GODOT_BIN" --headless --editor --path "$INSTALL_DIR/game" --quit-after 300 \
    >/dev/null 2>&1 &
  local pid=$!
  ( sleep 300; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  local watch=$!
  wait "$pid" 2>/dev/null || true
  kill "$watch" 2>/dev/null || true
}

ensure_git_lfs
ensure_godot
sync_repo
warm_cache

bold ""
info "To play again later, just re-run the same command, or:"
printf '       %s --path %s\n\n' "$GODOT_BIN" "$INSTALL_DIR/game"

if [ -n "${GTA6_NO_LAUNCH:-}" ]; then
  bold "Setup complete (GTA6_NO_LAUNCH set, not launching)."
  exit 0
fi

bold "Done. Launching GTA-VI-caliber..."
exec "$GODOT_BIN" --path "$INSTALL_DIR/game"
