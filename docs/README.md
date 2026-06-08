# `bsf-client` documentation

## Co-Authored-By: Claude <noreply@anthropic.com>

Architecture, build workflow, wire protocol, and reference material for the patched Banner Saga Factions client. Companion suite to `bsf-server/docs/` ([local](../../bsf-server/docs/) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/tree/main/bsf-server/docs/)) — the two stay in sync route-by-route.

## Doc map

| Doc                                                  | Answers                                                                                                                                             |
| ---------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------------------- |
| [`architecture.md`](./architecture.md)               | How does the patch-only repo model work? What does `GameMainAir.as` do at boot? Where does the server URL come from?                                |
| [`build-workflow.md`](./build-workflow.md)           | How do I go from a stock SWF to a built `.air` / `.apk` / `.ipa`? What are the prerequisites? How do I fix JPEXS decompile artifacts?               |
| [`wire-protocol.md`](./wire-protocol.md)             | Which AS3 class issues each `/services/*` request? What does the login flow look like end-to-end? How does the long-poll behave on a flaky network? |
| [`battle-engine.md`](./battle-engine.md)             | How does the battle FSM transition? Where are entity IDs constructed? Where is the per-turn DJB hash computed? What can cause a turn-0 desync?      |
| [`subsystem-index.md`](./subsystem-index.md)         | "Where do I look for X?" — package-by-package map of notable classes with both decompile and 2013-source paths.                                     |
| [`reference-codebases.md`](./reference-codebases.md) | When do I read `client-2013-as3` vs `client-decompiled-as3`? Which 12 files are stale in the 2013 source?                                           |

## Reading orders

### "I'm new to this client and want to understand it"

1. [`architecture.md`](./architecture.md) — start here for the 30,000-ft view.
2. [`build-workflow.md`](./build-workflow.md) — build it once on your own machine.
3. [`wire-protocol.md`](./wire-protocol.md) — trace a login from `PreAuthState` through the server response.
4. [`subsystem-index.md`](./subsystem-index.md) — bookmark this; you'll keep coming back to it.

### "I'm working on Discord/mobile crossplay"

1. `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — read all 6 items, especially Item 2 (Steam auth → Discord OAuth swap) and Item 6 (mobile OS branches).
2. [`reference-codebases.md`](./reference-codebases.md) — find each class you'll touch in either the 2013 source or the decompile.
3. [`wire-protocol.md`](./wire-protocol.md) → "Login flow walkthrough" — the patch point is `PreAuthState.as:33`.
4. `bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md` ([local](../../bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md)) — server-side prerequisites.

### "I'm a server dev and need to understand what the client expects"

1. [`architecture.md`](./architecture.md) → "What this client expects from the server" — three hard constraints (32-bit `user_id`, entity-ID format, long-poll URL).
2. [`wire-protocol.md`](./wire-protocol.md) — every `/services/*` route from the client direction, with cross-links to your existing `protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)).
3. [`battle-engine.md`](./battle-engine.md) — especially "Entity ID format" and "Per-turn DJB hash" before you touch anything that returns an `account_id`.

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
