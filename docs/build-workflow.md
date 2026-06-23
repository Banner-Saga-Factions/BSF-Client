# Build workflow

## Co-Authored-By: Claude <noreply@anthropic.com>

End-to-end build and packaging for `bsf-client`. For why the repo uses a patch-only model in the first place, see [`architecture.md`](./architecture.md) → "The patch-only repo model".

## The three-step flow

```powershell
.\scripts\decompile.ps1        # 1. JPEXS → _decompiled/  (~1,113 .as files)
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
Exporting actionscript... 1113 / 1113 files written.
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

## Per-target build notes

### Windows (`-target air`)

- Produces a `.air` file. The installer asks the user to install Adobe AIR if not present, then unpacks under `%PROGRAMFILES%`.
- For a one-click installer, use `-target native` (produces `.exe` on Windows) — bundles the AIR runtime.

### Android (`-target apk`)

**Remove the Steamworks ANE before packaging:**

In `META-INF/AIR/application.xml`, delete or comment out the `<extensionID>` block referencing `air.steamworks.ane.SteamworksAneContext` for mobile targets. The Steamworks ANE is Windows/Mac-only — `adt` will fail if you leave it in.

- Sign with the standard Android debug key (`adt -certificate -cn debug 2048-RSA android-debug.p12 debug`) for sideloading; production releases need a real Play Store key.
- The `bsf://` URL scheme registration works on Android via the AIR descriptor's `<android><manifestAdditions>` block.

### iOS (`-target ipa-app-store`)

- Requires an Apple Developer account, a provisioning profile (`.mobileprovision`), and an `iOS Distribution` `.p12`.
- Same Steamworks-ANE-removal step as Android.
- The `bsf://` URL scheme registration is in the AIR descriptor's `<iPhone><InfoAdditions>` block — `CFBundleURLSchemes`.

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
