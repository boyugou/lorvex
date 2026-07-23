import { useQueryClient } from '@tanstack/react-query';
import { createContext, useContext, useState, useEffect, useCallback, useMemo, type ReactNode } from 'react';
import { getPreference, setPreference } from '@/lib/ipc/settings';
import { reportClientError } from './errors/errorLogging';
import { invalidatePreferenceQueries } from './query/invalidation';
import { useMounted } from './useMounted';
import { PREF_LANGUAGE } from './preferences/keys';
import {
  applyBrowserLocaleDocumentAttributes,
  createBrowserI18nPreferenceLoadTimeoutHost,
  createBrowserI18nSystemLocaleRefreshRuntimeDeps,
  installI18nSystemLocaleRefreshRuntime,
  scheduleI18nPreferenceLoadTimeout,
} from './dates/i18nSystemLocale.runtime';
import {
  type Locale,
  type PluralTranslationKeys,
  type TranslationKey,
  type TranslationVars,
  detectSystemLocale,
  formatNumber as formatLocaleNumber,
  formatPluralTranslation,
  formatTranslation,
  loadLocale,
  resolveLocalePreference,
  localeRegistry,
  translate,
} from '../locales';

export type { Locale, TranslationKey, TranslationVars };
const i18nPreferenceLoadTimeoutHost = createBrowserI18nPreferenceLoadTimeoutHost();

interface I18nContextType {
  locale: Locale;
  usingSystemLocale: boolean;
  setLocale: (l: Locale) => void;
  applySystemLocale: () => void;
  t: (key: TranslationKey) => string;
  format: (key: TranslationKey, vars?: TranslationVars) => string;
  plural: (
    count: number,
    keys: PluralTranslationKeys,
    vars?: TranslationVars,
    options?: { fallback?: ((formattedCount: string) => string) | undefined },
  ) => string;
  formatNumber: (value: number) => string;
}

const I18nContext = createContext<I18nContextType>({
  locale: 'en',
  usingSystemLocale: true,
  setLocale: () => {},
  applySystemLocale: () => {},
  t: (key) => key,
  format: (key) => key,
  plural: (_count, keys) => keys.other,
  formatNumber: (value) => String(value),
});

export function I18nProvider({ children }: { children: ReactNode }) {
  // I18nProvider is mounted inside QueryClientProvider (see main.tsx)
  // so the React-Query cache is available here. setLocale /
  // applySystemLocale below pierce the cache directly through the
  // canonical helper instead of going through the `usePreference`
  // hook (the hook lives inside a component that consumes the
  // language preference, not inside the writer that produces it),
  // so any reader that calls `usePreference(PREF_LANGUAGE, ...)`
  // sees the updated value immediately rather than waiting for the
  // next refetch.
  const queryClient = useQueryClient();
  const [locale, setLocaleState] = useState<Locale>('en');
  const [usingSystemLocale, setUsingSystemLocale] = useState(true);
  const [loaded, setLoaded] = useState(false);
  // Monotonic counter bumped after a locale's translations are loaded, forcing
  // a re-render so `t()` picks up the newly cached translations.
  const [, setLocaleGeneration] = useState(0);
  // `useMounted()` returns a ref that is true only while mounted. The previous
  // inline `useEffect(() => () => { ref.current = false; }, [])` pattern broke
  // under React 19 StrictMode: the dev double-invoke runs cleanup on the first
  // pass and never resets the ref on the second mount, leaving the ref
  // permanently false and silently dropping all locale-change re-renders.
  const mountedRef = useMounted();

  const applyLocale = useCallback((code: Locale) => {
    setLocaleState(code);
    // Update document-level lang and dir attributes for screen readers,
    // browser font selection, and CSS logical property support.
    applyBrowserLocaleDocumentAttributes(code);
    // Eagerly load the locale's translation table (English is instant from cache).
    // While loading, translate() falls back to English via fallbackTranslations.
    loadLocale(code).then(() => {
      if (mountedRef.current) setLocaleGeneration((n) => n + 1);
    }).catch((error) => {
      reportClientError('i18n.loadLocale', 'Failed to load locale translations', error, code);
    });
    // mountedRef is a stable MutableRefObject from useMounted.
  }, [mountedRef]);

  useEffect(() => {
    let cancelled = false;

    const fallbackToSystem = () => {
      if (cancelled) return;
      const systemLocale = detectSystemLocale();
      applyLocale(systemLocale);
      setUsingSystemLocale(true);
      setLoaded(true);
    };

    // Timeout: if preference load hangs (e.g., DB locked), fall back after 3s.
    // when the fallback fires, the user silently gets
    // `detectSystemLocale()` with no indication their saved preference
    // didn't load. Route through `reportClientError` so Settings →
    // Diagnostics surfaces the slow/failed read even if the UI silently
    // recovers.
    const cleanupPreferenceLoadTimeout = scheduleI18nPreferenceLoadTimeout({
      timerHost: i18nPreferenceLoadTimeoutHost,
      onTimeout: () => {
        reportClientError(
          'i18n.loadPreference.timeout',
          'Language preference load exceeded 3s timeout; falling back to system default',
          null,
          undefined,
          'warn',
        );
        fallbackToSystem();
      },
    });

    getPreference(PREF_LANGUAGE).then(raw => {
      cleanupPreferenceLoadTimeout();
      if (cancelled) return;
      const resolved = resolveLocalePreference(raw);
      applyLocale(resolved.locale);
      setUsingSystemLocale(resolved.usingSystemLocale);
      setLoaded(true);
    }).catch((error) => {
      cleanupPreferenceLoadTimeout();
      if (cancelled) return;
      reportClientError('i18n.loadPreference', 'Failed to load language preference', error);
      fallbackToSystem();
    });

    return () => {
      cancelled = true;
      cleanupPreferenceLoadTimeout();
    };
  }, [applyLocale]);

  useEffect(() => {
    if (!loaded) return;
    return installI18nSystemLocaleRefreshRuntime(createBrowserI18nSystemLocaleRefreshRuntimeDeps({
      enabled: usingSystemLocale,
      applyLocale,
      currentLocale: locale,
      detectSystemLocale,
    }));
  }, [loaded, usingSystemLocale, locale, applyLocale]);

  const setLocale = useCallback((l: Locale) => {
    applyLocale(l);
    setUsingSystemLocale(false);
    setPreference(PREF_LANGUAGE, l).catch((error) => {
      reportClientError('i18n.setLocale', 'Failed to persist language preference', error, l);
    });
    // pierce the query cache so any reader using
    // `usePreference(PREF_LANGUAGE, ...)` (Settings panels, locale-
    // dependent diagnostics, the setup-status query that reads
    // the preference map) reflects the new value on its next
    // render. Without this, the raw `setPreference` write lands
    // in SQLite but `usePreference` would keep serving the stale
    // cache entry until the next scheduled refetch.
    invalidatePreferenceQueries(queryClient, { key: PREF_LANGUAGE });
  }, [applyLocale, queryClient]);

  const applySystemLocale = useCallback(() => {
    const systemLocale = detectSystemLocale();
    applyLocale(systemLocale);
    setUsingSystemLocale(true);
    setPreference(PREF_LANGUAGE, null).catch((error) => {
      reportClientError('i18n.applySystemLocale', 'Failed to reset language preference', error);
    });
    invalidatePreferenceQueries(queryClient, { key: PREF_LANGUAGE });
  }, [applyLocale, queryClient]);

  // `t` MUST be wrapped in `useCallback` so consumers
  // that depend on it (and there are many — every file that calls
  // `useI18n()` and lists `t` in a `useCallback`/`useEffect` dep array)
  // don't invalidate downstream memoization on every render. The
  // callback identity is stable per locale; locale change is the only
  // trigger for cache invalidation, which is the intended behavior.
  const t = useCallback((key: TranslationKey): string => translate(locale, key), [locale]);
  const format = useCallback(
    (key: TranslationKey, vars: TranslationVars = {}) => formatTranslation(locale, key, vars),
    [locale],
  );
  const plural = useCallback(
    (
      count: number,
      keys: PluralTranslationKeys,
      vars: TranslationVars = {},
      options: { fallback?: ((formattedCount: string) => string) | undefined } = {},
    ) => formatPluralTranslation(locale, count, keys, vars, options),
    [locale],
  );
  const formatNumber = useCallback((value: number) => formatLocaleNumber(locale, value), [locale]);

  const contextValue = useMemo(() => ({
    locale, usingSystemLocale, setLocale, applySystemLocale, t, format, plural, formatNumber,
  }), [locale, usingSystemLocale, setLocale, applySystemLocale, t, format, plural, formatNumber]);

  if (!loaded) return null;

  return (
    <I18nContext.Provider value={contextValue}>
      {children}
    </I18nContext.Provider>
  );
}

export function useI18n() {
  return useContext(I18nContext);
}

/** Language options for the settings UI, derived from the locale registry. */
export const LANGUAGE_OPTIONS: Array<{ value: Locale; label: string }> =
  localeRegistry.map(l => ({ value: l.code, label: l.label }));
