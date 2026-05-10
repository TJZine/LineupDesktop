const REDACTED_DIAGNOSTIC_PATTERNS = [
  /\brawMediaUrl\b/giu,
  /\btokenizedUrl\b/giu,
  /\bauthHeaders\b/giu,
  /\brawAuthHeaders\b/giu,
  /\bpersistentToken\b/giu,
  /\bcredentialMaterial\b/giu,
  /\bnativeHandle\b/giu,
  /\blibmpvObject\b/giu,
  /\bengineId\b/giu,
  /\belectronApi\b/giu,
  /\bnodeApi\b/giu,
  /\brawPlexPayload\b/giu,
  /\bstreamKey\b/giu,
  /\bpartKey\b/giu,
  /\bsecretDiagnostics\b/giu,
  /https?:\/\/[^\s"')]+/giu,
] as const;

export function redactMainProcessError(
  error: unknown,
  fallback = 'Main process operation failed.',
): string {
  const message = error instanceof Error && error.message.trim().length > 0
    ? error.message
    : fallback;

  return REDACTED_DIAGNOSTIC_PATTERNS.reduce(
    (current, pattern) => current.replace(pattern, '[redacted]'),
    message,
  );
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
