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
// It takes half a minute on a quiet machine and twice that on a busy one, opens
// a real game window, and is deliberately not part of any automatic check-in
// run. From the bsf-client folder:
//
//   node --test                                   # every client test
//   node --test tests\first-battle.test.js        # only this one
//   $env:BSF_TEST_VERBOSE=1; node --test          # and watch it work
//
// Name the file, or nothing at all — but do not name the folder. `node --test
// tests\` looks like it should work and does not: Node runs the folder as though
// it were a single file and reports a confusing "cannot find module" instead.
//
// ONE AT A TIME. There is one installed game and every run rewrites the setting
// that names its helper program, so two runs at once would spoil each other.
// `node --test` runs test FILES side by side, so this matters as soon as a
// second test file exists. The driver takes a lock and makes the second run
// wait its turn; `--test-concurrency=1` avoids the wait altogether.
//
// If the game, the server or the login live somewhere else, say so rather than
// editing anything: BSF_GAME_PATH, BSF_SERVER_URL, BSF_USERNAME, BSF_STEAM_ID.
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
    // Built first and started second, so the tidy-up above is holding it even if
    // starting is the thing that fails.
    // Pin the landing this test asserts on. The option defaults from BSF_LANDING,
    // so a shell that had exported it would otherwise send this run to the town and
    // leave the test waiting ninety seconds for a place it never reaches.
    session = new GameSession({ name: 'first-battle', landing: 'versus' });
    await session.start();
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

    // DO NOT DROP THIS as one wait too many, and do not settle for waiting on
    // the roster instead. A draft that started the battle as soon as the roster
    // arrived got no battle at all: `battle_state` answered "not in a battle"
    // for two solid minutes, and nothing anywhere reported an error.
    //
    // The reason is not that the roster was missing. It is that the game had not
    // finished deciding where the player goes. The state that loads the factions
    // asks to be told when that load finishes and then never cancels the
    // request, so when it finishes the game jumps to the ranked match search —
    // wherever it has got to in the meantime, throwing away a battle started in
    // between. Waiting for the player to land means that jump has already
    // happened and there is nothing left to throw the battle away.
    //
    // The fingerprint of getting this wrong, if it ever comes back: a request to
    // start a versus match with no matching cancel after it. A healthy run
    // cancels, because starting the practice battle is what cancels it.
    //
    // The landing place is checked, not just the request: another state sends
    // the same request with a different place while the player is still queuing
    // to log in, and matching that one would put us right back where we started.
    // `loc_versus` is where run-adl.ps1's arguments land — see the note above.
    const landed = await session.waitFor(
      'the player to land in the versus screen',
      m => m.event === 'HTTP_REQUEST' &&
        String(m.url || '').includes('services/game/location') &&
        m.body === 'loc_versus',
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
    // Compared by identifier rather than by name. The identifier carries the
    // fighter's class and its place in the party — `123456+2+axeman_start_1`
    // against `ai+2+axeman_start_1` — where the name is only what the character
    // is called. Two different line-ups sharing the same six names would walk
    // straight past a check on names.
    const withoutSide = unit => unit.id.startsWith(unit.team + '+')
      ? unit.id.slice(unit.team.length + 1)
      : unit.id;
    const lineUpOf = side => side.map(withoutSide).sort();
    const namesOf = side => side.map(u => u.name).sort();

    assert.equal(mine.length, theirs.length,
      `the two sides should be the same size: ${mine.length} against ${theirs.length}`);
    assert.deepEqual(lineUpOf(theirs), lineUpOf(mine),
      'the computer\'s side should be a copy of the player\'s party, fighter for fighter');

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
        assert.equal(state.finished, false, 'the battle ended before control came back');
        return state.turn && state.turn.playerControlled && !state.turn.committed ? state : null;
      },
      { timeoutMs: PATIENCE.turnComesRound, everyMs: 1000 }
    );
    assert.ok(backToUs.turn.number > stepped[stepped.length - 1],
      'control should come back on a later turn than the last one stepped');

    console.log(`      stepped the player's turns ${stepped.join(', ')}, control back on ${backToUs.turn.number}`);
  });

  await t.test('the game closed when asked, without being forced', async () => {
    // CLOSE WHEN NOTHING IS MOVING. Closing the game mid-move wedges it, which
    // this test found on its first run. Tearing the board down empties the
    // stores of reusable sprites, but the on-board markers that draw from those
    // stores are never unhooked from the battle first — so anything that still
    // raises a battle event afterwards reaches for a store that is now nothing.
    // Interrupting a unit's walk is the one thing that still does, which is why
    // "is anything walking" decides it. The game then stops half-way out and has
    // to be forced. The step above leaves the board still, so this one closes
    // into quiet. Written up in docs/driving-the-client.md; it is a real fault in
    // the game rather than in this test, and not what this test is here to find.
    const { closedPolitely } = await session.stop();
    assert.equal(closedPolitely, true,
      'the game would not close when asked. First thing to check: was a unit still ' +
      'walking? Closing mid-move wedges the game on the way out (issue #36) — see ' +
      'docs/driving-the-client.md, "Closing the game while a unit is walking hangs it". ' +
      'Forcing it also loses the game\'s own log, which a failed run needs most.');
  });
});
