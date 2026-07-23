import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  computeVisualViewportInset,
  installVisualViewportInsetTracking,
  type VisualViewportInsetHost,
} from '../../../app/src/lib/useVisualViewport';

const repoRoot = process.cwd();

test('computeVisualViewportInset clamps negative insets to zero', () => {
  assert.equal(computeVisualViewportInset(800, 780, 40), 0);
});

test('computeVisualViewportInset returns the soft-keyboard inset from viewport height and offset', () => {
  assert.equal(computeVisualViewportInset(800, 500, 20), 280);
});

test('installVisualViewportInsetTracking updates the inset immediately and on viewport changes', () => {
  let innerHeight = 800;
  let viewportHeight = 600;
  let offsetTop = 0;
  let listener: (() => void) | null = null;
  const insets: number[] = [];
  let clearCalls = 0;

  const host: VisualViewportInsetHost = {
    getInnerHeight: () => innerHeight,
    getViewportHeight: () => viewportHeight,
    getOffsetTop: () => offsetTop,
    onViewportChange: (nextListener) => {
      listener = nextListener;
      return () => {
        listener = null;
      };
    },
    setInsetPx: (insetPx) => {
      insets.push(insetPx);
    },
    clearInset: () => {
      clearCalls += 1;
    },
  };

  const cleanup = installVisualViewportInsetTracking(host);
  assert.deepEqual(insets, [200]);

  viewportHeight = 500;
  offsetTop = 20;
  listener?.();
  assert.deepEqual(insets, [200, 280]);

  cleanup();
  assert.equal(listener, null);
  assert.equal(clearCalls, 1);
});

test('installVisualViewportInsetTracking is a no-op without a host', () => {
  const cleanup = installVisualViewportInsetTracking(null);
  assert.doesNotThrow(() => cleanup());
});

test('visual viewport hook delegates browser host creation through the runtime helper', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/useVisualViewport.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/lib/useVisualViewport.runtime.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      "import { createBrowserVisualViewportInsetHost } from './useVisualViewport.runtime';",
    ),
  );
  assert.ok(source.includes('host: VisualViewportInsetHost | null = createBrowserVisualViewportInsetHost(),'));
  assert.ok(!source.includes("typeof window === 'undefined' || !window.visualViewport"));

  assert.ok(runtimeSource.includes('export function createBrowserVisualViewportInsetHost(): VisualViewportInsetHost | null {'));
  assert.ok(runtimeSource.includes("if (typeof window === 'undefined' || !window.visualViewport || typeof document === 'undefined') {"));
  assert.ok(runtimeSource.includes("document.documentElement.style.setProperty('--kb-inset', `${insetPx}px`);"));
  assert.ok(runtimeSource.includes("document.documentElement.style.removeProperty('--kb-inset');"));
});
