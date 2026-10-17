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

- the local server running on port 8082 (`bsf-server\start-server.bat`, or `node build\index.js` from
  `bsf-server` when other programs are running: see §5);
- `AIR_HOME` set;
- **our own build installed**: `scripts\build.ps1`, then copy `_build\app.game.air.swf` over the
  installed game's copy. The launcher refuses to start a build that is not ours.

From the `bsf-client` folder:

```powershell
node scripts\mod-host\runner.js                          # 10 battles, the plain player
node scripts\mod-host\runner.js --player armor-first      # 10 battles, the second player
node scripts\mod-host\runner.js --battles 5 --out _build\runner\try-1
node scripts\mod-host\runner.js --player armor-first --speed 4  # the same, played about twice as fast
node scripts\mod-host\runner.js --seed 1234               # repeat an earlier run's choices exactly
node scripts\mod-host\runner.js --variety 0               # the fixed play of the first runs (§3)
node scripts\mod-host\runner.js --steam-id 443456         # sign in as another local account (§5)
node scripts\mod-host\runner.js --summary-only _build\runner\try-1\runner-results.jsonl
```

Every run prints its **seed**, the number its random choices start from (§3). Pass it back with `--seed`
to play the same choices again. The seed, the account and the variety are on every results line and in
the summary.

A battle takes about 3½ minutes at normal speed, so 10 battles is about 35 minutes. With `--speed 4` it
takes about 1½ minutes (§4). Close other programs first: one long run was stopped by the PC running low
on memory. The game window opens and plays
itself. Leave it alone: a click can steal a turn from the runner.

**Nothing needs installing in the game folder.** For the length of the run, the start-up machinery
points the game's helper setting (`mods\host.json`) at a small go-between, and it puts the old setting
back afterwards. `scripts\install-mod-host.ps1` is only for the hand-run `host.js`.

## 2. What it writes

Into the output folder (default `_build\runner\<date-time>\`):

| File | One line per | Holds |
| ---- | ------------ | ----- |
| `runner-results.jsonl` (`.jsonl`: one JSON record per line, JSON being plain text for structured data) | battle | winner, turns, survivors per side, party, battle id, seconds, speed, account, seed and variety, the computer's suicides, a fingerprint of how the battle went |
| `runner-turns.jsonl` | player turn | what it did, how many commands it sent, how many the game refused and why, how long it took |
| `runner-summary.txt` | run | the totals below, also printed at the end |
| `deploy-<n>.json` | battle | the whole board on the deploy screen |

The summary gives the computer's win rate and its average survivors. It also shows how many battles
played out differently (§4 explains why that number matters), seconds per turn, and how fast turns
were decided.

It also counts the computer's **suicides**: a computer unit that walked up during the computer's turns,
in a stretch where the computer killed none of ours, and then died to the runner's very next attack. In
plain terms, it walked into a free kill. Issue #31 uses this count to decide whether the opponent needs a
rule against it. It undercounts on purpose: a unit the simple player could have killed but did not pick
is not counted. It can also overcount: any computer unit that changed tiles qualifies, so a wounded unit
stepping back counts too. Result files written before the count existed say "not counted" rather than 0. Last, it counts the `Error #1009` and "Something went
wrong while faking" lines in the game's own log.

**That count comes from the game's own log, `A-<n>.log.txt`, and only after the game has closed.** The
log is locked while the game runs and renumbered at every start
([`driving-the-client.md`](./driving-the-client.md) §5). So the runner reads every one written since the
run began that mentions a practice battle. **The session's run log in `_build\tests\` is not the game's
log.** It holds only the runner's own notes, and the first version of the runner counted there and
reported "no `#1009`" from a file that could never contain one. As a check that the right file was read,
the summary also counts `Error #1508`, which every start under `adl` (the AIR SDK's test launcher)
prints three times for the missing sound extension. Two of the eight practice-battle logs from
2026-10-16 had none, so a shortfall means "check which file was read", not "the count is wrong". If no
log is found at all, the summary says "NOT COUNTED" rather than zero. If the number of logs found
differs from the number of games the runner started, it adds a WARNING line.

## 3. The players it plays

Both players follow fixed rules on purpose. A yardstick that changes is no yardstick. But fixed rules
on both sides made battles replay move for move (§4), so since issue #31's Wave 3a each player varies
*which* option it takes among near-equals, without changing its rules:

- **Exact ties are broken at random.** Before, two equally weak enemies, or two tiles equally far away,
  were ordered by name or by position.
- **At each choice, now and again, it takes its second-best option.** The three choices are which enemy
  to go for, which tile to attack from, and which tile to step to. "Now and again" is `--variety`: 25
  times in 100 by default.
- **The random numbers come from the run's seed**, and each battle gets its own numbers from the seed and
  the battle's number. So one battle can be replayed on its own: same seed, same battle number.
- **`--variety 0` plays exactly as the first runs did**, with no randomness at all. Use it to compare with
  rows recorded before Wave 3a.

The variety makes the player slightly weaker than its strict rule, so compare varied runs with varied
runs.

**`strength`** (the default):

1. Attack the weakest enemy it can reach this turn (lowest strength first) with the basic strength
   attack. It attacks from where it stands, or after one move.
2. Otherwise, step toward the nearest enemy.
3. Otherwise, end the turn.

**`armor-first`** is the same player with one more rule. When a strength hit would do 1 damage or
less, it uses the armor attack instead, because armor soaks up a strength hit (`Op_DamageStr` in the
decompile uses armor as the defence). It is a far harder yardstick: against the unchanged computer it won
2 of 4 battles, where the plain player won 0 of 8 (the plan's *Measurements* table). One thing to know
when reading its numbers: in the 8-battle baseline's game log the computer chose
162 strength attacks and 29 armor attacks, and 134 of those 191 were at level 2 or higher, the game's
higher levels of an attack. Both scripted players only ever use level 1.

How it finds a tile to attack from: it works out every tile within its movement from which the game's
own range rule says the target can be hit. That rule measures the gap between the two blocks of tiles
the units cover, not between their corners (`TileRectRange.computeRange`). It then asks the game to
move to each tile in turn, shortest walk first, until one is accepted. The game has the last word: a
tile it cannot reach comes back refused with a reason, and the runner tries the next.

## 4. What the first runs settled (2026-10-16)

The plan asked three questions that only running the game could answer.

**Can the game start a second battle without a restart? Yes.** `start_ai_battle` from the finished
battle's screen loads a new battle. Each later battle reached the deploy screen within a few seconds,
against more than ten for the first after login. Every battle in every run so far started this way: 14
finished battles across four runs, and no restart was ever needed. The runner can restart the game if a
battle ever fails to start, and the summary counts any restarts, but that path has never run.

**Does each battle get new dice? Yes, though not through the battle id, and new dice often change
nothing.** An offline battle has no id: `battle_state` reports `battleId: null` every time. With no id,
the game seeds its dice from the clock (`BattleBoard.set sim`: `seedRng = getTimer()`, the milliseconds
since the game started), so each battle gets a different seed. The fingerprint records who acted on each
player turn and every unit's strength and armor at that moment. In the first runs every battle's
fingerprint differed (3 of 3 in a probe run, then 8 of 8 in the baseline).

**Corrected the same day: battles often repeat exactly.** Later runs found identical fingerprints:
battles 1 and 3 of the 4-battle `armor-first` baseline, and 4 of the 5 battles on the Wave 2 build.
All four baseline battles matched for their first 14 turns. Damage is mostly fixed arithmetic and both
sides choose by fixed rules, so a different seed changes a battle only when a roll actually decides
something. Rolls rarely do: a basic strength attack rolls the dice only when the target's armor would
bring the hit to 0 or below, and then only as a chance to miss (`Op_DamageStr.as:126-141`). The other
places in the battle code that roll are particular abilities (`OpDef_ExecAbility`, `Op_BloodyFlail`,
`Op_SlagAndBurnTileCross`) that these runs' basic attacks never use. Found in the Wave 2 review.
**So N battles are not N independent samples.**
Read the summary's "distinct battle traces" before trusting a win rate.

**Fixed in issue #31's Wave 3a: with the varied player (§3), battles differ.** At the default variety
of 25, every battle differed in both 8-battle runs: 8 of 8 on `test2` and 8 of 8 on `443456`. The
"distinct battle ids" line still reads 1, because an offline battle's id is always null. Still read
"distinct battle traces" in every summary, and especially after `--variety 0`.

**Can it play faster? Yes, about twice as fast at `--speed 4`** (added in Wave 2, 2026-10-16). `--speed N` sends the
bridge's `set_game_speed` once the fighting starts and sets it back to 1 when the battle ends normally
([`mod-bridge.md`](./mod-bridge.md) §5). The game then moves its clock on N times faster each frame and
shortens the computer's built-in pauses; some of the game's timers run on real time and do not speed up.
**If the runner is stopped with Ctrl-C, the game window can stay open at the higher speed:
close it** before playing online ([BSF-Client #72](https://github.com/Banner-Saga-Factions/BSF-Client/issues/72)). One trial battle at ×4 took 1.64 seconds a turn, against 3.5 at
normal speed for the same scripted player: 94 seconds a battle instead of about 210. It finished
normally, with no `#1009` and no "went wrong while faking" lines. Four more battles at ×4 averaged 1.68
seconds a turn. ×8 was not tried. No battle of the Wave 2 opponent was run at normal speed, so
"speed changes timing, not decisions" rests on reading the code.

**Is finding a tile by trial and refusal fast enough? Yes. No `battle_reachable` command is needed.**
A refused move or attack comes back fast enough that trying again costs little. Across the baseline's
253 player turns, a turn took a median of 4 commands and at worst 26. Most of a turn's time is spent
waiting for the unit to finish walking (about two tiles a second), not choosing. What *did* need fixing
was not speed but aim. Without knowing how big each unit is, 4 of the first 28 player turns moved to a
tile and then could not attack from it. So
`battle_state` now reports each unit's `size` ([`mod-bridge.md`](./mod-bridge.md) §5), and with it
wasted moves dropped to 0 (0 of 86 in a probe run, 0 of 253 in the baseline).

## 5. Traps

- **`bsf-server\start-server.bat` closes every Node program on the PC** before it starts the server
  (`Stop-Process -Name node`). That includes other Claude Code sessions and any runner in progress. When
  anything else might be running, start the already-built server directly from `bsf-server` instead:
  `node build\index.js`.
- **Two runs at once, from two worktrees, are not stopped.** The "one run at a time" lock lives in each
  worktree's own `_build\tests\`, and both runs would drive the one installed game. Also, check which build
  is installed (`app.game.air.swf` in the game folder) before a run. A baseline run on a build that already
  holds the next wave's changes measures the wrong thing.
- **Do not close the game while a unit is walking.** It hangs the game on the way out (issue #36). On a
  normal run the runner waits for a walk to finish before ending a turn, and closes only on a still
  board. **A run that fails partway does not wait:** it closes the game wherever it stands, and a game
  that has not closed 20 seconds after being asked is forced shut, which may leave its own log cut
  short. A cut-short log is still counted, so check the summary's "game closed" line for `BY FORCE`.
- **A run that fails with an error still leaves a summary.** `runner-summary.txt` then starts with a
  line beginning "RUN STOPPED EARLY". **Ctrl-C and a killed process leave none.** The per-battle lines
  are written as each battle ends, so `--summary-only <results file>` gives the totals for any run that
  finished at least one battle. Ctrl-C restores the game's helper setting and exits, but the code does
  not close the game, so look for a leftover game window.
- **Use a new `--out` folder each time.** The runner refuses a folder that already holds results.
- **A battle with no winner after 400 turns is recorded as `unfinished`.** It is not counted for either
  side. Change the cap with `--turn-cap`.
- **The party decides the match-up.** Both sides are a copy of the logged-in account's active party
  (`test2`, Steam id `123456`, by default; `--steam-id` picks another local account, and the server finds
  the account by that id). A different party gives different numbers, so compare runs on the same account.
- **A unit's id is not its class.** Ids keep the name a unit was hired under: `test2`'s `archer_start_1` is
  a Bowmaster and its `warrior_start_1` a Warhawk. Its party is a Bowmaster, a Siegearcher, 2 Axemen and 2
  Warhawks. Read a party's classes from `entityClass` in the account's `roster_json` in the server's
  database, not from the ids in `battle_state`. It matters for specials: only promoted classes have one.
- **The opponent mirrors your party unit for unit, including any Shieldbanger**, whose missing strength
  attack is behind crash `#1009`. The summary counts those lines.
