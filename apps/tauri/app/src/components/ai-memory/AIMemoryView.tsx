import { useScrollRestore } from '@/lib/useScrollRestore';
import { formatPageTitle } from '@/lib/pageTitle';
import { PREF_MEMORY_LOCK_ENABLED } from '@/lib/preferences/keys';
import type { View } from '@/lib/types';
import AssistantNotConfiguredPanel from '../ui/AssistantNotConfiguredPanel';
import { SearchIcon, SparkleIcon, WarningIcon } from '../ui/icons';
import ModuleStatePanel from '../ui/ModuleStatePanel';
import { Tooltip } from '../ui/Tooltip';
import { Button } from '../ui/Button';
import { SearchInput } from '../ui/SearchInput';
import { MemoryLockedState } from './MemoryLockedState';
import { AIMemorySkeleton } from './AIMemorySkeleton';
import { AddMemoryForm } from './AddMemoryForm';
import { NotesForAiSection } from './NotesForAiSection';
import { MemoryEntryList } from './MemoryEntryList';
import { useAIMemoryViewController } from './useAIMemoryViewController';

interface AIMemoryViewProps {
  /**
   * forwarded from MainViewContent so the empty-state
   * "Connect your AI assistant" card can deep-link into Settings →
   * Assistant MCP when the MCP server status resolves to false.
   */
  onNavigate?: ((view: View) => void) | undefined;
}

/**
 * AI memory view shell. Renders the page chrome (header, locked
 * state, scroll container, loading/error/empty panels, notes-for-AI
 * section, add-memory form, structured-memory list) on top of the
 * data + interaction model owned by `useAIMemoryViewController`. All
 * non-render concerns — lock state machine, draft persistence, query
 * lifecycle, copy-all — live in the controller; this component is
 * a thin presentational shell.
 */
export default function AIMemoryView({ onNavigate }: AIMemoryViewProps = {}) {
  const c = useAIMemoryViewController();
  const scroll = useScrollRestore('ai-memory');

  return (
    <div className="h-full flex flex-col overflow-hidden" data-preference-key={PREF_MEMORY_LOCK_ENABLED}>
      <title>{formatPageTitle(c.t('nav.memory'))}</title>
      <header className="px-4 sm:px-8 pt-1.5 pb-5 shrink-0">
        <p className="text-text-muted text-xs font-medium mb-1">{c.t('nav.memory')}</p>
        <div className="flex items-baseline justify-between">
          <h2 className="text-text-primary text-2xl font-light">{c.t('memory.title')}</h2>
          <div className="flex items-center gap-3">
            {c.entries.length > 0 && !(c.lockEnabled && c.isLocked) && (
              <button
                type="button"
                onClick={() => { void c.handleCopyAll(); }}
                disabled={c.copying}
                className="text-text-muted text-xs hover:text-text-secondary transition-colors disabled:opacity-50 rounded-r-control focus-ring-soft"
              >
                {c.copying ? c.t('common.copying') : c.t('memory.copyAll')}
              </button>
            )}
            {/* "+ Add memory" opens an inline creation
                form so standalone users (no MCP assistant connected)
                can seed human-owned memory entries themselves. */}
            {!(c.lockEnabled && c.isLocked) && !c.addFormOpen && (
              <Tooltip label={c.t('memory.addMemoryTooltip')}>
                <Button variant="ghost" size="sm" onClick={c.openAddForm}>
                  + {c.t('memory.addMemory')}
                </Button>
              </Tooltip>
            )}
          </div>
        </div>
        <p className="text-text-muted text-xs mt-2">{c.t('memory.subtitle')}</p>
      </header>

      {c.lockEnabled && c.isLocked ? (
        <MemoryLockedState
          t={c.t}
          authError={c.authError}
          onUnlock={() => { void c.handleUnlock(); }}
        />
      ) : (
        <div ref={scroll.ref} onScroll={scroll.onScroll} className="flex-1 overflow-y-auto overscroll-contain px-4 sm:px-8 pb-8 space-y-6">
          {c.isLoading ? (
            <AIMemorySkeleton />
          ) : c.isError && c.entries.length === 0 ? (
            <ModuleStatePanel
              variant="error"
              icon={<WarningIcon className="w-9 h-9" />}
              title={c.t('common.error')}
              actionLabel={c.t('error.tryAgain')}
              onAction={() => { void c.refetch(); }}
            />
          ) : (
            <>
              {/* Section 1: Your Notes for AI */}
              <NotesForAiSection
                entry={c.notesForAi}
                locale={c.locale}
                timezone={c.timezone}
                t={c.t}
                onMutate={c.invalidateMemory}
              />

              {/* inline "Add memory" form for standalone
                  users. Rendered above the memory list because it
                  produces rows that appear in that list, so the
                  intent → form → new row flow stays visible end to end. */}
              {c.addFormOpen && (
                <AddMemoryForm
                  t={c.t}
                  onMutate={c.invalidateMemory}
                  onClose={c.closeAddForm}
                  initialDraft={c.addFormDraft}
                  onDraftChange={c.persistDraft}
                />
              )}

              {/* Section 2: Structured memory — AI-authored and
                  user-seeded entries share one list. */}
              <section>
                <h2 className="text-text-primary text-base font-medium mb-1 flex items-center gap-2">
                  <SparkleIcon className="w-4 h-4 text-text-muted" />
                  {c.t('memory.aiGenerated')}
                </h2>
                <p className="text-text-muted text-xs mb-3">{c.t('memory.aiGeneratedDesc')}</p>

                {c.listEntries.length > 0 && (
                  <div className="flex items-center gap-3 mb-3">
                    <SearchInput
                      value={c.search}
                      onChange={c.setSearch}
                      placeholder={c.t('memory.searchPlaceholder')}
                    />
                    <span className="text-text-muted text-xs whitespace-nowrap tabular-nums">
                      {c.filteredListEntries.length}/{c.listEntries.length}
                    </span>
                  </div>
                )}

                {c.listEntries.length === 0 ? (
                  // when MCP isn't configured, the passive-voice
                  // "let your AI add notes" copy implies an assistant
                  // that doesn't exist yet — swap in the setup CTA
                  // instead. Users who already have an assistant
                  // connected keep seeing the normal copy, so the
                  // "+ Add memory" self-seed path stays obvious.
                  c.mcpUnconfigured && !c.addFormOpen ? (
                    <AssistantNotConfiguredPanel onNavigate={onNavigate} />
                  ) : !c.addFormOpen ? (
                    <ModuleStatePanel
                      icon={<SparkleIcon className="w-9 h-9" />}
                      title={c.t('memory.empty')}
                      subtitle={c.t('memory.emptyHint')}
                      actionLabel={`+ ${c.t('memory.addMemory')}`}
                      onAction={c.openAddForm}
                    />
                  ) : (
                    <ModuleStatePanel
                      icon={<SparkleIcon className="w-9 h-9" />}
                      title={c.t('memory.empty')}
                      subtitle={c.t('memory.emptyHint')}
                    />
                  )
                ) : c.filteredListEntries.length === 0 && c.normalizedSearch ? (
                  <ModuleStatePanel
                    icon={<SearchIcon className="w-9 h-9" />}
                    title={c.t('memory.noResults')}
                  />
                ) : null}

                <MemoryEntryList
                  entries={c.filteredListEntries}
                  locale={c.locale}
                  timezone={c.timezone}
                  t={c.t}
                  onMutate={c.invalidateMemory}
                  onOpenAddForm={c.openAddFormForCluster}
                />
              </section>
            </>
          )}
        </div>
      )}
    </div>
  );
}
