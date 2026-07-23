import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { repoRoot } from './shared.mjs';

test('AI memory surfaces delegate mutation ownership to dedicated runtime hooks', () => {
  const memoryEntryCardSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/MemoryEntryCard.tsx'),
    'utf8',
  );
  const notesForAiSectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/NotesForAiSection.tsx'),
    'utf8',
  );
  const historyModalSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/HistoryModal.tsx'),
    'utf8',
  );
  const actionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/useAiMemoryActions.ts'),
    'utf8',
  );

  assert.match(
    memoryEntryCardSource,
    /import \{ useForgetMemoryEntryAction \} from '\.\/useAiMemoryActions';/,
    'MemoryEntryCard should delegate forget mutations to a dedicated AI-memory action hook',
  );
  assert.doesNotMatch(memoryEntryCardSource, /useMutation\(\{|deleteAiMemoryEntry\(/);

  assert.match(
    notesForAiSectionSource,
    /import \{ useNotesForAiActions \} from '\.\/useAiMemoryActions';/,
    'NotesForAiSection should delegate save/delete mutations to a dedicated AI-memory action hook',
  );
  assert.doesNotMatch(notesForAiSectionSource, /useMutation\(\{|setNotesForAi\(|deleteNotesForAi\(/);

  assert.match(
    historyModalSource,
    /import \{ useRestoreMemoryRevisionAction \} from '\.\/useAiMemoryActions';/,
    'HistoryModal should delegate restore mutations to a dedicated AI-memory action hook',
  );
  assert.doesNotMatch(historyModalSource, /useMutation\(\{|restoreMemoryRevision\(/);

  assert.match(actionsSource, /export function useForgetMemoryEntryAction\(/);
  assert.match(actionsSource, /export function useNotesForAiActions\(/);
  assert.match(actionsSource, /export function useRestoreMemoryRevisionAction\(/);
  assert.match(actionsSource, /useMutation\(\{/);
});

test('AI memory content textareas use the backend memory content limit', () => {
  const sharedValidationSource = fs.readFileSync(
    path.join(repoRoot, 'shared/src/validation.ts'),
    'utf8',
  );
  const rustMemorySource = fs.readFileSync(
    path.join(repoRoot, 'lorvex-domain/src/memory/mod.rs'),
    'utf8',
  );
  const addMemoryFormSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/AddMemoryForm.tsx'),
    'utf8',
  );
  const notesForAiSectionSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/ai-memory/NotesForAiSection.tsx'),
    'utf8',
  );

  const rustLimit = rustMemorySource.match(/pub const MAX_MEMORY_CONTENT_LENGTH: usize = ([\d_]+);/);
  assert.ok(rustLimit, 'lorvex-domain should declare MAX_MEMORY_CONTENT_LENGTH');

  assert.match(
    sharedValidationSource,
    new RegExp(`export const MAX_MEMORY_CONTENT_LENGTH = ${rustLimit[1]};`),
    'shared validation should mirror the Rust memory content limit',
  );

  for (const [label, source] of [
    ['AddMemoryForm', addMemoryFormSource],
    ['NotesForAiSection', notesForAiSectionSource],
  ]) {
    assert.match(
      source,
      /import \{ MAX_MEMORY_CONTENT_LENGTH \} from '@lorvex\/shared\/validation';/,
      `${label} should import the memory content limit`,
    );
    assert.match(
      source,
      /maxLength=\{MAX_MEMORY_CONTENT_LENGTH\}/,
      `${label} content textarea should use the memory content limit`,
    );
    assert.doesNotMatch(
      source,
      /MAX_SHORT_TEXT_LENGTH/,
      `${label} should not cap memory content with the short-text limit`,
    );
  }
});
