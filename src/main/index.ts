import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  app,
  BrowserWindow,
  ipcMain,
  screen,
  type IpcMainInvokeEvent,
  session,
} from 'electron';

import {
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
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
import { DiagnosticEventStore } from './diagnostics/diagnosticEventStore.js';
import { registerDiagnosticsIpcHandlers, type DiagnosticsIpcTeardown } from './diagnostics/supportBundleIpc.js';
import { registerChannelComposition, type ChannelCompositionRegistration } from './channel/channelComposition.js';
import {
  createPlexPlaybackRuntimeComposition,
  createDesktopPlayerAdapterRuntimePort,
} from './player/plexPlaybackComposition.js';
import type { PlexPlaybackRuntime } from './player/plexPlaybackRuntime.js';
import { registerPlexComposition, type PlexCompositionRegistration } from './plex/plexComposition.js';
import { runSmokeAssertions, type ShellContainmentCounters } from './smokeAssertions.js';
import { registerShellAppCommandController } from './window/shellAppCommandController.js';
import { createShellWindowController } from './window/shellWindowController.js';
import type { PlexStreamResolverInput, PlexStreamResolverResult } from './plex/streamResolver.js';

registerLineupProtocolScheme();

const currentFile = fileURLToPath(import.meta.url);
const appRoot = path.resolve(path.dirname(currentFile), '..');
const rendererRoot = path.join(appRoot, 'renderer');
const preloadPath = path.join(appRoot, 'preload', 'index.cjs');
const shellMode = getShellMode();
const smokeMode = shellMode === 'smoke';
const diagnosticEventStore = new DiagnosticEventStore();

const shellWindowController = createShellWindowController({
  createBrowserWindow: (options) => new BrowserWindow(options),
  screen,
  preloadPath,
  smokeMode,
  publishShellStatus,
});
let teardownPlayerIpc: PlayerIpcTeardown | null = null;
let teardownDiagnosticsIpc: DiagnosticsIpcTeardown | null = null;
let plexComposition: PlexCompositionRegistration | null = null;
let channelComposition: ChannelCompositionRegistration | null = null;
let playbackRuntime: PlexPlaybackRuntime | null = null;
let channelSchedulerProgramStartHandler: (() => void | Promise<void>) | null = null;
let playerIpcQuitTeardownInProgress = false;
let playerIpcQuitTeardownComplete = false;
let containmentCounters: ShellContainmentCounters = {
  navigationDenied: 0,
  windowOpenDenied: 0,
  permissionDenied: 0,
  webviewDenied: 0,
};

app.commandLine.appendSwitch('disable-gpu');

app.whenReady()
  .then(async () => {
    registerLineupProtocolHandler(rendererRoot);
    configurePermissionContainment();
    registerShellIpcHandlers();
    teardownDiagnosticsIpc = registerDiagnosticsIpcHandlers({
      eventStore: diagnosticEventStore,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      getShellWindow: () => shellWindowController.getWindow(),
      appVersion: app.getVersion(),
    });
    teardownPlayerIpc = registerPlayerIpcHandlers({
      shellMode,
      isAuthorizedEvent,
      sendPlayerEvent,
      createRequestId,
      reportDiagnostic: reportMainProcessDiagnostic,
      diagnosticEventStore,
    });
    plexComposition = await registerPlexComposition({
      app,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      diagnosticEventStore,
    });
    let onChannelTunedCallback: ((channelId: string) => void | Promise<void>) | null = null;

    channelComposition = registerChannelComposition({
      app,
      shellMode,
      isAuthorizedEvent,
      createRequestId,
      plexRuntime: plexComposition.runtime,
      diagnosticEventStore,
      onChannelTuned: (channelId) => {
        if (onChannelTunedCallback) {
          void onChannelTunedCallback(channelId);
        }
      },
    });

    const fakePlaybackResolver = {
      async resolve(input: PlexStreamResolverInput): Promise<PlexStreamResolverResult> {
        const fakeMediaId = `plex-media-${input.mediaId}`;
        const fakeMediaTitle = `Live Program ${input.mediaId}`;
        const fakeMediaDurationMs = 1_200_000;
        if (input.mediaId.length === 0) {
          return {
            ok: false,
            error: {
              code: 'resource-missing',
              category: 'source',
              message: 'Missing media id',
              retryable: false,
              recoverable: false,
            },
            diagnostics: [],
          };
        }
        const payload = {
          media: {
            id: fakeMediaId,
            title: fakeMediaTitle,
            durationMs: fakeMediaDurationMs,
            container: 'mp4',
          },
          policy: {
            autoplay: input.autoplay ?? true,
            startPositionMs: input.startPositionMs ?? 0,
            preferredAudioTrackId: null,
            preferredSubtitleTrackId: null,
          },
          capabilityProfileId: input.capabilityProfile?.id || 'desktop-default-profile',
        };
        return {
          ok: true,
          load: payload,
          privatePlayback: {
            requestId: input.requestId,
            decisionKind: 'direct-play',
            playbackUrl: 'https://mock.plex.invalid/file.mp4',
            credentialHeader: { name: 'X-Plex-Token', value: 'mock-token' },
            selectedConnection: {
              protocol: 'https',
              address: 'mock.plex.invalid',
              port: 443,
              local: true,
              relay: false,
            },
            media: { id: payload.media.id, title: payload.media.title },
            setup: {
              playbackMode: 'direct-play',
              mediaPath: '/library/metadata/mock',
              variantId: 'mock-variant',
              partPath: '/library/parts/mock/file.mp4',
              selectedTrackIds: { video: null, audio: null, subtitle: null },
              selectedPrivateTrackIds: { video: null, audio: null, subtitle: null },
            },
          },
          decision: {
            kind: 'direct-play',
            candidateId: 'mock-candidate',
            selectedTrackIds: { video: null, audio: null, subtitle: null },
            summary: {
              media: {
                id: fakeMediaId,
                title: fakeMediaTitle,
              },
              container: 'mp4',
              videoCodec: 'h264',
              audioCodec: 'aac',
              audioLanguage: null,
              subtitleDelivery: null,
              subtitleLanguage: null,
              dynamicRange: 'sdr',
              action: 'direct-play',
            },
            reasonCodes: ['direct-play-supported'],
            unknowns: [],
          },
          pmsSession: null,
          diagnostics: [],
        };
      },
    };

    const fakePmsPort = {
      async releaseSession() {
        // No-op
      }
    };

    const capabilityProfile = {
      id: 'desktop-default-profile',
      directPlayContainers: ['mp4'],
      directPlayVideoCodecs: ['h264'],
      directPlayAudioCodecs: ['aac'],
      subtitleDeliveryModes: ['embedded', 'sidecar', 'none'],
      headerAuthSetup: 'supported',
      audioTrackSwitching: 'supported',
      subtitleTrackSwitching: 'supported',
      hdr: 'supported',
      dolbyVision: 'unsupported',
      directStream: {
        containerRemux: 'supported',
        audioTranscode: 'supported',
        subtitleConversion: 'supported',
      },
      transcode: {
        video: 'supported',
        audio: 'supported',
        subtitles: 'supported',
        hdr: 'supported',
      },
    } as const;

    const playerPort = teardownPlayerIpc.adapter
      ? createDesktopPlayerAdapterRuntimePort(teardownPlayerIpc.adapter)
      : {
          dispatch: async () => ({ ok: true, events: [] }),
          cleanup: async () => {},
        };

    const playbackRuntimeComposition = createPlexPlaybackRuntimeComposition({
      scheduler: channelComposition.activeChannelScheduler,
      resolver: fakePlaybackResolver,
      player: playerPort,
      pms: fakePmsPort,
      capabilityProfile,
      createRequestId,
      diagnosticEventStore,
    });
    playbackRuntime = playbackRuntimeComposition.runtime;

    channelSchedulerProgramStartHandler = async () => {
      if (playbackRuntime === null) {
        return;
      }
      try {
        await playbackRuntime.startCurrentPlayback('schedule-tick');
      } catch (error: unknown) {
        reportMainProcessDiagnostic('Automatic schedule tick playback transition failed', error);
      }
    };
    channelComposition.activeChannelScheduler.on('programStart', channelSchedulerProgramStartHandler);

    onChannelTunedCallback = async () => {
      if (playbackRuntime) {
        try {
          await playbackRuntime.startCurrentPlayback('manual-switch');
        } catch (error) {
          reportMainProcessDiagnostic('Manual channel switch playback start failed', error);
        }
      }
    };

    void channelComposition.guideRuntime.initializeActiveChannel()
      .then(async () => {
        if (playbackRuntime) {
          try {
            await playbackRuntime.startCurrentPlayback('startup');
          } catch (error) {
            reportMainProcessDiagnostic('Startup playback start failed', error);
          }
        }
      })
      .catch((error) => {
        reportMainProcessDiagnostic('Guide runtime active channel initialization failed', error);
      });
    const shellWindow = shellWindowController.createWindow();
    registerShellAppCommandController(shellWindow, {
      reportDiagnostic: reportMainProcessDiagnostic,
    });
    attachContainmentHandlers(shellWindow);
    await shellWindow.loadURL(LINEUP_SHELL_URL);
    if (!isAllowedShellUrl(shellWindow.webContents.getURL())) {
      throw new Error('Renderer loaded an unexpected URL.');
    }
    publishShellStatus('ready');
    if (smokeMode) {
      await runSmokeAssertions(shellWindow, containmentCounters);
      app.exit(0);
    }
  })
  .catch((error: unknown) => {
    console.error(redactError(error));
    app.exit(1);
  });

app.on('window-all-closed', () => {
  app.quit();
});

app.on('before-quit', (event) => {
  publishShellStatus('closing');
  const teardown = teardownPlayerIpc;
  if (playerIpcQuitTeardownComplete || teardown === null) {
    const localPlaybackRuntime = playbackRuntime;
    playbackRuntime = null;
    const localChannelComposition = channelComposition;
    channelComposition = null;
    if (localChannelComposition !== null && channelSchedulerProgramStartHandler !== null) {
      localChannelComposition.activeChannelScheduler.off(
        'programStart',
        channelSchedulerProgramStartHandler,
      );
      channelSchedulerProgramStartHandler = null;
    }
    const teardownPlex = plexComposition?.teardown ?? null;
    plexComposition = null;
    void Promise.all([
      localPlaybackRuntime?.teardown() ?? Promise.resolve(),
      teardownPlex?.() ?? Promise.resolve(),
      localChannelComposition?.teardown() ?? Promise.resolve(),
    ]).catch((error: unknown) => {
      reportMainProcessDiagnostic('Runtime composition cleanup failed during quit', error);
    });
    return;
  }
  if (playerIpcQuitTeardownInProgress) {
    event.preventDefault();
    return;
  }

  event.preventDefault();
  teardownPlayerIpc = null;
  teardownDiagnosticsIpc?.();
  teardownDiagnosticsIpc = null;
  const teardownPlex = plexComposition?.teardown ?? null;
  plexComposition = null;
  const localChannelComposition = channelComposition;
  channelComposition = null;
  playerIpcQuitTeardownInProgress = true;
  const localPlaybackRuntime = playbackRuntime;
  playbackRuntime = null;
  if (localChannelComposition !== null && channelSchedulerProgramStartHandler !== null) {
    localChannelComposition.activeChannelScheduler.off(
      'programStart',
      channelSchedulerProgramStartHandler,
    );
    channelSchedulerProgramStartHandler = null;
  }
  Promise.all([
    teardown.teardown(),
    teardownPlex?.() ?? Promise.resolve(),
    localChannelComposition?.teardown() ?? Promise.resolve(),
    localPlaybackRuntime?.teardown() ?? Promise.resolve(),
  ])
    .catch((error: unknown) => {
      reportMainProcessDiagnostic('Player IPC cleanup failed during quit', error);
    })
    .finally(() => {
      playerIpcQuitTeardownComplete = true;
      playerIpcQuitTeardownInProgress = false;
      app.quit();
    });
});

function attachContainmentHandlers(window: BrowserWindow): void {
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
    return shellSuccess(payload.requestId, shellWindowController.setFullscreen(enabled));
  });
}

function isAuthorizedEvent(event: IpcMainInvokeEvent): boolean {
  const shellWindow = shellWindowController.getWindow();
  if (shellWindow === null) {
    return false;
  }
  if (event.senderFrame === null) {
    return false;
  }
  const details: ShellIpcAuthorizationDetails = {
    senderMatchesShell: event.sender === shellWindow.webContents,
    senderDestroyed: event.sender.isDestroyed(),
    senderUrl: event.sender.getURL(),
    frameUrl: event.senderFrame.url,
    frameIsMainFrame: event.senderFrame === event.sender.mainFrame,
  };
  return isAuthorizedShellIpcRequest(details);
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
  const window = shellWindowController.getWindow();
  if (window === null || window.isDestroyed()) {
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

function getShellMode(): ShellMode {
  if (process.env.LINEUP_DESKTOP_SMOKE === '1') {
    return 'smoke';
  }
  if (process.env.NODE_ENV === 'production') {
    return 'production';
  }
  return 'development';
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
