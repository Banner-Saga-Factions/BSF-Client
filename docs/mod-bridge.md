# The mod bridge — talking to an external mod host

## Co-Authored-By: Claude <noreply@anthropic.com>

Our fork lets an outside helper program — a **"mod host"** — watch and steer the game without patching
the game file over and over. The client launches that program from its own `mods/` folder, and the two
talk over plain text: **one small JSON message per line**, in both directions. This doc is the contract
a mod-host author needs.

> **Secrets no longer reach the host.** The bridge used to forward your login message and session key
> to whatever helper was present. It now strips those values from every line in both directions. See §8
> for what is stripped, where that stops, and what a host can still see — a host remains a program
> running on your machine, so "not leaking your password" is not the same as "safe to run".

The in-code source of truth is the doc block at the top of `src/engine/mod/ModBridge.as:17-54`; this
doc narrates it. Jargon glossed on first use: **NativeProcess** = Adobe AIR's way to launch and talk to
a separate program; **stdin/stdout/stderr** = the program's input / output / error text channels;
**EOF** = "end of input", the signal a channel has closed.

---

## 1. What it is and why

Modding this client normally means editing the game file (surgery on the decompiled SWF) for every
change. The mod bridge replaces that with **one permanent patch** — the bridge itself — plus an
**external program you can rewrite freely.** The game ships a single hook; your logic lives in the
`mods/` folder, in any language you like, and you can change it without touching or rebuilding the
client. The design rationale is
[`../misc/Plan-Mod-Bridge-And-Scripting-Host.md`](../misc/Plan-Mod-Bridge-And-Scripting-Host.md).

**It is also how we test the client.** Driving the game by synthesising mouse clicks is slow, breaks when
a layout moves, and needs a real screen. The bridge does the deterministic half of that job instead —
see [`driving-the-client.md`](./driving-the-client.md) → "Two channels" for which channel owns what, and
`scripts/mod-host/host.js` for a working host you can read in one sitting.

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
break the one-object-per-line rule. `spliceBody` (`ModBridge.as:482-504`) handles this: a body that is
already single-line JSON is spliced in **verbatim** (so the host sees exactly what the server sent);
anything multi-line or non-JSON is re-encoded as a quoted JSON string. On the receiving side the host
must read one line at a time. The bridge itself reassembles the host's output across arbitrary chunk
boundaries and only acts on complete lines (`drainStdout`, `:513-564`).

**One exception to "verbatim": secrets are removed.** A body carrying a password, a Steam ticket or a
session key is re-encoded with those values replaced by `[redacted]` (§8). Every other body is passed
through untouched, so a host that hashes or compares raw bodies should expect the login to differ from
what the server actually sent.

**The host's three duties:**

1. **Keep stdout for protocol only** — every stdout line must be a valid command object; stray prints
   corrupt the stream.
2. **Log to stderr** — the bridge forwards the host's stderr into the game log, prefixed `[modhost]`
   (`onStderr`, `:566-576`).
3. **Quit when stdin reaches EOF** — AIR can't always kill the host, so the host must exit on its own
   when its input closes (see §4).

---

## 3. What the game can send — the static API

Everything the game (or a future injection) sends goes through six static entry points on `ModBridge`.
Each is a **cheap no-op when no host is present**, so hook sites stay one-liners:

| Call                                                  | What it does                                                                   |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| `ensureStarted(logger)` (`:134`)                      | Start the host on first call; idempotent and cheap afterward.                   |
| `running` (getter, `:244`)                            | Is the host process alive right now?                                            |
| `emit(name, data)` (`:250`)                           | Send a generic `{"event":name,"data":data}` line.                               |
| `emitHttpRequest(txn, url, body)` (`:300`)            | Copy an outbound server request to the host.                                    |
| `emitHttpResponse(txn, url, status, ok, rawBody)` (`:275`) | Copy a raw server response to the host.                                    |
| `registerCommand(name, handler)` (`:344`)             | Expose a named command a host can call (see §5).                                |

Plus one public flag, `spectatorMode` (`:105`), set by the built-in `set_spectator` command (see §7).

---

## 4. The host's life

- **Where it lives.** In `<applicationDirectory>/mods/`, launched with that folder as its working
  directory (`resolveHost`, `:173-230`; `start`, `:353-382`). There are two ways to name it:
  - **`mods/host.json`**, if present, names the program and its arguments —
    `{"program":"node.exe","args":["host.js"]}`. `program` is taken relative to `mods/` unless it is an
    absolute path. This is what lets a host be a **script**, which needs an interpreter to start it.
  - **`mods/host.exe`** otherwise, launched with **no arguments** — the original arrangement, unchanged.

  Either way the resolved program and its arguments are **written to the game log on every start**, and
  the descriptor is re-read on each restart, so editing it takes effect without restarting the game.
- **What trusting `mods/host.json` means.** It names something the game will run. That is no more
  dangerous than an executable sitting in the same folder — but it is less obvious, which is why the
  launch is logged. Treat the file as you would the program itself. There is no sandbox and none is
  claimed.
- **When it starts.** Lazily, **the first time the game talks to the server** — the HTTP tap calls
  `ensureStarted` on the first transaction (`HttpAction.as:140`). No server traffic, no host.
- **If it crashes.** The bridge restarts it, up to **three times** (`MAX_RESTARTS = 3`, `:73`;
  `onExit`, `:667-700`); after that it gives up and goes quiet. A host that stayed up for a minute
  counts as a clean run and **resets that budget**, so three unrelated blips hours apart no longer
  retire the bridge for the rest of the session.
- **When the game exits.** The bridge emits a final `SHUTDOWN`, closes the host's stdin (delivering EOF,
  the host's cue to exit), **reads anything the host has already written**, then force-kills it so a
  misbehaving host can't outlive the game as an orphan (`onAppExiting`, `:707-729`). That last read is
  why a host's closing summary now survives.
- **If anything is missing.** No NativeProcess support, no `host.exe`, or a `host.json` that will not
  parse or names a program that isn't there? The bridge **marks itself failed once and every call
  becomes a no-op** (`ensureStarted`, `:134-171`) — the game runs completely normally. (The bridge needs
  AIR's `extendedDesktop` profile, which `META-INF/AIR/application.xml:117` already declares. No `mods/`
  folder ships with the game.)

---

## 5. Commands — how the host steers the game

A host drives the game by writing a `{"cmd":…}` line. The bridge parses it (`processLine`, `:578-606`),
looks the name up in a static registry, and runs the handler (`executeCommand`, `:608-638`). If the
command carried an `id`, the handler's return value is sent back as a `RESULT` (or an `ERROR` if it
threw or the name is unknown) — that `id` is how a host **matches a reply to its request**.

Two commands are built in (`createBuiltins`, `:652-665`):

- **`ping`** → replies `"pong"`.
- **`set_spectator`** → sets the `spectatorMode` flag (see §7).

The registry is static and additive, so **more commands can be registered at runtime**, and three are —
all when the top-level game state is built (`GameFsm.as:171` and `:183`):

| Command | What it does | Replies with |
| ------- | ------------ | ------------ |
| **`start_ai_battle`** | Launches an offline practice battle. Takes an optional `spectate` flag and `scene` override. | `"ok"` |
| **`battle_state`** | Describes the battle running now — see below. | An object |
| **`battle_end_turn`** | Ends the turn in progress. | `{"ok":…}` |

The offline battle `start_ai_battle` launches is documented in [`offline-ai.md`](./offline-ai.md). A host
author registers their own commands the same way, via `registerCommand`.

### Reading and advancing a battle

Both battle commands live in `ModBattleControl.as`, kept apart from the bridge itself so `GameFsm` stays
a plain registration site. **Neither reaches the server**: reading touches getters only, and ending a
turn calls the same public `skip()` the on-screen countdown ring already calls when a turn runs out. The
one thing they add is *determinism* — the turn ends when you say so instead of when a timer says so.

**`battle_state`** answers `{"inBattle":false}` when the game is not in a battle. Otherwise:

```
{"inBattle":true,"battleId":"…","online":false,"finished":false,"state":"BattleStateTurnLocal",
 "turn":{"number":7,"entityId":"…","playerControlled":true,"committed":false,"complete":false},
 "units":[{"id":"…","name":"…","team":"…","playerControlled":true,"alive":true,
           "tile":{"x":4,"y":2},
           "stats":{"strength":{"current":9,"base":12},"armor":{"current":11,"base":9}, …}}]}
```

Three things about the unit list are worth knowing before you write assertions against it:

- **Scenery is filtered out.** Props such as `prop+pole03` are alive board entities with a team but no
  combat stats, and reading a stat off one throws. They are skipped the same way the offline AI skips
  them — anything without an ARMOR stat is not a combatant.
- **Dead units are kept.** The AI drops them; this does not. A checker watching for a crash wants to see
  the casualty rather than have it disappear.
- **Each stat gives `current` and `base`** — the same two numbers the on-screen stat panel shows, the
  second being what the unit was built with before buffs and damage. `state` is the battle's state-machine
  name, matching what the game log prints.

**`battle_end_turn`** ends only a *local* turn — the computer's turns end themselves and there is nothing
sensible to do to one from outside. It says why instead of failing quietly:
`{"ok":false,"reason":"not a local turn","state":"BattleStateTurnAi"}`, `"not in a battle"`, or
`"this turn was already ended"`. On success: `{"ok":true,"turn":7}`.

**Not yet available: issuing a move or an attack.** The machinery exists — it is the same path the online
game uses for an opponent's move (`BattleStateTurnRemote.handleMessage` parses a `BattleMoveData` and
queues a `BattleTurnCmdMove`) — but tile coordinates and target validation are a piece of work in their
own right. See [`driving-the-client.md`](./driving-the-client.md) → "Two channels".

---

## 6. The HTTP tap

The bridge is wired into the client's HTTP layer so a host can **observe all server traffic** without
touching each individual action. `HttpAction` copies every outbound request (`doSend` →
`emitHttpRequest`, `HttpAction.as:141`) and every raw response (`onResponseReceived` →
`emitHttpResponse`, `:253`) to the host. This is the firehose a combat log, a replay recorder, or a
live overlay reads from.

**Gotcha — a re-sent request is copied more than once.** `doSend` is also the re-send path, so a
request the client re-sends emits an `HTTP_REQUEST` each time. A host that records or counts requests
must **de-duplicate** (the `txn` + `url` are the same across the re-sends).

How often that happens is worth knowing, because it is more than a rare edge case: `HttpAction.canRetry`
re-sends whenever the response code is `0`, `404`, or `>= 500` — and never on a maintenance reply —
after `resendOnFailDelayMs` (1–2 s), **with no attempt cap**.

**Three numbers describe how much of the traffic re-sends, and they are easy to mix up.** **Twenty-three
classes** set `resendOnFail = true`; one of them is the shared battle base class — the template the
individual battle requests are built from, never sent by itself.
Three further battle classes inherit the flag without setting it, so **twenty-five concrete kinds of
request** re-send — `/battle/deploy`, `/battle/ready` and `/battle/sync` are the inheritors. And because
a single lobby class builds six different routes, **thirty distinct routes** re-send; that last figure
is the one to reach for when asking which routes a host can watch being hammered.

The twenty-three that set it: five of the roster actions that move renown (hire, promote, retire, stat
purchase, barracks-row unlock — but **not** rename or stat reset), seven `BattleTxn*` classes (`BattleTxn_Base` plus the move,
action, kill, exit, surrender and turn-query sends), all three `Lobby*Txn`, plus `ArrangePartyTxn`,
`LeaderboardsTxn`, `GameLocationTxn`, `VersusStartMatchTxn`, `UnitVariationTxn`, `TourneyJoinTxn`,
`SessionSteamOverlayTxn` and `IapInfoTxn` — the last is the in-app-purchase lookup, and the only one of
the three purchase classes that opts in.

So against a server that answers one of those codes for a permanent condition, a host sees the **same**
request line every couple of seconds indefinitely. The server-side rule this implies is written up in
`bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R10.

---

## 7. Who reads the spectator flag

`spectatorMode` is a single on/off switch a host flips with `set_spectator`. Today it is consumed by the
**offline battle loader**, which latches it to decide between "player vs AI" and the watch-two-AIs mode
(`AiBattleLoadState.as:85-86`) — see [`offline-ai.md`](./offline-ai.md) → "How to start one". The
watch-two-AIs mode it feeds is only partly built (planned, not shipped). The flag is deliberately
public so future input-gating (e.g. suppressing a spectator's battle actions) can consult it too.

---

## 8. What the host can and cannot see

**Secrets are removed before anything is sent.** Four field names are stripped wherever they appear, in
either direction, and their values replaced with `[redacted]`:

| Field | Where it used to escape |
| ----- | ----------------------- |
| `password` | the login request |
| `steam_auth_ticket` | the login request |
| `session_key` | the login reply |
| `steamCredentials` | the login reply |

Three details matter if you are relying on this:

- **Matched by field name, not by transaction.** A hook site added later cannot forget to opt in, and a
  route that starts echoing a session key is covered the day it does.
- **It fails closed.** A body that mentions one of those names but will not parse as JSON is replaced
  whole rather than passed through. Losing a line beats leaking a password on a body we could not read.
- **The cost is near zero.** Every body is scanned for those four names — a plain substring search — and
  only a body that hits one is parsed and rewritten.

**Where it stops, stated plainly:** it redacts a **field**, not a secret. `{"password":"hunter2"}`
becomes `[redacted]`; `{"note":"my password is hunter2"}` does **not**, because no field is named
`password` — the secret is loose inside ordinary text under an innocent key. Nothing the client sends
looks like that, and no server reply we know of does either, but a future route that writes a credential
into a message string would slip through. If you add one, add its field to `SECRET_FIELDS`
(`ModBridge.as:81`) — don't rely on the text being noticed.

*Correction to an earlier version of this doc:* it named a **Discord OAuth token** among the leaked
fields. There is no Discord token in the client — the whole source tree has no mention of Discord, and
Discord identity is resolved on the server. The fields above are what actually travelled.

### What a host still sees, and why that is not "safe"

Everything else: your account name, your Steam id, your roster, every battle you fight, every request and
reply. And a host is **a program running on your machine with your permissions** — the bridge starts it,
it is not sandboxed, and `mods/host.json` can point at anything (§4).

So: **run only a host you wrote or fully trust, and never distribute a build carrying a host others could
swap out.** That advice has not changed. What has changed is that a host you *do* trust can no longer
learn your password by accident, and a transcript of the traffic is no longer a credential file.

This closes finding **§3.2 (CRITICAL — ModBridge credential leak)** and its three smaller siblings in
[`../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`](../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md)
— that plan's **Wave 2**. The stdout buffer is now bounded, the restart counter resets after a clean run,
and the host's last lines are read before it is killed (§4).

---

## Related reading

- [`patch-inventory.md`](./patch-inventory.md) → "Mod bridge" — the exact `src/` files (the `ModBridge`
  and `ModBattleControl` new files and the `HttpAction` tap).
- [`driving-the-client.md`](./driving-the-client.md) → "Two channels" — when to reach for the bridge and
  when to look at the screen instead.
- `scripts/mod-host/host.js` and `scripts/install-mod-host.ps1` — a small working host, and the script
  that puts it where the game will find it.
- [`offline-ai.md`](./offline-ai.md) — the `start_ai_battle` command and the spectator flag, from the
  battle side.
- [`client-overview.md`](./client-overview.md) → "What our fork adds" — the mod bridge as one of the
  fork's four pillars.
- [`../misc/Plan-Mod-Bridge-And-Scripting-Host.md`](../misc/Plan-Mod-Bridge-And-Scripting-Host.md) — the
  design rationale and open decisions.
