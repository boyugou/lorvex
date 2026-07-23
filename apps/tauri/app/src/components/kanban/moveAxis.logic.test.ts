import { describe, expect, it } from 'vitest';

import { isKanbanMoveAxisHandled } from './moveAxis.logic';

describe('Kanban move axis contract', () => {
  it('handles the horizontal axis used by left/right column movement', () => {
    expect(isKanbanMoveAxisHandled('horizontal')).toBe(true);
  });

  it('keeps the legacy no-axis call path horizontal', () => {
    expect(isKanbanMoveAxisHandled(undefined)).toBe(true);
  });

  it('does not treat vertical arrows as Kanban column movement', () => {
    expect(isKanbanMoveAxisHandled('vertical')).toBe(false);
  });
});
