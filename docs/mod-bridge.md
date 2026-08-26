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

The registry is static and additive, so **more commands can be registered at runtime**, and six are —
all when the top-level game state is built (`GameFsm.as:171` and `:183`):

| Command | What it does | Replies with |
| ------- | ------------ | ------------ |
| **`start_ai_battle`** | Launches an offline practice battle. Takes an optional `spectate` flag and `scene` override. | `"ok"` |
| **`battle_state`** | Describes the battle running now — see below. | An object |
| **`battle_deploy_ready`** | Says "ready" on the deploy screen, which is what starts the fighting. | `{"ok":…}` |
| **`battle_end_turn`** | Ends the turn in progress. | `{"ok":…}` |
| **`battle_move`** | Walks the unit whose turn it is to a tile. | `{"ok":…}` |
| **`battle_attack`** | Has that unit swing at another one. Ends its turn. | `{"ok":…}` |

Together they are enough to play a battle from start to finish without a mouse:
`start_ai_battle` → `battle_deploy_ready` → (`battle_move`, `battle_attack` or `battle_end_turn`) per turn.

The offline battle `start_ai_battle` launches is documented in [`offline-ai.md`](./offline-ai.md). A host
author registers their own commands the same way, via `registerCommand`.

### Reading and playing a battle

All five battle commands live in `ModBattleControl.as`, kept apart from the bridge itself so `GameFsm`
stays a plain registration site.

**They add no behaviour the game did not already have.** Reading touches getters only, and each of the
four that change something goes through a path the game already drives from code rather than from the
mouse: readying the deployment calls the same public `autoDeployLocal()` the Ready button calls; ending a
turn calls the same public `skip()` the on-screen countdown ring calls when a turn runs out; moving does
what two clicks on a tile do; attacking does what the execute button does. What they add is
*determinism* — things happen when you say so instead of when a timer or a mouse says so.

**In an offline battle nothing reaches the server — and the word "offline" is doing real work there.**
The move and action commands the engine queues send only when the unit is player-controlled **and** the
battle is online (`BattleTurnCmdMove.as:25`, `BattleTurnCmdAction.as:28,36`), and the deployment send is
gated the same way (`BattleStateDeploy.as:139`). A practice battle is not online, so an injected move,
attack or ready plays out locally and sends nothing at all. Measured across the whole verification run:
the server logged only its keep-alive poll, and not one battle route.

> **But these commands are not confined to offline battles, and the docs used to imply they were.** A
> local party's turn in an *online* battle runs in the very same `BattleStateTurnLocal`
> (`BattleStateNextTurn.as:54-55`), which is what the commands test for. Point a host at a live match and
> `battle_move` sends `BattleTxnMoveSend`, `battle_attack` sends `BattleTxnActionSend`, `battle_end_turn`
> sends one too by way of its `abl_end` terminator, and `battle_deploy_ready` sends `BattleTxnDeploySend`
> — exactly what the mouse would send, which is also exactly what makes scripting a ranked match
> cheating. The safety property belongs to the offline battle, not to these commands.

**No battle command ever throws at the host.** A fault comes back as a described refusal rather than an
`ERROR` line. The reply shapes differ, though: the four commands that *do* something answer
`{"ok":true,…}` or `{"ok":false,"reason":"…"}`, while `battle_state` answers a description with no `ok`
field at all.

**`battle_state`** answers `{"inBattle":false}` when the game is not in a battle. Otherwise:

```
{"inBattle":true,"battleId":"…","online":false,"finished":false,"state":"BattleStateTurnLocal",
 "turn":{"number":7,"entityId":"…","playerControlled":true,"committed":false,"complete":false,
         "moved":false,"ability":null},
 "units":[{"id":"…","name":"…","team":"…","playerControlled":true,"alive":true,
           "tile":{"x":4,"y":2},
           "stats":{"strength":{"current":9,"base":12},"armor":{"current":11,"base":9}, …}}]}
```

`moved` and `ability` are there to make a refusal make sense: without them, "this unit has already moved"
comes out of nowhere. Read `moved` precisely — it means **the unit's move has been confirmed**, not that
it went anywhere. Attacking confirms the move whether or not the unit left its tile (the on-screen
execute button does the same), so a unit that stood still and swung reports `"moved":true`.

Three things about the unit list are worth knowing before you write assertions against it:

- **Scenery is filtered out.** Props such as `prop+pole03` are alive board entities with a team but no
  combat stats, and reading a stat off one throws. They are skipped the same way the offline AI skips
  them — anything without an ARMOR stat is not a combatant.
- **Dead units are kept.** The AI drops them; this does not. A checker watching for a crash wants to see
  the casualty rather than have it disappear.
- **Each stat gives `current` and `base`** — the same two numbers the on-screen stat panel shows, the
  second being what the unit was built with before buffs and damage. `state` is the battle's state-machine
  name, matching what the game log prints.

**`battle_deploy_ready`** says "ready" on the deploy screen. **A scripted battle cannot get anywhere
without it**, for a reason worth knowing:

> **An offline practice battle never leaves the deploy phase on its own.** The engine sets the deploy
> countdown to zero for any battle that is not online (`BattleFsm.as:113-115`), and a countdown of zero
> means no timer is ever created (`BaseBattleState.as:84`) — so the phase's own force-deploy can never
> fire. Every other exit runs through the same `isLocalDeployed` flag, which only a local party being
> marked deployed can set, and offline the only thing that marks it is the Ready button. Measured
> 2026-08-26: four `battle_state` readings spanning thirty-five seconds all answered `BattleStateDeploy`
> with `turn: null`, every unit already standing on its tile.

Entering the phase already places your units, so this changes where nothing — it only supplies the
confirmation. On success: `{"ok":true,"state":"BattleStateTurnLocal"}`, the state the battle moved to.
Refusals: `"not in a battle"`, `"not in the deploy phase"` (with `state`), or
`"this side has already said ready"` (which an offline battle never produces — see the table below).

**`battle_end_turn`** ends the turn in progress. On success:
`{"ok":true,"turn":6,"next":7,"state":"BattleStateTurnAi"}`. Mind those three: **`turn` is the turn you
just ended**, `next` is the one now starting, and `state`, like the one above, is the state the battle
**moved to**. An earlier version reported only `turn`, and reported the *next* number under that name —
a host asserting on it got the wrong turn. Refusals: `"not in a battle"`,
`"this turn cannot be ended from outside"` (with `state`), `"this turn was already ended"`, or
`"this turn is already committed"` — that last one when the turn is already ending, where calling `skip()`
again would make the engine log a re-termination error the host did nothing wrong to cause.

> *Correction to an earlier version of this doc, in two parts.*
>
> It said this command "ends only a local turn" and gave
> `{"ok":false,"reason":"not a local turn","state":"BattleStateTurnAi"}` as an example refusal. **That
> refusal cannot happen.** In the engine's own words a computer turn *is* a local turn —
> `BattleStateTurnAi` extends the same `BattleStateTurnLocalBase` the check tests for — so the command has
> always accepted the computer's turn as far as that check goes.
>
> **And it really does end a computer turn — sometimes.** Two runs on 2026-08-26 disagreed, which is the
> whole story. The first answered `{"ok":false,"reason":"this turn is already committed"}`; the second
> answered `{"ok":true,"turn":1,"next":2,"state":"BattleStateTurnLocal"}` and the battle carried on
> normally for three more turns afterwards. Both are correct, because there is a **window**: the computer
> commits its turn only when `performAction` runs, which is scheduled half a second after its walk
> *finishes* (`BattleStateTurnAi.as:39-43`). Ask early and you take the turn away from it; ask late and
> you get the refusal. A host cannot easily control which, so **do not build a test on either outcome** —
> handle both replies.
>
> One narrow hazard if you do use it: the computer's planning timer is not stopped by the same `skipped`
> flag its other two entry points check (`AiModuleDredge.as:72-94` versus `:42` and `:134`), so in
> principle it can still reach a second commit on an already-committed move. Not seen in either run.

### Issuing a move and an attack

> **Measured working 2026-08-26**, in the real game. Four moves in one battle each landed exactly on the
> tile asked for, `turn.moved` turning true each time; then an archer moved *and* attacked in the same
> turn — `abl_bow_str` at level 1, chosen for it automatically — taking the target from 16 strength to 15
> and handing the turn straight to the computer. All nine deliberately-illegal requests came back as
> `{"ok":false,"reason":…}` rather than as errors. Details in
> [`driving-the-client.md`](./driving-the-client.md) → "What the bridge can do today".

Both act on **the unit whose turn it is**. There is no "make that other unit move" — only the active unit
can act, exactly as on screen. Both need a turn this player controls, so both refuse during the
computer's turn (that is the one place they are stricter than `battle_end_turn`).

**`battle_move`** walks that unit to a tile:

```
{"cmd":"battle_move","id":11,"x":4,"y":2}
→ {"ok":true,"entityId":"…","from":{"x":3,"y":2},"to":{"x":4,"y":2},"steps":1,"turn":7}
```

`x` and `y` are the same coordinates `battle_state` reports for every unit. **You name a destination, not
a route** — the game's own pathfinder works out the steps, exactly as it does for a click. A tile the
player could not have clicked is refused, because the check asks the very same reach map the highlighted
tiles on screen are drawn from.

Moving does **not** end the turn, so what follows it is either `battle_attack` or `battle_end_turn`.

**`battle_attack`** has that unit swing at another one:

```
{"cmd":"battle_attack","id":12,"target":"<unit id>"}                     ← basic strength attack
{"cmd":"battle_attack","id":12,"target":"<unit id>","ability":"armor"}   ← basic armor attack
{"cmd":"battle_attack","id":12,"target":"<unit id>","ability":"abl_malice","level":2}
→ {"ok":true,"entityId":"…","ability":"abl_melee_str","level":1,"target":"…","turn":7}
```

`ability` takes either of two plain words — **`"strength"`** or **`"armor"`** — so a test does not have to
know that a Raider swings `abl_melee_str` while an Archer looses `abl_bow_str`. Anything else is read as a
literal ability id, and `level` picks which level of it (default 1). Left out altogether it means the
strength attack, falling back to the armor one for a unit that has no strength attack — a Shieldbanger
has only the armor kind, the same asymmetry behind crash `#1009`.

**An attack ends the turn**, because that is what it does on screen: the execute button commits the turn,
and the engine treats the ability as the turn's last act. If a move is still pending it is committed
first, so the unit walks and then swings, in that order.

A host may send the attack while the unit is still walking rather than waiting and guessing — but know
what that does: the engine does not queue the swing politely behind the walk, it **cuts the walk short**
(`BattleTurnCmdAction.as:19-22` calls `fastForwardMove`). The unit still ends up on the right tile. Only
the animation is skipped, which matters solely if you were about to photograph it. This has not been
exercised in a run; the verification run waited between the two.

**What works is any ability aimed at exactly one unit.** Two kinds are refused with a reason rather than
half-done, and both are the next small piece of work:

- **Aimed at a tile** — Rain of Arrows and its kin. There is no way to name the tile yet.
- **Hitting several units at once** — Tempest and its kin, anything taking more than one target. On
  screen these are aimed by sweeping up neighbours until the ability has as many as it takes
  (`BattleBoardController.handleAbilityAdjacentClick`); naming one target here would quietly hit one unit
  instead of all of them, which is worse than refusing.

**Every refusal, and when it happens.** Three of the first four — `not in a battle`,
`this turn was already ended` and `this turn is already committed` — are shared with `battle_end_turn`.
The fourth is not: `battle_end_turn` accepts turns these two refuse, and says
`this turn cannot be ended from outside` instead. Rows marked **†** are guards no input has been shown to
reach; they are listed because the code can still emit them, not because you should expect one.

| Reason | When |
| ------ | ---- |
| `not in a battle` | no battle running |
| `not a player-controlled turn` (+ `state`) | it is the computer's turn, or a deploy/finish moment |
| `this turn cannot be ended from outside` (+ `state`) | `battle_end_turn` during the other player's turn, or between turns |
| `this turn was already ended` | `battle_end_turn` came first |
| `this turn is already committed` | an attack was already issued |
| `this unit has already moved` | `battle_move` only |
| `this unit has already acted` † | `battle_attack` only — the row above catches this first in practice |
| `no turn is running` † | a turn state holding no turn |
| `this turn has no move to make` † | a turn whose move object is missing |
| `no unit is taking this turn` † | a turn with no unit |
| `a move needs a whole-number x and y` | missing or unusable coordinates |
| `no tile at 4,2` | off the board |
| `already standing there` | the destination is where the unit is |
| `4,2 is out of reach this turn` | outside the movement range |
| `no path to 4,2` † | reachable on paper, no route in practice |
| `an attack needs a target` | no `target` for an ability that needs one |
| `no unit with id X` | unknown target |
| `this unit has no strength attack` / `…no armor attack` / `…no basic attack` | this unit lacks that attack |
| `unknown ability: X` | not in the ability table |
| `ability X has no level N` | level outside what the ability has |
| `level must be a whole number` | unusable `level` |
| `this ability aims at a tile, which the bridge cannot do yet` | tile-aimed ability |
| `this ability hits several units at once, which the bridge cannot aim yet` (+ `targetCount`) | an ability taking more than one target |
| `that ability is not one a unit can be told to use here` † | the id names something that is not a battle ability |
| `this unit has no attacks` † / `this unit's … attack is not a battle ability` † | malformed unit definition |
| `the game rejected that attack` (+ `validation`) | the engine's own verdict — `OUT_OF_RANGE`, `INVALID_TARGET`, `INSUFFICIENT_TILE`, `INSUFFICIENT_STARS`, `MOVED`, `INAPPROPRIATE_TAGS` |
| `this unit cannot pay for that ability` | not enough willpower, exertion or horn |
| `not in the deploy phase` (+ `state`) | `battle_deploy_ready` after the fighting has started |
| `this side has already said ready` † | `battle_deploy_ready` twice — see below |
| `the game refused to start the battle` (+ `error`) | anything unforeseen while readying |

**Why "already said ready" never fires offline.** Readying finishes the deploy phase *there and then* —
`autoDeployLocal` runs straight through `checkDeploymentComplete` to `finishDeployment`
(`BattleStateDeploy.as:129-153, 246-250`), because with one local party and one computer party there is
no remote side to wait for. So a second `battle_deploy_ready` finds the battle already past deploy and
answers `not in the deploy phase`. The guard only earns its place in an online battle, where the phase
waits on the other player. The verification run showed exactly this.

Anything unforeseen comes back as `the game refused the move` / `…the attack` with the error text
attached and a `committed` flag. That flag matters: **`"committed":true` means the request had already
been accepted and the fault came afterwards**, while the unit was walking or the ability was playing out —
so the board may have changed even though the reply says no. `"committed":false` means nothing happened,
and a half-built move is put back where it started, so the turn is exactly as it was found.

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
