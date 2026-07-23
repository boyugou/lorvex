import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

test('read-only IPC wrappers do not emit mutation broadcasts', () => {
  // #3329: mutations.ts partitioned; getArchivedTasks lives in lifecycle.ts.
  const taskMutationsLifecycleSource = readFileSync(
    'app/src/lib/ipc/tasks/mutations/lifecycle.ts',
    'utf8',
  );
  const diagnosticsSource = readFileSync('app/src/lib/ipc/diagnostics.ts', 'utf8');

  assert.match(
    taskMutationsLifecycleSource,
    /export const getArchivedTasks = \([\s\S]*?\): Promise<ArchivedTasksResult> =>\s*\n\s*invoke\('get_archived_tasks', args, signal\);/,
    'getArchivedTasks should use plain invoke because get_archived_tasks is a read-only query',
  );
  assert.doesNotMatch(
    taskMutationsLifecycleSource,
    /invokeIpc\('get_archived_tasks'/,
    'get_archived_tasks must not broadcast ipc://mutation',
  );
  assert.match(
    diagnosticsSource,
    /export const exportDiagnosticsBundle = \([\s\S]*?\): Promise<ExportDiagnosticsBundleResult> =>\s*\n\s*invoke\('export_diagnostics_bundle', \{ dest_path: destPath \}, signal\);/,
    'exportDiagnosticsBundle writes a user ZIP but must not invalidate app-data queries',
  );
});

test('snapshot import preview and retention cleanup use the correct IPC mutation boundary', () => {
  const settingsSource = readFileSync('app/src/lib/ipc/settings.ts', 'utf8');

  assert.match(
    settingsSource,
    /export const runDataRetentionCleanup = \(signal\?: AbortSignal\): Promise<DataRetentionCleanupResult> =>\s*\n\s*invokeIpc\('run_data_retention_cleanup', undefined, signal\);/,
    'runDataRetentionCleanup deletes diagnostics/changelog rows and should broadcast a mutation without refreshing widgets',
  );
  assert.match(
    settingsSource,
    /options\?\.dryRun === true\s*\n\s*\? invoke\('import_data_snapshot', payload, options\.signal\)\s*\n\s*: invokeIpc\('import_data_snapshot', payload, options\?\.signal\)/,
    'snapshot dry-run previews should use plain invoke while real imports keep mutation side effects',
  );
});
