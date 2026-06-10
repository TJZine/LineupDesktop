import type { PlayerSnapshot } from '../contracts/player.js';
import {
  DEFAULT_EPG_PRESENTATION_SOURCE,
  type EpgPresentationSource,
} from './epg.js';
import {
  DEFAULT_PLAYER_OVERLAY_PRESENTATION,
  type PlayerOverlayPresentationSource,
} from './overlays.js';

export interface RendererPresentationFixtures {
  guide: EpgPresentationSource;
  overlays: PlayerOverlayPresentationSource;
  playerSnapshot: PlayerSnapshot;
}

export function createRendererPresentationFixtures(): RendererPresentationFixtures {
  return {
    guide: DEFAULT_EPG_PRESENTATION_SOURCE,
    overlays: DEFAULT_PLAYER_OVERLAY_PRESENTATION,
    playerSnapshot: DEFAULT_PLAYER_OVERLAY_PRESENTATION.playerSnapshot,
  };
}
