import fs from 'node:fs/promises';
import path from 'node:path';

import { net, protocol } from 'electron';
import { pathToFileURL } from 'node:url';

export const LINEUP_CSP =
  "default-src 'none'; script-src 'self'; style-src 'self'; img-src 'self'; connect-src 'none'; object-src 'none'; base-uri 'none'; form-action 'none'; frame-src 'none';";

/**
 * The lineup://shell handler serves only files under the renderer root with the
 * approved MIME allowlist and CSP, rejecting traversal, search params, and
 * non-shell hosts.
 */
const CONTENT_TYPES = new Map<string, string>([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
]);

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
  const url = new URL(urlText);
  if (url.protocol !== 'lineup:' || url.hostname !== 'shell' || url.search !== '') {
    return textResponse('Not found.', 404);
  }
  if (!url.pathname || url.pathname === '/') {
    return textResponse('Not found.', 404);
  }

  const filePath = path.resolve(rendererRoot, `.${decodeURIComponent(url.pathname)}`);
  const relativePath = path.relative(rendererRoot, filePath);
  if (
    relativePath.length === 0 ||
    relativePath.startsWith('..') ||
    path.isAbsolute(relativePath)
  ) {
    return textResponse('Not found.', 404);
  }

  const extension = path.extname(filePath);
  const contentType = CONTENT_TYPES.get(extension);
  if (!contentType) {
    return textResponse('Not found.', 404);
  }

  if (url.pathname === '/index.html') {
    const html = await fs.readFile(filePath, 'utf8');
    if (!html.includes(`content="${LINEUP_CSP}"`)) {
      return textResponse('Content Security Policy missing.', 500);
    }
    return new Response(html, {
      headers: {
        'Content-Security-Policy': LINEUP_CSP,
        'content-type': contentType,
      },
    });
  }

  const response = await net.fetch(pathToFileURL(filePath).toString());
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers: {
      'Content-Security-Policy': LINEUP_CSP,
      'content-type': contentType,
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
