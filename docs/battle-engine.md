# Battle engine (client side)

## Co-Authored-By: Claude <noreply@anthropic.com>

How the client runs a battle: the FSM that drives both players' lockstep turns, the board model that tracks every entity, the entity-ID format that _must match_ between clients, and the DJB hash that guarantees lockstep.

This doc covers the **client** side. The server's authoritative battle state and endgame logic live in `bsf-server/src/services/battle/Battle.ts` ([local](../../bsf-server/src/services/battle/Battle.ts) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/src/services/battle/Battle.ts)) — see `bsf-server/docs/gameFlow.md` ([local](../../bsf-server/docs/gameFlow.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/gameFlow.md)) and `bsf-server/docs/ARCHITECTURE.md` ([local](../../bsf-server/docs/ARCHITECTURE.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/ARCHITECTURE.md)) → "Battle State".

> **12-stale-file caveat:** the shipped `BattleBoard`, `BattleStateInit`, `BattleStateDeploy`, `BattleFsmConfig`, `BattleTurnOrder`, and `Op.as` are in the [12-stale-file exception list](./reference-codebases.md#prefer-2013-source-over-decompile--except-for-12-files) — read the JPEXS decompile under `bsf-refs\client-decompiled-as3\engine\battle\`, not the 2013 source for those files.

## Battle FSM — `BattleFsm`

`engine/battle/fsm/BattleFsm.as` extends `engine/core/fsm/Fsm`. It owns the per-battle state (`board`, `order`, `participants`, `turns`, `chat`, `session`) and dispatches to the state subclasses below.

```
BattleStateInit
    │   loads BattleCreateData; sends services/battle/ready (BattleTxnStartSend)
    ▼
BattleStateDeploy
    │   waits for the deployment UI; sends services/battle/deploy (BattleTxnDeploySend)
    ▼
BattleStateStart
    │   one-shot — opens the battle screen
    ▼
BattleStateNextTurn  ◀──┐
    │   computes DJB hash; sends services/battle/sync (BattleTxnTurnInitSend)
    │                   │
    ▼                   │
BattleStateTurn{Local,Remote,Ai}
    │   move / action / killed transactions on the local-player branch
    │   (BattleTxnMoveSend, BattleTxnActionSend, BattleTxnKillSend)
    │                   │
    └──────────────────┘
   loops over turns

BattleStateFinish ─→ BattleStateFinished       (normal end — both players see "you won")
                  └→ BattleStateAborted        (mid-battle disconnect)
                  └→ BattleStateSurrender      (services/battle/surrender via BattleTxnSurrenderSend)
                  └→ BattleStateError          (something went wrong)
                  └→ BattleStateRespawn        (re-enter after a transient disconnect)
```

The full state list lives under `engine/battle/fsm/state/` — 18 classes total. The turn states have a deeper subtree under `state/turn/`. See [`subsystem-index.md`](./subsystem-index.md#enginebattle--battle-internals) for the per-class table.

### One important side effect of `startFsm`

```actionscript
override public function startFsm(param1:Object) : void
{
   ...
   super.startFsm(param1);
   if(isOnline)
   {
      session.communicator.setPollTimeRequirement(this, 1000);   // line 374
   }
}
```

`BattleFsm.as:374` registers a 1-second poll requirement against the global `HttpCommunicator`. The long-poll cadence drops from 3 s (default) to 1 s for the duration of the battle, so server-side moves land quickly on the opponent's screen. When the FSM exits, `removePollTimeRequirement(this)` restores the 3-s default. See [`wire-protocol.md`](./wire-protocol.md#long-poll-mechanics).

## Board model

`engine/battle/board/model/` (decompile only — stale list).

| Class             | Role                                                                              |
| ----------------- | --------------------------------------------------------------------------------- |
| `BattleBoard`     | The board itself. Owns parties, entities, tiles, turn order, deployment metadata. |
| `BattleParty`     | One side's roster for this battle (player A vs player B, plus any AI parties).    |
| `BattleEntity`    | One unit on the board — facing, position, abilities, stats, alive/dead.           |
| `BattlePartyType` | Enum: `Player`, `Ai`, etc.                                                        |
| `BattleFacing`    | Direction the unit faces — affects shield bonuses.                                |

`BattleBoard` is the most-changed-since-2013 file in the codebase; the 2013 source under `client-2013-as3` is stale. Always read the decompile.

## Entity ID format — the lockstep contract

Every entity on the board has a string ID. The ID is constructed client-side in `BattleBoard.addPartyMember()`:

```actionscript
public function addPartyMember(
   param1:String,   // partyKey
   param2:String,   // entityId (if null, auto-constructed below)
   param3:String,   // battleId
   param4:String,   // accountId — the 32-bit user_id from login
   param5:String,   // deployment side
   param6:IEntityDef,  // unit definition
   ...
) : BattleEntity
{
   var _loc12_:BattleParty = createParty(param1, param3, param4, param5, ...);
   if(!param2)
   {
      param2 = param4 + "+" + _loc12_.numMembers + "+" + param6.id;   // line 456
   }
   ...
}
```

**Format:** `{account_id}+{member_count_before_this_unit}+{unit_def_id}`

- `account_id` — the 32-bit `user_id` from the login response (NOT the full 64-bit Steam ID).
- `member_count_before_this_unit` — the party's member count _before_ this entity is added. So the first unit is `+0+`, the second is `+1+`, etc.
- `unit_def_id` — the unit's definition ID string (e.g. `unit.archer.shieldmaiden`).

**Why this is load-bearing:** the per-turn DJB hash (next section) is computed over a string built from every entity's ID, in order. If your client and the opponent's client disagree on even _one_ character of _one_ entity ID, the hashes diverge at turn 0 and the battle desyncs immediately.

The most common way this breaks: the server returns different `account_id` values to the two players for the same opponent. That happens if the server reduces 64-bit Steam IDs inconsistently (e.g. one player sees the full 64-bit ID, the other sees the reduced 32-bit). See `bsf-server/CLAUDE.md` ([local](../../bsf-server/CLAUDE.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/CLAUDE.md)) → "32-bit account IDs in all in-game data" and `.claude/rules/gotchas.md`.

## Per-turn DJB hash — `BattleStateNextTurn`

`engine/battle/fsm/state/BattleStateNextTurn.as:127–133`:

```actionscript
private function computeHash() : int
{
   computeHashStr();
   hash = Hash.DJBHash(hashStr);   // line 130
   logger.debug("Turn Hash: " + hash + "\n" + hashStr);
   return hash;
}
```

`computeHashStr()` (walks the alive participants via `battleFsm.order.getAliveParticipants`) concatenates a per-entity string — one line per entity, newline-separated. Each line carries the entity's ID, the tile it stands on, and then a fixed list of twelve stats named in `SYNC_STATS`, **strength and armour first**, followed by willpower, armour break, exertion and the attack/resist modifiers. The DJB hash over that string is the **lockstep checksum**. Worth knowing which stats are in there: it is why two players who start from different numbers for the same unit are caught at the very first turn boundary rather than drifting silently — see `bsf-server/docs/client-contract.md` → R13 ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)).

The hash is sent to the server in the `BattleSyncData` message (`services/battle/sync`, `BattleTxnTurnInitSend`) — **online battles only**; offline AI battles skip both the hash and the send (see "Offline battles — the AI path" below). **If the two players' hashes for a turn don't match, the battle is desync'd** — and the original Stoic implementation aborted the battle over it.

**The comparison happens here, in the client — not on the server.** The server **relays** the message to the opponent; each client then checks the incoming hash against its own. `BattleFsm.handleSync` (`engine/battle/fsm/BattleFsm.as:336–361`):

```actionscript
var _loc2_:int = param1.turn;
var _loc4_:int = param1.hash;
if(turns.length > _loc2_)
{
   _loc3_ = turns[_loc2_].hash;
   if(_loc4_ != _loc3_)
   {
      logger.error("BattleSyncData DIVERGENCE detected at turn " + _loc2_);
      errors.push("BattleSyncData DIVERGENCE detected at turn " + _loc2_);
      transitionTo(BattleStateError,current.data);   // aborts the battle
   }
   ...
   return true;
}
logger.debug("BattleSyncData SYNC WAIT turn " + _loc2_);
return false;   // opponent is ahead — leave the message queued and retry later
```

So a divergence is **detected and acted on**: the battle transitions to `BattleStateError`. Two consequences worth knowing:

- **What the server owes us is relay fidelity, nothing more** — forward `turn` and `hash` to the opponent unaltered. `bsf-server` does that (`Battle.ts` `/battle/sync` builds the message and calls `pushData` on the opponent). It does **not** store the hash, and does not need to for detection to work.
- **The server has no record of *why* a battle ended, though.** It sees the abort but not the divergence, so a desync is invisible in server logs. That is a real observability gap — BSF-Custom-Server #165 — but it is a *logging* improvement, not the missing safety net an earlier version of this note claimed. See `bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R15.

Note the `return false` on the last line: if the opponent's sync arrives for a turn this client hasn't reached, the message is **not consumed** and is re-examined on a later pass. Ordering between the two clients is tolerated by design.

### Battle-id-seeded RNG

`BattleBoard.as:205` uses `Hash.DJBHash(battleId)` as the RNG seed for the entire battle. Both clients seed identically, so any random rolls (initial deployment shuffles, ability proc rolls) produce the same numbers on both sides — another lockstep guarantee.

## Offline battles — the AI path

Everything above describes an **online** battle. Our fork also runs this same FSM **offline**, against a
built-in AI opponent, with exactly two differences:

- **AI turns.** When a side is AI-controlled, `BattleStateNextTurn` routes it to `BattleStateTurnAi`
  rather than the local/remote turn states (`BattlePartyType.AI` → `BattleStateTurnAi`, gated on
  `BattleFsmConfig.enableAi`, `BattleStateNextTurn.as:60-69`). This dispatch is original Stoic code.
- **No per-turn sync.** An offline battle skips the hash-and-send above entirely — `handleEnteredState`
  gates it on `battleFsm.isOnline` (`:170-180`) and, when offline, goes straight to `nextTurn()`. The
  battle-id-seeded RNG still applies, so offline battles stay just as reproducible.

The full walkthrough — how the AI picks a move, what it can't do, and the fork's crash fixes — is in
[`offline-ai.md`](./offline-ai.md).

## Wire-message correspondence

Each battle FSM state sends or consumes one or more wire messages. The DTOs live under `tbs/srv/battle/data/` (mirrors of `bsf-refs\server-2013-java\src\main\java\tbs\srv\battle\data\`).

| Client class (sender)    | Server route             | Server-side DTO                                                  | Consumed-by client state                                               |
| ------------------------ | ------------------------ | ---------------------------------------------------------------- | ---------------------------------------------------------------------- |
| `BattleTxnStartSend`     | `POST /battle/ready`     | `BattleReadyData`                                                | (no response body)                                                     |
| `BattleTxnDeploySend`    | `POST /battle/deploy`    | `BattleDeployData`                                               | Opponent receives via `/services/game` long-poll → `BattleStateDeploy` |
| `BattleTxnTurnInitSend`  | `POST /battle/sync`      | `BattleSyncData`                                                 | Opponent's `BattleStateNextTurn`                                       |
| `BattleTxnMoveSend`      | `POST /battle/move`      | `BattleMoveData`                                                 | Opponent's `BattleStateTurnRemote`                                     |
| `BattleTxnActionSend`    | `POST /battle/action`    | `BattleActionData`                                               | Opponent's `BattleStateTurnRemote`                                     |
| `BattleTxnKillSend`      | `POST /battle/killed`    | `BattleKilledData`                                               | Triggers server-side endgame check; opponent gets `BattleFinishedData` |
| `BattleTxnQuery`         | `POST /battle/query`     | (read-only — refreshes the client's view of server battle state) | All states (debug-style probe)                                         |
| `BattleTxnExitSend`      | `POST /battle/exit`      | `BattleExitData`                                                 | `BattleStateAborted` / `BattleStateFinished`                           |
| `BattleTxnSurrenderSend` | `POST /battle/surrender` | `BattleSurrenderData`                                            | Triggers endgame; opponent receives `BattleFinishedData`               |

Battle-message JSON shapes: `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) (marked WIP — several messages are still stub-only; the doc gaps inventory tracks this).

## Server-pushed messages (the other direction)

Most battle progress arrives via the long-poll, not as responses to the client's own POSTs. The client polls `GET /services/game/{sessionKey}` (`TxnGet`) and demuxes the response array by a `type` discriminator. Messages relevant during a battle:

| Type                                  | Triggers (client side)                                                     |
| ------------------------------------- | -------------------------------------------------------------------------- |
| `BattleCreateData`                    | Stored as `battleFsm.battleCreateData`; transitions `GameFsm` into battle. |
| `BattleSyncData`                      | Opponent's turn hash + state — fed into `BattleStateNextTurn`.             |
| `BattleMoveData` / `BattleActionData` | Animates the opponent's move/action on the local board.                    |
| `BattleKilledData`                    | Removes a unit from the local board; checks endgame.                       |
| `BattleFinishedData`                  | Triggers `BattleStateFinished` — endgame screen + renown award.            |
| `BattleSurrenderData`                 | Triggers `BattleStateSurrender` on the opponent side.                      |
| `BattleAbortedData`                   | Mid-battle disconnect — triggers `BattleStateAborted`.                     |
| `BattleExitData`                      | Other side cleanly exited; finalize.                                       |

Server side: `pushData(...items)` in `bsf-server/src/services/auth/auth.ts` ([local](../../bsf-server/src/services/auth/auth.ts) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/src/services/auth/auth.ts)). See `bsf-server/docs/gameFlow.md` ([local](../../bsf-server/docs/gameFlow.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/gameFlow.md)) for the server's view of this sequence.

## Endgame — what `BattleFinishedData` carries

When a battle ends server-side, the server writes the ranking/renown rows then sends `BattleFinishedData` to both players via the long-poll. The client's `BattleStateFinished` reads:

- `winner` — `account_id` of the winning side (32-bit).
- `loser` — `account_id` of the losing side.
- `total_renown` — flat number to display ("you earned N renown").
- `aliveUnits` — final unit-alive map per player (for the result screen).
- (M1.5 target) per-award-type renown breakdown (UNDERDOG / STREAK / BOOST / EXPERT / DAILY / KILLS).
- (M1.5 target) new Elo on each side. Today the server stores the new Elo to the `ranking` table but does not surface it in `BattleFinishedData`.

The endgame screen rendering lives under `game/view/...battle...` (UI layer — out of scope for this doc).

## Common desync patterns

**Where to start:** the client that spots the mismatch logs `BattleSyncData DIVERGENCE detected at turn N` and drops into `BattleStateError` (see "Per-turn DJB hash" above). That line is the entry point — it names the turn, and it appears in the *client* log, not the server's.

When a battle desyncs at turn 0, the cause is almost always one of:

1. **Different `account_id`s between sides** — see [Entity ID format](#entity-id-format--the-lockstep-contract). Confirm both clients log the same `Credentials.userId` for the opponent (`Credentials.sessionKey` log line at `Credentials.as:126`).
2. **Different unit_def_ids** — usually because one party's `defs[]` (server-side) is out of date. Force-reload the party from `/account/info`.
3. **Different RNG seeds** — both clients should log `Turn Hash:` with the same `hashStr` for the same turn. If `hashStr` matches but `hash` differs, that's a `Hash.DJBHash` implementation bug (extremely unlikely — both sides use the same compiled SWF).

If `hashStr` differs between clients, walk the per-entity lines until you find the diverging one — that entity is the desync source.

## Related reading

- [`wire-protocol.md`](./wire-protocol.md) — every `/services/battle/*` route from the client side.
- `bsf-server/docs/gameFlow.md` ([local](../../bsf-server/docs/gameFlow.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/gameFlow.md)) — server-side battle lifecycle prose (`pushData` order, endgame computation, renown formula).
- `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) — wire-format DTOs (some battle messages are WIP).
- `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) Items 4–5 — entity IDs, DJB hash, long-poll behavior.
- [`reference-codebases.md`](./reference-codebases.md) — why battle code is read from `client-decompiled-as3` and not `client-2013-as3`.
