import type { PlayerSnapshot } from '../../contracts/player.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import type { AppRouteId } from '../navigation.js';

export interface SettingsPlaybackLifecycle {
  routeChanged(previousRoute: AppRouteId, nextRoute: AppRouteId, keepRunning: boolean): Promise<void>;
  observeSnapshot(snapshot: PlayerSnapshot): void;
  cleanup(): void;
}

export function createSettingsPlaybackLifecycle(options: {
  player: Pick<LineupDesktopPreloadApi['player'], 'dispatch'>;
  getSnapshot(): PlayerSnapshot;
}): SettingsPlaybackLifecycle {
  let active = true;
  let generation = 0;
  let sequence = 0;
  let pausedRequestId: string | null = null;

  const dispatch = async (
    intent: 'player.pauseIfCurrent' | 'player.playIfCurrent',
    ownedRequestId: string,
    operationGeneration: number,
  ): Promise<PlayerSnapshot | null> => {
    const requestId = `settings-playback-${intent === 'player.pauseIfCurrent' ? 'pause' : 'resume'}-${String(++sequence)}`;
    const result = await options.player.dispatch({
      intent,
      requestId,
      payload: { snapshotRequestId: ownedRequestId },
    }).catch(() => null);
    if (!active || operationGeneration !== generation || result === null || !result.ok || !result.value.accepted) {
      return null;
    }
    const currentSnapshot = options.getSnapshot();
    return result.value.snapshot.requestId === ownedRequestId
      && currentSnapshot.requestId === ownedRequestId
      ? result.value.snapshot
      : null;
  };

  return {
    async routeChanged(previousRoute, nextRoute, keepRunning): Promise<void> {
      const operationGeneration = ++generation;
      if (nextRoute === 'settings' && previousRoute !== 'settings') {
        pausedRequestId = null;
        if (keepRunning) return;
        const snapshot = options.getSnapshot();
        if (snapshot.requestId === null || snapshot.status !== 'playing' || !snapshot.playing) return;
        const paused = await dispatch('player.pauseIfCurrent', snapshot.requestId, operationGeneration);
        if (paused?.status === 'paused' && !paused.playing) pausedRequestId = snapshot.requestId;
        return;
      }
      if (previousRoute !== 'settings' || nextRoute === 'settings') return;
      const ownedRequestId = pausedRequestId;
      pausedRequestId = null;
      if (ownedRequestId === null) return;
      const snapshot = options.getSnapshot();
      if (snapshot.requestId !== ownedRequestId || snapshot.status !== 'paused' || snapshot.playing) return;
      await dispatch('player.playIfCurrent', ownedRequestId, operationGeneration);
    },
    observeSnapshot(snapshot): void {
      if (
        pausedRequestId !== null
        && (snapshot.requestId !== pausedRequestId || snapshot.status !== 'paused' || snapshot.playing)
      ) pausedRequestId = null;
    },
    cleanup(): void {
      active = false;
      generation += 1;
      pausedRequestId = null;
    },
  };
}
