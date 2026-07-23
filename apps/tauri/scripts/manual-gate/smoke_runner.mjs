#!/usr/bin/env node

import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const MAX_LOG_LINES = 80;

const STEPS = [
  {
    id: 'docs.templates',
    gate_refs: ['mcp-e2e', 'ui-regression', 'sync-recovery'],
    description: 'Manual-gate template contracts stay valid',
    command: 'npm run verify:manual-gate-templates',
  },
  {
    id: 'docs.evidence',
    gate_refs: ['mcp-e2e', 'ui-regression', 'sync-recovery'],
    description: 'Manual-gate evidence schema + freshness contract check',
    command: 'npm run verify:manual-gate-evidence',
  },
  {
    id: 'mcp.integration',
    gate_refs: ['mcp-e2e'],
    description: 'Single-client MCP protocol + behavior smoke',
    command: 'npm run test:mcp:integration',
  },
  {
    id: 'mcp.scale_budget',
    gate_refs: ['mcp-e2e'],
    description: 'MCP bounded payload + latency budget smoke at 1k/10k',
    command: 'npm run benchmark:mcp:scale -- --dataset=1000,10000',
  },
  {
    id: 'ui.wiring',
    gate_refs: ['ui-regression'],
    description: 'Menu/settings wiring contract static guard',
    command: 'npm run verify:ui-wiring',
  },
  {
    id: 'ui.module_matrix',
    gate_refs: ['ui-regression'],
    description: 'Sidebar/settings module contract matrix guard',
    command: 'npm run verify:module-contract-matrix',
  },
  {
    id: 'ui.typescript',
    gate_refs: ['ui-regression'],
    description: 'Settings/menu code path typecheck smoke',
    command: 'cd app && npx tsc --noEmit',
  },
  {
    id: 'ui.desktop_aux_window_contract',
    gate_refs: ['ui-regression', 'desktop-aux-window'],
    description: 'Desktop auxiliary-window fullscreen/cross-space contract guard',
    command: 'npm run verify:desktop-aux-window-contract',
  },
  {
    id: 'sync.replay',
    gate_refs: ['sync-recovery'],
    description: 'Deterministic sync replay/LWW/idempotency test slice',
    command: 'cd app/src-tauri && cargo test sync::remote_apply',
  },
  {
    id: 'sync.retry',
    gate_refs: ['sync-recovery'],
    description: 'Sync retry + mark-synced deterministic behavior slice',
    command: 'cd app/src-tauri && cargo test mark_sync_',
  },
  {
    id: 'dock.state_machine',
    gate_refs: ['desktop-aux-window'],
    description: 'Dock/window restore single-flight state machine guard',
    command: 'cd app/src-tauri && cargo test window_restore_single_flight_and_pending_replay_state_machine',
  },
];

const COVERAGE_MAP = {
  'mcp-e2e': {
    automated: [
      'docs.templates',
      'docs.evidence',
      'mcp.integration',
      'mcp.scale_budget',
    ],
    manual_only: [
      'Cross-client real operator execution across Claude Desktop + Claude Code + Codex.',
      'Prompt-level workflow UX judgment (WF-1..WF-5) and transcript quality.',
      'Screenshot evidence of UI state transitions after workflow execution.',
    ],
  },
  'ui-regression': {
    automated: [
      'ui.wiring',
      'ui.module_matrix',
      'ui.typescript',
      'ui.desktop_aux_window_contract',
      'dock.state_machine',
    ],
    manual_only: [
      'Tray popover visual/interaction behavior on real macOS menu bar surfaces.',
      'Retina/light/dark icon legibility and visual polish checks.',
      'Settings tactile UX checks (scroll feel, immediate control feedback) in signed builds.',
    ],
  },
  'sync-recovery': {
    automated: [
      'docs.templates',
      'docs.evidence',
      'sync.replay',
      'sync.retry',
    ],
    manual_only: [
      'Real filesystem/provider hydration/permission failure handling on operator machine.',
      'Recovery runbook actions requiring Settings UI intervention and manual sync retries.',
      'Post-recovery verification of user-intended final state across devices.',
    ],
  },
  'desktop-aux-window': {
    automated: [
      'ui.desktop_aux_window_contract',
      'dock.state_machine',
    ],
    manual_only: [
      'End-user Dock click behavior across macOS version/display/space/fullscreen permutations.',
      'Intermittent runtime reproduction requiring repeated physical interaction loops.',
      'Visual/frontmost focus confirmation that cannot be asserted from unit tests alone.',
    ],
  },
};

function fail(message) {
  console.error(`[manual_gate_smoke] ERROR: ${message}`);
  process.exit(1);
}

// `STEPS[]` and `COVERAGE_MAP` are tightly coupled but defined as two
// independent literals — every `STEPS[i].gate_refs` value should appear
// as a `COVERAGE_MAP` key, and every `COVERAGE_MAP[gate].automated`
// entry should reference a real `STEPS[i].id`. Pre-fix the two views
// could drift silently: a step rename or removal would leave the
// other half pointing at a non-existent id, and the report
// generator would happily emit a section listing dead step IDs.
// Validate fail-fast at module load (audit-pass-docs-finding-7).
(function assertStepsCoverageIntegrity() {
  const stepIds = new Set(STEPS.map((s) => s.id));
  const dangling = [];
  for (const [issue, entry] of Object.entries(COVERAGE_MAP)) {
    for (const automatedId of entry.automated) {
      if (!stepIds.has(automatedId)) {
        dangling.push(`COVERAGE_MAP[${issue}].automated references unknown step '${automatedId}'`);
      }
    }
  }
  for (const step of STEPS) {
    for (const gateRef of step.gate_refs) {
      if (!Object.prototype.hasOwnProperty.call(COVERAGE_MAP, gateRef)) {
        dangling.push(`STEPS[${step.id}].gate_refs references unknown COVERAGE_MAP key '${gateRef}'`);
      }
    }
  }
  if (dangling.length > 0) {
    console.error('[manual_gate_smoke] STEPS / COVERAGE_MAP integrity check FAILED:');
    for (const message of dangling) {
      console.error(`  - ${message}`);
    }
    process.exit(1);
  }
})();

function toPosix(relativePath) {
  return relativePath.split(path.sep).join('/');
}

function tailLines(value, maxLines = MAX_LOG_LINES) {
  const normalized = value.replace(/\r\n/g, '\n');
  const lines = normalized.split('\n');
  if (lines.length <= maxLines) return normalized.trim();
  return lines.slice(lines.length - maxLines).join('\n').trim();
}

function parseArgs(argv) {
  const options = {
    metadataOnly: false,
    outDir: 'artifacts/manual-gate-smoke',
  };

  for (let index = 0; index < argv.length; index += 1) {
    const token = argv[index];
    if (token === '--metadata-only') {
      options.metadataOnly = true;
      continue;
    }
    if (token === '--out-dir') {
      const value = argv[index + 1];
      if (!value || value.startsWith('--')) {
        fail('Missing value for --out-dir');
      }
      options.outDir = value;
      index += 1;
      continue;
    }
    fail(`Unknown argument: ${token}`);
  }

  return options;
}

function runStep(step, repoRoot) {
  const startedAt = new Date();
  const startedMs = Date.now();

  const result = spawnSync(step.command, {
    cwd: repoRoot,
    shell: true,
    encoding: 'utf8',
    maxBuffer: 1024 * 1024 * 16,
  });

  const finishedAt = new Date();
  const elapsedMs = Date.now() - startedMs;
  const stdout = result.stdout ?? '';
  const stderr = result.stderr ?? '';
  const status = result.status === 0 ? 'PASS' : 'FAIL';

  return {
    id: step.id,
    gate_refs: step.gate_refs,
    description: step.description,
    command: step.command,
    status,
    exit_code: result.status,
    signal: result.signal ?? null,
    started_at: startedAt.toISOString(),
    finished_at: finishedAt.toISOString(),
    elapsed_ms: elapsedMs,
    stdout_tail: tailLines(stdout),
    stderr_tail: tailLines(stderr),
    stdout_line_count: stdout === '' ? 0 : stdout.replace(/\r\n/g, '\n').split('\n').length,
    stderr_line_count: stderr === '' ? 0 : stderr.replace(/\r\n/g, '\n').split('\n').length,
  };
}

function renderMarkdown(report) {
  const lines = [];
  lines.push('# Manual Gate Smoke Runner Report');
  lines.push('');
  lines.push(`- Generated at (UTC): ${report.generated_at}`);
  lines.push(`- Overall: **${report.overall_status}**`);
  lines.push(`- Steps: ${report.passed_steps}/${report.total_steps} passed`);
  lines.push(`- Host: ${report.host.platform} ${report.host.release} (${report.host.arch})`);
  lines.push(`- Node: ${report.host.node}`);
  lines.push('');
  lines.push('## Step Summary');
  lines.push('');
  lines.push('| Step | Gate refs | Status | Duration (ms) |');
  lines.push('|---|---|---|---:|');
  for (const step of report.steps) {
    lines.push(`| \`${step.id}\` | ${step.gate_refs.map((gateRef) => `\`${gateRef}\``).join(', ')} | ${step.status} | ${step.elapsed_ms} |`);
  }
  lines.push('');
  lines.push('## Coverage Map');
  lines.push('');

  for (const gateRef of Object.keys(report.coverage_map).sort((a, b) => a.localeCompare(b))) {
    const coverage = report.coverage_map[gateRef];
    lines.push(`### \`${gateRef}\``);
    lines.push('');
    lines.push('Automated subset:');
    for (const stepId of coverage.automated) {
      lines.push(`- \`${stepId}\``);
    }
    lines.push('');
    lines.push('Manual-only checks (with rationale):');
    for (const reason of coverage.manual_only) {
      lines.push(`- ${reason}`);
    }
    lines.push('');
  }

  lines.push('## Failures');
  lines.push('');
  const failed = report.steps.filter((step) => step.status !== 'PASS');
  if (failed.length === 0) {
    lines.push('- none');
    lines.push('');
    return lines.join('\n');
  }

  for (const step of failed) {
    lines.push(`### \`${step.id}\``);
    lines.push('');
    lines.push(`- Command: \`${step.command}\``);
    lines.push(`- Exit code: ${step.exit_code}`);
    if (step.signal) {
      lines.push(`- Signal: ${step.signal}`);
    }
    lines.push('');
    if (step.stdout_tail) {
      lines.push('`stdout` tail:');
      lines.push('```text');
      lines.push(step.stdout_tail);
      lines.push('```');
      lines.push('');
    }
    if (step.stderr_tail) {
      lines.push('`stderr` tail:');
      lines.push('```text');
      lines.push(step.stderr_tail);
      lines.push('```');
      lines.push('');
    }
  }

  return lines.join('\n');
}

const scriptPath = fileURLToPath(import.meta.url);
const repoRoot = path.resolve(path.dirname(scriptPath), '..', '..');
const { metadataOnly, outDir } = parseArgs(process.argv.slice(2));
const outDirAbs = path.resolve(repoRoot, outDir);

if (outDirAbs !== repoRoot && !outDirAbs.startsWith(`${repoRoot}${path.sep}`)) {
  fail('Output directory must stay inside this repository');
}

fs.mkdirSync(outDirAbs, { recursive: true });

const steps = [];
for (const step of STEPS) {
  if (metadataOnly) {
    steps.push({
      id: step.id,
      gate_refs: step.gate_refs,
      description: step.description,
      command: step.command,
      status: 'PASS',
      exit_code: null,
      signal: null,
      started_at: new Date(0).toISOString(),
      finished_at: new Date(0).toISOString(),
      elapsed_ms: 0,
      stdout_tail: 'metadata-only: command not executed',
      stderr_tail: '',
      stdout_line_count: 1,
      stderr_line_count: 0,
    });
    continue;
  }
  console.log(`[manual_gate_smoke] RUN ${step.id}: ${step.command}`);
  const result = runStep(step, repoRoot);
  steps.push(result);
  console.log(`[manual_gate_smoke] ${result.status} ${step.id} (${result.elapsed_ms}ms)`);
}

const passedSteps = steps.filter((step) => step.status === 'PASS').length;
const report = {
  generated_at: new Date().toISOString(),
  repo_root: repoRoot,
  total_steps: steps.length,
  passed_steps: passedSteps,
  failed_steps: steps.length - passedSteps,
  overall_status: passedSteps === steps.length ? 'PASS' : 'FAIL',
  host: {
    node: process.version,
    platform: process.platform,
    release: os.release(),
    arch: process.arch,
  },
  steps,
  coverage_map: COVERAGE_MAP,
};

const timestamp = report.generated_at
  .replace(/:/g, '')
  .replace(/\.\d{3}Z$/, 'Z');
const jsonPath = path.join(outDirAbs, `manual-gate-smoke-${timestamp}.json`);
const mdPath = path.join(outDirAbs, `manual-gate-smoke-${timestamp}.md`);
const latestJsonPath = path.join(outDirAbs, 'manual-gate-smoke-latest.json');
const latestMdPath = path.join(outDirAbs, 'manual-gate-smoke-latest.md');

const jsonText = `${JSON.stringify(report, null, 2)}\n`;
const markdownText = `${renderMarkdown(report)}\n`;

fs.writeFileSync(jsonPath, jsonText, 'utf8');
fs.writeFileSync(mdPath, markdownText, 'utf8');
fs.writeFileSync(latestJsonPath, jsonText, 'utf8');
fs.writeFileSync(latestMdPath, markdownText, 'utf8');

console.log(`[manual_gate_smoke] Report JSON: ${toPosix(path.relative(repoRoot, jsonPath))}`);
console.log(`[manual_gate_smoke] Report MD: ${toPosix(path.relative(repoRoot, mdPath))}`);
console.log(`[manual_gate_smoke] Latest JSON: ${toPosix(path.relative(repoRoot, latestJsonPath))}`);
console.log(`[manual_gate_smoke] Latest MD: ${toPosix(path.relative(repoRoot, latestMdPath))}`);

if (report.overall_status !== 'PASS') {
  process.exitCode = 1;
}
