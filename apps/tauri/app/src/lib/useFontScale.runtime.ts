import type { FontScaleRootHost } from './useFontScale.logic';

export function createBrowserFontScaleRootHost(): FontScaleRootHost | null {
  if (typeof document === 'undefined') {
    return null;
  }

  return {
    addTransitionEndListener: (listener) => {
      document.documentElement.addEventListener('transitionend', listener, { once: true });
    },
    clearTransition: () => {
      document.documentElement.style.removeProperty('transition');
    },
    removeTransitionEndListener: (listener) => {
      document.documentElement.removeEventListener('transitionend', listener);
    },
    setTransition: (transition) => {
      document.documentElement.style.setProperty('transition', transition);
    },
    setFontSizePx: (fontSizePx) => {
      document.documentElement.style.fontSize = `${fontSizePx}px`;
    },
  };
}
