// relay.js — the go-between that lets a test talk to the running game.
//
// WHY THIS EXISTS. The game starts its helper program itself, so a test cannot
// simply start the game and then strike up a conversation with it: the helper is
// downstream of the game, not upstream of it. This program is the smallest thing
// that turns that round the right way. The game starts it as its helper; it
// immediately calls back to a test that is already waiting on a numbered door
// (a "port") on this machine, and from then on it copies bytes between the two,
// in both directions, changing nothing.
//
// That means the test — not this file — owns everything a test should own: when
// the game starts, what to say to it, how long to wait, what counts as a
// failure, and when to shut the game down.
//
// THE THREE RULES A HELPER MUST FOLLOW (see docs/mod-bridge.md):
//   - Standard output carries protocol lines only. Anything else corrupts it.
//     This program only ever writes what the test sent, so the rule passes
//     straight through to the test.
//   - Logging goes to the error channel; the game copies it into its own log,
//     tagged [modhost].
//   - Quit when input ends. The game cannot always kill us.
//
// It is started as:  node relay.js <port>
// The test picks the port, writes it into mods/host.json, and is listening on it
// before the game is launched.

'use strict';

const net = require('net');

const CONNECT_ATTEMPTS = 20;
const CONNECT_RETRY_MS = 250;

function log(message) {
  // The error channel — never standard output, which is protocol only.
  process.stderr.write('relay: ' + message + '\n');
}

const port = Number(process.argv[2]);
if (!Number.isInteger(port) || port <= 0 || port > 65535) {
  log('needs the test\'s port number as its one argument, e.g. "node relay.js 45231"');
  process.exit(1);
}

// Anything the game says before the test is on the line is kept here rather than
// dropped. The game's very first message — the one announcing the channel is
// open — arrives the moment this program starts, which can be a fraction of a
// second before the connection is made, and losing it would cost the test its
// clearest signal that the right build is running.
let waiting = [];
let socket = null;
let gameHasGone = false;

process.stdin.on('data', chunk => {
  // Deliberately raw bytes, never text. Unit names in this game contain
  // characters like ð and ö, which take more than one byte each, and a chunk can
  // split one down the middle. Copying bytes through untouched cannot corrupt
  // them; decoding and re-encoding them here could.
  if (socket) {
    socket.write(chunk);
  } else {
    waiting.push(chunk);
  }
});

process.stdin.on('end', () => {
  // The host contract: input ending is the cue to quit.
  gameHasGone = true;
  log('the game closed the channel, so this go-between is done');
  process.exit(0);
});

function connect(attemptsLeft) {
  const attempt = net.createConnection({ port: port, host: '127.0.0.1' });

  attempt.on('connect', () => {
    socket = attempt;
    log('connected to the test on port ' + port);
    for (const chunk of waiting) {
      socket.write(chunk);
    }
    waiting = [];
    // What the test says goes to the game verbatim. `end: false` keeps the
    // game's input open if the test hangs up first — closing it would look to
    // the game like the helper had died.
    socket.pipe(process.stdout, { end: false });
    socket.on('close', () => {
      // The test has finished with us. Stay alive and quiet until the game
      // closes its side: quitting now would make the game think the helper had
      // crashed and start a fresh one, which nobody is waiting for.
      socket = null;
      log('the test hung up; idling until the game closes');
    });
  });

  attempt.on('error', err => {
    if (gameHasGone) {
      return;
    }
    if (socket) {
      // A failure on a connection that was working. Report it and go quiet
      // rather than take the game's helper down mid-battle.
      log('the line to the test broke: ' + err.message);
      socket = null;
      return;
    }
    if (attemptsLeft > 1) {
      setTimeout(() => connect(attemptsLeft - 1), CONNECT_RETRY_MS);
      return;
    }
    log('could not reach the test on port ' + port + ' (' + err.message + '). ' +
      'Nothing is driving this game; it will run normally.');
  });
}

connect(CONNECT_ATTEMPTS);
log('started, calling the test on port ' + port);
