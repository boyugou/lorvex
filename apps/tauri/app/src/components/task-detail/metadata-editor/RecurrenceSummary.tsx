import {
  formatRecurrenceSummary,
  type RecurrenceRule,
  type Translator,
} from './shared';

/**
 * Read-only summary row for a persisted recurrence rule. Shown when
 * the field is not in edit mode and the task already has a rule.
 * Renders the localized "↻ every N weeks on Mon" line plus the inline
 * "edit" affordance that flips the parent into edit mode.
 */
export function RecurrenceSummary({
  rule,
  locale,
  t,
  onEdit,
}: {
  rule: RecurrenceRule;
  locale: string;
  t: Translator;
  onEdit: () => void;
}) {
  const frequencyLabels: Record<string, string> = {
    DAILY: t('task.recurrence.daily'),
    WEEKLY: t('task.recurrence.weekly'),
    MONTHLY: t('task.recurrence.monthly'),
    YEARLY: t('task.recurrence.yearly'),
  };
  const summary = formatRecurrenceSummary(
    rule,
    t('task.recurrence.every'),
    frequencyLabels[rule.freq] ?? rule.freq,
    t('task.recurrence.on'),
    t('task.recurrence.until'),
    locale,
    rule.interval,
  );
  return (
    <div>
      <span className="text-text-muted text-xs">{t('task.recurrence')}</span>
      <div className="flex items-center gap-2 mt-0.5">
        <span className="text-text-secondary text-sm">↻ {summary}</span>
        <button
          type="button"
          onClick={onEdit}
          className="text-xs text-text-muted hover:text-text-primary transition-colors rounded-r-control focus-ring-soft"
        >
          {t('common.edit')}
        </button>
      </div>
    </div>
  );
}
