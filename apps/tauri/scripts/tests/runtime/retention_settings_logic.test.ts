import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import test from 'node:test';

import {
  parseRetentionDaysPreference,
} from '../../../app/src/components/settings/data/retentionSettings.logic';

test('retention days parser accepts positive decimal integer payloads', () => {
  assert.equal(parseRetentionDaysPreference('7'), 7);
  assert.equal(parseRetentionDaysPreference('365'), 365);
});

test('retention days parser rejects missing, malformed, and non-integer payloads', () => {
  assert.equal(parseRetentionDaysPreference(null), null);
  assert.equal(parseRetentionDaysPreference('not json'), null);
  assert.equal(parseRetentionDaysPreference('"30"'), null);
  assert.equal(parseRetentionDaysPreference('0'), null);
  assert.equal(parseRetentionDaysPreference('-1'), null);
  assert.equal(parseRetentionDaysPreference('1.5'), null);
  assert.equal(parseRetentionDaysPreference('1e3'), null);
  assert.equal(parseRetentionDaysPreference('{"days":30}'), null);
});

test('retention days parser avoids broad JSON number parsing', () => {
  const source = readFileSync('app/src/components/settings/data/retentionSettings.logic.ts', 'utf8');
  assert.doesNotMatch(source, /JSON\.parse\(trimmed\)/);
});

test('retention settings controller subscribes to preference query cache instead of one-shot reads', () => {
  const source = readFileSync(
    'app/src/components/settings/data/useRetentionSettingsController.ts',
    'utf8',
  );

  assert.match(source, /usePreference\(/);
  assert.doesNotMatch(source, /getPreference\(/);
  assert.doesNotMatch(source, /useEffect\(\(\) => \{\s*let cancelled = false;/);
});
