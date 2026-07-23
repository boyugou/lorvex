import { useCallback, useEffect, useRef, useState } from 'react';
import { MAX_MEMORY_CONTENT_LENGTH } from '@lorvex/shared/validation';
import { confirm } from '@/lib/dialogs/confirm';
import type { TranslationKey } from '@/lib/i18n';
import { useFormController } from '@/lib/forms/useFormController';
import { isImeComposing } from '@/lib/ime';
import { AutosizingTextarea } from '../ui/AutosizingTextarea';
import { SparkleIcon } from '../ui/icons';
import { SubmitButton } from '../ui/SubmitButton';
import { ValidatedField } from '../ui/ValidatedField';
import { useCreateMemoryEntryAction } from './useAiMemoryActions';

// Keep in lock-step with MAX_HUMAN_MEMORY_KEY_LENGTH in
// app/src-tauri/src/commands/memory.rs. The backend is the source of
// truth; this constant just drives the `maxLength` attribute so the
// user gets immediate feedback instead of a round-trip rejection.
const MAX_KEY_CHARS = 64;

interface MemoryFormValues {
  key: string;
  content: string;
}

/**
 * Inline "+ Add memory" form that lets standalone users seed their
 * own memory entries without an AI assistant connected.
 *
 * Supports an optional `initialDraft` plus `onDraftChange` callback so a
 * parent (AIMemoryView) can persist the in-flight draft to localStorage
 * across memory-lock transitions — when the window blurs and the lock
 * clamps shut, the parent stashes the current draft and restores it on
 * unlock. The form clears the stash on successful save or explicit
 * cancel by calling `onDraftChange(null)`.
 *
 * `initialDraft` covers two distinct shapes:
 *   - A *rehydrated* stash from a prior session (real user input).
 *   - An *ephemeral CTA pre-fill* — e.g. clicking an empty-cluster
 *     "teach me about people" row seeds `{key: "people.", content: ""}`
 *     to nudge the namespace. Pre-fills are NOT user input and must
 *     stay out of the stash until the user actually types something.
 *
 * The form tracks first-user-interaction internally and only mirrors
 * values up via `onDraftChange` once that has fired. A pre-fill that
 * the user abandons therefore never reaches localStorage.
 */
export function AddMemoryForm({
  t,
  onMutate,
  onClose,
  initialDraft,
  onDraftChange,
}: {
  t: (k: TranslationKey) => string;
  onMutate: () => void;
  onClose: () => void;
  initialDraft?: MemoryFormValues | null;
  onDraftChange?: (draft: MemoryFormValues | null) => void;
}) {
  const keyRef = useRef<HTMLInputElement>(null);
  const mutation = useCreateMemoryEntryAction({
    t,
    onSuccess: () => {
      // Drop the stashed draft once the entry has landed.
      onDraftChange?.(null);
      onMutate();
    },
    onCreated: () => onClose(),
  });

  // shared form state machine. `validateOn: 'submit'` matches
  // the prior `attempted` pattern — silent until the user presses
  // Enter / Save / clicks Save, then "required" errors appear.
  const form = useFormController<MemoryFormValues>({
    initial: initialDraft ?? { key: '', content: '' },
    validators: {
      key: (v) => (v.trim().length === 0 ? t('memory.errorKeyRequired') : null),
      content: (v) => (v.trim().length === 0 ? t('memory.errorContentRequired') : null),
    },
    onSubmit: async ({ key, content }) => {
      // mutation.mutateAsync hands back a promise that rejects on IPC
      // error so useFormController surfaces it via submitError.
      // useCreateMemoryEntryAction owns toast + invalidation already.
      await mutation.mutateAsync({ key: key.trim(), content: content.trim() });
    },
  });

  // `hasUserInput` flips the first time the user types (or otherwise
  // mutates) either field. Until then, the form values may equal an
  // ephemeral CTA pre-fill (`{key: "people.", content: ""}`) seeded by
  // the parent — that pre-fill is a UI affordance, not in-flight user
  // work, so it must stay out of the localStorage stash. Mirroring is
  // gated on this flag to keep the stash contract honest: an
  // abandoned pre-fill (user clicks the CTA, then closes the form
  // without typing) leaves no trace.
  const [hasUserInput, setHasUserInput] = useState(false);

  // Mirror every value change up to the parent so it can persist the
  // draft to localStorage. Only fires after first user interaction,
  // so CTA pre-fills never reach the stash. Once `hasUserInput` is
  // true, an emptied form (user cleared both fields) writes `null` to
  // drop the stash.
  useEffect(() => {
    if (!onDraftChange) return;
    if (!hasUserInput) return;
    const hasContent =
      form.values.key.length > 0 || form.values.content.length > 0;
    if (hasContent) {
      onDraftChange({ key: form.values.key, content: form.values.content });
    } else {
      onDraftChange(null);
    }
  }, [form.values.key, form.values.content, onDraftChange, hasUserInput]);

  // When the parent seeds a new `initialDraft` after mount (e.g. the
  // user clicks an empty-cluster CTA while the form is already open),
  // re-seed the controller. `useFormController` captures `initial`
  // only at mount, so this `reset(nextInitial)` is the supported
  // re-seed path. Guard on `!form.isDirty` so we never clobber a
  // half-typed entry — the CTA is meant to prefill an empty slot, not
  // to discard live work.
  const seededKey = initialDraft?.key;
  const seededContent = initialDraft?.content;
  useEffect(() => {
    if (seededKey === undefined || seededContent === undefined) return;
    if (form.isDirty) return;
    if (
      form.values.key === seededKey &&
      form.values.content === seededContent
    ) {
      return;
    }
    form.reset({ key: seededKey, content: seededContent });
    // We deliberately depend only on the seeded values; `form.reset`
    // is referentially stable and `form.isDirty` / `form.values` are
    // read fresh inside the effect.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [seededKey, seededContent]);

  useEffect(() => {
    // Autofocus the key input when the form mounts — primary affordance.
    requestAnimationFrame(() => keyRef.current?.focus());
  }, []);

  const trimmedKey = form.values.key.trim();
  const trimmedContent = form.values.content.trim();
  const canSubmit =
    trimmedKey.length > 0 && trimmedContent.length > 0 && !mutation.isPending;

  const handleSubmit = () => {
    void form.submit();
  };

  // dismissal paths (Cancel button / Esc) gate behind a discard
  // confirm when the form is dirty so an accidental click doesn't drop
  // a half-typed memory key + content. Mirrors the pattern in
  // `AddHabitForm`. `form.isDirty` compares against the empty
  // initial values, so anything the user typed counts as dirty.
  const requestClose = useCallback(async () => {
    if (mutation.isPending) return;
    if (form.isDirty) {
      const ok = await confirm({
        title: t('memory.formDiscardConfirmTitle'),
        message: t('memory.formDiscardConfirmMessage'),
        variant: 'danger',
        confirmLabel: t('memory.formDiscardConfirmAction'),
        cancelLabel: t('memory.formKeepEditing'),
      });
      if (!ok) return;
    }
    // Explicit dismissal — drop the stash so the next open starts fresh.
    onDraftChange?.(null);
    onClose();
  }, [form.isDirty, mutation.isPending, onClose, onDraftChange, t]);

  return (
    <section
      aria-label={t('memory.addMemory')}
      className="bg-surface-2 border border-accent/40 rounded-r-card p-4 space-y-3"
    >
      <div className="flex items-center gap-2">
        <SparkleIcon className="w-4 h-4 text-accent" />
        <h3 className="text-text-primary text-sm font-medium">
          {t('memory.addMemory')}
        </h3>
      </div>
      <p className="text-text-muted text-xs">{t('memory.addMemoryFormHint')}</p>

      <div className="space-y-2">
        {/* route both inputs through `ValidatedField` so the rendered
            input gets `id` / `aria-invalid` / `aria-errormessage` wired
            up — the shared label span is kept for visual consistency
            with the rest of the AI memory view but the programmatic
            association now goes through ValidatedField's render-prop
            `fieldProps`. */}
        <ValidatedField
          label={t('memory.keyLabel')}
          showLabel={false}
          error={form.errors.key}
        >
          {({ fieldProps }) => (
            <label className="block">
              <span className="text-text-muted text-xs font-medium block mb-1">
                {t('memory.keyLabel')}
              </span>
              <input
                {...fieldProps}
                data-theme-form-control="true"
                ref={keyRef}
                type="text"
                value={form.values.key}
                onChange={(e) => {
                  setHasUserInput(true);
                  form.set('key', e.target.value);
                }}
                onBlur={() => {
                  // `blur` is a no-op for `validateOn: 'submit'`, but
                  // calling it here keeps the shape uniform should we
                  // ever flip the form to blur-mode.
                  form.blur('key');
                }}
                maxLength={MAX_KEY_CHARS}
                placeholder={t('memory.keyPlaceholder')}
                aria-label={t('memory.keyLabel')}
                className={`${fieldProps.className} w-full bg-surface-1 border border-surface-3 rounded-r-card px-3 py-1.5 text-sm text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft aria-[invalid=true]:border-danger/60`}
                onKeyDown={(e) => {
                  if (e.key === 'Escape' && !isImeComposing(e)) {
                    e.preventDefault();
                    void requestClose();
                  }
                }}
              />
            </label>
          )}
        </ValidatedField>
        <ValidatedField
          label={t('memory.valueLabel')}
          showLabel={false}
          error={form.errors.content}
        >
          {({ fieldProps }) => (
            <label className="block">
              <span className="text-text-muted text-xs font-medium block mb-1">
                {t('memory.valueLabel')}
              </span>
              <AutosizingTextarea
                {...fieldProps}
                data-theme-form-control="true"
                value={form.values.content}
                onChange={(e) => {
                  setHasUserInput(true);
                  form.set('content', e.target.value);
                }}
                onBlur={() => form.blur('content')}
                minRows={4}
                resize="vertical"
                maxLength={MAX_MEMORY_CONTENT_LENGTH}
                placeholder={t('memory.valuePlaceholder')}
                aria-label={t('memory.valueLabel')}
                className={`${fieldProps.className} w-full bg-surface-1 border border-surface-3 rounded-r-card px-3 py-2 text-sm text-text-primary placeholder:text-text-muted outline-hidden focus-ring-soft aria-[invalid=true]:border-danger/60`}
                onEscape={() => { void requestClose(); }}
                onKeyDown={(e) => {
                  if (e.key === 'Enter' && (e.metaKey || e.ctrlKey) && !isImeComposing(e)) {
                    e.preventDefault();
                    handleSubmit();
                  }
                }}
              />
            </label>
          )}
        </ValidatedField>
      </div>

      <div className="flex justify-end gap-2">
        <button
          type="button"
          onClick={() => { void requestClose(); }}
          className="rounded-r-card border border-card bg-surface-2/50 text-text-secondary text-xs font-medium px-3 py-1.5 hover:bg-surface-3/60 transition-colors focus-ring-soft"
        >
          {t('common.cancel')}
        </button>
        <SubmitButton
          type="button"
          isSaving={mutation.isPending}
          disabled={!canSubmit}
          onClick={handleSubmit}
          className="rounded-r-card bg-[var(--accent-tint-sm)] hover:bg-[var(--accent-tint-md)] text-accent text-xs font-semibold px-3 py-1.5 disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          {t('memory.saveMemory')}
        </SubmitButton>
      </div>
    </section>
  );
}
