// driver.js — start the real game, drive it with typed commands, photograph it.
//
// WHAT THIS IS FOR. Two questions about this client can only be answered by the
// running game: "does it still do the thing" and "what does it look like". The
// repository already answers the first — tests/lib/game-session.js talks to the
// game over the mod bridge. This adds the second, and puts both behind one
// command language so an agent can drive the game without writing a test.
//
//   node .claude/skills/run-bsf-client/driver.js smoke
//   node .claude/skills/run-bsf-client/driver.js battle
//   node .claude/skills/run-bsf-client/driver.js shell <<'EOF'
//   ready
//   battle
//   deploy
//   shot opening-board
//   ourturn
//   board
//   EOF
//
// WHY A COMMAND LANGUAGE AND NOT A TEST. A test asserts a fixed journey. An
// agent checking a change needs to stop somewhere in the middle and look around
// — read the board, photograph a panel, try a move it expects to be refused.
// Every step here is one line of stdin, so the journey is written at the call
// site instead of being compiled in.
//
// THE DIVISION OF LABOUR IT ENFORCES (docs/driving-the-client.md, "Two channels"):
// the bridge sets state up, and a screenshot confirms what a player sees. The
// expensive part of looking at the game is the twenty clicks needed to reach the
// moment worth photographing, not the looking. So `shot` is deliberately cheap
// and everything before it is scripted.
//
// WHAT IT ADDS OVER THE TEST HARNESS IT SITS ON:
//   - `shot`     — nothing else in this repository takes a picture.
//   - `ready`    — the sixty lines of login waiting that first-battle.test.js
//                  carries in its body, including the one wait whose comment
//                  says do not drop this. Copying that by hand is how it gets
//                  lost; docs/driving-the-client.md section 9 asked for it to move.
//   - `board`    — a readable board. "Nothing reads the board" was named as the
//                  gap every battle test would hit.
//   - refusals   — the bridge answers an illegal request with {ok:false,reason},
//                  which is an ordinary reply, not an error. Every acting command
//                  here checks it and stops with the game's own sentence.
//
// IT DRIVES OUR BUILD, BY DEFINITION. The bridge and the practice battle exist
// only in the copy we compile; the shipped Steam file has neither. If the channel
// never opens, that is the first thing to suspect — see SKILL.md.

'use strict';

const fs = require('fs');
const path = require('path');
const readline = require('readline');
const { execFile } = require('child_process');

const SKILL_DIR = __dirname;
const REPO_ROOT = path.resolve(SKILL_DIR, '..', '..', '..');
const { GameSession } = require(path.join(REPO_ROOT, 'tests', 'lib', 'game-session.js'));

const SCREENSHOT_PS1 = path.join(SKILL_DIR, 'screenshot.ps1');
const WINDOW_PS1 = path.join(SKILL_DIR, 'window.ps1');
const INPUT_PS1 = path.join(SKILL_DIR, 'input.ps1');
const OUTPUT_DIR = path.join(REPO_ROOT, '_build', 'tests');

// Real waits on a real game, matching the ones first-battle.test.js measured.
const PATIENCE = {
  login: 90000,
  battleLoads: 120000,
  turnComesRound: 90000,
};

// EVERY PLACE THE GAME REPORTS ARRIVING AT, taken from the states that announce
// one (each calls updateGameLocation with its own word). Two things make this
// table worth having rather than matching one string:
//
//   - `loc_login_queue` is DELIBERATELY ABSENT. The login queue announces itself
//     the same way, long before the player has gone anywhere, so a wait that
//     matched any announcement would finish far too early — which is the trap
//     that cost a whole battle once already.
//   - It doubles as the map for `where`, which is how a caller finds out whether
//     a click actually changed screens.
const LANDING_PLACES = {
  loc_strand: 'the town (camp)',
  loc_versus: 'the match search',
  loc_great_hall: 'the great hall, where the roster lives',
  loc_mead_house: 'the mead house',
  loc_proving_grounds: 'the proving grounds',
  loc_hall_of_valor: 'the hall of valor',
  loc_assemble_heroes: 'the party screen',
  loc_friend_lobby: 'the friend lobby',
  loc_battle: 'a battle',
  loc_tutorial: 'the tutorial',
};

// Canned journeys. Each is just a list of the same commands stdin accepts, so
// there is one language to learn and recipes are examples of it rather than a
// second mechanism.
const RECIPES = {
  // Proof of life: the right build launched, logged in, and is on screen.
  //
  // The sleep is not padding. `ready` reports a fact about the CONVERSATION —
  // the game has told the server where the player has gone — and the screen is
  // still drawing when that is already true. Photographing straight after it
  // catches the loading spinner, which looks like a hung game rather than a
  // picture taken too early.
  smoke: {
    landing: 'versus',
    steps: [
      'ready',
      'maximize',
      'sleep 6000',
      'ping',
      'shot logged-in',
    ],
  },
  // The full walk: a practice battle on the board, stepped, and photographed.
  // Reaching the deploy screen is itself proof the scene has drawn, so no sleep
  // is needed before these shots the way it is above.
  battle: {
    landing: 'versus',
    steps: [
      'ready',
      'maximize',
      'battle',
      'shot deploy-screen',
      'deploy',
      'ourturn',
      'board',
      'shot first-turn',
      'endturn',
      'ourturn',
      'settle',
      'board',
      'shot after-a-turn',
    ],
  },
  // The town, which is where every screen the bridge cannot reach hangs off —
  // the great hall and its roster, the mead house, the proving grounds. From
  // here the only way onward is clicking, so this stops at a picture: take it,
  // read the positions you want off it, then drive with `click` in a `shell`.
  camp: {
    landing: 'camp',
    steps: [
      'ready loc_strand',
      'maximize',
      'sleep 8000',
      'where',
      'shot camp',
    ],
  },
};

function stamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').replace('T', '_').slice(0, 19);
}

function say(text) {
  process.stdout.write(text + '\n');
}

/** Fail with the game's own words when a reply says the request was refused. */
function mustBeOk(what, reply) {
  if (reply && reply.ok === false) {
    throw new Error(`the game refused ${what}: ${reply.reason || '(no reason given)'}`);
  }
  return reply;
}

// -------------------------------------------------------------------------
// Steps — the things worth doing between "the game launched" and "look at this"
// -------------------------------------------------------------------------

/**
 * Wait until the game has logged in AND decided where the player goes.
 *
 * DO NOT SHORTEN THIS TO THE ROSTER. A draft of the first test started a battle
 * as soon as the roster arrived and got no battle at all — battle_state answered
 * "not in a battle" for two solid minutes with no error raised anywhere. The
 * roster was not the problem. The state that loads the factions asks to be told
 * when that load finishes and never cancels the request, so when it finishes the
 * game jumps to the match search from wherever it has since got to, throwing away
 * a battle started in between. Waiting for the player to land means that jump has
 * already happened and there is nothing left to discard it.
 *
 * The landing PLACE is checked, not just the request: the login queue sends the
 * same request with a different place, and matching that one lands us right back
 * in the same hole.
 */
async function stepReady(session, expected) {
  const login = await session.waitFor(
    'the login to be answered',
    m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/auth/login'),
    { timeoutMs: PATIENCE.login }
  );
  if (login.success !== true) {
    throw new Error(`the server refused the login (status ${login.status})`);
  }

  await session.waitFor(
    'the account and roster to arrive',
    m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/account/info'),
    { timeoutMs: PATIENCE.login }
  );

  const wanted = expected
    ? `the player to reach ${expected}`
    : 'the player to land somewhere';
  const landed = await session.waitFor(
    wanted,
    m => m.event === 'HTTP_REQUEST' &&
      String(m.url || '').includes('services/game/location') &&
      (expected ? m.body === expected : Object.hasOwn(LANDING_PLACES, String(m.body))),
    { timeoutMs: PATIENCE.login }
  );

  let note = `logged in; the player landed in ${landed.body} — ${LANDING_PLACES[landed.body] || 'somewhere unlisted'}`;

  // The one landing that means a setup mistake rather than a place. An account
  // that has not finished the tutorial is sent here instead of to the town, and
  // nothing about it reads as an error — you simply get the wrong screen.
  if (landed.body === 'loc_tutorial') {
    note += `
  This account has not finished the tutorial, so the game sent it there instead ` +
      'of to camp. Pick an account whose completed_tutorial is 1 (BSF_STEAM_ID).';
  }
  return note;
}

/**
 * Start a practice battle and wait for it to reach the deploy screen.
 *
 * start_ai_battle answers "ok" unconditionally — it reports only that the request
 * was passed on, never that a battle exists. So the answer is ignored and the
 * board is asked instead.
 */
async function stepStartBattle(session) {
  await session.send('start_ai_battle');
  const atDeploy = await session.until(
    'the battle to reach the deploy screen',
    async () => {
      const state = await session.send('battle_state');
      return state.inBattle && state.state === 'BattleStateDeploy' ? state : null;
    },
    { timeoutMs: PATIENCE.battleLoads, everyMs: 1000 }
  );
  return `on the deploy screen with ${atDeploy.units.length} units`;
}

/**
 * Leave the deploy screen.
 *
 * An offline battle never leaves it on its own: the engine zeroes the deploy
 * countdown when a battle is not online, and a zero countdown means no timer is
 * ever created, so the phase's own force-deploy can never fire. Saying ready is
 * the only way out, which is why a scripted battle needs this command at all.
 */
async function stepDeploy(session) {
  const ready = mustBeOk('the deployment', await session.send('battle_deploy_ready'));
  return `deployed; the battle is now in ${ready.state}`;
}

/**
 * Wait until it is the player's turn and that turn has not been committed.
 *
 * Only ever the player's own turn. Ending the COMPUTER'S turn works sometimes and
 * is refused other times — it commits its turn about half a second after it
 * finishes walking, and which side of that window a request lands on is not
 * something a caller controls. Waiting for our own turn sidesteps the race.
 *
 * This is also the "safe to close" signal. Closing the game while a unit is
 * walking wedges it on the way out (issue #36), and the bridge cannot report
 * whether anything is moving, so "it is the player's turn" stands in for "the
 * board is still".
 */
async function stepOurTurn(session) {
  const ours = await session.until(
    'the player\'s turn to come round',
    async () => {
      const state = await session.send('battle_state');
      if (state.finished) {
        throw new Error('the battle ended while waiting for the player\'s turn');
      }
      return state.turn && state.turn.playerControlled && !state.turn.committed ? state : null;
    },
    { timeoutMs: PATIENCE.turnComesRound, everyMs: 1000 }
  );
  return `turn ${ours.turn.number} is ours (${ours.turn.entityId || 'unnamed unit'})` +
    (ours.turn.moved ? ', already moved' : '');
}

async function stepEndTurn(session) {
  const ended = mustBeOk('ending the turn', await session.send('battle_end_turn'));
  return `ended turn ${ended.turn}; next is ${ended.next}`;
}

/**
 * Print the board the way the on-screen panel reads it.
 *
 * Units are grouped by side and shown with the current-versus-base numbers the
 * stat panel shows, because "what the game was told this unit is" and "what it
 * has left" are different questions and both get asked.
 */
function renderBoard(state) {
  if (!state.inBattle) {
    return 'not in a battle';
  }
  const lines = [];
  lines.push(`state ${state.state}` +
    (state.turn ? `, turn ${state.turn.number}` : ', no turn yet') +
    `, online=${state.online}, finished=${state.finished}`);

  const sides = new Map();
  for (const unit of state.units || []) {
    const key = unit.playerControlled ? 'ours' : 'theirs';
    if (!sides.has(key)) {
      sides.set(key, []);
    }
    sides.get(key).push(unit);
  }

  for (const [whose, units] of sides) {
    lines.push(`  ${whose} (${units.length}):`);
    for (const unit of units) {
      const at = unit.tile ? `(${unit.tile.x},${unit.tile.y})` : '(nowhere)';
      const stat = name => {
        const value = unit.stats && unit.stats[name];
        return value ? `${value.current}/${value.base}` : '?';
      };
      const acting = state.turn && state.turn.entityId === unit.id ? ' <- acting' : '';
      const dead = unit.alive ? '' : ' DEAD';
      lines.push(
        `    ${String(at).padEnd(8)} ${String(unit.name).padEnd(18)} ` +
        `str ${stat('strength').padEnd(7)} arm ${stat('armor').padEnd(7)} ` +
        `[${unit.id}]${acting}${dead}`
      );
    }
  }
  return lines.join('\n');
}

/**
 * Find a unit by id, by name, or by any unambiguous piece of either.
 *
 * Names are not unique — a practice battle mirrors the party, so both sides
 * field units with identical names and identical numbers. The identifier is what
 * separates them, so an ambiguous match is refused rather than guessed at.
 */
function findUnit(state, needle) {
  const units = state.units || [];
  const exact = units.filter(u => u.id === needle);
  if (exact.length === 1) {
    return exact[0];
  }
  const lower = String(needle).toLowerCase();
  const matches = units.filter(u =>
    String(u.id).toLowerCase().includes(lower) || String(u.name).toLowerCase().includes(lower));
  if (matches.length === 1) {
    return matches[0];
  }
  if (matches.length === 0) {
    throw new Error(`no unit matches "${needle}". Run "board" to see what is there.`);
  }
  throw new Error(
    `"${needle}" matches ${matches.length} units, and names are not unique in a ` +
    `practice battle (both sides mirror the same party). Use a full id: ` +
    matches.map(u => u.id).join(', ')
  );
}

/**
 * Run one of the small PowerShell helpers beside this file and read its answer.
 *
 * Both print a single line of JSON so a caller never has to parse prose, and both
 * take the launcher's process id so they search DOWN from our own game rather
 * than picking up a copy the developer happens to have open.
 */
function runHelper(session, script, extraArgs) {
  const args = ['-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', script].concat(extraArgs);
  if (session.launcher && session.launcher.pid) {
    args.push('-ProcessId', String(session.launcher.pid));
  } else {
    args.push('-ProcessName', 'adl');
  }

  return new Promise((resolve, reject) => {
    execFile('powershell.exe', args, { timeout: 30000 }, (err, stdout, stderr) => {
      const said = String(stdout || '').trim();
      let parsed = null;
      try {
        parsed = JSON.parse(said.split('\n').pop());
      } catch (parseErr) {
        // Fall through to the error below with whatever it actually said.
      }
      if (!parsed || parsed.ok !== true) {
        reject(new Error(
          `${path.basename(script)} failed: ` +
          `${(parsed && parsed.reason) || said || (err && err.message) || 'no output'}` +
          (stderr ? `\n${String(stderr).trim()}` : '')
        ));
        return;
      }
      resolve(parsed);
    });
  });
}

/** Photograph the game window. Returns what the capture script reported. */
function takeScreenshot(session, name) {
  const file = path.join(OUTPUT_DIR, `${stamp()}-${name || 'shot'}.png`);
  fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  return runHelper(session, SCREENSHOT_PS1, ['-Out', file]);
}

// -------------------------------------------------------------------------
// The command language
// -------------------------------------------------------------------------

const COMMANDS = {
  // ready [place] — wait for the game to log in and arrive somewhere.
  // Given a place (loc_strand, loc_versus, ...) it waits for that one in
  // particular, which is how a script says what it is expecting.
  async ready(session, args) {
    return stepReady(session, args[0]);
  },

  // where — the last place the game said it had arrived at.
  //
  // This is the feedback loop for clicking. A click either changed the screen or
  // did not, and the game announces every arrival, so this answers it without
  // taking a picture. Cheap enough to put after every click.
  async where(session) {
    const arrivals = session.messages.filter(m =>
      m.event === 'HTTP_REQUEST' &&
      String(m.url || '').includes('services/game/location') &&
      Object.hasOwn(LANDING_PLACES, String(m.body)));
    if (arrivals.length === 0) {
      return 'the game has not announced arriving anywhere yet';
    }
    const last = arrivals[arrivals.length - 1];
    const trail = arrivals.map(a => a.body).join(' -> ');
    return `${last.body} — ${LANDING_PLACES[last.body]}
  got there by: ${trail}`;
  },

  async ping(session) {
    const reply = await session.send('ping');
    if (reply !== 'pong') {
      throw new Error(`the game answered a ping with "${reply}" rather than "pong"`);
    }
    return 'pong';
  },

  async battle(session) {
    return stepStartBattle(session);
  },

  async deploy(session) {
    return stepDeploy(session);
  },

  async ourturn(session) {
    return stepOurTurn(session);
  },

  async endturn(session) {
    return stepEndTurn(session);
  },

  async state(session) {
    return JSON.stringify(await session.send('battle_state'));
  },

  // settle [timeoutMs] — wait until nothing on the board is moving any more.
  //
  // WHY THIS IS NEEDED. `move` answers as soon as the walk is ACCEPTED, not when
  // it is finished — the unit then walks over the next few seconds. Measured on
  // this machine: a six-step walk answered instantly, still showed the unit on
  // its starting tile when asked 0.1s later, was two tiles along at one second,
  // and had arrived by three. So roughly two tiles a second.
  //
  // That matters twice. A screenshot taken straight after a move photographs a
  // unit mid-stride, and an assertion about where something stands reads the old
  // tile and fails for the wrong reason. It matters a third time at shutdown:
  // closing the game while a unit is walking wedges it on the way out (issue
  // #36), so this is the honest form of the "is the board still?" question that
  // `ourturn` could only stand in for.
  //
  // HOW IT DECIDES. Two readings half a second apart that place every unit on
  // the same tile. That is a good-enough answer, not a perfect one: an animation
  // that moves nothing between tiles — a swing, a flinch — is invisible to it.
  async settle(session, args) {
    const timeoutMs = Number(args[0] || 20000);
    const snapshot = state => (state.units || [])
      .map(u => `${u.id}@${u.tile ? `${u.tile.x},${u.tile.y}` : '?'}`)
      .sort()
      .join('|');

    let previous = null;
    return session.until(
      'the board to stop moving',
      async () => {
        const state = await session.send('battle_state');
        if (!state.inBattle) {
          return 'not in a battle, so nothing is moving';
        }
        const now = snapshot(state);
        if (previous !== null && now === previous) {
          return 'the board is still';
        }
        previous = now;
        return null;
      },
      { timeoutMs, everyMs: 500 }
    );
  },

  async board(session) {
    return renderBoard(await session.send('battle_state'));
  },

  // move <x> <y>
  //
  // There is no "make that other unit move". Both acting commands work on the
  // unit whose turn it is, exactly as a click does — so a destination is the
  // whole request. The game's own pathfinder works out the route, and a tile the
  // player could not have clicked comes back refused, because the check reads the
  // same reach map the highlighted tiles on screen are drawn from.
  async move(session, args) {
    const [x, y] = args;
    if (x === undefined || y === undefined) {
      throw new Error('move needs a tile for the acting unit: move 4 2');
    }
    const before = await session.send('battle_state');
    const acting = (before.units || []).find(u => before.turn && u.id === before.turn.entityId);
    const reply = mustBeOk(`moving to (${x},${y})`,
      await session.send('battle_move', { x: Number(x), y: Number(y) }));
    const who = acting ? acting.name : 'the acting unit';
    return `${who} walked ${reply.from ? `(${reply.from.x},${reply.from.y}) -> ` : ''}` +
      `(${reply.to ? `${reply.to.x},${reply.to.y}` : `${x},${y}`})` +
      (reply.steps !== undefined ? ` in ${reply.steps} steps` : '');
  },

  // attack <target> [ability] [level]
  //
  // `ability` takes the plain words "strength" or "armor", so a caller need not
  // know that a Raider swings abl_melee_str while an Archer looses abl_bow_str.
  // Anything else is passed through as a literal ability id.
  //
  // AN ATTACK ENDS THE TURN, and if a move is still pending it is committed
  // first — the unit walks, then swings. That matters for the shutdown rule: an
  // attack hands the turn to the computer, which makes it far likelier that
  // something is walking when the game is asked to close.
  async attack(session, args) {
    const [target, ability, level] = args;
    if (target === undefined) {
      throw new Error('attack needs a target: attack warhawk   (or: attack <unit id> armor)');
    }
    const state = await session.send('battle_state');
    const victim = findUnit(state, target);
    const attacker = (state.units || []).find(u => state.turn && u.id === state.turn.entityId);

    const payload = { target: victim.id };
    if (ability) {
      payload.ability = ability;
    }
    if (level) {
      payload.level = Number(level);
    }
    const reply = mustBeOk(`attacking ${victim.name}`,
      await session.send('battle_attack', payload));
    return `${attacker ? attacker.name : 'the acting unit'} attacked ${victim.name}` +
      (reply.ability ? ` with ${reply.ability}` : '') +
      (reply.level ? ` level ${reply.level}` : '') +
      '; the turn is over';
  },

  // send <cmd> [json] — anything the bridge accepts, unmediated.
  async send(session, args) {
    const cmd = args[0];
    if (!cmd) {
      throw new Error('send needs a command name: send battle_state');
    }
    let payload = {};
    const rest = args.slice(1).join(' ').trim();
    if (rest) {
      try {
        payload = JSON.parse(rest);
      } catch (err) {
        throw new Error(`could not read those arguments as JSON: ${rest}`);
      }
    }
    return JSON.stringify(await session.send(cmd, payload));
  },

  // Make the window big enough to be worth photographing. Under the debug
  // runtime the game opens at about 518x422, at which nothing on screen can be
  // read. Do this once, after `ready`, before any `shot`.
  async maximize(session) {
    const result = await runHelper(session, WINDOW_PS1, ['-Maximize']);
    return `the window is now ${result.width}x${result.height}`;
  },

  // resize <width> <height>
  async resize(session, args) {
    const [width, height] = args;
    if (width === undefined || height === undefined) {
      throw new Error('resize needs a width and a height: resize 1600 900');
    }
    const result = await runHelper(session, WINDOW_PS1,
      ['-Width', String(Number(width)), '-Height', String(Number(height))]);
    return `the window is now ${result.width}x${result.height}`;
  },

  // click <x> <y> [left|right]
  //
  // X and Y ARE PIXELS ON THE LAST SCREENSHOT, measured from the top-left corner
  // of the captured image. The picture is the whole window, title bar included,
  // so a position read straight off the image is the position to pass — no
  // arithmetic, no allowance for borders.
  //
  // This synthesises real input: it brings the game to the front and moves the
  // actual mouse. The machine is not usable while a clicking script runs. It
  // refuses rather than clicking when the game did not come to the front, since
  // a click that lands in the wrong window is worse than a step that stops.
  //
  // IT CLICKS TWICE, ABOUT A SECOND APART, because once does not work. That rule
  // was written down for the battle board — first click arms, second commits —
  // but it holds in the town too: a lone click on the great hall did nothing on
  // two separate runs, while the same click repeated opened it every time. Add
  // `once` as a fourth word for a single click, which is what you want to arm a
  // battle action without committing it.
  //
  // Prefer the bridge for anything inside a battle; this is for the screens the
  // bridge cannot reach at all.
  async click(session, args) {
    const [x, y, button, once] = args;
    if (x === undefined || y === undefined) {
      throw new Error('click needs a position from the last screenshot: click 640 400');
    }
    const extra = ['-X', String(Number(x)), '-Y', String(Number(y))];
    if (button) {
      extra.push('-Button', String(button));
    }
    if (String(once).toLowerCase() === 'once') {
      extra.push('-Repeat', '1');
    }
    const result = await runHelper(session, INPUT_PS1, extra);
    return `clicked ${result.button} x${result.clicks} at ${result.at} (window ${result.window})` +
      (result.warning ? `
  WARNING: ${result.warning}` : '');
  },

  // zoom <x> <y> <w> <h> [scale] [name]
  //
  // A magnified crop of a fresh capture, in the same pixel space as `shot` and
  // `click`. This is what makes clicking accurate rather than approximate: on a
  // full 1938x1038 picture a small button's centre is a guess, and a guess is
  // how you end up clicking the wrong thing. Take a `shot`, find roughly where
  // the control is, `zoom` that region, then read the exact position off the
  // magnified picture and divide back down.
  async zoom(session, args) {
    const [x, y, w, h, scale, name] = args;
    if (x === undefined || y === undefined || w === undefined || h === undefined) {
      throw new Error('zoom needs a region: zoom 560 110 200 110');
    }
    const file = path.join(OUTPUT_DIR, `${stamp()}-${name || 'zoom'}.png`);
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    const factor = Number(scale || 4);
    const result = await runHelper(session, SCREENSHOT_PS1, [
      '-Out', file,
      '-CropX', String(Number(x)), '-CropY', String(Number(y)),
      '-CropW', String(Number(w)), '-CropH', String(Number(h)),
      '-Zoom', String(factor),
    ]);
    return `${result.path}
  region (${x},${y}) ${w}x${h} magnified ${factor}x — ` +
      `divide a position on it by ${factor} and add (${x},${y}) to get a click position`;
  },

  // shot [name]
  async shot(session, args) {
    const result = await takeScreenshot(session, args[0]);
    return `${result.path} (${result.width}x${result.height}, ${result.bytes} bytes)` +
      (result.warning ? `\n  WARNING: ${result.warning}` : '');
  },

  async sleep(session, args) {
    const ms = Number(args[0] || 1000);
    await new Promise(resolve => setTimeout(resolve, ms));
    return `waited ${ms}ms`;
  },

  async quit() {
    return { stop: true };
  },
};

/**
 * Run one line.
 *
 * `try <command>` is a prefix rather than a command of its own, because what it
 * changes is how a failure is treated rather than what is done. It exists for
 * the refusals: the bridge answers an illegal request with an ordinary reply
 * saying no, and checking that the right things ARE refused is half of testing
 * it. Without this, the first deliberate refusal ends the run.
 */
async function runCommand(session, line) {
  const parts = line.trim().split(/\s+/);

  if (parts[0] === 'try') {
    const inner = parts.slice(1).join(' ');
    if (!inner) {
      throw new Error('try needs a command to try: try move 99 99');
    }
    try {
      const result = await runCommand(session, inner);
      return `(allowed) ${result}`;
    } catch (err) {
      return `(refused, as expected) ${err.message}`;
    }
  }

  const verb = parts[0];
  const handler = COMMANDS[verb];
  if (!handler) {
    throw new Error(
      `no such command "${verb}". Known: try, ${Object.keys(COMMANDS).sort().join(', ')}`
    );
  }
  return handler(session, parts.slice(1));
}

// -------------------------------------------------------------------------
// Running it
// -------------------------------------------------------------------------

function readStdin() {
  return new Promise(resolve => {
    if (process.stdin.isTTY) {
      resolve([]);
      return;
    }
    const lines = [];
    const reader = readline.createInterface({ input: process.stdin });
    reader.on('line', line => lines.push(line));
    reader.on('close', () => resolve(lines));
  });
}

async function main() {
  const argv = process.argv.slice(2);
  const mode = argv[0] || 'smoke';

  if (mode === '--help' || mode === '-h' || mode === 'help') {
    say('node .claude/skills/run-bsf-client/driver.js <smoke|battle|camp|shell> [--landing versus|camp]');
    say('');
    say('  smoke   launch, log in, photograph the screen');
    say('  battle  launch, start a practice battle, step a turn, photograph it');
    say('  camp    launch into the town instead, and photograph it');
    say('  shell   launch, then run one command per line from stdin');
    say('');
    say('  --landing camp   land in the town, from which the great hall, mead house');
    say('                   and proving grounds are reachable by clicking. The default,');
    say('                   versus, goes straight to the match search.');
    say('');
    say(`commands: ${Object.keys(COMMANDS).sort().join(', ')}`);
    say('prefix any command with "try" to allow it to be refused without stopping the run');
    return 0;
  }

  // --landing may either come from the recipe or be given outright; given
  // outright it wins, so `battle --landing camp` is possible even though it is
  // an odd thing to want.
  let landing = null;
  const flagAt = argv.indexOf('--landing');
  if (flagAt >= 0) {
    landing = argv[flagAt + 1];
    if (!landing || (landing !== 'camp' && landing !== 'versus')) {
      say('--landing takes either "camp" or "versus".');
      return 2;
    }
  }

  let steps;
  if (mode === 'shell') {
    steps = (await readStdin()).map(l => l.replace(/#.*$/, '').trim()).filter(Boolean);
    landing = landing || 'versus';
  } else if (RECIPES[mode]) {
    steps = RECIPES[mode].steps.slice();
    landing = landing || RECIPES[mode].landing;
  } else {
    say(`unknown mode "${mode}". Try smoke, battle, camp, or shell — or --help.`);
    return 2;
  }

  // Built first and started second, so the shutdown below always has something
  // to shut down — including when starting is the thing that failed.
  const session = new GameSession({ name: `driver-${mode}`, landing: landing });
  let failure = null;

  say(`[driver] starting the game (mode: ${mode}, landing: ${landing}, ${steps.length} steps)`);
  say('[driver] this takes about half a minute; longer on a busy machine');

  try {
    await session.start();
    say('[driver] the channel opened, so this is our build');

    for (const step of steps) {
      const started = Date.now();
      let result;
      try {
        result = await runCommand(session, step);
      } catch (err) {
        say(`[fail] ${step}\n       ${err.message}`);
        failure = err;
        break;
      }
      if (result && result.stop) {
        say('[driver] quit');
        break;
      }
      const took = ((Date.now() - started) / 1000).toFixed(1);
      say(`[ok ${took}s] ${step}` + (result ? `\n  ${String(result).replace(/\n/g, '\n  ')}` : ''));
    }
  } catch (err) {
    say(`[fail] ${err.message}`);
    failure = err;
  }

  // ALWAYS close, and prefer closing politely. Forcing the game loses its own
  // log, which a failed run needs most of all.
  say('[driver] closing the game');
  let closedPolitely = false;
  try {
    ({ closedPolitely } = await session.stop());
  } catch (err) {
    say(`[driver] while closing: ${err.message}`);
  }

  say('');
  say(`transcript: ${session.transcriptPath}`);
  say(`run log:    ${session.runLogPath}`);

  if (!closedPolitely) {
    // Worth saying loudly even on a passing run: it is a real fault in the game
    // (issue #36) and the likeliest cause is closing while a unit was walking.
    say('');
    say('NOTE: the game had to be forced to close. The usual cause is closing while a');
    say('      unit was still walking, which wedges the game on its way out (issue #36).');
    say('      End with "ourturn" to leave the board still before shutting down.');
  }

  return failure ? 1 : 0;
}

main()
  .then(code => { process.exitCode = code; })
  .catch(err => {
    say(`[driver] ${err.stack || err.message}`);
    process.exitCode = 1;
  });
