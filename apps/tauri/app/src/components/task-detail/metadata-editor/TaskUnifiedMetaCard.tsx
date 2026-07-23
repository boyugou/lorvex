import { useEffect, useId, useRef, useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import { getAllLists } from '@/lib/ipc/tasks/lists';
import type { Task } from '@/lib/ipc/tasks/models';
import type { TaskUpdatePatch } from '@/lib/ipc/tasks/mutations/types';
import { formatDueDate } from '@/lib/format';
import { isImeComposing } from '@/lib/ime';
import { formatCalendarDate } from '@/lib/dates/dateLocale';
import { useConfiguredDayContext, getRelativeDateYmd, useConfiguredTimezone } from '@/lib/dayContext';
import { getNextMondayYmd, getNextWeekendYmd } from '@/lib/dayContextMath';
import {
  MAX_ESTIMATED_MINUTES,
  estimatedMinutesDraftChanged,
  estimatedMinutesDraftValue,
  resolveEstimatedMinutesDraftState,
} from '@/lib/estimatedMinutes';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { decodeListSelectionValue, encodeListSelectionValue } from '@/lib/listSelection';
import { formatNumber } from '@/locales';
import { toast } from '@/lib/notifications/toast';
import { DatePicker } from '@/components/ui/DatePicker';
import { AppSelect } from '@/components/ui/AppSelect';
import { CompactNumberInput } from '@/components/ui/CompactNumberInput';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { PRIORITY_NUMERIC_OPTIONS } from '@/components/task-card/support';
import { buildDueDatePatch } from '@/lib/tasks/dueAtPatch.logic';

// ── Types ─────────────────────────────────────────────────────────

type Translator = (key: TranslationKey) => string;
type SavePatch = (patch: TaskUpdatePatch) => Promise<void>;

interface TaskUnifiedMetaCardProps {
  task: Task;
  overdue: boolean;
  locale: string;
  t: Translator;
  onSave: SavePatch;
  isActionable: boolean;
  onDefer: (date: string | null) => void;
}

// ── Shared row styles ─────────────────────────────────────────────

const LABEL_CLASS = 'text-text-muted text-xs font-medium w-16 shrink-0';
const VALUE_BUTTON_CLASS = 'text-start text-xs px-2.5 py-1.5 rounded-r-control bg-surface-2 border border-surface-3 transition-colors hover:bg-surface-3 hover:border-accent/30 cursor-pointer focus-ring-soft min-w-0 flex-1';

// ── Component ─────────────────────────────────────────────────────

export function TaskUnifiedMetaCard({
  task,
  overdue,
  locale,
  t,
  onSave,
  isActionable,
  onDefer,
}: TaskUnifiedMetaCardProps) {
  const { data: lists = [] } = useQuery({ queryKey: QUERY_KEYS.lists(), queryFn: ({ signal }) => getAllLists(signal), staleTime: STALE_DEFAULT });
  const dayContext = useConfiguredDayContext();

  // Show defer only when the task needs attention: overdue or planned for today/past
  const needsDefer = overdue
    || (task.planned_date != null && task.planned_date <= dayContext.todayYmd)
    || (task.due_date != null && task.due_date <= dayContext.todayYmd);
  const dueDateStr = formatDueDate(task.due_date, {
    dayContext,
    locale,
    todayLabel: t('upcoming.today'),
    tomorrowLabel: t('upcoming.tomorrow'),
    yesterdayLabel: t('upcoming.yesterday'),
  });

  const plannedStr = task.planned_date
    ? formatCalendarDate(task.planned_date, locale)
    : null;

  const durationStr = task.estimated_minutes
    ? `${formatNumber(locale, task.estimated_minutes)}${t('common.min')}`
    : null;

  return (
    <div className="rounded-r-card bg-surface-2/30 border border-card overflow-hidden">
      {/* Field rows — consistent label:value pattern */}
      <div className="px-3 py-2 space-y-1.5">
        {/* Due date */}
        <MetaRow label={t('task.dueDate')}>
          <DatePickerButton
            value={task.due_date ?? null}
            display={dueDateStr}
            placeholder={t('task.noDueDate')}
            overdue={overdue}
            onSave={(date) => onSave(buildDueDatePatch(task, date))}
            showClear={!!task.due_date}
          />
        </MetaRow>

        {/* Planned date */}
        <MetaRow label={t('task.plannedDate')}>
          <DatePickerButton
            value={task.planned_date ?? null}
            display={plannedStr}
            placeholder={t('task.noPlannedDate')}
            onSave={(date) => onSave({ planned_date: date })}
            showClear={!!task.planned_date}
          />
        </MetaRow>

        {/* Priority */}
        <MetaRow label={t('task.priority')}>
          <AppSelect
            value={task.priority ?? ''}
            variant="muted"
            popoverLayer="modalPopover"
            className="flex-1"
            aria-label={t('task.priority')}
            onChange={async (e) => {
              const value = e.target.value ? Number(e.target.value) as Task['priority'] : null;
              await onSave({ priority: value });
            }}
          >
            <option value="">{t('task.noPriority')}</option>
            {PRIORITY_NUMERIC_OPTIONS.map((opt) => (
              <option key={opt.value} value={opt.value}>{t(opt.labelKey)}</option>
            ))}
          </AppSelect>
        </MetaRow>

        {/* List */}
        <MetaRow label={t('task.list')}>
          <AppSelect
            value={task.list_id ? encodeListSelectionValue(task.list_id) : ''}
            variant="muted"
            popoverLayer="modalPopover"
            className="flex-1"
            aria-label={t('task.list')}
            onChange={async (e) => {
              if (!e.target.value) return;
              const nextListId = decodeListSelectionValue(e.target.value);
              if (nextListId === null) return;
              await onSave({ list_id: nextListId });
            }}
          >
            {lists.map((list) => (
              <option key={list.id} value={encodeListSelectionValue(list.id)}>{list.icon ?? '•'} {list.name}</option>
            ))}
          </AppSelect>
        </MetaRow>

        {/* Duration */}
        <MetaRow label={t('task.duration')}>
          <DurationField
            key={task.id}
            value={task.estimated_minutes}
            display={durationStr}
            placeholder={t('task.noDuration')}
            locale={locale}
            t={t}
            onSave={async (minutes) => { await onSave({ estimated_minutes: minutes }); }}
          />
        </MetaRow>
      </div>

      {/* Quick due-date chips */}
      {isActionable && (
        <div className="px-3 py-2 border-t border-card">
          <QuickDueDateChips task={task} t={t} onSave={onSave} />
        </div>
      )}

      {/* Defer — only shown when task needs attention (overdue or planned for today/past) */}
      {isActionable && needsDefer && (
        <div className="px-3 py-2 border-t border-card">
          <DeferChips t={t} onDefer={onDefer} />
        </div>
      )}
    </div>
  );
}

// ── Sub-components ────────────────────────────────────────────────

function MetaRow({ label, children }: { label: string; children: React.ReactNode }) {
  return (
    <div className="flex items-center gap-3">
      <span className={LABEL_CLASS}>{label}</span>
      {children}
    </div>
  );
}

function DatePickerButton({
  value,
  display,
  placeholder,
  overdue = false,
  onSave,
  showClear,
}: {
  value: string | null;
  display: string | null;
  placeholder: string;
  overdue?: boolean;
  onSave: (date: string | null) => Promise<void>;
  showClear: boolean;
}) {
  const [open, setOpen] = useState(false);
  const anchorRef = useRef<HTMLButtonElement>(null);

  return (
    <>
      <button
        ref={anchorRef}
        type="button"
        onClick={() => setOpen(true)}
        className={`${VALUE_BUTTON_CLASS} ${
          overdue ? 'text-danger font-medium' : display ? 'text-text-secondary' : 'text-text-muted/50 italic'
        }`}
      >
        {display || placeholder}
      </button>
      {open && (
        <DatePicker
          value={value}
          onChange={async (date) => { await onSave(date); }}
          onClose={() => setOpen(false)}
          anchorRef={anchorRef}
          showClearButton={showClear}
          popoverLayer="modalPopover"
        />
      )}
    </>
  );
}

function DurationField({
  value,
  display,
  placeholder,
  locale,
  t,
  onSave,
}: {
  value: number | null;
  display: string | null;
  placeholder: string;
  locale: string;
  t: Translator;
  onSave: (minutes: number | null) => Promise<void>;
}) {
  const { format } = useI18n();
  const [editing, setEditing] = useState(false);
  // Controlled input so `aria-invalid` reflects the live-typed
  // value (an uncontrolled `defaultValue` + `reportValidity()` +
  // toast pattern shows sighted users a tooltip but leaves screen
  // readers silent).
  const [draft, setDraft] = useState<string>(estimatedMinutesDraftValue(value));
  const errorId = useId();
  const submittedRef = useRef(false);

  useEffect(() => {
    if (!editing) {
      setDraft(estimatedMinutesDraftValue(value));
      submittedRef.current = false;
    }
  }, [editing, value]);

  const { parsed, invalid } = resolveEstimatedMinutesDraftState(draft);
  const errorMessage = invalid
    ? format('capture.durationInvalid', { max: formatNumber(locale, MAX_ESTIMATED_MINUTES) })
    : null;

  if (editing) {
    return (
      <div className="flex flex-col gap-0.5 flex-1">
        <div className="flex gap-1 items-center">
          <CompactNumberInput
            aria-label={t('task.duration')}
            aria-invalid={invalid}
            aria-errormessage={invalid ? errorId : undefined}
            min={1}
            max={MAX_ESTIMATED_MINUTES}
            step="1"
            placeholder={t('common.min')}
            value={draft}
            onChange={(e) => setDraft(e.target.value)}
            autoFocus
            background="surface-3"
            grow
            className="px-2.5 py-1.5"
            onKeyDown={async (e) => {
              if (isImeComposing(e)) return;
              if (e.key === 'Enter') {
                if (invalid) {
                  toast.error(format('capture.durationInvalid', { max: formatNumber(locale, MAX_ESTIMATED_MINUTES) }));
                  return;
                }
                submittedRef.current = true;
                if (estimatedMinutesDraftChanged(value, parsed)) {
                  await onSave(parsed);
                }
                setEditing(false);
              }
              if (e.key === 'Escape') setEditing(false);
            }}
            onBlur={async () => {
              if (submittedRef.current) {
                submittedRef.current = false;
                return;
              }
              if (invalid) {
                toast.error(format('capture.durationInvalid', { max: formatNumber(locale, MAX_ESTIMATED_MINUTES) }));
                return;
              }
              submittedRef.current = true;
              if (estimatedMinutesDraftChanged(value, parsed)) {
                await onSave(parsed);
              }
              setEditing(false);
            }}
          />
          <span className="text-text-muted text-xs shrink-0">{t('common.min')}</span>
        </div>
        {errorMessage && (
          <p id={errorId} role="alert" className="text-3xs text-danger">
            {errorMessage}
          </p>
        )}
      </div>
    );
  }

  return (
    <button
      type="button"
      onClick={() => {
        setDraft(estimatedMinutesDraftValue(value));
        setEditing(true);
      }}
      className={`${VALUE_BUTTON_CLASS} ${display ? 'text-text-secondary' : 'text-text-muted/50 italic'}`}
    >
      {display || placeholder}
    </button>
  );
}

function QuickDueDateChips({ task, t, onSave }: { task: Task; t: Translator; onSave: SavePatch }) {
  const { timezone } = useConfiguredTimezone();

  const chips: Array<{ label: string; date: string | null }> = [
    { label: t('upcoming.today'), date: getRelativeDateYmd(timezone, 0) },
    { label: t('upcoming.tomorrow'), date: getRelativeDateYmd(timezone, 1) },
    { label: t('capture.weekend'), date: getNextWeekendYmd(timezone) },
    { label: t('capture.nextWeek'), date: getNextMondayYmd(timezone) },
  ];

  const hasDate = task.due_date !== null;

  return (
    <div className="flex items-center gap-1.5 flex-wrap">
      <span className="text-text-muted/50 text-3xs font-medium shrink-0">{t('task.dueDate')}</span>
      {chips.map((chip) => {
        const isActive = chip.date !== null && task.due_date === chip.date;
        return (
          <button
            type="button"
            key={chip.label}
            onClick={() => onSave(buildDueDatePatch(task, isActive ? null : chip.date))}
            className={`text-2xs px-2 py-0.5 rounded-full border transition-colors focus-ring-soft ${
              isActive
                ? 'bg-accent text-on-accent border-accent active:scale-[0.97]'
                : 'border-card text-text-muted/70 hover:border-accent/40 hover:text-accent'
            }`}
          >
            {chip.label}
          </button>
        );
      })}
      {hasDate && (
        <button
          type="button"
          onClick={() => onSave(buildDueDatePatch(task, null))}
          className="text-2xs px-2 py-0.5 rounded-full border border-card text-text-muted/50 hover:border-danger/40 hover:text-danger transition-colors focus-ring-soft"
        >
          {t('quickdate.clear')}
        </button>
      )}
    </div>
  );
}

function DeferChips({ t, onDefer }: { t: Translator; onDefer: (date: string | null) => void }) {
  const { timezone } = useConfiguredTimezone();

  const chips: Array<{ label: string; days: number }> = [
    { label: t('task.defer.1day'), days: 1 },
    { label: t('task.defer.3days'), days: 3 },
    { label: t('task.defer.1week'), days: 7 },
  ];

  return (
    <div className="flex items-center gap-1.5 flex-wrap">
      <span className="text-warning/60 text-3xs font-medium shrink-0">{t('task.defer')}</span>
      {chips.map((chip) => (
        <button
          type="button"
          key={chip.days}
          onClick={() => onDefer(getRelativeDateYmd(timezone, chip.days))}
          className="text-2xs px-2 py-0.5 rounded-full border border-warning/30 text-warning/70 hover:border-warning/50 hover:text-warning transition-colors focus-ring-soft"
        >
          {chip.label}
        </button>
      ))}
    </div>
  );
}
