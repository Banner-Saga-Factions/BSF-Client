# Changelog

What changed in this repository, newest first, written so a non-programmer can follow it. Each
entry links to the pull request that made the change.

The one earlier public build was the v2-beta pre-release of 2026-06-17; its download page has since
been removed. The current download is on the
[releases page](https://github.com/Banner-Saga-Factions/BSF-Client/releases/latest).

---

## [Unreleased]

### The match runner's practice battles now play out differently each time

The match runner measures the computer opponent by playing practice battles against it. Its battles kept
replaying move for move, so eight battles were really one or two. Its scripted player now sometimes takes
its second-best option instead of its best, and breaks ties at random. The random choices come from a
recorded number, so any run can be repeated exactly. The old fixed play is still one switch away. The
runner can also sign in as another local test account, whose units have special abilities to test with.
In two runs of eight, every battle differed. Nothing about how the opponent decides has changed.

*Technical:* `scripts/mod-host/runner.js` gains `--seed`, `--variety` and `--steam-id`/`--username`,
and records the account, seed and variety. Docs: `match-runner.md`, `misc/Plan-Improve-Battle-AI.md`.
BSF-Client #31, Wave 3a.

### The computer opponent now sees danger from units standing next to it

The computer opponent in offline practice battles kept walking its units into free kills. Its "can that
enemy reach me?" check left out both ends of an attack's reach, so it never saw danger from a sword
or axe. It also missed exact kills, counted the moving unit as its own friend, and added
one score twice. All four are fixed. Against the match runner's harder scripted player it went from
winning 2 of 4 battles to 4 of 4, though that second run was also sped up, so two things changed.

The match runner can now play battles about twice as fast through a developer-only switch, refused
in online battles. It also counts units the computer throws away.

*Technical:* `AiPlan.as` (inclusive range test, kill at `>=`, `computePositionalWeight` friends term,
`WEIGHT_FOCUS`), `AiModuleBase.buildEnemyArray` (caster out of `friends`); new `ModGameSpeed.as`,
`GameWrapper.as` and `BattleStateTurnAi.as` overlays, bridge command `set_game_speed`; runner `--speed`
and `computerSuicides`. Docs: `offline-ai.md`, `patch-inventory.md`, `mod-bridge.md`,
`match-runner.md`. BSF-Client #31, Wave 2.

### A helper that plays practice battles by itself, to measure how strong the computer opponent is

Making the computer opponent stronger (issue #31) needs a number to judge it by. A new helper, the
match runner, starts the real game, plays one side of offline practice battles with a fixed simple
strategy, and counts who wins. Its first runs showed that a second battle starts without restarting
the game, that every battle rolls new dice, and that the unchanged opponent beat the simple player in
all 8 baseline battles. So a second player, one that also uses the armor attack, was added to measure
against. The game's battle report now includes each unit's size so the runner aims correctly. Nothing
about how the opponent decides has changed.

*Technical:* new `scripts/mod-host/runner.js` and `docs/match-runner.md`;
`ModBattleControl.describeUnit` adds a read-only `size`; plan rewritten in
`misc/Plan-Improve-Battle-AI.md`. BSF-Client #31, Wave 1.
[#71](https://github.com/Banner-Saga-Factions/BSF-Client/pull/71).
### Our rebuilt game now has a Windows installer

The licence for the toolkit the game is built with does not allow handing out a game that runs
without being installed. So our rebuilt game now comes as one setup file. It installs for the
current user without asking for admin rights, and adds a Start-menu entry and an uninstaller.
Uninstalling leaves saved games and any Steam copy alone. Tested on 2026-10-16: install, play
with sound, reinstall over an installed copy, and uninstall. Nothing is published yet.

*Technical:* new `installer/bsf-factions.iss` (Inno Setup 6.3 or later) and `scripts/build-installer.ps1`;
see `docs/build-workflow.md` → "Windows installer". BSF-Custom-Server #47, Wave 3a.

### Our rebuilt game can now be packaged as a folder that starts on its own, with sound

Until now our rebuilt game could only run through a developer tool, and it was silent there. One
command now builds the game's folder: the game, its own copy of the runtime it needs, and the
sound and Steam add-ons. You copy the art and sound folders beside it from a Steam install.
Tested on 2026-10-16:
- Music and battle sounds play.
- The offline practice battle starts.
- With Steam running, a Steam account signs in.

Nothing is published yet: the download comes later, and first the developer kit's licence
terms on unpacked-and-run programs need a decision.

*Technical:* `scripts/build.ps1 -Target bundle` (captive runtime bundle, `-arch x86`, AIR SDK 51.3.2),
new `scripts/build-anes.ps1`, `scripts/run-adl.ps1 -Bundle`, `BSF_BUNDLE=1` in
`tests/lib/game-session.js`. BSF-Custom-Server #47, Wave 2.

### Every pull request now gets a report on broken links and script problems

This repository had no automatic checks. Each pull request now gets a summary page listing links
between documents that point at a missing file or heading, and problems found in the PowerShell
scripts. The checks only report and never block a merge. A check that failed to run says "TOOL DID
NOT RUN" instead of looking clean. The first run found 300 links that resolve and none broken, and
7 script findings. The game build is not part of it and stays on your own PC. None of this changes
what the game does.

*Technical:* `.github/workflows/quality-report.yml` (lychee, PSScriptAnalyzer),
`PSScriptAnalyzerSettings.psd1`.
[#62](https://github.com/Banner-Saga-Factions/BSF-Client/pull/62).

---

## Before this file existed

This file was started on 2026-10-11. Earlier changes are listed in one line each, taken from what their pull request said it did.

### September 2026

- Point readers at the page that now holds the reference tables ([#55](https://github.com/Banner-Saga-Factions/BSF-Client/pull/55))
- Correct what the docs say about running two copies of the game on one PC ([#52](https://github.com/Banner-Saga-Factions/BSF-Client/pull/52))
- Compile-check each commit once instead of twice, without letting a broken build through ([#48](https://github.com/Banner-Saga-Factions/BSF-Client/pull/48))
- Point the 32-bit account number rule at where it is actually written ([#46](https://github.com/Banner-Saga-Factions/BSF-Client/pull/46))
- Correct nine wrong statements about the game's launch switches ([#43](https://github.com/Banner-Saga-Factions/BSF-Client/pull/43))
- Document all of the roughly 40 launch switches, not just seven ([#41](https://github.com/Banner-Saga-Factions/BSF-Client/pull/41))

### August 2026

- Drive the game to any screen, photograph it, and write down what that taught us ([#38](https://github.com/Banner-Saga-Factions/BSF-Client/pull/38))
- Give the client its first test: it plays a practice battle by itself ([#37](https://github.com/Banner-Saga-Factions/BSF-Client/pull/37))
- Let a helper program play a whole battle without a mouse ([#35](https://github.com/Banner-Saga-Factions/BSF-Client/pull/35))
- Point reviewers at the real game when a claim is about what the game does ([#34](https://github.com/Banner-Saga-Factions/BSF-Client/pull/34))
- Write down why the offline opponent plays weakly, and track the plan to fix it ([#33](https://github.com/Banner-Saga-Factions/BSF-Client/pull/33))
- Keep the local Claude notes folder out of the repo's file list ([#32](https://github.com/Banner-Saga-Factions/BSF-Client/pull/32))
- Give this repo a review habit, including one reviewer briefed to disprove ([#30](https://github.com/Banner-Saga-Factions/BSF-Client/pull/30))
- Drive the client for testing over the mod bridge, and close the credential leak ([#28](https://github.com/Banner-Saga-Factions/BSF-Client/pull/28))
- Stop the launcher's log file being read as today's output, and fix the practice-key note ([#27](https://github.com/Banner-Saga-Factions/BSF-Client/pull/27))
- Correct what this repo says a unit fights with in battle ([#26](https://github.com/Banner-Saga-Factions/BSF-Client/pull/26))
- Write down how to run the game and check a change with your own eyes ([#24](https://github.com/Banner-Saga-Factions/BSF-Client/pull/24), [#25](https://github.com/Banner-Saga-Factions/BSF-Client/pull/25))
- Say what the server now answers when you join a room that is gone ([#23](https://github.com/Banner-Saga-Factions/BSF-Client/pull/23))
- Correct what these documents say about re-sending, the reconnecting banner, and offline battles ([#20](https://github.com/Banner-Saga-Factions/BSF-Client/pull/20))
- Correct who checks the turn checksums: the game does, not the server ([#19](https://github.com/Banner-Saga-Factions/BSF-Client/pull/19))

### July 2026

- Correct what these docs say about our server, and about the gap between the game's check-ins ([#18](https://github.com/Banner-Saga-Factions/BSF-Client/pull/18))
- Document the data model, the offline opponent, and the mod bridge ([#17](https://github.com/Banner-Saga-Factions/BSF-Client/pull/17))
- Document what a player sees: screens, artwork, and where the build differs from the source ([#16](https://github.com/Banner-Saga-Factions/BSF-Client/pull/16))
- Add a beginner's guide to how the client works and fix out-of-date facts ([#15](https://github.com/Banner-Saga-Factions/BSF-Client/pull/15))
- Point the client guide at the shared plain-language rule ([#14](https://github.com/Banner-Saga-Factions/BSF-Client/pull/14))

### May and June 2026

- Add a link rule for documents that point into the server repository ([#11](https://github.com/Banner-Saga-Factions/BSF-Client/pull/11))
- Fix dead links between the two repositories in the client documents ([#10](https://github.com/Banner-Saga-Factions/BSF-Client/pull/10))
- Add decoded spearman ability and class reference data for modding ([#9](https://github.com/Banner-Saga-Factions/BSF-Client/pull/9))
- Fix the build and decompile scripts for the decompiler's new location; document the signing certificate ([#8](https://github.com/Banner-Saga-Factions/BSF-Client/pull/8))
- Add a full set of documents for the patched client ([#5](https://github.com/Banner-Saga-Factions/BSF-Client/pull/5))
