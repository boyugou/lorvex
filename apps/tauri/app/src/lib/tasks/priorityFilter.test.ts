import { describe, expect, it } from 'vitest';

import { readPersistedState } from '../storage/useLocalStorageBackedState';
import {
  isPriorityOrNull,
  parsePriorityFilterValue,
} from './priorityFilter';

describe('priority filter values', () => {
  it('accepts only canonical Priority values or null from persisted state', () => {
    expect(readPersistedState('1', isPriorityOrNull)).toBe(1);
    expect(readPersistedState('2', isPriorityOrNull)).toBe(2);
    expect(readPersistedState('3', isPriorityOrNull)).toBe(3);
    expect(readPersistedState('null', isPriorityOrNull)).toBeNull();

    expect(readPersistedState('0', isPriorityOrNull)).toBeNull();
    expect(readPersistedState('4', isPriorityOrNull)).toBeNull();
    expect(readPersistedState('99', isPriorityOrNull)).toBeNull();
    expect(readPersistedState('1.5', isPriorityOrNull)).toBeNull();
    expect(readPersistedState('"1"', isPriorityOrNull)).toBeNull();
  });

  it('parses dropdown values without widening to arbitrary numbers', () => {
    expect(parsePriorityFilterValue('')).toBeNull();
    expect(parsePriorityFilterValue('1')).toBe(1);
    expect(parsePriorityFilterValue('2')).toBe(2);
    expect(parsePriorityFilterValue('3')).toBe(3);

    expect(parsePriorityFilterValue('0')).toBeUndefined();
    expect(parsePriorityFilterValue('4')).toBeUndefined();
    expect(parsePriorityFilterValue('99')).toBeUndefined();
    expect(parsePriorityFilterValue('1.0')).toBeUndefined();
  });
});
