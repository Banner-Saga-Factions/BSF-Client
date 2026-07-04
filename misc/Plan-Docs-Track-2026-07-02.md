# Client Docs Track — Execution Plan (2026-07-02)

## Co-Authored-By: Claude <noreply@anthropic.com>

**Source:** the approved `bsf-client` documentation-track planning chat (2026-07-02). This file is the
**in-repo anchor** for the whole track — each tier (P1 → P2 → P3) is run in its own fresh chat and
resumes from *here*, not from a transcript. It mirrors the proven server track,
`bsf-server/misc/Plan-Docs-Track-2026-06-19.md` ([local](../../bsf-server/misc/Plan-Docs-Track-2026-06-19.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Docs-Track-2026-06-19.md)).

## Context

The user's framing was "most of how the client works is a mystery." Exploration showed the truth is
narrower and reframes the effort: the client's **plumbing** is already well documented (a 7-file
`docs/` suite covering the patch/SWF/runtime model, build mechanics, the wire protocol, the
multiplayer battle FSM, a package map, and the reference-mirror discipline). What is a mystery is the
**original game's application layer** — the ~1,272-class app that Stoic wrote and we did not touch —
plus a body of reusable knowledge currently trapped inside `misc/Plan-*.md` instead of distilled into
`docs/`. Several load-bearing facts in the existing docs are also **stale** (see the accuracy-fix
table in P1). This track turns that into ~8 narrative docs plus targeted accuracy fixes and
meta-scaffolding, delivered in **3 review-gated tiers, one PR each**, so a newcomer — human or a
future Claude session — can build a working mental model of the whole client without re-deriving it
from decompiled source.

## Decisions (from the planning interview)

- **Scope = both.** Document each original Stoic subsystem as the mental-model backbone, and give each
  pillar doc a "Where our fork touches this" callout that cross-links one durable **patch inventory**.
- **Depth = architecture narrative** — per subsystem: responsibility, key classes, data flow, entry
  points, gotchas — *not* a per-class API reference. Kept sustainable against decompile churn by
  citing (not restating) and writing against `_decompiled/scripts` for the 12 stale files.
- **Rollout = tiered, one PR per tier, pause for review between tiers.**

## Conventions (apply to every doc — reuse, don't reinvent)

- **Cite, don't restate.** New docs cross-link the existing suite; durable concepts live in `docs/`,
  issue-specifics stay in `misc/Plan-*.md` and *link* to the concept (`bsf-client/CLAUDE.md` →
  "Documentation conventions").
- **Dual-link cross-repo form** into `bsf-server`:
  `` `<path>` ([local](rel) | [GitHub](…/BSF-Custom-Server/<blob|tree>/main/<path>)) `` (root `CLAUDE.md`).
  Server default branch = **`main`**; client default branch = **`master`**.
- **`%USERPROFILE%`-style paths** in committed docs — never hardcoded `C:\Users\...`.
- **`[Inference]` / `[Assumption]` labels** for anything read off decompiled code.
- **Write against `_decompiled/scripts`**, not the 2013 mirror, for the 12 stale files.
- **Plain language; gloss the jargon** (retained-mode, lockstep, ANE, symbol linkage, long-poll).
- **Per-tier approval gate:** before each tier's writes, present every planned file with
  What / Why / Tradeoff and get an explicit **y**. Write only after `y`. Each tier is its own cycle.

## Repo & branch logistics

`bsf-client` is a **git submodule** (repo `Banner-Saga-Factions/BSF-Client`, default branch **`master`**).
Doc work happens inside the submodule on branches `docs/p{1,2,3}-client-doc-gaps` **cut from
`origin/master`** (local `master` is often stale — verify before branching), each opened as a PR
against `BSF-Client:master`. After each client PR merges, two parent-repo follow-ups land separately:
the **submodule-pointer bump** and the one-line `REFERENCE.md` "Client-side" pointer.

## Verified baseline (confirmed on disk 2026-07-03)

| Fact | Value | Use |
|---|---|---|
| `bsf-client/_decompiled/scripts` (live generated tree) | **1,272** `.as` | "how many files does the client have" |
| `bsf-client/src/` overlays | **33** `.as` + 3 `.cff` fonts (+ `META-INF/AIR/application.xml`) | the real patch surface |
| `DiscordSteamworks.as` in `src/` **and** `_decompiled/` | **absent** | *referenced but planned / not-yet-created* |
| `%USERPROFILE%\Code\bsf-refs\client-decompiled-as3` mirror | **1,113** `.as` | the checked-in reference *snapshot* count (≠ 1,272 live) |
| `%USERPROFILE%\Code\bsf-refs\client-2013-as3` mirror | **385** `.as` | default-reference count |
| `game/session/states/` | **52** files = ~48 State subclasses + 4 helpers | the GameFsm state count (docs previously said "~37") |
| `game/session/actions/` | **24** files (22 `*Txn` extend `HttpJsonAction`) | the action count |
| `bsf-refs` mirrors are git repos? | **No** — plain directories | so provenance anchors on SWF **v1.10.51** + file counts, not a commit SHA |

## Progress

**Status (2026-07-03): P1 authored on `docs/p1-client-doc-gaps` (cut from `origin/master` `b6e357a`); pending review + PR.** P2/P3 not started.

- **PR 1 (P1) — the on-ramp, the game-flow spine, and scaffolding.** New `docs/client-overview.md`,
  `docs/game-flow.md`, `docs/patch-inventory.md`, `docs/doc-gaps.md`, and this tracker; accuracy fixes
  to `docs/architecture.md` + `docs/subsystem-index.md` + `docs/reference-codebases.md` (client
  reference block) + `docs/README.md` index + submodule `CLAUDE.md`. Retires the stale "only
  `PreAuthState` in `src/`" claim, the phantom `OnlineState`/`LoginState`, the "`DiscordSteamworks`
  exists" implication, and the 1,113-vs-1,272 file-count confusion.
- **PR 2 (P2) — the visible client.** New `docs/ui-system.md` + `docs/asset-loading.md`; extend
  `docs/build-workflow.md` ("Audio & the FMOD ANE", "AIR SDK 33-vs-51 wall") and `docs/subsystem-index.md`
  (real `game/gui`/`game/view` rows). Also folds in the deferred `build-workflow.md` file-count fix.
- **PR 3 (P3) — data model, offline AI, mod tooling.** New `docs/data-model.md` + `docs/offline-ai.md`
  + `docs/mod-bridge.md`; extend `docs/battle-engine.md` (offline-AI pointer) and `docs/subsystem-index.md`.
  Empties `docs/doc-gaps.md`.

---

## PR 1 — P1 tier · `docs/p1-client-doc-gaps`

| Deliverable | Type | Closes |
|---|---|---|
| `docs/client-overview.md` | new — "how the client works in one read" pillar map | on-ramp gap |
| `docs/game-flow.md` | new — `GameFsm` spine + ~48 states + 24 actions + the generic `Fsm`/`State` base | game-flow spine gap |
| `docs/patch-inventory.md` | new — the real `src/` inventory (33 overlays, what/why), `DiscordSteamworks` = planned | stale `src/` claim |
| `docs/doc-gaps.md` | new — remaining gaps as a tracked, closeable list | tracking |
| `misc/Plan-Docs-Track-2026-07-02.md` | new — this tracker | tracking |
| `docs/architecture.md` | edit — `src/` inventory, 1,272-vs-1,113 counts, `DiscordSteamworks` planned | doc drift |
| `docs/subsystem-index.md` | edit — drop "only file in `src/`", fix phantom states, `DiscordSteamworks` planned | doc drift |
| `docs/reference-codebases.md` | edit — client reference block (SWF v1.10.51 + top paths) | reference provenance |
| `docs/README.md` | edit — doc-map + reading-order additions | discoverability |
| `CLAUDE.md` (submodule) | edit — `~1,272` count, `DiscordSteamworks` planned, `doc-gaps.md` pointer | doc drift |

**Accuracy fixes (P1):**

| Fix | Wrong now | Correction |
|---|---|---|
| `src/` inventory | `architecture.md`/`subsystem-index.md` call `PreAuthState` the only file in `src/` | Real: **33 `.as` overlays** (+ 3 `.cff` fonts); point to `patch-inventory.md`. |
| `DiscordSteamworks` | referenced as if present | **Not in `src/` or `_decompiled/`** — mark *planned/not-yet-created* uniformly. |
| File count | `CLAUDE.md` "~1,267"; live-tree refs say "1,113" | **1,272** = live `_decompiled`; **1,113** = checked-in mirror snapshot (distinct meanings). |
| Phantom states | `subsystem-index.md` names `OnlineState`/`LoginState` (absent); keeps `OfflineState` (real) | Point at `game-flow.md`'s real ~48-state map. |
| `## Co-Authored-By:` signature | every `docs/*.md` line 3 | **KEEP — do not remove.** It is the intentional authorship mark; every `docs/*.md` **and** this tracker carries it uniformly. |

**Deferrals (called out, not dropped):** `build-workflow.md`'s "~1,113 .as files" count → **P2** (that
tier already edits the file); `scripts/run-adl.ps1`'s `DiscordSteamworks` reference → code cleanup,
logged in `doc-gaps.md`; parent `REFERENCE.md` "Client-side" pointer + submodule bump → parent-repo
follow-ups after merge.

**Tier-1 verify:** every named class/path spot-checked against `_decompiled/scripts`; line citations
read-confirmed; `patch-inventory.md` "why" confirmed against each file's header/comment; file-count
reconciliation (1,272 live / 33 `src/` / 1,113 mirror / 385 2013); Markdown + cross-repo link check.
Trim the three P1 entries from `doc-gaps.md`. → **pause for review.**

---

## PR 2 — P2 tier · `docs/p2-client-doc-gaps`

| Deliverable | Type |
|---|---|
| `docs/ui-system.md` | new — retained-mode widget toolkit + page/screen framework + battle HUD |
| `docs/asset-loading.md` | new — `ResourceManager` loader pipeline (consumed by UI **and** battle/anim/sound) |
| `docs/build-workflow.md` | extend — "Audio & the FMOD ANE", "AIR SDK 33-vs-51 wall"; fix the deferred file-count |
| `docs/subsystem-index.md` | extend — real `game/gui`/`game/view` rows (replace the stub) |

**Tier-2 verify:** UI class names spot-checked; asset-loader class graph confirmed; the FMOD/`NullSoundDriver`
fallback traced to the local-2-client hang; link check. Trim P2 entries from `doc-gaps.md`. → **pause.**

---

## PR 3 — P3 tier · `docs/p3-client-doc-gaps`

| Deliverable | Type |
|---|---|
| `docs/data-model.md` | new — entities + the `Def`/`Vars`/`Wrangler` pattern (documented once) |
| `docs/offline-ai.md` | new — `aimodule/` + the AI battle path (same lockstep FSM + DJB hash as multiplayer) |
| `docs/mod-bridge.md` | new — the NativeProcess newline-delimited-JSON bus to the mod host |
| `docs/battle-engine.md` | extend — short "Offline AI path" pointer to `offline-ai.md` |
| `docs/subsystem-index.md` | extend — `aimodule/`, `engine/mod/`, resource-loader rows |

**Tier-3 verify:** entity/`Def` triad confirmed; the offline battle path traced end-to-end; mod-bridge
wire protocol matched to `ModBridge.as`; link check. `doc-gaps.md` should be **empty** when P3 merges. → final review.

## End-to-end verification (every tier)

- **Per-claim:** named class/path spot-checked via Glob/Grep against `_decompiled/scripts` (use
  `_decompiled`, not the 2013 mirror, for the 12 stale files); line citations read-confirmed; inferences labeled.
- **Docs-only, so no builds.** Heavy commands (`decompile.ps1`, `build.ps1`, `yarn`) are the user's to
  run locally and paste back — none should be required for a docs tier.
- **Cross-repo link check:** every `[GitHub]` URL uses the right branch (`BSF-Custom-Server`→`main`,
  `BSF-Client`→`master`), `/blob/` for files and `/tree/` for dirs; drop any that would 404.
- **`doc-gaps.md` hygiene:** after each tier, delete the closed entries (don't strike-through).
