import { describe, it, expect } from 'vitest';

import { isAssertiveToast } from './ToastContainer.logic';

describe('isAssertiveToast (#3504)', () => {
  it('routes warning toasts to the assertive lane', () => {
    expect(isAssertiveToast({ type: 'warning' })).toBe(true);
  });

  it('routes error toasts to the assertive lane', () => {
    expect(isAssertiveToast({ type: 'error' })).toBe(true);
  });

  it('routes success toasts to the polite lane', () => {
    expect(isAssertiveToast({ type: 'success' })).toBe(false);
  });

  it('routes info toasts to the polite lane', () => {
    expect(isAssertiveToast({ type: 'info' })).toBe(false);
  });
});
