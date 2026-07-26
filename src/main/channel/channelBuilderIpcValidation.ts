import { Buffer } from 'node:buffer';

import {
  normalizeChannelSetupConfig,
  type NormalizedChannelSetupConfig,
} from '../../domain/channelBuilder/index.js';
import type { ChannelSetupOperationName } from '../../contracts/channel.js';

const REQUEST_ID_PATTERN = /^[A-Za-z0-9._-]{1,120}$/u;
const PLAN_ID_PATTERN = /^channel-builder-plan-[a-f0-9]{32}$/u;
const OPERATION_ID_PATTERN = /^channel-builder-(?:review|apply)-[a-f0-9]{32}$/u;
const MAX_REQUEST_BYTES = 64 * 1024;

export type ValidatedChannelBuilderRequest<T> =
  | Readonly<{ ok: true; requestId: string; payload: T }>
  | Readonly<{ ok: false; requestId: string }>;

export function readChannelSetupEmptyRequest(
  value: unknown,
  fallbackRequestId: string,
): ValidatedChannelBuilderRequest<Record<string, never>> {
  const envelope = readEnvelope(value, fallbackRequestId);
  if (!envelope.ok || Object.keys(envelope.payload).length !== 0) {
    return { ok: false, requestId: envelope.requestId };
  }
  return { ok: true, requestId: envelope.requestId, payload: {} };
}

export function readChannelSetupStartReviewRequest(
  value: unknown,
  fallbackRequestId: string,
): ValidatedChannelBuilderRequest<{ config: NormalizedChannelSetupConfig }> {
  const envelope = readEnvelope(value, fallbackRequestId);
  if (!envelope.ok || !hasExactKeys(envelope.payload, ['config'])) {
    return { ok: false, requestId: envelope.requestId };
  }
  const context = readConfigContext(envelope.payload.config);
  if (context === null) return { ok: false, requestId: envelope.requestId };
  const normalized = normalizeChannelSetupConfig(envelope.payload.config, context);
  return normalized.ok
    ? { ok: true, requestId: envelope.requestId, payload: { config: normalized.config } }
    : { ok: false, requestId: envelope.requestId };
}

export function readChannelSetupStartApplyRequest(
  value: unknown,
  fallbackRequestId: string,
): ValidatedChannelBuilderRequest<{ planId: string; confirmReplace: boolean }> {
  const envelope = readEnvelope(value, fallbackRequestId);
  if (
    !envelope.ok ||
    !hasExactKeys(envelope.payload, ['planId', 'confirmReplace']) ||
    typeof envelope.payload.planId !== 'string' ||
    !PLAN_ID_PATTERN.test(envelope.payload.planId) ||
    typeof envelope.payload.confirmReplace !== 'boolean'
  ) {
    return { ok: false, requestId: envelope.requestId };
  }
  return {
    ok: true,
    requestId: envelope.requestId,
    payload: {
      planId: envelope.payload.planId,
      confirmReplace: envelope.payload.confirmReplace,
    },
  };
}

export function readChannelSetupOperationRequest(
  value: unknown,
  fallbackRequestId: string,
): ValidatedChannelBuilderRequest<{ operationId: string }> {
  const envelope = readEnvelope(value, fallbackRequestId);
  if (
    !envelope.ok ||
    !hasExactKeys(envelope.payload, ['operationId']) ||
    typeof envelope.payload.operationId !== 'string' ||
    !OPERATION_ID_PATTERN.test(envelope.payload.operationId)
  ) {
    return { ok: false, requestId: envelope.requestId };
  }
  return {
    ok: true,
    requestId: envelope.requestId,
    payload: { operationId: envelope.payload.operationId },
  };
}

export function channelBuilderRequestError(
  operation: ChannelSetupOperationName,
  kind: 'unauthorized' | 'validation',
) {
  return {
    code: kind === 'unauthorized' ? 'CHANNEL_UNAUTHORIZED' : 'CHANNEL_VALIDATION_FAILED',
    message:
      kind === 'unauthorized'
        ? 'Channel setup request is not authorized.'
        : 'Channel setup request is invalid.',
    retryable: false,
    recoverable: kind === 'validation',
    operation,
  } as const;
}

function readEnvelope(
  value: unknown,
  fallbackRequestId: string,
): ValidatedChannelBuilderRequest<Record<string, unknown>> {
  const requestId =
    isPlainRecord(value) &&
    typeof value.requestId === 'string' &&
    REQUEST_ID_PATTERN.test(value.requestId)
      ? value.requestId
      : fallbackRequestId;
  if (
    !isPlainRecord(value) ||
    !hasExactKeys(value, ['requestId', 'payload']) ||
    value.requestId !== requestId ||
    !isPlainRecord(value.payload) ||
    encodedSize(value) > MAX_REQUEST_BYTES
  ) {
    return { ok: false, requestId };
  }
  return { ok: true, requestId, payload: value.payload };
}

function readConfigContext(
  value: unknown,
): Readonly<{ serverId: string; selectedLibraryIds: readonly string[] }> | null {
  if (
    !isPlainRecord(value) ||
    typeof value.serverId !== 'string' ||
    !Array.isArray(value.selectedLibraryIds)
  ) {
    return null;
  }
  return {
    serverId: value.serverId,
    selectedLibraryIds: value.selectedLibraryIds.filter(
      (entry): entry is string => typeof entry === 'string',
    ),
  };
}

function encodedSize(value: unknown): number {
  try {
    return Buffer.byteLength(JSON.stringify(value), 'utf8');
  } catch {
    return MAX_REQUEST_BYTES + 1;
  }
}

function isPlainRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null &&
    Object.getPrototypeOf(value) === Object.prototype;
}

function hasExactKeys(value: object, expected: readonly string[]): boolean {
  const actual = Object.keys(value).sort();
  const sortedExpected = [...expected].sort();
  return actual.length === sortedExpected.length &&
    actual.every((key, index) => key === sortedExpected[index]);
}
