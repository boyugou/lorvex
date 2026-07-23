import { createRef } from 'react';
import { renderToStaticMarkup } from 'react-dom/server';
import { describe, expect, it, vi } from 'vitest';

import { AppSelectContent } from './AppSelectContent';
import type { ParsedOption } from './model';
import {
  BASE_TRIGGER_CLASSES,
  VARIANT_TRIGGER_CLASSES,
} from './styles';
import type { AppSelectController } from './useAppSelectController';

vi.mock('react-dom', async () => {
  const actual = await vi.importActual<typeof import('react-dom')>('react-dom');
  return {
    ...actual,
    createPortal: (node: unknown) => node,
  };
});

const options: ParsedOption[] = [
  {
    key: 'alpha',
    value: 'alpha',
    label: 'Alpha',
    disabled: false,
  },
  {
    key: 'beta',
    value: 'beta',
    label: 'Beta',
    disabled: false,
  },
];

function createController(): AppSelectController {
  return {
    activeIndex: 0,
    handleKeyDown: vi.fn() as AppSelectController['handleKeyDown'],
    handleTriggerBlur: vi.fn() as AppSelectController['handleTriggerBlur'],
    handleTriggerClick: vi.fn(),
    handleTriggerFocus: vi.fn() as AppSelectController['handleTriggerFocus'],
    layoutClassName: '',
    listboxId: 'app-select-test',
    listboxPosition: {
      top: 80,
      left: 240,
      width: 180,
      openUpward: false,
    },
    listboxRef: createRef<HTMLDivElement>(),
    open: true,
    optionRefs: { current: [] },
    options,
    portalTarget: {} as Element,
    rootRef: createRef<HTMLDivElement>(),
    selectOption: vi.fn(),
    selectedOption: options[0],
    selectedValue: 'alpha',
    triggerRef: createRef<HTMLButtonElement>(),
    triggerVariantClasses: '',
    viewportHeight: 600,
  };
}

describe('AppSelectContent portal positioning', () => {
  it('renders the listbox with physical left positioning so RTL does not mirror viewport coordinates', () => {
    const html = renderToStaticMarkup(
      <div dir="rtl">
        <AppSelectContent controller={createController()} aria-label="Example" />
      </div>,
    );

    expect(html).toContain('left:240px');
    expect(html).not.toContain('inset-inline-start');
  });

  it('can promote modal-hosted listboxes above modal panels through the shared popover layer prop', () => {
    const html = renderToStaticMarkup(
      <AppSelectContent
        controller={createController()}
        aria-label="Example"
        popoverLayer="modalPopover"
      />,
    );

    expect(html).toContain('z-[calc(var(--z-modal)+2)]');
  });
});

describe('AppSelect style policy', () => {
  it('uses canonical focus-ring and shadow token utilities instead of raw Tailwind classes', () => {
    const styleSurface = [
      BASE_TRIGGER_CLASSES,
      ...Object.values(VARIANT_TRIGGER_CLASSES),
    ].join(' ');

    expect(styleSurface).toContain('focus-ring-soft');
    expect(styleSurface).not.toMatch(/\bfocus-visible:ring-[12]\b/);
    expect(styleSurface).not.toMatch(/\bfocus-visible:ring-accent(?:\/\d+)?\b/);
    expect(styleSurface).not.toMatch(/\bshadow-xs\b/);
  });
});
