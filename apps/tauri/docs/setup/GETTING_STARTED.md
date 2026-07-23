# Getting Started with Lorvex

This page is optimized for first-time users who just want Lorvex running fast.

Lorvex works in two strong modes:
- standalone app: capture, browse, plan, review, execute
- desktop + MCP: the best operator experience with AI-native automation

These are two product shapes of the same system, not a "real app vs secondary client" split.

## Fast path (recommended)

### Option A: Installed app (no source build)

Use this path only when you already have an internal or repo-visible package
for your OS. These packages are not a general public-download path; use Option
B when no package is available to you.

1. Install the Lorvex app package for your OS.
2. Open Lorvex → **Settings** → **Assistant MCP**.
3. Copy the generated config block for your MCP client.
4. Paste it into your MCP client config file.
5. Restart your MCP client.

Done. Lorvex serves MCP locally when the client launches it.

Reference: [ASSISTANT_MCP_SETUP.md](ASSISTANT_MCP_SETUP.md)

### Option B: Source checkout (dev/test users)

Prerequisites:
- macOS, Windows 10/11, or Linux
- Node.js 22+ (`engines: ">=22 <27"`)
- npm 10+
- Rust 1.86+ toolchain (`rustup`, `cargo`, `rustc`; MSRV pinned in `Cargo.toml`)
- Git

Clone + dependency install (first time only):

```bash
git clone https://github.com/boyugou/ai-native-todo.git lorvex
cd lorvex
npm ci
```

Development loop (default for source checkout):

```bash
npm run -w app tauri:dev
```

This launches Lorvex directly from your checkout. Use the one-click scripts only when you want local install smoke or packaging smoke from source.

Local install / packaging smoke (optional):

Windows (PowerShell):

```powershell
powershell -ExecutionPolicy Bypass -File .\scripts\update_and_install_windows.ps1 -Open
```

Linux:

```bash
bash scripts/update_and_install_linux.sh --install --open
```

macOS:

```bash
bash scripts/update_and_install.sh --open
```

What these scripts do:
- pull latest `main` (unless you pass `--no-pull` / `-NoPull`)
- build the app bundle
- install it on your machine
- optionally launch Lorvex

Canonical source-checkout development reference: [CONTRIBUTING.md](../../CONTRIBUTING.md)

## MCP connection check

In your MCP client, ask:

> Run `get_overview` and summarize the result.

If this returns real data, MCP wiring is healthy.

## Common commands

Windows script options:
- `-NoPull` skip `git pull`
- `-Bundle nsis|msi` choose installer type
- `-SilentInstall` silent mode (`nsis` or `msi`)
- `-Open` launch app after install

Linux script options:
- `--no-pull` skip `git pull`
- `--bundle deb|rpm|appimage` choose package type
- `--install` install after build
- `--open` launch app after build/install

macOS script options:
- `--no-pull` skip `git pull`
- `--open` launch app after install

## Troubleshooting

### Script says missing command

Install the missing prerequisite and rerun.

### MCP not connecting

1. Confirm config was copied from Lorvex Settings (not handwritten).
2. Use absolute paths in MCP config.
3. Restart MCP client after config updates.

### Linux package install asks for permissions

`--install` uses root privileges (sudo/root) for `deb`/`rpm` package installation.

### Windows build prerequisites

Install:
- Visual Studio C++ Build Tools (Desktop development with C++)
- WebView2 Runtime

### Linux build prerequisites (Tauri)

Ubuntu/Debian:

```bash
sudo apt-get update
sudo apt-get install -y \
  libwebkit2gtk-4.1-dev \
  libappindicator3-dev \
  librsvg2-dev \
  patchelf
```

## Data paths

- macOS: `~/Library/Application Support/Lorvex/db.sqlite`
- Windows: `%APPDATA%\\Lorvex\\db.sqlite`
- Linux: `${XDG_DATA_HOME:-~/.local/share}/Lorvex/db.sqlite`
