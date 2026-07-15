# Subsystem index — "Where do I look for X?"

## Co-Authored-By: Claude <noreply@anthropic.com>

A package-by-package map of notable classes in the shipped client (1,113 files under `bsf-refs\client-decompiled-as3\`). One line per class. Crossplay-relevant patch points marked with **★**.

For mirror selection (decompile vs 2013 source) and the 12-stale-file caveat, see [`reference-codebases.md`](./reference-codebases.md). Paths are relative to `bsf-refs\client-decompiled-as3\` (decompile) and `bsf-refs\client-2013-as3\game\code\client\` (2013 source).

## Root files (decompile only)

| Class         | Role                                                                                                                                                | Decompile path   | 2013 path                            |
| ------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------- | ------------------------------------ |
| `GameMainAir` | Adobe AIR entry point. CLI arg parsing (`--server`, `--qa`, `--version`, `--assets`, `--gui`, `--party`, `--child`), OS dispatch, asset-path setup. | `GameMainAir.as` | (none — entry point added post-2013) |
| `AneFixer`    | Workaround for ANE loading on Mac.                                                                                                                  | `AneFixer.as`    | (none)                               |

## `engine/core/` — primitives

| Class                            | Role                                                                                          | Decompile path                         | 2013 path                                                  |
| -------------------------------- | --------------------------------------------------------------------------------------------- | -------------------------------------- | ---------------------------------------------------------- |
| `HttpCommunicator`               | Long-poll loop, retry semantics, `setPollTimeRequirement` API. `DEFAULT_POLL_TIME = 3000` ms. | `engine/core/http/HttpCommunicator.as` | `lib.engine.core/src/engine/core/http/HttpCommunicator.as` |
| `HttpJsonAction`                 | Base class for every server transaction (auth, poll, battle messages).                        | `engine/core/http/HttpJsonAction.as`   | `lib.engine.core/src/engine/core/http/HttpJsonAction.as`   |
| `HttpRequest`                    | Single HTTP transaction. Status-code error rules.                                             | `engine/core/http/HttpRequest.as`      | `lib.engine.core/src/engine/core/http/HttpRequest.as`      |
| `Fsm`, `StateData`, `StatePhase` | Generic finite-state machine — base for `GameFsm` and `BattleFsm`.                            | `engine/core/fsm/`                     | `lib.engine.core/src/engine/core/fsm/`                     |
| `ILogger`                        | Logger interface used everywhere.                                                             | `engine/core/logging/ILogger.as`       | `lib.engine.core/src/engine/core/logging/ILogger.as`       |
| `Hash`                           | DJB hash used for per-turn battle sync.                                                       | `engine/core/hash/Hash.as`             | `lib.engine.core/src/engine/core/hash/Hash.as`             |

## `engine/session/` — session, chat, IAP, news

| Class                                           | Role                                                                                                                                                                        | Decompile path                       | 2013 path                                                |
| ----------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------ | -------------------------------------------------------- |
| `Credentials` ★                                 | Holds `userId:int` (32-bit), `sessionKey`, `steamId`, `steamAuthTicket`, etc. `urlCred = "/" + sessionKey`. Fires `EVENT_COMMITTED` / `EVENT_VALIDATION` / `EVENT_SESSION`. | `engine/session/Credentials.as`      | `lib.engine.core/src/engine/session/Credentials.as`      |
| `TxnGet`                                        | Long-poll GET — hits `services/game/{sessionKey}`.                                                                                                                          | `engine/session/TxnGet.as`           | `lib.engine.core/src/engine/session/TxnGet.as`           |
| `Session`                                       | Per-connection session state; owns the `HttpCommunicator`.                                                                                                                  | `engine/session/Session.as`          | `lib.engine.core/src/engine/session/Session.as`          |
| `Chat`, `ChatMsg`, `ChatSendTxn`, `ChatRoomMsg` | Chat subsystem — wire format `POST /services/chat/{room}/{sessionKey}`.                                                                                                     | `engine/session/Chat*.as`            | `lib.engine.core/src/engine/session/Chat*.as`            |
| `Alert`, `AlertManager`                         | In-game notification system.                                                                                                                                                | `engine/session/Alert*.as`           | `lib.engine.core/src/engine/session/Alert*.as`           |
| `Iap`, `IapManager`, `IIapManager`              | In-app-purchase manager (Steam micro-txn — not yet wired into `bsf-server`, see server M7+).                                                                                | `engine/session/Iap*.as`             | (not in 2013 — added post-launch)                        |
| `ServerStatusData`                              | Returned to client on `/services/game/...` long-poll.                                                                                                                       | `engine/session/ServerStatusData.as` | `lib.engine.core/src/engine/session/ServerStatusData.as` |
| `NewsDef`, `NewsEntryDef`                       | News-of-the-banner data (the popup is client-side only — see gotchas).                                                                                                      | `engine/session/News*.as`            | `lib.engine.core/src/engine/session/News*.as`            |

## `engine/battle/` — battle internals

Battle code has the most 12-stale-file exceptions; **read decompile for the files marked †**.

| Class                                                                                                                      | Role                                                                                                                                            | Decompile path                                        | 2013 path                                                            |
| -------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------- | -------------------------------------------------------------------- |
| `BattleFsm` | Battle finite-state machine. Tightens HTTP poll to 1000 ms via `setPollTimeRequirement(this, 1000)` on `startFsm` (line 374). | `engine/battle/fsm/BattleFsm.as` | Not on the 12-stale list (its `Config`/`TurnOrder`/`StateInit`/`StateDeploy` siblings are). |
| `BattleFsmConfig` †                                                                                                        | Wires up state classes for `BattleFsm`.                                                                                                         | `engine/battle/fsm/BattleFsmConfig.as`                | (stale)                                                              |
| `BattleTurnOrder` †                                                                                                        | Turn-order computation.                                                                                                                         | `engine/battle/fsm/BattleTurnOrder.as`                | (stale)                                                              |
| `BattleStateInit` †, `BattleStateDeploy` †                                                                                 | Battle bootstrap + deployment phases.                                                                                                           | `engine/battle/fsm/state/BattleState{Init,Deploy}.as` | (stale)                                                              |
| `BattleStateNextTurn`                                                                                                      | Computes DJB hash for sync (line 130 — `Hash.DJBHash(hashStr)`).                                                                                | `engine/battle/fsm/state/BattleStateNextTurn.as`      | `lib.engine.core/src/engine/battle/fsm/state/BattleStateNextTurn.as` |
| `BattleStateTurnLocal` / `Remote` / `Ai` / `Surrender` / `Finish` / `Finished` / `Aborted` / `Error` / `Respawn` / `Start` | The rest of the battle FSM states.                                                                                                              | `engine/battle/fsm/state/BattleState*.as`             | `lib.engine.core/src/engine/battle/fsm/state/BattleState*.as`        |
| `BattleBoard` † ★                                                                                                          | Board model. `addPartyMember()` builds entity IDs as `{account_id}+{count}+{unit_def_id}` (line 456). `DJBHash(battleId)` seeds RNG (line 205). | `engine/battle/board/model/BattleBoard.as`            | (stale — use decompile)                                              |
| `BattleBoardView` †, `EntityFlyText` †                                                                                     | Board rendering.                                                                                                                                | `engine/battle/board/view/`                           | (stale)                                                              |
| `BattleEntity`, `BattleParty`, `BattlePartyType`                                                                           | Per-unit, per-party state objects.                                                                                                              | `engine/battle/board/model/`                          | `lib.engine.core/src/engine/battle/board/model/`                     |
| `BattleAbility*`, `engine/battle/ability/effect/op/model/Op.as` †                                                          | Ability and effect system. `Op.as` is the only stale file in this subtree.                                                                      | `engine/battle/ability/`                              | (mostly OK — Op.as stale)                                            |
| `engine/battle/sim/`                                                                                                       | Battle simulation (server-authoritative; client mirror for legality checks).                                                                    | `engine/battle/sim/`                                  | `lib.engine.core/src/engine/battle/sim/`                             |

## `engine/steamworks/` — auth ANE stubs ★

Crossplay's main patch zone.

| Class                     | Role                                                                                                                       | Decompile path                                 | 2013 path     |
| ------------------------- | -------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ------------- |
| `ISteamworks`             | Interface every Steam call goes through.                                                                                   | `engine/steamworks/ISteamworks.as`             | (not in 2013) |
| `NullSteamworks`          | Complete no-op `ISteamworks` implementation. Crossplay **plans** to subclass this as `DiscordSteamworks` — not yet created (see [`patch-inventory.md`](./patch-inventory.md)). | `engine/steamworks/NullSteamworks.as`          | (not in 2013) |
| `SteamworksCallbackEvent` | Event dispatched on Steam-side callbacks.                                                                                  | `engine/steamworks/SteamworksCallbackEvent.as` | (not in 2013) |

## `engine/entity/`, `engine/def/`, `engine/anim/`, etc. — game-data layer

| Subpackage                                                                                                           | Role                                            | Stale?                    |
| -------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------- | ------------------------- |
| `engine/entity/def/` (`EntityDef`, `EntityClassDefList`)                                                             | Per-unit definitions (rank, abilities, sprite). | **Stale — use decompile** |
| `engine/entity/` (other)                                                                                             | Entity model.                                   | OK                        |
| `engine/def/`, `engine/ability/`, `engine/achievement/`                                                              | Other definition layers.                        | OK                        |
| `engine/anim/`, `engine/landscape/`, `engine/scene/`, `engine/vfx/`, `engine/path/`, `engine/tile/`, `engine/sound/` | Rendering / audio.                              | OK                        |
| `engine/stat/`, `engine/math/`                                                                                       | Stat math + numeric helpers.                    | OK                        |
| `engine/tourney/`                                                                                                    | Tournament client-side (server M7+).            | OK                        |

## `game/` — game-specific layer

### `game/cfg/`

| Class                                                                                                                                                                                       | Role                                                                                                                                | Stale?                    |
| ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------- | ------------------------- |
| `GameConfig` † ★                                                                                                                                                                            | Top-level config. `setupHosts()` at line 1222–1227 builds `serverHostsLive` from `_buildRelease`; overridden by `--server` CLI arg. | **Stale — use decompile** |
| `AccountInfoDefVars` †                                                                                                                                                                      | Account-info schema.                                                                                                                | **Stale**                 |
| `Lobby`, `LobbyManager`, `ILobby`, `LobbyMemberInfo`                                                                                                                                        | Lobby state (server M3b — currently a single-route stub).                                                                           | OK                        |
| `GameOptions`                                                                                                                                                                               | Settings (`overrideSteamId` lives here — feeds Steam-auth bypass).                                                                  | OK                        |
| `LeaderboardsManager`, `VsMonitor`, `TourneyManager`, `SystemMessageManager`, `PurchasableUnit(s)`, `GameKeyBinder`, `NameGenerator`, `FactionsConfig`, `FactionsLegend`, `BattleHudConfig` | Various managers.                                                                                                                   | OK                        |

### `game/session/`

| Class                   | Role                                                                                                                                                                                                                                                      |
| ----------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `GameFsm`               | Top-level game FSM (logged-out → connecting → in-game).                                                                                                                                                                                                   |
| `GameState`             | Base class for FSM states under `states/`.                                                                                                                                                                                                                |
| `states/PreAuthState` ★ | Login state. Calls Steam to get auth ticket; if `overrideSteamId` is set, supplies `"override-authticket"`. **The crossplay patch lives here** (replace the bypass string with a real Discord OAuth token). One of 33 `src/` overlays — see [`patch-inventory.md`](./patch-inventory.md). |
| `states/` (other)       | ~48 `GameFsm` states in families (auth, menu, versus, town/saga, battle-entry, tutorial) — e.g. `MainMenuState`, `AuthState`, `OfflineState`, `VersusFindMatchState`. Full map: [`game-flow.md`](./game-flow.md).                                                                                                                                                                                   |
| `actions/AuthTxn` ★     | Builds the POST body for `/services/auth/login/{protocolVersion}` (body at lines 17–26). Reads `user_id`, `session_key`, `vbb_name`, `display_name`, `build_number` from the response.                                                                    |
| `actions/` (other)      | Other server-bound actions (party arrange, unit hire, etc. — see [`wire-protocol.md`](./wire-protocol.md)).                                                                                                                                               |

### `game/view/`, `game/gui/`, `engine/gui/` — UI, screens & the battle HUD

The visible client. Full narrative in [`ui-system.md`](./ui-system.md) (the two widget roots, the page/screen framework, how a `GameFsm` state becomes a screen, and the battle HUD); loading mechanics in [`asset-loading.md`](./asset-loading.md). **★** marks a class the fork patches.

| Package / class | Role | Narrative |
|---|---|---|
| `engine/gui/core/` (`GuiSprite`, `GuiHList`, `GuiButton`/`GuiLabel`/`GuiImage`) | The code-driven widget toolkit; `GuiSprite` (`extends Sprite`) is the base of the `Page` framework. | [`ui-system.md`](./ui-system.md) |
| `engine/gui/page/` (`Page`, `PageManagerAdapter`) | Page lifecycle + the base FSM-state→page router. | [`ui-system.md`](./ui-system.md) |
| `game/gui/GuiBase` | The other widget root (`extends MovieClip`) — symbol-linked Flash clips; every real screen + the HUD. | [`ui-system.md`](./ui-system.md) |
| `game/gui/GameGuiContext` ★ | The service handle every Flash-authored widget calls into (`playSound`/`createDialog`/`translate`); carries the fork's compat shims. | [`ui-system.md`](./ui-system.md) |
| `game/gui/` shared widgets (`GuiDialog`, `GuiRoster`, `GuiAlert`, `GuiToolTip`, `GuiChat`, `GuiIcon`) + `GuiUtil` ★ | Dialogs, roster panel, chat, icons; `GuiUtil` is a guarded fork shim the rerouted `battle_initiative.swf` resolves to by name. | [`ui-system.md`](./ui-system.md) |
| `game/gui/page/` (`GamePage`, `ScenePage`, `BattleHudPage`) | The concrete screen base, the scene/battle host, and the combat HUD page. | [`ui-system.md`](./ui-system.md) |
| `game/gui/battle/` (`GuiBattleHud`, `GuiInitiative` ★, popups, fly-text) | The battle HUD widgets (SWF-resident). | [`ui-system.md`](./ui-system.md) |
| `game/view/` (`GameWrapper`, `GamePageManagerAdapter`) | The on-screen page holder + the concrete FSM-state→page map. | [`ui-system.md`](./ui-system.md) |

Loading mechanics for every clip / bitmap / animation above — the `guiresman` / `ResourceManager` pipeline — are in [`asset-loading.md`](./asset-loading.md). (A structured `engine/resource` row is deferred to P3.)

### `game/entity/`, `game/saga/`

Entity model and saga-mode (campaign) code. Brief for now: the entity `Def`/`Vars`/`Wrangler` data model is planned for `data-model.md` and the offline/saga flow for `offline-ai.md` (both P3 — see [`doc-gaps.md`](./doc-gaps.md)).

## `tbs/srv/` — wire-format DTOs

| Subpackage             | Role                                                                                                                                                                                                                                                                                                |
| ---------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `tbs/srv/battle/data/` | Battle message DTOs (`BattleReadyData`, `BattleDeployData`, `BattleSyncData`, `BattleMoveData`, `BattleActionData`, `BattleKilledData`, `BattleFinishedData`). Authoritative when a Fiddler capture or `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) is ambiguous. |
| `tbs/srv/db/models/`   | Other DTOs (`AccountData`, `RankingData`, `RosterData`, etc.).                                                                                                                                                                                                                                      |

Both subpackages have `lib.game/src/tbs/srv/...` mirrors in `client-2013-as3` — these are unmodified post-2013, so the 2013 source is preferred for readability.

## `lib/` — third-party libraries

Cinderpath, Starling, GreenSock-flavored utilities, JSON, etc. Read-only; you should never need to touch these. The original tree has these under `lib.engine.core/src/lib/`.

## Glossary — "I see X in a log, what is it?"

| Symbol            | Meaning                                                                                                   |
| ----------------- | --------------------------------------------------------------------------------------------------------- |
| `vbb_name`        | vBulletin username — the old auth path's display name. Today carries the player's username string.        |
| `child_number`    | Multi-account-on-one-Steam-account index (0 for primary).                                                 |
| `protocolVersion` | The integer in `/services/auth/login/{N}` — currently `11`.                                               |
| `urlCred`         | `"/" + sessionKey` — appended to every `/services/...` URL after login.                                   |
| `battleId`        | Per-battle UUID. Seeds the per-battle RNG via `DJBHash(battleId)`.                                        |
| `hash`            | Per-turn DJB hash over the battle state — both clients must compute the same value or the battle desyncs. |
