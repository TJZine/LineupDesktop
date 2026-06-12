import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

export type RendererBridgeFailureOperation =
  | 'player.dispatch'
  | 'player.getSnapshot'
  | 'guide.getPresentation'
  | 'player.tuneChannel';

export function recordRendererBridgeFailure(
  recordRendererEvent: LineupDesktopPreloadApi['diagnostics']['recordRendererEvent'],
  operation: RendererBridgeFailureOperation,
  message: string,
  context: Record<string, string>,
): void {
  void recordRendererEvent({
    requestId: `${operation.replace('.', '-')}-${Date.now()}`,
    event: {
      surface: 'renderer',
      category: 'ipc',
      severity: 'warning',
      operation,
      message: `${operation} failed: ${message}`,
      context,
    },
  }).catch(() => undefined);
}

export function summarizeRendererBridgeError(error: unknown): string {
  if (error instanceof Error && error.message.trim().length > 0) {
    return error.message;
  }
  return typeof error === 'string' && error.trim().length > 0 ? error : 'Renderer bridge call rejected.';
}
