import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import {
  createBrowserDangerZoneResetTimerHost,
  scheduleDangerZoneResetReload,
  type DangerZoneResetTimerHost,
} from '../../../app/src/components/settings/data/dangerZoneActions.runtime';

const repoRoot = process.cwd();

function createTimerHost() {
  const callbacks: Array<() => void> = [];
  const delays: number[] = [];
  const host: DangerZoneResetTimerHost = {
    setTimeout: (callback, delayMs) => {
      callbacks.push(callback);
      delays.push(delayMs);
      return `timer-${callbacks.length}` as ReturnType<typeof globalThis.setTimeout>;
    },
  };

  return {
    callbacks,
    delays,
    host,
  };
}

test('danger zone reset runtime schedules reload after the requested delay', () => {
  const timer = createTimerHost();
  let reloadCount = 0;

  scheduleDangerZoneResetReload(800, () => {
    reloadCount += 1;
  }, timer.host);

  assert.deepEqual(timer.delays, [800]);
  assert.equal(reloadCount, 0);

  timer.callbacks[0]?.();

  assert.equal(reloadCount, 1);
});

test('danger zone actions delegate reset reload timing through the runtime helper', () => {
  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/useDangerZoneActions.ts'),
    'utf8',
  );

  assert.ok(
    source.includes(
      "import {\n  createBrowserDangerZoneResetTimerHost,\n  scheduleDangerZoneResetReload,\n} from './dangerZoneActions.runtime';",
    ),
  );
  assert.ok(source.includes('const dangerZoneResetTimerHost = createBrowserDangerZoneResetTimerHost();'));
  assert.ok(source.includes("import { clearAllDrafts } from '@/lib/storage/drafts';"));
  assert.ok(source.includes('clearAllDrafts();'));
  assert.ok(source.includes('scheduleDangerZoneResetReload(RESET_RELOAD_DELAY_MS, () => {'));
  assert.ok(source.includes('window.location.reload();'));
  assert.ok(source.includes('}, dangerZoneResetTimerHost);'));
  assert.ok(!source.includes('globalThis.setTimeout'));
  assert.ok(!source.includes('window.setTimeout(() => {'));
});

test('danger zone reset runtime owns the browser timer host wiring', () => {
  const host = createBrowserDangerZoneResetTimerHost();
  assert.equal(typeof host.setTimeout, 'function');

  const source = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/settings/data/dangerZoneActions.runtime.ts'),
    'utf8',
  );

  assert.match(source, /export function createBrowserDangerZoneResetTimerHost\(\): DangerZoneResetTimerHost/);
  assert.ok(
    source.includes('setTimeout: (callback, delayMs) => globalThis.setTimeout(callback, delayMs),'),
  );
});
