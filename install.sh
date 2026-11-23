#!/usr/bin/env bash
# 105fm installer. Safe to re-run: it backs up anything it changes.
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
HS_DIR="$HOME/.hammerspoon"
KB_DIR="$HOME/.config/karabiner/assets/complex_modifications"
STAMP="$(date +%Y%m%d-%H%M%S)"

say()  { printf '\n\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  ✓ %s\n' "$*"; }
warn() { printf '  ! %s\n' "$*"; }

say "1/5  Checking prerequisites"
[[ "$(uname)" == "Darwin" ]] || { echo "macOS only."; exit 1; }
if [[ -x /usr/bin/fm ]]; then
  ok "Apple Foundation Models CLI found (/usr/bin/fm)"
else
  warn "/usr/bin/fm not found (needs macOS 27 with Apple Intelligence). The tool will use Anthropic Haiku for everything, so you will need an API key (step 4)."
fi

missing=()
[[ -d "/Applications/Hammerspoon.app" ]] || missing+=(hammerspoon)
[[ -d "/Applications/Karabiner-Elements.app" ]] || missing+=(karabiner-elements)
if (( ${#missing[@]} )); then
  if command -v brew >/dev/null; then
    read -r -p "  Install ${missing[*]} with Homebrew? [Y/n] " a
    if [[ ! "$a" =~ ^[Nn] ]]; then brew install --cask "${missing[@]}"; fi
  else
    warn "Install ${missing[*]} first (see README), then re-run this script."
    exit 1
  fi
fi
ok "Hammerspoon and Karabiner-Elements present"

say "2/5  Installing the Hammerspoon module"
mkdir -p "$HS_DIR"
if [[ -f "$HS_DIR/105fm.lua" ]]; then
  cp "$HS_DIR/105fm.lua" "$HS_DIR/105fm.lua.bak-$STAMP"
  ok "Backed up previous module"
fi
cp "$REPO_DIR/hammerspoon/105fm.lua" "$HS_DIR/105fm.lua"
ok "Copied 105fm.lua to $HS_DIR"

touch "$HS_DIR/init.lua"
if grep -q 'require("105fm")' "$HS_DIR/init.lua"; then
  ok "init.lua already loads the module"
else
  cp "$HS_DIR/init.lua" "$HS_DIR/init.lua.bak-$STAMP"
  printf '\n-- 105fm\nrequire("105fm")\n' >> "$HS_DIR/init.lua"
  ok "Added require(\"105fm\") to init.lua (backup: init.lua.bak-$STAMP)"
fi

say "3/5  Installing the Karabiner rule"
mkdir -p "$KB_DIR"
cp "$REPO_DIR/karabiner/105fm.json" "$KB_DIR/105fm.json"
ok "Copied rule to $KB_DIR"
warn "Enable it yourself: Karabiner-Elements → Complex Modifications → Add predefined rule → 105fm → Enable"

say "4/5  Anthropic API key (optional)"
if security find-generic-password -a "$USER" -s anthropic_api_key -w >/dev/null 2>&1; then
  ok "Key already in Keychain"
else
  echo "  Used only as a fallback when the local model fails (or for everything if fm is missing)."
  read -r -p "  Add an Anthropic API key to the Keychain now? [y/N] " a
  if [[ "$a" =~ ^[Yy] ]]; then
    security add-generic-password -a "$USER" -s anthropic_api_key -w
    ok "Key stored (Keychain service: anthropic_api_key)"
  else
    ok "Skipped - running local-only"
  fi
fi

say "5/5  Starting Hammerspoon"
open -a Hammerspoon
cat <<'EOF'
  Finish these by hand (one time):
    • System Settings → Privacy & Security → Accessibility → turn on Hammerspoon
    • Karabiner: enable the "105fm" rule (step 3)
    • Hammerspoon menu bar icon → Reload Config
  Then select some text anywhere and press both Shift keys together.
EOF
