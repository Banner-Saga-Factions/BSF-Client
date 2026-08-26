# Plan: Improve the Player-vs-AI Battle Opponent (Phased)

Tracked as issue #31 — "The offline opponent plays weakly: it never uses special abilities and never looks ahead".

## continue in a new chat, scoped to Tier 0 only. Paste this to kick it off:

▎ Implement Tier 0 from bsf-client/misc/Plan-Improve-Battle-AI.md — special-ability awareness (faction-safe via targetRule), focus-fire, and anti-suicide, plus the friends-array fix. Surgical overlays on AiPlan.as / AiModuleBase.as + a new AiModuleDredge.as overlay. Explain each edit as you go; stop before Tier 1.

## Context

The offline **Player-vs-AI** mode (`Plan-Issue-12-Player-vs-AI-Public-Release.md`) re-exposes the original Banner
Saga single-player AI, dormant in the Factions client. A run of crash fixes
(`Plan-Fix-Issue-12-ai-battle-init-hang.md`) got it to where the enemy **moves, attacks, and rests** —
but it plays **weakly against a thinking human**. This plan improves it.

**Goal (confirmed with the user):** ultimately a **genuinely challenging** opponent (should beat an
average player sometimes), reached **phased — quick wins first**. So Tier 0 (cheap, high-payoff) is
**execution-ready now**, Tier 1 (the look-ahead that's _actually required_ to reach "challenging") is
**designed as the next step**, and Tier 2 (external engine) is a **roadmap** item.

**On "could we use AI like Stockfish":** Stockfish itself is chess-specific and can't read this board.
What's portable is its _method_ — **search a tree of candidate moves + a strong evaluation function**.
Today's BSF AI is the evaluation half with **no search half**. So the arc is: sharpen the evaluator
(Tier 0) → add shallow search on top (Tier 1) → optionally move the brain out-of-process (Tier 2).
Combat is **near-deterministic** (small per-attack miss chance), so the right search flavor is
**expectimax / expected-damage**, not strict minimax — a detail, not a blocker.

### Two root causes of the weak play (confirmed in code)

1. **It ignores every special/signature ability.** `AiModuleDredge.tickAi` only enumerates the unit's
   basic strength and basic armor attacks (`getFirstAbilityByTag(ATTACK_STR / ATTACK_ARM)`) and falls
   back to `abl_rest`/`abl_end`. The interesting half of every unit's kit is invisible to it.
2. **Zero look-ahead.** It is a **greedy, single-unit, single-turn** planner scoring each move
   **statically** from the current board — no clone, no opponent-reply modeling. It walks units into
   tiles where they die for free, because the positional penalty is tiny next to `WEIGHT_KILL = 200`.

### Two facts that make the fixes safe (verified firsthand)

- **`fake` mode self-reverts** (`engine/entity/model/Entity.as:47-77`): `get stats()` returns
  `_fakeStats ? _fakeStats : _stats`; `set fake(true)` does `_fakeStats = _stats.clone(this)`;
  `set fake(false)` nulls it. So evaluating candidate moves under `board.fake=true` mutates only a
  throwaway clone — **it cannot corrupt the real board, no matter how many candidates we score.** The
  AI already uses this via `BattleAbility.getStatChange()` (`…/model/BattleAbility.as:86-125`); we just
  call it more, and (Tier 1) wrap it in a snapshot/restore loop.
- **Wrong-faction targeting is impossible** (`…/def/BattleAbilityTargetRule.as:43-135` +
  `…/model/BattleAbilityValidation.as:141-144`): `validate()` returns `INVALID_TARGET` unless
  `targetRule.isValid` passes — `FRIENDLY` needs same team, `ENEMY` needs different team, `SELF` needs
  self. `getStatChange` validates first, so a heal/buff can **never** enumerate onto an enemy and an
  attack can never enumerate onto a friend — a double safety net for Tier 0(a).

### Constraints

- The AI brain lives **inside `app.game.air.swf`**, patchable normally (`src/<pkg>.as` overlay →
  `apply-patches` → `build`), but **every tweak needs a client rebuild**. (This is the standing argument
  for Tier 2: ship a bridge once, then evolve the AI with no further reships.)
- `bsf-client/CLAUDE.md`: **surgical patches only, no engine refactors, extend existing classes.** Strong
  typing, explicit visibility, match decompiled style. Tier-0 edits **re-overlay** the existing `src/`
  copies of `AiModuleBase.as`/`AiPlan.as` (which already carry the issue-12 null-safety fixes), plus a
  **new** overlay of `AiModuleDredge.as`.

---

## Current AI — files & flow (what we modify)

| File (decompiled ref / `src` overlay)                     | Role                                                                                                                                                  |
| --------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------- |
| `engine/battle/fsm/state/BattleStateTurnAi.as` (~:20)     | Entry; hardcodes `new AiModuleDredge(this)`; runs `performMove()` then `performAction()`                                                              |
| `engine/battle/fsm/aimodule/AiModuleDredge.as`            | `tickAi()` = STR pass, then ARM pass → `chooseBestPlan()`; `performMove`/`performAction`                                                              |
| `engine/battle/fsm/aimodule/AiModuleBase.as` _(overlaid)_ | `findPlans()` enumerates candidates (already SPECIAL-rank-aware); ctor sets `atkStr`/`atkArm`/`isRanged`; `buildEnemyArray` fills `enemies`+`friends` |
| `engine/battle/fsm/aimodule/AiPlan.as` _(overlaid)_       | `computeWeight()` weighted-sum scoring + positional/threat math; `toString()` logs every plan                                                         |
| `engine/battle/board/model/BattleBoard.as` _(overlaid)_   | `set fake(...)` simulation switch                                                                                                                     |

**Scoring today** (`AiPlan.computeWeight`, weighted sum): `WEIGHT_KILL=200` (+ target-stat bonus), STR
damage ×45, ARM damage ×20, willpower/stars ×10 penalty, self-threat ×0.5 penalty, enemy-in-range ×0.25
reward, friend-distance ×15 (×2 ranged), small move-length penalty. ~40–80 candidates/unit/turn. Every
plan is logged via `AiPlan.toString()` — read the candidate set and chosen plan straight from the log.

---

## Phase 0 — Quick wins (execution-ready; one rebuild)

Three independent additive changes. No new public API, no engine refactor. Each new scoring term gets a
named constant near `AiPlan`'s other `WEIGHT_*` and a private field surfaced in `toString()` so it's
tunable from logs and trivially reversible.

### 0(a) Special-ability awareness — _the biggest single gain_

**Edit `AiModuleBase` ctor (overlaid):** after `atkStr`/`atkArm` are set, build a typed
`public var specials:Vector.<…>` from the unit's active abilities — read the actives ability-def-levels
off the turn entity's `def` (e.g. `entity.def.actives`; **confirm the exact accessor at implementation
time** and null-guard for units with none, matching the existing #12 null style), keeping only entries
whose `(.def as BattleAbilityDef).tag == BattleAbilityTag.SPECIAL`. (`attacks` holds only basic STR/ARM;
`actives` holds the signatures.)

**Edit `AiModuleDredge.tickAi` (new overlay):** add special passes after the STR/ARM passes and before
`chooseBestPlan`, reusing the same one-target-per-tick cursor pattern. **Pick the candidate array from
the special's `targetRule`** (verified routing):

| `targetRule`                                                                                                                              | Candidate array            |
| ----------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| `ENEMY`, `ENEMY_NEIGHBORS`                                                                                                                | `enemies`                  |
| `FRIENDLY`, `FRIENDLY_OTHER`                                                                                                              | `friends`                  |
| `SELF`                                                                                                                                    | `[caster]`                 |
| `TILE_ANY`, `TILE_EMPTY`, `ANY`, `NONE`, `ADJACENT_BATTLEENTITY`, `SPECIAL_RUN_THROUGH`, `SPECIAL_BATTERING_RAM`, `SPECIAL_SLAG_AND_BURN` | **skip (defer to Tier 1)** |

Pass the special's **rank-1 root def** to `findPlans` exactly like the STR/ARM roots; `findPlans` expands
levels internally and already caps SPECIAL level at `RANK`.

**Scoring:** damage specials are **already scored for free** — `AiPlan`'s ctor runs `getStatChange` for
any non-basic `abldef`, routing through the existing STR/ARM damage weights. Non-damage specials
(buff/heal/debuff) yield null statchanges → ~0 weight → harmlessly ignored. **Defer positive scoring of
non-damage abilities to Tier 1** (a heal/buff value heuristic is where mis-valuation risk lives; keep
Tier 0 to damage specials only, which is already a real strength gain).

**Defer to Tier 1 (too risky for a surgical patch):** tile/AoE specials (need a tile-candidate generator

- footprint scoring — `findPlans`/`computeMoveToRange` are entity-target-centric); the movement specials
  (reposition the caster, breaking anti-suicide's landing-tile assumption); and the faction-agnostic
  `ADJACENT_BATTLEENTITY` rule.

**Safety:** faction is chosen from `targetRule` _and_ independently re-checked by `validate()` inside
`getStatChange` — double guard (verified above).

### 0(b) Focus-fire — `AiPlan.as` (overlaid)

The existing "already-damaged target" bonus (`computeStrengthDamageWeight`/`computeArmorDamageWeight`,
the `(original − current) × weight / 2` terms) partly does this, but is weak between guaranteed kills.
Add a bounded term in `computeWeight`: `WEIGHT_FOCUS = 30`; for a damaging plan with a target,
`focusWeight = int(WEIGHT_FOCUS * (1 − target.STRENGTH / target.originalSTR))`, `weight += focusWeight`.
Kept ≤ `WEIGHT_KILL` so a real kill still dominates, but enough to make independently-greedy units
converge fire on the lowest-effective-HP enemy (killing removes a whole enemy turn — dominant here).

### 0(c) Anti-suicide — `AiPlan.as` (overlaid)

`computePositionalEnemyWeight` already estimates incoming damage at the landing tile but scales it only
×0.5 — trivial vs `WEIGHT_KILL`. Factor the per-enemy incoming-damage calc into a small shared helper
(reused by Tier 1), then in `computeWeight`: if predicted total incoming next-turn damage at `mv.last`
**≥ caster STR** (the tile gets the caster killed), subtract `WEIGHT_SUICIDE = 150`. Set **below**
`WEIGHT_KILL` so a _favorable_ lethal trade is still allowed, but above ordinary damage so the AI won't
suicide for chip damage. **Gate it** so it does _not_ apply when this plan itself kills an
equally-or-more-valuable target — that keeps the AI aggressive, not passive.

### 0(d) Fix the latent `friends` leak — `AiModuleBase.as` (overlaid)

`buildEnemyArray` `splice`s `enemies` but never clears `friends` (a cross-instance double-add). Harmless
today, but now **load-bearing** once focus-fire/anti-suicide read `friends`-relative geometry. One line:
clear `friends` alongside the existing `enemies` splice.

---

## Phase 1 — In-client look-ahead (designed; the step that reaches "challenging")

**Seam: subclass, don't patch in place.** New `src/engine/battle/fsm/aimodule/AiModuleSearch.as extends
AiModuleDredge` (inherits the now-special-aware enumeration + scoring). Swap the brain with a one-line
overlay at `BattleStateTurnAi.as:20`, gated behind a new `BattleFsmConfig.aiLookahead` flag (runtime
A/B + instant revert; keeps the legacy `AiModuleDredge` shippable).

**Depth-1 expectimax loop** over the top-K (≈6) statically-scored candidates:
snapshot (engine's `board.fake` stat-clone + save `pos`/`facing`/`alive`) → fake-apply our move+action →
**opponent picks its best single reply** (reuse `getStatChange`/the shared incoming-damage helper;
**detect fake deaths via `STR <= 0`**, since `set alive` is a fake no-op) → evaluate the resulting board
with the existing `computeWeight` terms → restore. Score replies with **expected damage**
`amount × (1 − missChance)` (`getStatChange` already reports `FAKE_MISS_CHANCE`) — that's the expectimax
over hit/miss. Pick the best post-reply candidate; feed it through the unchanged
`chooseBestPlan`/`performAction` path. **Effort ≈ 250–400 LOC.** Perf: K×N≈36 extra synchronous fake
executions on top of ~40–80 — milliseconds; the AI already runs on a `Timer(0,0)` tick loop, so spread
across ticks if a heavy turn ever stutters. Persisted-effect (DoT) modelling is out of scope for depth-1
(the fake clone copies stat _values_, not the effect list) — acceptable.

---

## Phase 2 — External engine via ModBridge (roadmap)

Builds on `Plan-Mod-Bridge-And-Scripting-Host.md`. Serialize battle state to JSON (~200 LOC: walk
`board.entities` → id/team/pos/facing/alive + `stats.getValue(StatType.*)` + each unit's
`attacks`/`actives` ids + willpower/exertion), ship over the existing `ModBridge` command channel
(`src/engine/mod/ModBridge.as`, `registerCommand(name,handler)` returning a result by `id`) to
`mods/host.exe`, compute the move there (alpha-beta / MCTS / learned policy), receive
`{move, ability, level, targetId}`, apply via the same path Tier 0/1 use. **Deferred because:** (1) no
battle-state serializer exists (`toJson`/`serialize` = 0 hits in `engine/battle`); (2) the AI turn is
synchronous in a `Timer` tick — an async stdin/stdout round-trip must park the turn FSM without tripping
deploy/turn timeouts; (3) the host must reimplement enough rules (range, willpower, armor-break/puncture,
miss math) to emit legal strong moves. **Why it's the long-term home:** ship the bridge once, then evolve
the AI with **no further client reships** — the literal "Stockfish-over-UCI" shape.

**Spike verification (2026-07-22) — Phase 2's premise holds.** A read-only investigation (feeding
Wave 1 of `bsf-server/misc/Plan-Reconcile-Server-Docs-With-Client-Doc-Track.md`) confirmed that **today
no ModBridge channel carries live battle state to `mods/host.exe` during an offline battle** — so an
external "brain" would be blind, and a genuinely smarter offline AI stays gated behind a client rebuild.
Evidence: the bridge's only automatic way to watch a battle is the HTTP tap (the copy of server traffic
forwarded to the host — `HttpAction.as:141`/`:253`), which an offline battle, making zero server calls,
never feeds; the generic `emit(...)` fires only for the `BRIDGE_READY`/`SHUTDOWN` lifecycle events
(`ModBridge.as:235`/`:466`) and **no `aimodule/*` or battle-engine code calls it**; and the host→game
commands (`start_ai_battle`, which just returns `"ok"`, and `set_spectator`) only *launch and flag* a
battle — they never read the board back. Checked against `src/engine/mod/ModBridge.as`, a whole-tree
grep, and the pristine shipped-SWF decompile (`%USERPROFILE%\Code\bsf-refs\client-decompiled-as3\` —
**zero** ModBridge references; the original game shipped no such bus). **Upshot — this doesn't change the
plan, it confirms it:** the one-time client build Tier 2 already calls for (the ~200-LOC battle-state
serializer — the code that packages the live board into JSON — plus the streaming/command hook) is
exactly what buys the "evolve the AI with no further reships" property; the launch/steer hooks that
already ship are not enough on their own.

---

## Critical files

| File                                                                      | Tier | Change                                                                                                              |
| ------------------------------------------------------------------------- | ---- | ------------------------------------------------------------------------------------------------------------------- |
| `src/engine/battle/fsm/aimodule/AiPlan.as` _(re-overlay)_                 | 0    | `WEIGHT_FOCUS`/`WEIGHT_SUICIDE` terms in `computeWeight`; shared incoming-damage helper; new fields in `toString()` |
| `src/engine/battle/fsm/aimodule/AiModuleBase.as` _(re-overlay)_           | 0    | Build `specials` list in ctor; clear `friends` in `buildEnemyArray`                                                 |
| `src/engine/battle/fsm/aimodule/AiModuleDredge.as` _(new overlay)_        | 0    | SPECIAL passes in `tickAi`, candidate array by `targetRule`                                                         |
| `src/engine/battle/fsm/aimodule/AiModuleSearch.as` _(new)_                | 1    | Depth-1 expectimax subclass                                                                                         |
| `src/engine/battle/fsm/state/BattleStateTurnAi.as` _(new overlay, ~:20)_  | 1    | One-line brain swap behind `BattleFsmConfig.aiLookahead`                                                            |
| `src/engine/battle/fsm/BattleFsmConfig.as` _(re-overlay)_                 | 1    | Add `aiLookahead` flag                                                                                              |
| `src/engine/mod/ModBridge.as` + new serializer/host                       | 2    | External-engine bridge                                                                                              |
| Reuse (don't edit): `…/ability/model/BattleAbility.as:86` `getStatChange` | 0/1  | The fake-eval primitive both tiers lean on                                                                          |

---

## Verification (run locally; paste back the newest log)

Build loop: `./scripts/apply-patches.ps1` → `./scripts/build.ps1` → copy `_build\app.game.air.swf` →
`…\win32\app.game.air.swf` → `./scripts/run-adl.ps1`. Trigger **Ctrl+Shift+A** (player-vs-AI), play a few
turns, **close the client** (the file log flushes only on close), read the newest
`…\Local Store\logs\A-*.log.txt`. The `AiPlan.toString()` lines show every candidate, each weight
component (the new terms once added), and the chosen plan.

- **First-run sanity (do this once):** dump each unit's actives `tag`/`targetRule` to the log to confirm
  the faction-routing table matches real ability data — the ability/entity JSON loads at runtime and
  wasn't eyeballed during design (contracts were read from the parsing code, not concrete records).
- **0(a) specials:** special-ability plan lines appear (abl id ≠ basic attack); a FRIENDLY/SELF special
  never appears with an enemy target; willpower (EXERTION/WILLPOWER) drops when one is used. **Stat-decay
  regression:** note an enemy's STR/ARM before vs after the AI turn — unchanged except by the _chosen_
  action (validates the fake sandbox under heavier enumeration).
- **0(b) focus-fire:** two wounded enemies → successive AI units pile onto the lower-HP one.
- **0(c) anti-suicide:** bait a kill that leaves the unit lethally exposed → it declines the suicidal
  tile, **but still takes a favorable lethal trade** (proves it isn't over-passive).
- **Tier 1:** flip `aiLookahead` → logs show it rejecting a high-static-weight plan whose post-reply
  expected score is worse.
- No new `#1009` in `engine.battle.fsm.aimodule` (the dormant-AI null-deref pattern from issue #12).

## Risks

- **Ability targeting** (Tier-0 crux): defused by the verified `targetRule` + `validate()` double guard;
  ambiguous tile/AoE/movement/`ADJACENT_BATTLEENTITY` rules are explicitly deferred.
- **A 0-weight special beating `abl_rest`:** floor special plans to require positive weight so resting
  still wins when correct (the existing rest/end fallback handles a null-abldef plan).
- **Over-passivity** from anti-suicide: bounded `WEIGHT_SUICIDE` < `WEIGHT_KILL` + the favorable-trade gate.
- **Latent null-derefs** on unusual kits (issue-12 pattern): guard the same way if they surface.
- **Rebuild per iteration** until Tier 2 — expected; budget for build/test loops.
