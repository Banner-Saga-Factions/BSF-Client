# The match runner: measuring the offline opponent

## Co-Authored-By: Claude <noreply@anthropic.com>

Making the computer opponent "stronger" needs a number to judge it by. The **match runner** supplies it.
It starts the real game, plays the player's side of an offline practice battle with a fixed, simple
strategy, writes down who won, and goes again, as many times as you ask. Nobody needs to be at the
keyboard. Run it before and after a change to the opponent and compare the two.

It is `scripts/mod-host/runner.js`. It talks to the game over the mod bridge
([`mod-bridge.md`](./mod-bridge.md)), the text channel between the game and a helper program. It uses
the same start-up and shutdown machinery as the client's automated test (`tests/lib/game-session.js`,
described in [`driving-the-client.md`](./driving-the-client.md) §9). The plan it serves is
[`../misc/Plan-Improve-Battle-AI.md`](../misc/Plan-Improve-Battle-AI.md).

---

## 1. Running it

It needs what the automated test needs:

- the local server running on port 8082 (`bsf-server\start-server.bat`);
- `AIR_HOME` set;
- **our own build installed**: `scripts\build.ps1`, then copy `_build\app.game.air.swf` over the
  installed game's copy. The launcher refuses to start a build that is not ours.

From the `bsf-client` folder:

```powershell
node scripts\mod-host\runner.js                          # 10 battles, the plain player
node scripts\mod-host\runner.js --player armor-first      # 10 battles, the harder player
node scripts\mod-host\runner.js --battles 5 --out _build\runner\try-1
node scripts\mod-host\runner.js --summary-only _build\runner\try-1\runner-results.jsonl
```

A battle takes about 3½ minutes, so 10 battles is about 35 minutes. Close other programs first: one
long run was stopped by the PC running low on memory. The game window opens and plays
itself. Leave it alone: a click can steal a turn from the runner.

**Nothing needs installing in the game folder.** For the length of the run, the start-up machinery
points the game's helper setting (`mods\host.json`) at a small go-between, and it puts the old setting
back afterwards. `scripts\install-mod-host.ps1` is only for the hand-run `host.js`.

## 2. What it writes

Into the output folder (default `_build\runner\<date-time>\`):

| File | One line per | Holds |
| ---- | ------------ | ----- |
| `runner-results.jsonl` | battle | winner, turns, survivors per side, party, battle id, seconds, a fingerprint of how the battle went |
| `runner-turns.jsonl` | player turn | what it did, how many commands it sent, how many the game refused and why, how long it took |
| `runner-summary.txt` | run | the totals below, also printed at the end |
| `deploy-<n>.json` | battle | the whole board on the deploy screen |

The summary gives the computer's win rate and its average survivors. It also shows how many battles had
different dice and how fast turns were decided. Last, it counts the `Error #1009` and "Something went
wrong while faking" lines in the game's own log.

**That count comes from the game's own log, `A-<n>.log.txt`, and only after the game has closed.** The
log is locked while the game runs and renumbered at every start
([`driving-the-client.md`](./driving-the-client.md) §5). So the runner reads every one written since the
run began that mentions a practice battle. **The session's run log in `_build\tests\` is not the game's
log.** It holds only the runner's own notes, and the first version of the runner counted there and
reported "no `#1009`" from a file that could never contain one. As a check that the right file was read,
the summary also counts `Error #1508`, which every start under `adl` prints three times for the missing
sound extension. If those are missing, distrust the count beside them. If no log is found at all, the
summary says "NOT COUNTED" rather than zero.

## 3. The players it plays

Both players are fixed on purpose. A yardstick that changes is no yardstick.

**`strength`** (the default):

1. Attack the weakest enemy it can reach this turn (lowest strength first) with the basic strength
   attack. It attacks from where it stands, or after one move.
2. Otherwise, step toward the nearest enemy.
3. Otherwise, end the turn.

**`armor-first`** is the same player with one more rule. When a strength hit would do 1 damage or
less, it uses the armor attack instead. That rule matters more than it sounds. **Armor soaks up a
strength hit.** The damage is roughly the attacker's strength minus the target's armor
(`Op_DamageStr` in the decompile uses armor as the defence). In a party where most units have armor 9
and strength 9 to 12, the plain player mostly chips. The computer opponent breaks armor first.

How it finds a tile to attack from: it works out every tile within its movement from which the game's
own range rule says the target can be hit. That rule measures the gap between the two blocks of tiles
the units cover, not between their corners (`TileRectRange.computeRange`). It then asks the game to
move to each tile in turn, shortest walk first, until one is accepted. The game has the last word: a
tile it cannot reach comes back refused with a reason, and the runner tries the next.

## 4. What the first runs settled (2026-10-16)

The plan asked three questions that only running the game could answer.

**Can the game start a second battle without a restart? Yes.** `start_ai_battle` from the finished
battle's screen loads a new battle. Each later battle reached the deploy screen in 2 to 3½ seconds,
against 11 to 12 for the first after login. Every battle in every run so far started this way: 13
battles across three runs, and no restart was ever needed. The runner can still
restart the game if a battle ever fails to start, and the summary counts any restarts.

**Does each battle get new dice? Yes, though not through the battle id.** An offline battle has no id:
`battle_state` reports `battleId: null` every time. With no id, the game seeds its dice from the clock
(`BattleBoard.set sim`: `seedRng = getTimer()`, the milliseconds since the game started). So each battle
gets a different seed anyway. Measured: every battle's fingerprint differed (3 of 3 in a probe run, then 8
of 8 in the baseline). The fingerprint records who acted on each player turn and every unit's strength and
armor at that moment. Both players and the opponent are deterministic, so differing fingerprints mean
differing dice.

**Is finding a tile by trial and refusal fast enough? Yes. No `battle_reachable` command is needed.**
A refused move or attack comes back in a few milliseconds. Across the baseline's 253 turns, a turn took
a median of 4 commands and at worst 26. Most of a turn's time is spent waiting for the unit to finish walking (about
two tiles a second), not choosing. What *did* need fixing was not speed but aim. Without knowing how big
each unit is, 4 of the first 28 turns moved to a tile and then could not attack from it. So
`battle_state` now reports each unit's `size` ([`mod-bridge.md`](./mod-bridge.md) §5), and with it
wasted moves dropped to 0 (0 of 86 in a probe run, 0 of 253 in the baseline).

## 5. Traps

- **Do not close the game while a unit is walking.** It hangs the game on the way out (issue #36). The
  runner waits for a walk to finish before ending a turn, and closes only on a still board.
- **A battle with no winner after 400 turns is recorded as `unfinished`.** It is not counted for either
  side. Change the cap with `--turn-cap`.
- **The party decides the match-up.** Both sides are a copy of the logged-in account's active party
  (`test2` by default). A different party gives different numbers, so compare runs on the same account.
- **The opponent mirrors your party unit for unit, including any Shieldbanger**, whose missing strength
  attack is behind crash `#1009`. The summary counts those lines.
