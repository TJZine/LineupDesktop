import { clearTimeout, setTimeout } from 'node:timers';

export function throwIfPlexRequestAborted(
  signal: AbortSignal | null | undefined,
  createError: () => Error,
): void {
  if (signal?.aborted) {
    throw createError();
  }
}

export function sleepWithPlexAbort(
  durationMs: number,
  signal: AbortSignal | null | undefined,
  createError: () => Error,
): Promise<void> {
  return new Promise((resolve, reject) => {
    if (signal?.aborted) {
      reject(createError());
      return;
    }

    const onAbort = () => {
      clearTimeout(timeout);
      signal?.removeEventListener('abort', onAbort);
      reject(createError());
    };
    const timeout = setTimeout(() => {
      signal?.removeEventListener('abort', onAbort);
      resolve();
    }, durationMs);
    signal?.addEventListener('abort', onAbort, { once: true });
  });
}
