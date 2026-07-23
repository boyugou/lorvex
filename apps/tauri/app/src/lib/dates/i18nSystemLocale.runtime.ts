import type { Locale } from '../../locales';
import { localeTextDirection } from '../../locales/registry';

interface I18nSystemLocaleRefreshRuntimeDeps {
  enabled: boolean;
  addDocumentListener: ((type: 'visibilitychange', listener: () => void) => () => void) | null;
  addWindowListener: ((type: 'focus', listener: () => void) => () => void) | null;
  applyLocale: (locale: Locale) => void;
  currentLocale: Locale;
  detectSystemLocale: () => Locale;
  getVisibilityState: () => DocumentVisibilityState;
}

export interface I18nPreferenceLoadTimeoutHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

export const I18N_PREFERENCE_LOAD_TIMEOUT_MS = 3_000;

export function applyBrowserLocaleDocumentAttributes(locale: Locale): void {
  if (typeof document === 'undefined') return;
  document.documentElement.lang = locale;
  document.documentElement.dir = localeTextDirection(locale);
}

export function createBrowserI18nSystemLocaleRefreshRuntimeDeps(
  deps: Omit<
    I18nSystemLocaleRefreshRuntimeDeps,
    'addDocumentListener' | 'addWindowListener' | 'getVisibilityState'
  >,
): I18nSystemLocaleRefreshRuntimeDeps {
  return {
    ...deps,
    addDocumentListener: typeof document === 'undefined'
      ? null
      : (type, listener) => {
          document.addEventListener(type, listener);
          return () => document.removeEventListener(type, listener);
        },
    addWindowListener: typeof window === 'undefined'
      ? null
      : (type, listener) => {
          window.addEventListener(type, listener);
          return () => window.removeEventListener(type, listener);
        },
    getVisibilityState: () => (typeof document === 'undefined' ? 'visible' : document.visibilityState),
  };
}

export function createBrowserI18nPreferenceLoadTimeoutHost(): I18nPreferenceLoadTimeoutHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function reconcileSystemLocaleRefresh(
  currentLocale: Locale,
  detectedLocale: Locale,
  visibilityState: DocumentVisibilityState,
): Locale | null {
  if (visibilityState !== 'visible') {
    return null;
  }
  return detectedLocale === currentLocale ? null : detectedLocale;
}

export function installI18nSystemLocaleRefreshRuntime(
  deps: I18nSystemLocaleRefreshRuntimeDeps,
): () => void {
  if (!deps.enabled) {
    return () => {};
  }

  let currentLocale = deps.currentLocale;
  const handle = () => {
    const nextLocale = reconcileSystemLocaleRefresh(
      currentLocale,
      deps.detectSystemLocale(),
      deps.getVisibilityState(),
    );
    if (nextLocale) {
      currentLocale = nextLocale;
      deps.applyLocale(nextLocale);
    }
  };

  const removeVisibility = deps.addDocumentListener
    ? deps.addDocumentListener('visibilitychange', handle)
    : () => {};
  const removeFocus = deps.addWindowListener
    ? deps.addWindowListener('focus', handle)
    : () => {};
  return () => {
    removeFocus();
    removeVisibility();
  };
}

export function scheduleI18nPreferenceLoadTimeout({
  timerHost,
  onTimeout,
  delayMs = I18N_PREFERENCE_LOAD_TIMEOUT_MS,
}: {
  timerHost: I18nPreferenceLoadTimeoutHost;
  onTimeout: () => void;
  delayMs?: number;
}): () => void {
  const handle = timerHost.setTimeout(onTimeout, delayMs);
  return () => timerHost.clearTimeout(handle);
}
