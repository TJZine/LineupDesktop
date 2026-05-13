/**
 * Policy sentinel for renderer and diagnostic redaction expectations. This
 * stub records the contract surface but is not enforcement by itself.
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

export interface RedactionFinding {
  surface: RedactionSurface;
  file: string;
  reason: 'raw-token' | 'raw-auth-header' | 'tokenized-url';
}
