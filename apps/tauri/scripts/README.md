# Scripts Directory

`scripts/` is the home for maintainer-facing automation entrypoints and the
internal helpers those entrypoints call.

## Top-Level Files

Top-level files are commands a maintainer may run directly from the repository
root, such as build, install, update, and development preflight scripts:

- `build_*.sh` / `build_windows.ps1`
- `install_cli.sh`
- `update_and_install*`
- `dev_session_preflight.sh`

Prefer the canonical `npm run ...` command when one exists in `package.json`.

## Subdirectories

- `ci/` — GitHub Actions helper scripts.
- `fixtures/` — non-entrypoint fixture/data files, including
  `scripts/fixtures/seed.sql` and `scripts/fixtures/seed_scale.sql`.
- `generate/` — generated documentation and type artifact refreshers.
- `lib/` — shared verifier/support utilities.
- `lint/` — project-specific lint helpers.
- `manual-gate/` — local/manual validation report generation.
- `mcp/` — MCP runtime staging and verification helpers.
- `release/` — release preflight and manifest helpers.
- `tests/` — test wrappers and contract/runtime/MCP test harnesses.
- `verify/` — static verification gates wired through `package.json`.

Do not add new internal `.mjs` automation directly under `scripts/`; place it
in the focused subdirectory and expose it through `package.json` if it is a
maintainer-facing command.
