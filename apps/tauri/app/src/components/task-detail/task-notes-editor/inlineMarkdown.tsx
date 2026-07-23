import type { ReactNode } from 'react';

interface ExternalLinkProps {
  href: string;
  children: ReactNode;
}

function ExternalLink({ href, children }: ExternalLinkProps) {
  return (
    <a
      href={href}
      target="_blank"
      rel="noreferrer"
      className="underline underline-offset-2 text-accent hover:text-accent/80"
    >
      {children}
    </a>
  );
}

export function renderInlineMarkdown(markdown: string): ReactNode {
  const trimmed = markdown.trim();
  if (!trimmed) return null;

  const linkMatch = trimmed.match(/^\[([^\]]+)\]\((https?:\/\/[^)]+)\)$/);
  if (linkMatch) {
    const [, label, href] = linkMatch;
    if (label && href) {
      return <ExternalLink href={href}>{label}</ExternalLink>;
    }
  }

  return trimmed;
}
