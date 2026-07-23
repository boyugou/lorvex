import { describe, expect, it } from 'vitest';

import { getPopoverLayerClasses } from './popoverLayer';

describe('popover layer classes', () => {
  it('keeps default popovers on the canonical popover tier', () => {
    expect(getPopoverLayerClasses('popover')).toEqual({
      root: 'z-[var(--z-popover)]',
      backdrop: 'z-[calc(var(--z-popover)-1)]',
      panel: 'z-[var(--z-popover)]',
    });
  });

  it('places modal-hosted popovers above modal panels', () => {
    expect(getPopoverLayerClasses('modalPopover')).toEqual({
      root: 'z-[calc(var(--z-modal)+1)]',
      backdrop: 'z-[calc(var(--z-modal)+1)]',
      panel: 'z-[calc(var(--z-modal)+2)]',
    });
  });
});
