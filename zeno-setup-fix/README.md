# Zeno Editor — Setup Fix Bundle (The Banner Saga)

The Mod Content DLC for *The Banner Saga* ships source assets that fail Zeno's schema validation, leaving the editor mostly non-functional out of the box. This bundle automates the fix.

## What's in here

| File | Purpose |
|---|---|
| `apply-fix.ps1` | One-shot Windows PowerShell fix script (recommended for most users). |
| `apply-fix.sh` | Same fix as a Git Bash script (needs Python in PATH for the JSON patch step). |
| `saga1.json.patch` | Unified diff of the saga1.json schema migration, for transparency or manual application. |
| `README.md` | This file — quick start at the top, full troubleshooting reference below. |

## Prerequisites

1. **The Banner Saga** installed via Steam.
2. **TBS - Mod Content** DLC installed (Steam → game **Properties** → **DLC** tab, free).
3. **Zeno's "Mod…" dialog completed** — you've already run Zeno once, clicked Mod…, entered a Mod Id, and the prep copy has populated your mod folder. By default the bundle expects `%USERPROFILE%\tbs_mods\<modid>\`.

The bundle does **not** include any game files. It operates only on files you already have through your own legal install of the game and the Mod Content DLC.

## Quick start

**PowerShell (Windows-native):**
```powershell
.\apply-fix.ps1 -ModId yourmodid
```

**Git Bash:**
```bash
./apply-fix.sh yourmodid
```

Optional second/third arguments override the game install path and the mod folder path:
```bash
./apply-fix.sh yourmodid "/c/Games/Steam/steamapps/common/tbs" "/c/some/other/mod/folder"
```

After the script finishes: **relaunch Zeno**. Check `compiler-0.log.txt`:
- `WRITING all outputs for saga1/saga1.json.z` confirms the saga1 source fix worked.
- `COMPILE FAILED    :  errs=14, oks=1` is the expected post-fix state (down from `errs=16, oks=0`).

To edit the saga master file in Zeno: **File → Open** and select your mod's `assets-src/saga1/saga1.json` (the tab does not auto-load — this is normal).

## What the scripts do

1. **Restore 6 broken compiled files** from your game install (Stoic's working compiled versions) into your mod output folder, and set the read-only attribute so Zeno's compiler can't overwrite them with empty/failed builds on relaunch.
2. **Patch `assets-src/saga1/saga1.json`** with the schema migration (remove the deprecated `fevs` field, add 7 new fields the current schema requires or expects).
3. **Unlock the compiled `saga1.json.z`** so the compiler can rewrite it from your patched source on the next launch.

The scripts are idempotent — running them again is safe. A backup of the original `saga1.json` is written to `saga1.json.bak` the first time the patch is applied.

## Creating additional mod projects

Zeno is one-mod-per-Mod-Id. To create a new mod (`mymod`) after you've already set up Zeno once on this machine:

1. Launch Zeno → click **Mod…** → enter `mymod` as Mod Id.
2. Double-check **Game Install Folder** is `C:\Program Files (x86)\Steam\steamapps\common\tbs` (Issue 2 can re-bite even on machines that previously had it right — don't trust Default).
3. Click OK. The prep copy runs again into `%USERPROFILE%\tbs_mods\mymod\` — fresh `assets-src\` and `assets\` populated from the same broken DLC sources as before.
4. Close the green screen. OK the Zeno Settings window.
5. **Run apply-fix on the new mod folder** *before* you try to use the editor:
   ```powershell
   .\apply-fix.ps1 -ModId mymod
   ```
   or
   ```bash
   ./apply-fix.sh mymod
   ```
6. Relaunch Zeno. Compiler should report `errs=14, oks=1`. You're good to mod.

Each mod project has its own independent copy of the broken files (Zeno's prep copies sources fresh per mod), so **the fix must be applied per project**. The script is idempotent — safe to run multiple times.

### Switching between existing mods

Zeno's `settings_app.json` tracks one active mod at a time. To switch from `test` to `test2`:

1. Click **Mod…** and enter the other id (e.g. `test2`).
2. Zeno detects the existing folder and reattaches without re-running the prep copy. You'll see `ModPreparer skipping copy to existing [...]` in the log — that's the no-op confirmation.

No need to re-run apply-fix when switching to an already-fixed mod. Each project's files persist as you left them.

## Manual application

If you'd rather apply the fix by hand (or are debugging), the rest of this README walks through everything the scripts do, plus the underlying causes and other common setup pitfalls.

---

# Troubleshooting reference

Supplement to the official Stoic modding doc. Covers the failures most people hit on a first attempt to set up Zeno for *The Banner Saga*.

Log files (read these first when anything fails):
```
%APPDATA%\Zeno.saga1\Local Store\zenolog\A-0.log.txt          ← main editor log
%APPDATA%\Zeno.saga1\Local Store\zenolog\compiler-0.log.txt   ← asset compiler log
```

---

## Issue 1 — `GAME ASSETS-SRC MISSING: INSTALL FROM STEAM DLC PANEL`

**Where you see it:** Red banner inside the **Mod Asset Settings** dialog after clicking "Mod…".

**Cause:** The free **TBS - Mod Content** DLC isn't installed. Note: the uncompiled `.json` files already present under `tbs\assets\` are runtime data, not mod sources — Zeno specifically needs the separate `assets-src\` tree that only the Mod Content DLC delivers.

**Fix:**
1. Steam → Library → right-click **The Banner Saga** → **Properties** → **DLC** tab.
2. Tick **TBS - Mod Content** to install it (free, ~1.5 GB).
3. Wait for Steam to finish the download.
4. Verify this path now exists:
   ```
   C:\Program Files (x86)\Steam\steamapps\common\tbs\assets-src
   ```
5. Relaunch Zeno and retry the Mod… dialog.

---

## Issue 2 — `INVALID GAME INSTALL FOLDER`

**Where you see it:** Red text under the **Game Install Folder** field in the Mod Asset Settings dialog.

**Cause:** Zeno's auto-detect (and the "Default" button) populates the field with **its own folder** — `...\tbs\win32\ZenoSaga1` — instead of the game install root. It's a Zeno bug, not your config.

**Fix:** Manually edit the field to the game's install root:
```
C:\Program Files (x86)\Steam\steamapps\common\tbs
```
That's the folder Steam's "Browse Local Files" opens — it contains both `assets\` and `win32\`. As soon as it's valid, the red banner clears and **OK** becomes clickable.

---

## Issue 3 — Log shows `SyntaxError: Error #1132` / `Failed to load prefs at [settings_app.json]`

**Where you see it:** Only in the log file (UI just shows "Unable to create compiler" and "Scene files menu is useless").

**Cause:** Zeno can write its own settings file in a broken state after a failed setup attempt — it stores Windows paths with raw backslashes (`"C:\Users\..."`), which is invalid JSON. Once the file is unparseable, every subsequent launch starts with no prefs, no compiler, and a dead editor.

**Fix (choose one):**

**Option A — easiest: delete the file and let Zeno regenerate it.**
```
%APPDATA%\Zeno.saga1\Local Store\settings_app.json
```
Delete it, relaunch Zeno, run the Mod… workflow from scratch (apply fixes for Issues 1 and 2 as needed).

**Option B — edit it by hand.** Open `settings_app.json` and convert any raw Windows path to a `file:///` URL with forward slashes. For example:
```json
// BAD — invalid JSON, backslashes are escape characters
"PREF_COMPILER_OUTPUT_URL": "C:\Users\you\tbs_mods\test1\assets"

// GOOD
"PREF_COMPILER_OUTPUT_URL": "file:///C:/Users/you/tbs_mods/test1/assets"
```

---

## Issue 4 — Tabs greyed out / hundreds of "unable to fetch active ability" errors / files keep disappearing

**Where you see it:** After the Mod… dialog succeeds and the prep copy completes, the editor opens but most tabs are greyed out or show no entries. The main log (`A-0.log.txt`) is flooded with errors like:
```
URLResourceLoader.onLoadFailed file:///.../common/ability/_ability_index.json.z: ErrorID 2032
EntityDef [gunnulf] unable to fetch active ability [abl_tempest]
EntityDef [eirik] unable to fetch active ability [abl_rally]
... (one block per character — 25+ characters)
```
The compiler log (`compiler-0.log.txt`) ends with:
```
COMPILE FAILED    :  errs=16, oks=0
```

**Cause:** The Mod Content DLC ships *source assets* that don't pass the public Zeno's schema validation — extra fields the schema rejects (`fevs`, `useCompleteParam`), missing mandatory fields (`campUrls`, `title_id`), enum values that no longer exist (`CAMERA_LOCK`), effect-op param shapes that changed (`RUN_THROUGH/damage_final`), and so on. This is almost certainly a **version mismatch**: the DLC was packaged by Stoic from an internal Zeno with a newer/different schema than the public one ships.

The cascade:
1. Compiler crashes on a handful of source files.
2. For each failed file, the corresponding compiled output (`.json.z`) is either never written or gets deleted.
3. The most consequential delete is `common/ability/_ability_index.json.z` — the master ability lookup.
4. At editor startup, every character entity tries to resolve its abilities through the missing index → cascading load failures → tabs can't populate.
5. Worse: the compiler **re-runs on every Zeno launch**, so any files you copy back manually get deleted again.

**Fix — what the scripts in this bundle do automatically.** If you'd rather apply the fix by hand, the steps below are exactly what the scripts execute.

### Step 1 — find which files are failing in *your* install

Open `compiler-0.log.txt` and grep for `FAILED to compile`. Each match is a file you'll need to restore. On a clean Mod… setup against TBS build 2.58.17 / depot 3268685 (May 2026), expect these 8:

```
common/ability/_ability_index.json.z
saga1/locale/fr/convo/part5/cnv_chat_eyvindawaken.json.z
saga1/scene/part2/wld_einartoft_2/wld_einartoft_2.json.z
saga1/scene/map/map_camp.json.z
saga1/scene/part1/wld_grofheim_2/wld_grofheim_2.json.z
saga1/scene/part2/cin_einartoft/cin_einartoft.json.z
saga1/saga1.json.z
saga1/scene/battle/music/frostvellr.btlmusic.json.z
```

Different TBS branches or future patches may produce a different set.

### Step 2 — copy them from the game install into your mod output, then lock

**Git Bash:**
```bash
GAME="/c/Program Files (x86)/Steam/steamapps/common/tbs/assets"
MOD="/c/Users/<you>/tbs_mods/<modid>/assets"
cd "$MOD"
for f in \
  "common/ability/_ability_index.json.z" \
  "saga1/locale/fr/convo/part5/cnv_chat_eyvindawaken.json.z" \
  "saga1/scene/part2/wld_einartoft_2/wld_einartoft_2.json.z" \
  "saga1/scene/map/map_camp.json.z" \
  "saga1/scene/part1/wld_grofheim_2/wld_grofheim_2.json.z" \
  "saga1/scene/part2/cin_einartoft/cin_einartoft.json.z" \
  "saga1/saga1.json.z" \
  "saga1/scene/battle/music/frostvellr.btlmusic.json.z"; do
  mkdir -p "$(dirname "$f")"
  cp "$GAME/$f" "$f"
  attrib.exe +R "$f"
done
```

**PowerShell:**
```powershell
$game = "C:\Program Files (x86)\Steam\steamapps\common\tbs\assets"
$mod  = "C:\Users\<you>\tbs_mods\<modid>\assets"
$files = @(
  "common\ability\_ability_index.json.z",
  "saga1\locale\fr\convo\part5\cnv_chat_eyvindawaken.json.z",
  "saga1\scene\part2\wld_einartoft_2\wld_einartoft_2.json.z",
  "saga1\scene\map\map_camp.json.z",
  "saga1\scene\part1\wld_grofheim_2\wld_grofheim_2.json.z",
  "saga1\scene\part2\cin_einartoft\cin_einartoft.json.z",
  "saga1\saga1.json.z",
  "saga1\scene\battle\music\frostvellr.btlmusic.json.z"
)
foreach ($f in $files) {
  $dst = Join-Path $mod $f
  New-Item -ItemType Directory -Force -Path (Split-Path $dst) | Out-Null
  Copy-Item -Force (Join-Path $game $f) $dst
  (Get-Item $dst).IsReadOnly = $true
}
```

Replace `<you>` and `<modid>` with your values. Verify with `attrib <file>` — each should show `A R`, not just `A`.

### Step 3 — relaunch Zeno

The cascading entity errors should disappear and tabs should populate. The compiler will still log the same 16 errors trying (and failing) to rewrite the locked files — those messages are now expected and harmless. The locked outputs survive.

### Trade-offs

Locking these files means you can't mod the asset types backed by them. As of the May 2026 build:

| Locked file | What's no longer moddable |
|---|---|
| `_ability_index.json.z` | Abilities (already documented as out of scope by Stoic) |
| `cnv_chat_eyvindawaken.json.z` | One French conversation |
| `wld_einartoft_2`, `wld_grofheim_2`, `cin_einartoft`, `map_camp` | Four specific scenes |
| `frostvellr.btlmusic.json.z` | One battle music cue |
| **`saga1.json.z`** | The saga master file — top-level saga structure. **Has a verified source-edit fix — see next section.** |

If you need to mod a different locked file, you'd need to fix the underlying schema issue in its source, then `attrib -R <file>` so the compiler can write a fresh version. We haven't worked out source fixes for the other six.

### `saga1.json.z` — verified source-edit fix (recommended)

`saga1.json.z` is the saga master file. Every other top-level configuration (cast, classes, items, achievements, banners, starting scene, difficulties, music, caravan art, spawn buckets, DLCs, talents, FMOD audio config) hangs off URL references inside it. Leaving it locked freezes all top-level structural changes — individual *content* (items, scenes, conversations, etc.) remains moddable, but registering new top-level content at the saga level is blocked.

Unlike the other six locked files, this one has a fix that's been verified end-to-end: the compiler accepts the edited source, writes a fresh `saga1.json.z`, the editor loads it without errors, and the Saga tab populates with every caravan / variable / happening / scene / bucket the saga defines. Recommended for anyone who'll do more than trivial modding.

**Step 1 — edit `assets-src/saga1/saga1.json`.** Make these source changes (or just apply `saga1.json.patch` included in this bundle):

```json
// REMOVE — property no longer in the SagaDefVars schema:
"fevs": ["saga1/fmod/saga1.fev"],

// ADD all of these — mandatory or newly expected by the schema:
"title_id": "title_tbs1",
"campUrls": [
  "saga1/scene/camp/cmp_snow/cmp_snow.json.z",
  "saga1/scene/camp/cmp_forest/cmp_forest.json.z"
],
"fmodPreloadUrl": "saga1/fmod/preload_banks.json.z",
"talentDefsUrl": "common/character/talent/talents.json.z",
"warPoppeningUrl": "saga1/convo/war/cnv_war.json.z",
"warPoppeningContinueUrl": "saga1/convo/war/cnv_war_decide.json.z",
"warPoppeningImpl": "Action_War_Impl_1",
```

You can leave the original `campMusic` and `id: "saga1"` fields in place — the schema accepts both as still-valid optional properties.

The non-obvious values come from decompressing the game's working `saga1.json.z` (zlib-deflate to AMF3, parse field names from the binary):
- `title_id: "title_tbs1"` — internal saga title identifier.
- `campUrls` — both targets exist as source files in `assets-src`.
- `warPoppeningUrl`, `warPoppeningContinueUrl` — both targets exist as source convos in `assets-src/saga1/convo/war/`.
- `warPoppeningImpl: "Action_War_Impl_1"` — engine class name, baked into the SWF.
- `fmodPreloadUrl` and `talentDefsUrl` point at compiled `.z` files that **do not have corresponding source `.json` files in the DLC.** The compiler tolerates this — it accepts URL string references without validating the source exists. Runtime works because Zeno's initial prep already copied compiled versions of those targets into your mod output during the original setup.

**Step 2 — unlock the compiled file** so the compiler can rewrite it from your edited source:

```bash
attrib.exe -R "C:\Users\<you>\tbs_mods\<modid>\assets\saga1\saga1.json.z"
```

**Step 3 — relaunch Zeno.** Watch `compiler-0.log.txt`. Expected:
```
[INFO]  WRITING all outputs for saga1/saga1.json.z
[ERROR] COMPILE FAILED    :  errs=14, oks=1
```
The `oks=1` is your freshly-compiled saga1. The 14 remaining errors are the other six still-locked files (× 2 ERROR lines each).

**Step 4 — load the saga into the editor.** The Saga tab does **not** auto-load — it stays blank until you explicitly open a saga. Use **File → Open** and select your source `saga1.json` at `assets-src/saga1/saga1.json`. The Caravans / Variables / Scenes / Happenings / Buckets panels then populate.

**Audio sanity-check:** because `fevs` was the old way to reference FMOD `.fev` files and we removed it without setting up an equivalent under the new schema (the DLC doesn't ship the corresponding `preload_banks.json` source), there's a theoretical risk of audio regressions. The runtime *should* still find audio via the compiled-and-locked `preload_banks.json.z` fallback, but verify after first mod export.

### When this might go away

If Stoic ships a Zeno update whose schemas match the DLC sources, the compiler will succeed and none of this is needed. Worth periodically checking Steam → game **Properties** → **Betas** tab for branches like `tip` or `qa` that may have a matching Zeno version.

---

## Happy-path setup, end to end

For a clean first-time install:

1. Install **The Banner Saga** via Steam.
2. Steam → game **Properties** → **DLC** tab → install **TBS - Mod Content**.
3. Launch `tbs\win32\ZenoSaga1\Zeno_saga1.exe`.
4. Click **Mod…**. Enter a Mod Id (lowercase letters / numbers / underscores).
5. **Manually set Game Install Folder** to `C:\Program Files (x86)\Steam\steamapps\common\tbs` (don't trust Default).
6. Leave Asset Root Path and Output URL at their suggested defaults.
7. **OK**. The prep copy runs (a couple of minutes). Green screen → close it.
8. Zeno Settings window appears with the new paths. **OK**. Compilation runs.
9. A "Loading" dialog gets stuck at the end — known bug, just close it manually.
10. **Run `apply-fix.ps1` or `apply-fix.sh`** from this bundle. (Manual equivalent: Steps in Issue 4 + the saga1 source-edit fix.)
11. Relaunch Zeno. You're in.
12. To edit the saga master itself: **File → Open** in Zeno and select `assets-src/saga1/saga1.json`.

---

## Running your mod in the game

After exporting from Zeno (see official doc), launch the game with:
```
"The Banner Saga.exe" -mods <modid>
```
…where `<modid>` matches the Mod Id you set in step 4 and there's a corresponding `tbs\mods\<modid>\` folder.

The in-Zeno **Test → Launch** menu item is broken in this build (`TypeError #1009` in the log) — always launch the game from the command line, not from Zeno.

---

## Known harmless log noise

These appear in `A-0.log.txt` even on a fully-working setup and can be ignored:

- `EntityDef [ekkill] unable to fetch active ability [abl_ekkill]` — one specific ability isn't in the locked index; only matters if you need to mod Ekkill.
- `somebody still listens to .../portrait.clipq` — internal cleanup warnings on portrait clips.
- `DefManager no such url in manifests: saga3/...` and matching `URLResourceLoader.onLoadFailed` — Saga 1 sources contain a stray reference to a Saga 3 file. Doesn't block editing.
- `JSON: BattleMusicDef:[states.useCompleteParam] property not defined in schema` — schema-mismatch warning on the locked battle music file. Expected.

---

*Tested on Windows 11, Zeno build 2.58.17, TBS depot 3268685 (May 2026).*
