import type {
  CustomChannelDraftInput,
  CustomChannelDraftValidationSummary,
  CustomChannelMediaMetadata,
  CustomChannelMediaPage,
  CustomChannelSnapshot,
} from '../../contracts/customChannels.js';
import type { LineupDesktopPreloadApi } from '../../contracts/shell.js';
import {
  addMediaCardToDraft,
  createCustomChannelOperationOwner,
  filterForAction,
  mediaTypesForFilter,
  normalizeDraftForSave,
  removeDraftItem,
  reorderChannel,
  type CustomChannelOperationKind,
} from './operationOwner.js';

export const CUSTOM_CHANNEL_ACTIONS = [
  'loadSnapshot',
  'browseSource',
  'searchMedia',
  'clearSearch',
  'toggleDraftHidden',
  'setFilterAll',
  'setFilterMovies',
  'setFilterEpisodes',
  'saveDraft',
  'addMedia',
  'openMetadata',
  'closeMetadata',
  'removeDraftItem',
  'duplicateChannel',
  'requestDeleteChannel',
  'confirmDeleteChannel',
  'toggleChannelVisibility',
  'moveChannelUp',
  'moveChannelDown',
] as const;

export type CustomChannelActionId = (typeof CUSTOM_CHANNEL_ACTIONS)[number];
export type CustomChannelActionOutcome = 'succeeded' | 'failed' | 'skipped' | 'stale';

export interface CustomChannelRendererState {
  snapshot: CustomChannelSnapshot | null;
  mediaPage: CustomChannelMediaPage | null;
  metadata: CustomChannelMediaMetadata | null;
  draft: CustomChannelDraftInput;
  validation: CustomChannelDraftValidationSummary | null;
  pending: boolean;
  mediaPending: boolean;
  metadataPending: boolean;
  lastError: string | null;
  query: string;
  mediaTypeFilter: 'all' | 'movies' | 'episodes';
  deleteConfirmationChannelId: string | null;
  lastSavedChannelId: string | null;
  pendingAction: CustomChannelOperationKind | null;
  pendingChannelId: string | null;
}

export interface CustomChannelController {
  getState(): CustomChannelRendererState;
  loadSnapshot(): Promise<CustomChannelActionOutcome>;
  browseSource(sourceId: string | null): Promise<CustomChannelActionOutcome>;
  searchMedia(sourceId: string | null): Promise<CustomChannelActionOutcome>;
  clearSearch(): void;
  clearMediaForSourceChange(): void;
  invalidateOperations(): void;
  startBlankDraft(): void;
  cancelDraft(): void;
  cancelDeleteConfirmation(): void;
  setDraftName(name: string): void;
  setDraftNumber(numberText: string): void;
  setSearchQuery(query: string): void;
  applyAction(action: CustomChannelActionId, detail?: string): Promise<CustomChannelActionOutcome>;
  handleBack(): boolean;
}

const DEFAULT_PAGE_LIMIT = 24;

export function createCustomChannelController(input: {
  bridge: LineupDesktopPreloadApi['customChannels'];
  onStateChanged(): void;
}): CustomChannelController {
  let state: CustomChannelRendererState = createInitialState();
  const operations = createCustomChannelOperationOwner();

  const setState = (next: CustomChannelRendererState): void => {
    state = next;
    input.onStateChanged();
  };

  const runOperation = async (
    kind: CustomChannelOperationKind,
    detail: string | undefined,
    operation: () => Promise<CustomChannelRendererState>,
    successful?: (next: CustomChannelRendererState) => boolean,
  ): Promise<CustomChannelActionOutcome> => {
    if (state.pending) return 'skipped';
    const operationId = operations.begin(kind, detail);
    setState({ ...state, pending: true, pendingAction: kind, pendingChannelId: detail ?? null, lastError: null });
    try {
      const next = await operation();
      if (!operations.isCurrent(operationId)) return 'stale';
      operations.clear(operationId);
      setState({ ...next, pending: false, pendingAction: null, pendingChannelId: null });
      return (successful?.(next) ?? next.lastError === null) ? 'succeeded' : 'failed';
    } catch {
      if (!operations.isCurrent(operationId)) return 'stale';
      operations.clear(operationId);
      setState({ ...state, pending: false, pendingAction: null, pendingChannelId: null, lastError: 'Custom channel action failed. Try again.' });
      return 'failed';
    }
  };

  const runMediaOperation = async (
    operation: () => Promise<CustomChannelRendererState>,
  ): Promise<CustomChannelActionOutcome> => {
    const operationId = operations.beginMedia();
    setState({ ...state, mediaPending: true, lastError: null });
    try {
      const next = await operation();
      if (!operations.isCurrentMedia(operationId)) return 'stale';
      setState({ ...next, mediaPending: false });
      return next.lastError === null ? 'succeeded' : 'failed';
    } catch {
      if (!operations.isCurrentMedia(operationId)) return 'stale';
      setState({ ...state, mediaPending: false, lastError: 'Media lookup failed. Try again.' });
      return 'failed';
    }
  };

  const runMetadataOperation = async (
    operation: () => Promise<CustomChannelRendererState>,
  ): Promise<CustomChannelActionOutcome> => {
    const operationId = operations.beginMetadata();
    setState({ ...state, metadataPending: true, lastError: null });
    try {
      const next = await operation();
      if (!operations.isCurrentMetadata(operationId)) return 'stale';
      setState({ ...next, metadataPending: false });
      return next.lastError === null ? 'succeeded' : 'failed';
    } catch {
      if (!operations.isCurrentMetadata(operationId)) return 'stale';
      setState({ ...state, metadataPending: false, lastError: 'Media details failed to load. Try again.' });
      return 'failed';
    }
  };

  const invalidateMediaOperations = (): void => {
    operations.invalidateMedia();
  };

  return {
    getState: () => state,
    loadSnapshot: () => runOperation('snapshot', undefined, async () => applySnapshotResult(state, await input.bridge.getSnapshot())),
    browseSource: async (sourceId) => {
      if (sourceId === null) {
        setState({ ...state, mediaPage: null, lastError: 'Choose a library before browsing media.' });
        return 'failed';
      }
      return runMediaOperation(async () =>
        applyMediaResult(state, await input.bridge.listMedia({
          sourceType: 'library',
          sourceId,
          limit: DEFAULT_PAGE_LIMIT,
          mediaTypes: mediaTypesForFilter(state.mediaTypeFilter),
          draftContent: state.draft.content,
        }))
      );
    },
    searchMedia: async (sourceId) => {
      const query = state.query.trim();
      if (query.length === 0) {
        setState({ ...state, lastError: 'Enter a search term before searching media.' });
        return 'failed';
      }
      return runMediaOperation(async () =>
        applyMediaResult(state, await input.bridge.listMedia({
          sourceType: 'search',
          ...(sourceId === null ? {} : { sourceId }),
          query,
          limit: DEFAULT_PAGE_LIMIT,
          mediaTypes: mediaTypesForFilter(state.mediaTypeFilter),
          draftContent: state.draft.content,
        }))
      );
    },
    clearSearch: () => {
      invalidateMediaOperations();
      setState({ ...state, query: '', mediaPage: null, metadata: null, mediaPending: false, metadataPending: false, lastError: null });
    },
    clearMediaForSourceChange: () => {
      invalidateMediaOperations();
      setState({
        ...state,
        query: '',
        mediaPage: null,
        metadata: null,
        draft: createDraftFromSnapshotOrInitial(state.snapshot),
        validation: null,
        mediaPending: false,
        metadataPending: false,
        lastError: null,
        lastSavedChannelId: null,
      });
    },
    invalidateOperations: () => {
      operations.invalidateAll();
      setState({
        ...state,
        pending: false,
        mediaPending: false,
        metadataPending: false,
        pendingAction: null,
        pendingChannelId: null,
      });
    },
    startBlankDraft: () => {
      operations.invalidateMedia();
      setState({
        ...state,
        draft: createDraftFromSnapshotOrInitial(state.snapshot),
        validation: null,
        mediaPage: null,
        metadata: null,
        query: '',
        lastError: null,
        lastSavedChannelId: null,
      });
    },
    cancelDraft: () => {
      operations.invalidateMedia();
      setState({
        ...state,
        draft: createDraftFromSnapshotOrInitial(state.snapshot),
        validation: null,
        mediaPage: null,
        metadata: null,
        query: '',
        lastError: null,
        lastSavedChannelId: null,
      });
    },
    cancelDeleteConfirmation: () => {
      setState({ ...state, deleteConfirmationChannelId: null, lastError: null });
    },
    setDraftName: (name) => {
      setState({
        ...state,
        draft: { ...state.draft, name: name.slice(0, 120) },
        validation: null,
        lastSavedChannelId: null,
      });
    },
    setDraftNumber: (numberText) => {
      const number = Number.parseInt(numberText, 10);
      setState({
        ...state,
        draft: {
          ...state.draft,
          number: Number.isFinite(number) ? number : state.draft.number,
        },
        validation: null,
        lastSavedChannelId: null,
      });
    },
    setSearchQuery: (query) => {
      invalidateMediaOperations();
      setState({
        ...state,
        query: query.slice(0, 128),
        mediaPage: null,
        metadata: null,
        mediaPending: false,
        metadataPending: false,
      });
    },
    applyAction: async (action, detail) => {
      switch (action) {
        case 'loadSnapshot':
          return runOperation('snapshot', undefined, async () => applySnapshotResult(state, await input.bridge.getSnapshot()));
        case 'toggleDraftHidden':
          setState({
            ...state,
            draft: { ...state.draft, hidden: !state.draft.hidden },
            lastSavedChannelId: null,
          });
          return 'succeeded';
        case 'setFilterAll':
        case 'setFilterMovies':
        case 'setFilterEpisodes':
          invalidateMediaOperations();
          setState({
            ...state,
            mediaTypeFilter: filterForAction(action),
            mediaPage: null,
            metadata: null,
            mediaPending: false,
            metadataPending: false,
            lastError: null,
          });
          return 'succeeded';
        case 'saveDraft':
          return runOperation('save', undefined, async () => {
            const draft = normalizeDraftForSave(state.draft);
            const validation = await input.bridge.validateDraft(draft);
            if (!validation.ok) return { ...state, lastError: validation.error.message };
            if (!validation.value.valid) {
              return {
                ...state,
                validation: validation.value,
                lastError: null,
              };
            }
            const result = await input.bridge.saveDraft(draft);
            if (!result.ok) return { ...state, lastError: result.error.message };
            return {
              ...state,
              snapshot: result.value.snapshot,
              validation: validation.value,
              draft: createDraftFromSnapshot(result.value.snapshot),
              deleteConfirmationChannelId: null,
              lastError: null,
              lastSavedChannelId: result.value.changedChannelId,
            };
          }, (next) => next.lastError === null && next.validation?.valid === true);
        case 'addMedia':
          if (detail === undefined) return 'skipped';
          setState(addMediaCardToDraft(state, detail));
          return state.lastError === null ? 'succeeded' : 'failed';
        case 'openMetadata':
          if (detail !== undefined) {
            return runMetadataOperation(async () =>
              applyMetadataResult(state, await input.bridge.getMediaMetadata({ ratingKey: detail }))
            );
          }
          return 'skipped';
        case 'closeMetadata':
          operations.invalidateMetadata();
          setState({ ...state, metadata: null, metadataPending: false, lastError: null });
          return 'succeeded';
        case 'removeDraftItem':
          if (detail === undefined) return 'skipped';
          setState(removeDraftItem(state, detail));
          return 'succeeded';
        case 'duplicateChannel':
          if (detail !== undefined) {
            return runOperation('duplicate', detail, async () => {
              const result = await input.bridge.duplicateChannelDraft({ channelId: detail });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return {
                ...state,
                draft: result.value.draft,
                validation: result.value.validation,
                lastError: null,
                lastSavedChannelId: null,
              };
            });
          }
          return 'skipped';
        case 'requestDeleteChannel':
          if (detail === undefined) return 'skipped';
          setState({ ...state, deleteConfirmationChannelId: detail ?? null, lastError: null });
          return 'succeeded';
        case 'confirmDeleteChannel':
          if (detail !== undefined) {
            return runOperation('delete', detail, async () => {
              const result = await input.bridge.deleteChannel({ channelId: detail, confirm: true });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return {
                ...state,
                snapshot: result.value.snapshot,
                deleteConfirmationChannelId: null,
                lastError: null,
              };
            }, (next) => next.lastError === null && next.deleteConfirmationChannelId === null);
          }
          return 'skipped';
        case 'toggleChannelVisibility':
          if (detail !== undefined) {
            const channel = state.snapshot?.channels.find((candidate) => candidate.id === detail);
            if (channel === undefined) return 'skipped';
            return runOperation('visibility', detail, async () => {
              const result = await input.bridge.setChannelVisibility({
                channelId: detail,
                hidden: !channel.hidden,
              });
              if (!result.ok) return { ...state, lastError: result.error.message };
              return { ...state, snapshot: result.value.snapshot, lastError: null };
            });
          }
          return 'skipped';
        case 'moveChannelUp':
        case 'moveChannelDown':
          if (detail !== undefined) {
            return runOperation('reorder', detail, async () => reorderChannel(state, input.bridge, detail, action === 'moveChannelUp' ? -1 : 1), (next) => next !== state && next.lastError === null);
          }
          return 'skipped';
        case 'browseSource':
        case 'searchMedia':
        case 'clearSearch':
          return 'skipped';
      }
    },
    handleBack: () => {
      if (state.metadata !== null || state.metadataPending) {
        operations.invalidateMetadata();
        setState({ ...state, metadata: null, metadataPending: false });
        return true;
      }
      if (state.deleteConfirmationChannelId !== null) {
        setState({ ...state, deleteConfirmationChannelId: null });
        return true;
      }
      if (state.query.length > 0 || state.mediaPage !== null || state.lastError !== null) {
        invalidateMediaOperations();
        setState({ ...state, query: '', mediaPage: null, mediaPending: false, lastError: null });
        return true;
      }
      return false;
    },
  };
}

function createInitialState(): CustomChannelRendererState {
  return {
    snapshot: null,
    mediaPage: null,
    metadata: null,
    draft: {
      number: 1,
      name: 'Custom Channel',
      hidden: false,
      content: [],
      playbackMode: 'sequential',
    },
    validation: null,
    pending: false,
    mediaPending: false,
    metadataPending: false,
    lastError: null,
    query: '',
    mediaTypeFilter: 'all',
    deleteConfirmationChannelId: null,
    lastSavedChannelId: null,
    pendingAction: null,
    pendingChannelId: null,
  };
}

function createDraftFromSnapshotOrInitial(snapshot: CustomChannelSnapshot | null): CustomChannelDraftInput {
  return snapshot === null ? createInitialState().draft : createDraftFromSnapshot(snapshot);
}

function createDraftFromSnapshot(snapshot: CustomChannelSnapshot): CustomChannelDraftInput {
  return {
    number: snapshot.nextAvailableNumber ?? Math.min(snapshot.channels.length + 1, snapshot.maxChannels),
    name: 'Custom Channel',
    hidden: false,
    content: [],
    playbackMode: 'sequential',
  };
}

function applySnapshotResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['getSnapshot']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, lastError: result.error.message };
  return {
    ...current,
    snapshot: result.value,
    draft: current.draft.content.length === 0 ? createDraftFromSnapshot(result.value) : current.draft,
    lastError: null,
  };
}

function applyMediaResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['listMedia']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, mediaPage: null, lastError: result.error.message };
  return { ...current, mediaPage: result.value, lastError: null };
}

function applyMetadataResult(
  current: CustomChannelRendererState,
  result: Awaited<ReturnType<LineupDesktopPreloadApi['customChannels']['getMediaMetadata']>>,
): CustomChannelRendererState {
  if (!result.ok) return { ...current, metadata: null, lastError: result.error.message };
  return { ...current, metadata: result.value, lastError: null };
}
