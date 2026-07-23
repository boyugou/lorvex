import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { confirm, confirmReject } from '../../../app/src/lib/dialogs/confirm';
import { readActiveConfirmTriggerElement } from '../../../app/src/lib/dialogs/confirm.runtime';

test('confirm runtime reads the active HTMLElement trigger through a guarded host seam', () => {
  class FakeHTMLElement {}
  const activeElement = new FakeHTMLElement();
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: { activeElement },
  });
  Object.defineProperty(globalThis, 'HTMLElement', {
    configurable: true,
    value: FakeHTMLElement,
  });

  try {
    assert.equal(readActiveConfirmTriggerElement(), activeElement);
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    if (originalHTMLElement === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      globalThis.HTMLElement = originalHTMLElement;
    }
  }
});

test('confirm runtime returns null without DOM element hosts', () => {
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;

  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: { activeElement: {} },
  });
  Reflect.deleteProperty(globalThis, 'HTMLElement');

  try {
    assert.equal(readActiveConfirmTriggerElement(), null);
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    if (originalHTMLElement === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      globalThis.HTMLElement = originalHTMLElement;
    }
  }
});

test('confirm delegates trigger capture to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/dialogs/confirm.ts'),
    'utf8',
  );
  const implementation = source.replace(/\/\*[\s\S]*?\*\/|\/\/.*$/gm, '');

  assert.match(source, /import \{ readActiveConfirmTriggerElement \} from '\.\/confirm\.runtime';/);
  assert.match(source, /const explicitTrigger = options\.triggerElement \?\? null;/);
  assert.match(source, /triggerElement: explicitTrigger \?\? readActiveConfirmTriggerElement\(\)/);
  assert.doesNotMatch(implementation, /\bdocument\b/);
  assert.doesNotMatch(implementation, /typeof HTMLElement/);
  assert.doesNotMatch(implementation, /instanceof HTMLElement/);
});

test('confirm falls back to a null trigger when HTMLElement is unavailable', async () => {
  const originalDocument = globalThis.document;
  const originalHTMLElement = globalThis.HTMLElement;
  Object.defineProperty(globalThis, 'document', {
    configurable: true,
    value: { activeElement: {} },
  });
  Reflect.deleteProperty(globalThis, 'HTMLElement');

  try {
    const confirmation = confirm({
      title: 'Discard changes?',
      message: 'This action cannot be undone.',
    });

    confirmReject();

    assert.equal(await confirmation, false);
  } finally {
    Object.defineProperty(globalThis, 'document', { configurable: true, value: originalDocument });
    if (originalHTMLElement === undefined) {
      Reflect.deleteProperty(globalThis, 'HTMLElement');
    } else {
      globalThis.HTMLElement = originalHTMLElement;
    }
  }
});
