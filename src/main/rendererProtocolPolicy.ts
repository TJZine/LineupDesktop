import path from 'node:path';

export type RendererProtocolResolution =
  | {
      ok: true;
      filePath: string;
      contentType: string;
      isIndex: boolean;
    }
  | { ok: false };

const CONTENT_TYPES = new Map<string, string>([
  ['.html', 'text/html; charset=utf-8'],
  ['.js', 'text/javascript; charset=utf-8'],
  ['.css', 'text/css; charset=utf-8'],
  ['.png', 'image/png'],
]);

/**
 * Resolves only self-owned renderer files under the supplied renderer root.
 * This policy is pure: malformed and rejected requests never touch the file
 * system and never throw.
 */
export function resolveRendererProtocolRequest(
  urlText: string,
  rendererRoot: string,
): RendererProtocolResolution {
  try {
    const url = new URL(urlText);
    if (
      url.protocol !== 'lineup:' ||
      url.host !== 'shell' ||
      url.username !== '' ||
      url.password !== '' ||
      url.search !== ''
    ) {
      return { ok: false };
    }

    const rawPath = extractRawPath(urlText);
    const decodedPath = decodeURIComponent(rawPath);
    if (
      decodedPath === '' ||
      decodedPath === '/' ||
      decodedPath.startsWith('//') ||
      decodedPath.includes('\0') ||
      hasTraversalSegment(decodedPath)
    ) {
      return { ok: false };
    }

    const resolvedRoot = path.resolve(rendererRoot);
    const filePath = path.resolve(resolvedRoot, `.${decodedPath}`);
    const relativePath = path.relative(resolvedRoot, filePath);
    if (
      relativePath.length === 0 ||
      relativePath.startsWith('..') ||
      path.isAbsolute(relativePath)
    ) {
      return { ok: false };
    }

    const contentType = CONTENT_TYPES.get(path.extname(filePath));
    if (contentType === undefined) {
      return { ok: false };
    }

    return {
      ok: true,
      filePath,
      contentType,
      isIndex: decodedPath === '/index.html',
    };
  } catch {
    return { ok: false };
  }
}

function extractRawPath(urlText: string): string {
  const schemeSeparator = urlText.indexOf('://');
  if (schemeSeparator < 0) return '';
  const pathStart = urlText.indexOf('/', schemeSeparator + 3);
  if (pathStart < 0) return '';
  const queryStart = urlText.indexOf('?', pathStart);
  const fragmentStart = urlText.indexOf('#', pathStart);
  const candidates = [queryStart, fragmentStart].filter((value) => value >= 0);
  const pathEnd = candidates.length === 0 ? urlText.length : Math.min(...candidates);
  return urlText.slice(pathStart, pathEnd);
}

function hasTraversalSegment(decodedPath: string): boolean {
  return decodedPath
    .replaceAll('\\', '/')
    .split('/')
    .some((segment) => segment === '..');
}
