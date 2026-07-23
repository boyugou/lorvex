import { describe, expect, it } from 'vitest';

import { classifyCommandError, parseCommandError } from './commandError';

describe('parseCommandError', () => {
  it('parses a typed validation envelope', () => {
    const envelope = JSON.stringify({ kind: 'validation', message: 'title required' });
    expect(parseCommandError(envelope)).toEqual({
      kind: 'validation',
      message: 'title required',
    });
  });

  it('parses a typed not_found envelope', () => {
    const envelope = JSON.stringify({ kind: 'not_found', message: 'Task not found: xyz' });
    expect(parseCommandError(envelope)).toEqual({
      kind: 'not_found',
      message: 'Task not found: xyz',
    });
  });

  it('parses a typed disk_full envelope and round-trips the detail field', () => {
    const envelope = JSON.stringify({
      kind: 'disk_full',
      message: 'Local storage is full.',
      detail: 'SQLITE_FULL: out of space',
    });
    expect(parseCommandError(envelope)).toEqual({
      kind: 'disk_full',
      message: 'Local storage is full.',
      detail: 'SQLITE_FULL: out of space',
    });
  });

  it('reads typed envelope from {message} object errors', () => {
    const envelope = JSON.stringify({ kind: 'internal', message: 'something failed' });
    expect(parseCommandError({ message: envelope })).toEqual({
      kind: 'internal',
      message: 'something failed',
    });
  });

  it('returns null for non-JSON strings', () => {
    expect(parseCommandError('plain error message')).toBeNull();
  });

  it('returns null for valid JSON that is not an envelope', () => {
    expect(parseCommandError(JSON.stringify({ foo: 'bar' }))).toBeNull();
    expect(parseCommandError(JSON.stringify([1, 2, 3]))).toBeNull();
  });

  it('returns null for envelopes with unknown kind', () => {
    expect(
      parseCommandError(JSON.stringify({ kind: 'novel_failure_class', message: 'unknown' })),
    ).toBeNull();
  });

  it('returns null for null/undefined/non-string inputs', () => {
    expect(parseCommandError(null)).toBeNull();
    expect(parseCommandError(undefined)).toBeNull();
    expect(parseCommandError(42)).toBeNull();
  });
});

describe('classifyCommandError', () => {
  it('returns the typed envelope when one parses', () => {
    const envelope = JSON.stringify({ kind: 'validation', message: 'bad' });
    expect(classifyCommandError(envelope)).toEqual({ kind: 'validation', message: 'bad' });
  });

  it('synthesizes an internal envelope from a free-text string', () => {
    expect(classifyCommandError('plain error')).toEqual({
      kind: 'internal',
      message: 'plain error',
    });
  });

  it('synthesizes an internal envelope from {message}-shaped errors', () => {
    expect(classifyCommandError({ message: 'oops' })).toEqual({
      kind: 'internal',
      message: 'oops',
    });
  });

  it('synthesizes an empty internal envelope from null', () => {
    expect(classifyCommandError(null)).toEqual({ kind: 'internal', message: '' });
  });
});
