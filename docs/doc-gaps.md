# Documentation gaps — `bsf-client`

## Co-Authored-By: Claude <noreply@anthropic.com>

This is the tracked, closeable list of **what the client docs still don't cover**. It is the client
analogue of `bsf-server/docs/doc-gaps.md` ([local](../../bsf-server/docs/doc-gaps.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/doc-gaps.md)).

**Hygiene rule:** when a doc lands that closes an entry, **delete that entry** (don't strike it
through). The list should be **empty** once the documentation track (P3) merges. The full plan is
[`../misc/Plan-Docs-Track-2026-07-02.md`](../misc/Plan-Docs-Track-2026-07-02.md).

Each entry names the gap, why it matters, and the source material a writer should mine.

---

## P3 — data model, offline AI, mod tooling

1. **Data model + the `Def`/`Vars`/`Wrangler` pattern** → planned `docs/data-model.md`.
   The JSON-definition triad documented once (**Def** = typed accessor, **Vars** = raw-JSON field bag,
   **Wrangler** = collection/loader), using `engine/entity/def` as the worked example, then the entity
   model and its mapping to server account/roster data. *Source:* `_decompiled/scripts/engine/entity/**`;
   `wire-protocol.md`; `bsf-server/docs/dataStructures.md`. Note the stale-file caveat for
   `EntityDef`/`EntityClassDefList`.

2. **Offline AI** → planned `docs/offline-ai.md`.
   Fills `battle-engine.md`'s explicit offline gap: `engine/battle/fsm/aimodule/*` (`AiModuleBase`,
   `AiModuleDredge`, `AiPlan`), `BattleStateAi`, and the entry path (`SkirmishState` /
   `ProvingGroundsState` / `AiBattleLoadState`). Key point: a solo battle reuses the **same lockstep FSM
   + per-turn DJB hash** as multiplayer. *Source:* `src/engine/battle/fsm/aimodule/**`,
   `src/game/session/states/AiBattleLoadState.as`; the two AI `misc/Plan-*.md`.

3. **Mod bridge** → planned `docs/mod-bridge.md`.
   The fork's non-Stoic scripting host: `src/engine/mod/ModBridge.as` (NativeProcess → `mods/host.exe`,
   newline-delimited JSON, command registry, restart/shutdown lifecycle) and the hook site
   `src/engine/core/http/HttpAction.as` (taps every request/response). *Source:* the in-file doc block
   in `ModBridge.as`; `patch-inventory.md` (mod-bridge group).

4. **`battle-engine.md` offline pointer** → planned short section.
   A pointer from the multiplayer battle-FSM doc to `offline-ai.md`, closing its documented gap.

---

## Cross-cutting cleanup (not a doc — a code reference to retire)

5. **`scripts/run-adl.ps1` references `DiscordSteamworks`** which does not exist in `src/`.
   Once `DiscordSteamworks.as` is either created or the launch script stops referencing it, this
   inconsistency clears. Tracked here so it isn't silently forgotten; `patch-inventory.md` records the
   class as *planned / not-yet-created*.
