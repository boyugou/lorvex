import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('general settings preferences are organized as a folder-backed subsystem with normalization, snapshot, writes, and types modules', () => {
  const rootSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/preferences.ts'),
    'utf8',
  );
  const normalizationSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/preferences/normalization.ts'),
    'utf8',
  );
  const snapshotSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/preferences/snapshot.ts'),
    'utf8',
  );
  const writesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/preferences/writes.ts'),
    'utf8',
  );
  const typesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/controller/general/preferences/types.ts'),
    'utf8',
  );

  assert.match(rootSource, /from '\.\/preferences\/normalization';/);
  assert.match(rootSource, /from '\.\/preferences\/snapshot';/);
  assert.match(rootSource, /from '\.\/preferences\/writes';/);
  assert.match(rootSource, /from '\.\/preferences\/types';/);
  assert.doesNotMatch(
    rootSource,
    /export function normalizeAdvancedPreferenceDraft|export async function loadGeneralSettingsSnapshot|export async function saveAdvancedPreferences/,
    'general preferences root should stay a barrel after folder extraction',
  );

  assert.match(normalizationSource, /export const DEFAULT_WEEKLY_REVIEW_DAY/);
  assert.match(normalizationSource, /export function normalizeAdvancedPreferenceDraft/);
  assert.match(snapshotSource, /export async function loadGeneralSettingsSnapshot/);
  assert.match(writesSource, /export async function saveAdvancedPreferences/);
  assert.match(writesSource, /export async function saveSidebarModulesPreference/);
  assert.match(typesSource, /export interface GeneralSettingsSnapshot/);
  assert.match(typesSource, /export interface SaveAdvancedPreferencesArgs/);
});
