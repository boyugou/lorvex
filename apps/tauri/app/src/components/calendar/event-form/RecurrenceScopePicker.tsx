import { useCallback, useEffect, useRef, useState, type KeyboardEvent } from 'react';
import { useI18n } from '@/lib/i18n';
import { Modal } from '@/components/ui/Modal';
import {
  recurrenceScopeAbortAll,
  recurrenceScopeReject,
  recurrenceScopeResolve,
  usePendingRecurrenceScope,
  type PendingRecurrenceScope,
  type RecurrenceScope,
} from './recurrenceScope';
import {
  handleRecurrenceScopeKeyboardNavigation,
  RECURRENCE_SCOPE_ORDER,
} from './recurrenceScopeKeyboard';

/**
 * Global host for the recurring-event scope picker. Mount once at the
 * app root, alongside `<ConfirmHost />`. Render-side counterpart of
 * `pickRecurrenceScope()` in `recurrenceScope.ts`.
 *
 * Three options cover the recurring-edit decisions users need:
 *
 *   1. This event only           — apply just to the tapped occurrence
 *   2. This and following events — split the series at the tapped date
 *   3. All events in the series  — apply to the whole recurrence rule
 *
 * Default selection is "This event only" — the narrowest, least-destructive
 * choice.
 */
export function RecurrenceScopeHost() {
  const pending = usePendingRecurrenceScope();
  // Reject all in-flight prompts with `RecurrenceScopeCancelled` when
  // the host unmounts so `await pickRecurrenceScope()` callers never
  // deadlock past a route change or app-shell swap.
  useEffect(() => {
    return () => {
      recurrenceScopeAbortAll();
    };
  }, []);
  if (!pending) return null;
  // Re-key on `pending.id` to reset local "selected" state when a
  // fresh pick queues up behind a previous one.
  return <RecurrenceScopePickerInner key={pending.id} pending={pending} />;
}

function RecurrenceScopePickerInner({ pending }: { pending: PendingRecurrenceScope }) {
  const { t } = useI18n();
  const titleKey = pending.mode === 'delete'
    ? 'calendar.recurrenceScope.deleteTitle'
    : 'calendar.recurrenceScope.editTitle';
  const subtitleKey = pending.mode === 'delete'
    ? 'calendar.recurrenceScope.deleteSubtitle'
    : 'calendar.recurrenceScope.editSubtitle';

  const [selected, setSelected] = useState<RecurrenceScope>('thisOnly');
  const settlingRef = useRef(false);
  const cancelRef = useRef<HTMLButtonElement>(null);
  const okRef = useRef<HTMLButtonElement>(null);
  const scopeButtonRefs = useRef<Record<RecurrenceScope, HTMLButtonElement | null>>({
    thisOnly: null,
    thisAndFollowing: null,
    allInSeries: null,
  });

  const selectScope = useCallback((scope: RecurrenceScope) => {
    setSelected(scope);
    scopeButtonRefs.current[scope]?.focus();
  }, []);

  const handleConfirm = useCallback(() => {
    if (settlingRef.current) return;
    settlingRef.current = true;
    recurrenceScopeResolve(selected);
  }, [selected]);

  const handleCancel = useCallback(() => {
    if (settlingRef.current) return;
    settlingRef.current = true;
    recurrenceScopeReject();
  }, []);

  // Auto-focus the "OK" button on open. Unlike `confirm()`'s
  // cancel-focus default, the picker is not destructive on confirm — it
  // re-prompts only if the user picks "All in series" via the radio +
  // OK. Pressing Enter applies the pre-selected default ("This event
  // only"), which is the safe least-surprising behavior.
  useEffect(() => {
    okRef.current?.focus();
  }, []);

  const handleRadioGroupKeyDown = useCallback((event: KeyboardEvent<HTMLDivElement>) => {
    handleRecurrenceScopeKeyboardNavigation({
      current: selected,
      key: event.key,
      preventDefault: () => event.preventDefault(),
      selectScope,
    });
  }, [selectScope, selected]);

  return (
    <Modal
      open
      onClose={handleCancel}
      size="sm"
      panelClassName="px-6 py-5 mx-4"
      ariaLabelledBy="recurrence-scope-title"
      triggerElement={pending.triggerElement}
    >
      <h3 id="recurrence-scope-title" className="text-text-primary text-sm font-semibold mb-1">
        {t(titleKey)}
      </h3>
      <p className="text-text-secondary text-xs leading-relaxed mb-4">
        {t(subtitleKey)}
      </p>
      <div
        className="space-y-1.5 mb-5"
        role="radiogroup"
        aria-labelledby="recurrence-scope-title"
        onKeyDown={handleRadioGroupKeyDown}
      >
        {RECURRENCE_SCOPE_ORDER.map((scope) => (
          <RecurrenceScopeOption
            key={scope}
            scope={scope}
            selected={selected === scope}
            onSelect={() => selectScope(scope)}
            buttonRef={(element) => { scopeButtonRefs.current[scope] = element; }}
            label={t(`calendar.recurrenceScope.${scope}.label`)}
            description={t(`calendar.recurrenceScope.${scope}.description`)}
          />
        ))}
      </div>
      <div className="flex gap-2.5 justify-end">
        <button
          ref={cancelRef}
          type="button"
          onClick={handleCancel}
          className="rounded-r-control border border-card bg-surface-2/50 text-text-secondary text-xs font-medium px-4 py-2 hover:bg-surface-3/60 active:scale-[0.97] transition-[color,background-color,transform] focus-ring-strong"
        >
          {t('calendar.recurrenceScope.cancel')}
        </button>
        <button
          ref={okRef}
          type="button"
          onClick={handleConfirm}
          className="rounded-r-control text-xs font-semibold px-4 py-2 active:scale-[0.97] transition-[color,background-color,transform] focus-ring-strong bg-accent/15 hover:bg-accent/25 text-accent"
        >
          {t('calendar.recurrenceScope.ok')}
        </button>
      </div>
    </Modal>
  );
}

function RecurrenceScopeOption({
  scope,
  selected,
  onSelect,
  buttonRef,
  label,
  description,
}: {
  scope: RecurrenceScope;
  selected: boolean;
  onSelect: () => void;
  buttonRef: (element: HTMLButtonElement | null) => void;
  label: string;
  description: string;
}) {
  return (
    <button
      ref={buttonRef}
      type="button"
      role="radio"
      aria-checked={selected}
      tabIndex={selected ? 0 : -1}
      onClick={onSelect}
      onKeyDown={(event) => {
        if (event.key === ' ') {
          event.preventDefault();
          onSelect();
        }
      }}
      data-scope={scope}
      className={
        'w-full text-start rounded-r-control border px-3 py-2.5 transition-[border-color,background-color] focus-ring-strong ' +
        (selected
          ? 'border-accent/60 bg-accent/10'
          : 'border-card bg-surface-2/30 hover:bg-surface-3/40 hover:border-surface-3')
      }
    >
      <div className="flex items-start gap-2.5">
        <span
          aria-hidden="true"
          className={
            'mt-0.5 inline-flex h-3.5 w-3.5 shrink-0 items-center justify-center rounded-full border ' +
            (selected ? 'border-accent bg-accent/20' : 'border-surface-3')
          }
        >
          {selected ? <span className="block h-1.5 w-1.5 rounded-full bg-accent" /> : null}
        </span>
        <span className="flex-1 min-w-0">
          <span className="block text-text-primary text-xs font-medium">{label}</span>
          <span className="block text-text-muted text-2xs mt-0.5 leading-relaxed">
            {description}
          </span>
        </span>
      </div>
    </button>
  );
}
