import {
  createBrowserFocusTrapHost,
  trapTabFocusWithinRuntime,
  type FocusTrapKeyboardEventLike,
  type FocusTrapOptions,
} from './focusTrap.runtime';

export type { FocusTrapKeyboardEventLike, FocusTrapOptions };

const browserFocusTrapHost = createBrowserFocusTrapHost();

export function trapTabFocusWithin(
  container: HTMLElement | null,
  event: FocusTrapKeyboardEventLike,
  options?: FocusTrapOptions,
): boolean {
  return trapTabFocusWithinRuntime(browserFocusTrapHost, container, event, options);
}
