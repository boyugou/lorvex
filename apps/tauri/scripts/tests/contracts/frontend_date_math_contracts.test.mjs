import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import test from 'node:test';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '../../..');

const scopedFrontendFiles = [
  'app/src/components/calendar/calendarViewUtils.ts',
  'app/src/components/upcoming/dateUtils.ts',
  'app/src/components/upcoming/WeekTimeline.logic.ts',
  'app/src/components/weekly-review/useWeeklyReviewController.ts',
  'app/src/lib/tasks/dayBuckets.ts',
  'app/src/lib/format/formatting.ts',
];

function readRepoFile(relPath) {
  return readFileSync(path.join(repoRoot, relPath), 'utf8');
}

test('frontend YMD day-offset callers import the canonical helper instead of local Date math', () => {
  for (const relPath of scopedFrontendFiles) {
    const source = readRepoFile(relPath);
    assert.doesNotMatch(
      source,
      /setUTCDate\s*\(/,
      `${relPath} must not offset YYYY-MM-DD values with local setUTCDate helpers`,
    );
    assert.doesNotMatch(
      source,
      /\+\s*\w+\s*\*\s*24\s*\*\s*60\s*\*\s*60\s*\*\s*1000/,
      `${relPath} must not offset YYYY-MM-DD values with hand-rolled millisecond day math`,
    );
  }
});

test('timezone wall-clock converters delegate to shared timezone math', () => {
  const dayContextMath = readRepoFile('app/src/lib/dayContextMath.ts');
  const timezone = readRepoFile('app/src/lib/dates/timezone.ts');

  assert.match(dayContextMath, /from ['"]\.\/dates\/timezoneMath(?:\.ts)?['"];/);
  assert.match(timezone, /from ['"]\.\/timezoneMath(?:\.ts)?['"];/);
  assert.doesNotMatch(
    dayContextMath,
    /function\s+offsetMinutesAt\b/,
    'dayContextMath.ts must not keep a private timezone offset probe',
  );
  assert.doesNotMatch(
    timezone,
    /function\s+tzOffsetMinutes\b/,
    'timezone.ts must not keep a private timezone offset probe',
  );
});
