import { useState, useEffect, useRef, useCallback, type ReactNode } from 'react';
import { useQuery, useQueryClient } from '@tanstack/react-query';
import { getVersion } from '@tauri-apps/api/app';
import { useMounted } from '../lib/useMounted';
import { useI18n } from '../lib/i18n';
import { formatPageTitle } from '../lib/pageTitle';
import { markErrorLogsViewed } from '@/lib/ipc/settings';
import { reportClientError } from '../lib/errors/errorLogging';
import { QUERY_KEYS } from '../lib/query/queryKeys';
import { formatTimestamp } from '../lib/dates/dateLocale';
import { useConfiguredDayContext } from '../lib/dayContext';
import { getSyncBackendSupportContext } from '../lib/syncBackend/model';
import { useRuntimeProfile } from '../lib/useRuntimeProfile';
import { prefersReducedMotion } from '../lib/reducedMotion';
import {
  buildSettingsSectionIds,
  createBrowserSettingsScrollSpyTimerHost,
  installSettingsScrollSpyRuntime,
} from './settingsView.runtime';
import { CalendarExportSection } from './settings/calendar/CalendarExportSection';
import { CalendarSubscriptionsPanel } from './settings/calendar/CalendarSubscriptionsPanel';
import { NativeCalendarPanel } from './settings/calendar/NativeCalendarPanel';
import { DataSettingsSection } from './settings/data/DataSettingsSection';
import { McpSetupSection } from './settings/assistant/McpSetupSection';
import { SyncSettingsPanel } from './settings/assistant/sync-settings/SyncSettingsPanel';
import { useAssistantSettingsController } from './settings/controller/useAssistantSettingsController';
import { useDataSettingsController } from './settings/controller/useDataSettingsController';
import { useGeneralSettingsController } from './settings/controller/useGeneralSettingsController';
import { AppearanceSettingsSection } from './settings/appearance/AppearanceSettingsSection';
import { GeneralPreferencesSection } from './settings/general/GeneralPreferencesSection';
import { SettingsScrollSpyNav } from './settings/SettingsScopeTabs';
import { SettingsAutosaveChip } from './settings/SettingsAutosaveChip';
import { SettingsViewSkeleton } from './settings/SettingsViewSkeleton';

interface SettingsViewProps {
  /**
   * deep-link target section id (e.g.
   * `settings-section-mcp`). When provided, the view scrolls to that
   * section as soon as it finishes loading so "Connect your AI
   * assistant" CTAs on ChangelogView / AIMemoryView / DailyReviewView
   * / HabitsView can route the user straight to Assistant MCP
   * instead of dropping them at the top of Settings.
   */
  initialSectionId?: string | undefined;
}

export default function SettingsView({ initialSectionId }: SettingsViewProps = {}) {
  const runtimeProfile = useRuntimeProfile();
  const usesMobileLayout = runtimeProfile.runtimeClass === 'mobile';
  const runtimeClass = runtimeProfile.runtimeClass;
  const trayPresentationKind = runtimeProfile.trayPresentationKind;
  const supportsBiometricLock = runtimeProfile.supportsBiometricLock;
  const syncBackendSupport = getSyncBackendSupportContext(runtimeProfile);
  const hasSyncBackends = syncBackendSupport.availableBackendKinds.length > 0;
  const supportsMcpHosting = runtimeProfile.supportsMcpHosting;
  const { t, locale } = useI18n();
  const { timezone } = useConfiguredDayContext();
  const { data: appVersionData } = useQuery({
    queryKey: QUERY_KEYS.appVersion(),
    // Let TanStack own the error path so a real Tauri IPC failure
    // (closed webview, missing permissions, plugin crash) surfaces
    // through the normal error-state machinery instead of being
    // collapsed into "no version available". The `?? null` below
    // tolerates `data === undefined` for both the loading and error
    // cases, so the rendered output is unchanged for users while
    // callers that look at `error` (DevTools, future telemetry) can
    // diagnose the broken IPC channel.
    queryFn: () => getVersion(),
    staleTime: Infinity,
    gcTime: Infinity,
    refetchOnMount: false,
    refetchOnWindowFocus: false,
    refetchOnReconnect: false,
  });
  const appVersion = appVersionData ?? null;
  const [activeSection, setActiveSection] = useState('settings-section-general');
  const settingsScrollRef = useRef<HTMLDivElement | null>(null);
  const navigateRef = useRef<(sectionId: string) => void>(() => {});
  const settingsMountedRef = useMounted();
  const generalSettings = useGeneralSettingsController({
    runtimeClass,
    trayPresentationKind,
    supportsBiometricLock,
    settingsMountedRef,
  });
  const dataSettings = useDataSettingsController({
    settingsMountedRef,
  });
  const refreshErrorLogs = dataSettings.refreshErrorLogs;
  const formatSyncTimestamp = useCallback((value: string | null): string => {
    if (!value) return t('settings.syncNever');
    if (Number.isNaN(Date.parse(value))) return value;
    return formatTimestamp(value, locale, timezone);
  }, [t, locale, timezone]);
  const assistantSettings = useAssistantSettingsController({
    syncBackendSupport,
    supportsMcpHosting,
    settingsMountedRef,
    formatSyncTimestamp,
    refreshErrorLogs,
  });
  const loaded = generalSettings.ready && assistantSettings.ready;

  useEffect(() => {
    const scrollContainer = settingsScrollRef.current;
    if (!scrollContainer || !loaded) return;
    const settingsDocument = typeof document === 'undefined' ? null : document;
    const settingsWindow = typeof window === 'undefined' ? undefined : window;
    const timerHost = createBrowserSettingsScrollSpyTimerHost();

    const runtime = installSettingsScrollSpyRuntime({
      createIntersectionObserver: (callback, options) => {
        const observer = new IntersectionObserver(
          callback as IntersectionObserverCallback,
          options as IntersectionObserverInit,
        );
        return {
          disconnect: () => observer.disconnect(),
          observe: (element) => observer.observe(element as Element),
        };
      },
      getElementById: (id) => settingsDocument?.getElementById(id) ?? null,
      readPrefersReducedMotion: () => prefersReducedMotion(settingsWindow),
      scrollContainer,
      sectionIds: buildSettingsSectionIds({ hasSyncBackends, supportsMcpHosting }),
      setActiveSection,
      ...timerHost,
    });
    navigateRef.current = runtime.navigate;

    return () => {
      runtime.cleanup();
      navigateRef.current = () => {};
    };
  }, [loaded, hasSyncBackends, supportsMcpHosting]);

  const handleNavigate = useCallback((sectionId: string) => {
    navigateRef.current(sectionId);
  }, []);

  // if the caller asked us to land on a specific section
  // (e.g. "Connect your AI assistant" buttons on ChangelogView, AI
  // Memory, Daily Review, Habits deep-link to `settings-section-mcp`),
  // scroll there as soon as the scroll-spy machinery is wired up. The
  // effect above populates `navigateRef` once `loaded` flips true; we
  // depend on the same flag so `scrollIntoView` finds a mounted
  // element. `consumedRef` makes sure we only auto-scroll once per
  // deep-link — if the user then scrolls away and returns via the
  // sidebar, that's their choice, not ours.
  const autoScrollConsumedRef = useRef<string | null>(null);
  useEffect(() => {
    if (!loaded) return;
    if (!initialSectionId) return;
    if (autoScrollConsumedRef.current === initialSectionId) return;
    autoScrollConsumedRef.current = initialSectionId;
    navigateRef.current(initialSectionId);
  }, [loaded, initialSectionId]);

  // when the user opens Settings → Data (which embeds
  // the Diagnostics panel), write `error_logs_last_viewed_at = now()`
  // so the sidebar badge clears. Scoped to the data section via the
  // scroll-spy's `activeSection` so a user who only reviews General
  // / Appearance doesn't silently acknowledge failures they never
  // looked at. Runs at most once per view-and-scroll: further visits
  // keep the marker monotonic (writes are idempotent — the value
  // only ever advances), so re-firing on subsequent scrolls is a
  // harmless no-op from the badge's perspective.
  const queryClient = useQueryClient();
  useEffect(() => {
    if (activeSection !== 'settings-section-data') return;
    let cancelled = false;
    markErrorLogsViewed()
      .then(() => {
        if (cancelled) return;
        // Refresh the sidebar badge so the acknowledgement lands
        // without waiting for the 30 s poll interval to tick.
        void queryClient.invalidateQueries({ queryKey: QUERY_KEYS.unseenErrorLogCount() });
      })
      .catch((error) => {
        reportClientError(
          'frontend.settings.diagnostics.mark_viewed',
          'Failed to mark error logs viewed',
          error,
        );
      });
    return () => {
      cancelled = true;
    };
  }, [activeSection, queryClient]);

  // Render the heading inside a shared shell so it stays a stable
  // DOM subtree across the loading↔loaded transition; only the body
  // inside the same scroll container changes. Otherwise assistive
  // tech re-announces the heading when the loaded state hydrates.
  const renderHeader = (chip?: ReactNode) => (
    <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
      <div className="flex items-start justify-between gap-3">
        <div>
          <p className="text-text-muted text-xs font-medium mb-1">{t('settings.title')}</p>
          <h2 className="text-text-primary text-2xl font-light">{t('settings.subtitle')}</h2>
          <p className="text-text-muted text-xs mt-2">{t('settings.hint')}</p>
        </div>
        {chip ? <div className="shrink-0 pt-1">{chip}</div> : null}
      </div>
    </header>
  );

  if (!loaded) {
    return (
      <div className="h-full flex flex-col overflow-hidden">
        <title>{formatPageTitle(t('nav.settings'))}</title>
        {renderHeader()}
        <div className="flex-1 min-h-0 pb-4">
          <SettingsViewSkeleton />
        </div>
      </div>
    );
  }

  const navSections = [
    { id: 'settings-section-general', label: t('settings.scopeGeneral') },
    { id: 'settings-section-appearance', label: t('settings.scopeAppearance') },
    ...(hasSyncBackends ? [{ id: 'settings-section-sync', label: t('settings.sync') }] : []),
    ...(supportsMcpHosting ? [{ id: 'settings-section-mcp', label: t('settings.mcpConnect') }] : []),
    // drop the `as Parameters<typeof t>[0]` cast —
    // the `settings.calendar` key is registered in both locales, so
    // the literal flows through `t()`'s `TranslationKey` parameter
    // unchanged. The cast was a refactor footgun: removing the key
    // from `locales/en.ts` would have surfaced as a runtime miss
    // instead of a compile error.
    { id: 'settings-section-calendar', label: t('settings.calendar') },
    { id: 'settings-section-data', label: t('settings.scopeData') },
  ];

  const autosaveChip = (
    <SettingsAutosaveChip state={generalSettings.autosaveState} />
  );

  return (
    <div className="h-full flex flex-col overflow-hidden">
      <title>{formatPageTitle(t('nav.settings'))}</title>
      {renderHeader(autosaveChip)}

        <div className="flex-1 min-h-0 px-4 sm:px-8">
        <div className="h-full rounded-r-panel border border-surface-3 bg-surface-2/20 overflow-hidden">
          <div className={`h-full min-h-0 ${usesMobileLayout ? 'flex flex-col' : 'grid grid-cols-[160px_minmax(0,1fr)]'}`}>
            <SettingsScrollSpyNav
              sections={navSections}
              activeSection={activeSection}
              onNavigate={handleNavigate}
              usesMobileLayout={usesMobileLayout}
            />

            <div
              ref={settingsScrollRef}
              className="min-h-0 overflow-y-auto overscroll-contain px-4 pe-3"
              style={{ scrollbarGutter: 'stable both-edges' }}
            >
              {/* 1 px hairline divider + 12 px (`gap-3`)
                  rhythm between settings groups. `divide-y` paints the
                  1 px stroke at `surface-3/60` so the separator reads
                  as structure without competing with section
                  headings. */}
              <div className="min-h-full pt-4 pb-16 flex flex-col gap-3 divide-y divide-surface-3/60 [&>*]:pt-3 [&>*:first-child]:pt-0">
                <div id="settings-section-general" className="space-y-4">
                    <GeneralPreferencesSection
                    runtimeClass={runtimeClass}
                    supportsBiometricLock={generalSettings.supportsBiometricLock}
                    workingHoursStart={generalSettings.workingHoursStart}
                    workingHoursEnd={generalSettings.workingHoursEnd}
                    autostart={generalSettings.autostart}
                    autostartBusy={generalSettings.autostartBusy}
                    trayIconVisible={generalSettings.trayIconVisible}
                    trayIconBusy={generalSettings.trayIconBusy}
                    trayIconTitleKey={generalSettings.trayIconTitleKey}
                    trayIconDescKey={generalSettings.trayIconDescKey}
                    trayIconVisibleKey={generalSettings.trayIconVisibleKey}
                    trayIconHiddenKey={generalSettings.trayIconHiddenKey}
                    desktopCloseAction={generalSettings.desktopCloseAction}
                    memoryLock={generalSettings.memoryLock}
                    memoryLockBusy={generalSettings.memoryLockBusy}
                    normalizedTimezone={generalSettings.normalizedTimezone}
                    timezoneOptions={generalSettings.timezoneOptions}
                    weeklyReviewDay={generalSettings.weeklyReviewDay}
                    weeklyReviewTime={generalSettings.weeklyReviewTime}
                    morningBriefingTime={generalSettings.morningBriefingTime}
                    sidebarModuleConfig={generalSettings.sidebarModuleConfig}
                    onWorkingHoursStartChange={generalSettings.setWorkingHoursStart}
                    onWorkingHoursEndChange={generalSettings.setWorkingHoursEnd}
                    onAutostartToggle={generalSettings.handleAutostartToggle}
                    onTrayIconToggle={generalSettings.handleTrayIconToggle}
                    onDesktopCloseActionChange={generalSettings.handleDesktopCloseActionChange}
                    onMemoryLockToggle={generalSettings.handleMemoryLockToggle}
                    onTimezoneChange={generalSettings.setTimezone}
                    onUseSystemTimezone={generalSettings.handleUseSystemTimezone}
                    onWeeklyReviewDayChange={generalSettings.setWeeklyReviewDay}
                    onWeeklyReviewTimeChange={generalSettings.setWeeklyReviewTime}
                    onMorningBriefingTimeChange={generalSettings.setMorningBriefingTime}
                    onSetSidebarModuleState={generalSettings.setSidebarModuleState}
                    onResetSidebarModules={generalSettings.resetSidebarModules}
                  />
                </div>

                <div id="settings-section-appearance" className="space-y-4">
                  <AppearanceSettingsSection />
                </div>

                {hasSyncBackends && (
                  <div id="settings-section-sync">
                    <SyncSettingsPanel
                      sync={assistantSettings.sync}
                    />
                  </div>
                )}

                {supportsMcpHosting && (
                  <div id="settings-section-mcp">
                    <McpSetupSection
                      mcp={assistantSettings.mcp}
                    />
                  </div>
                )}

                <div id="settings-section-calendar" className="space-y-4">
                  <NativeCalendarPanel />
                  <CalendarSubscriptionsPanel />
                  <CalendarExportSection />
                </div>

                <div id="settings-section-data" className="space-y-4">
                  <DataSettingsSection
                    data={dataSettings}
                    formatSyncTimestamp={formatSyncTimestamp}
                    appVersion={appVersion}
                  />
                </div>

                {appVersion && (
                  <p className="text-center text-text-muted text-xs pt-2 pb-1">
                    Lorvex v{appVersion}
                  </p>
                )}
              </div>
            </div>
          </div>
        </div>
      </div>
    </div>
  );
}
