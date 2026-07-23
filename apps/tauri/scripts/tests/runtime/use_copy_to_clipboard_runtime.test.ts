import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { createBrowserClipboardWriter } from '../../../app/src/lib/platform/useCopyToClipboard.runtime';

test('browser clipboard writer rejects when the Clipboard API is unavailable', async () => {
  const writer = createBrowserClipboardWriter(undefined);

  await assert.rejects(
    () => writer.writeText('hello'),
    /Clipboard API is unavailable/,
  );
});

test('browser clipboard writer preserves the clipboard writeText receiver', async () => {
  const calls: string[] = [];
  const clipboard = {
    async writeText(this: unknown, text: string) {
      assert.equal(this, clipboard);
      calls.push(text);
    },
  };
  const writer = createBrowserClipboardWriter({ clipboard });

  await writer.writeText('hello');

  assert.deepEqual(calls, ['hello']);
});

test('useCopyToClipboard delegates browser clipboard access to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/platform/useCopyToClipboard.ts'),
    'utf8',
  );

  assert.match(source, /import \{ createBrowserClipboardWriter \} from '\.\/useCopyToClipboard\.runtime';/);
  assert.match(source, /const clipboardWriterRef = useLazyRef\(\(\) => createBrowserClipboardWriter\(\)\);/);
  assert.doesNotMatch(source, /navigator\.clipboard/);
});
