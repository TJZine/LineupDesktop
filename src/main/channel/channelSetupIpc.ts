import { createRequire } from 'node:module';

import type { IpcMain, IpcMainInvokeEvent, WebContents } from 'electron';
import type {
  ChannelSetupBuildRequest,
  ChannelSetupCancelRequest,
  ChannelSetupConfigDraft,
  ChannelSetupConfigRequest,
  ChannelSetupEmptyRequest,
  ChannelSetupOperation,
  ChannelSetupWorkflowError,
  ChannelSetupWorkflowIpcResult,
} from '../../contracts/channel.js';
import { CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS } from '../../contracts/channel.js';
import {
  LINEUP_CHANNEL_SETUP_BUILD_CHANNEL,
  LINEUP_CHANNEL_SETUP_CANCEL_BUILD_CHANNEL,
  LINEUP_CHANNEL_SETUP_GET_RECORD_CHANNEL,
  LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL,
  LINEUP_CHANNEL_SETUP_PROGRESS_CHANNEL,
  LINEUP_CHANNEL_SETUP_REVIEW_CHANNEL,
} from '../../contracts/ipc.js';
import type { DesktopChannelSetupRuntime } from './setup/desktopChannelSetupRuntime.js';

type SetupIpcMain = Pick<IpcMain, 'handle' | 'removeHandler'>;
type SetupSender = Pick<WebContents, 'id' | 'send' | 'once' | 'removeListener' | 'isDestroyed'>;
interface SenderBinding { sender: SetupSender; listener: () => void; detached: boolean }
const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const BUILD_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const FORBIDDEN_KEYS = new Set<string>(CHANNEL_SETUP_FORBIDDEN_RENDERER_FIELD_KEYS);

export function registerChannelSetupIpcHandlers(options: {
  runtime: DesktopChannelSetupRuntime;
  isAuthorizedEvent(event: IpcMainInvokeEvent): boolean;
  createRequestId(prefix: string): string;
  ipcMain?: SetupIpcMain;
}): () => Promise<void> {
  const ipcMain = options.ipcMain ?? getElectronIpcMain();
  const senderCleanup = new Map<number, SenderBinding>();
  const bindSender = (sender: SetupSender) => {
    const existing = senderCleanup.get(sender.id);
    if (existing) return existing;
    const binding: SenderBinding = { sender, listener: () => undefined, detached: false };
    const listener = () => {
      binding.detached = true;
      options.runtime.releaseSender(sender.id);
      senderCleanup.delete(sender.id);
    };
    binding.listener = listener;
    sender.once('destroyed', listener);
    senderCleanup.set(sender.id, binding);
    return binding;
  };

  ipcMain.handle(LINEUP_CHANNEL_SETUP_GET_RECORD_CHANNEL, (event, raw) => {
    const request = readEmptyRequest(raw, options.createRequestId('channel-setup-record'));
    if (!options.isAuthorizedEvent(event)) return failure(request.requestId, unauthorized('getRecord'));
    if (!request.ok) return failure(request.requestId, invalid('getRecord'));
    return options.runtime.getRecord(request.requestId);
  });
  ipcMain.handle(LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL, (event, raw) => {
    const request = readConfigRequest(raw, options.createRequestId('channel-setup-preview'));
    if (!options.isAuthorizedEvent(event)) return failure(request.requestId, unauthorized('preview'));
    if (!request.ok) return failure(request.requestId, invalid('preview'));
    return options.runtime.preview(request.requestId, request.payload.config);
  });
  ipcMain.handle(LINEUP_CHANNEL_SETUP_REVIEW_CHANNEL, (event, raw) => {
    const request = readConfigRequest(raw, options.createRequestId('channel-setup-review'));
    if (!options.isAuthorizedEvent(event)) return failure(request.requestId, unauthorized('review'));
    if (!request.ok) return failure(request.requestId, invalid('review'));
    return options.runtime.review(request.requestId, request.payload.config);
  });
  ipcMain.handle(LINEUP_CHANNEL_SETUP_BUILD_CHANNEL, (event, raw) => {
    const request = readBuildRequest(raw, options.createRequestId('channel-setup-build'));
    if (!options.isAuthorizedEvent(event)) return failure(request.requestId, unauthorized('build'));
    if (!request.ok) return failure(request.requestId, invalid('build'));
    const senderBinding = bindSender(event.sender);
    return options.runtime.build({
      senderId: event.sender.id,
      requestId: request.requestId,
      buildId: request.payload.buildId,
      draft: request.payload.config,
      confirmReplace: request.payload.confirmReplace,
      onProgress: (progress, sequence) => {
        if (senderBinding.detached || event.sender.isDestroyed()) return;
        event.sender.send(LINEUP_CHANNEL_SETUP_PROGRESS_CHANNEL, {
          buildId: request.payload.buildId,
          buildRequestId: request.requestId,
          sequence,
          progress,
        });
      },
    });
  });
  ipcMain.handle(LINEUP_CHANNEL_SETUP_CANCEL_BUILD_CHANNEL, (event, raw) => {
    const request = readCancelRequest(raw, options.createRequestId('channel-setup-cancel'));
    if (!options.isAuthorizedEvent(event)) return failure(request.requestId, unauthorized('cancelBuild'));
    if (!request.ok) return failure(request.requestId, invalid('cancelBuild'));
    return { ok: true, requestId: request.requestId, value: options.runtime.cancelBuild(event.sender.id, request.payload.buildId) };
  });

  return async () => {
    for (const channel of [
      LINEUP_CHANNEL_SETUP_GET_RECORD_CHANNEL,
      LINEUP_CHANNEL_SETUP_PREVIEW_CHANNEL,
      LINEUP_CHANNEL_SETUP_REVIEW_CHANNEL,
      LINEUP_CHANNEL_SETUP_BUILD_CHANNEL,
      LINEUP_CHANNEL_SETUP_CANCEL_BUILD_CHANNEL,
    ]) ipcMain.removeHandler(channel);
    for (const binding of senderCleanup.values()) {
      binding.detached = true;
      binding.sender.removeListener('destroyed', binding.listener);
      options.runtime.releaseSender(binding.sender.id);
    }
    senderCleanup.clear();
    options.runtime.shutdown();
  };
}

type ReadResult<T> = { ok: true; requestId: string; payload: T } | { ok: false; requestId: string; payload: Partial<T> };

function readEmptyRequest(raw: unknown, fallback: string): ReadResult<ChannelSetupEmptyRequest['payload']> {
  const envelope = readEnvelope(raw, fallback);
  if (!envelope.ok || Object.keys(envelope.payload).length !== 0) return { ok: false, requestId: envelope.requestId, payload: {} };
  return { ok: true, requestId: envelope.requestId, payload: {} };
}

function readConfigRequest(raw: unknown, fallback: string): ReadResult<ChannelSetupConfigRequest['payload']> {
  const envelope = readEnvelope(raw, fallback);
  if (!envelope.ok || !hasExactKeys(envelope.payload, ['config']) || !isConfigDraft(envelope.payload.config)) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { config: envelope.payload.config } };
}

function readBuildRequest(raw: unknown, fallback: string): ReadResult<ChannelSetupBuildRequest['payload']> {
  const envelope = readEnvelope(raw, fallback);
  if (!envelope.ok || !hasExactKeys(envelope.payload, ['buildId', 'config', 'confirmReplace']) ||
    typeof envelope.payload.buildId !== 'string' || !BUILD_ID_PATTERN.test(envelope.payload.buildId) ||
    typeof envelope.payload.confirmReplace !== 'boolean' || !isConfigDraft(envelope.payload.config)) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: {
    buildId: envelope.payload.buildId,
    config: envelope.payload.config,
    confirmReplace: envelope.payload.confirmReplace,
  } };
}

function readCancelRequest(raw: unknown, fallback: string): ReadResult<ChannelSetupCancelRequest['payload']> {
  const envelope = readEnvelope(raw, fallback);
  if (!envelope.ok || !hasExactKeys(envelope.payload, ['buildId']) ||
    typeof envelope.payload.buildId !== 'string' || !BUILD_ID_PATTERN.test(envelope.payload.buildId)) {
    return { ok: false, requestId: envelope.requestId, payload: {} };
  }
  return { ok: true, requestId: envelope.requestId, payload: { buildId: envelope.payload.buildId } };
}

function readEnvelope(raw: unknown, fallback: string): ReadResult<Record<string, unknown>> {
  if (!isPlainRecord(raw)) return { ok: false, requestId: fallback, payload: {} };
  const requestId = typeof raw.requestId === 'string' && REQUEST_ID_PATTERN.test(raw.requestId) ? raw.requestId : fallback;
  if (!hasExactKeys(raw, ['requestId', 'payload']) || requestId !== raw.requestId || !isPlainRecord(raw.payload) || containsForbidden(raw.payload)) {
    return { ok: false, requestId, payload: {} };
  }
  return { ok: true, requestId, payload: raw.payload };
}

function isConfigDraft(value: unknown): value is ChannelSetupConfigDraft {
  if (!isPlainRecord(value) || containsForbidden(value)) return false;
  const required = ['selectedLibraryIds', 'maxChannels', 'buildMode', 'strategyConfig', 'actorStudioCombineMode', 'minItemsPerChannel'];
  const allowed = [...required, 'channelExpansion', 'seriesOrdering'];
  if (!required.every((key) => Object.hasOwn(value, key)) || Object.keys(value).some((key) => !allowed.includes(key))) return false;
  return Array.isArray(value.selectedLibraryIds) && value.selectedLibraryIds.length > 0 && value.selectedLibraryIds.length <= 24 &&
    value.selectedLibraryIds.every((id) => typeof id === 'string' && BUILD_ID_PATTERN.test(id)) &&
    new Set(value.selectedLibraryIds).size === value.selectedLibraryIds.length &&
    isIntegerInRange(value.maxChannels, 1, 500) &&
    (value.buildMode === 'append' || value.buildMode === 'replace' || value.buildMode === 'merge') &&
    isStrategyDraft(value.strategyConfig) &&
    (value.channelExpansion === undefined || isExpansionDraft(value.channelExpansion)) &&
    (value.seriesOrdering === undefined || isSeriesOrderingDraft(value.seriesOrdering)) &&
    (value.actorStudioCombineMode === 'separate' || value.actorStudioCombineMode === 'combined') &&
    isIntegerInRange(value.minItemsPerChannel, 1, Number.MAX_SAFE_INTEGER);
}

function isStrategyDraft(value: unknown): boolean {
  if (!isPlainRecord(value)) return false;
  const keys = new Set(['playlists', 'collections', 'recentlyAdded', 'genres', 'studios', 'actors', 'decades', 'directors']);
  if (Object.keys(value).some((key) => !keys.has(key))) return false;
  return Object.values(value).every((candidate) => {
    if (!isPlainRecord(candidate) || Object.keys(candidate).some((key) => !['enabled', 'priority', 'scope'].includes(key))) return false;
    return (candidate.enabled === undefined || typeof candidate.enabled === 'boolean') &&
      (candidate.priority === undefined || isIntegerInRange(candidate.priority, 1, Number.MAX_SAFE_INTEGER)) &&
      (candidate.scope === undefined || candidate.scope === 'per-library' || candidate.scope === 'cross-library');
  });
}
function isExpansionDraft(value: unknown): boolean {
  if (!isPlainRecord(value) || Object.keys(value).some((key) => ![
    'addAlternateLineups', 'alternateLineupCopies', 'variantType', 'variantBlockSize',
  ].includes(key))) return false;
  return (value.addAlternateLineups === undefined || typeof value.addAlternateLineups === 'boolean') &&
    (value.alternateLineupCopies === undefined || isIntegerInRange(value.alternateLineupCopies, 1, 3)) &&
    (value.variantType === undefined || value.variantType === 'none' || value.variantType === 'sequential' || value.variantType === 'block') &&
    (value.variantBlockSize === undefined || isIntegerInRange(value.variantBlockSize, 2, 5));
}
function isSeriesOrderingDraft(value: unknown): boolean {
  if (!isPlainRecord(value) || Object.keys(value).some((key) => !['basePlaybackMode', 'baseBlockSize'].includes(key))) return false;
  return (value.basePlaybackMode === undefined || value.basePlaybackMode === 'shuffle' || value.basePlaybackMode === 'sequential' || value.basePlaybackMode === 'block') &&
    (value.baseBlockSize === undefined || isIntegerInRange(value.baseBlockSize, 2, 5));
}
function isIntegerInRange(value: unknown, minimum: number, maximum: number): value is number {
  return typeof value === 'number' && Number.isSafeInteger(value) && value >= minimum && value <= maximum;
}

function containsForbidden(value: unknown): boolean {
  if (Array.isArray(value)) return value.some(containsForbidden);
  if (!isPlainRecord(value)) return false;
  return Object.entries(value).some(([key, child]) => FORBIDDEN_KEYS.has(key) || containsForbidden(child));
}
function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && Object.getPrototypeOf(value) === Object.prototype;
}
function hasExactKeys(value: object, keys: readonly string[]): boolean {
  const actual = Object.keys(value);
  return actual.length === keys.length && keys.every((key) => Object.hasOwn(value, key));
}
function unauthorized(operation: ChannelSetupOperation): ChannelSetupWorkflowError {
  return { code: 'CHANNEL_UNAUTHORIZED', message: 'Channel setup request is not authorized.', retryable: false, recoverable: false, operation };
}
function invalid(operation: ChannelSetupOperation): ChannelSetupWorkflowError {
  return { code: 'CHANNEL_VALIDATION_FAILED', message: 'Channel setup request payload is invalid.', retryable: false, recoverable: false, operation };
}
function failure<T>(requestId: string, error: ChannelSetupWorkflowError): ChannelSetupWorkflowIpcResult<T> {
  return { ok: false, requestId, error };
}
function getElectronIpcMain(): SetupIpcMain {
  return (createRequire(import.meta.url)('electron') as { ipcMain: SetupIpcMain }).ipcMain;
}
