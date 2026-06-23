# Plan — Fix BSF-Client #12, finding #2: offline AI battle loads but is not playable

> **Status (2026-06-22):** root cause **re-diagnosed from the real failure log** and the original theory
> (null `frameLeft` in the deploy branch) was **wrong**. The proven crash is fixable in `app.game.air.swf`
> via the normal patch model — **no gui-SWF editing needed**. Phase 1 fix is implemented in `src/`
> (`BattleHudPageLoadHelper`), awaiting a local build + re-test. Title keeps "init-hang" for link stability,
> but both that label and the earlier `frameLeft` diagnosis were wrong.
>
> Canonical execution plan: `~/.claude/plans/review-c-users-rleyb-code-bsf-bsf-client-splendid-lighthouse.md`.

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
(The repo-root `A-*.log.txt` and the other `…\Local Store\logs\A-*` files are from unrelated tests.)

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
- `AiModuleBase` constructor (`:43`) — `atkStr.id`/`atkArm.id` on the **caster** (the *next* crash, the
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
   the *deploy branch* with **real** entities (so it passes the Phase-1 null guard). The old gui-SWF
   `GuiInitiative` passes a **null child** to `GuiUtil.updateDisplayList`, which only guarded the *parent*.
   **Fixed:** `src/game/gui/GuiUtil.as` — guard null `param1` in `updateDisplayList` + `updateDisplayListAtIndex`
   (behavior-preserving: null child = nothing to add/remove).
2. **Ability-info crash** — selecting the Siege Archer ability: `InfoBarHelper.showAbilityInfo #1009`. It
   walks `guihud.initiative.infobar.setVisible(...)` / `turn.ability.def.description` unguarded. **Fixed:**
   `src/game/gui/InfoBarHelper.as` — walk the chain null-safely; skip showing the info bar if a link is null.

## Fixes applied so far (running list — all `app.game.air.swf`, normal patch model)

| # | Symptom | Root cause | Overlay |
|---|---------|-----------|---------|
| 1 | HUD #1009 at battle load, stuck in deploy | `checkInitiativeEntities` calls `setInitiativeEntities(null)` → old gui-SWF empty branch | `src/game/gui/page/BattleHudPageLoadHelper.as` |
| 2 | AI #1009, enemy never acts | `getFirstAbilityByTag(ATTACK_STR).def` on a str-less **enemy** (Shieldbanger) | `src/engine/battle/fsm/aimodule/AiPlan.as` |
| 3 | (latent) AI #1009 when AI's own str-less unit acts | `atkStr.id`/`atkArm.id` on null in ctor | `src/engine/battle/fsm/aimodule/AiModuleBase.as` |
| 4 | Deploy HUD #1009 (real entities) | null **child** into `GuiUtil.updateDisplayList` (gui-SWF deploy branch) | `src/game/gui/GuiUtil.as` |
| 5 | #1009 selecting an ability | unguarded `infobar` chain / `def.description` | `src/game/gui/InfoBarHelper.as` |

`GuiInitiative.as` overlay remains **inert/parked** (gui-SWF copy runs). Phase 3 (DisplayResourceLoader →
`currentDomain`) is still **not needed** — every crash so far was reachable/guardable from `app.game.air.swf`.

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
6. Escalate to **Phase 3** only if a crash is genuinely *inside* the gui-SWF `GuiInitiative` with no
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
