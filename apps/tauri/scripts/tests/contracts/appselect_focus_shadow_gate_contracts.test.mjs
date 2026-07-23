import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('AppSelect focus and shadow gates cover split arrays and raw shadow-xs', () => {
  const focusGateSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/verify/focus_ring_consistency.mjs'),
    'utf8',
  );
  const tailwindAuditSource = fs.readFileSync(
    path.join(repoRoot, 'scripts/lint/tailwind_class_audit.mjs'),
    'utf8',
  );
  const appSelectStylesSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ui/app-select/styles.ts'),
    'utf8',
  );

  assert.match(
    focusGateSource,
    /multiline:\s*true/,
    'focus-ring gate should scan across line boundaries so split class arrays cannot bypass it',
  );
  assert.ok(
    focusGateSource.includes('[\\s\\S]{0,240}'),
    'focus-ring gate should include a bounded cross-line matcher for split focus-visible ring composition',
  );
  assert.ok(
    tailwindAuditSource.includes('shadow-(?:xs|sm|md|lg|xl|2xl)'),
    'tailwind audit should forbid shadow-xs along with the existing raw shadow buckets',
  );

  assert.doesNotMatch(
    appSelectStylesSource,
    /focus-visible:ring-[12]|focus-visible:ring-accent(?:\/\d+)?/,
    'AppSelect should use focus-ring-* utilities instead of hand-rolled focus-visible ring classes',
  );
  assert.doesNotMatch(
    appSelectStylesSource,
    /\bshadow-xs\b/,
    'AppSelect should not use raw shadow-xs',
  );
});
