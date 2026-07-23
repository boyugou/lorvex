import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

const MENU_LOGIC_REL = 'app/src/app-shell/main-window/runtime/useMenuEvents.logic.ts';

/**
 * Statically parse the keys of `MENU_VIEW_TYPE_MAP` out of the `.ts` source.
 *
 * The contract runner (`node --test`) does not run with a TypeScript loader,
 * so importing the `.ts` file directly throws `ERR_UNKNOWN_FILE_EXTENSION`
 * inside an asynchronous-after-test handler — silently failing the suite
 * with a confusing diagnostic. Parsing the source keeps this `.mjs` test
 * loader-free and makes the Rust↔frontend menu-id parity check robust to
 * any future TS-runtime drift.
 *
 * The shape is a plain object literal:
 *
 *   export const MENU_VIEW_TYPE_MAP = {
 *     today: { type: 'today' },
 *     ...
 *   } satisfies Record<string, View>;
 *
 * so a regex over `^\s+(\w+):\s*\{` inside the literal body is unambiguous.
 * Anything more elaborate (RegExp on commas, eval) trades correctness for
 * cleverness — keep the parser dumb and the failure mode obvious.
 */
function readMenuViewTypeKeys() {
  const source = fs.readFileSync(path.join(repoRoot, MENU_LOGIC_REL), 'utf8');
  const startMatch = source.match(/export const MENU_VIEW_TYPE_MAP\s*=\s*\{/);
  if (!startMatch) {
    throw new Error(
      `[contract] could not locate MENU_VIEW_TYPE_MAP literal in ${MENU_LOGIC_REL}`,
    );
  }
  const startIdx = startMatch.index + startMatch[0].length;
  // The literal ends at the matching `}` — counted via brace depth so that
  // nested `{ type: 'today' }` value bodies do not terminate the scan early.
  let depth = 1;
  let endIdx = -1;
  for (let i = startIdx; i < source.length; i++) {
    const ch = source[i];
    if (ch === '{') depth += 1;
    else if (ch === '}') {
      depth -= 1;
      if (depth === 0) {
        endIdx = i;
        break;
      }
    }
  }
  if (endIdx === -1) {
    throw new Error(
      `[contract] unterminated MENU_VIEW_TYPE_MAP literal in ${MENU_LOGIC_REL}`,
    );
  }
  const body = source.slice(startIdx, endIdx);
  const keys = [...body.matchAll(/^\s*([a-z_][a-z0-9_]*):\s*\{/gm)].map(([, key]) => key);
  if (keys.length === 0) {
    throw new Error(
      `[contract] parsed MENU_VIEW_TYPE_MAP literal had zero keys — parser regex drifted`,
    );
  }
  return keys;
}

test('desktop-shell menu navigation payloads stay in sync with frontend menu view routing', () => {
  const rustSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/desktop_shell/app_menu.rs'),
    'utf8',
  );

  const rustPayloads = [...rustSource.matchAll(/"view_([a-z_]+)"/g)]
    .map(([, viewType]) => viewType)
    .filter((viewType, index, all) => all.indexOf(viewType) === index)
    .sort();

  const menuViewTypeKeys = readMenuViewTypeKeys();

  assert.deepEqual(
    rustPayloads,
    menuViewTypeKeys.filter((viewType) => viewType !== 'settings').sort(),
    'Rust `view_*` menu ids should stay in parity with frontend menu payload routing',
  );

  // The literal `menu://navigate` channel was lifted into the shared
  // `event_channels` module; assertions reference the constant.
  const eventChannelsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/event_channels.rs'),
    'utf8',
  );
  assert.match(
    eventChannelsSource,
    /pub const MENU_NAVIGATE: &str = "menu:\/\/navigate";/,
    'event_channels.rs should define the canonical menu://navigate channel constant',
  );
  assert.match(
    rustSource,
    /"settings"\s*=>\s*\{\s*let _ = app\.emit\(event_channels::MENU_NAVIGATE,\s*"settings"\);/s,
    'settings should continue emitting the dedicated menu://navigate payload via the shared constant',
  );
});
