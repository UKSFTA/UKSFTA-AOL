# Changelog

All notable changes to this project are recorded here.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).
Versioning follows [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.1] - 2026-08-29

### Fixed

- Proton builds with gamedrive enabled (for example Proton Hotfix) deleted
  the prefix's S: drive when TeamSpeak was launched. The script now exports
  STEAM_COMPAT_INSTALL_PATH and STEAM_COMPAT_LIBRARY_PATHS, derived from
  COMPAT_DATA_PATH. This prevents multiplayer signature kicks.
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

[Unreleased]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.0.1...master
[2.0.1]: https://github.com/UKSFTA/UKSFTA-AOL/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/UKSFTA/UKSFTA-AOL/compare/4261d5a...v2.0.0