// Pure helpers for `useFormController`.
//
// Kept separate from the React-glue file so the .logic tier can be
// exercised in the existing Node-environment vitest harness without
// jsdom. The hook itself is a thin shell around these functions.

type FieldValidator<T, TValues> = (
  value: T,
  // The full values map is passed so cross-field validators (e.g. "end
  // must be after start") can reach sibling values without resorting
  // to closure capture.
  values: Readonly<TValues>,
) => string | null;

export type Validators<TValues> = {
  [K in keyof TValues]?: FieldValidator<TValues[K], TValues>;
};

export type ErrorsOf<TValues> = {
  [K in keyof TValues]: string | null;
};

export type DirtyOf<TValues> = {
  [K in keyof TValues]: boolean;
};

/**
 * Compute the per-field dirty map by comparing each value to its
 * initial counterpart with `Object.is`. Object/array fields are
 * compared by reference — callers that put structured values in the
 * form should treat each replacement as a fresh reference (the same
 * discipline the rest of the codebase uses for React state).
 */
export function computeFieldDirty<TValues extends object>(
  initial: TValues,
  values: TValues,
): DirtyOf<TValues> {
  const result = {} as DirtyOf<TValues>;
  for (const key of Object.keys(initial) as Array<keyof TValues>) {
    result[key] = !Object.is(initial[key], values[key]);
  }
  return result;
}

/** Whole-form `isDirty` — true if ANY field differs from its initial value. */
export function computeIsDirty<TValues extends object>(
  initial: TValues,
  values: TValues,
): boolean {
  for (const key of Object.keys(initial) as Array<keyof TValues>) {
    if (!Object.is(initial[key], values[key])) return true;
  }
  return false;
}

/**
 * Run every registered validator and return the resulting errors map.
 * Fields without a validator default to `null`. The result is always
 * a fresh object — callers can reference-compare to detect change.
 */
export function runValidators<TValues extends object>(
  values: TValues,
  validators: Validators<TValues>,
): ErrorsOf<TValues> {
  const errors = {} as ErrorsOf<TValues>;
  for (const key of Object.keys(values) as Array<keyof TValues>) {
    const validator = validators[key];
    errors[key] = validator ? validator(values[key], values) : null;
  }
  return errors;
}

/**
 * Run a single field's validator. Returns `null` if no validator is
 * registered, mirroring the "no validator => no error" rule.
 */
export function runFieldValidator<TValues extends object>(
  key: keyof TValues,
  values: TValues,
  validators: Validators<TValues>,
): string | null {
  const validator = validators[key];
  return validator ? validator(values[key], values) : null;
}

/** True when no field has a non-null error. */
export function isErrorsClean<TValues extends object>(
  errors: ErrorsOf<TValues>,
): boolean {
  for (const key of Object.keys(errors) as Array<keyof TValues>) {
    if (errors[key] !== null) return false;
  }
  return true;
}

/** Build a fresh errors map with every field cleared to `null`. */
export function emptyErrors<TValues extends object>(
  initial: TValues,
): ErrorsOf<TValues> {
  const errors = {} as ErrorsOf<TValues>;
  for (const key of Object.keys(initial) as Array<keyof TValues>) {
    errors[key] = null;
  }
  return errors;
}
