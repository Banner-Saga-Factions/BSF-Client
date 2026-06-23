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

## Path conventions in this docs suite

Throughout `bsf-client/docs/` we cite files using **`bsf-refs\<mirror>\<path>`** (no `%USERPROFILE%\Code\` prefix) for compactness. The first reference per doc spells out the full `%USERPROFILE%\Code\bsf-refs\...` path; subsequent references abbreviate.

In Markdown line citations we use the convention **`<File>.as:<line>`** (e.g. `BattleBoard.as:456`) — same convention used in `bsf-server/docs/protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)) and the Findings doc.

## Related references

- Parent repo [`REFERENCE.md`](../../REFERENCE.md) — pinned `server-2013-java` SHA, top-7 highest-value server paths.
- Root [`CLAUDE.md`](../../CLAUDE.md) — reference-codebase table for all four mirrors (this doc covers the three client-side ones).
- `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — the deepest existing client-side analysis (6 items: server URL, Steam auth, login response, entity naming, long-poll, mobile branches). Cited heavily in [`wire-protocol.md`](./wire-protocol.md) and [`battle-engine.md`](./battle-engine.md).
