import type { PlayerSnapshot } from '../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../contracts/shell.js';
import {
  recordRendererBridgeFailure,
  summarizeRendererBridgeError,
} from './rendererBridgeFailures.js';

export interface PlayerBridgeSubscriptionOptions {
  player: LineupDesktopPreloadApi['player'];
  diagnostics: LineupDesktopPreloadApi['diagnostics'];
  getSnapshot(): PlayerSnapshot;
  setSnapshot(snapshot: PlayerSnapshot): void;
  render(): void;
}

export interface PlayerBridgeSubscription {
  initializeSnapshot(): Promise<void>;
  unsubscribe(): void;
}

export function subscribePlayerBridge(
  options: PlayerBridgeSubscriptionOptions,
): PlayerBridgeSubscription {
  const unsubscribe = options.player.onEvent((event) => {
    const snapshot = options.getSnapshot();
    if (event.event === 'state.changed') {
      options.setSnapshot(event.snapshot);
    } else if (event.event === 'time.updated') {
      options.setSnapshot({
        ...snapshot,
        positionMs: event.positionMs,
        durationMs: event.durationMs,
      });
    } else if (event.event === 'buffer.updated') {
      options.setSnapshot({
        ...snapshot,
        bufferedRanges: event.bufferedRanges,
      });
    } else if (event.event === 'media.loaded') {
      options.setSnapshot({
        ...snapshot,
        status: 'ready',
        media: event.media,
        durationMs: event.durationMs,
      });
    } else if (event.event === 'tracks.changed') {
      options.setSnapshot({
        ...snapshot,
        tracks: event.tracks,
      });
    } else if (event.event === 'track.selection.changed') {
      options.setSnapshot({
        ...snapshot,
        selectedAudioTrackId: event.audioTrackId,
        selectedSubtitleTrackId: event.subtitleTrackId,
        selectedVideoTrackId: event.videoTrackId,
      });
    } else if (event.event === 'ended') {
      options.setSnapshot({
        ...snapshot,
        status: 'ended',
        playing: false,
      });
    } else if (event.event === 'error') {
      options.setSnapshot({
        ...snapshot,
        status: 'error',
        playing: false,
        lastError: event.error,
      });
    }
    options.render();
  });

  return {
    initializeSnapshot: () => initializePlayerSnapshot(options),
    unsubscribe,
  };
}

async function initializePlayerSnapshot(options: PlayerBridgeSubscriptionOptions): Promise<void> {
  try {
    const result = await options.player.getSnapshot();
    if (result.ok) {
      options.setSnapshot(result.value);
      options.render();
      return;
    }
    recordRendererBridgeFailure(
      options.diagnostics.recordRendererEvent,
      'player.getSnapshot',
      result.error.message,
      {},
    );
  } catch (error: unknown) {
    recordRendererBridgeFailure(
      options.diagnostics.recordRendererEvent,
      'player.getSnapshot',
      summarizeRendererBridgeError(error),
      {},
    );
  }
}
