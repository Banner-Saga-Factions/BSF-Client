// host.js — the spike mod host: a small helper program the game talks to.
//
// WHAT THIS IS FOR: proving the mod bridge can act as the control channel for
// testing the client, instead of driving the game by synthesising mouse clicks.
// It is deliberately small. It does three things:
//
//   1. Writes down every line the game sends, to transcript.jsonl next to itself.
//      That file is the evidence for "no credentials leak" — search it for a
//      password and you should find only [redacted].
//   2. Answers the game's readiness message with a ping, so one line in the game
//      log tells you the channel is alive AND that the patched build is running.
//   3. If a script.json sits beside it, sends those commands in order, and prints
//      each reply. That is how a test drives a battle without touching the mouse.
//
// THE THREE RULES A HOST MUST FOLLOW (see docs/mod-bridge.md):
//   - Standard output carries protocol lines only. Anything else corrupts it.
//   - Logging goes to the error channel; the game copies it into its own log,
//     tagged [modhost].
//   - Quit when input ends. The game cannot always kill us.
//
// This does NOT settle which language mod hosts should be written in. It is a
// test driver that happens to be the first host; see
// misc/Plan-Mod-Bridge-And-Scripting-Host.md for that open decision.

'use strict';

const fs = require('fs');
const path = require('path');

const TRANSCRIPT = path.join(__dirname, 'transcript.jsonl');
const SCRIPT_FILE = path.join(__dirname, 'script.json');

let nextId = 1;
// Replies we are still waiting on, by the id we stamped on the request.
const pending = new Map();

function log(message) {
  // The error channel — never standard output, which is protocol only.
  process.stderr.write(message + '\n');
}

function send(command) {
  const id = nextId++;
  const line = JSON.stringify(Object.assign({ id: id }, command));
  pending.set(id, command.cmd);
  process.stdout.write(line + '\n');
  log('-> ' + line);
  return id;
}

// Start a fresh transcript each run, so what you read is this session's.
try {
  fs.writeFileSync(TRANSCRIPT, '');
} catch (err) {
  log('could not start a transcript at ' + TRANSCRIPT + ': ' + err.message);
}

function record(line) {
  try {
    // Appended one line at a time and flushed immediately: the game force-kills
    // us on exit, so anything merely buffered would be lost.
    fs.appendFileSync(TRANSCRIPT, line + '\n');
  } catch (err) {
    // A failed transcript must never take the host down.
  }
}

// ---------------------------------------------------------------------------
// The optional script: an array of steps, each a command to send.
//   [ {"afterMs": 500, "cmd": "battle_state"},
//     {"afterMs": 1000, "cmd": "battle_end_turn"} ]
// afterMs is the wait before that step, counted from the step before it.
// ---------------------------------------------------------------------------

function runScript() {
  let steps;
  try {
    if (!fs.existsSync(SCRIPT_FILE)) {
      log('no script.json — idling, and recording everything the game sends');
      return;
    }
    steps = JSON.parse(fs.readFileSync(SCRIPT_FILE, 'utf8'));
  } catch (err) {
    log('script.json is unusable, ignoring it: ' + err.message);
    return;
  }
  if (!Array.isArray(steps) || steps.length === 0) {
    log('script.json holds no steps');
    return;
  }
  log('script.json: ' + steps.length + ' step(s) to run');

  let index = 0;
  const runNext = () => {
    if (index >= steps.length) {
      log('script finished');
      return;
    }
    const step = steps[index++];
    const wait = typeof step.afterMs === 'number' ? step.afterMs : 0;
    setTimeout(() => {
      const command = Object.assign({}, step);
      delete command.afterMs;
      if (!command.cmd) {
        log('step ' + index + ' has no "cmd", skipping it');
      } else {
        send(command);
      }
      runNext();
    }, wait);
  };
  runNext();
}

// ---------------------------------------------------------------------------
// Reading the game's messages: one JSON object per line.
// ---------------------------------------------------------------------------

function handle(line) {
  record(line);

  let message;
  try {
    message = JSON.parse(line);
  } catch (err) {
    // One bad line must not stop the host — the bridge's own note says a
    // malformed body corrupts only its own line.
    log('could not read a line as JSON: ' + line.slice(0, 200));
    return;
  }

  if (message.event === 'BRIDGE_READY') {
    log('bridge ready — this is the patched build, not the shipped one');
    send({ cmd: 'ping' });
    runScript();
    return;
  }

  if (message.event === 'RESULT' || message.event === 'ERROR') {
    const which = pending.get(message.id) || 'unknown command';
    pending.delete(message.id);
    if (message.event === 'ERROR') {
      log('<- ' + which + ' failed: ' + message.message);
    } else {
      log('<- ' + which + ' answered: ' + JSON.stringify(message.result));
    }
    return;
  }

  if (message.event === 'SHUTDOWN') {
    log('game is closing');
    return;
  }

  // Everything else is the traffic copy — far too noisy to print in full, so
  // just note what arrived. The transcript has the whole thing.
  if (message.event === 'HTTP_REQUEST' || message.event === 'HTTP_RESPONSE') {
    log('<- ' + message.event + ' ' + message.txn);
  }
}

let buffered = '';
process.stdin.setEncoding('utf8');
process.stdin.on('data', chunk => {
  buffered += chunk;
  let breakAt;
  while ((breakAt = buffered.indexOf('\n')) >= 0) {
    const line = buffered.slice(0, breakAt).replace(/\r$/, '');
    buffered = buffered.slice(breakAt + 1);
    if (line.length > 0) {
      handle(line);
    }
  }
});

// The host contract: input ending is the cue to quit.
process.stdin.on('end', () => {
  log('input ended, quitting');
  process.exit(0);
});

log('mod host started in ' + __dirname);
