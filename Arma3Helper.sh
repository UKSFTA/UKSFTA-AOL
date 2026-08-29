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
#   ./Arma3Helper.sh launchopts – Fix Arma Steam launch options (ACRE2/TFAR)
#
# Original Repository: https://github.com/ninelore/armaonlinux
# Support:    https://discord.gg/p28Ra36  (ArmaOnUnix Discord)

_SCRIPTVER="2.0.1"

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
# VERSIONING
# -----------------------------------------------------------------------------
# Check for script updates (once per day max)
_update_stamp() { echo "$USERCONFIG/.last_update_check"; }

_check_for_update() {
    # Skip if no curl or if checked within last 24 hours
    command -v curl &>/dev/null || return 0
    local stamp
    stamp="$(_update_stamp)"
    if [[ -f "$stamp" ]]; then
        local age
        age=$(( $(date +%s) - $(stat -c %Y "$stamp" 2>/dev/null || echo 0) ))
        (( age < 86400 )) && return 0
    fi

    # Fetch remote script header and extract its _SCRIPTVER
    local remote_ver
    remote_ver=$(curl -fs --max-time 5 \
        "https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh" \
        2>/dev/null | grep -m1 '^_SCRIPTVER=' | cut -d'"' -f2)

    # Record check time regardless of result
    date +%s > "$stamp" 2>/dev/null

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
        mkdir -p "$USERCONFIG"
        cat <<EOF > "$USERCONFIG/config"
# Default configuration generated by Arma3Helper
PROTON_OFFICIAL_VERSION=""
COMPAT_DATA_PATH=""
STEAM_LIBRARY_PATH=""
PROTON_CUSTOM_VERSION=""
ESYNC=true
FSYNC=true
EOF
        chmod 600 "$USERCONFIG/config"
        echo "Created default configuration at $USERCONFIG/config"
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
# shellcheck source=/dev/null
source "$USERCONFIG/config"

# -----------------------------------------------------------------------------
# SETUP WIZARD
# -----------------------------------------------------------------------------
# Run setup wizard if config is default and Arma prefix exists
_setup_wizard() {
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
            _get_wrappercmd
            echo "Installing recommended DLLs..."
            "${_WRAPPER[@]}" d3dcompiler_43 d3dx10_43 d3dx11_43 xact_x64 xaudio29
            echo -e "\e[32mSetup complete.\e[0m"
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

# _confirmation <question>
#   Ask the user a yes/no question. Exits if they answer no.
_confirmation() {
    read -p "$1 (y/n) " -n 1 -r
    echo
    if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
        exit 1
    fi
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
                gsub(/.*"path"[[:space:]]*"|".*/, "")
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

    echo ""
    echo "================================================================"
    echo ""
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
        exit 1
    fi
}

###############################################################################
## RESOLVE PATHS
###############################################################################

# Determine the Steam root directory
_STEAM_ROOT="$(_find_steam_root)"

# -----------------------------------------------------------------------------
# Resolve COMPAT_DATA_PATH (Arma's Wine prefix)
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
        echo -e "\e[33mWarning\e[0m: Could not auto-detect Arma 3 library."
        echo "Falling back to: $COMPAT_DATA_PATH"
        echo "If this is wrong, set COMPAT_DATA_PATH in the config file."
        echo "Run './Arma3Helper.sh createconfig' to create the config file."
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
                done < <(find "$lib_path/compatibilitytools.d" -maxdepth 1 -type d -name "Proton*")
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
        else
            PROTON_OFFICIAL_VERSION="10.0"
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
if [[ -z "$PROTONEXEC" || ! -x "$PROTONEXEC" ]]; then
    echo "Error: No Proton executable found."
    if [[ -n "$PROTON_CUSTOM_VERSION" ]]; then
        echo "  Custom version:  $PROTON_CUSTOM_VERSION"
        echo "  Ensure this version is installed in compatibilitytools.d."
    else
        echo "  Searched for:  Proton $PROTON_OFFICIAL_VERSION"
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
_check_prefix_version

# Run setup wizard if config is default and Arma prefix exists.
# Must run after COMPAT_DATA_PATH is resolved.
# NOTE: _setup_wizard is called only in the no-args launch path (line ~1117)
# to avoid prompting on informational commands like listproton, help, etc.

# -----------------------------------------------------------------------------
# Ensure Arma's Steam launch options set XDG_RUNTIME_DIR (ACRE2/TFAR pipe fix).
#
# Steam Linux Runtime 4+ gives each pressure-vessel container a private /tmp,
# which splits the wineserver namespace between Arma (in-container) and
# TeamSpeak (launched on the host). ACRE2/TFAR named pipes then never connect.
# Steam launch options are the only way to set env vars inside the container,
# so we patch localconfig.vdf automatically. Idempotent; existing launch
# options are preserved. Run standalone with './Arma3Helper.sh launchopts'.
# -----------------------------------------------------------------------------
# Ensure Arma's Steam launch options expose the host paths ACRE2/TFAR and the
# user need. Steam Linux Runtime 4+ gives each pressure-vessel container a
# private /tmp and /home, so:
#   - Arma's wineserver socket is invisible to TeamSpeak on the host, which
#     breaks ACRE2/TFAR named pipes. Exposing /tmp puts the socket on host
#     /tmp, where TeamSpeak (launched by this script) joins the same wineserver.
#   - Arma cannot see the user's real Documents/Downloads for modlists/config.
# This is the standard pressure-vessel mechanism (PRESSURE_VESSEL_FILESYSTEMS_RW).
# Idempotent; existing launch options are preserved. Override the shared dirs
# with RUNTIME_SHARE_DIRS in the config file. Run standalone with
# './Arma3Helper.sh launchopts'.
# -----------------------------------------------------------------------------
_ensure_steam_launch_options() {
    # Validate: RUNTIME_SHARE_DIRS becomes part of the Steam launch options
    # string, so restrict it to safe characters (paths, colons, slashes).
    # An unescaped quote or shell metacharacter could inject into the VDF or
    # the game's command line.
    local share_dirs="${RUNTIME_SHARE_DIRS:-/tmp:$HOME/Documents:$HOME/Downloads}"
    if [[ ! "$share_dirs" =~ ^[A-Za-z0-9_/:.,-]+$ ]]; then
        echo -e "\e[33mWarning\e[0m: RUNTIME_SHARE_DIRS contains invalid characters. Using /tmp only."
        share_dirs="/tmp"
    fi
    local target="PRESSURE_VESSEL_FILESYSTEMS_RW=$share_dirs"
    local patched=0 skipped=0

    if ! command -v python3 &>/dev/null; then
        echo -e "\e[33mWarning\e[0m: python3 not found – cannot auto-configure Steam launch options."
        echo "Set this manually in Steam -> Arma 3 -> Properties -> Launch Options:"
        echo "  $target %command%"
        return 1
    fi

    echo "Checking Steam launch options for Arma 3..."
    local vdf out
    for vdf in "$_STEAM_ROOT"/userdata/*/config/localconfig.vdf; do
        [[ -f "$vdf" ]] || continue
        out=$(python3 - "$vdf" "$target" <<'PYEOF'
import re, shutil, sys
path, target = sys.argv[1], sys.argv[2]
data = open(path, 'rb').read()
if b'\x00' in data[:1024]:
    print('BINARY'); sys.exit(0)
text = data.decode('utf-8', errors='replace')
lines = text.splitlines(keepends=True)
block_start = None
for i in range(len(lines) - 1):
    if lines[i].strip() == '"107410"' and lines[i + 1].strip() == '{':
        block_start = i
        break
if block_start is None:
    print('NOAPP'); sys.exit(0)
depth = 1
k = block_start + 2
found = None
while k < len(lines) and depth > 0:
    s = lines[k].strip()
    if s == '{':
        depth += 1
    elif s == '}':
        depth -= 1
        if depth == 0:
            break
    elif depth == 1:
        m = re.match(r'^(\s*)"LaunchOptions"\s+"(.*)"\s*$', lines[k])
        if m:
            found = (k, m.group(2))
    k += 1
if found:
    k, old = found
    # drop stale PRESSURE_VESSEL_FILESYSTEMS_RW / XDG_RUNTIME_DIR assignments, keep the rest
    cleaned = re.sub(r'\b(?:PRESSURE_VESSEL_FILESYSTEMS_RW|XDG_RUNTIME_DIR)=\S*\s*', '', old).strip()
    new_val = target if not cleaned else target + ' ' + cleaned
    if new_val == old:
        print('ALREADY'); sys.exit(0)
    lines[k] = re.sub(r'^(.*)"LaunchOptions".*$', lambda m: m.group(1) + '"LaunchOptions"\t\t"' + new_val + '"', lines[k])
else:
    indent = re.match(r'^(\s*)', lines[block_start + 1]).group(1) + '\t'
    lines.insert(block_start + 2, indent + '"LaunchOptions"\t\t"' + target + '"\n')
shutil.copy2(path, path + '.bak-arma3helper')
open(path, 'w').write(''.join(lines))
print('PATCHED')
PYEOF
        )
        case "$out" in
            PATCHED) echo "  Patched launch options:  $vdf"; patched=$((patched+1));;
            ALREADY) echo "  Already configured:     $vdf";;
            BINARY)  echo "  Skipped (binary VDF):   $vdf"; echo "    Set manually in Steam: $target %command%"; skipped=$((skipped+1));;
            NOAPP)   echo "  No Arma 3 entry:        $vdf";;
            *)       echo "  Failed to patch:        $vdf"; skipped=$((skipped+1));;
        esac
    done

    if (( skipped > 0 )); then
        return 1
    fi
    if (( patched == 0 && skipped == 0 )); then
        echo -e "\e[33mWarning\e[0m: No Steam user data found for Arma 3."
        echo "Launch options could not be set automatically."
        echo "Set this manually in Steam -> Arma 3 -> Properties -> Launch Options:"
        echo "  $target %command%"
        return 1
    fi
    if (( patched > 0 )); then
        if pgrep -x steam &>/dev/null; then
            echo -e "\e[33mNote\e[0m: Steam is running and may overwrite this change on exit."
            echo "If it doesn't stick, close Steam fully, run './Arma3Helper.sh launchopts', then relaunch Arma."
        else
            echo "Done. Launch options applied – start Arma 3 and ACRE2 will connect."
        fi
    fi
}

###############################################################################
## MAIN COMMAND HANDLER
###############################################################################

# No arguments: launch TeamSpeak 3 inside Arma's Wine prefix.
# Arma 3 must be running first – TeamSpeak needs the game's audio session.
if [[ -z "$*" ]]; then
    _setup_wizard
    _ensure_steam_launch_options
    _checkpath "$TSPATH" "TeamSpeak 3"
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
    #   1. Download the TeamSpeak 3 Windows installer (64-bit version).
    #      Get it from: https://www.teamspeak.com/en/downloads/
    #      Choose 'Windows 64-bit' – do NOT use the Linux version.
    #
    #   2. Run this command:
    #      ./Arma3Helper.sh install /path/to/TeamSpeak3-Client-win64-x.x.x.exe
    #
    #   3. When the installer opens, you MUST:
    #      a. Select 'Install for All Users' (not 'Install for current user only')
    #         WHY: 'Install for All Users' places TS3 in
    #              C:\Program Files\TeamSpeak 3 Client\
    #              which is where this script expects to find it.
    #              'Install for current user only' places it in AppData\Local,
    #              which the script cannot find automatically.
    #
    #      b. Accept the default installation path WITHOUT changing it.
    #         The path should read: C:\Program Files\TeamSpeak 3 Client
    #         Do not alter this path.
    #
    #   4. After installation, launch TS3 with './Arma3Helper.sh' and then:
    #      - Go to Tools > Options > Addons
    #      - Disable 'Gamepad and Joystick Hotkey Support'
    #        WHY: This plugin crashes TS3 when a gamepad/controller is present.
    # -------------------------------------------------------------------------
        echo ""
        echo "============================================================"
        echo " TeamSpeak 3 Installer"
        echo "============================================================"
        echo ""
        echo " CRITICAL: Follow these steps in the installer exactly:"
        echo ""
        echo "  Step 1 – Select:"
        echo -e "             \e[33mInstall for All Users\e[0m"
        echo "           (NOT 'Install for current user only')"
        echo ""
        echo "  Step 2 – Accept the default path WITHOUT changing it:"
        echo -e "             \e[33mC:\\Program Files\\TeamSpeak 3 Client\e[0m"
        echo ""
        echo "  Step 3 – Complete the installation."
        echo ""
        echo "  Step 4 – After installation, disable this TS3 plugin:"
        echo -e "             \e[33mGamepad and Joystick Hotkey Support\e[0m"
        echo "           (Tools > Options > Addons)"
        echo ""
        echo "============================================================"
        echo ""
        sleep 3

        if [[ -z "$2" ]]; then
            echo "Error: No installer path was provided."
            echo ""
            echo "Usage:  ./Arma3Helper.sh install /path/to/TeamSpeak3-Client-win64-x.x.x.exe"
            echo ""
            echo "Download from: https://www.teamspeak.com/en/downloads/"
            echo "(Choose the Windows 64-bit version)"
            exit 1
        fi

        if [[ ! -f "$2" ]]; then
            echo "Error: File not found: $2"
            exit 1
        fi

        "$PROTONEXEC" run "$2"
        ;;

    # -------------------------------------------------------------------------
    "checkdeps")
    # -------------------------------------------------------------------------
    # Check all required system packages are installed.
        _check_dependencies
        ;;

    # -------------------------------------------------------------------------
    "launchopts")
    # -------------------------------------------------------------------------
    # Patch Arma 3's Steam launch options with XDG_RUNTIME_DIR so Arma and
    # TeamSpeak share a wineserver (required since Steam Linux Runtime 4
    # isolates /tmp per container, which breaks ACRE2/TFAR named pipes).
        _ensure_steam_launch_options
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
    #     xact_x64       – Microsoft XACT audio engine (fixes audio issues)
    #     xaudio29       – XAudio2 library (fixes audio crackling)
        echo "Running winetricks inside Arma 3's Wine prefix..."
        _get_wrappercmd
        echo "Using: ${_WRAPPER[*]}"
        echo ""
        export WINEPREFIX="$COMPAT_DATA_PATH/pfx"

        if [[ "$2" == "Arma" ]]; then
            echo "Installing recommended DLLs and components for Arma 3..."
            echo "  d3dcompiler_43 d3dx10_43 d3dx11_43 xact_x64 xaudio29"
            echo ""
            echo "This may take several minutes. Do not interrupt."
            echo ""
            "${_WRAPPER[@]}" d3dcompiler_43 d3dx10_43 d3dx11_43 xact_x64 xaudio29
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
        _get_wrappercmd
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
        echo "SteamAppId / SteamGameId:        $SteamAppId / $SteamGameId"
        echo "ESync:  $ESYNC"
        echo "FSync:  $FSYNC"
        echo ""
        echo "--- Required Arma 3 Steam Launch Options ---"
        echo "PRESSURE_VESSEL_FILESYSTEMS_RW=${RUNTIME_SHARE_DIRS:-/tmp:$HOME/Documents:$HOME/Downloads} %command%"
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
            # Can write to the script in place – update directly.
            if curl -fo "$0" https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/master/Arma3Helper.sh; then
                chmod +x "$0"
                echo ""
                echo "Update complete. Run './Arma3Helper.sh debug' to verify."
            else
                echo ""
                echo -e "\e[31mError\e[0m: Download failed. Script was NOT updated."
                exit 1
            fi
        else
            # Cannot write to $0 (e.g. installed in /usr/bin) – download to cwd.
            _dest="./Arma3Helper.sh"
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
        _tmpconfig="$USERCONFIG/config.tmp"
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
        echo "     Also makes sure Arma's Steam launch options expose the host"
        echo "     paths ACRE2/TFAR need (same as 'launchopts')."
        echo ""
        echo " ./Arma3Helper.sh install <path/to/TS3-installer.exe>"
        echo "     Install TeamSpeak 3 (Windows version) into Arma's prefix."
        echo "     During install: select 'Install for All Users' and accept"
        echo "     the default path (C:\\Program Files\\TeamSpeak 3 Client)."
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
        echo "     curl, Vulkan tools). Run this to diagnose missing software."
        echo ""
        echo " ./Arma3Helper.sh listproton"
        echo "     List all Proton versions installed on this system,"
        echo "     including official and custom/GE builds."
        echo ""
        echo " ./Arma3Helper.sh launchopts"
        echo "     Ensure Arma's Steam launch options expose host paths to the"
        echo "     container: /tmp (ACRE2/TFAR wineserver link) and your real"
        echo "     Documents/Downloads (modlists, config). Requires one Arma"
        echo "     relaunch after patching."
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