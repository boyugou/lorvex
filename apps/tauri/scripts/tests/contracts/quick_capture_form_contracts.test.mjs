import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

const repoRoot = process.cwd();

function readSource(relativePath) {
  return fs.readFileSync(path.join(repoRoot, relativePath), 'utf8');
}

test('quick capture centralizes tag draft handling across title toolbar and submit paths', () => {
  const titleInput = readSource('app/src/components/quick-capture/TitleInput.tsx');
  const toolbar = readSource('app/src/components/quick-capture/toolbar/TagsToggle.tsx');
  const formLogic = readSource('app/src/components/quick-capture/useQuickCaptureForm.logic.ts');

  assert.match(titleInput, /appendQuickCaptureTagDraft/);
  assert.match(titleInput, /parseQuickCaptureTagDraft/);
  assert.match(toolbar, /clampQuickCaptureTagDraftInput/);
  assert.match(toolbar, /currentQuickCaptureTagToken/);
  assert.match(toolbar, /replaceCurrentQuickCaptureTagToken/);
  assert.match(formLogic, /serializeQuickCaptureSubmissionTags/);
  assert.doesNotMatch(toolbar, /function parseTagTokens/);
  assert.doesNotMatch(toolbar, /function replaceCurrentToken/);
});

test('quick capture setup bootstrap loads setup status through one IPC path', () => {
  const formHook = readSource('app/src/components/quick-capture/useQuickCaptureForm.ts');
  const setupHook = readSource('app/src/components/quick-capture/useQuickCaptureSetupBootstrap.ts');

  assert.match(formHook, /useQuickCaptureSetupBootstrap/);
  assert.match(setupHook, /resolveQuickCaptureSetupBootstrap/);
  assert.match(setupHook, /quickCaptureSetupListSignature/);
  assert.match(setupHook, /shouldLoadQuickCaptureSetupStatus/);
  assert.equal(
    (setupHook.match(/getSetupStatus\(/g) ?? []).length,
    1,
    'quick capture setup hook should make exactly one setup-status IPC call site',
  );
  assert.doesNotMatch(
    setupHook,
    /Failed to load setup status \(fallback\)/,
    'quick capture should not keep the old second fallback setup-status effect',
  );
});

test('quick capture controller delegates draft, setup, date, submit, and view-model concerns', () => {
  const formHook = readSource('app/src/components/quick-capture/useQuickCaptureForm.ts');
  const draftHook = readSource('app/src/components/quick-capture/useQuickCaptureDraft.ts');
  const setupHook = readSource('app/src/components/quick-capture/useQuickCaptureSetupBootstrap.ts');
  const dateHook = readSource('app/src/components/quick-capture/useQuickCaptureDateResolution.ts');
  const submitHook = readSource('app/src/components/quick-capture/useQuickCaptureSubmit.ts');
  const viewModel = readSource('app/src/components/quick-capture/quickCaptureFormViewModel.ts');

  assert.match(formHook, /useQuickCaptureDraftAutosave/);
  assert.match(formHook, /useQuickCaptureSetupBootstrap/);
  assert.match(formHook, /useQuickCaptureDateResolution/);
  assert.match(formHook, /useQuickCaptureSubmit/);
  assert.match(formHook, /buildQuickCaptureFormViewModel/);
  assert.doesNotMatch(formHook, /readDraft|writeDraft|clearDraft|getSetupStatus\(|parseDateFromText|quickCapture\(/);

  assert.match(draftHook, /readQuickCaptureDraft/);
  assert.match(draftHook, /installQuickCaptureDraftAutosaveRuntime/);
  assert.match(setupHook, /getSetupStatus\(/);
  assert.match(setupHook, /resolveQuickCaptureSetupBootstrap/);
  assert.match(dateHook, /parseDateFromText/);
  assert.match(dateHook, /resolvedDueDate/);
  assert.match(submitHook, /quickCapture\(/);
  assert.match(submitHook, /onReopenForRetry/);
  assert.match(viewModel, /export function buildQuickCaptureFormViewModel/);
});
