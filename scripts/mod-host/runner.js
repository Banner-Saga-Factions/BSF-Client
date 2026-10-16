// runner.js — the match runner: plays the player's side of offline practice
// battles against the computer, many in a row, and counts who wins.
//
// WHAT THIS IS FOR. Issue #31 is about making the computer opponent stronger.
// "Stronger" needs a number, and this is where the number comes from. The runner
// starts the real game, starts a practice battle, plays the player's side with a
// fixed and deliberately simple strategy, writes down how the battle ended, and
// goes again. Run it before and after a change to the opponent, and compare.
//
// THE PLAYER IT PLAYS. Fixed and simple, so that it stays the same yardstick
// from one measurement to the next:
//   1. Hit the weakest enemy it can reach this turn (lowest strength first),
//      with the basic strength attack.
//   2. Otherwise, step toward the nearest enemy.
//   3. Otherwise, end the turn.
// That is --player strength, the default. --player armor-first is the same
// player with one rule added: when a strength hit would do 1 damage or less,
// use the armor attack instead. Armor soaks up a strength hit (damage is
// roughly the attacker's strength minus the target's armor). Measured
// 2026-10-16, the plain player lost 8 battles of 8 to the unchanged computer
// opponent; whether this second player is a fairer yardstick is not measured yet.
// "Can reach" is worked out with the game's own range rule and then put to the
// game: a move or an attack it would not allow comes back refused with a
// reason, and the runner tries the next option. The arithmetic only decides
// where to look first; the game has the last word.
//
// HOW IT TALKS TO THE GAME. Through the mod bridge (docs/mod-bridge.md), using
// the same launch-and-converse machinery as the automated test
// (tests/lib/game-session.js). That machinery points the game's helper slot at
// a go-between for the length of the run and puts the old setting back
// afterwards, so this file does not need installing into the game folder.
//
// WHAT IT NEEDS (the same as tests/first-battle.test.js):
//   - the local server up on port 8082   (bsf-server\start-server.bat)
//   - AIR_HOME set, and our own build installed in the game folder
//     (scripts\build.ps1, then copy _build\app.game.air.swf over the installed one)
//
// USAGE, from the bsf-client folder:
//   node scripts\mod-host\runner.js                 # 10 battles
//   node scripts\mod-host\runner.js --battles 5
//   node scripts\mod-host\runner.js --player armor-first
//   node scripts\mod-host\runner.js --speed 4         # play each battle 4x faster
//   node scripts\mod-host\runner.js --out _build\runner\my-run
//   node scripts\mod-host\runner.js --summary-only _build\runner\my-run\runner-results.jsonl
//
// WHAT IT WRITES, in the output folder (default _build\runner\<date-time>):
//   runner-results.jsonl  one line per battle: winner, turns, survivors per side
//   runner-summary.txt    the totals, also printed at the end (written when the run
//                         fails with an error, with a line saying so; not on Ctrl-C
//                         or a kill)
//   runner-turns.jsonl    one line per player turn: what it tried and how long it took
// plus the session's own transcript and run log in _build\tests\.
//
// Related reading: docs/driving-the-client.md (launching, logs, traps),
// docs/mod-bridge.md §5 (every battle command and refusal), and
// misc/Plan-Improve-Battle-AI.md (what the numbers are for).

'use strict';

const fs = require('fs');
const path = require('path');
const { GameSession } = require('../../tests/lib/game-session');

const REPO_ROOT = path.resolve(__dirname, '..', '..');

// Real waits on a real game: generous, never infinite.
const PATIENCE = {
  login: 90000,
  battleLoads: 120000,
  // The computer's turn plus our own; a stuck battle is reported, not waited on.
  turnComesRound: 120000,
  walkFinishes: 15000,
};

// A battle that has run this many turns is called unfinished and abandoned. The
// default is far above anything a normal battle reaches; it only exists so that
// two sides both refusing to engage cannot hold a run up for ever.
const DEFAULT_TURN_CAP = 400;

// The fixed players the runner can play (see the top of this file).
const PLAYERS = ['strength', 'armor-first'];

// The fastest the game's developer fast-forward allows (ModGameSpeed.MAX_SCALE).
// --speed is meant to change only how fast the battle plays on screen, not what
// either side decides; docs/match-runner.md §4 says what the first trial showed.
const MAX_SPEED = 8;

// ---------------------------------------------------------------------------
// Arguments
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const opts = {
    battles: 10,
    out: null,
    turnCap: DEFAULT_TURN_CAP,
    summaryOnly: null,
    player: 'strength',
    speed: 1,
  };
  for (let i = 0; i < argv.length; i++) {
    const arg = argv[i];
    const next = () => {
      const value = argv[++i];
      if (value === undefined || value.startsWith('--')) {
        throw new Error(`${arg} needs a value after it`);
      }
      return value;
    };
    // A whole number of at least 1. parseInt alone would turn "abc" into NaN and
    // "3.5" into 3, and a NaN turn cap quietly switches the safety net off.
    const wholeNumber = () => {
      const text = next();
      if (!/^[1-9]\d*$/.test(text)) {
        throw new Error(`${arg} needs a whole number of at least 1, not "${text}"`);
      }
      return parseInt(text, 10);
    };
    if (arg === '--battles') opts.battles = wholeNumber();
    else if (arg === '--out') opts.out = next();
    else if (arg === '--turn-cap') opts.turnCap = wholeNumber();
    else if (arg === '--summary-only') opts.summaryOnly = next();
    else if (arg === '--player') opts.player = next();
    else if (arg === '--speed') opts.speed = wholeNumber();
    else throw new Error(`unknown argument: ${arg}`);
  }
  if (opts.speed > MAX_SPEED) {
    throw new Error(`--speed can be at most ${MAX_SPEED}`);
  }
  if (!PLAYERS.includes(opts.player)) {
    throw new Error(`--player must be one of: ${PLAYERS.join(', ')}`);
  }
  return opts;
}

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').replace('T', '_').slice(0, 19);
}

function say(message) {
  process.stdout.write(`[${new Date().toISOString().slice(11, 19)}] ${message}\n`);
}

const pause = ms => new Promise(resolve => setTimeout(resolve, ms));

// ---------------------------------------------------------------------------
// Reading the board
// ---------------------------------------------------------------------------

/** The unit whose turn it is, or null. */
function actingUnit(state) {
  if (!state.turn) return null;
  return (state.units || []).find(u => u.id === state.turn.entityId) || null;
}

function stat(unit, name) {
  const s = unit.stats && unit.stats[name];
  return s ? s.current : null;
}

/** Tiles apart, counting steps along the grid (no diagonals). */
function gridDistance(a, b) {
  return Math.abs(a.x - b.x) + Math.abs(a.y - b.y);
}

/**
 * The player's side and the computer's side, as two lists of units, keyed off
 * playerControlled rather than team names, which are ids.
 */
function sides(state) {
  const units = state.units || [];
  return {
    ours: units.filter(u => u.playerControlled),
    theirs: units.filter(u => !u.playerControlled),
  };
}

function aliveOnBoard(units) {
  return units.filter(u => u.alive && u.tile);
}

/**
 * The block of tiles a unit covers if its corner stands on `tile`. A human
 * covers one tile, a varl two by two; `tile` is the corner with the smallest x
 * and y. Units without a reported size (an older build) count as one tile.
 */
function footprint(unit, tile) {
  const size = unit.size || { width: 1, length: 1 };
  const at = tile || unit.tile;
  return { left: at.x, front: at.y, right: at.x + size.width, back: at.y + size.length };
}

/**
 * How far apart two units are for an attack, the way the game measures it
 * (TileRectRange.computeRange in the decompile): the gap between the two
 * blocks, counted along the grid. Side by side is 1, diagonal neighbours 2.
 */
function rangeBetween(a, b) {
  let across = 0;
  if (b.left >= a.right) across = b.left - a.right + 1;
  else if (a.left >= b.right) across = a.left - b.right + 1;
  let along = 0;
  if (b.front >= a.back) along = b.front - a.back + 1;
  else if (a.front >= b.back) along = a.front - b.back + 1;
  return across + along;
}

/**
 * Every tile within `movement` steps of where the unit stands. Whether it can
 * actually get there (walls, other units, the board edge) is the game's call:
 * battle_move refuses a tile it cannot reach.
 */
function tilesWithin(me, movement) {
  const tiles = [];
  for (let dx = -movement; dx <= movement; dx++) {
    for (let dy = -movement; dy <= movement; dy++) {
      if (dx === 0 && dy === 0) continue;
      if (Math.abs(dx) + Math.abs(dy) > movement) continue;
      tiles.push({ x: me.tile.x + dx, y: me.tile.y + dy });
    }
  }
  return tiles;
}

// ---------------------------------------------------------------------------
// One turn
// ---------------------------------------------------------------------------

/**
 * Play the player's turn that is running now, and return a record of it.
 *
 * Every command goes through `ask`, which counts round trips and refusals, so
 * the record answers the wave's third question: is finding a tile by trial and
 * refusal fast enough?
 */
async function playTurn(session, state, opts) {
  const started = Date.now();
  const record = {
    turn: state.turn.number,
    unit: state.turn.entityId,
    action: null,
    target: null,
    moved: false,
    asks: 0,
    refusals: 0,
    refusalReasons: {},
    wastedMove: false,
  };

  const ask = async (cmd, args) => {
    record.asks++;
    const reply = await session.send(cmd, args);
    if (reply && reply.ok === false) {
      record.refusals++;
      // Strip the coordinates out of the reason, so "3,4 is out of reach" and
      // "5,6 is out of reach" count as the same kind of refusal.
      const kind = String(reply.reason).replace(/-?\d+,-?\d+/g, 'X,Y') +
        (reply.validation ? ` (${reply.validation})` : '');
      record.refusalReasons[kind] = (record.refusalReasons[kind] || 0) + 1;
    }
    return reply;
  };

  const me = actingUnit(state);
  const { ours, theirs } = sides(state);
  const enemySide = me && me.playerControlled ? theirs : ours;
  const enemies = aliveOnBoard(enemySide);

  if (!me || !me.tile || enemies.length === 0) {
    await ask('battle_end_turn');
    record.action = 'end';
    record.ms = Date.now() - started;
    return record;
  }

  // Weakest first; nearest breaks a tie, so the choice never depends on the
  // order the game happens to list units in.
  const byWeakness = enemies.slice().sort((a, b) =>
    (stat(a, 'strength') - stat(b, 'strength')) ||
    (rangeBetween(footprint(me), footprint(a)) - rangeBetween(footprint(me), footprint(b))) ||
    (a.id < b.id ? -1 : 1));

  // The basic attack's reach. The game reports a unit's range as one number;
  // a bow cannot shoot a unit standing right next to it, so anything that
  // reaches further than one tile is assumed not to hit at 1. That is only
  // where to look first: the game still judges every attack.
  const maxRange = stat(me, 'range') || 1;
  const minRange = maxRange > 1 ? 2 : 1;
  const movement = stat(me, 'movement') || 0;
  const candidates = movement > 0 ? tilesWithin(me, movement) : [];

  const attack = async enemy => {
    // No "ability" named: the bridge's default is the strength attack, falling
    // back to the armor one only for a unit that has no strength attack at all.
    // The armor-first player asks for the armor attack when a strength hit
    // would barely scratch, and falls back to the default if it is refused.
    let reply = null;
    if (opts.player === 'armor-first' &&
        stat(me, 'strength') - stat(enemy, 'armor') <= 1) {
      reply = await ask('battle_attack', { target: enemy.id, ability: 'armor' });
    }
    if (!reply || !reply.ok) {
      reply = await ask('battle_attack', { target: enemy.id });
    }
    if (reply.ok) {
      record.action = 'attack';
      record.target = enemy.id;
      record.ability = reply.ability;
      return true;
    }
    return false;
  };

  // 1. The weakest enemy reachable this turn: from where we stand, or after
  // one move. The tiles tried are those the game's own range rule says hit
  // the enemy, the shortest walk first.
  for (const enemy of byWeakness) {
    if (await attack(enemy)) break;
    const target = footprint(enemy);
    const tiles = candidates
      .filter(t => {
        const r = rangeBetween(footprint(me, t), target);
        return r >= minRange && r <= maxRange;
      })
      .sort((a, b) =>
        (gridDistance(me.tile, a) - gridDistance(me.tile, b)) ||
        (a.x - b.x) || (a.y - b.y));
    for (const tile of tiles) {
      const moved = await ask('battle_move', tile);
      if (!moved.ok) continue;
      record.moved = true;
      record.to = tile;
      if (await attack(enemy)) break;
      // The move happened and the attack is not possible from there after all.
      // A move cannot be taken back, so try anyone else in reach from here.
      for (const other of byWeakness) {
        if (other !== enemy && await attack(other)) break;
      }
      if (!record.action) record.wastedMove = true;
      break;
    }
    if (record.action || record.moved) break;
  }

  // 2. Nobody reachable: step toward the nearest enemy — the tile that leaves
  // the smallest gap, the shortest walk breaking a tie, and only ever closer.
  if (!record.action && !record.moved && candidates.length > 0) {
    const gapFrom = tile =>
      Math.min(...enemies.map(e => rangeBetween(footprint(me, tile), footprint(e))));
    const here = gapFrom(me.tile);
    const tiles = candidates
      .map(t => ({ t, gap: gapFrom(t) }))
      .filter(c => c.gap < here)
      .sort((a, b) =>
        (a.gap - b.gap) ||
        (gridDistance(me.tile, a.t) - gridDistance(me.tile, b.t)) ||
        (a.t.x - b.t.x) || (a.t.y - b.t.y))
      .map(c => c.t);
    for (const tile of tiles) {
      const moved = await ask('battle_move', tile);
      if (moved.ok) {
        record.moved = true;
        record.to = tile;
        break;
      }
    }
  }

  // 3. End the turn — unless an attack already did. Wait for a walk to finish
  // first: ending a turn mid-walk is untested ground, and closing the game
  // mid-walk is known to hang it (issue #36), so the runner keeps to still boards.
  if (!record.action) {
    if (record.moved) {
      await waitForWalk(session, me.id, record.to);
    }
    const ended = await ask('battle_end_turn');
    record.action = record.moved ? 'move' : 'end';
    if (!ended.ok) record.endRefused = ended.reason;
  }

  record.ms = Date.now() - started;
  return record;
}

/** Wait until a unit stands on the tile it was sent to. */
async function waitForWalk(session, unitId, tile) {
  const deadline = Date.now() + PATIENCE.walkFinishes;
  while (Date.now() < deadline) {
    const state = await session.send('battle_state');
    const unit = (state.units || []).find(u => u.id === unitId);
    if (!unit || !unit.alive || !unit.tile) return;
    if (unit.tile.x === tile.x && unit.tile.y === tile.y) return;
    await pause(250);
  }
}

// ---------------------------------------------------------------------------
// One battle
// ---------------------------------------------------------------------------

/** A unit by id, or null. */
function unitById(state, id) {
  return (state && state.units || []).find(u => u.id === id) || null;
}

/** Dead, or gone from the board. */
function isDown(state, id) {
  const u = unitById(state, id);
  return !u || !u.alive;
}

/**
 * The computer's units that walked up during its last stretch of turns and got
 * nothing for it: they moved, and none of our units died. `before` is the board
 * at the start of our previous turn and `now` the board at the start of this
 * one; between them only the computer acted, since our basic attacks move no
 * one but ourselves. If one of these is then killed by our very next attack, it
 * walked into a free kill: the runner counts that as a computer "suicide",
 * which is how issue #31 decides whether the opponent needs an anti-suicide
 * rule. It undercounts on purpose: a unit our simple player could have killed
 * but did not pick is not counted.
 */
function walkedInForNothing(before, now) {
  const weLostOne = (before.units || []).some(u =>
    u.playerControlled && u.alive && isDown(now, u.id));
  if (weLostOne) return [];
  return sides(now).theirs
    .filter(u => {
      const was = unitById(before, u.id);
      return u.alive && u.tile && was && was.tile &&
        (was.tile.x !== u.tile.x || was.tile.y !== u.tile.y);
    })
    .map(u => u.id);
}

/**
 * A short fingerprint of how a battle went: who acted on each turn, and every
 * unit's strength and armor after it. Two battles that differ here differed;
 * two that match very likely played the same, though tiles are not included.
 */
function boardFingerprint(state) {
  return (state.units || [])
    .map(u => `${u.id}:${u.alive ? 1 : 0}:${stat(u, 'strength')}/${stat(u, 'armor')}`)
    .sort()
    .join(',');
}

async function playBattle(session, index, opts, previousBattleId) {
  const record = {
    battle: index,
    player: opts.player,
    startedAt: new Date().toISOString(),
    battleId: null,
    winner: null,
    turns: null,
    survivors: null,
    party: null,
    playerTurns: 0,
    computerTurns: 0,
    secondsToDeploy: null,
    seconds: null,
    speed: opts.speed,
    computerSuicides: 0,
    suicides: [],
    trace: [],
  };
  const started = Date.now();

  const accepted = await session.send('start_ai_battle');
  if (accepted !== 'ok') {
    throw new Error(`start_ai_battle answered ${JSON.stringify(accepted)}`);
  }

  // The deploy screen of a NEW battle. Matching on the state alone would happily
  // accept the finished battle still on screen from last time, if the game never
  // left it — which is exactly the case the first question is about.
  let lastSeen = null;
  const atDeploy = await session.until(
    `battle ${index} to reach the deploy screen`,
    async () => {
      const state = await session.send('battle_state');
      lastSeen = state;
      if (!state.inBattle || state.state !== 'BattleStateDeploy') return null;
      return state;
    },
    { timeoutMs: PATIENCE.battleLoads, everyMs: 1000 }
  ).catch(err => {
    err.lastSeen = lastSeen;
    throw err;
  });
  record.secondsToDeploy = Math.round((Date.now() - started) / 100) / 10;
  record.battleId = atDeploy.battleId;
  record.sameIdAsPrevious = previousBattleId !== undefined && atDeploy.battleId === previousBattleId;
  const startSides = sides(atDeploy);
  record.party = startSides.ours.map(u => u.id.replace(/^[^+]*\+/, '')).sort();
  record.startCounts = { player: startSides.ours.length, computer: startSides.theirs.length };

  if (opts.outDir) {
    // The whole board at the start, for anyone checking what the runner saw.
    fs.writeFileSync(path.join(opts.outDir, `deploy-${index}.json`), JSON.stringify(atDeploy, null, 1));
  }

  const ready = await session.send('battle_deploy_ready');
  if (!ready.ok) {
    throw new Error(`the game would not accept ready: ${ready.reason}`);
  }
  if (opts.speed > 1) {
    // After the deploy screen, so the game can see this is an offline battle;
    // a run that asked for a speed it did not get would mislabel its numbers.
    const fast = await session.send('set_game_speed', { scale: opts.speed });
    if (!fast || !fast.ok) {
      throw new Error(`the game would not run at speed ${opts.speed}: ${fast && fast.reason}`);
    }
  }

  const turnLog = [];
  let lastTurnSeen = -1;
  let state = null;
  // For the suicide count (walkedInForNothing): the board at the start of our
  // previous turn, and a computer unit we attacked after it walked up for nothing.
  let before = atDeploy;
  let watch = null;
  const settleWatch = s => {
    if (!watch || !s || !s.inBattle) return;
    if (isDown(s, watch.unit)) {
      record.computerSuicides++;
      record.suicides.push(watch);
    }
    watch = null;
  };
  for (;;) {
    state = await session.until(
      `battle ${index}: the player's turn, or the end`,
      async () => {
        const s = await session.send('battle_state');
        if (!s.inBattle) return s;  // the battle went away under us
        if (s.finished) return s;
        if (s.turn && s.turn.number > lastTurnSeen &&
            s.turn.playerControlled && !s.turn.committed) return s;
        return null;
      },
      { timeoutMs: PATIENCE.turnComesRound, everyMs: 300 }
    );
    settleWatch(state);
    if (!state.inBattle || state.finished) break;

    // Turns in between were the computer's.
    record.computerTurns += lastTurnSeen < 0
      ? state.turn.number
      : state.turn.number - lastTurnSeen - 1;
    lastTurnSeen = state.turn.number;
    record.trace.push(`${state.turn.number}:${state.turn.entityId}|${boardFingerprint(state)}`);

    if (state.turn.number >= opts.turnCap) {
      record.winner = 'unfinished';
      break;
    }

    const suspects = walkedInForNothing(before, state);
    before = state;

    const turn = await playTurn(session, state, opts);
    turn.battle = index;
    turnLog.push(turn);
    record.playerTurns++;
    if (turn.action === 'attack' && suspects.includes(turn.target)) {
      watch = { unit: turn.target, turn: state.turn.number };
    }
  }

  // How it ended. Read once more after the last blow has landed.
  const finalState = state && state.inBattle ? await session.send('battle_state') : state;
  settleWatch(finalState);
  if (opts.speed > 1) {
    // Back to normal: always allowed, even once the battle has gone.
    await session.send('set_game_speed', { scale: 1 });
  }
  const endSides = sides(finalState && finalState.inBattle ? finalState : state);
  record.survivors = {
    player: aliveOnBoard(endSides.ours).length,
    computer: aliveOnBoard(endSides.theirs).length,
  };
  if (!record.winner) {
    if (record.survivors.player > 0 && record.survivors.computer === 0) record.winner = 'player';
    else if (record.survivors.computer > 0 && record.survivors.player === 0) record.winner = 'computer';
    else record.winner = 'unclear';
  }
  record.turns = finalState && finalState.turn ? finalState.turn.number : lastTurnSeen;
  record.finalState = finalState ? finalState.state : null;
  record.fingerprint = simpleHash(record.trace.join('\n'));
  record.seconds = Math.round((Date.now() - started) / 100) / 10;
  return { record, turnLog };
}

/** A short stable hash, so two traces can be compared at a glance. */
function simpleHash(text) {
  let h = 5381;
  for (let i = 0; i < text.length; i++) {
    h = ((h << 5) + h + text.charCodeAt(i)) | 0;
  }
  return (h >>> 0).toString(16);
}

// ---------------------------------------------------------------------------
// The run
// ---------------------------------------------------------------------------

async function startGame() {
  // Pin the landing: see first-battle.test.js for why it matters.
  const session = new GameSession({ name: 'runner', landing: 'versus' });
  try {
    await session.start();
    await session.waitFor(
      'the login to be answered',
      m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/auth/login'),
      { timeoutMs: PATIENCE.login });
    await session.waitFor(
      'the account and roster to arrive',
      m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/account/info'),
      { timeoutMs: PATIENCE.login });
    // DO NOT DROP THIS WAIT. A battle started before the player has landed is
    // thrown away by the game a moment later, silently. The full story is in
    // tests/first-battle.test.js and docs/driving-the-client.md §9.
    await session.waitFor(
      'the player to land in the versus screen',
      m => m.event === 'HTTP_REQUEST' &&
        String(m.url || '').includes('services/game/location') && m.body === 'loc_versus',
      { timeoutMs: PATIENCE.login });
  } catch (err) {
    // The caller only gets the session back on success, so close it here: a
    // timed-out wait would otherwise leave the game window open and keep this
    // process alive. If closing fails too, the start-up error is the one to report.
    try {
      await session.stop();
    } catch (stopErr) {
      say(`closing the game after the failed start-up also failed: ${stopErr.message}`);
    }
    throw err;
  }
  return session;
}

/**
 * Count the game-log lines worth knowing about, in the game's own logs.
 *
 * NOT the session's run log: that holds only the runner's own notes, never a
 * line the game printed. The first version of this counted there and reported
 * "#1009 x0" for a log that could never have contained one. The game's own log
 * is A-<n>.log.txt, locked until the game exits and renumbered on every start
 * (driving-the-client.md §5), so this reads every one written since the run
 * began. It also counts the "Error #1508" lines that a game under adl usually
 * prints three times for the missing sound extension, as a hint that the right
 * log was read.
 */
function countLogFlags(runStartedAt, gamesStarted) {
  const dir = path.join(process.env.APPDATA || '', 'TheBannerSagaFactions', 'Local Store', 'logs');
  let files = [];
  try {
    files = fs.readdirSync(dir)
      .filter(name => /^A-\d+\.log\.txt$/.test(name))
      .map(name => path.join(dir, name))
      .filter(file => fs.statSync(file).mtimeMs >= runStartedAt);
  } catch (err) {
    return { found: 0, reason: `could not list ${dir}: ${err.message}` };
  }
  const totals = { found: 0, error1009: 0, fakingWentWrong: 0, error1508: 0, battlesStarted: 0, files: [] };
  for (const file of files) {
    let text;
    try {
      text = fs.readFileSync(file, 'utf8');
    } catch (err) {
      continue;  // still locked: that game has not exited
    }
    // Only logs from games that started a practice battle are this run's.
    if (!/GameFsm\.startAiBattle/.test(text)) continue;
    const count = re => (text.match(re) || []).length;
    totals.found++;
    totals.files.push(path.basename(file));
    // Search the error text, never a bare number: every log line carries a
    // millisecond stamp that can contain the same digits (driving-the-client §5).
    totals.error1009 += count(/Error #1009/g);
    totals.fakingWentWrong += count(/Something went wrong while faking/g);
    totals.error1508 += count(/Error #1508/g);
    totals.battlesStarted += count(/GameFsm\.startAiBattle/g);
  }
  if (totals.found === 0) {
    totals.reason = `no game log in ${dir} written since the run began mentions a practice battle`;
  } else if (totals.found !== gamesStarted) {
    // A game closed by force may leave a log cut short or none, a locked one is
    // skipped above, and a game the owner started by hand during the run would be
    // counted too.
    totals.warning = `found ${totals.found} game logs for ${gamesStarted} games the runner started`;
  }
  return totals;
}

function summarise(results) {
  const n = results.length;
  const count = w => results.filter(r => r.winner === w).length;
  const computerWins = count('computer');
  const playerWins = count('player');
  const decided = computerWins + playerWins;
  const avg = (list, f) => list.length ? list.reduce((s, r) => s + f(r), 0) / list.length : 0;
  const compWon = results.filter(r => r.winner === 'computer');
  const ids = results.map(r => r.battleId);
  const prints = results.map(r => r.fingerprint);
  const lines = [
    `battles: ${n}   scripted player: ${[...new Set(results.map(r => r.player || 'strength'))].join(', ')}`,
    `computer won: ${computerWins}   player won: ${playerWins}   ` +
      `unfinished/unclear: ${n - decided}`,
    `computer win rate: ${decided ? (100 * computerWins / decided).toFixed(0) : '-'}% of decided battles`,
    `computer survivors when it won: ${compWon.length ? avg(compWon, r => r.survivors.computer).toFixed(2) : '-'}`,
    `computer survivors, all battles: ${avg(results, r => r.survivors.computer).toFixed(2)}   ` +
      `player survivors, all battles: ${avg(results, r => r.survivors.player).toFixed(2)}`,
    `turns per battle: ${avg(results, r => r.turns).toFixed(1)}   ` +
      `seconds per battle: ${avg(results, r => r.seconds).toFixed(0)}   ` +
      `seconds per turn: ${(avg(results, r => r.seconds) / (avg(results, r => r.turns) || 1)).toFixed(2)}   ` +
      `speed: ${[...new Set(results.map(r => r.speed || 1))].join(', ')}`,
    // Older result files have no suicide count; say so rather than print 0.
    results.every(r => typeof r.computerSuicides === 'number')
      ? `computer suicides (walked up, killed nothing, died to our next attack): ` +
        `${results.reduce((s, r) => s + r.computerSuicides, 0)} in all, ` +
        `${avg(results, r => r.computerSuicides).toFixed(2)} per battle`
      : 'computer suicides: not counted in this file (recorded before the counter existed)',
    `distinct battle ids: ${new Set(ids.map(String)).size} of ${n}   ` +
      `distinct battle traces: ${new Set(prints).size} of ${n}`,
    `game restarts needed: ${results.filter(r => r.afterRestart).length}`,
  ];
  return lines.join('\n');
}

function summariseTurns(turns) {
  if (turns.length === 0) return 'no player turns recorded';
  const ms = turns.map(t => t.ms).sort((a, b) => a - b);
  const asks = turns.map(t => t.asks).sort((a, b) => a - b);
  const pct = (list, p) => list[Math.min(list.length - 1, Math.floor(p * list.length))];
  const actions = {};
  for (const t of turns) actions[t.action] = (actions[t.action] || 0) + 1;
  return [
    `player turns: ${turns.length}   ` +
      Object.entries(actions).map(([k, v]) => `${k}: ${v}`).join('   '),
    `time to decide a turn (ms): median ${pct(ms, 0.5)}, 90th ${pct(ms, 0.9)}, worst ${ms[ms.length - 1]}`,
    `commands per turn: median ${pct(asks, 0.5)}, 90th ${pct(asks, 0.9)}, worst ${asks[asks.length - 1]}`,
    `moves that left no one to hit: ${turns.filter(t => t.wastedMove).length}`,
  ].join('\n');
}

async function main() {
  const opts = parseArgs(process.argv.slice(2));

  if (opts.summaryOnly) {
    const results = fs.readFileSync(opts.summaryOnly, 'utf8')
      .split('\n').filter(Boolean).map(line => JSON.parse(line));
    console.log(summarise(results));
    return;
  }

  const outDir = path.resolve(REPO_ROOT, opts.out || path.join('_build', 'runner', stamp()));
  const resultsPath = path.join(outDir, 'runner-results.jsonl');
  // Results are appended as each battle ends, so a reused folder would mix two runs.
  if (fs.existsSync(resultsPath)) {
    throw new Error(`${outDir} already holds results; pick a new --out folder`);
  }
  fs.mkdirSync(outDir, { recursive: true });
  opts.outDir = outDir;
  const turnsPath = path.join(outDir, 'runner-turns.jsonl');
  const summaryPath = path.join(outDir, 'runner-summary.txt');
  say(`writing to ${outDir}`);

  const results = [];
  const allTurns = [];
  const sessions = [];
  const runStartedAt = Date.now();
  let session = null;
  let gamesStarted = 0;
  let failure = null;
  let closeFailure = null;
  let previousBattleId;
  let restartNext = false;

  const stopSession = async () => {
    if (!session) return;
    const s = session;
    session = null;
    const { closedPolitely } = await s.stop();
    sessions.push({ s, closedPolitely });
  };

  try {
    for (let i = 1; i <= opts.battles; i++) {
      let afterRestart = false;
      if (!session || restartNext) {
        if (session) {
          await stopSession();
          afterRestart = true;
        }
        say('starting the game');
        session = await startGame();
        gamesStarted++;
        restartNext = false;
      }
      // The session keeps every message it has heard so it can answer waits for
      // things that already happened. Nothing below waits on old messages, so
      // each battle starts with the list empty.
      session.messages.length = 0;

      say(`battle ${i} of ${opts.battles}`);
      let outcome;
      try {
        outcome = await playBattle(session, i, opts, previousBattleId);
      } catch (err) {
        if (i > 1 && !afterRestart && /deploy screen/.test(err.message)) {
          // Question 1: a second battle did not start in the same game. Record
          // what the game said, restart it, and try this battle again.
          say(`battle ${i} did not start in the running game (${err.message.split('\n')[0]}); ` +
            `last reading: ${err.lastSeen ? `${err.lastSeen.inBattle ? err.lastSeen.state : 'not in a battle'}` : 'none'}`);
          restartNext = true;
          i--;
          continue;
        }
        throw err;
      }
      const { record, turnLog } = outcome;
      record.afterRestart = afterRestart;
      previousBattleId = record.battleId;
      results.push(record);
      allTurns.push(...turnLog);
      fs.appendFileSync(resultsPath, JSON.stringify(record) + '\n');
      for (const t of turnLog) fs.appendFileSync(turnsPath, JSON.stringify(t) + '\n');
      say(`battle ${i}: ${record.winner} won in ${record.turns} turns, ` +
        `survivors player ${record.survivors.player} / computer ${record.survivors.computer}, ` +
        `${record.seconds}s, id ${record.battleId}`);
    }
  } catch (err) {
    failure = err;
  } finally {
    // After a normal run nothing is walking: every battle above ends on a
    // finished board or on our own turn with a still board. After a failure the
    // game is closed wherever it stands, which can hang it on the way out
    // (issue #36); the session then forces it closed. A failure while closing is
    // kept apart so that it cannot hide the run's own error or skip the summary.
    try {
      await stopSession();
    } catch (err) {
      closeFailure = err;
    }
  }

  const flags = countLogFlags(runStartedAt, gamesStarted);
  const summary = [
    ...(failure
      ? [`RUN STOPPED EARLY after ${results.length} of ${opts.battles} battles: ` +
        `${String(failure.message).split('\n')[0]}`]
      : []),
    ...(closeFailure
      ? [`CLOSING THE GAME FAILED: ${String(closeFailure.message).split('\n')[0]}`]
      : []),
    summarise(results),
    summariseTurns(allTurns),
    flags.found > 0
      ? `game logs (${flags.files.join(', ')}): #1009 x${flags.error1009}, ` +
        `"went wrong while faking" x${flags.fakingWentWrong}, ` +
        `practice battles started x${flags.battlesStarted}, ` +
        `sound-extension #1508 x${flags.error1508} (3 per game start under adl; ` +
        `a shortfall means check which log was read, not that the count is wrong)`
      : `game logs NOT COUNTED: ${flags.reason}. Read them by hand before trusting this run.`,
    ...(flags.warning ? [`WARNING: ${flags.warning}. Read the logs by hand before trusting the count.`] : []),
    `game closed: ${sessions.map(x => x.closedPolitely ? 'politely' : 'BY FORCE').join(', ')}`,
  ].join('\n');
  fs.writeFileSync(summaryPath, summary + '\n');
  console.log('\n' + summary);
  if (failure) throw failure;
  if (closeFailure) throw closeFailure;
}

main().catch(err => {
  console.error(`runner failed: ${err.stack || err.message}`);
  process.exitCode = 1;
});
