import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import test from 'node:test';

const ROOT = process.cwd();

test('duration validation copy avoids raw ASCII max interpolation across entry points', () => {
  const quickCaptureForm = readFileSync(join(ROOT, 'app', 'src', 'components', 'quick-capture', 'useQuickCaptureSubmit.ts'), 'utf8');
  const durationDropdown = readFileSync(join(ROOT, 'app', 'src', 'components', 'quick-capture', 'toolbar', 'DurationDropdown.tsx'), 'utf8');
  const unifiedMeta = readFileSync(join(ROOT, 'app', 'src', 'components', 'task-detail', 'metadata-editor', 'TaskUnifiedMetaCard.tsx'), 'utf8');
  const estimatedMinutesField = readFileSync(join(ROOT, 'app', 'src', 'components', 'task-detail', 'metadata-editor', 'editable-grid', 'TaskMetricsFields.tsx'), 'utf8');

  assert.doesNotMatch(quickCaptureForm, /replace\('\{max\}', String\(MAX_ESTIMATED_MINUTES\)\)/);
  assert.doesNotMatch(durationDropdown, /replace\('\{max\}', String\(MAX_ESTIMATED_MINUTES\)\)/);
  assert.doesNotMatch(unifiedMeta, /replace\('\{max\}', String\(MAX_ESTIMATED_MINUTES\)\)/);
  assert.doesNotMatch(estimatedMinutesField, /replace\('\{max\}', String\(MAX_ESTIMATED_MINUTES\)\)/);
});
