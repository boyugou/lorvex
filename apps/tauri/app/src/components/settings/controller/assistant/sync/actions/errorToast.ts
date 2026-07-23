/**
 * map a `SyncErrorKind` to an actionable toast (user-
 * readable copy + Retry / Open System Settings / Open docs button).
 * Shared between the "Sync Now" catch handler and the SyncMethodCard
 * status line so both surfaces stay in sync.
 *
 * Design: this module is intentionally UI-free — it returns the copy
 * and action descriptor rather than calling `toast.*` itself, because
 * `SyncMethodCard` wants to render the same short text + button inline
 * instead of as a toast. `run.ts` adapts the return value into a
 * priority toast; the card adapts it into an inline row.
 */
import type { useI18n, TranslationKey } from '@/lib/i18n';
import type {
  SyncErrorEnvelope,
  SyncErrorKind,
} from '@/lib/syncBackend/errorKind';

type Translator = (key: TranslationKey) => string;
type Formatter = ReturnType<typeof useI18n>['format'];

interface SyncErrorPresentation {
  /** Short, actionable message (already localized + interpolated). */
  message: string;
  /** Optional action button — label + onClick. */
  action:
    | {
        label: string;
        onClick: () => void;
      }
    | null;
  /** Whether the toast/card row should be styled as "actionable enough
   * to protect from eviction". Currently true for all variants
   *  since the user losing one of these errors silently is much worse
   *  than losing a chatty success toast. */
  priority: boolean;
  /** Returned so callers can still show the raw backend message in
   *  diagnostics / copy-to-clipboard affordances. */
  rawMessage: string;
  /** Pass-through so callers can discriminate without re-parsing. */
  kind: SyncErrorKind;
}

interface BuildSyncErrorPresentationOptions {
  envelope: SyncErrorEnvelope;
  t: Translator;
  format: Formatter;
  retry: () => void;
}

export function buildSyncErrorPresentation({
  envelope,
  t,
  format,
  retry,
}: BuildSyncErrorPresentationOptions): SyncErrorPresentation {
  const base = {
    rawMessage: envelope.message,
    kind: envelope.kind,
    priority: true,
  };

  switch (envelope.kind) {
    case 'offline':
      return {
        ...base,
        message: t('sync.errors.offline'),
        action: { label: t('common.retry'), onClick: retry },
      };
    case 'permissions': {
      // Use the backend-extracted path when present. When absent,
      // the localized message without path interpolation still reads
      // well (we keep a version without `{path}` for that case).
      const message = envelope.path
        ? format('sync.errors.permissionsWithPath', { path: envelope.path })
        : t('sync.errors.permissions');
      return {
        ...base,
        message,
        action: { label: t('common.retry'), onClick: retry },
      };
    }
    case 'timeout':
      return {
        ...base,
        message: t('sync.errors.timeout'),
        action: { label: t('common.retry'), onClick: retry },
      };
    case 'unknown':
    default:
      return {
        ...base,
        message: t('settings.syncRunFailed'),
        action: null,
        priority: false,
      };
  }
}
