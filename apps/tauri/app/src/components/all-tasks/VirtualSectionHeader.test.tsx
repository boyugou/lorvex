import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import type { TaskSection } from './types';

vi.mock('@/lib/i18n', () => ({
  useI18n: () => ({
    formatNumber: (value: number) => String(value),
    t: (key: string) => ({
      'common.hourShort': 'h',
      'common.min': 'm',
    })[key] ?? key,
  }),
}));

import { VirtualSectionHeader } from './VirtualSectionHeader';

describe('VirtualSectionHeader heading semantics', () => {
  it('renders a real heading that contains the native collapse button', () => {
    const section: TaskSection = {
      key: 'priority-1',
      title: 'Priority 1',
      tasks: [
        { id: 'task-1', estimated_minutes: 30 } as never,
        { id: 'task-2', estimated_minutes: 45 } as never,
      ],
    };

    const html = renderToStaticMarkup(
      <VirtualSectionHeader
        section={section}
        collapsed
        onToggleCollapse={vi.fn()}
      />,
    );

    expect(html).toMatch(/<h2\b[^>]*>[\s\S]*<button\b[^>]*type="button"[^>]*aria-expanded="false"[^>]*>[\s\S]*Priority 1[\s\S]*<\/button>[\s\S]*<\/h2>/);
    expect(html).not.toContain('role="button"');
    expect(html).not.toContain('tabindex="0"');
  });
});
