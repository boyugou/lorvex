import { describe, expect, it, vi } from 'vitest';

import {
  resolveContextMenuKeyAction,
  resolveContextMenuFocusRestoreTarget,
  resolveContextSubmenuPosition,
  restoreContextMenuFocus,
} from './ContextMenu.runtime';

function focusTarget(isConnected: boolean) {
  return {
    focus: vi.fn(),
    isConnected,
  } as unknown as HTMLElement;
}

describe('context menu focus restore contract', () => {
  it('prefers the connected launcher over the fallback active element', () => {
    const launcher = focusTarget(true);
    const fallback = focusTarget(true);

    expect(resolveContextMenuFocusRestoreTarget(launcher, fallback)).toBe(launcher);
  });

  it('falls back to the pre-open active element when the launcher is disconnected', () => {
    const launcher = focusTarget(false);
    const fallback = focusTarget(true);

    expect(resolveContextMenuFocusRestoreTarget(launcher, fallback)).toBe(fallback);
  });

  it('does not restore focus when neither candidate is still connected', () => {
    const launcher = focusTarget(false);
    const fallback = focusTarget(false);

    expect(resolveContextMenuFocusRestoreTarget(launcher, fallback)).toBeNull();
    expect(restoreContextMenuFocus(launcher, fallback)).toBe(false);
    expect(launcher.focus).not.toHaveBeenCalled();
    expect(fallback.focus).not.toHaveBeenCalled();
  });

  it('focuses the resolved restore target', () => {
    const fallback = focusTarget(true);

    expect(restoreContextMenuFocus(null, fallback)).toBe(true);
    expect(fallback.focus).toHaveBeenCalledOnce();
  });
});

describe('context submenu positioning', () => {
  it('opens LTR submenus toward inline-end and falls back inline-start on overflow', () => {
    expect(resolveContextSubmenuPosition(
      { left: 100, right: 220, top: 40, width: 120 },
      { width: 160, height: 100 },
      { width: 500, height: 400 },
      'ltr',
    ).left).toBe(118);

    expect(resolveContextSubmenuPosition(
      { left: 330, right: 450, top: 40, width: 120 },
      { width: 160, height: 100 },
      { width: 500, height: 400 },
      'ltr',
    ).left).toBe(-158);
  });

  it('opens RTL submenus toward inline-end and falls back inline-start on overflow', () => {
    expect(resolveContextSubmenuPosition(
      { left: 220, right: 340, top: 40, width: 120 },
      { width: 160, height: 100 },
      { width: 500, height: 400 },
      'rtl',
    ).left).toBe(-158);

    expect(resolveContextSubmenuPosition(
      { left: 80, right: 200, top: 40, width: 120 },
      { width: 160, height: 100 },
      { width: 500, height: 400 },
      'rtl',
    ).left).toBe(118);
  });
});

describe('context menu submenu keyboard direction', () => {
  it('uses ArrowRight to open and ArrowLeft to close submenus in LTR', () => {
    expect(resolveContextMenuKeyAction(
      { key: 'ArrowRight' },
      { isSubmenuOpen: false, highlightedHasSubmenu: true, textDirection: 'ltr' },
    )).toBe('open-submenu');
    expect(resolveContextMenuKeyAction(
      { key: 'ArrowLeft' },
      { isSubmenuOpen: true, highlightedHasSubmenu: true, textDirection: 'ltr' },
    )).toBe('close-submenu');
  });

  it('uses ArrowLeft to open and ArrowRight to close submenus in RTL', () => {
    expect(resolveContextMenuKeyAction(
      { key: 'ArrowLeft' },
      { isSubmenuOpen: false, highlightedHasSubmenu: true, textDirection: 'rtl' },
    )).toBe('open-submenu');
    expect(resolveContextMenuKeyAction(
      { key: 'ArrowRight' },
      { isSubmenuOpen: true, highlightedHasSubmenu: true, textDirection: 'rtl' },
    )).toBe('close-submenu');
  });
});
