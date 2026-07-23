import { describe, expect, it } from 'vitest';

import {
  isNumberOrNull,
  isOneOf,
  isString,
  isStringArray,
  isStringOrNull,
  readPersistedState,
} from './useLocalStorageBackedState';

describe('validators', () => {
  it('isString accepts strings only', () => {
    expect(isString('hi')).toBe(true);
    expect(isString('')).toBe(true);
    expect(isString(0)).toBe(false);
    expect(isString(null)).toBe(false);
    expect(isString(undefined)).toBe(false);
    expect(isString({})).toBe(false);
  });

  it('isStringOrNull accepts string or null only', () => {
    expect(isStringOrNull('hi')).toBe(true);
    expect(isStringOrNull(null)).toBe(true);
    expect(isStringOrNull(undefined)).toBe(false);
    expect(isStringOrNull(0)).toBe(false);
  });

  it('isNumberOrNull accepts number or null only', () => {
    expect(isNumberOrNull(1)).toBe(true);
    expect(isNumberOrNull(0)).toBe(true);
    expect(isNumberOrNull(null)).toBe(true);
    expect(isNumberOrNull(undefined)).toBe(false);
    expect(isNumberOrNull('1')).toBe(false);
  });

  it('isStringArray rejects mixed-type arrays', () => {
    expect(isStringArray([])).toBe(true);
    expect(isStringArray(['a', 'b'])).toBe(true);
    expect(isStringArray(['a', 1])).toBe(false);
    expect(isStringArray(null)).toBe(false);
    expect(isStringArray('a,b')).toBe(false);
  });

  it('isOneOf narrows to the literal union', () => {
    const isViewMode = isOneOf(['list', 'timeline'] as const);
    expect(isViewMode('list')).toBe(true);
    expect(isViewMode('timeline')).toBe(true);
    expect(isViewMode('cards')).toBe(false);
    expect(isViewMode(null)).toBe(false);
  });
});

describe('readPersistedState', () => {
  it('returns null for missing or empty input', () => {
    expect(readPersistedState(null, isString)).toBeNull();
  });

  it('returns null for malformed JSON', () => {
    expect(readPersistedState('{not-json', isString)).toBeNull();
  });

  it('returns null when the parsed shape fails the validator', () => {
    expect(readPersistedState('123', isString)).toBeNull();
    expect(readPersistedState('true', isString)).toBeNull();
    expect(readPersistedState('[1, 2]', isStringArray)).toBeNull();
  });

  it('returns the typed value when validation succeeds', () => {
    expect(readPersistedState('"hello"', isString)).toBe('hello');
    expect(readPersistedState('null', isStringOrNull)).toBeNull();
    expect(readPersistedState('"world"', isStringOrNull)).toBe('world');
    expect(readPersistedState('[]', isStringArray)).toEqual([]);
    expect(readPersistedState('["a","b"]', isStringArray)).toEqual(['a', 'b']);
  });
});
