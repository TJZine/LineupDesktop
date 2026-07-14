import fs from 'node:fs/promises';

import { net, protocol } from 'electron';
import { pathToFileURL } from 'node:url';

import { resolveRendererProtocolRequest } from './rendererProtocolPolicy.js';

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

export function registerLineupProtocolHandler(rendererRoot: string): void {
  protocol.handle('lineup', async (request) => serveRendererFile(request.url, rendererRoot));
}

export async function serveRendererFile(urlText: string, rendererRoot: string): Promise<Response> {
  const resolution = resolveRendererProtocolRequest(urlText, rendererRoot);
  if (!resolution.ok) {
    return textResponse('Not found.', 404);
  }

  if (resolution.isIndex) {
    const html = await fs.readFile(resolution.filePath, 'utf8');
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

function textResponse(text: string, status: number): Response {
  return new Response(text, {
    status,
    headers: {
      'Content-Security-Policy': LINEUP_CSP,
      'content-type': 'text/plain; charset=utf-8',
    },
  });
}
