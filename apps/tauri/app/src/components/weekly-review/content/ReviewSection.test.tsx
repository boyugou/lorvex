import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import ReviewSection from './ReviewSection';

describe('ReviewSection disclosure semantics', () => {
  it('exposes expanded state and controls for collapsible sections', () => {
    const html = renderToStaticMarkup(
      <ReviewSection
        title="Completed"
        subtitle="What shipped this week"
        icon="checkmark"
        collapsible
        defaultExpanded={false}
      >
        <p>Completed items</p>
      </ReviewSection>,
    );

    const controls = html.match(/aria-controls="([^"]+)"/)?.[1];
    expect(controls).toBeTruthy();
    expect(html).toContain('aria-expanded="false"');
    expect(html).toContain(`id="${controls}"`);
    expect(html).toContain('hidden=""');
  });
});
