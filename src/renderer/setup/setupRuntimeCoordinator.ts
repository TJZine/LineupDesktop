import type { PlexRuntimeRendererState } from '../plexRuntimeState.js';

export type SetupLibraryLoadState = 'idle' | 'loading' | 'ready' | 'empty' | 'error';
export type SetupPreviewState = 'collapsed' | 'loading' | 'ready' | 'empty' | 'items-error' | 'metadata-error';

export interface SetupRuntimeState {
  library: SetupLibraryLoadState;
  preview: SetupPreviewState;
  serverId: string | null;
  previewSectionId: string | null;
  previewRatingKey: string | null;
}

export interface SetupRuntimeCoordinator {
  getState(): SetupRuntimeState;
  enterLibrary(serverId: string | null, plexState: PlexRuntimeRendererState): Promise<void>;
  retryLibraries(serverId: string | null): Promise<void>;
  loadPreview(sectionId: string): Promise<void>;
  retryPreview(): Promise<void>;
  loadPreviewMetadata(ratingKey: string): Promise<void>;
  collapsePreview(): void;
  invalidate(): void;
  reconcile(plexState: PlexRuntimeRendererState): void;
}

export function createSetupRuntimeCoordinator(input: {
  getPlexState(): PlexRuntimeRendererState;
  listLibrarySections(): Promise<void>;
  listLibraryItems(sectionId: string): Promise<void>;
  getMetadata(ratingKey: string): Promise<void>;
  onStateChanged(): void;
}): SetupRuntimeCoordinator {
  let generation = 0;
  let libraryIntent = 0;
  let previewIntent = 0;
  let metadataIntent = 0;
  let libraryLoadTail = Promise.resolve();
  let itemLoadTail = Promise.resolve();
  let metadataLoadTail = Promise.resolve();
  let loadedServerId: string | null = null;
  let state: SetupRuntimeState = initialState();
  const commit = (patch: Partial<SetupRuntimeState>): void => {
    state = { ...state, ...patch };
    input.onStateChanged();
  };
  const loadLibraries = (serverId: string | null): Promise<void> => {
    if (serverId === null) return Promise.resolve();
    const currentGeneration = generation;
    const currentIntent = ++libraryIntent;
    commit({ library: 'loading', serverId });
    const operation = libraryLoadTail.then(async () => {
      if (currentGeneration !== generation || currentIntent !== libraryIntent || state.serverId !== serverId) return;
      await input.listLibrarySections();
      if (currentGeneration !== generation || currentIntent !== libraryIntent || state.serverId !== serverId) return;
      const plex = input.getPlexState();
      if (plex.errorText !== null) {
        loadedServerId = null;
        commit({ library: 'error' });
        return;
      }
      loadedServerId = serverId;
      const eligible = plex.snapshot?.library.sections.some((section) => section.type === 'movie' || section.type === 'show') === true;
      commit({ library: eligible ? 'ready' : 'empty' });
    }).catch(() => {
      if (currentGeneration !== generation || currentIntent !== libraryIntent || state.serverId !== serverId) return;
      loadedServerId = null;
      commit({ library: 'error' });
    });
    libraryLoadTail = operation;
    return operation;
  };
  const loadItems = (sectionId: string): Promise<void> => {
    const currentGeneration = generation;
    const currentIntent = ++previewIntent;
    const currentServerId = state.serverId;
    ++metadataIntent;
    commit({ preview: 'loading', previewSectionId: sectionId, previewRatingKey: null });
    const operation = itemLoadTail.then(async () => {
      if (currentGeneration !== generation || currentIntent !== previewIntent || state.previewSectionId !== sectionId || state.serverId !== currentServerId) return;
      await input.listLibraryItems(sectionId);
      if (currentGeneration !== generation || currentIntent !== previewIntent || state.previewSectionId !== sectionId || state.serverId !== currentServerId) return;
      const plex = input.getPlexState();
      if (plex.errorText !== null) commit({ preview: 'items-error' });
      else if (plex.selectedSectionId !== sectionId || plex.snapshot?.library.selectedSectionId !== sectionId) commit({ preview: 'items-error' });
      else commit({ preview: plex.snapshot.library.items.length === 0 ? 'empty' : 'ready' });
    }).catch(() => {
      if (currentGeneration !== generation || currentIntent !== previewIntent || state.previewSectionId !== sectionId || state.serverId !== currentServerId) return;
      commit({ preview: 'items-error' });
    });
    itemLoadTail = operation;
    return operation;
  };
  return {
    getState: () => state,
    async enterLibrary(serverId, plexState) {
      if (serverId === null) return;
      const hasCurrent = loadedServerId === serverId
        && plexState.snapshot?.library.status === 'ready';
      if (hasCurrent) {
        const eligible = plexState.snapshot?.library.sections.some((section) => section.type === 'movie' || section.type === 'show') === true;
        commit({ serverId, library: eligible ? 'ready' : 'empty' });
        return;
      }
      await loadLibraries(serverId);
    },
    async retryLibraries(serverId) {
      loadedServerId = null;
      ++libraryIntent;
      await loadLibraries(serverId);
    },
    loadPreview: loadItems,
    async retryPreview() {
      if (state.preview === 'metadata-error' && state.previewRatingKey !== null) {
        await this.loadPreviewMetadata(state.previewRatingKey);
      } else if (state.previewSectionId !== null) await loadItems(state.previewSectionId);
    },
    async loadPreviewMetadata(ratingKey) {
      const currentGeneration = generation;
      const currentIntent = ++metadataIntent;
      const currentServerId = state.serverId;
      const currentSectionId = state.previewSectionId;
      commit({ preview: 'loading', previewRatingKey: ratingKey });
      const operation = metadataLoadTail.then(async () => {
        if (currentGeneration !== generation || currentIntent !== metadataIntent || state.previewRatingKey !== ratingKey || state.serverId !== currentServerId || state.previewSectionId !== currentSectionId) return;
        await input.getMetadata(ratingKey);
        if (currentGeneration !== generation || currentIntent !== metadataIntent || state.previewRatingKey !== ratingKey || state.serverId !== currentServerId || state.previewSectionId !== currentSectionId) return;
        commit({ preview: input.getPlexState().errorText === null ? 'ready' : 'metadata-error' });
      }).catch(() => {
        if (currentGeneration !== generation || currentIntent !== metadataIntent || state.previewRatingKey !== ratingKey || state.serverId !== currentServerId || state.previewSectionId !== currentSectionId) return;
        commit({ preview: 'metadata-error' });
      });
      metadataLoadTail = operation;
      await operation;
    },
    collapsePreview() {
      ++previewIntent;
      ++metadataIntent;
      commit({ preview: 'collapsed', previewRatingKey: null });
    },
    invalidate() {
      ++generation;
      ++libraryIntent;
      ++previewIntent;
      ++metadataIntent;
      loadedServerId = null;
      state = initialState();
      input.onStateChanged();
    },
    reconcile(plexState) {
      if (state.library === 'loading' || state.preview === 'loading') return;
      if (state.serverId !== null && plexState.selectedServerId !== state.serverId) this.invalidate();
    },
  };
}

function initialState(): SetupRuntimeState {
  return {
    library: 'idle',
    preview: 'collapsed',
    serverId: null,
    previewSectionId: null,
    previewRatingKey: null,
  };
}
