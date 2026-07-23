import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it } from 'vitest';

import { SettingsSection, TimeInput } from './SettingsPrimitives';

describe('settings primitives accessibility', () => {
  it('lets TimeInput expose a field-specific accessible label', () => {
    const html = renderToStaticMarkup(
      <TimeInput
        value="09:00"
        onChange={() => {}}
        ariaLabel="Working hours start"
      />,
    );

    expect(html).toContain('aria-label="Working hours start: 9:00');
  });

  it('preserves the current value when labelled by external text', () => {
    const html = renderToStaticMarkup(
      <>
        <span id="working-hours-start-label">Working hours start</span>
        <TimeInput
          value="09:00"
          onChange={() => {}}
          ariaLabelledBy="working-hours-start-label"
        />
      </>,
    );

    expect(html).toMatch(/aria-labelledby="working-hours-start-label [^"]+"/);
    expect(html).toContain('>9:00');
  });

  it('links collapsible section buttons to their controlled panel', () => {
    const html = renderToStaticMarkup(
      <SettingsSection title="Advanced" collapsible defaultOpen={false}>
        <p>Developer diagnostics</p>
      </SettingsSection>,
    );

    const controls = html.match(/aria-controls="([^"]+)"/)?.[1];
    expect(controls).toBeTruthy();
    expect(html).toContain('aria-expanded="false"');
    expect(html).toContain(`id="${controls}"`);
  });
});
