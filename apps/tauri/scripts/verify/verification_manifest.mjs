export const bundleDefinitions = {
  'verify:ci-typecheck': [
    bundle('verify:repo-governance'),
    npmScript('verify:migration-checksums'),
    npmScript('verify:updater-pubkey'),
    npmScript('verify:manual-gate-evidence'),
    bundle('verify:frontend-static-contracts'),
    npmScript('typecheck:mcp-tests'),
  ],
  'verify:frontend-static-contracts': [
    npmScript('verify:module-contract-matrix'),
    npmScript('verify:ui-wiring'),
    npmScript('verify:ipc-command-parity'),
    npmScript('verify:appselect-variant-contract'),
    npmScript('verify:theme-tokens'),
    npmScript('verify:design-tokens-completeness'),
    npmScript('verify:utility-completeness'),
    npmScript('verify:event-color-consistency'),
    npmScript('verify:motion-reduce-redundancy'),
    npmScript('verify:focus-ring-consistency'),
    npmScript('verify:markdown-prose-logical-css'),
    npmScript('verify:query-key-factory-contract'),
  ],
  'verify:repo-governance': [
    npmScript('verify:docs-index'),
    npmScript('verify:mcp-tools'),
    npmScript('verify:repo-facts'),
    npmScript('verify:repo-facts-prose'),
    npmScript('verify:docs-governance'),
    npmScript('verify:verification-matrix'),
    npmScript('verify:issue-lifecycle-evidence', { args: ['--', '--recent-closed', '5'] }),
    npmScript('verify:open-issue-lifecycle'),
    npmScript('verify:markdown-links'),
    npmScript('verify:contact-mail-absence'),
    npmScript('verify:manual-gate-templates'),
    npmScript('verify:manual-gate-smoke-metadata'),
    npmScript('verify:dev-session-preflight'),
    npmScript('verify:desktop-channel'),
    npmScript('verify:platform-csp-inheritance'),
    npmScript('verify:tauri-per-target-conf-parity'),
    npmScript('verify:platform-capability-contract'),
    npmScript('verify:platform-governance-contract'),
    npmScript('verify:platform-capability-matrix-contract'),
    npmScript('verify:sync-transport-abstraction-contract'),
    npmScript('verify:sync-transport-profile-contract'),
    npmScript('verify:sync-transport-manual-runner-contract'),
    npmScript('verify:sync-filesystem-bridge-cursor-contract'),
    npmScript('verify:mobile-sync-cadence-contract'),
    npmScript('verify:android-scaffold'),
    npmScript('verify:android-typography-contract'),
    npmScript('verify:android-background-reliability-contract'),
    npmScript('verify:popover-settings-feedback-contract'),
    npmScript('verify:desktop-aux-window-contract'),
    npmScript('verify:windows-copy-contract'),
    npmScript('verify:windows-typography-contract'),
    npmScript('verify:cargo-lockfile-integrity'),
    npmScript('verify:cargo-deps-aligned'),
    npmScript('verify:syncable-types-inventory'),
    npmScript('verify:shared-paths-parity'),
    npmScript('verify:validation-mirror-parity'),
    npmScript('verify:readme-cli-subcommands'),
    npmScript('verify:rust-fmt'),
    npmScript('verify:cargo-dead-code'),
    npmScript('verify:cargo-machete'),
    npmScript('verify:rust-too-many-arguments-budget'),
    npmScript('verify:knip-budget'),
    npmScript('verify:shellcheck'),
    npmScript('verify:audit-marker-count'),
    npmScript('verify:day-context-math'),
    npmScript('verify:i18n'),
    npmScript('verify:locale-types'),
    npmScript('verify:i18n-source-keys'),
    npmScript('typecheck', { workspace: 'app' }),
    npmScript('lint', { workspace: 'app' }),
    npmScript('lint:tailwind', { workspace: 'app' }),
    npmScript('test:contract-verifiers'),
    npmScript('test:runtime:logic'),
  ],
};

export const releasePreflightGates = [
  npmScript('verify:ci-typecheck'),
  npmScript('test:unit', { workspace: 'app' }),
  npmScript('test:e2e:smoke', { workspace: 'app' }),
  npmScript('test:e2e:visual', { workspace: 'app' }),
  npmScript('test:mcp:integration'),
  npmScript('test:mcp:migrations', { label: 'test:mcp:migrations' }),
  cargoGate('cargo check (mcp-server)', ['check', '--manifest-path', 'mcp-server/Cargo.toml']),
  cargoGate('cargo clippy (mcp-server) -- -D warnings', [
    'clippy',
    '--manifest-path',
    'mcp-server/Cargo.toml',
    '--',
    '-D',
    'warnings',
  ]),
  cargoGate('cargo test (mcp-server)', ['test', '--manifest-path', 'mcp-server/Cargo.toml']),
  npmScript('prepare:mcp', { workspace: 'app', args: ['--', '--debug'] }),
  npmScript('verify:mcp-runtime-bundle'),
  // `--all-targets` covers tests + examples + benches; without it, a test-only
  // compile breakage (e.g. test fixtures still using struct-literal init for a
  // field that was sealed `pub(crate)` in a workspace crate) compiles clean
  // here but breaks `cargo test` and downstream `cargo build` for DMG. #3298.
  cargoGate('cargo check (app/src-tauri) --all-targets', [
    'check',
    '--manifest-path',
    'app/src-tauri/Cargo.toml',
    '--all-targets',
  ]),
  cargoGate('cargo clippy (app/src-tauri) --all-targets -- -D warnings', [
    'clippy',
    '--manifest-path',
    'app/src-tauri/Cargo.toml',
    '--all-targets',
    '--',
    '-D',
    'warnings',
  ]),
  cargoGate('cargo test (app/src-tauri)', ['test', '--manifest-path', 'app/src-tauri/Cargo.toml']),
  cargoGate('cargo check -p lorvex-cli', ['check', '-p', 'lorvex-cli']),
  cargoGate('cargo clippy -p lorvex-cli -- -D warnings', ['clippy', '-p', 'lorvex-cli', '--', '-D', 'warnings']),
  cargoGate('cargo test -p lorvex-cli', ['test', '-p', 'lorvex-cli']),
  cargoGate('cargo test -p lorvex-runtime', ['test', '-p', 'lorvex-runtime']),
  cargoGate('cargo test -p lorvex-domain', ['test', '-p', 'lorvex-domain']),
  cargoGate('cargo test -p lorvex-store', ['test', '-p', 'lorvex-store']),
  cargoGate('cargo test -p lorvex-workflow', ['test', '-p', 'lorvex-workflow']),
  cargoGate('cargo test -p lorvex-sync', ['test', '-p', 'lorvex-sync']),
  cargoGate('cargo test -p lorvex-mcp-derive', ['test', '-p', 'lorvex-mcp-derive']),
  cargoGate('cargo clippy --workspace --all-targets -- -D warnings', [
    'clippy',
    '--workspace',
    '--all-targets',
    '--',
    '-D',
    'warnings',
  ]),
  cargoGate('cargo test --workspace', ['test', '--workspace']),
];

export const releaseBuildGates = [
  shellGate('CLI release build', ['bash', 'scripts/build_cli.sh']),
  shellGate('DMG build smoke', ['bash', 'scripts/build_dmg.sh']),
];

export const verificationDocs = {
  contributing: [
    section('Default CI TypeScript/static gate', [npmScript('verify:ci-typecheck')]),
    section('Frontend unit tests (CI gate)', [npmScript('test:unit', { workspace: 'app' })]),
    section('Playwright smoke (CI gate; local for UI changes)', [
      npmScript('test:e2e:smoke', { workspace: 'app' }),
    ]),
    section('Playwright visual regression (blocking CI/release gate; pinned Linux snapshots)', [
      npmScript('test:e2e:visual', { workspace: 'app' }),
    ]),
    section('MCP integration harness (full/local runtime coverage)', [npmScript('test:mcp:integration')]),
    section('MCP runtime Rust coverage', [
      npmScript('test:mcp:migrations'),
      cargoDoc(['check', '--manifest-path', 'mcp-server/Cargo.toml']),
      cargoDoc(['clippy', '--manifest-path', 'mcp-server/Cargo.toml', '--', '-D', 'warnings']),
      cargoDoc(['test', '--manifest-path', 'mcp-server/Cargo.toml']),
    ]),
    section('Prepared MCP runtime bundle (only when packaging/staged binary paths change)', [
      npmScript('prepare:mcp', { workspace: 'app', args: ['--', '--debug'] }),
      npmScript('verify:mcp-runtime-bundle'),
    ]),
    section('Rust (desktop app)', [
      // `--all-targets` covers tests + examples + benches so a test-only
      // compile breakage (sealed-field struct-literal regression class —
      // see #3298) is caught by the same boundary CI runs.
      cargoDoc(['check', '--manifest-path', 'app/src-tauri/Cargo.toml', '--all-targets']),
      cargoDoc([
        'clippy',
        '--manifest-path',
        'app/src-tauri/Cargo.toml',
        '--all-targets',
        '--',
        '-D',
        'warnings',
      ]),
      cargoDoc(['test', '--manifest-path', 'app/src-tauri/Cargo.toml']),
    ]),
    section('Rust (CLI + shared crates)', [
      cargoDoc(['check', '-p', 'lorvex-cli']),
      cargoDoc(['clippy', '-p', 'lorvex-cli', '--', '-D', 'warnings']),
      cargoDoc(['test', '-p', 'lorvex-cli']),
      cargoDoc(['test', '-p', 'lorvex-runtime']),
      cargoDoc(['test', '-p', 'lorvex-domain']),
      cargoDoc(['test', '-p', 'lorvex-store']),
      cargoDoc(['test', '-p', 'lorvex-workflow']),
      cargoDoc(['test', '-p', 'lorvex-sync']),
      cargoDoc(['test', '-p', 'lorvex-mcp-derive']),
    ]),
    section('Full workspace (recommended before milestones)', [
      cargoDoc(['clippy', '--workspace', '--all-targets', '--', '-D', 'warnings']),
      cargoDoc(['test', '--workspace']),
    ]),
  ],
  readme: [
    npmScript('verify:ci-typecheck'),
    cargoDoc(['check', '--manifest-path', 'app/src-tauri/Cargo.toml', '--all-targets'], { plainCargo: true }),
    cargoDoc(['clippy', '--manifest-path', 'app/src-tauri/Cargo.toml', '--all-targets', '--', '-D', 'warnings'], { plainCargo: true }),
    cargoDoc(['test', '--manifest-path', 'app/src-tauri/Cargo.toml', '--lib'], { plainCargo: true }),
    cargoDoc(['check', '--manifest-path', 'mcp-server/Cargo.toml'], { plainCargo: true }),
    cargoDoc(['clippy', '--manifest-path', 'mcp-server/Cargo.toml', '--', '-D', 'warnings'], { plainCargo: true }),
    cargoDoc(['test', '--manifest-path', 'mcp-server/Cargo.toml', '--lib'], { plainCargo: true }),
    cargoDoc(['clippy', '--workspace', '--all-targets', '--', '-D', 'warnings'], { plainCargo: true }),
    cargoDoc(['test', '--workspace', '--lib'], { plainCargo: true }),
  ],
  contributingPr: [
    npmScript('verify:ci-typecheck'),
    npmScript('test:unit', { workspace: 'app' }),
    npmScript('test:e2e:smoke', { workspace: 'app' }),
    npmScript('test:e2e:visual', { workspace: 'app' }),
    npmScript('test:mcp:migrations'),
    npmScript('test:mcp:integration'),
    npmScript('prepare:mcp', { workspace: 'app', args: ['--', '--debug'] }),
    npmScript('verify:mcp-runtime-bundle'),
    cargoDoc(['check', '--manifest-path', 'mcp-server/Cargo.toml']),
    cargoDoc(['clippy', '--manifest-path', 'mcp-server/Cargo.toml', '--', '-D', 'warnings']),
    cargoDoc(['test', '--manifest-path', 'mcp-server/Cargo.toml']),
    cargoDoc(['check', '--manifest-path', 'app/src-tauri/Cargo.toml', '--all-targets']),
    cargoDoc([
      'clippy',
      '--manifest-path',
      'app/src-tauri/Cargo.toml',
      '--all-targets',
      '--',
      '-D',
      'warnings',
    ]),
    cargoDoc(['test', '--manifest-path', 'app/src-tauri/Cargo.toml']),
  ],
};

export function flattenBundle(bundleName, stack = []) {
  if (stack.includes(bundleName)) {
    throw new Error(`verification bundle cycle detected: ${[...stack, bundleName].join(' -> ')}`);
  }
  const entries = bundleDefinitions[bundleName];
  if (!entries) {
    throw new Error(`unknown verification bundle: ${bundleName}`);
  }

  return entries.flatMap((entry) => (entry.kind === 'bundle' ? flattenBundle(entry.name, [...stack, bundleName]) : [entry]));
}

export function displayCommand(entry) {
  switch (entry.kind) {
    case 'bundle':
      return `npm run ${entry.name}`;
    case 'npm':
      return [
        'npm',
        'run',
        ...(entry.workspace ? ['-w', entry.workspace] : []),
        entry.script,
        ...(entry.args ?? []),
      ].join(' ');
    case 'cargo':
      return `${entry.plainCargo ? 'cargo' : '~/.cargo/bin/cargo'} ${entry.args.join(' ')}`;
    case 'shell':
      return entry.command.join(' ');
    default:
      throw new Error(`unsupported verification manifest entry: ${entry.kind}`);
  }
}

export function displayLabel(entry) {
  return entry.label ?? displayCommand(entry);
}

function bundle(name) {
  return { kind: 'bundle', name };
}

function npmScript(script, options = {}) {
  return {
    kind: 'npm',
    script,
    ...(options.workspace ? { workspace: options.workspace } : {}),
    ...(options.args ? { args: options.args } : {}),
    ...(options.label ? { label: options.label } : {}),
  };
}

function cargoGate(label, args) {
  return { kind: 'cargo', label, args };
}

function cargoDoc(args, options = {}) {
  return { kind: 'cargo', args, ...(options.plainCargo ? { plainCargo: true } : {}) };
}

function shellGate(label, command) {
  return { kind: 'shell', label, command };
}

function section(title, commands) {
  return { title, commands };
}
