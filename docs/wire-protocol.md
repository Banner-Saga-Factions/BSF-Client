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

`AccountInfoTxn` is the source of truth for the client's roster, party, currency, daily-login state, and purchasable units. It does **not** carry the friends list — `AccountInfoDefVars` has no such field, and friends arrive on the long poll as `tbs.srv.data.FriendsData`. See `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md)) → `AccountInfoData`.

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
| `services/roster/unit/variation{urlCred}/{unit_id}/{variation}/{lobby_id}` | `UnitVariationTxn.as` — **n/a on `bsf-server`** (no route). The session key is **not** last here. The trailing part is the **lobby id**, which the 2013 server used to tell the other player in the room that the unit had changed appearance. A player who is not in a room still sends a real number here — the client falls back to a personal lobby keyed to the player's own id — so do **not** expect `0` for the solo case, even though `0` is what the 2013 server treated as "no room to notify". |
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
| `POST /services/game/location{urlCred}`     | `GameLocationTxn.as`       | POST   | Reports which screen the player is on — saga camp, town, and the battle screen, including an offline practice battle. |

### Long-poll mechanics

`TxnGet` (`engine/session/TxnGet.as:13`) issues the GET. The HTTP client is `HttpCommunicator` (`engine/core/http/HttpCommunicator.as`).

Key constants and behaviors:

- **`HttpCommunicator.DEFAULT_POLL_TIME = 3000`** — a **sleep before the next poll is sent**, not a request timeout. `checkPoll` passes it to `HttpAction.send` as that method's *pre-send delay* argument, and `send` starts a `Timer` and **returns without sending** — the same argument slot a failed request's `resendOnFailDelayMs` uses. So the client waits 3 s, *then* issues the poll.
- **`fetchHandler` → `checkPoll()`** — on any response (success, empty array, error, or timeout) the next poll is queued behind that same 3-s delay. **The gap never grows** — there is no escalating back-off — but it is not zero either.
- **Consequence for the server side:** the client is *not* racing the server's hold. `bsf-server` holds a poll up to **5 s** (not 10 — see the note below), and a captured battle showed 85% of polls reaching that full 5 s, which is only possible because the client is content to wait. Worst-case latency for a server-pushed message is therefore **the gap** (3 s, or 1 s in an online battle) — a message pushed while a poll is already open goes out immediately.
- **Two different rules, easy to confuse.** What raises the "reconnecting…" banner and what gets
  re-sent are decided in different places, and they disagree:
  - **Banner** (`HttpCommunicator`, on **every** request, not just the poll): a status of `0`, or
    anything `401` and above **except exactly `500`**. So a refused poll (`429`) counts as an error
    towards it; a `500` does **not** — a `500` reads as "server alive". One error on its own shows
    nothing, though: see "Mobile network transitions" below for what it takes.
  - **Re-send** (`HttpAction.canRetry`): only `0`, `404`, or `500` and above — and never a maintenance
    reply, meaning a `503` whose body says the server is down for maintenance or rebooting. So `403`
    and `429` are never re-sent, while `500` always is.
  - They overlap only partly: `404` does both, `429` counts towards the banner but is dropped, and
    `500` is re-sent silently — for the kinds of request that opt in, which is not all of them.
- **`setPollTimeRequirement(id, ms)`** — any subsystem can register a tighter poll. The minimum across all registrants wins (`resetPollTime`). During an **online** battle, `BattleFsm.startFsm` registers `1000` ms, dropping the gap from 3 s to 1 s, and each turn boundary registers a tighter `700` ms. Both registrations are skipped when the battle is offline, so an offline practice battle keeps the 3 s default.

> **How long does the server hold it?** `bsf-server` holds **5 s** (`bsf-server/src/services/game.ts:98`). An earlier version of this doc said "up to 10 s", inherited from `Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) Item 5 — that figure describes the **original 2013 Stoic server**, not ours. Server-side detail: `bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R7–R9.

**What "the server pushes data" actually means:** the server holds an open GET, and when it has data to deliver it writes the response and closes. The client decodes the JSON array, hands each entry to a registered handler keyed on a `type` discriminator (`BattleCreateData`, `MatchCreated`, `BattleFinishedData`, etc. — see `bsf-server/docs/dataStructures.md` ([local](../../bsf-server/docs/dataStructures.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/dataStructures.md))), then immediately fires a new GET. Server side: `pushData()` in `bsf-server/src/services/auth/auth.ts`.

### Mobile network transitions

When Wi-Fi drops or the device switches to cellular, the in-flight `TxnGet` fails with status `0`. `fetchHandler` fires → `checkPoll()` → a new `TxnGet` is queued behind the usual poll gap (3 s, or 1 s in an online battle) — **not instantly**, but with no escalating back-off either, so recovery is prompt and the user sees no interruption beyond a missed push or two.

The "reconnecting…" banner is **not** a running count of errors, and it never inserts a back-off. It is a two-stage machine (`HttpErrorState`), both stages timed at five seconds:

- The first error puts the client on **probation**. Nothing is shown.
- The banner appears only if a further error arrives **more than five seconds after probation started**. A burst of errors inside that window stays on probation, and stays silent.
- **A single success clears probation immediately**, with no timing test — so an isolated failure followed by any success never reaches the banner at all.
- Leaving the banner is stricter than reaching it: it needs a success arriving more than five seconds after the *last* error, and every new error pushes that deadline out.

What this means for the server is written up in `bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R21.

## Chat

| Route                                 | Client class                    | Notes                                                                                                                                      |
| ------------------------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/chat/{room}{urlCred}` | `engine/session/ChatSendTxn.as` | Room is path-segment-encoded. Server side: `protocol-cross-reference.md` → Chat ([local](../../bsf-server/docs/protocol-cross-reference.md#chat) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/protocol-cross-reference.md#chat)). |

## Lobby

| Route                                    | Client class                                                                                                                               |
| ---------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| `POST /services/lobby/{action}{urlCred}` | `game/session/actions/LobbyTxn.as` — one class, six actions: `uninvite`, `exit`, `join`, `decline`, `ready`, `unready` |
| `POST /services/lobby/invite{urlCred}`   | `LobbyInviteTxn.as` (specialized)                                                                                                          |
| `POST /services/lobby/options{urlCred}`  | `LobbyOptionsTxn.as` (specialized)                                                                                                         |

All eight lobby routes are implemented on both sides — server side, `bsf-server/src/services/lobby.ts` ([local](../../bsf-server/src/services/lobby.ts) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/src/services/lobby.ts)). **Joining is the only one whose refusals this client could re-send.** A room the server no longer has is answered `409`; a room you were not invited to is answered `403`. This client re-sends neither. The other seven routes answer `200` against a room that is gone, so they never had the problem. Both join codes were `404` until 2026-08-18 — a code this client *does* re-send, with no attempt cap — see `bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R23. Note two things a refusal does **not** do: it does not move the player off the lobby screen — `Lobby.join` marks itself joined and switches screens *before* it sends, and nothing undoes that on a refusal — and it is not what you get after a server restart, because a session the server no longer recognises is refused by its front gate before any lobby code runs.

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

If any new route is added to the client without a corresponding server entry — or vice versa — that's a wire-protocol break.

> ⚠ **A missing route does not fail quietly — it fails forever.** **Twenty-five concrete kinds of request, across thirty routes**, re-send on failure (the full list is in [`mod-bridge.md`](./mod-bridge.md) → "The HTTP tap"), and `HttpAction.canRetry` re-sends on response code `0`, `404`, or `>= 500` with **no attempt cap**, every 1–2 s. So a route the client knows and the server answers `404` puts the client in a permanent re-send loop for the life of the process. Of the three gaps above, **`tourney/join` does exactly this** — its session key is the last path segment, so it passes the server's session check and then matches no route. `roster/unit/variation` escapes only by accident: its session key is the **fourth** segment once the `/services` prefix has been stripped — the form the server's own check sees — and the **fifth** as the client sends it (`/services/roster/unit/variation/{key}/{unit_id}/{variation}/{lobby_id}`). So the server rejects it with `403` first, and `403` is not re-sent. `account/tutorial` is safe because `TutorialCompletedTxn` does not opt into re-sending. The server-side rule this implies — never answer a permanent "no" with `404` or `5xx` — is tracked in BSF-Custom-Server #164 and written up in `bsf-server/docs/client-contract.md` ([local](../../bsf-server/docs/client-contract.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/client-contract.md)) → R10.

## Related reading

- `bsf-server/misc/Findings-Client-ActionScript-Crossplay.md` ([local](../../bsf-server/misc/Findings-Client-ActionScript-Crossplay.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/misc/Findings-Client-ActionScript-Crossplay.md)) — Items 1 (server URL), 2 (Steam auth), 3 (login response field names), 5 (long-poll mechanics) are cited above. Item 4 (entity naming + DJB hash) is covered in [`battle-engine.md`](./battle-engine.md). Item 6 (mobile OS branches) is covered in [`architecture.md`](./architecture.md).
- `bsf-server/docs/ARCHITECTURE.md` ([local](../../bsf-server/docs/ARCHITECTURE.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/ARCHITECTURE.md)) → "Endpoint Transport Map" — server-side classification of every route as direct / long-poll / plaintext-body.
- `bsf-server/docs/gameFlow.md` ([local](../../bsf-server/docs/gameFlow.md) | [GitHub](https://github.com/Banner-Saga-Factions/BSF-Custom-Server/blob/main/bsf-server/docs/gameFlow.md)) — battle-lifecycle prose (server side).
- [`subsystem-index.md`](./subsystem-index.md) — all Txn classes listed with package paths.
