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
  plays the player's side with a fixed simple strategy and reports how often the computer wins.
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

## Measurements

Each row is one run of the match runner on the `test2` account's party: 2 archers, 2 axemen, a warrior
and a warhawk on each side. The runner's output folders are in `_build\runner\` (not committed).

| Date | Build | Scripted player | Battles | Computer won | Computer survivors, avg | Player survivors, avg | Turns, avg | `#1009` |
| ---- | ----- | --------------- | ------- | ------------ | ----------------------- | --------------------- | ---------- | ------- |
| 2026-10-16 | Wave 1 (opponent unchanged from master `9603f55`) | `strength` | 8 | 8 (100%) | 2.88 of 6 | 0 | 65.5 | 0 |
| — | Wave 1 (opponent unchanged) | `armor-first` | not yet run | | | | | |

Before the baseline, three probe battles with the `strength` player all went to the computer, with 3–5
of its 6 units left. That is what prompted the yardstick change above.

**The baseline is smaller than planned, and half of it is missing.** A first 20-battle run was stopped by
the PC running low on memory after 2 battles (both computer wins, not counted above). A second run was
cut to 10 per player and then stopped by the owner after 8, before the `armor-first` run began. So
**Wave 2 starts by recording the `armor-first` baseline** on the unchanged opponent, before changing
anything. A battle takes about 3½ minutes, so 10 battles is about 35 minutes.

## What reading the code found (2026-10-16, not yet tested in a run)

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
  - **Trial and refusal is fast enough; no `battle_reachable` command is needed.** A refusal costs a
    few milliseconds and a turn takes a median of 4 commands (worst 26, over 253 turns). What it did need was each unit's size,
    without which 1 move in 7 went to a tile the unit could not attack from.
  - **The plain scripted player is too weak to measure against**, which revised the bar (above).
- **Branch:** `feat/ai-match-runner-31`.

### Wave 2: fix the opponent's eyesight, plus focus fire

- **Changes**, all in `src/engine/battle/fsm/aimodule/AiPlan.as` and `AiModuleBase.as`:
  - Findings 1–4: make the range test inclusive like `BattleAbilityValidation`, use `>=` for kills,
    leave the moving unit out of `friends`, and make the rest-or-advance check add enemies and friends.
  - Focus fire: `WEIGHT_FOCUS = 30` × the share of strength the target has lost, kept below
    `WEIGHT_KILL` so a real kill still wins.
  - Show the new terms in `toString()`.
  - Each fix carries a `[Inference] BSF-Client #31` comment, in the #12 style.
- **First, the missing baseline:** 10 battles against `armor-first` on the unchanged opponent.
- **Measure, then decide:** 10 battles against `armor-first`, then 10 against `strength`.
  - If the opponent's units still die on the turn after moving, with no kill to show for it, add the
    anti-suicide term (below).
  - If it turns timid instead (resting while it could attack), tune `WEIGHT_SELF_THREAT` down.
- **Docs:** `docs/offline-ai.md` §4/§5/§7 and `docs/patch-inventory.md`.
- **Verify:** the log shows non-zero `⌖e` for tiles next to a melee enemy; no new `#1009`; the runner's
  numbers against the Wave 1 baseline.
- **Branch:** `fix/ai-eyesight-31`. **Model:** Opus, high. It changes how the opponent decides.

**The anti-suicide term, if needed.** `computePositionalEnemyWeight` already estimates the damage a unit
would take on its landing tile, but scales it by only 0.5, which is tiny next to `WEIGHT_KILL = 200`.
If the predicted damage on the landing tile is at least the unit's strength, subtract
`WEIGHT_SUICIDE = 150`. Keep it below `WEIGHT_KILL` and skip it when the move itself kills a target of
equal or greater value, so a good trade is still allowed and the opponent does not turn passive.

### Wave 3: use the five single-enemy specials

- **Changes:**
  - `AiModuleBase` builds a `specials` list from `caster.def.actives` (`EntityDef.actives`). It keeps
    only `tag == SPECIAL`, `targetRule == ENEMY` and `targetCount == 1`, null-safe.
  - A new overlay of `AiModuleDredge.as` adds special passes in `tickAi`, after the strength and armor
    passes, using the same one-target-per-tick pattern.
  - A special plan is kept only if it scores above 0, so resting still wins when it should.
  - Fix finding 5 with a surgical overlay of `engine/battle/ability/model/BattleAbility.as`, so the
    `catch` switches pretend mode off and puts the unit back. Check `docs/patch-inventory.md` first in
    case it is already overlaid.
  - At battle start, log each opponent unit's actives (id, tag, target rule) to confirm the real data.
- **Verify:** special-ability plan lines appear and specials get used in battle; willpower drops when
  they are used; an enemy's stats change only from the chosen action; the runner's numbers.
- **Branch:** `feat/ai-specials-31`. **Model:** Opus, high. It adds the planner overlay and uses
  pretend mode far more often.

### Wave 4: one-move look-ahead

- **Changes:** a new `src/engine/battle/fsm/aimodule/AiModuleSearch.as` extending `AiModuleDredge`,
  switched in behind a hidden `BattleFsmConfig.aiLookahead` setting by an overlay of
  `BattleStateTurnAi.as:20`. Design below.
- **Stop rule:** the switch defaults on once the runner shows it beats the Wave 3 build. If the computer
  wins at least half its battles against `armor-first`, the owner plays it as the final check and #31
  can close. If not, the wave's write-up names the next step from the roadmap.
- **Branch:** `feat/ai-lookahead-31`. **Model:** Opus, high, or xhigh if the first measurements are
  puzzling. It is the hardest wave: a search loop over pretend mode.

**The look-ahead design.** Subclass rather than patch in place, so the original opponent stays shippable
and the switch can flip between them. For the top ~6 plans by today's score:

1. note the board (pretend mode's stat clone, plus each unit's position, facing and alive flag);
2. pretend-play our move and action;
3. pretend-play the other side's best single reply, scoring expected damage as
   `amount × (1 − missChance)` (`getStatChange` already reports `FAKE_MISS_CHANCE`). That averages over
   hit and miss rather than assuming the worst;
4. detect pretend deaths by `strength <= 0`, since setting `alive` does nothing in pretend mode;
5. re-score with the existing `computeWeight` terms and restore the board.

Pick the best plan after the reply and send it through the unchanged `chooseBestPlan` / `performAction`
path. About 250–400 lines. Cost: about 36 extra pretend runs on top of today's 40–80, which is
milliseconds; the opponent already thinks on a timer, so a heavy turn can be spread across ticks.
Effects that last several turns (damage over time) are out of scope at this depth, because the stat
clone copies values, not the list of effects.

### Roadmap (not scheduled)

- Scoring for buffs (Stonewall, Forge Ahead).
- Specials aimed at a tile, and ones that hit two targets. These need aiming code, and the bridge
  refuses them too.
- The external brain over the bridge (see the corrected note above).

## Critical files

| File | Wave | Change |
| ---- | ---- | ------ |
| `scripts/mod-host/runner.js` _(new)_ | 1 | The match runner |
| `src/engine/mod/ModBattleControl.as` | 1 | `size` on each unit in `battle_state` |
| `src/engine/battle/fsm/aimodule/AiPlan.as` _(re-overlay)_ | 2 | Findings 1, 2, 4; `WEIGHT_FOCUS`; maybe `WEIGHT_SUICIDE`; new terms in `toString()` |
| `src/engine/battle/fsm/aimodule/AiModuleBase.as` _(re-overlay)_ | 2, 3 | Finding 3; the `specials` list |
| `src/engine/battle/fsm/aimodule/AiModuleDredge.as` _(new overlay)_ | 3 | Special passes in `tickAi` |
| `src/engine/battle/ability/model/BattleAbility.as` _(new overlay)_ | 3 | Finding 5 |
| `src/engine/battle/fsm/aimodule/AiModuleSearch.as` _(new)_ | 4 | The look-ahead |
| `src/engine/battle/fsm/state/BattleStateTurnAi.as` _(new overlay)_, `BattleFsmConfig.as` | 4 | The switch |

## Risks

- **A special that scores 0 beating rest:** keep only special plans that score above 0.
- **Turning passive** from the anti-suicide term: keep it below `WEIGHT_KILL`, with the good-trade gate.
- **Hidden null references** on unusual unit kits (the issue #12 pattern): guard them the same way if
  they appear. The runner counts `#1009` in every run.
- **A rebuild per change.** Expected; each measurement is about 35 minutes of unattended play per player
  for 10 battles. Close other programs first: a long run was once stopped for lack of memory.
