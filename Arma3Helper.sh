#!/usr/bin/env bash

# SPDX-License-Identifier: GPL-2.0-only
#
# Arma3Helper.sh – Helper script for running Arma 3 with ACRE2 or TFAR on Linux
#
# Copyright (C) 2026 UKSFTA
#
# Original Author:  Ingo Reitz <9l@9lo.re>
# Contributing:     famfo <famfo@famfo.xyz>
# Testing:          G4rrus#3755
#
# This script does the following:
#   - Launches TeamSpeak 3 (Windows version) inside Arma's Wine/Proton prefix
#   - Installs TeamSpeak 3 into Arma's Wine/Proton prefix
#   - Runs winetricks and winecfg inside that prefix
#   - Auto-detects your Steam library paths, including external drives
#   - Lists available Proton versions (official and custom, for example GE-Proton)
#   - Checks for required system dependencies (GStreamer, winetricks, etc.)
#
# GLOSSARY:
#   Wine prefix / compatdata – A sandboxed Windows environment that Proton
#     creates for each game. Arma 3's prefix lives at:
#     <SteamLibrary>/steamapps/compatdata/107410/
#
#   Proton – Valve's compatibility layer. It translates Windows game calls
#     into Linux equivalents. Think of it as a Wine wrapper with extras.
#
#   ACRE2 / TFAR – TeamSpeak 3 plugins that provide in-game radio simulation
#     for Arma 3. Both require TeamSpeak 3 (Windows version) to run inside
#     the same Wine prefix as Arma.
#
# USAGE:
#   ./Arma3Helper.sh            – Launch TeamSpeak 3 (start Arma first!)
#   ./Arma3Helper.sh help       – Show full usage information
#   ./Arma3Helper.sh checkdeps  – Check required system packages
#   ./Arma3Helper.sh listproton – List available Proton versions
#
# Original Repository: https://github.com/ninelore/armaonlinux
# Support:    https://discord.gg/p28Ra36  (ArmaOnUnix Discord)

_SCRIPTVER="2.5.0"

###############################################################################
## USER CONFIGURATION
##
## You can edit the values directly here, or use an external config file.
## The external config file is preferred – it survives script updates.
## Run: ./Arma3Helper.sh createconfig
##
## IMPORTANT: All settings here can be left empty for auto-detection.
##            Only set them manually if auto-detection fails.
###############################################################################

# -----------------------------------------------------------------------------
# PROTON VERSION (official)
# -----------------------------------------------------------------------------
# Set this to the Proton version you selected in Arma 3's Compatibility tab
# in Steam. This MUST match exactly.
#
# Valid values:
#   Official versions: '11.0', '10.0', '9.0', '8.0', '7.0', '6.3', '5.13', '5.0'
#   Proton Experimental: 'Experimental'
#
# Leave empty to auto-detect the version that created Arma's prefix.
# If you use a custom/GE Proton build, leave this empty and set
# PROTON_CUSTOM_VERSION below instead.
#
PROTON_OFFICIAL_VERSION=""

# -----------------------------------------------------------------------------
# ARMA 3 COMPATDATA (Wine prefix) PATH
# -----------------------------------------------------------------------------
# Path to Arma 3's Wine prefix directory.
# Leave empty for auto-detection (recommended – works with external drives).
#
# The auto-detector scans all your Steam libraries from libraryfolders.vdf.
#
# If you need to set this manually, the format is:
#   /path/to/SteamLibrary/steamapps/compatdata/107410
#
COMPAT_DATA_PATH=""

# -----------------------------------------------------------------------------
# STEAM LIBRARY PATH (for Proton itself)
# -----------------------------------------------------------------------------
# Path to the steamapps folder where Proton is installed.
# Leave empty for auto-detection (recommended).
#
# Only set this manually if Proton lives in a different library than Arma 3
# AND auto-detection is not finding it.
# Example: '/media/external_drive/SteamLibrary/steamapps'
#
STEAM_LIBRARY_PATH=""

# -----------------------------------------------------------------------------
# CUSTOM / GE PROTON VERSION
# -----------------------------------------------------------------------------
# Use this if you are running a custom Proton build such as GE-Proton or
# Proton-TKG. Custom builds are installed into:
#   ~/.steam/steam/compatibilitytools.d/
#
# You can provide:
#   (a) The folder name inside compatibilitytools.d:
#         for example 'GE-Proton9-20'
#   (b) An absolute path to the proton executable:
#         for example '/home/user/.steam/steam/compatibilitytools.d/GE-Proton9-20/proton'
#
# Leave empty if you are using an official Proton version.
# Run './Arma3Helper.sh listproton' to see what custom builds are available.
#
PROTON_CUSTOM_VERSION=""

# -----------------------------------------------------------------------------
# ESYNC / FSYNC
# -----------------------------------------------------------------------------
# Esync and Fsync are performance optimisations that reduce CPU overhead in
# Wine/Proton. These settings MUST match what Arma 3 uses in Steam.
#
# If you have not explicitly disabled Esync or Fsync for Arma 3 in Steam,
# leave both as true. Mismatched settings can cause instability.
#
ESYNC=true
FSYNC=true

###############################################################################
## DO NOT EDIT BELOW THIS LINE
###############################################################################

# -----------------------------------------------------------------------------
# SIGNAL HANDLING
# -----------------------------------------------------------------------------
# Warn if the user interrupts a long-running operation (winetricks, install).
# The prefix may be left incomplete; do not silently pretend otherwise.
_interrupt_notice() {
    echo ""
    echo -e "\e[31mInterrupted.\e[0m The Wine prefix may be incomplete."
    echo "Re-run the command to finish, or run 'winetricks Arma' to repair."
    exit 130
}
trap '_interrupt_notice' INT TERM

# -----------------------------------------------------------------------------
# VERSIONING
# -----------------------------------------------------------------------------
# Check for script updates (once per day max)
_update_stamp() { echo "$USERCONFIG/.last_update_check"; }

_check_for_update() {
    # Skip if no curl, offline mode requested, or checked within last 24 hours
    command -v curl &>/dev/null || return 0
    [[ -n "$ARMA3HELPER_OFFLINE" ]] && return 0
    local stamp
    stamp="$(_update_stamp)"
    if [[ -f "$stamp" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
        (( age < 86400 )) && return 0
    fi

    # Fetch remote script header and extract its _SCRIPTVER
    # Use a short timeout so offline/airgapped use does not stall commands.
    local remote_ver
    remote_ver=$(curl -fs --max-time 2 --connect-timeout 2 \
        "https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh" \
        2>/dev/null | grep -m1 '^_SCRIPTVER=' | cut -d'"' -f2)

    # Record check time only on a successful fetch, so a flaky network
    # retries on the next run instead of waiting 24 hours.
    if [[ -n "$remote_ver" ]]; then
        date +%s > "$stamp" 2>/dev/null
    fi

    if [[ -n "$remote_ver" && "$remote_ver" != "$_SCRIPTVER" ]]; then
        echo ""
        echo -e "\e[33mA new version of Arma3Helper is available: $_SCRIPTVER → $remote_ver\e[0m"
        echo "  Run './Arma3Helper.sh update' to update."
        echo ""
    fi
}

# -----------------------------------------------------------------------------
# CONFIGURATION
# -----------------------------------------------------------------------------
# Generate config on demand if it doesn't exist
_ensure_config() {
    if [[ ! -e "$USERCONFIG/config" ]]; then
        if ! mkdir -p "$USERCONFIG" 2>/dev/null; then
            echo -e "\e[31mError\e[0m: Cannot create config directory: $USERCONFIG"
            echo "If you ran this script with sudo, fix the ownership:"
            echo "  sudo chown -R $(id -un):$(id -gn) $USERCONFIG"
            exit 1
        fi
        cat <<'EOF' > "$USERCONFIG/config"
# Arma3Helper user configuration
#
# This file persists across script updates. Settings here override the
# defaults built into Arma3Helper.sh.
#
# Leave a value empty to use auto-detection. Only set values manually if
# auto-detection fails.
#
# Generated by Arma3Helper

# -----------------------------------------------------------------------------
# PROTON VERSION (official)
# -----------------------------------------------------------------------------
# Set this to the Proton version you selected for Arma 3 in the
# Compatibility tab in Steam. This must match exactly.
#
# Valid values:
#   Official versions: '11.0', '10.0', '9.0', '8.0', '7.0', '6.3'
#   Proton Experimental: 'Experimental'
#
# Leave empty to auto-detect the version that created Arma's prefix.
# If you use a custom or GE Proton build, leave this empty and set
# PROTON_CUSTOM_VERSION below instead.
#
PROTON_OFFICIAL_VERSION=""

# -----------------------------------------------------------------------------
# ARMA 3 COMPATDATA (Wine prefix) PATH
# -----------------------------------------------------------------------------
# Path to Arma 3's Wine prefix directory.
# Leave empty for auto-detection. Auto-detection works with external drives.
#
# If you need to set this manually, the format is:
#   /path/to/SteamLibrary/steamapps/compatdata/107410
#
COMPAT_DATA_PATH=""

# -----------------------------------------------------------------------------
# STEAM LIBRARY PATH (for Proton itself)
# -----------------------------------------------------------------------------
# Path to the steamapps folder where Proton is installed.
# Leave empty for auto-detection (recommended).
#
# Only set this manually if Proton lives in a different library than Arma 3
# and auto-detection does not find it.
# Example: '/media/external_drive/SteamLibrary/steamapps'
#
STEAM_LIBRARY_PATH=""

# -----------------------------------------------------------------------------
# CUSTOM / GE PROTON VERSION
# -----------------------------------------------------------------------------
# Use this if you run a custom Proton build such as GE-Proton or Proton-TKG.
# Custom builds are installed into:
#   ~/.steam/steam/compatibilitytools.d/
#
# You can provide:
#   (a) The folder name inside compatibilitytools.d:
#         for example 'GE-Proton9-20'
#   (b) An absolute path to the proton executable:
#         for example '/home/user/.steam/steam/compatibilitytools.d/GE-Proton9-20/proton'
#
# Leave empty if you use an official Proton version.
# Run './Arma3Helper.sh listproton' to see which custom builds are installed.
#
PROTON_CUSTOM_VERSION=""

# -----------------------------------------------------------------------------
# ESYNC / FSYNC
# -----------------------------------------------------------------------------
# Esync and Fsync reduce CPU overhead in Wine/Proton.
# These settings must match what Arma 3 uses in Steam.
#
# If you have not disabled Esync or Fsync for Arma 3 in Steam, leave both
# as true. Mismatched settings can cause instability.
#
ESYNC=true
FSYNC=true

# -----------------------------------------------------------------------------
# STEAM COMPAT INSTALL PATH / LIBRARY PATHS (advanced)
# -----------------------------------------------------------------------------
# Proton builds with the gamedrive option enabled (for example Proton Hotfix)
# need these two variables to resolve the game's Steam library during
# 'proton run'. Without them, Proton deletes the S: drive from the prefix,
# which breaks server signature checks. The script derives them from
# COMPAT_DATA_PATH automatically. Set them here only to override that.
#
# Leave both empty unless you know you need an override.
#
STEAM_COMPAT_INSTALL_PATH=""
STEAM_COMPAT_LIBRARY_PATHS=""

# -----------------------------------------------------------------------------
# BIND HOST DIRECTORIES (set by the script)
# -----------------------------------------------------------------------------
# Set to true by './Arma3Helper.sh bindhost'. Do not edit by hand.
# When true, Arma 3 reads and writes profiles on the real host Documents
# and Downloads folders instead of the prefix-local ones. 'prefix reset
# --full' re-applies the binding automatically after recreating the prefix.
#
BIND_HOST_DIRS=false
EOF
        chmod 600 "$USERCONFIG/config"
        echo "Created default configuration at $USERCONFIG/config"
    elif [[ ! -r "$USERCONFIG/config" ]]; then
        echo -e "\e[31mError\e[0m: Config file is not readable: $USERCONFIG/config"
        echo "If you ran this script with sudo, fix the ownership:"
        echo "  sudo chown -R $(id -un):$(id -gn) $USERCONFIG"
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# CONFIGURATION SETUP
# -----------------------------------------------------------------------------
if [[ -n "$XDG_CONFIG_HOME" ]]; then
    USERCONFIG="$XDG_CONFIG_HOME/arma3helper"
else
    USERCONFIG="$HOME/.config/arma3helper"
fi

_ensure_config
# Validate the config before sourcing it. A bad edit produces raw bash
# errors that confuse new users; catch it and offer a clean recovery.
if ! bash -n "$USERCONFIG/config" 2>/dev/null; then
    echo -e "\e[31mError\e[0m: Your config file has a syntax error:"
    echo "  $USERCONFIG/config"
    echo ""
    echo "The script keeps a backup at: $USERCONFIG/config.bak-arma3helper"
    cp -f "$USERCONFIG/config" "$USERCONFIG/config.bak-arma3helper" 2>/dev/null
    echo ""
    read -p "Fix it now with a clean template? (y/n) " -n 1 -r
    echo
    if [[ "$REPLY" =~ ^[Yy]$ ]]; then
        cat <<'EOF' > "$USERCONFIG/config"
# Arma3Helper user configuration
#
# This file persists across script updates. Settings here override the
# defaults built into Arma3Helper.sh.
#
# Leave a value empty to use auto-detection. Only set values manually if
# auto-detection fails.
#
# Generated by Arma3Helper (recovered from a syntax error)

PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION=""
STEAM_COMPAT_INSTALL_PATH=""
STEAM_COMPAT_LIBRARY_PATHS=""
ESYNC=true
FSYNC=true
BIND_HOST_DIRS=false
EOF
        chmod 600 "$USERCONFIG/config"
        echo "Config reset. Run 'createconfig' for the full documented template."
    else
        echo "Fix the error in the file, then re-run this command."
        exit 1
    fi
fi
# shellcheck source=/dev/null
source "$USERCONFIG/config"

# -----------------------------------------------------------------------------
# SETUP WIZARD
# -----------------------------------------------------------------------------
# Run setup wizard if config is default and Arma prefix exists.
# The wizard dismiss flag persists: answering "n" disables the prompt until
# the config file is edited again.

# _warn_missing_plugins
#   Lightweight radio-plugin presence check for the launch path. Warns
#   with the exact fix when a plugin is missing or crash-disabled, instead
#   of letting the user discover it after joining a mission with no radio.
_warn_missing_plugins() {
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    [[ -d "$plugins_dir" ]] || return 0

    local acre2=0 tfar=0 disabled="" f
    # shellcheck disable=SC2012
    for f in "$plugins_dir"/acre2_win*.dll; do [[ -f "$f" ]] && acre2=1; done
    # shellcheck disable=SC2012
    for f in "$plugins_dir"/TFAR_*.dll; do [[ -f "$f" ]] && tfar=1; done
    # shellcheck disable=SC2012
    for f in "$plugins_dir"/config/plugins/*.disabled; do
        case "$(basename "$f")" in
            acre2_*.dll.disabled|TFAR_*.dll.disabled)
                disabled="${disabled:+$disabled, }$(basename "$f")"
                ;;
        esac
    done

    local warn=0
    if [[ "$acre2" == 0 ]]; then
        echo -e "\e[33mNote\e[0m: ACRE2 plugin not installed. Radios will not work."
        echo "  Install with:  ./Arma3Helper.sh acremod"
        warn=1
    fi
    if [[ "$tfar" == 0 ]]; then
        echo -e "\e[33mNote\e[0m: TFAR plugin not installed. Radios will not work."
        echo "  Install with:  ./Arma3Helper.sh tfarmod"
        warn=1
    fi
    if [[ -n "$disabled" ]]; then
        echo -e "\e[33mNote\e[0m: Plugin disabled after a crash: $disabled"
        echo "  Re-enable with:  ./Arma3Helper.sh acremod --enable"
        echo "                  ./Arma3Helper.sh tfarmod --enable"
        warn=1
    fi
    if [[ "$warn" == 1 ]]; then
        echo ""
        echo "  Run 'verifyradio' for the full check:  ./Arma3Helper.sh verifyradio"
    fi
}

_setup_wizard() {
    if [[ -n "$WIZARD_DISMISSED" ]]; then
        return 0
    fi

    # Check if config appears to be default (only defaults)
    local is_default=true
    if [[ -n "$PROTON_OFFICIAL_VERSION" || -n "$PROTON_CUSTOM_VERSION" || "$ESYNC" == "false" || "$FSYNC" == "false" ]]; then
        is_default=false
    fi

    if [[ "$is_default" == true && -d "$COMPAT_DATA_PATH" ]]; then
        echo -e "\e[32mWelcome to Arma3Helper!\e[0m"
        echo "Detected existing Arma 3 prefix, but configuration is default."
        echo "Would you like to run the setup wizard to prepare your prefix for ACRE2/TFAR?"
        echo "This will check your system dependencies and run the recommended Winetricks fixes."
        read -p "(y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            _check_dependencies

            # Step 1: TeamSpeak 3 must exist before plugins can be installed.
            if ! _ensure_ts3_installed; then
                echo "Setup paused. Install TeamSpeak 3 with:  ./Arma3Helper.sh install"
                return 0
            fi

            # Step 2: Winetricks DLLs for audio and thermal-vision fixes.
            _get_wrappercmd || return 0
            echo "Installing recommended DLLs..."
            export WINEPREFIX="$COMPAT_DATA_PATH/pfx"
            "${_WRAPPER[@]}" d3dcompiler_43 d3dx10_43 d3dx11_43 mfc140 xact_x64 xaudio29 xaudio2_9

            # Step 3: Verify the radio plugins.
            echo ""
            echo "Verifying radio plugins..."
            _check_radio_plugins

            echo ""
            echo -e "\e[32mSetup complete.\e[0m"
            echo "If your unit uses TFAR, run:  ./Arma3Helper.sh tfarmod"
            # A successful setup counts as dismissed, so the prompt does not
            # return on the next launch.
            if ! grep -q '^WIZARD_DISMISSED=' "$USERCONFIG/config" 2>/dev/null; then
                {
                    echo "WIZARD_DISMISSED=true"
                    cat "$USERCONFIG/config"
                } > "$USERCONFIG/config.tmp" 2>/dev/null && mv "$USERCONFIG/config.tmp" "$USERCONFIG/config"
            fi
        else
            # Persist the dismissal so the prompt does not return on every launch
            {
                echo "WIZARD_DISMISSED=true"
                cat "$USERCONFIG/config"
            } > "$USERCONFIG/config.tmp" 2>/dev/null && mv "$USERCONFIG/config.tmp" "$USERCONFIG/config"
            echo "Wizard dismissed. Edit your config file to run it again."
        fi
    fi
}

###############################################################################
## HELPER FUNCTIONS
###############################################################################

# _checkinstall <command>
#   Verify that a command-line tool is installed and in PATH.
#   Prints an error and exits if not found.
_checkinstall() {
    if [[ ! "$(command -v "$1")" ]]; then
        echo -e "\e[31mError\e[0m: '$1' is not installed or not in PATH."
        exit 1
    fi
}

# _checkpath <file_path> <display_name>
#   Verify that an executable file exists at the given path.
#   Prints an error and exits if not found or not executable.
_checkpath() {
    if [[ ! -x "$1" ]]; then
        echo -e "\e[31mError\e[0m: $2 not found at:"
        echo "  $1"
        exit 1
    fi
}

# _ensure_ts3_installed
#   Offer to auto-install TeamSpeak 3 when it is missing at launch time.
#   Returns 1 if the user declines or the install fails.
_ensure_ts3_installed() {
    local ts3exe="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe"
    if [[ -x "$ts3exe" ]]; then
        return 0
    fi

    echo -e "\e[33mTeamSpeak 3 is not installed in Arma's prefix.\e[0m"
    echo "Arma3Helper can download and install it automatically."
    read -p "Install TeamSpeak 3 now? (y/n) " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        echo "Install it later with:  ./Arma3Helper.sh install"
        return 1
    fi
    _install_ts3_auto
}

# _install_ts3_auto
#   Download and silently install the latest TeamSpeak 3 into the prefix.
_install_ts3_auto() {
    if ! _download_ts3; then
        echo "Manual install:  ./Arma3Helper.sh install /path/to/installer.exe"
        return 1
    fi
    echo "Installing TeamSpeak 3 (silent, for All Users)..."
    if "$PROTONEXEC" run "$_TS3_INSTALLER" /S /ALLUSERS; then
        if [[ -x "$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe" ]]; then
            echo -e "\e[32mTeamSpeak 3 installed successfully.\e[0m"
            return 0
        fi
    fi
    echo -e "\e[33mWarning\e[0m: The silent installer did not complete cleanly."
    echo "Run it manually:  ./Arma3Helper.sh install"
    return 1
}

# _confirmation <question>
#   Ask the user a yes/no question. Exits if they answer no.
_confirmation() {
    read -p "$1 (y/n) " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        exit 1
    fi
}

# _remove_gamepad_plugin
#   Delete the Gamepad and Joystick Hotkey Support plugin from the prefix.
#   The plugin crashes TeamSpeak 3 on many systems and TeamSpeak refuses to
#   fix it. The canonical Linux guides (ninelore, endigma) say to delete it.
#   This runs before every launch and is a no-op when the plugin is absent.
_remove_gamepad_plugin() {
    local plugins_root="$COMPAT_DATA_PATH/pfx/drive_c"
    local found=0
    local candidate
    # The plugin can live in the per-user Roaming folder or the Program Files
    # install folder, depending on the TS3 install type chosen.
    for candidate in \
        "$plugins_root/users/steamuser/AppData/Roaming/TS3Client/plugins" \
        "$plugins_root/Program Files/TeamSpeak 3 Client/plugins"; do
        if [[ -d "$candidate" ]]; then
            # One glob covers both the plugin DLL and its directory, since the
            # TS3 plugin installs as either gamepad_joystick.dll or a
            # gamepad_joystick/ folder depending on version.
            local f
            for f in "$candidate"/gamepad_joystick*; do
                if [[ -e "$f" ]]; then
                    rm -rf "$f"
                    echo "Removed crashing plugin: $(basename "$f")"
                    found=1
                fi
            done
        fi
    done
    if [[ "$found" == 1 ]]; then
        echo "Gamepad plugin removed. TS3 will no longer crash on startup."
    fi
    # Nothing to remove is a success, not an error.
    return 0
}

# _find_steam_root
#   Locate the Steam installation directory by checking common locations,
#   including standard installs and Flatpak sandboxed installs.
_find_steam_root() {
    local candidates=(
        "$HOME/.steam/steam"
        "$HOME/.local/share/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
        "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    )
    for path in "${candidates[@]}"; do
        if [[ -d "$path/steamapps" ]]; then
            echo "$path"
            return
        fi
    done
    # Not found
    echo ""
}

# _find_steam_libraries
#   Parse Steam's libraryfolders.vdf to discover all configured Steam library
#   paths. This handles external drives and additional library folders that
#   users add inside Steam. Returns one path per line.
#
#   Why this matters: many users store games on a separate drive or SSD.
#   The old approach of hardcoding ~/.steam/steam/steamapps fails in these
#   cases. This function reads the paths directly from Steam's config.
_find_steam_libraries() {
    local steam_root
    steam_root="$(_find_steam_root)"

    if [[ -z "$steam_root" ]]; then
        echo ""
        return
    fi

    # Steam stores library paths in config/libraryfolders.vdf.
    # Older Steam versions used steamapps/libraryfolders.vdf – check both.
    local vdf=""
    if [[ -f "$steam_root/config/libraryfolders.vdf" ]]; then
        vdf="$steam_root/config/libraryfolders.vdf"
    elif [[ -f "$steam_root/steamapps/libraryfolders.vdf" ]]; then
        vdf="$steam_root/steamapps/libraryfolders.vdf"
    fi

    if [[ -z "$vdf" ]]; then
        # VDF not found – fall back to the steam root.
        # Consumers append /steamapps themselves, so return the root, not steamapps.
        echo "$steam_root"
        return
    fi

    # Extract all 'path' key values from the VDF.
    # VDF format example:
    #     'path'    '/media/external/SteamLibrary'
    # The grep pattern looks for lines with 'path' and the sed strips quotes.
    grep -E '"path"' "$vdf" | sed -E 's/.*"path"[[:space:]]+"(.*)"/\1/'
}

# _find_arma_library
#   Search all Steam libraries to find the one that contains Arma 3
#   (Steam App ID 107410). Returns the path to that library's steamapps folder.
#
#   Detection order:
#     1. Parse libraryfolders.vdf for the library that lists app 107410
#        in its 'apps' block (the authoritative source).
#     2. Fall back to scanning each library for a compatdata/107410
#        directory that actually has content (pfx/ subdirectory).
#        An empty compatdata directory (Steam junk) is NOT a match.
_find_arma_library() {
    local steam_root
    steam_root="$(_find_steam_root)"
    local vdf=""

    if [[ -f "$steam_root/config/libraryfolders.vdf" ]]; then
        vdf="$steam_root/config/libraryfolders.vdf"
    elif [[ -f "$steam_root/steamapps/libraryfolders.vdf" ]]; then
        vdf="$steam_root/steamapps/libraryfolders.vdf"
    fi

    # Method 1: Parse VDF for the library that actually owns app 107410
    if [[ -n "$vdf" ]]; then
        local arma_lib
        arma_lib=$(awk '
            /"path"[[:space:]]*"/ {
                sub(/.*"path"[[:space:]]*"/, "")
                sub(/"$/, "")
                current = $0
            }
            /"107410"/ && current != "" {
                print current
                current = ""
            }
        ' "$vdf" | head -1)

        if [[ -n "$arma_lib" ]]; then
            local steamapps="$arma_lib/steamapps"
            if [[ -d "$steamapps/compatdata/107410" ]]; then
                echo "$steamapps"
                return
            fi
        fi
    fi

    # Method 2: Scan all libraries, but require actual content (pfx/)
    while IFS= read -r lib_path; do
        local compatdata="$lib_path/steamapps/compatdata/107410"
        if [[ -d "$compatdata/pfx" ]]; then
            echo "$lib_path/steamapps"
            return
        fi
    done < <(_find_steam_libraries)
    echo ""
}

# _list_custom_proton
#   List all custom Proton builds found in Steam's compatibilitytools.d folder.
#   This is where tools like GE-Proton are installed.
_list_custom_proton() {
    local steam_root
    steam_root="$(_find_steam_root)"
    local tools_dir="$steam_root/compatibilitytools.d"

    if [[ ! -d "$tools_dir" ]]; then
        echo "  (directory not found: $tools_dir)"
        return
    fi

    local found=false
    # Iterate through all entries in tools_dir
    shopt -s nullglob
    for dir in "$tools_dir"/*/; do
        _dir_name="$(basename "$dir")"
        # Only list if it is not an official Proton version (exclude if it starts with 'Proton' followed by a space)
        if [[ "$_dir_name" != Proton\ * ]]; then
            # Check if a 'proton' executable exists in the sub-directory
            if [[ -x "$dir/proton" ]]; then
                echo "  $_dir_name"
                found=true
            fi
        fi
    done
    shopt -u nullglob

    if [[ "$found" == false ]]; then
        echo "  (none installed)"
        echo "  Tip: Install GE-Proton via ProtonPlus, ProtonUp-Qt, or manually."
    fi
}

# _detect_distro
#   Detect the Linux distribution family.
#   Returns one of: arch, debian, fedora, unknown
_detect_distro() {
    if [[ -f /etc/os-release ]]; then
        # Read distro info from the standard os-release file
        local id id_like
        id=$(grep "^ID=" /etc/os-release | cut -d= -f2 | tr -d '"')
        id_like=$(grep "^ID_LIKE=" /etc/os-release | cut -d= -f2 | tr -d '"')
        local combined="$id_like $id"
        case "$combined" in
            *arch*)            echo "arch"    ;;
            *debian*|*ubuntu*) echo "debian"  ;;
            *fedora*|*rhel*|*centos*|*suse*)  echo "fedora"  ;;
            *)                 echo "unknown" ;;
        esac
    else
        echo "unknown"
    fi
}

# _check_pkg <package_name>
#   Check whether a system package is installed. Distro-aware.
#   Returns 0 (success) if installed, 1 if not.
_check_pkg() {
    local pkg="$1"
    local distro
    distro="$(_detect_distro)"

    case "$distro" in
        arch)
            pacman -Q "$pkg" &>/dev/null
            ;;
        debian)
            # Strip architecture suffix (for example :i386) for the package name check
            local base_pkg="${pkg%%:*}"
            dpkg -l "$base_pkg" 2>/dev/null | grep -q "^ii"
            ;;
        fedora)
            rpm -q "$pkg" &>/dev/null
            ;;
        *)
            # Generic fallback: check if a library matching the name is loaded
            ldconfig -p 2>/dev/null | grep -qi "$pkg"
            ;;
    esac
}

# _check_dependencies
#   Check all required system packages are installed.
#   This covers GStreamer (needed for Arma 3 audio under Proton), the
#   32-bit GStreamer variants (needed because Steam still uses 32-bit
#   components), and supporting tools like winetricks and curl.
#
#   Background: Arma 3 uses GStreamer for audio. Steam's runtime is partly
#   32-bit, so both 64-bit and 32-bit GStreamer libraries are required.
#   On Arch Linux, 32-bit packages come from the multilib repository.
_check_dependencies() {
    echo ""
    echo "================================================================"
    echo " Dependency Check"
    echo "================================================================"
    echo ""

    local distro
    distro="$(_detect_distro)"
    echo "Detected distribution family: $distro"
    echo ""
    echo "Checking GStreamer packages..."
    echo "  (GStreamer provides audio support for Arma 3 via Proton."
    echo "   Both 64-bit and 32-bit versions are required.)"
    echo ""

    # Define package names per distro.
    # The associative array maps a human-readable label to the package name.
    declare -A pkgs
    local install_cmd=""

    case "$distro" in
        arch)
            pkgs=(
                ["gstreamer (64-bit)"]="gstreamer"
                ["gst-plugins-base (64-bit)"]="gst-plugins-base"
                ["gst-plugins-good (64-bit)"]="gst-plugins-good"
                ["gstreamer (32-bit)"]="lib32-gstreamer"
                ["gst-plugins-base (32-bit)"]="lib32-gst-plugins-base"
                ["gst-plugins-good (32-bit)"]="lib32-gst-plugins-good"
            )
            install_cmd="sudo pacman -S"
            echo "  Note: 32-bit packages require the 'multilib' repository."
            echo "  Enable it in /etc/pacman.conf if not already active."
            echo ""
            ;;
        debian)
            pkgs=(
                ["gstreamer (64-bit)"]="gstreamer1.0-tools"
                ["gst-plugins-base (64-bit)"]="gstreamer1.0-plugins-base"
                ["gst-plugins-good (64-bit)"]="gstreamer1.0-plugins-good"
                ["gstreamer (32-bit)"]="gstreamer1.0-tools:i386"
                ["gst-plugins-base (32-bit)"]="gstreamer1.0-plugins-base:i386"
                ["gst-plugins-good (32-bit)"]="gstreamer1.0-plugins-good:i386"
            )
            install_cmd="sudo apt install"
            echo "  Note: 32-bit packages require multiarch support."
            echo "  Enable it with: sudo dpkg --add-architecture i386 && sudo apt update"
            echo ""
            ;;
        fedora)
            pkgs=(
                ["gstreamer (64-bit)"]="gstreamer1"
                ["gst-plugins-base (64-bit)"]="gstreamer1-plugins-base"
                ["gst-plugins-good (64-bit)"]="gstreamer1-plugins-good"
                ["gstreamer (32-bit)"]="gstreamer1.i686"
                ["gst-plugins-base (32-bit)"]="gstreamer1-plugins-base.i686"
                ["gst-plugins-good (32-bit)"]="gstreamer1-plugins-good.i686"
            )
            install_cmd="sudo dnf install"
            ;;
        *)
            echo -e "  \e[33mWarning\e[0m: Cannot identify your distribution."
            echo "  Please install the following packages manually:"
            echo "    gstreamer, gst-plugins-base, gst-plugins-good"
            echo "    (and their 32-bit / lib32 equivalents)"
            echo ""
            ;;
    esac

    # Check each package and collect any that are missing
    local missing=()
    if [[ ${#pkgs[@]} -gt 0 ]]; then
        for label in "${!pkgs[@]}"; do
            local pkg="${pkgs[$label]}"
            local check_name="${pkg%%:*}"   # strip :i386 suffix for the check
            if _check_pkg "$check_name"; then
                echo -e "  \e[32m[OK]\e[0m     $label  ($pkg)"
            else
                echo -e "  \e[31m[MISSING]\e[0m $label  ($pkg)"
                missing+=("$pkg")
            fi
        done
    fi

    echo ""
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo -e "\e[31mSome packages are missing.\e[0m Install them with:"
        echo ""
        echo "  $install_cmd ${missing[*]}"
        echo ""
    else
        echo -e "\e[32mAll GStreamer packages are present.\e[0m"
    fi

    # ----------------------------------------------------------------
    # Check for winetricks / protontricks
    # ----------------------------------------------------------------
    echo "Checking for winetricks / protontricks..."
    echo "  (Either tool is needed to install DLLs into Arma's prefix.)"
    echo ""
    local has_wt has_pt
    has_wt=$(command -v winetricks 2>/dev/null)
    has_pt=$(command -v protontricks 2>/dev/null)

    if [[ -n "$has_wt" ]]; then
        echo -e "  \e[32m[OK]\e[0m     winetricks  ($has_wt)"
    else
        echo -e "  \e[33m[MISSING]\e[0m winetricks"
    fi

    if [[ -n "$has_pt" ]]; then
        echo -e "  \e[32m[OK]\e[0m     protontricks  ($has_pt)"
    else
        echo -e "  \e[33m[MISSING]\e[0m protontricks"
    fi

    if [[ -z "$has_wt" && -z "$has_pt" ]]; then
        echo ""
        echo -e "  \e[31mNeither winetricks nor protontricks is installed.\e[0m"
        echo "  At least one is required. Install from your package manager."
    fi

    # ----------------------------------------------------------------
    # Check for curl (needed for update and createconfig)
    # ----------------------------------------------------------------
    echo ""
    echo "Checking for curl..."
    if command -v curl &>/dev/null; then
        echo -e "  \e[32m[OK]\e[0m     curl  ($(command -v curl))"
    else
        echo -e "  \e[31m[MISSING]\e[0m curl  (needed for 'update' and 'createconfig')"
    fi

    # ----------------------------------------------------------------
    # Check for vulkan tools (helps with Arma 3 crash issues)
    # ----------------------------------------------------------------
    echo ""
    echo "Checking for Vulkan tools..."
    echo "  (Vulkan support prevents Arma 3 from crashing on startup.)"
    echo ""
    if command -v vulkaninfo &>/dev/null; then
        echo -e "  \e[32m[OK]\e[0m     vulkan tools found"
    else
        echo -e "  \e[33m[MISSING]\e[0m vulkan tools not found"
        case "$distro" in
            arch)   echo "  Install: sudo pacman -S vulkan-tools" ;;
            debian) echo "  Install: sudo apt install mesa-vulkan-drivers vulkan-utils" ;;
            fedora) echo "  Install: sudo dnf install mesa-vulkan-drivers vulkan-tools" ;;
        esac
    fi

    # ----------------------------------------------------------------
    # Check the Steam library mount (external drives with noexec break
    # mod loading and Proton execution)
    # ----------------------------------------------------------------
    echo ""
    echo "Checking Steam library mount options..."
    echo "  (A noexec mount stops Proton and Workshop mods from running.)"
    echo ""
    local _mounted=0
    local lib_path
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        local compat="$lib_path/steamapps/compatdata/107410"
        local workshop="$lib_path/steamapps/workshop/content/107410"
        if [[ -d "$compat" || -d "$workshop" ]]; then
            _mounted=1
            local mnt
            mnt="$(df -P "$lib_path" 2>/dev/null | awk 'NR==2{print $6}')"
            if [[ -n "$mnt" ]]; then
                if mount | grep -q "on $mnt .*noexec"; then
                    echo -e "  \e[31m[ISSUE]\e[0m  $mnt is mounted noexec"
                    echo "    Proton and Workshop mods cannot run from a noexec drive."
                    echo "    Remount with exec:  sudo mount -o remount,exec $mnt"
                    echo "    Or move the Steam library to an ext4 drive."
                else
                    echo -e "  \e[32m[OK]\e[0m     $mnt (exec allowed)"
                fi
            fi
        fi
    done < <(_find_steam_libraries)
    if [[ "$_mounted" == 0 ]]; then
        echo "  (no Arma 3 library found to check)"
    fi

    # ----------------------------------------------------------------
    # Check for the Proton BattlEye Runtime (needed for online play)
    # ----------------------------------------------------------------
    echo ""
    echo "Checking for Proton BattlEye Runtime..."
    echo "  (BattlEye servers kick players without this runtime installed.)"
    echo ""
    if _check_battleye_runtime; then
        echo -e "  \e[32m[OK]\e[0m     Proton BattlEye Runtime found"
    else
        echo -e "  \e[33m[MISSING]\e[0m Proton BattlEye Runtime"
        echo "  Install it in Steam: Library -> Tools -> Proton BattlEye Runtime"
    fi

    # ----------------------------------------------------------------
    # Check ACRE2 / TFAR radio plugins in the TeamSpeak install
    # ----------------------------------------------------------------
    _check_radio_plugins

    echo ""
    echo "================================================================"
    echo ""
}

# _check_battleye_runtime
#   Return 0 if the Proton BattlEye Runtime is installed in any Steam library.
_check_battleye_runtime() {
    local lib_path
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        if [[ -d "$lib_path/steamapps/common/Proton BattlEye Runtime" ]]; then
            return 0
        fi
    done < <(_find_steam_libraries)
    return 1
}

# _check_radio_plugins
#   Verify the ACRE2 and TFAR plugins are present in the TeamSpeak plugins
#   directory inside the Arma prefix.
#
#   ACRE2 installs its own plugin DLLs when the mod loads, so a missing ACRE2
#   plugin usually means Arma has not been launched since the mod was added.
#   TFAR does not auto-install; use 'tfarmod' to copy its plugin.
#
#   A DLL with a '.disabled' suffix is TeamSpeak's own crash protection: the
#   plugin crashed the client once and TeamSpeak renamed it so it is not
#   loaded again. The plugin is still installed, but inactive.
_check_radio_plugins() {
    echo ""
    echo "Checking ACRE2 / TFAR radio plugins..."
    echo "  (These plugins let TeamSpeak exchange radio data with Arma 3.)"
    echo ""

    # Determine the prefix plugins directory. Prefer the All-Users install
    # location, which is where the script installs TeamSpeak.
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        echo -e "  \e[33m[MISSING]\e[0m TeamSpeak plugins folder not found."
        echo "    TeamSpeak 3 is not installed, or was installed for"
        echo "    the current user only. Run:  ./Arma3Helper.sh install"
        return 1
    fi

    local acre2_found=0
    local tfar_found=0
    local disabled_found=""

    # shellcheck disable=SC2012
    for f in "$plugins_dir"/*.dll; do
        case "$(basename "$f")" in
            acre2_*.dll)
                acre2_found=1
                ;;
            TFAR_*.dll)
                tfar_found=1
                ;;
        esac
    done
    # shellcheck disable=SC2012
    for f in "$plugins_dir"/*.disabled "$plugins_dir"/../config/plugins/*.disabled; do
        case "$(basename "$f")" in
            TFAR_*.dll.disabled|acre2_*.dll.disabled)
                disabled_found="${disabled_found:+$disabled_found, }$(basename "$f")"
                ;;
        esac
    done

    if [[ "$acre2_found" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     ACRE2 plugin present"
    else
        echo -e "  \e[33m[MISSING]\e[0m ACRE2 plugin"
        echo "    Launch Arma 3 once with the ACRE2 mod active. It"
        echo "    installs its plugin automatically when the mod loads."
        echo "    If that does not work, install it manually with:"
        echo "      ./Arma3Helper.sh acremod"
    fi

    if [[ "$tfar_found" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     TFAR plugin present"
    else
        echo -e "  \e[33m[MISSING]\e[0m TFAR plugin"
        echo "    TFAR does not install its plugin automatically."
        echo "    Install it with:  ./Arma3Helper.sh tfarmod"
    fi

    if [[ -n "$disabled_found" ]]; then
        echo -e "  \e[33m[ISSUE]\e[0m  Plugin disabled after a crash: $disabled_found"
        echo "    TeamSpeak disabled it because it crashed the client once."
        echo "    Re-enable with:  ./Arma3Helper.sh tfarmod --enable"
    fi

    return 0
}

# _install_acre2_plugin
#   Manually install the ACRE2 plugin from the Workshop mod folder.
#   ACRE2 normally installs its plugin automatically when the mod loads,
#   but this can fail if TeamSpeak was installed after the mod first
#   launched, or if the plugin file was removed. This command is the
#   repair path: it copies the DLLs straight from the mod source.
_install_acre2_plugin() {
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        echo -e "\e[31mError\e[0m: TeamSpeak plugins folder not found:"
        echo "  $plugins_dir"
        echo "Install TeamSpeak first:  ./Arma3Helper.sh install"
        return 1
    fi

    # ACRE2 plugin DLLs live in the Workshop mod folder under plugin/.
    local lib_path ws
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        while IFS= read -r ws; do
            [[ -z "$ws" ]] && continue
            local src="$ws/plugin"
            if [[ -f "$src/acre2_win64.dll" || -f "$src/acre2_win32.dll" ]]; then
                local copied=0
                # shellcheck disable=SC2012
                for f in "$src"/acre2_win*.dll; do
                    if [[ -f "$f" ]]; then
                        cp -f "$f" "$plugins_dir/"
                        echo "  Copied: $(basename "$f")"
                        copied=1
                    fi
                done
                if [[ "$copied" == 1 ]]; then
                    echo -e "\e[32mACRE2 plugin installed.\e[0m"
                    echo "Restart TeamSpeak 3 to load it."
                    return 0
                fi
            fi
        done < <(find "$lib_path/steamapps/workshop/content/107410" -maxdepth 1 -type d -iname "*751965892*" 2>/dev/null)
    done < <(_find_steam_libraries)

    echo -e "\e[31mError\e[0m: Could not find the ACRE2 plugin."
    echo "Install the ACRE2 mod from the Steam Workshop first."
    return 1
}

# _check_radio_connection
#   Diagnose why the radio plugins cannot talk to Arma 3. The plugins
#   exchange data with Arma through Windows named pipes, so both processes
#   must run inside the same Wine environment. This check names the exact
#   cause when a plugin reports 'cannot find game instance'.
_check_radio_connection() {
    echo ""
    echo "Checking radio connection to Arma 3..."
    echo ""

    # The pipes only exist while Arma runs, so Arma must be running first.
    if ! pgrep -f "arma3_x64" >/dev/null 2>&1; then
        echo -e "  \e[31m[STOPPED]\e[0m Arma 3 is not running."
        echo "    Start Arma 3 from Steam, wait for the main menu,"
        echo "    then start TeamSpeak 3 with:  ./Arma3Helper.sh"
        return 1
    fi
    echo -e "  \e[32m[OK]\e[0m     Arma 3 is running"

    echo ""
    echo -e "\e[32mThe radio connection path looks correct.\e[0m"
    echo "If radios still do not work, confirm in TeamSpeak that the"
    echo "plugin is enabled (Tools -> Options -> Addons)."
    echo ""

    # Show whether the radio mods are actually in the loaded mod list.
    echo "Loaded radio mods:"
    local mods
    mods="$(_parse_loaded_mods)"
    if [[ -z "$mods" ]]; then
        echo "  (could not read the loaded mod list)"
    else
        local acre2=0 tfar=0 id
        while IFS= read -r id; do
            [[ -z "$id" ]] && continue
            case "$id" in
                751965892) acre2=1 ;;
                894678801|620019431) tfar=1 ;;
            esac
        done <<< "$mods"
        if [[ "$acre2" == 1 ]]; then
            echo -e "  \e[32m[OK]\e[0m     ACRE2 is in the loaded mod list"
        else
            echo -e "  \e[31m[NOT LOADED]\e[0m ACRE2 – enable the ACRE2 mod in your launcher"
        fi
        if [[ "$tfar" == 1 ]]; then
            echo -e "  \e[32m[OK]\e[0m     TFAR is in the loaded mod list"
        else
            echo -e "  \e[33m[NOT LOADED]\e[0m TFAR – enable the TFAR mod if your unit uses it"
        fi
    fi
    return 0
}

# _find_latest_rpt
#   Locate the newest Arma 3 .rpt log file. The game writes these to
#   AppData/Local/Arma 3 inside the prefix. The newest one is the current
#   or most recent session. Its header records the exact launch command,
#   including the loaded mod list.
_find_latest_rpt() {
    local rpt_dir="$COMPAT_DATA_PATH/pfx/drive_c/users/steamuser/AppData/Local/Arma 3"
    # shellcheck disable=SC2012
    ls -t "$rpt_dir"/arma3*.rpt "$rpt_dir"/Arma3*.rpt 2>/dev/null | head -1
}

# _get_arma_cmdline
#   Get the command line of the running Arma 3 process. Prefer the live
#   process via /proc (always current, no log file needed), then fall back
#   to the newest RPT header (survives after Arma exits).
_get_arma_cmdline() {
    # Live process: NUL-separated args, convert to spaces.
    local pid
    pid="$(pgrep -f "arma3_x64" | head -1)"
    if [[ -n "$pid" && -r "/proc/$pid/cmdline" ]]; then
        tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null
        return 0
    fi
    # Fallback: newest RPT header records the launch command.
    local rpt
    rpt="$(_find_latest_rpt)"
    if [[ -n "$rpt" ]]; then
        head -3 "$rpt" | grep -m1 '\-mod=' || true
        return 0
    fi
    return 1
}

# _parse_loaded_mods
#   Extract the loaded mod list from the running Arma process (or the
#   newest RPT header). The launch line carries
#   '-mod=S:\workshop\content\107410\<id>;...'. Prints one workshop id
#   per line.
_parse_loaded_mods() {
    local cmdline
    cmdline="$(_get_arma_cmdline)"
    [[ -z "$cmdline" ]] && return 1
    # The mod list may be Windows-style (S:\workshop\...) or already a
    # host path. Extract everything after -mod= up to the next quote.
    local modlist
    modlist="$(echo "$cmdline" | sed -n 's/.*-mod=\([^"]*\)/\1/p' | sed 's/[; ]*$//')"
    [[ -z "$modlist" ]] && return 1
    # Keep only the workshop content ids: .../content/107410/<id>
    # Paths may be Windows-style (S:\workshop\content\107410\<id>) or
    # host-style (/media/.../steamapps/workshop/content/107410/<id>).
    echo "$modlist" | tr ';' '\n' | sed -n 's#.*[\\/]content[\\/]107410[\\/]##p' | sed '/^$/d'
}

# _mod_name_from_workshop
#   Print the human-readable name for a Workshop mod id from its mod.cpp.
_mod_name_from_workshop() {
    local id="$1" lib_path
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        local mc="$lib_path/steamapps/workshop/content/107410/$id/mod.cpp"
        if [[ -f "$mc" ]]; then
            sed -n 's/^name[[:space:]]*=[[:space:]]*"\(.*\)";/\1/p' "$mc" | head -1
            return 0
        fi
    done < <(_find_steam_libraries)
    return 1
}

# _list_installed_mods
#   List every Workshop mod installed for Arma 3 across all Steam
#   libraries, with human-readable names from mod.cpp.
_list_installed_mods() {
    local lib_path ws found=0
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        while IFS= read -r ws; do
            [[ -z "$ws" ]] && continue
            local id
            id="$(basename "$ws")"
            # Skip the content/107410 root itself; real mod dirs are the
            # Workshop item ids below it.
            [[ "$id" == "107410" ]] && continue
            local name
            name="$(_mod_name_from_workshop "$id")"
            if [[ -n "$name" ]]; then
                printf "  %-12s %s\n" "$id" "$name"
            else
                printf "  %-12s %s\n" "$id" "(no mod.cpp)"
            fi
            found=1
        done < <(find "$lib_path/steamapps/workshop/content/107410" -maxdepth 1 -type d 2>/dev/null | sort)
    done < <(_find_steam_libraries)
    if [[ "$found" == 0 ]]; then
        echo "  (no Workshop mods installed for Arma 3)"
    fi
}

# _list_loaded_mods
#   List the mods loaded in the current (or most recent) Arma session,
#   from the RPT header. Flags ACRE2 and TFAR presence.
_list_loaded_mods() {
    local mods
    mods="$(_parse_loaded_mods)"
    if [[ -z "$mods" ]]; then
        echo "  (no RPT log found – launch Arma 3 first)"
        return 1
    fi
    local count=0 acre2=0 tfar=0
    while IFS= read -r id; do
        [[ -z "$id" ]] && continue
        local name
        name="$(_mod_name_from_workshop "$id")"
        if [[ -z "$name" ]]; then
            name="(local mod or no mod.cpp)"
        fi
        printf "  %-12s %s\n" "$id" "$name"
        count=$((count + 1))
        case "$id" in
            751965892) acre2=1 ;;
            894678801|620019431) tfar=1 ;;
        esac
    done <<< "$mods"
    echo ""
    echo "  Total mods loaded: $count"
    if [[ "$acre2" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     ACRE2 is loaded"
    else
        echo -e "  \e[33m[NOT LOADED]\e[0m ACRE2"
    fi
    if [[ "$tfar" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     TFAR is loaded"
    else
        echo -e "  \e[33m[NOT LOADED]\e[0m TFAR"
    fi
    return 0
}

# _check_radio_chain
#   Verify the full chain for a radio mod: downloaded in Workshop, loaded
#   in the running game, and plugin present in TeamSpeak. Names the exact
#   failing stage so a user knows what to fix.
#   Args: $1 = mod label, $2 = workshop id (first), $3 = plugin glob,
#         $4 = extra workshop ids (space-separated, TFAR older version),
#         $5 = install command suffix (acremod / tfarmod).
_check_radio_chain() {
    local label="$1" wid="$2" plugglob="$3" extra_ids="$4" modcmd="$5"
    local ok=1

    echo ""
    echo "--- $label ---"

    # Stage 1: mod downloaded in Workshop (any Steam library).
    local lib_path ws found=0
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        if [[ -d "$lib_path/steamapps/workshop/content/107410/$wid" ]]; then
            found=1
            break
        fi
    done < <(_find_steam_libraries)
    if [[ "$found" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     Workshop mod downloaded"
    else
        echo -e "  \e[31m[FAIL]\e[0m  Workshop mod not downloaded (id $wid)"
        echo "    Subscribe to it in the Steam Workshop and let it download."
        ok=0
    fi

    # Stage 2: mod in the loaded mod list (live process or RPT).
    local mods id loaded=0
    mods="$(_parse_loaded_mods)"
    if [[ -n "$mods" ]]; then
        while IFS= read -r id; do
            [[ -z "$id" ]] && continue
            if [[ "$id" == "$wid" || " $extra_ids " == *" $id "* ]]; then
                loaded=1
                break
            fi
        done <<< "$mods"
    fi
    if [[ "$loaded" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     Mod loaded in the current game session"
    else
        echo -e "  \e[33m[WARN]\e[0m  Mod not in the loaded list"
        echo "    Enable it in your mod launcher, then restart Arma 3."
        ok=0
    fi

    # Stage 3: plugin DLL present in the prefix TeamSpeak install.
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    local plugin_found=0 disabled=0 f
    if [[ -d "$plugins_dir" ]]; then
        # shellcheck disable=SC2012
        for f in "$plugins_dir"/$plugglob; do
            [[ -f "$f" ]] && plugin_found=1
        done
        # shellcheck disable=SC2012
        for f in "$plugins_dir"/${plugglob}.disabled "$plugins_dir"/../config/plugins/${plugglob}.disabled; do
            [[ -f "$f" ]] && disabled=1
        done
    fi
    if [[ "$plugin_found" == 1 ]]; then
        echo -e "  \e[32m[OK]\e[0m     TeamSpeak plugin installed"
    elif [[ "$disabled" == 1 ]]; then
        echo -e "  \e[31m[FAIL]\e[0m  TeamSpeak plugin disabled after a crash"
        echo "    Re-enable with:  ./Arma3Helper.sh $modcmd --enable"
        ok=0
    else
        echo -e "  \e[31m[FAIL]\e[0m  TeamSpeak plugin not installed"
        echo "    Install with:  ./Arma3Helper.sh $modcmd"
        ok=0
    fi

    return $ok
}

# _verify_radio
#   Verify the complete chain for both radio mods.
_verify_radio() {
    local ok=0
    _check_radio_chain "ACRE2" "751965892" "acre2_win*.dll" "" "acremod" || ok=1
    _check_radio_chain "TFAR" "894678801" "TFAR_*.dll" "620019431" "tfarmod" || ok=1

    echo ""
    if [[ "$ok" == 0 ]]; then
        echo -e "\e[32mAll radio mods are fully installed and loaded.\e[0m"
    else
        echo -e "\e[33mOne or more radio mods need attention.\e[0m"
        echo "Fix the flagged stage above, then re-run:  ./Arma3Helper.sh verifyradio"
    fi
    echo ""
    return 0
}

# _find_tfar_plugin_source
#   Locate the TFAR plugin DLLs on the host. TFAR ships its plugin in the
#   Workshop mod folder (task_force_radio.ts3_plugin, a zip archive) or in
#   a plain 'TeamSpeak 3 Client' folder. Sets _TFAR_SRC_DIR when found.
_find_tfar_plugin_source() {
    local lib_path
    while IFS= read -r lib_path; do
        [[ -z "$lib_path" ]] && continue
        # Workshop mod folder: steamapps/workshop/content/107410/<tfar_id>
        local ws
        while IFS= read -r ws; do
            [[ -z "$ws" ]] && continue
            local plugin_zip="$ws/task_force_radio.ts3_plugin"
            local plugin_dir="$ws/TeamSpeak 3 Client"
            if [[ -f "$plugin_zip" ]]; then
                _TFAR_SRC_ZIP="$plugin_zip"
                _TFAR_SRC_DIR=""
                return 0
            elif [[ -d "$plugin_dir" ]]; then
                _TFAR_SRC_DIR="$plugin_dir"
                _TFAR_SRC_ZIP=""
                return 0
            fi
        done < <(find "$lib_path/steamapps/workshop/content/107410" -maxdepth 1 -type d 2>/dev/null)
    done < <(_find_steam_libraries)
    return 1
}

# _install_tfar_plugin
#   Copy the TFAR plugin into the prefix TeamSpeak plugins folder.
#   Also re-enables any plugin TeamSpeak disabled after a crash (the
#   '.disabled' crash-protection suffix).
_install_tfar_plugin() {
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        echo -e "\e[31mError\e[0m: TeamSpeak plugins folder not found:"
        echo "  $plugins_dir"
        echo "Install TeamSpeak first:  ./Arma3Helper.sh install"
        return 1
    fi

    _TFAR_SRC_ZIP=""
    _TFAR_SRC_DIR=""
    if ! _find_tfar_plugin_source; then
        echo -e "\e[31mError\e[0m: Could not find the TFAR plugin."
        echo "Install the Task Force Radio mod from the Steam Workshop first."
        return 1
    fi

    local tmpdir=""
    if [[ -n "$_TFAR_SRC_ZIP" ]]; then
        # .ts3plugin is a zip archive with a plugins/ subfolder.
        echo "Extracting TFAR plugin from Workshop package..."
        _checkinstall unzip || return 1
        tmpdir="$(mktemp -d)"
        if ! unzip -oq "$_TFAR_SRC_ZIP" -d "$tmpdir" 2>/dev/null; then
            echo -e "\e[31mError\e[0m: Could not extract the TFAR plugin package."
            rm -rf "$tmpdir"
            return 1
        fi
        _TFAR_SRC_DIR="$tmpdir"
    fi

    local copied=0
    # shellcheck disable=SC2012
    for f in "$_TFAR_SRC_DIR"/plugins/TFAR_*.dll "$_TFAR_SRC_DIR"/plugins/task_force_radio*.dll; do
        if [[ -f "$f" ]]; then
            cp -f "$f" "$plugins_dir/"
            echo "  Copied: $(basename "$f")"
            copied=1
        fi
    done
    [[ -n "$tmpdir" ]] && rm -rf "$tmpdir"

    if [[ "$copied" == 0 ]]; then
        echo -e "\e[31mError\e[0m: No TFAR plugin DLL found in: $_TFAR_SRC_ZIP$_TFAR_SRC_DIR"
        return 1
    fi

    echo -e "\e[32mTFAR plugin installed.\e[0m"
    echo "Restart TeamSpeak 3 to load it."
    return 0
}

# _enable_tfar_plugin
#   Re-enable TFAR plugins that TeamSpeak disabled after a crash
#   (the '.disabled' suffix). Rename them back to .dll.
_enable_tfar_plugin() {
    local plugins_dir="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/plugins"
    if [[ ! -d "$plugins_dir" ]]; then
        echo -e "\e[31mError\e[0m: TeamSpeak plugins folder not found:"
        echo "  $plugins_dir"
        return 1
    fi

    local found=0
    local cfg_plugins="$plugins_dir/../config/plugins"
    # shellcheck disable=SC2012
    for f in "$plugins_dir"/TFAR_*.dll.disabled "$plugins_dir"/acre2_*.dll.disabled \
             "$cfg_plugins"/TFAR_*.dll.disabled "$cfg_plugins"/acre2_*.dll.disabled; do
        if [[ -f "$f" ]]; then
            local target="${f%.disabled}"
            mv -f "$f" "$target"
            echo "  Re-enabled: $(basename "$target")"
            found=1
        fi
    done

    if [[ "$found" == 1 ]]; then
        echo -e "\e[32mPlugin re-enabled. Restart TeamSpeak 3 to load it.\e[0m"
    else
        echo "No disabled radio plugins found."
    fi
    return 0
}

# _get_wrappercmd
#   Determine which tool to use to install DLLs into the Wine prefix:
#   winetricks or protontricks. protontricks is checked first as it handles
#   the prefix environment more reliably when both are installed.
#   Sets the global _WRAPPER array: _WRAPPER[0] = command, _WRAPPER[1..] = args.
_get_wrappercmd() {
    local has_pt has_wt
    has_pt=$(command -v protontricks 2>/dev/null)
    has_wt=$(command -v winetricks 2>/dev/null)

    if [[ -n "$has_pt" ]]; then
        # protontricks takes the Steam App ID as its first argument
        _WRAPPER=(protontricks 107410)
    elif [[ -n "$has_wt" ]]; then
        _WRAPPER=(winetricks)
    else
        echo -e "\e[31mError\e[0m: Neither winetricks nor protontricks is installed."
        echo "Install one of them and try again. Run './Arma3Helper.sh checkdeps' for details."
        return 1
    fi
}

# _download_ts3
#   Download the latest TeamSpeak 3 Windows x64 installer and verify it.
#   Discovery + checksum come from the official version endpoint that winget
#   and the downloads page use. Returns the installer path in _TS3_INSTALLER.
#   Falls back to a manual-download message when the CDN challenge-blocks us.
_download_ts3() {
    _checkinstall curl || return 1
    _checkinstall python3 || return 1

    echo ""
    echo "Fetching latest TeamSpeak 3 version information..."
    local meta
    meta=$(curl -fs --max-time 10 "https://www.teamspeak.com/versions/client.json" 2>/dev/null) || {
        echo -e "\e[31mError\e[0m: Could not reach the TeamSpeak version server."
        return 1
    }

    local ver checksum url
    ver=$(echo "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['windows']['x86_64']['version'])" 2>/dev/null)
    checksum=$(echo "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['windows']['x86_64']['checksum'])" 2>/dev/null)
    url=$(echo "$meta" | python3 -c "import json,sys; print(json.load(sys.stdin)['windows']['x86_64']['mirrors']['teamspeak.com'])" 2>/dev/null)

    if [[ -z "$ver" || -z "$checksum" || -z "$url" ]]; then
        echo -e "\e[31mError\e[0m: Could not parse the TeamSpeak version information."
        echo "Download the Windows 64-bit installer manually from:"
        echo "  https://www.teamspeak.com/en/downloads/"
        return 1
    fi

    local dest="$USERCONFIG/TeamSpeak3-Client-win64-$ver.exe"
    echo "Latest version: $ver"
    echo "Downloading from: $url"
    echo ""
    if ! curl -fL --max-time 300 -o "$dest" "$url"; then
        echo -e "\e[31mError\e[0m: Download failed."
        echo "The TeamSpeak download server may block automated downloads."
        echo "Download the Windows 64-bit installer manually from:"
        echo "  https://www.teamspeak.com/en/downloads/"
        echo "Then run:  ./Arma3Helper.sh install /path/to/TeamSpeak3-Client-win64-$ver.exe"
        rm -f "$dest"
        return 1
    fi

    echo ""
    echo "Verifying download..."
    if ! echo "$checksum  $dest" | sha256sum -c - >/dev/null 2>&1; then
        echo -e "\e[31mError\e[0m: Checksum mismatch. Download may be corrupt."
        rm -f "$dest"
        return 1
    fi
    echo -e "\e[32mChecksum verified.\e[0m"
    _TS3_INSTALLER="$dest"
    return 0
}

###############################################################################
## RESOLVE PATHS
###############################################################################

# Determine the Steam root directory
_STEAM_ROOT="$(_find_steam_root)"

# -----------------------------------------------------------------------------
# Resolve COMPAT_DATA_PATH (Arma's Wine prefix)
# -----------------------------------------------------------------------------
# _is_info_command <cmd> [subcmd]
#   Return 0 if the command is informational or self-help: it must work on
#   a fresh machine with no Steam, no Proton, and no prefix. These commands
#   should not emit detection warnings that assume an installed game.
_is_info_command() {
    # 'prefix doctor' is read-only diagnostics and needs no Proton.
    if [[ "$1" == "prefix" && "$2" == "doctor" ]]; then
        return 0
    fi
    case "$1" in
        help|""|checkdeps|listproton|debug|update|createconfig|listmods| \
        tfarmod|acremod|acrecheck|verifyradio|winetricks|winecfg)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
if [[ -z "$COMPAT_DATA_PATH" ]]; then
    # Auto-detect by searching all configured Steam libraries
    _ARMA_LIB="$(_find_arma_library)"
    if [[ -n "$_ARMA_LIB" ]]; then
        COMPAT_DATA_PATH="$_ARMA_LIB/compatdata/107410"
        echo "Auto-detected Arma 3 in: $_ARMA_LIB"
    else
        # Fallback to the traditional default location
        COMPAT_DATA_PATH="$HOME/.steam/steam/steamapps/compatdata/107410"
        if ! _is_info_command "$1" "$2"; then
            echo -e "\e[33mWarning\e[0m: Could not auto-detect Arma 3 library."
            echo "Falling back to: $COMPAT_DATA_PATH"
            echo "If this is wrong, set COMPAT_DATA_PATH in the config file."
            echo "Run './Arma3Helper.sh createconfig' to create the config file."
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Resolve STEAM_LIBRARY_PATH (for finding Proton)
# -----------------------------------------------------------------------------
if [[ -z "$STEAM_LIBRARY_PATH" ]]; then
    STEAM_LIBRARY_PATH="$_STEAM_ROOT/steamapps"
fi

# Export the environment variables that Wine/Proton need to run correctly.
# These tell Proton where to find Arma's Wine prefix and the Steam client.
export STEAM_COMPAT_DATA_PATH="$COMPAT_DATA_PATH"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$_STEAM_ROOT"

# Proton builds with the gamedrive option enabled (for example Proton Hotfix)
# need STEAM_COMPAT_INSTALL_PATH and STEAM_COMPAT_LIBRARY_PATHS to resolve the
# game's Steam library during 'proton run'. When they are missing, Proton
# deletes the S: drive mapping from the live prefix. A running Arma then fails
# server signature checks on every S:-pathed file, which causes random
# "Wrong signature for file" kicks while TeamSpeak is open.
# The compatdata folder always lives in the same Steam library as the game,
# so derive both from COMPAT_DATA_PATH. Only export them when the derived
# library actually contains the game, so a wrong COMPAT_DATA_PATH can never
# point Proton at a wrong library.
if [[ -z "$STEAM_COMPAT_INSTALL_PATH" && -z "$STEAM_COMPAT_LIBRARY_PATHS" ]]; then
    _ARMA_LIBRARY="$(readlink -f "$COMPAT_DATA_PATH" 2>/dev/null)"
    _ARMA_LIBRARY="${_ARMA_LIBRARY%/compatdata/*}"
    if [[ -d "$_ARMA_LIBRARY/common/Arma 3" ]]; then
        export STEAM_COMPAT_INSTALL_PATH="$_ARMA_LIBRARY/common/Arma 3"
        export STEAM_COMPAT_LIBRARY_PATHS="$_ARMA_LIBRARY"
    elif ! _is_info_command "$1" "$2"; then
        echo -e "\e[33mWarning\e[0m: Could not locate Arma's Steam library from COMPAT_DATA_PATH."
        echo "Without STEAM_COMPAT_INSTALL_PATH and STEAM_COMPAT_LIBRARY_PATHS, newer Proton versions remove the prefix's S: drive, which breaks server signature checks. Export both in your config file."
    fi
fi
export SteamAppId="107410"
export SteamGameId="107410"

# Apply Esync/Fsync preferences.
# Esync and Fsync improve performance by reducing kernel overhead for Wine.
# They must match whatever Arma 3 is set to use in Steam.
if [[ "$ESYNC" == "false" ]]; then
    export PROTON_NO_ESYNC="1"
fi
if [[ "$FSYNC" == "false" ]]; then
    export PROTON_NO_FSYNC="1"
fi

# TeamSpeak 3 executable path inside the Wine prefix.
# This path is correct when TS3 was installed using 'Install for All Users'
# with the default path (C:\Program Files\TeamSpeak 3 Client).
# If TS3 ends up in AppData instead, see the 'install' command instructions.
TSPATH="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe"

# -----------------------------------------------------------------------------
# Resolve Proton version string
# -----------------------------------------------------------------------------
# Normalize the version string by removing any user-provided 'Proton ' prefix
PROTON_OFFICIAL_VERSION="${PROTON_OFFICIAL_VERSION#Proton }"

if [[ "$PROTON_OFFICIAL_VERSION" == "Proton Experimental" || \
      "$PROTON_OFFICIAL_VERSION" == "Experimental" ]]; then
    PROTON_OFFICIAL_VERSION="- Experimental"
    IS_EXPERIMENTAL=true
elif [[ -z "$PROTON_OFFICIAL_VERSION" && -z "$PROTON_CUSTOM_VERSION" ]]; then
    # Auto-detect from the prefix: read the version file that records which
    # Proton created Arma 3's Wine prefix, then match it to an installed build.
    _prefix_version_file="$COMPAT_DATA_PATH/version"
    _prefix_version=""
    if [[ -f "$_prefix_version_file" ]]; then
        _prefix_version="$(cat "$_prefix_version_file")"
    fi

    if [[ -n "$_prefix_version" ]]; then
        # Match the prefix version to an installed Proton directory.
        # Strategy: (1) substring match on directory name, (2) extract and
        # compare numeric version parts, (3) check the proton directory's own
        # version file.  Covers both official ("Proton 11.0-2") and custom
        # ("Proton-CachyOS Latest") naming conventions.
        _match_dir=""
        _match_is_custom=false

        while IFS= read -r lib_path; do
            [[ -n "$_match_dir" ]] && break

            # Check steamapps/common (official Proton)
            _sa="$lib_path/steamapps"
            if [[ -d "$_sa/common" ]]; then
                while IFS= read -r _dir; do
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
                    # Strip known prefixes, extract X.Y or X.Y.Z
                    _norm="${_ver// /-}"  # normalize spaces to hyphens
                    _norm="${_norm#Proton}"
                    _norm="${_norm#-}"
                    if [[ "$_norm" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                        _dir_num="${BASH_REMATCH[1]}"
                        _pv="${_prefix_version// /-}"
                        _pv="${_pv#Proton}"
                        _pv="${_pv#-}"
                        if [[ "$_pv" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                            _pv_num="${BASH_REMATCH[1]}"
                            if [[ "$_pv_num" == "$_dir_num" ]]; then
                                _match_dir="$_dir"
                                break
                            fi
                        fi
                    fi
                    # Strategy 3: check the proton directory's own version file
                    if [[ -f "$_dir/version" ]]; then
                        _dir_ver="$(cat "$_dir/version")"
                        # Try direct substring first
                        if [[ "$_dir_ver" == *"$_prefix_version"* ]]; then
                            _match_dir="$_dir"
                            break
                        fi
                        # Try extracting version numbers from the version file
                        if [[ -n "$_pv_num" ]]; then
                            _fv="${_dir_ver// /-}"
                            _fv="${_fv#Proton}"
                            _fv="${_fv#-}"
                            if [[ "$_fv" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                                _fv_num="${BASH_REMATCH[1]}"
                                if [[ "$_pv_num" == "$_fv_num" ]]; then
                                    _match_dir="$_dir"
                                    break
                                fi
                            fi
                        fi
                    fi
                done < <(find "$_sa/common" -maxdepth 1 -type d -name "Proton*")
            fi

            # Check compatibilitytools.d (custom Proton builds)
            if [[ -z "$_match_dir" && -d "$lib_path/compatibilitytools.d" ]]; then
                while IFS= read -r _dir; do
                    _ver="$(basename "$_dir")"
                    [[ -f "$_dir/proton" ]] || continue
                    # Skip non-game runtimes
                    [[ "$_ver" == *"Runtime"* || "$_ver" == *"BattlEye"* || \
                       "$_ver" == *"Hotfix"* || "$_ver" == *"Experimental"* ]] && continue
                    # Strategy 1: direct substring
                    if [[ "$_ver" == *"$_prefix_version"* ]]; then
                        _match_dir="$_dir"
                        _match_is_custom=true
                        break
                    fi
                    # Strategy 2: compare extracted version numbers
                    _norm="${_ver// /-}"
                    _norm="${_norm#Proton}"
                    _norm="${_norm#-}"
                    if [[ "$_norm" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                        _dir_num="${BASH_REMATCH[1]}"
                        _pv="${_prefix_version// /-}"
                        _pv="${_pv#Proton}"
                        _pv="${_pv#-}"
                        if [[ "$_pv" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                            _pv_num="${BASH_REMATCH[1]}"
                            if [[ "$_pv_num" == "$_dir_num" ]]; then
                                _match_dir="$_dir"
                                _match_is_custom=true
                                break
                            fi
                        fi
                    fi
                    # Strategy 3: check the proton directory's own version file
                    if [[ -f "$_dir/version" ]]; then
                        _dir_ver="$(cat "$_dir/version")"
                        # Try direct substring first
                        if [[ "$_dir_ver" == *"$_prefix_version"* ]]; then
                            _match_dir="$_dir"
                            _match_is_custom=true
                            break
                        fi
                        # Try extracting version numbers from the version file
                        if [[ -n "$_pv_num" ]]; then
                            _fv="${_dir_ver// /-}"
                            _fv="${_fv#Proton}"
                            _fv="${_fv#-}"
                            if [[ "$_fv" =~ ([0-9]+\.[0-9]+(\.[0-9]+)?) ]]; then
                                _fv_num="${BASH_REMATCH[1]}"
                                if [[ "$_pv_num" == "$_fv_num" ]]; then
                                    _match_dir="$_dir"
                                    _match_is_custom=true
                                    break
                                fi
                            fi
                        fi
                    fi
                done < <(find "$lib_path/compatibilitytools.d" -maxdepth 1 -type d -name "*Proton*")
            fi
        done < <(_find_steam_libraries)

        if [[ -n "$_match_dir" ]]; then
            if [[ "$_match_is_custom" == true ]]; then
                PROTONEXEC="$_match_dir/proton"
            else
                _ver="$(basename "$_match_dir")"
                PROTON_OFFICIAL_VERSION="${_ver#Proton }"
            fi
        fi
    fi

    # Fallback: pick the highest installed version if prefix matching failed.
    # Only when a real Proton exists. If nothing is installed, leave the
    # version empty: fabricating one here would lie to the user, and would
    # make the setup wizard think the config is not default.
    if [[ -z "$PROTON_OFFICIAL_VERSION" && -z "$PROTONEXEC" ]]; then
        _best_proton=""
        while IFS= read -r lib_path; do
            _sa="$lib_path/steamapps"
            if [[ -d "$_sa/common" ]]; then
                while IFS= read -r _dir; do
                    _ver="$(basename "$_dir")"
                    if [[ -f "$_dir/proton" ]] && \
                       [[ "$_ver" == *"Proton "* ]] && \
                       [[ "$_ver" != *"Runtime"* ]] && \
                       [[ "$_ver" != *"BattlEye"* ]] && \
                       [[ "$_ver" != *"Hotfix"* ]] && \
                       [[ "$_ver" != *"-"* ]]; then
                        _num="${_ver#Proton }"
                        _best_proton="$(printf '%s\n' "$_num" "$_best_proton" | sort -V | tail -1)"
                    fi
                done < <(find "$_sa/common" -maxdepth 1 -type d -name "Proton*")
            fi
        done < <(_find_steam_libraries)
        if [[ -n "$_best_proton" ]]; then
            PROTON_OFFICIAL_VERSION="$_best_proton"
        fi
    fi
fi

# -----------------------------------------------------------------------------
# Resolve Proton executable path
# -----------------------------------------------------------------------------
if [[ -n "$PROTON_CUSTOM_VERSION" ]]; then
    # Custom Proton build (for example GE-Proton, Proton-TKG)
    if [[ -x "$PROTON_CUSTOM_VERSION" ]]; then
        # Absolute path to the proton binary was provided
        PROTONEXEC="$PROTON_CUSTOM_VERSION"
    else
        # Search all libraries for the custom build folder
        PROTONEXEC=""
        while IFS= read -r lib_path; do
            _candidate="$lib_path/compatibilitytools.d/$PROTON_CUSTOM_VERSION/proton"
            if [[ -x "$_candidate" ]]; then
                PROTONEXEC="$_candidate"
                break
            fi
        done < <(_find_steam_libraries)
        # No blind fallback — only set PROTONEXEC if we actually found a working binary.
    fi
else
    # Official Proton: search all Steam libraries for the matching version.
    PROTONEXEC=""
    while IFS= read -r lib_path; do
        # Use a wildcard search to handle variations like 'Proton 9.0 (Beta)'
        for _cand_dir in "$lib_path/steamapps/common/Proton $PROTON_OFFICIAL_VERSION"*; do
            # Filter out non-Proton runtimes that might match the wildcard
            if [[ "$_cand_dir" == *"Runtime"* || "$_cand_dir" == *"Hotfix"* ]]; then
                continue
            fi
            if [[ -x "$_cand_dir/proton" ]]; then
                PROTONEXEC="$_cand_dir/proton"
                break 2
            fi
        done
    done < <(_find_steam_libraries)

    # Fallback: glob may miss directories with unusual naming.  Use find
    # (same approach as listproton) to catch anything the glob missed.
    if [[ -z "$PROTONEXEC" ]]; then
        while IFS= read -r lib_path; do
            _sa="$lib_path/steamapps"
            if [[ -d "$_sa/common" ]]; then
                while IFS= read -r _dir; do
                    _ver="$(basename "$_dir")"
                    if [[ -f "$_dir/proton" ]] && \
                       [[ "$_ver" == *"Proton $PROTON_OFFICIAL_VERSION"* ]] && \
                       [[ "$_ver" != *"Runtime"* ]] && \
                       [[ "$_ver" != *"BattlEye"* ]]; then
                        PROTONEXEC="$_dir/proton"
                        break 2
                    fi
                done < <(find "$_sa/common" -maxdepth 1 -type d -name "Proton*")
            fi
        done < <(_find_steam_libraries)
    fi
fi

# Bail out early if we could not find any Proton executable.
# Informational and self-help commands must still work without Proton:
# a new user without Steam needs help, checkdeps, and listproton more
# than anything. Only commands that actually run Proton or need a
# working prefix require it.
if ! _is_info_command "$1" "$2" && { [[ -z "$PROTONEXEC" || ! -x "$PROTONEXEC" ]]; }; then
    echo "Error: No Proton executable found."
    if [[ -n "$PROTON_CUSTOM_VERSION" ]]; then
        echo "  Custom version:  $PROTON_CUSTOM_VERSION"
        echo "  Ensure this version is installed in compatibilitytools.d."
    elif [[ -n "$PROTON_OFFICIAL_VERSION" ]]; then
        echo "  Searched for:  Proton $PROTON_OFFICIAL_VERSION"
    else
        echo "  No Proton version was found on this system."
    fi
    echo "  Ensure Proton is installed in your Steam library."
    echo "  Run './Arma3Helper.sh listproton' to see what is available."
    echo "  Set PROTON_OFFICIAL_VERSION or PROTON_CUSTOM_VERSION in your config."
    exit 1
fi

# -----------------------------------------------------------------------------
# PREFIX PROTECTION
# -----------------------------------------------------------------------------
# Check if the prefix version matches the configured Proton version.
# Must run after COMPAT_DATA_PATH and PROTON_OFFICIAL_VERSION are resolved.
_check_prefix_version() {
    local version_file="$COMPAT_DATA_PATH/version"
    if [[ -f "$version_file" ]]; then
        local stored_version
        stored_version=$(cat "$version_file")
        if [[ -n "$PROTON_OFFICIAL_VERSION" && "$stored_version" != *"$PROTON_OFFICIAL_VERSION"* ]]; then
            echo -e "\e[33mWarning\e[0m: Proton version mismatch!"
            echo "Configured: $PROTON_OFFICIAL_VERSION"
            echo "Prefix set to: $stored_version"
            echo "Changing Proton versions can cause audio or plugin issues."
            _confirmation "Do you want to continue anyway?"
        fi
    fi
}

# -----------------------------------------------------------------------------
# PREFIX DOCTOR
# -----------------------------------------------------------------------------
# Read-only health check for Arma's Wine prefix. Prints the key marker files,
# checks the Windows system directory, and reports mount options. Exits 0 when
# the prefix looks healthy, 1 when a check fails.
_prefix_doctor() {
    local pfx="$COMPAT_DATA_PATH/pfx"
    local issues=0

    echo ""
    echo "================================================================"
    echo " Prefix Doctor – $COMPAT_DATA_PATH"
    echo "================================================================"
    echo ""

    echo "--- Marker files ---"
    if [[ -f "$COMPAT_DATA_PATH/version" ]]; then
        echo "version file:             $(cat "$COMPAT_DATA_PATH/version")"
    else
        echo -e "\e[31mMISSING\e[0m version file. Prefix was never created."
        ((issues++))
    fi
    if [[ -f "$COMPAT_DATA_PATH/config_info" ]]; then
        echo "config_info:              present"
    else
        echo -e "\e[33mWARN\e[0m config_info missing. Proton may rebuild on next launch."
    fi

    echo ""
    echo "--- Windows system directory ---"
    local sys32="$pfx/drive_c/windows/system32"
    if [[ -d "$sys32" ]]; then
        local kernel32 wineboot
        kernel32=$(test -f "$sys32/kernel32.dll" && echo present || echo MISSING)
        wineboot=$(test -f "$sys32/wineboot.exe" && echo present || echo MISSING)
        echo "system32:                 exists"
        echo "kernel32.dll:             $kernel32"
        echo "wineboot.exe:             $wineboot"
        [[ "$kernel32" == "MISSING" ]] && ((issues++))
        [[ "$wineboot" == "MISSING" ]] && ((issues++))
    else
        echo -e "\e[31mMISSING\e[0m system32 directory. Prefix is corrupt."
        ((issues++))
    fi

    echo ""
    echo "--- Drive mappings (dosdevices) ---"
    if [[ -d "$pfx/dosdevices" ]]; then
        local drive
        for drive in "$pfx/dosdevices"/[a-z]:; do
            [[ -e "$drive" ]] && echo "  $(basename "$drive")"
        done
        # c: must exist and be a real directory or symlink
        if [[ -e "$pfx/dosdevices/c:" ]]; then
            echo "c: drive:                 mapped"
        else
            echo -e "\e[31mMISSING\e[0m c: drive mapping"
            ((issues++))
        fi
    else
        echo -e "\e[31mMISSING\e[0m dosdevices directory"
        ((issues++))
    fi

    echo ""
    echo "--- Prefix creation state ---"
    if [[ -f "$pfx/creation_sync_guard" ]]; then
        echo "creation_sync_guard:      present"
        echo "                          Not necessarily an error. Some Proton"
        echo "                          builds (e.g. CachyOS) leave this file in"
        echo "                          place on healthy prefixes. Only treat it"
        echo "                          as a problem if other checks also fail."
    else
        echo "creation_sync_guard:      absent"
    fi

    echo ""
    echo "--- Wineserver ---"
    if pgrep -x wineserver &>/dev/null; then
        echo "wineserver:               running"
    else
        echo "wineserver:               not running"
    fi

    echo ""
    echo "--- Filesystem mount ---"
    local mount_point
    mount_point=$(df -P "$COMPAT_DATA_PATH" 2>/dev/null | awk 'NR==2 {print $6}')
    if [[ -n "$mount_point" ]]; then
        local opts
        opts=$(mount | awk -v mp="$mount_point" '$3 == mp {print $6}' | tr -d '()')
        echo "mount point:              $mount_point"
        echo "mount options:            ${opts:-unknown}"
        if [[ "$opts" == *noexec* ]]; then
            echo -e "\e[31mFAIL\e[0m mounted noexec. Proton cannot run here."
            ((issues++))
        elif [[ "$opts" == *nosuid* || "$opts" == *nodev* ]]; then
            echo -e "\e[33mWARN\e[0m restricted mount options (nosuid/nodev)."
        fi
        case "$opts" in
            *ntfs*|*fuseblk*) echo -e "\e[33mWARN\e[0m NTFS/fuseblk filesystem. Symlinks and exec may be limited." ;;
        esac
    fi

    echo ""
    if (( issues > 0 )); then
        echo -e "\e[31mVerdict: $issues issue(s) found.\e[0m"
        echo "Try './Arma3Helper.sh prefix reset' to repair in place."
        exit 1
    else
        echo -e "\e[32mVerdict: prefix looks healthy.\e[0m"
        exit 0
    fi
}

# -----------------------------------------------------------------------------
# PREFIX RESET
# -----------------------------------------------------------------------------
# Two modes:
#   inplace – Proton's destroyprefix removes only the tracked Wine system
#             files; the next Arma launch re-copies them. User data in
#             drive_c (Documents, AppData, Program Files) is preserved.
#   full    – move the whole compatdata aside and let Proton recreate it.
#             Arma 3 has no Steam Cloud, so all user data is backed up first:
#             profiles, loadouts, missions, TS3 config, TS3 install, plugins.
_prefix_reset() {
    local mode="$1"
    local pfx="$COMPAT_DATA_PATH/pfx"
    local backup_dir

    if [[ ! -d "$pfx" ]]; then
        echo -e "\e[31mError\e[0m: No prefix found at $pfx"
        echo "Launch Arma 3 once from Steam to create it."
        exit 1
    fi

    echo ""
    echo "================================================================"
    if [[ "$mode" == "full" ]]; then
        echo " Prefix Reset (full) – recreate prefix"
    else
        echo " Prefix Reset (in-place) – repair Wine system files"
    fi
    echo "================================================================"
    echo ""
    echo "Arma 3 stores profiles, loadouts, missions, and settings in"
    echo "Documents INSIDE the prefix. There is no Steam Cloud for Arma 3."
    echo ""

    if [[ "$mode" == "full" ]]; then
        echo "This will back up your user data, then move the whole prefix aside."
        echo "A fresh prefix is created on your next Arma 3 launch."
    else
        echo "This removes Proton's system files and rebuilds them in place."
        echo "Your Documents, AppData, and Program Files data is preserved."
    fi
    echo ""
    _confirmation "Continue?"

    # Stop any running Wine processes so the prefix is not in use.
    if [[ -n "$PROTONEXEC" && -x "$PROTONEXEC" ]]; then
        echo "Stopping wineserver..."
        "$PROTONEXEC" run wineserver -k 2>/dev/null
        sleep 1
    fi

    if [[ "$mode" == "full" ]]; then
        # ---- FULL RESET: back up user data, then move compatdata aside ----
        backup_dir="$HOME/Arma3Helper-prefix-backup-$(date +%Y%m%d-%H%M%S)"
        mkdir -p "$backup_dir"
        local userhome="$pfx/drive_c/users/steamuser"

        # Documents/Arma 3 – the default profile: loadouts, missions, saves,
        # settings, screenshots. Arma 3 has no Steam Cloud, so this is the
        # only copy that exists.
        if [[ -d "$userhome/Documents/Arma 3" ]]; then
            cp -a "$userhome/Documents/Arma 3" "$backup_dir/"
            echo "Backed up default profile:   $backup_dir/Arma 3"
        else
            echo "No default Arma 3 profile found."
        fi

        # Documents/Arma 3 - Other Profiles – one folder per custom profile.
        # Named profiles live here, not in the default folder.
        if [[ -d "$userhome/Documents/Arma 3 - Other Profiles" ]]; then
            cp -a "$userhome/Documents/Arma 3 - Other Profiles" "$backup_dir/"
            echo "Backed up custom profiles:   $backup_dir/Arma 3 - Other Profiles"
        else
            echo "No custom profiles found."
        fi

        # AppData/Local/Arma 3 Launcher/Presets – mod preset files. Small and
        # high value; rebuilding a modlist by hand is painful.
        if [[ -d "$userhome/AppData/Local/Arma 3 Launcher/Presets" ]]; then
            cp -a "$userhome/AppData/Local/Arma 3 Launcher/Presets" "$backup_dir/"
            echo "Backed up mod presets:       $backup_dir/Presets"
        fi

        # TS3 config (Roaming) – identity, settings, bookmarks, plugins
        if [[ -d "$userhome/AppData/Roaming/TS3Client" ]]; then
            cp -a "$userhome/AppData/Roaming/TS3Client" "$backup_dir/"
            echo "Backed up TS3 config:        $backup_dir/TS3Client"
        fi

        # TS3 install (Program Files) – the all-users install location
        if [[ -d "$pfx/drive_c/Program Files/TeamSpeak 3 Client" ]]; then
            cp -a "$pfx/drive_c/Program Files/TeamSpeak 3 Client" "$backup_dir/"
            echo "Backed up TS3 install:       $backup_dir/TeamSpeak 3 Client"
        fi

        # Move the whole compatdata aside (delete = data loss, move = recoverable)
        mv "$COMPAT_DATA_PATH" "${COMPAT_DATA_PATH}.old-$(date +%Y%m%d-%H%M%S)"
        echo ""
        echo -e "\e[32mPrefix moved aside. Backup saved to:\e[0m"
        echo "  $backup_dir"
        echo ""
        echo "Next steps:"
        echo "  1. Launch Arma 3 from Steam once – Proton creates a fresh prefix."
        echo "  2. Run './Arma3Helper.sh bindhost' if you use host Documents."
        echo "  3. Run './Arma3Helper.sh winetricks Arma' to reinstall DLLs."
        echo "  4. Restore your data from the backup if needed."
        echo "  5. If everything works, delete the .old-* prefix folder."
    else
        # ---- IN-PLACE RESET: Proton's own tracked-file removal ----
        echo "Running Proton's destroyprefix (removes tracked Wine system files)..."
        if "$PROTONEXEC" destroyprefix 2>/dev/null; then
            echo "destroyprefix complete."
        else
            echo -e "\e[33mWARN\e[0m destroyprefix reported a non-zero exit. Continuing anyway."
        fi

        # Remove the creation guard so Proton re-copies the system files on
        # the next launch instead of treating the prefix as already created.
        if [[ -f "$pfx/creation_sync_guard" ]]; then
            rm -f "$pfx/creation_sync_guard"
            echo "Removed creation_sync_guard."
        fi

        echo ""
        echo -e "\e[32mIn-place reset complete.\e[0m"
        echo "Your Documents, AppData, and Program Files data is preserved."
        echo ""
        echo "Next steps:"
        echo "  1. Launch Arma 3 from Steam once – Proton rebuilds the system files."
        echo "  2. Re-run './Arma3Helper.sh winetricks Arma' if audio/visuals break."
        echo "  3. Reinstall TeamSpeak 3 only if it no longer launches."
    fi
}

# -----------------------------------------------------------------------------
# BIND HOST DIRECTORIES
# -----------------------------------------------------------------------------
# Point the prefix's Documents and Downloads shell folders at the real host
# folders, using Wine's registry (no symlinks, no Steam-side changes).
#
# Why this works:
#   - Proton maps the prefix's Z: drive to the container root (always present).
#   - pressure-vessel bind-mounts the host /home at the same path inside the
#     container. So Z:\home\<user>\Documents IS the host ~/Documents.
#   - Wine's SHGetFolderPath(CSIDL_PERSONAL) and SHGetKnownFolderPath
#     (FOLDERID_Documents) both read the "Personal" value in User Shell
#     Folders. One registry write covers both APIs Arma 3 uses.
#
# Result: Arma 3 reads and writes profiles, loadouts, missions, and modlists
# on the HOST filesystem. Deleting the prefix no longer destroys them. A
# fresh prefix picks them up immediately after bindhost is re-applied.
#
# The registry write runs inside the prefix via Proton, so it does not need
# WINEPREFIX or a running game. It sets:
#   Personal   -> Z:\home\<user>\Documents
#   Downloads  -> Z:\home\<user>\Downloads
#   the FOLDERID_Documents GUID  ({FDD39AD0-238F-46AF-ADB4-6C85480369C7})
#   the FOLDERID_Downloads GUID  ({374DE290-123F-4565-9164-39C4925E467B})
_bind_host_dirs() {
    if [[ -z "$PROTONEXEC" || ! -x "$PROTONEXEC" ]]; then
        echo -e "\e[31mError\e[0m: No Proton executable found. Cannot edit the prefix registry."
        exit 1
    fi
    if [[ ! -d "$COMPAT_DATA_PATH/pfx" ]]; then
        echo -e "\e[31mError\e[0m: No prefix found at $COMPAT_DATA_PATH/pfx"
        echo "Launch Arma 3 once from Steam to create it."
        exit 1
    fi

    local host_docs host_dl
    host_docs="Z:\\\\home\\\\$(whoami)\\\\Documents"
    host_dl="Z:\\\\home\\\\$(whoami)\\\\Downloads"

    echo ""
    echo "================================================================"
    echo " Bind Host Directories"
    echo "================================================================"
    echo ""
    echo "This makes Arma 3 use your REAL host folders:"
    echo "  Documents -> $HOME/Documents"
    echo "  Downloads -> $HOME/Downloads"
    echo ""
    echo "Your profiles, loadouts, missions, and settings then live on the"
    echo "host. Deleting the Wine prefix will NOT lose them."
    echo ""
    _confirmation "Continue?"

    # Stop any running Wine so the registry write is not contested.
    "$PROTONEXEC" run wineserver -k 2>/dev/null
    sleep 1

    local key="HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders"
    local guid_docs="{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"
    local guid_dl="{374DE290-123F-4565-9164-39C4925E467B}"

    "$PROTONEXEC" run reg add "$key" /v Personal /t REG_SZ /d "$host_docs" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg add "$key" /v Downloads /t REG_SZ /d "$host_dl" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg add "$key" /v "$guid_docs" /t REG_SZ /d "$host_docs" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg add "$key" /v "$guid_dl" /t REG_SZ /d "$host_dl" /f >/dev/null 2>&1

    # Stop Wine again so the registry file is flushed cleanly.
    "$PROTONEXEC" run wineserver -k 2>/dev/null

    # Persist the binding in the config so prefix reset --full can re-apply it.
    if ! grep -q '^BIND_HOST_DIRS=' "$USERCONFIG/config" 2>/dev/null; then
        {
            echo "BIND_HOST_DIRS=true"
            cat "$USERCONFIG/config"
        } > "$USERCONFIG/config.tmp" 2>/dev/null && mv "$USERCONFIG/config.tmp" "$USERCONFIG/config"
    fi

    echo ""
    echo -e "\e[32mDone.\e[0m Arma 3 now uses your host Documents and Downloads."
    echo "Restart Arma 3 once for the change to take effect."
}

# -----------------------------------------------------------------------------
# UNBIND HOST DIRECTORIES
# -----------------------------------------------------------------------------
# Revert the bind: point Documents and Downloads back at the prefix-local
# folders (%USERPROFILE%\Documents, %USERPROFILE%\Downloads).
_unbind_host_dirs() {
    if [[ -z "$PROTONEXEC" || ! -x "$PROTONEXEC" ]]; then
        echo -e "\e[31mError\e[0m: No Proton executable found. Cannot edit the prefix registry."
        exit 1
    fi
    if [[ ! -d "$COMPAT_DATA_PATH/pfx" ]]; then
        echo -e "\e[31mError\e[0m: No prefix found at $COMPAT_DATA_PATH/pfx"
        exit 1
    fi

    echo ""
    echo "Reverting Documents and Downloads to the prefix-local folders..."
    _confirmation "Continue?"

    "$PROTONEXEC" run wineserver -k 2>/dev/null
    sleep 1

    local key="HKCU\\Software\\Microsoft\\Windows\\CurrentVersion\\Explorer\\User Shell Folders"
    local guid_docs="{FDD39AD0-238F-46AF-ADB4-6C85480369C7}"
    local guid_dl="{374DE290-123F-4565-9164-39C4925E467B}"

    "$PROTONEXEC" run reg add "$key" /v Personal /t REG_EXPAND_SZ /d "%USERPROFILE%\\\\Documents" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg add "$key" /v Downloads /t REG_EXPAND_SZ /d "%USERPROFILE%\\\\Downloads" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg delete "$key" /v "$guid_docs" /f >/dev/null 2>&1
    "$PROTONEXEC" run reg delete "$key" /v "$guid_dl" /f >/dev/null 2>&1

    "$PROTONEXEC" run wineserver -k 2>/dev/null

    # Remove the config flag so prefix reset --full does not re-apply it.
    sed -i '/^BIND_HOST_DIRS=/d' "$USERCONFIG/config" 2>/dev/null

    echo ""
    echo -e "\e[32mDone.\e[0m Documents and Downloads are back to the prefix-local folders."
}

# Run setup wizard if config is default and Arma prefix exists.
# Must run after COMPAT_DATA_PATH is resolved.
# NOTE: _setup_wizard is called only in the no-args launch path (line ~1186)
# to avoid prompting on informational commands like listproton, help, etc.
# NOTE: _check_prefix_version is also launch-path only, for the same reason.

###############################################################################
## MAIN COMMAND HANDLER
###############################################################################

# No arguments: launch TeamSpeak 3 inside Arma's Wine prefix.
# Arma 3 must be running first – TeamSpeak needs the game's audio session.
if [[ -z "$*" ]]; then
    # Single-instance guard: prevent two TS3 clients racing on one prefix
    # and two concurrent localconfig.vdf patches. Best-effort; flock may
    # be absent on exotic systems, in which case we proceed without it.
    if command -v flock &>/dev/null; then
        exec 9>"$USERCONFIG/launch.lock"
        if ! flock -n 9; then
            echo -e "\e[31mError\e[0m: Another Arma3Helper instance is already running."
            exit 1
        fi
    fi
    _setup_wizard
    _check_prefix_version
    _remove_gamepad_plugin
    # Warn if Arma is not running, since the radio plugins cannot connect
    # to a game that is not up. Non-blocking: the user may start Arma after
    # TeamSpeak.
    if ! pgrep -f "arma3_x64" >/dev/null 2>&1; then
        echo -e "\e[33mNote\e[0m: Arma 3 does not appear to be running."
        echo "Start Arma 3 first, or the radio plugins cannot connect."
    fi
    _warn_missing_plugins
    if _ensure_ts3_installed; then
        _checkpath "$TSPATH" "TeamSpeak 3"
    else
        exit 1
    fi
    echo ""
    echo "------------------------------------------------------------"
    echo " Launching TeamSpeak 3 inside Arma 3's Wine prefix"
    echo " IMPORTANT: Start Arma 3 BEFORE running this command!"
    echo " TeamSpeak must run inside the same prefix as Arma."
    echo "------------------------------------------------------------"
    echo ""
    "$PROTONEXEC" run "$TSPATH"
    exit $?
fi

# Check for script updates (once per day, non-blocking)
_check_for_update

case "$1" in

    # -------------------------------------------------------------------------
    "install")
    # -------------------------------------------------------------------------
    # Install the TeamSpeak 3 Windows client into Arma's Wine prefix.
    #
    # CRITICAL INSTALLATION STEPS:
    #
    #   1. Run this command:
    #      ./Arma3Helper.sh install
    #      It downloads the latest Windows 64-bit installer, verifies it, and
    #      installs it silently. You can also pass an installer path you
    #      downloaded yourself:
    #      ./Arma3Helper.sh install /path/to/TeamSpeak3-Client-win64-x.x.x.exe
    #
    #   2. The silent install uses 'Install for All Users', which places TS3 in
    #      C:\Program Files\TeamSpeak 3 Client\ - where this script expects it.
    #      (An installer launched manually must select 'Install for All Users'
    #      and keep the default path.)
    #
    #   3. (automatic) The crashing Gamepad and Joystick plugin is deleted at
    #      every launch.
    # -------------------------------------------------------------------------
        echo ""
        echo "============================================================"
        echo " TeamSpeak 3 Installer"
        echo "============================================================"
        echo ""

        installer_path="$2"
        if [[ -z "$installer_path" ]]; then
            if _download_ts3; then
                installer_path="$_TS3_INSTALLER"
            else
                exit 1
            fi
        fi

        if [[ ! -f "$installer_path" ]]; then
            echo "Error: File not found: $installer_path"
            exit 1
        fi

        echo ""
        echo "Installing TeamSpeak 3 into Arma's Wine prefix..."
        echo "This installs silently with 'Install for All Users'."
        echo "The Gamepad and Joystick plugin is deleted automatically at"
        echo "every launch."
        echo ""

        if "$PROTONEXEC" run "$installer_path" /S /ALLUSERS; then
            echo ""
            echo "Installer finished."
        else
            echo ""
            echo -e "\e[33mWarning\e[0m: The silent installer reported an error."
            echo "Run it manually to see the installer dialog:"
            echo "  $installer_path"
            exit 1
        fi

        # Verify the install landed where the script expects it.
        _ts3exe="$COMPAT_DATA_PATH/pfx/drive_c/Program Files/TeamSpeak 3 Client/ts3client_win64.exe"
        if [[ -x "$_ts3exe" ]]; then
            echo -e "\e[32mTeamSpeak 3 installed successfully.\e[0m"
            echo "Launch it with:  ./Arma3Helper.sh"
        else
            echo -e "\e[33mNote\e[0m: ts3client_win64.exe was not found at the expected path yet."
            echo "Launch Arma 3 and then run './Arma3Helper.sh' - the script"
            echo "checks the full prefix for the executable."
        fi
        ;;

    # -------------------------------------------------------------------------
    "checkdeps")
    # -------------------------------------------------------------------------
    # Check all required system packages are installed.
        _check_dependencies
        ;;

    # -------------------------------------------------------------------------
    "listproton")
    # -------------------------------------------------------------------------
    # List all Proton versions available on this system (official and custom).
        echo ""
        echo "================================================================"
        echo " Available Proton Versions"
        echo "================================================================"
        echo ""
        echo "Official Proton versions (installed via Steam):"

        _any_official=false
        while IFS= read -r lib_path; do
            _sa="$lib_path/steamapps"
            if [[ -d "$_sa/common" ]]; then
                # Use find to locate directories starting with 'Proton' to handle spaces and wildcards
                while IFS= read -r _dir; do
                    if [[ -f "$_dir/proton" ]]; then
                        _ver="$(basename "$_dir")"
                        # Filter out non-Proton runtimes (Runtime, BattlEye) but keep Version, Experimental, and Hotfix
                        if [[ "$_ver" == *"Proton "* ]] && [[ "$_ver" != *"Runtime"* ]] && [[ "$_ver" != *"BattlEye"* ]] && [[ "$_ver" != *"-"* ]]; then
                            echo "  $_ver"
                            _any_official=true
                        elif [[ "$_ver" == *"Proton - Experimental"* || "$_ver" == *"Proton Hotfix"* ]]; then
                            echo "  $_ver"
                            _any_official=true
                        fi
                    fi
                done < <(find "$_sa/common" -maxdepth 1 -type d -name "Proton*")
            fi
        done < <(_find_steam_libraries)

        if [[ "$_any_official" == false ]]; then
            echo "  (none found – install a Proton version via Steam)"
        fi

        echo ""
        echo "Custom / GE Proton builds (from compatibilitytools.d):"
        _list_custom_proton

        echo ""
        echo "================================================================"
        echo ""
        echo "To use a version, edit your config file:"
        echo "  $USERCONFIG/config"
        echo ""
        echo "Official:  Set PROTON_OFFICIAL_VERSION='9.0'  (example)"
        echo "Custom:    Set PROTON_CUSTOM_VERSION='GE-Proton9-20' (example)"
        echo "           Leave the other one empty."
        echo ""
        ;;

    # -------------------------------------------------------------------------
    "winetricks")
    # -------------------------------------------------------------------------
    # Run winetricks (or protontricks) inside Arma 3's Wine prefix.
    #
    # Special case: './Arma3Helper.sh winetricks Arma'
    #   Installs the standard set of DLLs required for ACRE2/TFAR and fixes
    #   common audio and thermal-vision issues.
    #
    #   DLLs installed:
    #     d3dcompiler_43 – DirectX shader compiler (fixes some rendering issues)
    #     d3dx10_43      – DirectX 10 (required by some mods)
    #     d3dx11_43      – DirectX 11 (required by some mods)
    #     mfc140         – Microsoft C++ runtime (required by some mods)
    #     xact_x64       – Microsoft XACT audio engine (fixes audio issues)
    #     xaudio29       – XAudio2 library (fixes audio crackling)
    #     xaudio2_9      – XAudio 2.9 (fixes crackle after Arma 2.22 update)
        echo "Running winetricks inside Arma 3's Wine prefix..."
        _get_wrappercmd || exit 1
        echo "Using: ${_WRAPPER[*]}"
        echo ""
        export WINEPREFIX="$COMPAT_DATA_PATH/pfx"

        if [[ "$2" == "Arma" ]]; then
            echo "Installing recommended DLLs and components for Arma 3..."
            echo "  d3dcompiler_43 d3dx10_43 d3dx11_43 mfc140 xact_x64 xaudio29 xaudio2_9"
            echo ""
            echo "This may take several minutes. Do not interrupt."
            echo ""
            "${_WRAPPER[@]}" d3dcompiler_43 d3dx10_43 d3dx11_43 mfc140 xact_x64 xaudio29 xaudio2_9
            echo ""
            echo "Done. Run Arma 3 and check if audio/thermal-vision issues are resolved."
        else
            echo "Running: ${_WRAPPER[*]} ${*:2}"
            "${_WRAPPER[@]}" "${@:2}"
        fi
        ;;

    # -------------------------------------------------------------------------
    "winecfg")
    # -------------------------------------------------------------------------
    # Open Wine's configuration GUI for Arma 3's prefix.
    # Useful for manually overriding DLLs or adjusting Windows version settings.
        echo "Opening winecfg for Arma 3's Wine prefix..."
        _get_wrappercmd || exit 1
        echo "Using: ${_WRAPPER[*]}"
        export WINEPREFIX="$COMPAT_DATA_PATH/pfx"
        "${_WRAPPER[@]}" winecfg
        ;;

    # -------------------------------------------------------------------------
    "debug")
    # -------------------------------------------------------------------------
    # Print full debug information.
    # Share this output when asking for help on the Discord.
        echo ""
        echo "================================================================"
        echo " Debug Information – Arma3Helper.sh"
        echo "================================================================"
        echo ""

        echo "Script version:         $_SCRIPTVER"

        # Check for updates via GitHub (ignore cache — user explicitly asked)
        if command -v curl &>/dev/null; then
            _remote_ver=$(curl -fs --max-time 5 \
                "https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh" \
                2>/dev/null | grep -m1 '^_SCRIPTVER=' | cut -d'"' -f2)
            if [[ -n "$_remote_ver" ]]; then
                if [[ "$_remote_ver" == "$_SCRIPTVER" ]]; then
                    echo "GitHub version:         $_remote_ver (up to date)"
                else
                    echo "GitHub version:         $_remote_ver (update available!)"
                fi
            fi
        fi

        echo "--- Paths ---"
        echo "Steam root:              $_STEAM_ROOT"
        echo "Arma 3 library:          $(_find_arma_library)"
        echo "COMPAT_DATA_PATH:        $COMPAT_DATA_PATH"
        echo "STEAM_LIBRARY_PATH:      $STEAM_LIBRARY_PATH"
        echo "Proton executable:       $PROTONEXEC"
        echo "TS3 executable:          $TSPATH"
        echo ""
        echo "--- Status ---"
        echo "Proton executable found: $(test -x "$PROTONEXEC" && echo 'YES' || echo 'NO')"
        echo "TS3 executable found:    $(test -x "$TSPATH" && echo 'YES' || echo 'NO')"
        echo "Config file:             $USERCONFIG/config"
        echo ""
        echo "--- Proton Configuration ---"
        if [[ -n "$PROTON_CUSTOM_VERSION" ]]; then
            echo "Type:    Custom"
            echo "Value:   $PROTON_CUSTOM_VERSION"
        elif [[ "$IS_EXPERIMENTAL" == true ]]; then
            echo "Type:    Official Experimental"
        else
            echo "Type:    Official"
            echo "Version: $PROTON_OFFICIAL_VERSION"
        fi
        echo ""
        echo "--- Environment Variables ---"
        echo "STEAM_COMPAT_DATA_PATH:          $STEAM_COMPAT_DATA_PATH"
        echo "STEAM_COMPAT_CLIENT_INSTALL_PATH: $STEAM_COMPAT_CLIENT_INSTALL_PATH"
        echo "STEAM_COMPAT_INSTALL_PATH:       $STEAM_COMPAT_INSTALL_PATH"
        echo "STEAM_COMPAT_LIBRARY_PATHS:      $STEAM_COMPAT_LIBRARY_PATHS"
        echo "SteamAppId / SteamGameId:        $SteamAppId / $SteamGameId"
        echo "ESync:  $ESYNC"
        echo "FSync:  $FSYNC"
        echo ""
        # Warn about the Proton 11.0-1 Workshop regression: it re-downloaded
        # Workshop mods on every launch. Fixed in 11.0-2.
        if [[ -n "$PROTON_OFFICIAL_VERSION" && "$PROTON_OFFICIAL_VERSION" == "11.0-1" ]]; then
            echo -e "\e[33mWarning\e[0m: Proton 11.0-1 re-downloads Workshop mods on every launch."
            echo "Update to Proton 11.0-2 or newer, or use Proton Experimental."
            echo ""
        fi
        echo ""
        echo "--- Launch Command ---"
        echo "\"$PROTONEXEC\" run \"$TSPATH\""
        echo ""
        echo "--- All Steam Libraries ---"
        while IFS= read -r lib; do
            _sa="$lib/steamapps"
            _has_arma=""
            [[ -d "$_sa/compatdata/107410" ]] && _has_arma=" [Arma 3 here]"
            echo "  $lib$_has_arma"
        done < <(_find_steam_libraries)
        echo ""
        echo "--- Custom Proton Builds ---"
        _list_custom_proton
        echo ""
        echo "================================================================"
        echo ""
        echo "If you are seeking support, please share the output above"
        echo "on the ArmaOnUnix Discord: https://discord.gg/p28Ra36"
        echo ""
        ;;

    # -------------------------------------------------------------------------
    "update")
    # -------------------------------------------------------------------------
    # Download the latest version of this script from GitHub.
    # WARNING: This will overwrite any changes made directly inside the script.
    # Your external config file (USERCONFIG/config) is NOT affected.
        echo -e "\e[33mWarning\e[0m: This will overwrite any edits made inside the script itself."
        echo "Your external config at '$USERCONFIG/config' will NOT be affected."
        echo "(Use './Arma3Helper.sh createconfig' to migrate settings to the external config.)"
        echo ""
        _confirmation "Proceed with update?"
        _checkinstall curl
        if [[ -w "$0" ]]; then
            # Can write to the script in place. Download to a temp file first,
            # then move it into place atomically. This protects the running
            # script from truncation if the download is interrupted.
            _tmpscript="$0.tmp"
            if curl -fo "$_tmpscript" https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh; then
                chmod +x "$_tmpscript"
                cp -f "$0" "$0.bak-arma3helper"
                mv -f "$_tmpscript" "$0"
                echo ""
                echo "Update complete. Run './Arma3Helper.sh debug' to verify."
                echo "Previous version kept at: $0.bak-arma3helper"
            else
                rm -f "$_tmpscript"
                echo ""
                echo -e "\e[31mError\e[0m: Download failed. Script was NOT updated."
                exit 1
            fi
        else
            # Cannot write to $0 (e.g. installed in /usr/bin). Download to the
            # current working directory, which the user owns. Never write to
            # dirname "$0" — that is the same permission-denied directory.
            _dest="$PWD/Arma3Helper.sh"
            echo "Cannot write to '$0' (permission denied)."
            echo "Downloading to: $_dest"
            if curl -fo "$_dest" https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh; then
                chmod +x "$_dest"
                echo ""
                echo "Update complete. Replace the installed script manually:"
                echo "  sudo cp $_dest $0"
                echo "Then run: ./Arma3Helper.sh debug"
            else
                echo ""
                echo -e "\e[31mError\e[0m: Download failed. Script was NOT updated."
                exit 1
            fi
        fi
        ;;

    # -------------------------------------------------------------------------
    "prefix")
    # -------------------------------------------------------------------------
    # Diagnose or repair Arma's Wine prefix.
    #
    #   prefix doctor        – read-only health check
    #   prefix reset         – in-place repair, preserves user data
    #   prefix reset --full  – recreate prefix, backs up user data first
    #
    # IMPORTANT: Arma 3 stores profiles, loadouts, missions, and settings in
    # Documents inside the prefix, NOT on the host. There is no Steam Cloud
    # for Arma 3. Any repair that recreates the prefix must back up that data
    # first or it is lost permanently.
    if [[ "$2" == "doctor" ]]; then
        _prefix_doctor
    elif [[ "$2" == "reset" ]]; then
        if [[ "$3" == "--full" ]]; then
            _prefix_reset full
        else
            _prefix_reset inplace
        fi
    else
        echo "Usage:"
        echo "  ./Arma3Helper.sh prefix doctor         Diagnose the prefix (read-only)"
        echo "  ./Arma3Helper.sh prefix reset          Repair in place (preserves user data)"
        echo "  ./Arma3Helper.sh prefix reset --full   Recreate prefix (backs up user data first)"
        exit 1
    fi
    ;;

    # -------------------------------------------------------------------------
    "listmods")
    # -------------------------------------------------------------------------
    # List installed and/or loaded mods for debugging.
    #
    #   listmods            – show both installed and loaded
    #   listmods installed  – only Workshop mods installed on disk
    #   listmods loaded     – only the mods in the current/last session
    echo ""
    echo "================================================================"
    echo " Arma 3 Mods"
    echo "================================================================"
    echo ""
    if [[ "$2" == "installed" ]]; then
        echo "Installed Workshop mods:"
        _list_installed_mods
    elif [[ "$2" == "loaded" ]]; then
        echo "Mods loaded in the latest Arma 3 session:"
        _list_loaded_mods
    else
        echo "Mods loaded in the latest Arma 3 session:"
        _list_loaded_mods
        echo ""
        echo "Installed Workshop mods:"
        _list_installed_mods
    fi
    echo ""
    echo "================================================================"
    echo ""
    ;;

    # -------------------------------------------------------------------------
    "verifyradio")
    # -------------------------------------------------------------------------
    # Verify the full chain for ACRE2 and TFAR: Workshop mod downloaded,
    # mod loaded in the running game, plugin installed in TeamSpeak.
    _verify_radio
    ;;

    # -------------------------------------------------------------------------
    "acremod")
    # -------------------------------------------------------------------------
    # Install the ACRE2 plugin into the prefix TeamSpeak install. ACRE2
    # normally auto-installs its plugin when the mod loads, but that can
    # fail when TeamSpeak is installed later. This is the repair path.
    _install_acre2_plugin
    ;;

    # -------------------------------------------------------------------------
    "acrecheck")
    # -------------------------------------------------------------------------
    # Diagnose why the radio plugins cannot talk to Arma 3 (the 'cannot
    # find game instance' error). Names the exact cause and fix.
    _check_radio_connection
    ;;

    # -------------------------------------------------------------------------
    "tfarmod")
    # -------------------------------------------------------------------------
    # Install the Task Force Radio plugin into the prefix TeamSpeak install.
    # TFAR does not auto-install its plugin (unlike ACRE2). The plugin DLLs
    # are found in the Workshop mod folder and copied into the prefix.
    #
    #   tfarmod        – install the TFAR plugin (also re-enables if disabled)
    #   tfarmod --enable – re-enable a plugin TeamSpeak disabled after a crash
    if [[ "$2" == "--enable" ]]; then
        _enable_tfar_plugin
    else
        _install_tfar_plugin
    fi
    ;;

    # -------------------------------------------------------------------------
    "createconfig")
    # -------------------------------------------------------------------------
    # Create an external config file at ~/.config/arma3helper/config.
    # This file persists across script updates. Settings in it override
    # the defaults set inside this script.
        if [[ -e "$USERCONFIG/config" ]]; then
            echo -e "\e[33mA config file already exists at:\e[0m $USERCONFIG/config"
            _confirmation "Override it with a fresh template?"
        fi
        _checkinstall curl
        mkdir -p "$USERCONFIG"
        # mktemp avoids leaving an orphaned .tmp file on Ctrl-C
        _tmpconfig="$(mktemp "$USERCONFIG/config.XXXXXX")"
        if curl -fo "$_tmpconfig" \
            https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/config; then
            mv "$_tmpconfig" "$USERCONFIG/config"
            echo ""
            echo "Config file created at: $USERCONFIG/config"
            echo "Edit it to set your Proton version and other preferences."
        else
            rm -f "$_tmpconfig"
            echo ""
            echo -e "\e[31mError\e[0m: Download failed. Config was NOT created."
            exit 1
        fi
        ;;
    "bindhost")
    # -------------------------------------------------------------------------
    # Point the prefix's Documents and Downloads at the real host folders.
        _bind_host_dirs
        ;;
    "unbindhost")
    # -------------------------------------------------------------------------
    # Revert Documents and Downloads to the prefix-local folders.
        _unbind_host_dirs
        ;;

    # -------------------------------------------------------------------------
    "help"|*)
    # -------------------------------------------------------------------------
    # Print usage information.
        echo ""
        echo "================================================================"
        echo " Arma3Helper.sh – Usage Guide"
        echo "================================================================"
        echo ""
        echo " ./Arma3Helper.sh"
        echo "     Launch TeamSpeak 3 inside Arma 3's Wine prefix."
        echo "     Always start Arma 3 FIRST before running this."
        echo ""
        echo " ./Arma3Helper.sh install [path/to/TS3-installer.exe]"
        echo "     Install TeamSpeak 3 (Windows version) into Arma's prefix."
        echo "     With no path, downloads and verifies the latest installer"
        echo "     automatically. Installs silently for All Users."
        echo ""
        echo " ./Arma3Helper.sh winetricks Arma"
        echo "     Install recommended DLLs for Arma 3. Run this once before"
        echo "     your first session to fix audio and visual issues."
        echo ""
        echo " ./Arma3Helper.sh winetricks <args>"
        echo "     Run any winetricks command inside Arma 3's Wine prefix."
        echo ""
        echo " ./Arma3Helper.sh winecfg"
        echo "     Open Wine configuration for Arma 3's prefix."
        echo ""
        echo " ./Arma3Helper.sh checkdeps"
        echo "     Check all required system packages (GStreamer, winetricks,"
        echo "     curl, Vulkan tools) plus the BattlEye runtime, the noexec"
        echo "     mount check, and the ACRE2/TFAR radio plugins."
        echo ""
        echo " ./Arma3Helper.sh listmods"
        echo "     List mods installed and mods loaded in the latest session."
        echo "     Use 'listmods loaded' or 'listmods installed' for one list."
        echo ""
        echo " ./Arma3Helper.sh verifyradio"
        echo "     Verify the full radio chain for ACRE2 and TFAR: Workshop"
        echo "     mod downloaded, mod loaded in the game, plugin in TeamSpeak."
        echo ""
        echo " ./Arma3Helper.sh acrecheck"
        echo "     Diagnose why radio plugins cannot find the Arma 3 game"
        echo "     instance: Arma running, radio mod loaded."
        echo ""
        echo " ./Arma3Helper.sh acremod"
        echo "     Install the ACRE2 plugin manually. ACRE2 normally installs"
        echo "     it automatically; use this when auto-install failed."
        echo ""
        echo " ./Arma3Helper.sh tfarmod"
        echo "     Install the Task Force Radio plugin into the prefix"
        echo "     TeamSpeak install. TFAR does not auto-install its plugin."
        echo ""
        echo " ./Arma3Helper.sh tfarmod --enable"
        echo "     Re-enable a radio plugin TeamSpeak disabled after a crash."
        echo ""
        echo " ./Arma3Helper.sh listproton"
        echo "     List all Proton versions installed on this system,"
        echo "     including official and custom/GE builds."
        echo ""
        echo " ./Arma3Helper.sh debug"
        echo "     Print full diagnostic information. Share this output when"
        echo "     asking for help on the Discord."
        echo ""
        echo " ./Arma3Helper.sh update"
        echo "     Update this script from GitHub. This resets in-script edits."
        echo "     Use an external config file to avoid losing your settings."
        echo ""
echo " ./Arma3Helper.sh createconfig"
         echo "     Create an external config at $USERCONFIG/config"
         echo "     that persists across script updates."
         echo ""
         echo " ./Arma3Helper.sh prefix doctor"
         echo "     Diagnose Arma's Wine prefix (read-only). Checks the"
         echo "     version file, system directory, drive mappings, and mount."
         echo ""
         echo " ./Arma3Helper.sh prefix reset"
         echo "     Repair the prefix in place. Rebuilds Proton's system files"
         echo "     and preserves your profiles, loadouts, and TeamSpeak data."
         echo ""
         echo " ./Arma3Helper.sh prefix reset --full"
         echo "     Recreate the prefix. Backs up your Arma 3 profiles and"
         echo "     TeamSpeak data first, then moves the old prefix aside."
         echo ""
         echo " ./Arma3Helper.sh bindhost"
         echo "     Point Arma's Documents and Downloads at your real host"
         echo "     folders. Profiles then survive prefix deletion."
         echo ""
         echo " ./Arma3Helper.sh unbindhost"
         echo "     Revert Documents and Downloads to the prefix-local folders."
         echo ""
         echo " ./Arma3Helper.sh help"
         echo "     Show this help message."
        echo ""
        echo "================================================================"
        echo " Before reporting issues, check your settings and run:"
        echo "   ./Arma3Helper.sh checkdeps"
        echo "   ./Arma3Helper.sh debug"
        echo ""
        echo " Support: https://discord.gg/p28Ra36  (ArmaOnUnix Discord)"
        echo "================================================================"
        echo ""
        ;;

esac