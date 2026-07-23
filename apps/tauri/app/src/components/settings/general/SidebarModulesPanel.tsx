import type { ReactNode } from 'react';

import { useI18n } from '@/lib/i18n';
import { usePreference } from '@/lib/query/usePreference';
import { parseBool } from '@/lib/query/usePreference.logic';
import {
  getModuleState,
  isSidebarPrimaryModule,
  type SidebarModule,
  type SidebarModuleState,
} from '@/lib/sidebarModules';
import {
  BoltIcon,
  CalendarDayIcon,
  CalendarUpcomingIcon,
  ChartIcon,
  ClipboardIcon,
  FlameIcon,
  GridIcon,
  KanbanIcon,
  LinkIcon,
  NotebookIcon,
  RecurrenceIcon,
  SparkleIcon,
  SunIcon,
  TargetIcon,
  ThoughtBubbleIcon,
} from '@/components/ui/icons';
import { AppSelect } from '@/components/ui/AppSelect';
import { Toggle } from '@/components/ui/Toggle';
import { SIDEBAR_MODULE_OPTIONS } from './catalog';
import type { SidebarModulesPanelProps } from './types';

/** Icon lookup for each sidebar module. */
const MODULE_ICONS: Record<SidebarModule, ReactNode> = {
  today: <SunIcon />,
  upcoming: <CalendarUpcomingIcon />,
  all_tasks: <ClipboardIcon />,
  someday: <ThoughtBubbleIcon />,
  calendar: <CalendarDayIcon />,
  eisenhower: <GridIcon />,
  kanban: <KanbanIcon />,
  dependencies: <LinkIcon />,
  habits: <FlameIcon />,
  daily_review: <NotebookIcon />,
  memory: <SparkleIcon />,
  review: <ChartIcon />,
  recurring: <RecurrenceIcon />,
  ai_changelog: <BoltIcon />,
  focus: <TargetIcon />,
};

/** State label i18n key by state. */
const STATE_LABEL_KEYS: Record<SidebarModuleState, Parameters<ReturnType<typeof useI18n>['t']>[0]> = {
  show: 'settings.sidebarStateShow',
  more: 'settings.sidebarStateMore',
  hidden: 'settings.sidebarStateHidden',
};

/** Static Tailwind class maps for the dropdown state indicator dot. */
const STATE_DOT_CLASSES: Record<SidebarModuleState, string> = {
  show: 'bg-accent',
  more: 'bg-text-secondary',
  hidden: 'bg-surface-3',
};

/** Ordered list of all visibility states for the dropdown. */
const ALL_STATES: SidebarModuleState[] = ['show', 'more', 'hidden'];

/** Primary modules can only be 'show' or 'hidden' (no 'more'). */
const PRIMARY_STATES: SidebarModuleState[] = ['show', 'hidden'];

/** Inner content without the wrapping SettingsSection — used when the parent controls collapse. */
export function SidebarModulesPanelContent({
  sidebarModuleConfig,
  onSetSidebarModuleState,
  onResetSidebarModules,
}: Omit<SidebarModulesPanelProps, 'runtimeClass'>) {
  const { t, format } = useI18n();
  const { value: hideEmptyLists, set: setHideEmptyLists } = usePreference(
    'sidebar_hide_empty_lists',
    parseBool(false),
  );

  const primaryModules = SIDEBAR_MODULE_OPTIONS.filter((o) => o.section === 'primary');
  const secondaryModules = SIDEBAR_MODULE_OPTIONS.filter((o) => o.section === 'secondary');

  return (
    <div className="space-y-4">
      <div className="space-y-3">
        <div className="space-y-1.5">
          <p className="text-xs font-medium text-text-muted">{t('settings.sidebarPrimarySection')}</p>
          <div className="rounded-r-card border border-surface-3 bg-surface-1 divide-y divide-surface-3">
            {primaryModules.map((option) => {
              const state = getModuleState(option.id, sidebarModuleConfig);
              const isPrimary = isSidebarPrimaryModule(option.id);
              return (
                <ModuleRow
                  key={option.id}
                  moduleId={option.id}
                  icon={MODULE_ICONS[option.id]}
                  label={t(option.labelKey)}
                  state={state}
                  availableStates={isPrimary ? PRIMARY_STATES : ALL_STATES}
                  onStateChange={(newState) => onSetSidebarModuleState(option.id, newState)}
                  t={t}
                  format={format}
                />
              );
            })}
          </div>
        </div>

        <div className="space-y-1.5">
          <p className="text-xs font-medium text-text-muted">{t('settings.sidebarSecondarySection')}</p>
          <div className="rounded-r-card border border-surface-3 bg-surface-1 divide-y divide-surface-3">
            {secondaryModules.map((option) => {
              const state = getModuleState(option.id, sidebarModuleConfig);
              return (
                <ModuleRow
                  key={option.id}
                  moduleId={option.id}
                  icon={MODULE_ICONS[option.id]}
                  label={t(option.labelKey)}
                  state={state}
                  availableStates={ALL_STATES}
                  onStateChange={(newState) => onSetSidebarModuleState(option.id, newState)}
                  t={t}
                  format={format}
                />
              );
            })}
          </div>
        </div>
      </div>

      <Toggle
        checked={hideEmptyLists}
        onChange={(value) => { void setHideEmptyLists(value); }}
        label={t('settings.hideEmptyLists')}
      />

      <p className="text-xs text-text-muted">{t('settings.sidebarModulesHint')}</p>

      <button
        type="button"
        onClick={onResetSidebarModules}
        className="text-xs text-text-muted hover:text-text-secondary rounded-r-control focus-ring-soft"
      >
        {t('settings.sidebarModulesReset')}
      </button>
    </div>
  );
}

/** A single module row with icon, name, state indicator, and dropdown selector. */
function ModuleRow({
  moduleId,
  icon,
  label,
  state,
  availableStates,
  onStateChange,
  t,
  format,
}: {
  moduleId: SidebarModule;
  icon: ReactNode;
  label: string;
  state: SidebarModuleState;
  availableStates: SidebarModuleState[];
  onStateChange: (state: SidebarModuleState) => void;
  t: ReturnType<typeof useI18n>['t'];
  format: ReturnType<typeof useI18n>['format'];
}) {
  return (
    <div
      className="flex items-center gap-3 px-3 py-2.5 transition-colors"
    >
      <span className={`w-4 h-4 shrink-0 ${state === 'hidden' ? 'text-text-muted/50' : 'text-text-secondary'}`}>
        {icon}
      </span>

      <span
        className={`flex-1 text-sm min-w-0 truncate ${state === 'hidden' ? 'text-text-muted/50 line-through' : 'text-text-primary'}`}
      >
        {label}
      </span>

      <span className={`w-1.5 h-1.5 rounded-full shrink-0 ${STATE_DOT_CLASSES[state]}`} />

      <AppSelect
        value={state}
        variant="muted"
        className="w-24 shrink-0"
        aria-label={format('settings.sidebarModuleVisibilityA11y', { label })}
        onChange={(event) => {
          const value = event.target.value as SidebarModuleState;
          if (value !== state) onStateChange(value);
        }}
      >
        {availableStates.map((s) => (
          <option key={`${moduleId}-${s}`} value={s}>
            {t(STATE_LABEL_KEYS[s])}
          </option>
        ))}
      </AppSelect>
    </div>
  );
}
