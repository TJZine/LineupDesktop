import { RENDERER_FORBIDDEN_PAYLOAD_KEYS } from './ipc.js';
import { PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS } from './persistence.js';
import { PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS } from './player.js';

/**
 * Policy sentinel for renderer and diagnostic redaction expectations.
 */
export const REDACTION_BOUNDARY = {
  rendererMayPersistSecrets: false,
  rendererMayReceiveRawAuthHeaders: false,
  rendererMayReceiveNativeHandles: false,
  diagnosticsMustBeRedacted: true,
} as const;

export type RedactionSurface =
  | 'renderer'
  | 'preload'
  | 'main'
  | 'native-helper'
  | 'logs'
  | 'diagnostics'
  | 'tests'
  | 'codex-output';

export const RD17_DIAGNOSTIC_FORBIDDEN_FIELD_KEYS = [
  'path',
  'filePath',
  'directory',
  'userData',
  'home',
  'username',
  'env',
  'argv',
  'pid',
  'process',
  'stderr',
  'stdout',
  'crashDump',
  'minidump',
  'stack',
  'rawLog',
  'rawIpc',
  'mediaPath',
  'localPath',
  'serverUri',
  'connectionUri',
  'privatePlaybackDescriptor',
  'headers',
  'authorization',
  'token',
  'credential',
  'secret',
] as const;

export const DIAGNOSTIC_FORBIDDEN_FIELD_KEYS = [
  ...new Set([
    ...PLAYER_FORBIDDEN_PRIVILEGED_FIELD_KEYS,
    ...RENDERER_FORBIDDEN_PAYLOAD_KEYS,
    ...PERSISTENCE_FORBIDDEN_RENDERER_FIELD_KEYS,
    ...RD17_DIAGNOSTIC_FORBIDDEN_FIELD_KEYS,
  ]),
] as const;

export type DiagnosticForbiddenFieldKey = (typeof DIAGNOSTIC_FORBIDDEN_FIELD_KEYS)[number];

export interface RedactionFinding {
  surface: RedactionSurface;
  file: string;
  reason:
    | 'raw-token'
    | 'raw-auth-header'
    | 'tokenized-url'
    | 'raw-filesystem-path'
    | 'raw-process-data'
    | 'native-handle'
    | 'raw-ipc-frame';
}
