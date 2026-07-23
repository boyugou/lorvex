# AI Surfaces Naming

## Scope

This document defines naming for:

- App
- CLI
- MCP
- TUI
- host vs surface
- authority vs owner
- embedded MCP vs external MCP

## Current State In Code

Observed in:

- `app/src-tauri/src/mcp_runtime.rs`
- `lorvex-runtime/src/mcp_authority.rs`
- `lorvex-runtime/src/capabilities/mod.rs`
- `lorvex-cli/src/commands/mcp/`
- `lorvex-cli/src/commands/setup/`
- `docs/setup/ASSISTANT_MCP_SETUP.md`
- `docs/design/MULTI_SURFACE_ARCHITECTURE.md`

Current repo reality:

- App can host an embedded/bundled MCP runtime
- CLI can host MCP via `lorvex mcp serve`
- runtime now has a persisted `mcp_host_authority` table
- capability profiles distinguish:
  - `DesktopApp`
  - `DesktopCliAgent`
  - `DesktopCliTui`
  - `MobilePeer`

The codebase is already treating App and CLI as different hosts, with multiple surfaces under them.

## Current State vs Target State

### Current State

The current repo is in a transitional but coherent state:

- the **App** can act as an MCP host through a bundled helper/runtime path
- the **CLI** can act as an MCP host through `lorvex mcp serve`
- `mcp_host_authority` now exists as shared runtime coordination state
- setup docs and product wording still reflect both older App-binary language and newer CLI-hosted language

Concretely, there are two real MCP host shapes in the codebase today:

- **App-hosted embedded MCP**
  - resolved by `app/src-tauri/src/mcp_runtime.rs`
  - currently framed around a bundled `lorvex-mcp-server` helper binary
- **CLI-hosted MCP**
  - exposed by `lorvex mcp serve`
  - configured by CLI setup/install commands

This means the system is no longer deciding between "App or CLI exists". Both can exist, and the main consistency question is which one should be considered the active external host.

### Target State

The target model is stricter:

- exactly one **active external MCP host**
- App and CLI may both be installed
- both may share the same DB and local runtime state
- but only one is exposed to external agents at a time

The intended product behavior is:

- **App-only installation**
  - App remains a complete product
  - embedded MCP works without requiring CLI
- **CLI-only installation**
  - CLI is the MCP host
- **App + CLI installation**
  - CLI is the recommended external host
  - App remains available as GUI host and platform-capability host

This target state does not require deleting the App-hosted MCP capability. It requires making host authority explicit and consistent.

## Canonical Distinctions

### Host

A host is a runtime container that can provide a surface.

Canonical hosts:

- `App host`
- `CLI host`

### Surface

A surface is an operator-facing interaction mode.

Canonical surfaces:

- `GUI surface`
- `MCP surface`
- `TUI surface`
- `shell command surface`

### Authority

Authority answers:

- which host should be the canonical external MCP endpoint

Canonical runtime term:

- `mcp_host_authority`

### Owner

Owner answers:

- which runtime currently holds a background sync lease

Canonical runtime term:

- `sync_owner`

These must not be conflated.

## Product Terms

### Lorvex App

Preferred product meaning:

- human-primary GUI product
- can host embedded MCP
- on Apple platforms, owns privileged calendar/cloud capabilities

### Lorvex CLI

Preferred product meaning:

- always-on agent runtime
- non-GUI DB + MCP tool host
- can also expose TUI and shell commands

### MCP

Preferred meaning:

- the agent/operator surface
- not the same thing as the CLI as a whole

### TUI

Preferred meaning:

- a secondary inspection surface within CLI
- not the primary identity of CLI

## Embedded MCP vs External MCP

The repo currently supports both:

- App-hosted embedded MCP
- CLI-hosted external MCP

These should be named explicitly.

Use:

- `embedded MCP`
- `external MCP host`

Do not blur them together as just:

- `the MCP server`

because product behavior differs depending on which host is active.

## Active External MCP Naming

Final naming rule:

- external agents should see exactly one active Lorvex MCP endpoint
- that choice is governed by `mcp_host_authority`

Recommended user-facing wording:

- `Active MCP Host`
- `Current MCP Host`

Recommended operator/runtime wording:

- `mcp_host_authority`

Avoid:

- `default MCP`
- `preferred server`
- `selected endpoint`

unless used as explanatory copy over the canonical term

## App Embedded MCP vs CLI-Hosted MCP

This distinction should now be treated as first-class.

### App Embedded MCP

Use this term when referring to:

- the App's bundled MCP helper/runtime
- especially for MAS users
- especially in App settings, diagnostics, and setup flows

Recommended wording:

- `embedded MCP`
- `App MCP host`

Avoid:

- presenting this as the only Lorvex MCP shape

### CLI-Hosted MCP

Use this term when referring to:

- `lorvex mcp serve`
- Homebrew / direct-install runtime
- always-on agent workflows

Recommended wording:

- `CLI-hosted MCP`
- `CLI MCP host`

Avoid:

- pretending it is just another alias of the embedded helper binary

## Consistency Rules

### Setup docs

Setup docs must always distinguish:

- which host is being configured
- whether the config points to:
  - bundled App helper binary
  - or `lorvex mcp serve`
- whether authority is App or CLI

### Settings and diagnostics

Settings should display:

- `Active MCP Host`
- `Recommended MCP Host`
- install state of CLI
- whether App embedded MCP is available

### Product language

Use:

- `Lorvex App`
- `Lorvex CLI`
- `embedded MCP`
- `CLI-hosted MCP`
- `Active MCP Host`

Avoid:

- saying "the MCP server" when host identity matters
- implying that App and CLI are just two spellings for the same runtime path

## Capability Profile Naming

Current code uses:

- `DesktopApp`
- `DesktopCliAgent`
- `DesktopCliTui`
- `MobilePeer`

These are good canonical operator/runtime profile names and should stay.

Use them in:

- runtime code
- diagnostics
- architecture docs

Do not leak them directly into UI unless there is a strong reason.

## Setup Copy Rule

Because the repo currently contains both:

- `lorvex-mcp-server`
- `lorvex mcp serve`

all future setup docs must distinguish:

- App embedded MCP path
- CLI MCP path
- active external MCP host

Do not use one generic setup narrative that hides the host distinction.

## Final Decision

Use this naming model:

- `App` and `CLI` are hosts
- `GUI`, `MCP`, `TUI`, and shell commands are surfaces
- `mcp_host_authority` decides the active external MCP endpoint
- `sync_owner` decides the active background sync lease holder
- `embedded MCP` and `external MCP host` are distinct concepts
- current code supports both App-hosted and CLI-hosted MCP
- the target product model is one active external MCP host with explicit authority
