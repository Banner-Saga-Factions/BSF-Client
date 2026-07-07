# BSF-Client

## Co-Authored-By: Claude <noreply@anthropic.com>

Patched ActionScript 3 source for The Banner Saga Factions game client, built on top of the
original AIR/Flash client decompiled with JPEXS. Goal: enable mobile/Windows crossplay by
replacing Steam auth with Discord OAuth and adding a `bsf://` deep-link URL scheme.

See [`docs/`](./docs/) for architecture, build workflow, wire-protocol reference,
and the client-side bsf-refs guide. The original analysis at
`bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md))
is the canonical historical artifact and is cited throughout the new docs.

## Documentation

| Doc | Purpose |
| --- | --- |
| [`docs/README.md`](./docs/README.md) | Doc index — start here. |
| [`docs/client-overview.md`](./docs/client-overview.md) | The whole client in one read: what it is, how it boots, and the four pillars. |
| [`docs/game-flow.md`](./docs/game-flow.md) | The `GameFsm` spine — its states, the server actions, and the generic FSM base. |
| [`docs/architecture.md`](./docs/architecture.md) | Patch-only repo model, runtime stack, `GameMainAir` boot sequence, and the resource-SWF crash model. |
| [`docs/build-workflow.md`](./docs/build-workflow.md) | Decompile → patch → build flow, prerequisites, per-target packaging, FMOD audio + the AIR SDK wall, JPEXS fixes. |
| [`docs/wire-protocol.md`](./docs/wire-protocol.md) | Client side of every `/services/*` route, login flow, long-poll mechanics. |
| [`docs/battle-engine.md`](./docs/battle-engine.md) | Battle FSM, entity ID format, DJB hash mechanics, common desync patterns. |
| [`docs/ui-system.md`](./docs/ui-system.md) | The visible client: the two widget roots, the page/screen framework, and the battle HUD. |
| [`docs/asset-loading.md`](./docs/asset-loading.md) | The resource-loading pipeline beneath UI **and** battle/anim/sound. |
| [`docs/subsystem-index.md`](./docs/subsystem-index.md) | "Where do I look for X?" package-by-package class map with decompile and 2013-source paths. |
| [`docs/reference-codebases.md`](./docs/reference-codebases.md) | Guide to the three client mirrors under `bsf-refs/` and the 12-stale-file exception list. |
| [`docs/patch-inventory.md`](./docs/patch-inventory.md) | Everything in `src/` — the fork's 33 overlays grouped by concern, each with what/why. |
| [`docs/doc-gaps.md`](./docs/doc-gaps.md) | The tracked, closeable list of remaining client-doc gaps. |

## Prerequisites

| Tool                        | Notes                                                                                                                                                                                                                   |
| --------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Java 11+                    | Required by JPEXS. Install Temurin 21 from https://adoptium.net/                                                                                                                                                        |
| JPEXS Free Flash Decompiler | Install to `C:\Program Files (x86)\FFDec\` — https://github.com/jindrapetrik/jpexs-decompiler/releases                                                                                                                  |
| HARMAN AIR SDK 33.1+        | Set `AIR_HOME` env var to SDK root — https://airsdk.harman.com/                                                                                                                                                         |
| Original SWF (v1.10.51)     | Not included. Default path: `C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32\app.game.air.swf`. Fallback: unzip `BannerSagaFactions-client.zip` from the BSF-Custom-Server GitHub release. |

## Build workflow

```powershell
# 1. Export all ~1,272 AS3 files from the original SWF to _decompiled/
.\scripts\decompile.ps1

# 2. Overlay the patch files from src/ onto the decompile output
.\scripts\apply-patches.ps1

# 3. Compile and package
.\scripts\build.ps1 -Target windows    # or: android, ios
```

## What lives in this repo

| Path                           | Purpose                                                                                   |
| ------------------------------ | ----------------------------------------------------------------------------------------- |
| `src/`                         | Only the files being patched or added — applied over the decompile by `apply-patches.ps1` |
| `META-INF/AIR/application.xml` | AIR app descriptor — **planned** to add the `bsf://` URL scheme for the Discord OAuth callback (not yet in the committed descriptor)       |
| `scripts/decompile.ps1`        | Runs JPEXS to export the full AS3 source into `_decompiled/`                              |
| `scripts/apply-patches.ps1`    | Copies `src/` onto the decompile output before compilation                                |
| `scripts/build.ps1`            | Compiles with `amxmlc`, packages with `adt`                                               |

`_decompiled/` and `_build/` are gitignored and regenerated by the scripts above.

## Crossplay patch files

| File                                         | Change                                                                                       |
| -------------------------------------------- | -------------------------------------------------------------------------------------------- |
| `src/game/session/states/PreAuthState.as`    | Replace Steam ticket fetch with Discord OAuth token                                          |
| `src/engine/steamworks/DiscordSteamworks.as` | **Planned — not yet created.** Intended `ISteamworks` stub feeding Discord credentials through the existing Steam auth path; crossplay currently lives in `PreAuthState.as` |
| `META-INF/AIR/application.xml`               | **Planned — not yet applied.** Add the `bsf://` URL scheme and remove the Steamworks ANE for mobile targets                            |

Server-side prerequisites are tracked in `bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md` ([local](../bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md)).

## Build notes

- `build.ps1` is a starting template. First compile will likely surface a handful of JPEXS
  decompiler artifacts (missing `override`, minor type mismatches). Fix them one at a time —
  the output is ~95% compilable as-is.
- For mobile builds, remove the `air.steamworks.ane.SteamworksAneContext` `<extensionID>`
  from `application.xml` before running `adt`.
- Replace `SIGNING_KEY.p12` in `build.ps1` with your actual certificate path. Never commit
  the `.p12` file — it is gitignored.
- Server URL does not require a SWF recompile. Pass `--server https://your-domain/` as a
  launch argument to the AIR executable instead.
