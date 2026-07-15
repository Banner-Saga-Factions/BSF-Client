# Wire protocol (client side)

## Co-Authored-By: Claude <noreply@anthropic.com>

The client side of every `/services/*` route — which AS3 class issues the request, what fields go on the wire, which class consumes the response.

This is the opposite-direction mirror of `bsf-server/docs/protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)), which maps the same routes to their Java handlers. The two docs are linked route-by-route in the tables below.

For server-side request/response shapes, see `bsf-server/docs/serverEndpoints.md` ([local](../../bsf-server/docs/serverEndpoints.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/serverEndpoints.md)) and `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)). For battle-flow specifics, see [`battle-engine.md`](./battle-engine.md).

## Anatomy of every request

Every server call is built from `HttpJsonAction` (`engine/core/http/HttpJsonAction.as`). The common pattern, from `game/session/actions/AuthTxn.as:28`:

```actionscript
super("services/auth/login/" + credentials.protocolVersion,
      HttpRequestMethod.POST,
      body,        // JSON-serialized
      callback,    // Function — invoked with parsed JSON response
      logger);
```

Three things determine the final URL:

1. **The path prefix** — `services/<group>/<action>` (e.g. `services/roster/unit/hire`).
2. **`credentials.urlCred`** — `"/" + sessionKey` (`Credentials.as:133–136`). Appended to every authenticated path. Login is the exception: it sends `"/" + protocolVersion` (currently `"/11"`) instead, because there is no session yet.
3. **Per-call suffix** — a few routes add more segments (e.g. `services/session/steam/overlay{urlCred}/{flag}`).

Final form: `<hostUrl>/services/<path><urlCred>[/<suffix>]`. The `<hostUrl>` is set by `GameConfig.setupHosts()` (`game/cfg/GameConfig.as:1222`) or overridden by `--server` (see [`architecture.md`](./architecture.md) → "Boot sequence").

## Auth

| Route                                         | Client class                        | Method | Notes                                                                                                                                                                                                                                                                                                                                      |
| --------------------------------------------- | ----------------------------------- | ------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/auth/login/{protocolVersion}` | `game/session/actions/AuthTxn.as`   | POST   | Body: `{username, password, child_number, steam_id, steam_auth_ticket, display_name, client_config}` (lines 17–26). Response sets `credentials.userId`, `vbb_name`, `displayName`, `sessionKey`, `buildNumber` (lines 47–56). Server side: `protocol-cross-reference.md` → Auth ([local](../../bsf-server/docs/protocol-cross-reference.md#auth) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#auth)). |
| `POST /services/auth/logout{urlCred}`         | `game/session/actions/LogoutTxn.as` | POST   | Body: `{}` (the urlCred carries the session).                                                                                                                                                                                                                                                                                              |

### Login flow walkthrough

1. **`PreAuthState.handleEnteredState`** (`game/session/states/PreAuthState.as:18`) fires when the client transitions to pre-auth. It either:
   - Reads a real Steam ticket (`SteamUser_GetAuthSessionTicketHandle()` + `SteamUser_GetAuthSessionTicket(handle)` at lines 38–42), or
   - Uses the `overrideSteamId` bypass (lines 31–34) — sets `steamAuthTicket = "override-authticket"`. **This is the crossplay patch point**: the BSF Discord OAuth flow replaces that bypass string with a real Discord OAuth token.
2. **`credentials.commit()`** dispatches `Credentials.EVENT_COMMITTED`. The state listens (line 25) and on a valid `Credentials` transitions to `StatePhase.COMPLETED`.
3. **`GameFsm`** advances to `LoginQueueState` → `AuthState`, which constructs an `AuthTxn` with the credentials.
4. **`AuthTxn`** POSTs the body at lines 17–26 to `services/auth/login/11`. On 200, `handleJsonResponseProcessing` (lines 31–59) writes the response fields back into `credentials`.
5. **`credentials.sessionKey = ...`** at line 52 (the line comment explicitly says `set session key last`) is the gate — Credentials becomes `valid` once both `sessionKey` and `userId` are set, fires `EVENT_COMMITTED` again, and `AuthState` transitions to the main-menu lifecycle.

**32-bit constraint:** `credentials.userId` is declared `int` (`Credentials.as:20`) — a 32-bit signed integer. The server's `user_id` field **must fit in 32 bits**. Full 64-bit Steam IDs (`>= 76561197960265728`) are reduced by `bsf-server` to `userId - 76561197960265728` before being sent to the client (see `bsf-server/CLAUDE.md` ([local](../../bsf-server/CLAUDE.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/CLAUDE.md)) and root `.claude/rules/gotchas.md`). Discord snowflakes go through the same reduction pattern.

The `"11"` in `/services/auth/login/11` is the **protocol version** (`credentials.protocolVersion`), not a magic constant. It happens to match the only protocol version the shipped SWF sends, which is why `bsf-server` can hardcode it as the unauthenticated-bypass sentinel.

## Account

| Route                                      | Client class                                   | Method                                                      |
| ------------------------------------------ | ---------------------------------------------- | ----------------------------------------------------------- |
| `GET /services/account/info{urlCred}`      | `game/session/actions/AccountInfoTxn.as`       | GET                                                         |
| `POST /services/account/tutorial{urlCred}` | `game/session/actions/TutorialCompletedTxn.as` | POST — empty body. **Currently 404 on `bsf-server`** (M3a). |

`AccountInfoTxn` is the source of truth for the client's roster, party, currency, friends list, daily-login state, and purchasable units. See `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) → `AccountInfoData`.

## Roster

All under `services/roster/...{urlCred}`. All POST.

| Route                                         | Client class                                               |
| --------------------------------------------- | ---------------------------------------------------------- |
| `services/roster/party/arrange`               | `ArrangePartyTxn.as`                                       |
| `services/roster/unit/hire`                   | `PurchaseRosterUnitTxn.as`                                 |
| `services/roster/unit/promote`                | `PromoteUnitTxn.as`                                        |
| `services/roster/unit/rename`                 | `RenameUnitTxn.as`                                         |
| `services/roster/unit/retire`                 | `RetireRosterUnitTxn.as`                                   |
| `services/roster/unit/stats/purchase`         | `PurchaseStatsTxn.as`                                      |
| `services/roster/unit/stats/reset`            | `ResetStatsTxn.as`                                         |
| `services/roster/unit/variation/{id}/{x}/{y}` | `UnitVariationTxn.as` — **n/a on `bsf-server`** (no route) |
| `services/roster/unlock`                      | `RosterRowUnlockTxn.as`                                    |

Server side: `protocol-cross-reference.md` → Roster ([local](../../bsf-server/docs/protocol-cross-reference.md#roster) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#roster)).

## Battle

All under `services/battle/...{urlCred}`. All POST. Server side: `protocol-cross-reference.md` → Battle ([local](../../bsf-server/docs/protocol-cross-reference.md#battle) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#battle)). Client implementation lives in `engine/battle/fsm/txn/` (engine layer — not under `game/session/actions/`).

| Route                       | Client class                | Sent from FSM state                          |
| --------------------------- | --------------------------- | -------------------------------------------- |
| `services/battle/ready`     | `BattleTxnStartSend.as`     | `BattleStateInit`                            |
| `services/battle/deploy`    | `BattleTxnDeploySend.as`    | `BattleStateDeploy`                          |
| `services/battle/sync`      | `BattleTxnTurnInitSend.as`  | `BattleStateNextTurn`                        |
| `services/battle/query`     | `BattleTxnQuery.as`         | Various — read-only state probe              |
| `services/battle/move`      | `BattleTxnMoveSend.as`      | `BattleStateTurnLocal`                       |
| `services/battle/action`    | `BattleTxnActionSend.as`    | `BattleStateTurnLocal`                       |
| `services/battle/killed`    | `BattleTxnKillSend.as`      | `BattleStateTurnLocal` (after a kill)        |
| `services/battle/exit`      | `BattleTxnExitSend.as`      | `BattleStateFinished` / `BattleStateAborted` |
| `services/battle/surrender` | `BattleTxnSurrenderSend.as` | `BattleStateSurrender`                       |

The battle FSM transition graph and message bodies are documented in [`battle-engine.md`](./battle-engine.md).

## Versus / queue

| Route                               | Client class                                  |
| ----------------------------------- | --------------------------------------------- |
| `POST /services/vs/start{urlCred}`  | `VersusStartMatchTxn.as`                      |
| `POST /services/vs/cancel{urlCred}` | `VersusCancelTxn.as` — body: `{match_handle}` |

Server side: `protocol-cross-reference.md` → Versus / queue ([local](../../bsf-server/docs/protocol-cross-reference.md#versus--queue) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#versus--queue)). Matchmaking math is still M2 on the server side — see `bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md` ([local](../../bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md)).

## Game (long-poll + misc)

| Route                                       | Client class               | Method | Notes                                                                  |
| ------------------------------------------- | -------------------------- | ------ | ---------------------------------------------------------------------- |
| `GET /services/game{urlCred}`               | `engine/session/TxnGet.as` | GET    | **The long-poll.** See "Long-poll mechanics" below.                    |
| `POST /services/game/leaderboards{urlCred}` | `LeaderboardsTxn.as`       | POST   | Server returns static `data/lboard.json` today.                        |
| `POST /services/game/location{urlCred}`     | `GameLocationTxn.as`       | POST   | Reports the player's current in-game location (saga camp, town, etc.). |

### Long-poll mechanics

`TxnGet` (`engine/session/TxnGet.as:13`) issues the GET. The HTTP client is `HttpCommunicator` (`engine/core/http/HttpCommunicator.as`).

Key constants and behaviors:

- **`DEFAULT_POLL_TIME = 3000`** (line 18) — the **client request timeout** (not a sleep). The server may hold the connection for up to 10 s; if the client's 3-s timeout fires first, the request aborts and `fetchHandler` immediately starts a new one.
- **`fetchHandler` → `checkPoll()`** (lines 143–147 + 119–141) — on any response (success, empty array, error, or timeout) the next request fires immediately. **No back-off.**
- **Error rules** (`HttpCommunicator.as:43–50`):
  - status `0` (network failure) — notice error, retry.
  - status `>= 401` and `!= 500` — notice error, retry.
  - status `500` — treated as **alive** (server is up but degraded; client does not back off).
- **`setPollTimeRequirement(id, ms)`** (line 168–172) — any subsystem can register a tighter poll. The minimum across all registrants wins (`resetPollTime`, line 180–193). During a battle, `BattleFsm.startFsm` (`engine/battle/fsm/BattleFsm.as:374`) registers `1000` ms, dropping the poll cadence from 3 s to 1 s.

**What "the server pushes data" actually means:** the server holds an open GET, and when it has data to deliver it writes the response and closes. The client decodes the JSON array, hands each entry to a registered handler keyed on a `type` discriminator (`BattleCreateData`, `MatchCreated`, `BattleFinishedData`, etc. — see `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md))), then immediately fires a new GET. Server side: `pushData()` in `bsf-server/src/services/auth/auth.ts`.

### Mobile network transitions

When Wi-Fi drops or the device switches to cellular, the in-flight `TxnGet` fails with status `0`. `fetchHandler` fires → `checkPoll()` → new `TxnGet` is issued **instantly with no delay**. The user sees no visible interruption beyond a single missed push.

`HttpErrorState` tracks consecutive errors for UI display (the "reconnecting…" banner) but does not insert back-off. See `Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) Item 5.

## Chat

| Route                                 | Client class                    | Notes                                                                                                                                      |
| ------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/chat/{room}{urlCred}` | `engine/session/ChatSendTxn.as` | Room is path-segment-encoded. Server side: `protocol-cross-reference.md` → Chat ([local](../../bsf-server/docs/protocol-cross-reference.md#chat) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#chat)). |

## Lobby

| Route                                    | Client class                                                                                                                               |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/lobby/{action}{urlCred}` | `game/session/actions/LobbyTxn.as` (catch-all — 8 actions: `invite`, `uninvite`, `exit`, `join`, `decline`, `options`, `ready`, `unready`) |
| `POST /services/lobby/invite{urlCred}`   | `LobbyInviteTxn.as` (specialized)                                                                                                          |
| `POST /services/lobby/options{urlCred}`  | `LobbyOptionsTxn.as` (specialized)                                                                                                         |

The server currently has a single 200-OK catch-all for `/services/lobby/...` (M3b — see `bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md` ([local](../../bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Integrate-Original-Stoic-Server.md)) Blocker #9). The 8 actions are implemented on the client and waiting for server-side support.

## Session

| Route                                                  | Client class                                     | Notes                                                                                                                                                  |
| ------------------------------------------------------ | ------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/session/steam/overlay{urlCred}/{flag}` | `game/session/actions/SessionSteamOverlayTxn.as` | The `{flag}` is `true` or `false` (Steam overlay opened/closed). Server side: special-cased no-op pass-through allowlist in `bsf-server/src/index.ts` ([local](../../bsf-server/src/index.ts) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/src/index.ts)). |

## Tournament (server M7+)

| Route                                  | Client class        | Notes                                                  |
| -------------------------------------- | ------------------- | ------------------------------------------------------ |
| `POST /services/tourney/join{urlCred}` | `TourneyJoinTxn.as` | **n/a on `bsf-server`** today; tournament work is M7+. |

## Discord OAuth (BSF-only, outside `/services`)

These routes do **not** flow through `HttpCommunicator` — they are AIR `URLLoader` calls or browser-side links handled by the `bsf://` URL scheme that the AIR descriptor (`META-INF/AIR/application.xml`) is **planned** to register — not yet in the committed descriptor.

| Route                               | Used by                                   | Notes                                                     |
| ----------------------------------- | ----------------------------------------- | --------------------------------------------------------- |
| `GET /login/discord/`               | Browser link from in-client button        | Redirects the user's browser to Discord OAuth.            |
| `GET /login/discord/oauth-callback` | Discord redirect                          | Server sets a one-shot `bsf_oauth_state` cookie (CSRF).   |
| `POST /login/discord/session`       | (BSF-server-only, no client analogue yet) | Exchanges OAuth code for a `session_key` — currently 501. |
| `bsf://oauth?...`                   | OS deep-link → AIR                        | Delivers the OAuth result back to the running client.     |

This flow is the subject of the parent repo's `bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md` ([local](../../bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Plan-Enable-Mobile-Windows-Crossplay.md)). The client-side patch surface will be the `bsf://` scheme registration (planned) and the `PreAuthState` bypass swap.

## Counting / sanity check

Every `/services/*` route in this doc has a matching row in `bsf-server/docs/protocol-cross-reference.md` ([local](../../bsf-server/docs/protocol-cross-reference.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md)), with three exceptions:

- `roster/unit/variation` — client has it, server does not (n/a).
- `account/tutorial` — client has it, server does not (M3a).
- `tourney/join` — client has it, server does not (M7+).

If any new route is added to the client without a corresponding server entry — or vice versa — that's a wire-protocol break and shows up as a 404 or 501. Verification step #3 in [`bsf-client/docs/README.md`](./README.md) runs the count both ways.

## Related reading

- `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — Items 1 (server URL), 2 (Steam auth), 3 (login response field names), 5 (long-poll mechanics) are cited above. Item 4 (entity naming + DJB hash) is covered in [`battle-engine.md`](./battle-engine.md). Item 6 (mobile OS branches) is covered in [`architecture.md`](./architecture.md).
- `bsf-server/docs/ARCHITECTURE.md` ([local](../../bsf-server/docs/ARCHITECTURE.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/ARCHITECTURE.md)) → "Endpoint Transport Map" — server-side classification of every route as direct / long-poll / plaintext-body.
- `bsf-server/docs/gameFlow.md` ([local](../../bsf-server/docs/gameFlow.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/gameFlow.md)) — battle-lifecycle prose (server side).
- [`subsystem-index.md`](./subsystem-index.md) — all Txn classes listed with package paths.
