import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import { Toggle } from './Toggle';

describe('Toggle label activation semantics', () => {
  it('renders a real checkbox switch targeted by the visible label', () => {
    const html = renderToStaticMarkup(
      <Toggle
        id="hide-completed-toggle"
        checked={false}
        onChange={vi.fn()}
        label="Hide completed"
      />,
    );

    expect(html).toContain('<label for="hide-completed-toggle"');
    expect(html).toContain('id="hide-completed-toggle"');
    expect(html).toContain('type="checkbox"');
    expect(html).toContain('role="switch"');
    expect(html).not.toContain('<button');
  });

  it('keeps description text associated with the switch input', () => {
    const html = renderToStaticMarkup(
      <Toggle
        id="desktop-behavior-toggle"
        checked
        onChange={vi.fn()}
        label="Launch on login"
        description="Start Lorvex when the desktop session starts."
      />,
    );

    expect(html).toContain('aria-describedby="desktop-behavior-toggle-description"');
    expect(html).toContain('id="desktop-behavior-toggle-description"');
  });

  it('uses aria-label for unlabeled switches while keeping them labelable externally', () => {
    const html = renderToStaticMarkup(
      <Toggle
        id="dependency-graph-toggle"
        checked={false}
        onChange={vi.fn()}
        ariaLabel="Hide completed"
      />,
    );

    expect(html).toContain('aria-label="Hide completed"');
    expect(html).toContain('id="dependency-graph-toggle"');
    expect(html).toContain('type="checkbox"');
  });
});
