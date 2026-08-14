# Game flow — the `GameFsm` spine

## Co-Authored-By: Claude <noreply@anthropic.com>

[`architecture.md`](./architecture.md) → "Boot sequence" traces startup up to the point where the
top-level state machine takes over. **This doc picks up there** and covers everything that happens
*after* boot: how the game moves between login, menus, matchmaking, scenes, towns, and battles.

The whole session is one finite-state machine — a controller that is always in exactly one named
**state** and moves to another state on an event. That machine is `GameFsm`.

> **Depth note.** This is an architecture narrative, not a per-class reference. State *roles* below are
> summarized from class names and their family; where a role is inferred rather than traced line-by-line
> it is marked `[Inference]`. Wire shapes (request/response bodies) are **not** repeated here — they
> live in [`wire-protocol.md`](./wire-protocol.md).

## `GameFsm` — the top-level machine

`GameFsm` (`game/session/GameFsm.as`) `extends Fsm`, the generic state machine described in the next
section. It owns the single "what is the game doing right now?" state and drives the transitions the
player experiences: authenticate → main menu → (matchmake / load a scene / enter a battle / walk a
saga town) → back to menu.

Its states live in `game/session/states/` (**52 files**: ~48 actual states plus 4 helpers) and its
server-bound actions in `game/session/actions/` (**24 files**). The boot hand-off from
`architecture.md` lands in the first family below (`PreAuthState` → `LoginQueueState` → `AuthState` →
`MainMenuState`).

## The generic `Fsm` / `State` base — documented once

Both `GameFsm` **and** the battle engine's `BattleFsm` are built on the same small primitive under
`engine/core/fsm/`. Understanding it once explains both machines. ([`battle-engine.md`](./battle-engine.md)
links here rather than re-explaining it.)

| Class | Role |
|---|---|
| `Fsm` | The machine itself (`extends EventDispatcher`). Holds the current `State`, queues events, and runs transitions. `GameFsm` and `BattleFsm` both extend it. |
| `State` | Base class for one state (`extends EventDispatcher implements IUpdateable`). Subclasses override lifecycle hooks — enter, update-per-frame, exit. |
| `StatePhase`, `StatePhaseEvent` | A state runs through **phases** (e.g. entering → active → exiting); these model that sub-lifecycle so a state can do async work (like loading) before it's "really" active. |
| `StateData`, `StateDataEnum` | A small typed key/value bag carried between states, so one state can hand data to the next without global variables. |
| `FsmEvent`, `FsmMsgQueue` | The event type transitions fire on, and the queue that serializes them so events are processed one at a time in order. |

The game layer then subclasses `State` twice:

- **`GameState`** (`game/session/GameState.as`, `extends State`) — the base for every `GameFsm` state.
- **Scene bases** — `SceneState` and `SceneLoadState` both `extend GameState`; `TownState extends
  SceneState`. A **`*LoadState`** loads a scene's resources, then hands off to the matching **scene
  state** once loading completes. This load-then-run pair repeats across towns, camps, tutorials, and
  our offline AI battle.

So the inheritance spine is: `Fsm` → `GameFsm`; and `State` → `GameState` → `SceneState`/`SceneLoadState`
→ concrete states.

## The state families

The ~48 states group into families by what part of the game they drive. (`★` = a state our fork
patched or added — see [`patch-inventory.md`](./patch-inventory.md).)

### Boot & authentication

| State | Role |
|---|---|
| `StartState` | First state after boot; engine/config bring-up. |
| `FlashState` | Early splash / transition frame. `[Inference]` |
| `PreAuthState` ★ | Gets a Steam auth ticket — **or**, if `overrideSteamId` is set, substitutes the crossplay bypass token (`PreAuthState.as:31–33`). The crossplay patch point; see [`wire-protocol.md`](./wire-protocol.md). |
| `LoginQueueState` | Waits in the server's login queue. |
| `AuthState` | Performs the login transaction and holds credentials. |
| `AuthFailedState` | Login failed — surfaces the error. |
| `AuthBuildMismatchState` | Client build doesn't match what the server expects. |
| `VideoQueueState` | Queues the intro/branding videos. `[Inference]` |
| `ReadyState` | Post-auth "ready to enter the game" gate. `[Inference]` |

### Main menu & account

| State | Role |
|---|---|
| `MainMenuState` | The main-menu hub — the fan-out point to everything below. |
| `AccountInfoState` | Loads the player's account + roster. |
| `AssembleHeroesState` | Party-assembly screen (choose your battle party). |
| `FactionsState` | Faction-related menu flow. `[Inference]` |
| `HallOfValorState` | Hall of Valor / leaderboards screen. |
| `OfflineState` | Offline / disconnected mode. |

### Scene machinery (bases)

| State | Role |
|---|---|
| `SceneState` | Base for a *loaded, running* scene (`extends GameState`). |
| `SceneLoadState` ★ | Base for *loading* a scene's resources, then handing off to its scene state. |
| `SceneStateBattleHandler` | Helper (not a state) — bridges scene states into battle handling. |

### Town & saga (single-player campaign)

| State | Role |
|---|---|
| `SagaState` | Drives the saga (campaign) flow. |
| `GreatHallState` | The Great Hall town scene. |
| `MeadHouseState` | The Mead House (where you hire units). |
| `TownState` | Town scene base (`extends SceneState`). |
| `TownLoadState` | Loads a town (`extends SceneLoadState`). |
| `MapCampState` / `MapCampLoadState` | The camp map scene + its loader. |

### Versus (multiplayer matchmaking)

| State | Role |
|---|---|
| `VersusFindMatchState` | Searching for an opponent. |
| `VersusMatchedState` | Match found — hand off to battle entry. |
| `VersusCancelState` | Player cancelled the search. |
| `VersusFailState` | Matchmaking failed. |
| `FriendLobbyState` | Friend-invite lobby. |

### Battle entry

| State | Role |
|---|---|
| `ProvingGroundsState` ★ | Proving-grounds practice battle. |
| `SkirmishState` ★ | Skirmish battle entry. |
| `AiBattleLoadState` ★ | **New (fork):** loads an offline battle vs the dormant AI — `extends SceneLoadState`, sets no opponent name so the **battle engine** makes no server calls (the session layer still polls and still reports which screen the player is on). See [`patch-inventory.md`](./patch-inventory.md). |

Once a battle-entry state finishes loading, control passes to the **battle** FSM (`BattleFsm`),
documented in [`battle-engine.md`](./battle-engine.md).

### Video

| State | Role |
|---|---|
| `VideoState` | Base — plays a full-screen video. |
| `VideoTutorial1State` / `VideoTutorial2State` | Tutorial videos (`extend VideoState`). |

### Tutorial (`states/tutorial/`)

A 15-file sub-family (13 states + 2 helpers) that mirrors the main flow for the new-player tutorial: `TutorialStartState`,
`TutorialLoadPartyState`, `TutorialMeadHouseState` (`extends MeadHouseState`), `TutorialProvingGroundsState`
(`extends ProvingGroundsState`), the town trio (`TutorialTownState` / `TutorialTownLoadState` /
`TutorialTownFinishState`), the battle trio (`TutorialBattleLoadState` / `TutorialBattleLoadDirectState`
/ `TutorialBattleState`), the two tutorial videos, and `TutorialEndState`. Two helpers —
`HelperTutorialState` and `RegisterTutorialStates` — wire the sub-family up rather than being states
themselves.

## The actions — how a state talks to the server

When a state needs the server, it fires an **action**: a class in `game/session/actions/` that builds
one HTTP request and reads the response. Of the 24 files there, **22 are `*Txn` classes** that
`extend HttpJsonAction` (the generic JSON-over-HTTP transaction base — see
[`subsystem-index.md`](./subsystem-index.md) → `engine/core/`); the other two are the `VsType` enum and
the `ClientConfigData` data holder.

Grouped by what they do (bodies + routes are in [`wire-protocol.md`](./wire-protocol.md)):

| Family | Actions |
|---|---|
| **Auth / session** | `AuthTxn`, `LogoutTxn`, `SessionSteamOverlayTxn`, `ClientConfigData` |
| **Account / roster** | `AccountInfoTxn`, `ArrangePartyTxn`, `PromoteUnitTxn`, `RenameUnitTxn`, `PurchaseStatsTxn`, `ResetStatsTxn`, `PurchaseRosterUnitTxn`, `RetireRosterUnitTxn`, `RosterRowUnlockTxn`, `UnitVariationTxn` |
| **Matchmaking / versus** | `VersusStartMatchTxn`, `VersusCancelTxn`, `VsType` |
| **Lobby** | `LobbyTxn`, `LobbyInviteTxn`, `LobbyOptionsTxn` |
| **Tournament** | `TourneyJoinTxn` |
| **Progression / misc** | `LeaderboardsTxn`, `GameLocationTxn`, `TutorialCompletedTxn` |

## Where our fork touches this

The game-flow layer is where the **offline player-vs-AI** feature plugs in. It adds `AiBattleLoadState`
and patches a handful of existing states/config so an AI battle loads down the same scene-load path a
tutorial battle uses — but with no opponent name, so the shared battle FSM computes "offline" and makes
zero server calls. The patched files (`GameFsm`, `SceneLoadState`, `GameStateDataEnum`, plus the
`aimodule/` brain and the board/scene setup) are catalogued with their reasons in
[`patch-inventory.md`](./patch-inventory.md) → "Offline player-vs-AI"; the design write-up is
[`offline-ai.md`](./offline-ai.md).

## Related reading

- [`architecture.md`](./architecture.md) — the boot sequence that precedes `GameFsm`.
- [`battle-engine.md`](./battle-engine.md) — `BattleFsm`, which reuses the generic `Fsm`/`State` base above.
- [`wire-protocol.md`](./wire-protocol.md) — the request/response body for every action.
- [`subsystem-index.md`](./subsystem-index.md) — class-level "where do I look for X?".
