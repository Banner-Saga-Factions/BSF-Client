# `bsf-client` documentation

## Co-Authored-By: Claude <noreply@anthropic.com>

Architecture, build workflow, wire protocol, and reference material for the patched Banner Saga Factions client. Companion suite to `bsf-server/docs/` ([local](../../bsf-server/docs/) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/tree/main/bsf-server/docs/)) — the two stay in sync route-by-route.

## Doc map

| Doc                                                  | Answers                                                                                                                                             |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`client-overview.md`](./client-overview.md)         | **Start here.** What is the client, how does it boot, and what are its four big pieces? A one-read map with hand-offs.                               |
| [`game-flow.md`](./game-flow.md)                     | What happens after boot? The `GameFsm` state machine, its ~48 states + 24 server actions, and the generic FSM base.                                 |
| [`architecture.md`](./architecture.md)               | How does the patch-only repo model work? What does `GameMainAir.as` do at boot? Where does the server URL come from?                                |
| [`build-workflow.md`](./build-workflow.md)           | How do I go from a stock SWF to a built `.air` / `.apk` / `.ipa`? What are the prerequisites? How do I fix JPEXS decompile artifacts?               |
| [`driving-the-client.md`](./driving-the-client.md)   | How do I run the game and check a change with my own eyes? Reading the board, keyboard and mouse control, and which log is the real one.            |
| [`wire-protocol.md`](./wire-protocol.md)             | Which AS3 class issues each `/services/*` request? What does the login flow look like end-to-end? How does the long-poll behave on a flaky network? |
| [`battle-engine.md`](./battle-engine.md)             | How does the battle FSM transition? Where are entity IDs constructed? Where is the per-turn DJB hash computed? What can cause a turn-0 desync?      |
| [`ui-system.md`](./ui-system.md)                     | The visible client: the two widget roots, the page/screen framework, how a `GameFsm` state becomes a screen, and the battle HUD.                    |
| [`asset-loading.md`](./asset-loading.md)             | The loader pipeline beneath UI **and** battle/anim/sound: `ResourceManager`, the resource types, the two loaders, and object pools.                 |
| [`subsystem-index.md`](./subsystem-index.md)         | "Where do I look for X?" — package-by-package map of notable classes with both decompile and 2013-source paths.                                     |
| [`reference-codebases.md`](./reference-codebases.md) | When do I read `client-2013-as3` vs `client-decompiled-as3`? Which 12 files are stale in the 2013 source?                                           |
| [`patch-inventory.md`](./patch-inventory.md)         | Exactly what does our fork change? The 33 `src/` overlays grouped by concern, each with what changed and why.                                       |
| [`data-model.md`](./data-model.md)                   | How does a JSON def become a typed object? The `Def`/`Vars`/`Wrangler` triad, the entity model, and why battle stats come from your roster.          |
| [`offline-ai.md`](./offline-ai.md)                   | How do offline practice battles work? Starting one, how the AI picks its move, what it can't do, and what our fork fixed.                            |
| [`mod-bridge.md`](./mod-bridge.md)                   | How does the mod bridge talk to `mods/host.exe`? The wire protocol, the command registry, the lifecycle — and the known security gap.               |
| [`doc-gaps.md`](./doc-gaps.md)                       | What's still undocumented? The tracked, closeable list of remaining client-doc gaps.                                                                |

## Reading orders

### "I'm new to this client and want to understand it"

1. [`client-overview.md`](./client-overview.md) — the whole client in one read; start here.
2. [`architecture.md`](./architecture.md) — the patch model, runtime stack, boot sequence, and resource-SWF crash model.
3. [`game-flow.md`](./game-flow.md) — the `GameFsm` spine that everything after the menu runs on.
4. [`ui-system.md`](./ui-system.md) — what you see: the widget roots, the page framework, and the battle HUD.
5. [`asset-loading.md`](./asset-loading.md) — how a screen's clip (and every other asset) is loaded.
6. [`wire-protocol.md`](./wire-protocol.md) — trace a login from `PreAuthState` through the server response.
7. [`data-model.md`](./data-model.md) — how the JSON defs behind units, classes, and your roster load.
8. [`build-workflow.md`](./build-workflow.md) — build it once on your own machine.
9. [`subsystem-index.md`](./subsystem-index.md) — bookmark this; you'll keep coming back to it.

### "I'm working on the UI / a screen / the battle HUD"

1. [`ui-system.md`](./ui-system.md) — the two widget roots, the page framework, and the `GameFsm` state→screen trace.
2. [`asset-loading.md`](./asset-loading.md) — how a screen's clip and every other asset is loaded.
3. [`architecture.md`](./architecture.md) → "Resource SWFs and runtime class resolution" — why a gui class you patched may not run.
4. [`patch-inventory.md`](./patch-inventory.md) → "Battle HUD & gui compatibility" — the fork's UI repairs.

### "I'm working on Discord/mobile crossplay"

1. `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — read all 6 items, especially Item 2 (Steam auth → Discord OAuth swap) and Item 6 (mobile OS branches).
2. [`reference-codebases.md`](./reference-codebases.md) — find each class you'll touch in either the 2013 source or the decompile.
3. [`wire-protocol.md`](./wire-protocol.md) → "Login flow walkthrough" — the patch point is `PreAuthState.as:33`.
4. `bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md` ([local](../../bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md)) — server-side prerequisites.

### "I'm a server dev and need to understand what the client expects"

1. [`architecture.md`](./architecture.md) → "What this client expects from the server" — three hard constraints (32-bit `user_id`, entity-ID format, long-poll URL).
2. [`wire-protocol.md`](./wire-protocol.md) — every `/services/*` route from the client direction, with cross-links to your existing `protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)).
3. [`battle-engine.md`](./battle-engine.md) — especially "Entity ID format" and "Per-turn DJB hash" before you touch anything that returns an `account_id`.
4. [`data-model.md`](./data-model.md) — the client-side shape of the account/roster data your `dataStructures.md` describes.

### "I'm working on offline AI battles or the mod bridge"

1. [`offline-ai.md`](./offline-ai.md) — how an offline practice battle runs and how the AI thinks.
2. [`driving-the-client.md`](./driving-the-client.md) — start one yourself and watch it; how to read the board and which log to trust.
3. [`battle-engine.md`](./battle-engine.md) — the turn FSM the offline battle rides on.
4. [`mod-bridge.md`](./mod-bridge.md) — drive the game (or watch its traffic) from an external host.
5. [`patch-inventory.md`](./patch-inventory.md) — the fork surface both features touch.

## Source material

The deepest pre-existing client analysis is `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — 6 items, 256 lines, written when the crossplay work started. It is _misfiled_ on the server side because that's where its author lived, but the content is canonical for the client. This suite cites it heavily rather than duplicating it.

Read-only reference codebases live alongside `BSF/` at `%USERPROFILE%\Code\bsf-refs\`:

- `client-2013-as3` — original 2013 Stoic source (385 files, **default reference**).
- `client-decompiled-as3` — JPEXS decompile of the shipped SWF v1.10.51 (1,113 files, authoritative for the 12-stale-file exception list).
- `client-swf-and-ane` — raw decompile inputs.

See [`reference-codebases.md`](./reference-codebases.md) for the decision tree.

## Related top-level docs

- Root [`CLAUDE.md`](../../CLAUDE.md) — repo-wide conventions, reference-codebase table, doc-path style.
- Root [`REFERENCE.md`](../../REFERENCE.md) — pinned `server-2013-java` SHA and top-7 highest-value server paths.
- [`bsf-client/CLAUDE.md`](../CLAUDE.md) — AS3 coding standards, patch-file rules, refactoring protocol.
- [`bsf-client/README.md`](../README.md) — quick-start build instructions.
- `bsf-server/docs/README.md` directory ([local](../../bsf-server/docs/) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/tree/main/bsf-server/docs/)) — server-side counterpart suite.
