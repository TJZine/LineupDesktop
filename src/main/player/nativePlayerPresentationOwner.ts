import type {
  PlayerPresentationRequest,
  PlayerPresentationResult,
  PlayerSnapshot,
} from '../../contracts/player.js';
import type {
  NativePlayerHostPort,
  NativePlayerPresentationUpdate,
} from './nativePlayerHostPort.js';
import type { platform as processPlatform } from 'node:process';

type RuntimePlatform = typeof processPlatform;

export interface NativePlayerParentIdentity {
  hwnd: string;
  pid: number;
}

export interface NativePlayerPresentationOwnerOptions {
  platform: RuntimePlatform;
  host: Pick<NativePlayerHostPort, 'updatePresentation'> | null;
  getSnapshot(): PlayerSnapshot | null;
  getParentIdentity(): NativePlayerParentIdentity | null;
  initialDocumentEpoch?: number;
}

interface PendingUpdate {
  request: PlayerPresentationRequest & { documentEpoch: number };
  resolve(result: PlayerPresentationResult): void;
}

export class NativePlayerPresentationOwner {
  readonly #options: NativePlayerPresentationOwnerOptions;
  #documentEpoch: number;
  #epochNegotiated = false;
  #latestRevision = 0;
  #active: PendingUpdate | null = null;
  #trailing: PendingUpdate | null = null;
  #disposed = false;
  #disposePromise: Promise<void> | null = null;
  #epochExhausted = false;

  constructor(options: NativePlayerPresentationOwnerOptions) {
    this.#options = options;
    this.#documentEpoch = positive(options.initialDocumentEpoch) ? options.initialDocumentEpoch : 1;
  }

  invalidateDocument(): boolean {
    if (this.#disposed || this.#disposePromise !== null || this.#epochExhausted) return false;
    this.#settlePendingAsStale(true);
    if (this.#documentEpoch === Number.MAX_SAFE_INTEGER) {
      this.#epochExhausted = true;
      return false;
    }
    this.#documentEpoch += 1;
    this.#epochNegotiated = false;
    this.#latestRevision = 0;
    return true;
  }

  update(value: unknown): Promise<PlayerPresentationResult> {
    const correlation = readCorrelation(value);
    if (this.#disposed || this.#disposePromise !== null || this.#epochExhausted || !isPresentationRequest(value)) {
      return Promise.resolve(failure('rejected', correlation.documentEpoch, correlation.revision));
    }
    if (value.documentEpoch === null) {
      if (this.#epochNegotiated) return Promise.resolve(failure('main-stale', null, value.revision));
      this.#epochNegotiated = true;
      this.#latestRevision = value.revision;
      if (value.mode !== 'hidden') {
        return Promise.resolve(success('deferred', this.#documentEpoch, value.revision));
      }
      return this.#enqueue({ ...value, documentEpoch: this.#documentEpoch }).then((result) =>
        result.ok ? result : { ...result, documentEpoch: null });
    }
    if (!this.#epochNegotiated || value.documentEpoch !== this.#documentEpoch || value.revision <= this.#latestRevision) {
      return Promise.resolve(failure('main-stale', value.documentEpoch, value.revision));
    }
    this.#latestRevision = value.revision;
    return this.#enqueue(value as PlayerPresentationRequest & { documentEpoch: number });
  }

  async hide(): Promise<PlayerPresentationResult> {
    if (this.#disposed) return failure('lifecycle-failure', this.#documentEpoch, null);
    return this.#enqueue({
      documentEpoch: this.#documentEpoch,
      revision: Math.max(1, this.#latestRevision),
      requestId: null,
      mode: 'hidden',
      rect: null,
    });
  }

  dispose(): Promise<void> {
    if (this.#disposePromise !== null) return this.#disposePromise;
    this.#disposePromise = this.#dispose();
    return this.#disposePromise;
  }

  async #dispose(): Promise<void> {
    try {
      await this.hide();
    } finally {
      this.#disposed = true;
      this.#settlePendingAsStale();
    }
  }

  #enqueue(request: PlayerPresentationRequest & { documentEpoch: number }): Promise<PlayerPresentationResult> {
    return new Promise((resolve) => {
      const pending = { request: copyRequest(request), resolve };
      if (this.#active === null) {
        this.#active = pending;
        void this.#executeActive();
        return;
      }
      this.#trailing?.resolve(failure('main-stale', this.#trailing.request.documentEpoch, this.#trailing.request.revision));
      this.#trailing = pending;
    });
  }

  async #executeActive(): Promise<void> {
    const active = this.#active;
    if (active === null) return;
    let result: PlayerPresentationResult;
    try {
      result = await this.#execute(active.request);
    } catch {
      result = failure('lifecycle-failure', active.request.documentEpoch, active.request.revision);
    }
    active.resolve(result);
    if (this.#active !== active) return;
    this.#active = this.#trailing;
    this.#trailing = null;
    if (this.#active !== null) void this.#executeActive();
  }

  async #execute(request: PlayerPresentationRequest & { documentEpoch: number }): Promise<PlayerPresentationResult> {
    if (request.documentEpoch !== this.#documentEpoch ||
      (request.revision < this.#latestRevision && request.mode !== 'hidden')) {
      return failure('main-stale', request.documentEpoch, request.revision);
    }
    if (this.#options.platform !== 'win32') {
      return success('unsupported', request.documentEpoch, request.revision);
    }
    const host = this.#options.host;
    if (host?.updatePresentation === undefined) {
      return success('unsupported', request.documentEpoch, request.revision);
    }
    const parent = this.#options.getParentIdentity();
    if (parent === null) {
      return failure('rejected', request.documentEpoch, request.revision);
    }
    if (request.mode !== 'hidden' && !this.#isEligible(request)) {
      return failure('main-stale', request.documentEpoch, request.revision);
    }
    const update: NativePlayerPresentationUpdate = {
      documentEpoch: request.documentEpoch,
      revision: request.revision,
      parentHwnd: parent.hwnd,
      parentPid: parent.pid,
      loadedRequestId: request.requestId,
      mode: request.mode,
      bounds: request.rect,
    };
    const nativeResult = await host.updatePresentation(update);
    if (!nativeResult.ok) {
      if (nativeResult.classification === 'pre-send-rejected') {
        return failure('rejected', request.documentEpoch, request.revision);
      }
      return failure(nativeResult.error.category === 'timeout' ? 'timeout' : 'lifecycle-failure', request.documentEpoch, request.revision);
    }
    if (nativeResult.status === 'stale') {
      return failure('helper-stale', request.documentEpoch, request.revision);
    }
    if (request.mode === 'hidden') {
      return nativeResult.status === 'hidden'
        ? success('hidden', request.documentEpoch, request.revision)
        : failure('lifecycle-failure', request.documentEpoch, request.revision);
    }
    if (nativeResult.status !== 'applied' || request.documentEpoch !== this.#documentEpoch ||
      request.revision !== this.#latestRevision || !this.#isEligible(request)) {
      const hidden = await host.updatePresentation({ ...update, mode: 'hidden', bounds: null });
      if (!hidden.ok) {
        if (hidden.classification === 'pre-send-rejected') {
          return failure('rejected', request.documentEpoch, request.revision);
        }
        return failure(hidden.error.category === 'timeout' ? 'timeout' : 'lifecycle-failure', request.documentEpoch, request.revision);
      }
      if (hidden.status === 'hidden' || hidden.status === 'stale') {
        return failure('helper-stale', request.documentEpoch, request.revision);
      }
      return failure('lifecycle-failure', request.documentEpoch, request.revision);
    }
    return success('applied', request.documentEpoch, request.revision);
  }

  #isEligible(request: PlayerPresentationRequest): boolean {
    const snapshot = this.#options.getSnapshot();
    if (snapshot === null || request.requestId === null || snapshot.requestId !== request.requestId ||
      !['ready', 'buffering', 'playing', 'paused', 'seeking', 'stalled'].includes(snapshot.status)) return false;
    return request.mode !== 'guide-classic-pip' || snapshot.playing;
  }

  #settlePendingAsStale(keepActive = false): void {
    for (const pending of [this.#active, this.#trailing]) {
      if (pending !== null) pending.resolve(failure('main-stale', pending.request.documentEpoch, pending.request.revision));
    }
    if (!keepActive) this.#active = null;
    this.#trailing = null;
  }
}

function success(status: 'applied' | 'hidden' | 'deferred' | 'unsupported', documentEpoch: number, revision: number): PlayerPresentationResult {
  return { ok: true, status, documentEpoch, revision };
}

function failure(status: 'main-stale' | 'helper-stale' | 'rejected' | 'timeout' | 'lifecycle-failure', documentEpoch: number | null, revision: number | null): PlayerPresentationResult {
  switch (status) {
    case 'main-stale': return { ok: false, status, documentEpoch, revision, error: { code: 'PLAYER_PRESENTATION_MAIN_STALE', message: 'Player presentation request is stale.', recoverable: true, retryable: false } };
    case 'helper-stale': return { ok: false, status, documentEpoch, revision, error: { code: 'PLAYER_PRESENTATION_HELPER_STALE', message: 'Native presentation request is stale.', recoverable: true, retryable: false } };
    case 'rejected': return { ok: false, status, documentEpoch, revision, error: { code: 'PLAYER_PRESENTATION_REJECTED', message: 'Player presentation request was rejected.', recoverable: true, retryable: false } };
    case 'timeout': return { ok: false, status, documentEpoch, revision, error: { code: 'PLAYER_PRESENTATION_TIMEOUT', message: 'Native presentation request timed out.', recoverable: true, retryable: true } };
    case 'lifecycle-failure': return { ok: false, status, documentEpoch, revision, error: { code: 'PLAYER_PRESENTATION_LIFECYCLE_FAILURE', message: 'Native presentation is unavailable.', recoverable: true, retryable: true } };
  }
}

function isPresentationRequest(value: unknown): value is PlayerPresentationRequest {
  if (!isRecord(value) || !hasExactKeys(value, ['documentEpoch', 'revision', 'requestId', 'mode', 'rect'])) return false;
  if (!(value.documentEpoch === null || positive(value.documentEpoch)) || !positive(value.revision) ||
    !(value.requestId === null || typeof value.requestId === 'string' && /^[A-Za-z0-9._-]{1,120}$/u.test(value.requestId)) ||
    !['hidden', 'player-full', 'guide-overlay-full', 'guide-classic-pip'].includes(String(value.mode))) return false;
  if (value.mode === 'hidden') return value.rect === null;
  if (!isRecord(value.rect) || !hasExactKeys(value.rect, ['x', 'y', 'width', 'height'])) return false;
  const { x, y, width, height } = value.rect;
  if (![x, y, width, height].every((item) => typeof item === 'number' && Number.isFinite(item)) ||
    !(typeof x === 'number' && typeof y === 'number' && typeof width === 'number' && typeof height === 'number') ||
    x < 0 || y < 0 || width <= 0 || height <= 0 || x + width > 1 || y + height > 1) return false;
  return value.mode === 'guide-classic-pip' || x === 0 && y === 0 && width === 1 && height === 1;
}

function readCorrelation(value: unknown): { documentEpoch: number | null; revision: number | null } {
  if (!isRecord(value)) return { documentEpoch: null, revision: null };
  return { documentEpoch: value.documentEpoch === null || positive(value.documentEpoch) ? value.documentEpoch : null, revision: positive(value.revision) ? value.revision : null };
}
function copyRequest(request: PlayerPresentationRequest & { documentEpoch: number }): PlayerPresentationRequest & { documentEpoch: number } {
  return { ...request, rect: request.rect === null ? null : { ...request.rect } };
}
function positive(value: unknown): value is number { return typeof value === 'number' && Number.isSafeInteger(value) && value > 0; }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === 'object' && value !== null && !Array.isArray(value) && Object.getPrototypeOf(value) === Object.prototype; }
function hasExactKeys(value: Record<string, unknown>, keys: readonly string[]): boolean { const actual = Object.keys(value); return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key)); }
