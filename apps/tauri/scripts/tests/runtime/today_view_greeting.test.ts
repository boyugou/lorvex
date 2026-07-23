import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { resolveTodayGreetingKey } from '../../../app/src/components/today-view/greeting';

test('today view greeting resolves from timezone clock boundaries', () => {
  assert.equal(resolveTodayGreetingKey('00:00'), 'greeting.morning');
  assert.equal(resolveTodayGreetingKey('11:59'), 'greeting.morning');
  assert.equal(resolveTodayGreetingKey('12:00'), 'greeting.afternoon');
  assert.equal(resolveTodayGreetingKey('16:59'), 'greeting.afternoon');
  assert.equal(resolveTodayGreetingKey('17:00'), 'greeting.evening');
  assert.equal(resolveTodayGreetingKey('23:59'), 'greeting.evening');
});

test('today view greeting fails closed for malformed clock values', () => {
  assert.equal(resolveTodayGreetingKey(''), 'greeting.morning');
  assert.equal(resolveTodayGreetingKey('24:00'), 'greeting.morning');
  assert.equal(resolveTodayGreetingKey('noon'), 'greeting.morning');
});

test('today view controller derives greeting from the shared current-time hook', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/today-view/useTodayViewController.ts'),
    'utf8',
  );

  assert.match(
    source,
    /import \{ useCurrentTime \} from ['"](?:@\/lib\/time\/useCurrentTime|\.\.\/\.\.\/lib\/time\/useCurrentTime)['"];/,
  );
  assert.match(source, /const currentTime = useCurrentTime\(dayContext\.timezone\);/);
  assert.match(source, /const greeting = t\(resolveTodayGreetingKey\(currentTime\)\);/);
  assert.doesNotMatch(source, /new Intl\.DateTimeFormat\('en-US'[\s\S]*hour:[\s\S]*new Date\(\)/);
});
