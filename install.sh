#!/bin/bash
set -euo pipefail

echo "======================================"
echo " Auto Flutter + Android Install Script"
echo "======================================"

# -------- Helpers --------
log() { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err() { echo "[ERR ] $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"
}

add_path_to_rc_top() {
  local p="$1"
  [ -z "${REQUIRED_SHELL_RC:-}" ] && return 0
  grep -qs "export PATH=.*$p" "$REQUIRED_SHELL_RC" && return 0
  {
    echo "export PATH=\"$p:\$PATH\""
  } | cat - "$REQUIRED_SHELL_RC" > "$REQUIRED_SHELL_RC.tmp" && mv "$REQUIRED_SHELL_RC.tmp" "$REQUIRED_SHELL_RC"
}

# -------- Detect shell rc --------
USER_SHELL="$(basename "${SHELL:-/bin/zsh}")"
case "$USER_SHELL" in
  zsh) REQUIRED_SHELL_RC="$HOME/.zshrc" ;;
  bash) REQUIRED_SHELL_RC="$HOME/.bash_profile" ;;
  *) warn "Unknown shell $USER_SHELL; PATH persistence may be skipped" ;;
esac

# -------- Check for CI mode --------
CI_MODE=false
if [ "${1:-}" = "--ci" ]; then
  CI_MODE=true
  log "Running in CI mode (non-interactive)"
fi

# --- 1) Install Homebrew ---
if ! command -v brew >/dev/null 2>&1; then
  log "Installing Homebrew..."
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed."
fi

# --- 2) Remove Homebrew Dart/flutter if present ---
brew list --formula 2>/dev/null | grep -q '^dart$' && brew uninstall dart --force || true
brew list --cask 2>/dev/null | grep -q '^flutter$' && brew uninstall --cask flutter --force || true

# --- 3) Ensure Git is installed ---
if ! command -v git >/dev/null 2>&1; then
    log "Git not found. Installing Git..."
    brew install git
else
    log "Git already installed."
fi

# --- 4) Install Flutter SDK ---
FLUTTER_HOME="$HOME/flutter"
if [ ! -d "$FLUTTER_HOME/bin" ]; then
    log "Installing Flutter SDK..."
    git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_HOME"
else
    log "Flutter already installed at $FLUTTER_HOME"
fi
FLUTTER_PATH="$FLUTTER_HOME/bin"
export PATH="$FLUTTER_PATH:$PATH"
add_path_to_rc_top "$FLUTTER_PATH"

# --- 5) Install CocoaPods ---
if ! command -v pod >/dev/null 2>&1; then
  log "Installing CocoaPods..."
  sudo gem install cocoapods --no-document
fi
GEM_BIN_PATH=$(sudo ruby -e 'require "rubygems"; puts Gem.bindir' 2>/dev/null || echo "/usr/local/bin")
export PATH="$GEM_BIN_PATH:$PATH"
add_path_to_rc_top "$GEM_BIN_PATH"

# --- 6) Install Android Studio ---
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
ANDROID_HOME="$ANDROID_SDK_ROOT"
CMDLINE_TOOLS="$ANDROID_SDK_ROOT/cmdline-tools/latest"

if ! brew list --cask android-studio >/dev/null 2>&1; then
  [ -f /usr/local/bin/studio ] && sudo rm -f /usr/local/bin/studio
  log "Installing Android Studio..."
  brew install --cask android-studio
else
  log "Android Studio already installed"
fi

# --- 7) Install Android SDK cmdline-tools ---
log "Configuring Android SDK directories"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "$CMDLINE_TOOLS" ]; then
  log "Installing Android command-line tools"
  TMP_ZIP="/tmp/cmdline-tools.zip"
  curl -fsSL -o "$TMP_ZIP" https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
  unzip -q "$TMP_ZIP" -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$CMDLINE_TOOLS"
  rm "$TMP_ZIP"
fi

export PATH="$CMDLINE_TOOLS/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
add_path_to_rc_top "$CMDLINE_TOOLS/bin"
add_path_to_rc_top "$ANDROID_SDK_ROOT/platform-tools"

require_cmd sdkmanager

# --- 8) Install latest SDK packages ---
log "Resolving latest Android SDK packages"
LATEST_PLATFORM=$(sdkmanager --list | grep -o 'platforms;android-[0-9]\+' | sort -V | tail -1)
LATEST_BUILD_TOOLS=$(sdkmanager --list | grep -o 'build-tools;[0-9.]\+' | sort -V | tail -1)

log "Installing: platform-tools, $LATEST_PLATFORM, $LATEST_BUILD_TOOLS"
sdkmanager --install \
  "platform-tools" \
  "$LATEST_PLATFORM" \
  "$LATEST_BUILD_TOOLS" \
  "extras;android;m2repository" \
  "extras;google;m2repository" \
  "ndk-bundle" || true

# --- 9) Accept all licenses via Flutter ---
if [ "$CI_MODE" = true ]; then
  log "Accepting Android licenses in CI mode (automatic)"
  yes | flutter doctor --android-licenses >/dev/null
else
  log "Accepting Android licenses (interactive)"
  flutter doctor --android-licenses
fi

# --- 10) Flutter config ---
flutter config --android-sdk "$ANDROID_SDK_ROOT"

# --- 11) Final verification ---
if [ "$CI_MODE" = false ]; then
  log "Running flutter doctor verification"
  flutter doctor
else
  log "Skipping flutter doctor in CI mode"
fi

echo "============================"
echo " Installation Completed!"
echo "============================"
