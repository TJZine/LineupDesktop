import type { IpcMainInvokeEvent, WebContents } from 'electron';
import { randomBytes } from 'node:crypto';

import { redactDiagnosticText } from '../../contracts/diagnostics.js';
import type { ShellMode } from '../../contracts/shell.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { DesktopChannelPersistenceStore } from '../persistence/desktopChannelPersistenceStore.js';
import type { ChannelPersistenceReadyCapability } from '../persistence/channelPersistenceBootstrapOwner.js';
import type { ChannelPersistenceStoragePort } from '../../domain/channel/channelPersistenceStore.js';
import { registerChannelIpcHandlers, type ChannelIpcTeardown } from './channelIpc.js';
import { ChannelRuntime } from './channelRuntime.js';
import { ChannelPersistenceStore } from '../../domain/channel/channelPersistenceStore.js';
import {
  ChannelBuilderContextEpochOwner,
  type ChannelBuilderPlexContextSource,
} from './channelBuilderContextEpochOwner.js';
import { ChannelBuilderOperationOwner } from './channelBuilderOperationOwner.js';
import { ChannelBuilderPlanningWorker } from './channelBuilderPlanningWorker.js';
import { ChannelBuilderRuntime } from './channelBuilderRuntime.js';
import { ChannelLineupMutationCoordinator } from './channelLineupMutationCoordinator.js';
import { DesktopPlexChannelBuilderFacetSource } from '../plex/desktopPlexChannelBuilderFacetSource.js';
import { registerCustomChannelIpcHandlers, type CustomChannelIpcTeardown } from './customChannelIpc.js';
import { CustomChannelMediaPicker } from './customChannelMediaPicker.js';
import { CustomChannelRuntime } from './customChannelRuntime.js';
import type { DesktopPlexRuntime } from '../plex/desktopPlexRuntime.js';
import { PlexLibraryMinimalAdapter } from './plexLibraryMinimalAdapter.js';
import { ChannelScheduler } from '../../domain/scheduler/channelScheduler.js';
import { GuideRuntime, type GuidePastItemsWindowSnapshot } from './guideRuntime.js';
import type { ChannelClock, ChannelLogger } from '../../domain/channel/interfaces.js';
import { ChannelPublicReferenceOwner } from './channelPublicReferenceOwner.js';
import { GuideArtworkOwner } from './guideArtworkOwner.js';
import type { GuideArtworkSessionGenerationOwner } from '../plex/guideArtworkSessionGenerationOwner.js';
import type { LivePlexGuideArtworkTransport } from '../plex/livePlexTransport.js';
import { DesktopGuidePreferencesStore } from './desktopGuidePreferencesStore.js';

export interface CreateChannelCompositionOptions {
  persistence:
    | Readonly<{
        kind: 'disk';
        readyCapability: ChannelPersistenceReadyCapability;
      }>
    | Readonly<{
        kind: 'memory';
        storage: ChannelPersistenceStoragePort;
      }>;
  plexRuntime: DesktopPlexRuntime;
  onChannelTuned?: (channelId: string) => void | Promise<void>;
  diagnosticEventStore?: DiagnosticEventStore;
  channelBuilderContextSource?: ChannelBuilderPlexContextSource;
  guideArtworkSessionGenerationOwner: GuideArtworkSessionGenerationOwner;
  guideArtworkTransport: LivePlexGuideArtworkTransport;
  guidePreferencesFilePath?: string;
  getPastItemsWindowSnapshot?: () => Promise<GuidePastItemsWindowSnapshot>;
}

export interface RegisterChannelCompositionIpcOptions {
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  diagnosticEventStore?: DiagnosticEventStore;
}

export type ChannelCompositionTeardown = () => Promise<void>;

export interface ChannelComposition {
  runtime: ChannelRuntime;
  guideRuntime: GuideRuntime;
  activeChannelScheduler: ChannelScheduler;
  guideArtworkOwner: GuideArtworkOwner;
  teardown: ChannelCompositionTeardown;
}

export interface ChannelCompositionRegistration extends ChannelComposition {}

export function bindGuideArtworkOwnerToWebContents(
  webContents: Pick<WebContents, 'once'>,
  guideArtworkOwner: Pick<GuideArtworkOwner, 'dispose'>,
): void {
  webContents.once('destroyed', () => guideArtworkOwner.dispose());
}

type ChannelCompositionState = {
  customChannelRuntime: CustomChannelRuntime;
  customChannelMediaPicker: CustomChannelMediaPicker;
  channelIpcTeardown: ChannelIpcTeardown | null;
  customIpcTeardown: CustomChannelIpcTeardown | null;
  teardownPromise: Promise<void> | null;
  publicReferenceOwner: ChannelPublicReferenceOwner;
  guideArtworkOwner: GuideArtworkOwner;
  unsubscribeGuidePreferenceScope: (() => void) | null;
};

const compositionStates = new WeakMap<ChannelComposition, ChannelCompositionState>();

export function createChannelComposition(
  options: CreateChannelCompositionOptions,
): ChannelComposition {
  const clock: ChannelClock = { now: () => Date.now() };
  const sharedChannelStore =
    options.persistence.kind === 'disk'
      ? new DesktopChannelPersistenceStore({
          readyCapability: options.persistence.readyCapability,
        })
      : options.persistence.storage;
  const persistenceStore = new ChannelPersistenceStore(sharedChannelStore);
  const plexLibraryAdapter = new PlexLibraryMinimalAdapter(options.plexRuntime);
  const customChannelMediaPicker = new CustomChannelMediaPicker({
    plexRuntime: options.plexRuntime,
  });
  const activeChannelScheduler = new ChannelScheduler({ clock });
  const guideLogger = createGuideRuntimeLogger(options.diagnosticEventStore);
  const guideArtworkOwner = new GuideArtworkOwner(
    options.guideArtworkSessionGenerationOwner,
    options.guideArtworkTransport,
  );
  const guidePreferencesStore = options.guidePreferencesFilePath === undefined
    ? null
    : new DesktopGuidePreferencesStore(options.guidePreferencesFilePath);
  let guideRuntime: GuideRuntime | null = null;
  const contextOwner = new ChannelBuilderContextEpochOwner(
    options.channelBuilderContextSource ?? options.plexRuntime,
  );
  const planningWorker = new ChannelBuilderPlanningWorker();
  const operationOwner = new ChannelBuilderOperationOwner({
    randomHex128: () => randomBytes(16).toString('hex'),
    releasePlan: (planId) => contextOwner.release(planId),
  });
  const mutationCoordinator = new ChannelLineupMutationCoordinator(
    persistenceStore,
    options.guideArtworkSessionGenerationOwner,
  );
  const publicReferenceOwner = new ChannelPublicReferenceOwner();
  const builderRuntime = new ChannelBuilderRuntime({
    store: persistenceStore,
    contextOwner,
    facetSource: new DesktopPlexChannelBuilderFacetSource(contextOwner),
    planningWorker,
    operationOwner,
    mutationCoordinator,
    refreshGuide: async () => {
      if (guideRuntime === null) throw new Error('Guide runtime is unavailable.');
      await guideRuntime.refreshActiveChannelSelection();
    },
    randomHex128: () => randomBytes(16).toString('hex'),
  });
  const runtime = new ChannelRuntime({
    storage: sharedChannelStore,
    builderRuntime,
    publicReferenceOwner,
    clock,
    logger: guideLogger,
  });
  guideRuntime = new GuideRuntime({
    repository: runtime.getRepository(),
    plexLibraryAdapter,
    activeChannelScheduler,
    clock,
    onChannelTuned: typeof options.onChannelTuned === 'function' ? options.onChannelTuned : undefined,
    logger: guideLogger,
    guideArtworkOwner,
    ...(guidePreferencesStore === null ? {} : {
      preferencesStore: guidePreferencesStore,
      guideContextSource: options.plexRuntime,
      getPastItemsWindowSnapshot: options.getPastItemsWindowSnapshot,
    }),
  });
  const unsubscribeGuidePreferenceScope = guidePreferencesStore === null
    ? null
    : options.guideArtworkSessionGenerationOwner.subscribe(() => guideRuntime?.invalidatePreferenceScope());
  const customChannelRuntime = new CustomChannelRuntime({
    storage: sharedChannelStore,
    mutationCoordinator,
    clock,
    logger: guideLogger,
    onChannelsChanged: async () => {
      await guideRuntime.refreshActiveChannelSelection();
    },
  });

  const state: ChannelCompositionState = {
    customChannelRuntime,
    customChannelMediaPicker,
    channelIpcTeardown: null,
    customIpcTeardown: null,
    teardownPromise: null,
    publicReferenceOwner,
    guideArtworkOwner,
    unsubscribeGuidePreferenceScope,
  };
  const composition: ChannelComposition = {
    runtime,
    guideRuntime,
    activeChannelScheduler,
    guideArtworkOwner,
    teardown: () => teardownChannelComposition(runtime, state),
  };
  compositionStates.set(composition, state);
  return composition;
}

export function registerChannelCompositionIpc(
  composition: ChannelComposition,
  options: RegisterChannelCompositionIpcOptions,
): ChannelCompositionRegistration {
  const state = compositionStates.get(composition);
  if (
    state === undefined ||
    state.channelIpcTeardown !== null ||
    state.customIpcTeardown !== null ||
    state.teardownPromise !== null
  ) {
    throw new Error('Channel composition IPC is already registered or closed.');
  }
  state.channelIpcTeardown = registerChannelIpcHandlers({
    runtime: composition.runtime,
    guideRuntime: composition.guideRuntime,
    publicReferenceOwner: state.publicReferenceOwner,
    isAuthorizedEvent: options.isAuthorizedEvent,
    createRequestId: options.createRequestId,
  });
  state.customIpcTeardown = registerCustomChannelIpcHandlers({
    runtime: state.customChannelRuntime,
    mediaPicker: state.customChannelMediaPicker,
    isAuthorizedEvent: options.isAuthorizedEvent,
    createRequestId: options.createRequestId,
  });
  options.diagnosticEventStore?.record({
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'channel.composition.register',
    message: 'Channel setup runtime composition registered.',
    context: {
      shellMode: options.shellMode,
      storage: 'main-owned',
    },
  });

  return {
    ...composition,
  };
}

function teardownChannelComposition(
  runtime: ChannelRuntime,
  state: ChannelCompositionState,
): Promise<void> {
  state.teardownPromise ??= (async () => {
    await state.customIpcTeardown?.();
    await state.channelIpcTeardown?.();
    state.guideArtworkOwner.dispose();
    state.unsubscribeGuidePreferenceScope?.();
    runtime.shutdown();
  })();
  return state.teardownPromise;
}

function createGuideRuntimeLogger(
  diagnosticEventStore: DiagnosticEventStore | undefined,
): ChannelLogger {
  return {
    warn: (message, detail) => {
      diagnosticEventStore?.record({
        surface: 'main',
        category: 'lifecycle',
        severity: 'warning',
        status: 'observed',
        operation: 'channel.guideRuntime.warn',
        message,
        context: sanitizeChannelDiagnosticDetail(detail),
      });
    },
    error: (message, detail) => {
      diagnosticEventStore?.record({
        surface: 'main',
        category: 'lifecycle',
        severity: 'error',
        status: 'failed',
        operation: 'channel.guideRuntime.error',
        message,
        context: sanitizeChannelDiagnosticDetail(detail),
      });
    },
  };
}

export function sanitizeChannelDiagnosticDetail(detail: unknown): Record<string, unknown> {
  if (typeof detail !== 'object' || detail === null || Array.isArray(detail)) {
    return {};
  }
  return sanitizeDiagnosticRecord(detail as Record<string, unknown>, 0);
}

function sanitizeDiagnosticRecord(
  detail: Record<string, unknown>,
  depth: number,
): Record<string, unknown> {
  if (depth > 2) {
    return { summary: 'detail-depth-exceeded' };
  }
  const result: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(detail)) {
    if (isSensitiveDiagnosticKey(key)) {
      result[key] = '[redacted]';
      continue;
    }
    if (typeof value === 'string') {
      result[key] = redactDiagnosticText(value).slice(0, 2000);
    } else if (typeof value === 'number' || typeof value === 'boolean' || value === null) {
      result[key] = value;
    } else if (Array.isArray(value)) {
      result[key] = value.slice(0, 20).map((entry) => {
        if (typeof entry === 'string') {
          return redactDiagnosticText(entry).slice(0, 2000);
        }
        if (typeof entry === 'object' && entry !== null) {
          return sanitizeDiagnosticRecord(entry as Record<string, unknown>, depth + 1);
        }
        return entry;
      });
    } else if (typeof value === 'object' && value !== null) {
      result[key] = sanitizeDiagnosticRecord(value as Record<string, unknown>, depth + 1);
    }
  }
  return result;
}

function isSensitiveDiagnosticKey(key: string): boolean {
  return /token|secret|credential|password|auth|header|url|uri|path|file/i.test(key);
}
