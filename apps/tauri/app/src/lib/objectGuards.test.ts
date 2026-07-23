import { describe, expect, it } from 'vitest';

import {
  hasOnlyKeys,
  isObjectRecord,
  isPlainRecord,
  parseJsonRecord,
} from '@/lib/objectGuards';

describe('objectGuards', () => {
  it('accepts object literals and prototype-less records', () => {
    expect(isPlainRecord({ key: 'value' })).toBe(true);
    expect(isPlainRecord(Object.create(null))).toBe(true);
  });

  it('rejects null, arrays, and class/object instances', () => {
    expect(isPlainRecord(null)).toBe(false);
    expect(isPlainRecord(['value'])).toBe(false);
    expect(isPlainRecord(new Date())).toBe(false);
    expect(isPlainRecord(new (class CustomRecord {})())).toBe(false);
  });

  it('keeps a broad non-array object guard for legacy error envelopes', () => {
    expect(isObjectRecord({ key: 'value' })).toBe(true);
    expect(isObjectRecord(new Date())).toBe(true);
    expect(isObjectRecord(['value'])).toBe(false);
    expect(isObjectRecord(null)).toBe(false);
  });

  it('checks unknown keys against an allowlist', () => {
    const allowed = new Set(['kind', 'id']);

    expect(hasOnlyKeys({ kind: 'list', id: '123' }, allowed)).toBe(true);
    expect(hasOnlyKeys({ kind: 'list', id: '123', extra: true }, allowed)).toBe(false);
  });

  it('parses JSON records and rejects non-record JSON', () => {
    expect(parseJsonRecord('{"kind":"list"}')).toEqual({ kind: 'list' });
    expect(parseJsonRecord('null')).toBeNull();
    expect(parseJsonRecord('["kind"]')).toBeNull();
    expect(parseJsonRecord('{')).toBeNull();
  });
});
