# Patch inventory — everything in `bsf-client/src/`

## Co-Authored-By: Claude <noreply@anthropic.com>

This is the **complete, durable map** of what our fork actually changes. `src/` holds the patch files
that get overlaid on the freshly-decompiled `_decompiled/` tree at build time (see
[`architecture.md`](./architecture.md) → "The patch-only repo model"). Every pillar doc links here for
its "where does our fork touch this?" answer, so this is the single source of truth — not a table
buried in a plan.

## The shape of `src/`

| What | Count | Notes |
|---|---|---|
| Patched/added `.as` overlays | **33** | The behavior + repair surface below. |
| Embedded font glyph data | 3 `.cff` | `src/_assets/*.cff` — the outlines the three font wrappers re-embed. |
| AIR descriptor | 1 | `META-INF/AIR/application.xml` — **outside `src/`**; declares the `extendedDesktop` profile (needed by the mod bridge's NativeProcess) and lists the platform ANEs (Adobe Native Extensions — bundled native-code plugins, e.g. Steamworks and FMOD). Adding the `bsf://` URL scheme is **planned — not yet in the committed descriptor**. |

**Two kinds of patch.** Roughly a third of the 33 overlays change **no behavior at all** — they are
faithful repairs of code the JPEXS decompiler mangled (illegal class names, lost imports, raw
bytecode opcodes). The rest are real fork changes: crossplay, offline AI, the mod bridge, and gui
compatibility. Each row below says which it is.

> **`DiscordSteamworks.as` is *planned*, not present.** Several docs and `scripts/run-adl.ps1` refer to
> a `DiscordSteamworks` crossplay driver. It does **not** exist in `src/` or in `_decompiled/` yet —
> the crossplay auth patch currently lives entirely in `PreAuthState.as`. Treat any reference to
> `DiscordSteamworks` as a not-yet-created plan.

---

## Crossplay & startup (2)

| File | What changed | Why |
|---|---|---|
| `src/GameMainAir.as` | The AIR entry point and top of the boot spine (see [`client-overview.md`](./client-overview.md)). | Overlaid so the boot path can wire the fork's additions. `[Inference]` — there is no in-file patch comment; its role is confirmed by its imports (`FmodSoundDriver`/`NullSoundDriver`, `SteamworksAne`, `GameWrapper`, `GameConfig`). |
| `src/game/session/states/PreAuthState.as` | When `overrideSteamId` is set, replaces the Steam auth-ticket fetch with the crossplay bypass token (`:31–33`, sets `steamAuthTicket = "override-authticket"`). | The documented crossplay auth patch point — trace it in [`wire-protocol.md`](./wire-protocol.md) → login flow. |

## Mod bridge (2)

| File | What changed | Why |
|---|---|---|
| `src/engine/mod/ModBridge.as` | **New file.** A bidirectional bus to an external mod-host process launched via NativeProcess (`mods/host.exe`): one JSON object per newline-terminated line, a command registry, and a restart/shutdown lifecycle. If the host is missing it marks itself failed once and every emit becomes a cheap no-op. | The fork's non-Stoic scripting hook. Full wire protocol is in the file's own doc block; narrative in [`mod-bridge.md`](./mod-bridge.md). |
| `src/engine/core/http/HttpAction.as` | Taps every outbound request (`doSend`) and raw response (`onResponseReceived`) into `ModBridge`, lazy-starting the host on the first transaction (`:136`, "PATCH begin"). | Lets a mod observe all server traffic without touching each individual action. |

## Offline player-vs-AI (9)

The self-contained battle against the game's dormant AI. It reuses the same battle FSM + per-turn sync
hash as multiplayer ([`battle-engine.md`](./battle-engine.md)); design write-up in [`offline-ai.md`](./offline-ai.md).

| File | What changed | Why |
|---|---|---|
| `src/game/session/states/AiBattleLoadState.as` | **New file.** Loads an offline battle vs the dormant AI (`extends SceneLoadState`). Sets no opponent name → the battle computes `isOnline=false` → **zero** server calls. Two modes: player-vs-AI and AI-vs-AI spectator. | The entry point for the whole offline feature. |
| `src/engine/battle/fsm/aimodule/AiModuleBase.as` | Guards a null `atkStr`/`atkArm` for a unit that lacks that stat, during AI target scoring (`:46`). | `[Inference]` BSF-Client #12 — an armor-only unit crashed the AI's scoring. |
| `src/engine/battle/fsm/aimodule/AiPlan.as` | Guards a null ability returned by `getFirstAbilityByTag(ATTACK_STR)` during AI planning (`:235`). | `[Inference]` BSF-Client #12 — same class of null-stat crash on the planning side. |
| `src/engine/battle/board/model/BattleBoard.as` † | Adds a CPU-controlled party, fully deployed up front (`:483`). | So an offline battle has an opponent with no human deploy step. |
| `src/engine/scene/model/SceneLoader.as` | Injects a mirrored CPU roster into the opposite deployment area (`:51`). | Builds the AI's side of the board from a mirror of the player's party. |
| `src/game/session/states/SceneLoadState.as` | Handles the `AI_OPPONENT_PARTY` when set by `AiBattleLoadState` (`:89`). | Threads the offline opponent through the shared scene-load path. |
| `src/game/session/GameFsm.as` | Registers the offline load's exits (same shape as `SceneLoadState`) (`:148`). | Wires the new offline states into the top-level machine. |
| `src/game/session/states/GameStateDataEnum.as` | Adds the offline vs-AI mode data key (`:86`). | The typed flag that marks a session as an offline/spectator battle. |
| `src/game/cfg/GameKeyBinder.as` | Adds a dev trigger — Ctrl+Shift+A launches an offline player-vs-AI battle (`:15`). | A developer shortcut into the feature. (Flagged as a public-release hardening item — the raw chord can fire in unintended contexts.) |

## Battle HUD & gui compatibility (7)

Shims and guards that keep the older UI code baked into the **resource gui SWFs** from crashing against
the modern app. Read [`architecture.md`](./architecture.md) → "Resource SWFs and runtime class
resolution" first — it explains *why* a shim reaches some crashes and not others.

| File | What changed | Why |
|---|---|---|
| `src/game/gui/GameGuiContext.as` | Re-adds context members Stoic moved onto `Legend`, delegating to `legend.*`: the `party`/`renown` getters (`:342`, `:347`) and the Mead-House hire members `rosterSlotAvailable`/`purchaseRosterUnit` (`:355`, `:360`). | `[Inference]` Fixes `#1069 (property not found)` when a stale gui SWF calls a member the modern context dropped. |
| `src/game/gui/IGuiContext.as` | The same re-adds on the context **interface** — `party`/`renown` (`:80`, `:82`) and `rosterSlotAvailable`/`purchaseRosterUnit` (`:86`, `:88`). | Keeps the interface and its implementations in agreement. |
| `src/game/gui/mock/MockGuiContext.as` | Mirrors the `party`/`renown` additions in the mock/test context (`implements IGuiContext`, imports `Legend`). | So the mock still satisfies the interface after the shim. `[Inference]` — inferred from its imports; no in-file comment. |
| `src/game/gui/InfoBarHelper.as` | Guards the unguarded `guihud.initiative.infobar` chain (`:98`). | `[Inference]` BSF-Client #12 — a null in that chain crashed the HUD. |
| `src/game/gui/GuiUtil.as` | Guards a null child parameter (`:136`). | `[Inference]` BSF-Client #12 — this is the **by-name reroute target**: routing `battle_initiative.swf` into the current domain makes the gui-SWF's `GuiInitiative` resolve *this* guarded `GuiUtil`, absorbing the null. |
| `src/game/gui/page/BattleHudPageLoadHelper.as` | Guards the initiative-SWF load-completion race (`:422`). | `[Inference]` BSF-Client #12 finding #2 — the initiative SWF can finish loading at an awkward moment. |
| `src/game/gui/battle/initiative/GuiInitiative.as` | **Inert overlay.** The file's own doc block records that the gui-SWF's copy wins symbol linkage and runs instead of this one, so this app copy does **not** execute at runtime. | Retained for the speculative frame-left guards and as the reference for the reroute mechanism. A worked example of the gui-SWF blind spot ([`architecture.md`](./architecture.md)). |

## Resource & scene loading (2)

| File | What changed | Why |
|---|---|---|
| `src/engine/resource/loader/DisplayResourceLoader.as` | Routes `battle_initiative.swf` into `ApplicationDomain.currentDomain` (`:61`). | `[Inference]` BSF-Client #12 "Crash A" — makes the gui-SWF's by-name `GuiUtil` resolve to our guarded copy. Fixed the reliable crash across long offline battles. |
| `src/engine/resource/ResourceTree.as` | Decompiler-artifact repair: file-internal classes (declared after the package block) don't inherit the file's imports (`:84`). | **No behavior change** — a faithful compile fix. |

## Board, landscape & battle-move rendering — decompiler repairs (4)

All four are **no-behavior-change** repairs of decompiler damage.

| File | What changed |
|---|---|
| `src/engine/battle/board/view/indicator/EntityFlyText.as` † | File-internal-classes import repair (`:136`). |
| `src/engine/battle/fsm/BattleMove.as` | File-internal-classes import repair (`:706`). |
| `src/engine/landscape/view/LandscapeView.as` | Repairs raw AVM2 iterator opcodes (`hasnext`/`hasnext2`) the decompiler left as-is (`:293`). |
| `src/engine/tile/Tiles.as` | File-internal-classes import repair (`:220`). |

## Fonts (4 overlays + 3 assets) — decompiler repairs

| File | What changed |
|---|---|
| `src/MinionProBoldFont.as`, `src/MinionProRegularFont.as`, `src/VinqueFont.as` | Faithful rename of the decompiler's illegal-named embedded-font wrapper classes (`:5`). |
| `src/starling/text/BitmapFont.as` | File-internal-classes import repair (`:400`). |
| `src/_assets/*.cff` (3) | The embedded glyph outlines the three font wrappers re-embed (Vinque, Minion Pro Regular, Minion Pro Bold). |

## Audio (1)

| File | What changed | Why |
|---|---|---|
| `src/engine/sound/NullSoundDriver.as` | File-internal-classes import repair of the no-op sound driver (`:165`). | **No behavior change.** The FMOD-vs-`NullSoundDriver` fallback story (which causes the local-2-client init hang) is documented in [`build-workflow.md`](./build-workflow.md) → "Audio & the FMOD ANE". |

## Saga (1)

| File | What changed | Why |
|---|---|---|
| `src/game/saga/GameSaga.as` | Overlaid; `extends` the engine `Saga`, overrides scene-state save/restore, and imports the offline scene states. | `[Inference]` — part of the offline / single-player scene-state plumbing (see [`offline-ai.md`](./offline-ai.md)). The exact change is **not** called out in an in-file comment; treat as inferred. |

## View (1)

| File | What changed | Why |
|---|---|---|
| `src/game/view/TutorialTooltip.as` | Hand-repaired: the CLI decompile of this file was badly corrupted (unrecoverable) (`:12`). | **No behavior change** — a rescue of a file JPEXS could not lift cleanly. |

---

## Count reconciliation

33 `.as` overlays = 2 (crossplay/startup) + 2 (mod bridge) + 9 (offline AI) + 7 (gui) + 2 (resource) +
4 (board/landscape) + 4 (fonts) + 1 (audio) + 1 (saga) + 1 (view). Of these, **~11 are pure
decompiler-artifact repairs** with no behavior change (`ResourceTree`, the four
board/landscape repairs, the four font repairs, `NullSoundDriver`, and `TutorialTooltip`) — the honest "real
fork behavior" surface is closer to **~22 files**.

`†` marks files that are also on the **12-stale-file list** (where the 2013 mirror is stale and the
decompile is authoritative — see [`reference-codebases.md`](./reference-codebases.md)): `BattleBoard`,
`EntityFlyText`. Read `_decompiled/` (not the 2013 source) when working on them.

## Related reading

- [`architecture.md`](./architecture.md) — the patch model + the resource-SWF crash/repair model.
- [`client-overview.md`](./client-overview.md) — the four fork extensions in context.
- [`reference-codebases.md`](./reference-codebases.md) — "did Stoic do it, or did we?" provenance recipe.
