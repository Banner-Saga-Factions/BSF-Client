# Reference codebases (client side)

## Co-Authored-By: Claude <noreply@anthropic.com>

Three read-only mirrors of the original Banner Saga Factions client live alongside this repo at `%USERPROFILE%\Code\bsf-refs\`. None of them are built or shipped — they exist so contributors can read original Stoic source and the decompiled shipped SWF without checking out giant trees into `bsf-client/`.

This is the client-side analogue of the parent repo's [`REFERENCE.md`](../../REFERENCE.md), which covers the server side.

> **Do not vendor, submodule, copy, or otherwise pull these directories into `bsf-client/` or `BSF/`.** The patch-only repo model depends on `_decompiled/` being a _generated_ gitignored tree, not a checked-in mirror.

## The four AS3 trees — editable vs reference

This is the part that trips people up: **two of these trees are JPEXS decompiles of the same SWF**, so it looks like you have a choice of where to make changes. You don't. There is exactly **one tree you edit** and **three read-only reference mirrors**. You never edit a reference mirror — you read them to decide what to patch in `src/`.

| Tree                              | Role                                                                                                | Tracked?               | You…                       |
| --------------------------------- | -------------------------------------------------------------------------------------------------- | ---------------------- | -------------------------- |
| `bsf-client/src/`                 | **The only thing you edit.** Patch files overlaid on `_decompiled/` at build time.                 | committed              | **edit**                   |
| `bsf-client/_decompiled/`         | Working decompile you build against. Generated from your own SWF by `scripts/decompile.ps1`.        | gitignored (generated) | build against, never edit  |
| `bsf-refs\client-2013-as3\`       | Readable 2013 Stoic source — the **default** thing to read.                                         | read-only reference    | read                       |
| `bsf-refs\client-decompiled-as3\` | Checked-in snapshot of the SWF decompile — read when 2013 is missing or stale.                      | read-only reference    | read                       |
| `bsf-refs\client-swf-and-ane\`    | Raw `app.game.air.swf` + ANE inputs (binary).                                                       | read-only reference    | rarely touch               |

**`_decompiled/` vs `client-decompiled-as3/` — same content, different jobs.** Both are JPEXS decompiles of the same shipped SWF, so their files are near-identical. They are _not_ redundant:

- `bsf-client/_decompiled/` is **generated locally and gitignored** — the working copy the compiler overlays your `src/` patches onto. Every contributor regenerates it from their own SWF; it is a _build input_, never read as a reference and never committed.
- `bsf-refs\client-decompiled-as3\` is a **stable, checked-in reference snapshot** you _read_ while deciding what to patch — outside the build, shared across contributors so line citations stay stable.

Keeping these two separate is exactly what makes the patch-only model work (see [`architecture.md`](./architecture.md) → "The patch-only repo model"). The rest of this doc covers the **three reference mirrors** (the bottom three rows above) — when to read each.

## The three mirrors

| Path                              | What it is                                                                                                                                                  | Files       | When to consult                                                                                                                                                                                                                       |
| --------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `bsf-refs\client-2013-as3\`       | Original 2013-era ActionScript source Stoic shared. Multi-module layout under `game/code/client/lib.engine.core/src/` and `game/code/client/lib.game/src/`. | 385 `.as`   | **Default reference.** 97 % of overlapping classes are signature-equivalent to the shipped SWF and the original code is dramatically more readable than the decompile (real parameter names, original comments, original whitespace). |
| `bsf-refs\client-decompiled-as3\` | JPEXS decompile of the shipped SWF v1.10.51. Flat layout: `engine/`, `game/`, `tbs/`, `lib/`, plus root-level `GameMainAir.as` and `AneFixer.as`.           | 1,113 `.as` | Use for code added after 2013 (~732 files don't exist in the 2013 source), or to verify any of the 12 files in the stale-list below.                                                                                                  |
| `bsf-refs\client-swf-and-ane\`    | Raw `app.game.air.swf` plus extracted ANE scripts (decompile inputs).                                                                                       | binary      | Rarely read directly. Needed only to regenerate the decompile if JPEXS or the SWF changes.                                                                                                                                            |

## Prefer 2013 source over decompile — _except_ for 12 files

A pass-2 signature comparison (2026-05-16) found 369 of 381 overlapping files are byte-equivalent in API surface. The 12 exceptions are files Stoic actually modified after 2013, where the **2013 source is stale** and the decompile is authoritative:

- **`engine/battle/fsm/`** (4) — `BattleFsmConfig`, `BattleTurnOrder`, `BattleStateDeploy`, `BattleStateInit`
- **`engine/battle/board/`** (3) — `BattleBoard`, `BattleBoardView`, `EntityFlyText`
- **`engine/battle/ability/effect/op/model/Op.as`** (1)
- **`engine/entity/def/`** (2) — `EntityDef`, `EntityClassDefList`
- **`game/cfg/`** (2) — `GameConfig`, `AccountInfoDefVars`

Pattern: post-2013 changes were exclusively gameplay iteration — battle internals, entity defs, game config. Core utilities, the protocol layer (`tbs/srv/...`), JSON serialization, stats, and session-state code are all unchanged. Comparison artifacts: `%USERPROFILE%\Code\bsf-refs-compare\`.

This list is duplicated in root [`CLAUDE.md`](../../CLAUDE.md) → "Reference Codebases" so AI agents picking either entry point see the same caveat.

## Decision tree — "I need to read class X, which mirror?"

```
Does X live under engine/battle/fsm/, engine/battle/board/, engine/entity/def/, game/cfg/, or is it Op.as?
  └── YES → read client-decompiled-as3/  (the 12-stale exception)
  └── NO  → does X exist in client-2013-as3/ (with the same package path under lib.engine.core/src/ or lib.game/src/)?
             ├── YES → read client-2013-as3/  (cleaner, named params, original comments)
             └── NO  → read client-decompiled-as3/  (X is post-2013, decompile is the only source)
```

In practice: when in doubt, open both — they sit side-by-side and a quick diff confirms whether the 2013 source is authoritative or stale for that file.

## Verifying provenance — "did Stoic do it, or did we?"

When something looks wrong — a context is missing a member, a method does nothing — the first question is always: **is this pre-existing in Stoic's shipped game, or did our decompile/recompile introduce it?** The answer changes everything (a pre-existing skew is a bounded thing to shim; a decompile artifact means the rebuild is lossy). The two read-only mirrors are the oracles, because **they predate and are untouched by our patching.**

**Integrity check first.** Confirm `client-decompiled-as3\` really is the pristine original: it must contain **none of our new files** (`ModBridge.as`, `AiBattleLoadState.as`, …). (`DiscordSteamworks.as` is *planned*, not yet created — it is not a reliable marker.) If those are absent, the mirror is the untouched shipped decompile and is safe to trust as the "what shipped" oracle.

**The recipe:**

1. **What shipped?** Look up the member/behavior in `client-decompiled-as3\` (faithful decompile of the shipped SWF).
2. **What did Stoic write?** Cross-check `client-2013-as3\` (Stoic's readable source). Two independent Stoic artifacts agreeing is strong proof.
3. **Did we change it?** Check `bsf-client/src/` for an overlay of that class. No overlay ⇒ we didn't touch it.
4. **Conclude.** Present in both mirrors + no `src/` overlay ⇒ **Stoic's, pre-existing.** Differs only in our `src/` overlay ⇒ **ours.**

**Worked example (BSF-Client #12).** "Did we move `party`/`renown` off `GameGuiContext` onto `Legend`?" — No, Stoic did: `Legend.party` (`engine/entity/def/Legend.as:85`) and `Legend.renown` (`:137`, real `_renown` field + `"Legend.RENOWN"` event) exist in **both** `client-2013-as3\` and `client-decompiled-as3\`; the shipped `GameGuiContext` has only `get legend()`; and there is **no** `src/.../Legend.as` overlay. Our `src/game/gui/GameGuiContext.as` shim does the _opposite_ (re-adds `party`/`renown` onto the context, delegating to `legend.*`).

### The silent-decompile-loss trap

The dangerous decompile failure is not a compile error — it is a method JPEXS lifts as an **empty `{}` body**: it compiles, runs as a silent no-op, and a compile-diff audit will **never** flag it. To tell a genuine stub from a lift failure, **check `client-2013-as3\`**: if Stoic's readable source _also_ has an empty body, it is a genuine base-class stub (often a server-txn method whose real work lives in a subclass), not a decompile loss.

**Worked example.** `Legend`'s roster ops (`hireRosterUnit`, `purchaseStat`, `rename`, `promote`, `purchaseVariation`) are empty `{}` in `client-decompiled-as3\` — alarming until you confirm they are **also** empty in `client-2013-as3\Legend.as`. Genuine stubs, faithfully decompiled. (Caveat: which `Legend` subclass is live at runtime then determines whether a call actually no-ops — verify the subclass before asserting behavior.)

## Path conventions in this docs suite

Throughout `bsf-client/docs/` we cite files using **`bsf-refs\<mirror>\<path>`** (no `%USERPROFILE%\Code\` prefix) for compactness. The first reference per doc spells out the full `%USERPROFILE%\Code\bsf-refs\...` path; subsequent references abbreviate.

In Markdown line citations we use the convention **`<File>.as:<line>`** (e.g. `BattleBoard.as:456`) — same convention used in `bsf-server/docs/protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)) and the Findings doc.

**A line number is useless unless you say which copy it belongs to.** There are several copies of this client, and the same function sits at a different line in each. The re-send test in `HttpAction` is at line **359** in this repository (both `src/` and the generated `_decompiled/`, which hold the same file once `apply-patches.ps1` has run), **346** in `bsf-refs\client-decompiled-as3\`, and **380** in `bsf-refs\client-2013-as3\`. A bare number with no copy named sends the reader to the wrong place. So:

- **Say which copy**, in the doc's opening note. [`asset-loading.md`](./asset-loading.md) and [`ui-system.md`](./ui-system.md) already do; other docs should follow.
- **Prefer naming the function** to citing a line whenever the name is unambiguous. A name never goes stale.
- **Treat `_decompiled/` numbers as "look near here."** That tree is regenerated by script, so its numbering moves when the decompiler version changes *or* when our own patches grow — the 13-line gap in the example above is our ModBridge patch, not a decompiler difference.

## Pinned provenance & highest-value client paths

This is the client-side counterpart to the server block in [`REFERENCE.md`](../../REFERENCE.md)
("Pinned reference SHA" + "Top 7 highest-value paths"). This docs suite is written against these anchors.

**Provenance anchor — there is no commit SHA to pin.** Unlike the server's Java reference (a checkout
with a recorded upstream commit), these client mirrors are **plain directories, not git repositories** —
there is nothing to `rev-parse`. The stable anchor is instead:

- **Shipped SWF version `v1.10.51`** — what `client-decompiled-as3\` (and a fresh local `_decompiled/`)
  decompile from. A decompile of a binary has no upstream repo, so the version string *is* its provenance.
- **File-count fingerprints** — `client-decompiled-as3\` = **1,113** `.as`; `client-2013-as3\` = **385**
  `.as`; a fresh local `_decompiled/scripts` = **~1,272** `.as`. If any of these drift, the reference has
  changed and this doc + the 12-stale-file list should be re-verified.

If a newer SWF is ever adopted, bump the version here and re-run the pass-2 signature comparison.

**Top highest-value client paths.** Ordered by how often the docs and patches touch them. Paths under
`_decompiled/scripts/` unless noted; `†` = on the 12-stale-file list, so **read `_decompiled/`, not the
2013 mirror**.

1. `game/session/GameFsm.as` — the top-level state machine; the spine of [`game-flow.md`](./game-flow.md).
2. `game/session/states/PreAuthState.as` — the crossplay auth patch point (`:31–33`).
3. `engine/battle/fsm/BattleFsm.as` — the battle state machine ([`battle-engine.md`](./battle-engine.md)). (Its `*Config`/`*Init`/`*Deploy`/`*TurnOrder` siblings **are** on the 12-stale list — read `_decompiled/` for those.)
4. `engine/battle/board/model/BattleBoard.as` † — entity-ID construction (`:456`) + per-battle RNG seed.
5. `engine/battle/fsm/state/BattleStateNextTurn.as` — the per-turn DJB sync hash (`:130`).
6. `game/cfg/GameConfig.as` † — hosts, options, config root (`setupHosts()` at `:1222`).
7. `engine/entity/def/EntityDef.as` † — per-unit definitions (the `Def` pattern; planned `data-model.md`).
8. `engine/resource/ResourceManager.as` — the asset loader (planned `asset-loading.md`).
9. `engine/gui/core/GuiApplication.as` — the app + render-loop host in the boot spine.
10. `engine/core/http/HttpCommunicator.as` / `engine/session/TxnGet.as` — the long-poll loop + its GET.
11. `src/engine/mod/ModBridge.as` — the fork's mod bus (planned `mod-bridge.md`).

The full `src/` patch surface is [`patch-inventory.md`](./patch-inventory.md). A one-line "Client-side"
pointer to this section will be added to parent [`REFERENCE.md`](../../REFERENCE.md) as a separate
parent-repo follow-up (it lives outside this submodule).

## Related references

- Parent repo [`REFERENCE.md`](../../REFERENCE.md) — pinned `server-2013-java` SHA, top-7 highest-value server paths.
- Root [`CLAUDE.md`](../../CLAUDE.md) — reference-codebase table for all four mirrors (this doc covers the three client-side ones).
- `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — the deepest existing client-side analysis (6 items: server URL, Steam auth, login response, entity naming, long-poll, mobile branches). Cited heavily in [`wire-protocol.md`](./wire-protocol.md) and [`battle-engine.md`](./battle-engine.md).
