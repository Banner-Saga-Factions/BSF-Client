# UI system — the widget toolkit, the page framework, and the battle HUD

## Co-Authored-By: Claude <noreply@anthropic.com>

[`game-flow.md`](./game-flow.md) covers the `GameFsm` **spine** — the invisible state machine that decides
what the game is doing right now (logging in, matchmaking, sitting in a town, running a battle). **This doc
picks up there** and covers what the player actually *sees* when a state becomes current: the on-screen
widgets, the framework that swaps one full screen for the next, and the combat HUD (the "heads-up display" —
the buttons, bars, and popups layered over a battle).

> **Depth note.** This is an architecture narrative, not a per-class reference. It names the load-bearing
> classes and cites the rest so you can open them yourself. Every path is under
> `_decompiled/scripts/` (the generated full source — see [`architecture.md`](./architecture.md)), and
> line numbers are spot-checked but drift when the SWF is re-decompiled; treat them as "look near here."
> Anything read off decompiled code rather than traced end-to-end is marked `[Inference]`.

## The one fact to hold onto: two widget roots

Almost every confusing thing about the client's UI comes from **not** knowing this: the client builds its
interface from **two unrelated base classes**, and which one a screen uses changes everything about how it
loads, how it's patched, and how it breaks.

| | `GuiSprite` | `GuiBase` |
|---|---|---|
| **Where** | `engine/gui/core/GuiSprite.as:8` | `game/gui/GuiBase.as:8` |
| **Extends** | `flash.display.Sprite` | `flash.display.MovieClip` |
| **Built by** | Code — you `new` it and position it. | An artist, in Flash. The class is **symbol-linked** to a movie clip that lives inside a resource SWF. |
| **Layout** | "Retained-mode" **anchor layout** — you declare rules ("pin to the top, center horizontally") once and the widget re-lays-out its children whenever it resizes. | Whatever the Flash timeline says; code just grabs named children out of the clip. |
| **Used for** | The `Page` framework's plumbing, and debug/console overlays. | Every real screen and the whole battle HUD. |

Here **"symbol linkage"** means: a movie clip inside a `.swf` is tagged in Flash with a class name, so
creating the clip creates that class. The class body that runs is the copy **baked into that SWF**, not the
copy in your rebuilt app — which is the root of a whole family of gui-SWF gotchas (owned by
[`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution"; the short version is
near the end of this doc).

**Neither root is Starling — and neither is anything else in the shipped client.** The SWF bundles the
Starling GPU renderer, but it is **never started** (`new Starling` appears nowhere in the source, and
`GameMainAir.as:64` declares an `s:Starling` field it never assigns). Everything renders on the **native
Flash display list**: menus and the HUD through `GuiSprite`/`GuiBase`, and the isometric battle board and
scenes through the **`as3isolib`** library (`BattleBoardView` builds an `as3isolib.display.IsoView`, itself
a `flash.display.Sprite`). `[Inference]` Starling is compiled in but inert. (`architecture.md` → "Runtime
stack" states the same.)

## Layer 1 — the widget toolkit

### The `GuiSprite` side — code-driven widgets

`GuiSprite` is a `Sprite` that manages its own size and lays out its children through an **anchor policy**:

- **Anchor layout.** Each `GuiSprite` can hold a `GuiSpriteAnchorPolicy` (`engine/gui/core/GuiSpriteAnchorPolicy.as:5`)
  describing how it pins to its parent — `percentWidth`, `horizontalCenter`, `verticalCenter`, and so on.
  `GuiSprite.layoutGuiSprite()` (`GuiSprite.as:310`) applies the policy and recursively re-lays-out children,
  so a resize cascades down the tree without per-widget resize code.
- **The one real container.** `GuiHList` (`engine/gui/core/GuiHList.as:5`, `extends GuiSprite`) lays a row of
  children out horizontally. It is the only general-purpose layout container in this toolkit.
- **The leaf widgets.** `GuiButton` (`engine/gui/core/GuiButton.as:8`), `GuiLabel` (`GuiLabel.as:6`), and
  `GuiImage` (`GuiImage.as:6`) all `extend GuiSprite`. Input arrives as ordinary Flash mouse events, which a
  button re-dispatches as a **semantic** event — `GuiButtonEvent` — so callers listen for "this button was
  clicked" rather than raw mouse coordinates.

`[Inference]` This code-driven toolkit is used chiefly for **debug/console overlays** and as the base of the
`Page` framework below; the *player-facing* screens are almost all built the `GuiBase` way. So the
load-bearing role of `GuiSprite` for shipping code is "the class `Page` extends," not "the button toolkit."

### The `GuiBase` side — Flash-authored widgets with a service handle

A `GuiBase` is a `MovieClip` an artist drew, given two things by code:

- **A context.** `initGuiBase(IGuiContext)` (`GuiBase.as:18`) hands the clip a service object (below) and wires
  up input-eating so clicks don't fall through to the scene behind it.
- **Named children.** `getGuiChild(...)` (`GuiBase.as:46`) looks a child up by the name the artist gave it on
  the timeline (`getChildByName`) and binds it to a typed property — the bridge between "a clip the artist
  made" and "a field the code can call"; `requireGuiChild(...)` (`GuiBase.as:72`) then asserts that a required
  child was bound.

That service object is **`GameGuiContext`** (`game/gui/GameGuiContext.as:45`, `implements IGuiContext`) — the
single handle every Flash-authored widget uses to reach the running game. It exposes exactly what a widget
needs and nothing else: `playSound(...)` (`:167`), `createDialog()` (`:415`), `translate(...)` (`:461`) for
localized text, plus icon builders and account/roster accessors. Because widgets only ever talk to this
interface, a stale SWF-resident widget can keep working as long as the context still answers the calls it
makes — which is exactly the seam our fork uses to repair drift (see "Where our fork touches this").

**Shared widgets** live under `game/gui/` and are reused across screens — dialogs, tooltips, alerts, the
roster panel, chat, and icons. They are a deliberate mix of roots:

| Widget | Class | Root |
|---|---|---|
| Dialog (modal message box) | `game/gui/GuiDialog.as:10` | `MovieClip` (symbol-linked) |
| Tooltip | `game/gui/GuiToolTip.as:7` | `GuiBase` |
| Alert | `game/gui/GuiAlert.as:10` | `GuiBase` |
| Roster panel | `game/gui/GuiRoster.as:17` | `MovieClip` (symbol-linked) |
| Chat | `game/gui/GuiChat.as:14` | `GuiBase` |
| Icon (portrait / ability art) | `game/gui/GuiIcon.as:12` | `Sprite` (lightweight, code-built) |

The pervasive **`IGui*` interface indirection** (`IGuiContext`, `IGuiDialog`, `IGuiGreatHall`, …) is what makes
this survivable: app code holds an *interface*, and the concrete class satisfying it can be the copy baked into
a resource SWF. A stale SWF class still fits the app's type checks, which is why the client boots at all with a
mix of old and new UI code.

## Layer 2 — the page & screen framework

A **`Page`** is one full-screen unit of UI. The framework's job is to show exactly one page at a time and swap
pages as the `GameFsm` moves between states.

- **`Page`** (`engine/gui/page/Page.as:10`, `extends GuiSprite`) is a full-screen widget with a small
  lifecycle: `start()` (`:40`) shows it, `terminate()` (`:45`) hides it and marks it dead, `cleanup()` (`:52`)
  releases what it held, and `update(int)` (`:155`) ticks it each frame. Its `state` moves through
  **`PageState`** — `INIT → LOADING → READY → TERMINATED` (`engine/gui/page/PageState.as`) — and every change
  notifies the manager so the loading overlay can come and go.
- **`PageManagerAdapter`** (`engine/gui/page/PageManagerAdapter.as:19`) is the **router**. It keeps a table of
  "FSM state class → page class" (`registerFsmStatePageClass`, `:127`), listens for the FSM's "current state
  changed" event, and on each change builds the matching page (`fsmCurrentHandler`, `:137`). Assigning
  `currentPage` (`:252`) terminates the outgoing page and `start()`s the incoming one; `updateLoadingPage()`
  (`:219`) shows a loading screen while the new page's assets stream in.
- **`GamePageManagerAdapter`** (`game/view/GamePageManagerAdapter.as:61`, `extends PageManagerAdapter`) is the
  concrete router for this game. Its constructor **is** the screen map: a block of `registerFsmStatePageClass`
  calls (`:90–109`) that name every state→page pair (the roster table below), plus `pageCtorFunc` (`:179`) which
  actually builds a page as `new PageClass(config)`. It also owns the overlays that sit *outside* the FSM
  routing (`:112–122`) — the marketplace and the story/war conversation popups. It is built once in
  `GameWrapper` (`game/view/GameWrapper.as:153`) and stored on `GameConfig.pageManager` (`game/cfg/GameConfig.as:266`).
- **`GamePage`** (`game/gui/GamePage.as:33`, `extends Page`) is the base every real screen extends. It adds the
  two things a game screen needs: **content loading** and **button wiring**.
  - `loadFullPageMovieClip(name)` (`:114`) asks the UI resource manager (`config.guiresman` — see
    [`asset-loading.md`](./asset-loading.md)) for the screen's Flash clip. Subclasses fill in `handleStart()`
    (`:175`, kick off the load) and `handleLoaded()` (`:183`, wire the loaded clip up); the base `checkReady()`
    (`:210`) waits until every requested asset is in, then flips the page to `READY` and calls the current
    game-state's `handlePageReady()` (`:235`).
  - `regButtonClick(...)` (`:256`) binds a Flash button to an FSM transition; when clicked,
    `buttonClickFsmStateHandler` (`:297`) calls `config.fsm.transitionTo(nextState)` (`:302`). This is the
    **reverse edge** — how a button press moves the whole game to a new state.
- **`ScenePage`** (`game/gui/page/ScenePage.as:30`, `extends GamePage`) is the special page that hosts a live
  isometric scene (a town, a camp, a battlefield) instead of a flat menu. It owns the bridge into battle
  handling and, in battle, creates the HUD (Layer 3).

## The money trace: an FSM state becomes a screen

Here is the single flow that ties the whole layer together — the walk from "the game decided to show the Great
Hall" to "the Great Hall is on screen and interactive." Read this once and the rest of the framework falls into
place.

1. **Something requests the state.** A button on the previous screen (via `buttonClickFsmStateHandler`, above)
   or game logic calls `config.fsm.transitionTo(GreatHallState, data)`.
2. **The FSM switches, then announces it.** `Fsm.transitionTo` (`engine/core/fsm/Fsm.as:212`) swaps in the new
   state and enters it. The new state runs through its **phases**; once it reaches "entered," the FSM fires
   `FsmEvent.CURRENT` (`Fsm.as:281`). (The announce is decoupled from the switch — the event fires when the
   state is *ready*, not the instant `transitionTo` is called.)
3. **The router picks the page.** `PageManagerAdapter.fsmCurrentHandler` (`:137`) looks up
   `GreatHallState` in its table, finds `GreatHallPage`, and builds it via `pageCtorFunc` → `new GreatHallPage(config)`
   (`GamePageManagerAdapter.as:179`).
4. **The old page leaves, the new page starts.** `set currentPage` (`:252`) terminates whatever was showing,
   adds the new page to the on-screen holder, and calls `start()`.
5. **The page asks for its art.** `GreatHallPage.handleStart()` calls
   `loadFullPageMovieClip("great_hall.swf/assets.greathall")` (`game/gui/page/GreatHallPage.as:33`) — a request
   into the UI resource manager.
6. **The art arrives and is wired up.** When the clip finishes loading, the base `checkReady()` runs
   `GreatHallPage.handleLoaded()`, which casts the loaded clip to the interface `IGuiGreatHall` and calls
   `init(...)` on it. The page flips to `READY`, and the base calls the current game-state's `handlePageReady()`
   (`GameState.handlePageReady`, `game/session/GameState.as:39`).
7. **Meanwhile, a loading screen covers the gap.** From the moment the page reported `LOADING`,
   `updateLoadingPage()` showed `GameLoadingPage` (`loading.swf`) on top; step 6 lets it retire.

**And the reverse edge:** a Flash button inside `great_hall.swf`, bound by `regButtonClick`, calls
`transitionTo(SkirmishState)` — and the whole cycle runs again for the next screen. `GameFsm`
(`game/session/GameFsm.as:72`) is the machine driving all of this; the states themselves are catalogued in
[`game-flow.md`](./game-flow.md).

## Layer 3 — the screens

Every player-facing screen is a `GamePage` subclass registered to an FSM state. The "resource SWF" column is
the exact symbol string the page passes to `loadFullPageMovieClip` (or `getGuiPageResource`); the art itself
ships *inside* that SWF. Registrations are all in `GamePageManagerAdapter.as:90–109`.

| Screen | FSM state | Page class (`game/gui/page/…`) | Resource SWF (symbol) |
|---|---|---|---|
| Login | `PreAuthState` | `LoginPage` | *(built by its own loader — no single page clip)* |
| Start / title | `StartState` | `StartPage` | `start.swf/assets.start` (`StartPage.as:34`) |
| Main menu | `MainMenuState` | `MainMenuPage` | `main_menu.swf/assets.main_menu` (`MainMenuPage.as:19`) |
| Town | `TownState` | `TownPage` | `strand_options.swf/gui.strand.options` (`TownPage.as:73`) |
| Great Hall | `GreatHallState` | `GreatHallPage` | `great_hall.swf/assets.greathall` (`GreatHallPage.as:33`) |
| Mead House | `MeadHouseState` | `MeadHousePage` | `mead_house.swf/assets.mead_house` (`MeadHousePage.as:32`) |
| Hall of Valor | `HallOfValorState` | `HallOfValorPage` | `hall_of_valor.swf/assets.hall_of_valor` (`HallOfValorPage.as:44`) |
| Versus | `VersusFindMatchState` / `VersusMatchedState` | `VersusPage` | `vs_match.swf/vs_match_page` (`VersusPage.as:96`) |
| Skirmish | `SkirmishState` | `SkirmishPage` | *(own loader)* |
| Proving Grounds | `ProvingGroundsState` | `ProvingGroundsPage` | `pages.swf/assets.proving_grounds` (`ProvingGroundsPage.as:44`) |
| Assemble Heroes | `AssembleHeroesState` | `AssembleHeroesPage` | `pages.swf/assets.proving_grounds` (`AssembleHeroesPage.as:32`) |
| Login queue | `LoginQueueState` | `LoginQueuePage` | `login_queue.swf/loginQueue` (`LoginQueuePage.as:32`) |
| Friend lobby | `FriendLobbyState` | `FriendLobbyPage` | `friend_lobby.swf/assets.friend_lobby` (`FriendLobbyPage.as:66`) |
| Map camp | `MapCampState` | `MapCampPage` | `travel.swf/gui.map_camp` (`MapCampPage.as:49`) |
| Scene / battle host | `SceneState` | `ScenePage` | iso scene + `pages.swf` banner overlays (`ScenePage.as:181–186`) |
| Video / intro | `VideoState` / `FlashState` | `VideoPage` / `FlashPage` | *(video — no page clip)* |

**Overlays** are pages the `GamePageManagerAdapter` owns directly, *not* routed by the FSM — they appear on top
of whatever screen is current: `GameLoadingPage` (`loading.swf/assets.loading`), the story/war conversation
popups `PoppeningPage` (`convo.swf/assets.poppening`) and `WarPage` (`convo.swf/assets.war`), `NewsPage`
(`news.swf/assets.news`), and the marketplace (`marketplace.swf`, built at `GamePageManagerAdapter.as:112`).
There is no single "options" screen — options live per-context (in-battle `GuiOptions`, in-town saga options).

## The battle HUD

In battle, the `ScenePage` creates a **`BattleHudPage`** (`game/gui/page/BattleHudPage.as:56`, `extends
GamePage`) — the controls layered over the isometric board. Because there are many widgets, a helper loads them:
**`BattleHudPageLoadHelper`** (`game/gui/page/BattleHudPageLoadHelper.as:19`) requests each one from its resource
SWF in its constructor (`:95–121`) and wires it up as it arrives.

| Widget | Class (`game/gui/battle/…`) | Resource SWF (symbol) |
|---|---|---|
| Top HUD bar | `GuiBattleHud.as:7` | `battle.swf/gui.battle_hud` |
| **Initiative bar** (turn order) | `initiative/GuiInitiative.as:37` | `battle_initiative.swf/gui.battle_initiative` |
| ↳ active frame / order / stat flags / unit banner | `GuiInitiativeActiveFrame` / `GuiInitiativeOrder` / `GuiInitiativeStatFlags` / `GuiInitiativeUnitInfoBanner` | *(same SWF)* |
| Unit info panel | `GuiBattleInfo.as:13` | child of `battle_initiative.swf` |
| Self popup (radial actions) | `GuiSelfPopup.as:15` | `battle_self_popup.swf/gui.self_popup` |
| Move / Ability popup | `GuiMovePopup` / `GuiAbilityPopup` | `battle_self_popup.swf/gui.move_popup` · `…/gui.ability_popup` |
| Enemy popup | `GuiEnemyPopup.as:14` | `battle_enemy_popup.swf/gui_enemy_popup` |
| Options / Help | `GuiOptions` / `GuiBattleHelp` | `battle.swf/gui.battle.options` · `…/gui.battle.help` |
| Fly-text ("Pillage!", "Forge ahead!") | raw `MovieClip`s | `go_battle.swf`, `go_pillage.swf`, `go_pillage2.swf`, `forge_ahead.swf` |
| Match resolution (end-of-battle) | `GuiMatchResolution` (page `MatchResolutionPage`) | `match_resolution.swf/assets.match_resolution` |

Two widgets load through their own helpers rather than `BattleHudPageLoadHelper`: the **Horn** (`GuiHorn`, via
`HornHelper`) and **battle chat** (`GuiBattleChat`, `→ GuiChat`). The non-visual helpers compiled *from the app
tree* — `InfoBarHelper`, `HornHelper`, `PopupSelfHelper` / `PopupEnemyHelper`, `BattleHudDamageHelper`,
`RadialAction` — are ordinary app classes (not symbol-linked), so they are directly patchable, unlike the
SWF-resident widgets above.

## The gotcha: gui classes run from the resource SWF, not your patch

The single trap that catches everyone working on UI: a `game.gui.*` screen or HUD class you edit in `src/` may
**never run**. Because these classes are **symbol-linked** to clips inside the resource SWFs, the copy that
executes is the one Stoic baked into `great_hall.swf`, `battle_initiative.swf`, and friends — an *older*
generation than your rebuilt app SWF. `GuiInitiative.as:1–17` opens with a header comment stating exactly this
("INERT OVERLAY — this code does NOT run at runtime"), proven by runtime logs.

That skew is what produces the offline-battle crash the fork had to fix: the initiative bar's SWF-resident copy
throws a null-reference error (`#1009`) when the battle starts with no entities yet, killing the HUD
(`BattleHudPageLoadHelper.checkInitiativeEntities`, `:420`, with the guard and its `[Inference]` explanation at
`:422–432`). **The full model — why symbol-linked code can't be patched from the app, the by-name exception, and
the three repair mechanisms — is owned by [`architecture.md`](./architecture.md) → "Resource SWFs and runtime
class resolution."** Read that before touching anything UI; this section only points at it.

## Where our fork touches this

Our patches don't rewrite the UI — they **reach around** the stale SWF-resident widgets. The relevant edits are
catalogued in [`patch-inventory.md`](./patch-inventory.md) → "Battle HUD & gui compatibility (7)": a guard in
`BattleHudPageLoadHelper` so the empty initiative bar can't crash the HUD, app-side compatibility getters added
back onto `GameGuiContext` (so a stale widget calling `party` / `renown` / `rosterSlotAvailable` still gets an
answer, delegating to `Legend`), and a guarded `GuiUtil` the rerouted `battle_initiative.swf` resolves to by
name. Each entry there says *what* drift it repairs and *why* that repair mechanism was chosen — this doc just
points you at the map.

## Related reading

- [`game-flow.md`](./game-flow.md) — the `GameFsm` states and transitions that drive which page is shown.
- [`asset-loading.md`](./asset-loading.md) — how `loadFullPageMovieClip` / `guiresman` actually fetch a screen's clip.
- [`architecture.md`](./architecture.md) — the resource-SWF class-resolution model behind the UI gotchas.
- [`patch-inventory.md`](./patch-inventory.md) — the exact `src/` edits that repair gui-SWF drift.
- [`subsystem-index.md`](./subsystem-index.md) — class-level "where do I look for X?" for `engine/gui` and `game/gui`.
