import { describe, expect, it } from 'vitest';

import {
  computeFieldDirty,
  computeIsDirty,
  emptyErrors,
  isErrorsClean,
  runFieldValidator,
  runValidators,
  type Validators,
} from './useFormController.logic';

interface ExampleValues {
  title: string;
  count: number;
  flag: boolean;
}

const initial: ExampleValues = { title: '', count: 1, flag: false };

describe('computeFieldDirty', () => {
  it('returns false for every field when values match initial', () => {
    expect(computeFieldDirty(initial, { ...initial })).toEqual({
      title: false,
      count: false,
      flag: false,
    });
  });

  it('flags only mutated fields', () => {
    const dirty = computeFieldDirty(initial, { ...initial, title: 'hi' });
    expect(dirty.title).toBe(true);
    expect(dirty.count).toBe(false);
    expect(dirty.flag).toBe(false);
  });

  it('uses Object.is, so NaN equals NaN and -0 differs from +0', () => {
    const seed = { value: Number.NaN } as Record<string, unknown>;
    expect(computeFieldDirty(seed, { value: Number.NaN })).toEqual({ value: false });
    expect(computeFieldDirty({ value: 0 }, { value: -0 })).toEqual({ value: true });
  });
});

describe('computeIsDirty', () => {
  it('is false when nothing changed', () => {
    expect(computeIsDirty(initial, { ...initial })).toBe(false);
  });

  it('is true when any single field is mutated', () => {
    expect(computeIsDirty(initial, { ...initial, count: 2 })).toBe(true);
  });
});

describe('runValidators', () => {
  const validators: Validators<ExampleValues> = {
    title: (v) => (v.trim().length === 0 ? 'required' : null),
    count: (v) => (v < 1 ? 'too low' : null),
  };

  it('runs every registered validator and yields null for fields without one', () => {
    const errors = runValidators({ title: '', count: 0, flag: false }, validators);
    expect(errors).toEqual({ title: 'required', count: 'too low', flag: null });
  });

  it('produces a clean errors map on valid input', () => {
    const errors = runValidators({ title: 'ok', count: 5, flag: true }, validators);
    expect(isErrorsClean(errors)).toBe(true);
  });

  it('passes the full values map for cross-field rules', () => {
    const xValidators: Validators<ExampleValues> = {
      count: (v, values) => (values.flag && v < 10 ? 'flag-needs-10' : null),
    };
    const errors = runValidators({ title: '', count: 5, flag: true }, xValidators);
    expect(errors.count).toBe('flag-needs-10');
  });
});

describe('runFieldValidator', () => {
  it('returns null when no validator is registered for the key', () => {
    expect(runFieldValidator('flag', initial, {})).toBeNull();
  });
});

describe('emptyErrors', () => {
  it('produces null for every field key', () => {
    expect(emptyErrors(initial)).toEqual({ title: null, count: null, flag: null });
  });
});

describe('isErrorsClean', () => {
  it('is true for a fully-null errors map', () => {
    expect(isErrorsClean({ a: null, b: null })).toBe(true);
  });
  it('is false when any field has a non-null error', () => {
    expect(isErrorsClean({ a: null, b: 'oops' })).toBe(false);
  });
});
