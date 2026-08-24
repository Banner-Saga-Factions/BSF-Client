# Running and driving the client by hand

## Co-Authored-By: Claude <noreply@anthropic.com>

Some client defects only show up on screen. A unit stands in the wrong place, a panel renders empty, a
turn never passes — none of that fails a test, and none of it appears in a diff. This doc is about the
other kind of checking: **start the real game, look at it, click it, and see.**

It covers how to launch it, how to read what you are looking at, how to drive it — including from an
automated agent that can only take still screenshots — and the traps that waste an afternoon if nobody
wrote them down. **Clicking is no longer the only way to drive it: §8 explains which half of the job
belongs to the mod bridge instead, and that is the section to read first if you are automating
anything.** For _why_ the launcher works the way it does (the runtime mismatch, the missing audio
extension), see [`build-workflow.md`](./build-workflow.md) → "The AIR SDK 33-vs-51 wall". For how the
offline computer opponent actually thinks, see [`offline-ai.md`](./offline-ai.md).

Everything below was **measured** on real runs — 2026-08-19 and 2026-08-21 — not inferred from source.
Where a claim is an inference or rests on a small sample, it says so.

**Two different builds appear below, and the difference matters.** The 2026-08-19 run used **our
recompiled SWF** under `adl` (`scripts/run-adl.ps1`) — the build carrying the offline
player-versus-computer work. The 2026-08-21 run used the **shipped Steam client**, launched by
`bsf-server\launch-game-2p.ps1`, which has none of our patches: no `Ctrl+Shift+A` practice battle and
no mod bridge. Each section says which build it describes. What the game does on screen — the banners,
the initiative bar, the two-click rule — is the same in both.

---

## 1. The launch, in order

1. **Start the server first.** `bsf-server\start-server.bat` rebuilds and starts it on port 8082. The
   client boots through login, so with nothing listening you only get to see the pre-login path. Note
   that this batch file **stops every running `node` process** on the machine, deliberately, so a stale
   build can't answer your requests — check you have nothing else running on Node first.
2. **Launch the client** with `bsf-client\scripts\run-adl.ps1`. It builds a temporary descriptor and
   runs the compiled SWF under the modern debug runtime. It changes nothing in the Steam install.
3. **Expect no sound.** The audio extension is stripped for this launcher, so the game falls back to a
   silent driver and logs three `Error #1508` lines. That is normal here, not a fault.

The launcher's default arguments include `--versus_start`, which **puts you straight into matchmaking**
rather than at camp. On a single-player test machine that search never finds anyone, which is harmless
— but don't read the "Searching for a match" screen as a hang.

### Two players at once — one window, not two (both builds)

`bsf-server\launch-game-2p.ps1` starts the Steam build with two usernames, and the result is not what
the name suggests. Passing `--username a,b` makes the game build **one game view per name and lay them
side by side inside a single window** — left is the first name, right is the second. Each half is a
fully separate game: its own login, its own connection, its own battle state. They simply share a
window.

**This is game code, not launcher code, so our build does it too.** The splitting happens in
`GameMainAir.parseArguments` → `initWrappers`, with `--steam_id` and `--child` applied per view — all of
it inside the SWF we compile. `run-adl.ps1` simply used to hardcode one name. It now takes the same
comma-separated form:

```powershell
.\scripts\run-adl.ps1 -Username "test,Pieloaf" -SteamId "123456,293850"
```

Pass one id per name; the launcher stops you if the counts differ, because otherwise the later views
quietly share the first id and log in as each other.

> ⚠ **Measured 2026-08-23: this launches, matches and deploys, but the battle does not start.** Both
> halves logged in, found each other, and agreed on one battle (a single `battleId` across both). Both
> reported themselves ready. Neither ever saw the other as ready — `remotesReady=false` throughout — so
> the battle sat at its opening state. A separate fault appeared alongside it: a `#1034` type-coercion
> error killed the initiative bar, in the known resource-SWF class-resolution blind spot (§8). The
> shipped Steam build does complete two-player battles, so **for now two-player testing still belongs on
> the shipped build.** Tracked as its own piece of work; do not read the paragraph above as "this works".

That is the single most useful fact here for two-player testing: **one screenshot captures both
players at once**, so there is no window to hunt for, nothing to alt-tab between, and no chance of the
two captures being a second apart. With `--versus_start` the two halves also queue on their own and
match each other, so a battle needs no clicks at all to start.

Two smaller things about that launcher: the Steam executable hands off to the real game process and
exits, so the script prints "Game has closed" while the game is still running — that is not a failure.
And the two halves *do* share some engine-wide state, so treat "both screens agree" as evidence about
the game, not proof that two independent programs agree.

---

## 2. Reading the screen

Three things tell you what is going on. Learning them turns "I think that unit is the enemy's" into a
fact.

**Press `Tab` to show every unit's banner.** Each banner is a stat readout, and it is easy to misread
as a team colour because it is half blue and half red:

| Part of the banner | What it is |
| ------------------ | ---------- |
| Gold star on top   | Willpower  |
| Blue (left) half   | Armor      |
| Red (right) half   | Strength   |

**The banner does not tell you which side a unit is on.** In an offline practice battle both parties
are identical mirrors of your own roster, so the stats match too, and you cannot tell them apart that
way at all.

**The initiative bar along the bottom is the side indicator.** Each portrait sits on a coloured
background — **blue is yours, red is the computer's** — and in a full battle they strictly alternate,
yours first. That bar is also the turn order; it rotates as units act.

**The stat panel on the left describes the active unit only.** It repeats the banner numbers and adds
movement, exertion (how much willpower may be spent in one turn), and break. It also names the unit,
and it shows each stat as **current / base** — the second number being the value the unit was built
with. That second number is the one to read when you want to know what the game was *told* a unit is,
as opposed to what it currently has after buffs and damage.

**The blue ring around the active unit's portrait is a countdown.** It empties as that unit's time to
act runs out; when it empties the turn passes on its own. So a battle left alone keeps cycling turns
by itself.

---

## 3. What the numbers mean

Enough of the rules to interpret what you see. Taken from Stoic's own tutorial videos for this game and
confirmed against observed behaviour:

- **Strength is both damage and health.** A wounded unit hits softer.
- **Armor subtracts from strength damage.** Damage dealt to strength = attacker's strength − target's
  armor. Attacking a fresh 9-armor target with an 8-strength archer does _nothing_.
- **If your strength is below their armor you can miss outright** — 10% miss chance per point of
  deficit.
- **Break is the damage you do when you attack armor instead**, and it does not shrink as you get hurt.
  So the standard opening is _break armor first, then kill_.
- **Willpower buys extra movement, extra damage, or an ability, and does not come back on its own** —
  only resting restores it. Exertion caps how much can be spent in a single turn.
- **Passives matter and are easy to miss.** An Axeman standing beside an ally forms a shield wall that
  raises both units' armor. We watched an archer's armor drop from 11 to 9 the moment she stepped away
  from hers — worth knowing before you file a bug about armor changing on its own.

---

## 4. Driving it

**Keyboard input works plainly.** Synthetic key events reach the game with no special handling:

| Key            | Effect                                                                   |
| -------------- | ------------------------------------------------------------------------ |
| `Ctrl+Shift+A` | Start an offline practice battle — **our recompiled build only**, not the Steam one ([`offline-ai.md`](./offline-ai.md) §2) |
| `Tab`          | Toggle all banners                                                       |
| Right-click    | Cancel the armed attack mode                                             |

`Esc` does **not** cancel attack mode, and the arrow keys do **not** pan the camera. Use right-click.

**Mouse input needs two clicks, and this is the one rule that matters.** The first click on a target
_arms_ the action — a green check mark and a tooltip appear, and a movement path is drawn — and a
second click _commits_ it. That much is ordinary game UI.

The part that catches automation out: **the two clicks must be far enough apart in real time.** Two
clicks fired back-to-back inside a single scripted burst arm the action and then do nothing, apparently
because both land inside the same rendering frame. Sending the second click a second or more later, as
a separate step, commits reliably every time. If your automation "clicks twice and nothing happens",
this is why — it is not a missed coordinate.

**Screen scaling will silently break your coordinates.** On a 125% display the game reports the screen
as 1536×864 while Windows reports 1920×1080. Capture and clicking must both use the **Windows** numbers,
and the capturing process must declare itself scaling-aware or the image comes back at the smaller size
and every click lands about a quarter short. Verify a capture really is full-size before trusting any
coordinate derived from it.

**Still screenshots are enough, but only just.** One frame per step, a second or two apart, is fine for
reading a menu, a board state, or a crash dialog. It will not catch an animation or a one-frame flash.
Cropping to the game window keeps each frame cheap, and magnifying a small region — the initiative bar,
a cluster of banners — is what actually answers questions.

### Watching without touching

You do not have to bring the game to the front to see it. Windows can be asked to paint a copy of
themselves — `PrintWindow` with the "render full content" flag — which returns a picture of a window
that is buried behind others, with no click and no change of focus. It worked on the game, on Windows
Terminal and on Visual Studio Code. This is what makes it possible to watch a live battle and a server
console at the same time without disturbing either.

### Taking control, when you do need to

Windows refuses to let a background program steal the foreground, so simply asking for it fails
silently. Two things work: **clicking the window's taskbar button**, or tapping the ALT key first and
then asking (the tap releases the lock). Whichever you use, **check which window is actually focused
before sending a keystroke.** A `Tab` meant for the game once went to a terminal instead, and nothing
about the game's appearance said so.

Related: a single click only *arms* an action, so a stray click on the board is recoverable — right-
click cancels it. There is no equivalent safety net for keystrokes.

### Let the battle play itself

Nobody has to play. Each unit's turn passes on its own when its ring empties, and every passed turn
also resets the server's own patience (a 90-second limit before it declares the silent side beaten).
The result is a battle that cycles turns unattended for as long as you like — useful, because you can
watch a specific unit come round again without touching anything. The catch is that nothing ever dies,
so such a battle never ends by itself.

When you do want to move things along, click a unit and choose **rest** to end its turn early.

### Let the server tell you when to look

The most reliable way to photograph a *particular* unit is not to watch the screen for it. The server
logs the acting unit at every turn boundary, by identifier, in the form
`{account}+{index}+{unit id}`. Trigger the screenshot on that line and the frame is tied to that unit
by its id — not by a name read off a banner. That distinction is not academic: in one run two units in
the same battle carried identical numbers, and only the identifier separated them. The matching
server-side note is in `bsf-server/docs/client-contract.md` → "Measured evidence" ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)).

---

## 5. Where the logs are — and two traps

There are three log files, and only one of them is useful while the game is running.

| File                                                           | Use it for                                       |
| -------------------------------------------------------------- | ------------------------------------------------ |
| `%APPDATA%\TheBannerSagaFactions\Local Store\logs\A-0.log.txt` | The client's own log — but read the numbering note below. |
| `bsf-client\_build\adl-run.log`                                | The `adl` launcher's copy — see the trap below. Does not exist for the Steam build. |
| The launcher's console output                                  | Only the launcher's own status lines.            |

**The number in the filename is not a session number, and does not name a player.** The client rotates
this family of files on every start — today's becomes `-1`, and so on. It rotates **once per game
view**, so a two-player launch leaves *two* fresh files rather than one, and which file belongs to
which player cannot be read off the number. Identify a file by looking inside it, not by its name.

**Trap 1 — the launcher's copy is buffered and can be lost entirely.** `run-adl.ps1` pipes the game's
output through `Tee-Object`, which holds it until the pipeline finishes. While the game runs, that file
still contains **the previous session**, and if you force-kill the process the current session's copy is
never written at all. Reading it mid-run and believing it is today's output is an easy and convincing
mistake — the stale content looks perfectly plausible.

**Trap 2 — the real log is exclusively locked while the game runs.** `A-0.log.txt` cannot be read at all
until the client exits, not even with a shared handle. So in practice: **screenshots are your evidence
during the run, and `A-0.log.txt` is your evidence afterwards.** Plan around that rather than fighting
it.

**The way out of both traps: use the server's log instead.** When you are testing anything the client
and server both touch, the server is the better witness — it is readable *while* the run is happening,
it is plain text, and it timestamps the same events. Start it yourself with its output sent to a file
rather than to a console window, and then searching it beats photographing a terminal. Two hours were
lost to the alternative: reading a server console by screenshot, then losing the earlier lines
entirely when the editor panel holding it was resized. If the lines you need have already scrolled
away, the terminal's own find function will still reach them — but a file you can search is better
than both.

**Reading it afterwards, count state entries, not message text.** The turn state appears under two
spellings: `State.enterState [BattleFsm/BattleStateTurnAi]` marks an actual AI turn, while
`BattleStateTurnAI.moveExecutedHandler` is a line printed _inside_ that turn — the capital `AI` is a
typo in the log string, and there is only one class, `BattleStateTurnAi.as`. Counting both inflates the
AI's turn count. Grep for `State.enterState` and nothing else.

---

## 6. What one measured run looked like (recompiled build, under `adl`)

A complete offline practice battle, read from `A-0.log.txt`:

```
GameFsm.startAiBattle spectate=false scene=<default>
Init → Deploy → Start
NextTurn → TurnLocal → NextTurn → TurnAi → NextTurn → TurnLocal
NextTurn → TurnAi → NextTurn → TurnLocal → NextTurn → TurnAi → NextTurn → TurnLocal
```

**4 player turns, 3 computer turns, strictly alternating, player first.** That is measured confirmation
that the offline AI takes its turns — worth having, because [`offline-ai.md`](./offline-ai.md)
necessarily labels much of its behaviour `[Inference]` from reading the decompiled code.

In 1,957 log lines the only errors were **three `#1508`** (the absent audio extension, expected) and
**one `#2032`** — a news fetch reaching for `stoicstudio.com`, the original studio's long-dead server.

**No `#1009` and no `#1069`.** The known crash in the damage-preview overlay
(`DamageFlagOverlay.onRender:74`, see `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md` §3.1) did not
fire — consistent with the account we used fielding no Shieldbanger. Which leads to a testing note
worth keeping:

> **The database row picks your crash exposure.** The offline battle mirrors your active party onto both
> sides, so a single armor-only unit in `party_ids_json` puts one on _both_ teams and makes that crash
> near-certain. Check the party before you run, and choose the account deliberately depending on whether
> you are trying to reproduce the crash or avoid it.

**One open question this run did not settle:** across its 3 turns the computer only moved — we never saw
it spend willpower or use an ability. Three turns is far too small a sample to conclude anything, and
the log does not clearly record ability use. Worth answering properly, because "does the offline AI ever
use its abilities" bears directly on whether it is worth improving.

---

## 7. A correction that run produced (recompiled build, under `adl`)

[`offline-ai.md`](./offline-ai.md) §7 says to press `Ctrl+Shift+A` "during a battle screen". That reads
as though you must already be in a battle. You do not — it worked from the **matchmaking screen**, and
the trigger does no checking of where you are at all: `GameFsm.startAiBattle` transitions
unconditionally (see `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md` §3.3). The practical rule is
the opposite of a requirement: press it only **after** your party has loaded, because firing it earlier
crashes on a null reference.

---

## 8. Two channels — what to drive with clicks, and what to drive with the bridge

Everything above describes driving the game by synthesising input. That works, and it settled a real
question. But it is slow, it breaks when a layout moves, and it needs a real desktop with a real screen.
The client also carries a purpose-built remote-control channel — the **mod bridge**, one small JSON
message per line between the game and a helper program ([`mod-bridge.md`](./mod-bridge.md)). This section
records which of the two owns which job, so the choice is made deliberately rather than by habit.

### The rule

| Channel | Owns | Why |
| ------- | ---- | --- |
| **Mod bridge** | Our fork's own behaviour, reproducing and hunting crashes, measuring what the computer opponent does, and **setting up** any state worth looking at | Deterministic, scriptable, needs no screen |
| **Screen** | Layout, rendering, animation, and final confirmation of anything a player sees | No JSON protocol will ever answer these |

**They are not rivals.** The expensive part of screen testing is not the looking — it is the twenty
clicks needed to reach the state worth looking at. Drive the setup over the bridge, then take the
screenshot. That is the whole reason to have both.

### Why both aim at our own build

The bridge exists only in our rebuilt copy of the game, so choosing it means testing something the
shipped Steam copy is not. That sounds like a serious objection and mostly is not, for two reasons.

**Our build is meant to become what players run.** The public release
(`misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`) is the destination; Stoic has given permission to
redistribute, and the game is delisted from Steam. So the shipped copy is the legacy artefact, not the
target. Work spent making our build testable is work spent on the build players will eventually have.

**The capability gap is narrower than it looks — but it is not closed.** Two-player side-by-side is game
code we compile, and our launcher now drives it (§1). Measured, it gets as far as both halves matching
into one battle and both declaring themselves ready, and no further: neither sees the other as ready, and
the initiative bar dies on the way with a type-coercion error in the resource-SWF blind spot below. The
shipped copy still completes two-player battles. Beyond that, our build differs in runtime (modern AIR
rather than the shipped 2013 one) and in the missing extensions: no sound, no Steam.

So: **run the bridge and single-client screen work against our build, and keep two-player on the shipped
copy until the fault above is fixed.** The long-run direction is unchanged — our build is where this is
heading — but the handover is not done, and writing it down as done would have cost somebody a day.

### What the bridge can do today

`ping`, `start_ai_battle`, `battle_state` and `battle_end_turn`. That is enough to start a practice
battle, read the board — every unit's side, place, and current-versus-base numbers — and step the turns
along deterministically instead of waiting on the countdown ring.

**Measured working 2026-08-23**, in the real game rather than a test harness. The game log for that run
shows the whole path: the helper starting (`ModBridge started host: …node.exe host.js`, so the
descriptor works), its own lines coming back tagged `[modhost]`, `ping` answered `"pong"`, and
`battle_state` answering `{"inBattle":false}` from outside a battle. A separate practice battle ran to
nine turns.

One thing that run also showed: **`Error #3218` while writing to the helper's input** appears
occasionally — once mid-session and once at shutdown. It is caught and logged, traffic continues after
it, and the shutdown one is expected (the helper has already quit on end-of-input by then). Treat a
single one as noise; a burst of them means the helper has stopped reading.

**It cannot yet issue a move or an attack.** The machinery is there and proven (it is the same path the
online game uses to apply an opponent's move), but tile coordinates and target validation are their own
piece of work.

> **A note worth keeping, because the plan document reads more strictly than it means.**
> `Plan-Issue-12` §3.6 says the bridge "cannot host the AI". That is true and refers to a decision-maker,
> which needs the live in-battle objects afresh every turn. It does **not** rule out driving a scripted
> test, which replays known steps and checks the result. Different requirement, different answer.

### Setting it up

```powershell
.\scripts\install-mod-host.ps1              # put the helper in the game's mods\ folder
.\scripts\install-mod-host.ps1 -Remove      # take it out again
```

The helper writes everything the game sent to `mods\transcript.jsonl`, and if a `mods\script.json` is
present it sends those commands in order (`scripts\mod-host\script.example.json` shows the shape). Its
own logging comes back tagged `[modhost]` in the game log.

### The trap this replaces: which build am I actually running?

`run-adl.ps1` used to check only that *a* game file was installed, not that it was ours. Launching the
shipped file under the modern runtime works and looks completely normal — but there is no bridge and no
`Ctrl+Shift+A`, and nothing on screen says so. That was a genuine afternoon-sized trap; the install
directory holds the shipped file by default.

Two things now close it. The launcher compares the installed file against the one we last built and
refuses to start on a mismatch (pass `-AllowUnpatched` to override deliberately). And one line in the
game log — `[modhost] bridge ready` — answers the question outright, because the shipped build cannot
produce it.

---

## Related reading

- [`mod-bridge.md`](./mod-bridge.md) — the message contract, the commands, and what a helper program can
  and cannot see.
- [`build-workflow.md`](./build-workflow.md) — building the SWF, and why the client must run under the
  modern debug runtime with no audio extension.
- [`offline-ai.md`](./offline-ai.md) — what the computer opponent does on its turn, and what it can't do.
- [`battle-engine.md`](./battle-engine.md) — the turn state machine whose names appear in the trace above.
- `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md` — the open blockers, including the damage-overlay
  crash.
