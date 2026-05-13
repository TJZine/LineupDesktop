import { redactDiagnosticText } from '../contracts/diagnostics.js';

/**
 * Best-effort diagnostic redaction patterns cover token-shaped keys, auth
 * headers, URLs, local paths, process/native identifiers, and secret-shaped
 * fields before main-process errors are logged.
 */
export function redactMainProcessError(
  error: unknown,
  fallback = 'Main process operation failed.',
): string {
  const message = error instanceof Error && error.message.trim().length > 0
    ? error.message
    : fallback;

  return redactDiagnosticText(message);
}

export function reportMainProcessDiagnostic(message: string, error: unknown): void {
  console.error(`${message}: ${redactMainProcessError(error)}`);
}
