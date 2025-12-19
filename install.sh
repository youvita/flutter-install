#!/bin/bash
set -euo pipefail

echo "======================================"
echo " Auto Flutter + Android Install Script"
echo "======================================"

# -------- Helpers --------
log()  { echo "[INFO] $*"; }
warn() { echo "[WARN] $*"; }
err()  { echo "[ERR ] $*"; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || err "Missing command: $1"
}

# -------- Shell RC --------
USER_SHELL="$(basename "${SHELL:-/bin/zsh}")"
case "$USER_SHELL" in
  zsh) SHELL_RC="$HOME/.zshrc" ;;
  bash) SHELL_RC="$HOME/.bash_profile" ;;
  *) SHELL_RC="" ;;
esac

add_path_to_rc() {
  local p="$1"
  [ -z "$SHELL_RC" ] && return
  grep -qs "$p" "$SHELL_RC" || echo "export PATH=\"$p:\$PATH\"" >> "$SHELL_RC"
}

# -------- Android config --------
ANDROID_SDK_ROOT="$HOME/Library/Android/sdk"
ANDROID_HOME="$ANDROID_SDK_ROOT"
CMDLINE_TOOLS="$ANDROID_SDK_ROOT/cmdline-tools/latest"

export ANDROID_SDK_ROOT ANDROID_HOME

# ==============================
# 1) Homebrew
# ==============================
if ! command -v brew >/dev/null; then
  log "Installing Homebrew"
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
else
  log "Homebrew already installed"
fi

# ==============================
# 2) Git
# ==============================
command -v git >/dev/null || brew install git

# ==============================
# 3) Flutter
# ==============================
FLUTTER_HOME="$HOME/flutter"
if [ ! -d "$FLUTTER_HOME" ]; then
  log "Installing Flutter SDK"
  git clone https://github.com/flutter/flutter.git -b stable "$FLUTTER_HOME"
fi

export PATH="$FLUTTER_HOME/bin:$PATH"
add_path_to_rc "$FLUTTER_HOME/bin"

# ==============================
# 4) CocoaPods
# ==============================
if ! command -v pod >/dev/null; then
  log "Installing CocoaPods"
  sudo gem install cocoapods --no-document
fi

# ==============================
# 5) Android Studio
# ==============================
if ! brew list --cask android-studio >/dev/null 2>&1; then
  log "Installing Android Studio"
  [ -f /usr/local/bin/studio ] && sudo rm -f /usr/local/bin/studio
  brew install --cask android-studio
fi

# ==============================
# 6) Android cmdline-tools
# ==============================
log "Installing Android command-line tools"
mkdir -p "$ANDROID_SDK_ROOT/cmdline-tools"

if [ ! -d "$CMDLINE_TOOLS" ]; then
  TMP_ZIP="/tmp/cmdline-tools.zip"
  curl -fsSL -o "$TMP_ZIP" \
    https://dl.google.com/android/repository/commandlinetools-mac-11076708_latest.zip
  unzip -q "$TMP_ZIP" -d "$ANDROID_SDK_ROOT/cmdline-tools"
  mv "$ANDROID_SDK_ROOT/cmdline-tools/cmdline-tools" "$CMDLINE_TOOLS"
  rm -f "$TMP_ZIP"
fi

export PATH="$CMDLINE_TOOLS/bin:$ANDROID_SDK_ROOT/platform-tools:$PATH"
add_path_to_rc "$CMDLINE_TOOLS/bin"
add_path_to_rc "$ANDROID_SDK_ROOT/platform-tools"

require_cmd sdkmanager

# ==============================
# 7) Install SDK packages
# ==============================
log "Installing Android SDK packages"

sdkmanager --sdk_root="$ANDROID_SDK_ROOT" \
  "platform-tools" \
  "platforms;android-36" \
  "build-tools;36.1.0" \
  "extras;android;m2repository" \
  "extras;google;m2repository" \
  "ndk-bundle"

# ==============================
# 8) Accept licenses (BEST POSSIBLE)
# ==============================
log "Accepting Android licenses (may require 1 manual run)"
yes | sdkmanager --licenses --sdk_root="$ANDROID_SDK_ROOT" || true

# ==============================
# 9) Flutter config
# ==============================
flutter config --android-sdk "$ANDROID_SDK_ROOT"

echo "======================================"
echo " INSTALL COMPLETE"
echo "======================================"
echo "👉 If this is the FIRST install:"
echo "   Run once manually:"
echo "     flutter doctor --android-licenses"
echo "======================================"
