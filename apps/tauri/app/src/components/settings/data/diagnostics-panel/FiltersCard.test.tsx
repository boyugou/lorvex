import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { FiltersCard } from './FiltersCard';

function renderFiltersCard(): string {
  const queryClient = new QueryClient({
    defaultOptions: {
      queries: {
        retry: false,
      },
    },
  });

  return renderToStaticMarkup(
    <QueryClientProvider client={queryClient}>
      <FiltersCard
        deviceScope=""
        onDeviceScopeChange={() => {}}
        onTimeWindowChange={() => {}}
        timeWindow="day"
      />
    </QueryClientProvider>,
  );
}

describe('FiltersCard accessibility', () => {
  it('programmatically labels the diagnostics device select with its visible label', () => {
    const html = renderFiltersCard();
    const labelMatch = html.match(/<label[^>]+for="([^"]+)"[^>]*>diagnostics\.deviceScope\.label<\/label>/);

    expect(labelMatch?.[1]).toBeTruthy();
    expect(html).toContain(`<select data-theme-form-control="true" id="${labelMatch?.[1]}"`);
  });

  it('labels the time window radio group and exposes one tabbable radio', () => {
    const html = renderFiltersCard();
    const labelMatch = html.match(/<p id="([^"]+)"[^>]*>diagnostics\.timeWindow\.label<\/p>/);

    expect(labelMatch?.[1]).toBeTruthy();
    expect(html).toContain(`role="radiogroup" aria-labelledby="${labelMatch?.[1]}"`);
    expect(html).toContain('role="radio"');
    expect(html).toContain('aria-checked="true"');
    expect(html).toContain('aria-checked="false"');
    expect(html).toContain('tabindex="0"');
    expect(html).toContain('tabindex="-1"');
  });
});
