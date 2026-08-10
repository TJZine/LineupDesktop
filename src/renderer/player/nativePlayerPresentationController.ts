import type {
  PlayerPresentationMode,
  PlayerPresentationRequest,
  PlayerPresentationResult,
} from '../../contracts/player.js';

export interface NativePlayerPresentationIntent {
  mode: PlayerPresentationMode;
  requestId: string | null;
}

export interface NativePlayerPresentationControllerOptions {
  element: HTMLElement;
  updatePresentation(input: PlayerPresentationRequest): Promise<PlayerPresentationResult>;
  getIntent(): NativePlayerPresentationIntent;
  viewport(): { width: number; height: number };
  compositionElement?: HTMLElement;
  createResizeObserver?(listener: () => void): { observe(element: Element): void; disconnect(): void };
}

export interface NativePlayerPresentationController {
  reconcile(): void;
  teardown(): Promise<void>;
}

export function createNativePlayerPresentationController(
  options: NativePlayerPresentationControllerOptions,
): NativePlayerPresentationController {
  let documentEpoch: number | null = null;
  let revision = 0;
  let active: PlayerPresentationRequest | null = null;
  let latest: PlayerPresentationRequest | null = null;
  let applied: PlayerPresentationRequest | null = null;
  let disposed = false;
  let teardownRequest: PlayerPresentationRequest | null = null;
  let teardownPromise: Promise<void> | null = null;
  let resolveTeardown: (() => void) | null = null;
  const compositionElement = options.compositionElement ?? options.element.ownerDocument?.documentElement ?? options.element;

  const closeAperture = (): void => {
    options.element.dataset.nativePresentationAperture = 'opaque';
    compositionElement.dataset.nativePresentationAperture = 'opaque';
  };

  const setMode = (mode: PlayerPresentationMode): void => {
    options.element.dataset.nativePresentationMode = mode;
    compositionElement.dataset.nativePresentationMode = mode;
  };

  const describeIntent = (
    intent: NativePlayerPresentationIntent,
  ): Pick<PlayerPresentationRequest, 'requestId' | 'mode' | 'rect'> => {
    const rect = measureRect(intent.mode, options.element, options.viewport());
    const mode = intent.mode === 'guide-classic-pip' && rect === null ? 'hidden' : intent.mode;
    return {
      requestId: intent.requestId,
      mode,
      rect: mode === 'hidden' ? null : rect,
    };
  };

  const createRequest = (
    descriptor: Pick<PlayerPresentationRequest, 'requestId' | 'mode' | 'rect'>,
  ): PlayerPresentationRequest => ({
    documentEpoch,
    revision: ++revision,
    ...descriptor,
  });

  const dispatch = (request: PlayerPresentationRequest): void => {
    active = request;
    void options.updatePresentation(request).then((result) => {
      if (active !== request) return;
      if (result.ok && result.documentEpoch > 0) documentEpoch = result.documentEpoch;
      if (!disposed) {
        const current = describeIntent(options.getIntent());
        const stillCurrent = samePresentation(current, request) &&
          result.revision === request.revision && result.documentEpoch === request.documentEpoch &&
          latest === null && revision === request.revision;
        if (result.ok && result.status === 'applied' && stillCurrent) {
          applied = request;
          options.element.dataset.nativePresentationAperture = 'open';
          compositionElement.dataset.nativePresentationAperture = 'open';
        } else {
          closeAperture();
          if (result.ok && result.status === 'hidden' && stillCurrent) applied = request;
        }
        if (latest === null && result.ok && result.status === 'deferred' &&
          samePresentation(current, request) && revision === request.revision) {
          latest = createRequest(current);
        }
      } else {
        closeAperture();
      }
      active = null;
      if (latest !== null) {
        const trailing = latest.documentEpoch === null && documentEpoch !== null
          ? { ...latest, documentEpoch }
          : latest;
        latest = null;
        dispatch(trailing);
      } else if (request === teardownRequest) finishTeardown();
    }, () => {
      if (active !== request) return;
      active = null;
      closeAperture();
      if (latest !== null) {
        const trailing = latest.documentEpoch === null && documentEpoch !== null
          ? { ...latest, documentEpoch }
          : latest;
        latest = null;
        dispatch(trailing);
      } else if (request === teardownRequest) finishTeardown();
    });
  };

  const finishTeardown = (): void => {
    resolveTeardown?.();
    resolveTeardown = null;
  };

  const reconcile = (): void => {
    if (disposed) return;
    const intent = options.getIntent();
    setMode(intent.mode);
    const descriptor = describeIntent(intent);
    setMode(descriptor.mode);
    const pending = latest ?? active;
    if (pending !== null && samePresentation(pending, descriptor)) return;
    if (active === null && applied !== null && samePresentation(applied, descriptor)) return;
    applied = null;
    closeAperture();
    const request = createRequest(descriptor);
    if (active === null) dispatch(request);
    else latest = request;
  };

  const observer = options.createResizeObserver?.(reconcile) ??
    (typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(reconcile));
  observer?.observe(options.element);
  closeAperture();

  return {
    reconcile,
    teardown() {
      if (teardownPromise !== null) return teardownPromise;
      applied = null;
      closeAperture();
      observer?.disconnect();
      disposed = true;
      setMode('hidden');
      const hidden: PlayerPresentationRequest = {
        documentEpoch,
        revision: ++revision,
        requestId: null,
        mode: 'hidden',
        rect: null,
      };
      teardownRequest = hidden;
      teardownPromise = new Promise<void>((resolve) => { resolveTeardown = resolve; });
      latest = hidden;
      if (active === null) {
        latest = null;
        dispatch(hidden);
      }
      return teardownPromise;
    },
  };
}

function measureRect(
  mode: PlayerPresentationMode,
  element: HTMLElement,
  viewport: { width: number; height: number },
): PlayerPresentationRequest['rect'] {
  if (mode === 'hidden') return null;
  if (mode === 'player-full' || mode === 'guide-overlay-full') return { x: 0, y: 0, width: 1, height: 1 };
  if (viewport.width <= 0 || viewport.height <= 0) return null;
  const rect = element.getBoundingClientRect();
  const left = clamp(rect.left / viewport.width);
  const top = clamp(rect.top / viewport.height);
  const right = clamp(rect.right / viewport.width);
  const bottom = clamp(rect.bottom / viewport.height);
  if (right <= left || bottom <= top) return null;
  return { x: left, y: top, width: right - left, height: bottom - top };
}

function clamp(value: number): number { return Math.min(1, Math.max(0, value)); }

function samePresentation(
  left: Pick<PlayerPresentationRequest, 'requestId' | 'mode' | 'rect'>,
  right: Pick<PlayerPresentationRequest, 'requestId' | 'mode' | 'rect'>,
): boolean {
  return left.requestId === right.requestId && left.mode === right.mode && sameRect(left.rect, right.rect);
}

function sameRect(
  left: PlayerPresentationRequest['rect'],
  right: PlayerPresentationRequest['rect'],
): boolean {
  return left === null || right === null
    ? left === right
    : left.x === right.x && left.y === right.y && left.width === right.width && left.height === right.height;
}
