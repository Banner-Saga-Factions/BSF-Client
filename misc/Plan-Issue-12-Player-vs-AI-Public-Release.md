# Review & Verdict — `fix/ai-battle-init-hang-12` (player-vs-AI) + the decompile/recompile question

> Companion to [`Plan-Fix-Issue-12-ai-battle-init-hang.md`](./Plan-Fix-Issue-12-ai-battle-init-hang.md).
> This is the public-release critique + decompile-vs-recompile verdict + the wave breakdown that carries
> the feature from "playable" to "shippable."

## Context

This reviews the BSF-Client branch `fix/ai-battle-init-hang-12` and answers a core worry: **is
decompile/recompile of the client `.swf` the right path, or will we never find all the issues it
introduces?** It also tests a specific hypothesis: that the AIR SDK jump (HARMAN **33.1 → 51**) *caused*
the gui-SWF town crashes. Decisions that framed the review: target = **public, player-facing**;
deliverable = **verdict + tradeoffs**; scope = **everything** (battle + town + spectator + Ranked).

A 6-dimension review (with adversarial verification) was run across two workflow sessions. All six
dimensions completed; the **crux was independently confirmed by four skeptic agents**. Confidence is
flagged per finding: **[verified]** = adversarially confirmed or directly re-read; **[single-pass]** = one
reviewer, not yet cross-checked.

---

## TL;DR

- **The SDK hypothesis: NO — the AIR 33→51 jump does *not* cause the town crashes.** [verified ×4]
  The broken UI class (`GuiGreatHall`) is **symbol-linked** inside `great_hall.swf` and always runs from
  that SWF regardless of AIR version or `ApplicationDomain`. The SDK jump *is*, separately, the cause of
  the runtime/packaging wall (§5).
- **The town crashes are a *bounded* API-drift problem, NOT silent decompiler damage.** [verified] The
  shipped `GameGuiContext` genuinely never had `party`/`renown` (Stoic moved them to `Legend`); the
  resource gui SWFs carry an *older generation* of the UI code that still calls `context.party`. JPEXS
  did **not** drop members.
- **This substantially answers the worry.** The recompile itself is **high-fidelity** (~12 hand-edited
  lines total across the whole patch set; everything else byte-identical to the decompile). There is
  **no unbounded "silent breakage across 1,267 files" tail.** The real risk surface is finite and
  enumerable.
- **Verdict: KEEP decompile/recompile** (it's high-fidelity *and* the only way to add app code), in a
  **hybrid** with JPEXS bytecode-patches for the few unshimmable gui-SWF cases. Don't switch approaches.
- **Public release is still blocked** by concrete, findable things: a player-facing crash (§3.1), a
  credential leak (§3.2), launch-safety gaps incl. an unimplemented spectator mode documented as working
  (§3.3), the packaging/runtime wall + no audio (§5), and no regression/repro guard (§5).

---

## 1. Architecture in plain English

The game = a main app SWF (`app.game.air.swf`, ~1,267 classes) **plus** resource "gui" SWFs loaded at
runtime (`battle_initiative.swf`, `great_hall.swf`, `mead_house.swf`, …) that carry **art + some compiled
UI "symbol classes."** We decompile/recompile **only the app SWF** (`src/` → `_decompiled/` → AIR SDK 51);
the gui SWFs ship **unchanged** (original, built with AIR SDK 33.1). Two ways a class reference resolves
at runtime, and this is the whole story of the town crashes:
- **Symbol linkage** (a movie clip is tagged with a class) → **always** the copy bundled *in that gui
  SWF*. Version- and domain-independent. **Cannot** be patched from the app.
- **By-name** (`new Foo()` / `context.party`) → resolves through the application domain, so it can hit the
  patched app copy.

> **Canonical references** (the reusable version of §1–§2 now lives in the docs suite — read these for the
> general mechanism, this plan for the issue-12-specific findings):
> - Two-tier SWF model + symbol-linkage vs by-name + the three repair mechanisms →
>   [`../docs/architecture.md`](../docs/architecture.md) → "Resource SWFs and runtime class resolution".
> - The "Stoic vs us" provenance recipe + the silent-decompile-loss trap →
>   [`../docs/reference-codebases.md`](../docs/reference-codebases.md) → "Verifying provenance".
>
> **Terms used below:** *symbol-linkage* = a class baked into a resource SWF (always runs from that SWF);
> *by-name* = a reference resolved through the app domain (patchable); *shim* = re-add a dropped member to
> an app class delegating to its new home; *reroute* = load a resource SWF into `currentDomain` so its
> by-name deps hit the app copy; *JPEXS-patch* = edit a resource SWF's bytecode directly. *[verified]* /
> *[single-pass]* mark per-finding confidence (defined under Context).

## 2. The crux, resolved (answers the SDK question) — [verified by 4 skeptic agents]

The chain, each link read directly from the files:
1. `GreatHallPage.handleStart()` loads `great_hall.swf` and **casts the embedded movie clip**
   (`greathall extends GuiGreatHall`) to `IGuiGreatHall`. There is **no `new GuiGreatHall()`** in app
   code → the great hall UI is **symbol-linked**.
2. Symbol-linked classes **always run from their own SWF**, proven empirically by the `battle_initiative`
   reroute (loading it into `currentDomain` left the gui-SWF symbol still winning; only the *by-name*
   `GuiUtil` dependency resolved to the app copy).
3. So the **stale gui-SWF `GuiGreatHall`** — which calls `context.party`/`context.renown` — is what
   executes.
4. The pristine **shipped** decompile proves JPEXS did **not** drop anything: shipped `GameGuiContext` has
   only `get legend()` and shipped `IGuiContext` never declared `party`/`renown`. Stoic genuinely
   **refactored these onto `Legend`** and updated the app's *own* `GuiGreatHall` (it uses
   `context.legend.party`) — a 248-line divergence from the stale gui-SWF copy.
5. The `party` shim works because `context.party` is a **late-bound** property read on the concrete
   app-domain context instance, regardless of which `GuiGreatHall` calls it.

**Proof it was Stoic (not us) who moved `party`/`renown` onto `Legend` — re-verified 2026-06-25:**
The identical `Legend.party` (`engine/entity/def/Legend.as:85`) and `Legend.renown` (`:137`, with a real
`_renown` backing field + `"Legend.RENOWN"` change event — original machinery, not a delegate) appear in
**both** Stoic's readable **2013 source** (`bsf-refs/client-2013-as3/.../engine/entity/def/Legend.as`) and
the **pristine shipped decompile** (`bsf-refs/client-decompiled-as3/.../Legend.as`). The shipped
`GameGuiContext` has only `get legend()`, never `party`/`renown`. We have **no `Legend` overlay** in
`src/` (Glob: none) and the mirror is provably the untouched original (it contains none of our new files —
`ModBridge.as`/`AiBattleLoadState.as` both absent). So the refactor predates us by ~13 years; the
`src/GameGuiContext.as` shim does the *opposite* (re-adds `party`/`renown` onto the context delegating to
`legend.*`). Aside: the empty `{}` bodies in `Legend` (`hireRosterUnit`/`purchaseStat`/`rename`/`promote`/
`purchaseVariation`) are **genuinely empty in the 2013 source too** — base-class stubs, NOT a JPEXS lift
loss — which stress-tests and strengthens the "recompile is high-fidelity" verdict.

**So: the cause is generational API drift between the older resource gui SWFs and the modern app SWF —
not decompiler data-loss (b1 refuted), not an AIR 33→51 domain-resolution flip (b2 refuted).** The SDK
instinct was a reasonable guess, but symbol linkage is version-independent, so the SDK can't be the
selector. *(One honest residual: the exact reason the shipped game tolerated the stale path isn't fully
reconstructable from the decompile — most likely the shipped app/gui SWFs were a matched pair our
forward-decompiled app no longer matches — but this doesn't change any conclusion or fix below.)*

**Consequences:**
- Building with **AIR SDK 33.1 will NOT fix the town crashes** (symbol linkage is SDK-independent). It's
  still worth trying, but for **shippability** (§5), not for these crashes.
- Routing `great_hall.swf`/`mead_house.swf` into `currentDomain` will **not** flip the symbol either.
- The town backlog is **bounded and enumerable**: it's exactly the set of members the stale gui-SWF UI
  classes call that the modern context moved/renamed. Fix each with an **app-side shim** (dropped member,
  by-name) or a **JPEXS bytecode patch** (symbol class, or a getter-called-as-function like Ranked
  `#1006`).

## 3. State of the branch — confirmed findings

### 3.1 [verified] CRITICAL — player-facing `#1009` on armor-only units (`DamageFlagOverlay.onRender:74`)
`turn.entity.def.attacks.getFirstAbilityByTag(ATTACK_STR).def` — null for an armor-only unit
(Shieldbanger); `.def` throws. This is the **player HUD** twin of the AI bug the branch already fixed, but
**unguarded**. Because the feature mirrors the party onto both sides, any armor-only unit in the active
party reliably crashes the damage-preview overlay on the player's own turn. Fix: same null-safe guard
pattern as `AiPlan`.

### 3.2 [verified] CRITICAL — ModBridge credential leak
`HttpAction`'s tap emits the **verbatim `AuthTxn` request body** (username/password / Discord-OAuth token)
**and** response (`session_key`) over stdout to any local `mods/host.exe`. Redact/disable the auth-txn tap
before any shared build. (Lower, [single-pass]: unbounded stdout buffer, restart counter never resets,
final stdout lines dropped on exit.)

### 3.3 [verified] HIGH — launch-boundary safety gaps (the AI-wiring release-blockers)
The battle-engine plumbing itself is **sound** [verified by trace]: independent stat copies (combat never
mutates the roster def), `friendly=true` gates kill/promotion/renown, `isOnline=false` end-to-end (zero
server calls), and the AI party deploys + takes turns correctly. The defects are all at the **trigger**:
- **Spectator/AI-vs-AI is unimplemented** but documented as working: `SPECTATE` is latched and never
  consumed downstream (nothing makes side 0 an AI or suppresses the HUD). In "everything" scope this is a
  feature gap, not just a bug.
- **`Ctrl+Shift+A` ships to players** (`GameKeyBinder.as:19`, `KeyBindGroup.COMBAT`, no debug gate) and
  **`startAiBattle` does no source-state validation** → launchable from login (NPE on null
  `config.legend`), town, or mid-battle (tears down a live battle).
- **No precondition guards**: empty/zero-member party; `items[0]` not validated to be a 2-deployment-area
  versus map.

### 3.4 [single-pass] HIGH — compat shims deref `config.legend` with no null guard
`GameGuiContext.party/renown/rosterSlotAvailable/purchaseRosterUnit` delegate to `legend.*`, but
`GameConfig.legend` can be **null** (no saga/factions set) → a precise `#1069` becomes an opaque `#1009`.
*Correction (2026-06-25):* the "`legend.hireRosterUnit` is an empty stub" sub-claim refers to the **base**
`Legend` (its body is genuinely empty in Stoic's 2013 source); whether a hire actually no-ops depends on
which `Legend` subclass is live at runtime (it may override `hireRosterUnit` to send a server txn). Identify
the runtime `Legend` subclass before asserting the hire silently no-ops — defer to the Wave-5 roster work.

### 3.5 [single-pass] MEDIUM — domain-reroute blast radius
Routing `battle_initiative.swf` into `currentDomain` pulls **471 bundled classes** into the app domain
(incl. stale copies of `ModBridge`/`HttpAction`/`DisplayResourceLoader`); safe only because AS3 keeps the
**first-defined** (app) class — an undocumented, load-order-dependent invariant. Document it; prefer
narrowly-scoped fixes going forward.

### 3.6 [single-pass] Strategic — ModBridge cannot host the AI
The dormant AI works on **live in-sim objects**; the only serialized move-injection path
(`BattleStateTurnRemote`) is on the **online** path this feature disables. ModBridge can *orchestrate*
(start/spectate/telemetry) but the AI **must stay in-SWF and be patched**. An external brain is not an
escape from app-SWF surgery.

## 4. The decision + approach tradeoffs

**Keep decompile/recompile for the app SWF — it is high-fidelity and the only path that lets you add new
app code (the feature itself). Run it as a hybrid: app code via recompile; surgical gui-SWF fixes via
JPEXS bytecode-patch where a shim can't reach (symbol classes, getter-called-as-function `#1006`).**
Do **not** switch wholesale and do **not** decompile the gui SWFs too (doubles the surface, worsens the
wall).

| Approach | Fidelity risk | Crash coverage | Effort | Shippability |
|---|---|---|---|---|
| **Recompile app SWF @ SDK 51 (current)** | **Low** — ~12 documented hand-edited lines; rest byte-identical | Good, given §6 harness | Med | **Blocked** by runtime/packaging wall |
| **Recompile app SWF @ SDK 33.1** | Low (same compiler gen as original) | Same | Low (swap SDK) | **Possibly unblocks** wall + ANEs — worth testing |
| **JPEXS bytecode-patch only** | Very low (binary preserved) | Same dormant-AI tail | High per fix, scoped | Good (original runtime) — best for the gui-SWF/`#1006` cases |
| **External ModBridge brain** | n/a | Can't host the AI (§3.6) | — | Not a substitute |
| **Decompile the gui SWFs too** | High (doubles surface) | Removes shims | High | Worse |

## 5. Public-release gap list (prioritized)

- **MUST** — player-facing crash `DamageFlagOverlay:74` (§3.1).
- **MUST** — ModBridge credential leak (§3.2).
- **MUST** — packaging/runtime wall: only `adl` (SDK-51) runs the build today; packaged `adt` builds
  **reject the FMOD/Steamworks ANEs on desktop (error 112)** → no runnable player build and **no audio**.
  The SDK-33.1 experiment targets exactly this.
- **MUST** — bound the dormant-AI crash tail via §6 (can't ship "fix as you hit it").
- **MUST** — launch safety: gate/remove the global `Ctrl+Shift+A`, add source-state validation + party
  guards (§3.3).
- **SHOULD** — finish or de-scope **spectator** (currently documented-but-unimplemented).
- **SHOULD** — enumerate + fix the **bounded** gui-SWF drift backlog (shim vs JPEXS-patch), incl. Ranked
  `#1006` and the deeper-town members (stat-buy/promote/color-variant); shim null-guards (§3.4).
- **SHOULD** — build **reproducibility**: pin the JPEXS version + source-SWF hash (overlays bake in
  JPEXS-version-specific register/symbol names → a JPEXS upgrade can silently break them); fix the docs,
  which claim `src/` holds only `PreAuthState.as` but it holds ~33 files incl. bulk gameplay/render
  overlays.

## 6. Systematic crash-discovery strategy (replaces whack-a-mole)

1. **Static deref audit** — grep the AI module + battle HUD for the one proven pattern,
   `getFirstAbilityByTag(<TAG>).{def,id}` and sibling unguarded `.def/.id/.tag` derefs, across the full
   roster's ability sets. (`DamageFlagOverlay` was found exactly this way.)
2. **AI-vs-AI fuzz via ModBridge spectator** (once spectator exists) — auto-run battles over every roster
   unit × ability × board condition, logging every uncaught `#1009/#1069/#1006`.
3. **Fidelity-regression harness** — golden-output diffing recompiled-vs-shipped on deterministic inputs
   (AMF/JSON round-trips, battle-replay determinism, damage spot-checks) to catch *silent* drift. Lower
   priority now that §2 shows the fidelity surface is small and bounded, but still the right safety net
   for a public build.

## 7. Work broken into waves (each sized for a fresh cold-start chat)

Priority: **P0** = release-blocking, do first; **P1** = required for public release; **P2** = polish.
Waves are largely independent — the only soft dependency is Wave 6 (spectator) unlocking Wave 3's fuzz
loop. Each kickoff prompt is copy-pasteable into a new chat (which auto-loads `CLAUDE.md` + memory). All
reference this in-repo plan (`misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`).

### Wave 1 — Crash & launch hardening (P0, small)
**Goal:** kill the confirmed player-facing crash and make the offline-AI trigger safe to ship.
**Do:** (a) null-guard `DamageFlagOverlay.onRender:74` (`getFirstAbilityByTag(ATTACK_STR).def`), same
behavior-preserving pattern as the `AiPlan` fix; (b) gate `Ctrl+Shift+A` so it doesn't reach players
(debug-flag or remove) — `src/game/cfg/GameKeyBinder.as:19`; (c) add source-state validation to
`GameFsm.startAiBattle` (`:186`) + null `config.legend` / empty-party / non-versus-scene guards in
`AiBattleLoadState`; (d) null-guard the `config.legend` derefs in the `GameGuiContext` shims (§3.4).
> **Kickoff:** "Issue-12 Wave 1 (crash & launch hardening). Per `misc/Plan-Issue-12-Player-vs-AI-Public-Release.md`
> §3.1/§3.3/§3.4: add a behavior-preserving null guard to
> `src/engine/battle/board/view/overlay/DamageFlagOverlay.as:74` (`getFirstAbilityByTag(ATTACK_STR).def`
> is null for armor-only units — player-HUD twin of the fixed AiPlan bug); gate the `Ctrl+Shift+A` keybind
> in `GameKeyBinder.as` so it doesn't ship to players; add source-state + null-`config.legend` +
> empty-party + non-versus-scene guards to `GameFsm.startAiBattle` / `AiBattleLoadState`; and null-guard
> the `legend.*` shims in `GameGuiContext.as`. All overlays route through `_decompiled/` via apply-patches;
> keep each diff minimal vs the decompile. Then build + verify a Ctrl+Shift+A battle with an armor-only
> unit (e.g. Shieldbanger) in the party."

### Wave 2 — ModBridge credential-leak fix (P0, small)
**Goal:** stop leaking auth credentials to `mods/host.exe`.
**Do:** redact/suppress the `AuthTxn` request body (username/password/Discord token) **and** the
`session_key` in the `HttpAction` tap (`doSend`/`onResponseReceived`); bound the stdout buffer; reset the
restart counter on a clean run; flush the final stdout line on exit.
> **Kickoff:** "Issue-12 Wave 2 (ModBridge security). Per the public-release plan §3.2: the `HttpAction`
> tap (`src/engine/core/http/HttpAction.as`) emits the verbatim AuthTxn request body and the `session_key`
> response to `mods/host.exe`. Redact auth/secret fields before emitting (allowlist or skip AuthTxn
> entirely); also bound `ModBridge.m_stdoutBuf`, reset the restart counter on success, and flush the final
> line on exit. Verify the bridge still works for non-auth txns."

### Wave 3 — Dormant-AI crash-tail audit (P1, medium/investigative)
**Goal:** surface the FULL latent-crash tail systematically instead of one-by-one.
**Do:** static deref audit of `engine/battle/fsm/aimodule/*` + the battle HUD overlays for the proven
pattern `getFirstAbilityByTag(<TAG>).{def,id}` and sibling unguarded `.def/.id/.tag`/stat derefs; map each
to the unit/board condition that triggers it across the full roster; guard each behavior-preservingly.
> **Kickoff:** "Issue-12 Wave 3 (dormant-AI crash-tail audit). Per the public-release plan §6.1: grep
> `src/engine/battle/fsm/aimodule/*` and the battle HUD overlays for `getFirstAbilityByTag(<TAG>).def/.id`
> and other unguarded `.def/.id/.tag`/stat derefs the dormant AI never exercised in real PvP. Produce the
> full list with the unit + board condition that triggers each, then add minimal null guards. Goal: a
> bounded, enumerated tail, not whack-a-mole."

### Wave 4 — Shippability: AIR SDK 33.1 build + packaging (P0-strategic, experiment)
**Goal:** get a runnable PACKAGED player build *with audio* — clear the runtime/packaging wall. (This does
NOT fix the town crashes — symbol linkage is SDK-independent, §2 — it's purely about shippability.)
**Do:** rebuild with HARMAN AIR SDK 33.1; package via `adt` with the FMOD + Steamworks ANEs; test running
outside `adl`; confirm audio; investigate the `adt` error-112 ANE rejection. Decide whether to switch the
build SDK to 33.1.
> **Kickoff:** "Issue-12 Wave 4 (shippability / AIR SDK). Per the public-release plan §5: today only `adl`
> (SDK-51) runs the build and packaged `adt` builds reject the FMOD/Steamworks ANEs (error 112) = no
> player build + no audio. Try rebuilding with the ORIGINAL HARMAN AIR SDK 33.1 (`scripts/build.ps1`),
> package via `adt` with the ANEs, and report whether it runs standalone with sound. Note: this is for
> shippability only — it will NOT fix the gui-SWF town crashes (those are symbol-linked, SDK-independent)."

### Wave 5 — Bounded gui-SWF drift backlog (P1, medium/large; may split town vs ranked)
**Goal:** enumerate + fix every remaining stale gui-SWF call across town + ranked + popups.
**Do:** extract/enumerate stale `context.*` + drifted symbol-class calls across
`great_hall`/`mead_house`/proving-grounds/versus/ranked/popup SWFs; classify each by repair mechanism
(app-shim for a dropped member called by-name; JPEXS bytecode-patch for a symbol class or a
getter-called-as-function); implement — incl. Ranked `#1006` (single-instruction
`callproperty…totalPower` → `getproperty`) and the deeper-town members (stat-buy/promote/color-variant;
`purchaseVariation` also helps #119). Apply the two-mechanism rule from the issue-12 plan.
> **Kickoff:** "Issue-12 Wave 5 (gui-SWF drift backlog). Per the public-release plan §2/§5: the town/ranked
> crashes are a BOUNDED API-drift problem (stale gui-SWF UI classes calling members the modern app context
> moved to `Legend`). Extract + enumerate every stale `context.*`/drifted-symbol call across great_hall,
> mead_house, versus, ranked, proving-grounds, and the battle popups; classify each as app-shim vs
> JPEXS-patch; then implement. Includes the Ranked `#1006` single-instruction JPEXS patch (`totalPower`
> getter-called-as-function) and deeper-town members. Use the two-mechanism rule from
> `Plan-Fix-Issue-12-ai-battle-init-hang.md`."

### Wave 6 — Spectator (AI-vs-AI): implement or de-scope (P2)
**Goal:** make `SPECTATE` real or stop documenting it as working.
**Do:** consume `SPECTATE` downstream — route side 0 through `addAiParty` too + suppress `BattleHudPage`
local controls + add a spectator key — OR formally de-scope and correct the `AiBattleLoadState` docstring.
Implementing it unlocks the Wave 3 fuzz loop.
> **Kickoff:** "Issue-12 Wave 6 (spectator). Per the public-release plan §3.3: `SPECTATE` is latched in
> `AiBattleLoadState`/`GameFsm` but never consumed — the AI-vs-AI spectator the docstring claims doesn't
> exist. Either implement it (side 0 also an AI via `SceneLoader.addAiParty`, suppress `BattleHudPage`
> local controls, add a spectator key) or de-scope it and fix the false docstring. If implemented, it
> enables an AI-vs-AI fuzz loop for Wave 3."

### Wave 7 — Build reproducibility + honest docs (P2, small)
**Goal:** make the build deterministic and the docs match reality.
**Do:** pin the JPEXS version + source-SWF hash in `scripts/decompile.ps1` (overlays bake in
JPEXS-version-specific register/symbol names → a JPEXS upgrade can silently break them); correct
`docs/build-workflow.md`, `docs/architecture.md`, `CLAUDE.md` (they claim `src/` holds only
`PreAuthState.as`; it holds ~33 files incl. bulk overlays). Optionally scaffold the §6.3 regression harness.
> **Kickoff:** "Issue-12 Wave 7 (build reproducibility + docs). Per the public-release plan §5: pin the
> JPEXS version + source-SWF hash in `scripts/decompile.ps1` so a JPEXS upgrade can't silently break the
> register-name-dependent overlays; and correct `docs/build-workflow.md` / `docs/architecture.md` /
> `CLAUDE.md`, which understate the `src/` patch surface (~33 files, not just PreAuthState.as)."

## Open items / residual uncertainty

- The §3.4/§3.5 (shim null-deref, reroute blast radius) and the build-risk findings are **[single-pass]**
  — their verifiers were lost to a session limit; re-verify before relying on exact numbers (e.g. "471
  classes").
- The exact reason the *shipped* game tolerated the stale `GuiGreatHall` path (§2 residual) — not needed
  for any fix, but the one loose thread if you want full closure.
- The existing project memory's "Stoic moved party/renown onto `Legend`" diagnosis is **vindicated** by
  §2; the refinement is that it's symbol-linked + decompiler-faithful + SDK-independent, and the backlog
  is bounded.

## Verification

- For the confirmed crash fixes: edit the `src/` overlay → `apply-patches.ps1` → `build.ps1` → copy
  `app.game.air.swf` → `run-adl.ps1`; start a Ctrl+Shift+A battle with an armor-only unit in the party and
  confirm no `#1009` on the damage overlay; open Great Hall / Mead House and confirm no `#1069`.
- SDK-33.1 experiment: build with the 33.1 SDK, package via `adt` with the FMOD/Steamworks ANEs, and
  confirm whether it runs outside `adl` and restores audio (the real shippability test).
