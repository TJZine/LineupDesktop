import path from 'node:path';
import { fileURLToPath } from 'node:url';
import fs from 'node:fs/promises';

import {
  app,
  BaseWindow,
  WebContentsView,
  ipcMain,
  screen,
  type IpcMainInvokeEvent,
  session,
} from 'electron';

import {
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_MEDIA_INPUT_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
} from '../contracts/ipc.js';
import {
  LINEUP_APP_NAME,
  LINEUP_SHELL_URL,
  type ShellCapabilities,
  type ShellMode,
  type ShellStatusEvent,
  type WindowFullscreenState,
  isWindowFullscreenIntentEnvelope,
  shellFailure,
  shellSuccess,
} from '../contracts/shell.js';
import type { PlayerEvent } from '../contracts/player.js';
import { registerLineupProtocolHandler, registerLineupProtocolScheme } from './protocol.js';
import { redactMainProcessError, reportMainProcessDiagnostic } from './redactedDiagnostics.js';
import {
  isAllowedShellUrl,
  isAuthorizedShellIpcRequest,
  type ShellIpcAuthorizationDetails,
} from './shellSecurity.js';
import { registerPlayerIpcHandlers, type PlayerIpcTeardown } from './player/playerIpc.js';
import { createProductionNativeHostFactory } from './player/productionNativeHostFactory.js';
import { NativePlayerPresentationOwner } from './player/nativePlayerPresentationOwner.js';
import { DiagnosticEventStore } from './diagnostics/diagnosticEventStore.js';
import { registerDiagnosticsIpcHandlers, type DiagnosticsIpcTeardown } from './diagnostics/supportBundleIpc.js';
import {
  bindGuideArtworkOwnerToWebContents,
  createChannelComposition,
  registerChannelCompositionIpc,
  type ChannelCompositionRegistration,
} from './channel/channelComposition.js';
import { bootstrapPlaybackRuntime } from './player/playbackRuntimeBootstrap.js';
import {
  createPlaybackEventRouter,
  type PlaybackEventRouter,
} from './player/playbackEventRouter.js';
import {
  PlaybackProgramTransitionOwner,
} from './player/playbackProgramTransitionOwner.js';
import {
  registerPlayerRecoveryIpc,
  type PlayerRecoveryIpcTeardown,
} from './player/playerRecoveryIpc.js';
import { wirePlexPlaybackCleanup } from './player/plexPlaybackCleanupWiring.js';
import type { PlexPlaybackRuntime } from './player/plexPlaybackRuntime.js';
import {
  createPlexComposition,
  registerPlexCompositionIpc,
  type PlexCompositionRegistration,
} from './plex/plexComposition.js';
import { runSmokeAssertions, type ShellContainmentCounters } from './smokeAssertions.js';
import { registerShellAppCommandController } from './window/shellAppCommandController.js';
import { createShellWindowController, type ShellWindow } from './window/shellWindowController.js';
import { resolveDesktopGuidePreferencesFilePath, resolveDesktopSettingsFilePath } from './persistence/appDataPaths.js';
import { DesktopSettingsStore } from './persistence/desktopSettingsStore.js';
import { registerSettingsIpcHandlers, type SettingsIpcTeardown } from './settings/settingsIpc.js';
import { createSettingsNativeHostComposition } from './settings/settingsNativeHostComposition.js';
import { SmokeBootstrapOwner } from './smokeBootstrapOwner.js';
import { SingleInstanceOwner } from './singleInstanceOwner.js';
import { ChannelPersistenceBootstrapOwner } from './persistence/channelPersistenceBootstrapOwner.js';
import { ChannelPersistenceStartupOwner } from './persistence/channelPersistenceStartupOwner.js';
import { DesktopChannelPersistenceStore } from './persistence/desktopChannelPersistenceStore.js';
import { createChannelBuilderSmokeFixture } from './channel/channelBuilderSmokeFixture.js';
import { cleanupFailedApplicationStartup } from './applicationStartupCleanup.js';
import { ApplicationQuitLifecycleOwner } from './applicationQuitLifecycleOwner.js';

registerLineupProtocolScheme();

const currentFile = fileURLToPath(import.meta.url);
const appRoot = path.resolve(path.dirname(currentFile), '..');
const rendererRoot = path.join(appRoot, 'renderer');
const preloadPath = path.join(appRoot, 'preload', 'index.cjs');
let shellMode: ShellMode = 'development';
const diagnosticEventStore = new DiagnosticEventStore();

let shellWindowController: ReturnType<typeof createShellWindowController> | null = null;
let teardownPlayerIpc: PlayerIpcTeardown | null = null;
let teardownDiagnosticsIpc: DiagnosticsIpcTeardown | null = null;
let teardownSettingsIpc: SettingsIpcTeardown | null = null;
let plexComposition: PlexCompositionRegistration | null = null;
let channelComposition: ChannelCompositionRegistration | null = null;
let playbackRuntime: PlexPlaybackRuntime | null = null;
let playbackEventRouter: PlaybackEventRouter | null = null;
let playbackProgramTransitionOwner: PlaybackProgramTransitionOwner | null = null;
let teardownPlayerRecoveryIpc: PlayerRecoveryIpcTeardown | null = null;
let nativePlayerPresentationOwner: NativePlayerPresentationOwner | null = null;
let shellPresentationCleanupInProgress: Promise<void> | null = null;
let singleInstanceOwner: SingleInstanceOwner | null = null;
let applicationQuitLifecycleOwner: ApplicationQuitLifecycleOwner | null = null;
let applicationStartupSettled: Promise<void> = Promise.resolve();
let containmentCounters: ShellContainmentCounters = {
  navigationDenied: 0,
  windowOpenDenied: 0,
  permissionDenied: 0,
  webviewDenied: 0,
};

app.commandLine.appendSwitch('disable-gpu');

const applicationStartup = startApplication();
applicationStartupSettled = applicationStartup.then(
  () => undefined,
  () => undefined,
);
void applicationStartup.catch(async (error: unknown) => {
  if (applicationQuitLifecycleOwner?.isQuitRequested() === true) return;
  try {
    await cleanupShellAndNativePresentation();
  } catch (cleanupError: unknown) {
    reportMainProcessDiagnostic('Shell and presentation cleanup after startup failure failed', cleanupError);
  }
  const cleanupSettingsIpc = teardownSettingsIpc;
  teardownSettingsIpc = null;
  const cleanupDiagnosticsIpc = teardownDiagnosticsIpc;
  teardownDiagnosticsIpc = null;
  const teardownPlayer = teardownPlayerIpc;
  teardownPlayerIpc = null;
  const teardownRouter = playbackEventRouter;
  playbackEventRouter = null;
  const teardownPlaybackRuntime = playbackRuntime;
  playbackRuntime = null;
  const teardownTransitionOwner = playbackProgramTransitionOwner;
  playbackProgramTransitionOwner = null;
  const teardownRecoveryIpc = teardownPlayerRecoveryIpc;
  teardownPlayerRecoveryIpc = null;
  const cleanupSingleInstanceOwner = singleInstanceOwner;
  singleInstanceOwner = null;
  const teardownChannel = channelComposition?.teardown ?? null;
  channelComposition = null;
  const teardownPlex = plexComposition?.teardown ?? null;
  plexComposition = null;
  await cleanupFailedApplicationStartup(
    {
      settingsIpc: cleanupSettingsIpc,
      diagnosticsIpc: cleanupDiagnosticsIpc,
      playerRecoveryIpc: teardownRecoveryIpc,
      playbackTransitionOwner: teardownTransitionOwner,
      playerIpc: teardownPlayer,
      playbackEventRouter: teardownRouter,
      playbackRuntime: teardownPlaybackRuntime,
      channelComposition: teardownChannel,
      plexComposition: teardownPlex,
      singleInstanceOwner: cleanupSingleInstanceOwner,
    },
    reportMainProcessDiagnostic,
  );
  console.error(redactError(error));
  app.exit(1);
});

async function startApplication(): Promise<void> {
  const smokeBootstrap = new SmokeBootstrapOwner({
    app,
    argv: process.argv,
    environment: process.env,
    platform: process.platform,
  }).validate();
  if (smokeBootstrap.status === 'failed') {
    throw new Error(smokeBootstrap.error.message);
  }
  shellMode =
    smokeBootstrap.status === 'smoke'
      ? 'smoke'
      : process.env.NODE_ENV === 'production'
        ? 'production'
        : 'development';
  const smokeMode = shellMode === 'smoke';
  singleInstanceOwner = new SingleInstanceOwner({
    app,
    getWindow: () => shellWindowController?.getWindow()?.baseWindow ?? null,
  });
  if (!singleInstanceOwner.acquire().primary) return;
  const quitLifecycleOwner = new ApplicationQuitLifecycleOwner({
    cleanupCurrentOwners: cleanupApplicationRuntimeForQuit,
    waitForStartupSettlement: () => applicationStartupSettled,
    quit: () => app.quit(),
    reportDiagnostic: reportMainProcessDiagnostic,
  });
  applicationQuitLifecycleOwner = quitLifecycleOwner;
  registerApplicationLifecycleHandlers(quitLifecycleOwner);

  const smokeFixture =
    smokeBootstrap.status === 'smoke'
      ? createChannelBuilderSmokeFixture(smokeBootstrap.capability)
      : null;
  let persistence:
    | Parameters<typeof createChannelComposition>[0]['persistence'];
  let channelStartupStore: DesktopChannelPersistenceStore | null = null;
  if (smokeFixture !== null) {
    persistence = { kind: 'memory', storage: smokeFixture.storage };
  } else {
    const bootstrap = await new ChannelPersistenceBootstrapOwner({
      app,
      platform: process.platform,
      fileSystem: {
        realpath: (value) => fs.realpath(value),
        lstat: (value) => fs.lstat(value),
        mkdir: async (value, options) => {
          await fs.mkdir(value, options);
        },
      },
    }).bootstrap();
    if (quitLifecycleOwner.isQuitRequested()) return;
    if (bootstrap.status !== 'ready') throw new Error(bootstrap.error.message);
    channelStartupStore = new DesktopChannelPersistenceStore({
      readyCapability: bootstrap.capability,
    });
    persistence = { kind: 'disk', readyCapability: bootstrap.capability };
  }

  const plexCreated = await createPlexComposition({
    app,
    diagnosticEventStore,
  });
  if (quitLifecycleOwner.isQuitRequested()) {
    await runQuitCleanupStep('Plex cleanup failed during quit', () => plexCreated.teardown());
    return;
  }
  plexComposition = plexCreated;
  if (channelStartupStore !== null) {
    const startup = await new ChannelPersistenceStartupOwner({
      store: channelStartupStore,
      clock: { now: () => Date.now() },
    }).loadAndRepair();
    if (quitLifecycleOwner.isQuitRequested()) return;
    if (!startup.ok) throw new Error(startup.error.message);
  }
  await app.whenReady();
  if (quitLifecycleOwner.isQuitRequested()) return;
  shellWindowController = createShellWindowController({
    createBaseWindow: (options) => new BaseWindow(options),
    createWebContentsView: (options) => new WebContentsView(options),
    screen,
    preloadPath,
    smokeMode,
    publishShellStatus,
    invalidatePresentationDocument: () => nativePlayerPresentationOwner?.invalidateDocument(),
    hidePresentation: () => nativePlayerPresentationOwner?.hide() ?? Promise.resolve(),
  });
  const settingsStore = new DesktopSettingsStore({
    settingsFilePath: resolveDesktopSettingsFilePath(app),
    migrationEventSink: (event) => {
      diagnosticEventStore.record({
        surface: 'main', category: 'lifecycle', severity: event.status === 'succeeded' ? 'info' : 'error',
        status: event.status, operation: 'settings.migration', message: 'Desktop settings migration completed.',
        result: event.status === 'succeeded' ? 'success' : 'failure',
        context: { fromVersion: event.fromVersion, toVersion: event.toVersion, status: event.status, revision: event.revision },
      });
    },
  });
  const channelCreated = createChannelComposition({
    persistence,
    plexRuntime: plexCreated.runtime,
    guideArtworkSessionGenerationOwner: plexCreated.guideArtworkSessionGenerationOwner,
    guideArtworkTransport: plexCreated.guideArtworkTransport,
    channelBuilderContextSource: smokeFixture?.contextSource,
    diagnosticEventStore,
    guidePreferencesFilePath: resolveDesktopGuidePreferencesFilePath(app),
    getPastItemsWindowSnapshot: async () => {
      const snapshot = await settingsStore.loadSnapshot();
      return {
        revision: snapshot.revision,
        pastItemsWindow: snapshot.values.pastItemsWindow,
        libraryTabsEnabled: snapshot.values.libraryTabsEnabled,
      };
    },
  });
  channelComposition = channelCreated;
  plexComposition = registerPlexCompositionIpc(plexCreated, {
    shellMode,
    isAuthorizedEvent,
    createRequestId,
    diagnosticEventStore,
  });
  channelComposition = registerChannelCompositionIpc(channelCreated, {
    shellMode,
    isAuthorizedEvent,
    createRequestId,
    diagnosticEventStore,
  });

    registerLineupProtocolHandler(rendererRoot, channelCreated.guideArtworkOwner, {
      recordDeliveryFailure: () => {
        diagnosticEventStore.record({
          surface: 'main',
          category: 'ipc',
          severity: 'warning',
          status: 'failed',
          operation: 'guide.artwork.delivery',
          message: 'Guide artwork delivery failed.',
          result: 'failure',
        });
      },
    });
    configurePermissionContainment();
    registerShellIpcHandlers();
    const initialSettingsSnapshot = await settingsStore.loadSnapshot();
    if (quitLifecycleOwner.isQuitRequested()) return;
    const productionNativeHostFactory = shellMode === 'production'
      ? createProductionNativeHostFactory({ diagnosticEventStore })
      : null;
    const settingsNativeHostComposition = createSettingsNativeHostComposition({
      shellMode,
      platform: process.platform,
      initialSnapshot: initialSettingsSnapshot,
      createProductionNativeHost: () => productionNativeHostFactory?.() ?? null,
      createRequestId,
      diagnosticEventStore,
    });
    const {
      nativeHost: productionNativeHost,
      settingsPolicy,
      settingsAudioOutputOwner,
    } = settingsNativeHostComposition;
    nativePlayerPresentationOwner = new NativePlayerPresentationOwner({
      platform: process.platform,
      host: productionNativeHost,
      getSnapshot: () => teardownPlayerIpc?.adapter?.getSnapshot() ?? null,
      getParentIdentity: () => getShellWindowController().getNativeParentIdentity(),
    });
    teardownSettingsIpc = registerSettingsIpcHandlers({
      store: settingsStore,
      policy: settingsPolicy,
      audioOutputOwner: settingsAudioOutputOwner,
      isAuthorizedEvent,
      ipcMain,
    });
    teardownDiagnosticsIpc = registerDiagnosticsIpcHandlers({
      eventStore: diagnosticEventStore,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      getShellWindow: () => getShellWindowController().getBaseWindow(),
      appVersion: app.getVersion(),
    });
    const eventRouter = createPlaybackEventRouter({
      getRuntime: () => playbackRuntime,
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    playbackEventRouter = eventRouter;
    teardownPlayerIpc = registerPlayerIpcHandlers({
      shellMode,
      isAuthorizedEvent,
      sendSynchronousPlayerEvent: sendPlayerEvent,
      onAsynchronousAdapterEvents: eventRouter.route,
      createRequestId,
      reportDiagnostic: reportMainProcessDiagnostic,
      diagnosticEventStore,
      nativeHost: productionNativeHost,
      presentationOwner: nativePlayerPresentationOwner,
      onNativeHostLifecycleFailure: () => {
        const transitionOwner = playbackProgramTransitionOwner;
        const runtime = playbackRuntime;
        const releaseCleanupHold =
          transitionOwner?.acquireCleanupHold() ?? (() => undefined);
        eventRouter.flushCurrentRuntime();
        transitionOwner?.invalidate();
        void (async () => {
          try {
            await runtime?.handleHelperCrash();
          } catch (error: unknown) {
            reportMainProcessDiagnostic(
              'Playback cleanup on helper-crash failed',
              error,
            );
          } finally {
            releaseCleanupHold();
          }
        })();
      },
    });
    wirePlexPlaybackCleanup({
      plexRuntime: plexComposition.runtime,
      getPlaybackRuntime: () => {
        const runtime = playbackRuntime;
        if (runtime === null) {
          return null;
        }
        return {
          cleanup: async (input) => {
            const transitionOwner = playbackProgramTransitionOwner;
            const releaseCleanupHold =
              transitionOwner?.acquireCleanupHold() ?? (() => undefined);
            transitionOwner?.invalidate();
            try {
              return await runtime.cleanup(input);
            } finally {
              releaseCleanupHold();
            }
          },
        };
      },
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    const playbackRuntimeComposition = bootstrapPlaybackRuntime({
      shellMode,
      scheduler: channelComposition.activeChannelScheduler,
      adapter: teardownPlayerIpc.adapter,
      createRequestId,
      onEvents: (events) => {
        for (const event of events) {
          sendPlayerEvent(event);
        }
      },
      diagnosticEventStore,
      plexRuntime: plexComposition.runtime,
      settingsPolicy,
      settingsAudioOutputOwner,
    });
    playbackRuntime = playbackRuntimeComposition.runtime;
    const transitionOwner = new PlaybackProgramTransitionOwner({
      scheduler: channelComposition.activeChannelScheduler,
      runtime: playbackRuntime,
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    playbackProgramTransitionOwner = transitionOwner;
    teardownPlayerRecoveryIpc = registerPlayerRecoveryIpc({
      transitionOwner,
      getSnapshot: () => teardownPlayerIpc?.adapter?.getSnapshot() ?? null,
      isAuthorizedEvent,
      createRequestId,
    });
    void channelComposition.guideRuntime.initializeActiveChannel()
      .catch((error) => {
        reportMainProcessDiagnostic('Guide runtime active channel initialization failed', error);
      });
    const shellWindow = await getShellWindowController().createWindow();
    if (quitLifecycleOwner.isQuitRequested()) return;
    bindGuideArtworkOwnerToWebContents(shellWindow.webContents, channelCreated.guideArtworkOwner);
    registerShellAppCommandController(shellWindow, {
      sendMediaInput: (input) => sendToShellWindow(LINEUP_SHELL_MEDIA_INPUT_CHANNEL, input),
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    attachContainmentHandlers(shellWindow);
    await shellWindow.loadURL(LINEUP_SHELL_URL);
    if (quitLifecycleOwner.isQuitRequested()) return;
    if (!isAllowedShellUrl(shellWindow.webContents.getURL())) {
      throw new Error('Renderer loaded an unexpected URL.');
    }
    publishShellStatus('ready');
    getShellWindowController().showWindow();
    if (smokeMode) {
      await runSmokeAssertions(shellWindow, containmentCounters);
      if (quitLifecycleOwner.isQuitRequested()) return;
      app.exit(0);
    }
}

function registerApplicationLifecycleHandlers(
  quitLifecycleOwner: ApplicationQuitLifecycleOwner,
): void {
  app.on('window-all-closed', () => {
    app.quit();
  });

  app.on('before-quit', (event) => {
    if (!quitLifecycleOwner.isQuitRequested()) {
      try {
        publishShellStatus('closing');
      } catch (error: unknown) {
        reportMainProcessDiagnostic('Shell closing status publication failed', error);
      }
    }
    quitLifecycleOwner.handleBeforeQuit(event);
  });
}

async function cleanupApplicationRuntimeForQuit(): Promise<void> {
  const cleanupSingleInstanceOwner = singleInstanceOwner;
  singleInstanceOwner = null;
  const cleanupSettingsIpc = teardownSettingsIpc;
  teardownSettingsIpc = null;
  const cleanupDiagnosticsIpc = teardownDiagnosticsIpc;
  teardownDiagnosticsIpc = null;
  const cleanupPlayerRecoveryIpc = teardownPlayerRecoveryIpc;
  teardownPlayerRecoveryIpc = null;
  const cleanupPlaybackProgramTransitionOwner = playbackProgramTransitionOwner;
  playbackProgramTransitionOwner = null;
  const cleanupPlayerIpc = teardownPlayerIpc;
  teardownPlayerIpc = null;
  const cleanupPlaybackEventRouter = playbackEventRouter;
  playbackEventRouter = null;
  const cleanupPlaybackRuntime = playbackRuntime;
  playbackRuntime = null;
  const cleanupChannelComposition = channelComposition;
  channelComposition = null;
  const cleanupPlexComposition = plexComposition;
  plexComposition = null;

  await runQuitCleanupStep(
    'Single-instance cleanup failed during quit',
    () => cleanupSingleInstanceOwner?.teardown(),
  );
  await runQuitCleanupStep('Settings IPC cleanup failed during quit', () => cleanupSettingsIpc?.());
  await runQuitCleanupStep('Diagnostics IPC cleanup failed during quit', () => cleanupDiagnosticsIpc?.());
  await runQuitCleanupStep(
    'Player recovery IPC cleanup failed during quit',
    () => cleanupPlayerRecoveryIpc?.(),
  );
  await runQuitCleanupStep(
    'Playback transition cleanup failed during quit',
    () => cleanupPlaybackProgramTransitionOwner?.dispose(),
  );
  await runQuitCleanupStep(
    'Guide artwork cleanup failed during quit',
    () => cleanupChannelComposition?.guideArtworkOwner.dispose(),
  );
  await runQuitCleanupStep(
    'Shell and presentation cleanup failed during quit',
    cleanupShellAndNativePresentation,
  );
  await runQuitCleanupStep('Player IPC cleanup failed during quit', () => cleanupPlayerIpc?.teardown());
  await runQuitCleanupStep(
    'Playback event cleanup failed during quit',
    () => cleanupPlaybackEventRouter?.dispose(),
  );
  await runQuitCleanupStep(
    'Playback runtime cleanup failed during quit',
    () => cleanupPlaybackRuntime?.teardown(),
  );
  await Promise.all([
    runQuitCleanupStep('Plex cleanup failed during quit', () => cleanupPlexComposition?.teardown()),
    runQuitCleanupStep(
      'Channel cleanup failed during quit',
      () => cleanupChannelComposition?.teardown(),
    ),
  ]);
}

async function runQuitCleanupStep(
  failureMessage: string,
  cleanup: () => unknown | Promise<unknown>,
): Promise<void> {
  try {
    await cleanup();
  } catch (error: unknown) {
    reportMainProcessDiagnostic(failureMessage, error);
  }
}

function attachContainmentHandlers(window: ShellWindow): void {
  window.webContents.setWindowOpenHandler(() => {
    containmentCounters.windowOpenDenied += 1;
    return { action: 'deny' };
  });

  window.webContents.on('will-navigate', (event, targetUrl) => {
    if (!isAllowedShellUrl(targetUrl)) {
      containmentCounters.navigationDenied += 1;
      event.preventDefault();
    }
  });

  window.webContents.on('will-attach-webview', (event) => {
    containmentCounters.webviewDenied += 1;
    event.preventDefault();
  });

  window.webContents.on('did-navigate', (_event, targetUrl) => {
    if (!isAllowedShellUrl(targetUrl)) {
      window.webContents.stop();
    }
  });
}

function cleanupShellAndNativePresentation(): Promise<void> {
  if (shellPresentationCleanupInProgress !== null) return shellPresentationCleanupInProgress;
  const controller = shellWindowController;
  const presentationOwner = nativePlayerPresentationOwner;
  const cleanup = (async (): Promise<void> => {
    const errors: Error[] = [];
    try {
      await controller?.dispose();
    } catch (error: unknown) {
      errors.push(error instanceof Error ? error : new Error('Shell window cleanup failed.'));
    }
    try {
      await presentationOwner?.dispose();
    } catch (error: unknown) {
      errors.push(error instanceof Error ? error : new Error('Native presentation cleanup failed.'));
    } finally {
      if (shellWindowController === controller) shellWindowController = null;
      if (nativePlayerPresentationOwner === presentationOwner) nativePlayerPresentationOwner = null;
    }
    if (errors.length === 1) throw errors[0];
    if (errors.length > 1) {
      throw new AggregateError(errors, 'Shell and native presentation cleanup failed.');
    }
  })();
  shellPresentationCleanupInProgress = cleanup.finally(() => {
    shellPresentationCleanupInProgress = null;
  });
  return shellPresentationCleanupInProgress;
}

function configurePermissionContainment(): void {
  session.defaultSession.setPermissionRequestHandler((_webContents, _permission, callback) => {
    containmentCounters.permissionDenied += 1;
    callback(false);
  });
  session.defaultSession.setPermissionCheckHandler(() => {
    containmentCounters.permissionDenied += 1;
    return false;
  });
}

function registerShellIpcHandlers(): void {
  ipcMain.handle(LINEUP_SHELL_GET_CAPABILITIES_CHANNEL, (event) => {
    const requestId = createRequestId('shell');
    if (!isAuthorizedEvent(event)) {
      return shellFailure<ShellCapabilities>(requestId, 'unauthorized', 'Request is not authorized.');
    }
    return shellSuccess(requestId, getShellCapabilities());
  });

  ipcMain.handle(LINEUP_WINDOW_INTENT_CHANNEL, (event, payload: unknown) => {
    const requestId = getRequestId(payload);
    if (!isAuthorizedEvent(event)) {
      return shellFailure<WindowFullscreenState>(
        requestId,
        'unauthorized',
        'Request is not authorized.',
      );
    }
    if (!isWindowFullscreenIntentEnvelope(payload)) {
      return shellFailure<WindowFullscreenState>(
        requestId,
        'validation-failed',
        'Window intent payload is invalid.',
      );
    }

    const enabled = payload.intent === 'window.enterFullscreen';
    return shellSuccess(payload.requestId, getShellWindowController().setFullscreen(enabled));
  });
}

function isAuthorizedEvent(event: IpcMainInvokeEvent): boolean {
  try {
    const shellWindow = getShellWindowController().getWindow();
    if (shellWindow === null || event.sender !== shellWindow.webContents || event.sender.isDestroyed()) {
      return false;
    }
    const senderFrame = event.senderFrame;
    if (senderFrame === null) return false;
    const details: ShellIpcAuthorizationDetails = {
      senderMatchesShell: true,
      senderDestroyed: false,
      senderUrl: event.sender.getURL(),
      frameUrl: senderFrame.url,
      frameIsMainFrame: senderFrame === event.sender.mainFrame,
    };
    return isAuthorizedShellIpcRequest(details);
  } catch {
    return false;
  }
}

function getShellCapabilities(): ShellCapabilities {
  const platform = process.platform;
  return {
    appName: LINEUP_APP_NAME,
    appVersion: app.getVersion(),
    platform:
      platform === 'darwin' || platform === 'linux' || platform === 'win32'
        ? platform
        : 'unknown',
    shellMode,
    protocolOrigin: 'lineup://shell',
  };
}

function publishShellStatus(status: ShellStatusEvent['status']): void {
  sendToShellWindow(LINEUP_SHELL_STATUS_CHANGED_CHANNEL, {
    status,
    timestampMs: Date.now(),
  } satisfies ShellStatusEvent);
}

function sendPlayerEvent(event: PlayerEvent): void {
  sendToShellWindow(LINEUP_PLAYER_EVENT_CHANNEL, event);
}

function sendToShellWindow(channel: string, payload: unknown): void {
  const window = shellWindowController?.getWindow() ?? null;
  if (window === null || window.baseWindow.isDestroyed()) {
    return;
  }

  const { webContents } = window;
  if (webContents.isDestroyed()) {
    return;
  }

  try {
    webContents.send(channel, payload);
  } catch (error) {
    reportMainProcessDiagnostic('Shell event delivery failed', error);
  }
}

function getShellWindowController(): NonNullable<typeof shellWindowController> {
  if (shellWindowController === null) {
    throw new Error('Shell window controller is unavailable.');
  }
  return shellWindowController;
}

function getRequestId(payload: unknown): string {
  if (
    typeof payload === 'object' &&
    payload !== null &&
    'requestId' in payload &&
    typeof payload.requestId === 'string'
  ) {
    return payload.requestId;
  }
  return createRequestId('invalid');
}

function createRequestId(prefix: string): string {
  return `${prefix}-${Date.now()}-${Math.random().toString(36).slice(2)}`;
}

function redactError(error: unknown): string {
  return redactMainProcessError(error, 'Electron shell startup failed.');
}
