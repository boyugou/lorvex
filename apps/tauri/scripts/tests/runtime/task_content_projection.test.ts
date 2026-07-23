import assert from 'node:assert/strict';
import test from 'node:test';

import { projectTaskBodyContent } from '../../../app/src/lib/tasks/contentProjection';

test('projectTaskBodyContent skips checklist and heading lines when deriving the body snippet', () => {
  assert.deepEqual(
    projectTaskBodyContent('- [ ] First\n- [x] Second\n\n## Details\nActual note line'),
    {
      bodySnippet: 'Actual note line',
    },
  );
});

test('projectTaskBodyContent returns nulls when no body is present', () => {
  assert.deepEqual(
    projectTaskBodyContent(null),
    {
      bodySnippet: null,
    },
  );
});
