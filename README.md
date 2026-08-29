# Arma 3 on Linux Helper

## Community Fork

This repository is a community-maintained fork of the original `armaonlinux` project. It
was developed by members of our milsim community to provide enhanced documentation,
improved installation scripts, and better support for custom configurations. While
created to streamline the onboarding process for our own members, we have made this
public to support the wider Arma on Linux/Unix community.

## Improvements

- **Steam Library Auto-Detection:** Now supports external drives and non-standard
  library locations automatically.
- **Custom Proton Support:** Improved support for custom and GE-Proton versions.
- **Proton Auto-Detection:** Reads the Proton version from Arma's prefix and
  matches it to an installed build. No manual version setting needed.
- **Setup Wizard:** Automated onboarding detects existing installations and guides
  users through necessary `winetricks`/dependency setup.
- **Prefix Protection:** Proactive safety check alerts users to potential Proton-version
  mismatches to prevent configuration breakage.
- **Automated CI/CD:** Integrated GitHub Actions workflow to automatically render and
  deploy the documentation to GitHub Pages (supporting both HTML and PDF formats).
  CI also runs shellcheck and a unit test suite on every push and pull request.
- **Unit Tests:** A test suite (`test_arma3helper.sh`) covers version matching,
  Steam library discovery, symlink handling, and edge cases.
- **Full Documentation:** A guide in Quarto (`.qmd`) format is included, written to
  the standards of the Joint Service Publication 101 (JSP 101) Writers' Handbook.
- **Enhanced Dependencies:** Expanded checks to ensure multilib GStreamer libraries are
  present for audio support.

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
