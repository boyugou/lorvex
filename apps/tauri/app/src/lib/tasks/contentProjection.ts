interface TaskBodyProjection {
  bodySnippet: string | null;
}

function extractBodySnippetInternal(body: string, maxLen: number): string | null {
  for (const line of body.split('\n')) {
    const trimmed = line.trim();
    if (!trimmed) continue;
    if (/^- \[[ xX]\]/.test(trimmed)) continue;
    if (/^#{1,3}\s/.test(trimmed)) continue;
    return trimmed.length > maxLen ? `${trimmed.slice(0, maxLen)}…` : trimmed;
  }
  return null;
}

export function projectTaskBodyContent(
  body: string | null,
  maxSnippetLength = 80,
): TaskBodyProjection {
  if (!body) {
    return {
      bodySnippet: null,
    };
  }

  return {
    bodySnippet: extractBodySnippetInternal(body, maxSnippetLength),
  };
}
