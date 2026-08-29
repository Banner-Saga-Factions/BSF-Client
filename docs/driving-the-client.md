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

Everything below was **measured** on real runs — 2026-08-19, 2026-08-21 and 2026-08-29 — not inferred
from source.
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

### Landing at camp instead — and why removing one argument is not enough

Matchmaking is a dead end for anything that is not a battle. The town is where the great hall (the
roster), the mead house and the proving grounds hang off, and the only way into any of them is to click
a building. `run-adl.ps1 -Landing camp` goes there instead.

**The obvious way to write that option is wrong, and it fails in a way that looks like a hang.** Simply
dropping `--versus_start` does not leave you at camp: the game stops at the **main menu** and never
reports arriving anywhere, so anything waiting for a landing message waits forever. Measured
2026-08-29, then traced:

- `--factions` and `--developer` set the **same single run-mode value**, so whichever comes last wins.
  The launcher passes them in that order, which leaves the mode on DEVELOPER.
- `--versus_start` sets it back to FACTIONS — so that one argument was quietly doing **two** jobs:
  choosing the match search, and repairing the mode the previous argument had overwritten.
- The mode decides `startInFactions` (`GameMainAir.as:714`), and `ReadyState` only enters the state
  that leads to the town when that is true. Otherwise it stops at the main menu.

So the camp landing passes `--developer --factions` in **that** order and leaves `--versus_start` out.
If you ever edit the launcher's argument list, this is the trap: the order of those two is load-bearing
and nothing on screen says so.

**Camp also needs an account that has finished the tutorial.** `FactionsState` sends an account whose
`completed_tutorial` is 0 to the tutorial instead, which reads as the wrong screen rather than as a
refusal. Check the `accounts` table before blaming the launcher.

**Where each building goes**, from `TownState.handleLandscapeClick` — worth having written down,
because the buildings carry no labels until you hover them:

| Hotspot | Goes to |
| ------- | ------- |
| `click_greathall` | the great hall — roster, promotions, and the match banners |
| `click_meadhouse` | the mead house, where units are hired |
| `click_provinggrounds` | the proving grounds |
| `click_hall_of_valor` | the hall of valor |
| `click_marketplace` | opens the marketplace panel over the town |
| `click_firetower` | **avoid** — a quit dialog, or straight out to the main menu |
| `click_trophytower`, `click_weavershut` | accepted, and do nothing |

The two burning braziers are the fire tower. A scripted run that clicks one gets a modal dialog it was
not expecting, which is a slow way to lose a session.

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

**And the rule is not about targeting — it is about clicking.** The paragraphs above describe arming an
attack, which makes the two clicks sound like a feature of the battle board. They are not. Measured
2026-08-29 on the **town**, where nothing is being armed and there is no check mark to see: a single
click on the great hall did nothing at all, twice, on separate runs. The same click preceded by any
other click, or simply repeated a second later, opened it every time — four runs, no exceptions. So
treat **two spaced clicks as the way to click anything**, and a single click as the special case you
ask for deliberately when you want to arm a battle action without committing it.

Worth saying what this is *not*, because both guesses cost a run each. It is not the pointer failing to
register as having entered the target: adding intermediate movement events before the press changed
nothing. And it is not a wrong coordinate: the position was confirmed by magnifying the picture first,
and the very same position worked on the next click.

**Screen scaling will silently break your coordinates.** On a 125% display the game reports the screen
as 1536×864 while Windows reports 1920×1080. Capture and clicking must both use the **Windows** numbers,
and the capturing process must declare itself scaling-aware or the image comes back at the smaller size
and every click lands about a quarter short. Verify a capture really is full-size before trusting any
coordinate derived from it.

**Resizing the window between the picture and the click breaks them just as quietly**, and one Windows
call does it by accident. Asking to "restore" a window — the usual way to un-minimise one — *shrinks* a
window that is maximised. A driver that called it before every click turned a 1938×1038 window into
1042×767 between one step and the next, after which every position read off the previous picture was
meaningless. Un-minimise only a window that is actually minimised, and have whatever does the clicking
refuse a position that falls outside the window as it is now, rather than clicking somewhere arbitrary.

**Under the debug launcher the window opens at about 518×422**, which is the size in the application
descriptor. It is big enough for the mod bridge, which never looks at the screen, and far too small to
read an initiative bar, a stat panel or a banner. Nothing on screen suggests the window is smaller than
it should be. Make it bigger before photographing anything.

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

`ping`, `start_ai_battle`, `battle_state`, `battle_deploy_ready`, `battle_end_turn`, `battle_move` and
`battle_attack`. That is enough to **play a whole battle without a mouse**: start it, get past the deploy
screen, read the board — every unit's side, place, and current-versus-base numbers — walk a unit to a
named tile, have it swing at another unit, and step the turns along deterministically instead of waiting
on the countdown ring. A tile the player could not have clicked, or an attack the game would not have
allowed, comes back refused with a reason rather than half-happening.

**The first four were measured working 2026-08-23**, in the real game rather than a test harness. The
game log for that run shows the whole path: the helper starting
(`ModBridge started host: …node.exe host.js`, so the descriptor works), its own lines coming back tagged
`[modhost]`, `ping` answered `"pong"`, and `battle_state` answering `{"inBattle":false}` from outside a
battle. A separate practice battle ran to nine turns.

**Playing a battle was measured working 2026-08-26**, in one offline practice battle driven entirely from
a helper program with nobody touching the keyboard:

```
battle_deploy_ready          -> ok, state BattleStateTurnLocal
turn 0  warhawk   (0,8) -> (6,8)   6 steps, landed exactly there
turn 2  raider    (0,7) -> (5,8)   6 steps, landed exactly there
turn 4  axeman    (0,6) -> (4,8)   6 steps, landed exactly there
turn 6  archer    (0,10)-> (3,8)   5 steps, then attacked from the new tile
        abl_bow_str level 1 on the computer's warhawk: strength 16 -> 15
        turn 6 -> 7, state BattleStateTurnAi   (the attack ended the turn)
```

Two things in there are worth pulling out. **The attack picked `abl_bow_str` by itself** — the archer's
own strength attack — from a request that named only a target, which is the point of the plain-word
default. And **moving and attacking in the same turn works**, with the walk sequenced ahead of the swing
by the engine rather than by the host waiting and guessing.

**All eleven deliberately-illegal requests were refused with a sentence**, not an error: off the board, no
coordinates, null coordinates, onto its own tile, a friendly target, an unknown unit, an unknown ability,
a tile-aimed ability, an ability hitting several units at once (`abl_tempest`, `targetCount: 2`), a level
the ability does not have, and readying a deployment that had already started.

**One thing two runs disagreed about, which is the finding.** Ending the *computer's* turn was refused in
the first run (`"this turn is already committed"`) and succeeded in the second
(`{"ok":true,"turn":1,"next":2}`), with the battle carrying on normally afterwards. There is a real
window — the computer commits its turn only half a second after its walk finishes — and which side of it
you land on is not something a host controls. Handle both replies; do not build a test on either.

> **The gate that made all of this impossible until now.** An offline battle **never leaves the deploy
> phase on its own**: the engine zeroes the deploy countdown when a battle is not online
> (`BattleFsm.as:113-115`) and a zero countdown means no timer is ever created (`BaseBattleState.as:84`),
> so the phase's own force-deploy can never fire. Measured before the fix: four readings spanning
> thirty-five seconds, all `BattleStateDeploy`, `turn: null`. That is thirty-five seconds of evidence, not
> a proof about eternity — but every exit traced in the code runs through a flag only the Ready button
> sets offline, so the reading and the watching agree. The nine-turn run in §6 had a human present, which
> is the likeliest explanation for how it got past deploy, though nothing recorded says so.
> `battle_deploy_ready` calls the same public method that button calls, and is what makes a scripted
> battle possible at all.

One thing that run also showed: **`Error #3218` while writing to the helper's input** appears
occasionally — once mid-session and once at shutdown. It is caught and logged, traffic continues after
it, and the shutdown one is expected (the helper has already quit on end-of-input by then). Treat a
single one as noise; a burst of them means the helper has stopped reading.

**What it still cannot aim is an ability at a tile** (Rain of Arrows and its kin) **or one that hits
several units at once** (Tempest and its kin). Both are refused with a reason. Anything aimed at exactly
one unit works.

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

> **The automated test in §9 borrows this same slot.** It writes its own `mods\host.json`, naming its
> go-between rather than this helper, and puts yours back when it finishes. So do not expect a hand
> setup to survive a test run that was killed halfway — and if the bridge ever seems to have stopped
> working, look at `mods\host.json` first.

### A driver that already does both

`.claude/skills/run-bsf-client/` is a ready-made handle on all of this, so neither channel has to be
rebuilt from scratch each time. `driver.js` launches the game, talks to the bridge, clicks the window
and photographs it, taking one command per line — `ready`, `battle`, `board`, `move`, `click`, `shot`,
`zoom`. It reuses `tests/lib/game-session.js` for the conversation itself, so there is one
implementation of the launch-and-shutdown machinery rather than two. `SKILL.md` beside it is the
operating manual; this document remains the reasoning behind it.

**Ask the game where it is rather than photographing it to find out.** Every state that the player can
arrive at announces itself to the server — `loc_strand` for the town, `loc_great_hall`, `loc_mead_house`,
`loc_versus` and so on — so a helper watching that traffic can say which screen the game is on, and
therefore whether a click did anything, without taking a picture at all. That is much cheaper than a
screenshot and far more precise than looking at one, and it turns "did that click work?" into a fact.
Two cautions carried over from the readiness rule in section 9: match on the **place**, not merely on
the request, because the login queue sends one too; and remember the announcement is a fact about the
game's state machine, which runs ahead of what has finished drawing.

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

## 9. The first automated test — and the two things it found

Everything above is a person driving the game. `tests/first-battle.test.js` is that same journey with
nobody at the keyboard: it starts the game, watches it log in, starts a practice battle, checks the
board, steps three of the player's turns, and closes the game again. It is the client's first automated
test of any kind. Half a minute on a quiet machine, twice that on a busy one — most of it spent waiting
for the game to load a battle, which is why every wait here is generous.

```powershell
node --test                                # every client test
node --test tests\first-battle.test.js     # only this one
$env:BSF_TEST_VERBOSE=1; node --test       # and watch it work
```

Name the file, or name nothing at all — but **do not name the folder**. `node --test tests\` looks
right and is not: Node runs the folder as though it were a single file and reports a baffling "cannot
find module".

It needs three things in place: the local server up (§1), `AIR_HOME` set and our own build installed
(both checked by `run-adl.ps1`, which refuses to launch a build that is not ours). If the game, the
server or the login live somewhere else on your machine, say so rather than editing anything —
`BSF_GAME_PATH`, `BSF_SERVER_URL`, `BSF_USERNAME`, `BSF_STEAM_ID`.

**One run at a time.** There is one installed game, with one setting naming its helper program, and
every run rewrites that setting. Two runs at once would hand each other the wrong port and then put
each other's settings back — which does not look like a clash, it looks like a flaky game. `node --test`
runs test **files** side by side, so this stops being hypothetical the day a second test file exists.
The driver takes a lock and makes the second run wait its turn; `--test-concurrency=1` avoids the wait.

**It is a test of our build by definition**, since the channel it drives and the practice battle it
starts exist only in the copy we compile. That is the deliberate trade §8 sets out, not an oversight —
but it does mean a failure here can never be blamed on the original game.

### Getting a conversation with a game you started

The game starts its helper program, so a test cannot simply start the game and then talk to it: the
helper is downstream of the game, not upstream of it. Three small files turn that round.

| File | Job |
| ---- | --- |
| `tests/relay.js` | Installed as the game's helper. Calls back to the test already waiting on a numbered door, then copies bytes between the two, changing nothing. |
| `tests/lib/game-session.js` | Starts the game, holds the conversation, closes it down. Everything a test should own — timeouts, failures, shutdown — lives here rather than in the game's helper. |
| `tests/first-battle.test.js` | The checks themselves. |

The test picks a free port, writes `mods/host.json` naming the relay and that port, starts the game and
waits; whatever `host.json` held before is put back at the end. The descriptor names the file **in this
repository** rather than copying it into the game folder, so there is only ever one copy to edit — the
installed `host.js` had already drifted behind the repository's by the time this was written, which is
exactly the drift that arrangement prevents.

Two details worth keeping. The relay **holds on to anything the game says before the test is on the
line**: the message announcing the channel is open arrives the instant the helper starts, a fraction
before the connection completes, and losing it would cost the test its clearest evidence that the right
build is running. And it copies **raw bytes, never text** — unit names contain characters like ð and ö
that take more than one byte, and a chunk can split one down the middle.

### Wait for the game to say it is ready; do not count seconds

A fixed wait before `start_ai_battle` is what the example script does, and it is a guess. The game says
when it is ready, in three messages the tap already carries: the login being answered, the account and
roster arriving, and then a `services/game/location` request — the player landing somewhere.

**The last one is the one that matters, and waiting only for the roster is not enough.** A draft of this
test started the battle as soon as the roster arrived and **the battle silently never started** —
`battle_state` answered `{"inBattle":false}` for two solid minutes with no error raised anywhere.
Waiting for the landing message instead turned that into a battle on the board in nine seconds.

The reason is not that the roster was missing; it had arrived. It is that **the battle was started and
then thrown away.** `FactionsState.handleEnteredState` asks to be told when the faction load finishes
and **never cancels that request** — the class has no `handleCleanup` and never removes the listener. So
whenever the load completes, `factionsHandler` runs *wherever the game has since got to* and calls
`transitionTo(VersusFindMatchState)`, discarding a battle started in between. `Fsm.transitionTo` guards
only on the machine already stopping, so nothing refuses it. Waiting for the landing message means that
jump has already happened and there is nothing left to throw the battle away.

> **The fingerprint, if this ever comes back:** a `/vs/start` with **no** `/vs/cancel` after it. A
> healthy run shows the cancel, because starting the practice battle is what cancels the search.
> Measured across four runs — the three good ones each had one `/vs/start` and a cancel; the failed one
> had two `/vs/start` and no cancel at all, and never reported a battle.

Two things this also settles about `start_ai_battle`: it answers `"ok"` **unconditionally**
(`GameFsm.as`), reporting only that the request was passed on, never that a battle exists — which is the
whole of "no error anywhere". And a battle is confirmed only by `battle_state` saying so.

With the launch arguments `run-adl.ps1` passes, the place the player lands is `loc_versus` — the match
search rather than camp (`--versus_start` → `FactionsState`'s ranked branch, which also returns before
the tutorial check, so an account that has not finished the tutorial still gets here). Note `loc_versus`
itself does not distinguish ranked from a quick match; both send the same word. Two smaller traps in the
same area: the login queue sends a `services/game/location` request too, with a different place, so a
test matching on the request alone can match far too early — check the place, not just the request. And
an offline session never sends one at all, because the game only reports a location when it has a
session key and is not offline.

### Writing the second one — what it will cost, and what to move first

The driver gives a test **transport**: start the game, send a command, wait for a message, poll until
something is true, shut down. What it does not yet give is **steps**. Everything between "the game
launched" and "it is my turn" currently lives inside `first-battle.test.js` as test body — the three
login waits, `start_ai_battle` and the poll for the deploy screen, saying ready, and waiting for a turn
the player controls and has not yet committed.

That is around sixty lines, and the second test starts by copying them. **Including the one wait that
carries a "do not drop this" warning** — the one guarding against the discarded battle above. A warning
that only survives if whoever copies it copies carefully is not much of a warning, which is the argument
for moving those steps onto the driver (`waitUntilReady`, `startPracticeBattle`, `waitForOurTurn`) before
there are two copies of them rather than after. It is a move, not new code.

Three more gaps, named here so the next author meets them on paper rather than at the keyboard. None are
worth building before a second test actually needs them:

- **Nothing reads the board.** "The unit whose turn it is" and "an enemy standing next to this tile" will
  be written by every battle test. They belong next to the driver, not in it.
- **`send` has no "this must have worked" form.** Each acting command needs two checks — that the reply
  came, and that it says `ok` — so a `session.act(...)` that throws with the game's own refusal attached
  would halve the noise. Refusals arrive as ordinary replies with `{ok: false, reason}`, not as errors,
  so the roughly twenty-five documented refusals in [`mod-bridge.md`](./mod-bridge.md) §5 can all be
  tested with no new machinery at all.
- **The driver cannot tell whether the board is moving.** `waitForOurTurn` is also the "safe to close"
  signal, for the reason in the next section — and a test that moves and attacks is far likelier to be
  mid-walk at shutdown than this one is, because an attack ends the turn and hands it to the computer.

> **Three of the four now exist — beside the driver rather than in it.** The run skill's `driver.js`
> (section 8) has the login steps, a readable board, and a "this must have worked" wrapper that stops
> with the game's own refusal; "is the board still?" is answered by comparing two readings half a second
> apart, which catches a walk but not an animation that moves nobody. So the second test's real cost is
> now a **move** into `tests/lib/game-session.js` rather than fresh code — and the argument above still
> stands, because the wait carrying the "do not drop this" warning is still copied rather than shared.
>
> One measurement worth taking across with them: **a move is reported when it is accepted, not when it
> is finished.** A six-step walk answered instantly, still showed the unit on its starting tile a tenth
> of a second later, was two tiles along at one second, and had arrived by three — roughly two tiles a
> second. A test asserting where something stands, or a screenshot meant to show it there, has to wait
> that out.

### Closing the game while a unit is walking hangs it

**This is a real fault in the game, found by the test on its first run** — tracked as
[issue #36](https://github.com/Banner-Saga-Factions/BSF-Client/issues/36). Closing the window mid-battle
starts the game's own exit path, which tears the board down; tearing down a unit that is *still walking*
interrupts the walk, and the interruption sets off a chain that asks the sprite pool for a target
indicator after that pool has been emptied and set to nothing:

```
GameMainAir/exitingHandler -> GameConfig/cleanup -> Fsm/stopFsm -> SceneState/handleCleanup
  -> Scene/cleanup -> BattleBoard/cleanup -> BattleEntity/cleanup
  -> BattleEntityMobility/cleanup -> WalkTilesBehavior/interrupt -> ... -> BattleMove/setExecuted
  -> BattleFsm/turnInRangeHandler -> TargetIndicatorSprite/set url
  -> AnimClipSpritePool/pop -> addPool   ->  TypeError #1009
```

**Name the fault carefully, because the obvious name is the wrong one.** It is tempting to call this
"`AnimClipSpritePool.addPool` reads `pools` after `cleanup` set it to nothing" — true, but that is a
symptom, and fixing that line would not fix the hang. The fault is one level up: **the sprite stores are
torn down while every target marker is still listening to the battle.** `BattleBoardView.cleanup` clears
all three stores and never cleans up its entity views, and the only call to `EntityView.cleanup` — which
is what would unhook a marker — comes from the handler for an entity being *removed*. So each marker
keeps all its listeners through teardown, and the next battle event reaches a store that is now nothing.
Three consequences worth knowing:

- **`BitmapPool.addPool` already has the guard `AnimClipSpritePool.addPool` lacks** (`if(!pools) return
  null;`). Whoever hit this before fixed one sibling and not the other, which is a good sign of the
  shape of the bug and a bad sign for guarding just one more line.
- **Add that guard and the crash moves rather than goes away** — `pop` then returns nothing and the
  reclaim path reads `popped[...]` off the same emptied store.
- **Which class appears in the stack is an accident** of whether that marker was showing a clip or a
  still image; the bitmap store's guard means the same close can land in `BitmapPool.reclaim` instead.

**Why it hangs rather than crashes and exits.** `GameMainAir.exitingHandler` marks the exit as handled
*before* the cleanup loop that throws, and both the `preventDefault()` and the timer that actually calls
`exit()` come *after* it. So the throw strands the shutdown with no route left to finish it, and the
"already handled" mark makes a second attempt return immediately.

Measured both ways: closing while the computer's unit was walking did not complete within twenty
seconds — the game had to be forced — while closing with the board still completed in **1.7 seconds**,
three times over. The walk really is the trigger: a unit is only interruptible between starting a move
and finishing it, and every clean run closed mid-battle with a full board of markers and exited fine.

The test therefore waits for control to come back to the player before closing — a fair thing to check
anyway, since a turn has to come *back* from the computer rather than merely leave the player. Anyone
driving the game by hand can avoid it the same way: **do not close mid-move.** One honest limit: the
bridge does not report whether anything is moving, so "it is the player's turn" is a stand-in for "the
board is still" rather than a direct reading of it.

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
