# Changelog

What changed in this repository, newest first, written so a non-programmer can follow it. Each
entry links to the pull request that made the change.

The one earlier public build was the v2-beta pre-release of 2026-06-17; its download page has since
been removed. The current download is on the
[releases page](https://github.com/Banner-Saga-Factions/BSF-Client/releases/latest).

---

## [Unreleased]

### Our rebuilt game can now be packaged as a folder that starts on its own, with sound

Until now our rebuilt game could only run through a developer tool, and it was silent there. One
command now builds the game's folder: the game, its own copy of the runtime it needs, and the
sound and Steam add-ons. You copy the art and sound folders beside it from a Steam install.
Tested on 2026-10-16:
- Music and battle sounds play.
- The offline practice battle starts.
- With Steam running, a Steam account signs in.

The earlier belief that this needed an older developer kit was wrong. It needed a different kind of
package. Nothing is published yet: the download comes later, and first the developer kit's licence
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
