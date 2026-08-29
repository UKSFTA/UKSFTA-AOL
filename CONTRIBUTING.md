# Contributing

Thank you for contributing to UKSFTA-AOL.

This project helps the Arma on Linux community run TeamSpeak 3 and the
ACRE2 and TFAR plugins inside Arma's Wine prefix.

## Standards

All contributions must meet these standards:

- **ASD-STE100** for prose. Write in Simplified Technical English.
  British spelling: `-ise`, not `-ize`. No contractions, no semicolons,
  no em dashes.
- **Shellcheck clean** for bash. No warnings, info, or errors.
- **Tests pass** before you open a pull request.
- **Signed commits** (GPG) for every commit.

## Development Workflow

1. Fork the repository.
2. Create a feature branch from `master`:
   ```
   git checkout -b fix/short-description
   ```
   Branch types: `feat`, `fix`, `docs`, `refactor`, `test`, `ops`, `sec`.
3. Make your change.
4. Run the checks:
   ```
   bash -n Arma3Helper.sh
   shellcheck -e SC1090 -e SC1091 Arma3Helper.sh test_arma3helper.sh
   bash test_arma3helper.sh
   ```
5. Commit with a clear message:
   ```
   <component>: <imperative summary, <50 chars>

   - <change rationale>
   - <requirement or defect reference>
   ```
   Example: `fix: handle empty prefix directory`
6. Open a pull request to `master`.

## Test Suite

The test suite lives in `test_arma3helper.sh`. It runs without a real
Steam installation. It uses mock directories for version matching and
Steam library discovery.

Add a test for any logic you change. Edge cases are requirements.

## Commit Messages

Follow the format in the Defence Git Practices standard:

- Subject: imperative, no full stop, under 50 characters
- Body: what changed, why, and what it links to
- No mentions of AI or tooling
- GPG-signed

Good:

```
fix: handle empty prefix directory
```

Bad:

```
Updated the script
```

## Documentation

The guide `arma3-linux-guide.qmd` is written to the JSP 101 Writers'
Handbook standard. Update it when you change user-facing behaviour.

## Report a Security Issue

See [SECURITY.md](SECURITY.md). Report vulnerabilities privately. Do not
open a public issue.

## Support

Community support is on the [ArmaOnUnix Discord](https://discord.gg/p28Ra36).