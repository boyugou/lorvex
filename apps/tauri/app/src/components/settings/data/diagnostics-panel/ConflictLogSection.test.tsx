import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { ConflictLogSection } from './ConflictLogSection';

describe('ConflictLogSection disclosure semantics', () => {
  it('links the toggle to its controlled panel', () => {
    const queryClient = new QueryClient({
      defaultOptions: {
        queries: {
          retry: false,
        },
      },
    });
    const html = renderToStaticMarkup(
      <QueryClientProvider client={queryClient}>
        <ConflictLogSection
          timeWindow="day"
          sinceIso={null}
          sourceDeviceId={null}
          formatSyncTimestamp={(value) => value ?? ''}
        />
      </QueryClientProvider>,
    );

    const controls = html.match(/aria-controls="([^"]+)"/)?.[1];
    expect(controls).toBeTruthy();
    expect(html).toContain('aria-expanded="false"');
    expect(html).toContain(`id="${controls}"`);
    expect(html).toContain('hidden=""');
  });
});
