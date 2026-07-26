import {
  createLibrarySetBinding,
  createProfileBinding,
  createServerBinding,
} from '../../domain/channelBuilder/index.js';
import type { ChannelBuilderContextBinding } from '../../domain/channelBuilder/types.js';
import type {
  ChannelBuilderFacetAccessInput,
  ChannelBuilderFacetAccessPort,
  ChannelBuilderFacetSession,
} from '../plex/channelBuilderFacetSession.js';
import type {
  DesktopPlexBuilderContextEvent,
  DesktopPlexBuilderContextListener,
  DesktopPlexBuilderContextResult,
  DesktopPlexBuilderContextUnsubscribe,
  DesktopPlexBuilderLibraryPair,
} from '../plex/desktopPlexContextNotifications.js';

export type ChannelBuilderSelectedContext = Readonly<{
  context: ChannelBuilderContextBinding;
  selectedLibraryPairs: readonly DesktopPlexBuilderLibraryPair[];
}>;

export type ChannelBuilderRetainedContextRegistration = Readonly<{
  planId: string;
  context: ChannelBuilderContextBinding;
  selectedLibraryPairs: readonly DesktopPlexBuilderLibraryPair[];
  invalidate(): void;
}>;

export interface ChannelBuilderPlexContextSource {
  getBuilderContextForMain(): DesktopPlexBuilderContextResult;
  subscribeBuilderContextForMain(
    listener: DesktopPlexBuilderContextListener,
  ): DesktopPlexBuilderContextUnsubscribe;
  withChannelBuilderFacetSession<T>(
    input: ChannelBuilderFacetAccessInput,
    run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T>;
}

type RetainedContext = {
  context: ChannelBuilderContextBinding;
  selectedLibraryPairs: readonly DesktopPlexBuilderLibraryPair[];
  invalidate(): void;
};

export class ChannelBuilderContextEpochOwner implements ChannelBuilderFacetAccessPort {
  private readonly source: ChannelBuilderPlexContextSource;
  private readonly retained = new Map<string, RetainedContext>();
  private readonly unsubscribe: DesktopPlexBuilderContextUnsubscribe;
  private lastResult: DesktopPlexBuilderContextResult = null;
  private contextEpoch = 0;
  private closed = false;

  constructor(source: ChannelBuilderPlexContextSource) {
    this.source = source;
    this.unsubscribe = source.subscribeBuilderContextForMain((event) => {
      this.acceptEvent(event);
    });
  }

  capture(selectedLibraryIds: readonly string[]): ChannelBuilderSelectedContext {
    return deriveSelectedContext(
      this.source.getBuilderContextForMain(),
      selectedLibraryIds,
      this.contextEpoch,
    );
  }

  assertCurrent(
    context: ChannelBuilderContextBinding,
    selectedLibraryPairs: readonly DesktopPlexBuilderLibraryPair[],
  ): void {
    const current = deriveSelectedContext(
      this.source.getBuilderContextForMain(),
      selectedLibraryPairs.map((pair) => pair.libraryId),
      this.contextEpoch,
    );
    if (
      current.context.profileBinding !== context.profileBinding ||
      current.context.serverBinding !== context.serverBinding ||
      current.context.librarySetBinding !== context.librarySetBinding ||
      !equalPairs(current.selectedLibraryPairs, selectedLibraryPairs)
    ) {
      throw contextChangedError();
    }
  }

  retain(registration: ChannelBuilderRetainedContextRegistration): void {
    if (this.closed || this.retained.has(registration.planId)) {
      throw new Error('Channel Builder retained context registration was rejected.');
    }
    this.assertCurrent(registration.context, registration.selectedLibraryPairs);
    this.retained.set(registration.planId, {
      context: registration.context,
      selectedLibraryPairs: clonePairs(registration.selectedLibraryPairs),
      invalidate: registration.invalidate,
    });
  }

  release(planId: string): void {
    this.retained.delete(planId);
  }

  async withSession<T>(
    input: ChannelBuilderFacetAccessInput,
    run: (session: ChannelBuilderFacetSession) => Promise<T>,
  ): Promise<T> {
    const selected = this.capture(input.selectedLibraryIds);
    this.assertInput(input, selected);
    const result = await this.source.withChannelBuilderFacetSession(input, run);
    this.assertCurrent(input.expectedContext, selected.selectedLibraryPairs);
    return result;
  }

  shutdown(): void {
    if (this.closed) return;
    this.closed = true;
    this.unsubscribe();
    for (const retained of this.retained.values()) retained.invalidate();
    this.retained.clear();
  }

  private assertInput(
    input: ChannelBuilderFacetAccessInput,
    selected: ChannelBuilderSelectedContext,
  ): void {
    if (
      selected.context.contextEpoch !== input.expectedContext.contextEpoch ||
      selected.context.profileBinding !== input.expectedContext.profileBinding ||
      selected.context.serverBinding !== input.expectedContext.serverBinding ||
      selected.context.librarySetBinding !== input.expectedContext.librarySetBinding
    ) {
      throw contextChangedError();
    }
  }

  private acceptEvent(event: DesktopPlexBuilderContextEvent): void {
    if (this.closed) return;
    const previous = this.lastResult;
    this.lastResult = event.result;
    if (event.kind === 'initial') return;
    if (!Number.isSafeInteger(this.contextEpoch + 1)) {
      throw new Error('Channel Builder context epoch overflow.');
    }
    this.contextEpoch += 1;
    for (const [planId, retained] of this.retained) {
      if (invalidatesRetainedContext(previous, event.result, retained)) {
        this.retained.delete(planId);
        retained.invalidate();
      }
    }
  }
}

function deriveSelectedContext(
  result: DesktopPlexBuilderContextResult,
  selectedLibraryIds: readonly string[],
  contextEpoch: number,
): ChannelBuilderSelectedContext {
  if (result === null || !result.ok || selectedLibraryIds.length < 1) {
    throw contextChangedError();
  }
  const pairsById = new Map(result.snapshot.libraryPairs.map((pair) => [pair.libraryId, pair]));
  const selectedLibraryPairs = selectedLibraryIds.map((libraryId) => {
    const pair = pairsById.get(libraryId);
    if (pair === undefined) throw contextChangedError();
    return pair;
  });
  if (new Set(selectedLibraryIds).size !== selectedLibraryIds.length) {
    throw contextChangedError();
  }
  try {
    return {
      context: {
        contextEpoch,
        profileBinding: createProfileBinding(result.snapshot.activeProfileId),
        serverBinding: createServerBinding(result.snapshot.selectedServerId),
        librarySetBinding: createLibrarySetBinding([...selectedLibraryPairs].sort(comparePairs)),
      },
      selectedLibraryPairs: clonePairs(selectedLibraryPairs),
    };
  } catch {
    throw contextChangedError();
  }
}

function invalidatesRetainedContext(
  previous: DesktopPlexBuilderContextResult,
  current: DesktopPlexBuilderContextResult,
  retained: RetainedContext,
): boolean {
  if (previous === null || !previous.ok || current === null || !current.ok) return true;
  if (
    previous.snapshot.activeProfileId !== current.snapshot.activeProfileId ||
    previous.snapshot.selectedServerId !== current.snapshot.selectedServerId
  ) {
    return true;
  }
  const currentPairs = new Map(current.snapshot.libraryPairs.map((pair) => [pair.libraryId, pair]));
  return retained.selectedLibraryPairs.some(
    (pair) => currentPairs.get(pair.libraryId)?.libraryUuid !== pair.libraryUuid,
  );
}

function clonePairs(
  pairs: readonly DesktopPlexBuilderLibraryPair[],
): readonly DesktopPlexBuilderLibraryPair[] {
  return Object.freeze(pairs.map((pair) => Object.freeze({ ...pair })));
}

function equalPairs(
  left: readonly DesktopPlexBuilderLibraryPair[],
  right: readonly DesktopPlexBuilderLibraryPair[],
): boolean {
  return left.length === right.length &&
    left.every(
      (pair, index) =>
        pair.libraryId === right[index]?.libraryId &&
        pair.libraryUuid === right[index]?.libraryUuid,
    );
}

function comparePairs(
  left: DesktopPlexBuilderLibraryPair,
  right: DesktopPlexBuilderLibraryPair,
): number {
  return left.libraryId.localeCompare(right.libraryId) ||
    left.libraryUuid.localeCompare(right.libraryUuid);
}

function contextChangedError(): Error & { code: 'CHANNEL_CONTEXT_CHANGED' } {
  return Object.assign(new Error('Channel Builder context changed.'), {
    code: 'CHANNEL_CONTEXT_CHANGED' as const,
  });
}
