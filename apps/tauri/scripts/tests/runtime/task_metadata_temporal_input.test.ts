import assert from 'node:assert/strict';
import test from 'node:test';

import {
  getOptionalTimeInputValue,
  resolveOptionalTimeInputBlurValue,
} from '../../../app/src/components/task-detail/taskMetadataTemporalInput';

test('temporal task metadata inputs clear invalid stored values on blur', () => {
  assert.equal(getOptionalTimeInputValue(' 09:30 '), '');

  assert.equal(resolveOptionalTimeInputBlurValue(' 09:30 ', ''), null);
});

test('temporal task metadata inputs preserve canonical stored values and intentional clears', () => {
  assert.equal(getOptionalTimeInputValue('09:30'), '09:30');

  assert.equal(resolveOptionalTimeInputBlurValue('09:30', ''), null);
  assert.equal(resolveOptionalTimeInputBlurValue('09:30', '09:30'), undefined);
});

test('temporal task metadata inputs allow replacing invalid stored values with canonical new values', () => {
  assert.equal(resolveOptionalTimeInputBlurValue(' 09:30 ', '10:15'), '10:15');
});
