#!/usr/bin/env bash
# apply-fix.sh — Patches Zeno's schema-mismatch issues so The Banner Saga's
# editor can compile and load the Mod Content DLC source assets.
#
# Run AFTER you've already used Zeno's "Mod..." dialog to create your project.
# Usage: ./apply-fix.sh <mod-id> [<game-root>] [<mod-root>]
#
#   <mod-id>     The Mod Id you set in Zeno's Mod... dialog (e.g. "test1").
#   <game-root>  TBS install path. Default: standard Steam location.
#   <mod-root>   Mod project path. Default: %USERPROFILE%\tbs_mods\<mod-id>
#
# This script:
#   1. Restores 6 broken compiled .json.z files from your game install.
#   2. Marks them read-only (so Zeno's compiler can't delete them on relaunch).
#   3. Applies the saga1.json schema migration so the saga master file compiles.
#   4. Unlocks the compiled saga1.json.z so the compiler can write a fresh one.
#
# Idempotent — running it twice is safe.

set -euo pipefail

MOD_ID="${1:-}"
if [[ -z "$MOD_ID" ]]; then
  echo "ERROR: Mod Id required. Usage: $0 <mod-id> [<game-root>] [<mod-root>]" >&2
  exit 1
fi

GAME_ROOT="${2:-/c/Program Files (x86)/Steam/steamapps/common/tbs}"
MOD_ROOT="${3:-${USERPROFILE//\\//}/tbs_mods/$MOD_ID}"
# Normalise C:\path\with\backslashes to /c/path/forward/slashes for Git Bash
MOD_ROOT="${MOD_ROOT//\\//}"
case "$MOD_ROOT" in
  [A-Za-z]:/*) drive="${MOD_ROOT%%:*}"; rest="${MOD_ROOT#*:}"; MOD_ROOT="/${drive,,}${rest}";;
esac

GAME_ASSETS="$GAME_ROOT/assets"
MOD_ASSETS="$MOD_ROOT/assets"
MOD_SRC="$MOD_ROOT/assets-src"

echo "Game root:  $GAME_ROOT"
echo "Mod root:   $MOD_ROOT"
echo ""

# --- Sanity checks ---
if [[ ! -d "$GAME_ASSETS" ]]; then
  echo "ERROR: Game install not found at: $GAME_ASSETS" >&2
  echo "       Pass the correct path as the second argument." >&2
  exit 1
fi

if [[ ! -d "$GAME_ROOT/assets-src" ]] && [[ ! -d "$MOD_SRC" ]]; then
  echo "WARNING: TBS - Mod Content DLC may not be installed." >&2
  echo "         Open Steam -> The Banner Saga -> Properties -> DLC and tick" >&2
  echo "         'TBS - Mod Content'." >&2
fi

if [[ ! -d "$MOD_ROOT" ]]; then
  echo "ERROR: Mod folder not found at: $MOD_ROOT" >&2
  echo "       Run Zeno, click 'Mod...', and complete the setup first." >&2
  exit 1
fi

# --- Files to restore + lock (saga1.json.z handled separately via source fix) ---
BROKEN_FILES=(
  "common/ability/_ability_index.json.z"
  "saga1/locale/fr/convo/part5/cnv_chat_eyvindawaken.json.z"
  "saga1/scene/part2/wld_einartoft_2/wld_einartoft_2.json.z"
  "saga1/scene/map/map_camp.json.z"
  "saga1/scene/part1/wld_grofheim_2/wld_grofheim_2.json.z"
  "saga1/scene/part2/cin_einartoft/cin_einartoft.json.z"
  "saga1/scene/battle/music/frostvellr.btlmusic.json.z"
)

echo "=== Restoring and locking 6 broken compiled files ==="
for f in "${BROKEN_FILES[@]}"; do
  src="$GAME_ASSETS/$f"
  dst="$MOD_ASSETS/$f"

  if [[ ! -f "$src" ]]; then
    echo "  skip (not in game install): $f"
    continue
  fi

  mkdir -p "$(dirname "$dst")"

  # Clear read-only attribute first if present (so we can overwrite)
  if [[ -f "$dst" ]]; then
    attrib.exe -R "$(cygpath -w "$dst" 2>/dev/null || echo "$dst")" 2>/dev/null || true
  fi

  cp -f "$src" "$dst"
  attrib.exe +R "$(cygpath -w "$dst" 2>/dev/null || echo "$dst")" >/dev/null
  echo "  locked: $f"
done

# --- saga1.json source-edit fix ---
echo ""
echo "=== Applying saga1.json schema migration ==="
SAGA1_SRC="$MOD_SRC/saga1/saga1.json"

if [[ ! -f "$SAGA1_SRC" ]]; then
  echo "  ERROR: saga1.json not found at $SAGA1_SRC" >&2
  echo "         Did the Mod... prep step finish? Check assets-src exists." >&2
  exit 1
fi

if grep -q '"title_id": "title_tbs1"' "$SAGA1_SRC" && ! grep -q '"fevs":' "$SAGA1_SRC"; then
  echo "  saga1.json already patched, skipping"
else
  # Backup
  if [[ ! -f "$SAGA1_SRC.bak" ]]; then
    cp "$SAGA1_SRC" "$SAGA1_SRC.bak"
    echo "  backup created: saga1.json.bak"
  fi

  # Multi-line search-and-replace: replace the fevs block with the new fields.
  # Anchored on the line BEFORE (dlcsUrl) and AFTER (happenings) to avoid mismatch.
  python - "$SAGA1_SRC" <<'PYEOF'
import sys
path = sys.argv[1]
with open(path, 'r', encoding='utf-8') as f:
    src = f.read()
old = (
    '\t"dlcsUrl": "saga1/dlcs1.json.z",\n'
    '\t"fevs": [\n'
    '\t\t"saga1/fmod/saga1.fev"\n'
    '\t],\n'
    '\t"happenings": [\n'
)
new = (
    '\t"dlcsUrl": "saga1/dlcs1.json.z",\n'
    '\t"campUrls": [\n'
    '\t\t"saga1/scene/camp/cmp_snow/cmp_snow.json.z",\n'
    '\t\t"saga1/scene/camp/cmp_forest/cmp_forest.json.z"\n'
    '\t],\n'
    '\t"fmodPreloadUrl": "saga1/fmod/preload_banks.json.z",\n'
    '\t"talentDefsUrl": "common/character/talent/talents.json.z",\n'
    '\t"title_id": "title_tbs1",\n'
    '\t"warPoppeningContinueUrl": "saga1/convo/war/cnv_war_decide.json.z",\n'
    '\t"warPoppeningImpl": "Action_War_Impl_1",\n'
    '\t"warPoppeningUrl": "saga1/convo/war/cnv_war.json.z",\n'
    '\t"happenings": [\n'
)
if old not in src:
    sys.exit("ERROR: expected fevs block not found in saga1.json — file may have an unexpected format")
out = src.replace(old, new, 1)
with open(path, 'w', encoding='utf-8') as f:
    f.write(out)
print("  patched: saga1.json")
PYEOF
fi

# --- Unlock compiled saga1.json.z so compiler can rewrite it ---
SAGA1_Z="$MOD_ASSETS/saga1/saga1.json.z"
if [[ -f "$SAGA1_Z" ]]; then
  attrib.exe -R "$(cygpath -w "$SAGA1_Z" 2>/dev/null || echo "$SAGA1_Z")" 2>/dev/null || true
  echo "  unlocked: saga1/saga1.json.z (compiler will rewrite from source)"
fi

echo ""
echo "Done. Relaunch Zeno."
echo "Expected compile log: 'WRITING all outputs for saga1/saga1.json.z' and 'errs=14, oks=1'."
echo "To edit the saga master file in Zeno: File -> Open -> $SAGA1_SRC"
