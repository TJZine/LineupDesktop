import type { LineupDesktopPreloadApi } from '../contracts/shell.js';

declare global {
  interface Window {
    lineupDesktop: LineupDesktopPreloadApi;
  }
}

export {};
