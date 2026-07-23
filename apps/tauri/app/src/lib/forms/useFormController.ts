import { useCallback, useMemo, useRef, useState } from 'react';

import { useMounted } from '../useMounted';
import {
  computeFieldDirty,
  computeIsDirty,
  emptyErrors,
  isErrorsClean,
  runFieldValidator,
  runValidators,
  type DirtyOf,
  type ErrorsOf,
  type Validators,
} from './useFormController.logic';

/**
 * Controls when validators fire. The default `'submit'` mirrors how
 * the hand-rolled forms in this codebase already behave — they only
 * surface errors after the user presses Enter / clicks Save, so
 * users don't see "title required" the moment the form mounts.
 */
type ValidateOn = 'submit' | 'blur' | 'change';

export interface UseFormControllerOptions<TValues extends object> {
  /**
   * Initial values. The reference is captured once (via lazy ref)
   * — re-rendering with a different `initial` object after mount does
   * NOT re-seed the form. Callers that need to reset to a new initial
   * snapshot should call `reset(nextInitial)`.
   */
  initial: TValues;
  validators?: Validators<TValues> | undefined;
  validateOn?: ValidateOn | undefined;
  /**
   * Submit handler. May be sync or async. When it throws, the hook
   * captures the error in `submitError` and `submit()` resolves to
   * `false` so callers can branch without try/catch at every site.
   */
  onSubmit: (values: TValues) => void | Promise<void>;
}

export interface FormController<TValues extends object> {
  values: TValues;
  errors: ErrorsOf<TValues>;
  fieldDirty: DirtyOf<TValues>;
  /** True when ANY field differs from initial. */
  isDirty: boolean;
  /** True when no field currently has an error. */
  isValid: boolean;
  /** True while `onSubmit` is in flight. */
  isSaving: boolean;
  /** Captured value of the most recent thrown submit error, or `null`. */
  submitError: unknown;
  /** True after the first `submit()` attempt — drives 'submit'-mode error gating. */
  submitAttempted: boolean;

  /** Set a single field. */
  set<K extends keyof TValues>(key: K, value: TValues[K]): void;
  /** Patch multiple fields in one render. */
  setValues(patch: Partial<TValues>): void;
  /**
   * Mark a field as blurred. Triggers validation when `validateOn ===
   * 'blur'`. No-op for other modes.
   */
  blur<K extends keyof TValues>(key: K): void;
  /**
   * Run validators + invoke `onSubmit`. Returns `true` on success,
   * `false` if validation failed or `onSubmit` threw. Safe to call
   * concurrently — re-entrant calls while `isSaving` is true return
   * `false` without firing `onSubmit` again.
   */
  submit(): Promise<boolean>;
  /**
   * Reset every field to its initial value (or to `nextInitial` if
   * provided). Clears errors, dirty tracking, submit state.
   */
  reset(nextInitial?: TValues): void;
  /** Imperative validate trigger (e.g. for blur on inputs you don't render with a wrapper). */
  validateField<K extends keyof TValues>(key: K): void;
  validateAll(): boolean;
}

/**
 * Generic form state machine.
 *
 * Owns: per-field values, dirty tracking (vs. initial), per-field
 * errors, composite isDirty / isValid / isSaving, reset to initial,
 * and a submit() that runs validators then calls a user-provided
 * onSubmit. By default validators only run on submit so users don't
 * get error spam while typing — opt into stricter modes with
 * `validateOn`.
 *
 * Intentionally NOT included: keystroke-level form-level error
 * surfacing, async validators, schema integration, field arrays.
 * Those are scope-creep; the four migrating forms only need the
 * primitives above. Add them when a real consumer demands it.
 */
export function useFormController<TValues extends object>(
  options: UseFormControllerOptions<TValues>,
): FormController<TValues> {
  const { onSubmit } = options;
  const validateOn: ValidateOn = options.validateOn ?? 'submit';

  // Capture `initial` lazily so the hook is robust to inline-object
  // callers (every render produces a fresh `{...}` literal). Callers
  // that need to re-seed should use `reset(nextInitial)`.
  const initialRef = useRef<TValues>(options.initial);

  const [values, setValuesState] = useState<TValues>(initialRef.current);
  const [errors, setErrors] = useState<ErrorsOf<TValues>>(() => emptyErrors(initialRef.current));
  const [isSaving, setIsSaving] = useState(false);
  const [submitError, setSubmitError] = useState<unknown>(null);
  const [submitAttempted, setSubmitAttempted] = useState(false);

  // The validators map is read fresh from props every render, so a
  // caller passing inline arrow functions doesn't get stale closures.
  // We stash it in a ref to keep `submit` / `validateField` referentially
  // stable for downstream `useEffect` dep arrays.
  const validatorsRef = useRef<Validators<TValues>>(options.validators ?? {});
  validatorsRef.current = options.validators ?? {};

  const onSubmitRef = useRef(onSubmit);
  onSubmitRef.current = onSubmit;

  const mountedRef = useMounted();

  // Track in-flight submission via a ref so concurrent `submit()`
  // calls (e.g. double-click) collapse to one IPC. The `isSaving`
  // state is what callers render against; the ref is what we consult
  // synchronously to short-circuit re-entry.
  const submittingRef = useRef(false);

  const fieldDirty = useMemo<DirtyOf<TValues>>(
    () => computeFieldDirty(initialRef.current, values),
    [values],
  );
  const isDirty = useMemo(() => computeIsDirty(initialRef.current, values), [values]);
  const isValid = useMemo(() => isErrorsClean(errors), [errors]);

  const set = useCallback(<K extends keyof TValues>(key: K, value: TValues[K]) => {
    setValuesState((previous) => {
      if (Object.is(previous[key], value)) return previous;
      const next = { ...previous, [key]: value };
      if (validateOn === 'change') {
        setErrors((prevErrors) => {
          const fieldError = runFieldValidator(key, next, validatorsRef.current);
          if (Object.is(prevErrors[key], fieldError)) return prevErrors;
          return { ...prevErrors, [key]: fieldError };
        });
      } else if (validateOn === 'submit' || validateOn === 'blur') {
        // If the field already has a surfaced error (from a prior
        // submit / blur) and the user is now editing it, clear that
        // error eagerly — leaving it red while the user retypes is
        // user-hostile. New errors only re-surface on the next gate.
        setErrors((prevErrors) =>
          prevErrors[key] === null ? prevErrors : { ...prevErrors, [key]: null },
        );
      }
      return next;
    });
  }, [validateOn]);

  const setValues = useCallback((patch: Partial<TValues>) => {
    setValuesState((previous) => {
      let changed = false;
      const next = { ...previous };
      for (const key of Object.keys(patch) as Array<keyof TValues>) {
        const value = patch[key];
        if (value !== undefined && !Object.is(previous[key], value)) {
          next[key] = value as TValues[typeof key];
          changed = true;
        }
      }
      return changed ? next : previous;
    });
  }, []);

  const validateField = useCallback(<K extends keyof TValues>(key: K) => {
    setErrors((prevErrors) => {
      const fieldError = runFieldValidator(key, valuesRef.current, validatorsRef.current);
      if (Object.is(prevErrors[key], fieldError)) return prevErrors;
      return { ...prevErrors, [key]: fieldError };
    });
  }, []);

  // Mirror `values` into a ref so `validateField` / `submit` /
  // `validateAll` can read the latest snapshot without subscribing to
  // it (which would invalidate every memoized callback on every
  // keystroke).
  const valuesRef = useRef(values);
  valuesRef.current = values;

  const blur = useCallback(<K extends keyof TValues>(key: K) => {
    if (validateOn !== 'blur') return;
    validateField(key);
  }, [validateOn, validateField]);

  const validateAll = useCallback((): boolean => {
    const next = runValidators(valuesRef.current, validatorsRef.current);
    setErrors(next);
    return isErrorsClean(next);
  }, []);

  const reset = useCallback((nextInitial?: TValues) => {
    if (nextInitial !== undefined) {
      initialRef.current = nextInitial;
    }
    setValuesState(initialRef.current);
    setErrors(emptyErrors(initialRef.current));
    setSubmitError(null);
    setSubmitAttempted(false);
    setIsSaving(false);
    submittingRef.current = false;
  }, []);

  const submit = useCallback(async (): Promise<boolean> => {
    if (submittingRef.current) return false;
    setSubmitAttempted(true);
    if (!validateAll()) return false;
    submittingRef.current = true;
    setIsSaving(true);
    setSubmitError(null);
    try {
      await onSubmitRef.current(valuesRef.current);
      if (mountedRef.current) {
        setIsSaving(false);
      }
      submittingRef.current = false;
      return true;
    } catch (error) {
      if (mountedRef.current) {
        setSubmitError(error);
        setIsSaving(false);
      }
      submittingRef.current = false;
      return false;
    }
  }, [mountedRef, validateAll]);

  return {
    values,
    errors,
    fieldDirty,
    isDirty,
    isValid,
    isSaving,
    submitError,
    submitAttempted,
    set,
    setValues,
    blur,
    submit,
    reset,
    validateField,
    validateAll,
  };
}
