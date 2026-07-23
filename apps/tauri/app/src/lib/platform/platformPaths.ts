import { getRuntimeId } from './platform';
import {
  getClaudeCodeConfigPathHintForRuntime,
  getClaudeDesktopConfigPathHintForRuntime,
  getCodexConfigPathHintForRuntime,
} from './platform.logic';

export function getClaudeDesktopConfigPathHint(): string {
  return getClaudeDesktopConfigPathHintForRuntime(getRuntimeId());
}

export function getClaudeCodeConfigPathHint(): string {
  return getClaudeCodeConfigPathHintForRuntime(getRuntimeId());
}

export function getCodexConfigPathHint(): string {
  return getCodexConfigPathHintForRuntime(getRuntimeId());
}
