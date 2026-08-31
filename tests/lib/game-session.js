// game-session.js — start the real game, talk to it, and shut it down again.
//
// WHAT THIS IS. One test-shaped object wrapped around a running copy of the
// game. It starts the game, waits for the game's own channel to call back
// (see ../relay.js), lets a test send commands and read replies, and closes the
// game down at the end. A test using it reads as a list of things to check,
// with none of the process wrangling showing through.
//
// WHAT IT IS NOT. It is not a fake or a stand-in. Everything here drives the
// real game, on a real board, against the local server. That is the point: the
// claims worth testing on the client — what the board looks like, whether a
// turn steps — are claims only a running game can settle.
//
// THE SHAPE OF A RUN:
//
//   test process                            the game
//     |                                        |
//     |  1. listens on a free port             |
//     |  2. writes mods/host.json, naming ---> |
//     |     ../relay.js and that port          |
//     |  3. starts scripts/run-adl.ps1 ------> | starts, logs in
//     |                                        |  \_ starts relay.js as its helper
//     |  4. <=== relay connects, and from here on it is one conversation ===>
//     |  5. send commands, read replies, check what came back
//     |  6. close the game's window; force it only if that does not work
//     |  7. put the previous mods/host.json back
//
// TWO THINGS IT DELIBERATELY DOES NOT GUESS. It never waits a fixed number of
// seconds for the game to be ready: it waits for the messages that say so. And
// it never assumes the game it is driving is our own build: if the channel never
// opens, the run fails saying exactly that, because the shipped copy of the game
// has no channel to open.

'use strict';

const fs = require('fs');
const net = require('net');
const path = require('path');
const { spawn, execFile } = require('child_process');

const REPO_ROOT = path.resolve(__dirname, '..', '..');
const RELAY_PATH = path.join(REPO_ROOT, 'tests', 'relay.js');
const LAUNCHER_PATH = path.join(REPO_ROOT, 'scripts', 'run-adl.ps1');
const OUTPUT_DIR = path.join(REPO_ROOT, '_build', 'tests');

// ONE RUN AT A TIME, and this file is how a second one finds out.
//
// There is one game installed, with one slot naming its helper program, and
// every run rewrites that slot. Two runs at once would hand each other the wrong
// port and then put each other's settings back — which does not look like a
// clash, it looks like a flaky game. Worth knowing: `node --test` runs test
// FILES side by side, so the day a second test file exists this stops being
// hypothetical. Hence a lock rather than a warning in the documentation.
const LOCK_PATH = path.join(OUTPUT_DIR, 'one-run-at-a-time.lock');

// The same defaults scripts/run-adl.ps1 uses. Each can be overridden from the
// environment, so a machine with the game somewhere else needs no code change.
const DEFAULTS = {
  gamePath: process.env.BSF_GAME_PATH ||
    'C:\\Program Files (x86)\\Steam\\steamapps\\common\\The Banner Saga Factions\\win32',
  serverUrl: process.env.BSF_SERVER_URL || 'http://localhost:8082/',
  username: process.env.BSF_USERNAME || 'test2',
  steamId: process.env.BSF_STEAM_ID || '123456',
  // Where the player ends up after logging in: 'versus' for the match search,
  // 'camp' for the town the great hall and mead house open off. Everything
  // written before this option existed lands in versus, so that stays default.
  landing: process.env.BSF_LANDING || 'versus',
};

// How long to give each part of the run before calling it a failure. Generous,
// because these are real waits on a real game — but never infinite, so a stuck
// run reports what it was waiting for instead of hanging until somebody notices.
const TIMEOUTS = {
  channelOpens: 90000,   // launch, log in, and the helper calling back
  reply: 15000,          // one command and its answer
  gameCloses: 20000,     // the window closing after we ask it to
  lock: 180000,          // another run of this test finishing and letting go
};

const POLL_EVERY_MS = 500;

/** Write to a log only while it is still open. */
function writeIfOpen(stream, text) {
  // Closing a log while something is still writing to it raises an error that
  // nothing is listening for, which would end the run — after every check had
  // already passed, which is the worst possible moment to be confusing.
  if (stream && !stream.writableEnded && !stream.destroyed) {
    stream.write(text);
  }
}

function nowStamp() {
  return new Date().toISOString().replace(/[:.]/g, '-').replace('T', '_').slice(0, 19);
}

/** A promise that rejects, rather than hangs, when something takes too long. */
function withTimeout(promise, ms, what) {
  let timer;
  const bell = new Promise((_, reject) => {
    timer = setTimeout(() => {
      const err = new Error(`gave up after ${(ms / 1000).toFixed(0)}s waiting for ${what}`);
      // Marked so a poll can tell "this answer was slow" from "this check
      // failed". Swallowing both would turn a real failure into a timeout.
      err.timedOut = true;
      reject(err);
    }, ms);
  });
  return Promise.race([promise, bell]).finally(() => clearTimeout(timer));
}

class GameSession {
  constructor(options) {
    this.options = Object.assign({}, DEFAULTS, options);
    this.name = options && options.name ? options.name : 'run';

    this.server = null;      // our listening socket, waiting for the relay
    this.socket = null;      // the line to the relay once it calls back
    this.launcher = null;    // the PowerShell process running run-adl.ps1
    this.launcherOutput = [];
    this.launcherExited = null;

    this.nextId = 1;
    this.awaitingReply = new Map();  // id -> {resolve, reject, cmd}
    this.messages = [];              // everything the game has said, parsed
    this.watchers = new Set();       // callbacks wanting to see new messages

    this.transcript = null;
    this.runLog = null;
    this.previousHostJson = null;    // so we can put the developer's own back
    this.hostJsonPath = null;
    this.stopped = false;
    this.closedPolitely = false;
    this.lockHeld = false;
    this.safetyNet = null;           // puts the game folder back if we are killed
  }

  // ---------------------------------------------------------------------
  // Starting up
  // ---------------------------------------------------------------------

  /**
   * Start the game and wait until it will talk to us.
   *
   * Construct the session first and call this second, so that whoever holds the
   * session can always shut it down — including when starting is what failed.
   */
  async start() {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
    const stem = path.join(OUTPUT_DIR, `${nowStamp()}-${this.name}`);
    this.transcriptPath = `${stem}-transcript.jsonl`;
    this.runLogPath = `${stem}-run.log`;
    this.transcript = fs.createWriteStream(this.transcriptPath);
    this.runLog = fs.createWriteStream(this.runLogPath);
    // A log that cannot be written must never end the run. Say so and carry on.
    this.transcript.on('error', err =>
      process.stderr.write(`could not write the transcript: ${err.message}\n`));
    this.runLog.on('error', err =>
      process.stderr.write(`could not write the run log: ${err.message}\n`));

    // Everything from here on can leave something behind — a listening socket, a
    // rewritten setting in the game folder, a running game — so all of it is
    // covered, not just the wait at the end.
    try {
      await this._checkTheGroundIsClear();
      await this._takeTheLock();

      const port = await this._listen();
      this.note(`listening on port ${port}`);
      this._installRelayAsHelper(port);
      this._launchTheGame();

      // The helper calls back the moment the game first talks to the server,
      // which is the login. Until then there is nothing to talk to.
      await this._untilChannelOpens();
    } catch (err) {
      // Never leave a game running, a socket listening, or the game folder
      // rewritten behind a failed start.
      await this.stop();
      throw new Error(
        `${err.message}\n\n` +
        'The channel only exists in our own build, so the usual causes are: the ' +
        'installed game is the shipped copy rather than ours, the server is not ' +
        'running, or AIR_HOME is unset.\n\n' +
        `What the launcher said:\n${this._lastLauncherOutput()}\n\n` +
        `Full run log: ${this.runLogPath}`
      );
    }
  }

  // ---------------------------------------------------------------------
  // One run at a time
  // ---------------------------------------------------------------------

  /** Wait for any other run to finish, then claim the game install. */
  async _takeTheLock() {
    const deadline = Date.now() + TIMEOUTS.lock;
    for (;;) {
      try {
        // "wx" means create it, and fail if somebody else already has.
        const handle = fs.openSync(LOCK_PATH, 'wx');
        fs.writeSync(handle, String(process.pid));
        fs.closeSync(handle);
        this.lockHeld = true;
        this._armTheSafetyNet();
        return;
      } catch (err) {
        if (err.code !== 'EEXIST') {
          throw err;
        }
        if (this._clearedAbandonedLock()) {
          continue;
        }
        if (Date.now() >= deadline) {
          throw new Error(
            `another run of this test has been holding ${LOCK_PATH} for ` +
            `${(TIMEOUTS.lock / 1000).toFixed(0)}s. Only one run at a time can ` +
            'drive the one installed game. If you are sure nothing else is ' +
            'running, delete that file.'
          );
        }
        this.note('another run holds the game; waiting for it to finish');
        await new Promise(resolve => setTimeout(resolve, 2000));
      }
    }
  }

  /** True if the lock belonged to a run that has since died, and we removed it. */
  _clearedAbandonedLock() {
    let owner;
    try {
      owner = Number(fs.readFileSync(LOCK_PATH, 'utf8').trim());
    } catch (err) {
      return false;
    }
    if (Number.isInteger(owner) && owner > 0) {
      try {
        // Signal 0 asks "is this still alive?" without disturbing it.
        process.kill(owner, 0);
        return false;
      } catch (err) {
        if (err.code === 'EPERM') {
          return false;   // alive, just not ours to signal
        }
      }
    }
    try {
      fs.rmSync(LOCK_PATH, { force: true });
      this.note(`cleared a lock left behind by run ${owner}, which is no longer running`);
      return true;
    } catch (err) {
      return false;
    }
  }

  _releaseLock() {
    if (!this.lockHeld) {
      return;
    }
    this.lockHeld = false;
    try {
      fs.rmSync(LOCK_PATH, { force: true });
    } catch (err) {
      // Nothing useful to do; the next run will see it is abandoned.
    }
  }

  /**
   * Put the game folder back even if this process is killed outright.
   *
   * Without this, a Ctrl+C in the wrong second leaves the game pointing at a
   * relay that will never answer — and, worse, the NEXT run would read that as
   * "the developer's own setting" and faithfully restore it, making a temporary
   * mess permanent.
   */
  _armTheSafetyNet() {
    if (this.safetyNet) {
      return;
    }
    this.safetyNet = () => {
      this._restoreHostJson();
      this._releaseLock();
    };
    this.onInterrupt = () => {
      this.safetyNet();
      process.exit(130);
    };
    process.on('exit', this.safetyNet);
    process.on('SIGINT', this.onInterrupt);
    process.on('SIGBREAK', this.onInterrupt);
  }

  _disarmTheSafetyNet() {
    if (!this.safetyNet) {
      return;
    }
    process.off('exit', this.safetyNet);
    process.off('SIGINT', this.onInterrupt);
    process.off('SIGBREAK', this.onInterrupt);
    this.safetyNet = null;
  }

  /** Refuse to start on the conditions that otherwise produce baffling failures. */
  async _checkTheGroundIsClear() {
    if (!fs.existsSync(this.options.gamePath)) {
      throw new Error(
        `No game installed at ${this.options.gamePath}. ` +
        'Set BSF_GAME_PATH if yours lives somewhere else.'
      );
    }
    if (!fs.existsSync(LAUNCHER_PATH)) {
      throw new Error(`Missing the launcher script at ${LAUNCHER_PATH}`);
    }
    await this._checkTheServerIsUp();
  }

  /**
   * The game cannot get past its login without the server, and the failure that
   * produces is a poor one to debug: the run spends half a minute starting a
   * game, then reports that the login came back with status 0, which says
   * nothing about why. Ask first, and say the useful sentence instead.
   */
  _checkTheServerIsUp() {
    const url = new URL(this.options.serverUrl);
    const port = Number(url.port) || (url.protocol === 'https:' ? 443 : 80);
    return new Promise((resolve, reject) => {
      const probe = net.createConnection({ host: url.hostname, port: port });
      const giveUp = message => {
        probe.destroy();
        reject(new Error(
          `Nothing is answering at ${this.options.serverUrl} (${message}). The game ` +
          'cannot get past its login without it — start bsf-server\\start-server.bat, ' +
          'or set BSF_SERVER_URL if yours is somewhere else.'
        ));
      };
      probe.setTimeout(3000);
      probe.on('connect', () => { probe.destroy(); resolve(); });
      probe.on('timeout', () => giveUp('it did not answer in time'));
      probe.on('error', err => giveUp(err.message));
    });
  }

  _listen() {
    return new Promise((resolve, reject) => {
      this.server = net.createServer(socket => this._onRelayConnected(socket));
      this.server.on('error', reject);
      // Port 0 means "any free one", so two runs can never collide over a
      // number somebody picked out of the air.
      this.server.listen(0, '127.0.0.1', () => resolve(this.server.address().port));
    });
  }

  /**
   * Point the game's helper slot at our go-between.
   *
   * The descriptor names the file in this repository by its full path rather
   * than copying it into the game folder, so there is only ever one copy and it
   * cannot quietly fall behind the one being edited. Whatever was there before
   * is put back when the run ends.
   */
  _installRelayAsHelper(port) {
    const modsDir = path.join(this.options.gamePath, 'mods');
    fs.mkdirSync(modsDir, { recursive: true });
    this.hostJsonPath = path.join(modsDir, 'host.json');

    // What is there now is usually the developer's own setting, to be handed
    // back untouched at the end. But if a previous run was killed before it
    // could tidy up, what is there is OUR setting from that run — and treating
    // that as "theirs" would write it back at the end and make the loss
    // permanent. So: recognise our own handwriting and keep nothing.
    const existing = fs.existsSync(this.hostJsonPath)
      ? fs.readFileSync(this.hostJsonPath)
      : null;
    this.previousHostJson = this._isOurOwnDescriptor(existing) ? null : existing;
    if (existing && this.previousHostJson === null) {
      this.note('the game was still pointing at a previous run of this test; not keeping that');
    }

    const descriptor = {
      program: process.execPath,             // the same Node running this test
      args: [RELAY_PATH, String(port)],
    };
    fs.writeFileSync(this.hostJsonPath, JSON.stringify(descriptor, null, 2));
    this.note(`the game's helper is now: ${descriptor.program} ${descriptor.args.join(' ')}`);
  }

  /** Did this test write the setting sitting in the game folder? */
  _isOurOwnDescriptor(contents) {
    if (!contents) {
      return false;
    }
    try {
      const parsed = JSON.parse(contents.toString('utf8'));
      return Array.isArray(parsed.args) &&
        parsed.args.some(arg => String(arg) === RELAY_PATH);
    } catch (err) {
      // Unreadable, so certainly not ours. Leave it alone and put it back.
      return false;
    }
  }

  _launchTheGame() {
    const args = [
      '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', LAUNCHER_PATH,
      '-GamePath', this.options.gamePath,
      '-ServerUrl', this.options.serverUrl,
      '-Username', this.options.username,
      '-SteamId', this.options.steamId,
      '-Landing', this.options.landing,
    ];
    this.note(`starting: powershell ${args.join(' ')}`);
    this.launcher = spawn('powershell.exe', args, { windowsHide: true });

    const keep = chunk => {
      const text = chunk.toString();
      this.launcherOutput.push(text);
      writeIfOpen(this.runLog, text);
      if (process.env.BSF_TEST_VERBOSE === '1') {
        process.stderr.write(text);
      }
    };
    this.launcher.stdout.on('data', keep);
    this.launcher.stderr.on('data', keep);
    this.launcher.on('error', err => {
      this._abandonEveryone(new Error(`could not start the launcher: ${err.message}`));
    });

    this.launcherExited = new Promise(resolve => {
      this.launcher.on('exit', code => {
        this.note(`the launcher exited with code ${code}`);
        resolve(code);
        // Anything still waiting on the game is never going to be answered.
        this._abandonEveryone(new Error(
          `the game stopped before the test was done (launcher exit code ${code}).\n` +
          this._lastLauncherOutput()
        ));
      });
    });
  }

  /** Resolves once the relay has connected and the game has said hello. */
  _untilChannelOpens() {
    return this.waitFor(
      'the game to announce its channel is open',
      message => message.event === 'BRIDGE_READY',
      { timeoutMs: TIMEOUTS.channelOpens }
    );
  }

  _onRelayConnected(socket) {
    if (this.socket) {
      // A second game is talking to us. Refuse it rather than interleave two
      // conversations on one line.
      this.note('a second helper tried to connect; refused');
      socket.destroy();
      return;
    }
    this.socket = socket;
    this.note('the game\'s helper connected');

    let buffered = '';
    socket.setEncoding('utf8');
    socket.on('data', chunk => {
      buffered += chunk;
      let breakAt;
      while ((breakAt = buffered.indexOf('\n')) >= 0) {
        const line = buffered.slice(0, breakAt).replace(/\r$/, '');
        buffered = buffered.slice(breakAt + 1);
        if (line.length > 0) {
          this._onLine(line);
        }
      }
    });
    socket.on('error', err => this.note(`the line to the game broke: ${err.message}`));
    socket.on('close', () => {
      if (this.socket !== socket) {
        return;
      }
      // Forget the dead line. Without this, later commands are written into
      // nothing and simply time out one by one, and a replacement helper — the
      // game starts up to three — would be turned away as "a second helper",
      // silencing the channel for good with nothing to show why.
      this.socket = null;
      this.note('the game closed the line');
      if (!this.stopped) {
        this._abandonEveryone(new Error(
          'the game closed the channel while the test was still using it — its ' +
          'helper may have crashed.\n' +
          `Transcript so far: ${this.transcriptPath}`
        ));
      }
    });
  }

  // ---------------------------------------------------------------------
  // Listening
  // ---------------------------------------------------------------------

  _onLine(line) {
    // Written down one line at a time and flushed as it arrives, so a run that
    // dies mid-battle still leaves behind everything it had heard.
    writeIfOpen(this.transcript, line + '\n');

    let message;
    try {
      message = JSON.parse(line);
    } catch (err) {
      this.note(`could not read a line as JSON: ${line.slice(0, 200)}`);
      return;
    }

    if ((message.event === 'RESULT' || message.event === 'ERROR') &&
        this.awaitingReply.has(message.id)) {
      const waiting = this.awaitingReply.get(message.id);
      this.awaitingReply.delete(message.id);
      if (message.event === 'ERROR') {
        waiting.reject(new Error(`the game refused "${waiting.cmd}": ${message.message}`));
      } else {
        waiting.resolve(message.result);
      }
    }

    this.messages.push(message);
    for (const watcher of Array.from(this.watchers)) {
      watcher(message);
    }
  }

  /**
   * Wait for a message matching `predicate`.
   *
   * It looks at what has already arrived before it starts waiting. That matters
   * more than it sounds: the messages worth waiting for — the roster arriving,
   * the player landing somewhere — often turn up while the test is still busy
   * checking the last thing, and a waiter that only watched the future would sit
   * there until it timed out over a message it had already been sent.
   */
  waitFor(what, predicate, { timeoutMs = TIMEOUTS.reply } = {}) {
    for (const message of this.messages) {
      if (predicate(message)) {
        return Promise.resolve(message);
      }
    }
    const arrival = new Promise((resolve, reject) => {
      const watcher = message => {
        if (predicate(message)) {
          this.watchers.delete(watcher);
          resolve(message);
        }
      };
      this.watchers.add(watcher);
      this._onAbandon(err => {
        this.watchers.delete(watcher);
        reject(err);
      });
    });
    return withTimeout(arrival, timeoutMs, what);
  }

  /**
   * Ask the game something repeatedly until the answer is the one wanted.
   * `check` is handed the reply and returns either a value to keep or a falsy
   * value meaning "not yet".
   */
  async until(what, check, { timeoutMs = 60000, everyMs = POLL_EVERY_MS } = {}) {
    const deadline = Date.now() + timeoutMs;
    let slowAnswer = null;
    for (;;) {
      try {
        const got = await check();
        if (got) {
          return got;
        }
        slowAnswer = null;
      } catch (err) {
        // A slow answer is not a failure. The game is single-threaded, and
        // loading a battle can block it for longer than one reply is allowed —
        // so keep asking until OUR deadline rather than failing at the first
        // reply's much shorter one. Anything else (a failed check inside the
        // poll, say) is a real failure and goes straight up.
        if (!err.timedOut) {
          throw err;
        }
        slowAnswer = err.message;
      }
      if (Date.now() >= deadline) {
        throw new Error(
          `gave up after ${(timeoutMs / 1000).toFixed(0)}s waiting for ${what}` +
          (slowAnswer ? `; the game also stopped answering (${slowAnswer})` : '') +
          `\nWhat the game said is in ${this.transcriptPath}`
        );
      }
      await new Promise(resolve => setTimeout(resolve, everyMs));
    }
  }

  // ---------------------------------------------------------------------
  // Talking
  // ---------------------------------------------------------------------

  /** Send one command and wait for its answer. */
  send(cmd, args = {}, { timeoutMs = TIMEOUTS.reply } = {}) {
    if (!this.socket) {
      return Promise.reject(new Error(`cannot send "${cmd}": no line to the game`));
    }
    const id = this.nextId++;
    // The command and its number go on LAST, so a command's own arguments can
    // never overwrite the number a reply is matched by. `battle_move` and
    // `battle_attack` will be the first commands to carry arguments at all.
    const line = JSON.stringify(Object.assign({}, args, { cmd: cmd, id: id }));

    const answer = new Promise((resolve, reject) => {
      this.awaitingReply.set(id, { resolve, reject, cmd });
      this._onAbandon(err => {
        this.awaitingReply.delete(id);
        reject(err);
      });
    });
    this.socket.write(line + '\n');
    this.note(`-> ${line}`);
    return withTimeout(answer, timeoutMs, `an answer to "${cmd}"`)
      .then(result => {
        this.note(`<- ${cmd}: ${JSON.stringify(result)}`);
        return result;
      });
  }

  // ---------------------------------------------------------------------
  // Shutting down
  // ---------------------------------------------------------------------

  /**
   * Close the game down and put the game folder back as it was.
   *
   * Asks the window to close first, which runs the game's own exit path — the
   * helper is told, and the game's log is written out properly. Only a game that
   * ignores that gets forced, because forcing it loses the log entirely, which is
   * the one piece of evidence a failed run most needs.
   *
   * Safe to call twice; the second call does nothing.
   */
  async stop() {
    if (this.stopped) {
      return { closedPolitely: this.closedPolitely };
    }
    this.stopped = true;

    let closedPolitely = false;
    try {
      if (this.launcher && this.launcher.exitCode === null) {
        await this._askTheWindowsToClose(this.launcher.pid);
        closedPolitely = await this._waitForLauncher(TIMEOUTS.gameCloses);
        if (!closedPolitely) {
          this.note('the game did not close when asked; forcing it');
          await this._forceKill(this.launcher.pid);
          await this._waitForLauncher(5000);
        }
      }
    } catch (err) {
      this.note(`while shutting down: ${err.message}`);
    }

    this.closedPolitely = closedPolitely;

    if (this.socket) {
      this.socket.destroy();
      this.socket = null;
    }
    if (this.server) {
      this.server.close();
      this.server = null;
    }
    this._restoreHostJson();
    this._releaseLock();
    this._disarmTheSafetyNet();

    // Stop listening to the game's output BEFORE closing the log it is written
    // to. The launcher prints its last couple of lines as it goes, and Node
    // delivers a child's "it exited" before its final output — so a chunk can
    // still arrive here. Writing it into a closed log raises an error nobody is
    // catching, which would end the run after every check had already passed.
    if (this.launcher) {
      this.launcher.stdout.removeAllListeners('data');
      this.launcher.stderr.removeAllListeners('data');
    }

    await Promise.all([
      new Promise(resolve => this.transcript.end(resolve)),
      new Promise(resolve => this.runLog.end(resolve)),
    ]);

    return { closedPolitely };
  }

  /**
   * Ask every window belonging to the game to close.
   *
   * The game runs as a grandchild of the launcher, so this walks down from the
   * launcher to find it rather than closing every copy of the runtime on the
   * machine — a developer with their own game open should not lose it because a
   * test finished.
   */
  _askTheWindowsToClose(rootPid) {
    const script = [
      `$rootPid = ${Number(rootPid)}`,
      '$all = Get-CimInstance Win32_Process | Select-Object ProcessId, ParentProcessId',
      '$found = @()',
      '$frontier = @($rootPid)',
      'while ($frontier.Count -gt 0) {',
      '  $next = @()',
      '  foreach ($p in $frontier) {',
      '    foreach ($c in $all) {',
      '      if ($c.ParentProcessId -eq $p -and $found -notcontains $c.ProcessId) {',
      '        $found += $c.ProcessId; $next += $c.ProcessId } } }',
      '  $frontier = $next }',
      'foreach ($id in $found) {',
      '  $proc = Get-Process -Id $id -ErrorAction SilentlyContinue',
      '  if ($proc -and $proc.MainWindowHandle -ne 0) {',
      '    Write-Output ("closing " + $proc.ProcessName + " " + $proc.Id)',
      '    $null = $proc.CloseMainWindow() } }',
    ].join('\n');

    return new Promise(resolve => {
      execFile('powershell.exe', ['-NoProfile', '-Command', script],
        { timeout: 15000 }, (err, stdout, stderr) => {
          if (err) {
            this.note(`asking the window to close did not work: ${err.message}`);
          }
          const said = String(stdout || '').trim();
          this.note(said ? `close request: ${said}` : 'close request: no window found to close');
          if (stderr && String(stderr).trim()) {
            this.note(`close request said: ${String(stderr).trim()}`);
          }
          resolve();
        });
    });
  }

  _forceKill(rootPid) {
    return new Promise(resolve => {
      execFile('taskkill', ['/PID', String(rootPid), '/T', '/F'],
        { timeout: 10000 }, () => resolve());
    });
  }

  _waitForLauncher(ms) {
    if (!this.launcher || this.launcher.exitCode !== null) {
      return Promise.resolve(true);
    }
    return Promise.race([
      this.launcherExited.then(() => true),
      new Promise(resolve => setTimeout(() => resolve(false), ms)),
    ]);
  }

  _restoreHostJson() {
    if (!this.hostJsonPath) {
      return;
    }
    try {
      if (this.previousHostJson === null) {
        fs.rmSync(this.hostJsonPath, { force: true });
      } else {
        fs.writeFileSync(this.hostJsonPath, this.previousHostJson);
      }
      this.note('put the game\'s own helper setting back');
    } catch (err) {
      this.note(`could not restore ${this.hostJsonPath}: ${err.message}`);
    }
    this.hostJsonPath = null;
  }

  // ---------------------------------------------------------------------
  // Housekeeping
  // ---------------------------------------------------------------------

  /** Register a callback for "the game is gone, give up on whatever you wanted". */
  _onAbandon(callback) {
    if (!this.abandonHandlers) {
      this.abandonHandlers = new Set();
    }
    if (this.abandonReason) {
      callback(this.abandonReason);
      return;
    }
    this.abandonHandlers.add(callback);
  }

  _abandonEveryone(reason) {
    this.abandonReason = reason;
    for (const callback of Array.from(this.abandonHandlers || [])) {
      callback(reason);
    }
    if (this.abandonHandlers) {
      this.abandonHandlers.clear();
    }
  }

  _lastLauncherOutput(lines = 25) {
    const all = this.launcherOutput.join('').split('\n');
    return all.slice(-lines).join('\n').trim();
  }

  /** A line for the run log — never for the game, which only reads commands. */
  note(message) {
    const line = `[${new Date().toISOString().slice(11, 23)}] ${message}\n`;
    writeIfOpen(this.runLog, line);
    if (process.env.BSF_TEST_VERBOSE === '1') {
      process.stderr.write(line);
    }
  }
}

module.exports = { GameSession };
