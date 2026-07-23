import type { TranslationKey } from '@/lib/i18n';
import { toIpcErrorMessage } from '@/lib/ipc/core.logic';
import { reportClientError } from '@/lib/errors/errorLogging';
import { toast } from '@/lib/notifications/toast';

export function reportCalendarError(
  action: 'create' | 'update' | 'delete' | 'undo-delete' | 'skipOccurrence',
  error: unknown,
  t: (key: TranslationKey) => string,
  context?: Record<string, unknown>,
): void {
  const details = toIpcErrorMessage(error);
  const contextText = context ? ` context=${JSON.stringify(context)}` : '';
  reportClientError(
    'frontend.calendar',
    `Failed to ${action} calendar event`,
    error,
    `${details}${contextText}`,
    'error',
  );
  // route through errorWithDetail so disk-full sentinels and
  // Rust-internal leakage (PoisonError, Utf8Error, objc2 ptrs) are redacted
  // into the localized fallback instead of rendered verbatim in the toast.
  toast.errorWithDetail(error, t('common.error'));
}

export function reportCalendarTaskActionError(
  action: string,
  error: unknown,
  taskId: string,
): void {
  reportClientError(
    `calendar.${action}`,
    `Calendar task action failed: ${action}`,
    error,
    taskId,
    'warn',
  );
}

export const EVENT_COLORS = [
  '#4A90D9', '#E5534B', '#57AB5A', '#DAAA3F', '#986EE2',
  '#CC6B2C', '#768390', '#E275AD',
];

/** Maps each event color hex to its i18n key for screen-reader-friendly labels. */
export const EVENT_COLOR_NAME_KEYS: Record<string, TranslationKey> = {
  '#4A90D9': 'calendar.colorBlue',
  '#E5534B': 'calendar.colorRed',
  '#57AB5A': 'calendar.colorGreen',
  '#DAAA3F': 'calendar.colorYellow',
  '#986EE2': 'calendar.colorPurple',
  '#CC6B2C': 'calendar.colorOrange',
  '#768390': 'calendar.colorGray',
  '#E275AD': 'calendar.colorPink',
};
