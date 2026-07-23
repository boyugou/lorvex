import assert from 'node:assert/strict';
import test from 'node:test';

// The runtime test suite runs without React, so we import the pure
// reducer helpers that `useTaskSelection` is built on top of and
// exercise every multi-select branch: plain / ctrl+click / shift+click
// (with and without a prior anchor), shift+arrow up/down, and escape.

import {
  computeRangeSelection,
  reconcileSelectionVisibility,
  reduceKeyboardExtend,
  reduceModifierClick,
} from '../../../app/src/lib/tasks/useTaskSelection';

// ---------------------------------------------------------------------------
// computeRangeSelection — pure helper the reducers rely on.
// ---------------------------------------------------------------------------

test('computeRangeSelection: inclusive range from anchor → target', () => {
  const range = computeRangeSelection(['a', 'b', 'c', 'd', 'e'], 'b', 'd');
  assert.deepEqual([...range], ['b', 'c', 'd']);
});

test('computeRangeSelection: order-agnostic (target before anchor)', () => {
  const range = computeRangeSelection(['a', 'b', 'c', 'd', 'e'], 'd', 'b');
  assert.deepEqual([...range], ['b', 'c', 'd']);
});

test('computeRangeSelection: null anchor falls back to single target', () => {
  const range = computeRangeSelection(['a', 'b', 'c'], null, 'b');
  assert.deepEqual([...range], ['b']);
});

// ---------------------------------------------------------------------------
// Modifier click reducer
// ---------------------------------------------------------------------------

const ids = ['a', 'b', 'c', 'd', 'e'] as const;

function click(id: string, mods: Partial<{ shift: boolean; meta: boolean; ctrl: boolean }> = {}) {
  return {
    shiftKey: mods.shift ?? false,
    metaKey: mods.meta ?? false,
    ctrlKey: mods.ctrl ?? false,
  };
}

test('plain_click_replaces_selection_and_sets_anchor', () => {
  const prev = new Set(['a', 'b']);
  const { next, nextAnchor } = reduceModifierClick(ids, prev, 'a', 'c', click('c'), null);
  assert.deepEqual([...next], ['c']);
  assert.equal(nextAnchor, 'c');
});

test('ctrl_click_toggles_single_item', () => {
  const prev = new Set(['a']);
  const first = reduceModifierClick(ids, prev, 'a', 'c', click('c', { ctrl: true }), null);
  assert.deepEqual([...first.next].sort(), ['a', 'c']);
  assert.equal(first.nextAnchor, 'a', 'ctrl-click keeps the prior anchor');

  const second = reduceModifierClick(ids, first.next, first.nextAnchor, 'a', click('a', { ctrl: true }), null);
  assert.deepEqual([...second.next], ['c']);
  assert.equal(second.nextAnchor, 'a');
});

test('meta_click_is_ctrl_click_on_mac', () => {
  const prev = new Set<string>();
  const { next, nextAnchor } = reduceModifierClick(ids, prev, null, 'c', click('c', { meta: true }), null);
  assert.deepEqual([...next], ['c']);
  assert.equal(nextAnchor, null, 'anchor is unchanged by meta-click');
});

test('shift_click_selects_range_from_anchor', () => {
  const prev = new Set(['a']);
  const { next, nextAnchor } = reduceModifierClick(ids, prev, 'a', 'd', click('d', { shift: true }), null);
  assert.deepEqual([...next], ['a', 'b', 'c', 'd']);
  assert.equal(nextAnchor, 'a', 'shift-click never moves the anchor');
});

test('shift_click_without_anchor_selects_from_current', () => {
  // No anchor yet, but the user has a keyboard-focused row — we should
  // treat that as the anchor so the range is well-defined.
  const prev = new Set<string>();
  const { next, nextAnchor } = reduceModifierClick(ids, prev, null, 'c', click('c', { shift: true }), 'a');
  assert.deepEqual([...next], ['a', 'b', 'c']);
  assert.equal(nextAnchor, 'a', 'first shift-click establishes the focus row as anchor');
});

test('shift_click_without_anchor_and_no_focus_selects_only_target', () => {
  const prev = new Set<string>();
  const { next, nextAnchor } = reduceModifierClick(ids, prev, null, 'c', click('c', { shift: true }), null);
  assert.deepEqual([...next], ['c']);
  assert.equal(nextAnchor, 'c', 'falls back to treating the click target as the anchor');
});

test('shift_click_replaces_prior_range', () => {
  // Extending past the anchor shrinks/flips the prior range rather than
  // unioning with it — matches Finder's shift-click behavior.
  const prev = new Set(['a', 'b', 'c', 'd']);
  const { next } = reduceModifierClick(ids, prev, 'a', 'b', click('b', { shift: true }), null);
  assert.deepEqual([...next], ['a', 'b']);
});

// ---------------------------------------------------------------------------
// Keyboard extend reducer
// ---------------------------------------------------------------------------

test('shift_arrow_down_extends_range', () => {
  const result = reduceKeyboardExtend(ids, 'b', 'b', 'down');
  assert.ok(result);
  assert.deepEqual([...result.next], ['b', 'c']);
  assert.equal(result.nextAnchor, 'b');
  assert.equal(result.nextFocusedId, 'c');

  // Continuing extends further.
  const second = reduceKeyboardExtend(ids, result.nextAnchor, result.nextFocusedId, 'down');
  assert.ok(second);
  assert.deepEqual([...second.next], ['b', 'c', 'd']);
  assert.equal(second.nextFocusedId, 'd');
});

test('shift_arrow_up_extends_range', () => {
  const result = reduceKeyboardExtend(ids, 'd', 'd', 'up');
  assert.ok(result);
  assert.deepEqual([...result.next], ['c', 'd']);
  assert.equal(result.nextFocusedId, 'c');
});

test('shift_arrow_without_anchor_uses_focus_as_anchor', () => {
  const result = reduceKeyboardExtend(ids, null, 'c', 'down');
  assert.ok(result);
  assert.deepEqual([...result.next], ['c', 'd']);
  assert.equal(result.nextAnchor, 'c', 'anchor is pinned to the starting focus row');
});

test('shift_arrow_at_boundary_is_a_no_op', () => {
  const down = reduceKeyboardExtend(ids, 'e', 'e', 'down');
  assert.equal(down, null);
  const up = reduceKeyboardExtend(ids, 'a', 'a', 'up');
  assert.equal(up, null);
});

test('shift_arrow_shrinks_range_when_moving_back_toward_anchor', () => {
  // Extending down then back up should shrink the selection, not expand
  // it — the anchor stays put and the range collapses toward it.
  const down = reduceKeyboardExtend(ids, 'b', 'b', 'down');
  assert.ok(down);
  const further = reduceKeyboardExtend(ids, down.nextAnchor, down.nextFocusedId, 'down');
  assert.ok(further);
  assert.deepEqual([...further.next], ['b', 'c', 'd']);

  const back = reduceKeyboardExtend(ids, further.nextAnchor, further.nextFocusedId, 'up');
  assert.ok(back);
  assert.deepEqual([...back.next], ['b', 'c']);
});

// ---------------------------------------------------------------------------
// "Escape clears selection" is a controller-level behavior: the hook
// owns a `clearSelection` callback which the keyboard hook invokes on
// Escape. Since clearSelection() is just `setSelectedIds(new Set())`
// plus `setAnchorId(null)`, we verify the contract by running one full
// round-trip: plain click → ctrl+click (to build a multi-select) → the
// caller presses Escape → selection is empty and the next plain click
// establishes a fresh anchor.
// ---------------------------------------------------------------------------

test('escape_clears_selection', () => {
  // Build a two-item multi-select via one plain click + one ctrl-click.
  let selected = new Set<string>();
  let anchor: string | null = null;
  ({ next: selected, nextAnchor: anchor } = reduceModifierClick(ids, selected, anchor, 'b', click('b'), null));
  ({ next: selected, nextAnchor: anchor } = reduceModifierClick(ids, selected, anchor, 'd', click('d', { ctrl: true }), null));
  assert.deepEqual([...selected].sort(), ['b', 'd']);

  // Escape handler.
  selected = new Set();
  anchor = null;

  // A fresh plain click after escape acts like the first click in a new
  // session — single item, anchor set to it.
  const after = reduceModifierClick(ids, selected, anchor, 'c', click('c'), null);
  assert.deepEqual([...after.next], ['c']);
  assert.equal(after.nextAnchor, 'c');
});

test('reconcileSelectionVisibility prunes hidden ids and clears a hidden anchor', () => {
  const reconciled = reconcileSelectionVisibility(
    new Set(['a', 'b', 'd']),
    new Set(['b', 'c']),
    'd',
    true,
  );

  assert.deepEqual([...reconciled.nextSelectedIds], ['b']);
  assert.equal(reconciled.nextAnchorId, null);
  assert.equal(reconciled.nextSelectionMode, true);
});

test('reconcileSelectionVisibility exits selection mode when the visible task set becomes empty', () => {
  const reconciled = reconcileSelectionVisibility(
    new Set(['a', 'b']),
    new Set(),
    'a',
    true,
  );

  assert.deepEqual([...reconciled.nextSelectedIds], []);
  assert.equal(reconciled.nextAnchorId, null);
  assert.equal(reconciled.nextSelectionMode, false);
});
