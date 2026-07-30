# The mod bridge — talking to an external mod host

## Co-Authored-By: Claude <noreply@anthropic.com>

Our fork lets an outside helper program — a **"mod host"** — watch and steer the game without patching
the game file over and over. The client launches `mods/host.exe` and the two talk over plain text:
**one small JSON message per line**, in both directions. This doc is the contract a mod-host author
needs.

> ⚠ **It also carries a known, unfixed security hole** — today the login message (password / Discord
> token) and your session key are forwarded to the host. Don't ship builds that run untrusted hosts
> until the planned fix lands. Details in §8.

The in-code source of truth is the doc block at the top of `src/engine/mod/ModBridge.as:14-38`; this
doc narrates it. Jargon glossed on first use: **NativeProcess** = Adobe AIR's way to launch and talk to
a separate program; **stdin/stdout/stderr** = the program's input / output / error text channels;
**EOF** = "end of input", the signal a channel has closed.

---

## 1. What it is and why

Modding this client normally means editing the game file (surgery on the decompiled SWF) for every
change. The mod bridge replaces that with **one permanent patch** — the bridge itself — plus an
**external program you can rewrite freely.** The game ships a single hook; your logic lives in
`mods/host.exe`, which you can change without touching or rebuilding the client. The design rationale is
[`../misc/Plan-Mod-Bridge-And-Scripting-Host.md`](../misc/Plan-Mod-Bridge-And-Scripting-Host.md).

---

## 2. The messages

Every message is **one JSON object on its own line** (newline-delimited JSON, "NDJSON"), in both
directions.

**Game → host** (written to the host's stdin) comes in a few shapes:

```
{"event":"HTTP_REQUEST","txn":"AuthTxn","url":"services/auth/login/11","body":{…}}
{"event":"HTTP_RESPONSE","txn":"AuthTxn","url":"…","status":200,"success":true,"body":{…}}
{"event":"RESULT","id":7,"result":"pong"}          ← reply to a host command that carried an "id"
{"event":"ERROR","id":7,"message":"unknown command: foo"}
{"event":"BRIDGE_READY","data":null}               ← generic emits wrap their payload under "data"
```

**Host → game** (written to the host's stdout) is always a command:

```
{"cmd":"ping","id":7}
{"cmd":"set_spectator","value":true}
```

**Keeping every message on one line.** A server response can be large or contain newlines, which would
break the one-object-per-line rule. `spliceBody` (`ModBridge.as:258-274`) handles this: a body that is
already single-line JSON is spliced in **verbatim** (so the host sees exactly what the server sent);
anything multi-line or non-JSON is re-encoded as a quoted JSON string. On the receiving side the host
must read one line at a time. The bridge itself reassembles the host's output across arbitrary chunk
boundaries and only acts on complete lines (`onStdout`, `:282-326`).

**The host's three duties:**

1. **Keep stdout for protocol only** — every stdout line must be a valid command object; stray prints
   corrupt the stream.
2. **Log to stderr** — the bridge forwards the host's stderr into the game log, prefixed `[modhost]`
   (`onStderr`, `:328-338`).
3. **Quit when stdin reaches EOF** — AIR can't always kill the host, so the host must exit on its own
   when its input closes (see §4).

---

## 3. What the game can send — the static API

Everything the game (or a future injection) sends goes through six static entry points on `ModBridge`.
Each is a **cheap no-op when no host is present**, so hook sites stay one-liners:

| Call                                                  | What it does                                                                   |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| `ensureStarted(logger)` (`:78`)                       | Start the host on first call; idempotent and cheap afterward.                   |
| `running` (getter, `:111`)                            | Is the host process alive right now?                                            |
| `emit(name, data)` (`:117`)                           | Send a generic `{"event":name,"data":data}` line.                               |
| `emitHttpRequest(txn, url, body)` (`:167`)            | Copy an outbound server request to the host.                                    |
| `emitHttpResponse(txn, url, status, ok, rawBody)` (`:142`) | Copy a raw server response to the host.                                     |
| `registerCommand(name, handler)` (`:211`)             | Expose a named command a host can call (see §5).                                |

Plus one public flag, `spectatorMode` (`:52`), set by the built-in `set_spectator` command (see §7).

---

## 4. The host's life

- **Where it lives.** `<applicationDirectory>/mods/host.exe`, launched with `mods/` as its working
  directory and **no arguments** (`ensureStarted`, `:93`; `start`, `:220-243`). The host's own runtime
  (Node, Python, a native exe) is opaque to the game.
- **When it starts.** Lazily, **the first time the game talks to the server** — the HTTP tap calls
  `ensureStarted` on the first transaction (`HttpAction.as:140`). No server traffic, no host.
- **If it crashes.** The bridge restarts it, up to **three times** (`MAX_RESTARTS = 3`, `:44`;
  `onExit`, `:429-452`); after that it gives up and goes quiet.
- **When the game exits.** The bridge emits a final `SHUTDOWN`, closes the host's stdin (delivering EOF,
  the host's cue to exit), then force-kills it so a misbehaving host can't outlive the game as an orphan
  (`onAppExiting`, `:459-477`).
- **If anything is missing.** No NativeProcess support, or no `host.exe`? The bridge **marks itself
  failed once and every call becomes a no-op** (`:84-102`) — the game runs completely normally. (The
  bridge needs AIR's `extendedDesktop` profile, which `META-INF/AIR/application.xml:117` already
  declares. No `mods/` folder ships with the game.)

---

## 5. Commands — how the host steers the game

A host drives the game by writing a `{"cmd":…}` line. The bridge parses it (`processLine`, `:340-368`),
looks the name up in a static registry, and runs the handler (`executeCommand`, `:370-399`). If the
command carried an `id`, the handler's return value is sent back as a `RESULT` (or an `ERROR` if it
threw or the name is unknown) — that `id` is how a host **matches a reply to its request**.

Two commands are built in (`createBuiltins`, `:414-427`):

- **`ping`** → replies `"pong"`.
- **`set_spectator`** → sets the `spectatorMode` flag (see §7).

The registry is static and additive, so **more commands can be registered at runtime** — the game-flow
code adds **`start_ai_battle`** (launch an offline battle) when the top-level game state is built
(`GameFsm.as:170-176`). The offline battle it launches is documented in
[`offline-ai.md`](./offline-ai.md). A host author registers their own commands the same way, via
`registerCommand`.

---

## 6. The HTTP tap

The bridge is wired into the client's HTTP layer so a host can **observe all server traffic** without
touching each individual action. `HttpAction` copies every outbound request (`doSend` →
`emitHttpRequest`, `HttpAction.as:141`) and every raw response (`onResponseReceived` →
`emitHttpResponse`, `:253`) to the host. This is the firehose a combat log, a replay recorder, or a
live overlay reads from.

**Gotcha — a retried request is copied more than once.** `doSend` is also the retry path, so a request
that the client retries emits an `HTTP_REQUEST` each time. A host that records or counts requests must
**de-duplicate** (the `txn` + `url` are the same across the retries).

How often that happens is worth knowing, because it is more than a rare edge case: `HttpAction.canRetry`
(`HttpAction.as:346`) retries whenever the response code is `0`, `404`, or `>= 500`, after
`resendOnFailDelayMs` (1–2 s), **with no attempt cap**. Twenty-three `*Txn` classes opt in via
`resendOnFail = true` — every renown-spending roster action, every `BattleTxn*` (set on
`BattleTxn_Base`), all three `Lobby*Txn`, plus `ArrangePartyTxn`, `LeaderboardsTxn`, `GameLocationTxn`,
`VersusStartMatchTxn`, `UnitVariationTxn`, `TourneyJoinTxn` and `SessionSteamOverlayTxn`. So against a
server that answers one of those codes for a permanent condition, a host sees the **same** request line
every couple of seconds indefinitely. The server-side rule this implies is written up in
`bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R10.

---

## 7. Who reads the spectator flag

`spectatorMode` is a single on/off switch a host flips with `set_spectator`. Today it is consumed by the
**offline battle loader**, which latches it to decide between "player vs AI" and the watch-two-AIs mode
(`AiBattleLoadState.as:80-81`) — see [`offline-ai.md`](./offline-ai.md) → "How to start one". The
watch-two-AIs mode it feeds is only partly built (planned, not shipped). The flag is deliberately
public so future input-gating (e.g. suppressing a spectator's battle actions) can consult it too.

---

## 8. ⚠ Known security gap

The HTTP tap forwards traffic **verbatim** — including the login. The `AuthTxn` request body
(username / password / Discord OAuth token) and the response (`session_key`) are copied to
`mods/host.exe` word-for-word. Any host, trusted or not, sees your credentials and session key.

This is a **known, verified, not-yet-fixed** issue — it is finding **§3.2 (CRITICAL — ModBridge
credential leak)** in
[`../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`](../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md),
and its fix is that plan's **Wave 2** (redact the auth body and session key from the tap; also bound the
stdout buffer, reset the restart counter on a clean run, and flush the final line on exit). This doc
links the finding rather than restating it.

**Until that fix lands: only run a mod host you wrote or fully trust,** and never distribute a build
that ships a host others could swap out.

---

## Related reading

- [`patch-inventory.md`](./patch-inventory.md) → "Mod bridge" — the exact `src/` files (the `ModBridge`
  new file and the `HttpAction` tap).
- [`offline-ai.md`](./offline-ai.md) — the `start_ai_battle` command and the spectator flag, from the
  battle side.
- [`client-overview.md`](./client-overview.md) → "What our fork adds" — the mod bridge as one of the
  fork's four pillars.
- [`../misc/Plan-Mod-Bridge-And-Scripting-Host.md`](../misc/Plan-Mod-Bridge-And-Scripting-Host.md) — the
  design rationale and open decisions.
