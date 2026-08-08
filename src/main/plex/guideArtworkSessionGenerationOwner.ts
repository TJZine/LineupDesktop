import {
  createProfileBinding,
  createServerBinding,
} from '../../domain/channelBuilder/index.js';
import type { DesktopPlexAuthService } from './auth/index.js';
import type { DesktopPlexServerDiscovery } from './discovery/index.js';
import type { PlexConnection } from './discovery/types.js';

export type GuideArtworkReadySession = Readonly<{
  generationId: number;
  status: 'ready';
  profileBinding: string;
  serverBinding: string;
  connection: Readonly<PlexConnection>;
  token: string;
  lineupRevision: number;
}>;

export type GuideArtworkSessionSnapshot = GuideArtworkReadySession | Readonly<{
  generationId: number;
  status: 'unavailable' | 'disposed';
  profileBinding: null;
  serverBinding: null;
  connection: null;
  token: null;
  lineupRevision: null;
}>;

export type GuideArtworkSessionListener = (
  snapshot: GuideArtworkSessionSnapshot,
) => void;

export type GuideArtworkTransitionLease = Readonly<{
  settle(): void;
}>;

type ArtworkAuthSource = Pick<
  DesktopPlexAuthService,
  'getActiveUserId' | 'getActiveTokenForMain'
>;

type ArtworkServerSource = Pick<
  DesktopPlexServerDiscovery,
  'getSelectedServerSummary' | 'getSelectedConnectionForMain'
>;

export class GuideArtworkSessionGenerationOwner {
  private readonly listeners = new Set<GuideArtworkSessionListener>();
  private readonly activeTransitions = new Set<symbol>();
  private snapshot: GuideArtworkSessionSnapshot;

  public constructor(
    private readonly authService: ArtworkAuthSource,
    private readonly serverDiscovery: ArtworkServerSource,
    initialGenerationId = 1,
  ) {
    if (!Number.isSafeInteger(initialGenerationId) || initialGenerationId < 1) {
      throw new Error('Guide artwork generation seed is invalid.');
    }
    this.snapshot = unavailableSnapshot(initialGenerationId);
  }

  public getSnapshot(): GuideArtworkSessionSnapshot {
    return this.snapshot;
  }

  public captureCurrent(lineupRevision: number): GuideArtworkReadySession | null {
    if (this.getSnapshot().status === 'disposed' || this.activeTransitions.size > 0) return null;
    const current = this.readCurrentInputs(lineupRevision);
    if (this.snapshot.status === 'disposed' || this.activeTransitions.size > 0) return null;
    if (current === null) {
      if (this.snapshot.status === 'ready') this.invalidateTransition('current-input-unavailable');
      return null;
    }
    const previous = this.snapshot;
    if (previous.status === 'ready') {
      if (matchesCurrent(previous, current)) return previous;
      this.invalidateTransition('current-input-changed');
      if (this.getSnapshot().status === 'disposed') return null;
    }
    const generationId = this.nextGenerationId();
    if (generationId === null) return null;
    const snapshot: GuideArtworkReadySession = Object.freeze({
      generationId,
      status: 'ready',
      profileBinding: current.profileBinding,
      serverBinding: current.serverBinding,
      connection: current.connection,
      token: current.token,
      lineupRevision: current.lineupRevision,
    });
    this.publish(snapshot);
    return snapshot;
  }

  public invalidateTransition(_reason: string): void {
    if (this.snapshot.status === 'disposed') return;
    const generationId = this.nextGenerationId();
    if (generationId === null) return;
    this.publish(unavailableSnapshot(generationId));
  }

  public beginTransition(reason: string): GuideArtworkTransitionLease {
    if (this.getSnapshot().status === 'disposed') return INERT_TRANSITION_LEASE;
    const transitionId = Symbol(reason);
    this.activeTransitions.add(transitionId);
    this.invalidateTransition(reason);
    if (this.snapshot.status === 'disposed') return INERT_TRANSITION_LEASE;
    let settled = false;
    return Object.freeze({
      settle: () => {
        if (settled || this.snapshot.status === 'disposed') return;
        settled = true;
        this.activeTransitions.delete(transitionId);
      },
    });
  }

  public isCurrent(generationId: number): boolean {
    return this.snapshot.status === 'ready' && this.snapshot.generationId === generationId;
  }

  public subscribe(listener: GuideArtworkSessionListener): () => void {
    if (this.snapshot.status === 'disposed') {
      listener(this.snapshot);
      return () => undefined;
    }
    this.listeners.add(listener);
    return () => {
      this.listeners.delete(listener);
    };
  }

  public dispose(): void {
    if (this.snapshot.status === 'disposed') return;
    const generationId = this.nextGenerationId(false);
    this.activeTransitions.clear();
    this.publish(disposedSnapshot(generationId ?? this.snapshot.generationId));
    this.listeners.clear();
  }

  private readCurrentInputs(lineupRevision: number): GuideArtworkReadySession | null {
    if (!Number.isSafeInteger(lineupRevision) || lineupRevision < 0) return null;
    const profileId = this.authService.getActiveUserId()?.trim() ?? '';
    const token = this.authService.getActiveTokenForMain();
    const serverId = this.serverDiscovery.getSelectedServerSummary()?.serverId.trim() ?? '';
    const connection = this.serverDiscovery.getSelectedConnectionForMain();
    if (profileId === '' || token === null || token === '' || serverId === '' || connection === null) {
      return null;
    }
    try {
      return Object.freeze({
        generationId: this.snapshot.generationId,
        status: 'ready',
        profileBinding: createProfileBinding(profileId),
        serverBinding: createServerBinding(serverId),
        connection: freezeConnection(connection),
        token,
        lineupRevision,
      });
    } catch {
      return null;
    }
  }

  private nextGenerationId(disposeOnOverflow = true): number | null {
    if (this.snapshot.generationId >= Number.MAX_SAFE_INTEGER) {
      if (disposeOnOverflow) {
        this.publish(disposedSnapshot(this.snapshot.generationId));
        this.listeners.clear();
      }
      return null;
    }
    return this.snapshot.generationId + 1;
  }

  private publish(snapshot: GuideArtworkSessionSnapshot): void {
    this.snapshot = snapshot;
    for (const listener of [...this.listeners]) {
      try {
        listener(snapshot);
      } catch {
        // Session invalidation must notify remaining subscribers synchronously.
      }
    }
  }
}

const INERT_TRANSITION_LEASE: GuideArtworkTransitionLease = Object.freeze({
  settle: () => undefined,
});

function freezeConnection(connection: PlexConnection): Readonly<PlexConnection> {
  return Object.freeze({
    uri: connection.uri,
    protocol: connection.protocol,
    address: connection.address,
    port: connection.port,
    local: connection.local,
    relay: connection.relay,
    latencyMs: connection.latencyMs,
  });
}

function unavailableSnapshot(generationId: number): GuideArtworkSessionSnapshot {
  return Object.freeze({
    generationId,
    status: 'unavailable',
    profileBinding: null,
    serverBinding: null,
    connection: null,
    token: null,
    lineupRevision: null,
  });
}

function disposedSnapshot(generationId: number): GuideArtworkSessionSnapshot {
  return Object.freeze({
    generationId,
    status: 'disposed',
    profileBinding: null,
    serverBinding: null,
    connection: null,
    token: null,
    lineupRevision: null,
  });
}

function matchesCurrent(
  snapshot: GuideArtworkReadySession,
  current: GuideArtworkReadySession,
): boolean {
  return snapshot.profileBinding === current.profileBinding &&
    snapshot.serverBinding === current.serverBinding &&
    snapshot.token === current.token &&
    snapshot.lineupRevision === current.lineupRevision &&
    sameConnection(snapshot.connection, current.connection);
}

function sameConnection(left: Readonly<PlexConnection>, right: Readonly<PlexConnection>): boolean {
  return left.uri === right.uri &&
    left.protocol === right.protocol &&
    left.address === right.address &&
    left.port === right.port &&
    left.local === right.local &&
    left.relay === right.relay &&
    left.latencyMs === right.latencyMs;
}
