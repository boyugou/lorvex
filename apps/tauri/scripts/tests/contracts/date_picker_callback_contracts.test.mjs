import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function source(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), 'utf8');
}

test('DatePicker keyboard selection depends on the current selection callback', () => {
  const datePicker = source('app/src/components/ui/DatePicker.controller.ts');

  assert.doesNotMatch(
    datePicker,
    /react-hooks\/exhaustive-deps/,
    'DatePicker must not suppress hook dependency checks around keyboard selection',
  );
  assert.match(
    datePicker,
    /const isDisabled = useCallback\(\(ymd: string\) => minDate \? ymd < minDate : false, \[minDate\]\);/,
    'DatePicker should memoize isDisabled with minDate as its only dependency',
  );
  assert.match(
    datePicker,
    /const handleSelectDate = useCallback\(\(ymd: string\) => \{[\s\S]*?onChange\(ymd\);[\s\S]*?onClose\(\);[\s\S]*?\}, \[isDisabled, onChange, onClose\]\);/,
    'DatePicker should memoize handleSelectDate with the current onChange callback',
  );
  assert.match(
    datePicker,
    /const handleKeyDown = useCallback\(\(e: React\.KeyboardEvent\) => \{[\s\S]*?handleSelectDate\(focusedDay\);[\s\S]*?\}, \[onClose, focusedDay, viewMonth, viewYear, isDisabled, handleSelectDate, weekStartDay\]\);/,
    'DatePicker keyboard handler should depend on handleSelectDate so Enter/Space use the latest onChange',
  );
});
