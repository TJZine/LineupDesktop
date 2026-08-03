import fs from 'node:fs/promises';

import { net, protocol } from 'electron';
import { pathToFileURL } from 'node:url';

import { resolveRendererProtocolRequest } from './rendererProtocolPolicy.js';
import { ARTWORK_REF_ID_PATTERN } from '../contracts/artwork.js';
import type { GuideArtworkDelivery, GuideArtworkOwner } from './channel/guideArtworkOwner.js';

export interface GuideArtworkProtocolDiagnosticPort {
  recordDeliveryFailure(): void;
}

export const LINEUP_CSP =
  "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none';";

export function registerLineupProtocolScheme(): void {
  protocol.registerSchemesAsPrivileged([
    {
      scheme: 'lineup',
      privileges: {
        standard: true,
        secure: true,
      },
    },
  ]);
}

export function registerLineupProtocolHandler(
  rendererRoot: string,
  guideArtworkOwner?: Pick<GuideArtworkOwner, 'get'>,
  diagnosticPort?: GuideArtworkProtocolDiagnosticPort,
): void {
  protocol.handle('lineup', async (request) =>
    serveLineupProtocolRequest(request, rendererRoot, guideArtworkOwner, diagnosticPort));
}

export async function serveLineupProtocolRequest(
  request: Pick<Request, 'url' | 'method'>,
  rendererRoot: string,
  guideArtworkOwner?: Pick<GuideArtworkOwner, 'get'>,
  diagnosticPort?: GuideArtworkProtocolDiagnosticPort,
): Promise<Response> {
  if (isArtworkRoute(request.url)) {
    return serveGuideArtwork(request, guideArtworkOwner, diagnosticPort);
  }
  if (request.method !== 'GET') return textResponse('Not found.', 404);
  return serveRendererFile(request.url, rendererRoot);
}

export async function serveRendererFile(urlText: string, rendererRoot: string): Promise<Response> {
  const resolution = resolveRendererProtocolRequest(urlText, rendererRoot);
  if (!resolution.ok) {
    return textResponse('Not found.', 404);
  }

  if (resolution.isIndex) {
    let html: string;
    try {
      html = await fs.readFile(resolution.filePath, 'utf8');
    } catch (error) {
      return textResponse('Unable to load renderer.', isNodeErrorWithCode(error, 'ENOENT') ? 404 : 500);
    }
    if (!html.includes(`content="${LINEUP_CSP}"`)) {
      return textResponse('Content Security Policy missing.', 500);
    }
    return new Response(html, {
      headers: {
        'Content-Security-Policy': LINEUP_CSP,
        'content-type': resolution.contentType,
      },
    });
  }

  const response = await net.fetch(pathToFileURL(resolution.filePath).toString());
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: {
      'Content-Security-Policy': LINEUP_CSP,
      'content-type': resolution.contentType,
    },
  });
}

function isNodeErrorWithCode(error: unknown, code: string): boolean {
  return error instanceof Error
    && 'code' in error
    && (error as { code?: unknown }).code === code;
}

function textResponse(text: string, status: number): Response {
  return new Response(text, {
    status,
    headers: {
      'Content-Security-Policy': LINEUP_CSP,
      'content-type': 'text/plain; charset=utf-8',
    },
  });
}

async function serveGuideArtwork(
  request: Pick<Request, 'url' | 'method'>,
  guideArtworkOwner: Pick<GuideArtworkOwner, 'get'> | undefined,
  diagnosticPort: GuideArtworkProtocolDiagnosticPort | undefined,
): Promise<Response> {
  if (request.method !== 'GET') return textResponse('Not found.', 404);
  const refId = readArtworkRefId(request.url);
  if (refId === null || guideArtworkOwner === undefined) {
    return textResponse('Not found.', 404);
  }
  let delivery: GuideArtworkDelivery | null;
  try {
    delivery = await guideArtworkOwner.get(refId);
  } catch {
    try { diagnosticPort?.recordDeliveryFailure(); } catch { /* diagnostics are best-effort */ }
    return textResponse('Not found.', 404);
  }
  if (delivery === null) return textResponse('Not found.', 404);
  return new Response(new Uint8Array(delivery.bytes).buffer, {
    status: 200,
    headers: {
      'Content-Security-Policy': LINEUP_CSP,
      'content-type': delivery.mimeType,
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
    },
  });
}

function isArtworkRoute(urlText: string): boolean {
  try {
    const url = new URL(urlText);
    return url.protocol === 'lineup:' && url.host === 'shell' &&
      (url.pathname === '/artwork' || url.pathname.startsWith('/artwork/'));
  } catch {
    return false;
  }
}

function readArtworkRefId(urlText: string): string | null {
  try {
    const url = new URL(urlText);
    if (
      url.protocol !== 'lineup:' ||
      url.host !== 'shell' ||
      url.username !== '' ||
      url.password !== '' ||
      url.search !== '' ||
      url.hash !== ''
    ) return null;
    const match = /^\/artwork\/([^/]+)$/u.exec(url.pathname);
    if (match === null || match[1] === undefined || !ARTWORK_REF_ID_PATTERN.test(match[1])) {
      return null;
    }
    return match[1];
  } catch {
    return null;
  }
}
