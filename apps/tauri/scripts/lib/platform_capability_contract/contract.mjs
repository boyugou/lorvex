export const SCRIPT_TAG = '[verify:platform-capability-contract]';

function fail(message) {
  throw new Error(`${SCRIPT_TAG} ${message}`);
}

export function assert(condition, message) {
  if (!condition) {
    fail(message);
  }
}
