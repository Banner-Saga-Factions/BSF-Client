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
   (`BattleStateTurnAi.as:37` — `delayedCall(0.5, …performMove)`). The developer fast-forward used by
   the match runner shortens it; at normal speed it is half a second ([`match-runner.md`](./match-runner.md)).
2. **Score every option.** `performMove` (`AiModuleDredge.as:47`) kicks off a per-frame ticker; each
   tick, `tickAi` (`:81`) takes one more enemy and builds "walk here and hit that enemy" plans for
   it (`findPlans`, `AiModuleBase.as:205`), trying the unit's basic strength attack, then its basic
   armor-breaking attack, then, since issue #31, each of its special abilities that hits one enemy
   (`findSpecialPlans`, `AiModuleDredge.as:132`). A special's plan is kept only if it would take away
   some strength or armor. (Spreading the work over frames keeps a big board from hitching.)
3. **Weigh each plan** (`AiPlan.computeWeight`, `AiPlan.as:340-377`): a plan that **kills** earns a
   large fixed bonus (+200); damage counts heavily; a blow hard enough to break a target counts extra;
   hitting an enemy that is already wounded earns more, through the damage score and, since issue #31,
   up to 30 points of focus fire;
   moving far or spending willpower costs a little. Where the unit would end up counts too: standing
   within reach of an enemy's basic attack costs points, having an enemy within reach of its own earns
   a few, and every tile between it and each friend costs 15 (30 for an archer).
4. **Play the best one.** `chooseBestPlan` (`AiModuleDredge.as:177`) sorts by weight and hands the
   list to `pickPlan`, which takes the top plan (the look-ahead brain below picks differently); if
   nothing can reach an enemy it either steps closer or rests. After the move finishes, another
   half-second pause, then `performAction` uses the chosen attack or special — or `abl_end` /
   `abl_rest` if there was no worthwhile attack.

[Inference] throughout — read from the decompiled `aimodule/` code.

### The look-ahead brain (issue #31, Wave 4)

There are two brains, and a switch picks between them (`ModAiBrain`, set over the mod bridge with
`set_ai_brain`: [`mod-bridge.md`](./mod-bridge.md) §5). **`dredge`** is everything above. **`search`**
(`AiModuleSearch`, `engine/battle/fsm/aimodule/AiModuleSearch.as`) thinks the same way, then, before it
commits, asks of its best plans: *"if I do this, what is the worst the enemy who acts next can do back
to me?"* **`search` is the default** since Wave 4 measured it (below); `dredge` stays one bridge
command away. Steps 1 to 3 are unchanged; only step 4's choice is different:

1. Take the **6 best different plans**. Plans that end on the same tile with the same ability, level
   and target count once, because the planner makes the same "rest" plan once for every enemy.
2. For each one, **imagine our move once**: stand the unit on the plan's last tile, switch pretend mode
   on, and if the plan attacks, play the attack on the pretend stats.
3. **Find who replies**: the next enemy in the game's turn order (`BattleTurnOrder.aliveOrder`) whose
   pretend strength is above 0. If our imagined attack kills the unit due next, the enemy after it
   replies.
4. **Score its best reply**: its basic strength or armor attack on each of our units it can reach this
   turn, found with the game's own route-finding (`BattleMove.computeMoveToRange`). The best one counts.
5. **Put everything back** (in a `finally` block, code that runs even after an error), then take
   `WEIGHT_REPLY × reply` off the plan's score and play the best plan after that. A tie keeps the plan
   the normal brain ranked higher. On any error it logs `BSF #31 look-ahead failed` and plays the top
   plan, so a turn never stalls on it.

**Why the reply is worked out, not played.** Pretend mode is one on/off switch (`BattleBoard.fake`):
switching it on gives every unit a throw-away copy of its stats, switching it off throws every copy
away, and switching it to the value it already has does nothing. So it cannot be nested. Playing the
reply the usual way (`BattleAbility.getStatChange`, §5) would end the pretend mode our own imagined
move lives in. Instead the reply uses the game's attack rule, read off the pretend stats:

- **Strength attack** (`Op_DamageStr`, the rule all three basic strength attacks use): damage is the
  attacker's strength, plus any strength bonus, plus the puncture bonus if it does not have to move
  first, minus the target's armor. If that comes to 0 or less, the attack lands for 1 point or misses
  for 0, with a 10% miss chance for each point short, at most 80%. (`BattleCalculationHelper
  .strengthNormalMiss` is not used: nothing in the game calls it, and it counts one point more than
  the attack does.)
- **Armor attack**: `BattleCalculationHelper.armorNormalDamage`, the attacker's armor-break, at most
  the target's armor.

**One more trap, from reading the game.** A unit cannot be moved while it holds pretend stats
(`BattleEntity.setPos` does nothing then), so the unit is moved *before* pretend mode starts and moved
back *after* it ends, the order `getStatChange` already uses.

**The weights.** The reply is scored in points similar to the planner's own, and taken off a plan's
score. They are not the same: the planner doubles the damage term when its hit takes the target to or
below the damage, adds a bonus for strength or armor already lost, and subtracts for the target's miss chance;
the reply has none of those, so threats against us can count for much less than our own hits do. The
reply also ignores `MIN_STRENGTH_ATTACK`, `NEVER_MISS`, damage resistance, and, for an armor attack,
current stats (it reads base):

| Term | Points | Where it comes from |
| ---- | ------ | ------------------- |
| Strength the reply takes from one of ours | 45 per point, times the chance it lands | `AiPlan`'s strength damage weight |
| The reply kills one of ours (damage ≥ its strength) | + 200 + its willpower ÷ 3 + strength + armor-break + armor ÷ 2, times the chance it lands | `AiPlan.computeWeight`'s kill bonus |
| Armor the reply takes from one of ours | 20 per point | `AiPlan`'s armor damage weight |
| How much of the reply comes off the plan | `WEIGHT_REPLY` = 1 (all of it) | Wave 4's starting value |

The older "danger from enemies in reach" term (§4, step 3) stays: it covers every enemy roughly, where
the reply covers the next one exactly.

**What it cannot see.** The reply's route is found on the real board, where the tile we imagine
leaving still shows us standing on it: the unit's move events are muted while imagining, as
`getStatChange` mutes them, so the board's map of who stands where is never told. Distances use the
imagined position. It scores only the next enemy, not the turns after that; it ignores the reply's
special abilities and willpower-boosted hits; and the rest and walk-closer plans get the same check,
since walking into a free kill is the case the look-ahead exists for.

**The log lines.** One per plan looked at, then one per turn:

```
BSF #31 look-ahead: plan 7 old -547 reply 135 by 123456+1+archer_start_2 on ai+0+archer_start_1 -> -682
BSF #31 look-ahead: ai+0+archer_start_1 changed its choice from plan 7 to plan 5 after looking at 6 plans
```

The match runner counts them ([`match-runner.md`](./match-runner.md) §2). Each look takes about 40 ms,
so about a quarter of a second per computer turn (measured 2026-10-17). How it compares with `dredge`
is in [`../misc/Plan-Improve-Battle-AI.md`](../misc/Plan-Improve-Battle-AI.md) → *Measurements*.

---

## 5. What it can't do, and the "imagined move" trick

**Its limits:**

- **It uses only the specials that hit one enemy.** Until issue #31 it used none. Specials aimed at a
  tile (Rain of Arrows, Slag and Burn), at two targets (Tempest), at a friend or at itself (Forge
  Ahead, Stonewall), and the ones with their own targeting rules (Run Through, Battering Ram) are
  still never tried. **Malice** passes the filter but is never chosen: it does no damage when used,
  and the planner rates a special by the strength or armor it takes away at once. [Inference]
- **Two of the specials it tries were never chosen on one account.** Measured 2026-10-16 on account
  `443456`: in 4 battles it chose Sundering Impact 8 times and Bloody Flail 3 times, but never Bird of
  Prey or Bring the Pain (on `test2` it chose Bird of Prey twice). Bird of Prey's higher levels add
  reach, not damage, while the bow's raised basic attack hit harder. The planner sees Bring the Pain
  take away only armor, at every level, so a stronger strength hit beats it; whatever else it does
  counts for nothing.
- **It scores only the main target.** Sundering Impact also hurts enemies next to the target; the
  planner does not count them. [Inference]
- **It never walks closer just to bring an enemy into a special's reach.** The special passes keep
  only plans that use the special, so the longer reach of Bird of Prey matters only for a shot it can
  take this turn. [Inference]
- **A lean toward hitting wounded enemies, but no teamwork.** Each unit still plans on its own. The
  original damage score already adds 22½ points for each point of strength the target has lost
  (`AiPlan.as:170-172`); issue #31's focus fire adds at most 30 more. Finishing the wounded one is not
  always right: in Factions, leaving an enemy unit weakened but alive can be a deliberate strategy, so
  whether this lean helps is for the measurements to show.

**The "imagined move" trick.** To score "what would this hit actually do?", the AI needs to *try* the
attack without really changing the board. It does this by running the attack in a **pretend mode**
(`BattleAbility.getStatChange`, `engine/battle/ability/model/BattleAbility.as:86`, overlaid since
issue #31):

1. Flip the board into pretend mode — `board.fake = true` (`:104`).
2. Actually execute the attack, and measure how far the target's stat dropped (`:107-111`).
3. Flip the board back and restore the attacker's position (`:128-130`). If step 2 fails, the error
   branch now does the same (`:115`); before issue #31 it left the board in pretend mode. The failed
   imagined attack may still hold up the turn ([#78](https://github.com/Banner-Saga-Factions/BSF-Client/issues/78)).

Three things keep the pretend attack from leaking into the real game:

- Each unit swaps its real record for a **scratch copy** (`_fakeRecord`) while pretending, so real stats
  are untouched (`BattleEntity.as:539` and `:643-652`).
- The dice hand out a **separate pretend generator** (`_fakeRng`) so the real, reproducible dice stream
  is not advanced (`BattleAbilityManager.as:149-156`). This is why scoring dozens of imagined moves
  never changes the actual rolls the real battle will make. Measured 2026-10-16: across 349 special
  passes in 4 battles, Bloody Flail's random hits included, the real dice were rolled 0 times.
- An imagined lethal hit **can't actually remove anyone**: a unit's `alive` setter is a no-op while
  faking (`BattleEntity.as:549-551`), and `Effect` skips its whole kill-handling block in faking mode
  (`Effect.as:235`), so the target only loses strength on the scratch record. The planner decides a
  blow is lethal on its own, by **arithmetic** — if the imagined strength damage equals or exceeds the
  target's remaining strength, it sets the plan's `killed` flag (`AiPlan.as:116-125`). (Until issue #31
  it needed the damage to *exceed* it, so an exact kill went unrewarded.) (The "killing effect in
  fake" throw at `Effect.as:241` is a defensive assertion that does not fire during scoring.)

So the AI can score every option it likes without ever touching the real board or the shared dice.

---

## 6. What our fork fixed

The AI planner is Stoic's own code, but it had only ever been exercised against the game's scripted
matchups. Pointed at an arbitrary player party it crashed, so the fork adds **three small guards**
(each tagged `[Inference] BSF-Client #12`, none of which changes how the AI *plays*):

| Crash | Cause in the original | Guard |
| ----- | --------------------- | ----- |
| Unit with no basic strength/armor attack (e.g. a Shieldbanger) | the code reads the attack's id without checking it exists | `AiModuleBase.as:58-64` — treat a missing attack as "not a bow", leave it null |
| Scenery prop on the board (e.g. a pole) | props are alive but carry no combat stats, so the plan math asks for an ARMOR stat that isn't there | `AiModuleBase.as:176-181` — skip any board entity without an ARMOR stat |
| Enemy unit with no strength attack | the counter-threat math reads a missing attack before its own guard runs | `AiPlan.as:278-279` — compute that term null-safely |

**Then issue #31 fixed how it sees the board.** Read from the code first, then measured with the match
runner ([`match-runner.md`](./match-runner.md)). Each fix is tagged `[Inference] BSF-Client #31`:

| What was wrong | Effect on play | Fix |
| -------------- | -------------- | --- |
| The "is that unit within reach?" test left out both ends of an attack's range. A basic melee attack reaches 0 to 1 tiles, so no distance ever passed; a bow (2 to 5) only counted at 3 and 4. | It could not see the danger of standing next to an enemy melee unit, nor the chance to threaten one, so it walked into free kills. | Both ends count, as in the game's own rule (`BattleAbilityValidation.validate`) — `AiPlan.as:282` and the test below it |
| A kill needed damage *greater than* the target's strength. | A blow that took a target to exactly 0 got no kill bonus. | Damage equal to the remaining strength counts — `AiPlan.as:118` |
| The unit taking its turn was in its own friends list. | It was marked down for every step away from its own square. | Leave it out — `AiModuleBase.as:187-191` |
| The "rest here or walk closer" check added the enemy term twice and never counted friends. | That choice ignored where friends stood. | Enemies plus friends — `AiPlan.as:242` |

Plus one new term, **focus fire** (`WEIGHT_FOCUS`, `AiPlan.as:51` and `:199`): up to 30 points, in
proportion to the share of strength the target has already lost, on strength and armor attacks alike. Each
plan's log line shows it as `foc=`. It is small beside the existing wounded-target part of the damage
score, so it mostly matters for armor attacks. The measured effect of all of these is in
[`../misc/Plan-Improve-Battle-AI.md`](../misc/Plan-Improve-Battle-AI.md) → *Measurements*.

**Then issue #31 gave it specials** (Wave 3b), each change also tagged `[Inference] BSF-Client #31`:

| What was wrong | Effect on play | Fix |
| -------------- | -------------- | --- |
| The planner never tried a special ability. | Half of each promoted unit's kit went unused. | Each unit's specials that hit one enemy are listed (`AiModuleBase.buildSpecials`) and tried after the basic attacks (`AiModuleDredge.findSpecialPlans`); a plan is kept only if it takes away strength or armor |
| A special's level was capped by the unit's rank. | The computer could use a special up to one level higher than a player with the same unit. | The player's rule, as in `BattleEntity.highestAvailableAbilityDef`: the unit's special stat (`ACTIVE_0`), which the game sets to rank − 1 when it loads the unit, and its willpower, plus our own cap at the ability's top level (`AiModuleBase.findPlans`). Owner's choice |
| A failed imagined move returned without leaving pretend mode (finding 5). | Never seen; it would have left the whole board pretending. The turn may still be held up ([#78](https://github.com/Banner-Saga-Factions/BSF-Client/issues/78)). | The error branch undoes what the success path undoes (`BattleAbility.getStatChange`) |

Two log lines help check it. On the computer's first turn of a battle, `BSF #31 AI actives:` lists
each of its units' abilities as the running game loaded them, and whether each is tried. Each special pass
logs `BSF #31 special pass:` with how many plans it kept and how many of the battle's real dice were
rolled while imagining (`Rng.sampleCount`, the game's own count of rolls).

A separate problem — the offline battle **hanging on the loading screen** — was fixed elsewhere; its
write-up is [`../misc/Plan-Fix-Issue-12-ai-battle-init-hang.md`](../misc/Plan-Fix-Issue-12-ai-battle-init-hang.md).
The full player-vs-AI public-release picture (all the crash fixes and open items) is in
[`../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`](../misc/Plan-Issue-12-Player-vs-AI-Public-Release.md).

---

## 7. Known gaps

- **It sees only the specials that hit one enemy** (§5). Buffs, specials aimed at a tile or at two
  targets, and the ones with their own targeting rules are on the issue #31 roadmap.
- **It looks ahead one move at most, and only with the `search` brain.** The `dredge` brain scores each
  option against the board exactly as it stands, one unit at a time (§4, step 3). It judges danger from
  where each enemy stands *now*, not from where that enemy could walk to before attacking, and a kill
  earns a large fixed bonus while standing somewhere dangerous costs comparatively little. So it can
  still walk a unit into a place where it dies for nothing (§6 has what issue #31 fixed so far). The
  `search` brain (§4, "The look-ahead brain") checks the reply of the next enemy only, and only its
  basic attacks. Further steps are tracked in issue #31 and written up in
  [`../misc/Plan-Improve-Battle-AI.md`](../misc/Plan-Improve-Battle-AI.md).
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
  in the shipped Steam copy.) The key plays at normal speed against the default brain, `search`. To pick
  the brain and the speed, start the battle from a helper script instead:
  [`match-runner.md`](./match-runner.md) §1, "Playing it yourself against a chosen brain".

---

## Related reading

- [`battle-engine.md`](./battle-engine.md) — the turn state machine, the sync hash, and the seeded dice
  the offline battle rides on (and its new "Offline battles — the AI path" pointer).
- [`mod-bridge.md`](./mod-bridge.md) — the `start_ai_battle` command and the spectator flag, from the
  bus side.
- [`data-model.md`](./data-model.md) — where the `_fakeStats` scratch copy from §5 comes from.
- [`patch-inventory.md`](./patch-inventory.md) → "Offline player-vs-AI" — the exact `src/` files this
  feature touches.
