export const SETTINGS_SCROLL_SPY_FALLBACK_MS = 800;

interface SettingsScrollContainerLike {
  addEventListener: (type: 'scrollend', listener: () => void) => void;
  removeEventListener: (type: 'scrollend', listener: () => void) => void;
}

interface SettingsSectionElementLike {
  id: string;
  scrollIntoView: (options: { behavior: 'auto' | 'smooth' }) => void;
}

interface SettingsIntersectionEntryLike {
  boundingClientRect: { top: number };
  isIntersecting: boolean;
  target: { id: string };
}

interface SettingsIntersectionObserverLike {
  disconnect: () => void;
  observe: (element: SettingsSectionElementLike) => void;
}

interface SettingsIntersectionObserverOptionsLike {
  root: SettingsScrollContainerLike;
  rootMargin: string;
  threshold: number;
}

export interface SettingsScrollSpyTimerHost {
  clearTimeout: (handle: unknown) => void;
  setTimeout: (callback: () => void, delayMs: number) => unknown;
}

interface SettingsScrollSpyRuntimeDeps extends SettingsScrollSpyTimerHost {
  createIntersectionObserver: (
    callback: (entries: SettingsIntersectionEntryLike[]) => void,
    options: SettingsIntersectionObserverOptionsLike,
  ) => SettingsIntersectionObserverLike;
  fallbackDelayMs?: number | undefined;
  getElementById: (id: string) => SettingsSectionElementLike | null;
  readPrefersReducedMotion: () => boolean;
  scrollContainer: SettingsScrollContainerLike;
  sectionIds: readonly string[];
  setActiveSection: (sectionId: string) => void;
}

interface SettingsScrollSpyRuntime {
  cleanup: () => void;
  navigate: (sectionId: string) => void;
}

export function buildSettingsSectionIds({
  hasSyncBackends,
  supportsMcpHosting,
}: {
  hasSyncBackends: boolean;
  supportsMcpHosting: boolean;
}): string[] {
  return [
    'settings-section-general',
    'settings-section-appearance',
    ...(hasSyncBackends ? ['settings-section-sync'] : []),
    ...(supportsMcpHosting ? ['settings-section-mcp'] : []),
    'settings-section-calendar',
    'settings-section-data',
  ];
}

export function createBrowserSettingsScrollSpyTimerHost(): SettingsScrollSpyTimerHost {
  return {
    clearTimeout: (handle) => {
      globalThis.clearTimeout(handle as ReturnType<typeof globalThis.setTimeout>);
    },
    setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),
  };
}

export function resolveFirstVisibleSettingsSection(
  entries: readonly SettingsIntersectionEntryLike[],
): string | null {
  const visible = entries
    .filter((entry) => entry.isIntersecting && entry.target.id.trim() !== '')
    .sort((a, b) => a.boundingClientRect.top - b.boundingClientRect.top);
  return visible[0]?.target.id ?? null;
}

export function installSettingsScrollSpyRuntime(
  deps: SettingsScrollSpyRuntimeDeps,
): SettingsScrollSpyRuntime {
  const elements = deps.sectionIds
    .map((id) => deps.getElementById(id))
    .filter((element): element is SettingsSectionElementLike => element !== null);

  let disposed = false;
  let suppressObserver = false;
  let fallbackTimer: unknown = null;

  const clearFallbackTimer = () => {
    if (fallbackTimer === null) return;
    deps.clearTimeout(fallbackTimer);
    fallbackTimer = null;
  };

  const clearSuppression = () => {
    suppressObserver = false;
    clearFallbackTimer();
  };

  const observer = deps.createIntersectionObserver((entries) => {
    if (disposed || suppressObserver) return;
    const nextSectionId = resolveFirstVisibleSettingsSection(entries);
    if (nextSectionId) {
      deps.setActiveSection(nextSectionId);
    }
  }, {
    root: deps.scrollContainer,
    threshold: 0.1,
    rootMargin: '-10% 0px -80% 0px',
  });

  elements.forEach((element) => observer.observe(element));
  deps.scrollContainer.addEventListener('scrollend', clearSuppression);

  const navigate = (sectionId: string) => {
    if (disposed) return;
    const sectionElement = deps.getElementById(sectionId);
    if (!sectionElement) return;
    suppressObserver = true;
    deps.setActiveSection(sectionId);
    sectionElement.scrollIntoView({
      behavior: deps.readPrefersReducedMotion() ? 'auto' : 'smooth',
    });
    clearFallbackTimer();
    fallbackTimer = deps.setTimeout(
      clearSuppression,
      deps.fallbackDelayMs ?? SETTINGS_SCROLL_SPY_FALLBACK_MS,
    );
  };

  const cleanup = () => {
    if (disposed) return;
    disposed = true;
    clearFallbackTimer();
    observer.disconnect();
    deps.scrollContainer.removeEventListener('scrollend', clearSuppression);
  };

  return { cleanup, navigate };
}
