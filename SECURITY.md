# Security Policy

## Supported Versions

Only the latest release on the `master` branch receives security fixes.

| Version | Supported |
|---|---|
| latest (`master`) | yes |
| earlier releases | no |

## Reporting a Vulnerability

Report vulnerabilities privately. Do not open a public issue for a
security problem.

To report:

1. Open a private report on GitHub:
   https://github.com/UKSFTA/UKSFTA-AOL/security/advisories/new
2. Include the script version (`./Arma3Helper.sh debug` prints it)
3. Describe the problem and how to reproduce it

You will get an acknowledgement within 7 days. We keep you informed of
progress until the issue is resolved.

## Scope

This project is a bash helper script. The main security-relevant areas are:

- Commands that download files (`update`, `createconfig`)
- Commands that run executables (`install`, `winetricks`, `winecfg`)
- The external config file at `~/.config/arma3helper/config`

The config file is sourced by the script. Treat it as executable code.
Do not copy a config file from an untrusted source.

## Security Practices

The project follows these practices:

- Signed commits (GPG) for traceability
- Shellcheck in CI for every push and pull request
- The config file is created with mode 600 (owner read/write only)
- Downloads use HTTPS and fail on HTTP errors
- No secrets are stored in the repository