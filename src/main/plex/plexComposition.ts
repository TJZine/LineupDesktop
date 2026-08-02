import os from 'node:os';

import type { App, IpcMainInvokeEvent } from 'electron';
import { safeStorage } from 'electron';

import type { ShellMode } from '../../contracts/shell.js';
import type { DiagnosticEventStore } from '../diagnostics/diagnosticEventStore.js';
import { resolveDesktopAppDataPaths } from '../persistence/appDataPaths.js';
import { DesktopPersistenceStore } from '../persistence/desktopPersistenceStore.js';
import { createElectronSafeStorageCodec } from '../persistence/secureStorageCodec.js';
import {
  createDesktopPlexAuthConfig,
  DesktopPlexAuthService,
} from './auth/index.js';
import { DesktopPlexCredentialStore } from './auth/desktopPlexCredentialStore.js';
import { DesktopPlexSelectedServerStore } from './discovery/desktopPlexSelectedServerStore.js';
import { DesktopPlexServerDiscovery } from './discovery/desktopPlexServerDiscovery.js';
import { readOrCreateDesktopPlexClientIdentifier } from './desktopPlexClientIdentity.js';
import { DesktopPlexRuntime } from './desktopPlexRuntime.js';
import { LivePlexTransport } from './livePlexTransport.js';
import { registerPlexIpcHandlers, type PlexIpcTeardown } from './plexIpc.js';
import { GuideArtworkSessionGenerationOwner } from './guideArtworkSessionGenerationOwner.js';

export interface CreatePlexCompositionOptions {
  app: Pick<App, 'getPath' | 'getVersion'>;
  diagnosticEventStore?: DiagnosticEventStore;
}

export interface RegisterPlexCompositionIpcOptions {
  shellMode: ShellMode;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  diagnosticEventStore?: DiagnosticEventStore;
}

export interface PlexComposition {
  runtime: DesktopPlexRuntime;
  guideArtworkSessionGenerationOwner: GuideArtworkSessionGenerationOwner;
  liveTransport: LivePlexTransport;
  teardown: () => Promise<void>;
}

export interface PlexCompositionRegistration {
  runtime: DesktopPlexRuntime;
  guideArtworkSessionGenerationOwner: GuideArtworkSessionGenerationOwner;
  liveTransport: LivePlexTransport;
  teardown: () => Promise<void>;
}

type PlexCompositionState = {
  registrationTeardown: PlexIpcTeardown | null;
  teardownPromise: Promise<void> | null;
};

const compositionStates = new WeakMap<PlexComposition, PlexCompositionState>();

export async function createPlexComposition(
  options: CreatePlexCompositionOptions,
): Promise<PlexComposition> {
  const paths = resolveDesktopAppDataPaths(options.app);
  const clientIdentifier = await readOrCreateDesktopPlexClientIdentifier(paths);
  const persistenceStore = new DesktopPersistenceStore({
    persistenceFilePath: paths.persistenceFilePath,
    secureStringCodec: createElectronSafeStorageCodec(safeStorage),
  });
  const credentialStore = new DesktopPlexCredentialStore({ persistenceStore });
  const selectedServerStore = new DesktopPlexSelectedServerStore({ persistenceStore });
  const authConfig = createDesktopPlexAuthConfig({
    clientIdentifier,
    platformVersion: os.release(),
    deviceName: 'Lineup Desktop',
  });
  const liveTransport = new LivePlexTransport({ authConfig });
  const authService = new DesktopPlexAuthService({
    config: authConfig,
    transport: liveTransport,
    credentialStore,
  });
  const serverDiscovery = new DesktopPlexServerDiscovery({
    transport: liveTransport,
    selectedServerStore,
  });
  const guideArtworkSessionGenerationOwner = new GuideArtworkSessionGenerationOwner(
    authService,
    serverDiscovery,
  );
  const runtime = new DesktopPlexRuntime({
    authService,
    credentialStore,
    serverDiscovery,
    libraryTransport: liveTransport,
    channelBuilderFacetTransport: liveTransport,
    guideArtworkSessionGenerationOwner,
    diagnosticEventStore: options.diagnosticEventStore,
  });
  const state: PlexCompositionState = {
    registrationTeardown: null,
    teardownPromise: null,
  };
  const composition: PlexComposition = {
    runtime,
    guideArtworkSessionGenerationOwner,
    liveTransport,
    teardown: () => teardownComposition(runtime, state),
  };
  compositionStates.set(composition, state);
  return composition;
}

export function registerPlexCompositionIpc(
  composition: PlexComposition,
  options: RegisterPlexCompositionIpcOptions,
): PlexCompositionRegistration {
  const state = compositionStates.get(composition);
  if (state === undefined || state.registrationTeardown !== null || state.teardownPromise !== null) {
    throw new Error('Plex composition IPC is already registered or the composition is closed.');
  }
  const teardownIpc = registerPlexIpcHandlers({
    runtime: composition.runtime,
    isAuthorizedEvent: options.isAuthorizedEvent,
    createRequestId: options.createRequestId,
  });
  let registrationTeardownPromise: Promise<void> | null = null;
  state.registrationTeardown = () => {
    registrationTeardownPromise ??= teardownIpc();
    return registrationTeardownPromise;
  };

  options.diagnosticEventStore?.record({
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'plex.composition.register',
    message: 'Plex runtime composition registered.',
    context: {
      shellMode: options.shellMode,
      storage: 'main-owned',
    },
  });

  return {
    runtime: composition.runtime,
    guideArtworkSessionGenerationOwner: composition.guideArtworkSessionGenerationOwner,
    liveTransport: composition.liveTransport,
    teardown: () => teardownComposition(composition.runtime, state),
  };
}

function teardownComposition(
  runtime: DesktopPlexRuntime,
  state: PlexCompositionState,
): Promise<void> {
  state.teardownPromise ??= (async () => {
    if (state.registrationTeardown === null) {
      await runtime.shutdown();
      return;
    }
    await state.registrationTeardown();
  })();
  return state.teardownPromise;
}
