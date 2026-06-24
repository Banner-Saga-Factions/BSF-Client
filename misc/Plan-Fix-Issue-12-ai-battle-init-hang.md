# Plan — Fix BSF-Client #12, finding #2: offline AI battle loads but is not playable

> **Status (2026-06-23): PLAYABLE END-TO-END — milestone reached.** A full offline AI battle now runs
> **deploy → resolution with 0 uncaught `#1009`** (Wave 2 exit criteria met; verified by the user). The
> enabling fix is the scoped `battle_initiative.swf` → `currentDomain` reroute — see the "Crash A RESOLVED"
> update below. The title keeps "init-hang" for link stability, but that label and the earlier `frameLeft`
> diagnosis were both wrong; the real root causes are in the fix table and dated updates below.
>
> **Remaining, deferred to future cold-start chats:** finding #1 (unit portraits) is **confirmed still
> missing** after the reroute → Wave 3; AI-vs-AI spectator → Wave 4.
>
> Canonical wave plan: `~/.claude/plans/review-bsf-client-misc-plan-fix-issue-12-clever-storm.md`.

## TL;DR (read this first)

1. The battle is **not** stuck in init. Init completes; it reaches `BattleStateDeploy` and sits there dead.
2. The deploy stall is caused by a **null-reference crash (`TypeError #1009`) while the battle HUD is being
   built** — but **not** where the old plan said. The real crash is
   `BattleHudPageLoadHelper.checkInitiativeEntities → GuiInitiative.setInitiativeEntities(null) →
GuiUtil.updateDisplayList`. The initiative bar is asked to render **before any entities exist**, and the
   old gui-SWF copy of `GuiInitiative` dereferences a null in its empty/"nonsetting" branch.
3. A broken HUD ⇒ deploy controls don't work ⇒ deployment never completes ⇒ match never starts.
4. **The fix is in `app.game.air.swf`, not the gui SWF.** `BattleHudPageLoadHelper` (the caller that passes
   the null) lives in `app.game.air.swf` and is patchable the normal way (`src/` → `apply-patches` →
   `build`). Guarding the null call there stops the crash without touching `battle_initiative.swf`.

## How we know (runtime evidence)

Authoritative log: `%APPDATA%\TheBannerSagaFactions\Local Store\logs\A-8.log-AI-battle-failed.txt`.
(The `…\Local Store\logs\A-*` files are from unrelated tests.)

```
GuiBattleHud.initiative value=[object battle_initiative] _initiative=null
GuiInitiative.init
GuiInitiative.setEntities null, len=_          <- entities passed in are NULL
GuiInitiative.setEntities deployMode=false     <- NOT the deploy branch
GuiInitiative.setEntities nonsetting-start     <- the empty/"nonsetting" else branch
[ERROR] ... TypeError #1009 ...
    at game.gui::GuiUtil$/updateDisplayList()
    at game.gui.battle.initiative::GuiInitiative/setInitiativeEntities()
    at game.gui.page::BattleHudPageLoadHelper/checkInitiativeEntities()
    at game.gui.page::BattleHudPageLoadHelper/initiativeLoadedHandler()
    ...
    at game.gui.page::ScenePageBattleHandler/createHud()
```

After the crash the FSM still limps into `BattleStateDeploy` and stays there until the client is closed —
the "stuck in deploy" symptom — because the HUD failed to build.

## Why the original `frameLeft` theory was wrong

- The crash log shows `deployMode=false` and `entities=null`. The `frameLeft` derefs are in the **deploy**
  and **normal** branches (entities present) — neither runs here. Execution goes to the **else** branch.
- `startingParent` is **not** null (the old theory's premise): `GuiBattleHud.set initiative`
  (`GuiBattleHud.as:67-83`) `addChild`s the initiative before `init()` runs, so `this.parent` is the hud.
- The class that runs is an **older copy inside `gui\battle_initiative.swf`** (it logs `nonsetting-start` /
  `setEntities null`, strings that exist in no reference tree and not in our `src/` copy). The committed
  `frameLeft` guard patched the `app.game.air.swf` copy — which is **dead at runtime** and wouldn't crash
  here anyway (`GuiUtil.updateDisplayList` already null-guards its parent arg, `GuiUtil.as:136-139`).

## Why the original game never crashed here

`setInitiativeEntities(null, …)` is a benign "nothing to show yet" call. The original game's load-order
timing populated entities before the initiative SWF finished loading, so the empty branch ran with the bar
already hidden / never hit the null. The offline AI path (`AiBattleLoadState`) loads the initiative SWF while
entities are still null, so it reaches the old gui-SWF copy's faulty empty branch.

## The fix (Phase 1 — landed in `src/`)

Guard the null-entities call in the **caller**, which is in `app.game.air.swf` and patchable normally.

`src/game/gui/page/BattleHudPageLoadHelper.as` (full-file overlay of the decompile; one method changed):

```actionscript
private function checkInitiativeEntities() : void
{
   // guard null entities -- see the in-file comment for the full why
   if(_initiative && initiativeEntities)
   {
      _initiative.setInitiativeEntities(initiativeEntities,initiativeDeployMode);
   }
}
```

- Guards **null only**, not empty-length — an empty vector is a legitimate "hide the bar" call and the old
  branch handles empty without the null deref.
- Skipping the initial null call is behavior-preserving: the bar is hidden by default; the real, populated
  call runs later (via `setInitiativeEntities` → `checkInitiativeEntities`) and renders normally.
- Shared by both modes: `ScenePageBattleHandler.createHud()` (`:143`) is unconditional, so **AI-vs-AI
  spectator hits the same crash** — this fix unblocks spectator too.

The old `src/game/gui/battle/initiative/GuiInitiative.as` overlay is **kept but inert** (the gui-SWF copy
runs, not it); its header now says so and its `frameLeft` guards are marked speculative-until-Phase-3.

## If a second crash appears (Phase 2 → Phase 3)

The A-8 crash happened on the **initial null call**, before the deploy branch ever ran with real entities. So
after Phase 1, re-test and watch: if a **new** gui-SWF-internal `#1009` surfaces (e.g. the deploy-branch
`frameLeft`), escalate to the systemic fix:

- **Phase 3 (recommended systemic):** change `DisplayResourceLoader` (`DisplayResourceLoader.as:61-64`) to
  load gui SWFs into `ApplicationDomain.currentDomain` with `allowCodeImport = false`, so the symbol
  `gui.battle_initiative` binds to the **newer, fixed** `GuiInitiative` in `app.game.air.swf` (and our `src/`
  overlay) instead of the stale gui-SWF copy. This removes the whole class of gui-SWF-internal bugs at once,
  makes the inert `GuiInitiative` overlay live, and likely fixes **finding #1** (missing portraits — same
  blind spot). Risks: verify the gui SWFs' symbol classes all exist in `app.game.air.swf`; broad blast radius
  (all gui SWFs use this loader — consider scoping to the battle gui SWFs).
- **Fallback:** a scripted JPEXS-CLI build step that applies `src/` AS overlays into the gui SWFs at build
  time (reproducible, low runtime risk, more tooling). Hand-editing the SWF in JPEXS is rejected for a
  player-facing feature — not version-controlled.

## Update (2026-06-22) — Phase 1 verified; next blocker was the dormant AI (now also fixed)

Local build + run (`A-0.log-ai test2.txt`) confirmed **Phase 1 works**: the battle deploys, Ready works, and
the player takes a turn — the HUD `#1009` is gone. The next blocker was a **separate crash in the dormant
AI** (engine code, not a gui SWF). When the enemy AI computes its move it throws:

```
TypeError #1009 at AiPlan$/computePositionalEnemyWeight
  <- computePositionalWeightEnemies <- computePositionalWeight <- AiModuleBase/findPlans
  <- AiModuleDredge/tickAi <- timerHandler
```

Root cause: `BattleAbilityDefLevels.getFirstAbilityByTag(ATTACK_STR)` returns **null** for a unit with no
strength attack (a Shieldbanger's basic attack is armor-only), and two spots deref that result before the
null check:

- `AiPlan.computePositionalEnemyWeight` (`:234`) — `…getFirstAbilityByTag(ATTACK_STR).def` on an **enemy**
  (the crash seen). The value is even guarded one line later (`if(_loc13_)`), so the deref just predates the
  guard. **Fixed:** compute it null-safely.
- `AiModuleBase` constructor (`:43`) — `atkStr.id`/`atkArm.id` on the **caster** (the _next_ crash, the
  moment the AI's own Shieldbanger acts). **Fixed:** null-safe bow check; downstream
  (`AiModuleDredge.performMove`, `AiPlan`) already tolerates null `atkStr`/`atkArm`.

Both are in `app.game.air.swf` and patched the normal way. New overlays:
`src/engine/battle/fsm/aimodule/AiPlan.as`, `src/engine/battle/fsm/aimodule/AiModuleBase.as`. The repeated
`Op_MoveToRange … as close as possible` spam in the log is the AI timer retrying after each uncaught crash;
fixing the `#1009` should let `findPlans` complete so the AI commits a move and ends its turn.

This is the **"dormant AI never exercised in arbitrary Factions PvP"** risk: latent null-derefs surface when
the AI faces a real mirrored human/varl party. If re-test hits another `#1009` in `engine.battle.fsm.aimodule`,
it is most likely the same missing-ability pattern in another spot — guard it the same way.

> Side note: the Adobe AIR error you dismissed at match load is almost certainly the known benign FMOD sound
> failure (`Error #1508`, adl has no FMOD ANE) — the client runs without sound. Not a blocker.

## Update (2026-06-23) — two more `#1009`s, both fixed in `app.game.air.swf`

After the AI fix, the AI now **moves and rests** (AI fix verified). Two further crashes, both again inside
`app.game.air.swf` utilities (no Phase 3 needed):

1. **Deploy HUD crash** — `BattleStateDeploy.handleEnteredState → BattleBoard.autoDeployPartyById → … →
BattleHudPage.checkDeploymentInitiative → BattleHudPageLoadHelper.setInitiativeEntities (public) →
checkInitiativeEntities → GuiInitiative.setInitiativeEntities → GuiUtil.updateDisplayList #1009`. This is
   the _deploy branch_ with **real** entities (so it passes the Phase-1 null guard). The old gui-SWF
   `GuiInitiative` passes a **null child** to `GuiUtil.updateDisplayList`, which only guarded the _parent_.
   **Fixed:** `src/game/gui/GuiUtil.as` — guard null `param1` in `updateDisplayList` + `updateDisplayListAtIndex`
   (behavior-preserving: null child = nothing to add/remove).
2. **Ability-info crash** — selecting the Siege Archer ability: `InfoBarHelper.showAbilityInfo #1009`. It
   walks `guihud.initiative.infobar.setVisible(...)` / `turn.ability.def.description` unguarded. **Fixed:**
   `src/game/gui/InfoBarHelper.as` — walk the chain null-safely; skip showing the info bar if a link is null.

## Fixes applied so far (running list — all `app.game.air.swf`, normal patch model)

| #   | Symptom                                                 | Root cause                                                                                                                             | Overlay                                                                                                                |
| --- | ------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 1   | HUD #1009 at battle load, stuck in deploy               | `checkInitiativeEntities` calls `setInitiativeEntities(null)` → old gui-SWF empty branch                                               | `src/game/gui/page/BattleHudPageLoadHelper.as`                                                                         |
| 2   | AI #1009, enemy never acts                              | `getFirstAbilityByTag(ATTACK_STR).def` on a str-less **enemy** (Shieldbanger)                                                          | `src/engine/battle/fsm/aimodule/AiPlan.as`                                                                             |
| 3   | (latent) AI #1009 when AI's own str-less unit acts      | `atkStr.id`/`atkArm.id` on null in ctor                                                                                                | `src/engine/battle/fsm/aimodule/AiModuleBase.as`                                                                       |
| 4   | Deploy HUD #1009, `setInitiativeEntities` deploy branch | null **child** into `GuiUtil.updateDisplayList`; the gui-SWF `GuiInitiative` symbol still runs, but `GuiUtil` (called **by name**) now resolves to our guarded copy via the domain reroute | `src/game/gui/GuiUtil.as` + `src/engine/resource/loader/DisplayResourceLoader.as` (route `battle_initiative.swf` → `currentDomain`) — **FIXED, verified ~4 battles / 0 #1009** |
| 5   | #1009 _selecting_ an ability (`showAbilityInfo`)        | unguarded `infobar` chain / `def.description`                                                                                          | `src/game/gui/InfoBarHelper.as`                                                                                        |
| 6   | #1009 _executing_ an ability (`hideAbilityInfo`)        | same unguarded `infobar` chain                                                                                                         | `src/game/gui/InfoBarHelper.as`                                                                                        |
| 7   | AI `ArgumentError: No such stat: ARMOR on prop+pole03`  | `buildEnemyArray` treats scenery props as enemies; props lack combat stats                                                             | `src/engine/battle/fsm/aimodule/AiModuleBase.as`                                                                       |
| 8   | Great hall `#1069 IGuiContext::party/renown not found` (Quick Match crash + great-hall/roster portraits blank) | stale `great_hall.swf` / `mead_house.swf` `GuiGreatHall` / `GuiMeadHouse` call old `context.party` / `context.renown`; rebuilt app moved them onto `context.legend.*` and dropped them from the context | `src/game/gui/IGuiContext.as` + `src/game/gui/GameGuiContext.as` + `src/game/gui/mock/MockGuiContext.as` — compat shim re-adds `party`/`renown` (→ `legend.*`). **FIXED, verified 2026-06-24** |
| 9   | Mead House `#1069 IGuiContext::rosterSlotAvailable not found` (clicking **Hire** throws) | stale `mead_house.swf` `GuiMeadHouse` calls `context.rosterSlotAvailable()` (`:296`) + `context.purchaseRosterUnit(...)` (`:264`) as **functions**; the refactor moved both onto `Legend` (`rosterSlotAvailable` getter, `hireRosterUnit`) and dropped them from the context | `src/game/gui/IGuiContext.as` + `src/game/gui/GameGuiContext.as` (delegate → `legend.rosterSlotAvailable` / `legend.hireRosterUnit`); `MockGuiContext` already satisfies. **FIXED, verified 2026-06-24 (Hire confirmed)** |

`GuiInitiative.as` overlay remains **inert/parked** (gui-SWF copy runs).

## Strategic inflection (2026-06-23): the deploy HUD crash (Crash A) needs Phase 3 — RESOLVED (see next section)

Fix #4 (the `GuiUtil` null-child guard) was built and deployed, but the deploy crash **persists unchanged** —
while fix #5/#6 (`InfoBarHelper`) clearly took effect (the throw moved `showAbilityInfo` → `hideAbilityInfo`).
The only explanation: the `GuiUtil.updateDisplayList` call made _from inside_ `GuiInitiative` resolves to a
**`GuiUtil` bundled inside `battle_initiative.swf`**, not our patched `app.game.air.swf` copy. (Gui SWFs load
with `allowCodeImport` into a child ApplicationDomain; classes the gui SWF was compiled with — `GuiInitiative`
**and its dependency `GuiUtil`** — resolve from that child domain first.)

**Consequence:** Crash A cannot be fixed by guarding `GuiUtil` (or any class the gui SWF bundled) from
`app.game.air.swf`. This is the **Phase 3** trigger. Two tracks remain:

- **Track 1 — `app.game.air.swf` guards (cheap, continue as before):** any crash whose _throwing_ class is NOT
  bundled in the gui SWF — the AI (`AiPlan`, `AiModuleBase`) and HUD helpers reached from `app.game.air.swf`
  (`InfoBarHelper`, `BattleHudPageLoadHelper`). Fixes #6/#7 are here.
- **Track 2 — Phase 3 (systemic, deliberate) for the gui-SWF HUD:** in `DisplayResourceLoader`
  (`DisplayResourceLoader.as:61-64`) load the battle gui SWFs into `ApplicationDomain.currentDomain` with
  `allowCodeImport = false`, so the `app.game.air.swf` copies of `GuiInitiative` **and** `GuiUtil` (both
  already patched in `src/`) win. Fixes Crash A and likely the rest of the HUD crashes at once, and makes the
  parked `GuiInitiative.as` live. **Verify first:** every class the battle gui SWFs instantiate by symbol must
  exist in `app.game.air.swf` (else those symbols fail to resolve); broad blast radius — scope to the battle
  gui SWFs. **Fallback:** ship a JPEXS-patched `battle_initiative.swf` via a scripted build step if Phase 3's
  class-linkage is too risky.

> Playbook caveat (updates step 2 below): the throwing class is _usually_ in `app.game.air.swf`, but NOT when
> the gui SWF bundled it (e.g. `GuiUtil` called from `GuiInitiative`). If a guard built into `app.game.air.swf`
> has no effect on the crash, suspect a gui-SWF-bundled copy → Track 2.

## Update (2026-06-23, later) — Crash A RESOLVED with a *scoped, lightweight* Phase 3

Crash A is fixed; the offline AI battle is playable (deploy → turns → resolution). The fix is a **single line**
in `DisplayResourceLoader` — much cheaper than the full Phase 3 above.

**What we did:** route **only** `battle_initiative.swf` into `ApplicationDomain.currentDomain`, keeping
`allowCodeImport = true` (not the `false` the inflection proposed):

```actionscript
_loc5_ = url.indexOf("battle_initiative.swf") != -1 ? ApplicationDomain.currentDomain : null;
```

**The surprising mechanism (proven against the runtime log).** The gui-SWF `GuiInitiative` **symbol still binds
to its own bundled copy** — it keeps logging `GuiInitiative.init` / `setEntities ... nonsetting-start`, strings
absent from both the raw `_decompiled` app copy and our `src/` overlay. So the reroute did **not** make our
`GuiInitiative` win. **But `GuiUtil` is referenced _by name_**, so inside `currentDomain` the gui-SWF
`GuiInitiative`'s `GuiUtil.updateDisplayList(...)` calls resolve to the already-defined, **guarded**
`app.game.air.swf` `GuiUtil` (`src/game/gui/GuiUtil.as`), which null-guards the child and absorbs the crash.
**Symbol-linkage classes stay gui-SWF; by-name class references resolve to the app copy** — that asymmetry is
the whole trick, and it means we did **not** need `allowCodeImport=false` (and its "every symbol class must
exist in app.game.air.swf" risk) for this crash.

**Verification:** ~4 offline AI battles (`A-*.log`; turns up to 39; two battles in one session) — **0 ×
`#1009`**, vs. a reliable crash before. The reroute was the only change since "persists unchanged", so causation
is clean.

**Status notes:**
- Fix-table row #4 → **FIXED**.
- `GuiInitiative.as` overlay stays **inert** (the gui-SWF copy runs). Its `frameleft` guards are
  belt-and-suspenders: only load-bearing if a *residual* deploy-branch `#1009` (the gui-SWF copy's own
  unguarded `frameleft` deref) ever appears — then escalate this one SWF to `allowCodeImport=false` to force
  the app `GuiInitiative` (frameleft-guarded) to win too.
- **CORRECTED (Wave 3, 2026-06-23):** the `#1069 IGuiContext::party/renown not found` loading
  `GreatHallPage`/`MeadHousePage`/`VersusPage` is **not** an unpopulated account context — it is a
  **stale-gui-SWF API mismatch**, and it is **blocking** (it breaks Quick Match and the great-hall/roster
  portraits = finding #1, which fail because the throw aborts page load before rendering). `great_hall.swf` /
  `mead_house.swf` bundle pre-refactor `GuiGreatHall` / `GuiMeadHouse` that call `context.party` /
  `context.renown`; the rebuilt app moved those onto `Legend` (`context.legend.*`) and dropped them from
  `GameGuiContext` / `IGuiContext`, so the stale by-name calls find nothing. The Crash-A reroute does **not**
  apply (no app-side property to resolve to). **Fix (implemented, VERIFIED 2026-06-24 — Quick Match + portraits
  render):** a backward-compat shim re-adds `party` / `renown` to `IGuiContext` + `GameGuiContext` (→
  `legend.*`) and `party` to `MockGuiContext`. Plan: `~/.claude/plans/context-i-get-this-toasty-simon.md`.

Canonical wave plan: `~/.claude/plans/review-bsf-client-misc-plan-fix-issue-12-clever-storm.md`.

## Update (2026-06-23, later still) — Playable milestone reached; remaining waves deferred

**Wave 2 exit criteria met.** A complete offline AI battle was played from **deploy → resolution with 0
uncaught `#1009`** (the scoped reroute was the last fix needed). Waves 1 + 2 of the canonical wave plan are
**done**, and the client branch `fix/ai-battle-init-hang-12` is pushed.

**Finding #1 (unit portraits) — CONFIRMED still broken.** The scoped `battle_initiative.swf` reroute fixed
Crash A (the initiative HUD) but did **not** restore unit portraits; portraits are still missing in a played
battle. Finding #1 is therefore a **real, open issue**, deferred to **Wave 3** — likely a *different* gui SWF
(`battle_self_popup.swf` / `battle_enemy_popup.swf`), to be confirmed with the same decompile-diff decision
gate and a scoped reroute-or-guard.

**Deferred to future cold-start chats** (kickoff prompts live in the canonical wave plan):

- **Wave 3** — portraits (finding #1, confirmed broken).
- **Wave 4** — AI-vs-AI spectator (Chunk 2).

**Deferred (git):** the parent-repo submodule pointer bump (`bc5258e → 163a495`) is intentionally **not**
committed yet — it lands when issue-12 merges to client `master`, to avoid pointing a parent branch at an
unmerged client SHA.

## Update (2026-06-24) — Wave 3: great-hall context shim landed (portraits + Quick Match fixed); Ranked `#1006` deferred

**Root cause (corrected) for finding #1 + a Quick Match crash.** The great hall (`great_hall.swf`) and mead
house / roster (`mead_house.swf`) load their pages as movie clips whose `GuiGreatHall` / `GuiMeadHouse` are
**stale symbol classes**, compiled before party/renown moved off the gui context onto `Legend`. They call
`context.party` / `context.renown` **by name** on the rebuilt app `GameGuiContext`, which dropped both →
`#1069`. That throw fires during page **load**, which is why the great-hall/roster **portraits never rendered**
(finding #1) — it was never a battle-SWF blind spot, so the clever-storm decompile-diff / reroute-or-guard gate
did **not** apply (the portrait classes are by-name → app copy; a reroute changes nothing). The fix is an
app-side compat shim.

**Fix (landed, VERIFIED).** Re-add `party` / `renown` to `IGuiContext` + `GameGuiContext` (delegating to
`legend.party` / `legend.renown`) and `party` to `MockGuiContext`. New overlays: `src/game/gui/IGuiContext.as`,
`src/game/gui/GameGuiContext.as`, `src/game/gui/mock/MockGuiContext.as`. **User-verified 2026-06-24:** Quick
Match no longer throws and great-hall + roster **portraits render**. Fix-table row #8.

**Ranked Match `#1006` — deferred (not shimmable; online-only).** Clicking Ranked throws `TypeError #1006:
value is not a function` in the stale `GuiGreatHallBannerVersus.rankedMatchHandler`. This is a **call-shape
drift**: the stale code *calls as a function* something the refactor made a **property** (`createDialog()`,
`totalPower`, `partyLimitsExceeded` all exist now; `totalPower`/`partyLimitsExceeded` are getters — likely
`context.party.totalPower()` on the now-`int` property). A getter on a shared class can't be made callable
without breaking the app's own property-style callers, so **the shim approach can't fix it**. The plan's
`allowCodeImport=false` reroute fallback is **also out**: in the AIR app sandbox, loading a code-bearing SWF
with `allowCodeImport=false` throws `SecurityError #3226` (the SWF would fail to load entirely). The only real
fix is a **JPEXS patch of `great_hall.swf`** (the gui SWFs are packed, not loose) — heavy, and online-only
payoff (Ranked is server matchmaking, not part of the offline AI feature).

**Decision (2026-06-24):** park Ranked; the next chat does **"investigate first, then decide."**

**Next-chat kickoff prompt:**
> Issue-12 Wave 3 follow-up (Ranked `#1006`): decompile `great_hall.swf` (the gui SWFs are packed — extract it
> the way `battle_initiative.swf` was extracted into `_decompiled/gui/`), read
> `game.gui.pages::GuiGreatHallBannerVersus.rankedMatchHandler` and `GuiGreatHall`, and pin the exact
> call-shape drift behind `TypeError #1006` (suspect `context.party.totalPower()` — `totalPower` is now a
> property). Enumerate every other stale `context.*` call in `great_hall.swf` / `mead_house.swf`, then
> recommend JPEXS-patch vs. park. Context: the `party`/`renown` compat shim (committed) already fixed Quick
> Match + portraits; `allowCodeImport=false` is ruled out (SecurityError #3226 on code-bearing SWFs).

## Update (2026-06-24, later) — Wave 3 follow-up: Mead-House Hire `#1069` shimmed; `#1006` narrowed to one instruction

Follows through on the "investigate first, then decide" kickoff above. The user extracted `great_hall.swf` +
`mead_house.swf` into `_decompiled/gui/{great_hall,mead_house}/`; a read-only `context.*` enumeration of both
trees (the planned "Step 2") is **done**, and both remaining town crashes are pinned at their call sites.

**Mead-House "Hire" `#1069` — FIXED (app-side shim; user-verified: Hire → confirm a hire, no `#1069`).** Stale
`GuiMeadHouse` calls two members the refactor moved onto `Legend`, both as **functions**:
`context.rosterSlotAvailable()` (`GuiMeadHouse.as:296`) → now `legend.rosterSlotAvailable` (a **getter**), and
`context.purchaseRosterUnit(pu,fake,cb)` (`:264`) → renamed `legend.hireRosterUnit(...)`. Fix re-adds both to
`IGuiContext` + `GameGuiContext` as thin delegates to `legend.*` (matching the stale **function** form);
`MockGuiContext` already declared both, so no change there. Fix-table row #9; same by-name mechanism as the
party/renown shim (row #8).

**Scope = Hire only (2 members), by design.** The full enumeration of **both** extracted trees shows these are the
*only* missing-member calls. The sibling roster ops are **not** in these SWFs: `.promote(` / `.rename(` have
**zero** call-sites; `purchaseStat`/`purchaseStats`/`purchaseVariation`/`setStatsToMinimum` hits are the SWFs'
own **bundled old context-class copies**, not page calls; `getKillsRequiredToPromote` is called on
`context.statCosts` (present), not the context. They live in **other** screens (proving grounds etc.) and are
**deferred** to a future wave — extract those SWFs, enumerate, shim only verified call-sites (all targets already
exist on `Legend.as:121–151`; `purchaseVariation` also helps **#119**).

**Ranked `#1006` — narrowed to a single-instruction patch (still author-don't-apply = Wave 2).** Confirmed at
`GuiGreatHallBannerVersus.as:80` → `context.party.totalPower()` (a getter called as a function). **Correction to
the earlier note:** `partyLimitsExceeded` is read as a **property** already (`GuiGreatHall.as:190`, no parens) — it
matches the new getter and does **not** crash, so the JPEXS patch is just the one `callproperty …::totalPower,0`
→ `getproperty …::totalPower` swap. Not shimmable (a getter can't be made callable app-side).

**Two-mechanism rule (validated):** missing member dropped from the context → **app-side shim** (delegate to its
new `legend.*` home, *matching the stale call form*); member that became a getter but is called as a function →
**JPEXS SWF patch** (only fix). Cleaner signature oracle than `MockGuiContext`: each stale SWF bundles its own old
`game/gui/IGuiContext.as` (e.g. `_decompiled/gui/mead_house/scripts/game/gui/IGuiContext.as:138,140`).

Reviewed/split plan: `~/.claude/plans/review-c-users-rleyb-claude-plans-swf-pa-transient-gadget.md` (Wave 1 = this
shim; Wave 2 = the `#1006` patch authoring). Committed on `fix/ai-battle-init-hang-12`.

## Playbook for the next `#1009` (so any session can continue mechanically)

1. Reproduce, read the stack from the AIR popup **and** `_build/adl-run.log` (uncaught Timer/event errors land
   there, not always the app file log). The app file log flushes only on client close.
2. Find the **throwing** frame and the **originating** frame. So far the throwing class is always in
   `app.game.air.swf` (decompiled under `_decompiled/scripts/...`), even when called from the gui-SWF
   `GuiInitiative`. That class is patchable the normal way.
3. Add a **minimal, behavior-preserving** null guard (skip the optional work; never change real logic). Match
   the existing decompiled style; keep the overlay byte-identical to `_decompiled` except the guard.
4. Overlay path mirrors the package: `src/<pkg path>.as` → `apply-patches.ps1` copies to
   `_decompiled/scripts/<pkg path>.as`. Verify with `diff _decompiled/scripts/<f> src/<f>` (only your change)
   and an `awk` brace count.
5. Rebuild → copy SWF → `run-adl.ps1` → repro → paste newest log. Repeat.
6. Escalate to **Phase 3** only if a crash is genuinely _inside_ the gui-SWF `GuiInitiative` with no
   `app.game.air.swf` choke point to guard.

## Verify (run locally; paste back the newest log)

1. `./scripts/apply-patches.ps1` → `./scripts/build.ps1` (compile-only) → copy
   `_build\app.game.air.swf` → `…\The Banner Saga Factions\win32\app.game.air.swf` → `./scripts/run-adl.ps1`.
2. Trigger **Ctrl+Shift+A** (player-vs-AI). Close the client (the log flushes only on close); read the
   newest `…\Local Store\logs\A-*.log.txt`.
3. **Pass:** no `#1009 … GuiInitiative/setInitiativeEntities` during HUD load; FSM progresses past
   `BattleStateDeploy` (a `BattleStateStart` / `turnNumber=` line appears); deployment is interactive and a
   turn can be taken.
4. If a new gui-SWF-internal `#1009` appears, capture it and proceed to Phase 3.
5. Then build/verify the **spectator** path (Chunk 2 — side 0 = AI + HUD-control suppression).

## Build / run notes (unchanged, still true)

- `apply-patches.ps1` (src→_decompiled) → `build.ps1` (compiles `_decompiled`→`_build\app.game.air.swf`) →
  **copy** to `…\win32\app.game.air.swf` → `run-adl.ps1`.
- adl is the only runtime that can run the SDK-51 build; the captive 2013 runtime can't.
- The AIR file logger buffers — **the log only flushes when the client is closed**; the newest `A-*.log.txt`
  after closing is the run you want.
