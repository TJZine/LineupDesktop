import { setTimeout as delay } from 'node:timers/promises';

export function throwIfPlexRequestAborted(
  signal: AbortSignal | null | undefined,
  createError: () => Error,
): void {
  if (signal?.aborted) {
    throw createError();
  }
}

export async function sleepWithPlexAbort(
  durationMs: number,
  signal: AbortSignal | null | undefined,
  createError: () => Error,
): Promise<void> {
  throwIfPlexRequestAborted(signal, createError);
  try {
    await delay(durationMs, undefined, signal === null || signal === undefined ? undefined : { signal });
  } catch (error) {
    if (signal?.aborted) {
      throw createError();
    }
    throw error;
  }
}
