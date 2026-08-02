import test from 'node:test';
import assert from 'node:assert/strict';
import { existsSync, readFileSync } from 'node:fs';
import ts from 'typescript';

import {
  LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL,
  LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
  LINEUP_PLAYER_TUNE_CHANNEL,
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLAYER_RECOVERY_CHANNEL,
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_MEDIA_INPUT_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
  LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL,
  LINEUP_SETTINGS_REPLACE_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  PLAYER_RENDERER_INTENTS,
} from '../../contracts/ipc.js';
import {
  CHANNEL_SETUP_ERROR_CODES,
  CHANNEL_SETUP_BUILD_MODES,
  CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS,
  CHANNEL_SETUP_OPERATIONS,
  CHANNEL_SETUP_STATUS_VALUES,
} from '../../contracts/channel.js';
import {
  CUSTOM_CHANNEL_ERROR_CODES,
  CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS,
  CUSTOM_CHANNEL_OPERATIONS,
  CUSTOM_CHANNEL_VALIDATION_CODES,
} from '../../contracts/customChannels.js';
import {
  DIAGNOSTIC_CATEGORIES,
  DIAGNOSTIC_SEVERITIES,
  DIAGNOSTIC_STATUSES,
  DIAGNOSTIC_SURFACES,
  DIAGNOSTICS_ERROR_CODES,
  DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
  DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
  REDACTION_SCAN_FINDING_LABELS,
} from '../../contracts/diagnostics.js';
import {
  PLAYER_COMMAND_VALUES,
  PLAYER_ERROR_CATEGORIES,
  PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
  PLAYER_STATUS_VALUES,
  PLAYER_TRACK_DELIVERY_TYPE_VALUES,
  PLAYER_TRACK_KIND_VALUES,
} from '../../contracts/player.js';
import {
  PLEX_FORBIDDEN_RENDERER_FIELD_KEYS,
  PLEX_RUNTIME_ERROR_CODES,
  PLEX_RUNTIME_OPERATIONS,
} from '../../contracts/plex.js';
import {
  PLAYER_RECOVERY_ACTIONS,
  SHELL_STATUS_VALUES,
} from '../../contracts/shell.js';
import {
  DEFAULT_DESKTOP_SETTINGS_VALUES,
  createConservativeDesktopSettingsCapabilities,
} from '../../contracts/settings.js';

const preloadSourceUrl = new URL('../../preload/index.cts', import.meta.url);
const preloadSourceText = readFileSync(preloadSourceUrl, 'utf8');
const preloadChannelsSourceUrl = new URL('../../preload/channels.cts', import.meta.url);
const preloadChannelsSourceText = readFileSync(preloadChannelsSourceUrl, 'utf8');
const channelGuardSourceUrl = new URL('../../preload/channelBridgeGuards.cts', import.meta.url);
const channelGuardSourceText = readFileSync(channelGuardSourceUrl, 'utf8');
const channelSetupBridgeSourceUrl = new URL('../../preload/channelSetupBridge.cts', import.meta.url);
const channelSetupBridgeSourceText = readFileSync(channelSetupBridgeSourceUrl, 'utf8');
const customChannelGuardSourceUrl = new URL('../../preload/customChannelBridgeGuards.cts', import.meta.url);
const customChannelGuardSourceText = readFileSync(customChannelGuardSourceUrl, 'utf8');
const customChannelBridgeSourceUrl = new URL('../../preload/customChannelBridge.cts', import.meta.url);
const customChannelBridgeSourceText = readFileSync(customChannelBridgeSourceUrl, 'utf8');
const diagnosticsGuardSourceUrl = new URL('../../preload/diagnosticsBridgeGuards.cts', import.meta.url);
const diagnosticsGuardSourceText = readFileSync(diagnosticsGuardSourceUrl, 'utf8');
const guideBridgeSourceUrl = new URL('../../preload/guideBridge.cts', import.meta.url);
const guideBridgeSourceText = readFileSync(guideBridgeSourceUrl, 'utf8');
const playerBridgeSourceUrl = new URL('../../preload/playerBridge.cts', import.meta.url);
const playerBridgeSourceText = readFileSync(playerBridgeSourceUrl, 'utf8');
const playerRecoveryBridgeSourceText = readFileSync(
  new URL('../../preload/playerRecoveryBridge.cts', import.meta.url),
  'utf8',
);
const settingsGuardSourceUrl = new URL('../../preload/settingsBridgeGuards.cts', import.meta.url);
const settingsGuardSourceText = readFileSync(settingsGuardSourceUrl, 'utf8');
const settingsAudioValidationSourceText = readFileSync(
  new URL('../../contracts/settingsAudioValidation.ts', import.meta.url),
  'utf8',
);
const settingsBridgeSourceUrl = new URL('../../preload/settingsBridge.cts', import.meta.url);
const settingsBridgeSourceText = readFileSync(settingsBridgeSourceUrl, 'utf8');
const preloadBundleToolSourceText = readFileSync(
  new URL('../../../tools/bundle-preload.mjs', import.meta.url),
  'utf8',
);
const preloadBundleOutputUrl = new URL('../../../dist/preload/index.cjs', import.meta.url);
const preloadSourceFile = ts.createSourceFile(
  'src/preload/index.cts',
  preloadSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const preloadChannelsSourceFile = ts.createSourceFile(
  'src/preload/channels.cts',
  preloadChannelsSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const channelGuardSourceFile = ts.createSourceFile(
  'src/preload/channelBridgeGuards.cts',
  channelGuardSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const diagnosticsGuardSourceFile = ts.createSourceFile(
  'src/preload/diagnosticsBridgeGuards.cts',
  diagnosticsGuardSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const channelSetupBridgeSourceFile = ts.createSourceFile(
  'src/preload/channelSetupBridge.cts',
  channelSetupBridgeSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const customChannelGuardSourceFile = ts.createSourceFile(
  'src/preload/customChannelBridgeGuards.cts',
  customChannelGuardSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const customChannelBridgeSourceFile = ts.createSourceFile(
  'src/preload/customChannelBridge.cts',
  customChannelBridgeSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const guideBridgeSourceFile = ts.createSourceFile(
  'src/preload/guideBridge.cts',
  guideBridgeSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);
const playerBridgeSourceFile = ts.createSourceFile(
  'src/preload/playerBridge.cts',
  playerBridgeSourceText,
  ts.ScriptTarget.Latest,
  true,
  ts.ScriptKind.TS,
);

type PreloadInvokeCall = {
  channel: string;
  request: { requestId: string; payload?: unknown };
};

function evaluateChannelGuardModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(channelGuardSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/channelBridgeGuards.cts',
  }).outputText;
  const requireGuard = (moduleName: string) => {
    if (moduleName === '../contracts/channel.js') {
      return {
        CHANNEL_SETUP_ERROR_CODES,
        CHANNEL_SETUP_OPERATIONS,
        CHANNEL_SETUP_STATUS_VALUES,
      };
    }
    if (moduleName === '../domain/channelBuilder/config.js') {
      return {
        normalizeChannelSetupConfig: () => {
          throw new Error('Channel config normalization is not exercised by this harness.');
        },
      };
    }
    if (moduleName === '../domain/channelBuilder/types.js') {
      return {
        containsChannelBuilderCredentialMarker: (raw: string) =>
          /(^|[^A-Za-z0-9_])(?:bearer|token|authorization|headers?)(?=$|[^A-Za-z0-9_])/iu.test(raw),
      };
    }
    return assert.fail(`unexpected channel bridge guard require ${moduleName}`);
  };
  const evaluateGuards = new Function('require', 'exports', 'module', compiled);
  evaluateGuards(requireGuard, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateDiagnosticsGuardModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(diagnosticsGuardSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/diagnosticsBridgeGuards.cts',
  }).outputText;
  const requireGuard = (moduleName: string) => {
    assert.fail(`unexpected diagnostics bridge guard require ${moduleName}`);
  };
  const evaluateGuards = new Function('require', 'exports', 'module', compiled);
  evaluateGuards(requireGuard, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluatePreloadChannelsModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(preloadChannelsSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/channels.cts',
  }).outputText;
  const requireChannels = (moduleName: string) => {
    assert.fail(`unexpected preload channels require ${moduleName}`);
  };
  const evaluateChannels = new Function('require', 'exports', 'module', compiled);
  evaluateChannels(requireChannels, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateChannelSetupBridgeModule(
  channelGuardExports: Record<string, unknown>,
): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(channelSetupBridgeSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/channelSetupBridge.cts',
  }).outputText;
  const requireBridge = (moduleName: string) => {
    if (moduleName === './channelBridgeGuards.cjs') {
      return channelGuardExports;
    }
    assert.fail(`unexpected channel setup bridge require ${moduleName}`);
  };
  const evaluateBridge = new Function('require', 'exports', 'module', compiled);
  evaluateBridge(requireBridge, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateCustomChannelGuardModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(customChannelGuardSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/customChannelBridgeGuards.cts',
  }).outputText;
  const requireGuard = (moduleName: string) => {
    assert.fail(`unexpected custom channel bridge guard require ${moduleName}`);
  };
  const evaluateGuards = new Function('require', 'exports', 'module', compiled);
  evaluateGuards(requireGuard, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateCustomChannelBridgeModule(
  customChannelGuardExports: Record<string, unknown>,
): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(customChannelBridgeSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/customChannelBridge.cts',
  }).outputText;
  const requireBridge = (moduleName: string) => {
    if (moduleName === './customChannelBridgeGuards.cjs') {
      return customChannelGuardExports;
    }
    assert.fail(`unexpected custom channel bridge require ${moduleName}`);
  };
  const evaluateBridge = new Function('require', 'exports', 'module', compiled);
  evaluateBridge(requireBridge, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateGuideBridgeModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(guideBridgeSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/guideBridge.cts',
  }).outputText;
  const requireGuide = (moduleName: string) => {
    assert.fail(`unexpected guide bridge require ${moduleName}`);
  };
  const evaluateGuide = new Function('require', 'exports', 'module', compiled);
  evaluateGuide(requireGuide, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluatePlayerBridgeModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(playerBridgeSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/playerBridge.cts',
  }).outputText;
  const requirePlayerBridge = (moduleName: string) => {
    assert.fail(`unexpected player bridge require ${moduleName}`);
  };
  const evaluatePlayerBridge = new Function('require', 'exports', 'module', compiled);
  evaluatePlayerBridge(requirePlayerBridge, exportsObject, moduleObject);
  return moduleObject.exports as Record<string, unknown>;
}

function evaluatePlayerRecoveryBridgeModule(): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(playerRecoveryBridgeSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/playerRecoveryBridge.cts',
  }).outputText;
  new Function('require', 'exports', 'module', compiled)(
    (moduleName: string) => {
      if (moduleName === '../contracts/shell.js') {
        return { PLAYER_RECOVERY_ACTIONS };
      }
      return assert.fail(`unexpected player recovery bridge require ${moduleName}`);
    },
    exportsObject,
    moduleObject,
  );
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateSettingsGuardModule(): Record<string, unknown> {
  const sharedExports = {};
  const sharedModule = { exports: sharedExports };
  const compiledShared = ts.transpileModule(settingsAudioValidationSourceText, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: 'src/contracts/settingsAudioValidation.ts',
  }).outputText;
  new Function('require', 'exports', 'module', compiledShared)(
    (moduleName: string) => assert.fail(`unexpected settings audio validation require ${moduleName}`),
    sharedExports,
    sharedModule,
  );
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(settingsGuardSourceText, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: 'src/preload/settingsBridgeGuards.cts',
  }).outputText;
  new Function('require', 'exports', 'module', compiled)(
    (moduleName: string) => {
      if (moduleName === '../contracts/settingsAudioValidation.js') {
        return sharedModule.exports;
      }
      return assert.fail(`unexpected settings guard require ${moduleName}`);
    },
    exportsObject,
    moduleObject,
  );
  return moduleObject.exports as Record<string, unknown>;
}

function evaluateSettingsBridgeModule(guards: Record<string, unknown>): Record<string, unknown> {
  const exportsObject = {};
  const moduleObject = { exports: exportsObject };
  const compiled = ts.transpileModule(settingsBridgeSourceText, {
    compilerOptions: { module: ts.ModuleKind.CommonJS, target: ts.ScriptTarget.ES2022 },
    fileName: 'src/preload/settingsBridge.cts',
  }).outputText;
  new Function('require', 'exports', 'module', compiled)(
    (moduleName: string) => {
      if (moduleName === './settingsBridgeGuards.cjs') return guards;
      return assert.fail(`unexpected settings bridge require ${moduleName}`);
    },
    exportsObject,
    moduleObject,
  );
  return moduleObject.exports as Record<string, unknown>;
}

function createPreloadHarness(
  invoke: (
    channel: string,
    request: unknown,
    input: (value: unknown) => unknown,
  ) => unknown | Promise<unknown>,
): {
  api: Record<string, { [method: string]: (...args: unknown[]) => Promise<unknown> }>;
  calls: PreloadInvokeCall[];
  input: (value: unknown) => unknown;
} {
  const calls: PreloadInvokeCall[] = [];
  let exposedApi: unknown = null;
  const input = (value: unknown) => JSON.parse(JSON.stringify(value)) as unknown;
  const channelGuardExports = evaluateChannelGuardModule();
  const diagnosticsGuardExports = evaluateDiagnosticsGuardModule();
  const preloadChannelExports = evaluatePreloadChannelsModule();
  const channelSetupBridgeExports = evaluateChannelSetupBridgeModule(channelGuardExports);
  const customChannelGuardExports = evaluateCustomChannelGuardModule();
  const customChannelBridgeExports = evaluateCustomChannelBridgeModule(customChannelGuardExports);
  const guideBridgeExports = evaluateGuideBridgeModule();
  const playerBridgeExports = evaluatePlayerBridgeModule();
  const playerRecoveryBridgeExports = evaluatePlayerRecoveryBridgeModule();
  const settingsBridgeExports = evaluateSettingsBridgeModule(evaluateSettingsGuardModule());
  const compiled = ts.transpileModule(preloadSourceText, {
    compilerOptions: {
      module: ts.ModuleKind.CommonJS,
      target: ts.ScriptTarget.ES2022,
    },
    fileName: 'src/preload/index.cts',
  }).outputText;
  const requireElectron = (moduleName: string) => {
    if (moduleName === './channelBridgeGuards.cjs') {
      return channelGuardExports;
    }
    if (moduleName === './channels.cjs') {
      return preloadChannelExports;
    }
    if (moduleName === './channelSetupBridge.cjs') {
      return channelSetupBridgeExports;
    }
    if (moduleName === './customChannelBridge.cjs') {
      return customChannelBridgeExports;
    }
    if (moduleName === './diagnosticsBridgeGuards.cjs') {
      return diagnosticsGuardExports;
    }
    if (moduleName === './guideBridge.cjs') {
      return guideBridgeExports;
    }
    if (moduleName === './playerBridge.cjs') {
      return playerBridgeExports;
    }
    if (moduleName === './playerRecoveryBridge.cjs') {
      return playerRecoveryBridgeExports;
    }
    if (moduleName === './settingsBridge.cjs') {
      return settingsBridgeExports;
    }
    assert.equal(moduleName, 'electron');
    return {
      contextBridge: {
        exposeInMainWorld: (key: string, value: unknown) => {
          assert.equal(key, 'lineupDesktop');
          exposedApi = value;
        },
      },
      ipcRenderer: {
        invoke: async (channel: string, request: unknown) => {
          assert.ok(isPreloadInvokeRequest(request));
          calls.push({ channel, request });
          return invoke(channel, request, input);
        },
        on: () => undefined,
        removeListener: () => undefined,
      },
    };
  };
  const exportsObject = {};
  const evaluatePreload = new Function('require', 'exports', compiled);
  evaluatePreload(requireElectron, exportsObject);
  assert.ok(exposedApi !== null && typeof exposedApi === 'object');
  return {
    api: exposedApi as Record<string, { [method: string]: (...args: unknown[]) => Promise<unknown> }>,
    calls,
    input,
  };
}

function isPreloadInvokeRequest(value: unknown): value is { requestId: string; payload?: unknown } {
  return (
    typeof value === 'object' &&
    value !== null &&
    'requestId' in value &&
    typeof value.requestId === 'string'
  );
}

function isPlexInvokeRequest(value: unknown): value is { requestId: string; payload: unknown } {
  return isPreloadInvokeRequest(value) && 'payload' in value;
}

function createSafePlexSnapshot(): Record<string, unknown> {
  return {
    auth: {
      state: 'signed-in',
      pin: { id: 42, code: 'ABCD', expiresAtMs: 2, claimed: false },
      profile: { accountId: 'account-1', displayName: 'Profile' },
      homeUsers: [{ id: 'home-1', title: 'Profile', admin: false, protected: true }],
      credentialStatus: 'present',
    },
    servers: {
      status: 'ready',
      selected: null,
      items: [],
      lastSelection: null,
    },
    library: {
      status: 'ready',
      sections: [],
      selectedSectionId: null,
      items: [],
      search: null,
      metadata: null,
    },
    lastError: null,
    updatedAtMs: 3,
  };
}

function createSafePlexFailure(
  operation: string,
  requestId: string,
  code = 'PLEX_AUTH_REQUIRED',
): Record<string, unknown> {
  return {
    ok: false,
    requestId,
    error: {
      code,
      message: 'Plex request failed.',
      retryable: false,
      recoverable: true,
      operation,
    },
  };
}

function createSafePlayerSnapshot(): Record<string, unknown> {
  return {
    requestId: 'player-load-1',
    status: 'playing',
    media: { id: 'media-1', title: 'Episode 1' },
    capabilityProfileId: 'profile-1',
    seekSupport: 'supported',
    positionMs: 1,
    durationMs: null,
    bufferedRanges: [],
    playing: true,
    volume: 1,
    muted: false,
    playbackRate: 1,
    selectedAudioTrackId: null,
    selectedSubtitleTrackId: null,
    selectedVideoTrackId: null,
    tracks: [],
    quality: {
      mode: 'direct-play',
      sourceDynamicRange: 'hlg',
      outputDynamicRangeStatus: 'unknown',
    },
    lastError: null,
  };
}

function createSafeCustomChannelSnapshot(): Record<string, unknown> {
  return {
    channels: [],
    currentChannelId: null,
    visibleChannelCount: 0,
    hiddenChannelCount: 0,
    maxChannels: 500,
    nextAvailableNumber: 1,
    updatedAtMs: 3,
    storage: { status: 'ready', repaired: false },
  };
}

const APPROVED_PRELOAD_CHANNEL_CONSTANTS = {
  LINEUP_SHELL_GET_CAPABILITIES_CHANNEL,
  LINEUP_SHELL_MEDIA_INPUT_CHANNEL,
  LINEUP_WINDOW_INTENT_CHANNEL,
  LINEUP_SHELL_STATUS_CHANGED_CHANNEL,
  LINEUP_PLAYER_COMMAND_CHANNEL,
  LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLAYER_CLEANUP_CHANNEL,
  LINEUP_PLAYER_EVENT_CHANNEL,
  LINEUP_PLAYER_RECOVERY_CHANNEL,
  LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL,
  LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL,
  LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL,
  LINEUP_PLEX_GET_SNAPSHOT_CHANNEL,
  LINEUP_PLEX_REQUEST_PIN_CHANNEL,
  LINEUP_PLEX_POLL_PIN_CHANNEL,
  LINEUP_PLEX_CANCEL_PIN_CHANNEL,
  LINEUP_PLEX_GET_HOME_USERS_CHANNEL,
  LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL,
  LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL,
  LINEUP_PLEX_REFRESH_SERVERS_CHANNEL,
  LINEUP_PLEX_SELECT_SERVER_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL,
  LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL,
  LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL,
  LINEUP_PLEX_GET_METADATA_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL,
  LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL,
  LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL,
  LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL,
  LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
  LINEUP_PLAYER_TUNE_CHANNEL,
  LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
  LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL,
  LINEUP_SETTINGS_REPLACE_CHANNEL,
} as const;

const APPROVED_IPC_CHANNELS_BY_METHOD = {
  invoke: new Set([
    'LINEUP_SHELL_GET_CAPABILITIES_CHANNEL',
    'LINEUP_WINDOW_INTENT_CHANNEL',
    'LINEUP_PLAYER_COMMAND_CHANNEL',
    'LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLAYER_CLEANUP_CHANNEL',
    'LINEUP_PLAYER_RECOVERY_CHANNEL',
    'LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL',
    'LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL',
    'LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL',
    'LINEUP_PLEX_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLEX_REQUEST_PIN_CHANNEL',
    'LINEUP_PLEX_POLL_PIN_CHANNEL',
    'LINEUP_PLEX_CANCEL_PIN_CHANNEL',
    'LINEUP_PLEX_GET_HOME_USERS_CHANNEL',
    'LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL',
    'LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL',
    'LINEUP_PLEX_REFRESH_SERVERS_CHANNEL',
    'LINEUP_PLEX_SELECT_SERVER_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL',
    'LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL',
    'LINEUP_PLEX_GET_METADATA_CHANNEL',
    'LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL',
    'LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL',
    'LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL',
    'LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL',
    'LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL',
    'LINEUP_GUIDE_GET_PRESENTATION_CHANNEL',
    'LINEUP_PLAYER_TUNE_CHANNEL',
  ]),
  on: new Set([
    'LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'LINEUP_SHELL_MEDIA_INPUT_CHANNEL',
    'LINEUP_PLAYER_EVENT_CHANNEL',
  ]),
  removeListener: new Set([
    'LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'LINEUP_SHELL_MEDIA_INPUT_CHANNEL',
    'LINEUP_PLAYER_EVENT_CHANNEL',
  ]),
} as const;

const APPROVED_IPC_METHODS = new Set(Object.keys(APPROVED_IPC_CHANNELS_BY_METHOD));

function readPreloadStringArrayConst(name: string): string[] {
  const declaration = findPreloadVariableDeclaration(name);
  assert.ok(declaration?.initializer, `expected ${name} in preload entrypoint`);
  return readStringArrayInitializer(preloadSourceFile, name, declaration.initializer);
}

function readCustomChannelGuardStringArrayConst(name: string): string[] {
  const declaration = findVariableDeclaration(customChannelGuardSourceFile, name);
  assert.ok(declaration?.initializer, `expected ${name} in custom channel bridge guards`);
  return readStringArrayInitializer(customChannelGuardSourceFile, name, declaration.initializer);
}

function readDiagnosticsGuardStringArrayConst(name: string): string[] {
  const declaration = findVariableDeclaration(diagnosticsGuardSourceFile, name);
  assert.ok(declaration?.initializer, `expected ${name} in diagnostics bridge guards`);
  return readStringArrayInitializer(diagnosticsGuardSourceFile, name, declaration.initializer);
}

function findPreloadVariableDeclaration(name: string): ts.VariableDeclaration | null {
  return findVariableDeclaration(preloadSourceFile, name);
}

function findVariableDeclaration(
  sourceFile: ts.SourceFile,
  name: string,
): ts.VariableDeclaration | null {
  let result: ts.VariableDeclaration | null = null;

  function visit(node: ts.Node): void {
    if (result !== null) {
      return;
    }
    if (ts.isVariableDeclaration(node) && ts.isIdentifier(node.name) && node.name.text === name) {
      result = node;
      return;
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
  return result;
}

function findDiagnosticsGuardFunctionDeclaration(name: string): ts.FunctionDeclaration | null {
  return findFunctionDeclaration(diagnosticsGuardSourceFile, name);
}

function findFunctionDeclaration(
  sourceFile: ts.SourceFile,
  name: string,
): ts.FunctionDeclaration | null {
  let result: ts.FunctionDeclaration | null = null;

  function visit(node: ts.Node): void {
    if (result !== null) {
      return;
    }
    if (ts.isFunctionDeclaration(node) && node.name?.text === name) {
      result = node;
      return;
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
  return result;
}

function readStringArrayInitializer(
  sourceFile: ts.SourceFile,
  name: string,
  initializer: ts.Expression,
): string[] {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isArrayLiteralExpression(expression), `expected ${name} to be an array literal`);
  return expression.elements.flatMap((element) => {
    if (ts.isSpreadElement(element) && ts.isIdentifier(element.expression)) {
      const declaration = findVariableDeclaration(sourceFile, element.expression.text);
      assert.ok(declaration?.initializer, `expected ${name} spread ${element.expression.text} in ${sourceFile.fileName}`);
      return readStringArrayInitializer(sourceFile, element.expression.text, declaration.initializer);
    }
    assert.ok(ts.isStringLiteral(element), `expected ${name} to contain only string literals or const spreads`);
    return [element.text];
  });
}

function readStringConstInitializer(name: string, initializer: ts.Expression): string {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isStringLiteral(expression), `expected ${name} to be a string literal`);
  return expression.text;
}

function readRegExpConstInitializer(name: string): { pattern: string; flags: string } {
  const declaration = findPreloadVariableDeclaration(name);
  assert.ok(declaration?.initializer, `expected ${name} in preload entrypoint`);
  return readRegExpInitializer(name, declaration.initializer);
}

function readDiagnosticsGuardRegExpConstInitializer(name: string): { pattern: string; flags: string } {
  const declaration = findVariableDeclaration(diagnosticsGuardSourceFile, name);
  assert.ok(declaration?.initializer, `expected ${name} in diagnostics bridge guards`);
  return readRegExpInitializer(name, declaration.initializer);
}

function readRegExpInitializer(name: string, initializer: ts.Expression): { pattern: string; flags: string } {
  const expression = unwrapExpression(initializer);
  assert.ok(ts.isRegularExpressionLiteral(expression), `expected ${name} to be a RegExp literal`);
  const match = /^\/(.*)\/([a-z]*)$/su.exec(expression.text);
  assert.ok(match, `expected ${name} to have a parseable RegExp literal`);
  return { pattern: match[1], flags: match[2] };
}

function unwrapExpression(expression: ts.Expression): ts.Expression {
  let current = expression;
  while (
    ts.isAsExpression(current) ||
    ts.isSatisfiesExpression(current) ||
    ts.isParenthesizedExpression(current)
  ) {
    current = current.expression;
  }
  return current;
}

function collectPreloadChannelConstants(): Map<string, string> {
  const constants = new Map<string, string>();

  function visit(node: ts.Node): void {
    if (
      ts.isVariableDeclaration(node) &&
      ts.isIdentifier(node.name) &&
      node.name.text.endsWith('_CHANNEL')
    ) {
      assert.ok(node.initializer, `${node.name.text} must have a string initializer`);
      assert.ok(
        isTopLevelConstDeclaration(node),
        `${node.name.text} must be a top-level const channel declaration`,
      );
      assert.equal(
        constants.has(node.name.text),
        false,
        `${node.name.text} must not be redeclared`,
      );
      constants.set(node.name.text, readStringConstInitializer(node.name.text, node.initializer));
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadChannelsSourceFile);
  return constants;
}

function collectContextBridgeExposureCalls(): ts.CallExpression[] {
  const calls: ts.CallExpression[] = [];

  function visit(node: ts.Node): void {
    assertNoForbiddenElectronAccess(node);

    if (ts.isIdentifier(node) && node.text === 'contextBridge') {
      assert.ok(
        isApprovedContextBridgeIdentifierUse(node),
        `contextBridge aliasing or direct exposure is not allowed: ${describeNode(node.parent)}`,
      );
    }

    if (
      ts.isElementAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'contextBridge'
    ) {
      assert.fail(`contextBridge dynamic access is not allowed: ${describeNode(node)}`);
    }

    if (
      ts.isPropertyAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'contextBridge' &&
      node.name.text !== 'exposeInMainWorld'
    ) {
      assert.fail(`contextBridge.${node.name.text} is not an approved preload exposure`);
    }

    if (
      ts.isCallExpression(node) &&
      ts.isPropertyAccessExpression(node.expression) &&
      ts.isIdentifier(node.expression.expression) &&
      node.expression.expression.text === 'contextBridge' &&
      node.expression.name.text === 'exposeInMainWorld'
    ) {
      calls.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return calls;
}

function describeNode(node: ts.Node, sourceFile = preloadSourceFile): string {
  return node.getText(sourceFile).replaceAll(/\s+/gu, ' ');
}

function assertNoElectronValueImports(sourceFile = preloadSourceFile): void {
  function visit(node: ts.Node): void {
    if (
      ts.isImportDeclaration(node) &&
      ts.isStringLiteral(node.moduleSpecifier) &&
      node.moduleSpecifier.text === 'electron' &&
      node.importClause !== undefined &&
      !isTypeOnlyImportClause(node.importClause)
    ) {
      assert.fail(`Electron value imports are not allowed in preload: ${describeNode(node, sourceFile)}`);
    }
    ts.forEachChild(node, visit);
  }

  visit(sourceFile);
}

function isTypeOnlyImportClause(importClause: ts.ImportClause): boolean {
  if (importClause.isTypeOnly) {
    return true;
  }
  if (importClause.name !== undefined) {
    return false;
  }
  const namedBindings = importClause.namedBindings;
  return (
    namedBindings !== undefined &&
    ts.isNamedImports(namedBindings) &&
    namedBindings.elements.length > 0 &&
    namedBindings.elements.every((element) => element.isTypeOnly)
  );
}

function isTopLevelConstDeclaration(node: ts.VariableDeclaration): boolean {
  return (
    node.initializer !== undefined &&
    (node.parent.flags & ts.NodeFlags.Const) !== 0 &&
    ts.isVariableStatement(node.parent.parent) &&
    ts.isSourceFile(node.parent.parent.parent)
  );
}

function isElectronRequireBinding(node: ts.Identifier): boolean {
  if (
    !ts.isBindingElement(node.parent) ||
    node.parent.name !== node ||
    !ts.isObjectBindingPattern(node.parent.parent)
  ) {
    return false;
  }

  const declaration = node.parent.parent.parent;
  return ts.isVariableDeclaration(declaration) && isApprovedElectronRequireDeclaration(declaration);
}

function isElectronRequireCall(node: ts.Node): node is ts.CallExpression {
  return (
    ts.isCallExpression(node) &&
    ts.isIdentifier(node.expression) &&
    node.expression.text === 'require' &&
    node.arguments.length === 1 &&
    ts.isStringLiteral(node.arguments[0]) &&
    node.arguments[0].text === 'electron'
  );
}

function isApprovedElectronRequireCall(node: ts.CallExpression): boolean {
  let parent = node.parent;
  while (ts.isAsExpression(parent) || ts.isParenthesizedExpression(parent)) {
    parent = parent.parent;
  }

  return ts.isVariableDeclaration(parent) && isApprovedElectronRequireDeclaration(parent);
}

function isApprovedElectronRequireDeclaration(declaration: ts.VariableDeclaration): boolean {
  return (
    declaration.initializer !== undefined &&
    (declaration.parent.flags & ts.NodeFlags.Const) !== 0 &&
    ts.isVariableStatement(declaration.parent.parent) &&
    ts.isSourceFile(declaration.parent.parent.parent) &&
    isElectronRequireCall(unwrapExpression(declaration.initializer)) &&
    ts.isObjectBindingPattern(declaration.name) &&
    declaration.name.elements.length === 2 &&
    declaration.name.elements[0] !== undefined &&
    declaration.name.elements[1] !== undefined &&
    isExactElectronBindingElement(declaration.name.elements[0], 'contextBridge') &&
    isExactElectronBindingElement(declaration.name.elements[1], 'ipcRenderer')
  );
}

function isExactElectronBindingElement(element: ts.BindingElement, name: string): boolean {
  return (
    element.propertyName === undefined &&
    element.dotDotDotToken === undefined &&
    ts.isIdentifier(element.name) &&
    element.name.text === name &&
    element.initializer === undefined
  );
}

function hasElectronRequireExpression(node: ts.Expression): boolean {
  const expression = unwrapExpression(node);
  if (isElectronRequireCall(expression)) {
    return true;
  }
  if (ts.isPropertyAccessExpression(expression) || ts.isElementAccessExpression(expression)) {
    return hasElectronRequireExpression(expression.expression);
  }
  return false;
}

function isApprovedIpcRendererIdentifierUse(node: ts.Identifier): boolean {
  return (
    isElectronRequireBinding(node) ||
    (ts.isPropertyAccessExpression(node.parent) &&
      node.parent.expression === node &&
      ts.isCallExpression(node.parent.parent) &&
      node.parent.parent.expression === node.parent)
  );
}

function isApprovedContextBridgeIdentifierUse(node: ts.Identifier): boolean {
  return (
    isElectronRequireBinding(node) ||
    (ts.isPropertyAccessExpression(node.parent) &&
      node.parent.expression === node &&
      node.parent.name.text === 'exposeInMainWorld' &&
      ts.isCallExpression(node.parent.parent) &&
      node.parent.parent.expression === node.parent)
  );
}

function collectBindingIdentifiers(name: string): ts.Identifier[] {
  const bindings: ts.Identifier[] = [];

  function visit(node: ts.Node): void {
    if (ts.isIdentifier(node) && node.text === name && isBindingIdentifier(node)) {
      bindings.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return bindings;
}

function isBindingIdentifier(node: ts.Identifier): boolean {
  const parent = node.parent;
  return (
    (ts.isVariableDeclaration(parent) && parent.name === node) ||
    (ts.isBindingElement(parent) && parent.name === node) ||
    (ts.isParameter(parent) && parent.name === node) ||
    (ts.isFunctionDeclaration(parent) && parent.name === node) ||
    (ts.isClassDeclaration(parent) && parent.name === node) ||
    (ts.isTypeAliasDeclaration(parent) && parent.name === node) ||
    (ts.isInterfaceDeclaration(parent) && parent.name === node) ||
    (ts.isImportSpecifier(parent) && parent.name === node) ||
    (ts.isImportClause(parent) && parent.name === node) ||
    (ts.isNamespaceImport(parent) && parent.name === node)
  );
}

function assertApprovedChannelIdentifier(name: string): void {
  assert.ok(
    Object.hasOwn(APPROVED_PRELOAD_CHANNEL_CONSTANTS, name),
    `${name} is not an approved preload channel constant`,
  );
  const bindings = collectBindingIdentifiers(name);
  assert.equal(bindings.length, 1, `${name} must have exactly one binding`);

  const declaration = findVariableDeclaration(preloadChannelsSourceFile, name);
  assert.ok(declaration, `${name} must be declared in preload channel constants`);
  assert.ok(isTopLevelConstDeclaration(declaration), `${name} must be a top-level const`);
  assert.ok(declaration.initializer, `${name} must have a string initializer`);
  assert.equal(
    readStringConstInitializer(name, declaration.initializer),
    APPROVED_PRELOAD_CHANNEL_CONSTANTS[name as keyof typeof APPROVED_PRELOAD_CHANNEL_CONSTANTS],
    `${name} must match ipc.ts`,
  );
}

function isInvokePlexChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isFunctionDeclaration(current) &&
      current.name?.text === 'invokePlex' &&
      current.parameters.some((parameter) => ts.isIdentifier(parameter.name) && parameter.name.text === 'channel')
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokeChannelSetupChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isVariableDeclaration(current) &&
      ts.isIdentifier(current.name) &&
      current.name.text === 'invokeChannelSetup'
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokeCustomChannelsChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isVariableDeclaration(current) &&
      ts.isIdentifier(current.name) &&
      current.name.text === 'invokeCustomChannels'
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokeGuideChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isVariableDeclaration(current) &&
      ts.isIdentifier(current.name) &&
      current.name.text === 'invokeGuide'
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokePlayerSnapshotChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isVariableDeclaration(current) &&
      ts.isIdentifier(current.name) &&
      current.name.text === 'invokePlayerSnapshot'
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokePlayerRecoveryChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') {
    return false;
  }
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (
      ts.isVariableDeclaration(current) &&
      ts.isIdentifier(current.name) &&
      current.name.text === 'invokePlayerRecovery'
    ) {
      return true;
    }
    current = current.parent;
  }
  return false;
}

function isInvokeSettingsChannelParameter(node: ts.Identifier): boolean {
  if (node.text !== 'channel') return false;
  let current: ts.Node | undefined = node;
  while (current !== undefined && !ts.isSourceFile(current)) {
    if (ts.isVariableDeclaration(current) && ts.isIdentifier(current.name) &&
      current.name.text === 'invokeSettings') return true;
    current = current.parent;
  }
  return false;
}

function assertApprovedElectronRequireBinding(): void {
  const declarations: ts.VariableDeclaration[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isVariableDeclaration(node) &&
      node.initializer !== undefined &&
      isElectronRequireCall(unwrapExpression(node.initializer))
    ) {
      declarations.push(node);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  assert.equal(declarations.length, 1, 'expected exactly one Electron require binding');
  assert.ok(
    isApprovedElectronRequireDeclaration(declarations[0]),
    'expected exact top-level const { contextBridge, ipcRenderer } = require("electron") binding',
  );
}

function collectInvokePlexChannelArguments(): string[] {
  const channels: string[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'invokePlex'
    ) {
      const [channelExpression] = node.arguments;
      assert.ok(channelExpression, 'invokePlex must pass a channel');
      assert.ok(ts.isIdentifier(channelExpression), 'invokePlex channel must be a constant');
      assertApprovedChannelIdentifier(channelExpression.text);
      channels.push(channelExpression.text);
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return channels;
}

function collectCreateChannelSetupBridgeChannelArguments(): string[] {
  const channels: string[] = [];

  function visit(node: ts.Node): void {
    if (
      ts.isCallExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'createChannelSetupBridge'
    ) {
      const [invokeExpression, channelsExpression] = node.arguments;
      assert.ok(invokeExpression, 'createChannelSetupBridge must pass an invoke function');
      assert.ok(
        ts.isIdentifier(invokeExpression) && invokeExpression.text === 'invokeChannelSetup',
        'createChannelSetupBridge must receive the narrow channel setup invoke function',
      );
      const channelBindings = channelsExpression === undefined
        ? undefined
        : unwrapExpression(channelsExpression);
      assert.ok(
        channelBindings !== undefined && ts.isObjectLiteralExpression(channelBindings),
        'createChannelSetupBridge must receive literal channel bindings',
      );
      for (const property of channelBindings.properties) {
        assert.ok(ts.isPropertyAssignment(property), 'channel setup bridge channels must be property assignments');
        assert.ok(ts.isIdentifier(property.initializer), 'channel setup bridge channel values must be constants');
        assertApprovedChannelIdentifier(property.initializer.text);
        channels.push(property.initializer.text);
      }
    }
    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);
  return channels;
}

function assertNoForbiddenElectronAccess(node: ts.Node): void {
  if (ts.isCallExpression(node) && isElectronRequireCall(node)) {
    assert.ok(
      isApprovedElectronRequireCall(node),
      `Electron require must stay as the approved destructured binding: ${describeNode(node.parent)}`,
    );
  }

  if (
    (ts.isPropertyAccessExpression(node) || ts.isElementAccessExpression(node)) &&
    hasElectronRequireExpression(node.expression)
  ) {
    assert.fail(`Dynamic Electron member access is not allowed: ${describeNode(node)}`);
  }
}

test('preload guard vocabulary matches contract vocabulary', () => {
  assert.doesNotMatch(preloadSourceText, /\.\/vocabulary\.cjs/u);
  assert.deepEqual(readDiagnosticsGuardRegExpConstInitializer('DIAGNOSTICS_REQUEST_ID_PATTERN'), {
    pattern: DIAGNOSTICS_REQUEST_ID_PATTERN_SOURCE,
    flags: 'u',
  });
  assert.deepEqual(readRegExpConstInitializer('PLEX_REQUEST_ID_PATTERN'), {
    pattern: '^[A-Za-z0-9._-]{1,120}$',
    flags: 'u',
  });
  assert.deepEqual(readDiagnosticsGuardRegExpConstInitializer('DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN'), {
    pattern: DIAGNOSTICS_UNSAFE_RENDERER_CONTEXT_VALUE_PATTERN_SOURCE,
    flags: 'iu',
  });
  assert.deepEqual(readPreloadStringArrayConst('SHELL_STATUS_VALUES'), [...SHELL_STATUS_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_ERROR_CATEGORIES'), [...PLAYER_ERROR_CATEGORIES]);
  assert.deepEqual(
    readPreloadStringArrayConst('PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS'),
    [...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS],
  );
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_STATUS_VALUES'), [...PLAYER_STATUS_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_COMMAND_VALUES'), [...PLAYER_COMMAND_VALUES]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_RENDERER_INTENT_VALUES'), [
    ...PLAYER_RENDERER_INTENTS,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('PLAYER_TRACK_KIND_VALUES'), [
    ...PLAYER_TRACK_KIND_VALUES,
  ]);
  assert.deepEqual(
    readPreloadStringArrayConst('PLAYER_TRACK_DELIVERY_TYPE_VALUES'),
    [...PLAYER_TRACK_DELIVERY_TYPE_VALUES],
  );
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTIC_SURFACES'), [
    ...DIAGNOSTIC_SURFACES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTIC_CATEGORIES'), [
    ...DIAGNOSTIC_CATEGORIES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTIC_SEVERITIES'), [
    ...DIAGNOSTIC_SEVERITIES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTIC_STATUSES'), [
    ...DIAGNOSTIC_STATUSES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTICS_RENDERER_EVENT_CATEGORIES'), [
    ...DIAGNOSTICS_RENDERER_EVENT_CATEGORIES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTICS_RENDERER_EVENT_SEVERITIES'), [
    ...DIAGNOSTICS_RENDERER_EVENT_SEVERITIES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('DIAGNOSTICS_ERROR_CODES'), [
    ...DIAGNOSTICS_ERROR_CODES,
  ]);
  assert.deepEqual(readDiagnosticsGuardStringArrayConst('REDACTION_SCAN_FINDING_LABELS'), [
    ...REDACTION_SCAN_FINDING_LABELS,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('PLEX_RUNTIME_OPERATIONS'), [
    ...PLEX_RUNTIME_OPERATIONS,
  ]);
  assert.deepEqual(readPreloadStringArrayConst('PLEX_RUNTIME_ERROR_CODES'), [
    ...PLEX_RUNTIME_ERROR_CODES,
  ]);
  assert.match(channelGuardSourceText, /CHANNEL_SETUP_STATUS_VALUES/u);
  assert.match(channelGuardSourceText, /CHANNEL_SETUP_ERROR_CODES/u);
  assert.match(channelGuardSourceText, /CHANNEL_SETUP_OPERATIONS/u);
  assert.deepEqual([...CHANNEL_SETUP_BUILD_MODES], ['append', 'replace', 'merge']);
  assert.ok(CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS.length > 0);
  assert.deepEqual(readCustomChannelGuardStringArrayConst('CUSTOM_CHANNEL_OPERATIONS'), [
    ...CUSTOM_CHANNEL_OPERATIONS,
  ]);
  assert.deepEqual(readCustomChannelGuardStringArrayConst('CUSTOM_CHANNEL_ERROR_CODES'), [
    ...CUSTOM_CHANNEL_ERROR_CODES,
  ]);
  assert.deepEqual(readCustomChannelGuardStringArrayConst('CUSTOM_CHANNEL_VALIDATION_CODES'), [
    ...CUSTOM_CHANNEL_VALIDATION_CODES,
  ]);
  assert.deepEqual(
    readCustomChannelGuardStringArrayConst('CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS'),
    [...CUSTOM_CHANNEL_FORBIDDEN_RENDERER_FIELD_KEYS],
  );
  const preloadPlexForbiddenKeys = readPreloadStringArrayConst('PLEX_FORBIDDEN_RENDERER_FIELD_KEYS');
  assert.deepEqual(
    [...new Set(preloadPlexForbiddenKeys)].sort(),
    [...new Set(PLEX_FORBIDDEN_RENDERER_FIELD_KEYS)].sort(),
  );
  assert.equal(preloadPlexForbiddenKeys.length, new Set(preloadPlexForbiddenKeys).size);
});

test('preload Plex bridge validates invoke results before returning them', async () => {
  const snapshot = createSafePlexSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        sectionId: '1',
        offset: 0,
        limit: 25,
        items: [],
        snapshot,
      },
    });
  });

  const result = await harness.api.plex.listLibraryItems(harness.input({
    sectionId: '1',
    offset: 0.9,
    filter: { type: 1, year: 2020 },
    includeCollections: true,
  }));

  assert.equal(harness.calls.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(harness.calls[0]?.request.payload)), {
    sectionId: '1',
    offset: 0,
    filter: { type: 1, year: 2020 },
    includeCollections: true,
  });
  assert.equal((result as { ok: boolean }).ok, true);
});

test('preload player bridge validates snapshot invoke results before returning them', async () => {
  const snapshot = createSafePlayerSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: snapshot,
    });
  });

  const result = await harness.api.player.getSnapshot();

  assert.equal(harness.calls.length, 1);
  assert.equal((result as { ok: boolean }).ok, true);
});

test('preload player recovery bridge exposes only the closed action vocabulary and validates settlement', async () => {
  const snapshot = createSafePlayerSnapshot();
  const accepted = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: { status: 'accepted', snapshot },
    });
  });

  const acceptedResult = await accepted.api.player.recover(
    accepted.input({ action: 'retry-current' }),
  );

  assert.equal((acceptedResult as { ok: boolean }).ok, true);
  assert.equal(accepted.calls.length, 1);
  assert.equal(accepted.calls[0]?.channel, LINEUP_PLAYER_RECOVERY_CHANNEL);
  assert.deepEqual(accepted.calls[0]?.request.payload, { action: 'retry-current' });

  const invalidResult = await accepted.api.player.recover(
    accepted.input({ action: 'restart-player' }),
  );
  assert.equal((invalidResult as { ok: boolean }).ok, false);
  assert.equal(accepted.calls.length, 1);

  const rejected = createPreloadHarness(() => Promise.reject(new Error('private rejection')));
  const rejectedResult = await rejected.api.player.recover(
    rejected.input({ action: 'skip-next' }),
  );
  assert.equal((rejectedResult as { ok: boolean }).ok, false);
  assert.equal(
    (rejectedResult as { error: { code: string; message: string } }).error.code,
    'PLAYER_OPERATION_UNAVAILABLE',
  );
  assert.equal(
    (rejectedResult as { error: { recoverable: boolean; retryable: boolean } })
      .error.recoverable,
    true,
  );
  assert.equal(
    (rejectedResult as { error: { recoverable: boolean; retryable: boolean } })
      .error.retryable,
    true,
  );
  assert.doesNotMatch(
    (rejectedResult as { error: { message: string } }).error.message,
    /private rejection/u,
  );

  const mismatched = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: `${request.requestId}-mismatch`,
      value: { status: 'accepted', snapshot },
    });
  });
  const mismatchedResult = await mismatched.api.player.recover(
    mismatched.input({ action: 'retry-current' }),
  );
  assert.equal((mismatchedResult as { ok: boolean }).ok, false);
  assert.equal(
    (mismatchedResult as { error: { code: string } }).error.code,
    'PLAYER_RECOVERY_VALIDATION_FAILED',
  );

  const nestedForbiddenError = {
    code: 'PLAYER_RECOVERY_UNAVAILABLE',
    category: 'unknown',
    message: 'Player recovery is unavailable.',
    recoverable: true,
    retryable: true,
    diagnostic: {
      component: 'player-recovery',
      operation: 'recover',
      counts: { nativeHandle: 1 },
    },
  };
  const privilegedAccepted = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        status: 'accepted',
        snapshot: {
          ...snapshot,
          lastError: nestedForbiddenError,
        },
      },
    });
  });
  const privilegedAcceptedResult = await privilegedAccepted.api.player.recover(
    privilegedAccepted.input({ action: 'retry-current' }),
  );
  assert.equal((privilegedAcceptedResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedAcceptedResult as { error: { code: string } }).error.code,
    'PLAYER_RECOVERY_VALIDATION_FAILED',
  );
  assert.doesNotMatch(JSON.stringify(privilegedAcceptedResult), /nativeHandle/u);

  const privilegedFailure = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: false,
      requestId: request.requestId,
      value: { status: 'failed', snapshot },
      error: nestedForbiddenError,
    });
  });
  const privilegedFailureResult = await privilegedFailure.api.player.recover(
    privilegedFailure.input({ action: 'skip-next' }),
  );
  assert.equal((privilegedFailureResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedFailureResult as { error: { code: string } }).error.code,
    'PLAYER_RECOVERY_VALIDATION_FAILED',
  );
  assert.doesNotMatch(JSON.stringify(privilegedFailureResult), /nativeHandle/u);
});

test('preload custom channel bridge validates renderer requests and invoke results', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        items: [],
        offset: 0,
        limit: 24,
        total: null,
        hasMore: false,
      },
    });
  });

  const invalid = await harness.api.customChannels.listMedia(harness.input({
    sourceType: 'search',
    query: 'http://private',
  }));
  assert.equal((invalid as { ok: boolean }).ok, false);
  assert.equal((invalid as { error: { code: string } }).error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');
  assert.equal(harness.calls.length, 0);

  const valid = await harness.api.customChannels.listMedia(harness.input({
    sourceType: 'search',
    query: 'movie',
    limit: 24,
  }));
  assert.equal((valid as { ok: boolean }).ok, true);
  assert.equal(harness.calls.length, 1);
  assert.deepEqual(JSON.parse(JSON.stringify(harness.calls[0]?.request.payload)), {
    sourceType: 'search',
    query: 'movie',
    limit: 24,
  });
});

test('preload custom channel bridge rejects forbidden invoke result fields', async () => {
  const privilegedSuccess = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        ...createSafeCustomChannelSnapshot(),
        token: 'private',
      },
    });
  });
  const successResult = await privilegedSuccess.api.customChannels.getSnapshot();
  assert.equal((successResult as { ok: boolean }).ok, false);
  assert.equal(
    (successResult as { error: { code: string } }).error.code,
    'CUSTOM_CHANNEL_VALIDATION_FAILED',
  );

  const privilegedFailure = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: false,
      requestId: request.requestId,
      error: {
        code: 'CUSTOM_CHANNEL_UNKNOWN',
        message: 'Failed with token=private.',
        retryable: false,
        recoverable: false,
        operation: 'getSnapshot',
      },
    });
  });
  const failureResult = await privilegedFailure.api.customChannels.getSnapshot();
  assert.equal((failureResult as { ok: boolean }).ok, false);
  assert.doesNotMatch(
    (failureResult as { error: { message: string } }).error.message,
    /token=|private/u,
  );
  assert.equal(
    (failureResult as { error: { code: string } }).error.code,
    'CUSTOM_CHANNEL_VALIDATION_FAILED',
  );
});

test('preload player bridge converts malformed or privileged snapshot results to local validation failures', async () => {
  const privileged = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        ...createSafePlayerSnapshot(),
        quality: {
          mode: 'direct-play',
          sourceDynamicRange: 'hlg',
          outputDynamicRangeStatus: 'unknown',
          rawQualitySource: 'private',
        },
      },
    });
  });
  const privilegedResult = await privileged.api.player.getSnapshot();

  assert.equal((privilegedResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedResult as { error: { code: string } }).error.code,
    'PLAYER_VALIDATION_FAILED',
  );

  const mismatched = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: `${request.requestId}-mismatch`,
      value: createSafePlayerSnapshot(),
    });
  });
  const mismatchedResult = await mismatched.api.player.cleanup();

  assert.equal((mismatchedResult as { ok: boolean }).ok, false);
  assert.equal(
    (mismatchedResult as { error: { code: string } }).error.code,
    'PLAYER_VALIDATION_FAILED',
  );
});

test('preload player dispatch validates invoke results before returning them', async () => {
  const snapshot = createSafePlayerSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        accepted: true,
        events: [{ event: 'state.changed', requestId: request.requestId, snapshot }],
        snapshot,
      },
    });
  });

  const result = await harness.api.player.dispatch(harness.input({
    intent: 'player.play',
    requestId: 'player-command-1',
    payload: {},
  }));

  assert.equal(harness.calls.length, 1);
  assert.equal((result as { ok: boolean }).ok, true);
});

test('preload player dispatch forwards guarded lifecycle intent envelopes unchanged', async () => {
  const snapshot = createSafePlayerSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: { accepted: true, events: [], snapshot },
    });
  });
  const envelopes = [
    {
      intent: 'player.pauseIfCurrent',
      requestId: 'settings-pause-1',
      payload: { snapshotRequestId: 'player-load-1' },
    },
    {
      intent: 'player.stopIfCurrent',
      requestId: 'input-stop-1',
      payload: { snapshotRequestId: 'player-load-1' },
    },
    {
      intent: 'player.seekRelativeIfCurrent',
      requestId: 'input-seek-1',
      payload: { snapshotRequestId: 'player-load-1', deltaMs: -10_000 },
    },
  ];

  for (const envelope of envelopes) {
    const result = await harness.api.player.dispatch(harness.input(envelope));
    assert.equal((result as { ok: boolean }).ok, true);
  }
  assert.deepEqual(harness.calls, envelopes.map((request) => ({
    channel: LINEUP_PLAYER_COMMAND_CHANNEL,
    request,
  })));
});

test('preload player dispatch converts malformed or privileged invoke results to local validation failures', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPreloadInvokeRequest(request));
    const snapshot = createSafePlayerSnapshot();
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        accepted: true,
        events: [{
          event: 'state.changed',
          requestId: request.requestId,
          snapshot: {
            ...snapshot,
            media: { id: 'media-1', title: 'Episode 1', playbackUrl: 'private' },
          },
        }],
        snapshot,
      },
    });
  });

  const result = await harness.api.player.dispatch(harness.input({
    intent: 'player.play',
    requestId: 'player-command-2',
    payload: {},
  }));

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLAYER_VALIDATION_FAILED',
  );
});

test('guide bridge validates presentation request ranges and result envelopes', async () => {
  const guideBridgeExports = evaluateGuideBridgeModule();
  const createGuideBridge = guideBridgeExports.createGuideBridge as (
    invoke: (channel: string, request: { requestId: string; payload: unknown }) => Promise<unknown>,
    channels: { getPresentation: string; tuneChannel: string },
    createRequestId: (prefix: string) => string,
  ) => { getPresentation: (input: { startTimeMs: number; durationMs: number }) => Promise<unknown> };
  const validPresentation = {
    channels: [
      {
        id: 'channel-1',
        number: '1',
        name: 'Channel One',
        programs: [
          {
            id: 'program-1',
            title: 'Program One',
            subtitle: '',
            description: 'A safe description.',
            showTitle: '',
            episodeLabel: '',
            rating: 'TV-PG',
            quality: ['HD'],
            genres: ['Drama'],
            startsAtMs: 1,
            endsAtMs: 2,
          },
        ],
      },
    ],
    nowWatching: {
      title: 'Program One',
      subtitle: '',
      channelId: 'channel-1',
      startsAtMs: 1,
      endsAtMs: 2,
    },
  };

  let invoked = false;
  const bridge = createGuideBridge(
    async (_channel, request) => {
      invoked = true;
      return {
        ok: true,
        requestId: request.requestId,
        value: validPresentation,
      };
    },
    {
      getPresentation: LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
      tuneChannel: LINEUP_PLAYER_TUNE_CHANNEL,
    },
    () => 'guide-request-1',
  );

  const invalidRange = await bridge.getPresentation({ startTimeMs: 0, durationMs: 0 });
  assert.equal((invalidRange as { ok: boolean }).ok, false);
  assert.equal(invoked, false);

  const valid = await bridge.getPresentation({ startTimeMs: 0, durationMs: 60_000 });
  assert.equal((valid as { ok: boolean }).ok, true);

  const wrongRequestBridge = createGuideBridge(
    async () => ({
      ok: true,
      requestId: 'other-request',
      value: validPresentation,
    }),
    {
      getPresentation: LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
      tuneChannel: LINEUP_PLAYER_TUNE_CHANNEL,
    },
    () => 'guide-request-2',
  );
  const wrongRequest = await wrongRequestBridge.getPresentation({ startTimeMs: 0, durationMs: 60_000 });
  assert.equal((wrongRequest as { ok: boolean }).ok, false);

  const extraFieldBridge = createGuideBridge(
    async (_channel, request) => ({
      ok: true,
      requestId: request.requestId,
      value: {
        ...validPresentation,
        token: 'secret-token',
      },
    }),
    {
      getPresentation: LINEUP_GUIDE_GET_PRESENTATION_CHANNEL,
      tuneChannel: LINEUP_PLAYER_TUNE_CHANNEL,
    },
    () => 'guide-request-3',
  );
  const extraField = await extraFieldBridge.getPresentation({ startTimeMs: 0, durationMs: 60_000 });
  assert.equal((extraField as { ok: boolean }).ok, false);
});

test('preload Plex bridge accepts nullable metadata and search types', async () => {
  const snapshot = createSafePlexSnapshot();
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        item: null,
        snapshot,
      },
    });
  });

  const metadata = await harness.api.plex.getMetadata(harness.input({ ratingKey: 'missing' }));

  assert.equal((metadata as { ok: boolean }).ok, true);

  const searchHarness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        query: 'movie',
        sectionId: null,
        items: [],
        snapshot,
      },
    });
  });
  const search = await searchHarness.api.plex.searchLibrary(
    searchHarness.input({ query: 'movie', limit: 10, types: ['movie', 'episode'] }),
  );

  assert.equal((search as { ok: boolean }).ok, true);
  assert.deepEqual(JSON.parse(JSON.stringify(searchHarness.calls[0]?.request.payload)), {
    query: 'movie',
    limit: 10,
    types: ['movie', 'episode'],
  });
});

test('preload Plex bridge converts malformed or privileged invoke results to local validation failures', async () => {
  const privileged = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: { snapshot: createSafePlexSnapshot(), accessToken: 'private' },
    });
  });
  const privilegedResult = await privileged.api.plex.getSnapshot();

  assert.equal((privilegedResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedResult as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );

  const malformedCancelled = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ...createSafePlexFailure('pollPin', request.requestId, 'PLEX_CANCELLED'),
      cancelled: false,
    });
  });
  const malformedCancelledResult = await malformedCancelled.api.plex.pollPin(
    malformedCancelled.input({ pinId: 42 }),
  );

  assert.equal((malformedCancelledResult as { ok: boolean }).ok, false);
  assert.equal(
    (malformedCancelledResult as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
});

test('preload Plex bridge converts invoke rejections to local validation failures', async () => {
  const harness = createPreloadHarness(() => {
    throw new Error('raw token serverUri failure');
  });

  const result = await harness.api.plex.getSnapshot();

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal(
    (result as { error: { message: string; operation: string } }).error.message,
    'Plex invoke failed (Error).',
  );
  assert.equal(
    (result as { error: { message: string; operation: string } }).error.operation,
    'getSnapshot',
  );
  assert.doesNotMatch(JSON.stringify(result), /raw token|serverUri/u);
});

test('preload Plex bridge rejects mismatched success request ids locally', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: `${request.requestId}-mismatch`,
      value: createSafePlexSnapshot(),
    });
  });

  const result = await harness.api.plex.getSnapshot();

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
});

test('preload Plex bridge rejects mismatched failure request ids locally', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input(createSafePlexFailure('pollPin', `${request.requestId}-mismatch`));
  });

  const result = await harness.api.plex.pollPin(harness.input({ pinId: 42 }));

  assert.equal((result as { ok: boolean }).ok, false);
  assert.equal(
    (result as { error: { code: string } }).error.code,
    'PLEX_VALIDATION_FAILED',
  );
  assert.equal((result as { requestId: string }).requestId, harness.calls[0]?.request.requestId);
});

test('preload Plex bridge rejects invalid pin ids and limits without IPC', async () => {
  const harness = createPreloadHarness(() => {
    assert.fail('invalid Plex renderer input must not invoke IPC');
  });

  for (const input of [{ pinId: 1.5 }, { pinId: Number.NaN }, { pinId: 0 }]) {
    const result = await harness.api.plex.pollPin(harness.input(input));
    assert.equal((result as { ok: boolean }).ok, false);
    assert.equal(
      (result as { error: { code: string } }).error.code,
      'PLEX_VALIDATION_FAILED',
    );
  }

  for (const input of [
    { sectionId: '1', limit: 1.5 },
    { sectionId: '1', limit: 5001 },
    { sectionId: '', limit: 25 },
    { sectionId: 42, limit: 25 },
    { sectionId: null, limit: 25 },
    { sectionId: 'x'.repeat(257), limit: 25 },
    { sectionId: '1', filter: { 'bad key': 1 } },
    { sectionId: '1', filter: { token: 'unsafe' } },
    { sectionId: '1', filter: { serverUri: 'unsafe' } },
    { sectionId: '1', filter: { year: { raw: 2020 } } },
    { sectionId: '1', includeCollections: 'yes' },
  ]) {
    const result = await harness.api.plex.listLibraryItems(harness.input(input));
    assert.equal((result as { ok: boolean }).ok, false);
    assert.equal(
      (result as { error: { code: string } }).error.code,
      'PLEX_VALIDATION_FAILED',
    );
  }

  for (const input of [
    { query: 'movie', types: ['server'] },
    { query: 'movie', types: ['movie', 42] },
    { query: 'movie', limit: 0 },
    { query: 'movie', limit: -1 },
  ]) {
    const result = await harness.api.plex.searchLibrary(harness.input(input));
    assert.equal((result as { ok: boolean }).ok, false);
    assert.equal(
      (result as { error: { code: string } }).error.code,
      'PLEX_VALIDATION_FAILED',
    );
  }

  assert.equal(harness.calls.length, 0);
});

test('preload channel setup bridge validates status results before returning them', async () => {
  const harness = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        status: 'not-configured',
        lineupRevision: 1,
        channelCount: 1,
        currentChannelId: 'channel-one',
        currentChannelNumber: 101,
        currentChannelName: 'Channel One',
        channelNumbers: [101],
        channels: [{
          id: 'channel-one',
          number: 101,
          name: 'Channel One',
          sourceLibraryId: 'movies',
          sourceLibraryName: 'Movies',
          itemCount: 12,
        }],
        updatedAtMs: 123,
        builder: { completion: 'unknown', normalizedConfig: null, completedAtMs: null },
        recovery: { loaded: true, repaired: false },
      },
    });
  });

  const result = await harness.api.channelSetup.getStatus();

  assert.equal(harness.calls[0]?.channel, LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL);
  assert.equal((result as { ok: boolean }).ok, true);

  const privileged = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        status: 'configured',
        channelCount: 1,
        currentChannelId: 'channel-one',
        currentChannelNumber: 101,
        currentChannelName: 'Channel One',
        channelNumbers: [101],
        channels: [],
        updatedAtMs: 123,
        recovery: { loaded: true, repaired: false },
        persistenceFilePath: 'private',
      },
    });
  });

  const privilegedResult = await privileged.api.channelSetup.getStatus();
  assert.equal((privilegedResult as { ok: boolean }).ok, false);
  assert.equal(
    (privilegedResult as { error: { code: string } }).error.code,
    'CHANNEL_VALIDATION_FAILED',
  );
  assert.equal(
    (privilegedResult as { error: { operation: string } }).error.operation,
    'getStatus',
  );

  const unsafeChannelName = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: true,
      requestId: request.requestId,
      value: {
        status: 'configured',
        channelCount: 1,
        currentChannelId: 'channel-one',
        currentChannelNumber: 101,
        currentChannelName: 'Channel One',
        channelNumbers: [101],
        channels: [{
          id: 'channel-one',
          number: 101,
          name: '<b>Channel One</b>',
          sourceLibraryId: 'movies',
          sourceLibraryName: 'Movies',
          itemCount: 12,
        }],
        updatedAtMs: 123,
        recovery: { loaded: true, repaired: false },
      },
    });
  });

  const unsafeChannelNameResult = await unsafeChannelName.api.channelSetup.getStatus();
  assert.equal((unsafeChannelNameResult as { ok: boolean }).ok, false);
  assert.equal(
    (unsafeChannelNameResult as { error: { code: string } }).error.code,
    'CHANNEL_VALIDATION_FAILED',
  );

  for (const invalidNumber of [0, 501]) {
    const invalidNumberHarness = createPreloadHarness((_channel, request, input) => {
      assert.ok(isPlexInvokeRequest(request));
      return input({
        ok: true,
        requestId: request.requestId,
        value: {
          status: 'configured',
          channelCount: 1,
          currentChannelId: 'channel-one',
          currentChannelNumber: invalidNumber,
          currentChannelName: 'Channel One',
          channelNumbers: [101],
          channels: [],
          updatedAtMs: 123,
          recovery: { loaded: true, repaired: false },
        },
      });
    });

    const invalidResult = await invalidNumberHarness.api.channelSetup.getStatus();
    assert.equal((invalidResult as { ok: boolean }).ok, false);
    assert.equal(
      (invalidResult as { error: { code: string } }).error.code,
      'CHANNEL_VALIDATION_FAILED',
    );
  }

  for (const invalidNumber of [0, 501]) {
    const invalidNumbersHarness = createPreloadHarness((_channel, request, input) => {
      assert.ok(isPlexInvokeRequest(request));
      return input({
        ok: true,
        requestId: request.requestId,
        value: {
          status: 'configured',
          channelCount: 1,
          currentChannelId: 'channel-one',
          currentChannelNumber: 101,
          currentChannelName: 'Channel One',
          channelNumbers: [invalidNumber],
          channels: [],
          updatedAtMs: 123,
          recovery: { loaded: true, repaired: false },
        },
      });
    });

    const invalidResult = await invalidNumbersHarness.api.channelSetup.getStatus();
    assert.equal((invalidResult as { ok: boolean }).ok, false);
    assert.equal(
      (invalidResult as { error: { code: string } }).error.code,
      'CHANNEL_VALIDATION_FAILED',
    );
  }

  const unsafeMessage = createPreloadHarness((_channel, request, input) => {
    assert.ok(isPlexInvokeRequest(request));
    return input({
      ok: false,
      requestId: request.requestId,
      error: {
        code: 'CHANNEL_STORAGE_UNAVAILABLE',
        message: `Failed at ${['C:', 'Users', 'private', 'channels.json'].join('\\')} with token=private`,
        retryable: true,
        recoverable: true,
        operation: 'getStatus',
      },
    });
  });

  const unsafeMessageResult = await unsafeMessage.api.channelSetup.getStatus();
  assert.equal((unsafeMessageResult as { ok: boolean }).ok, false);
  assert.equal(
    (unsafeMessageResult as { error: { code: string } }).error.code,
    'CHANNEL_VALIDATION_FAILED',
  );
  assert.equal(
    (unsafeMessageResult as { error: { operation: string } }).error.operation,
    'getStatus',
  );

  const rejectedStatus = createPreloadHarness(() => {
    throw new Error('raw token serverUri failure');
  });

  const rejectedStatusResult = await rejectedStatus.api.channelSetup.getStatus();
  assert.equal((rejectedStatusResult as { ok: boolean }).ok, false);
  assert.equal(
    (rejectedStatusResult as { error: { code: string } }).error.code,
    'CHANNEL_VALIDATION_FAILED',
  );
  assert.equal(
    (rejectedStatusResult as { error: { operation: string } }).error.operation,
    'getStatus',
  );
  assert.doesNotMatch(JSON.stringify(rejectedStatusResult), /raw token|serverUri/u);

});

test('preload channel operation guard accepts only the exhaustive phase and result cross-product', () => {
  const guard = evaluateChannelGuardModule().isChannelSetupOperationResult as (
    value: unknown,
    requestId: string,
  ) => boolean;
  const requestId = 'operation-contract';
  const reviewId = `channel-builder-review-${'a'.repeat(32)}`;
  const applyId = `channel-builder-apply-${'b'.repeat(32)}`;
  const base = {
    startedAtMs: 1,
    updatedAtMs: 2,
    result: null,
    error: null,
  };
  const valid = [
    { ...base, operationId: reviewId, kind: 'review', state: 'queued', phase: 'discover-facets', progress: { completed: 0, total: null } },
    { ...base, operationId: reviewId, kind: 'review', state: 'running', phase: 'discover-facets', progress: { completed: 4, total: null } },
    { ...base, operationId: reviewId, kind: 'review', state: 'canceling', phase: 'plan', progress: { completed: 1, total: 1 } },
    {
      ...base,
      operationId: reviewId,
      kind: 'review',
      state: 'review-ready',
      phase: 'review-ready',
      progress: { completed: 1, total: 1 },
      result: {
        kind: 'review',
        planId: `channel-builder-plan-${'c'.repeat(32)}`,
        contextEpoch: 1,
        lineupRevision: 2,
        status: 'ready',
        diff: {
          summary: { created: 1, removed: 0, unchanged: 0 },
          samples: { created: ['Movies'], removed: [], unchanged: [] },
        },
        warnings: [],
        reachedCap: false,
      },
    },
    { ...base, operationId: applyId, kind: 'apply', state: 'queued', phase: 'materialize', progress: { completed: 0, total: 2 } },
    { ...base, operationId: applyId, kind: 'apply', state: 'running', phase: 'materialize', progress: { completed: 1, total: 2 } },
    { ...base, operationId: applyId, kind: 'apply', state: 'running', phase: 'persist', progress: { completed: 0, total: 1 } },
    { ...base, operationId: applyId, kind: 'apply', state: 'running', phase: 'refresh-guide', progress: { completed: 1, total: 1 } },
    {
      ...base,
      operationId: applyId,
      kind: 'apply',
      state: 'succeeded',
      phase: 'done',
      progress: { completed: 1, total: 1 },
      result: {
        kind: 'apply',
        commit: 'committed',
        summary: {
          created: 1,
          removed: 0,
          unchanged: 0,
          skipped: 0,
          finalChannelCount: 1,
          reachedMaxChannels: false,
          watchChannelId: 'channel-one',
          byStrategy: Object.fromEntries([
            'collections', 'playlists', 'genres', 'directors', 'decades',
            'recentlyAdded', 'studios', 'actors',
          ].map((key) => [key, { created: key === 'collections' ? 1 : 0, skipped: 0 }])),
          warnings: [],
        },
        guideRefresh: 'completed',
      },
    },
    { ...base, operationId: reviewId, kind: 'review', state: 'canceled', phase: 'done', progress: { completed: 1, total: 1 }, result: { kind: 'canceled' } },
    {
      ...base,
      operationId: applyId,
      kind: 'apply',
      state: 'failed',
      phase: 'done',
      progress: { completed: 1, total: 1 },
      error: {
        code: 'CHANNEL_UNKNOWN',
        message: 'Channel setup could not complete the request.',
        retryable: true,
        recoverable: true,
        operation: 'startApply',
      },
    },
  ];
  for (const operation of valid) {
    assert.equal(guard({ ok: true, requestId, value: { operation } }, requestId), true);
  }
  const invalid = [
    { ...valid[0], operationId: applyId },
    { ...valid[0], progress: { completed: 0, total: 1 } },
    { ...valid[4], state: 'canceling', phase: 'persist', progress: { completed: 0, total: 1 } },
    { ...valid[1], phase: 'materialize', progress: { completed: 0, total: 1 } },
    { ...valid[9], progress: { completed: 0, total: 1 } },
    { ...valid[3], result: { ...(valid[3] as { result: object }).result, extra: true } },
  ];
  for (const operation of invalid) {
    assert.equal(guard({ ok: true, requestId, value: { operation } }, requestId), false);
  }
});

test('preload diagnostics guards validate count map keys and values', () => {
  assert.equal(
    diagnosticsGuardSourceText.includes(
      'function isFiniteNonNegativeNumberMap(value: unknown, allowedKeys: readonly string[]): boolean {',
    ),
    true,
  );
  assert.match(
    diagnosticsGuardSourceText,
    /hasOnlyKeys\(value, \[\], allowedKeys\) &&\s*Object\.values\(value\)\.every\(isFiniteNonNegativeNumber\)/u,
  );
  assert.equal(
    diagnosticsGuardSourceText.includes('isFiniteNonNegativeNumberMap(value.surfaceCounts, DIAGNOSTIC_SURFACES)'),
    true,
  );
  assert.equal(
    diagnosticsGuardSourceText.includes('isFiniteNonNegativeNumberMap(value.severityCounts, DIAGNOSTIC_SEVERITIES)'),
    true,
  );
  assert.equal(
    diagnosticsGuardSourceText.includes('isFiniteNonNegativeNumberMap(value.findingsByLabel, REDACTION_SCAN_FINDING_LABELS)'),
    true,
  );
});

test('preload diagnostics guards accept declared record surfaces and reject case-variant forbidden fields', () => {
  const diagnosticsGuardExports = evaluateDiagnosticsGuardModule();
  const isDiagnosticsRecordRendererEventResult =
    diagnosticsGuardExports.isDiagnosticsRecordRendererEventResult as (value: unknown) => boolean;

  const baseRecord = {
    schemaVersion: 1,
    id: 'diagnostic-record-1',
    timestampMs: 1,
    surface: 'main',
    category: 'lifecycle',
    severity: 'info',
    status: 'observed',
    operation: 'startup',
    message: 'ready',
  };

  assert.equal(
    isDiagnosticsRecordRendererEventResult({
      ok: true,
      requestId: 'diagnostics-record-1',
      value: baseRecord,
    }),
    true,
  );
  assert.equal(
    isDiagnosticsRecordRendererEventResult({
      ok: true,
      requestId: 'diagnostics-record-2',
      value: {
        ...baseRecord,
        context: {
          RawAuthHeaders: 'Bearer secret',
        },
      },
    }),
    false,
  );
});

test('preload diagnostics export guard rejects contradictory redaction reports', () => {
  const diagnosticsGuardExports = evaluateDiagnosticsGuardModule();
  const guard =
    diagnosticsGuardExports.isDiagnosticsExportSupportBundleResult as (value: unknown) => boolean;
  const report = {
    redactionVersion: 'rd17-redaction-v1',
    scannedFileCount: 6,
    scannedByteCount: 512,
    findingCount: 0,
    findingsByLabel: {},
    truncatedRecordCount: 0,
    omittedFileCount: 0,
    status: 'passed',
    timestampMs: 1,
  };
  const success = {
    status: 'succeeded',
    bundleId: 'bundle-1',
    bundleDirectoryName: 'lineup-desktop-support-bundle-1',
    createdAtMs: 1,
    fileCount: 6,
    byteCount: 512,
    includedFiles: [
      'manifest.json',
      'diagnostics.ndjson',
      'crash-recovery.json',
      'player-snapshot.json',
      'environment.json',
      'redaction-report.json',
    ],
    redactionReport: report,
  };

  assert.equal(guard(success), true);
  assert.equal(guard({
    ...success,
    redactionReport: { ...report, status: 'failed' },
  }), false);
  assert.equal(guard({
    ...success,
    redactionReport: {
      ...report,
      findingCount: 1,
      findingsByLabel: { 'raw-filesystem-path': 1 },
      status: 'passed',
    },
  }), false);
  assert.equal(guard({
    ...success,
    redactionReport: {
      ...report,
      findingCount: 2,
      findingsByLabel: { 'raw-filesystem-path': 1 },
      status: 'failed',
    },
  }), false);
  assert.equal(guard({
    ...success,
    fileCount: 5,
  }), false);
  assert.equal(guard({
    ...success,
    redactionReport: {
      ...report,
      scannedFileCount: 5,
    },
  }), false);
});

test('preload diagnostics result guard validates cancellation discriminator exactly', () => {
  const declaration = findDiagnosticsGuardFunctionDeclaration('isDiagnosticsResult');
  assert.ok(declaration, 'expected preload diagnostics result guard to be declared');

  const source = declaration.getText(diagnosticsGuardSourceFile);
  assert.match(
    source,
    /const hasValidCancellationFlag = value\.cancelled === undefined \|\| value\.cancelled === true;/u,
  );
  assert.match(
    source,
    /hasOnlyKeys\(value, \['ok', 'requestId', 'error'\], \['cancelled'\]\) &&\s*hasValidCancellationFlag && isDiagnosticsError\(value\.error\)/u,
  );
  assert.doesNotMatch(source, /typeof value\.cancelled === 'boolean'/u);
});

test('preload channel constants match approved IPC contract exports', () => {
  const preloadChannelConstants = collectPreloadChannelConstants();
  assert.deepEqual(
    [...preloadChannelConstants.keys()].sort(),
    Object.keys(APPROVED_PRELOAD_CHANNEL_CONSTANTS).sort(),
  );

  for (const [name, expectedValue] of Object.entries(APPROVED_PRELOAD_CHANNEL_CONSTANTS)) {
    assertApprovedChannelIdentifier(name);
    assert.equal(preloadChannelConstants.get(name), expectedValue, `${name} must match ipc.ts`);
  }
});

test('preload settings bridge exposes three total guarded methods with exact request-id behavior', async () => {
  const bridgeExports = evaluateSettingsBridgeModule(evaluateSettingsGuardModule());
  const createBridge = bridgeExports.createSettingsBridge as (
    invoke: (channel: string, input: unknown) => Promise<unknown>,
    channels: { getSnapshot: string; replace: string; getAudioOutputs: string },
  ) => Record<string, (input: unknown) => Promise<unknown>>;
  const calls: Array<{ channel: string; input: unknown }> = [];
  const bridge = createBridge(async (channel, input) => {
    calls.push({ channel, input });
    const requestId = (input as { requestId: string }).requestId;
    if (channel === LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL) {
      return {
        ok: true,
        requestId,
        value: {
          status: 'unavailable',
          reason: 'platform-unsupported',
          outputs: [{ kind: 'system-default', id: 'system-default', label: 'System default' }],
        },
      };
    }
    return {
      ok: true,
      requestId,
      value: {
        snapshot: {
          schemaVersion: 2,
          revision: channel === LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL ? 2 : 3,
          status: 'ready',
          values: DEFAULT_DESKTOP_SETTINGS_VALUES,
        },
        capabilities: createConservativeDesktopSettingsCapabilities(),
      },
    };
  }, {
    getSnapshot: LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
    replace: LINEUP_SETTINGS_REPLACE_CHANNEL,
    getAudioOutputs: LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL,
  });
  assert.deepEqual(Object.keys(bridge).sort(), ['getAudioOutputs', 'getSnapshot', 'replace']);
  assert.equal((await bridge.getSnapshot?.({ requestId: 'settings-get-1' }) as { ok: boolean }).ok, true);
  assert.equal((await bridge.replace?.({
    requestId: 'settings-replace-1',
    expectedRevision: 2,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId: 'system-default' },
  }) as { ok: boolean }).ok, true);
  assert.equal((await bridge.getAudioOutputs?.({
    requestId: 'settings-audio-1',
  }) as { ok: boolean }).ok, true);
  assert.equal((await bridge.replace?.({
    requestId: 'settings-replace-2',
    expectedRevision: 3,
    values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId: `audio_${'Q'.repeat(43)}` },
  }) as { ok: boolean }).ok, true);
  for (const audioOutputDeviceId of [' system-default', `audio_${'Q'.repeat(42)}`, 'native-output']) {
    const rejected = await bridge.replace?.({
      requestId: 'settings-replace-invalid-audio',
      expectedRevision: 3,
      values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId },
    }) as { ok: boolean; error: { code: string } };
    assert.equal(rejected.ok, false);
    assert.equal(rejected.error.code, 'validation-failed');
  }
  const invalid = await bridge.replace?.({ requestId: 'bad id' }) as { ok: boolean; requestId: string; error: { code: string } };
  assert.equal(invalid.ok, false);
  assert.equal(invalid.requestId, 'settings-invalid-request');
  assert.equal(invalid.error.code, 'validation-failed');
  assert.equal(calls.length, 4);
});

test('preload settings bridge maps invoke rejection and mismatched results without rejecting', async () => {
  const createBridge = evaluateSettingsBridgeModule(evaluateSettingsGuardModule()).createSettingsBridge as (
    invoke: (channel: string, input: unknown) => Promise<unknown>,
    channels: { getSnapshot: string; replace: string; getAudioOutputs: string },
  ) => Record<string, (input: unknown) => Promise<unknown>>;
  const channels = {
    getSnapshot: LINEUP_SETTINGS_GET_SNAPSHOT_CHANNEL,
    replace: LINEUP_SETTINGS_REPLACE_CHANNEL,
    getAudioOutputs: LINEUP_SETTINGS_GET_AUDIO_OUTPUTS_CHANNEL,
  };
  const rejected = createBridge(async () => { throw new Error('raw invoke detail'); }, channels);
  const rejection = await rejected.getSnapshot?.({ requestId: 'settings-get-2' }) as { error: { code: string; message: string } };
  assert.equal(rejection.error.code, 'operation-failed');
  assert.doesNotMatch(rejection.error.message, /raw|invoke/u);
  const mismatched = createBridge(async () => ({ ok: false, requestId: 'settings-other', error: {
    code: 'operation-failed', message: 'Desktop settings operation failed.',
  } }), channels);
  const mismatch = await mismatched.getSnapshot?.({ requestId: 'settings-get-3' }) as { requestId: string; error: { code: string } };
  assert.equal(mismatch.requestId, 'settings-get-3');
  assert.equal(mismatch.error.code, 'validation-failed');
});

test('preload settings guards reject persisted system-default, invalid capability pairs, and extra keys', () => {
  const guards = evaluateSettingsGuardModule();
  const isSettingsResult = guards.isSettingsResult as (value: unknown, requestId: string) => boolean;
  const base = {
    ok: true,
    requestId: 'settings-get-strict',
    value: {
      snapshot: {
        schemaVersion: 2,
        revision: 1,
        status: 'ready',
        values: DEFAULT_DESKTOP_SETTINGS_VALUES,
      },
      capabilities: createConservativeDesktopSettingsCapabilities(),
    },
  };
  assert.equal(isSettingsResult(base, base.requestId), true);
  assert.equal(isSettingsResult({
    ...base,
    value: {
      ...base.value,
      snapshot: {
        ...base.value.snapshot,
        values: { ...DEFAULT_DESKTOP_SETTINGS_VALUES, audioOutputDeviceId: 'system-default' },
      },
    },
  }, base.requestId), false);
  assert.equal(isSettingsResult({
    ...base,
    value: {
      ...base.value,
      capabilities: {
        ...base.value.capabilities,
        transcode: { status: 'supported', reason: 'native-proof-required' },
      },
    },
  }, base.requestId), false);
  assert.equal(isSettingsResult({
    ...base,
    value: { ...base.value, extra: true },
  }, base.requestId), false);
});

test('preload settings audio guards reject unsafe, unordered, duplicate, and mismatched results', () => {
  const guards = evaluateSettingsGuardModule();
  const isAudioResult = guards.isSettingsAudioOutputResult as (
    value: unknown,
    requestId: string,
  ) => boolean;
  const requestId = 'settings-audio-strict';
  const system = { kind: 'system-default', id: 'system-default', label: 'System default' };
  const device = {
    kind: 'device',
    id: `audio_${'A'.repeat(43)}`,
    label: 'Speakers',
  };
  const base = {
    ok: true,
    requestId,
    value: { status: 'ready', reason: 'available', outputs: [system, device] },
  };
  assert.equal(isAudioResult(base, requestId), true);
  assert.equal(isAudioResult({ ...base, requestId: 'settings-audio-other' }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: { ...base.value, outputs: [device, system] },
  }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: { ...base.value, outputs: [system, device, device] },
  }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: {
      status: 'unavailable',
      reason: 'helper-unavailable',
      outputs: [system, device],
    },
  }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: {
      status: 'partial',
      reason: 'device-list-sanitized',
      outputs: [system],
    },
  }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: {
      ...base.value,
      outputs: [system, { ...device, label: 'unsafe\u0007label' }],
    },
  }, requestId), false);
  assert.equal(isAudioResult({
    ...base,
    value: {
      ...base.value,
      outputs: [system, { ...device, label: 'unsafe\u202Elabel' }],
    },
  }, requestId), false);
});

test('preload bridge guard rejects Electron value imports while allowing type imports', () => {
  const typeOnlySource = ts.createSourceFile(
    'fixture.cts',
    [
      "import type { IpcRendererEvent } from 'electron';",
      "import { type BrowserWindowConstructorOptions } from 'electron';",
      'const event: IpcRendererEvent | null = null;',
      'const options: BrowserWindowConstructorOptions | null = null;',
      'void event;',
      'void options;',
    ].join('\n'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  assert.doesNotThrow(() => assertNoElectronValueImports(typeOnlySource));

  const valueImportSource = ts.createSourceFile(
    'fixture.cts',
    [
      "import { ipcRenderer as unsafeIpc } from 'electron';",
      "unsafeIpc.invoke('lineup:unsafe');",
    ].join('\n'),
    ts.ScriptTarget.Latest,
    true,
    ts.ScriptKind.TS,
  );
  assert.throws(
    () => assertNoElectronValueImports(valueImportSource),
    /Electron value imports are not allowed in preload/u,
  );
});

test('preload split keeps Electron values in index and built preload has no local preload requires', () => {
  assertNoElectronValueImports(channelGuardSourceFile);
  assertNoElectronValueImports(preloadChannelsSourceFile);
  assertNoElectronValueImports(channelSetupBridgeSourceFile);
  assertNoElectronValueImports(customChannelGuardSourceFile);
  assertNoElectronValueImports(customChannelBridgeSourceFile);
  assertNoElectronValueImports(diagnosticsGuardSourceFile);
  assertNoElectronValueImports(guideBridgeSourceFile);
  assertNoElectronValueImports(playerBridgeSourceFile);
  assert.doesNotMatch(channelGuardSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(preloadChannelsSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(channelSetupBridgeSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(customChannelGuardSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(customChannelBridgeSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(diagnosticsGuardSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(guideBridgeSourceText, /require\(['"]electron['"]\)/u);
  assert.doesNotMatch(playerBridgeSourceText, /require\(['"]electron['"]\)/u);
  assert.match(preloadSourceText, /from '\.\/channels\.cjs'/u);
  assert.match(preloadSourceText, /from '\.\/channelSetupBridge\.cjs'/u);
  assert.match(preloadSourceText, /from '\.\/customChannelBridge\.cjs'/u);
  assert.match(preloadSourceText, /from '\.\/diagnosticsBridgeGuards\.cjs'/u);
  assert.match(preloadSourceText, /from '\.\/guideBridge\.cjs'/u);
  assert.match(preloadSourceText, /from '\.\/playerBridge\.cjs'/u);
  assert.match(channelSetupBridgeSourceText, /from '\.\/channelBridgeGuards\.cjs'/u);
  assert.match(customChannelBridgeSourceText, /from '\.\/customChannelBridgeGuards\.cjs'/u);
  assert.match(preloadBundleToolSourceText, /bundle:\s*true/u);
  assert.match(preloadBundleToolSourceText, /external:\s*\[\s*'electron'\s*\]/u);
});

test(
  'built preload bundle has no local preload requires',
  { skip: !existsSync(preloadBundleOutputUrl) ? 'run npm run build:electron before bundle verification' : false },
  () => {
  const preloadBundleOutputText = readFileSync(preloadBundleOutputUrl, 'utf8');
  assert.match(preloadBundleOutputText, /require\(["']electron["']\)/u);
  assert.doesNotMatch(preloadBundleOutputText, /channels\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /channelBridgeGuards\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /channelSetupBridge\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /customChannelBridge\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /customChannelBridgeGuards\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /diagnosticsBridgeGuards\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /guideBridge\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /playerBridge\.cjs/u);
  assert.doesNotMatch(preloadBundleOutputText, /require\(["']\.(?:\/|\\)[^"']+["']\)/u);
  assert.doesNotMatch(preloadBundleOutputText, /\bfrom\s+["']\.(?:\/|\\)[^"']+["']/u);
  assert.doesNotMatch(preloadBundleOutputText, /\bimport\(["']\.(?:\/|\\)[^"']+["']\)/u);
  },
);

test('preload custom channel reorder request rejects duplicate ids and clones nested season filters', () => {
  const customChannelGuardExports = evaluateCustomChannelGuardModule();
  const createReorderRequest = customChannelGuardExports.createCustomChannelReorderRequest as
    ((input: { channelIds: readonly string[] }) => { ok: boolean; result: { error: { code: string } } });
  const createListMediaRequest = customChannelGuardExports.createCustomChannelListMediaRequest as
    ((input: {
      sourceType: 'search';
      query: string;
      draftContent: readonly [{ type: 'show'; sourceId: string; title: string; seasonFilter: readonly number[] }];
    }) => {
      ok: boolean;
      payload?: { draftContent?: readonly [{ type: 'show'; seasonFilter?: readonly number[] }] };
    });
  const duplicateIds = createReorderRequest({ channelIds: ['channel-1', 'channel-1'] });
  assert.equal(duplicateIds.ok, false);
  assert.equal(duplicateIds.result.error.code, 'CUSTOM_CHANNEL_VALIDATION_FAILED');

  const originalSeasonFilter = [1, 2];
  const request = createListMediaRequest({
    sourceType: 'search',
    query: 'episodes',
    draftContent: [{ type: 'show', sourceId: 'show-1', title: 'Show One', seasonFilter: originalSeasonFilter }],
  });
  assert.equal(request.ok, true);
  if (request.ok !== true || request.payload === undefined) {
    assert.fail('expected cloned list media request payload');
  }
  {
    const draftEntry = request.payload.draftContent?.[0];
    assert.equal(draftEntry?.type, 'show');
    if (draftEntry?.type === 'show' && draftEntry.seasonFilter) {
      assert.notEqual(draftEntry.seasonFilter, originalSeasonFilter);
      assert.deepEqual(draftEntry.seasonFilter, originalSeasonFilter);
    }
  }
});

test('preload bridge exposes only the typed lineupDesktop world', () => {
  assertNoElectronValueImports();
  assertApprovedElectronRequireBinding();

  const exposureCalls = collectContextBridgeExposureCalls();
  assert.equal(exposureCalls.length, 1, 'expected exactly one contextBridge exposure');

  const [exposureCall] = exposureCalls;
  const [worldKey, exposedValue] = exposureCall.arguments;
  assert.ok(ts.isStringLiteral(worldKey), 'expected exposed world key to be a string literal');
  assert.equal(worldKey.text, 'lineupDesktop');
  assert.ok(ts.isIdentifier(exposedValue), 'expected exposed value to be an identifier');
  assert.equal(exposedValue.text, 'lineupDesktop');
  assert.equal(
    collectBindingIdentifiers('lineupDesktop').length,
    1,
    'expected exactly one lineupDesktop binding',
  );

  const bridgeDeclaration = findPreloadVariableDeclaration('lineupDesktop');
  assert.ok(bridgeDeclaration, 'expected typed lineupDesktop bridge object');
  assert.ok(
    bridgeDeclaration.parent.flags & ts.NodeFlags.Const,
    'expected lineupDesktop bridge object to be const',
  );
  assert.ok(
    bridgeDeclaration.type !== undefined &&
      ts.isTypeReferenceNode(bridgeDeclaration.type) &&
      ts.isIdentifier(bridgeDeclaration.type.typeName) &&
      bridgeDeclaration.type.typeName.text === 'LineupDesktopPreloadApi',
    'expected lineupDesktop bridge object to be typed as LineupDesktopPreloadApi',
  );
  assert.ok(
    bridgeDeclaration.initializer !== undefined &&
      ts.isObjectLiteralExpression(unwrapExpression(bridgeDeclaration.initializer)),
    'expected lineupDesktop bridge object to be an object literal',
  );
});

test('preload bridge uses ipcRenderer only through approved methods and channels', () => {
  assertNoElectronValueImports();
  assertApprovedElectronRequireBinding();

  const observedCalls: string[] = [];

  function visit(node: ts.Node): void {
    assertNoForbiddenElectronAccess(node);

    if (ts.isIdentifier(node) && node.text === 'ipcRenderer') {
      assert.ok(
        isApprovedIpcRendererIdentifierUse(node),
        `ipcRenderer aliasing or direct exposure is not allowed: ${describeNode(node.parent)}`,
      );
    }

    if (
      ts.isElementAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'ipcRenderer'
    ) {
      assert.fail(`ipcRenderer dynamic access is not allowed: ${describeNode(node)}`);
    }

    if (
      ts.isPropertyAccessExpression(node) &&
      ts.isIdentifier(node.expression) &&
      node.expression.text === 'ipcRenderer'
    ) {
      assert.ok(ts.isCallExpression(node.parent) && node.parent.expression === node);
      const methodName = node.name.text;
      assert.ok(
        APPROVED_IPC_METHODS.has(methodName),
        `ipcRenderer.${methodName} is not an approved preload bridge method`,
      );

      const [channelExpression] = node.parent.arguments;
      assert.ok(channelExpression, `ipcRenderer.${methodName} must pass an explicit channel`);
      assert.ok(
        ts.isIdentifier(channelExpression),
        `ipcRenderer.${methodName} channel must be an approved constant identifier, got ${describeNode(
          channelExpression,
        )}`,
      );

      if (isInvokePlexChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokePlex.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokeChannelSetupChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokeChannelSetup.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokeCustomChannelsChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokeCustomChannels.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokeGuideChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokeGuide.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokePlayerSnapshotChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokePlayerSnapshot.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokePlayerRecoveryChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokePlayerRecovery.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      if (isInvokeSettingsChannelParameter(channelExpression)) {
        observedCalls.push(`${methodName}:invokeSettings.channel`);
        ts.forEachChild(node, visit);
        return;
      }

      const approvedChannels =
        APPROVED_IPC_CHANNELS_BY_METHOD[
          methodName as keyof typeof APPROVED_IPC_CHANNELS_BY_METHOD
        ];
      assert.ok(
        approvedChannels.has(channelExpression.text),
        `ipcRenderer.${methodName} is not approved for ${channelExpression.text}`,
      );
      assertApprovedChannelIdentifier(channelExpression.text);
      observedCalls.push(`${methodName}:${channelExpression.text}`);
    }

    ts.forEachChild(node, visit);
  }

  visit(preloadSourceFile);

  assert.deepEqual(observedCalls.sort(), [
    'invoke:LINEUP_DIAGNOSTICS_EXPORT_SUPPORT_BUNDLE_CHANNEL',
    'invoke:LINEUP_DIAGNOSTICS_GET_SUMMARY_CHANNEL',
    'invoke:LINEUP_DIAGNOSTICS_RECORD_RENDERER_EVENT_CHANNEL',
    'invoke:LINEUP_PLAYER_COMMAND_CHANNEL',
    'invoke:LINEUP_SHELL_GET_CAPABILITIES_CHANNEL',
    'invoke:LINEUP_WINDOW_INTENT_CHANNEL',
    'invoke:invokeChannelSetup.channel',
    'invoke:invokeCustomChannels.channel',
    'invoke:invokeGuide.channel',
    'invoke:invokePlayerRecovery.channel',
    'invoke:invokePlayerSnapshot.channel',
    'invoke:invokePlex.channel',
    'invoke:invokeSettings.channel',
    'on:LINEUP_PLAYER_EVENT_CHANNEL',
    'on:LINEUP_SHELL_MEDIA_INPUT_CHANNEL',
    'on:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
    'removeListener:LINEUP_PLAYER_EVENT_CHANNEL',
    'removeListener:LINEUP_SHELL_MEDIA_INPUT_CHANNEL',
    'removeListener:LINEUP_SHELL_STATUS_CHANGED_CHANNEL',
  ]);
  assert.deepEqual(collectInvokePlexChannelArguments().sort(), [
    'LINEUP_PLEX_CANCEL_PIN_CHANNEL',
    'LINEUP_PLEX_GET_HOME_USERS_CHANNEL',
    'LINEUP_PLEX_GET_METADATA_CHANNEL',
    'LINEUP_PLEX_GET_SNAPSHOT_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_ITEMS_CHANNEL',
    'LINEUP_PLEX_LIST_LIBRARY_SECTIONS_CHANNEL',
    'LINEUP_PLEX_POLL_PIN_CHANNEL',
    'LINEUP_PLEX_REFRESH_SERVERS_CHANNEL',
    'LINEUP_PLEX_REQUEST_PIN_CHANNEL',
    'LINEUP_PLEX_RESTORE_SELECTED_SERVER_CHANNEL',
    'LINEUP_PLEX_SEARCH_LIBRARY_CHANNEL',
    'LINEUP_PLEX_SELECT_SERVER_CHANNEL',
    'LINEUP_PLEX_SWITCH_HOME_USER_CHANNEL',
  ]);
  assert.deepEqual(collectCreateChannelSetupBridgeChannelArguments().sort(), [
    'LINEUP_CHANNEL_SETUP_CANCEL_CHANNEL',
    'LINEUP_CHANNEL_SETUP_GET_OPERATION_CHANNEL',
    'LINEUP_CHANNEL_SETUP_GET_STATUS_CHANNEL',
    'LINEUP_CHANNEL_SETUP_START_APPLY_CHANNEL',
    'LINEUP_CHANNEL_SETUP_START_REVIEW_CHANNEL',
  ]);

  function collectCreateCustomChannelBridgeChannelArguments(): string[] {
    const channels: string[] = [];
    assert.ok(customChannelBridgeSourceFile.statements.length > 0);

    function visit(node: ts.Node): void {
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === 'createCustomChannelBridge'
      ) {
        const [invokeExpression, channelsExpression] = node.arguments;
        assert.ok(invokeExpression, 'createCustomChannelBridge must pass an invoke function');
        assert.ok(
          ts.isIdentifier(invokeExpression) && invokeExpression.text === 'invokeCustomChannels',
          'createCustomChannelBridge must receive the narrow custom channel invoke function',
        );
        const channelBindings = channelsExpression === undefined
          ? undefined
          : unwrapExpression(channelsExpression);
        assert.ok(
          channelBindings !== undefined && ts.isObjectLiteralExpression(channelBindings),
          'createCustomChannelBridge must receive literal channel bindings',
        );
        for (const property of channelBindings.properties) {
          assert.ok(ts.isPropertyAssignment(property), 'custom channel bridge channels must be property assignments');
          assert.ok(ts.isIdentifier(property.initializer), 'custom channel bridge channel values must be constants');
          assertApprovedChannelIdentifier(property.initializer.text);
          channels.push(property.initializer.text);
        }
      }
      ts.forEachChild(node, visit);
    }

    visit(preloadSourceFile);
    return channels;
  }

  assert.deepEqual(collectCreateCustomChannelBridgeChannelArguments().sort(), [
    'LINEUP_CUSTOM_CHANNEL_DELETE_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_DUPLICATE_DRAFT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_GET_MEDIA_METADATA_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_GET_SNAPSHOT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_LIST_MEDIA_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_REORDER_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_SAVE_DRAFT_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_SET_VISIBILITY_CHANNEL',
    'LINEUP_CUSTOM_CHANNEL_VALIDATE_DRAFT_CHANNEL',
  ]);

  function collectCreateGuideBridgeChannelArguments(): string[] {
    const channels: string[] = [];

    function visit(node: ts.Node): void {
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === 'createGuideBridge'
      ) {
        const [invokeExpression, channelsExpression] = node.arguments;
        assert.ok(invokeExpression, 'createGuideBridge must pass an invoke function');
        assert.ok(
          ts.isIdentifier(invokeExpression) && invokeExpression.text === 'invokeGuide',
          'createGuideBridge must receive the narrow guide invoke function',
        );
        const channelBindings = channelsExpression === undefined
          ? undefined
          : unwrapExpression(channelsExpression);
        assert.ok(
          channelBindings !== undefined && ts.isObjectLiteralExpression(channelBindings),
          'createGuideBridge must receive literal channel bindings',
        );
        for (const property of channelBindings.properties) {
          assert.ok(ts.isPropertyAssignment(property), 'guide bridge channels must be property assignments');
          assert.ok(ts.isIdentifier(property.initializer), 'guide bridge channel values must be constants');
          assertApprovedChannelIdentifier(property.initializer.text);
          channels.push(property.initializer.text);
        }
      }
      ts.forEachChild(node, visit);
    }

    visit(preloadSourceFile);
    return channels;
  }

  assert.deepEqual(collectCreateGuideBridgeChannelArguments().sort(), [
    'LINEUP_GUIDE_GET_PRESENTATION_CHANNEL',
    'LINEUP_PLAYER_TUNE_CHANNEL',
  ]);

  function collectCreatePlayerSnapshotBridgeChannelArguments(): string[] {
    const channels: string[] = [];

    function visit(node: ts.Node): void {
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === 'createPlayerSnapshotBridge'
      ) {
        const [invokeExpression, channelsExpression] = node.arguments;
        assert.ok(invokeExpression, 'createPlayerSnapshotBridge must pass an invoke function');
        assert.ok(
          ts.isIdentifier(invokeExpression) && invokeExpression.text === 'invokePlayerSnapshot',
          'createPlayerSnapshotBridge must receive the narrow player snapshot invoke function',
        );
        const channelBindings = channelsExpression === undefined
          ? undefined
          : unwrapExpression(channelsExpression);
        assert.ok(
          channelBindings !== undefined && ts.isObjectLiteralExpression(channelBindings),
          'createPlayerSnapshotBridge must receive literal channel bindings',
        );
        for (const property of channelBindings.properties) {
          assert.ok(ts.isPropertyAssignment(property), 'player snapshot bridge channels must be property assignments');
          assert.ok(ts.isIdentifier(property.initializer), 'player snapshot bridge channel values must be constants');
          assertApprovedChannelIdentifier(property.initializer.text);
          channels.push(property.initializer.text);
        }
      }
      ts.forEachChild(node, visit);
    }

    visit(preloadSourceFile);
    return channels;
  }

  assert.deepEqual(collectCreatePlayerSnapshotBridgeChannelArguments().sort(), [
    'LINEUP_PLAYER_CLEANUP_CHANNEL',
    'LINEUP_PLAYER_GET_SNAPSHOT_CHANNEL',
  ]);

  function collectCreatePlayerTuneBridgeChannelArguments(): string[] {
    const channels: string[] = [];

    function visit(node: ts.Node): void {
      if (
        ts.isCallExpression(node) &&
        ts.isIdentifier(node.expression) &&
        node.expression.text === 'createPlayerTuneBridge'
      ) {
        const [invokeExpression, channelExpression] = node.arguments;
        assert.ok(invokeExpression, 'createPlayerTuneBridge must pass an invoke function');
        assert.ok(
          ts.isIdentifier(invokeExpression) && invokeExpression.text === 'invokeGuide',
          'createPlayerTuneBridge must receive the narrow guide invoke function',
        );
        assert.ok(ts.isIdentifier(channelExpression), 'createPlayerTuneBridge channel must be a constant');
        assertApprovedChannelIdentifier(channelExpression.text);
        channels.push(channelExpression.text);
      }
      ts.forEachChild(node, visit);
    }

    visit(preloadSourceFile);
    return channels;
  }

  assert.deepEqual(collectCreatePlayerTuneBridgeChannelArguments().sort(), [
    'LINEUP_PLAYER_TUNE_CHANNEL',
  ]);
});
