import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { extractRustFunctionBody, readAppSources, readRustSources, readTypeScriptSources, repoRoot } from './shared.mjs';

function readStringConstant(source, pattern, description, groupIndex = 1) {
  const match = source.match(pattern);
  assert.ok(match, `Expected ${description}`);
  return match[groupIndex];
}

test('quick capture intents reuse the deep-link event channel and pending queue transport', () => {
  const commandsSource = readRustSources(
    'app/src-tauri/src/commands.rs',
    // Post-#3303 split: window_commands.rs is now a folder.
    'app/src-tauri/src/commands/ui/window_commands',
  );
  const desktopShellSource = readRustSources('app/src-tauri/src/desktop_shell');
  const deepLinkSource = readRustSources('app/src-tauri/src/deep_link');
  const appSource = readAppSources();

  const rustEvent = readStringConstant(
    deepLinkSource,
    /pub const DEEP_LINK_OPEN_EVENT: &str = "([^"]+)";/,
    'DEEP_LINK_OPEN_EVENT in deep_link/',
  );

  const quickCaptureBody = extractRustFunctionBody(commandsSource, 'open_main_quick_capture');
  assert.match(
    quickCaptureBody,
    /let target = crate::deep_link::DeepLinkTarget::QuickCapture;/,
    'open_main_quick_capture should package quick capture requests as the canonical deep-link payload',
  );
  assert.match(
    quickCaptureBody,
    /crate::deep_link::enqueue_pending\(target\.clone\(\)\);/,
    'open_main_quick_capture should enqueue quick capture requests so the main app can recover missed live events',
  );
  assert.match(
    quickCaptureBody,
    /app\.emit\(crate::deep_link::DEEP_LINK_OPEN_EVENT, target\.to_payload\(\)\)/,
    'open_main_quick_capture should emit the canonical deep-link open event',
  );
  assert.match(
    desktopShellSource,
    /"quick_capture"\s*=>\s*\{[\s\S]*?let target = crate::deep_link::DeepLinkTarget::QuickCapture;[\s\S]*?crate::deep_link::enqueue_pending\(target\.clone\(\)\);[\s\S]*?app\.emit\(crate::deep_link::DEEP_LINK_OPEN_EVENT, target\.to_payload\(\)\);/,
    'tray menu quick capture should reuse the same deep-link event channel and pending queue transport',
  );
  assert.equal(
    rustEvent,
    'deep-link://open',
    'quick capture transport should reuse the canonical deep-link open event',
  );
  assert.doesNotMatch(
    appSource,
    /listen\('tray:\/\/quick-capture',/,
    'App.tsx should not keep a dedicated tray quick capture listener once quick capture transport reuses the deep-link channel',
  );
});

test('open_main_task_detail reuses the deep-link event channel and pending queue transport', () => {
  const rustSource = readRustSources(
    'app/src-tauri/src/commands.rs',
    // Post-#3303 split: window_commands.rs is now a folder.
    'app/src-tauri/src/commands/ui/window_commands',
  );
  const deepLinkSource = readRustSources('app/src-tauri/src/deep_link');
  const appSource = readAppSources();

  const rustEvent = readStringConstant(
    deepLinkSource,
    /pub const DEEP_LINK_OPEN_EVENT: &str = "([^"]+)";/,
    'DEEP_LINK_OPEN_EVENT in deep_link/',
  );
  const taskDetailBody = extractRustFunctionBody(rustSource, 'open_main_task_detail');

  assert.match(
    taskDetailBody,
    /let target = crate::deep_link::DeepLinkTarget::Task \{ task_id \};/,
    'open_main_task_detail should package task detail requests as the canonical deep-link task payload',
  );
  assert.match(
    taskDetailBody,
    /crate::deep_link::enqueue_pending\(target\.clone\(\)\);/,
    'open_main_task_detail should enqueue task detail requests so the main app can recover missed live events',
  );
  assert.match(
    taskDetailBody,
    /app\.emit\(crate::deep_link::DEEP_LINK_OPEN_EVENT, target\.to_payload\(\)\)/,
    'open_main_task_detail should emit the canonical deep-link open event',
  );
});

test('tray popover-opened event channel stays aligned between Rust emitters and popover listeners', () => {
  // The literal channel string was lifted to a shared `event_channels` module
  // so Rust callers reference it by constant; the popover listener still
  // hard-codes the literal until a renderer-side constant ships.
  const eventChannelsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src-tauri/src/event_channels.rs'),
    'utf8',
  );
  const trayEmitSource = readRustSources('app/src-tauri/src/desktop_shell');
  const controllerSource = readTypeScriptSources(
    'app/src/components/popover-window/usePopoverWindowController.ts',
    'app/src/components/popover-window/controller',
  );

  const rustEvent = readStringConstant(
    eventChannelsSource,
    /pub const TRAY_POPOVER_OPENED: &str = "([^"]+)";/,
    'TRAY_POPOVER_OPENED constant in event_channels.rs',
  );
  // Confirm the emit site references the canonical constant.
  assert.match(
    trayEmitSource,
    /app\.emit\(event_channels::TRAY_POPOVER_OPENED,\s*\(\)\)/,
    'desktop_shell tray emitter should reference the shared TRAY_POPOVER_OPENED constant',
  );
  const appEvent = readStringConstant(
    controllerSource,
    /listen\('([^']+)', onOpened\)/,
    'tray popover-opened listener channel in the popover controller tree',
  );

  assert.equal(
    appEvent,
    rustEvent,
    'PopoverWindow should listen on the same tray popover-opened channel that Rust emits',
  );
});

test('deep-link open event channel stays aligned between Rust and App listeners', () => {
  const rustSource = readRustSources('app/src-tauri/src/deep_link');
  const appSource = readAppSources();

  const rustEvent = readStringConstant(
    rustSource,
    /pub const DEEP_LINK_OPEN_EVENT: &str = "([^"]+)";/,
    'DEEP_LINK_OPEN_EVENT in deep_link/',
  );
  const appEvent = readStringConstant(
    appSource,
    /listen<DeepLinkTarget>\('([^']+)', \(event\) => \{/,
    'deep-link open listener channel in App.tsx',
  );

  assert.equal(
    appEvent,
    rustEvent,
    'App.tsx should listen on the same deep-link open event channel that Rust emits',
  );
});
