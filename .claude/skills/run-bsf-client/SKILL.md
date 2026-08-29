---
name: run-bsf-client
description: Build, install, launch and drive the Banner Saga Factions game client. Use when asked to run or start the client, play or step a practice battle, read the battle board, click through the town to the great hall or roster screens, take a screenshot of the game, or check that a client change works in the real running game rather than only in tests.
---

Start the real game and drive it from a script. The handle is
`.claude/skills/run-bsf-client/driver.js` — it launches the client, talks to it over
the mod bridge (a one-line-of-JSON channel built into our build of the game),
clicks the window, and photographs it. One command per line of standard input.

**Two halves, and which one you need depends on the screen.** The bridge reaches a
battle and nothing else — it can start one, read the board and step turns without a
screen at all. Every other screen the game has (the town, the great hall where the
roster lives, the mead house) is reachable only the way a player reaches it, by
clicking. Land at `camp` for those.

All paths below are relative to `bsf-client/`.

**Read this if you are deciding *what* to check, not how:**
[`docs/driving-the-client.md`](../../../docs/driving-the-client.md) is the measured
account of how this game behaves — which questions belong to the bridge, which need
a picture, and what the game's logs will and will not tell you. This file is the
operating instructions; that one is the reasoning. Do not duplicate it here.

## Prerequisites

Three things, all of which the launcher checks and complains about by name:

```powershell
node --version              # v24.15.0 here; the driver needs Node 24+
echo $env:AIR_HOME          # C:\AirSDK\AIRSDK_51.3.2 — adl.exe lives in bin\ under it
Test-Path "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32"
```

The game must be installed, but it is **not** run from Steam — the Steam copy ships a
2013 runtime that cannot load a SWF built with the modern SDK. The launcher runs our
compiled file under the AIR debug runtime instead, reading assets out of the Steam
folder.

If any of those live elsewhere, say so with `BSF_GAME_PATH`, `BSF_SERVER_URL`,
`BSF_USERNAME`, `BSF_STEAM_ID` rather than editing anything.

## Setup: install our build over the shipped one

**Do this first, and check it every time.** The Steam folder holds the shipped game
file by default, and the shipped file has no mod bridge and no practice battle —
so the driver cannot drive it at all. This machine was in exactly that state when
this skill was written, because verifying the game files in Steam quietly puts the
original back.

```powershell
# What is installed, and what we last built?
Get-FileHash "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32\app.game.air.swf" -Algorithm MD5
Get-FileHash .\_build\app.game.air.swf -Algorithm MD5
```

Different hashes mean the shipped file is installed. Keep a copy of it, then put ours in:

```powershell
$install = "C:\Program Files (x86)\Steam\steamapps\common\The Banner Saga Factions\win32\app.game.air.swf"
Copy-Item $install .\_build\shipped-app.game.air.swf      # so it can be put back
Copy-Item .\_build\app.game.air.swf $install -Force
```

To go back to the shipped game, copy `_build\shipped-app.game.air.swf` over the
installed file (or verify the files in Steam). No administrator rights were needed
for either copy.

If `_build\app.game.air.swf` does not exist, build it first — see
[`docs/build-workflow.md`](../../../docs/build-workflow.md):

```powershell
powershell .\scripts\decompile.ps1        # only needed once
powershell .\scripts\apply-patches.ps1
powershell .\scripts\build.ps1 -Target windows
```

## Setup: start the server

The client cannot get past its login without it, and the driver refuses to start
rather than let that fail confusingly half a minute later.

```powershell
cd ..\bsf-server
node build\index.js          # already built; prints "Express server listening on port 8082"
```

**Use that line, not `start-server.bat`, while the driver is running.** The batch
file deliberately runs `Stop-Process -Name node -Force` to make sure no stale build
answers requests — and the driver, and the go-between the game talks through, are
both Node. Starting the server that way mid-run kills them. Rebuild with
`yarn build` separately if you need to.

## Run (agent path)

From `bsf-client/`. Two canned journeys and one open one:

```powershell
node .claude\skills\run-bsf-client\driver.js smoke     # launch, log in, photograph the screen
node .claude\skills\run-bsf-client\driver.js battle    # practice battle, stepped and photographed
node .claude\skills\run-bsf-client\driver.js camp      # land in the town instead, and photograph it
```

Measured end to end on this machine: `smoke` 43 seconds, `battle` 80, `camp` 50 —
about half a minute of each is the game starting up, and another 30 seconds of
`battle` is the battle scene loading.

For anything else, `shell` reads one command per line and stops at the first
failure. In PowerShell:

```powershell
@"
ready
maximize
battle
deploy
ourturn
board
shot my-picture
"@ | node .claude\skills\run-bsf-client\driver.js shell
```

The same thing from a POSIX shell, which is how it was verified:

```bash
node .claude/skills/run-bsf-client/driver.js shell <<'EOF'
ready
battle
deploy
ourturn
move 6 8
settle
board
EOF
```

### Reaching the roster and the other town screens

The bridge cannot get to them; clicking can. Land at camp, photograph the town,
click the building, then check where you ended up — `where` answers that without
another picture, because the game announces every arrival.

```bash
node .claude/skills/run-bsf-client/driver.js shell --landing camp <<'EOF'
ready loc_strand
maximize
sleep 8000
click 1140 320
sleep 3500
where
shot great-hall
zoom 420 140 720 240 2 roster-portraits
EOF
```

That is a verified run: it ends in `loc_great_hall`, with the party's portraits and
promotion badges legible in the magnified picture. `(1140, 320)` is the large flagged
building on the hill in a maximised 1938x1038 window — read the position off your own
`shot camp` rather than trusting that number at any other window size.

**The town's buildings and where each one goes**, from `TownState.handleLandscapeClick`:

| Hotspot | Goes to |
| --- | --- |
| `click_greathall` | the great hall — roster, promotions, and the match banners |
| `click_meadhouse` | the mead house, where units are hired |
| `click_provinggrounds` | the proving grounds |
| `click_hall_of_valor` | the hall of valor |
| `click_marketplace` | opens the marketplace panel over the town |
| `click_firetower` | **avoid** — a quit dialog, or straight out to the main menu |
| `click_trophytower`, `click_weavershut` | accepted, and do nothing |

The two burning braziers are the fire tower. Clicking one asks the game to quit, and
a modal dialog is exactly the thing that stalls a scripted run.

### The commands

| Command | What it does |
| --- | --- |
| `ready [place]` | Wait until the game has logged in **and** arrived somewhere. Always first. Name a place (`loc_strand`, `loc_versus`) to insist on that one. |
| `where` | The last place the game said it arrived at, and the trail of how it got there. The cheap way to tell whether a click worked. |
| `maximize` / `resize <w> <h>` | Make the window big enough to photograph. See Gotchas. |
| `ping` | Prove the channel answers. |
| `battle` | Start a practice battle and wait for the deploy screen. |
| `deploy` | Leave the deploy screen. A practice battle never leaves it on its own. |
| `ourturn` | Wait until it is the player's turn and that turn is uncommitted. |
| `settle` | Wait until nothing on the board is moving. |
| `board` | Print the board — both sides, tiles, and current/base numbers. |
| `state` | The raw reply from the game, unformatted. |
| `move <x> <y>` | Walk the acting unit to a tile. |
| `attack <target> [ability] [level]` | Have the acting unit swing. `ability` takes `strength` or `armor`. Ends the turn. |
| `endturn` | End the player's turn. |
| `shot [name]` | Photograph the window into `_build\tests\`. |
| `zoom <x> <y> <w> <h> [scale] [name]` | A magnified crop of a fresh capture, so a small control's position can be read exactly rather than guessed. |
| `click <x> <y> [left|right] [once]` | Click the window at a position read off the last picture. Clicks **twice** by default; see Gotchas. |
| `send <cmd> [json]` | Any bridge command, unmediated. |
| `sleep <ms>`, `quit` | |
| `try <command>` | Run it and carry on even if the game refuses — for checking that illegal things *are* refused. |

`move` and `attack` act on **the unit whose turn it is**; there is no way to make some
other unit act, exactly as on screen. Every command that does something checks the
game's answer and stops with the game's own sentence if it was refused. The full
contract, including about twenty-five refusal messages, is in
[`docs/mod-bridge.md`](../../../docs/mod-bridge.md).

Screenshots, transcripts and run logs all land in `_build\tests\`, named by the time
they were taken. The transcript is every line the game said, which is where to look
when a run fails.

## Run (human path)

```powershell
powershell .\scripts\run-adl.ps1
```

A window opens; press `Ctrl+Shift+A` for a practice battle, but **only after the
party has loaded** — earlier than that it crashes on a missing reference. The
launcher refuses to start if the installed file is not the one we built; pass
`-AllowUnpatched` to override that on purpose.

## Test

```powershell
node --test                                 # every client test
node --test tests\first-battle.test.js      # only this one
$env:BSF_TEST_VERBOSE=1; node --test        # and watch it work
```

Name the file or name nothing — **never name the folder**. `node --test tests\` runs
the folder as though it were one file and reports a baffling "cannot find module".

The tests and this driver share one installed game and one setting naming its
go-between, so only one can run at a time. The driver takes a lock and makes the
second run wait.

## Gotchas

Measured on this machine, on 2026-08-29, unless said otherwise.

- **The window opens at about 518×422.** That is the size in the application
  descriptor, and at it nothing on screen can be read — not the initiative bar, not
  the stat panel, not a banner. `maximize` takes it to 1938×1038. Put it after
  `ready` and before any `shot`. Nothing on screen suggests the window is smaller
  than it should be.

- **`ready` is true before the screen has caught up.** It reports a fact about the
  conversation — the game has told the server where the player went — and the game
  is still drawing when that is already true. A picture taken straight after it
  catches the loading spinner, which reads as a hung game. The `smoke` recipe waits
  six seconds for this reason; `battle` needs no wait because reaching the deploy
  screen is itself proof the scene drew.

- **A move is reported when it is accepted, not when it is finished.** `move 6 8`
  answered instantly and said the unit walked six steps — and the board still
  showed it on its starting tile 0.1 seconds later, two tiles along at one second,
  and arrived by three. Roughly two tiles a second. So a screenshot taken straight
  after a move photographs a unit mid-stride, and an assertion about where
  something stands reads the old tile. Use `settle`.

- **One click does nothing; it takes two.** Measured four times over: a lone click
  on the great hall did nothing on two separate runs, while the same click preceded
  by any other click, or simply repeated, opened it every time. The rule was already
  written down for the battle board — first click arms, second commits, and the two
  must be about a second apart — but it holds for town buildings too, so it is a
  property of the game's clicking rather than of targeting. `click` therefore clicks
  twice, spaced, by default. Pass `once` as a fourth word when you deliberately want
  a single one.

- **Clicking takes over the machine.** It brings the game to the front and moves the
  real mouse pointer, so the computer is not usable while a clicking script runs. It
  refuses rather than clicking if the game did not come to the front, because a click
  that lands in the wrong window is worse than a step that stops.

- **Click positions are pixels on the picture, title bar included.** The capture and
  the click use the same coordinate space, so a position read straight off a `shot`
  is the position to pass. When a control is small, `zoom` that region first and
  divide back down — reading a button's centre off a full 1938x1038 picture is a
  guess, and a guess is how you click the wrong thing.

- **An account that has not finished the tutorial cannot land at camp.** It is sent
  to the tutorial instead, which reads as the wrong screen rather than a refusal
  (`FactionsState.as:64`). The default account is fine; check others with the query
  below, looking at `completed_tutorial`.

- **Do not close the game while a unit is walking.** It wedges on the way out and
  has to be forced, which also loses the game's own log —
  [issue #36](https://github.com/Banner-Saga-Factions/BSF-Client/issues/36). The
  driver always tries to close politely and says so loudly if it could not. End a
  run with `ourturn` or `settle`.

- **Unit names are not unique, and both sides share them.** A practice battle
  mirrors the player's own party onto the opposite side, so there are two units
  called Warhawk with the same numbers. `move`/`attack` refuse an ambiguous name
  and print the full identifiers instead; identifiers read
  `{account}+{place in party}+{unit}`, so `123456+0+warhawk_start_0` is the
  player's and `ai+0+warhawk_start_0` is the computer's.

- **Which account you log in as decides what you can crash into.** The practice
  battle mirrors the party in the database, so a single armour-only unit in a party
  puts one on *both* sides and makes the known damage-overlay crash near-certain.
  The default account (`123456`, passed as `test2`) fields no Shieldbanger and so
  avoids it; three other accounts in the local database do carry one. Choose
  deliberately depending on whether you are trying to reproduce that crash or avoid
  it. Check with:
  `sqlite3 ..\bsf-server\data\bsf.db "select user_id, party_ids_json from accounts;"`

- **Deployment positions vary between runs**, and so do armour values, because
  standing next to an Axeman raises armour on both. Two runs of the same recipe
  will not print the same board. Do not assert on exact starting tiles.

- **Reading a stale log is easy and convincing.** While the game runs,
  `_build\adl-run.log` still holds the *previous* session, and the game's own log
  is locked shut until it exits. During a run, the driver's transcript in
  `_build\tests\` and the server's output are the readable witnesses.

## Troubleshooting

**"the game stopped before the test was done" / the channel never opened.**
Almost always the shipped game file rather than ours — see Setup. The launcher's
own output is quoted in the error and says so explicitly when the hashes differ.

**"Nothing is answering at http://localhost:8082/".** The server is not up. Start it
as above; do not use `start-server.bat` while a run is in progress.

**"AIR_HOME is not set."** Point it at the AIR SDK root, the folder with `bin\adl.exe`.

**"another run of this test has been holding … one-run-at-a-time.lock".** A previous
run was killed before it could tidy up. The driver clears the lock by itself if the
process that took it is gone; if it insists and you are sure nothing is running,
delete `_build\tests\one-run-at-a-time.lock`.

**The bridge worked yesterday and does nothing now.** Look at `mods\host.json` in the
game folder first. Every run rewrites it and puts it back at the end, so a run that
was killed halfway can leave it pointing at a go-between that will never answer.

**A click did nothing.** Most likely it was a single click — see Gotchas; `click`
does two by default, so this mainly bites when `once` was passed. Otherwise check
`where` before and after: it names the screen the game thinks it is on, which
separates "the click missed" from "the click worked and the screen looks the same".

**It landed in the tutorial instead of camp.** The account has not finished the
tutorial. Pick another:
`sqlite3 ..\bsf-server\data\bsf.db "select user_id, completed_tutorial from accounts;"`

**It stopped at the main menu and never announced arriving anywhere.** The run mode
ended up as DEVELOPER rather than FACTIONS, so `ReadyState` never entered the state
that leads to the town. `--factions` and `--developer` set the same single value and
the last one wins, which is why the camp landing orders them deliberately. If you
have edited the launcher's argument list, that is the thing to check.

**A screenshot came back tiny or blank.** Tiny means the window was never maximized.
Blank would mean the window refused to paint a copy of itself; the capture script
warns when an image is suspiciously small for its dimensions.
