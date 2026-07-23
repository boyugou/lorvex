import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { createElement } from 'react';

import { createBrowserAppSelectRuntimeDeps } from '../../../app/src/components/ui/app-select/AppSelect.runtime';
import { parseOptions } from '../../../app/src/components/ui/app-select/model';

const contentSource = readFileSync(
  new URL('../../../app/src/components/ui/app-select/AppSelectContent.tsx', import.meta.url),
  'utf8',
);
const controllerSource = readFileSync(
  new URL('../../../app/src/components/ui/app-select/useAppSelectController.ts', import.meta.url),
  'utf8',
);
const modelSource = readFileSync(
  new URL('../../../app/src/components/ui/app-select/model.ts', import.meta.url),
  'utf8',
);

test('AppSelect content delegates portal host and viewport reads to its controller', () => {
  assert.doesNotMatch(contentSource, /\bdocument\.body\b/);
  assert.doesNotMatch(contentSource, /\bwindow\.innerHeight\b/);
});

test('AppSelect controller delegates browser document/window/Node wiring to runtime seams', () => {
  assert.doesNotMatch(controllerSource, /\bdocument\b/);
  assert.doesNotMatch(controllerSource, /\bwindow\b/);
  assert.doesNotMatch(controllerSource, /\bNode\b/);
});

test('AppSelect option model reads typed option props without record casts', () => {
  assert.doesNotMatch(modelSource, /child\.props as Record<string, unknown>/);
});

test('AppSelect option model parses option children while ignoring non-option nodes', () => {
  const options = parseOptions([
    createElement('option', { key: 'explicit', value: 'alpha' }, 'Alpha'),
    createElement('span', { key: 'ignored' }, 'Ignored'),
    createElement('option', { key: 'fallback', disabled: true }, 'Fallback'),
  ]);

  assert.deepEqual(options, [
    {
      key: 'explicit',
      value: 'alpha',
      label: 'Alpha',
      disabled: false,
    },
    {
      key: 'fallback',
      value: 'Fallback',
      label: 'Fallback',
      disabled: true,
    },
  ]);
});

test('AppSelect browser runtime reads viewport, portal target, and guarded containment', () => {
  class FakeNode {}

  const body = {} as HTMLElement;
  const insideNode = new FakeNode() as unknown as Node;
  const outsideNode = new FakeNode() as unknown as Node;
  const container = { contains: (node: Node) => node === insideNode } as HTMLElement;

  const runtime = createBrowserAppSelectRuntimeDeps({
    documentTarget: {
      body,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    windowTarget: {
      innerWidth: 640,
      innerHeight: 480,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    nodeConstructor: FakeNode as unknown as typeof Node,
  });

  assert.deepEqual(runtime.readViewport(), { width: 640, height: 480 });
  assert.equal(runtime.readPortalTarget(), body);
  assert.equal(runtime.containsTarget(container, insideNode), true);
  assert.equal(runtime.containsTarget(container, outsideNode), false);
  assert.equal(runtime.containsTarget(container, {} as EventTarget), false);
});

test('AppSelect browser runtime is inert without DOM hosts and delegates dismissal cleanup', () => {
  const noHosts = createBrowserAppSelectRuntimeDeps({
    documentTarget: undefined,
    windowTarget: undefined,
    nodeConstructor: undefined,
  });

  assert.equal(noHosts.readViewport(), null);
  assert.equal(noHosts.readPortalTarget(), null);
  assert.equal(noHosts.containsTarget({ contains: () => true } as HTMLElement, {} as EventTarget), false);
  assert.doesNotThrow(() => {
    const cleanup = noHosts.startDismissRuntime({
      getTrigger: () => null,
      getPanel: () => null,
      onDismiss: () => assert.fail('dismiss should not run without document'),
    });
    cleanup();
  });

  class FakeNode {}

  const listeners = new Map<string, EventListener>();
  const dismissed: string[] = [];
  const triggerNode = new FakeNode() as unknown as Node;
  const outsideNode = new FakeNode() as unknown as Node;
  const trigger = { contains: (node: Node) => node === triggerNode } as HTMLElement;

  const runtime = createBrowserAppSelectRuntimeDeps({
    documentTarget: {
      body: {} as HTMLElement,
      addEventListener: (type, listener) => {
        listeners.set(type, listener as EventListener);
      },
      removeEventListener: (type, listener) => {
        if (listeners.get(type) === listener) listeners.delete(type);
      },
    },
    windowTarget: {
      innerWidth: 320,
      innerHeight: 240,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    nodeConstructor: FakeNode as unknown as typeof Node,
  });

  const cleanup = runtime.startDismissRuntime({
    getTrigger: () => trigger,
    getPanel: () => null,
    onDismiss: () => dismissed.push('dismiss'),
  });

  listeners.get('pointerdown')?.({ target: triggerNode } as Event);
  listeners.get('pointerdown')?.({ target: outsideNode } as Event);
  cleanup();

  assert.deepEqual(dismissed, ['dismiss']);
  assert.equal(listeners.size, 0);
});
