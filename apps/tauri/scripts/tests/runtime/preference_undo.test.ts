import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  performPreferenceWriteWithSnapshot,
} from '../../../app/src/lib/hooks/usePreferenceMutationWithUndo';
import {
  buildRestoreDefaultsSnapshot,
} from '../../../app/src/components/settings/RestoreDefaultsButton';
import {
  APPEARANCE_DEFAULT_KEYS,
  getPreferenceDefault,
  PREFERENCE_DEFAULTS,
  RETENTION_DEFAULT_KEYS,
} from '../../../app/src/lib/preferences/defaults';

// Issue #2546 — cover the two shared invariants for preference
// mutation Undo that live below the React layer:
//   1. The snapshot-and-replay round-trip restores the previously
//      persisted raw string exactly (set theme=dark → undo → theme
//      reads back what it was before the set).
//   2. The "Restore defaults" registry lists only preferences that
//      have a concrete default registered, and the per-category key
//      bundles stay in sync with PREFERENCE_DEFAULTS. Drift here would
//      silently skip keys from the reset bundle with only a console
//      warning at runtime.

test('preference undo: set → undo round-trips the previous raw value', async () => {
  // Simulate an in-memory preference store the "writer" injects into.
  // The test is deliberately backend-agnostic — we only assert that
  // running forward then undo lands the stored string back at the
  // pre-forward snapshot.
  const store = new Map<string, string>();
  store.set('theme', JSON.stringify('light'));
  const previousRaw = store.get('theme') ?? null;

  const writer = async (key: string, value: unknown): Promise<void> => {
    store.set(key, JSON.stringify(value));
  };

  const result = await performPreferenceWriteWithSnapshot(
    'theme',
    previousRaw,
    'dark',
    writer,
  );
  assert.equal(result.applied, true, 'forward write should have applied');
  assert.equal(store.get('theme'), JSON.stringify('dark'));

  await result.undo();
  assert.equal(
    store.get('theme'),
    JSON.stringify('light'),
    'undo must restore the exact previous raw value',
  );
});

test('preference undo: equal previous + next value is a no-op (no toast, no write)', async () => {
  const store = new Map<string, string>();
  store.set('theme', JSON.stringify('dark'));
  let writeCount = 0;
  const writer = async (key: string, value: unknown): Promise<void> => {
    writeCount += 1;
    store.set(key, JSON.stringify(value));
  };

  const result = await performPreferenceWriteWithSnapshot(
    'theme',
    store.get('theme') ?? null,
    'dark',
    writer,
  );
  assert.equal(result.applied, false, 'no-op path must not run the writer');
  assert.equal(writeCount, 0);
});

test('preference undo: null snapshot means "preference absent" — undo writes null back', async () => {
  const store = new Map<string, string>();
  // theme has never been written.
  const writes: Array<{ key: string; value: unknown }> = [];
  const writer = async (key: string, value: unknown): Promise<void> => {
    writes.push({ key, value });
    if (value === null) {
      store.delete(key);
    } else {
      store.set(key, JSON.stringify(value));
    }
  };

  const result = await performPreferenceWriteWithSnapshot(
    'theme',
    null, // no previous value
    'ember',
    writer,
  );
  assert.equal(result.applied, true);
  assert.equal(store.get('theme'), JSON.stringify('ember'));

  await result.undo();
  assert.equal(
    writes[writes.length - 1]?.value,
    null,
    'undo of a first-write must send null to restore "absent" state',
  );
  assert.equal(store.has('theme'), false);
});

test('restore defaults undo: snapshot includes keys that were absent before restore', () => {
  const present = new Map<string, string>();
  present.set('theme', JSON.stringify('dark'));

  assert.deepEqual(
    buildRestoreDefaultsSnapshot(['theme', 'font_scale'], present),
    [
      { key: 'theme', raw: JSON.stringify('dark') },
      { key: 'font_scale', raw: null },
    ],
  );
});

test('restore defaults undo: implementation replays absent keys as null', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/settings/RestoreDefaultsButton.tsx'),
    'utf8',
  );

  assert.match(source, /buildRestoreDefaultsSnapshot/);
  assert.match(source, /raw === null \? null : parseJsonValueOrNull\(raw\)/);
  assert.doesNotMatch(source, /for \(const \[key, raw\] of args\.snapshot\.entries\(\)\)/);
});

test('restore defaults registry: every grouped key has a registered default', () => {
  // Every key surfaced to a per-category Restore Defaults button MUST
  // have a registered default — otherwise the button silently skips
  // that key with a console warning, leaving the user with the
  // "Restore" label but no observable effect.
  for (const key of APPEARANCE_DEFAULT_KEYS) {
    assert.notEqual(
      getPreferenceDefault(key),
      undefined,
      `APPEARANCE_DEFAULT_KEYS entry '${key}' is missing from PREFERENCE_DEFAULTS`,
    );
  }
  for (const key of RETENTION_DEFAULT_KEYS) {
    assert.notEqual(
      getPreferenceDefault(key),
      undefined,
      `RETENTION_DEFAULT_KEYS entry '${key}' is missing from PREFERENCE_DEFAULTS`,
    );
  }

  // Defaults table must cover known canonical keys for the two bundles.
  assert.equal(PREFERENCE_DEFAULTS['ai_briefing_enabled'], true);
  assert.equal(PREFERENCE_DEFAULTS['theme'], 'system');
  assert.equal(PREFERENCE_DEFAULTS['font_scale'], 1.0);
  assert.equal(PREFERENCE_DEFAULTS['ai_changelog_retention_policy'], null);
  assert.equal(PREFERENCE_DEFAULTS['error_log_retention_days'], null);
  // hide_completed_older_than_days is a number with a bounded default;
  // assert it is positive so the reset button reverts to a sensible
  // "hide history past N days" window instead of 0 (always-show).
  const hideCompletedDefault = PREFERENCE_DEFAULTS['hide_completed_older_than_days'];
  assert.equal(typeof hideCompletedDefault, 'number');
  assert.ok((hideCompletedDefault as number) > 0);
});

test('restore defaults registry: unknown keys return undefined, not null', () => {
  assert.equal(
    getPreferenceDefault('not_a_real_preference_key'),
    undefined,
    'unregistered keys must surface undefined so callers can skip rather than write null',
  );
});

test('restore defaults registry: default value type avoids no-explicit-any suppression', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/preferences/defaults.ts'),
    'utf8',
  );

  assert.doesNotMatch(source, /no-explicit-any/);
  assert.doesNotMatch(source, /type PreferenceDefaultValue = any/);
  assert.match(source, /export type PreferenceDefaultValue =/);
});

test('ai briefing preference key is registry-owned', () => {
  const appSourceFiles = [
    'app/src/components/settings/general/GeneralPreferencesSection.tsx',
    'app/src/components/today-view/TodayViewContent.tsx',
    'app/src/components/popover-window/PopoverWindowContent.tsx',
    'app/src/lib/preferences/defaults.ts',
    'app/src/lib/query/usePreference.ts',
  ];

  for (const file of appSourceFiles) {
    const source = fs.readFileSync(path.join(process.cwd(), file), 'utf8');
    assert.doesNotMatch(
      source,
      /['"]ai_briefing_enabled['"]/,
      `${file} must use PREF_AI_BRIEFING_ENABLED instead of a raw string literal`,
    );
  }

  const registry = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/preferences/keys.ts'),
    'utf8',
  );
  assert.match(registry, /PREF_AI_BRIEFING_ENABLED = 'ai_briefing_enabled'/);
});
