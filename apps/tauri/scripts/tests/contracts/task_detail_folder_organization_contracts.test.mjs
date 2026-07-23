import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import test from 'node:test';

import { readTypeScriptSources, repoRoot } from './shared.mjs';

test('TaskDetail is organized as a folder-backed subsystem with controller runtime modules, support, and content modules', () => {
  const rootSource = fs.readFileSync(path.join(repoRoot, 'app/src/components/TaskDetail.tsx'), 'utf8');
  const contentIndexSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/index.ts'),
    'utf8',
  );
  const contentSource = readTypeScriptSources(
    'app/src/components/task-detail/content/TaskDetailContent.tsx',
    'app/src/components/task-detail/content/detail-content',
  );
  const relationsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailRelations.tsx'),
    'utf8',
  );
  const relationActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/useTaskDetailRelationActions.ts'),
    'utf8',
  );
  const relationSearchSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/useTaskDetailRelationSearch.ts'),
    'utf8',
  );
  const relationComposerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/useTaskDetailRelationComposer.ts'),
    'utf8',
  );
  const relationSearchInputSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailRelationSearchInput.tsx'),
    'utf8',
  );
  const infoSectionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailInfoSections.tsx'),
    'utf8',
  );
  const eventLinksSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailEventLinks.tsx'),
    'utf8',
  );
  const eventLinkActionsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/useTaskDetailEventLinkActions.ts'),
    'utf8',
  );
  const eventLinkComposerSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/useTaskDetailEventLinkComposer.ts'),
    'utf8',
  );
  const eventLinkSearchInputSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailEventLinkSearchInput.tsx'),
    'utf8',
  );
  const stateViewsSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/content/TaskDetailStateViews.tsx'),
    'utf8',
  );
  const controllerSource = readTypeScriptSources(
    'app/src/components/task-detail/controller',
  );
  const controllerDir = path.join(repoRoot, 'app/src/components/task-detail/controller');
  const supportSource = fs.readFileSync(
    path.join(repoRoot, 'app/src/components/task-detail/support.ts'),
    'utf8',
  );

  assert.match(
    rootSource,
    /import \{ TaskDetailContent \} from '\.\/task-detail\/content';/,
    'TaskDetail root should render the folder-backed content module',
  );
  assert.match(
    rootSource,
    /useTaskDetailController\(/,
    'TaskDetail root should delegate task-detail orchestration to the dedicated controller',
  );
  assert.match(
    rootSource,
    /import \{ useTaskDetailController \} from '\.\/task-detail\/controller\/useTaskDetailController';/,
    'TaskDetail root should source controller orchestration from the named controller module',
  );
  assert.equal(
    fs.existsSync(path.join(controllerDir, 'index.ts')),
    false,
    'TaskDetail controller should not hide implementation behind an index.ts entrypoint',
  );
  assert.match(
    controllerSource,
    /export function useTaskDetailController\(\{/,
    'TaskDetail should keep controller composition in a dedicated controller root',
  );
  assert.match(
    controllerSource,
    /export function useTaskDetailQueries\(/,
    'TaskDetail task queries and dependency hydration should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function useTaskDetailDrafts\(/,
    'TaskDetail draft persistence should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /export function useTaskDetailMutations\(/,
    'TaskDetail mutations should live in a dedicated runtime module',
  );
  assert.match(
    controllerSource,
    /invalidateTaskDetailWriteQueries/,
    'TaskDetail query invalidation should use the shared invalidation helper from queryKeys',
  );
  assert.match(
    controllerSource,
    /export function useTaskDetailControllerState\(/,
    'TaskDetail derived presentation state should live in a dedicated controller runtime module',
  );
  assert.match(
    contentIndexSource,
    /export \{ default as TaskDetailContent \} from '\.\/TaskDetailContent';/,
    'task-detail/content should expose a barrel export for the content root',
  );
  assert.match(
    contentSource,
    /export default function TaskDetailContent/,
    'TaskDetail rendering should live in a dedicated content module',
  );
  assert.match(
    contentSource,
    /import \{ TaskDetailRelations \} from '\.\.\/TaskDetailRelations';/,
    'TaskDetail content subsystem should delegate dependency rendering to a focused content module',
  );
  assert.match(
    contentSource,
    /from '\.\.\/TaskDetailInfoSections'/,
    'TaskDetail content subsystem should delegate informational sections to a focused content module',
  );
  assert.match(
    contentSource,
    /import \{ TaskDetailErrorState, TaskDetailLoadingState \} from '\.\/TaskDetailStateViews';/,
    'TaskDetail content root should delegate loading and error shells to a focused content module',
  );
  assert.doesNotMatch(
    contentSource,
    /<DepLink|function TaskDetailLoadingState|function TaskDetailErrorState/,
    'TaskDetail content root should stay a composition boundary instead of re-growing local dependency or state-view implementations',
  );
  assert.match(
    contentSource,
    /controller\.handlePermanentDelete\(\)/,
    'TaskDetail content root should delegate permanent-delete to the controller handler instead of re-implementing it inline',
  );
  assert.match(
    relationsSource,
    /export function TaskDetailRelations/,
    'TaskDetail content should keep dependency sections in a dedicated relations module',
  );
  assert.match(
    relationsSource,
    /import \{ useTaskDetailRelationActions \} from '\.\/useTaskDetailRelationActions';/,
    'TaskDetail relations should delegate mutation ownership to a dedicated runtime hook',
  );
  assert.match(
    relationsSource,
    /import \{ useTaskDetailRelationComposer \} from '\.\/useTaskDetailRelationComposer';/,
    'TaskDetail relations should delegate add-mode orchestration to a dedicated runtime hook',
  );
  assert.match(
    relationsSource,
    /import \{ TaskDetailRelationSearchInput \} from '\.\/TaskDetailRelationSearchInput';/,
    'TaskDetail relations should delegate search presentation to a focused search-input module',
  );
  assert.doesNotMatch(
    relationsSource,
    /useQueryClient\(|searchTasks\(|getTask\(|updateTask\(|function TaskSearchInput|useTaskDetailRelationSearch\(/,
    'TaskDetail relations should not keep direct transport/search ownership, add-mode state, or inline search UI',
  );
  assert.match(
    relationActionsSource,
    /export function useTaskDetailRelationActions\(/,
    'TaskDetail relation mutations should live in a dedicated runtime hook',
  );
  assert.match(
    relationComposerSource,
    /export function useTaskDetailRelationComposer\(/,
    'TaskDetail relation add-mode orchestration should live in a dedicated runtime hook',
  );
  assert.match(
    relationSearchSource,
    /export function useTaskDetailRelationSearch\(/,
    'TaskDetail relation search should live in a dedicated runtime hook',
  );
  assert.match(
    relationSearchInputSource,
    /import \{ useTaskDetailRelationSearch \} from '\.\/useTaskDetailRelationSearch';/,
    'TaskDetail relation search input should delegate query ownership to the dedicated runtime hook',
  );
  assert.doesNotMatch(
    relationSearchInputSource,
    /searchTasks\(/,
    'TaskDetail relation search input should not query tasks directly once search ownership moves into the dedicated hook',
  );
  assert.match(
    infoSectionsSource,
    /export function TaskDetailAiNotes/,
    'TaskDetail content should keep info/history sections in a dedicated module',
  );
  assert.match(
    eventLinksSource,
    /import \{ useTaskDetailEventLinkActions \} from '\.\/useTaskDetailEventLinkActions';/,
    'TaskDetail event links should delegate mutations to a focused runtime hook',
  );
  assert.match(
    eventLinksSource,
    /import \{ useTaskDetailEventLinkComposer \} from '\.\/useTaskDetailEventLinkComposer';/,
    'TaskDetail event links should delegate add-mode orchestration to a dedicated runtime hook',
  );
  assert.match(
    eventLinksSource,
    /import \{ TaskDetailEventLinkSearchInput \} from '\.\/TaskDetailEventLinkSearchInput';/,
    'TaskDetail event links should delegate search presentation to a focused search-input module',
  );
  assert.doesNotMatch(
    eventLinksSource,
    /useMutation\(\{|function EventSearchInput|useTaskDetailEventLinkSearch\(|split\(':'\)/,
    'TaskDetail event links content should not keep inline mutation, provider-id parsing, or search ownership',
  );
  assert.match(
    eventLinkActionsSource,
    /export function useTaskDetailEventLinkActions\(/,
    'TaskDetail event link mutations should live in a dedicated runtime hook',
  );
  assert.match(
    eventLinkActionsSource,
    /useMutation\(\{/,
    'TaskDetail event link runtime hook should own mutation wiring',
  );
  assert.match(
    eventLinkComposerSource,
    /export function useTaskDetailEventLinkComposer\(/,
    'TaskDetail event-link add-mode orchestration should live in a dedicated runtime hook',
  );
  assert.match(
    eventLinkSearchInputSource,
    /import \{ useTaskDetailEventLinkSearch \} from '\.\/useTaskDetailEventLinkSearch';/,
    'TaskDetail event-link search input should delegate query ownership to the dedicated runtime hook',
  );
  assert.doesNotMatch(
    eventLinkSearchInputSource,
    /getCalendarEventsUnified\(/,
    'TaskDetail event-link search input should not query calendar events directly once search ownership moves into the dedicated hook',
  );
  assert.match(
    stateViewsSource,
    /export function TaskDetailLoadingState/,
    'TaskDetail content should keep loading state rendering in a dedicated state-view module',
  );
  assert.match(
    stateViewsSource,
    /export function TaskDetailErrorState/,
    'TaskDetail content should keep error state rendering in a dedicated state-view module',
  );
  assert.match(
    supportSource,
    /export function reportTaskDetailActionError\(/,
    'TaskDetail structured error logging should live in a dedicated support module',
  );
});
