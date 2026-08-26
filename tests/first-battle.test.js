// first-battle.test.js — the first automated test of the game client.
//
// WHAT IT CHECKS. That a helper program can start the game, watch it log in,
// start a practice battle against the computer, read the board, step several
// turns, and close the game down again — with nobody touching the mouse.
//
// WHY THIS ONE FIRST. Most claims about the client cannot be settled by reading
// code: what the board holds, whether a turn actually advances, whether the
// thing that just launched is even our build. Those need the running game. This
// test walks the shortest path that touches all of them, so a change that breaks
// the game's spine fails here instead of in somebody's afternoon.
//
// WHAT IT NEEDS BEFORE IT WILL RUN:
//   - The local server up on port 8082  (bsf-server\start-server.bat)
//   - AIR_HOME pointing at the AIR SDK, as scripts\run-adl.ps1 requires
//   - Our own build of the game installed — scripts\build.ps1, then copy
//     _build\app.game.air.swf over the installed one
//
// It takes a minute or two, opens a real game window, and is deliberately not
// part of any automatic check-in run. From the bsf-client folder, start it with:
//
//   node --test                                   # every client test
//   node --test tests\first-battle.test.js        # only this one
//   $env:BSF_TEST_VERBOSE=1; node --test          # and watch it work
//
// Name the file, or nothing at all — but do not name the folder. `node --test
// tests\` looks like it should work and does not: Node runs the folder as though
// it were a single file and reports a confusing "cannot find module" instead.
//
// IT IS A TEST OF OUR BUILD, BY DEFINITION. The channel it drives, and the
// practice battle it starts, exist only in the copy we compile — the shipped
// game has neither. That is not a gap in the test: our build is what players are
// meant to end up with (see misc/Plan-Issue-12-Player-vs-AI-Public-Release.md),
// and the shipped copy is the legacy artefact. It does mean a failure here can
// never be blamed on the original game.
//
// Related reading: docs/driving-the-client.md (which jobs belong to this channel
// and which need a screenshot) and docs/mod-bridge.md (every command and every
// refusal it can answer with).

'use strict';

const { test } = require('node:test');
const assert = require('node:assert/strict');
const { GameSession } = require('./lib/game-session');

/** How long to let the game get itself to a given point. Real waits on a real game. */
const PATIENCE = {
  login: 90000,
  battleLoads: 120000,
  turnComesRound: 90000,
};

/** How many of the player's turns to step. Enough to prove turns advance and
 *  hand back and forth, without turning a smoke test into a whole battle. */
const TURNS_TO_STEP = 3;

test('a helper program can drive a practice battle from start to finish', async t => {
  let session = null;
  let atDeploy = null;

  // A backstop, not the shutdown itself: the run closes the game in its own last
  // step, and this only catches the case where something failed before then and
  // would otherwise leave a game running.
  t.after(async () => {
    if (session) {
      await session.stop();
      console.log(`      transcript: ${session.transcriptPath}`);
      console.log(`      run log:    ${session.runLogPath}`);
    }
  });

  await t.test('the channel opened, so this is our build', async () => {
    session = await GameSession.start({ name: 'first-battle' });
    const reply = await session.send('ping');
    assert.equal(reply, 'pong', 'the game should answer a ping with a pong');
  });

  await t.test('the game logged in and the roster arrived', async () => {
    const login = await session.waitFor(
      'the login to be answered',
      m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/auth/login'),
      { timeoutMs: PATIENCE.login }
    );
    assert.equal(login.success, true, `the server refused the login (status ${login.status})`);

    const account = await session.waitFor(
      'the account and roster to arrive',
      m => m.event === 'HTTP_RESPONSE' && String(m.url || '').includes('services/account/info'),
      { timeoutMs: PATIENCE.login }
    );
    assert.equal(account.success, true, `the server would not send the account (status ${account.status})`);

    // Landing somewhere is the game's own signal that it has finished setting
    // itself up: it is only sent once the config is loaded and the account has
    // been read, which is everything a battle needs to exist.
    //
    // DO NOT DROP THIS as one wait too many. A draft that started the battle as
    // soon as the roster arrived got no battle at all — `battle_state` answered
    // "not in a battle" for two solid minutes, with no error raised anywhere.
    const landed = await session.waitFor(
      'the player to land somewhere',
      m => m.event === 'HTTP_REQUEST' && String(m.url || '').includes('services/game/location'),
      { timeoutMs: PATIENCE.login }
    );
    console.log(`      logged in, and the player landed in: ${landed.body}`);
  });

  await t.test('a practice battle started and reached the deploy screen', async () => {
    const started = await session.send('start_ai_battle');
    assert.equal(started, 'ok', 'the game should accept the request to start a practice battle');

    // The battle has a scene to load, so ask repeatedly rather than guess how
    // long that takes on this machine.
    atDeploy = await session.until(
      'the battle to reach the deploy screen',
      async () => {
        const state = await session.send('battle_state');
        return state.inBattle && state.state === 'BattleStateDeploy' ? state : null;
      },
      { timeoutMs: PATIENCE.battleLoads, everyMs: 1000 }
    );

    assert.equal(atDeploy.online, false, 'a practice battle must not be an online one');
    assert.equal(atDeploy.finished, false, 'the battle should not be over before it starts');
    assert.equal(atDeploy.turn, null, 'nobody has taken a turn yet on the deploy screen');
  });

  await t.test('the board holds two mirrored sides of real fighters', async () => {
    const units = atDeploy.units;
    assert.ok(Array.isArray(units), 'the battle should report a list of units');
    assert.ok(units.length >= 2, `expected fighters on both sides, got ${units.length}`);

    const sides = new Map();
    for (const unit of units) {
      if (!sides.has(unit.team)) {
        sides.set(unit.team, []);
      }
      sides.get(unit.team).push(unit);
    }
    assert.equal(sides.size, 2, `expected exactly two sides, got ${[...sides.keys()].join(', ')}`);

    const [first, second] = [...sides.values()];
    const mine = first.every(u => u.playerControlled) ? first : second;
    const theirs = mine === first ? second : first;

    assert.ok(mine.every(u => u.playerControlled), 'one whole side should belong to the player');
    assert.ok(theirs.every(u => !u.playerControlled), 'the other whole side should belong to the computer');

    // The practice battle mirrors the player's own party into the opposite
    // deployment area, so the two sides should match fighter for fighter. If
    // this ever fails, the opponent is being built from something else.
    const namesOf = side => side.map(u => u.name).sort();
    assert.equal(mine.length, theirs.length,
      `the two sides should be the same size: ${mine.length} against ${theirs.length}`);
    assert.deepEqual(namesOf(theirs), namesOf(mine),
      'the computer\'s side should be a copy of the player\'s party');

    for (const unit of units) {
      const who = `${unit.name} [${unit.id}]`;
      assert.equal(unit.alive, true, `${who} should be alive at the deploy screen`);
      assert.ok(unit.tile && Number.isInteger(unit.tile.x) && Number.isInteger(unit.tile.y),
        `${who} should be standing on a tile, got ${JSON.stringify(unit.tile)}`);
      // Every fighter carries both numbers the on-screen panel shows. Scenery —
      // poles and the like — has no armour and is filtered out before it gets
      // here, so anything missing these is not scenery leaking through but a
      // fighter that failed to build.
      for (const stat of ['strength', 'armor']) {
        const value = unit.stats && unit.stats[stat];
        assert.ok(value && typeof value.current === 'number' && typeof value.base === 'number',
          `${who} should have a ${stat} of current and base, got ${JSON.stringify(value)}`);
      }
    }

    console.log(`      ${mine.length} against ${theirs.length}: ${namesOf(mine).join(', ')}`);
  });

  await t.test(`the deploy screen gives way and ${TURNS_TO_STEP} turns step`, async () => {
    // A practice battle never leaves the deploy screen on its own — the deploy
    // countdown is zero when a battle is offline, so no timer is ever created to
    // force it. Saying ready is the only way out, which is why a scripted battle
    // needs this command to exist at all.
    const ready = await session.send('battle_deploy_ready');
    assert.equal(ready.ok, true, `the game would not accept ready: ${ready.reason}`);
    assert.equal(ready.state, 'BattleStateTurnLocal', 'saying ready should start the fighting');

    const stepped = [];
    for (let i = 0; i < TURNS_TO_STEP; i++) {
      // Only ever the player's own turn. Ending the computer's turn works
      // sometimes and is refused other times — it commits its turn about half a
      // second after it finishes walking, and which side of that a request lands
      // on is not something a test can control. Waiting for our own turn sidesteps
      // the race entirely.
      const ours = await session.until(
        'the player\'s turn to come round',
        async () => {
          const state = await session.send('battle_state');
          assert.equal(state.finished, false, 'the battle ended before the test had stepped its turns');
          return state.turn && state.turn.playerControlled && !state.turn.committed ? state : null;
        },
        { timeoutMs: PATIENCE.turnComesRound, everyMs: 1000 }
      );

      const number = ours.turn.number;
      const ended = await session.send('battle_end_turn');
      assert.equal(ended.ok, true, `the game would not end turn ${number}: ${ended.reason}`);
      assert.equal(ended.turn, number, 'the reply should name the turn just ended');
      assert.equal(ended.next, number + 1, 'the next turn should be the one after it');
      stepped.push(number);
    }

    for (let i = 1; i < stepped.length; i++) {
      assert.ok(stepped[i] > stepped[i - 1],
        `turns should only ever go forward, got ${stepped.join(', ')}`);
    }

    // Wait for control to come back one last time. Worth checking on its own —
    // a turn has to come back from the computer, not merely leave the player —
    // and it leaves the board still, with nobody walking, which is what the
    // shutdown step below needs.
    const backToUs = await session.until(
      'control to come back from the computer one last time',
      async () => {
        const state = await session.send('battle_state');
        return state.turn && state.turn.playerControlled && !state.turn.committed ? state : null;
      },
      { timeoutMs: PATIENCE.turnComesRound, everyMs: 1000 }
    );
    assert.ok(backToUs.turn.number > stepped[stepped.length - 1],
      'control should come back on a later turn than the last one stepped');

    console.log(`      stepped the player's turns ${stepped.join(', ')}, control back on ${backToUs.turn.number}`);
  });

  await t.test('the game closed when asked, without being forced', async () => {
    // CLOSE WHEN NOTHING IS MOVING. This run found that closing the game while a
    // unit is walking hangs it: the game starts its own exit, tears the board
    // down, and interrupting the walk sets off a chain that asks the sprite pool
    // for a target indicator after that pool has already been emptied and set to
    // nothing — Error #1009 inside AnimClipSpritePool.addPool. The exit never
    // finishes and the game has to be forced. The step above therefore leaves the
    // board still before this one closes it. The hang is a real fault in the
    // game, written up in docs/driving-the-client.md; when it is fixed this
    // ordering stops mattering, and until then it is not what this test is for.
    const { closedPolitely } = await session.stop();
    assert.equal(closedPolitely, true,
      'the game should close on request; forcing it loses its log, which a failed run needs most');
  });
});
