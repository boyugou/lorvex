import { describe, expect, it } from 'vitest';

import {
  __getToastsForTests,
  __resetToastsForTests,
  dismissToastsByContext,
  toast,
} from './toast';

describe('toast.warning (#3495)', () => {
  it('emits a warning-typed toast with the message', () => {
    __resetToastsForTests();
    toast.warning('Original restored, replacement still present');
    const toasts = __getToastsForTests();
    expect(toasts).toHaveLength(1);
    expect(toasts[0]?.type).toBe('warning');
    expect(toasts[0]?.message).toBe('Original restored, replacement still present');
  });

  it('warning is independent from error in the dedup window', () => {
    __resetToastsForTests();
    toast.error('Same copy');
    toast.warning('Same copy');
    const toasts = __getToastsForTests();
    // Different `type` keys mean the warning is not deduped against
    // the error — both render so the user sees the partial-success
    // signal even if a related error toast was just emitted.
    expect(toasts.map((item) => item.type)).toEqual(
      expect.arrayContaining(['error', 'warning']),
    );
    expect(toasts).toHaveLength(2);
  });

  it('supports an optional action like the error variant', () => {
    __resetToastsForTests();
    let clicked = 0;
    toast.warning('Cleanup pending', {
      label: 'Open',
      onClick: () => {
        clicked += 1;
      },
    });
    const toasts = __getToastsForTests();
    expect(toasts[0]?.action?.label).toBe('Open');
    void toasts[0]?.action?.onClick();
    expect(clicked).toBe(1);
  });
});

describe('dismissToastsByContext', () => {
  it('dismisses only visible toasts with the matching context', () => {
    __resetToastsForTests();

    toast.info('Peer deleted list', { label: 'Restore', onClick: () => undefined }, 'list:list-1');
    toast.info('Peer deleted task', { label: 'Restore', onClick: () => undefined }, 'task:task-1');

    dismissToastsByContext('list:list-1');

    const toasts = __getToastsForTests();
    expect(toasts).toHaveLength(2);
    expect(toasts.find((item) => item.message === 'Peer deleted list')?.dismissing).toBe(true);
    expect(toasts.find((item) => item.message === 'Peer deleted task')?.dismissing).toBeFalsy();
  });

  it('clears context dedupe state so a later matching toast can replace an invalidated one', () => {
    __resetToastsForTests();

    toast.info('Peer deleted list', { label: 'Restore', onClick: () => undefined }, 'list:list-1');
    dismissToastsByContext('list:list-1');
    toast.info('Peer deleted list', { label: 'Restore', onClick: () => undefined }, 'list:list-1');

    const matching = __getToastsForTests().filter(
      (item) => item.message === 'Peer deleted list',
    );
    expect(matching).toHaveLength(2);
    expect(matching.some((item) => item.dismissing)).toBe(true);
    expect(matching.some((item) => !item.dismissing)).toBe(true);
  });
});
