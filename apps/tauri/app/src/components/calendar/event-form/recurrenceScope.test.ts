import { describe, expect, it, vi } from 'vitest';
import {
  pickRecurrenceScope,
  recurrenceScopeAbortAll,
  recurrenceScopeReject,
  recurrenceScopeResolve,
  RecurrenceScopeCancelled,
} from './recurrenceScope';
import {
  handleRecurrenceScopeKeyboardNavigation,
  moveRecurrenceScopeSelection,
} from './recurrenceScopeKeyboard';

// Sanity tests for the imperative queue surface. The visual picker is
// covered by integration; here we just pin the contract that
// pickRecurrenceScope() resolves with whatever scope `resolve()`
// dispatches, returns null on reject(), and serializes overlapping
// calls FIFO.
describe('pickRecurrenceScope queue', () => {
  it('resolves with the scope passed to recurrenceScopeResolve', async () => {
    const promise = pickRecurrenceScope({ mode: 'edit' });
    // Dispatched in a microtask so the host (had it been mounted)
    // would have rendered. Resolve immediately.
    queueMicrotask(() => recurrenceScopeResolve('thisAndFollowing'));
    await expect(promise).resolves.toBe('thisAndFollowing');
  });

  it('resolves with null on reject', async () => {
    const promise = pickRecurrenceScope({ mode: 'delete' });
    queueMicrotask(() => recurrenceScopeReject());
    await expect(promise).resolves.toBeNull();
  });

  it('queues overlapping requests FIFO', async () => {
    const first = pickRecurrenceScope({ mode: 'edit' });
    const second = pickRecurrenceScope({ mode: 'delete' });
    recurrenceScopeResolve('thisOnly');
    recurrenceScopeResolve('allInSeries');
    await expect(first).resolves.toBe('thisOnly');
    await expect(second).resolves.toBe('allInSeries');
  });

  it('rejects in-flight + queued prompts with RecurrenceScopeCancelled on host unmount', async () => {
    const first = pickRecurrenceScope({ mode: 'edit' });
    const second = pickRecurrenceScope({ mode: 'delete' });
    recurrenceScopeAbortAll();
    await expect(first).rejects.toBeInstanceOf(RecurrenceScopeCancelled);
    await expect(second).rejects.toBeInstanceOf(RecurrenceScopeCancelled);
  });
});

describe('recurrence scope keyboard navigation', () => {
  it('moves through scopes with arrow keys', () => {
    expect(moveRecurrenceScopeSelection('thisOnly', 'ArrowDown')).toBe('thisAndFollowing');
    expect(moveRecurrenceScopeSelection('thisAndFollowing', 'ArrowRight')).toBe('allInSeries');
    expect(moveRecurrenceScopeSelection('allInSeries', 'ArrowDown')).toBe('thisOnly');
    expect(moveRecurrenceScopeSelection('thisOnly', 'ArrowUp')).toBe('allInSeries');
  });

  it('jumps to the first and last scope with Home and End', () => {
    expect(moveRecurrenceScopeSelection('allInSeries', 'Home')).toBe('thisOnly');
    expect(moveRecurrenceScopeSelection('thisOnly', 'End')).toBe('allInSeries');
  });

  it('leaves unsupported keys unchanged', () => {
    expect(moveRecurrenceScopeSelection('thisAndFollowing', 'Tab')).toBe('thisAndFollowing');
    expect(moveRecurrenceScopeSelection('allInSeries', ' ')).toBe('allInSeries');
  });

  it('prevents default and selects the next scope for navigation keys', () => {
    const preventDefault = vi.fn();
    const selectScope = vi.fn();

    const handled = handleRecurrenceScopeKeyboardNavigation({
      current: 'thisOnly',
      key: 'ArrowDown',
      preventDefault,
      selectScope,
    });

    expect(handled).toBe(true);
    expect(preventDefault).toHaveBeenCalledTimes(1);
    expect(selectScope).toHaveBeenCalledWith('thisAndFollowing');
  });

  it('prevents default even when Home or End stays on the boundary option', () => {
    const preventDefault = vi.fn();
    const selectScope = vi.fn();

    const handled = handleRecurrenceScopeKeyboardNavigation({
      current: 'thisOnly',
      key: 'Home',
      preventDefault,
      selectScope,
    });

    expect(handled).toBe(true);
    expect(preventDefault).toHaveBeenCalledTimes(1);
    expect(selectScope).not.toHaveBeenCalled();
  });

  it('does not handle non-navigation keys', () => {
    const preventDefault = vi.fn();
    const selectScope = vi.fn();

    const handled = handleRecurrenceScopeKeyboardNavigation({
      current: 'thisAndFollowing',
      key: 'Tab',
      preventDefault,
      selectScope,
    });

    expect(handled).toBe(false);
    expect(preventDefault).not.toHaveBeenCalled();
    expect(selectScope).not.toHaveBeenCalled();
  });
});
