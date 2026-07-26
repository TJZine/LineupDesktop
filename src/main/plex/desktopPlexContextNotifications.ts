export type DesktopPlexBuilderLibraryPair = Readonly<{
  libraryId: string;
  libraryUuid: string;
}>;

export type DesktopPlexBuilderContextSnapshot = Readonly<{
  activeProfileId: string;
  selectedServerId: string;
  libraryPairs: readonly DesktopPlexBuilderLibraryPair[];
}>;

export type DesktopPlexBuilderContextError = Readonly<{
  code: 'profile-unavailable' | 'server-unavailable' | 'libraries-unavailable';
}>;

export type DesktopPlexBuilderContextResult =
  | Readonly<{ ok: true; snapshot: DesktopPlexBuilderContextSnapshot }>
  | Readonly<{ ok: false; error: DesktopPlexBuilderContextError }>
  | null;

export type DesktopPlexBuilderContextEvent = Readonly<{
  kind: 'initial' | 'changed';
  revision: number;
  result: DesktopPlexBuilderContextResult;
}>;

export type DesktopPlexBuilderContextListener = (
  event: DesktopPlexBuilderContextEvent,
) => void;

export type DesktopPlexBuilderContextUnsubscribe = () => void;

export class DesktopPlexContextNotifications {
  private result: DesktopPlexBuilderContextResult = null;
  private revision = 0;
  private readonly listeners = new Set<DesktopPlexBuilderContextListener>();

  public get(): DesktopPlexBuilderContextResult {
    return cloneResult(this.result);
  }

  public subscribe(
    listener: DesktopPlexBuilderContextListener,
  ): DesktopPlexBuilderContextUnsubscribe {
    if (typeof listener !== 'function') {
      throw new TypeError('Plex builder context listener must be a function.');
    }
    this.invoke(listener, {
      kind: 'initial',
      revision: this.revision,
      result: this.get(),
    });
    this.listeners.add(listener);
    let active = true;
    return () => {
      if (!active) return;
      active = false;
      this.listeners.delete(listener);
    };
  }

  public publish(result: DesktopPlexBuilderContextResult): void {
    const normalized = normalizeResult(result);
    if (JSON.stringify(normalized) === JSON.stringify(this.result)) return;
    if (!Number.isSafeInteger(this.revision + 1)) {
      throw new Error('Plex builder context revision overflow.');
    }
    this.result = normalized;
    this.revision += 1;
    const event: DesktopPlexBuilderContextEvent = Object.freeze({
      kind: 'changed',
      revision: this.revision,
      result: this.get(),
    });
    for (const listener of [...this.listeners]) this.invoke(listener, event);
  }

  private invoke(
    listener: DesktopPlexBuilderContextListener,
    event: DesktopPlexBuilderContextEvent,
  ): void {
    try {
      listener(event);
    } catch {
      // One main-only observer cannot disrupt context publication.
    }
  }
}

function normalizeResult(
  result: DesktopPlexBuilderContextResult,
): DesktopPlexBuilderContextResult {
  if (result === null) return null;
  if (!result.ok) {
    if (
      result.error.code !== 'profile-unavailable' &&
      result.error.code !== 'server-unavailable' &&
      result.error.code !== 'libraries-unavailable'
    ) {
      throw new TypeError('Invalid Plex builder context error.');
    }
    return Object.freeze({ ok: false, error: Object.freeze({ code: result.error.code }) });
  }
  const activeProfileId = readIdentifier(result.snapshot.activeProfileId);
  const selectedServerId = readIdentifier(result.snapshot.selectedServerId);
  if (activeProfileId === null || selectedServerId === null) {
    throw new TypeError('Invalid Plex builder context identity.');
  }
  const libraryPairs = normalizePairs(result.snapshot.libraryPairs);
  return Object.freeze({
    ok: true,
    snapshot: Object.freeze({
      activeProfileId,
      selectedServerId,
      libraryPairs,
    }),
  });
}

function normalizePairs(
  input: readonly DesktopPlexBuilderLibraryPair[],
): readonly DesktopPlexBuilderLibraryPair[] {
  if (!Array.isArray(input) || input.length < 1) {
    throw new TypeError('Invalid Plex builder library catalog.');
  }
  const pairs = input.map((pair) => {
    const libraryId = readIdentifier(pair.libraryId);
    const libraryUuid = readIdentifier(pair.libraryUuid);
    if (libraryId === null || libraryUuid === null) {
      throw new TypeError('Invalid Plex builder library pair.');
    }
    return Object.freeze({ libraryId, libraryUuid });
  });
  pairs.sort(
    (left, right) =>
      left.libraryId.localeCompare(right.libraryId) ||
      left.libraryUuid.localeCompare(right.libraryUuid),
  );
  if (
    new Set(pairs.map((pair) => pair.libraryId)).size !== pairs.length ||
    new Set(pairs.map((pair) => `${pair.libraryId}\u0000${pair.libraryUuid}`)).size !==
      pairs.length
  ) {
    throw new TypeError('Invalid Plex builder library catalog.');
  }
  return Object.freeze(pairs);
}

function cloneResult(
  result: DesktopPlexBuilderContextResult,
): DesktopPlexBuilderContextResult {
  return result === null ? null : normalizeResult(result);
}

function readIdentifier(value: unknown): string | null {
  if (typeof value !== 'string') return null;
  const normalized = value.trim();
  return normalized.length > 0 && normalized.length <= 512 ? normalized : null;
}
