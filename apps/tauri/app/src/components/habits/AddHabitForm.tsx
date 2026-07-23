import { useCallback, useEffect, useRef, useState } from 'react';
import { MAX_HABIT_CUE_LENGTH, MAX_TITLE_LENGTH } from '@lorvex/shared/validation';

import { confirm } from '@/lib/dialogs/confirm';
import { useFormController } from '@/lib/forms/useFormController';
import { useI18n } from '@/lib/i18n';
import { createHabit } from '@/lib/ipc/habits';
import type { Habit, HabitFrequencyType } from '@/lib/ipc/habits';
import { toIpcErrorMessage } from '@/lib/ipc/core';
import { defineEntityHooks } from '@/lib/query/defineEntityHooks';
import { Button } from '../ui/Button';
import { SubmitButton } from '../ui/SubmitButton';
import { ValidatedField } from '../ui/ValidatedField';
import { XIcon } from '../ui/icons';
import {
  normalizeHabitTargetCountInput,
  normalizeHabitTargetCountValue,
} from './form.logic';
import { installHabitFormEscapeRuntime } from './AddHabitForm.runtime';

const MAX_HABIT_ICON_LENGTH = 4;
const HABIT_TARGET_MIN = 1;
const HABIT_TARGET_MAX = 50;

interface AddHabitFormProps {
  onClose: () => void;
  /// Optional partial pre-fill driven by the empty-state template
  /// chips. Anything omitted falls back to the form's defaults
  /// (blank name, daily frequency, target count 1) so callers that
  /// just want the bare form can still pass `undefined`.
  initialValues?: Partial<HabitFormValues>;
}

interface HabitFormValues {
  name: string;
  icon: string;
  cue: string;
  frequency: HabitFrequencyType;
  targetCount: number;
}

const habitFormHooks = defineEntityHooks({
  entity: 'habit',
  mutations: {
    create: {
      run: (values: HabitFormValues): Promise<Habit> =>
        createHabit({
          name: values.name.trim(),
          icon: values.icon.trim() || null,
          cue: values.cue.trim() || null,
          frequencyType: values.frequency,
          targetCount: normalizeHabitTargetCountValue(values.targetCount),
        }),
      errorContext: 'create_habit',
    },
  },
});

export function AddHabitForm({ onClose, initialValues }: AddHabitFormProps) {
  const { t } = useI18n();
  // Server-error state stays local — it spans two presentation slots
  // (the `name` field's inline error vs. a form-level <p role="alert">)
  // and isn't a fit for useFormController's per-field error map. The
  // hook owns synchronous validation; backend rejections that may or
  // may not map to a single field stay outside.
  const [serverError, setServerError] = useState<{ field: 'name' | 'form'; message: string } | null>(null);
  const focusOnMountRef = useFocusOnMountRef();
  const formRef = useRef<HTMLFormElement>(null);

  const mutation = habitFormHooks.mutations.create.useMutation({
    successMessage: t('habits.formCreated'),
    errorMessage: t('habits.formCreateFailed'),
    onSuccess: () => onClose(),
    onError: (error) => {
      const detail = toIpcErrorMessage(error);
      const looksLikeNameError = /name|title/i.test(detail);
      setServerError({
        field: looksLikeNameError ? 'name' : 'form',
        message: detail,
      });
    },
  });

  const form = useFormController<HabitFormValues>({
    initial: {
      name: initialValues?.name ?? '',
      icon: initialValues?.icon ?? '',
      cue: initialValues?.cue ?? '',
      frequency: initialValues?.frequency ?? 'daily',
      targetCount: initialValues?.targetCount ?? 1,
    },
    validators: {
      name: (v) => {
        const trimmed = v.trim();
        if (trimmed.length === 0) return t('habits.formNameRequired');
        if (trimmed.length > MAX_TITLE_LENGTH) return t('habits.formNameTooLong');
        return null;
      },
      icon: (v) => (v.length > MAX_HABIT_ICON_LENGTH ? t('habits.formIconTooLong') : null),
      cue: (v) => (v.length > MAX_HABIT_CUE_LENGTH ? t('habits.formCueTooLong') : null),
      targetCount: (v) => {
        const normalized = normalizeHabitTargetCountValue(v);
        if (normalized < HABIT_TARGET_MIN || normalized > HABIT_TARGET_MAX) {
          return t('habits.formTargetOutOfRange');
        }
        return null;
      },
    },
    onSubmit: async (values) => {
      setServerError(null);
      await mutation.mutateAsync(values);
    },
  });

  const nameInlineError = form.errors.name ?? (serverError?.field === 'name' ? serverError.message : null);
  const formLevelError = serverError?.field === 'form' ? serverError.message : null;

  const trimmedName = form.values.name.trim();

  // dismissal paths (X / Cancel / Esc) gate behind a discard
  // confirm when the form is dirty so an accidental click doesn't drop
  // a half-filled form. `form.isDirty` compares values to initial.
  const requestClose = useCallback(async () => {
    if (mutation.isPending) return;
    if (form.isDirty) {
      const ok = await confirm({
        title: t('habits.formDiscardConfirmTitle'),
        message: t('habits.formDiscardConfirmMessage'),
        variant: 'danger',
        confirmLabel: t('habits.formDiscardConfirmAction'),
        cancelLabel: t('habits.formKeepEditing'),
      });
      if (!ok) return;
    }
    onClose();
  }, [form.isDirty, mutation.isPending, onClose, t]);

  // Esc key parity with the X / Cancel buttons. Without this, Esc
  // (handled by the modal shell or native form behaviour) would drop
  // a dirty form silently.
  useEffect(() => {
    return installHabitFormEscapeRuntime({
      windowTarget: window,
      getFormRoot: () => formRef.current,
      requestClose,
    });
  }, [requestClose]);

  const canSubmit =
    trimmedName.length > 0 &&
    trimmedName.length <= MAX_TITLE_LENGTH &&
    form.values.icon.length <= MAX_HABIT_ICON_LENGTH &&
    form.values.cue.length <= MAX_HABIT_CUE_LENGTH &&
    !mutation.isPending;

  const handleSubmit = useCallback(
    (event: React.FormEvent) => {
      event.preventDefault();
      void form.submit();
    },
    [form],
  );

  return (
    <form
      ref={formRef}
      onSubmit={handleSubmit}
      className="mb-6 bg-surface-2 border border-surface-3 rounded-r-panel p-5 space-y-4 shadow-[var(--shadow-tooltip)] animate-[fade-in_0.15s_ease-out]"
      aria-label={t('habits.formTitle')}
    >
      <div className="flex items-center justify-between">
        <h2 className="heading-section">{t('habits.formTitle')}</h2>
        {/* canonical icon-button primitive (28×28). */}
        <Button
          variant="ghost"
          size="icon"
          onClick={() => { void requestClose(); }}
          aria-label={t('common.close')}
        >
          <XIcon className="w-4 h-4" />
        </Button>
      </div>

      <div className="flex gap-2">
        <ValidatedField
          label={t('habits.formIconLabel')}
          showLabel={false}
          error={form.errors.icon}
        >
          {({ fieldProps }) => (
            <label className="contents">
              <span className="sr-only">{t('habits.formIconLabel')}</span>
              <input
                {...fieldProps}
                type="text"
                data-theme-form-control="true"
                value={form.values.icon}
                onChange={(e) => form.set('icon', e.target.value.slice(0, MAX_HABIT_ICON_LENGTH))}
                placeholder={t('habits.formIconPlaceholder')}
                aria-label={t('habits.formIconLabel')}
                className={`${fieldProps.className} w-16 text-center text-base rounded-r-card bg-surface-3/60 border border-surface-3 px-2 py-2 focus-visible:outline-hidden focus:border-accent/50 focus-ring-soft aria-[invalid=true]:border-danger/60`}
              />
            </label>
          )}
        </ValidatedField>
        <ValidatedField
          label={t('habits.formNameLabel')}
          showLabel={false}
          error={nameInlineError}
          className="flex-1 space-y-1"
        >
          {({ fieldProps }) => (
            <label className="contents">
              <span className="sr-only">{t('habits.formNameLabel')}</span>
              <input
                {...fieldProps}
                type="text"
                data-theme-form-control="true"
                ref={focusOnMountRef}
                value={form.values.name}
                onChange={(e) => {
                  form.set('name', e.target.value.slice(0, MAX_TITLE_LENGTH));
                  if (serverError?.field === 'name') setServerError(null);
                }}
                placeholder={t('habits.formNamePlaceholder')}
                maxLength={MAX_TITLE_LENGTH}
                aria-label={t('habits.formNameLabel')}
                className={`${fieldProps.className} w-full text-sm rounded-r-card bg-surface-3/60 border border-surface-3 px-3 py-2 focus-visible:outline-hidden focus:border-accent/50 focus-ring-soft aria-[invalid=true]:border-danger/60`}
              />
            </label>
          )}
        </ValidatedField>
      </div>

      <ValidatedField
        label={t('habits.formCueLabel')}
        showLabel={false}
        error={form.errors.cue}
      >
        {({ fieldProps }) => (
          <label className="block">
            <span className="sr-only">{t('habits.formCueLabel')}</span>
            <input
              {...fieldProps}
              type="text"
              data-theme-form-control="true"
              value={form.values.cue}
              onChange={(e) => form.set('cue', e.target.value.slice(0, MAX_HABIT_CUE_LENGTH))}
              maxLength={MAX_HABIT_CUE_LENGTH}
              placeholder={t('habits.formCuePlaceholder')}
              aria-label={t('habits.formCueLabel')}
              className={`${fieldProps.className} w-full text-sm rounded-r-card bg-surface-3/60 border border-surface-3 px-3 py-2 focus-visible:outline-hidden focus:border-accent/50 focus-ring-soft aria-[invalid=true]:border-danger/60`}
            />
          </label>
        )}
      </ValidatedField>

      <div className="grid grid-cols-2 gap-3">
        <ValidatedField
          label={t('habits.formFrequencyLabel')}
          showLabel={false}
        >
          {({ fieldProps }) => (
            <label className="flex flex-col gap-1">
              <span className="text-xs text-text-muted">{t('habits.formFrequencyLabel')}</span>
              <select
                {...fieldProps}
                data-theme-form-control="true"
                value={form.values.frequency}
                onChange={(e) => form.set('frequency', e.target.value as HabitFrequencyType)}
                className={`${fieldProps.className} text-sm rounded-r-card bg-surface-3/60 border border-surface-3 px-3 py-2 focus-visible:outline-hidden focus:border-accent/50 focus-ring-soft aria-[invalid=true]:border-danger/60`}
              >
                <option value="daily">{t('habits.frequencyDaily')}</option>
                <option value="weekly">{t('habits.frequencyWeekly')}</option>
                <option value="monthly">{t('habits.frequencyMonthly')}</option>
              </select>
            </label>
          )}
        </ValidatedField>
        <ValidatedField
          label={t('habits.formTargetLabel')}
          showLabel={false}
          error={form.errors.targetCount}
        >
          {({ fieldProps }) => (
            <label className="flex flex-col gap-1">
              <span className="text-xs text-text-muted">{t('habits.formTargetLabel')}</span>
              <input
                {...fieldProps}
                type="number"
                data-theme-form-control="true"
                min={HABIT_TARGET_MIN}
                max={HABIT_TARGET_MAX}
                value={form.values.targetCount}
                onChange={(e) => form.set('targetCount', normalizeHabitTargetCountInput(e.target.value))}
                aria-label={t('habits.formTargetLabel')}
                className={`${fieldProps.className} text-sm rounded-r-card bg-surface-3/60 border border-surface-3 px-3 py-2 tabular-nums focus-visible:outline-hidden focus:border-accent/50 focus-ring-soft aria-[invalid=true]:border-danger/60`}
              />
            </label>
          )}
        </ValidatedField>
      </div>

      {formLevelError ? (
        <p role="alert" className="text-xs text-danger">
          {formLevelError}
        </p>
      ) : null}

      <div className="flex items-center justify-end gap-2 pt-1">
        <button
          type="button"
          onClick={() => { void requestClose(); }}
          className="text-xs px-3 py-1.5 rounded-r-card border border-surface-3 text-text-secondary hover:bg-surface-3/60 transition-colors focus-ring-soft"
        >
          {t('common.cancel')}
        </button>
        <SubmitButton
          isSaving={mutation.isPending}
          disabled={!canSubmit}
          savingLabel={t('habits.formSubmitting')}
          className="text-xs px-3 py-1.5 rounded-r-card border border-accent/40 text-accent bg-accent/10 hover:bg-accent/20 active:scale-[0.97] disabled:opacity-50 disabled:cursor-not-allowed focus-ring-soft"
        >
          {t('habits.formSubmit')}
        </SubmitButton>
      </div>
    </form>
  );
}

/**
 * One-shot focus-on-mount ref. Centralised at the bottom of the file
 * so the component body stays focused on form-state wiring.
 */
function useFocusOnMountRef() {
  const focusedRef = useRef(false);
  return useCallback((node: HTMLInputElement | null) => {
    if (focusedRef.current || node === null) return;
    focusedRef.current = true;
    node.focus();
  }, []);
}
