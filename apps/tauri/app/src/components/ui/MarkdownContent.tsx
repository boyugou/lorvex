import { Children, isValidElement, type MouseEvent, type ReactNode, useMemo, useState } from 'react';
import ReactMarkdown from 'react-markdown';
import remarkGfm from 'remark-gfm';
import { openUrl } from '@tauri-apps/plugin-opener';

import { reportClientError } from '@/lib/errors/errorLogging';
import { useI18n } from '@/lib/i18n';
import { isAllowedLinkUrl } from '@/lib/security/urlSafety';

interface MarkdownContentProps {
  content: string;
  className?: string;
}

interface MarkdownElementProps {
  children?: ReactNode;
  checked?: boolean;
  type?: string;
}

function classListIncludes(className: string | undefined, target: string): boolean {
  return typeof className === 'string' && className.split(/\s+/).includes(target);
}

function findTaskCheckboxState(children: ReactNode): boolean | null {
  let state: boolean | null = null;
  Children.forEach(children, (child) => {
    if (state !== null || !isValidElement<MarkdownElementProps>(child)) return;
    if (child.type === 'input' && child.props.type === 'checkbox') {
      state = Boolean(child.props.checked);
      return;
    }
    state = findTaskCheckboxState(child.props.children);
  });
  return state;
}

function findTaskCheckboxStateFromNode(node: unknown): boolean | null {
  if (node === null || typeof node !== 'object') return null;
  const candidate = node as {
    tagName?: unknown;
    properties?: Record<string, unknown>;
    children?: unknown;
  };
  if (candidate.tagName === 'input' && candidate.properties?.type === 'checkbox') {
    return Boolean(candidate.properties.checked);
  }
  if (Array.isArray(candidate.children)) {
    for (const child of candidate.children) {
      const state = findTaskCheckboxStateFromNode(child);
      if (state !== null) return state;
    }
  }
  return null;
}

interface SafeMarkdownImageProps {
  src: string;
  alt: string;
  title?: string;
  fallbackLabel: string;
}

/**
 * Markdown <img> renderer with native-decode hints plus a broken-image
 * affordance. `loading='lazy'` defers off-screen decode, `decoding='async'`
 * keeps decoding off the main thread; on a fetch / decode failure we
 * swap in a small token-styled placeholder so a revoked `blob:` URL or
 * failed `data:` decode doesn't leave a transparent gap. Intrinsic
 * size is intentionally not declared — the markdown grammar doesn't
 * carry width/height, and reserving a fixed `aspect-ratio` would
 * mis-shape any legitimate image whose ratio differs.
 */
function SafeMarkdownImage({ src, alt, title, fallbackLabel }: SafeMarkdownImageProps) {
  const [failed, setFailed] = useState(false);
  if (failed) {
    return (
      <span
        role="img"
        aria-label={alt || fallbackLabel}
        className="inline-flex items-center gap-1.5 px-2 py-1 rounded-r-control border border-card bg-surface-2 text-text-muted text-xs"
        {...(title ? { title } : {})}
      >
        <svg
          width="14"
          height="14"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.4"
          strokeLinecap="round"
          strokeLinejoin="round"
          aria-hidden="true"
        >
          <rect x="2" y="3" width="12" height="10" rx="1.5" />
          <path d="m2 11 3-3 2 2 3-3 4 4" />
          <path d="m2 3 12 10" />
        </svg>
        <span>{fallbackLabel}</span>
      </span>
    );
  }
  return (
    <img
      src={src}
      alt={alt}
      {...(title ? { title } : {})}
      loading="lazy"
      decoding="async"
      onError={() => setFailed(true)}
      className="max-w-full rounded-r-control"
    />
  );
}

/**
 * Renders markdown text as styled HTML. Supports GFM (GitHub Flavored Markdown):
 * headings, lists, checkboxes, bold, italic, links, code, blockquotes, hr.
 *
 * Links open via Tauri's native opener (system browser) instead of webview navigation.
 */
export default function MarkdownContent({ content, className }: MarkdownContentProps) {
  const { t } = useI18n();
  const plugins = useMemo(() => [remarkGfm], []);
  const completedTaskPrefix = t('markdown.taskList.completedPrefix');
  const incompleteTaskPrefix = t('markdown.taskList.incompletePrefix');

  if (!content) return null;

  return (
    <div className={`markdown-content select-text-content ${className ?? ''}`}>
      <ReactMarkdown
        remarkPlugins={plugins}
        components={{
          a: ({ href, children }) => {
            const allowed = isAllowedLinkUrl(href);
            const handleClick = (e: MouseEvent) => {
              e.preventDefault();
              e.stopPropagation();
              if (allowed && href) {
                void openUrl(href).catch((error) => {
                  reportClientError(
                    'markdown.openUrl',
                    'Failed to open markdown link',
                    error,
                    href,
                    'warn',
                  );
                });
              }
            };
            // defense-in-depth anchor attrs. onClick is the
            // primary safety gate (preventDefault + openUrl), but if a
            // future refactor drops onClick these ensure a click would
            // still open out-of-process and with noopener/noreferrer.
            return (
              <a
                href={allowed ? href : '#'}
                onClick={handleClick}
                target={allowed ? '_blank' : undefined}
                rel={allowed ? 'noopener noreferrer' : undefined}
                className="text-accent hover:text-accent/80 underline underline-offset-2 cursor-pointer"
              >
                {children}
              </a>
            );
          },
          // default <img> renderer has no scheme filter.
          // AI-authored ai_notes and daily_review.* content flows
          // through MarkdownContent, so a prompt-injected
          // `![pixel](http://attacker.com/beacon.png)` would render the
          // raw <img>. CSP `img-src 'self' data: blob:` blocks the
          // network fetch today, but defense-in-depth: refuse to emit
          // an <img> for any non-allowed scheme up front, and drop the
          // fallback broken-image silently.
          img: ({ src, alt, title }) => {
            if (typeof src !== 'string' || src.length === 0) return null;
            // Allowed: data: / blob: images embedded in AI review
            // summaries. Everything else is blocked — reflects the CSP
            // img-src policy at the renderer layer so a CSP relaxation
            // later doesn't silently re-enable tracking pixels.
            if (
              src.startsWith('data:image/')
              || src.startsWith('blob:')
            ) {
              return (
                <SafeMarkdownImage
                  src={src}
                  alt={alt ?? ''}
                  {...(title ? { title } : {})}
                  fallbackLabel={t('markdown.imageUnavailable')}
                />
              );
            }
            return null;
          },
          li: ({ className, children, node, ...props }) => {
            const taskState = findTaskCheckboxStateFromNode(node) ?? findTaskCheckboxState(children);
            if (classListIncludes(className, 'task-list-item') || taskState !== null) {
              return (
                <li {...props} className={className}>
                  <span className="sr-only">
                    {taskState ? completedTaskPrefix : incompleteTaskPrefix}
                  </span>
                  {children}
                </li>
              );
            }
            return (
              <li {...props} className={className}>
                {children}
              </li>
            );
          },
          // With rehypeRaw disabled, react-markdown only emits
          // rendered inputs for GFM task-list checkboxes. The list item
          // above owns the accessible state + text; this native
          // checkbox is the visual affordance only.
          input: ({ checked, node: _node, ...props }) => (
            <input
              {...props}
              type="checkbox"
              checked={checked}
              disabled
              aria-hidden="true"
              tabIndex={-1}
              className="me-1.5 accent-accent pointer-events-none align-middle"
            />
          ),
          code: ({ children, className: codeClassName }) => {
            // Detect code blocks (has language class) vs inline code
            const isBlock = typeof codeClassName === 'string' && codeClassName.startsWith('language-');
            if (isBlock) {
              return (
                <code className={`text-xs text-text-secondary whitespace-pre ${codeClassName ?? ''}`}>
                  {children}
                </code>
              );
            }
            return (
              <code className="bg-surface-2 border border-card rounded-r-control px-1 py-0.5 text-[0.85em] text-text-primary">
                {children}
              </code>
            );
          },
        }}
      >
        {content}
      </ReactMarkdown>
    </div>
  );
}
