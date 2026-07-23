import { emit } from '@/lib/platform/events';
import { isMacRuntime } from '@/lib/platform/platform';
import { useCallback } from 'react';
import { useI18n } from '@/lib/i18n';
import { usePreferenceMutationWithUndo } from '@/lib/hooks/usePreferenceMutationWithUndo';
import { usePreference } from '@/lib/query/usePreference';
import { parseBool } from '@/lib/query/usePreference.logic';
import { PREF_AI_BRIEFING_ENABLED } from '@/lib/preferences/keys';
import { reportClientError } from '@/lib/errors/errorLogging';
import { Toggle } from '@/components/ui/Toggle';
import { LanguagePicker } from '../LanguagePicker';
import { SettingsSection } from '../SettingsPrimitives';
import { AdvancedPreferencesPanel } from './AdvancedPreferencesPanel';
import { DesktopBehaviorPanelContent } from './DesktopBehaviorPanel';
import { HabitRemindersPanelContent } from './HabitRemindersPanel';
import { SidebarModulesPanelContent } from './SidebarModulesPanel';
import { WorkflowPreferencesPanelContent } from './WorkflowPreferencesPanel';
import type { GeneralPreferencesSectionProps } from './types';

export function GeneralPreferencesSection({
  runtimeClass,
  supportsBiometricLock,
  workingHoursStart,
  workingHoursEnd,
  autostart,
  autostartBusy,
  trayIconVisible,
  trayIconBusy,
  trayIconTitleKey,
  trayIconDescKey,
  trayIconVisibleKey,
  trayIconHiddenKey,
  desktopCloseAction,
  memoryLock,
  memoryLockBusy,
  normalizedTimezone,
  timezoneOptions,
  weeklyReviewDay,
  weeklyReviewTime,
  morningBriefingTime,
  sidebarModuleConfig,
  onWorkingHoursStartChange,
  onWorkingHoursEndChange,
  onAutostartToggle,
  onTrayIconToggle,
  onDesktopCloseActionChange,
  onMemoryLockToggle,
  onTimezoneChange,
  onUseSystemTimezone,
  onWeeklyReviewDayChange,
  onWeeklyReviewTimeChange,
  onMorningBriefingTimeChange,
  onSetSidebarModuleState,
  onResetSidebarModules,
}: GeneralPreferencesSectionProps) {
  const { t, locale, setLocale, usingSystemLocale, applySystemLocale } = useI18n();
  const usesMobileLayout = runtimeClass === 'mobile';

  return (
    <>
      <SettingsSection title={t('settings.language')} description={t('settings.languageDesc')}>
        <LanguagePicker
          value={locale}
          usingSystem={usingSystemLocale}
          onChange={setLocale}
          onUseSystem={applySystemLocale}
        />
      </SettingsSection>

      {!usesMobileLayout && (
        <SettingsSection title={t('settings.sidebarModules')} description={t('settings.sidebarModulesDesc')}>
          <SidebarModulesPanelContent
            sidebarModuleConfig={sidebarModuleConfig}
            onSetSidebarModuleState={onSetSidebarModuleState}
            onResetSidebarModules={onResetSidebarModules}
          />
        </SettingsSection>
      )}

      <SettingsSection title={t('settings.workflowSchedule')} description={t('settings.workflowScheduleDesc')}>
        <WorkflowPreferencesPanelContent
          workingHoursStart={workingHoursStart}
          workingHoursEnd={workingHoursEnd}
          onWorkingHoursStartChange={onWorkingHoursStartChange}
          onWorkingHoursEndChange={onWorkingHoursEndChange}
        />
      </SettingsSection>

      <SettingsSection title={t('settings.habitsSection')} description={t('settings.habitsSectionDesc')}>
        <HabitRemindersPanelContent />
      </SettingsSection>

      <SettingsSection title={t('settings.aiBriefing')} description={t('settings.aiBriefingDesc')}>
        <AiBriefingToggle />
      </SettingsSection>

      {!usesMobileLayout && (
        <SettingsSection
          title={t('settings.keyboardShortcuts.title')}
          description={t('settings.keyboardShortcuts.description')}
        >
          <KeyboardShortcutsLauncher />
        </SettingsSection>
      )}

      {!usesMobileLayout && (
        <SettingsSection title={t('settings.desktopBehaviorSection')} description={t('settings.desktopBehaviorSectionDesc')}>
          <DesktopBehaviorPanelContent
            supportsBiometricLock={supportsBiometricLock}
            autostart={autostart}
            autostartBusy={autostartBusy}
            trayIconVisible={trayIconVisible}
            trayIconBusy={trayIconBusy}
            trayIconTitleKey={trayIconTitleKey}
            trayIconDescKey={trayIconDescKey}
            trayIconVisibleKey={trayIconVisibleKey}
            trayIconHiddenKey={trayIconHiddenKey}
            desktopCloseAction={desktopCloseAction}
            memoryLock={memoryLock}
            memoryLockBusy={memoryLockBusy}
            onAutostartToggle={onAutostartToggle}
            onTrayIconToggle={onTrayIconToggle}
            onDesktopCloseActionChange={onDesktopCloseActionChange}
            onMemoryLockToggle={onMemoryLockToggle}
          />
        </SettingsSection>
      )}

      <AdvancedPreferencesPanel
        normalizedTimezone={normalizedTimezone}
        timezoneOptions={timezoneOptions}
        weeklyReviewDay={weeklyReviewDay}
        weeklyReviewTime={weeklyReviewTime}
        morningBriefingTime={morningBriefingTime}
        onTimezoneChange={onTimezoneChange}
        onUseSystemTimezone={onUseSystemTimezone}
        onWeeklyReviewDayChange={onWeeklyReviewDayChange}
        onWeeklyReviewTimeChange={onWeeklyReviewTimeChange}
        onMorningBriefingTimeChange={onMorningBriefingTimeChange}
      />
    </>
  );
}

function KeyboardShortcutsLauncher() {
  const { t } = useI18n();
  // Reuse the existing menu IPC event the title-bar shortcut, the
  // global Cmd+/ binding, and the command-palette entry all emit.
  // Keeps a single panel-open path so the modal lifecycle stays
  // owned by `DesktopMainWindow` rather than fanning state out to
  // each entry point.
  const openShortcuts = useCallback(() => {
    emit('menu://open-shortcuts').catch((error: unknown) => {
      reportClientError(
        'settings.openShortcuts',
        'Failed to emit menu://open-shortcuts from settings',
        error,
        undefined,
        'warn',
      );
    });
  }, []);

  // Platform-correct chord glyph. Mirrors the OnboardingChecklist
  // recipe (QUICK_CAPTURE_HINT_GLYPH) — hard-coding `⌘` on Windows /
  // Linux shows the Command symbol next to a Ctrl-bound shortcut the
  // user cannot actually type. The shortcut itself is the same
  // `KeyboardShortcutsPanel`-toggling chord; only the rendered
  // modifier label changes.
  const shortcutGlyph = isMacRuntime() ? '⌘ /' : 'Ctrl /';

  return (
    <button
      type="button"
      onClick={openShortcuts}
      className="inline-flex items-center gap-2 px-3 py-1.5 rounded-r-control border border-card bg-surface-2/40 text-text-primary text-sm hover:bg-surface-2 active:scale-[0.98] transition-[background-color,transform] duration-150 focus-ring-soft"
    >
      <span aria-hidden="true" className="text-text-muted">{shortcutGlyph}</span>
      <span>{t('settings.keyboardShortcuts.openLabel')}</span>
    </button>
  );
}

function AiBriefingToggle() {
  const { t } = useI18n();
  const { value: enabled, isSaving } = usePreference(
    PREF_AI_BRIEFING_ENABLED,
    parseBool(true),
  );
  // success toast + Undo for the briefing toggle. The hook
  // replaces the raw `usePreference.set` call; we still read via
  // usePreference so the cached value stays in sync with every other
  // consumer that subscribes to this key.
  const { run: runBriefingToggle } = usePreferenceMutationWithUndo({
    key: PREF_AI_BRIEFING_ENABLED,
    errorKeyPrefix: 'settings.aiBriefing',
  });

  return (
    <Toggle
      checked={enabled}
      onChange={(value) => { void runBriefingToggle(value); }}
      disabled={isSaving}
      // Both `'common.enabled'` and `'common.disabled'` are literal
      // `TranslationKey`s, so the typed-key system validates the
      // call without any `as Parameters<typeof t>[0]` cast.
      label={enabled ? t('common.enabled') : t('common.disabled')}
    />
  );
}
