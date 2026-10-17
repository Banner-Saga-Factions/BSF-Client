# Plan: a stronger offline battle opponent (issue #31)

Tracked as [BSF-Client #31](https://github.com/Banner-Saga-Factions/BSF-Client/issues/31): "The offline
opponent plays weakly: it never uses special abilities and never looks ahead". This file is the wave plan
and what each wave found. Whether a wave is ready, blocked or done lives on the
[roadmap board](https://github.com/orgs/Banner-Saga-Factions/projects/3), not here. The ready-to-paste
prompt that starts each wave is a comment on the issue.

## What this is about

The offline practice battle (`Ctrl+Shift+A`, or the bridge's `start_ai_battle`) works, but the computer
opponent has two weaknesses. It never uses its units' special abilities, and it never looks ahead: it
scores each possible move against the board as it stands, never asking what the other side will do
next. How it thinks today is in [`../docs/offline-ai.md`](../docs/offline-ai.md).

**Decisions (owner, 2026-10-16):**

- **The thinking stays inside the game.** Quick fixes first, then a one-move look-ahead. Moving the
  "brain" out to a helper program stays on the roadmap.
- **Progress is measured, not guessed.** The match runner ([`../docs/match-runner.md`](../docs/match-runner.md))
  plays the player's side with a simple strategy and reports how often the computer wins.
- **One opponent strength.** No difficulty levels. A hidden developer switch is fine for comparing two
  versions.
- **Fix the opponent's "eyesight" bugs first, then measure.** Add the anti-suicide penalty only if
  suicides still show up after the fix.
- **Unattended runs are fine.** Claude starts the client and the local server, and the runner plays N
  battles in the background.
- **No overlap with the #47 installer work.** #47 changes nothing under `src/` and no build scripts.
  Stay out of its worktree and test folder. The installer packs whatever bundle is built when it runs,
  so the improved opponent ships in the first bundle built after it merges.

**The bar for "challenging", as revised 2026-10-16 after Wave 1's first runs.** The original bar was
"the computer beats the scripted player in at least half of mirror battles". The unchanged computer
already beat the plain scripted player in every battle (see *Measurements*), so that bar measured
nothing. The plain player uses only strength attacks, and armor soaks those up. So the owner chose:

- The yardstick is the **`armor-first`** scripted player: the same simple player, except that it uses
  the armor attack when a strength hit would do 1 damage or less.
- **The bar is the computer winning at least half of the battles against `armor-first`**, with the
  computer's average survivors as the tie-breaker between two versions that both clear it.
- Baselines are recorded for both players, so each later wave can be compared against either.
- Then the owner plays it, as the final check.

**Where that bar stands after Wave 2 (2026-10-16): cleared, but on too little evidence to close the
issue.** The unchanged computer already won 2 of 4 against `armor-first`, exactly the bar, and the Wave 2
build won 4 of 4. But those runs held only 3 and 2 distinct battles: the battles barely vary (see
*Measurements*). The bar has to be re-checked once Wave 3 makes the battles vary.

**Re-checked in Wave 3a (2026-10-16): cleared, on battles that now differ.** With the varied player,
every battle in both runs was distinct, and the installed build (meant to be Wave 2, not verified) won 5 of 8 on `test2` and 8 of 8 on
`443456`. These are the rows 3b and Wave 4 compare against. They are not comparable with the earlier
rows: the varied player may be weaker than the fixed one (not measured).

## Measurements

Each row is one run of the match runner. Until Wave 3a every run used the `test2` account (Steam id
`123456`), whose party is a **Bowmaster, a Siegearcher, 2 Axemen and 2 Warhawks** on each side.
Earlier versions of this file said "2 archers, 2 axemen, a warrior and a warhawk". That was read from the
units' ids, which keep the name each unit was hired under, not its class
([`../docs/match-runner.md`](../docs/match-runner.md) §5). From Wave 3a there is a second account,
`443456`: a Thrasher, a Siegearcher, a Bowmaster, a Warmaster, a Shieldmaster and a Backbiter. The
runner's output folders are in `_build\runner\` (not committed).

| Date | Build | Scripted player | Battles (distinct) | Computer won | Computer survivors, avg | Player survivors, avg | Turns, avg | Suicides | `#1009` |
| ---- | ----- | --------------- | ------------------ | ------------ | ----------------------- | --------------------- | ---------- | -------- | ------- |
| 2026-10-16 | Wave 1 (opponent unchanged from master `9603f55`) | `strength` | 8 (8) | 8 (100%) | 2.88 of 6 | 0 | 65.5 | not counted | 0 |
| 2026-10-16 | Wave 1 (opponent unchanged), runner at `7baa1b8` | `armor-first` | 4 (3) | 2 (50%) | 1.00 | 0.50 | 59.5 | not counted | 0 |
| 2026-10-16 | Wave 2, `--speed 4` | `armor-first` | 4 (2) | 4 (100%) | 3.00 | 0 | 58.5 | 4 (one event, repeated) | 0 |
| 2026-10-16 | Installed build, meant to be Wave 2 (master `bca6dd8`) but not verified, `--speed 4`, runner 3a at variety 25, seed `1197659914`, account `test2` | `armor-first` | 8 (8) | 5 (63%) | 1.38 | 0.50 | 56.9 | 2 | 0 |
| 2026-10-16 | The same, seed `1198581929`, account `443456` | `armor-first` | 8 (8) | 8 (100%) | 2.63 | 0 | 67.3 | 3 | 0 |
| 2026-10-16 | Wave 3b (specials), `--speed 4`, variety 25, seed `1197659914`, account `test2`; stopped after 4 | `armor-first` | 4 (4) | 4 (100%) | 3.50 | 0 | 50.3 | 0 | 0 |
| 2026-10-16 | The same, seed `1198581929`, account `443456`; stopped after 4 | `armor-first` | 4 (4) | 4 (100%) | 3.50 | 0 | 61.0 | 0 | 0 |
| 2026-10-17 | Wave 4 build, brain `dredge`, `--speed 4`, variety 25, seed `1197659914`, account `test2` | `armor-first` | 4 (4) | 1 (25%) | 0.50 | 1.00 | 56.3 | 2 | 0 |
| 2026-10-17 | The same build, brain `search` (look-ahead), same seed and account | `armor-first` | 4 (4) | 4 (100%) | 3.25 | 0 | 53.5 | 0 | 0 |
| 2026-10-17 | The same build, brain `dredge`, seed `1198581929`, account `443456` | `armor-first` | 4 (4) | 4 (100%) | 3.25 | 0 | 66.3 | 1 | 0 |
| 2026-10-17 | The same build, brain `search`, same seed and account | `armor-first` | 4 (4) | 4 (100%) | 3.75 | 0 | 59.8 | 0 | 0 |

"Distinct" counts battles whose fingerprints differ (the summary's "distinct battle traces"). A
battle that repeats another turn for turn adds no evidence; see
[`../docs/match-runner.md`](../docs/match-runner.md) §4. The Wave 2 row is backed by a fifth battle,
the ×4 speed trial, which repeated the same battle as Wave 2's battles 2–4.

Before the baseline, four probe battles with the `strength` player all went to the computer, with 3–5
of its 6 units left. That is what prompted the yardstick change above.

**Check before relying on `armor-first`.** In the baseline run's game log, 134 of the computer's 191
attack choices were at level 2 or higher, and 162 were strength attacks against 29 armor attacks. Both
scripted players only use level 1. So armor soaking up strength hits may not be the whole reason the
plain player loses. The `armor-first` baseline (2 wins in 4) shows it closes much of the gap.

**The baselines are smaller than planned.** A first 20-battle run was stopped by the PC running low on
memory after 2 battles (both computer wins, not counted above). A second run was cut to 10 per player
and then stopped by the owner after 8, before the `armor-first` run began. Wave 2 recorded the
`armor-first` baseline at the start, at 4 battles by the owner's choice, on the Wave 1 build with the
reviewed runner.

**The battles barely vary (found in Wave 2).** Two of the four baseline battles were identical turn for
turn, and four of the five battles on the Wave 2 build were the same battle. Each battle gets a fresh
dice seed, but a roll seldom decides anything, and both sides choose by fixed rules. So the
"Battles" column overstates the evidence; the number in brackets is what counts.

**Wave 3a made them vary (2026-10-16).** With the scripted player taking its second-best option 25 times
in 100, 8 of 8 battles differed in each of the two runs, at the first setting tried. Seen in the
`443456` run: 15 of its 262 player turns ended with no action, all by the player's Shieldmaster, a unit
that covers 2×2 tiles. On each, the game refused every tile it tried as out of reach, so its fixed rule
ended the turn. Why those tiles were out of reach was not checked. The rule was left alone, since
changing it would change the yardstick. In
both runs the computer chose no special, as expected before 3b.

**Wave 3b's runs were stopped at 4 battles each** (owner's choice): the game log had already shown
what the wave needed to see, so the rest would only have firmed up the win rate. Set against the
first 4 battles of 3a's runs, which used the same seeds, the computer went from 3 of 4 won with 1.50
survivors to 4 of 4 with 3.50 on `test2`, and from 4 of 4 with 3.25 to 4 of 4 with 3.50 on `443456`.
Four battles are too few to call that a gain, and the pairing is loose: a seed fixes the scripted
player's choices, but each battle's dice come from the clock.

**Wave 4 compared both brains on one build (2026-10-17)**, switched over the bridge before each battle,
with 3a's and 3b's seeds. The look-ahead (`search`) matched or beat the planner without it (`dredge`) on
computer survivors on both accounts: 3.25 against 0.50 on `test2`, 3.75 against 3.25 on `443456`. It
had no suicides in the 8 measured battles against 3 for `dredge` (the one-battle smoke run of the same build had 1), and no errors: no `#1009`, no "went wrong while faking", and no
failed look-ahead in 233 computer turns. It changed the normal choice on 12 of 110 turns on `test2` and
4 of 123 on `443456`. **Read the `test2` gap with care:** the same `dredge` brain on the same seed won
4 of 4 with 3.50 survivors in 3b's run, and 1 of 4 with 0.50 here. Nothing in `dredge` changed between
the two (the seam only moves "take the top plan" into its own function). So 4 battles on `test2` swing
widely, and that account's gap is mostly noise. The `443456` gap is small. What the runs do show is
that the look-ahead breaks nothing and costs about a quarter of a second per computer turn.

## What reading the code found (2026-10-16; findings 1–4 fixed and measured in Wave 2)

Sources: the opponent files our fork overlays (`src/engine/battle/fsm/aimodule/AiPlan.as`,
`AiModuleBase.as`), the decompile at `%USERPROFILE%\Code\bsf-refs\client-decompiled-as3\`, and the
Factions ability files, decoded from `assets\common\ability\*.json.z` (AMF3, the game's compressed binary
format).

1. **It cannot see danger from melee units.** `AiPlan.computePositionalEnemyWeight` counts an enemy as a
   threat only when `range < rangeMax && range > rangeMin`. The game's own rule
   (`BattleAbilityValidation.as:217-221`) includes both ends. Basic melee is `0..1`, so no whole-number
   distance ever passes and melee threat is always 0. Bows (`2..5`) count only at 3 and 4. The same test
   gates the opponent's own "I threaten them" reward. This is the likeliest cause of "walks into a free
   kill".
2. **It misses exact kills.** The engine kills at `damage >= strength` (`Op_DamageStr.as`: the KILLING
   tag; `BattleEntity.strengthChangeHandler`: `value <= 0`). `AiPlan`'s constructor flags a kill only at
   `amount > strength`, so a blow that takes a target exactly to 0 gets no kill bonus.
3. **The moving unit counts itself as a friend.** `buildEnemyArray` puts the unit taking its turn into
   `friends`, so the "stay near friends" term penalises it for leaving its own square. The earlier plan's
   "friends list leak" was wrong: the list is rebuilt fresh each turn.
4. **The rest-or-advance check counts enemies twice and friends never.** `computePositionalWeight`
   calls `computePositionalWeightEnemies` twice.
5. **A failed imagined move can leave the board in "pretend" mode.** The opponent scores a move by
   playing it on a throwaway copy of the stats ("pretend" mode, `board.fake`). `BattleAbility.getStatChange`'s
   `catch` returns without switching pretend mode off and without moving the unit back. That has never
   been seen to happen, but scoring more abilities makes it more likely.
6. **Specials in Factions.** The reference class list (`client-swf-and-ane/character_classes.json.z`)
   gives:

   | Fits the existing "hit one enemy" scoring (Wave 3) | Needs new work (roadmap) |
   | --- | --- |
   | Sundering Impact (Warmaster, Wardog), Bring the Pain (Shieldmaster), Bloody Flail (Thrasher), Bird of Prey (Bowmaster), Malice (Provoker) | Buffs score 0 today: Stonewall (Axemaster, self), Forge Ahead (Warleader, ally). Aimed at a tile: Rain of Arrows (Skystriker), Slag and Burn (Siegearcher). Special rules: Tempest (Warhawk, two targets), Run Through (Backbiter), Battering Ram (Strongarm) |

   This is the reference copy. The running game may load a different one, so Wave 3 logs the real list.

   **Checked while planning Wave 3 (2026-10-16)** against the installed game's
   `assets\common\character\character_classes.json.z`, which lists the same specials for these classes:
   - **Only promoted classes have a special.** Archer, axeman, warrior and shieldbanger have none. So the
     `test2` party can only ever show one single-enemy special: the Bowmaster's Bird of Prey. Account `443456` shows four:
     Bloody Flail, Bird of Prey, Sundering Impact and Bring the Pain. No test account has a Provoker
     (owner's choice).
   - **Malice does no damage when used.** It sets up a response at the start of the target's next turn
     (`WAIT_FOR_START_TURN`). The opponent judges an action by the strength or armor it removes right away,
     so it will always rate Malice at 0. Scoring it belongs with buff scoring on the roadmap.
   - **Bloody Flail rolls dice for each hit**, picking strength or armor damage at random. When the
     opponent imagines using it, the roll happens during the imagining, so its rating is one random sample.
   - **The planner already half-supports specials.** `AiModuleBase.findPlans` already caps a special's
     level at the unit's rank, and `AiPlan` already measures both strength and armor change for any ability
     that is neither basic attack. What is missing is a pass in `AiModuleDredge.tickAi` that tries them.

Two facts from the earlier plan still hold and make the fixes safe:

- **Pretend mode undoes itself** (`engine/entity/model/Entity.as:47-77`). Switching it on clones the
  stats and switching it off throws the clone away, so scoring a move cannot damage the real board.
  Finding 5 is the one way out of that, and Wave 3 closes it.
- **An ability cannot be aimed at the wrong side.** `BattleAbilityValidation.validate` refuses a target
  that the ability's target rule does not allow, and `getStatChange` validates first.

### The external-brain note, corrected

The earlier plan's "Tier 2" said a helper program could not see a battle: on 2026-07-22 no bridge
channel carried battle state, so an outside "brain" would be blind. **That is out of date.** Since
2026-08-26 the bridge has `battle_state`, `battle_move` and `battle_attack`
(`src/engine/mod/ModBattleControl.as`; [`../docs/mod-bridge.md`](../docs/mod-bridge.md) §5). A helper
program can read the whole board and play a battle. Wave 1's match runner does exactly that, and on
2026-10-16 `battle_state` gained each unit's footprint (`size`) for it.

What an external brain still lacks is narrower: **a way for the computer's own turn to hand control to
the helper and wait.** Today the computer's turn runs inside the game on a timer, and the bridge's move and
attack commands refuse to act on it. The helper would also need the rules the game applies (range, willpower,
armor break, miss chance), though trial and refusal over the bridge covers range and reach cheaply
([`../docs/match-runner.md`](../docs/match-runner.md) §4). It stays on the roadmap.

## Waves (BSF-Client; one wave = one chat = one pull request)

Every wave works in its own client worktree off `origin/master`, never in the main `bsf-client` checkout:
`git -C bsf-client worktree add --no-track -b <branch> ..\..\BSF-client-ai-31 origin/master`. If the
earlier wave has not merged yet, stack on its branch instead. A new worktree has no `_decompiled\`: copy
it from the main checkout, then apply-patches → build → copy the SWF into the game folder → run. Commit
through `scripts/verify-and-commit.ps1`. Each wave adds rows to *Measurements* above.

### Wave 1: the match runner and baseline numbers (no opponent change)

- **Changes:** `scripts/mod-host/runner.js` (the match runner, with the `strength` and `armor-first`
  players), `docs/match-runner.md`, a `size` field on each unit in `battle_state`
  (`src/engine/mod/ModBattleControl.as`, read-only), and this plan.
- **What running it settled** (details in [`../docs/match-runner.md`](../docs/match-runner.md) §4):
  - **A second battle starts without restarting the game.** Every battle in every run started this way.
  - **Each battle gets new dice.** An offline battle has no id (`battleId` is null), so the game seeds
    its dice from its clock. Every battle's trace differed.
  - **Trial and refusal is fast enough; no `battle_reachable` command is needed.** A refusal comes
    back fast enough that trying again costs little, and a turn takes a median of 4 commands (worst 26, over 253 player turns).
    What it did need was each unit's size, without which 4 of the first 28 player turns went to a tile the unit could not
    attack from.
  - **The plain scripted player is too weak to measure against**, which revised the bar (above).
- **Branch:** `feat/ai-match-runner-31`.

### Wave 2: fix the opponent's eyesight, plus focus fire

- **Built** (2026-10-16), in `src/engine/battle/fsm/aimodule/AiPlan.as` and `AiModuleBase.as`, each
  with a `[Inference] BSF-Client #31` comment (details in [`../docs/offline-ai.md`](../docs/offline-ai.md) §6):
  - Findings 1–4: the range test includes both ends like `BattleAbilityValidation`, a kill counts at
    `>=`, the moving unit is left out of `friends`, and the rest-or-advance check adds enemies and friends.
  - Focus fire: `WEIGHT_FOCUS = 30` × the share of strength the target has lost, on strength and armor
    attacks, kept far below `WEIGHT_KILL` (the weights are summed, so this alone does not guarantee a
    kill wins). Shown as `foc=` in the plan log line.
- **Added because battles were too slow to measure** (the owner's request): a developer fast-forward.
  `ModGameSpeed.as` (new), one line in a new `GameWrapper.as` overlay that scales each frame's elapsed
  time, the computer's two pauses in a new `BattleStateTurnAi.as` overlay, the bridge command
  `set_game_speed` (refused above 1 outside an offline battle), and the runner's `--speed`. ×4 cut a
  turn from 3.5 to about 1.65 seconds ([`../docs/match-runner.md`](../docs/match-runner.md) §4).
- **Added to measure suicides:** the runner counts a computer unit that walked up, in a stretch with no
  computer kill, and died to the runner's very next attack.
- **Measured** (*Measurements* above): the `armor-first` baseline first, on the unchanged opponent; then
  4 battles against `armor-first` at ×4. The `strength` run was dropped by the owner's choice: 4 battles,
  after the fix, against `armor-first` only.
  - The computer went from 2 of 4 to 4 of 4, with 3.00 survivors instead of 1.00. This changed two
    things at once: the baseline ran at normal speed and this run at ×4, and the new opponent was never
    run at normal speed. Code reading says speed changes only timing; no run has tested it.
  - Focus fire is not the likely cause: the damage score already adds 22½ points per strength point a
    target has lost, against focus fire's 30 at most. In Factions, leaving an enemy weakened but alive
    can be a deliberate strategy, so the lean toward finishing wounded units is not assumed to help.
  - The log shows the fixes at work: 262 of 414 plans in the trial battle had a non-zero `⌖e` (danger
    from enemies within reach), and 70 a non-zero `foc=`.
- **The anti-suicide term was not added**, by the owner's choice, although the count met the rule set
  for it (at least 1 per battle). The 4 counted were a single event, one of the computer's archers
  (`ai+0+archer_start_1`) at turn 26, repeated in battles that played out the same way. One event in two
  distinct battles is not a pattern. Revisit once battles vary.
- **Timidity:** not seen; the computer won every battle with half its side left.
- **Branch:** `fix/ai-eyesight-31`, stacked on `feat/ai-match-runner-31`. **Model:** Opus, high.

**The anti-suicide term, if needed.** `computePositionalEnemyWeight` already estimates the damage a unit
would take on its landing tile, but scales it by only 0.5, which is tiny next to `WEIGHT_KILL = 200`.
If the predicted damage on the landing tile is at least the unit's strength, subtract
`WEIGHT_SUICIDE = 150`. Keep it below `WEIGHT_KILL` and skip it when the move itself kills a target of
equal or greater value, so a good trade is still allowed and the opponent does not turn passive.

### Wave 3, split in two (owner, 2026-10-16)

Planning found that making battles vary, adding a party that has specials, and the specials themselves
were too much for one pull request, so Wave 3 became 3a and 3b. Every measurement from here on is **8
battles of `armor-first` at `--speed 4`**, on both accounts, with the seed recorded.

### Wave 3a: make battles vary, and record fresh baselines

- **Changes, none to the opponent:** the runner's `--seed`, `--variety` and `--steam-id`
  ([`../docs/match-runner.md`](../docs/match-runner.md) §1, §3). The scripted player breaks exact ties at
  random and takes its second-best option 25 times in 100, from a seed it logs.
- **Measured** on the installed build (meant to be Wave 2, not verified): see *Measurements*.
- **Branch:** `feat/ai-runner-variety-31`. **Model:** Opus, medium.

### Wave 3b: use the single-enemy specials

- **Changes:**
  - `AiModuleBase` builds a `specials` list from `caster.def.actives` (`EntityDef.actives`). It keeps
    only `tag == SPECIAL`, `targetRule == ENEMY` and `targetCount == 1`, null-safe.
  - A new overlay of `AiModuleDredge.as` adds special passes in `tickAi`, after the strength and armor
    passes, using the same one-target-per-tick pattern.
  - A special plan is kept only if its strength or armor change is above 0, so resting still wins when
    it should, and Malice is tried but never chosen.
  - Fix finding 5 with a surgical overlay of `engine/battle/ability/model/BattleAbility.as`, so the
    `catch` switches pretend mode off and puts the unit back. Check `docs/patch-inventory.md` first in
    case it is already overlaid.
  - At battle start, log each opponent unit's actives (id, tag, target rule) to confirm the real data.
- **Verify:** special-ability plan lines appear and specials get used in battle; willpower drops when
  they are used; an enemy's stats change only from the chosen action; whether imagining Bloody Flail
  changes later dice rolls; the runner's numbers on both accounts.
- **Branch:** `feat/ai-specials-31`. **Model:** Opus, high. It adds the planner overlay and uses
  pretend mode far more often.
- **Built and measured** (2026-10-16; numbers in *Measurements*, details in
  [`../docs/offline-ai.md`](../docs/offline-ai.md) §5 and §6):
  - **A special's level follows the player's rule** (owner's choice): the unit's special stat, which
    the game sets to rank − 1, and its willpower. Stoic's rank cap allowed up to one level more than a
    player gets.
  - **The real ability lists match the reference.** The computer's first-turn log listed Bird of Prey,
    Bloody Flail, Sundering Impact and Bring the Pain as tried. Tempest, Slag and Burn and Run Through
    were skipped. No Malice appeared, but neither party has a Provoker, so it was never offered.
  - **Specials are chosen, but rarely.** On `443456`, in 4 battles: Sundering Impact 8 times and Bloody
    Flail 3 times, out of 129 choices; Bring the Pain and Bird of Prey never. On `test2`, Bird of
    Prey 2 times in 4 battles. Bird of Prey's higher levels add reach, not damage, while the bow's
    raised basic attack hit harder (4 damage against 6 in the `443456` log). The planner sees Bring the Pain
    take away only armor (2 at level 1), so a level-2 strength hit beats it.
  - **Willpower drops** on the units that used specials, read from the runner's board readings. Those
    readings cannot tie a drop to one action, since a level-2 basic attack costs willpower too.
  - **Imagining Bloody Flail does not change later dice rolls.** In 349 special passes over 4 battles,
    the battle's real dice were rolled 0 times (the game's own roll count, logged by each special pass).
    The logs also hold the start of a fifth battle, cut short when the runner was stopped; the counts
    here leave it out.
  - **No new errors:** no `#1009`, no "went wrong while faking", no failed special pass, in either run.
  - **Not checked:** that an enemy's stats change only from the chosen action.

### Wave 4: one-move look-ahead

Re-planned 2026-10-17 (plan comment on #31). Since 3b already won 4 of 4 on both accounts, the wave is
judged mainly by **computer survivors**, the bar's tie-breaker.

- **Changes** (the durable write-up is [`../docs/offline-ai.md`](../docs/offline-ai.md) §4, "The
  look-ahead brain"):
  - **One seam in `AiModuleDredge`:** the plan list and the chosen plan are `protected`, and "play the
    top plan" is its own function, `pickPlan`. Nothing else in it changes.
  - **`AiModuleSearch` (new), `extends AiModuleDredge`, overrides `pickPlan`.** For the 6 best
    different plans it imagines our move once, finds the next enemy in the turn order, scores that
    enemy's best basic attack on any of our units it can reach, and takes those points off the plan
    (`WEIGHT_REPLY` = 1). Everything is put back in a `finally`; any error plays the top plan.
  - **The switch is `ModAiBrain`**, read as each computer turn starts, set over the bridge with
    `set_ai_brain`, with runner `--brain`. Not `BattleFsmConfig`: a second, stale copy of that class
    ships inside `gui\battle_initiative.swf`, and a static setting needs a rebuild to flip. A bridge
    setting lets one build measure both brains.
- **What planning and building found:**
  1. **Pretend mode cannot be nested.** `BattleBoard.fake` is one on/off flag: on clones every unit's
     stats, off throws the clones away, and setting it to the value it already has does nothing. So
     the first design's step 3, "pretend-play the reply", would have wiped our own imagined move. The
     reply is worked out from the pretend stats with the game's attack rule instead.
  2. **The game's real miss rule is in `Op_DamageStr`**, not in the `BattleCalculationHelper
     .strengthNormalMiss` helper the kickoff named. Nothing calls that helper, and it counts one point
     more than the attack does. The rule, the same in all three basic strength attacks: a strength
     attack that does not beat armor lands for 1 or misses for 0, at 10% per point short, at most 80%.
  3. **A unit cannot be moved while it holds pretend stats** (`BattleEntity.setPos` returns at once).
     So it is moved before pretend mode starts and moved back after it ends, as `getStatChange` does.
  4. **The reply's route is found on a board that is not told about our imagined move**, since the
     unit's move events are muted while imagining. Distances use the imagined position, but the tile
     we leave still counts as taken. Filed for Wave 4b (point 5) by the owner.
  5. **We know who replies.** `battleFsm.order.aliveOrder` starts with the unit taking its turn, and the
     first entry on the other team is the next enemy to act.
- **Measured** (rows in *Measurements*): the stop rule is met. `search` matched or beat `dredge` on
  computer survivors on both accounts, with no new errors, so `ModAiBrain` defaults to `search` in the
  wave's last commit. Each look takes about 40 ms, so about a quarter of a second per computer turn.
- **The owner played it (2026-10-17)**, one battle on `443456` against the default build (no helper
  connected, so the default brain): the owner won in 46 turns. The game log shows the look-ahead on
  22 of its 23 computer turns (the 23rd had no plan to look at; 131 plans looked at), one changed choice, and no errors.
- **Next:** Wave 4b below, or close #31 (owner's call).
- **Branch:** `feat/ai-lookahead-31`, stacked on `feat/ai-specials-31`. **Model:** Opus, high.

### Wave 4b (proposed 2026-10-17): units that get stuck, or box in a friend

The owner watched the Wave 4 runs and saw units stand still or wander instead of walking around logs
and other units, and a Thrasher block a Varl friend from reaching an attack. Read from the Wave 4 game
logs; not yet fixed:

1. **Walking closer earns nothing.** With no enemy in reach, a "walk toward that enemy" plan is scored
   almost only by its distance from friends (`computePositionalWeight`: the enemy term is 0 out of
   reach). So a unit drifts toward its friends instead of toward the enemy. Seen: in the last `dredge`
   battle on `443456`, the computer's Backbiter went (13,8), (11,10), (8,9), (8,4), (10,6), (9,9), then
   rested twice while the last enemy was out of reach.
2. **The rest rule favours standing still.** `findPlans` rests when the tile it would walk to scores no
   better than where it stands and its willpower is not full, which walking away from friends never
   does.
3. **Friends box each other in.** The friends term (15 points a tile, 30 for archers) bunches the side,
   and nothing scores standing in a friend's way. A 2×2 Varl needs a two-wide gap. Seen: in the last
   `search` battle on `443456`, turn 9, the computer's Warmaster at (12,5) found no route to any of 6
   enemies, with any attack or its special, after its Backbiter moved to (11,6) and an archer to (12,7).
   It ended the turn where it stood.
4. **The route-finder aims only at the tiles touching the target** (`BattleMove.pathToRect`), within
   the unit's move plus 20. If none is free, it returns no route at all, not a partial one.
5. **The look-ahead's reply routes over a stale board** (Wave 4 finding 4, filed here by the owner).
   While imagining, the unit's move events are muted, so the board's map of who stands where
   (`BattleBoardTiles`) still shows it on the tile it would leave and not on the tile it would reach.
   So the replying enemy may be judged unable to pass the vacated tile, or able to walk through the
   imagined one. Distances use the imagined position, so only the route is wrong. Read from code, not
   measured. A fix moves the unit's place in that map for the length of the look, without telling the
   on-screen view, and puts it back in the same `finally`.

**Proposed changes**, measured with the same 4-battle runs on both accounts plus two new runner counts,
"stalled computer turns" (no move and no action while enemies remain) and "boxed-in computer turns" (no
route to any enemy):

- a progress term: points per tile of *walking* distance gained toward the nearest enemy, only when no
  attack is possible;
- rest only when it cannot get closer, or is badly hurt;
- a fallback route to the reachable tile nearest the target by walking distance;
- a weaker pull toward friends: the nearest friend only, or nothing within 2–3 tiles;
- leave room: among tiles that reach the same enemy, prefer the one that keeps the most tiles next to
  it free, counting tiles a 2×2 friend could use;
- if those are not enough, a "don't block" check on the best 2–3 plans: does the end tile cut a friend
  who has not yet acted off from its best target?
- point 5: tell the board's tile map where the imagined unit stands during the look-ahead.

It changes the planner both brains share, so it is its own wave, stacked on `feat/ai-lookahead-31`
(Opus, high), and not part of Wave 4's comparison.

### Roadmap (not scheduled)

- **A Claude sparring partner** ([#80](https://github.com/Banner-Saga-Factions/BSF-Client/issues/80)):
  a Claude Code chat plays the player's side by hand over the bridge. The win rate is at its ceiling
  against the scripted players, so this is the stronger yardstick. Offline player turns have no time
  limit (owner).
- **"Claude learns the game and teaches the in-game AI"**, recorded in #80 as an idea, not scheduled.
  Claude does not learn between chats, so it cannot train the opponent. What it can do is spar and
  read logs.
- Scoring for buffs (Stonewall, Forge Ahead).
- Specials aimed at a tile, and ones that hit two targets. These need aiming code, and the bridge
  refuses them too.
- A deeper look-ahead (more than the next enemy, or the reply's specials).
- The external brain over the bridge (see the corrected note above).

## Critical files

| File | Wave | Change |
| ---- | ---- | ------ |
| `scripts/mod-host/runner.js` _(new)_ | 1, 3a, 4 | The match runner; 3a: `--seed`, `--variety`, `--steam-id`; 4: `--brain` and the look-ahead counts |
| `src/engine/mod/ModBattleControl.as` | 1, 4 | `size` on each unit in `battle_state`; 4: `set_ai_brain` |
| `src/engine/mod/ModAiBrain.as` _(new)_ | 4 | The brain switch |
| `src/engine/battle/fsm/aimodule/AiPlan.as` _(re-overlay)_ | 2 | Findings 1, 2, 4; `WEIGHT_FOCUS`; maybe `WEIGHT_SUICIDE`; new terms in `toString()` |
| `src/engine/battle/fsm/aimodule/AiModuleBase.as` _(re-overlay)_ | 2, 3b | Finding 3; the `specials` list |
| `src/engine/battle/fsm/aimodule/AiModuleDredge.as` _(new overlay)_ | 3b, 4 | Special passes in `tickAi`; 4: the `pickPlan` seam |
| `src/engine/battle/ability/model/BattleAbility.as` _(new overlay)_ | 3b | Finding 5 |
| `src/engine/battle/fsm/aimodule/AiModuleSearch.as` _(new)_ | 4 | The look-ahead |
| `src/engine/mod/ModGameSpeed.as` _(new)_, `src/game/view/GameWrapper.as` _(new overlay)_ | 2 | The developer fast-forward |
| `src/engine/battle/fsm/state/BattleStateTurnAi.as` _(overlay since Wave 2)_ | 2, 4 | Wave 2: the pauses follow the fast-forward. Wave 4: builds the brain `ModAiBrain` picks |

## Risks

- **A special that scores 0 beating rest:** keep only special plans that score above 0.
- **Turning passive** from the anti-suicide term: keep it below `WEIGHT_KILL`, with the good-trade gate.
- **Hidden null references** on unusual unit kits (the issue #12 pattern): guard them the same way if
  they appear. The runner counts `#1009` in every run.
- **A rebuild per change.** Expected; each measurement is about 35 minutes of unattended play per player
  for 10 battles. Close other programs first: a long run was once stopped for lack of memory.
