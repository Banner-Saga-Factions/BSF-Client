# Build workflow

## Co-Authored-By: Claude <noreply@anthropic.com>

End-to-end build and packaging for `bsf-client`. For why the repo uses a patch-only model in the first place, see [`architecture.md`](./architecture.md) → "The patch-only repo model".

## The three-step flow

```powershell
.\scripts\decompile.ps1        # 1. JPEXS → _decompiled/  (~1,272 .as files)
.\scripts\apply-patches.ps1    # 2. src/   → _decompiled/  (overlay patches)
.\scripts\build.ps1            # 3. amxmlc + adt → _build/  (.air, .apk, .ipa)
```

All three scripts are PowerShell — the project is Windows-first. Mac users with HARMAN AIR SDK can run the same scripts under PowerShell Core.

## Prerequisites

| Tool                            | Why it's needed                                 | How to get it                                                                                                                                                                                        |
| ------------------------------- | ----------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Java 11+**                    | JPEXS is a JVM tool.                            | Temurin 21 from https://adoptium.net/ — set `JAVA_HOME` if `java -version` doesn't already work in PowerShell.                                                                                       |
| **JPEXS Free Flash Decompiler** | Extracts AS3 from the SWF.                      | Install to `C:\Program Files (x86)\FFDec\` (the default). Releases: https://github.com/jindrapetrik/jpexs-decompiler/releases                                                                        |
| **HARMAN AIR SDK 33.1+**        | `amxmlc` (compiler) + `adt` (packager).         | https://airsdk.harman.com/ — set `AIR_HOME` env var to the SDK root.                                                                                                                                 |
| **Original SWF v1.10.51**       | Input to `decompile.ps1`. Not committed.        | Default: `C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32\app.game.air.swf`. Fallback: unzip `BannerSagaFactions-client.zip` from the BSF-Custom-Server GitHub release. |
| **Signing certificate**         | `adt` packaging requires a code-signing `.p12`. | See [Signing certificate](#signing-certificate) below for what it is, why AIR requires it, and how to generate one.                                                                                  |

Verify each prerequisite is on the path before running `decompile.ps1`:

```powershell
java -version                              # any 11+
ls "C:\Program Files (x86)\FFDec\ffdec.bat"
$env:AIR_HOME                              # must be set
& "$env:AIR_HOME\bin\amxmlc.bat" -version
```

## Signing certificate

`adt` will not produce an unsigned package — there is no `--no-sign` flag. Every `.air`, `.apk`, and `.ipa` carries a digital signature that serves two purposes:

- **Identity** — cryptographically ties the build to whoever holds the private key, so updates can be verified as coming from the same source as prior releases.
- **Tamper-evidence** — if a packaged file is modified after signing, the signature breaks and the OS refuses to install it.

A `.p12` (PKCS#12) file is a password-protected container holding the **private key** (the secret — never commit or share) and a **certificate** (the public half — embedded in your build so the OS can verify the signature).

For local development, a **self-signed** cert is fine. Generate one in seconds:

```powershell
& "$env:AIR_HOME\bin\adt.bat" -certificate -cn BSF 2048-RSA SIGNING_KEY.p12 yourpassword
```

Drop the resulting `SIGNING_KEY.p12` in the repo root (or pass `-KeystorePath C:\path\to\your.p12` to `build.ps1`). `.p12` files are gitignored. Real Play Store / App Store distribution needs a CA-issued cert — that's covered in the per-target notes below.

## Distribution & certificate identity

You almost certainly **do not have the certificate Stoic originally signed Factions with** — it shipped with the game, not with the source. This section explains exactly what that does (and does not) break when you ship a rebuilt client to players. Short version: it's mostly fine, because this project distributes full repackaged installers rather than AIR auto-updates, and the original shipped through Steam.

**The one rule that governs everything below:** an AIR app's update identity = **app ID + signing certificate**. Two packages can update each other only if they share the app ID _and_ are signed by the same cert (or are bridged by a migration signature). Because you lack Stoic's `.p12`, every build you make is — to AIR — a _different publisher_ than the shipped client. There is no workaround for that fact; only its consequences matter, and they're manageable.

### What players experience

| Audience                                                | What happens                                                                                                                                                                                  | Why                                                                                                                                                                                                                                                                              |
| ------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Existing players** (already have the Steam Factions install) | Your rebuilt client installs as a **separate** app and coexists with the Steam copy — no certificate clash. Their local save data (`global_0.sol`, cached account / roster / news) **carries over**. | Steam dropped the original on disk itself; it was never registered through the AIR installer, so there is no AIR-managed "original" for your build's cert to collide with. Save data survives because AIR keys local storage to the **app ID** — unchanged at `TheBannerSagaFactions` — not the cert. _(See assumptions.)_ |
| **New players** (first-ever install)                    | Clean install. Only wart: a self-signed cert shows an **"unknown publisher"** prompt, and on Windows, SmartScreen may flag the `.exe`. Functionally fine.                                       | No prior app exists, so nothing to conflict with. Self-signed certs aren't vouched for by a certificate authority, hence the warnings.                                                                                                                                            |

### Your cert is the new permanent baseline

Whatever cert you sign your **first public build** with, reuse it for **every** future update — forever:

- **Same cert across your builds** → they update each other cleanly.
- **Different cert between two of _your own_ builds** → the AIR installer refuses to install one over the other ("already installed by a different publisher"); players must uninstall first. This is the main _self-inflicted_ trap — avoid it by never rotating the cert.
- You can **never** make a build that updates Stoic's original in place. `adt`'s `-migrate` flag (sign with a new cert _plus_ a signature from the old one) is the official bridge for a cert change, but it requires the **old** cert — which you don't have. So migrating from the original is impossible; establish your own cert as the baseline and move on.

**Practical guidance:** generate **one** signing cert with a long validity, back up the `.p12` as a permanent project asset, and store its password where you won't lose it. Losing it re-creates this entire problem against your _own_ prior releases. A CA-issued code-signing cert (instead of self-signed) removes the SmartScreen / "unknown publisher" warnings but is **not** required for the game to run.

### Mobile

Factions originally shipped on **Windows and macOS only** — there was never a mobile release. So there is no "existing mobile install" to update: any Android / iOS build (see the per-target notes below) is a brand-new app signed with **your own** key from day one, free of the cross-cert concerns above. Mobile signing has its own rules — Android update keys must match across versions; iOS requires your own Apple Distribution cert — but those only ever involve _your_ keys, never Stoic's.

### Assumptions

These claims rest on a few things worth verifying before you rely on them with real players:

- **[Assumption — medium confidence]** The original Factions was distributed via **Steam as plain on-disk files**, not installed through the Adobe AIR Application Installer. This is why a rebuilt client with a different cert coexists with the Steam copy instead of being rejected at install time. _Verify on one real machine before publishing install instructions_ — captive-runtime vs. shared-runtime packaging can change install-over behavior.
- **[Assumption — high confidence]** Local save data survives a cert change because the descriptor has **no `<publisherID>`** (commented out in `META-INF/AIR/application.xml`) and targets AIR namespace ≥ 1.5.3 (it uses `3.7`), so AIR derives the storage path from the **app ID alone**. This continuity breaks the moment you change `<id>` — keep it as `TheBannerSagaFactions`.
- **[Fact — per project history]** Factions released on Windows / macOS only; the Android / iOS targets in this repo are new crossplay work, not updates to any prior mobile app.

## Step 1 — `decompile.ps1`

JPEXS exports the SWF's AS3 bytecode to source. Output lands in `_decompiled/` (gitignored). Typical runtime: 60–120 seconds; first run can be slower as JPEXS caches font/asset tables.

Common output:

```
JPEXS scanning frames... 1/47 ... 47/47
Exporting actionscript... 1272 / 1272 files written.
```

After this, `_decompiled/` mirrors the package layout described in [`subsystem-index.md`](./subsystem-index.md): `engine/`, `game/`, `tbs/`, `lib/` plus root-level `GameMainAir.as` and `AneFixer.as`.

**Troubleshooting:**

- _"JPEXS not found"_ — set the install path explicitly: `$env:JPEXS_HOME = "C:\Program Files (x86)\FFDec"` and re-run.
- _"Cannot open SWF"_ — the script defaults to the Steam install path. If your SWF lives elsewhere, edit the path at the top of `decompile.ps1` or pass it as an argument.
- _"Out of heap space"_ — JPEXS by default uses 512 MB. Edit `ffdec.bat` to bump `-Xmx` to `2g`.

## Step 2 — `apply-patches.ps1`

Copies every file under `src/` onto its mirror path in `_decompiled/`, overwriting the decompiled version. Idempotent — running it twice in a row is harmless.

Today's `src/` is intentionally small:

| File                                      | Replaces                                                                            |
| ----------------------------------------- | ----------------------------------------------------------------------------------- |
| `src/game/session/states/PreAuthState.as` | `_decompiled/game/session/states/PreAuthState.as` (Steam-auth bypass for crossplay) |
| `META-INF/AIR/application.xml`            | (does not overlay — used directly by `adt` in step 3)                               |

To add a new patch: drop a file at `src/<same-package-path>/<ClassName>.as` and re-run.

## Step 3 — `build.ps1`

Two phases.

### Phase A — `amxmlc` compile

```
amxmlc -source-path=_decompiled -output=_build/bsf.swf _decompiled/GameMainAir.as
```

The compiler walks every `.as` file referenced from `GameMainAir.as`, transitively. Compile time: 20–40 seconds.

### Phase B — `adt` package

```
adt -package -storetype pkcs12 -keystore SIGNING_KEY.p12 \
    -target <target> _build/<output> META-INF/AIR/application.xml _build/bsf.swf assets/ gui/
```

Per target:

| Target  | Output           | adt `-target` flag                                     |
| ------- | ---------------- | ------------------------------------------------------ |
| Windows | `_build/bsf.air` | `air` (cross-platform) or `native` (Windows installer) |
| Android | `_build/bsf.apk` | `apk` or `apk-debug`                                   |
| iOS     | `_build/bsf.ipa` | `ipa-ad-hoc` or `ipa-app-store`                        |

## Audio & the FMOD ANE

Sound is the one subsystem that routinely runs in a **degraded** (reduced-capability) mode during development, and knowing why saves a lot of head-scratching. All audio goes through a small driver interface — `ISoundDriver` (`engine/sound/ISoundDriver.as:8`) — with two implementations:

| Driver | Where | What it does |
|---|---|---|
| `FmodSoundDriver` | `air/fmod/ane/FmodSoundDriver.as:20` | The real thing. It reaches the native FMOD audio engine through an **ANE** (AIR Native Extension — a bundle of native OS code an AIR app can call into), opening the extension by id (`CONTEXT_ID = "air.fmod.ane.FmodContext"`, `:23`) via `ExtensionContext.createExtensionContext` (`:284`). |
| `NullSoundDriver` | `engine/sound/NullSoundDriver.as:9` | A silent stand-in. Every method is a no-op — `init()` just returns `true` (`:74`) and events play nothing. The game runs normally, minus sound. |

**Which driver you get is decided at startup, and it can downgrade silently.** `GameMainAir.as:163` hardcodes `FmodSoundDriver` as the intended driver (`new GameWrapper(0, appInfo, FmodSoundDriver, false)`); that class is threaded through `GameWrapper` (`:89`) into `GameConfig.soundDriverClazz` (`:287`) and handed to `FmodSoundSystem.init` (`engine/sound/config/FmodSoundSystem.as:74`). `init` **tries** to build the FMOD driver and, if anything goes wrong, quietly falls back — the `if (!driver)` branch (`:96–99`) constructs a `NullSoundDriver` instead and carries on. Three things trigger the fallback:

- **Sound is disabled** — `init` skips the FMOD attempt entirely.
- **The ANE is absent or won't load** — constructing `FmodSoundDriver` throws, and the `catch` nulls the driver.
- **`driver.init()` returns `false`** — the native side reported failure.

The downgrade is invisible to the rest of the game because everything downstream only talks to the `ISoundDriver` interface. Startup even gates on the sound system being "ready" (`GameConfig.checkReady:724` waits for `fevPreloader.complete`), but `NullSoundDriver`'s preloader reports complete immediately (`NullFevPreloader.complete` is hardcoded `true`, `NullSoundDriver.as:188`), so a silent client still boots.

Both ANEs are **declared** in the descriptor (`META-INF/AIR/application.xml:145–148` — `air.fmod.ane.FmodContext` and `air.steamworks.ane.SteamworksAneContext`), but the `.ane` binaries themselves are not committed to this patch repo. That is why the dev launcher strips them (see "The AIR SDK 33-vs-51 wall" below) and the client runs on `NullSoundDriver` day to day.

### The local two-client hang

This is the one FMOD quirk that will eat an afternoon if you don't know it. **FMOD's ANE initializes only once per machine.** So when `launch-game-2p.ps1` opens two clients on the same PC to test a battle, the *first* gets the real `FmodSoundDriver` and the *second* falls back to `NullSoundDriver`. The two clients then load resources along **different paths**, and that asymmetry wedges the FMOD-side client:

1. The FMOD-side client loads its sound banks (`common/fmod/character_quality_*.fsb`). A side effect of `FmodSoundDefBundle.fsbLoadedHandler` (`air/fmod/ane/FmodSoundDefBundle.as:121`) **leaks an item** in the page's loading tracker (`GamePage.monitor` — the resource monitor from [`asset-loading.md`](./asset-loading.md)).
2. Because that tracker never empties, `ScenePage.handleLoaded()` never re-fires, so `doInitReady()` (`game/gui/page/ScenePage.as:366`) never runs.
3. `doInitReady` is what calls `BattleStateInit.setReady()` (`engine/battle/fsm/state/BattleStateInit.as:53`). Without it the client never sends its local `POST services/battle/ready` (`BattleTxnStartSend`), so the battle's init state **hangs forever** waiting to be told it's ready.

A workaround patch is drafted in **Banner-Saga-Factions/BSF-Client#7** (a 15-second timeout in `BattleStateInit` that force-calls `setReady()`), but it is **not applied** — it needs a full SWF rebuild. The practical fix is what `launch-game-2p.ps1` already bakes in: `--versus_start --versus_countdown 0` skips the wait. **This is a same-machine artifact only** — a real 1-v-1 across two separate machines gives both clients real FMOD, so they either both race past it or both dodge it. The authoritative write-up (kept on the server side, since that is where the missing `/battle/ready` is noticed) is `bsf-server/.claude/rules/gotchas.md` ([local](../../bsf-server/.claude/rules/gotchas.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/.claude/rules/gotchas.md)).

## The AIR SDK 33-vs-51 wall

The prerequisites table above lists "HARMAN AIR SDK 33.1+," but the config that actually **runs** the rebuilt client is **SDK 51** — and the gap between those two numbers is a wall with real consequences.

The original SWF was built against **AIR 3.7** (`META-INF/AIR/application.xml:2` declares the `air/application/3.7` namespace; the SWF is version 20, stamped 2013). That 2013-era runtime ships with the Steam install and is what a packaged client would normally run on. But the moment you recompile with a modern SDK, three things bite:

1. **The 2013 captive runtime can't run a modern SWF.** A SWF compiled with SDK 51 links against newer APIs the old runtime lacks, so it fails to load with a silent `VerifyError`. The workaround is `scripts/run-adl.ps1`, which launches the compiled SWF under the **SDK 51 debug runtime** (`adl`) instead of the captive one. To do that it rewrites the descriptor's namespace from `3.7` to `51.0` (`run-adl.ps1:49`) and **strips the `<extensions>` block** (`:50`) — which is exactly why running under `adl` drops you to `NullSoundDriver` (no ANEs declared, so the audio fallback above fires). `build.ps1` compiles with `-swf-version=20` (`:67`) and flags this same runtime mismatch inline (`:62–65`).
2. **You can't package a real audio build for desktop.** `adt` (the packager) **rejects the FMOD and Steamworks ANEs on desktop targets with error 112** (`build.ps1:11–12`), so there is no signed, double-clickable build that has sound. Today the only way to run the rebuilt client is under `adl` — which has no ANEs anyway.
3. **The 33→51 jump is *not* the cause of the town crashes.** It is tempting to blame the SDK bump for the gui-SWF crashes, but that was **ruled out** (verified four ways): those crashes are a **symbol-linkage** problem — owned by [`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution" — which is version-independent. The gui SWFs ship unchanged as their AIR-33.1 originals; only the app SWF recompiles at 51.

There is an **untested candidate fix** for the packaging wall (points 1–2): rebuild the app SWF with the **original HARMAN AIR SDK 33.1** and package via `adt` with the ANEs, to see whether a same-generation build runs standalone with sound and clears the error-112 rejection. It would **not** touch the town crashes (point 3). The full experiment plan and the four-way SDK-hypothesis verdict are in [`../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`](../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md).

## Common JPEXS artifacts and how to fix them

The decompile is ~95 % compilable as-is. The 5 % that fails almost always falls into these buckets:

| Symptom                                         | Cause                                                                                       | Fix                                                                                                       |
| ----------------------------------------------- | ------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `Method must be marked override`                | JPEXS lost an `override` keyword that the bytecode implied.                                 | Add `override` to the offending method, in `src/` (not in `_decompiled/` — patches survive re-decompile). |
| `Incompatible override`                         | Decompiler picked the wrong type for a parameter that was a base class in the bytecode.     | Widen the type in `src/` (`* `, `Object`, or the actual base class).                                      |
| `Cannot resolve attribute` on a `private` field | A method references a private field of another class — decompile artifact, not real source. | Make the field `internal` or add a public getter, in `src/`.                                              |
| Compile loops forever                           | A circular `import` was reconstructed incorrectly.                                          | Move the offending `import` block to the top of the file or fold the class into its caller.               |

Patches **belong in `src/`**, never in `_decompiled/` — anything in `_decompiled/` is wiped on the next `decompile.ps1` run.

For deeper guidance on AS3 patch hygiene, see [`bsf-client/CLAUDE.md`](../CLAUDE.md) → "AS3 Coding Standards" and "Refactoring Protocol".

## Patching a resource gui SWF (`patch-gui-swf.ps1`)

The three-step flow above only rebuilds `app.game.air.swf`. The **resource gui SWFs** (`great_hall.swf`, `mead_house.swf`, `battle_initiative.swf`, …) ship as Stoic's originals and are never recompiled — so when the bug is in a **symbol-linked** class baked into a resource SWF (or a getter-called-as-a-function, `#1006`), no `src/` overlay can reach it. The only fix is to edit that SWF's bytecode directly with JPEXS. See [`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution" for _when_ this is the right mechanism (vs. an app-side shim or a domain reroute).

`scripts/patch-gui-swf.ps1` is the worked example: it fixes the Ranked-match crash (`#1006`) by swapping one AVM2 instruction in `great_hall.swf`. It reads the install SWF **read-only** and writes a patched **copy** to `_build/great_hall.patched.swf` — it does **not** install anything (Ranked is online-only, so that patch stays shelved). Use it as a template for future resource-SWF patches.

The hard-won, reusable parts of the recipe (these cost a session to rediscover the first time):

- **First, find _every_ call site — sibling classes in the same SWF often share the drift.** A method-turned-getter (or a dropped property) is usually called from more than one place. Before patching, `grep -rn` the whole extracted tree (`_decompiled/gui/<swf>/`) for the member and patch each site (or explicitly document the ones you defer). Real example: the Ranked `totalPower()` fix in `GuiGreatHallBannerVersus` has identical, separate twins in `GuiGreatHallBannerTournament` (`onTourneyBannerClick`, `onJoinClick`) — same SWF, different method-body indices — that a Versus-only patch silently misses.
- **`-replace` addresses AS3 method bodies by their _global_ index in the SWF's ABC**, not by class+method: `ffdec -replace <in> <out> "<dotted.class.Name>" <pcode-file> <methodBodyIndex>`. There's no clean CLI way to read that index (`showMethodBodyId` / `-config export.formats=…` are GUI-only — see the last bullet), so derive it once by sweep, then **bake it in with a verification guard** (intrinsic to a fixed asset, so it won't drift — but the guard aborts rather than emit a bad patch if the SWF is ever replaced):
  1. Export the class P-code: `ffdec -selectclass <Class> -format script:pcode -export script <dir> <swf>`.
  2. For a candidate index _i_, `-replace` your edited method block into a throwaway output, re-export, and check whether the target instruction disappeared from the class.
  3. The single _i_ whose patch is the _only_ one that removes the instruction is the method-body index. Narrow the sweep first: replacing an arbitrary index and re-exporting reveals which class that index belongs to, so you can home in on the target class's block (indices run roughly in script order).
- **Import the whole `method … end ; method` block, not just the `body`.** A body-only import silently drops the method's parameter signature (`foo(param1:T)` → `foo()`); a 0-param method later invoked _with_ an argument throws AVM2 `#1063` at call time — you'd trade one crash for another.
- **The getter-as-function fix is `callproperty X, 0` → `getproperty X`.** Identical stack effect (both pop the receiver, push one value). The patched body is one byte shorter (no arg-count operand), so JPEXS renumbers the method's jump-offset labels (`ofs0064` → `ofs0063`); that renumbering is cosmetic, not a behavior change.
- **Verify by re-decompiling the _patched copy_ and diffing its P-code against the original** — the only lines that may differ are the swapped instruction and those `ofs####` labels. Also hash the input SWF before/after to prove it was untouched. `patch-gui-swf.ps1` runs all of these checks itself and deletes its output if any fails.
- **Don't trust the GUI-only knobs from the CLI.** `showMethodBodyId` and `-config export.formats=…` do _not_ annotate the CLI P-code export with method indices (they affect the JPEXS GUI panel only) — which is why the index has to be derived by the sweep above.

## Per-target build notes

### Windows (`-target air`)

- Produces a `.air` file. The installer asks the user to install Adobe AIR if not present, then unpacks under `%PROGRAMFILES%`.
- For a one-click installer, use `-target native` (produces `.exe` on Windows) — bundles the AIR runtime.

### Android (`-target apk`)

**Remove the Steamworks ANE before packaging:**

In `META-INF/AIR/application.xml`, delete or comment out the `<extensionID>` block referencing `air.steamworks.ane.SteamworksAneContext` for mobile targets. The Steamworks ANE is Windows/Mac-only — `adt` will fail if you leave it in.

- Sign with the standard Android debug key (`adt -certificate -cn debug 2048-RSA android-debug.p12 debug`) for sideloading; production releases need a real Play Store key.
- The `bsf://` URL scheme registration **would** be added for Android via an `<android><manifestAdditions>` block — **planned; not yet in the committed descriptor** (`META-INF/AIR/application.xml` has no `<android>` block today).

### iOS (`-target ipa-app-store`)

- Requires an Apple Developer account, a provisioning profile (`.mobileprovision`), and an `iOS Distribution` `.p12`.
- Same Steamworks-ANE-removal step as Android.
- The `bsf://` URL scheme registration **would** go in the `<iPhone><InfoAdditions>` block as `CFBundleURLSchemes` — **planned; not yet in the committed descriptor** (the current `<iPhone>` block declares only `UIDeviceFamily`).

## "I just want to point the client at my custom server"

You don't need to rebuild anything. Pass `--server` as a launch argument to the AIR executable:

```powershell
& "C:\Program Files (x86)\The Banner Saga Factions\TheBannerSagaFactions.exe" --server "http://localhost:8080/"
```

This overrides `serverHostsLive` in `GameMainAir.as:381–385`. The rest of the build pipeline is only needed if you're actually patching `.as` code. See [`architecture.md`](./architecture.md) → "Configuration hierarchy" and [`wire-protocol.md`](./wire-protocol.md).

## Related reading

- [`README.md`](../README.md) — quick-start version of this doc.
- [`architecture.md`](./architecture.md) — what gets built and why.
- [`bsf-client/CLAUDE.md`](../CLAUDE.md) — AS3 coding standards and patch-file rules.
- [`reference-codebases.md`](./reference-codebases.md) — when to read 2013 source vs decompile.
