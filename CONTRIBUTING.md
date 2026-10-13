# Contributing to Lorvex

Thank you for looking. The full guide, with the build and test commands, the module
layout, how to add an MCP tool, and the commit style, is
[`apps/apple/docs/CONTRIBUTING.md`](apps/apple/docs/CONTRIBUTING.md). The short version:

- **Pure Swift.** The app and its core are Swift packages under `apps/apple`; there is no
  second implementation and no web runtime.
- **Build and test** from `apps/apple`: `./script/verify_swift.sh` (it compiles the string
  catalogs first, which a plain `swift test` does not), then `./script/verify_static_gates.sh`.
- **Read the philosophy first** if you are proposing a feature:
  [`docs/vision/DESIGN_PHILOSOPHY.md`](docs/vision/DESIGN_PHILOSOPHY.md) says what Lorvex
  leaves out on purpose.
- **Never commit** credentials, signing material, email addresses, or a developer machine's
  paths. Contact goes through the [lorvex.app](https://lorvex.app) support and privacy pages.
- **A security problem** goes to the private report form described in
  [`SECURITY.md`](SECURITY.md), not to a public issue.
