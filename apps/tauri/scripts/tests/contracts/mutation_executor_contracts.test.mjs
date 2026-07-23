import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readRustSources, repoRoot } from './shared.mjs';

function source(relPath) {
  const absPath = path.join(repoRoot, relPath);
  return fs.existsSync(absPath) ? fs.readFileSync(absPath, 'utf8') : '';
}

function sources(relPaths) {
  return relPaths.map(source).join('\n');
}

function functionSlice(sourceText, signaturePattern, nextSignaturePattern) {
  const startMatch = signaturePattern.exec(sourceText);
  assert.ok(startMatch, `missing function signature ${signaturePattern}`);
  const start = startMatch.index;
  const rest = sourceText.slice(start + startMatch[0].length);
  const endMatch = nextSignaturePattern.exec(rest);
  assert.ok(endMatch, `missing function boundary ${nextSignaturePattern}`);
  return sourceText.slice(start, start + startMatch[0].length + endMatch.index);
}

test('Mutation<T> migrated surfaces use executor adapters instead of open-coded apply-plus-audit funnels', () => {
  const workflowMutation = source('lorvex-workflow/src/mutation.rs');
  const mcpChangeTrackingRoot = source('mcp-server/src/runtime/change_tracking/mod.rs');
  const mcpExecutor = readRustSources('mcp-server/src/runtime/change_tracking/mutation_executor');
  const cliSharedEffects = source('lorvex-cli/src/commands/shared/effects/mod.rs');

  assert.match(
    workflowMutation,
    /pub struct MutationExecution\b/,
    'workflow mutation module should expose the execution payload finalized by surface adapters',
  );
  assert.match(
    workflowMutation,
    /pub fn execute_with_context\b/,
    'workflow mutation module should provide an executor that runs apply and a required finalizer together',
  );
  assert.doesNotMatch(
    workflowMutation,
    /\bfn apply_with_context\b/,
    'workflow mutation module should not keep the old apply-only helper after finalizer executor migration',
  );
  assert.match(
    mcpChangeTrackingRoot,
    /^mod mutation_executor;$/m,
    'MCP change tracking should keep mutation executor side effects in a focused module',
  );
  assert.match(
    mcpChangeTrackingRoot,
    /pub\(crate\) use mutation_executor::\{[\s\S]*\bexecute_mcp_mutation\b[\s\S]*\};/m,
    'MCP change tracking facade should expose the mutation executor adapter',
  );
  assert.match(
    mcpExecutor,
    /pub\(crate\) fn execute_mcp_mutation\b/,
    'MCP adapter should own with_hlc_session + log_change for Mutation<T> sites',
  );
  assert.match(
    mcpExecutor,
    /pub\(crate\) fn execute_mcp_batch_mutation_with_audit_finalizer\b/,
    'MCP adapter should provide a batch audit helper for Mutation<T> sites that log entity_ids',
  );
  assert.match(
    cliSharedEffects,
    /pub\(crate\) fn execute_cli_entity_mutation_map_store_error\b/,
    'CLI shared effects should own apply + outbox + changelog + local_change_seq for Mutation<T> sites',
  );

  const directApplyImports = [
    ...readRustSources('mcp-server/src').matchAll(/use lorvex_workflow::mutation::\{[^}]*apply_with_context[^}]*}/g),
    ...readRustSources('lorvex-cli/src').matchAll(/use lorvex_workflow::mutation::\{[^}]*apply_with_context[^}]*}/g),
  ];
  assert.equal(
    directApplyImports.length,
    0,
    'surface modules should not import apply_with_context directly after executor adapter migration',
  );

  const directApplyCalls = [
    ...readRustSources('mcp-server/src').matchAll(/\bapply_with_context\(/g),
    ...readRustSources('lorvex-cli/src').matchAll(/\bapply_with_context\(/g),
  ];
  assert.equal(
    directApplyCalls.length,
    0,
    'surface modules should not call apply_with_context directly after executor adapter migration',
  );
});

test('CLI preference delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const preferenceSource = source('lorvex-cli/src/commands/mutate/preferences/effects.rs');
  const deleteFunctionSource = functionSlice(
    preferenceSource,
    /\npub\(crate\) fn delete_preference_with_conn\b/,
    /$/,
  );

  assert.match(
    preferenceSource,
    /struct DeletePreferenceMutation\b/,
    'CLI delete_preference should describe the clear as a Mutation descriptor',
  );
  assert.match(
    preferenceSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeletePreferenceMutation/,
    'CLI delete_preference descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deleteFunctionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI delete_preference should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    deleteFunctionSource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI delete_preference should let the executor path own HLC minting and audit logging',
  );
});

test('CLI daily review add and amend writes use Mutation executor instead of open-coded HLC and audit', () => {
  const dailySource = source('lorvex-cli/src/commands/mutate/reviews/effects/daily.rs');
  const syncOutboxSource = source('lorvex-cli/src/commands/mutate/reviews/effects/sync_outbox.rs');
  const combined = `${dailySource}\n${syncOutboxSource}`;

  assert.match(
    dailySource,
    /struct AddCliDailyReviewMutation\b/,
    'CLI add_daily_review should describe the upsert as a Mutation descriptor',
  );
  assert.match(
    dailySource,
    /struct AmendCliDailyReviewMutation\b/,
    'CLI amend_daily_review should describe the update as a Mutation descriptor',
  );
  assert.match(
    dailySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddCliDailyReviewMutation/,
    'CLI add_daily_review descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    dailySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AmendCliDailyReviewMutation/,
    'CLI amend_daily_review descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...dailySource.matchAll(/\bexecute_cli_mutation_with_finalizer\(/g)].length,
    2,
    'CLI daily review add and amend handlers should each call the CLI mutation executor adapter',
  );
  assert.match(
    syncOutboxSource,
    /enqueue_daily_review_payload_upsert\([^)]*hlc_state:\s*&mut HlcState/s,
    'CLI daily review outbox helper should reuse the executor HLC state',
  );
  assert.doesNotMatch(
    combined,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI daily review writes should let the executor path own HLC minting and audit logging',
  );
});

test('CLI habit reminder policy writes use Mutation executor instead of open-coded HLC and audit', () => {
  const policySource = source('lorvex-cli/src/commands/mutate/habits/effects/reminder_policy.rs');

  assert.match(
    policySource,
    /struct UpsertCliHabitReminderPolicyMutation\b/,
    'CLI habit reminder policy upsert should describe the row write as a Mutation descriptor',
  );
  assert.match(
    policySource,
    /struct DeleteCliHabitReminderPolicyMutation\b/,
    'CLI habit reminder policy delete should describe the row write as a Mutation descriptor',
  );
  assert.match(
    policySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UpsertCliHabitReminderPolicyMutation/,
    'CLI habit reminder policy upsert descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    policySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCliHabitReminderPolicyMutation/,
    'CLI habit reminder policy delete descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...policySource.matchAll(/\bexecute_cli_mutation_with_finalizer\(/g)].length,
    2,
    'CLI habit reminder policy upsert and delete should each call the CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    policySource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI habit reminder policy writes should let the executor path own HLC minting and audit logging',
  );
});

test('CLI task capture write uses Mutation executor instead of open-coded HLC and parent audit', () => {
  const captureSource = source('lorvex-cli/src/commands/mutate/tasks/capture_effects.rs');

  assert.match(
    captureSource,
    /struct CreateCliCapturedTaskMutation\b/,
    'CLI task capture should describe task creation as a Mutation descriptor',
  );
  assert.match(
    captureSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateCliCapturedTaskMutation/,
    'CLI task capture descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    captureSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI task capture should use the shared CLI mutation executor adapter',
  );
  assert.match(
    captureSource,
    /\blorvex_workflow::task_create::create_task\(/,
    'CLI task capture should reuse the canonical workflow task-create implementation',
  );
  assert.doesNotMatch(
    captureSource,
    /\bCliHlcStateHandle\b|\blog_cli_changelog\(/,
    'CLI task capture should let the executor path own HLC session setup and audit logging',
  );
});

test('CLI task trash restore write uses Mutation executor instead of open-coded HLC and audit', () => {
  const restorePath = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/restore.rs';
  const restoreSource = source(restorePath);
  const restoreFunctionSource = functionSlice(
    restoreSource,
    /\npub\(crate\) fn restore_task_from_trash_in_tx\b/,
    /$/,
  );

  assert.match(
    restoreSource,
    /struct RestoreCliTaskFromTrashMutation\b/,
    'CLI restore_task_from_trash should describe trash restore as a Mutation descriptor',
  );
  assert.match(
    restoreSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RestoreCliTaskFromTrashMutation/,
    'CLI trash restore descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    restoreFunctionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI restore_task_from_trash should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    restoreFunctionSource,
    /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI restore_task_from_trash should let the executor own HLC minting and audit logging',
  );
});

test('CLI task trash archive write uses Mutation executor instead of open-coded HLC and audit', () => {
  const archivePath = 'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/archive.rs';
  const archiveSource = source(archivePath);
  const archiveFunctionSource = functionSlice(
    archiveSource,
    /\npub\(crate\) fn archive_task_in_tx\b/,
    /$/,
  );

  assert.match(
    archiveSource,
    /struct ArchiveCliTaskToTrashMutation\b/,
    'CLI archive_task should describe trash archive as a Mutation descriptor',
  );
  assert.match(
    archiveSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+ArchiveCliTaskToTrashMutation/,
    'CLI trash archive descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    archiveFunctionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI archive_task should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    archiveFunctionSource,
    /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI archive_task should let the executor own HLC minting and audit logging',
  );
});

test('CLI task complete/cancel/reopen writes use Mutation executor instead of open-coded HLC and audit', () => {
  const lifecycleSource = source('lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/mod.rs');
  const completeSource = functionSlice(
    lifecycleSource,
    /\npub\(crate\) fn complete_task_in_tx\b/,
    /\n\/\/\/ Owned-tx wrapper\. See `complete_task_with_conn` for the rationale\.\n#\[cfg\(test\)\]\npub\(crate\) fn cancel_task_with_conn\b/,
  );
  const cancelSource = functionSlice(
    lifecycleSource,
    /\npub\(crate\) fn cancel_task_in_tx\b/,
    /\n\/\/\/ Owned-tx wrapper\. See `complete_task_with_conn` for the rationale\.\n#\[cfg\(test\)\]\npub\(crate\) fn reopen_task_with_conn\b/,
  );
  const reopenSource = functionSlice(
    lifecycleSource,
    /\npub\(crate\) fn reopen_task_in_tx\b/,
    /\n\/\/\/ Owned-tx wrapper\. See `complete_task_with_conn` for the rationale\.\n#\[cfg\(test\)\]\npub\(crate\) fn defer_task_with_conn\b/,
  );

  assert.match(
    lifecycleSource,
    /struct CliLifecycleMutation\b/,
    'CLI complete/cancel/reopen should share a lifecycle Mutation descriptor',
  );
  assert.match(
    lifecycleSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CliLifecycleMutation/,
    'CliLifecycleMutation should implement the workflow Mutation trait',
  );
  for (const [name, body] of [
    ['complete_task_in_tx', completeSource],
    ['cancel_task_in_tx', cancelSource],
    ['reopen_task_in_tx', reopenSource],
  ]) {
    assert.match(
      body,
      /\brun_lifecycle_transition_in_tx\(/,
      `${name} should route through the shared lifecycle mutation helper`,
    );
    assert.doesNotMatch(
      body,
      /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
      `${name} should let the executor own HLC minting and audit logging`,
    );
  }
});

test('CLI task defer write uses Mutation executor instead of open-coded HLC and audit', () => {
  const lifecycleSource = source('lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/mod.rs');
  const deferSource = functionSlice(
    lifecycleSource,
    /\npub\(crate\) fn defer_task_in_tx\b/,
    /\n#\[cfg\(test\)\]\nmod tests;/,
  );

  assert.match(
    lifecycleSource,
    /struct DeferCliTaskMutation\b/,
    'CLI defer_task should describe deferral as a Mutation descriptor',
  );
  assert.match(
    lifecycleSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeferCliTaskMutation/,
    'DeferCliTaskMutation should implement the workflow Mutation trait',
  );
  assert.match(
    deferSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'defer_task_in_tx should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    deferSource,
    /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'defer_task_in_tx should let the executor own HLC minting and audit logging',
  );
});

test('CLI task permanent delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deleteSource = source(
    'lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/trash/permanent_delete.rs',
  );
  const deleteFunction = functionSlice(
    deleteSource,
    /\npub\(crate\) fn permanent_delete_task_in_tx\b/,
    /\n}\s*$/,
  );

  assert.match(
    deleteSource,
    /struct PermanentDeleteCliTaskMutation\b/,
    'CLI permanent_delete_task should describe the root hard-delete as a Mutation descriptor',
  );
  assert.match(
    deleteSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+PermanentDeleteCliTaskMutation/,
    'PermanentDeleteCliTaskMutation should implement the workflow Mutation trait',
  );
  assert.match(
    deleteFunction,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'permanent_delete_task_in_tx should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    deleteFunction,
    /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'permanent_delete_task_in_tx should let the executor own HLC minting and audit logging',
  );
});

test('CLI task update write uses Mutation executor instead of open-coded HLC and audit', () => {
  const updateSource = source('lorvex-cli/src/commands/mutate/tasks/lifecycle_effects/update.rs');
  const updateFunction = functionSlice(
    updateSource,
    /\npub\(crate\) fn update_task_with_conn\b/,
    /\n}\s*$/,
  );

  assert.match(
    updateSource,
    /\bTaskUpdateInput\b/,
    'CLI update_task should route task patches through the canonical task update workflow',
  );
  assert.match(
    updateFunction,
    /\bflush_with_backend\(/,
    'update_task_with_conn should use the canonical task update flush backend',
  );
  assert.doesNotMatch(
    updateFunction,
    /\bnext_hlc_version\b|\bwith_hlc_state\b/,
    'update_task_with_conn should not use the legacy CLI HLC helpers',
  );
});

test('CLI memory writes use Mutation executor instead of open-coded HLC and audit', () => {
  const memorySource = readRustSources('lorvex-cli/src/commands/mutate/memory/effects');

  assert.match(
    memorySource,
    /struct WriteCliMemoryMutation\b/,
    'CLI memory write should describe memory upserts as a Mutation descriptor',
  );
  assert.match(
    memorySource,
    /struct DeleteCliMemoryMutation\b/,
    'CLI memory delete should describe memory deletes as a Mutation descriptor',
  );
  assert.match(
    memorySource,
    /struct RestoreCliMemoryMutation\b/,
    'CLI memory restore should describe revision restores as a Mutation descriptor',
  );
  assert.match(
    memorySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+WriteCliMemoryMutation/,
    'CLI memory write descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    memorySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCliMemoryMutation/,
    'CLI memory delete descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    memorySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RestoreCliMemoryMutation/,
    'CLI memory restore descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...memorySource.matchAll(/\bexecute_cli_mutation_with_finalizer\(/g)].length,
    3,
    'CLI memory write/delete/restore should each call the CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    memorySource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI memory writes should let the executor path own HLC minting and audit logging',
  );
});

test('CLI list CRUD writes use Mutation executor instead of open-coded HLC and audit', () => {
  const listSource = source('lorvex-cli/src/commands/mutate/lists/effects.rs');
  const listCrudSource = listSource.slice(
    listSource.indexOf('struct CreateCliListMutation'),
    listSource.indexOf('pub(crate) fn move_tasks_to_list_with_conn'),
  );

  assert.match(
    listCrudSource,
    /struct CreateCliListMutation\b/,
    'CLI list create should describe list insertion as a Mutation descriptor',
  );
  assert.match(
    listCrudSource,
    /struct UpdateCliListMutation\b/,
    'CLI list update should describe list patches as a Mutation descriptor',
  );
  assert.match(
    listCrudSource,
    /struct DeleteCliListMutation\b/,
    'CLI list delete should describe list deletion as a Mutation descriptor',
  );
  assert.match(
    listCrudSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateCliListMutation/,
    'CLI list create descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    listCrudSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UpdateCliListMutation/,
    'CLI list update descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    listCrudSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCliListMutation/,
    'CLI list delete descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...listCrudSource.matchAll(/\bexecute_cli_mutation_with_finalizer\(/g)].length,
    3,
    'CLI list create/update/delete should each call the CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    listCrudSource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI list CRUD writes should let the executor path own HLC minting and audit logging',
  );
});

test('CLI list task move write uses Mutation executor instead of open-coded HLC and audit', () => {
  const listSource = source('lorvex-cli/src/commands/mutate/lists/effects.rs');
  const moveSource = functionSlice(
    listSource,
    /\npub\(crate\) fn move_tasks_to_list_with_conn\b/,
    /\n}\s*$/,
  );

  assert.match(
    listSource,
    /struct MoveTasksToListMutation\b/,
    'CLI move_tasks_to_list should describe moved task rows as a Mutation descriptor',
  );
  assert.match(
    listSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+MoveTasksToListMutation/,
    'CLI move_tasks_to_list descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    moveSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI move_tasks_to_list should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    moveSource,
    /\blog_cli_changelog\(|\bhlc\.generate\(/,
    'CLI move_tasks_to_list should let the executor path own HLC minting and audit logging',
  );
});

test('CLI workflow list ops use Mutation executor instead of open-coded audit', () => {
  const listOpsSource = source('lorvex-cli/src/commands/workflow/list_ops.rs');
  const reorganizeSource = functionSlice(
    listOpsSource,
    /\npub\(crate\) fn run_reorganize_list\b/,
    /\nfn parse_reorganize_strategy\b/,
  );
  const permanentDeleteSource = functionSlice(
    listOpsSource,
    /\nfn run_permanent_delete_workflow\b/,
    /\n}\s*$/,
  );

  for (const descriptor of [
    'ReorganizeListCliMutation',
    'PermanentDeleteWorkflowCliMutation',
  ]) {
    assert.match(
      listOpsSource,
      new RegExp(`impl(?:<[^>]+>)?\\s+Mutation\\s+for\\s+${descriptor}`),
      `${descriptor} should implement the workflow Mutation trait`,
    );
  }
  assert.match(
    reorganizeSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'run_reorganize_list should use the shared CLI mutation executor adapter',
  );
  assert.match(
    permanentDeleteSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'run_permanent_delete_workflow should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    listOpsSource,
    /\blog_cli_changelog\(/,
    'CLI workflow list ops should let executor finalizers own audit logging',
  );
});

test('CLI habit create and update writes use Mutation executor instead of open-coded HLC and audit', () => {
  const habitCrudSource = readRustSources('lorvex-cli/src/commands/mutate/habits/effects/habit_crud');
  const createUpdateSource = sources([
    'lorvex-cli/src/commands/mutate/habits/effects/habit_crud/create.rs',
    'lorvex-cli/src/commands/mutate/habits/effects/habit_crud/update.rs',
  ]);

  assert.match(
    createUpdateSource,
    /struct CreateCliHabitMutation\b/,
    'CLI habit create should describe habit insertion as a Mutation descriptor',
  );
  assert.match(
    createUpdateSource,
    /struct UpdateCliHabitMutation\b/,
    'CLI habit update should describe habit updates as a Mutation descriptor',
  );
  assert.match(
    createUpdateSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateCliHabitMutation/,
    'CLI habit create descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    createUpdateSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UpdateCliHabitMutation/,
    'CLI habit update descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...createUpdateSource.matchAll(/\bexecute_cli_entity_mutation_map_store_error\(/g)].length,
    2,
    'CLI habit create and update should each call the CLI mutation executor entity adapter',
  );
  assert.doesNotMatch(
    createUpdateSource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI habit create/update should let the executor path own HLC minting and audit logging',
  );
});

test('CLI habit delete cascade write uses Mutation executor instead of open-coded HLC and audit', () => {
  const habitCrudSource = readRustSources('lorvex-cli/src/commands/mutate/habits/effects/habit_crud');
  const deleteSource = functionSlice(
    habitCrudSource,
    /\npub\(crate\) fn delete_habit_with_conn\b/,
    /\n}\s*$/,
  );

  assert.match(
    habitCrudSource,
    /struct DeleteCliHabitMutation\b/,
    'CLI habit delete should describe the root delete and child tombstones as a Mutation descriptor',
  );
  assert.match(
    habitCrudSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCliHabitMutation/,
    'CLI habit delete descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deleteSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI habit delete should use the CLI mutation executor adapter so cascade side effects share one HLC session',
  );
  assert.doesNotMatch(
    deleteSource,
    /\bnext_hlc_version\b|\blog_cli_changelog\(/,
    'CLI habit delete should let the executor path own root HLC minting and cascade audit logging',
  );
});

test('daily review add and amend writes use Mutation executor instead of open-coded HLC and audit', () => {
  const addSource = source('mcp-server/src/reviews/daily/writes/add.rs');
  const amendSource = source('mcp-server/src/reviews/daily/writes/amend.rs');
  const combined = `${addSource}\n${amendSource}`;

  assert.match(
    addSource,
    /struct AddDailyReviewMutation\b/,
    'add_daily_review should describe the upsert as a Mutation descriptor',
  );
  assert.match(
    amendSource,
    /struct AmendDailyReviewMutation\b/,
    'amend_daily_review should describe the update as a Mutation descriptor',
  );
  assert.match(
    combined,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddDailyReviewMutation/,
    'add_daily_review descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    combined,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AmendDailyReviewMutation/,
    'amend_daily_review descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...combined.matchAll(/\bexecute_mcp_mutation\(/g)].length,
    2,
    'daily review add and amend handlers should each call the MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    combined,
    /\bgenerate_hlc_version\b/,
    'daily review writes should mint versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    combined,
    /\blog_change\b|\bLogChangeParams\b/,
    'daily review writes should let execute_mcp_mutation own audit logging',
  );
});

test('list create write uses Mutation executor instead of open-coded HLC and audit', () => {
  const createListSource = source('mcp-server/src/lists/mutations/create.rs');

  assert.match(
    createListSource,
    /struct CreateListMutation\b/,
    'create_list should describe list insertion as a Mutation descriptor',
  );
  assert.match(
    createListSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateListMutation/,
    'create_list descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    createListSource,
    /\bexecute_mcp_mutation\(/,
    'create_list should use the MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    createListSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'create_list should let the executor own HLC minting and audit logging',
  );
});

test('list delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deleteListSource = source('mcp-server/src/lists/mutations/delete/mod.rs');
  const mcpExecutor = readRustSources('mcp-server/src/runtime/change_tracking/mutation_executor');

  assert.match(
    mcpExecutor,
    /pub\(crate\) fn execute_mcp_mutation_with_undo_tombstone_audit_finalizer\b/,
    'MCP mutation executor should provide a delete adapter that preserves tombstone payloads and undo bundles',
  );
  assert.match(
    deleteListSource,
    /struct DeleteListMutation\b/,
    'delete_list should describe the list deletion as a Mutation descriptor',
  );
  assert.match(
    deleteListSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteListMutation/,
    'delete_list descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deleteListSource,
    /\bexecute_mcp_mutation_with_undo_tombstone_audit_finalizer\(/,
    'delete_list should use the MCP mutation executor adapter for undoable tombstone deletes',
  );
  assert.doesNotMatch(
    deleteListSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'delete_list should let the executor own HLC minting and audit logging',
  );
});

test('task reminder add write uses Mutation executor instead of open-coded HLC and audit', () => {
  const addReminderSource = source('mcp-server/src/tasks/lifecycle/writes/add_reminder.rs');

  assert.match(
    addReminderSource,
    /struct AddTaskReminderMutation\b/,
    'add_task_reminder should describe the insert as a Mutation descriptor',
  );
  assert.match(
    addReminderSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddTaskReminderMutation/,
    'add_task_reminder descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    addReminderSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'add_task_reminder should use the MCP mutation executor audit finalizer so reminder relation sync stays attached',
  );
  assert.doesNotMatch(
    addReminderSource,
    /\bgenerate_hlc_version\b/,
    'add_task_reminder should mint reminder row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    addReminderSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'add_task_reminder should let the executor finalizer own audit logging',
  );
});

test('task update write uses Mutation executor instead of open-coded HLC and audit', () => {
  const updateTaskSource = source('mcp-server/src/tasks/mutations/update/mod.rs');

  assert.match(
    updateTaskSource,
    /struct UpdateTaskMutation\b/,
    'update_task should describe the task patch as a Mutation descriptor',
  );
  assert.match(
    updateTaskSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UpdateTaskMutation/,
    'update_task descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    updateTaskSource,
    /\bexecute_mcp_mutation(?:_map_store_error|_with_audit_finalizer)?\(/,
    'update_task should use an MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    updateTaskSource,
    /\bgenerate_hlc_version\b/,
    'update_task should mint task row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    updateTaskSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'update_task should let the executor finalizer own audit logging',
  );
});

test('task update dependency and tag side effects reuse the executor HLC session', () => {
  const dependenciesSource = source('mcp-server/src/tasks/dependencies.rs');
  const tagsSource = source('mcp-server/src/tasks/tags.rs');
  const postUpdateSource = source('mcp-server/src/tasks/mutations/update/mod.rs');

  assert.match(
    postUpdateSource,
    /\bflush_task_update_effects\(/,
    'update_task dependency side effects should flush from the canonical workflow outcome',
  );
  assert.match(
    postUpdateSource,
    /\bsync_effects\b/,
    'update_task tag side effects should flush from the canonical workflow outcome',
  );
  assert.match(
    postUpdateSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'update_task status lifecycle side effects should stay attached to the mutation finalizer',
  );
  assert.doesNotMatch(
    `${dependenciesSource}\n${tagsSource}\n${source('mcp-server/src/tasks/lifecycle/effects.rs')}`,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b/,
    'dependency, tag, and lifecycle status side effects should not open their own HLC sessions under update_task',
  );
});

test('task reminder replacement write uses Mutation executor instead of open-coded HLC and audit', () => {
  const setRemindersSource = source('mcp-server/src/tasks/lifecycle/writes/set_reminders.rs');

  assert.match(
    setRemindersSource,
    /struct SetTaskRemindersMutation\b/,
    'set_task_reminders should describe reminder replacement as a Mutation descriptor',
  );
  assert.match(
    setRemindersSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+SetTaskRemindersMutation/,
    'set_task_reminders descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    setRemindersSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'set_task_reminders should use the MCP mutation executor audit finalizer for reminder relation sync',
  );
  assert.doesNotMatch(
    setRemindersSource,
    /\bgenerate_hlc_version\b/,
    'set_task_reminders should mint reminder row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    setRemindersSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'set_task_reminders should let the executor finalizer own parent audit logging',
  );
});

test('task reminder removal write uses Mutation executor instead of open-coded HLC and audit', () => {
  const removeReminderSource = source('mcp-server/src/tasks/lifecycle/writes/remove_reminder.rs');

  assert.match(
    removeReminderSource,
    /struct RemoveTaskReminderMutation\b/,
    'remove_task_reminder should describe parent touch plus child delete as a Mutation descriptor',
  );
  assert.match(
    removeReminderSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RemoveTaskReminderMutation/,
    'remove_task_reminder descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    removeReminderSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'remove_task_reminder should use the MCP mutation executor audit finalizer for reminder tombstone sync',
  );
  assert.doesNotMatch(
    removeReminderSource,
    /\bgenerate_hlc_version\b/,
    'remove_task_reminder should mint the parent task version through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    removeReminderSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'remove_task_reminder should let the executor finalizer own parent audit logging',
  );
});

test('task checklist writes use Mutation executor instead of open-coded HLC and audit', () => {
  const checklistSource = source('mcp-server/src/tasks/lifecycle/writes/checklist.rs');

  assert.match(
    checklistSource,
    /enum TaskChecklistMutation\b/,
    'task checklist handlers should describe checklist writes as Mutation descriptors',
  );
  assert.match(
    checklistSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+TaskChecklistMutation/,
    'task checklist descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    checklistSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'task checklist handlers should use the MCP mutation executor audit finalizer for item relation sync',
  );
  assert.doesNotMatch(
    checklistSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'task checklist writes should mint task and item row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    checklistSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'task checklist writes should let the executor finalizer own parent audit logging',
  );
});

test('task defer write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deferSource = source('mcp-server/src/tasks/lifecycle/writes/defer.rs');

  assert.match(
    deferSource,
    /struct DeferTaskMutation\b/,
    'defer_task should describe the deferral patch as a Mutation descriptor',
  );
  assert.match(
    deferSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeferTaskMutation/,
    'defer_task descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deferSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'defer_task should use the MCP mutation executor audit finalizer for shifted reminder sync',
  );
  assert.doesNotMatch(
    deferSource,
    /\bgenerate_hlc_version\b/,
    'defer_task should mint task and shifted-reminder row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    deferSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'defer_task should let the executor finalizer own parent audit logging',
  );
});

test('task complete write uses Mutation executor instead of open-coded audit', () => {
  const completeSource = source('mcp-server/src/tasks/lifecycle/writes/complete.rs');

  assert.match(
    completeSource,
    /struct CompleteTaskMutation\b/,
    'complete_task should describe the lifecycle completion as a Mutation descriptor',
  );
  assert.match(
    completeSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CompleteTaskMutation/,
    'complete_task descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    completeSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'complete_task should use the MCP mutation executor audit finalizer so lifecycle sync fan-out stays attached',
  );
  assert.doesNotMatch(
    completeSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'complete_task should let the executor finalizer own parent audit logging',
  );
});

test('task cancel and reopen writes use Mutation executor instead of open-coded HLC and audit', () => {
  const cancelSource = source('mcp-server/src/tasks/lifecycle/writes/cancel.rs');
  const reopenSource = source('mcp-server/src/tasks/lifecycle/writes/reopen.rs');
  const combined = `${cancelSource}\n${reopenSource}`;

  assert.match(
    cancelSource,
    /struct CancelTaskMutation\b/,
    'cancel_task should describe the lifecycle cancellation as a Mutation descriptor',
  );
  assert.match(
    reopenSource,
    /struct ReopenTaskMutation\b/,
    'reopen_task should describe the lifecycle reopen as a Mutation descriptor',
  );
  assert.match(
    combined,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CancelTaskMutation/,
    'cancel_task descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    combined,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+ReopenTaskMutation/,
    'reopen_task descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...combined.matchAll(/\bexecute_mcp_mutation_with_audit_finalizer\(/g)].length,
    2,
    'cancel_task and reopen_task should each use the MCP mutation executor audit finalizer for lifecycle sync fan-out',
  );
  assert.doesNotMatch(
    combined,
    /\bgenerate_hlc_version\b/,
    'cancel_task and reopen_task should mint lifecycle row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    combined,
    /\blog_change\b|\bLogChangeParams\b/,
    'cancel_task and reopen_task should let the executor finalizer own parent audit logging',
  );
});

test('task batch move write uses Mutation executor instead of open-coded HLC and audit', () => {
  const batchMoveSource = source('mcp-server/src/tasks/batch/move_tasks.rs');

  assert.match(
    batchMoveSource,
    /struct BatchMoveTasksMutation\b/,
    'batch_move_tasks should describe moved task rows as a Mutation descriptor',
  );
  assert.match(
    batchMoveSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchMoveTasksMutation/,
    'batch_move_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchMoveSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_move_tasks should use the MCP batch mutation executor audit finalizer for entity_ids audit',
  );
  assert.doesNotMatch(
    batchMoveSource,
    /\bgenerate_hlc_version\b/,
    'batch_move_tasks should mint per-task row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchMoveSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_move_tasks should let the executor finalizer own batch audit logging',
  );
});

test('task batch reopen write uses Mutation executor instead of open-coded HLC and audit', () => {
  const batchReopenSource = source('mcp-server/src/tasks/batch/reopen.rs');

  assert.match(
    batchReopenSource,
    /struct BatchReopenTasksMutation\b/,
    'batch_reopen_tasks should describe reopened task rows as a Mutation descriptor',
  );
  assert.match(
    batchReopenSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchReopenTasksMutation/,
    'batch_reopen_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchReopenSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_reopen_tasks should use the MCP batch mutation executor audit finalizer for entity_ids audit',
  );
  assert.doesNotMatch(
    batchReopenSource,
    /\bgenerate_hlc_version\b/,
    'batch_reopen_tasks should mint lifecycle row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchReopenSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_reopen_tasks should let the executor finalizer own batch audit logging',
  );
});

test('task batch complete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const batchCompleteSource = source('mcp-server/src/tasks/batch/complete.rs');

  assert.match(
    batchCompleteSource,
    /struct BatchCompleteTasksMutation\b/,
    'batch_complete_tasks should describe completed task rows as a Mutation descriptor',
  );
  assert.match(
    batchCompleteSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCompleteTasksMutation/,
    'batch_complete_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchCompleteSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_complete_tasks should use the MCP batch mutation executor audit finalizer for entity_ids audit',
  );
  assert.doesNotMatch(
    batchCompleteSource,
    /\bgenerate_hlc_version\b/,
    'batch_complete_tasks should mint lifecycle row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchCompleteSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_complete_tasks should let the executor finalizer own batch audit logging',
  );
});

test('task batch defer write uses Mutation executor instead of open-coded HLC and audit', () => {
  const batchDeferSource = source('mcp-server/src/tasks/batch/defer/mod.rs');

  assert.match(
    batchDeferSource,
    /struct BatchDeferTasksMutation\b/,
    'batch_defer_tasks should describe deferred task rows as a Mutation descriptor',
  );
  assert.match(
    batchDeferSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchDeferTasksMutation/,
    'batch_defer_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchDeferSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_defer_tasks should use the MCP batch mutation executor audit finalizer for entity_ids audit',
  );
  assert.doesNotMatch(
    batchDeferSource,
    /\bgenerate_hlc_version\b/,
    'batch_defer_tasks should mint task and shifted-reminder row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchDeferSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_defer_tasks should let the executor finalizer own batch audit logging',
  );
});

test('task batch update write uses Mutation executor instead of open-coded HLC and parent audit', () => {
  const batchUpdateSource = source('mcp-server/src/tasks/batch/update/mod.rs');

  assert.match(
    batchUpdateSource,
    /struct BatchUpdateTasksMutation\b/,
    'batch_update_tasks should describe updated task rows as a Mutation descriptor',
  );
  assert.match(
    batchUpdateSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchUpdateTasksMutation/,
    'batch_update_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchUpdateSource,
    /\bexecute_mcp_batch_mutation_with_undo_audit_finalizer\(/,
    'batch_update_tasks should use the MCP batch mutation executor audit finalizer with undo bundle support',
  );
  assert.doesNotMatch(
    batchUpdateSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'batch_update_tasks should mint task and child row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchUpdateSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_update_tasks should let the executor own the parent batch audit row',
  );
});

test('task batch cancel by ids write uses Mutation executor instead of open-coded HLC and audit', () => {
  const batchCancelSource = source('mcp-server/src/tasks/batch/cancel_by_ids/mod.rs');

  assert.match(
    batchCancelSource,
    /struct BatchCancelTasksMutation\b/,
    'batch_cancel_tasks should describe cancelled task rows as a Mutation descriptor',
  );
  assert.match(
    batchCancelSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCancelTasksMutation/,
    'batch_cancel_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchCancelSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_cancel_tasks should use the MCP batch mutation executor audit finalizer for entity_ids audit',
  );
  assert.doesNotMatch(
    batchCancelSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b/,
    'batch_cancel_tasks should mint lifecycle row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchCancelSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_cancel_tasks should let the executor finalizer own batch audit logging',
  );
});

test('task batch cancel in list write uses Mutation executor instead of open-coded HLC in handler', () => {
  const batchCancelInListSource = source('mcp-server/src/tasks/batch/cancel/mod.rs');

  assert.match(
    batchCancelInListSource,
    /struct BatchCancelTasksInListMutation\b/,
    'batch_cancel_tasks_in_list should describe the in-list cancellation as a Mutation descriptor',
  );
  assert.match(
    batchCancelInListSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCancelTasksInListMutation/,
    'batch_cancel_tasks_in_list descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchCancelInListSource,
    /\bexecute_mcp_mutation_with_finalizer\(/,
    'batch_cancel_tasks_in_list should use the MCP mutation executor while preserving conditional no-op audit behavior',
  );
  assert.doesNotMatch(
    batchCancelInListSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'batch_cancel_tasks_in_list should mint lifecycle row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchCancelInListSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_cancel_tasks_in_list handler should keep supplemental audit logging outside the orchestration path',
  );
});

test('task recurrence writes use Mutation executor instead of open-coded HLC and audit', () => {
  const recurrenceSource = source('mcp-server/src/tasks/lifecycle/recurrence/mod.rs');

  assert.match(
    recurrenceSource,
    /struct SetTaskRecurrenceMutation\b/,
    'set_recurrence should describe recurrence replacement as a Mutation descriptor',
  );
  assert.match(
    recurrenceSource,
    /struct AddTaskRecurrenceExceptionMutation\b/,
    'add_task_recurrence_exception should describe exception insertion as a Mutation descriptor',
  );
  assert.match(
    recurrenceSource,
    /struct RemoveTaskRecurrenceExceptionMutation\b/,
    'remove_task_recurrence_exception should describe exception removal as a Mutation descriptor',
  );
  assert.match(
    recurrenceSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+SetTaskRecurrenceMutation/,
    'set_recurrence descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    recurrenceSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddTaskRecurrenceExceptionMutation/,
    'add_task_recurrence_exception descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    recurrenceSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RemoveTaskRecurrenceExceptionMutation/,
    'remove_task_recurrence_exception descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...recurrenceSource.matchAll(/\bexecute_mcp_mutation\(/g)].length,
    3,
    'task recurrence handlers should each call the MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    recurrenceSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b/,
    'task recurrence writes should mint task row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    recurrenceSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'task recurrence writes should let the executor own audit logging',
  );
});

test('calendar event exception writes use Mutation executor instead of open-coded HLC and audit', () => {
  const exceptionSource = source('mcp-server/src/calendar/exceptions.rs');

  assert.match(
    exceptionSource,
    /struct AddEventExceptionMutation\b/,
    'add_event_exception should describe exception insertion as a Mutation descriptor',
  );
  assert.match(
    exceptionSource,
    /struct RemoveEventExceptionMutation\b/,
    'remove_event_exception should describe exception removal as a Mutation descriptor',
  );
  assert.match(
    exceptionSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddEventExceptionMutation/,
    'add_event_exception descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    exceptionSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RemoveEventExceptionMutation/,
    'remove_event_exception descriptor should implement the workflow Mutation trait',
  );
  assert.equal(
    [...exceptionSource.matchAll(/\bexecute_mcp_mutation\(/g)].length,
    2,
    'event exception handlers should each call the MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    exceptionSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b/,
    'event exception writes should mint calendar row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    exceptionSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'event exception writes should let the executor own audit logging',
  );
});

test('CLI calendar event exception writes use Mutation executor instead of open-coded HLC and audit', () => {
  const exceptionSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/exceptions.rs');

  assert.match(
    exceptionSource,
    /struct AddCliCalendarEventExceptionMutation\b/,
    'CLI add_calendar_event_exception should describe exception insertion as a Mutation descriptor',
  );
  assert.match(
    exceptionSource,
    /struct RemoveCliCalendarEventExceptionMutation\b/,
    'CLI remove_calendar_event_exception should describe exception removal as a Mutation descriptor',
  );
  assert.match(
    exceptionSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+AddCliCalendarEventExceptionMutation/,
    'CLI add_calendar_event_exception descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    exceptionSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RemoveCliCalendarEventExceptionMutation/,
    'CLI remove_calendar_event_exception descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    exceptionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI calendar event exception writes should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    exceptionSource,
    /\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI calendar event exception writes should let the executor own HLC minting and audit logging',
  );
});

test('CLI calendar provider event link writes use Mutation executor instead of open-coded audit', () => {
  const providerLinkSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/provider_links.rs');

  assert.match(
    providerLinkSource,
    /struct LinkCliTaskProviderEventMutation\b/,
    'CLI provider event link should describe the upsert as a Mutation descriptor',
  );
  assert.match(
    providerLinkSource,
    /struct UnlinkCliTaskProviderEventMutation\b/,
    'CLI provider event unlink should describe the delete as a Mutation descriptor',
  );
  assert.match(
    providerLinkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+LinkCliTaskProviderEventMutation/,
    'CLI provider event link descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    providerLinkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UnlinkCliTaskProviderEventMutation/,
    'CLI provider event unlink descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    providerLinkSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI provider event link helper should call the CLI mutation executor adapter',
  );
  assert.match(
    providerLinkSource,
    /\nfn execute_provider_event_link_mutation\b/,
    'CLI provider event link writes should route through one local finalizer helper',
  );
  assert.equal(
    [...providerLinkSource.matchAll(/\bexecute_provider_event_link_mutation\(/g)].length,
    2,
    'CLI provider event link and unlink handlers should both use the local finalizer helper',
  );
  assert.doesNotMatch(
    providerLinkSource,
    /\blog_cli_changelog\(/,
    'CLI provider event link writes should let the executor finalizer own audit logging',
  );
});

test('calendar event update write uses Mutation executor instead of open-coded HLC and audit', () => {
  const updateSource = source('mcp-server/src/calendar/mutations/update/mod.rs');
  const functionSource = functionSlice(
    updateSource,
    /\npub\(crate\) fn update_calendar_event\b/,
    /\n#\[cfg\(test\)\]/,
  );

  assert.match(
    updateSource,
    /\bUpdateCalendarEventMutation\b/,
    'update_calendar_event should route event patching through a Mutation descriptor',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation\(/,
    'update_calendar_event should use the MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    functionSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'update_calendar_event should let the executor own HLC minting and audit logging',
  );
});

test('CLI calendar event update write uses Mutation executor instead of open-coded HLC and audit', () => {
  const updateSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/update.rs');

  assert.match(
    updateSource,
    /\bUpdateCalendarEventMutation\b/,
    'CLI update_calendar_event should route event patching through a Mutation descriptor',
  );
  assert.match(
    updateSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI update_calendar_event should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    updateSource,
    /\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI update_calendar_event should let the executor own HLC minting and audit logging',
  );
});

test('calendar event delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deleteSource = source('mcp-server/src/calendar/mutations/delete.rs');
  const functionSource = functionSlice(
    deleteSource,
    /\npub\(crate\) fn delete_calendar_event\b/,
    /$/,
  );

  assert.match(
    deleteSource,
    /struct DeleteCalendarEventMutation\b/,
    'delete_calendar_event should describe event deletion as a Mutation descriptor',
  );
  assert.match(
    deleteSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCalendarEventMutation/,
    'calendar event delete descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation_with_tombstone_audit_finalizer\(/,
    'delete_calendar_event should use the tombstone-aware MCP mutation executor adapter',
  );
  assert.doesNotMatch(
    functionSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'delete_calendar_event should let the executor own HLC minting and parent audit logging',
  );
});

test('CLI calendar event delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deleteSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/delete.rs');
  const functionSource = functionSlice(
    deleteSource,
    /\npub\(crate\) fn delete_calendar_event_with_conn\b/,
    /$/,
  );

  assert.match(
    deleteSource,
    /struct DeleteCliCalendarEventMutation\b/,
    'CLI delete_calendar_event should describe event deletion as a Mutation descriptor',
  );
  assert.match(
    deleteSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteCliCalendarEventMutation/,
    'CLI calendar event delete descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    functionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI delete_calendar_event should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    functionSource,
    /\bnext_hlc_version\b|\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI delete_calendar_event should let the executor own HLC minting and audit logging',
  );
});

test('calendar event create writes use Mutation executor instead of open-coded HLC and audit', () => {
  const createSource = source('mcp-server/src/calendar/mutations/create.rs');
  const singleCreateSource = functionSlice(
    createSource,
    /\npub\(crate\) fn create_calendar_event\b/,
    /\npub\(crate\) fn batch_create_calendar_events\b/,
  );
  const batchCreateSource = functionSlice(
    createSource,
    /\npub\(crate\) fn batch_create_calendar_events\b/,
    /$/,
  );

  assert.match(
    createSource,
    /\bCreateCalendarEventMutation\b/,
    'create_calendar_event should route event insertion through a Mutation descriptor',
  );
  assert.match(
    createSource,
    /struct BatchCreateCalendarEventsMutation\b/,
    'batch_create_calendar_events should describe event insertion as a Mutation descriptor',
  );
  assert.match(
    createSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCreateCalendarEventsMutation/,
    'calendar event batch create descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    singleCreateSource,
    /\bexecute_mcp_mutation\(/,
    'create_calendar_event should use the MCP mutation executor adapter',
  );
  assert.match(
    batchCreateSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'batch_create_calendar_events should use the MCP mutation executor batch audit adapter',
  );
  for (const [name, body] of [
    ['create_calendar_event', singleCreateSource],
    ['batch_create_calendar_events', batchCreateSource],
  ]) {
    assert.doesNotMatch(
      body,
      /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
      `${name} should let the executor own HLC minting and audit logging`,
    );
  }
});

test('CLI calendar event create write uses Mutation executor instead of open-coded HLC and audit', () => {
  const createSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/create.rs');
  const singleCreateSource = functionSlice(
    createSource,
    /\npub\(crate\) fn create_calendar_event_with_conn\b/,
    /\npub\(crate\) fn create_calendar_events_with_conn\b/,
  );

  assert.match(
    createSource,
    /\bCreateCalendarEventMutation\b/,
    'CLI create_calendar_event should route event creation through a Mutation descriptor',
  );
  assert.match(
    singleCreateSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI create_calendar_event should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    singleCreateSource,
    /\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI create_calendar_event should let the executor own HLC minting and audit logging',
  );
});

test('CLI calendar event batch create write uses Mutation executor instead of open-coded HLC and audit', () => {
  const createSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/create.rs');
  const batchCreateSource = functionSlice(
    createSource,
    /\npub\(crate\) fn create_calendar_events_with_conn\b/,
    /$/,
  );

  assert.match(
    createSource,
    /struct BatchCreateCliCalendarEventsMutation\b/,
    'CLI batch create_calendar_events should describe event creation as a Mutation descriptor',
  );
  assert.match(
    createSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCreateCliCalendarEventsMutation/,
    'CLI calendar event batch create descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchCreateSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI batch create_calendar_events should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    batchCreateSource,
    /\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI batch create_calendar_events should let the executor own HLC minting and audit logging',
  );
});

test('CLI task calendar event link writes use Mutation executor instead of open-coded HLC and audit', () => {
  const linkSource = source('lorvex-cli/src/commands/mutate/calendar/effects/mutations/links.rs');
  const linkTasksSource = functionSlice(
    linkSource,
    /\npub\(crate\) fn link_tasks_to_calendar_event_with_conn\b/,
    /\npub\(crate\) fn unlink_task_from_calendar_event_with_conn\b/,
  );
  const unlinkSource = functionSlice(
    linkSource,
    /\npub\(crate\) fn unlink_task_from_calendar_event_with_conn\b/,
    /$/,
  );

  assert.match(
    linkSource,
    /struct LinkCliTasksToCalendarEventMutation\b/,
    'CLI link_tasks_to_calendar_event should describe edge upserts as a Mutation descriptor',
  );
  assert.match(
    linkSource,
    /struct UnlinkCliTaskFromCalendarEventMutation\b/,
    'CLI unlink_task_from_calendar_event should describe edge deletion as a Mutation descriptor',
  );
  assert.match(
    linkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+LinkCliTasksToCalendarEventMutation/,
    'CLI task-calendar link descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    linkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UnlinkCliTaskFromCalendarEventMutation/,
    'CLI task-calendar unlink descriptor should implement the workflow Mutation trait',
  );
  for (const [name, body] of [
    ['link_tasks_to_calendar_event_with_conn', linkTasksSource],
    ['unlink_task_from_calendar_event_with_conn', unlinkSource],
  ]) {
    assert.match(
      body,
      /\bexecute_cli_mutation_with_finalizer\(/,
      `${name} should use the shared CLI mutation executor adapter`,
    );
    assert.doesNotMatch(
      body,
      /\bwith_hlc_state\b|\blog_cli_changelog\(/,
      `${name} should let the executor own HLC minting and audit logging`,
    );
  }
});

test('provider event link writes use Mutation executor instead of open-coded audit', () => {
  const providerLinkSource = source('mcp-server/src/calendar/provider_event_links/mod.rs');
  const linkSource = functionSlice(
    providerLinkSource,
    /\npub\(crate\) fn link_task_to_provider_event\b/,
    /\npub\(crate\) fn unlink_task_from_provider_event\b/,
  );
  const unlinkSource = functionSlice(
    providerLinkSource,
    /\npub\(crate\) fn unlink_task_from_provider_event\b/,
    /\npub\(crate\) fn get_provider_event_links_for_task\b/,
  );

  assert.match(
    providerLinkSource,
    /struct LinkTaskToProviderEventMutation\b/,
    'link_task_to_provider_event should describe provider link upsert as a Mutation descriptor',
  );
  assert.match(
    providerLinkSource,
    /struct UnlinkTaskFromProviderEventMutation\b/,
    'unlink_task_from_provider_event should describe provider link deletion as a Mutation descriptor',
  );
  assert.match(
    providerLinkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+LinkTaskToProviderEventMutation/,
    'provider link upsert descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    providerLinkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UnlinkTaskFromProviderEventMutation/,
    'provider link deletion descriptor should implement the workflow Mutation trait',
  );
  for (const [name, body] of [
    ['link_task_to_provider_event', linkSource],
    ['unlink_task_from_provider_event', unlinkSource],
  ]) {
    assert.match(
      body,
      /\bexecute_mcp_mutation_with_audit_finalizer\(/,
      `${name} should use the MCP mutation executor audit adapter`,
    );
    assert.doesNotMatch(
      body,
      /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
      `${name} should let the executor own audit logging`,
    );
  }
});

test('task calendar event link writes use Mutation executor instead of open-coded HLC and audit', () => {
  const linkSource = source('mcp-server/src/calendar/task_calendar_event_links/mod.rs');
  const singleLinkSource = functionSlice(
    linkSource,
    /\npub\(crate\) fn link_task_to_event\b/,
    /\npub\(crate\) fn unlink_task_from_event\b/,
  );
  const singleUnlinkSource = functionSlice(
    linkSource,
    /\npub\(crate\) fn unlink_task_from_event\b/,
    /\npub\(crate\) fn get_linked_events_for_task\b/,
  );
  const batchLinkSource = functionSlice(
    linkSource,
    /\npub\(crate\) fn batch_link_tasks_to_event\b/,
    /\n#\[cfg\(test\)\]/,
  );

  assert.match(
    linkSource,
    /struct LinkTaskToEventMutation\b/,
    'link_task_to_event should describe edge upsert as a Mutation descriptor',
  );
  assert.match(
    linkSource,
    /struct UnlinkTaskFromEventMutation\b/,
    'unlink_task_from_event should describe edge deletion as a Mutation descriptor',
  );
  assert.match(
    linkSource,
    /struct BatchLinkTasksToEventMutation\b/,
    'batch_link_tasks_to_event should describe edge upserts as a Mutation descriptor',
  );
  assert.match(
    linkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+LinkTaskToEventMutation/,
    'task-calendar link upsert descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    linkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UnlinkTaskFromEventMutation/,
    'task-calendar link deletion descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    linkSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchLinkTasksToEventMutation/,
    'task-calendar batch link descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    singleLinkSource,
    /\bexecute_mcp_mutation_with_skippable_audit_finalizer\(/,
    'link_task_to_event should use the MCP mutation executor audit adapter while preserving no-op audit skipping',
  );
  assert.match(
    singleUnlinkSource,
    /\bexecute_mcp_mutation_with_tombstone_audit_finalizer\(/,
    'unlink_task_from_event should use the MCP mutation executor tombstone adapter',
  );
  assert.match(
    batchLinkSource,
    /\bexecute_mcp_mutation_with_audit_entries_finalizer\(/,
    'batch_link_tasks_to_event should use the MCP mutation executor multi-entry audit adapter',
  );
  for (const [name, body] of [
    ['link_task_to_event', singleLinkSource],
    ['unlink_task_from_event', singleUnlinkSource],
    ['batch_link_tasks_to_event', batchLinkSource],
  ]) {
    assert.doesNotMatch(
      body,
      /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
      `${name} should let the executor own HLC minting and audit logging`,
    );
  }
});

test('memory delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const deleteMemorySource = source('mcp-server/src/memory/delete.rs');

  assert.match(
    deleteMemorySource,
    /struct DeleteMemoryMutation\b/,
    'delete_memory should describe memory deletion as a Mutation descriptor',
  );
  assert.match(
    deleteMemorySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteMemoryMutation/,
    'delete_memory descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deleteMemorySource,
    /\bexecute_mcp_mutation_with_tombstone_audit_finalizer\(/,
    'delete_memory should use the MCP mutation executor tombstone adapter',
  );
  assert.doesNotMatch(
    deleteMemorySource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b/,
    'delete_memory should mint row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    deleteMemorySource,
    /\blog_change\b|\bLogChangeParams\b/,
    'delete_memory should let the executor own audit logging',
  );
});

test('memory restore write uses Mutation executor instead of open-coded HLC and audit', () => {
  const historySource = source('mcp-server/src/memory/history.rs');
  const restoreSource = functionSlice(
    historySource,
    /\npub\(crate\) fn restore_memory_revision\b/,
    /\n}\s*$/,
  );

  assert.match(
    historySource,
    /struct RestoreMemoryRevisionMutation\b/,
    'restore_memory_revision should describe memory restoration as a Mutation descriptor',
  );
  assert.match(
    historySource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RestoreMemoryRevisionMutation/,
    'restore_memory_revision descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    restoreSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'restore_memory_revision should use the MCP mutation executor audit adapter',
  );
  assert.doesNotMatch(
    restoreSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'restore_memory_revision should let the executor own HLC minting and parent audit logging',
  );
});

test('preference delete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const preferenceSource = source('mcp-server/src/preferences/storage.rs');
  const deletePreferenceSource = functionSlice(
    preferenceSource,
    /\npub\(crate\) fn delete_preference\b/,
    /\npub\(crate\) fn get_all_preferences\b/,
  );

  assert.match(
    preferenceSource,
    /struct DeletePreferenceMutation\b/,
    'delete_preference should describe preference deletion as a Mutation descriptor',
  );
  assert.match(
    preferenceSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeletePreferenceMutation/,
    'delete_preference descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    deletePreferenceSource,
    /\bexecute_mcp_mutation_with_undo_tombstone_audit_finalizer\(/,
    'delete_preference should use the MCP mutation executor adapter for undoable tombstone deletes',
  );
  assert.doesNotMatch(
    deletePreferenceSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'delete_preference should let the executor own HLC minting and audit logging',
  );
});

test('complete setup write uses Mutation executor instead of open-coded HLC and audit', () => {
  const setupSource = source('mcp-server/src/system/setup/mod.rs');
  const completeSetupSource = functionSlice(
    setupSource,
    /\npub\(crate\) fn complete_setup\b/,
    /\n}\s*\n\n#\[cfg\(test\)\]/,
  );

  assert.match(
    setupSource,
    /struct CompleteSetupMutation\b/,
    'complete_setup should describe setup preference writes as a Mutation descriptor',
  );
  assert.match(
    setupSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CompleteSetupMutation/,
    'complete_setup descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    completeSetupSource,
    /\bexecute_mcp_batch_mutation_with_audit_finalizer\(/,
    'complete_setup should use the MCP batch mutation executor audit adapter',
  );
  assert.doesNotMatch(
    completeSetupSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'complete_setup should let the executor own HLC minting and aggregate audit logging',
  );
});

test('habit create write uses Mutation executor instead of open-coded HLC and audit', () => {
  const habitsSource = source('mcp-server/src/habits/writes/create_update.rs');
  const createHabitSource = functionSlice(
    habitsSource,
    /\npub\(crate\) fn create_habit\b/,
    /\npub\(crate\) struct UpdateHabitParams\b/,
  );

  assert.match(
    habitsSource,
    /struct CreateHabitMutation\b/,
    'create_habit should describe habit insertion as a Mutation descriptor',
  );
  assert.match(
    habitsSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateHabitMutation/,
    'create_habit descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    createHabitSource,
    /\bexecute_mcp_mutation\(/,
    'create_habit should execute through the MCP mutation executor',
  );
  assert.doesNotMatch(
    createHabitSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'create_habit should let the executor own HLC minting and audit logging',
  );
});

test('habit update write uses Mutation executor instead of open-coded HLC and audit', () => {
  const habitsSource = source('mcp-server/src/habits/writes/create_update.rs');
  const updateHabitSource = functionSlice(
    habitsSource,
    /\npub\(crate\) fn update_habit\b/,
    /\n}\s*$/,
  );

  assert.match(
    habitsSource,
    /struct UpdateHabitMutation\b/,
    'update_habit should describe habit updates as a Mutation descriptor',
  );
  assert.match(
    habitsSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UpdateHabitMutation/,
    'update_habit descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    updateHabitSource,
    /\bexecute_mcp_mutation\(/,
    'update_habit should execute through the MCP mutation executor',
  );
  assert.doesNotMatch(
    updateHabitSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'update_habit should let the executor own HLC minting and audit logging',
  );
});

test('habit complete write uses Mutation executor instead of open-coded HLC and audit', () => {
  const completionsSource = source('mcp-server/src/habits/writes/completions.rs');
  const completeHabitSource = functionSlice(
    completionsSource,
    /\npub\(crate\) fn complete_habit\b/,
    /\npub\(crate\) fn uncomplete_habit\b/,
  );

  assert.match(
    completionsSource,
    /struct CompleteHabitMutation\b/,
    'complete_habit should describe completion upserts as a Mutation descriptor',
  );
  assert.match(
    completionsSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CompleteHabitMutation/,
    'complete_habit descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    completeHabitSource,
    /\bexecute_mcp_mutation\(/,
    'complete_habit should execute through the MCP mutation executor',
  );
  assert.doesNotMatch(
    completeHabitSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'complete_habit should let the executor own HLC minting and audit logging',
  );
});

test('habit uncomplete write uses Mutation executor instead of open-coded audit', () => {
  const completionsSource = source('mcp-server/src/habits/writes/completions.rs');
  const uncompleteHabitSource = functionSlice(
    completionsSource,
    /\npub\(crate\) fn uncomplete_habit\b/,
    /\npub\(crate\) fn batch_complete_habit\b/,
  );

  assert.match(
    completionsSource,
    /struct UncompleteHabitMutation\b/,
    'uncomplete_habit should describe completion deletes as a Mutation descriptor',
  );
  assert.match(
    completionsSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+UncompleteHabitMutation/,
    'uncomplete_habit descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    uncompleteHabitSource,
    /\bexecute_mcp_mutation\(/,
    'uncomplete_habit should execute through the MCP mutation executor',
  );
  assert.doesNotMatch(
    uncompleteHabitSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'uncomplete_habit should let the executor own audit logging',
  );
});

test('habit reminder policy writes use Mutation executor instead of open-coded HLC and audit', () => {
  const remindersSource = sources([
    'mcp-server/src/habits/reminders/mod.rs',
    'mcp-server/src/habits/reminders/upsert.rs',
    'mcp-server/src/habits/reminders/delete.rs',
  ]);
  const upsertSource = functionSlice(
    remindersSource,
    /\npub\(crate\) fn upsert_habit_reminder_policy\b/,
    /\npub\(crate\) fn delete_habit_reminder_policy\b/,
  );
  const deleteSource = functionSlice(
    remindersSource,
    /\npub\(crate\) fn delete_habit_reminder_policy\b/,
    /$/,
  );

  assert.match(
    remindersSource,
    /\bUpsertHabitReminderPolicyMutation\b/,
    'upsert_habit_reminder_policy should describe policy upserts as a Mutation descriptor',
  );
  assert.match(
    remindersSource,
    /\bDeleteHabitReminderPolicyMutation\b/,
    'delete_habit_reminder_policy should describe policy deletes as a Mutation descriptor',
  );
  assert.match(
    remindersSource,
    /\bexecute_mcp_mutation/,
    'habit reminder policy writes should use MCP mutation executor adapters',
  );
  assert.match(
    upsertSource,
    /\bexecute_mcp_mutation(?:_with_dynamic_audit_finalizer)?\(/,
    'upsert_habit_reminder_policy should execute through the MCP mutation executor',
  );
  assert.match(
    deleteSource,
    /\bexecute_mcp_mutation_with_tombstone_audit_finalizer\(/,
    'delete_habit_reminder_policy should execute through the tombstone-aware MCP mutation executor',
  );
  assert.doesNotMatch(
    upsertSource,
    /\bgenerate_hlc_version\b|\blog_change\b|\bLogChangeParams\b/,
    'upsert_habit_reminder_policy should let the executor own HLC minting and audit logging',
  );
  assert.doesNotMatch(
    deleteSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'delete_habit_reminder_policy should let the executor own audit logging',
  );
});

test('habit delete root write uses Mutation executor instead of open-coded HLC and parent audit', () => {
  const deleteSource = source('mcp-server/src/habits/writes/delete.rs');
  const functionSource = functionSlice(
    deleteSource,
    /\npub\(crate\) fn delete_habit\b/,
    /$/,
  );

  assert.match(
    deleteSource,
    /struct DeleteHabitMutation\b/,
    'delete_habit should describe the root habit delete as a Mutation descriptor',
  );
  assert.match(
    deleteSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+DeleteHabitMutation/,
    'delete_habit descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation_with_undo_tombstone_audit_finalizer\(/,
    'delete_habit should use the undo+tombstone MCP mutation executor adapter for the parent habit delete',
  );
  assert.doesNotMatch(
    functionSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'delete_habit should mint cascade tombstone and root delete versions through the executor-provided HLC session',
  );
});

test('set current focus uses Mutation executor instead of open-coded HLC and audit', () => {
  const focusSource = sources([
    'mcp-server/src/focus/current/writes/mod.rs',
    'mcp-server/src/focus/current/writes/set.rs',
    'mcp-server/src/focus/current/writes/add.rs',
    'mcp-server/src/focus/current/writes/clear.rs',
    'mcp-server/src/focus/current/writes/remove.rs',
  ]);
  const functionSource = functionSlice(
    focusSource,
    /\npub\(crate\) fn set_current_focus\b/,
    /\npub\(crate\) fn add_to_current_focus\b/,
  );

  assert.match(
    focusSource,
    /\bSetCurrentFocusMutation\b/,
    'set_current_focus should describe the aggregate write as a Mutation descriptor',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation\(/,
    'set_current_focus should use the MCP mutation executor for root audit/sync finalization',
  );
  assert.doesNotMatch(
    functionSource,
    /\bgenerate_hlc_version\b|\blog_change\(/,
    'set_current_focus should not mint HLC versions or write root audit rows directly',
  );
});

test('add to current focus uses Mutation executor instead of open-coded HLC and audit', () => {
  const focusSource = sources([
    'mcp-server/src/focus/current/writes/mod.rs',
    'mcp-server/src/focus/current/writes/set.rs',
    'mcp-server/src/focus/current/writes/add.rs',
    'mcp-server/src/focus/current/writes/clear.rs',
    'mcp-server/src/focus/current/writes/remove.rs',
  ]);
  const functionSource = functionSlice(
    focusSource,
    /\npub\(crate\) fn add_to_current_focus\b/,
    /\npub\(crate\) fn clear_current_focus\b/,
  );

  assert.match(
    focusSource,
    /\bAddToCurrentFocusMutation\b/,
    'add_to_current_focus should describe the aggregate write as a Mutation descriptor',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation\(/,
    'add_to_current_focus should use the MCP mutation executor for root audit/sync finalization',
  );
  assert.doesNotMatch(
    functionSource,
    /\bgenerate_hlc_version\b|\blog_change\(/,
    'add_to_current_focus should not mint HLC versions or write root audit rows directly',
  );
});

test('clear current focus uses Mutation executor instead of open-coded root audit', () => {
  const focusSource = sources([
    'mcp-server/src/focus/current/writes/mod.rs',
    'mcp-server/src/focus/current/writes/set.rs',
    'mcp-server/src/focus/current/writes/add.rs',
    'mcp-server/src/focus/current/writes/clear.rs',
    'mcp-server/src/focus/current/writes/remove.rs',
  ]);
  const functionSource = functionSlice(
    focusSource,
    /\npub\(crate\) fn clear_current_focus\b/,
    /\npub\(crate\) fn remove_from_current_focus\b/,
  );

  assert.match(
    focusSource,
    /\bClearCurrentFocusMutation\b/,
    'clear_current_focus should describe the aggregate delete as a Mutation descriptor',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation_with_finalizer\(/,
    'clear_current_focus should use an MCP mutation executor adapter for tombstone audit finalization',
  );
  assert.doesNotMatch(
    functionSource,
    /\blog_change\(/,
    'clear_current_focus should not write root audit rows directly in the handler body',
  );
});

test('remove from current focus uses Mutation executor instead of open-coded HLC and root audit', () => {
  const focusSource = sources([
    'mcp-server/src/focus/current/writes/mod.rs',
    'mcp-server/src/focus/current/writes/set.rs',
    'mcp-server/src/focus/current/writes/add.rs',
    'mcp-server/src/focus/current/writes/clear.rs',
    'mcp-server/src/focus/current/writes/remove.rs',
  ]);
  const functionSource = functionSlice(
    focusSource,
    /\npub\(crate\) fn remove_from_current_focus\b/,
    /$/,
  );

  assert.match(
    focusSource,
    /\bRemoveFromCurrentFocusMutation\b/,
    'remove_from_current_focus should describe update/delete outcomes as a Mutation descriptor',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation_with_finalizer\(/,
    'remove_from_current_focus should use an MCP mutation executor adapter for dynamic update/delete audit finalization',
  );
  assert.doesNotMatch(
    functionSource,
    /\bgenerate_hlc_version\b|\blog_change\(/,
    'remove_from_current_focus should not mint HLC versions or write root audit rows directly in the handler body',
  );
});

test('focus schedule save writes use Mutation executor instead of open-coded HLC and audit', () => {
  const scheduleSource = source('mcp-server/src/focus/schedule/save.rs');

  for (const descriptor of [
    'SaveFocusScheduleMutation',
    'ApplyScheduleToCurrentFocusMutation',
    'EnsureDashboardScheduleSectionMutation',
  ]) {
    assert.match(
      scheduleSource,
      new RegExp(`struct ${descriptor}\\b`),
      `${descriptor} should describe one save_focus_schedule write through Mutation`,
    );
    assert.match(
      scheduleSource,
      new RegExp(`impl(?:<[^>]+>)?\\s+Mutation\\s+for\\s+${descriptor}`),
      `${descriptor} should implement the workflow Mutation trait`,
    );
  }
  assert.match(
    scheduleSource,
    /\bexecute_mcp_mutation\(/,
    'save_focus_schedule write phases should use MCP mutation executor adapters',
  );
  assert.doesNotMatch(
    scheduleSource,
    /\bgenerate_hlc_version\b|\blog_change\(/,
    'focus schedule save should not mint HLC versions or write audit rows directly',
  );
});

test('rename tag write uses Mutation executor instead of open-coded HLC and audit', () => {
  const tagsSource = source('mcp-server/src/system/tags/mod.rs');
  const functionSource = functionSlice(
    tagsSource,
    /\npub\(crate\) fn rename_tag\b/,
    /\nstruct /,
  );

  assert.match(
    tagsSource,
    /struct RenameTagMutation\b/,
    'rename_tag should describe tag rename/merge fan-out as a Mutation descriptor',
  );
  assert.match(
    tagsSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RenameTagMutation/,
    'rename_tag descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    functionSource,
    /\bexecute_mcp_mutation_with_skip_sync_audit_finalizer\(/,
    'rename_tag should use an executor adapter that can audit without duplicating tag sync',
  );
  assert.doesNotMatch(
    tagsSource,
    /\bgenerate_hlc_version\b|\bwith_hlc_session\b|\blog_change\b|\bLogChangeParams\b/,
    'rename_tag should let the executor own HLC minting and audit logging',
  );
});

test('CLI rename tag write uses Mutation executor instead of open-coded HLC and audit', () => {
  const renameSource = source('lorvex-cli/src/commands/mutate/tags/effects/rename.rs');
  const functionSource = functionSlice(
    renameSource,
    /\npub\(crate\) fn rename_tag_with_conn\b/,
    /$/,
  );

  assert.match(
    renameSource,
    /struct RenameCliTagMutation\b/,
    'CLI rename_tag should describe tag rename/merge fan-out as a Mutation descriptor',
  );
  assert.match(
    renameSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+RenameCliTagMutation/,
    'CLI rename_tag descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    functionSource,
    /\bexecute_cli_mutation_with_finalizer\(/,
    'CLI rename_tag should use the shared CLI mutation executor adapter',
  );
  assert.doesNotMatch(
    functionSource,
    /\bwith_hlc_state\b|\blog_cli_changelog\(/,
    'CLI rename_tag should let the executor own HLC minting and audit logging',
  );
});

test('task create write uses Mutation executor instead of open-coded HLC and parent audit', () => {
  const createTaskSource = source('mcp-server/src/tasks/mutations/create/mod.rs');

  assert.match(
    createTaskSource,
    /struct CreateTaskMutation\b/,
    'create_task should describe task creation as a Mutation descriptor',
  );
  assert.match(
    createTaskSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+CreateTaskMutation/,
    'create_task descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    createTaskSource,
    /\bexecute_mcp_mutation_with_audit_finalizer\(/,
    'create_task should use the MCP mutation executor audit finalizer for create side effects',
  );
  assert.doesNotMatch(
    createTaskSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'create_task should mint task and child row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    createTaskSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'create_task should let the executor own the parent task audit row',
  );
});

test('task batch create write uses Mutation executor instead of open-coded HLC and parent audit', () => {
  const batchCreateSource = source('mcp-server/src/tasks/mutations/batch/mod.rs');
  const mcpExecutor = readRustSources('mcp-server/src/runtime/change_tracking/mutation_executor');

  assert.match(
    mcpExecutor,
    /pub\(crate\) fn execute_mcp_batch_mutation_with_undo_audit_finalizer\b/,
    'MCP mutation executor should provide a batch audit adapter that preserves undo bundles',
  );
  assert.match(
    batchCreateSource,
    /struct BatchCreateTasksMutation\b/,
    'batch_create_tasks should describe created task rows as a Mutation descriptor',
  );
  assert.match(
    batchCreateSource,
    /impl(?:<[^>]+>)?\s+Mutation\s+for\s+BatchCreateTasksMutation/,
    'batch_create_tasks descriptor should implement the workflow Mutation trait',
  );
  assert.match(
    batchCreateSource,
    /\bexecute_mcp_batch_mutation_with_undo_audit_finalizer\(/,
    'batch_create_tasks should use the MCP batch mutation executor audit finalizer with undo bundle support',
  );
  assert.doesNotMatch(
    batchCreateSource,
    /\bwith_hlc_session\b|\bgenerate_hlc_version\b/,
    'batch_create_tasks should mint task and child row versions through the executor-provided HLC session',
  );
  assert.doesNotMatch(
    batchCreateSource,
    /\blog_change\b|\bLogChangeParams\b/,
    'batch_create_tasks should let the executor own the parent batch audit row',
  );
});

test('task create migration does not leave orphaned legacy insert helpers', () => {
  const legacyPaths = [
    'mcp-server/src/tasks/mutations/shared.rs',
    'mcp-server/src/tasks/mutations/shared/draft.rs',
    'mcp-server/src/tasks/mutations/shared/prepared.rs',
  ];

  for (const relPath of legacyPaths) {
    assert.equal(
      fs.existsSync(path.join(repoRoot, relPath)),
      false,
      `${relPath} should be removed instead of retaining an uncompiled create-task path that can bypass the executor`,
    );
  }
});

test('daily review local writers fail closed on LWW no-op results before side effects', () => {
  const storeSource = source('lorvex-store/src/repositories/daily_review_ops/mod.rs');
  const mcpAddSource = source('mcp-server/src/reviews/daily/writes/add.rs');
  const mcpAmendSource = source('mcp-server/src/reviews/daily/writes/amend.rs');
  const cliSource = source('lorvex-cli/src/commands/mutate/reviews/effects/daily.rs');
  const tauriSource = source('app/src-tauri/src/commands/reviews.rs');
  const surfaceSources = `${mcpAddSource}\n${mcpAmendSource}\n${cliSource}\n${tauriSource}`;

  assert.match(
    storeSource,
    /pub fn require_daily_review_write_applied\b/,
    'daily review repository should expose one typed helper that maps stale bool results to StoreError::StaleVersion',
  );
  assert.equal(
    [...surfaceSources.matchAll(/\brequire_daily_review_write_applied\(/g)].length,
    6,
    'MCP add/amend, CLI add/amend, and both Tauri upsert flows should check the LWW bool result before child/outbox/audit side effects',
  );
  assert.match(
    storeSource,
    /StoreError::StaleVersion\s*\{\s*entity:\s*ENTITY_DAILY_REVIEW/s,
    'daily review stale helper should preserve typed StoreError::StaleVersion metadata',
  );
});

test('recurrence focus-plan rewire audit belongs to MCP lifecycle boundary, not workflow SQL', () => {
  const workflowRewireSource = source('lorvex-workflow/src/lifecycle/spawn_successor/rewire.rs');
  const workflowSpawnSource = source('lorvex-workflow/src/lifecycle/spawn_successor/mod.rs');
  const mcpLifecycleEffects = source('mcp-server/src/tasks/lifecycle/effects.rs');

  assert.doesNotMatch(
    workflowRewireSource,
    /INSERT INTO ai_changelog|insert_rewire_changelog/,
    'workflow focus-plan rewire should not insert ai_changelog rows directly',
  );
  assert.doesNotMatch(
    workflowSpawnSource,
    /insert_rewire_changelog/,
    'recurrence successor workflow should return rewire dates instead of owning audit writes',
  );
  assert.match(
    mcpLifecycleEffects,
    /recurrence_rewire/,
    'MCP lifecycle flush should own recurrence_rewire audit rows for AI/MCP-originated lifecycle writes',
  );
  assert.match(
    mcpLifecycleEffects,
    /\.skip_sync\(\)/,
    'MCP recurrence_rewire audit rows should skip duplicate aggregate sync because lifecycle flush already enqueues the aggregate upsert',
  );
});
