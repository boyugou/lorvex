import assert from 'node:assert/strict';
import test from 'node:test';

import {
  collapseAllSections,
  expandAllSections,
  isCollapsedSectionKeyArray,
  readCollapsedSectionSet,
  serializeCollapsedSectionSet,
  toggleCollapsedSection,
} from '../../../app/src/lib/collapsibleSections.logic';

test('collapsible sections: validator accepts only string arrays', () => {
  assert.equal(isCollapsedSectionKeyArray(['open', 'completed']), true);
  assert.equal(isCollapsedSectionKeyArray(['open', 1]), false);
  assert.equal(isCollapsedSectionKeyArray({ show: ['open'] }), false);
});

test('collapsible sections: read + serialize preserves stable key order', () => {
  const collapsed = readCollapsedSectionSet(['overdue', 'today']);
  assert.deepEqual(serializeCollapsedSectionSet(collapsed), ['overdue', 'today']);
});

test('collapsible sections: toggle adds and removes the targeted key without mutating the input set', () => {
  const start = new Set(['open']);
  const added = toggleCollapsedSection(start, 'completed');
  assert.deepEqual([...start], ['open']);
  assert.deepEqual([...added], ['open', 'completed']);

  const removed = toggleCollapsedSection(added, 'open');
  assert.deepEqual([...removed], ['completed']);
});

test('collapsible sections: collapseAll deduplicates repeated keys', () => {
  const collapsed = collapseAllSections(['today', 'today', 'overdue']);
  assert.deepEqual([...collapsed], ['today', 'overdue']);
});

test('collapsible sections: expandAll returns an empty set', () => {
  assert.deepEqual([...expandAllSections()], []);
});
