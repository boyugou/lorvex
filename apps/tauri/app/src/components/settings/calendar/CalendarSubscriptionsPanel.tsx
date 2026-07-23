import { useState } from 'react';
import { useQuery } from '@tanstack/react-query';
import {
  listCalendarSubscriptions,
  type CalendarSubscription,
} from '@/lib/ipc/calendar';
import { useI18n, type TranslationKey } from '@/lib/i18n';
import { isImeComposing } from '@/lib/ime';
import { useConfiguredDayContext } from '@/lib/dayContext';
import { formatTimestamp } from '@/lib/dates/dateLocale';
import { QUERY_KEYS } from '@/lib/query/queryKeys';
import { STALE_DEFAULT } from '@/lib/query/timing';
import { SettingsSection } from '../SettingsPrimitives';
import { XIcon, RecurrenceIcon } from '@/components/ui/icons';
import { Button } from '@/components/ui/Button';
import { Tooltip } from '@/components/ui/Tooltip';
import { ValidatedField } from '@/components/ui/ValidatedField';
import { EVENT_COLORS } from '@/components/calendar/viewSupport';
import { themedSwatch } from '@/lib/colors/themedSwatch';
import { useCalendarSubscriptionActions } from './useCalendarSubscriptionActions';

// subscription `error_message` is a raw, English-only
// Rust string (e.g. "Failed to fetch .ics: error sending request for
// url ..." / "Response is not a valid iCalendar file") that bleeds
// through to the UI verbatim, leaking implementation detail and
// breaking i18n. Map known patterns to a localized phrase; the raw
// string is still discoverable via the <details> disclosure for
// support / debugging. Order is significant — the first matching
// pattern wins.
const SUB_ERROR_PATTERNS: ReadonlyArray<{ test: RegExp; key: TranslationKey }> = [
  { test: /not a valid iCalendar/i, key: 'settings.calendarSubErrorInvalidIcs' as TranslationKey },
  { test: /Invalid calendar subscription URL/i, key: 'settings.calendarSubErrorInvalidUrl' as TranslationKey },
  { test: /truncat/i, key: 'settings.calendarSubErrorTruncated' as TranslationKey },
  { test: /timed out|timeout|deadline exceeded/i, key: 'settings.calendarSubErrorTimeout' as TranslationKey },
  { test: /404|not found/i, key: 'settings.calendarSubErrorNotFound' as TranslationKey },
  { test: /401|403|unauthor|forbidden/i, key: 'settings.calendarSubErrorUnauthorized' as TranslationKey },
  { test: /429|rate.?limit/i, key: 'settings.calendarSubErrorRateLimited' as TranslationKey },
  { test: /too large|exceeds.*size|payload.*size/i, key: 'settings.calendarSubErrorTooLarge' as TranslationKey },
  { test: /dns|resolve|connect|network|sending request|reqwest|tls|ssl/i, key: 'settings.calendarSubErrorNetwork' as TranslationKey },
];

export function localizeCalendarSubscriptionError(
  raw: string,
  t: (key: TranslationKey) => string,
): string {
  for (const { test, key } of SUB_ERROR_PATTERNS) {
    if (test.test(raw)) return t(key);
  }
  return t('settings.calendarSubErrorGeneric' as TranslationKey);
}

function calendarSubscriptionHealthKey(health: CalendarSubscription['sync_health']): TranslationKey {
  switch (health) {
    case 'disabled':
      return 'settings.calendarSubHealthDisabled';
    case 'pending':
      return 'settings.calendarSubHealthPending';
    case 'stale':
      return 'settings.calendarSubHealthStale';
    case 'failing':
      return 'settings.calendarSubHealthFailing';
    default:
      return 'settings.calendarSubHealthHealthy';
  }
}

interface CalendarSubscriptionToggleCopy {
  stateLabel: string;
  ariaLabel: string;
}

type CalendarSubscriptionToggleFormat = (
  key: TranslationKey,
  vars: Record<string, string>,
) => string;

export function buildCalendarSubscriptionToggleCopy(
  sub: Pick<CalendarSubscription, 'name' | 'enabled'>,
  t: (key: TranslationKey) => string,
  format: CalendarSubscriptionToggleFormat,
): CalendarSubscriptionToggleCopy {
  const enabledKey: TranslationKey = 'settings.calendarSubStateEnabled';
  const disabledKey: TranslationKey = 'settings.calendarSubStateDisabled';
  const stateLabel = t(sub.enabled ? enabledKey : disabledKey);
  const nextStateLabel = t(sub.enabled ? disabledKey : enabledKey);

  return {
    stateLabel,
    ariaLabel: format('settings.calendarSubToggleLabel', {
      name: sub.name,
      state: stateLabel,
      nextState: nextStateLabel,
    }),
  };
}

export function CalendarSubscriptionsPanel() {
  const { t, locale } = useI18n();
  const { timezone } = useConfiguredDayContext();

  const { data: subscriptions = [], isLoading } = useQuery({
    queryKey: QUERY_KEYS.calendarSubscriptions(),
    queryFn: ({ signal }) => listCalendarSubscriptions(signal),
    staleTime: STALE_DEFAULT,
  });

  const [showAdd, setShowAdd] = useState(false);
  const [newName, setNewName] = useState('');
  const [newUrl, setNewUrl] = useState('');

  const nextAutoColor = EVENT_COLORS[subscriptions.length % EVENT_COLORS.length] ?? EVENT_COLORS[0]!;
  const {
    addPending,
    colorPending,
    handleAddSubscription,
    handleColorChange,
    handleRemoveSubscription,
    handleRetryNow,
    handleSyncSubscription,
    handleToggleSubscription,
    removePending,
    retryNowPending,
    syncPending,
    togglePending,
  } = useCalendarSubscriptionActions({
    nextAutoColor,
    onAddSuccess: () => {
      setNewName('');
      setNewUrl('');
      setShowAdd(false);
    },
  });

  // a11y: show inline URL validation (not just toast) so
  // the error is reachable via `aria-errormessage`. The toast still
  // fires for sighted hosts' attention, but screen readers rely on
  // the role="alert" paragraph inside ValidatedField.
  const trimmedNewUrl = newUrl.trim();
  const urlLooksValid =
    trimmedNewUrl.length === 0
    || trimmedNewUrl.startsWith('https://');
  const urlError = trimmedNewUrl.length > 0 && !urlLooksValid
    ? t('settings.calendarSubUrlError')
    : null;

  const handleAdd = () => {
    handleAddSubscription(newName, newUrl);
  };

  return (
    <SettingsSection title={t('settings.calendarSubscriptions')}>
      <div className="space-y-3">
        <div className="flex items-center justify-end">
          <button type="button" onClick={() => setShowAdd(!showAdd)}
            className="text-xs text-accent hover:text-accent/80 transition-colors focus-ring-soft rounded-r-control">
            {showAdd ? t('common.cancel') : t('settings.calendarSubAdd')}
          </button>
        </div>

        {showAdd && (
          <div className="space-y-2 bg-surface-2/60 rounded-r-card p-3.5">
            <ValidatedField
              label={t('settings.calendarSubNamePlaceholder')}
              showLabel={false}
            >
              {({ fieldProps }) => (
                <input
                  {...fieldProps}
                  type="text"
                  data-theme-form-control="true"
                  value={newName}
                  onChange={(e) => setNewName(e.target.value)}
                  placeholder={t('settings.calendarSubNamePlaceholder')}
                  aria-label={t('settings.calendarSubNamePlaceholder')}
                  className={`${fieldProps.className} w-full bg-surface-1 border border-surface-3 rounded-r-control px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted outline-hidden focus:border-accent/50 focus-ring-soft`}
                />
              )}
            </ValidatedField>
            <ValidatedField
              label={t('settings.calendarSubUrlPlaceholder')}
              showLabel={false}
              error={urlError}
            >
              {({ fieldProps }) => (
                <input
                  {...fieldProps}
                  type="url"
                  data-theme-form-control="true"
                  value={newUrl}
                  onChange={(e) => setNewUrl(e.target.value)}
                  placeholder="https://example.com/calendar.ics"
                  aria-label={t('settings.calendarSubUrlPlaceholder')}
                  className={`${fieldProps.className} w-full bg-surface-1 border border-surface-3 rounded-r-control px-2.5 py-1.5 text-xs text-text-primary placeholder:text-text-muted outline-hidden focus:border-accent/50 focus-ring-soft font-mono`}
                  onKeyDown={(e) => { if (e.key === 'Enter' && !isImeComposing(e)) handleAdd(); }}
                />
              )}
            </ValidatedField>
            <button type="button" onClick={handleAdd}
              disabled={addPending || !newName.trim() || !newUrl.trim() || Boolean(urlError)}
              className="text-xs px-3 py-1.5 bg-accent text-on-accent rounded-r-control hover:bg-accent/90 disabled:opacity-50 disabled:cursor-not-allowed transition-colors focus-ring-strong">
              {addPending ? t('settings.calendarSubAdding') : t('settings.calendarSubAddButton')}
            </button>
          </div>
        )}

        {isLoading ? (
          <div className="space-y-2 animate-pulse">
            <div className="h-3 w-40 rounded-r-control bg-surface-2" />
            <div className="h-3 w-32 rounded-r-control bg-surface-2" />
          </div>
        ) : subscriptions.length === 0 ? (
          <p className="text-xs text-text-muted italic">{t('settings.calendarSubEmpty')}</p>
        ) : (
          <div className="space-y-2">
            {subscriptions.map((sub: CalendarSubscription) => (
              <SubscriptionRow key={sub.id} sub={sub} t={t} locale={locale} timezone={timezone}
                onToggle={(enabled: boolean) => handleToggleSubscription(sub.id, enabled)}
                onSync={() => handleSyncSubscription(sub.id)}
                onRetryNow={() => handleRetryNow(sub.id)}
                onRemove={() => { void handleRemoveSubscription(sub.id, sub.url); }}
                onColorChange={(color: string | null) => handleColorChange(sub.id, color)}
                colorPending={colorPending}
                syncPending={syncPending}
                removePending={removePending}
                retryNowPending={retryNowPending}
                togglePending={togglePending} />
            ))}
          </div>
        )}
      </div>
    </SettingsSection>
  );
}

function SubscriptionRow({ sub, t, locale, timezone, onToggle, onSync, onRetryNow, onRemove, onColorChange, colorPending, syncPending, removePending, retryNowPending, togglePending }: {
  sub: CalendarSubscription; t: (key: TranslationKey) => string; locale: string; timezone: string;
  onToggle: (enabled: boolean) => void; onSync: () => void; onRetryNow: () => void; onRemove: () => void;
  onColorChange: (color: string | null) => void; colorPending: boolean; syncPending: boolean; removePending: boolean; retryNowPending: boolean; togglePending: boolean;
}) {
  const { format } = useI18n();
  // a feed that has failed at least once surfaces the
  // "Retry now" affordance AND a humanized "next retry" timestamp so
  // the user can see how long the scheduler intends to wait before
  // trying on its own. The retry button clears the backoff gate
  // server-side and triggers an immediate fetch.
  const hasBackoff = sub.consecutive_failures > 0;
  const nextRetryLabel = sub.next_retry_at
    ? formatTimestamp(sub.next_retry_at, locale, timezone)
    : null;
  const [showColors, setShowColors] = useState(false);
  const healthLabel = t(calendarSubscriptionHealthKey(sub.sync_health));
  const toggleCopy = buildCalendarSubscriptionToggleCopy(sub, t, format);
  return (
    <div className="flex items-start gap-3 bg-surface-2/40 rounded-r-card p-3 border border-card">
      <Tooltip label={t('settings.calendarSubChangeColor' as TranslationKey)}>
        <button type="button" onClick={() => setShowColors(!showColors)}
          disabled={colorPending}
          aria-label={t('settings.calendarSubChangeColor' as TranslationKey)}
          className="shrink-0 mt-0.5 w-3.5 h-3.5 rounded-full border border-surface-3 transition-transform hover:scale-110 motion-reduce:hover:scale-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100"
          style={{ backgroundColor: themedSwatch(sub.color || EVENT_COLORS[0], 'tile') }} />
      </Tooltip>
      <div className="flex-1 min-w-0 space-y-1">
        <span className={`text-xs font-medium truncate block ${sub.enabled ? 'text-text-primary' : 'text-text-muted line-through'}`}>{sub.name}</span>
        <p className="text-xs text-text-muted font-mono truncate" title={sub.url}>{sub.url}</p>
        <p className="text-xs text-text-muted/70">{healthLabel}</p>
        {sub.error_message && (
          // localized phrase up front; raw English
          // server/library error tucked inside <details> so it remains
          // available for support without being the headline UX.
          <details className="text-xs text-danger group">
            <summary className="cursor-pointer truncate select-none">
              {localizeCalendarSubscriptionError(sub.error_message, t)}
            </summary>
            <pre className="mt-1 text-2xs whitespace-pre-wrap break-words font-mono text-danger/80 bg-[var(--danger-tint-xs)] rounded-r-control px-2 py-1">
              {sub.error_message}
            </pre>
          </details>
        )}
        {sub.last_fetched_at && !sub.error_message && (
          <p className="text-xs text-text-muted/60">
            {t('settings.calendarSubLastSync' as TranslationKey)}: {formatTimestamp(sub.last_fetched_at, locale, timezone)}
          </p>
        )}
        {hasBackoff && nextRetryLabel && (
          // informational — lets the user see the
          // scheduler's next attempt time without opening diagnostics.
          // Muted to visually de-emphasize compared to the loud red
          // error_message above.
          <p className="text-xs text-text-muted/60">
            {t('settings.calendarSubNextRetry' as TranslationKey)}: {nextRetryLabel}
            <span className="ms-1 text-text-muted/50">
              ({format('settings.calendarSubFailuresCount' as TranslationKey, { 0: sub.consecutive_failures })})
            </span>
          </p>
        )}
        {showColors && (
          <div className="flex gap-1.5 flex-wrap pt-1">
            {EVENT_COLORS.map((c) => (
              // Audit a11y: icon-only buttons need aria-label — `title`
              // is inconsistently exposed (VoiceOver often ignores it,
              // NVDA delays, TalkBack skips). Color swatches were
              // announced only as "button" with no indication of
              // color; the hex code is the least-worst universal
              // label.
              <button
                key={c}
                type="button"
                onClick={() => { onColorChange(c); setShowColors(false); }}
                disabled={colorPending}
                className={`w-5 h-5 rounded-full border-2 transition-transform hover:scale-110 motion-reduce:hover:scale-100 disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:scale-100 ${sub.color === c ? 'border-accent scale-110' : 'border-transparent'}`}
                style={{ backgroundColor: themedSwatch(c, 'tile') }}
                aria-label={`${t('settings.calendarSubChangeColor' as TranslationKey)} — ${c}`}
                aria-pressed={sub.color === c}
              />
            ))}
          </div>
        )}
      </div>
      <div className="shrink-0 flex items-center gap-1">
        {hasBackoff && (
          // labeled "Retry now" button — deliberately
          // verbose instead of an icon-only glyph because the whole
          // point is that the user saw the red error state and is
          // making a deliberate choice to push past the backoff.
          // Renders only when `consecutive_failures > 0` so it doesn't
          // clutter healthy rows.
          <button
            type="button"
            onClick={onRetryNow}
            disabled={retryNowPending}
            className="text-xs px-2 py-0.5 rounded-r-control bg-accent/10 text-accent hover:bg-accent/20 transition-colors disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
          >
            {retryNowPending
              ? t('settings.calendarSubRetryNowPending' as TranslationKey)
              : t('settings.calendarSubRetryNow' as TranslationKey)}
          </button>
        )}
        <Tooltip label={t('settings.calendarSubSyncNow')}>
          <button type="button" onClick={onSync} disabled={syncPending}
            className="text-text-muted hover:text-accent p-1 rounded-r-control transition-colors disabled:opacity-50"
            aria-label={t('settings.calendarSubSyncNow')}>
            <RecurrenceIcon className="w-3.5 h-3.5" />
          </button>
        </Tooltip>
        <button type="button" onClick={() => onToggle(!sub.enabled)}
          disabled={togglePending}
          className={`text-xs px-1.5 py-0.5 rounded-r-control transition-colors disabled:opacity-50 disabled:cursor-not-allowed ${sub.enabled ? 'chip-success chip-success-interactive' : 'text-text-muted bg-surface-3/50'}`}
          aria-pressed={sub.enabled}
          aria-label={toggleCopy.ariaLabel}>
          {toggleCopy.stateLabel}
        </button>
        <Tooltip label={t('common.remove')}>
          {/* canonical icon-button primitive (28×28). The
              `hover:text-danger` ergonomics get folded into the
              `secondary`/ghost recipe; if the danger-on-hover affordance
              is needed back it should be promoted to the Button primitive
              rather than re-rolled here. */}
          <Button
            variant="ghost"
            size="icon"
            onClick={onRemove}
            disabled={removePending}
            aria-label={t('common.remove')}
          >
            <XIcon className="w-3.5 h-3.5" />
          </Button>
        </Tooltip>
      </div>
    </div>
  );
}
