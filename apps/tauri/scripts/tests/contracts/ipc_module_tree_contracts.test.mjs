import assert from 'node:assert/strict';
import { existsSync } from 'node:fs';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const appSrc = path.join(repoRoot, 'app/src');
const ipcDir = path.join(appSrc, 'lib/ipc');

function read(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

function collectSourceFiles(dir, files = []) {
  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const fullPath = path.join(dir, entry.name);
    if (entry.isDirectory()) {
      collectSourceFiles(fullPath, files);
    } else if (/\.(ts|tsx)$/.test(entry.name)) {
      files.push(fullPath);
    }
  }
  return files;
}

test('frontend IPC has no broad root or wildcard barrels', () => {
  for (const deletedBarrel of [
    'app/src/lib/ipc.ts',
    'app/src/lib/ipc/tasks/index.ts',
    'app/src/lib/ipc/tasks/mutations/index.ts',
    'app/src/lib/ipc/lists/index.ts',
  ]) {
    assert.equal(
      existsSync(path.join(repoRoot, deletedBarrel)),
      false,
      `${deletedBarrel} should stay deleted; import the owning IPC module directly`,
    );
  }

  for (const file of collectSourceFiles(ipcDir)) {
    const relativePath = path.relative(repoRoot, file);
    const source = fs.readFileSync(file, 'utf8');
    assert.doesNotMatch(
      source,
      /export\s+\*\s+from\s+['"][^'"]+['"]/,
      `${relativePath} should not reintroduce wildcard IPC barrels`,
    );
  }
});

test('app code imports IPC wrappers from owning domain modules', () => {
  const bannedImport = /from\s+['"](?:@\/lib\/ipc|(?:\.{1,2}\/)+[^'"]*lib\/ipc(?:\/(?:tasks|tasks\/mutations|lists))?)['"]/;
  const bannedRootSpecifier = /(?:import\s*\(\s*|vi\.mock\s*\(\s*)['"]@\/lib\/ipc['"]/;

  for (const file of collectSourceFiles(appSrc)) {
    const relativePath = path.relative(repoRoot, file);
    if (relativePath.startsWith('app/src/lib/ipc/')) {
      continue;
    }

    const source = fs.readFileSync(file, 'utf8');
    assert.doesNotMatch(
      source,
      bannedImport,
      `${relativePath} should import IPC from focused modules such as @/lib/ipc/tasks/queries`,
    );
    assert.doesNotMatch(
      source,
      bannedRootSpecifier,
      `${relativePath} should not dynamically import or mock the root IPC barrel`,
    );
  }
});

test('focused IPC modules continue to own their public surfaces', () => {
  const coreSource = read('app/src/lib/ipc/core.ts');
  const taskModelsSource = read('app/src/lib/ipc/tasks/models.ts');
  const taskQueriesSource = read('app/src/lib/ipc/tasks/queries.ts');
  const taskMutationsTypesSource = read('app/src/lib/ipc/tasks/mutations/types.ts');
  const taskMutationsQuickCaptureSource = read('app/src/lib/ipc/tasks/mutations/quickCapture.ts');
  const taskMutationsLifecycleSource = read('app/src/lib/ipc/tasks/mutations/lifecycle.ts');
  const taskReviewsSource = read('app/src/lib/ipc/tasks/reviews.ts');
  const taskListsSource = read('app/src/lib/ipc/tasks/lists.ts');
  const syncSource = read('app/src/lib/ipc/sync.ts');
  const settingsSource = read('app/src/lib/ipc/settings.ts');
  const runtimeSource = read('app/src/lib/ipc/runtime.ts');
  const dashboardSource = [
    read('app/src/lib/ipc/dashboard.ts'),
    existsSync(path.join(repoRoot, 'app/src/lib/ipc/dashboard.logic.ts'))
      ? read('app/src/lib/ipc/dashboard.logic.ts')
      : '',
  ].join('\n');
  const calendarSource = read('app/src/lib/ipc/calendar.ts');

  assert.match(coreSource, /export const IPC_MUTATION_BROADCAST_EVENT = 'ipc:\/\/mutation';/);
  assert.match(coreSource, /import \{ normalizeInvokePayload \} from '\.\/core\.logic';/);
  assert.match(coreSource, /tauriInvoke<T>\(command,\s*normalizeInvokePayload\(payload\)\)/);
  assert.match(coreSource, /export async function invokeIpc<T>\(/);
  assert.match(coreSource, /export \{ toIpcErrorMessage, toUserFacingErrorMessage \} from '\.\/core\.logic';/);

  assert.match(taskModelsSource, /export type \{[^}]*Task[^}]*\} from '@lorvex\/shared\/types'/);
  assert.match(taskModelsSource, /export type \{[^}]*DailyReview[^}]*\} from '@lorvex\/shared\/types'/);
  assert.match(taskQueriesSource, /export const getAllTasks = \(\s*includeCompleted\?: boolean,\s*includeCancelled\?: boolean,\s*signal\?: AbortSignal,\s*\): Promise<Task\[]> =>/s);
  assert.match(taskQueriesSource, /export const getTaskAttribution = \(id: string, signal\?: AbortSignal\): Promise<TaskAttribution \| null> =>/);
  assert.match(taskMutationsTypesSource, /export interface TaskWithUndo \{/);
  assert.match(taskMutationsTypesSource, /interface TaskUpdatePatchFields \{/);
  assert.match(taskMutationsTypesSource, /export type TaskUpdatePatch = \{\s*\[K in keyof TaskUpdatePatchFields\]\?: TaskUpdatePatchFields\[K\] \| undefined;\s*\};/);
  assert.match(taskMutationsTypesSource, /recurrence: TaskUpdateRecurrenceRule \| null;/);
  assert.match(taskMutationsTypesSource, /export function stripUndefinedTaskUpdatePatch\(patch: TaskUpdatePatch\): TaskUpdatePatch \{/);
  assert.match(taskMutationsQuickCaptureSource, /export interface QuickCaptureInput \{[\s\S]*title: string;[\s\S]*signal\?: AbortSignal \| undefined;[\s\S]*\}/);
  assert.match(taskMutationsQuickCaptureSource, /export const quickCapture = \(\{[\s\S]*title,[\s\S]*signal,[\s\S]*\}: QuickCaptureInput\): Promise<Task> =>/);
  assert.match(taskMutationsQuickCaptureSource, /export const updateTask = \(id: string, updates: TaskUpdatePatch, signal\?: AbortSignal\): Promise<TaskWithUndo> =>/);
  assert.match(taskMutationsLifecycleSource, /export const completeTask = \(id: string, signal\?: AbortSignal\): Promise<TaskWithUndo> =>/);
  assert.match(taskReviewsSource, /export const getOverview = \(signal\?: AbortSignal\): Promise<Overview> =>/);
  assert.match(taskReviewsSource, /export const getDailyReviews = \(limit\?: number, signal\?: AbortSignal\): Promise<DailyReview\[]> =>/);
  assert.match(taskListsSource, /export const getAllLists = \(signal\?: AbortSignal\): Promise<ListWithCount\[]> =>/);

  assert.match(syncSource, /export interface SyncStatus \{/);
  assert.match(syncSource, /export const runFilesystemBridgeSync = \(\s*rootPath: string,\s*maxEvents\?: number,\s*signal\?: AbortSignal,\s*\): Promise<FilesystemBridgeSyncResult> =>/s);
  assert.doesNotMatch(syncSource, /runRemote providerSync|Remote providerSyncResult/);

  assert.match(settingsSource, /export const getPreference = \(key: PreferenceKey, signal\?: AbortSignal\): Promise<string \| null> =>/);
  assert.match(settingsSource, /export const appendErrorLog = \(/);
  assert.match(settingsSource, /export const importDataSnapshot = \(/);

  assert.match(runtimeSource, /export interface DeepLinkTarget \{/);
  assert.match(runtimeSource, /export const hidePopoverWindow = \(signal\?: AbortSignal\): Promise<void> =>/);

  assert.match(dashboardSource, /const DEFAULT_DASHBOARD_LAYOUT: DashboardLayout = \{/);
  assert.match(dashboardSource, /function isDashboardSection\(value: unknown\): value is DashboardSection \{/);

  assert.match(calendarSource, /export const createCalendarEvent = \(params: \{/);
  assert.match(calendarSource, /export const updateCalendarEvent = \(/);
});
