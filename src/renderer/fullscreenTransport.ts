import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

type WindowBridge = LineupDesktopPreloadApi['window'];
type FullscreenResult = Awaited<ReturnType<WindowBridge['setFullscreen']>>;

export interface FullscreenTransportCoordinator extends WindowBridge {}

export function createFullscreenTransportCoordinator(options: {
  bridge: WindowBridge;
  reconcile(enabled: boolean): void;
}): FullscreenTransportCoordinator {
  let tail = Promise.resolve();
  let latestIntent: { enabled: boolean; operation: Promise<FullscreenResult> } | null = null;

  return {
    setFullscreen(enabled) {
      if (latestIntent?.enabled === enabled) return latestIntent.operation;

      const operation = tail.then(async () => {
        const result = await options.bridge.setFullscreen(enabled);
        if (isValidFullscreenResult(result)) options.reconcile(result.value.enabled);
        return result;
      });
      latestIntent = { enabled, operation };
      tail = operation.then(
        () => undefined,
        () => undefined,
      );
      void operation.finally(() => {
        if (latestIntent?.operation === operation) latestIntent = null;
      }).catch(() => undefined);
      return operation;
    },
  };
}

function isValidFullscreenResult(
  result: FullscreenResult,
): result is FullscreenResult & { ok: true } {
  return result.ok === true && typeof result.value.enabled === 'boolean';
}
