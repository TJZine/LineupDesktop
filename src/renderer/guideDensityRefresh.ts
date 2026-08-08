import type { AppRouteId } from './navigation.js';

export interface GuideDensityRefreshLatch {
  noteChange(): void;
  hasPending(): boolean;
  consume(loading: boolean, route: AppRouteId): boolean;
}

export function createGuideDensityRefreshLatch(): GuideDensityRefreshLatch {
  let pending = false;
  return {
    noteChange: () => {
      pending = true;
    },
    hasPending: () => pending,
    consume: (loading, route) => {
      if (loading || !pending) return false;
      pending = false;
      return route === 'guide' || route === 'player';
    },
  };
}
