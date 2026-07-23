import type { VisualViewportInsetHost } from './useVisualViewport';

export function createBrowserVisualViewportInsetHost(): VisualViewportInsetHost | null {
  if (typeof window === 'undefined' || !window.visualViewport || typeof document === 'undefined') {
    return null;
  }

  return {
    getInnerHeight: () => window.innerHeight,
    getOffsetTop: () => window.visualViewport?.offsetTop ?? 0,
    getViewportHeight: () => window.visualViewport?.height ?? window.innerHeight,
    onViewportChange: (listener) => {
      const vv = window.visualViewport;
      if (!vv) return () => {};
      vv.addEventListener('resize', listener, { passive: true });
      vv.addEventListener('scroll', listener, { passive: true });
      return () => {
        vv.removeEventListener('resize', listener);
        vv.removeEventListener('scroll', listener);
      };
    },
    setInsetPx: (insetPx) => {
      document.documentElement.style.setProperty('--kb-inset', `${insetPx}px`);
    },
    clearInset: () => {
      document.documentElement.style.removeProperty('--kb-inset');
    },
  };
}
