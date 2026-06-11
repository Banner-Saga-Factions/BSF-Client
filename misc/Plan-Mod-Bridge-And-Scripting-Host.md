# Plan: Mod Bridge & External Scripting Host

Status: **Phase 1 implemented** (event bus + HTTP tap). Host runtime decision pending.
Date: 2026-06-10

## Goal

Enable dynamic, non-destructive modding of the Factions client — Discord Rich Presence, combat logging, match playback, spectator/puppet mode, custom overlays — by scripting in an accessible language (Lua/JS/Python) **without** repeated SWF surgery. One permanent set of AS3 patches exposes an event bus; all mod logic lives in external text files.

## Verified foundations

- `META-INF/AIR/application.xml` declares `extendedDesktop` in `supportedProfiles` → `NativeProcess` is available.
- All client–server traffic is HTTP request/response through a single base class, `engine/core/http/HttpAction.as` (`game/session/actions/*Txn.as`, `engine/battle/fsm/txn/BattleTxn*`, IAP, lobby). There is no socket stream; "server packets" = txn responses, and the player's own actions travel in txn **requests**.
- The client's battle polling (`BattleTxnQuery`) also flows through this base class, so a single tap captures live opponent state.

## Architecture

```
+--------------------+   stdin: NDJSON events    +---------------------+
|  AS3 client (SWF)  | ------------------------> |  mods/host.exe      |
|  engine.mod.       |                           |  (runtime TBD)      |
|  ModBridge         | <------------------------ |  loads mod scripts, |
|                    |   stdout: NDJSON commands |  Discord RPC, logs  |
+--------------------+   stderr: host logging    +---------------------+
```

- **Wire protocol:** one JSON object per LF-terminated line, both directions. stdout is reserved for protocol lines; host logging must use stderr. Full spec in the `ModBridge.as` header comment.
- **Host discovery:** `<applicationDirectory>/mods/host.exe`, cwd = `mods/`, no args. Absent host = bridge disables itself once; every emit is then a no-op. The game must never depend on the host.
- **Commands** (host → AS3) go through an explicit registry (`ModBridge.registerCommand`), not reflection. Built-ins: `ping`, `set_spectator`. Commands carrying an `id` get a `RESULT`/`ERROR` reply.
- **Lifecycle:** crash restart (max 3 attempts), clean shutdown on app exit, buffered stdout parsing safe against chunk-split lines and split multi-byte UTF-8.

## Implemented (Phase 1)

| File | Change |
|------|--------|
| `src/engine/mod/ModBridge.as` | New — the bridge described above |
| `src/engine/core/http/HttpAction.as` | Patched decompile — emits `HTTP_REQUEST` in `doSend()` and `HTTP_RESPONSE` (verbatim wire string) in `onResponseReceived()`; lazy-starts the host on the first txn (AuthTxn at startup) |

Not yet compiled — needs a local `apply-patches.ps1; build.ps1 -Target windows` run.

## Open decision: host runtime

| Option | Pros | Cons |
|--------|------|------|
| LuaJIT | ~1 MB single exe; one language end-to-end | Discord IPC (named pipe `\\.\pipe\discord-ipc-0`) must be hand-rolled via FFI; thin ecosystem |
| Node host + embedded Lua mods (e.g. wasmoon) | Mature Discord RPC / JSON / tooling libs; Lua stays the mod language; sandboxable | Two languages; Lua↔JS bridging layer; bundled exe is tens of MB |
| Node host + JS mods | Least machinery | Mods get full Node API unless sandboxed; less conventional for game modding |

Library maintenance status above is unverified — check before committing.

## Roadmap

1. **Echo-host spike** — 20-line host that logs every event and answers `ping`; validates the bus end-to-end. Blocks nothing; do first after a green build.
2. **Decide host runtime** (table above), then Discord Rich Presence from `HTTP_RESPONSE` events (match start/end, map, opponent).
3. **Combat logging / match recording** — host archives all `HTTP_REQUEST`/`HTTP_RESPONSE` lines per battle. Server-side recording in `bsf-server` may be the better long-term source of truth ([local](../../bsf-server/) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/tree/main/bsf-server/)).
4. **Spectator/puppet mode** — gate outbound actions centrally in the `BattleTxn*Send` constructors via `ModBridge.spectatorMode` (single small file family; avoids per-click-handler injections). Battle FSM files are post-2013-stale: patch the decompile only.
5. **Overlay layer** — new injected Sprite layer with a few drawing primitives (tile-coordinate rects/text), exposed via `registerCommand`.
6. **Match playback** — replay injector feeding archived responses into the battle FSM. Most invasive item; design after 3–5 are working.

## Risks

- `amxmlc` strict-mode friction on the patched decompile (untested).
- The bus is by design arbitrary-code-execution for any local mod. Never route network/server data into the command router; consider a manifest/allowlist before mods are shared publicly.
- Multi-line (pretty-printed) JSON responses are re-encoded as strings to preserve framing — hosts must handle both `body` shapes.
