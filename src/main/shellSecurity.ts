import { LINEUP_PROTOCOL_ORIGIN, LINEUP_SHELL_URL } from '../contracts/shell.js';

/**
 * Shell IPC authorization is tied to the app-owned BrowserWindow sender, an
 * alive main frame, the exact shell URL, and the lineup://shell origin.
 */
export interface ShellIpcAuthorizationDetails {
  senderMatchesShell: boolean;
  senderDestroyed: boolean;
  senderUrl: string;
  frameUrl: string;
  frameIsMainFrame: boolean;
}

export function isAllowedShellUrl(url: string): boolean {
  return url === LINEUP_SHELL_URL;
}

export function isAllowedShellOrigin(url: string): boolean {
  try {
    const parsedUrl = new URL(url);
    return `${parsedUrl.protocol}//${parsedUrl.hostname}` === LINEUP_PROTOCOL_ORIGIN;
  } catch {
    return false;
  }
}

export function isAuthorizedShellIpcRequest(
  details: ShellIpcAuthorizationDetails,
): boolean {
  return (
    details.senderMatchesShell &&
    !details.senderDestroyed &&
    details.frameIsMainFrame &&
    isAllowedShellUrl(details.senderUrl) &&
    isAllowedShellOrigin(details.frameUrl)
  );
}
