import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

function source(relPath) {
  return fs.readFileSync(path.join(repoRoot, relPath), 'utf8');
}

test('DatePicker splits controller, grid, chips, and platform shells', () => {
  const datePicker = source('app/src/components/ui/DatePicker.tsx');
  const controller = source('app/src/components/ui/DatePicker.controller.ts');
  const content = source('app/src/components/ui/DatePickerContent.tsx');
  const grid = source('app/src/components/ui/DatePickerGrid.tsx');
  const chips = source('app/src/components/ui/DatePickerQuickChips.tsx');
  const desktop = source('app/src/components/ui/DatePickerDesktopPopover.tsx');
  const mobile = source('app/src/components/ui/DatePickerMobileSheet.tsx');

  assert.match(datePicker, /useDatePickerController\(/);
  assert.match(datePicker, /<DatePickerContent\b/);
  assert.match(datePicker, /<DatePickerMobileSheet\b/);
  assert.match(datePicker, /<DatePickerDesktopPopover\b/);
  assert.doesNotMatch(datePicker, /buildDatePickerGrid|weeks\.map|quickChips\.map|pushModalEscapeHandler|resolveDatePickerDesktopPosition/);

  assert.match(controller, /export function useDatePickerController\(/);
  assert.match(controller, /resolveDatePickerDesktopPosition\(/);
  assert.match(controller, /pushModalEscapeHandler\(onClose\)/);
  assert.match(controller, /const handleSelectDate = useCallback\(\(ymd: string\) => \{[\s\S]*?onChange\(ymd\);[\s\S]*?onClose\(\);[\s\S]*?\}, \[isDisabled, onChange, onClose\]\);/);
  assert.match(controller, /const handleKeyDown = useCallback\(\(e: React\.KeyboardEvent\) => \{[\s\S]*?handleSelectDate\(focusedDay\);[\s\S]*?\}, \[onClose, focusedDay, viewMonth, viewYear, isDisabled, handleSelectDate, weekStartDay\]\);/);

  assert.match(content, /<DatePickerQuickChips\b/);
  assert.match(content, /<DatePickerGrid\b/);
  assert.match(content, /goToPrevYear|goToPrevMonth|goToNextMonth|goToNextYear|goToToday/);

  assert.match(grid, /export function DatePickerGrid\(/);
  assert.match(grid, /role="grid"/);
  assert.match(grid, /formatDatePickerDayAriaLabel\(/);
  assert.match(grid, /dayButtonRefs\.current\.set/);

  assert.match(chips, /export function DatePickerQuickChips\(/);
  assert.match(chips, /<ToggleChip\b/);
  assert.doesNotMatch(chips, /buildDatePickerGrid|role="grid"/);

  assert.match(desktop, /export function DatePickerDesktopPopover\(/);
  assert.match(desktop, /createPortal\(panel, document\.body\)/);
  assert.match(desktop, /role="dialog"/);

  assert.match(mobile, /export function DatePickerMobileSheet\(/);
  assert.match(mobile, /<ModalShell\b/);
  assert.match(mobile, /onPanelKeyDown=\{handleKeyDown\}/);
});
