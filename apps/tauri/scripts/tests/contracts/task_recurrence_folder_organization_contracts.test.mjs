import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('task recurrence helpers are organized as a folder-backed support subtree', () => {
  const suiteRoot = path.join(repoRoot, 'app/src-tauri/src/commands/tasks/recurrence');
  const rootSource = fs.readFileSync(path.join(suiteRoot, 'mod.rs'), 'utf8');
  const storeRoot = path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence');
  const storeFacadeSource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-store/src/calendar_timeline/recurrence.rs'),
    'utf8',
  );

  for (const fileName of [
    'count_end.rs',
    'next_occurrence.rs',
    'range_queries.rs',
  ]) {
    assert.ok(
      fs.existsSync(path.join(suiteRoot, fileName)),
      `task_recurrence module should include ${fileName}`,
    );
  }

  for (const fileName of ['month_year.rs', 'mutation.rs', 'occurrence.rs', 'parse.rs', 'weekly.rs']) {
    assert.ok(
      fs.existsSync(path.join(storeRoot, fileName)),
      `shared recurrence module should include ${fileName}`,
    );
  }

  assert.match(rootSource, /^mod count_end;$/m);
  assert.match(rootSource, /^mod next_occurrence;$/m);
  assert.match(rootSource, /^mod range_queries;$/m);
  assert.match(rootSource, /pub\(crate\) use count_end::count_end_date;/);
  assert.match(rootSource, /pub\(crate\) use range_queries::overlaps_calendar_range;/);
  assert.match(storeFacadeSource, /^mod mutation;$/m);
  assert.match(storeFacadeSource, /pub use mutation::\{decrement_recurrence_count, inject_bymonthday\};/);
});
