# Security Policy

## Reporting a Vulnerability

If you discover a security vulnerability in Lorvex, please report it responsibly:

**Report channel:** open a [private security advisory on GitHub](https://github.com/boyugou/ai-native-todo/security/advisories/new). This is the only reporting path — Lorvex has no security email mailbox.

**Please include:**
- Description of the vulnerability
- Steps to reproduce
- Potential impact
- Suggested fix (if any)

**Do NOT:**
- Open a public issue for security vulnerabilities
- Exploit the vulnerability beyond what's needed to demonstrate it

## Response Timeline

- **Acknowledgment:** Within 48 hours
- **Initial assessment:** Within 1 week
- **Fix or mitigation:** Depends on severity; critical issues are prioritized

## Scope

### In scope
- The Lorvex desktop application (Tauri + React)
- The MCP server binary (`lorvex-mcp-server`)
- The SQLite database layer and migration system
- Filesystem-bridge sync implementation
- Build and release infrastructure (GitHub Actions workflows)

### Out of scope
- Third-party MCP clients (Claude Desktop, etc.)
- Issues in upstream dependencies (report to the dependency maintainer)
- Denial of service against local-only resources

## Security Model

Lorvex is a **local-first** application:

- **All data is stored locally** in a SQLite database on the user's machine
- **No Lorvex cloud servers** — the Tauri app does not phone home. The current
  Tauri line has no active cloud sync transport; export/import is the supported
  backup and transfer path until a future provider-neutral sync provider exists.
- **MCP server uses stdio transport** — the security boundary is the OS process boundary. Any process on the local machine that can spawn the MCP binary has full database access. This is the standard MCP security model.
- **No authentication on MCP** — by design; the OS provides process isolation
- **No Tauri iCloud/CloudKit path** — Apple ecosystem sync and App Store
  distribution belong to the Swift app under `apps/apple`, not this Tauri line.

## Supported Versions

Lorvex does not yet have a stable public support line. Security fixes land on
the main branch and the latest published pre-release channel until a stable
public release policy exists.

| Version / channel | Supported |
|-------------------|-----------|
| Main branch and latest published pre-release | Yes |
| Older pre-release or test tags | No |
| Stable `1.0.x` | Not yet public |
