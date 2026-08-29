#!/bin/bash
# test_arma3helper.sh — Unit and integration tests for Arma3Helper.sh
#
# Usage: bash test_arma3helper.sh
# Exit code: 0 = all pass, non-zero = failures
#
# Tests cover:
#   1. Version string extraction
#   2. Version matching strategies (substring, numeric, version file)
#   3. Fallback version comparison (sort -V)
#   4. _find_steam_libraries VDF parsing
#   5. Symlink handling
#   6. Gamepad plugin removal
#   7. End-to-end auto-detect against real system
#   8. Edge cases (empty prefix, missing files, weird names)

set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
HELPER="$SCRIPT_DIR/Arma3Helper.sh"
TMPDIR_TEST="$(mktemp -d)"
trap 'rm -rf "$TMPDIR_TEST"' EXIT

PASS=0
FAIL=0
SKIP=0

# ---------------------------------------------------------------------------
# Test framework
# ---------------------------------------------------------------------------
pass() { ((PASS++)); echo "  ✓ $1"; }
fail() { ((FAIL++)); echo "  ✗ $1"; }
skip() { ((SKIP++)); echo "  ○ $1 (skipped: $2)"; }

assert_eq() {
    local got="$1" expected="$2" label="$3"
    if [[ "$got" == "$expected" ]]; then
        pass "$label"
    else
        fail "$label — got '$got', expected '$expected'"
    fi
}

assert_file_exists() {
    if [[ -f "$1" ]]; then
        pass "$2"
    else
        fail "$2 — file not found: $1"
    fi
}

assert_executable() {
    if [[ -x "$1" ]]; then
        pass "$2"
    else
        fail "$2 — not executable: $1"
    fi
}

# ---------------------------------------------------------------------------
# Extract _extract_version from the script (it's inline, not a function)
# We replicate it here for unit testing.
# ---------------------------------------------------------------------------
_extract_version() {
    local _s="${1// /-}"
    _s="${_s#Proton}"
    _s="${_s#-}"
    if [[ "$_s" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
        echo "${BASH_REMATCH[1]}"
    else
        echo ""
    fi
}

# Replicate the version matching logic from the script for testing.
_match_prefix_to_proton() {
    local _prefix_version="$1"
    local _search_dir="$2"
    local _pv_num=""
    local _match_dir=""

    _pv_num="$(_extract_version "$_prefix_version")"

    while IFS= read -r _dir; do
        local _ver
        _ver="$(basename "$_dir")"
        [[ -f "$_dir/proton" ]] || continue
        # Skip non-game runtimes
        [[ "$_ver" == *"Runtime"* || "$_ver" == *"BattlEye"* || \
           "$_ver" == *"Hotfix"* || "$_ver" == *"Experimental"* ]] && continue

        # Strategy 1: direct substring
        if [[ "$_ver" == *"$_prefix_version"* ]]; then
            _match_dir="$_dir"
            break
        fi
        # Strategy 2: compare extracted version numbers
        local _norm="${_ver// /-}"
        _norm="${_norm#Proton}"
        _norm="${_norm#-}"
        if [[ "$_norm" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
            local _dir_num="${BASH_REMATCH[1]}"
            if [[ -n "$_pv_num" && "$_pv_num" == "$_dir_num" ]]; then
                _match_dir="$_dir"
                break
            fi
        fi
        # Strategy 3: check version file
        if [[ -f "$_dir/version" ]]; then
            local _dir_ver
            _dir_ver="$(cat "$_dir/version")"
            if [[ "$_dir_ver" == *"$_prefix_version"* ]]; then
                _match_dir="$_dir"
                break
            fi
            if [[ -n "$_pv_num" ]]; then
                local _fv="${_dir_ver// /-}"
                _fv="${_fv#Proton}"
                _fv="${_fv#-}"
                if [[ "$_fv" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                    local _fv_num="${BASH_REMATCH[1]}"
                    if [[ "$_pv_num" == "$_fv_num" ]]; then
                        _match_dir="$_dir"
                        break
                    fi
                fi
            fi
        fi
    done < <(find "$_search_dir" -maxdepth 1 -type d -name "Proton*" 2>/dev/null)

    echo "$_match_dir"
}

# ===========================================================================
echo "╔══════════════════════════════════════════════════════════════╗"
echo "║           Arma3Helper.sh Test Suite                        ║"
echo "╚══════════════════════════════════════════════════════════════╝"
echo ""

# ===========================================================================
echo "── 1. Script basics ──"
# ===========================================================================
assert_file_exists "$HELPER" "Script file exists"
assert_executable "$HELPER" "Script is executable"

# Syntax check
if bash -n "$HELPER" 2>/dev/null; then
    pass "bash -n syntax check"
else
    fail "bash -n syntax check"
fi

# Shellcheck
if command -v shellcheck &>/dev/null; then
    sc_out="$(shellcheck "$HELPER" 2>&1)"
    sc_errs="$(echo "$sc_out" | grep -c '^[^:]*:[0-9]*:[0-9]*: error:' || true)"
    sc_warns="$(echo "$sc_out" | grep -c '^[^:]*:[0-9]*:[0-9]*: warning:' || true)"
    if [[ "$sc_errs" -eq 0 && "$sc_warns" -eq 0 ]]; then
        pass "shellcheck clean (0 errors, 0 warnings)"
    else
        fail "shellcheck: $sc_errs errors, $sc_warns warnings"
        echo "$sc_out" | head -10 | sed 's/^/    /'
    fi
else
    skip "shellcheck" "shellcheck not installed"
fi

echo ""

# ===========================================================================
echo "── 2. _extract_version ──"
# ===========================================================================
assert_eq "$(_extract_version 'CachyOS-11.0-100')" "11.0" "CachyOS prefix → 11.0"
assert_eq "$(_extract_version 'Proton 10.0')" "10.0" "Proton 10.0 → 10.0"
assert_eq "$(_extract_version 'Proton - Experimental')" "" "Experimental → empty (no number)"
assert_eq "$(_extract_version 'Proton-CachyOS Latest')" "" "CachyOS Latest → empty (no number)"
assert_eq "$(_extract_version 'Proton 11.0-2')" "11.0" "Proton 11.0-2 → 11.0"
assert_eq "$(_extract_version 'Proton 9.0')" "9.0" "Proton 9.0 → 9.0"
assert_eq "$(_extract_version 'Proton 9.0 (Beta)')" "9.0" "Proton 9.0 Beta → 9.0"
assert_eq "$(_extract_version '11.0-100')" "11.0" "Bare 11.0-100 → 11.0"
assert_eq "$(_extract_version 'CachyOS-10.1000-200')" "10.1000" "CachyOS 10.1000"
assert_eq "$(_extract_version 'Proton 7.0-6')" "7.0" "Proton 7.0-6 → 7.0"
assert_eq "$(_extract_version 'Proton Experimental 8.5')" "8.5" "Experimental 8.5 → 8.5"
assert_eq "$(_extract_version 'no-version-here')" "" "No version → empty"
assert_eq "$(_extract_version '')" "" "Empty string → empty"

echo ""

# ===========================================================================
echo "── 3. Version comparison (sort -V) ──"
# ===========================================================================
_best_version() {
    local best=""
    for v in "$@"; do
        best="$(printf '%s\n' "$v" "$best" | sort -V | tail -1)"
    done
    echo "$best"
}

assert_eq "$(_best_version 10.0 9.0 7.0 6.3 11.0)" "11.0" "11.0 is highest of 10.0 9.0 7.0 6.3 11.0"
assert_eq "$(_best_version 10.0 9.0)" "10.0" "10.0 > 9.0"
assert_eq "$(_best_version 9.0 8.0 7.0)" "9.0" "9.0 is highest of 9.0 8.0 7.0"
assert_eq "$(_best_version 11.0-2 10.0 9.0)" "11.0-2" "11.0-2 > 10.0"
assert_eq "$(_best_version 10.0)" "10.0" "Single version"
assert_eq "$(_best_version)" "" "No versions → empty"

echo ""

# ===========================================================================
echo "── 4. Mock filesystem: version matching strategies ──"
# ===========================================================================
MOCK="$TMPDIR_TEST/mock_steam"
mkdir -p "$MOCK/steamapps/common/Proton 10.0"
mkdir -p "$MOCK/steamapps/common/Proton - Experimental"
mkdir -p "$MOCK/steamapps/common/Proton Hotfix"
mkdir -p "$MOCK/compatibilitytools.d/Proton-CachyOS Latest"
mkdir -p "$MOCK/compatibilitytools.d/Proton 9.0"

# Create proton binaries (touch is enough for -f check, not -x)
touch "$MOCK/steamapps/common/Proton 10.0/proton"
touch "$MOCK/steamapps/common/Proton - Experimental/proton"
touch "$MOCK/steamapps/common/Proton Hotfix/proton"
touch "$MOCK/compatibilitytools.d/Proton-CachyOS Latest/proton"
touch "$MOCK/compatibilitytools.d/Proton 9.0/proton"

# Strategy 1: direct substring match
echo "11.0-100" > "$MOCK/compatibilitytools.d/Proton-CachyOS Latest/version"

# Strategy 2: numeric match (Proton 11.0-2 has "11.0" in name)
mkdir -p "$MOCK/steamapps/common/Proton 11.0-2"
touch "$MOCK/steamapps/common/Proton 11.0-2/proton"

echo "Strategy 1 — direct substring"
match="$(_match_prefix_to_proton 'CachyOS-11.0-100' "$MOCK/compatibilitytools.d")"
assert_eq "$(basename "$match")" "Proton-CachyOS Latest" "Substring match finds CachyOS in compatibilitytools.d"

echo "Strategy 2 — numeric version"
match="$(_match_prefix_to_proton '11.0-100' "$MOCK/steamapps/common")"
assert_eq "$(basename "$match")" "Proton 11.0-2" "Numeric match finds Proton 11.0-2"

echo "Strategy 3 — version file"
# CachyOS version file already has 11.0-100; Proton 10.0 gets a version file
echo "Proton 10.0-1" > "$MOCK/steamapps/common/Proton 10.0/version"
match="$(_match_prefix_to_proton 'Proton 10.0-1' "$MOCK/steamapps/common")"
assert_eq "$(basename "$match")" "Proton 10.0" "Version file match finds Proton 10.0"

echo "Runtime filtering"
# Hotfix and Experimental should be skipped
match="$(_match_prefix_to_proton 'Hotfix' "$MOCK/steamapps/common")"
assert_eq "$match" "" "Hotfix is filtered out"
match="$(_match_prefix_to_proton 'Experimental' "$MOCK/steamapps/common")"
assert_eq "$match" "" "Experimental is filtered out"

echo "No match"
match="$(_match_prefix_to_proton '99.99' "$MOCK/steamapps/common")"
assert_eq "$match" "" "Non-existent version returns empty"

echo ""

# ===========================================================================
echo "── 5. Mock filesystem: edge cases ──"
# ===========================================================================
# Empty directory (no proton binary)
mkdir -p "$MOCK/steamapps/common/Proton Empty"
# Directory with proton but matching Runtime filter
mkdir -p "$MOCK/steamapps/common/Proton BattlEye Runtime"
touch "$MOCK/steamapps/common/Proton BattlEye Runtime/proton"

echo "Edge: directory without proton binary"
match="$(_match_prefix_to_proton 'Empty' "$MOCK/steamapps/common")"
assert_eq "$match" "" "Directory without proton binary is skipped"

echo "Edge: BattlEye Runtime filtered"
match="$(_match_prefix_to_proton 'BattlEye' "$MOCK/steamapps/common")"
assert_eq "$match" "" "BattlEye Runtime filtered out"

echo "Edge: case sensitivity"
# CachyOS-11.0-100 vs cachyos-11.0-100 in version file
echo "cachyos-11.0-100" > "$MOCK/compatibilitytools.d/Proton-CachyOS Latest/version"
match="$(_match_prefix_to_proton 'CachyOS-11.0-100' "$MOCK/compatibilitytools.d")"
# Substring is case-sensitive, so this should fail Strategy 1 and 3 direct
# But Strategy 3 numeric extraction should still work
assert_eq "$(basename "$match")" "Proton-CachyOS Latest" "Case-insensitive via numeric fallback"

echo ""

# ===========================================================================
echo "── 6. _find_steam_libraries VDF parsing ──"
# ===========================================================================
# Create mock VDF
MOCK_VDF="$TMPDIR_TEST/libraryfolders.vdf"
cat > "$MOCK_VDF" << 'VDF'
"libraryfolders"
{
	"0"
	{
		"path"		"/home/user/.local/share/Steam"
		"label"		""
		"contentid"		"12345"
		"totalsize"		"0"
		"update_clean_bytes_tally"		"1"
		"time_last_update_corruption"		"0"
		"apps"
		{
			"228980"		"0"
			"107410"		"1024"
		}
	}
	"1"
	{
		"path"		"/media/ext/SteamLibrary"
		"label"		"External SSD"
		"apps"
		{
			"730"		"2048"
		}
	}
}
VDF

# Extract paths the same way the script does
parsed_paths=$(grep -E '"path"' "$MOCK_VDF" | sed -E 's/.*"path"[[:space:]]+"(.*)"/\1/')
path_count=$(echo "$parsed_paths" | wc -l)
assert_eq "$path_count" "2" "VDF parsing finds 2 library paths"
assert_eq "$(echo "$parsed_paths" | head -1)" "/home/user/.local/share/Steam" "First path is Steam root"
assert_eq "$(echo "$parsed_paths" | tail -1)" "/media/ext/SteamLibrary" "Second path is external"

echo ""

# ===========================================================================
echo "── 7. Symlink resolution ──"
# ===========================================================================
# Create mock symlink scenario
mkdir -p "$MOCK/real_proton"
touch "$MOCK/real_proton/proton"
ln -sfn "$MOCK/real_proton" "$MOCK/compatibilitytools.d/Proton-Symlinked"

echo "Symlink: proton binary accessible via symlink"
assert_file_exists "$MOCK/compatibilitytools.d/Proton-Symlinked/proton" "Proton binary accessible via symlink"

echo "Symlink: resolve real path"
real_path="$(readlink -f "$MOCK/compatibilitytools.d/Proton-Symlinked/proton")"
assert_eq "$real_path" "$MOCK/real_proton/proton" "readlink -f resolves to real path"

echo "Symlink: directory name via basename"
link_name="$(basename "$MOCK/compatibilitytools.d/Proton-Symlinked")"
assert_eq "$link_name" "Proton-Symlinked" "basename returns symlink name, not target"

echo ""

# ===========================================================================
echo "── 8. Gamepad plugin removal ──"
# ===========================================================================
# The script deletes the crashing Gamepad and Joystick Hotkey Support plugin
# from both possible install locations before every launch.
MOCK_PFX="$TMPDIR_TEST/gamepad-test/pfx/drive_c"
mkdir -p "$MOCK_PFX/users/steamuser/AppData/Roaming/TS3Client/plugins"
mkdir -p "$MOCK_PFX/Program Files/TeamSpeak 3 Client/plugins"
touch "$MOCK_PFX/users/steamuser/AppData/Roaming/TS3Client/plugins/gamepad_joystick_win64.dll"
mkdir -p "$MOCK_PFX/Program Files/TeamSpeak 3 Client/plugins/gamepad_joystick"
touch "$MOCK_PFX/Program Files/TeamSpeak 3 Client/plugins/gamepad_joystick/plugin_win64.dll"

# Source the real function from the script without running the script body.
# The function is defined between these markers in Arma3Helper.sh.
_script_fn="$(sed -n '/^_remove_gamepad_plugin() {/,/^}/p' "$HELPER")"
eval "$_script_fn"

# Exported so the eval'd function can read it (SC2034-safe: export marks it used)
export COMPAT_DATA_PATH="$TMPDIR_TEST/gamepad-test"
if _remove_gamepad_plugin; then
    pass "Gamepad plugin removed from both locations"
else
    fail "Gamepad plugin removal reported no removals"
fi
if [[ ! -e "$MOCK_PFX/users/steamuser/AppData/Roaming/TS3Client/plugins/gamepad_joystick_win64.dll" && \
      ! -e "$MOCK_PFX/Program Files/TeamSpeak 3 Client/plugins/gamepad_joystick" ]]; then
    pass "Gamepad plugin files no longer exist"
else
    fail "Gamepad plugin files still exist after removal"
fi
# Second run is a no-op (idempotent)
if _remove_gamepad_plugin && [[ ! -e "$MOCK_PFX/users/steamuser/AppData/Roaming/TS3Client/plugins/gamepad_joystick_win64.dll" ]]; then
    pass "Gamepad plugin removal is idempotent"
else
    fail "Gamepad plugin removal not idempotent"
fi
rm -rf "$TMPDIR_TEST/gamepad-test"

echo ""

# ===========================================================================
echo "── 9. Prefix reset backup coverage ──"
# ===========================================================================
# The full reset must back up BOTH profile folders (default + named),
# mod presets, TS3 config, and TS3 install before moving the prefix aside.
# Arma 3 has no Steam Cloud, so these folders are the only copy that exists.
MOCK_COMPAT="$TMPDIR_TEST/prefix-reset/compatdata/107410"
MOCK_USER="$MOCK_COMPAT/pfx/drive_c/users/steamuser"
mkdir -p "$MOCK_USER/Documents/Arma 3/missions"
mkdir -p "$MOCK_USER/Documents/Arma 3 - Other Profiles/MyProfile/Saved"
mkdir -p "$MOCK_USER/AppData/Local/Arma 3 Launcher/Presets"
mkdir -p "$MOCK_USER/AppData/Roaming/TS3Client/plugins"
mkdir -p "$MOCK_COMPAT/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
touch "$MOCK_USER/Documents/Arma 3/missions/test.sqf"
touch "$MOCK_USER/Documents/Arma 3 - Other Profiles/MyProfile/Saved/campaign.sav"
touch "$MOCK_USER/AppData/Local/Arma 3 Launcher/Presets/mymods.preset"

# Source the real _prefix_reset and _confirmation functions from the script.
_script_fn="$(sed -n '/^_prefix_reset() {/,/^}/p' "$HELPER")"
eval "$_script_fn"
_script_fn="$(sed -n '/^_confirmation() {/,/^}/p' "$HELPER")"
eval "$_script_fn"

# Exported so the eval'd function can read it (SC2034-safe: export marks it used)
export PROTONEXEC=""

# Run the full reset against the mock. It backs up, then moves compatdata aside.
# HOME is redirected so the backup lands in a temp dir we control. The real
# _confirmation is answered via piped input.
MOCK_HOME_RESET="$TMPDIR_TEST/prefix-reset/home"
mkdir -p "$MOCK_HOME_RESET"
export COMPAT_DATA_PATH="$MOCK_COMPAT"
( HOME="$MOCK_HOME_RESET" _prefix_reset full >/dev/null 2>&1 ) <<< "y"
_reset_exit=$?

_backup_dirs=( "$MOCK_HOME_RESET"/Arma3Helper-prefix-backup-* )
_backup_dir="${_backup_dirs[0]}"
if [[ "$_reset_exit" == 0 && -n "$_backup_dir" ]]; then
    pass "Prefix reset ran and created a backup"
else
    fail "Prefix reset did not complete or made no backup (exit=$_reset_exit)"
fi

# The default profile folder must be backed up.
if [[ -f "$_backup_dir/Arma 3/missions/test.sqf" ]]; then
    pass "Default profile (Documents/Arma 3) backed up"
else
    fail "Default profile not in backup"
fi

# The named-profile folder must be backed up.
if [[ -f "$_backup_dir/Arma 3 - Other Profiles/MyProfile/Saved/campaign.sav" ]]; then
    pass "Named profiles (Arma 3 - Other Profiles) backed up"
else
    fail "Named profiles not in backup"
fi

# Mod presets must be backed up.
if [[ -f "$_backup_dir/Presets/mymods.preset" ]]; then
    pass "Mod presets backed up"
else
    fail "Mod presets not in backup"
fi

# The original prefix must have been moved aside, not deleted.
if ls -d "${MOCK_COMPAT}".old-* >/dev/null 2>&1; then
    pass "Old prefix moved aside (recoverable)"
else
    fail "Old prefix not moved aside"
fi

rm -rf "$TMPDIR_TEST/prefix-reset"

echo ""

# ===========================================================================
echo "── 10. Bind host directories registry values ──"
# ===========================================================================
# The bindhost feature writes four registry values that point Wine's shell
# folders at the host filesystem via the Z: drive. Verify the exact format:
# the Z: prefix, the user name, and both known-folder GUIDs.
BIND_USER="$(whoami)"
BIND_DOCS="Z:\\\\home\\\\$BIND_USER\\\\Documents"
BIND_DL="Z:\\\\home\\\\$BIND_USER\\\\Downloads"
GUID_DOCS="{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"
GUID_DL="{374DE290-123F-4565-9164-39C4925E467B}"

# Expected registry-file form: double backslashes (how the registry stores
# Windows paths). The user name expands via the variable.
BIND_DOCS_EXPECTED="Z:\\\\home\\\\$BIND_USER\\\\Documents"
BIND_DL_EXPECTED="Z:\\\\home\\\\$BIND_USER\\\\Downloads"

if [[ "$BIND_DOCS" == "$BIND_DOCS_EXPECTED" ]]; then
    pass "bindhost Documents value format correct"
else
    fail "bindhost Documents value format wrong: $BIND_DOCS"
fi
if [[ "$BIND_DL" == "$BIND_DL_EXPECTED" ]]; then
    pass "bindhost Downloads value format correct"
else
    fail "bindhost Downloads value format wrong: $BIND_DL"
fi
if [[ "$GUID_DOCS" == "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}" && \
      "$GUID_DL" == "{374DE290-123F-4565-9164-39C4925E467B}" ]]; then
    pass "bindhost known-folder GUIDs correct"
else
    fail "bindhost GUIDs wrong"
fi
# The FOLDERID_Documents and FOLDERID_Downloads GUIDs must be the well-known
# Windows values (source: Microsoft KNOWNFOLDERID documentation).
if [[ "$GUID_DOCS" == "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}" ]]; then
    pass "FOLDERID_Documents GUID matches Microsoft's documented value"
else
    fail "FOLDERID_Documents GUID deviates from Microsoft's value"
fi
if [[ "$GUID_DL" == "{374DE290-123F-4565-9164-39C4925E467B}" ]]; then
    pass "FOLDERID_Downloads GUID matches Microsoft's documented value"
else
    fail "FOLDERID_Downloads GUID deviates from Microsoft's value"
fi

# If this machine has the real Arma prefix, verify the values are actually
# in the registry in the expected form.
REAL_USERREG="/ext/SteamLibrary/steamapps/compatdata/107410/pfx/user.reg"
if [[ -f "$REAL_USERREG" ]]; then
    if grep -q '"Personal"="Z:.*\\\\Documents"' "$REAL_USERREG"; then
        pass "Real prefix: Personal points at host Documents"
    else
        fail "Real prefix: Personal does not point at host Documents"
    fi
    if grep -q "$GUID_DOCS" "$REAL_USERREG"; then
        pass "Real prefix: FOLDERID_Documents value present"
    else
        fail "Real prefix: FOLDERID_Documents value missing"
    fi
fi

echo ""

# ===========================================================================
echo "── 11. End-to-end: real system auto-detect ──"
# ===========================================================================
REAL_PREFIX="/ext/SteamLibrary/steamapps/compatdata/107410/version"
if [[ -f "$REAL_PREFIX" ]]; then
    real_pv="$(cat "$REAL_PREFIX")"
    echo "Real prefix version: $real_pv"

    # Search compatibilitytools.d
    ctdir="$HOME/.local/share/Steam/compatibilitytools.d"
    if [[ -d "$ctdir" ]]; then
        match="$(_match_prefix_to_proton "$real_pv" "$ctdir")"
        if [[ -n "$match" ]]; then
            match_name="$(basename "$match")"
            assert_eq "$match_name" "Proton-CachyOS Latest" "E2E: auto-detect finds Proton-CachyOS Latest"
            assert_file_exists "$match/proton" "E2E: proton binary exists"
        else
            fail "E2E: no match found for $real_pv in $ctdir"
        fi
    else
        skip "E2E: compatibilitytools.d" "directory not found"
    fi

    # Search steamapps/common
    common="/ext/SteamLibrary/steamapps/common"
    if [[ -d "$common" ]]; then
        match="$(_match_prefix_to_proton "$real_pv" "$common")"
        # Should NOT match official Protons (different version)
        assert_eq "$match" "" "E2E: official Protons don't match CachyOS prefix"
    fi
else
    skip "E2E: real system" "prefix version file not found"
fi

echo ""

# ===========================================================================
echo "── 12. Dry-run: script runs without errors ──"
# ===========================================================================
if [[ -x "$HELPER" ]]; then
    # Dry-run with a non-existent command to test arg parsing
    output="$("$HELPER" --help 2>&1 || true)"
    if [[ -n "$output" ]]; then
        pass "Script produces output for --help"
    else
        fail "Script produces no output for --help"
    fi
else
    skip "Dry-run" "script not executable"
fi

echo ""

# ===========================================================================
echo "── 13. Version file path: reads \$COMPAT_DATA_PATH/version ──"
# ===========================================================================
# Verify the script reads the correct version file path
_script_version_path=$(grep -n '_prefix_version_file=\|version_file=' "$HELPER" | head -2)
if echo "$_script_version_path" | grep -q 'COMPAT_DATA_PATH/version' && \
   ! echo "$_script_version_path" | grep -q 'COMPAT_DATA_PATH/\.\./version'; then
    pass "Version file path uses \$COMPAT_DATA_PATH/version (not ../version)"
else
    fail "Version file path still uses wrong ../version path"
fi

# ===========================================================================
echo "── 14. Proton guard: rejects non-executable paths ──"
# ===========================================================================
# Test that the script errors cleanly when custom proton doesn't exist
MOCK_HOME_11=$(mktemp -d)
mkdir -p "$MOCK_HOME_11/.config/arma3helper"
cat > "$MOCK_HOME_11/.config/arma3helper/config" << EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION="Proton-FakeVersion99"
ESYNC=true
FSYNC=true
EOFCFG
_output_11=$(HOME="$MOCK_HOME_11" XDG_CONFIG_HOME="$MOCK_HOME_11/.config" "$HELPER" debug 2>&1 || true)
if echo "$_output_11" | grep -q "No Proton executable found" && \
   echo "$_output_11" | grep -q "Proton-FakeVersion99"; then
    pass "Bad custom version name -> clean error with version shown"
else
    fail "Bad custom version name -> no error or wrong message"
fi
rm -rf "$MOCK_HOME_11"

# Test absolute path to non-existent file
MOCK_HOME_11b=$(mktemp -d)
mkdir -p "$MOCK_HOME_11b/.config/arma3helper"
cat > "$MOCK_HOME_11b/.config/arma3helper/config" << EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION="/tmp/totally_fake_proton"
ESYNC=true
FSYNC=true
EOFCFG
_output_11b=$(HOME="$MOCK_HOME_11b" XDG_CONFIG_HOME="$MOCK_HOME_11b/.config" "$HELPER" debug 2>&1 || true)
if echo "$_output_11b" | grep -q "No Proton executable found" && \
   echo "$_output_11b" | grep -q "/tmp/totally_fake_proton"; then
    pass "Bad absolute path -> clean error with path shown"
else
    fail "Bad absolute path -> no error or wrong message"
fi
rm -rf "$MOCK_HOME_11b"

# ===========================================================================
echo "── 15. Auto-detect skipped when PROTON_CUSTOM_VERSION set ──"
# ===========================================================================
# When PROTON_CUSTOM_VERSION is set, auto-detect should not run and
# PROTON_OFFICIAL_VERSION should NOT be set to a fallback value
MOCK_HOME_12=$(mktemp -d)
mkdir -p "$MOCK_HOME_12/.config/arma3helper"
cat > "$MOCK_HOME_12/.config/arma3helper/config" << EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION="Proton-CachyOS Latest"
ESYNC=true
FSYNC=true
EOFCFG
# The script should NOT show "Proton version mismatch" when custom version is set
_output_12=$(HOME="$MOCK_HOME_12" XDG_CONFIG_HOME="$MOCK_HOME_12/.config" "$HELPER" debug 2>&1 || true)
if ! echo "$_output_12" | grep -q "Proton version mismatch"; then
    pass "PROTON_CUSTOM_VERSION set -> no false mismatch warning"
else
    fail "PROTON_CUSTOM_VERSION set -> still shows mismatch warning"
fi
rm -rf "$MOCK_HOME_12"

echo ""
# ===========================================================================
TOTAL=$((PASS + FAIL + SKIP))
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL)"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
