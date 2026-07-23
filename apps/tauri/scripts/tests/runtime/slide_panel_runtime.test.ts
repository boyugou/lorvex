import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserSlidePanelTabTrapRuntimeDeps,
  installSlidePanelTabTrapRuntime,
  shouldTrapSlidePanelTabKey,
} from '../../../app/src/components/ui/SlidePanel.runtime';

interface FakePanel {
  id: string;
}

interface FakeActiveElement {
  id: string;
}

const panel: FakePanel = { id: 'panel' };
const insideActive: FakeActiveElement = { id: 'inside' };
const outsideActive: FakeActiveElement = { id: 'outside' };

function isInside(targetPanel: FakePanel, activeElement: FakeActiveElement): boolean {
  return targetPanel === panel && activeElement === insideActive;
}

test('slide panel tab trap predicate only allows Tab when focus is inside the panel', () => {
  assert.equal(
    shouldTrapSlidePanelTabKey({
      key: 'Tab',
      panel,
      activeElement: insideActive,
      isActiveInsidePanel: isInside,
    }),
    true,
  );
  assert.equal(
    shouldTrapSlidePanelTabKey({
      key: 'Escape',
      panel,
      activeElement: insideActive,
      isActiveInsidePanel: isInside,
    }),
    false,
  );
  assert.equal(
    shouldTrapSlidePanelTabKey({
      key: 'Tab',
      panel,
      activeElement: outsideActive,
      isActiveInsidePanel: isInside,
    }),
    false,
  );
  assert.equal(
    shouldTrapSlidePanelTabKey({
      key: 'Tab',
      panel: null,
      activeElement: insideActive,
      isActiveInsidePanel: isInside,
    }),
    false,
  );
  assert.equal(
    shouldTrapSlidePanelTabKey({
      key: 'Tab',
      panel,
      activeElement: null,
      isActiveInsidePanel: isInside,
    }),
    false,
  );
});

test('slide panel tab trap runtime traps inside Tab and unregisters cleanup', () => {
  let listener: EventListener | undefined;
  let activeElement = insideActive;
  const calls: string[] = [];

  const cleanup = installSlidePanelTabTrapRuntime({
    documentTarget: {
      addEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        listener = nextListener as EventListener;
      },
      removeEventListener: (type, nextListener) => {
        assert.equal(type, 'keydown');
        if (listener === nextListener) {
          listener = undefined;
          calls.push('cleanup');
        }
      },
    },
    getPanel: () => panel,
    getActiveElement: () => activeElement,
    isActiveInsidePanel: isInside,
    trapTabFocus: (trappedPanel, event) => {
      calls.push(`${trappedPanel.id}:${event.key}`);
    },
  });

  listener?.({ key: 'Tab' } as KeyboardEvent);
  activeElement = outsideActive;
  listener?.({ key: 'Tab' } as KeyboardEvent);
  listener?.({ key: 'Escape' } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, ['panel:Tab', 'cleanup']);
  assert.equal(listener, undefined);
});

test('slide panel tab trap runtime is a no-op without a document target', () => {
  const calls: string[] = [];

  const cleanup = installSlidePanelTabTrapRuntime({
    documentTarget: undefined,
    getPanel: () => panel,
    getActiveElement: () => insideActive,
    isActiveInsidePanel: isInside,
    trapTabFocus: () => calls.push('trap'),
  });

  cleanup();

  assert.deepEqual(calls, []);
});

test('slide panel browser tab trap deps safely read active element host state', () => {
  const calls: string[] = [];
  let listener: EventListener | undefined;
  const activeNode = {} as Node;
  const documentTarget = {
    activeElement: activeNode,
    addEventListener: (_type: string, nextListener: EventListener) => {
      listener = nextListener;
    },
    removeEventListener: (_type: string, nextListener: EventListener) => {
      if (listener === nextListener) listener = undefined;
    },
  };
  const panelElement = {
    contains: (activeElement: Node) => activeElement === activeNode,
  } as HTMLElement;

  const deps = createBrowserSlidePanelTabTrapRuntimeDeps({
    documentTarget,
    getPanel: () => panelElement,
    nodeConstructor: Object as unknown as typeof Node,
    trapTabFocus: (_panel, event) => calls.push(event.key),
  });

  const cleanup = installSlidePanelTabTrapRuntime(deps);
  listener?.({ key: 'Tab' } as KeyboardEvent);
  cleanup();

  assert.deepEqual(calls, ['Tab']);
  assert.equal(listener, undefined);
});

test('slide panel browser tab trap deps are inert without document or Node hosts', () => {
  const panelElement = {
    contains: () => true,
  } as unknown as HTMLElement;

  const noDocumentDeps = createBrowserSlidePanelTabTrapRuntimeDeps({
    documentTarget: undefined,
    getPanel: () => panelElement,
    nodeConstructor: Object as unknown as typeof Node,
    trapTabFocus: () => assert.fail('trapTabFocus should not run without a document target'),
  });

  assert.equal(noDocumentDeps.documentTarget, undefined);
  assert.equal(noDocumentDeps.getActiveElement(), null);
  assert.equal(noDocumentDeps.isActiveInsidePanel(panelElement, {} as Element), false);

  const noNodeDeps = createBrowserSlidePanelTabTrapRuntimeDeps({
    documentTarget: {
      activeElement: {} as Element,
      addEventListener: () => undefined,
      removeEventListener: () => undefined,
    },
    getPanel: () => panelElement,
    nodeConstructor: undefined,
    trapTabFocus: () => assert.fail('trapTabFocus should not run without Node'),
  });

  assert.equal(noNodeDeps.getActiveElement(), null);
  assert.equal(noNodeDeps.isActiveInsidePanel(panelElement, {} as Element), false);
});

test('slide panel component delegates Tab trapping to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/SlidePanel.tsx'),
    'utf8',
  );

  assert.match(
    source,
    /import \{\s*createBrowserSlidePanelTabTrapRuntimeDeps,\s*installSlidePanelTabTrapRuntime,\s*\} from '\.\/SlidePanel\.runtime';/,
  );
  assert.match(source, /return installSlidePanelTabTrapRuntime\(\s*createBrowserSlidePanelTabTrapRuntimeDeps\(\{/);
  assert.match(source, /getPanel: \(\) => panelRef\.current,/);
  assert.match(source, /trapTabFocus: trapTabFocusWithin,/);
  assert.doesNotMatch(source, /getActiveElement: \(\) => document\.activeElement,/);
  assert.doesNotMatch(source, /activeElement instanceof Node/);
  assert.doesNotMatch(source, /const handler = \(e: KeyboardEvent\) => \{/);
  assert.doesNotMatch(source, /document\.addEventListener\('keydown', handler\)/);
});
