export interface ToolCase {
  name: string;
  args: Record<string, unknown>;
}

export interface ToolBenchmarkResult {
  tool: string;
  elapsed_ms: number;
  payload_bytes: number;
  metadata_ok: boolean;
  metadata_note: string;
  limit: number | null;
  returned: number | null;
  total_matching: number | null;
  truncated: boolean | null;
}

export interface DatasetBenchmarkResult {
  dataset_size: number;
  runtime: 'rust';
  tools: ToolBenchmarkResult[];
  total_elapsed_ms: number;
  max_tool_elapsed_ms: number;
  max_payload_bytes: number;
}
