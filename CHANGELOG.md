# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Changed

- Guide: removed `-exThreads`, `-enableHT`, and `-hugepages` advice. These
  reduce performance since Arma 2.20.
- Guide: documented 64-bit default and 32-bit deprecation.
- Guide: added ProtonDB-sourced troubleshooting (8 kHz mouse freeze,
  640×480 lock, cursor escape, VRAM leak) and the 44.1 kHz audio fix.
- Guide: documented script protections (wizard, prefix check, gamepad
  removal, S: drive, single-instance guard) and checkdeps coverage
  (BattlEye runtime, noexec mounts).

## [2.1.2] - 2026-08-29

### Changed

- Install help and guide document the Proton Experimental installer hang
  at `fsync: up and running` (upstream issue #36). Use a stable Proton.
- Install help notes the gamepad plugin is deleted automatically, replacing
  the manual disable step.
- CI actions bumped to current major versions (checkout v7,
  upload-pages-artifact v5, deploy-pages v5). Closes dependabot PRs.

## [2.1.1] - 2026-08-29

### Added

- `xaudio2_9` in the winetricks DLL set. Arma 2.22 moved to XAudio 2.9,
  which causes crackle under some Proton versions. This is the current
  audio fix (replaces the obsolete `xaudio2_7` advice).
- `mfc140` in the winetricks DLL set, matching the canonical set.
- `checkdeps` warns when a Steam library sits on a `noexec` mount. Proton
  and Workshop mods cannot run from such a drive.
- `checkdeps` verifies the Proton BattlEye Runtime is installed.
- `debug` warns on Proton 11.0-1, which re-downloads Workshop mods on
  every launch (fixed in 11.0-2).

### Fixed

- Guide: replaced the obsolete `xaudio2_7=n` audio advice with `xaudio2_9`.

## [2.1.0] - 2026-08-29

### Added

- Gamepad and Joystick plugin is deleted automatically before each TeamSpeak
  launch. The plugin crashes TeamSpeak 3 and the bug is unfixed upstream.
- Single-instance guard: a second launch fails with a clear message instead
  of racing on the prefix.
- Signal trap: interrupting winetricks or install prints a warning that the
  prefix may be incomplete.
- Wizard dismissal persists: answering no stops the prompt until the config
  is edited again.
- Offline mode: `ARMA3HELPER_OFFLINE=1` skips the update check.
- Test suite: 49 tests, including gamepad plugin removal.

### Fixed

- Wizard installed DLLs into `~/.wine` instead of Arma's prefix. It now
  exports `WINEPREFIX` before installing.
- Update command truncated the running script on an interrupted download.
  It now downloads to a temp file and moves it into place, keeping a backup.
- GE-Proton builds (`GE-Proton9-20`) were never auto-detected because the
  search only matched directories starting with "Proton".
- Prefix version check prompted on informational commands such as `help` and
  `listproton`. It now runs only on the launch path.
- Wizard aborted the launch when winetricks or protontricks was missing. It
  now warns and continues.
- VDF patch corrupted non-UTF-8 bytes in `localconfig.vdf`. It now preserves
  them.
- Steam library detection used an awk pattern that fails on some
  implementations. The path extraction is now portable.
- Update fallback downloaded to the working directory instead of the
  script's own directory.
- `RUNTIME_SHARE_DIRS` rejected paths containing spaces.
- Config directory owned by root after a sudo run now gives a clear chown
  hint instead of failing silently.
- Update check stamped the cache even when the fetch failed, blocking
  retries for 24 hours. It now stamps only on success.

## [2.0.2] - 2026-08-29

### Fixed

- Proton builds with gamedrive enabled (for example Proton Hotfix) deleted
  the prefix's S: drive when TeamSpeak was launched. The script now exports
  STEAM_COMPAT_INSTALL_PATH and STEAM_COMPAT_LIBRARY_PATHS, derived from
  COMPAT_DATA_PATH. This prevents multiplayer signature kicks.

## [2.0.1] - 2026-08-29

### Fixed

- `createconfig` downloaded a config template that did not exist in the
  repository. The command now works. The template file is in the repo.
- `.gitignore` excluded the `config` file from tracking.
- Test suite ran only locally. CI now runs shellcheck and the test suite
  on every push and pull request.
- Unused `assert_true` and `assert_false` helpers caused a shellcheck
  failure in CI. Removed.
- Winetricks wrapper command now uses a bash array. This prevents path
  splitting when the tool is installed in a path with spaces.
- STE-100 banned words removed from script comments.

### Added

- `SECURITY.md` with a private reporting process.
- `CONTRIBUTING.md` with the contribution standards.
- `CHANGELOG.md` with release history.
- Unit tests in `test_arma3helper.sh` (46 tests).

## [2.0.0] - 2026-08-29

### Added

- Auto-detection of the Proton version from Arma's prefix.
- Three-strategy matching: substring, numeric version, version file.
- Update notification: the script checks GitHub daily for a new version.
- Debug output shows local and GitHub versions.

### Fixed

- Proton executable guard now checks the file is executable, not just set.
- Auto-detect no longer runs when a custom Proton version is set.
- Setup wizard now runs only on the launch path, not on `listproton`,
  `help`, or `checkdeps`.
- Version file read from the correct path (`$COMPAT_DATA_PATH/version`).
- `_find_steam_libraries` fallback returned a doubled path.

## [1.0.0] - 2026-08-08

### Fixed

- Proton search fallback for directories with unusual naming.
- Guard for an empty Proton path.
- Steam library discovery from `libraryfolders.vdf`.
- ACRE2 and TFAR pipe fix after Steam Linux Runtime 4 container isolation.

[Unreleased]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.1.2...master
[2.1.2]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.1.1...v2.1.2
[2.1.1]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.0.2...v2.1.0
[2.0.2]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.0.1...v2.0.2
[2.0.1]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/UKSFTA/UKSFTA-AOL/compare/4261d5a...v2.0.0