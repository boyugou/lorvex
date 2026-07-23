import { describe, expect, it } from 'vitest';

import {
  encodePreferenceCacheValue,
  parseBool,
  parseJsonValidated,
  parseString,
} from './usePreference.logic';

describe('usePreference parsers', () => {
  it('encodes optimistic cache values in the same JSON wire format as setPreference', () => {
    expect(encodePreferenceCacheValue('custom-value')).toBe('"custom-value"');
    expect(encodePreferenceCacheValue(null)).toBeNull();
    expect(encodePreferenceCacheValue(true)).toBe('true');
    expect(encodePreferenceCacheValue(3)).toBe('3');
    expect(encodePreferenceCacheValue(['today'])).toBe('["today"]');
  });

  it('parses boolean preferences with invalid-value fallback', () => {
    const parse = parseBool(false);
    expect(parse(null)).toBe(false);
    expect(parse('not-json')).toBe(false);
    expect(parse('"true"')).toBe(false);
    expect(parse('true')).toBe(true);
  });

  it('parses string preferences with invalid-value fallback', () => {
    const parse = parseString('');
    expect(parse(null)).toBe('');
    expect(parse('not-json')).toBe('');
    expect(parse('false')).toBe('');
    expect(parse('"custom-value"')).toBe('custom-value');
  });

  it('requires an explicit guard for structural JSON preferences', () => {
    const parse = parseJsonValidated(
      ['today'],
      (value): value is string[] => Array.isArray(value) && value.every((item) => typeof item === 'string'),
    );
    expect(parse(null)).toEqual(['today']);
    expect(parse('{"show":["today"]}')).toEqual(['today']);
    expect(parse('["today","memory"]')).toEqual(['today', 'memory']);
  });
});
