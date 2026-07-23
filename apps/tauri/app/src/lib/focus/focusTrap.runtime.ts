export type FocusTrapKeyboardEventLike = {
  key: string;
  shiftKey: boolean;
  defaultPrevented: boolean;
  preventDefault: () => void;
};

export type FocusTrapOptions = {
  extraRoots?: Array<HTMLElement | null>;
};

type FocusTrapComputedStyle = Pick<CSSStyleDeclaration, 'display' | 'visibility'>;

interface FocusTrapHost {
  getActiveElement: () => HTMLElement | null;
  getComputedStyle: (element: HTMLElement) => FocusTrapComputedStyle | null;
  getElementConstructor: () => typeof HTMLElement | null;
}

const FOCUSABLE_SELECTOR = [
  'a[href]',
  'button:not([disabled])',
  'input:not([disabled])',
  'select:not([disabled])',
  'textarea:not([disabled])',
  '[tabindex]:not([tabindex="-1"])',
  '[contenteditable]:not([contenteditable="false"])',
].join(', ');

export function createBrowserFocusTrapHost(): FocusTrapHost {
  return {
    getActiveElement: () => {
      const elementConstructor = typeof HTMLElement === 'undefined' ? null : HTMLElement;
      if (!elementConstructor || typeof document === 'undefined') return null;
      return document.activeElement instanceof elementConstructor ? document.activeElement : null;
    },
    getComputedStyle: (element) => {
      if (typeof window === 'undefined' || typeof window.getComputedStyle !== 'function') {
        return null;
      }
      return window.getComputedStyle(element);
    },
    getElementConstructor: () => (typeof HTMLElement === 'undefined' ? null : HTMLElement),
  };
}

function isFocusableElement(host: FocusTrapHost, element: HTMLElement): boolean {
  const style = host.getComputedStyle(element);
  if (!style) return false;

  return (
    !element.hasAttribute('disabled')
    && !element.hasAttribute('inert')
    && element.getAttribute('aria-hidden') !== 'true'
    && element.tabIndex >= 0
    && style.display !== 'none'
    && style.visibility !== 'hidden'
    && style.visibility !== 'collapse'
    && element.getClientRects().length > 0
  );
}

function getFocusableElements(
  host: FocusTrapHost,
  container: HTMLElement | null,
  extraRoots: Array<HTMLElement | null> = [],
): HTMLElement[] {
  const elementConstructor = host.getElementConstructor();
  if (!elementConstructor) return [];

  const roots = [container, ...extraRoots].filter(
    (root): root is HTMLElement => root instanceof elementConstructor,
  );
  if (roots.length === 0) return [];

  const seen = new Set<HTMLElement>();
  const focusable: HTMLElement[] = [];
  for (const root of roots) {
    const candidates = [root, ...Array.from(root.querySelectorAll<HTMLElement>(FOCUSABLE_SELECTOR))];
    for (const candidate of candidates) {
      if (seen.has(candidate)) continue;
      seen.add(candidate);
      if (candidate.matches(FOCUSABLE_SELECTOR) && isFocusableElement(host, candidate)) {
        focusable.push(candidate);
      }
    }
  }
  return focusable;
}

export function trapTabFocusWithinRuntime(
  host: FocusTrapHost,
  container: HTMLElement | null,
  event: FocusTrapKeyboardEventLike,
  options?: FocusTrapOptions,
): boolean {
  if (event.defaultPrevented || event.key !== 'Tab') return false;
  const focusableElements = getFocusableElements(host, container, options?.extraRoots ?? []);
  if (focusableElements.length === 0) return false;

  const activeElement = host.getActiveElement();
  const currentIndex = activeElement ? focusableElements.indexOf(activeElement) : -1;

  if (event.shiftKey) {
    if (currentIndex <= 0) {
      event.preventDefault();
      focusableElements[focusableElements.length - 1]?.focus();
      return true;
    }
    return false;
  }

  if (currentIndex === -1 || currentIndex === focusableElements.length - 1) {
    event.preventDefault();
    focusableElements[0]?.focus();
    return true;
  }

  return false;
}
