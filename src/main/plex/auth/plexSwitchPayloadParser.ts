import { PlexAuthError } from './plexAuthError.js';

const SWITCH_TOKEN_KEYS = ['authToken', 'authenticationToken', 'token'] as const;
const SWITCH_PAYLOAD_CONTAINER_KEYS = new Set(['mediacontainer', 'user', 'homeuser']);

export interface PlexSwitchPayloadResult {
  authToken: string;
}

export function parseSwitchPayloadData(payload: unknown): PlexSwitchPayloadResult {
  const token = findSwitchTokenInPayload(payload, new WeakSet<object>());
  if (token) {
    return { authToken: token };
  }

  if (typeof payload === 'string') {
    return parseSwitchPayloadText(payload);
  }

  throw new PlexAuthError('parse-error', 'Plex Home switch response did not include auth token');
}

function parseSwitchPayloadText(payload: string): PlexSwitchPayloadResult {
  const text = payload.trim();

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      return parseSwitchPayloadData(JSON.parse(text));
    } catch (error) {
      if (error instanceof PlexAuthError) {
        throw error;
      }
      throw new PlexAuthError('parse-error', 'Unable to parse Plex Home switch JSON payload');
    }
  }

  if (text.startsWith('<')) {
    const token = parseSwitchTokenXml(text);
    if (token) {
      return { authToken: token };
    }
  }

  throw new PlexAuthError('parse-error', 'Plex Home switch response did not include auth token');
}

function parseSwitchTokenXml(payload: string): string | null {
  return parseSwitchTokenDocument(payload) ?? parseSwitchTokenText(payload);
}

function parseSwitchTokenDocument(payload: string): string | null {
  if (typeof DOMParser !== 'function') {
    return null;
  }

  try {
    const parser = new DOMParser();
    const doc = parser.parseFromString(payload, 'application/xml');
    if (doc.getElementsByTagName('parsererror').length > 0) {
      return null;
    }

    const candidates = [
      doc.documentElement,
      doc.getElementsByTagName('User')[0],
      doc.getElementsByTagName('HomeUser')[0],
    ];

    for (const candidate of candidates) {
      const token = readTokenFromXmlNode(candidate);
      if (token) {
        return token;
      }
    }
  } catch {
    return null;
  }

  return null;
}

function readTokenFromXmlNode(node: Element | null | undefined): string | null {
  if (!node) {
    return null;
  }

  const attrToken = findSwitchToken(readXmlNodeAttributes(node));
  if (attrToken) {
    return attrToken;
  }

  for (const key of SWITCH_TOKEN_KEYS) {
    const child = node.getElementsByTagName(key)[0];
    const value = child?.textContent?.trim();
    if (value) {
      return value;
    }
  }

  return null;
}

function parseSwitchTokenText(payload: string): string | null {
  for (const key of SWITCH_TOKEN_KEYS) {
    const escapedKey = escapeRegExp(key);
    const attrMatch = payload.match(new RegExp(`${escapedKey}=["']([^"']+)["']`, 'i'));
    if (attrMatch?.[1]) {
      return attrMatch[1];
    }

    const nodeMatch = payload.match(new RegExp(`<${escapedKey}>([^<]+)</${escapedKey}>`, 'i'));
    if (nodeMatch?.[1]) {
      return nodeMatch[1];
    }
  }

  return null;
}

function findSwitchToken(record: Record<string, unknown>): string | null {
  const normalizedKeys = new Set(SWITCH_TOKEN_KEYS.map((key) => key.toLowerCase()));

  for (const [key, value] of Object.entries(record)) {
    if (!normalizedKeys.has(key.toLowerCase()) || typeof value !== 'string') {
      continue;
    }

    const trimmed = value.trim();
    if (trimmed.length > 0) {
      return trimmed;
    }
  }

  return null;
}

function findSwitchTokenInPayload(payload: unknown, seen: WeakSet<object>): string | null {
  if (!payload) {
    return null;
  }

  if (Array.isArray(payload)) {
    if (seen.has(payload)) {
      return null;
    }
    seen.add(payload);

    for (const entry of payload) {
      const token = findSwitchTokenInPayload(entry, seen);
      if (token) {
        return token;
      }
    }
    return null;
  }

  if (typeof payload !== 'object') {
    return null;
  }

  if (seen.has(payload)) {
    return null;
  }
  seen.add(payload);

  const record = payload as Record<string, unknown>;
  const direct = findSwitchToken(record);
  if (direct) {
    return direct;
  }

  for (const [key, value] of Object.entries(record)) {
    if (typeof value === 'string' && SWITCH_PAYLOAD_CONTAINER_KEYS.has(key.toLowerCase())) {
      const nested = findSwitchTokenInStructuredString(value, seen);
      if (nested) {
        return nested;
      }
      continue;
    }

    const nested = findSwitchTokenInPayload(value, seen);
    if (nested) {
      return nested;
    }
  }

  return null;
}

function findSwitchTokenInStructuredString(payload: string, seen: WeakSet<object>): string | null {
  const text = payload.trim();
  if (!text) {
    return null;
  }

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      return findSwitchTokenInPayload(JSON.parse(text), seen);
    } catch {
      return null;
    }
  }

  if (text.startsWith('<')) {
    return parseSwitchTokenXml(text);
  }

  return null;
}

function readXmlNodeAttributes(node: Element): Record<string, unknown> {
  return Object.fromEntries(
    Array.from(node.attributes, (attribute) => [attribute.name, attribute.value] as const),
  );
}

function escapeRegExp(value: string): string {
  return value.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
}
