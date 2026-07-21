# Client overview — how the whole client works, in one read

## Co-Authored-By: Claude <noreply@anthropic.com>

This is the **start-here** doc: what the Banner Saga Factions client *is*, how it boots, and the four
big pieces that make it up — each with a short teaser that hands off to a deeper doc. It restates
nothing; every section points at the doc that owns the detail.

If you read one page before touching the client, read this one, then follow the reading order at the
bottom.

## What the client is

The client is the **original, shipped Banner Saga Factions game** — an Adobe AIR desktop app — with a
small set of **patches** overlaid on top of it so it can talk to our own server and run a few things
the original never did (offline practice, a mod hook, Discord/Steam crossplay).

Two facts shape everything else:

- **It's an Adobe AIR / Flash application.** AIR is the desktop runtime that hosts Flash's
  ActionScript 3 (AS3) bytecode. The client renders entirely on the **native Flash display list** —
  menus and the HUD as native display objects, and the isometric battle board and scenes via the
  `as3isolib` library. The SWF also bundles the Starling GPU renderer, but `[Inference]` it is never
  started (see [`ui-system.md`](./ui-system.md)). The full runtime stack (AIR, the Flash VM, Starling,
  the Steamworks native extension) is laid out in [`architecture.md`](./architecture.md) → "Runtime stack".
- **It talks to the server over HTTP long-poll.** "Long-poll" means the client makes an ordinary web
  request and the server *holds it open* until it has something to send back, then the client
  immediately asks again — a simple way to get near-real-time pushes over plain HTTP. Every request
  and message shape is documented in [`wire-protocol.md`](./wire-protocol.md).

We do **not** ship a rebuilt game. We ship the original SWF (the compiled Flash file) with our patch
files layered on. How that patch-only model works — decompile, overlay `src/`, recompile — is in
[`architecture.md`](./architecture.md) → "The patch-only repo model", and the exact list of what we
patched is in [`patch-inventory.md`](./patch-inventory.md).

## The startup spine

When you launch the client, control flows down a fixed chain of objects. Knowing these six names lets
you place almost any log line or breakpoint:

```
GameMainAir  →  GuiApplication  →  GameWrapper  →  EngineCoreContext  →  GameConfig  →  GameFsm
 (AIR entry)    (app + render     (game screen    (engine services:     (all config,   (the game's
                 loop host)         container)      logging, sound…)      hosts, opts)   state machine)
```

- **`GameMainAir`** (`GameMainAir.as`, the repo root) is the AIR entry point — it parses launch flags,
  detects the OS, and boots the engine. Its boot phases (CLI args like `--server`, OS dispatch,
  `GameConfig.setupHosts()`) are documented step-by-step in [`architecture.md`](./architecture.md) →
  "Boot sequence".
- **`GuiApplication` → `GameWrapper` → `EngineCoreContext` → `GameConfig`** stand up the render loop,
  the on-screen container, the shared engine services (logging, sound, resources), and the
  configuration object every later system reads from.
- **`GameFsm`** (`game/session/GameFsm.as`) is where the boot sequence *ends and the game begins*: a
  finite-state machine (a controller that is always in exactly one named "state" — login, main menu,
  a battle, a town — and moves between them on events). Everything after the main menu is a `GameFsm`
  state transition. That whole spine is [`game-flow.md`](./game-flow.md).

## The four pillars

Almost every question about the client falls into one of four areas. Each is a teaser here and a
deep-dive elsewhere.

### 1. The game-flow spine — `GameFsm` and its states

`GameFsm` drives the entire session: authenticating, sitting in menus, matchmaking, loading a scene,
running a battle, walking a saga town. It has ~48 states (grouped into families) and 24 server-bound
"actions" that issue the HTTP requests. It is built on a **generic finite-state-machine primitive**
(`engine/core/fsm/`) that the battle engine reuses too. **Deep-dive:** [`game-flow.md`](./game-flow.md).

### 2. The visible client — UI, scenes, and the battle HUD

The screens, buttons, panels, and the in-battle heads-up display are a retained-mode widget toolkit
(the widgets persist as objects you mutate, rather than being redrawn from scratch each frame) plus a
page/screen framework that a `GameFsm` scene-state loads. A wrinkle unique to this game: some UI code
lives in **separate "resource" SWFs** loaded at runtime, which is the root of most UI crashes — see
[`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution". **Deep-dive:**
[`ui-system.md`](./ui-system.md) and [`asset-loading.md`](./asset-loading.md).

### 3. The battle engine

A battle is its own finite-state machine (`BattleFsm`, built on the same generic FSM base) that runs
in **lockstep** — both players' clients simulate the same battle independently and check a per-turn
hash to prove they stayed in sync. Entity IDs, the DJB sync hash, and turn flow are already documented
in [`battle-engine.md`](./battle-engine.md). Our **offline** player-vs-AI battles reuse that exact same
machine (see [`offline-ai.md`](./offline-ai.md)).

### 4. Subsystems and the fork's extensions

The narrower pieces: the data model (how unit/entity definitions are loaded from JSON), the offline AI
brain, and the **mod bridge** (a channel to an external helper process). Three of these are the fork's
own additions, not Stoic's. Where each of our patches lives and why is the one durable map:
[`patch-inventory.md`](./patch-inventory.md). **Deep-dives:** [`data-model.md`](./data-model.md),
[`offline-ai.md`](./offline-ai.md), [`mod-bridge.md`](./mod-bridge.md).

## What our fork adds on top of Stoic's game

Four extensions, all catalogued in [`patch-inventory.md`](./patch-inventory.md):

1. **Crossplay auth** — swap the Steam auth ticket for a Discord OAuth token when a launch option asks
   for it (`PreAuthState.as`). See [`wire-protocol.md`](./wire-protocol.md) → login flow.
2. **Offline player-vs-AI** — a self-contained battle against the game's dormant AI, making **zero**
   server calls (`AiBattleLoadState.as` + the `aimodule/` brain).
3. **A mod bridge** — a bidirectional pipe to an external mod-host process over newline-delimited JSON
   (`engine/mod/ModBridge.as`), tapped into every server request (`engine/core/http/HttpAction.as`).
4. **gui-SWF repairs** — small compatibility shims and guards that keep the older UI code baked into
   the resource SWFs from crashing against the modern app (`architecture.md` → "The gui-SWF API skew").

A large share of the `src/` overlay is not behavior at all — it's **decompiler-artifact repair**
(faithful fixes to code the JPEXS decompiler mangled), kept separate from real changes in
[`patch-inventory.md`](./patch-inventory.md).

## Where the code lives (one-line map)

| Package root | What's in it |
|---|---|
| `engine/` | Engine primitives: HTTP, the generic FSM, logging, battle internals, session, Steam, audio, rendering (~55% of the files). |
| `game/`   | The game layer on top of `engine/`: config, the `GameFsm` states, server-bound actions, UI views, saga (campaign). |
| `tbs/`    | Wire-format data mirrors — match the server's `tbs.srv.*` packages 1:1. |
| `lib/`    | Third-party libraries (Starling, tweens, JSON). Read-only. |
| `src/`    | **Our** patch overlays (33 files) — see [`patch-inventory.md`](./patch-inventory.md). |

Class-level pointers are in [`subsystem-index.md`](./subsystem-index.md) ("Where do I look for X?").

## Reading order — "I want to understand the whole client"

1. **This doc** — the shape of the whole thing.
2. [`architecture.md`](./architecture.md) — the patch model, the runtime stack, the boot sequence, and
   the resource-SWF crash model.
3. [`game-flow.md`](./game-flow.md) — the `GameFsm` spine that everything after the menu runs on.
4. [`wire-protocol.md`](./wire-protocol.md) — trace a login and a battle over the wire.
5. [`battle-engine.md`](./battle-engine.md) — how a battle actually runs (lockstep + sync hash).
6. [`ui-system.md`](./ui-system.md) — the widget roots, the page/screen framework, and the battle HUD.
7. [`asset-loading.md`](./asset-loading.md) — how screens and every other asset are loaded.
8. [`patch-inventory.md`](./patch-inventory.md) — exactly what our fork changed, and why.
9. [`subsystem-index.md`](./subsystem-index.md) — bookmark it; you'll keep coming back.

The remaining pillars each have their own deep-dive now: [`data-model.md`](./data-model.md) (units,
classes, and the def loader), [`offline-ai.md`](./offline-ai.md) (the offline battle and its AI), and
[`mod-bridge.md`](./mod-bridge.md) (the external mod host).
