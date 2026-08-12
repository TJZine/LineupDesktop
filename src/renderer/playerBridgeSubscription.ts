import type { PlayerEvent, PlayerSnapshot } from '../contracts/player.js';
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
  onSnapshot?(snapshot: PlayerSnapshot, authoritative: boolean, explicitTrackList?: boolean): void;
  onEvent?(event: PlayerEvent): void;
  render(): void;
  renderProgress(): void;
}

export interface PlayerBridgeSubscription {
  initializeSnapshot(): Promise<void>;
  unsubscribe(): void;
}

export function subscribePlayerBridge(
  options: PlayerBridgeSubscriptionOptions,
): PlayerBridgeSubscription {
  let active = true;
  let projectionGeneration = 0;
  const project = (
    snapshot: PlayerSnapshot,
    authoritative: boolean,
    explicitTrackList = false,
    render: () => void = options.render,
  ): void => {
    if (!active) return;
    projectionGeneration += 1;
    options.setSnapshot(snapshot);
    options.onSnapshot?.(snapshot, authoritative, explicitTrackList);
    render();
  };

  const unsubscribeBridge = options.player.onEvent((event) => {
    if (!active) return;
    options.onEvent?.(event);
    const snapshot = options.getSnapshot();
    if (event.event === 'state.changed') {
      project(event.snapshot, true);
      return;
    }
    if (event.event === 'command.settled' || event.event === 'warning' || event.event === 'error') {
      return;
    }
    if (event.requestId !== snapshot.requestId) return;
    switch (event.event) {
      case 'time.updated':
        project(
          { ...snapshot, positionMs: event.positionMs, durationMs: event.durationMs },
          false,
          false,
          options.renderProgress,
        );
        return;
      case 'buffer.updated':
        project({ ...snapshot, bufferedRanges: event.bufferedRanges }, false);
        return;
      case 'media.loaded':
        project({ ...snapshot, media: event.media, durationMs: event.durationMs }, false);
        return;
      case 'tracks.changed':
        project({ ...snapshot, tracks: event.tracks }, false, true);
        return;
      case 'track.selection.changed':
        project({
          ...snapshot,
          selectedAudioTrackId: event.audioTrackId,
          selectedSubtitleTrackId: event.subtitleTrackId,
          selectedVideoTrackId: event.videoTrackId,
        }, false);
        return;
      case 'quality.changed':
        project({ ...snapshot, quality: event.quality }, false);
        return;
      case 'ended':
        project({ ...snapshot, status: 'ended', playing: false }, false);
        return;
      default: {
        const exhaustive: never = event;
        return exhaustive;
      }
    }
  });

  return {
    async initializeSnapshot(): Promise<void> {
      const startGeneration = projectionGeneration;
      try {
        const result = await options.player.getSnapshot();
        if (!active || projectionGeneration !== startGeneration) return;
        if (result.ok) {
          project(result.value, true);
          return;
        }
        recordRendererBridgeFailure(
          options.diagnostics.recordRendererEvent,
          'player.getSnapshot',
          result.error.message,
          {},
        );
      } catch (error: unknown) {
        if (!active || projectionGeneration !== startGeneration) return;
        recordRendererBridgeFailure(
          options.diagnostics.recordRendererEvent,
          'player.getSnapshot',
          summarizeRendererBridgeError(error),
          {},
        );
      }
    },
    unsubscribe(): void {
      if (!active) return;
      active = false;
      projectionGeneration += 1;
      unsubscribeBridge();
    },
  };
}
