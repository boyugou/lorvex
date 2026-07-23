import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('sync backend runtime is organized as a facade plus focused module tree', () => {
  const backendDir = path.join(repoRoot, 'app/src/lib/syncBackend');
  const errorKindSource = fs.readFileSync(path.join(backendDir, 'errorKind.ts'), 'utf8');
  const modelSource = fs.readFileSync(path.join(backendDir, 'model.ts'), 'utf8');
  const preferencesSource = fs.readFileSync(path.join(backendDir, 'preferences.ts'), 'utf8');
  const runtimeLogicSource = fs.readFileSync(path.join(backendDir, 'runtime.logic.ts'), 'utf8');
  const runtimeSource = fs.readFileSync(path.join(backendDir, 'runtime.ts'), 'utf8');

  assert.deepEqual(
    fs
      .readdirSync(backendDir)
      .filter((entry) => (entry.endsWith('.ts') || entry.endsWith('.tsx')) && !entry.endsWith('.test.ts'))
      .sort(),
    ['errorKind.ts', 'kinds.ts', 'model.ts', 'preferences.ts', 'runtime.logic.ts', 'runtime.ts'],
    'syncBackend/ should expose focused error-kind, kinds, model, preferences, runtime logic, and runtime facade modules',
  );

  assert.equal(
    fs.existsSync(path.join(repoRoot, 'app/src/lib/syncBackend.ts')),
    false,
    'sync backend support should live under syncBackend/ instead of a flat hotspot file',
  );

  const kindsSource = fs.readFileSync(path.join(backendDir, 'kinds.ts'), 'utf8');
  assert.match(kindsSource, /export type SyncBackendKind =/);
  assert.match(kindsSource, /filesystem_bridge/);
  assert.doesNotMatch(kindsSource, /cloudkit_private/);
  assert.match(modelSource, /export interface SyncBackendSettings \{/);
  assert.match(modelSource, /export interface SyncBackendConfigs \{/);
  assert.match(modelSource, /export function createDefaultSyncBackendConfigs\(/);
  assert.match(modelSource, /export function buildSyncBackendConfig\(/);
  assert.match(modelSource, /export function resolveSyncBackend\(/);
  assert.match(preferencesSource, /export function parseStoredSyncEnabledPreference\(/);
  assert.match(preferencesSource, /export function parseStoredSyncBackendKindPreference\(/);
  assert.match(preferencesSource, /export function parseStoredSyncBackendConfigsPreference\(/);
  assert.match(preferencesSource, /export function resolveStoredSyncBackendSettings\(/);
  assert.match(errorKindSource, /export type SyncErrorKind =/);
  assert.match(errorKindSource, /export function parseSyncErrorEnvelope\(/);
  assert.match(runtimeLogicSource, /export async function runSyncBackendWithDeps\(/);
  assert.match(runtimeLogicSource, /export async function runSyncBackendNowWithDeps\(/);
  assert.match(runtimeLogicSource, /function summarizeSyncBackendRun\(/);
  assert.match(runtimeSource, /export async function runSyncBackend\(/);
  assert.match(runtimeSource, /export async function runSyncBackendNow\(/);
  assert.match(runtimeSource, /from '\.\/runtime\.logic';/);
});
