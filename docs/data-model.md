# The data model — units, classes, and the `Def`/`Vars`/`Wrangler` pattern

## Co-Authored-By: Claude <noreply@anthropic.com>

The game's units, character classes, and combat numbers are **not** baked into the program. They live
in **data files** — JSON (plain-text lists of names and numbers) that the client reads at startup and
turns into typed objects the game code can ask questions of. This doc explains, once, the naming
pattern the whole codebase uses to read those files, then follows one real example end to end: how a
character class like **Axemaster** travels from a file on disk to a unit standing on your roster.

Read [`asset-loading.md`](./asset-loading.md) first if you want the loader plumbing (how bytes become
a resource); this doc picks up where that leaves off — how a loaded data blob becomes a **def**.

---

## 1. The three-part pattern, read once

Almost every kind of game data follows the same three-part naming pattern. It is a **convention the
code follows, not one shared base class** — each data type writes its own trio, and only a tiny loader
core is actually shared:

| Part         | Suffix         | What it is                                                                                                    |
| ------------ | -------------- | ------------------------------------------------------------------------------------------------------------- |
| **Def**      | `XxxDef`       | The finished, **typed** object the game asks questions of (`axemaster.strengthRange`, `.abilities`).          |
| **Vars**     | `XxxDefVars`   | The **checker/converter**: takes the raw JSON and fills in a Def. (Named "Vars" = it reads the variables.)    |
| **Wrangler** | `XxxDefWrangler` | The **fetcher**: loads the file and collects the results into a list of Defs.                                |

The `Vars` class is literally a subclass of the `Def` — e.g. `EntityClassDefVars extends
EntityClassDef` — so "the thing that parses the JSON" *is* "the typed object", just with a constructor
that knows how to read a raw JSON object. ([Inference] confirmed for `EntityClassDefVars`,
`EntityDefVars`, `AccountInfoDefVars`.)

Only two things are shared across every trio:

- **The loader core** — `engine/resource/def/`: `DefResource` reads and JSON-parses the file
  (`DefResource.as:18-32`) and, if the file lists child resources, transparently pulls them in too
  (`:34-50`); `DefWrangler` drives one load and hands back the raw parsed object via its `.vars` getter
  (`DefWrangler.as:104-107`); `DefWranglerWrangler` runs a whole batch of wranglers and fires one
  "all done" event.
- **The validation gate** — `EngineJsonDef.validateThrow` (`engine/def/EngineJsonDef.as:15-25`) checks
  a raw object against a Def's `schema` through a pluggable validator and throws `ArgumentError` if it
  doesn't match. That validator is wired at startup: `GameMainAir` sets it to a real JSON-schema
  checker (`GameMainAir.as:147` → `EngineJsonDefImpl.validate`, built on the Frigga library), which
  logs every offending property. So **the `schema` blocks are enforced at load** — a malformed data
  file is caught with a clear error naming the bad field, not silently accepted.

Everything else — `EntityClassDef`, `GameStatCostsDef`, `SagaDef`, `AccountInfoDef`, … — just repeats
the naming pattern with its own fields.

---

## 2. When the data loads

Most game data loads **once, in a single batch at boot.** `GameConfig` builds a `DefWranglerWrangler`
and queues the whole common data set onto it (`GameConfig.as:592-610`): character classes
(`common/character/character_classes.json.z`, `:595`), prop/scenery classes, per-class stat costs, the
starting roster, the battle scene list, sound, achievements, and battle triggers. One `wranglers.load()`
kicks them all off; a single `complete` event says the game data is ready.

Data that isn't needed until later loads **on demand:**

- **Account/faction data** — `FactionsConfig` keeps its own wrangler and loads after login, off the
  `GameConfig.EVENT_ACCOUNT_INFO` event (`FactionsConfig.as:50`), because it depends on *who* logged in.
- **Campaign (saga) data** — `engine/saga/SagaDefLoader` wrangles campaign defs only when a saga
  actually starts, so the boot batch stays small. [Inference]

---

## 3. Class definitions are templates

A **character class** (`EntityClassDef`, built by `EntityClassDefVars`) is a *template*, not a unit.
Take Axemaster in the readable sample [`misc/factions_character_classes.json`](../misc/factions_character_classes.json).
Its `EntityClassDefVars` constructor (`EntityClassDefVars.as:88-134`) reads:

- **Stat ranges — `min`/`max`, not a value** (`:109-121`). A class says "an Axemaster's strength lives
  somewhere between these two numbers", it does **not** fix the number. This is the load-bearing rule
  §5 comes back to.
- **Ability lists** — `actives` (e.g. `abl_stonewall`, `abl_end`, `abl_rest`) and `attacks`, stored as
  ability ids the ability system resolves later.
- **Appearances** — the visual variations (`v0`/`v1`/`v2` portraits, icons, animations), each with an
  optional `unlock_id`/`acquire_id` that gates it.
- **A parent class** — the `parent` field lets a class build on another so shared traits live in one
  place (`_parentEntityClassId`, `:95`). [Inference]

The `schema` block at the top of the class (`EntityClassDefVars.as:14-86`) is the field-by-field
contract — the best quick reference for "what can a class file contain."

---

## 4. Unit definitions are your actual units

Where a *class* carries ranges, a **unit** (`EntityDef`, built by `EntityDefVars`) carries **concrete
numbers**. `EntityDefVars.fromJson` (`EntityDefVars.as:171-211`) points the unit at its class
(`:179`), reads its own ability **levels**, and adds its own **concrete stat values** (`:201`) — this
particular Axemaster has strength **10**, not "8–12". Right after, `clampStats` (`:209`) trims those
values back inside the class's min/max, so a unit can never carry a number its class forbids.

The live thing standing on the battle board is a third object — a `BattleEntity` — that **wraps one
`EntityDef`** and reads its numbers during the fight. One wrinkle worth flagging here: `Entity.stats`
returns a scratch copy called `_fakeStats` when one is set (`engine/entity/model/Entity.as:47-50`).
That is the offline AI's "imagined move" machinery temporarily swapping in a pretend copy so it can
score a hit without touching the real unit — fully explained in
[`offline-ai.md`](./offline-ai.md) → "The 'imagined move' trick". In normal play `_fakeStats` is null
and the unit uses its real numbers.

---

## 5. Your account and roster

When you log in, the server's account answer is parsed by `AccountInfoDefVars`
(`game/cfg/AccountInfoDefVars.as:52-90`) into an in-memory account object called the **`legend`**:

- `legend.roster` — every unit you own, each a full `EntityDef` (from `param1.roster`, `:58`).
- `legend.party` — the subset you take into battle (`:59`).
- `legend.renown` — your currency (`:60`); plus row count, unlocks, purchases, daily-login state.

The exact wire fields are in [`wire-protocol.md`](./wire-protocol.md) → "Account" and, on the server
side, `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)).

**The rule that keeps resurfacing in debugging — and it is the opposite of what this document used to
say.** In a battle against another player, a unit fights with the numbers the **server sent with that
battle**, and so does the opponent's copy of it. Both parties on both screens are built from that one
message. Your roster still matters — the server builds the party from it, and it decides who is in the
party and the order they act in — but it is not what the units fight with. The class definition fills
in only stats the message leaves out and pulls out-of-range values back inside the allowed band (§3,
§4); it also recomputes the first-ability slot and the injury fields from rank whatever arrives.

Measured on 2026-08-21: a unit whose strength and armour were changed on the way over — and only there
— showed the changed numbers on **both** players' screens, while the roster on file kept its real ones.
So editing the stats inside a server-sent battle party does not do nothing; it silently changes the
battle for both players. An offline practice battle is different: it builds both sides from your own
roster. Server side, with the full method: `bsf-server/docs/client-contract.md` → R13 ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)).

Separately, and still true: the server sending a short or unresolved party shows up as a power
mismatch — see the matchmaking gotchas in `bsf-server`.

---

## 6. From a file to a unit — the whole path

Tying the pieces together, here is how one **Axemaster** travels from disk to the battlefield:

1. **Boot** — `GameConfig` queues `character_classes.json.z` onto its loader batch (§2).
2. **Load + parse** — `DefResource` reads the file and JSON-parses it into a plain object; if the file
   names child files, those load too (§1).
3. **Build the template** — an `EntityClassDefWrangler` walks the parsed list and turns each entry into
   an `EntityClassDefVars` → a typed `EntityClassDef`. The Axemaster template now knows its stat
   **ranges**, its ability list, and its appearances (§3).
4. **Make your roster unit** — when your account loads, each unit you own becomes an `EntityDef` (built
   by `EntityDefVars`) that carries its **own concrete numbers** plus a pointer to the Axemaster
   template; `clampStats` trims those numbers back inside the template's min/max (§4).
5. **Fight** — the live `BattleEntity` wraps that `EntityDef` and fights with **its** numbers; the
   template is never consulted again (§5).

One chain, start to finish: **file → `DefResource` → Wrangler → Vars → Def (template) → Def (your unit)
→ `BattleEntity`.**

---

## 7. Naming traps

- **"Vars" means three different things.** (1) A class-name suffix for the JSON reader
  (`EntityClassDefVars`). (2) `DefWrangler.vars` — a getter returning the **raw parsed JSON** object
  (`DefWrangler.as:104`). (3) `EntityDef`'s `_vars` field — a saga **`VariableBag`** (a campaign
  key-value store), unrelated to either (`EntityDefVars.as:176`). Same word, three meanings.
- **`game/entity/` does *not* hold the entity model.** It holds only the `GameStatCosts` trio
  (promotion/hire cost tables). The real entity model lives in `engine/entity/` — `def/` for the
  templates, `model/` for the live objects.
- **The schema check looks optional but isn't.** Read on its own, `validateThrow` guards on a
  `_validate` function pointer that reads as "maybe wired" — but `GameMainAir` wires it at boot (§1),
  so schema validation really does run. Don't mistake the null-guard for "validation is off."
- **The 2013 source is stale for these files.** `engine/entity/def/*` and `game/cfg/*` are on the
  12-file stale list — read the decompile (`_decompiled/scripts/…`), not the 2013 mirror. See
  [`reference-codebases.md`](./reference-codebases.md).

---

## 8. Where to read more

- [`asset-loading.md`](./asset-loading.md) → "A data blob (a def)" — the loader layer beneath this one
  (`DefResource` fanning out into a `ResourceTree`).
- [`offline-ai.md`](./offline-ai.md) — where the `_fakeStats` "imagined move" copy from §4 comes from.
- [`wire-protocol.md`](./wire-protocol.md) → "Account" — the account/roster answer this doc maps in.
- [`subsystem-index.md`](./subsystem-index.md) → "game-data layer" — the class-by-class index.
- `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) — the server's view of the same account/roster data.
