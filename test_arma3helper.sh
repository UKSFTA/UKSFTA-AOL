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
#   6. End-to-end auto-detect against real system
#   7. Edge cases (empty prefix, missing files, weird names)

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

assert_true() {
    local label="$2"
    if [[ "$1" == true ]]; then
        pass "$label"
    else
        fail "$label — expected true, got false"
    fi
}

assert_false() {
    local label="$2"
    if [[ "$1" == false ]]; then
        pass "$label"
    else
        fail "$label — expected false, got true"
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
echo "── 8. End-to-end: real system auto-detect ──"
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
echo "── 9. Dry-run: script runs without errors ──"
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
# Summary
# ===========================================================================
TOTAL=$((PASS + FAIL + SKIP))
echo "═══════════════════════════════════════════════════════════════"
echo "  Results: $PASS passed, $FAIL failed, $SKIP skipped (of $TOTAL)"
echo "═══════════════════════════════════════════════════════════════"

if [[ $FAIL -gt 0 ]]; then
    exit 1
fi
exit 0
