# Arma 3 on Linux Helper

## Community Fork

This repository is a community-maintained fork of the original `armaonlinux` project. It
was developed by members of our milsim community to provide enhanced documentation,
improved installation scripts, and better support for custom configurations. While
created to streamline the onboarding process for our own members, we have made this
public to support the wider Arma on Linux/Unix community.

## Improvements

- **Steam Library Auto-Detection:** Supports external drives and non-standard
  library locations automatically.
- **Proton Auto-Detection:** Reads the Proton version from Arma's prefix and
  matches it to an installed build. No manual version setting needed.
- **TeamSpeak 3 Auto-Install:** Downloads, verifies, and installs the latest
  TeamSpeak 3 silently. Also offered automatically if TeamSpeak is missing
  at launch.
- **Radio Plugin Management:** `tfarmod` and `acremod` install the TFAR and
  ACRE2 plugins. `verifyradio` checks the full chain: Workshop mod downloaded,
  mod loaded in the game, plugin installed in TeamSpeak.
- **Radio Diagnostics:** `acrecheck` names the exact cause when radio plugins
  cannot find the game. `listmods` shows installed and loaded mods, read live
  from the running game.
- **Native Host Documents:** `bindhost` points Arma's Documents and Downloads
  at your real host folders through Wine's registry, so profiles survive
  prefix deletion. No Steam launch options or symlinks needed.
- **Prefix Doctor and Reset:** `prefix doctor` diagnoses a broken prefix;
  `prefix reset` repairs in place or recreates it with full backup.
- **Setup Wizard:** Chains the full onboarding flow: dependencies, TeamSpeak
  install, Winetricks DLLs, and radio plugin verification.
- **Self-Healing Launch:** Warns with the exact fix when plugins are missing
  or disabled, and offers to install TeamSpeak 3 when absent.
- **Automated CI/CD:** GitHub Actions renders and deploys the documentation
  to GitHub Pages, and runs shellcheck plus a unit test suite (86 tests) on
  every push and pull request.
- **Full Documentation:** A guide in Quarto (`.qmd`) format, written to the
  standards of the Joint Service Publication 101 (JSP 101) Writers' Handbook.
- **Enhanced Dependencies:** Checks multilib GStreamer libraries, the
  BattlEye runtime, and noexec mounts.

## Quick Start

If you are new to this guide, see **Annex B – Quick Reference Commands** in `arma3-linux-guide.qmd` for a complete, step-by-step setup workflow.

## Usage

See the internal help:

```bash
./Arma3Helper.sh help
```

For detailed setup instructions, please consult the `arma3-linux-guide.qmd` file.

## Support

Community support is available on the [ArmaOnUnix Discord](https://discord.gg/p28Ra36).

## Licence and Attribution

This project is a community fork of [armaonlinux](https://github.com/ninelore/armaonlinux)
by Ingo Reitz. The helper script is licensed under the GNU General Public License
version 2 (see `LICENSE`). The guide (`arma3-linux-guide.qmd`) is adapted in part from
upstream documentation, which is licensed under the Creative Commons Attribution
4.0 licence; upstream attribution is retained in the guide's history and title
metadata. The Pandoc template in `templates/` retains its original third-party
licence headers.
