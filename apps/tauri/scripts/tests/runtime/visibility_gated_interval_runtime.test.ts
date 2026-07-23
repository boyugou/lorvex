import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { startVisibilityGatedIntervalRuntime } from '../../../app/src/lib/time/intervalHooks.runtime';

test('visibility-gated interval runtime still mounts and disposes without a document host', () => {
  const calls: string[] = [];

  const dispose = startVisibilityGatedIntervalRuntime({
    intervalMs: 15_000,
    documentTarget: null,
    host: {
      isVisible: () => true,
      runTick: () => {
        calls.push('tick');
      },
      setInterval: () => {
        calls.push('arm');
        return () => {
          calls.push('disarm');
        };
      },
    },
  });

  dispose();

  assert.deepEqual(calls, ['tick', 'arm', 'disarm']);
});

test('visibility-gated interval hook delegates optional document wiring to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/time/useVisibilityGatedInterval.ts'),
    'utf8',
  );
  const runtimeSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/time/intervalHooks.runtime.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{[\s\S]*createBrowserVisibilityGatedIntervalRuntimeDeps,[\s\S]*startVisibilityGatedIntervalRuntime,[\s\S]*\} from '\.\/intervalHooks\.runtime';/,
  );
  assert.match(
    source,
    /return startVisibilityGatedIntervalRuntime\(\{[\s\S]*\.\.\.createBrowserVisibilityGatedIntervalRuntimeDeps\(\(\) => cbRef\.current\(\)\),[\s\S]*\}\);/s,
  );
  assert.doesNotMatch(source, /documentTarget: typeof document === 'undefined' \? null : document/);
  assert.doesNotMatch(source, /const timer = setInterval\(/);

  assert.match(
    runtimeSource,
    /export function createBrowserVisibilityGatedIntervalRuntimeDeps\(/,
  );
  assert.match(
    runtimeSource,
    /documentTarget: typeof document === 'undefined' \? null : document,/,
  );
  assert.match(
    runtimeSource,
    /isVisible: \(\) => \(typeof document === 'undefined' \? true : document\.visibilityState === 'visible'\),/,
  );
});
