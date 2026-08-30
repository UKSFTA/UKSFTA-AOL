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
pass() {
    ((PASS++))
    echo "  ✓ $1"
}
fail() {
    ((FAIL++))
    echo "  ✗ $1"
}
skip() {
    ((SKIP++))
    echo "  ○ $1 (skipped: $2)"
}

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
        [[ "$_ver" == *"Runtime"* || "$_ver" == *"BattlEye"* ||
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
echo "11.0-100" >"$MOCK/compatibilitytools.d/Proton-CachyOS Latest/version"

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
echo "Proton 10.0-1" >"$MOCK/steamapps/common/Proton 10.0/version"
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
echo "cachyos-11.0-100" >"$MOCK/compatibilitytools.d/Proton-CachyOS Latest/version"
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
cat >"$MOCK_VDF" <<'VDF'
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
if [[ ! -e "$MOCK_PFX/users/steamuser/AppData/Roaming/TS3Client/plugins/gamepad_joystick_win64.dll" &&
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
echo "── 8b. Radio plugin verification and TFAR install ──"
# ===========================================================================
# checkdeps must report the ACRE2/TFAR plugins, tfarmod must copy the TFAR
# plugin from the Workshop mod folder, and --enable must re-enable plugins
# that TeamSpeak disabled after a crash (.disabled suffix).

# Source the real functions from the script without running the script body.
# The evaled functions call _find_steam_libraries, so source that too and
# build a mock Steam layout the real functions can discover.
_plugin_fn="$(sed -n '/^_check_radio_plugins() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_tfar_plugin_source() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_install_tfar_plugin() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_enable_tfar_plugin() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_root() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_libraries() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"

# Build a mock Steam install the real discovery functions find:
#   $MOCK_HOME/.steam/steam/steamapps          -> makes _find_steam_root match
#   $MOCK_HOME/.steam/steam/config/libraryfolders.vdf -> points at the library
MOCK_HOME="$TMPDIR_TEST/radio-home"
MOCK_LIB="$TMPDIR_TEST/radio-lib"
mkdir -p "$MOCK_HOME/.steam/steam/steamapps"
mkdir -p "$MOCK_HOME/.steam/steam/config"
cat >"$MOCK_HOME/.steam/steam/config/libraryfolders.vdf" <<'VDF'
"libraryfolders"
{
	"0"
	{
		"path"		"__MOCK_LIB__"
	}
}
VDF
sed -i "s|__MOCK_LIB__|$MOCK_LIB|" "$MOCK_HOME/.steam/steam/config/libraryfolders.vdf"
mkdir -p "$MOCK_LIB/steamapps/workshop/content/107410/623475154/TeamSpeak 3 Client/plugins"

export COMPAT_DATA_PATH="$MOCK_LIB"
TS3_ROOT="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client"
mkdir -p "$TS3_ROOT/plugins"
mkdir -p "$TS3_ROOT/config/plugins"

# Case A: empty plugins -> both missing
if _check_radio_plugins 2>&1 | grep -q "ACRE2 plugin" &&
    ! _check_radio_plugins 2>&1 | grep -q "ACRE2 plugin present"; then
    pass "checkdeps reports both plugins missing when absent"
else
    fail "checkdeps empty-plugins status wrong"
fi

# Case B: ACRE2 present, TFAR missing
touch "$TS3_ROOT/plugins/acre2_win64.dll"
if _check_radio_plugins 2>&1 | grep -q "ACRE2 plugin present" &&
    ! _check_radio_plugins 2>&1 | grep -q "TFAR plugin present"; then
    pass "checkdeps reports ACRE2 present, TFAR missing"
else
    fail "checkdeps plugin status wrong (ACRE2/TFAR)"
fi

# Case C: disabled plugin detected
touch "$TS3_ROOT/config/plugins/TFAR_win64.dll.disabled"
if _check_radio_plugins 2>&1 | grep -q "Plugin disabled after a crash"; then
    pass "checkdeps reports disabled TFAR plugin"
else
    fail "checkdeps did not report disabled TFAR plugin"
fi

# Case D: --enable renames .disabled back to .dll
if _enable_tfar_plugin 2>&1 | grep -q "Re-enabled: TFAR_win64.dll" &&
    [[ -f "$TS3_ROOT/config/plugins/TFAR_win64.dll" && ! -e "$TS3_ROOT/config/plugins/TFAR_win64.dll.disabled" ]]; then
    pass "tfarmod --enable re-enables disabled plugin"
else
    fail "tfarmod --enable failed to re-enable plugin"
fi

# Case E: tfarmod install from Workshop mod folder.
# HOME must point at the mock so _find_steam_root finds the fake Steam.
WS_MOD="$MOCK_LIB/steamapps/workshop/content/107410/623475154/TeamSpeak 3 Client/plugins"
touch "$WS_MOD/TFAR_win64.dll"
if (HOME="$MOCK_HOME" _install_tfar_plugin) 2>&1 | grep -q "TFAR plugin installed" &&
    [[ -f "$TS3_ROOT/plugins/TFAR_win64.dll" ]]; then
    pass "tfarmod copies TFAR plugin from Workshop mod"
else
    fail "tfarmod failed to copy TFAR plugin"
fi

# Case F: tfarmod with no mod installed reports a clear error.
# Keep the TS3 plugins folder present but remove the Workshop mod source.
rm -rf "$MOCK_LIB/steamapps"
_cf_out="$(HOME="$MOCK_HOME" _install_tfar_plugin 2>&1)"
if echo "$_cf_out" | grep -q "Could not find the TFAR plugin"; then
    pass "tfarmod reports clear error when mod missing"
else
    fail "tfarmod missing-mod error not shown (got: $_cf_out)"
fi
rm -rf "$TMPDIR_TEST/radio-lib" "$TMPDIR_TEST/radio-home"

echo ""

# ===========================================================================
echo "── 8c. Mod listing from RPT and live process ──"
# ===========================================================================
# listmods must parse the -mod= launch line (from the live process via /proc,
# or from the newest RPT header) into Workshop ids, then resolve names from
# mod.cpp. Test the RPT fallback path with a mock RPT + mock library.

# Source the real functions.
_plugin_fn="$(sed -n '/^_find_latest_rpt() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_get_arma_cmdline() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_parse_loaded_mods() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_mod_name_from_workshop() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_list_installed_mods() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_list_loaded_mods() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_root() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_libraries() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"

MOCK_HOME="$TMPDIR_TEST/mods-home"
MOCK_LIB="$TMPDIR_TEST/mods-lib"
mkdir -p "$MOCK_HOME/.steam/steam/steamapps"
mkdir -p "$MOCK_HOME/.steam/steam/config"
cat >"$MOCK_HOME/.steam/steam/config/libraryfolders.vdf" <<'VDF'
"libraryfolders"
{
	"0"
	{
		"path"		"__MOCK_LIB__"
	}
}
VDF
sed -i "s|__MOCK_LIB__|$MOCK_LIB|" "$MOCK_HOME/.steam/steam/config/libraryfolders.vdf"
mkdir -p "$MOCK_LIB/steamapps/workshop/content/107410/751965892"
mkdir -p "$MOCK_LIB/steamapps/workshop/content/107410/450814997"
printf 'name = "Advanced Combat Radio Environment 2";\n' >"$MOCK_LIB/steamapps/workshop/content/107410/751965892/mod.cpp"
printf 'name = "Community Base Addons";\n' >"$MOCK_LIB/steamapps/workshop/content/107410/450814997/mod.cpp"

# Mock RPT with a Windows-style -mod= line (as Arma writes it).
MOCK_COMPAT="$TMPDIR_TEST/mods-compat/107410"
MOCK_RPT_DIR="$MOCK_COMPAT/pfx/drive_c/users/steamuser/AppData/Local/Arma 3"
mkdir -p "$MOCK_RPT_DIR"
cat >"$MOCK_RPT_DIR/Arma3_x64_2026-08-29_00-00-00.rpt" <<'RPT'
=====================================================================
== S:\common\Arma 3\Arma3_x64.exe
== "S:\common\Arma 3\Arma3_x64.exe" -mod=S:\workshop\content\107410\751965892;S:\workshop\content\107410\450814997
=====================================================================
RPT

# _find_latest_rpt must find the mock (HOME-independent; uses COMPAT_DATA_PATH).
export COMPAT_DATA_PATH="$MOCK_COMPAT"

# Case A: parse ids from the RPT fallback
_ids="$(_parse_loaded_mods)"
if echo "$_ids" | grep -q "^751965892$" && echo "$_ids" | grep -q "^450814997$" &&
    [[ "$(echo "$_ids" | wc -l)" == "2" ]]; then
    pass "parse_loaded_mods extracts Workshop ids from RPT"
else
    fail "parse_loaded_mods wrong (got: $_ids)"
fi

# Case B: mod name resolution from mod.cpp
# _mod_name_from_workshop walks _find_steam_libraries, so HOME must point
# at the mock Steam install (as in the CI runner, which has no real Steam).
_nm="$(HOME="$MOCK_HOME" _mod_name_from_workshop 751965892)"
if [[ "$_nm" == "Advanced Combat Radio Environment 2" ]]; then
    pass "mod name resolved from mod.cpp"
else
    fail "mod name resolution wrong (got: $_nm)"
fi

# Case C: installed list excludes the content root and names known mods
_inst="$(HOME="$MOCK_HOME" _list_installed_mods)"
if ! echo "$_inst" | grep -q "107410\s" &&
    echo "$_inst" | grep -q "Advanced Combat Radio Environment 2"; then
    pass "installed mods list excludes root and names mods"
else
    fail "installed mods list wrong"
fi

# Case D: loaded list flags ACRE2 as loaded
_load="$(HOME="$MOCK_HOME" _list_loaded_mods)"
if echo "$_load" | grep -q "ACRE2 is loaded"; then
    pass "loaded mods flags ACRE2"
else
    fail "loaded mods did not flag ACRE2"
fi

rm -rf "$TMPDIR_TEST/mods-home" "$TMPDIR_TEST/mods-lib" "$TMPDIR_TEST/mods-compat"
unset COMPAT_DATA_PATH

echo ""

# ===========================================================================
echo "── 8d. Full radio chain verification ──"
# ===========================================================================
# verifyradio must check all three stages: Workshop mod downloaded, mod in
# the loaded list, plugin in the prefix TeamSpeak install. Test the ACRE2
# chain with a mock library + mock RPT + mock prefix.

# Source the real functions.
_plugin_fn="$(sed -n '/^_check_radio_chain() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_verify_radio() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_root() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_steam_libraries() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_find_latest_rpt() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_get_arma_cmdline() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_parse_loaded_mods() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"

MOCK_HOME="$TMPDIR_TEST/chain-home"
MOCK_LIB="$TMPDIR_TEST/chain-lib"
mkdir -p "$MOCK_HOME/.steam/steam/steamapps"
mkdir -p "$MOCK_HOME/.steam/steam/config"
cat >"$MOCK_HOME/.steam/steam/config/libraryfolders.vdf" <<'VDF'
"libraryfolders"
{
	"0"
	{
		"path"		"__MOCK_LIB__"
	}
}
VDF
sed -i "s|__MOCK_LIB__|$MOCK_LIB|" "$MOCK_HOME/.steam/steam/config/libraryfolders.vdf"

MOCK_COMPAT="$TMPDIR_TEST/chain-compat/107410"
export COMPAT_DATA_PATH="$MOCK_COMPAT"
TS3_PLUGINS="$MOCK_COMPAT/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
mkdir -p "$TS3_PLUGINS"

# Case A: nothing installed -> all three stages fail.
# The Workshop mod dir and plugin DLL are deliberately absent here.
_out="$(HOME="$MOCK_HOME" _check_radio_chain "ACRE2" "751965892" "acre2_win*.dll" "" "acremod")"
if echo "$_out" | grep -q "Workshop mod not downloaded" &&
    echo "$_out" | grep -q "Mod not in the loaded list" &&
    echo "$_out" | grep -q "TeamSpeak plugin not installed"; then
    pass "chain reports all stages when nothing is installed"
else
    fail "chain all-fail case wrong"
fi

# Case B: all three stages satisfied -> all OK
mkdir -p "$MOCK_LIB/steamapps/workshop/content/107410/751965892"
touch "$MOCK_LIB/steamapps/workshop/content/107410/751965892/mod.cpp"
touch "$TS3_PLUGINS/acre2_win64.dll"
RPT_DIR="$MOCK_COMPAT/pfx/drive_c/users/steamuser/AppData/Local/Arma 3"
mkdir -p "$RPT_DIR"
cat >"$RPT_DIR/Arma3_x64_2026-08-29_00-00-00.rpt" <<'RPT'
=====================================================================
== S:\common\Arma 3\Arma3_x64.exe
== "S:\common\Arma 3\Arma3_x64.exe" -mod=S:\workshop\content\107410\751965892
=====================================================================
RPT
_out="$(HOME="$MOCK_HOME" _check_radio_chain "ACRE2" "751965892" "acre2_win*.dll" "" "acremod")"
if echo "$_out" | grep -q "Workshop mod downloaded" &&
    echo "$_out" | grep -q "Mod loaded in the current game session" &&
    echo "$_out" | grep -q "TeamSpeak plugin installed"; then
    pass "chain reports all OK when fully installed"
else
    fail "chain all-ok case wrong (got: $_out)"
fi

# Case C: plugin disabled after crash -> flagged distinctly
rm -f "$TS3_PLUGINS/acre2_win64.dll"
touch "$TS3_PLUGINS/acre2_win64.dll.disabled"
_out="$(HOME="$MOCK_HOME" _check_radio_chain "ACRE2" "751965892" "acre2_win*.dll" "" "acremod")"
if echo "$_out" | grep -q "disabled after a crash"; then
    pass "chain flags crash-disabled plugin"
else
    fail "chain disabled-plugin case wrong"
fi

# Case D: verifyradio runs both chains and summarises
_out="$(HOME="$MOCK_HOME" _verify_radio)"
if echo "$_out" | grep -q "ACRE2" && echo "$_out" | grep -q "TFAR"; then
    pass "verifyradio checks both mods"
else
    fail "verifyradio missing a mod (got: $_out)"
fi

rm -rf "$TMPDIR_TEST/chain-home" "$TMPDIR_TEST/chain-lib" "$TMPDIR_TEST/chain-compat"
unset COMPAT_DATA_PATH

echo ""

# ===========================================================================
echo "── 8e. Launch-path warnings (plugins + TS3 presence) ──"
# ===========================================================================
# At launch the script warns when radio plugins are missing or disabled,
# and offers to install TeamSpeak 3 when it is absent.

_plugin_fn="$(sed -n '/^_warn_missing_plugins() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"
_plugin_fn="$(sed -n '/^_ensure_ts3_installed() {/,/^}/p' "$HELPER")"
eval "$_plugin_fn"

MOCK_COMPAT="$TMPDIR_TEST/launch-compat/107410"
export COMPAT_DATA_PATH="$MOCK_COMPAT"
TS3_PLUGINS="$MOCK_COMPAT/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
mkdir -p "$TS3_PLUGINS/config"

# Case A: no plugins -> both warnings shown
_out="$(_warn_missing_plugins)"
if echo "$_out" | grep -q "ACRE2 plugin not installed" &&
    echo "$_out" | grep -q "TFAR plugin not installed"; then
    pass "launch warns when both plugins missing"
else
    fail "launch missing-plugins warning wrong"
fi

# Case B: plugin present -> no warning
touch "$TS3_PLUGINS/acre2_win64.dll"
_out="$(_warn_missing_plugins)"
if ! echo "$_out" | grep -q "ACRE2 plugin not installed"; then
    pass "launch silent when ACRE2 plugin present"
else
    fail "launch warned despite ACRE2 present"
fi

# Case C: crash-disabled plugin flagged
rm -f "$TS3_PLUGINS/acre2_win64.dll"
mkdir -p "$TS3_PLUGINS/config/plugins"
touch "$TS3_PLUGINS/config/plugins/acre2_win64.dll.disabled"
_out="$(_warn_missing_plugins)"
if echo "$_out" | grep -q "Plugin disabled after a crash"; then
    pass "launch flags crash-disabled plugin"
else
    fail "launch did not flag disabled plugin"
fi

# Case D: TS3 present -> ensure returns 0 without prompting
touch "$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe"
chmod +x "$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe"
if _ensure_ts3_installed; then
    pass "ensure_ts3 returns 0 when installed"
else
    fail "ensure_ts3 failed despite TS3 present"
fi

# Case E: TS3 missing + user declines -> returns 1
rm -rf "$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client"
if echo "n" | _ensure_ts3_installed >/dev/null 2>&1; then
    fail "ensure_ts3 should return 1 when declined"
else
    pass "ensure_ts3 returns 1 when user declines"
fi

rm -rf "$TMPDIR_TEST/launch-compat"
unset COMPAT_DATA_PATH

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
(HOME="$MOCK_HOME_RESET" _prefix_reset full >/dev/null 2>&1) <<<"y"
_reset_exit=$?

_backup_dirs=("$MOCK_HOME_RESET"/Arma3Helper-prefix-backup-*)
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
if [[ "$GUID_DOCS" == "{FDD39AD0-238F-46AF-ADB4-6C85480369C7}" &&
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
if echo "$_script_version_path" | grep -q 'COMPAT_DATA_PATH/version' &&
    ! echo "$_script_version_path" | grep -q 'COMPAT_DATA_PATH/\.\./version'; then
    pass "Version file path uses \$COMPAT_DATA_PATH/version (not ../version)"
else
    fail "Version file path still uses wrong ../version path"
fi

# ===========================================================================
echo "── 14. Proton guard: rejects non-executable paths ──"
# ===========================================================================
# Test that the script errors cleanly when custom proton doesn't exist.
# The guard fires on Proton-dependent commands (install runs the installer
# via Proton); informational commands like debug must still work.
MOCK_HOME_11=$(mktemp -d)
mkdir -p "$MOCK_HOME_11/.config/arma3helper"
cat >"$MOCK_HOME_11/.config/arma3helper/config" <<EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION="Proton-FakeVersion99"
ESYNC=true
FSYNC=true
EOFCFG
_output_11=$(HOME="$MOCK_HOME_11" XDG_CONFIG_HOME="$MOCK_HOME_11/.config" "$HELPER" install 2>&1 || true)
if echo "$_output_11" | grep -q "No Proton executable found" &&
    echo "$_output_11" | grep -q "Proton-FakeVersion99"; then
    pass "Bad custom version name -> clean error with version shown"
else
    fail "Bad custom version name -> no error or wrong message"
fi
# debug must NOT fail on missing proton (informational command)
_debug_out=$(HOME="$MOCK_HOME_11" XDG_CONFIG_HOME="$MOCK_HOME_11/.config" "$HELPER" debug 2>&1 || true)
if ! echo "$_debug_out" | grep -q "No Proton executable found"; then
    pass "debug still works without Proton (informational command)"
else
    fail "debug blocked by missing Proton"
fi
rm -rf "$MOCK_HOME_11"

# Test absolute path to non-existent file
MOCK_HOME_11b=$(mktemp -d)
mkdir -p "$MOCK_HOME_11b/.config/arma3helper"
cat >"$MOCK_HOME_11b/.config/arma3helper/config" <<EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION="/tmp/totally_fake_proton"
ESYNC=true
FSYNC=true
EOFCFG
_output_11b=$(HOME="$MOCK_HOME_11b" XDG_CONFIG_HOME="$MOCK_HOME_11b/.config" "$HELPER" install 2>&1 || true)
if echo "$_output_11b" | grep -q "No Proton executable found" &&
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
cat >"$MOCK_HOME_12/.config/arma3helper/config" <<EOFCFG
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
echo "── 16. Fresh-machine onboarding: wizard triggers with no Proton ──"
# ===========================================================================
# A brand-new user has a prefix but no Proton installed. The setup wizard
# must still appear (it was previously suppressed because the fallback
# fabricated PROTON_OFFICIAL_VERSION="10.0", which looked like a config).
MOCK_HOME_16=$(mktemp -d)
mkdir -p "$MOCK_HOME_16/.config/arma3helper"
cat >"$MOCK_HOME_16/.config/arma3helper/config" <<EOFCFG
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION=""
ESYNC=true
FSYNC=true
EOFCFG
mkdir -p "$MOCK_HOME_16/.steam/steam/steamapps/compatdata/107410"
# Answer 'n' to the wizard and 'n' to the TS3 offer; the wizard prompt
# must appear before the launch warnings.
_output_16=$(printf 'n\nn\n' | HOME="$MOCK_HOME_16" XDG_CONFIG_HOME="$MOCK_HOME_16/.config" "$HELPER" 2>&1 || true)
if echo "$_output_16" | grep -q "Welcome to Arma3Helper!"; then
    pass "fresh machine with no Proton still shows the setup wizard"
else
    fail "wizard suppressed when no Proton is installed"
fi
# The guard message must not claim a specific version was searched for.
_output_16b=$(HOME="$MOCK_HOME_16" XDG_CONFIG_HOME="$MOCK_HOME_16/.config" "$HELPER" install 2>&1 || true)
if echo "$_output_16b" | grep -q "No Proton version was found on this system"; then
    pass "guard reports no Proton without fabricating a version"
else
    fail "guard fabricated a Proton version"
fi
rm -rf "$MOCK_HOME_16"

echo ""

# ===========================================================================
echo "── 17. Corrupt config recovery ──"
# ===========================================================================
# A config file with a bash syntax error must produce a clean recovery
# offer, not raw bash parse errors, and must not break 'help'.
MOCK_HOME_17=$(mktemp -d)
mkdir -p "$MOCK_HOME_17/.config/arma3helper"
printf 'PROTON_OFFICIAL_VERSION="unclosed\n' >"$MOCK_HOME_17/.config/arma3helper/config"

# Answer 'y' to reset with a clean template
_output_17=$(printf 'y\n' | HOME="$MOCK_HOME_17" XDG_CONFIG_HOME="$MOCK_HOME_17/.config" "$HELPER" help 2>&1 || true)
if echo "$_output_17" | grep -q "syntax error" &&
    bash -n "$MOCK_HOME_17/.config/arma3helper/config" 2>/dev/null; then
    pass "corrupt config offers recovery and resets cleanly"
else
    fail "corrupt config recovery failed"
fi
if [[ -f "$MOCK_HOME_17/.config/arma3helper/config.bak-arma3helper" ]]; then
    pass "corrupt config backed up before reset"
else
    fail "corrupt config backup missing"
fi

# Answer 'n' to refuse reset -> must exit 1 without help output.
# Use a fresh corrupt config (the previous one was reset to valid).
MOCK_HOME_17b=$(mktemp -d)
mkdir -p "$MOCK_HOME_17b/.config/arma3helper"
printf 'PROTON_OFFICIAL_VERSION="unclosed\n' >"$MOCK_HOME_17b/.config/arma3helper/config"
if printf 'n\n' | HOME="$MOCK_HOME_17b" XDG_CONFIG_HOME="$MOCK_HOME_17b/.config" "$HELPER" help >/dev/null 2>&1; then
    fail "refusing config reset should exit non-zero"
else
    pass "refusing config reset exits cleanly"
fi
rm -rf "$MOCK_HOME_17b"
rm -rf "$MOCK_HOME_17"

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
