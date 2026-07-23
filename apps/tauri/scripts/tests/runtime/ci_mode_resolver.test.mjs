import { describe, it } from 'node:test';
import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';
import path from 'node:path';
import {
  parseChangedFiles,
  parsePrLabels,
  readPrChangedFiles,
  readPrLabels,
  resolveCiMode,
} from '../../ci/resolve_ci_mode.mjs';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..', '..');
const resolverPath = path.join(repoRoot, 'scripts', 'ci', 'resolve_ci_mode.mjs');

describe('resolveCiMode', () => {
  it('push -> full main gate', () => {
    const r = resolveCiMode({ event: 'push', dispatchFull: 'false', prLabels: [] });
    assert.equal(r.run_full, true);
    assert.equal(r.mode, 'full-main-push');
  });

  it('pull_request without ci:full -> fast', () => {
    const r = resolveCiMode({ event: 'pull_request', dispatchFull: 'false', prLabels: ['bug', 'enhancement'] });
    assert.equal(r.run_full, false);
    assert.equal(r.mode, 'fast-pr-default');
  });

  it('pull_request with ci:full -> full', () => {
    const r = resolveCiMode({ event: 'pull_request', dispatchFull: 'false', prLabels: ['ci:full', 'bug'] });
    assert.equal(r.run_full, true);
    assert.equal(r.mode, 'full-pr-label');
  });

  it('workflow_dispatch full=true -> full', () => {
    const r = resolveCiMode({ event: 'workflow_dispatch', dispatchFull: 'true', prLabels: [] });
    assert.equal(r.run_full, true);
    assert.equal(r.mode, 'full-manual-dispatch');
  });

  it('workflow_dispatch full=false -> fast', () => {
    const r = resolveCiMode({ event: 'workflow_dispatch', dispatchFull: 'false', prLabels: [] });
    assert.equal(r.run_full, false);
    assert.equal(r.mode, 'fast-manual-dispatch');
  });

  it('unknown event -> fast', () => {
    const r = resolveCiMode({ event: 'schedule', dispatchFull: 'false', prLabels: [] });
    assert.equal(r.run_full, false);
    assert.equal(r.mode, 'fast-unknown-event');
  });

  it('pull_request with empty labels -> fast', () => {
    const r = resolveCiMode({ event: 'pull_request', dispatchFull: 'false', prLabels: [] });
    assert.equal(r.run_full, false);
    assert.equal(r.mode, 'fast-pr-default');
  });

  for (const changedFile of [
    'app/src-tauri/src/commands/sync/cloudkit/runtime/push_pull.rs',
    'app/src-tauri/src/mcp_runtime.rs',
    'lorvex-sync/src/apply/envelope.rs',
    'mcp-server/src/server/startup.rs',
    'scripts/mcp/prepare_runtime.mjs',
    'scripts/tests/mcp/integration/task_lifecycle.ts',
  ]) {
    it(`pull_request touching ${changedFile} -> full`, () => {
      const r = resolveCiMode({
        event: 'pull_request',
        dispatchFull: 'false',
        prLabels: [],
        changedFiles: [changedFile, 'README.md'],
      });
      assert.equal(r.run_full, true);
      assert.equal(r.mode, 'full-pr-risky-path');
      assert.equal(r.reason, `risky-path:${changedFile}`);
    });
  }

  it('pull_request touching docs only -> fast', () => {
    const r = resolveCiMode({
      event: 'pull_request',
      dispatchFull: 'false',
      prLabels: [],
      changedFiles: ['docs/execution/CI_RELEASE_TRIGGER_POLICY.md', 'README.md'],
    });
    assert.equal(r.run_full, false);
    assert.equal(r.mode, 'fast-pr-default');
  });

  it('parses pull request labels from the configured environment variable', () => {
    const labels = readPrLabels({
      event: 'pull_request',
      labelsEnvName: 'PR_LABELS_JSON',
      env: { PR_LABELS_JSON: '["ci:full","bug"]' },
    });
    assert.deepEqual(labels, ['ci:full', 'bug']);
  });

  it('parses changed files from the configured environment variable', () => {
    const files = readPrChangedFiles({
      event: 'pull_request',
      changedFilesEnvName: 'PR_CHANGED_FILES',
      env: { PR_CHANGED_FILES: 'lorvex-sync/src/lib.rs\nREADME.md\n' },
    });
    assert.deepEqual(files, ['lorvex-sync/src/lib.rs', 'README.md']);
  });

  it('parses changed files from JSON arrays', () => {
    assert.deepEqual(parseChangedFiles('["mcp-server/src/main.rs","README.md"]', { event: 'pull_request' }), [
      'mcp-server/src/main.rs',
      'README.md',
    ]);
  });

  it('fails closed when pull request label JSON is malformed', () => {
    assert.throws(
      () => parsePrLabels('["ci:full"', { event: 'pull_request' }),
      /Failed to parse pull_request label JSON/,
    );
  });

  it('fails closed when pull request labels are not a string array', () => {
    assert.throws(
      () => parsePrLabels('{"name":"ci:full"}', { event: 'pull_request' }),
      /expected an array/,
    );
    assert.throws(
      () => parsePrLabels('["ci:full",42]', { event: 'pull_request' }),
      /expected every label name to be a string/,
    );
  });

  it('fails closed when configured pull request changed files are malformed JSON', () => {
    assert.throws(
      () => parseChangedFiles('["lorvex-sync/src/lib.rs"', { event: 'pull_request' }),
      /Failed to parse pull_request changed files/,
    );
  });

  it('CLI exits nonzero instead of silently selecting fast CI on malformed pull request labels', () => {
    const result = spawnSync(
      process.execPath,
      [
        resolverPath,
        '--event',
        'pull_request',
        '--dispatch-full',
        'false',
        '--pr-labels-env',
        'PR_LABELS_JSON',
        '--changed-files-env',
        'PR_CHANGED_FILES',
      ],
      {
        encoding: 'utf8',
        env: {
          ...process.env,
          PR_LABELS_JSON: '["ci:full"',
          PR_CHANGED_FILES: 'README.md',
        },
      },
    );

    assert.notEqual(result.status, 0);
    assert.match(result.stderr, /refusing to choose fast CI by default/);
    assert.equal(result.stdout.trim(), '');
  });
});
