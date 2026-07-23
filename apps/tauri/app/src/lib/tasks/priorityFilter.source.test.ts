import { describe, expect, it } from 'vitest';

type FsNS = { readFileSync: (path: string, encoding: 'utf8') => string };
const fs = (await import(/* @vite-ignore */ 'node:fs' as string)) as unknown as FsNS;

const PERSISTED_PRIORITY_FILTER_CONTROLLERS = [
  'src/components/all-tasks/useAllTasksController.ts',
  'src/components/upcoming/useUpcomingController.ts',
  'src/components/eisenhower/useEisenhowerController.ts',
  'src/components/kanban/useKanbanController.ts',
] as const;

describe('priority filter persistence boundary', () => {
  it('restores persisted priority filters through the Priority validator only', () => {
    for (const path of PERSISTED_PRIORITY_FILTER_CONTROLLERS) {
      const source = fs.readFileSync(path, 'utf8');

      expect(source, path).toMatch(/\bisPriorityOrNull\b/);
      expect(source, path).not.toMatch(/\bisNumberOrNull\b/);
    }
  });

  it('parses dropdown priority values without accepting arbitrary numbers', () => {
    const source = fs.readFileSync('src/components/ui/PriorityFilterDropdown.tsx', 'utf8');

    expect(source).toMatch(/\bparsePriorityFilterValue\b/);
    expect(source).not.toMatch(/\bNumber\(/);
  });
});
