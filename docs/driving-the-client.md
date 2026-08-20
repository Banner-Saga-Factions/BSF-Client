# Running and driving the client by hand

## Co-Authored-By: Claude <noreply@anthropic.com>

Some client defects only show up on screen. A unit stands in the wrong place, a panel renders empty, a
turn never passes — none of that fails a test, and none of it appears in a diff. This doc is about the
other kind of checking: **start the real game, look at it, click it, and see.**

It covers how to launch it, how to read what you are looking at, how to drive it — including from an
automated agent that can only take still screenshots — and the traps that waste an afternoon if nobody
wrote them down. For _why_ the launcher works the way it does (the runtime mismatch, the missing audio
extension), see [`build-workflow.md`](./build-workflow.md) → "The AIR SDK 33-vs-51 wall". For how the
offline computer opponent actually thinks, see [`offline-ai.md`](./offline-ai.md).

Everything below was **measured** on a real run on 2026-08-19, not inferred from source. Where a claim
is an inference or rests on a small sample, it says so.

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
movement, exertion (how much willpower may be spent in one turn), and break.

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
| `Ctrl+Shift+A` | Start an offline practice battle ([`offline-ai.md`](./offline-ai.md) §2) |
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

---

## 5. Where the logs are — and two traps

There are three log files, and only one of them is useful while the game is running.

| File                                                           | Use it for                                       |
| -------------------------------------------------------------- | ------------------------------------------------ |
| `%APPDATA%\TheBannerSagaFactions\Local Store\logs\A-0.log.txt` | **The real log for the current run.**            |
| `bsf-client\_build\adl-run.log`                                | The launcher's copy — see the trap below.        |
| The launcher's console output                                  | Only the launcher's own status lines.            |

**Trap 1 — the launcher's copy is buffered and can be lost entirely.** `run-adl.ps1` pipes the game's
output through `Tee-Object`, which holds it until the pipeline finishes. While the game runs, that file
still contains **the previous session**, and if you force-kill the process the current session's copy is
never written at all. Reading it mid-run and believing it is today's output is an easy and convincing
mistake — the stale content looks perfectly plausible.

**Trap 2 — the real log is exclusively locked while the game runs.** `A-0.log.txt` cannot be read at all
until the client exits, not even with a shared handle. So in practice: **screenshots are your evidence
during the run, and `A-0.log.txt` is your evidence afterwards.** Plan around that rather than fighting
it.

**Reading it afterwards, count state entries, not message text.** The turn state appears under two
spellings: `State.enterState [BattleFsm/BattleStateTurnAi]` marks an actual AI turn, while
`BattleStateTurnAI.moveExecutedHandler` is a line printed _inside_ that turn — the capital `AI` is a
typo in the log string, and there is only one class, `BattleStateTurnAi.as`. Counting both inflates the
AI's turn count. Grep for `State.enterState` and nothing else.

---

## 6. What one measured run looked like

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

## 7. A correction this run produced

[`offline-ai.md`](./offline-ai.md) §7 says to press `Ctrl+Shift+A` "during a battle screen". That reads
as though you must already be in a battle. You do not — it worked from the **matchmaking screen**, and
the trigger does no checking of where you are at all: `GameFsm.startAiBattle` transitions
unconditionally (see `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md` §3.3). The practical rule is
the opposite of a requirement: press it only **after** your party has loaded, because firing it earlier
crashes on a null reference.

---

## Related reading

- [`build-workflow.md`](./build-workflow.md) — building the SWF, and why the client must run under the
  modern debug runtime with no audio extension.
- [`offline-ai.md`](./offline-ai.md) — what the computer opponent does on its turn, and what it can't do.
- [`battle-engine.md`](./battle-engine.md) — the turn state machine whose names appear in the trace above.
- `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md` — the open blockers, including the damage-overlay
  crash.
