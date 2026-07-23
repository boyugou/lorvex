import assert from 'node:assert/strict';
import test from 'node:test';

import {
  createHarness,
  parseJsonContent,
  parseTaskEnvelope,
} from '../../shared';

test('get_weekly_review_brief supports completed section bounds with metadata', async (t) => {
  const harness = await createHarness('weekly-brief-bounds');
  t.after(async () => {
    await harness.cleanup();
  });

  for (let i = 0; i < 6; i += 1) {
    const createResult = await harness.client.callTool({
      name: 'create_task',
      arguments: {
        title: `weekly-complete-${i}`,
      },
    });
    const task = parseTaskEnvelope<{ id: string }>(createResult);
    await harness.client.callTool({
      name: 'complete_task',
      arguments: { id: task.id },
    });
  }

  const briefResult = await harness.client.callTool({
    name: 'get_weekly_review_brief',
    arguments: {
      completed_limit: 3,
    },
  });
  const brief = parseJsonContent<{
    completed_this_week: Array<{ id: string }>;
    section_meta: {
      completed_this_week: {
        limit: number;
        total_matching: number;
        returned: number;
        truncated: boolean;
      };
    };
  }>(briefResult);

  assert.equal(brief.completed_this_week.length, 3);
  assert.equal(brief.section_meta.completed_this_week.limit, 3);
  assert.equal(brief.section_meta.completed_this_week.returned, 3);
  assert.equal(brief.section_meta.completed_this_week.truncated, true);
  assert.ok(
    brief.section_meta.completed_this_week.total_matching >= 6,
    'Expected completed total to include all completed tasks in window',
  );
});
