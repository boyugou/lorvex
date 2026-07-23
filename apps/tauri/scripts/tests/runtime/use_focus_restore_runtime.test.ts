import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readActiveHTMLElement } from '../../../app/src/lib/focus/useFocusRestore.runtime';

test('focus restore active element reader returns null without DOM hosts', () => {
  assert.equal(readActiveHTMLElement(undefined, undefined), null);
});

test('focus restore active element reader returns only matching active HTMLElements', () => {
  class FakeHTMLElement {}

  const activeElement = new FakeHTMLElement();
  const elementConstructor = FakeHTMLElement as unknown as typeof HTMLElement;

  assert.equal(
    readActiveHTMLElement(
      { activeElement } as unknown as Pick<Document, 'activeElement'>,
      elementConstructor,
    ),
    activeElement,
  );
  assert.equal(
    readActiveHTMLElement(
      { activeElement: {} } as unknown as Pick<Document, 'activeElement'>,
      elementConstructor,
    ),
    null,
  );
});

test('useFocusRestore delegates active element reads to the runtime seam', () => {
  const source = fs.readFileSync(
    path.join(process.cwd(), 'app/src/lib/focus/useFocusRestore.ts'),
    'utf8',
  );

  assert.match(source, /import \{ readActiveHTMLElement \} from '\.\/useFocusRestore\.runtime';/);
  assert.match(source, /machine\.open\(readActiveHTMLElement\(\)\);/);
  assert.doesNotMatch(source, /document\.activeElement instanceof HTMLElement/);
});

test('focus restore overlay consumers delegate active element reads to the runtime seam', () => {
  const slidePanelSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/SlidePanel.tsx'),
    'utf8',
  );
  const modalShellSource = fs.readFileSync(
    path.join(process.cwd(), 'app/src/components/ui/overlay/ModalShell.tsx'),
    'utf8',
  );

  assert.match(
    slidePanelSource,
    /import \{ readActiveHTMLElement \} from ['"](?:@\/lib\/focus\/useFocusRestore\.runtime|\.\.\/\.\.\/lib\/focus\/useFocusRestore\.runtime)['"];/,
  );
  assert.match(slidePanelSource, /machine\.open\(readActiveHTMLElement\(\)\);/);
  assert.doesNotMatch(slidePanelSource, /document\.activeElement instanceof HTMLElement/);

  assert.match(
    modalShellSource,
    /import \{ readActiveHTMLElement \} from ['"](?:@\/lib\/focus\/useFocusRestore\.runtime|\.\.\/\.\.\/\.\.\/lib\/focus\/useFocusRestore\.runtime)['"];/,
  );
  assert.match(modalShellSource, /triggerRef\.current\s*\?\?\s*readActiveHTMLElement\(\)/);
  assert.doesNotMatch(modalShellSource, /document\.activeElement instanceof HTMLElement/);
});
