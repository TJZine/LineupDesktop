import type { PlayerSnapshot } from '../contracts/player.js';
import type { FocusRegistry, FocusState } from './navigation.js';
import {
  applyPlayerOverlayAction,
  createPlayerOverlayView,
  resolvePlayerOverlayFocusId,
  type PlayerOverlayActionId,
  type PlayerOverlayState,
} from './overlays.js';
import {
  recordRendererBridgeFailure,
  summarizeRendererBridgeError,
} from './rendererBridgeFailures.js';
import type { RendererPresentationFixtures } from './presentationFixtures.js';

export interface PlayerOverlayActionContext {
  getOverlayState(): PlayerOverlayState;
  setOverlayState(state: PlayerOverlayState): void;
  getPlayerSnapshot(): PlayerSnapshot;
  getFocusState(): FocusState;
  setFocusState(state: FocusState): void;
  getFocusRegistry(): FocusRegistry;
  getPresentationFixtures(): RendererPresentationFixtures;
  renderApp(): void;
}

let channelCommitTimeoutId: number | null = null;

export async function selectAudioTrack(
  trackId: string,
  context: PlayerOverlayActionContext,
): Promise<void> {
  const requestId = `select-audio-${Date.now()}`;
  const playerSnapshot = context.getPlayerSnapshot();
  const snapshotRequestId = playerSnapshot.requestId;
  if (snapshotRequestId === null) {
    recordPlayerDispatchFailure(
      'player.selectAudio',
      requestId,
      new Error('Player snapshot request id is unavailable.'),
    );
    return;
  }
  try {
    await window.lineupDesktop.player.dispatch({
      intent: 'player.selectAudio',
      requestId,
      payload: { trackId, snapshotRequestId },
    });
  } catch (error: unknown) {
    recordPlayerDispatchFailure('player.selectAudio', requestId, error);
  }
}

export async function selectSubtitleTrack(
  trackId: string | null,
  context: PlayerOverlayActionContext,
): Promise<void> {
  const requestId = `select-subtitle-${Date.now()}`;
  const playerSnapshot = context.getPlayerSnapshot();
  const snapshotRequestId = playerSnapshot.requestId;
  if (snapshotRequestId === null) {
    recordPlayerDispatchFailure(
      'player.selectSubtitle',
      requestId,
      new Error('Player snapshot request id is unavailable.'),
    );
    return;
  }
  try {
    await window.lineupDesktop.player.dispatch({
      intent: 'player.selectSubtitle',
      requestId,
      payload: { trackId, snapshotRequestId },
    });
  } catch (error: unknown) {
    recordPlayerDispatchFailure('player.selectSubtitle', requestId, error);
  }
}

function recordPlayerDispatchFailure(operation: string, requestId: string, error: unknown): void {
  recordRendererBridgeFailure(
    window.lineupDesktop.diagnostics.recordRendererEvent,
    'player.dispatch',
    summarizeRendererBridgeError(error),
    { operation, requestId },
  );
}

export function applyOverlayAction(
  action: PlayerOverlayActionId,
  context: PlayerOverlayActionContext,
): void {
  const playerSnapshot = context.getPlayerSnapshot();
  const presentationFixtures = context.getPresentationFixtures();
  const focusRegistry = context.getFocusRegistry();

  if (action.startsWith('channelDigit')) {
    if (channelCommitTimeoutId !== null) {
      window.clearTimeout(channelCommitTimeoutId);
    }
    channelCommitTimeoutId = window.setTimeout(() => {
      channelCommitTimeoutId = null;
      applyOverlayAction('commitChannelNumber', context);
    }, 2500);
  } else if (
    action === 'commitChannelNumber' ||
    action === 'clearChannelNumber' ||
    action === 'closeTopOverlay'
  ) {
    if (channelCommitTimeoutId !== null) {
      window.clearTimeout(channelCommitTimeoutId);
      channelCommitTimeoutId = null;
    }
  }

  if (action === 'volumeUp' || action === 'volumeDown') {
    const currentVolume = playerSnapshot.volume;
    const nextVolume = action === 'volumeUp'
      ? Math.min(1, Math.round((currentVolume + 0.1) * 10) / 10)
      : Math.max(0, Math.round((currentVolume - 0.1) * 10) / 10);
    const requestId = `volume-change-${Date.now()}`;
    void window.lineupDesktop.player.dispatch({
      intent: 'player.setVolume',
      requestId,
      payload: { volume: nextVolume },
    }).catch((error: unknown) => recordPlayerDispatchFailure('player.setVolume', requestId, error));
  } else if (action === 'toggleMute') {
    const requestId = `mute-change-${Date.now()}`;
    void window.lineupDesktop.player.dispatch({
      intent: 'player.setMute',
      requestId,
      payload: { muted: !playerSnapshot.muted },
    }).catch((error: unknown) => recordPlayerDispatchFailure('player.setMute', requestId, error));
  } else if (action === 'cycleAudioTrack') {
    const audioTracks = playerSnapshot.tracks.filter((t) => t.kind === 'audio' && t.available);
    if (audioTracks.length > 0) {
      const selectedAudioIndex = audioTracks.findIndex((t) => t.selected);
      const nextAudioTrack = audioTracks[(selectedAudioIndex + 1) % audioTracks.length];
      if (nextAudioTrack) {
        void selectAudioTrack(nextAudioTrack.id, context);
      }
    }
  } else if (action === 'cycleSubtitleTrack') {
    const subtitleTracks = playerSnapshot.tracks.filter((t) => t.kind === 'subtitle' && t.available);
    const subtitleOptions: (string | null)[] = [null, ...subtitleTracks.map((t) => t.id)];
    const currentSub = playerSnapshot.selectedSubtitleTrackId;
    const currentIndex = subtitleOptions.indexOf(currentSub);
    const nextSub = subtitleOptions[(currentIndex + 1) % subtitleOptions.length];
    void selectSubtitleTrack(nextSub, context);
  }

  const nextState = applyPlayerOverlayAction(
    context.getOverlayState(),
    action,
    Date.now(),
    presentationFixtures.overlays,
  );
  context.setOverlayState(nextState);

  const view = createPlayerOverlayView(nextState, {
    ...presentationFixtures.overlays,
    playerSnapshot,
  });
  const updatedFocus = focusRegistry.focusTarget(
    context.getFocusState(),
    resolvePlayerOverlayFocusId(view),
  ).state;
  context.setFocusState(updatedFocus);
  context.renderApp();
}
