# Offline player-vs-AI battles

## Co-Authored-By: Claude <noreply@anthropic.com>

Our fork added something the original game never shipped: a **practice battle against the computer,
fully offline** — the battle itself sends the server nothing. This doc explains how to start one,
how the computer decides its moves, what it is bad at, and the small fixes we made so it doesn't crash
against a modern party.

Behavior claims here are read off the decompiled AI code and labeled `[Inference]`. The AI
*improvement* roadmap (making it smarter) is deliberately **not** in this doc — that is future work,
tracked separately.

---

## 1. What it is

- A **practice battle against the computer.** You bring your real party; the computer fields a copy of
  it and fights you.
- **Nothing is farmed.** No renown, no rewards, no promotions — the battle is flagged "friendly", so
  kills don't count.
- **No battle traffic.** No matchmaking, no ranking, no per-turn sync — see §3. The game is not silent
  altogether, though: entering the battle screen still reports which screen you are on, and the
  background poll keeps running throughout, at its usual three-second gap unless something else asks
  for a faster one (sending a chat message does).
- A **watch-two-AIs "spectator" mode** is wired at the flag level but not finished (see §7).

---

## 2. How to start one

There are two entry points, and both land in the same place — `GameFsm.startAiBattle`
(`game/session/GameFsm.as:187-197`), which jumps the game to a new state, `AiBattleLoadState`:

1. **A hidden keyboard shortcut — `Ctrl+Shift+A`** during play (`game/cfg/GameKeyBinder.as:19-22`). A
   developer trigger; there is no menu button.
2. **A mod-host command — `start_ai_battle`** over the mod bridge
   (`GameFsm.as:170-176`). This lets an external helper launch a battle with no new client build; the
   command's registration and reply mechanics belong to [`mod-bridge.md`](./mod-bridge.md) → "Commands".

The computer's team is a **mirror copy of your own active party.** `AiBattleLoadState`
(`game/session/states/AiBattleLoadState.as`) reads your party twice into two independent copies — one
for you, one for the AI opponent (`:72-73`) — and marks the battle `friendly=true` (`:77`), which is
what tells the game to skip kill credit and renown. Because it sets up the opponent with **no name**,
the shared battle engine concludes the battle is offline and makes no server calls at all
(`:16-18`). The spectator flag is latched here too, from either an explicit request or the mod bridge's
`ModBridge.spectatorMode` (`:85-86`).

**Starting one is not the same as getting it going.** An offline battle stops at the deploy screen and
**waits there** until something says ready. The engine zeroes the deploy countdown whenever a battle is
not online (`engine/battle/fsm/BattleFsm.as:113-115`), and a countdown of zero means the timer that would
force the deployment through is never created at all (`engine/battle/fsm/state/BaseBattleState.as:84`).
Your units are already standing on their tiles by then — only the confirmation is missing. Two things
supply it: the **Ready button** on screen (`BattleHudPage.guiBattleHudDeployReady`), or the mod bridge's
**`battle_deploy_ready`**, which calls the same public method that button calls. Measured 2026-08-26:
without either, four readings spanning thirty-five seconds all showed the battle still in
`BattleStateDeploy` with no turn started. Anyone scripting a battle needs to know this, because nothing
on the client's side ever times out and complains.

**Setting the record straight — Stoic's leftover "offline" screens are not this.** The original code
carries a few offline-*looking* states, but none is a working offline battle: `SkirmishState` is an
empty stub (a constructor and nothing else), `OfflineState` just sets up an offline account and tears
down the server connection before exiting (no battle), and `ProvingGroundsState` is an **online**
party-arranging screen that talks to the server. The
offline battle is genuinely new to the fork.

---

## 3. The same battle engine as multiplayer — said precisely

An offline battle is **not** a separate, simpler combat system. It runs the *identical* turn state
machine and the *same* seeded dice as a multiplayer battle — both are documented in
[`battle-engine.md`](./battle-engine.md), which this doc does not re-explain.

The **only** thing an offline battle skips in the turn loop is the per-turn **checksum-and-sync
exchange** (it also skips the two poll speed-ups — see [`wire-protocol.md`](./wire-protocol.md) →
"Long-poll mechanics"). In a
multiplayer battle, at the top of every turn each client computes a hash of the board and sends it to
the server so the two clients can prove they stayed in step (the "lockstep" contract). Offline there is
no second client to compare against, so that step is pointless — and the original engine already knew
how to skip it. `BattleStateNextTurn.handleEnteredState` gates the hash-and-send on
`battleFsm.isOnline` (`engine/battle/fsm/state/BattleStateNextTurn.as:170-180`): online, it computes
the hash and sends it; offline, it goes straight to the next turn. The battle-id-seeded dice above that
gate still apply, so an offline battle is just as reproducible as an online one. One practical upshot:
with no sync exchange, an offline battle **cannot desync** — the whole class of turn-0 hash-mismatch
failures that haunts online play simply doesn't exist here. The dispatch that
routes an AI-controlled side to the AI turn-state (`BattlePartyType.AI` → `BattleStateTurnAi`, gated on
`BattleFsmConfig.enableAi`, `:60-69`) is also original Stoic code — the offline path was **dormant in
the engine, not bolted on**. See [`battle-engine.md`](./battle-engine.md#offline-battles--the-ai-path)
→ "Offline battles — the AI path".

---

## 4. How the computer takes a turn

When it is the AI side's turn, `BattleStateTurnAi` (`engine/battle/fsm/state/BattleStateTurnAi.as`)
drives a planner called `AiModuleDredge`:

1. **A half-second pause** so the turn is watchable, not instant
   (`BattleStateTurnAi.as:28` — `delayedCall(0.5, …performMove)`).
2. **Score every option.** `performMove` (`AiModuleDredge.as:38`) kicks off a per-frame ticker; each
   tick, `tickAi` (`:72-94`) takes one more enemy and builds "walk here and hit that enemy" plans for
   it (`findPlans`, `AiModuleBase.as:104-176`), trying the unit's basic strength attack, then its basic
   armor-breaking attack. (Spreading the work over frames keeps a big board from hitching.)
3. **Weigh each plan** (`AiPlan.computeWeight`, `AiPlan.as:298-333`): a plan that **kills** earns a
   large fixed bonus (+200); damage counts heavily; a blow hard enough to break a target counts extra;
   moving far or spending willpower costs a little.
4. **Play the best one.** `chooseBestPlan` (`AiModuleDredge.as:96-125`) sorts by weight and takes the
   top plan; if nothing can reach an enemy it either steps closer or rests. After the move finishes,
   another half-second pause, then `performAction` (`:132-158`) uses the chosen attack — or `abl_end` /
   `abl_rest` if there was no worthwhile attack.

[Inference] throughout — read from the decompiled `aimodule/` code.

---

## 5. What it can't do, and the "imagined move" trick

**Its limits:**

- **It never uses special abilities.** The planner only ever feeds itself the two *basic* attacks
  (strength and armor); a unit's special is never even considered. The code inside `findPlans` that
  would handle a special (`AiModuleBase.as:157-159`) is unreachable from this planner. [Inference]
- **No team-up / focus-fire.** Each unit plans on its own; there is no logic to gang up on one target.

**The "imagined move" trick.** To score "what would this hit actually do?", the AI needs to *try* the
attack without really changing the board. It does this by running the attack in a **pretend mode**
(`BattleAbility.getStatChange`, `engine/battle/ability/model/BattleAbility.as:86`):

1. Flip the board into pretend mode — `board.fake = true` (`:104`).
2. Actually execute the attack, and measure how far the target's stat dropped (`:107-111`).
3. Flip the board back and restore the attacker's position (`:118-120`).

Three things keep the pretend attack from leaking into the real game:

- Each unit swaps its real record for a **scratch copy** (`_fakeRecord`) while pretending, so real stats
  are untouched (`BattleEntity.as:539` and `:643-652`).
- The dice hand out a **separate pretend generator** (`_fakeRng`) so the real, reproducible dice stream
  is not advanced (`BattleAbilityManager.as:149-156`). This is why scoring dozens of imagined moves
  never changes the actual rolls the real battle will make.
- An imagined lethal hit **can't actually remove anyone**: a unit's `alive` setter is a no-op while
  faking (`BattleEntity.as:549-551`), and `Effect` skips its whole kill-handling block in faking mode
  (`Effect.as:235`), so the target only loses strength on the scratch record. The planner decides a
  blow is lethal on its own, by **arithmetic** — if the imagined strength damage exceeds the target's
  remaining strength, it sets the plan's `killed` flag (`AiPlan.as:107-112`). (The "killing effect in
  fake" throw at `Effect.as:241` is a defensive assertion that does not fire during scoring.)

So the AI can score every option it likes without ever touching the real board or the shared dice.

---

## 6. What our fork fixed

The AI planner is Stoic's own code, but it had only ever been exercised against the game's scripted
matchups. Pointed at an arbitrary player party it crashed, so the fork adds **three small guards**
(each tagged `[Inference] BSF-Client #12`, none of which changes how the AI *plays*):

| Crash | Cause in the original | Guard |
| ----- | --------------------- | ----- |
| Unit with no basic strength/armor attack (e.g. a Shieldbanger) | the code reads the attack's id without checking it exists | `AiModuleBase.as:46-52` — treat a missing attack as "not a bow", leave it null |
| Scenery prop on the board (e.g. a pole) | props are alive but carry no combat stats, so the plan math asks for an ARMOR stat that isn't there | `AiModuleBase.as:79-84` — skip any board entity without an ARMOR stat |
| Enemy unit with no strength attack | the counter-threat math reads a missing attack before its own guard runs | `AiPlan.as:242-243` — compute that term null-safely |

The planner driver itself (`AiModuleDredge`) is untouched.

A separate problem — the offline battle **hanging on the loading screen** — was fixed elsewhere; its
write-up is [`../misc/Plan-Fix-Issue-12-ai-battle-init-hang.md`](../misc/Plan-Fix-Issue-12-ai-battle-init-hang.md).
The full player-vs-AI public-release picture (all the crash fixes and open items) is in
[`../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`](../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md).

---

## 7. Known gaps

- **It cannot see any special ability.** Planning a turn, it only ever considers a unit's basic
  strength attack and its basic armour-breaking attack (§4, step 2) — every signature and special
  ability a unit carries is invisible to it, so the interesting half of each kit is never used.
- **It never looks ahead.** Each option is scored against the board exactly as it stands, one unit at
  a time, with no attempt to imagine the reply (§4, step 3). A kill earns a large fixed bonus while
  standing somewhere dangerous costs very little, so it will walk a unit into a place where it dies
  for nothing. Both gaps, and a three-tier plan for closing them, are tracked in issue #31 and
  written up in [`../misc/Plan-Improve-Battle-AI.md`](../misc/Plan-Improve-Battle-AI.md).
- **Portraits.** A known display issue with unit portraits in the offline flow — tracked in the
  public-release plan above.
- **Spectator (watch two AIs) is not finished.** The `SPECTATE` / `ModBridge.spectatorMode` flag is
  read and latched (§2), but the "turn side 0 into a second AI and hide the player's controls" wiring
  is only partly built — planned, not shipped.
- **Ranked and Tournament stay online-only.** They need matchmaking and the server, by design.
- **Try it yourself.** In a battle-capable build, press `Ctrl+Shift+A` to drop into an offline practice
  fight against a mirror of your party. You do **not** need to be in a battle already — measured
  2026-08-19, it works from the matchmaking screen, and the key does no checking of where you are. The
  real constraint runs the other way: press it only **after your party has loaded**, or it fails on a
  missing reference. (This is our own added key, so it exists in a build made from this repository, not
  in the shipped Steam copy.)

---

## Related reading

- [`battle-engine.md`](./battle-engine.md) — the turn state machine, the sync hash, and the seeded dice
  the offline battle rides on (and its new "Offline battles — the AI path" pointer).
- [`mod-bridge.md`](./mod-bridge.md) — the `start_ai_battle` command and the spectator flag, from the
  bus side.
- [`data-model.md`](./data-model.md) — where the `_fakeStats` scratch copy from §5 comes from.
- [`patch-inventory.md`](./patch-inventory.md) → "Offline player-vs-AI" — the exact `src/` files this
  feature touches.
