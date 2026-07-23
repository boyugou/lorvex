import { useQuery } from '@tanstack/react-query';
import { useCallback } from 'react';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import { useI18n } from '@/lib/i18n';
import { parseStringArrayPreference } from '@/lib/preferences/parser';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT, STALE_LONG } from '@/lib/query/timing';
import { localeWeekStartDay, localizedWeekdayOptions, parseWeekStartDayPreference } from '@/lib/dates/dateLocale';
import { usePreference } from '@/lib/query/usePreference';
import { parseJson } from '@/lib/query/usePreference.logic';
import {
  PREF_FOCUS_BREAK_MINUTES,
  PREF_FOCUS_CONFIRM_SKIP_BREAK,
  PREF_FOCUS_CONFIRM_EXIT,
  PREF_FOCUS_BREAK_END_ALERT,
  PREF_FOCUS_WINDOW_OPACITY,
} from '@/lib/preferences/keys';
import { Toggle } from '@/components/ui/Toggle';
import { ToggleChip } from '@/components/ui/ToggleChip';
import { TimeInput } from '../SettingsPrimitives';
import type { WorkflowPreferencesPanelProps } from './types';

/** Inner content without the wrapping SettingsSection — used when the parent controls collapse. */
export function WorkflowPreferencesPanelContent({
  workingHoursStart,
  workingHoursEnd,
  onWorkingHoursStartChange,
  onWorkingHoursEndChange,
}: WorkflowPreferencesPanelProps) {
  const { t, locale } = useI18n();
  const defaultWeekStartDay = localeWeekStartDay();

  const { value: weekStartDay, set: setWeekStartDay } = usePreference(
    'week_starts_on',
    (raw) => parseWeekStartDayPreference(raw, defaultWeekStartDay),
    { staleTime: STALE_LONG },
  );
  const weekdayOptions = localizedWeekdayOptions(locale, defaultWeekStartDay, 'short');

  return (
    <div className="space-y-4">
      <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t('settings.workingHours')}</p>
        <p className="text-xs text-text-muted">{t('settings.workingHoursDesc')}</p>
        <div className="flex items-center gap-3 mt-1.5">
          <TimeInput
            value={workingHoursStart}
            onChange={onWorkingHoursStartChange}
            ariaLabel={t('settings.workingHoursStart')}
          />
          <span className="text-text-muted text-sm">{t('settings.to')}</span>
          <TimeInput
            value={workingHoursEnd}
            onChange={onWorkingHoursEndChange}
            ariaLabel={t('settings.workingHoursEnd')}
          />
        </div>
      </div>

      <FocusBreakSection />

      <FocusAppearanceSection />

      <FocusConfirmationsSection />

      <QuietHoursSection />

      <MutedListsSection />

      <div className="space-y-1.5">
        <p className="text-xs text-text-secondary font-medium">{t('settings.weekStartsOn')}</p>
        <div className="flex flex-wrap items-center border border-surface-3 rounded-r-control overflow-hidden w-fit mt-1.5">
          {weekdayOptions.map((option) => (
            <ToggleChip
              key={option.dayIndex}
              size="md"
              variant="segmented"
              onClick={() => { void setWeekStartDay(option.dayIndex); }}
              selected={weekStartDay === option.dayIndex}
              aria-pressed={weekStartDay === option.dayIndex}
            >
              {option.label}
            </ToggleChip>
          ))}
        </div>
      </div>
    </div>
  );
}

const FOCUS_BREAK_OPTIONS = [0, 5, 10] as const;

function FocusBreakSection() {
  const { t } = useI18n();

  const { value: breakMinutes, set: setBreakMinutes } = usePreference(
    PREF_FOCUS_BREAK_MINUTES,
    parseJson(0),
    { staleTime: STALE_LONG },
  );

  const labelForOption = (opt: number): string => {
    if (opt === 0) return t('settings.focusBreakOff');
    if (opt === 5) return t('settings.focusBreak5');
    return t('settings.focusBreak10');
  };

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-text-secondary font-medium">{t('settings.focusBreak')}</p>
      <p className="text-xs text-text-muted">{t('settings.focusBreakDesc')}</p>
      <div className="flex items-center border border-surface-3 rounded-r-control overflow-hidden w-fit mt-1.5">
        {FOCUS_BREAK_OPTIONS.map((opt) => (
          <ToggleChip
            key={opt}
            size="md"
            variant="segmented"
            onClick={() => { void setBreakMinutes(opt); }}
            selected={breakMinutes === opt}
          >
            {labelForOption(opt)}
          </ToggleChip>
        ))}
      </div>
    </div>
  );
}

const FOCUS_OPACITY_MIN = 0.3;
const FOCUS_OPACITY_MAX = 1.0;
const FOCUS_OPACITY_DEFAULT = 0.95;

function clampOpacity(n: number): number {
  if (!Number.isFinite(n)) return FOCUS_OPACITY_DEFAULT;
  return Math.max(FOCUS_OPACITY_MIN, Math.min(FOCUS_OPACITY_MAX, n));
}

function FocusAppearanceSection() {
  const { t, locale } = useI18n();

  const { value: opacity, set: setOpacity } = usePreference(
    PREF_FOCUS_WINDOW_OPACITY,
    (raw) => {
      if (raw === null) return FOCUS_OPACITY_DEFAULT;
      return clampOpacity(parseFloat(raw));
    },
    { staleTime: STALE_LONG },
  );

  const pct = Math.round(opacity * 100);
  const percentLabel = new Intl.NumberFormat(locale, {
    style: 'percent',
    maximumFractionDigits: 0,
  }).format(opacity);

  return (
    <div className="space-y-1.5">
      <div className="flex items-baseline justify-between gap-3">
        <p className="text-xs text-text-secondary font-medium">{t('settings.focus.opacity.label')}</p>
        <span className="text-2xs tabular-nums text-text-muted">{percentLabel}</span>
      </div>
      <p className="text-xs text-text-muted">{t('settings.focus.opacity.description')}</p>
      <input
        type="range"
        min={Math.round(FOCUS_OPACITY_MIN * 100)}
        max={Math.round(FOCUS_OPACITY_MAX * 100)}
        step={1}
        value={pct}
        onChange={(e) => {
          void setOpacity(clampOpacity(Number(e.target.value) / 100));
        }}
        aria-label={t('settings.focus.opacity.label')}
        aria-valuetext={percentLabel}
        className="w-full mt-1.5 accent-accent cursor-pointer"
      />
    </div>
  );
}

/**
 * Surface the three focus-mode safety toggles introduced in so
 * users can opt out of the confirm/alert prompts on a per-preference
 * basis. All three default to `true` — turning any of them off
 * is a deliberate "I know what I'm doing, stop interrupting me" action.
 */
function FocusConfirmationsSection() {
  const { t } = useI18n();

  const { value: confirmSkipBreak, set: setConfirmSkipBreak } = usePreference(
    PREF_FOCUS_CONFIRM_SKIP_BREAK,
    parseJson(true),
    { staleTime: STALE_LONG },
  );
  const { value: confirmExit, set: setConfirmExit } = usePreference(
    PREF_FOCUS_CONFIRM_EXIT,
    parseJson(true),
    { staleTime: STALE_LONG },
  );
  const { value: breakEndAlert, set: setBreakEndAlert } = usePreference(
    PREF_FOCUS_BREAK_END_ALERT,
    parseJson(true),
    { staleTime: STALE_LONG },
  );

  return (
    <div className="space-y-3">
      <div>
        <p className="text-xs text-text-secondary font-medium">{t('settings.focus.confirmations')}</p>
        <p className="text-xs text-text-muted">{t('settings.focus.confirmationsDesc')}</p>
      </div>
      <FocusToggleRow
        label={t('settings.focus.confirmSkipBreak.label')}
        description={t('settings.focus.confirmSkipBreak.description')}
        checked={confirmSkipBreak}
        onChange={(value) => { void setConfirmSkipBreak(value); }}
      />
      <FocusToggleRow
        label={t('settings.focus.confirmExit.label')}
        description={t('settings.focus.confirmExit.description')}
        checked={confirmExit}
        onChange={(value) => { void setConfirmExit(value); }}
      />
      <FocusToggleRow
        label={t('settings.focus.breakEndAlert.label')}
        description={t('settings.focus.breakEndAlert.description')}
        checked={breakEndAlert}
        onChange={(value) => { void setBreakEndAlert(value); }}
      />
    </div>
  );
}

interface FocusToggleRowProps {
  label: string;
  description: string;
  checked: boolean;
  onChange: (value: boolean) => void;
}

function FocusToggleRow({ label, description, checked, onChange }: FocusToggleRowProps) {
  return (
    <div className="flex items-start justify-between gap-3 py-1">
      <div className="space-y-0.5 flex-1 min-w-0">
        <p className="text-xs text-text-primary font-medium">{label}</p>
        <p className="text-xs text-text-muted leading-snug">{description}</p>
      </div>
      <Toggle checked={checked} onChange={onChange} ariaLabel={label} />
    </div>
  );
}

function QuietHoursSection() {
  const { t } = useI18n();

  const { value: start, set: setStart } = usePreference(
    'quiet_hours_start',
    parseJson(''),
    { staleTime: STALE_LONG },
  );
  const { value: end, set: setEnd } = usePreference(
    'quiet_hours_end',
    parseJson(''),
    { staleTime: STALE_LONG },
  );

  const enabled = !!start && !!end;

  const handleToggle = useCallback(async (enable: boolean) => {
    if (enable) {
      await setStart('22:00');
      await setEnd('07:00');
    } else {
      await setStart(null);
      await setEnd(null);
    }
  }, [setStart, setEnd]);

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-text-secondary font-medium">{t('settings.quietHours')}</p>
      <p className="text-xs text-text-muted">{t('settings.quietHoursDesc')}</p>
      <div className="mt-1.5">
        <Toggle
          checked={enabled}
          onChange={(value) => { void handleToggle(value); }}
          label={t('settings.quietHoursEnable')}
        />
      </div>
      {enabled && (
        <div className="flex items-center gap-3 mt-1.5">
          <TimeInput
            value={start}
            onChange={(v) => { void setStart(v); }}
            ariaLabel={t('settings.quietHoursStart')}
          />
          <span className="text-text-muted text-sm">{t('settings.to')}</span>
          <TimeInput
            value={end}
            onChange={(v) => { void setEnd(v); }}
            ariaLabel={t('settings.quietHoursEnd')}
          />
        </div>
      )}
    </div>
  );
}

function MutedListsSection() {
  const { t } = useI18n();

  const { data: lists = [] } = useQuery({
    queryKey: QUERY_KEYS.lists(),
    queryFn: ({ signal }) => getAllLists(signal),
    staleTime: STALE_DEFAULT,
  });

  const parseMutedSet = useCallback((raw: string | null): Set<string> => {
    return new Set<string>(parseStringArrayPreference(raw));
  }, []);

  const { value: mutedSet, set: setMutedPref } = usePreference(
    'notification_muted_lists',
    parseMutedSet,
  );

  const handleToggle = useCallback((listId: string) => {
    const next = new Set(mutedSet);
    if (next.has(listId)) {
      next.delete(listId);
    } else {
      next.add(listId);
    }
    void setMutedPref([...next]);
  }, [mutedSet, setMutedPref]);

  return (
    <div className="space-y-1.5">
      <p className="text-xs text-text-secondary font-medium">{t('settings.mutedLists')}</p>
      <p className="text-xs text-text-muted">{t('settings.mutedListsDesc')}</p>
      {lists.length === 0 ? (
        <p className="text-xs text-text-muted italic mt-1">{t('settings.mutedListsNone')}</p>
      ) : (
        <div className="space-y-1 mt-1.5">
          {lists.map((list) => (
            <div key={list.id} className="py-0.5">
              <Toggle
                checked={mutedSet.has(list.id)}
                onChange={() => handleToggle(list.id)}
                label={`${list.icon ? `${list.icon} ` : ''}${list.name}`}
              />
            </div>
          ))}
        </div>
      )}
    </div>
  );
}
