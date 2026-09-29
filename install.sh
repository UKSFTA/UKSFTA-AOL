#!/bin/sh
# Install Arma3Helper into a user bin directory (default: ~/.local/bin).
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/UKSFTA/UKSFTA-AOL/main/install.sh | sh
#   ./install.sh --dir ~/bin
#   ./install.sh --system           # install to /usr/local/bin (needs root)
#   ./install.sh --ref v2.6.1       # install a specific tag
#   ./install.sh --local            # install the Arma3Helper.sh next to this file
#
# The script is installed with mode 0755, so no manual chmod is needed.
# Re-run the same command to update.

set -eu

REPO="UKSFTA/UKSFTA-AOL"
ASSET="Arma3Helper.sh"
COMMAND="Arma3Helper"
REF="main"
LOCAL=0

usage() {
    cat <<'EOF'
Install Arma3Helper into a user bin directory.

Usage: install.sh [options]

Options:
  --dir PATH    Install directory (default: ~/.local/bin)
  --system      Install to /usr/local/bin (needs root)
  --ref REF     Git ref to download (default: main, for example v2.6.1)
  --local       Install the Arma3Helper.sh next to this script
  -h, --help    Show this help
EOF
}

install_dir="${ARMA3HELPER_BIN_DIR:-}"

while [ "$#" -gt 0 ]; do
    case "$1" in
    --dir)
        [ "$#" -ge 2 ] || {
            echo "Error: --dir needs a path." >&2
            exit 1
        }
        install_dir="$2"
        shift 2
        ;;
    --system)
        install_dir="/usr/local/bin"
        shift
        ;;
    --ref)
        [ "$#" -ge 2 ] || {
            echo "Error: --ref needs a value." >&2
            exit 1
        }
        REF="$2"
        shift 2
        ;;
    --local)
        LOCAL=1
        shift
        ;;
    -h | --help)
        usage
        exit 0
        ;;
    *)
        echo "Error: unknown option: $1" >&2
        usage >&2
        exit 1
        ;;
    esac
done

if [ -z "$install_dir" ]; then
    if [ -z "${HOME:-}" ]; then
        echo "Error: HOME is not set. Use --dir to choose an install directory." >&2
        exit 1
    fi
    install_dir="$HOME/.local/bin"
fi

tmp=""
cleanup() {
    if [ -n "$tmp" ]; then
        rm -f "$tmp"
    fi
}
trap cleanup EXIT HUP INT TERM

if [ "$LOCAL" -eq 1 ]; then
    src_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
    src="$src_dir/$ASSET"
    if [ ! -f "$src" ]; then
        echo "Error: $src not found." >&2
        echo "Run --local from a repository checkout." >&2
        exit 1
    fi
else
    url="https://raw.githubusercontent.com/$REPO/$REF/$ASSET"
    tmp="$(mktemp "${TMPDIR:-/tmp}/arma3helper.XXXXXX")"
    echo "Downloading $ASSET ($REF)..."
    if command -v curl >/dev/null 2>&1; then
        curl -fsSL -o "$tmp" "$url"
    elif command -v wget >/dev/null 2>&1; then
        wget -qO "$tmp" "$url"
    else
        echo "Error: curl or wget is required." >&2
        exit 1
    fi
    src="$tmp"
fi

version="$(sed -n 's/^_SCRIPTVER="\(.*\)"/\1/p' "$src" | head -1)"

if [ ! -d "$install_dir" ] && ! mkdir -p "$install_dir"; then
    echo "Error: cannot create $install_dir." >&2
    echo "For a system install, run with sudo, or use --dir ~/.local/bin." >&2
    exit 1
fi

if command -v install >/dev/null 2>&1; then
    install -m 0755 "$src" "$install_dir/$COMMAND"
else
    cp -f "$src" "$install_dir/$COMMAND"
    chmod 0755 "$install_dir/$COMMAND"
fi

echo "Installed Arma3Helper ${version:-(version unknown)} to $install_dir/$COMMAND"

case ":$PATH:" in
*":$install_dir:"*) ;;
*)
    echo "Note: $install_dir is not on your PATH."
    echo "Add it with: export PATH=\"$install_dir:\$PATH\""
    ;;
esac

echo "Run 'Arma3Helper help' to start."
