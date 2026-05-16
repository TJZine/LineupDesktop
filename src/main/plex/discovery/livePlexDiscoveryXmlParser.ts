import type { PlexApiConnection, PlexApiResource } from './types.js';
import { LivePlexTransportError } from '../livePlexTransportError.js';

const MIN_PORT = 1;
const MAX_PORT = 65_535;
const XML_TAG_PATTERN = /<\s*(\/?)([A-Za-z_][\w:.-]*)([^<>]*?)(\/?)\s*>/gu;

export function parseXmlDiscoveryResourceArray(text: string, status: number): PlexApiResource[] {
  const normalizedText = stripXmlPreamble(text);
  const resources: PlexApiResource[] = [];
  const stack: Array<{ name: string; device?: PlexApiResource }> = [];
  let rootCount = 0;
  let cursor = 0;

  for (const match of normalizedText.matchAll(XML_TAG_PATTERN)) {
    const gap = normalizedText.slice(cursor, match.index);
    if (gap.includes('<') || (stack.length === 0 && gap.trim().length > 0)) {
      throwInvalidXml(status);
    }
    cursor = match.index + match[0].length;

    const closing = (match[1] ?? '').length > 0;
    const name = (match[2] ?? '').toLowerCase();
    const attributes = parseXmlAttributes(match[3] ?? '', status);
    const selfClosing = (match[4] ?? '').length > 0;
    if (closing) {
      if (selfClosing || attributes.size > 0 || stack.length === 0) {
        throwInvalidXml(status);
      }
      const closed = stack.pop();
      if (!closed || closed.name !== name) {
        throwInvalidXml(status);
      }
      if (closed.device) {
        resources.push(closed.device);
      }
      continue;
    }

    if (stack.length === 0) {
      rootCount += 1;
      if (rootCount > 1) {
        throwInvalidXml(status);
      }
    }

    if (name === 'device') {
      const device = mapXmlDeviceAttributes(attributes);
      if (selfClosing) {
        resources.push(device);
      } else {
        stack.push({ name, device });
      }
      continue;
    }

    if (name === 'connection') {
      const currentDevice = findCurrentXmlDevice(stack);
      if (currentDevice) {
        currentDevice.connections.push(mapXmlConnectionAttributes(attributes));
      }
    }

    if (!selfClosing) {
      stack.push({ name });
    }
  }

  const trailing = normalizedText.slice(cursor);
  if (
    trailing.includes('<') ||
    (stack.length === 0 && trailing.trim().length > 0) ||
    stack.length > 0 ||
    rootCount === 0
  ) {
    throwInvalidXml(status);
  }
  return resources;
}

function findCurrentXmlDevice(stack: Array<{ name: string; device?: PlexApiResource }>): PlexApiResource | null {
  for (let index = stack.length - 1; index >= 0; index -= 1) {
    const device = stack[index]?.device;
    if (device) {
      return device;
    }
  }
  return null;
}

function stripXmlPreamble(text: string): string {
  return text
    .replace(/<\?xml\b[\s\S]*?\?>/giu, '')
    .replace(/<!--[\s\S]*?-->/gu, '')
    .trim();
}

function parseXmlAttributes(rawAttributes: string, status: number): Map<string, string> {
  const attributes = new Map<string, string>();
  let cursor = 0;
  while (cursor < rawAttributes.length) {
    cursor = skipXmlWhitespace(rawAttributes, cursor);
    if (cursor >= rawAttributes.length) {
      break;
    }

    const nameStart = cursor;
    while (cursor < rawAttributes.length && /[^\s=]/u.test(rawAttributes[cursor] ?? '')) {
      cursor += 1;
    }
    const name = rawAttributes.slice(nameStart, cursor);
    cursor = skipXmlWhitespace(rawAttributes, cursor);
    if (name.length === 0 || rawAttributes[cursor] !== '=') {
      throwInvalidXml(status);
    }
    cursor += 1;
    cursor = skipXmlWhitespace(rawAttributes, cursor);

    const quote = rawAttributes[cursor];
    if (quote !== '"' && quote !== "'") {
      throwInvalidXml(status);
    }
    cursor += 1;
    const valueStart = cursor;
    while (cursor < rawAttributes.length && rawAttributes[cursor] !== quote) {
      cursor += 1;
    }
    if (rawAttributes[cursor] !== quote) {
      throwInvalidXml(status);
    }
    attributes.set(name, decodeXmlAttribute(rawAttributes.slice(valueStart, cursor), status));
    cursor += 1;
  }
  return attributes;
}

function skipXmlWhitespace(value: string, cursor: number): number {
  let nextCursor = cursor;
  while (nextCursor < value.length && /\s/u.test(value[nextCursor] ?? '')) {
    nextCursor += 1;
  }
  return nextCursor;
}

function mapXmlDeviceAttributes(attributes: Map<string, string>): PlexApiResource {
  return {
    clientIdentifier: readString(attributes.get('clientIdentifier')),
    name: readString(attributes.get('name')),
    sourceTitle: readString(attributes.get('sourceTitle')),
    ownerId: readString(attributes.get('ownerId')),
    owned: readBoolean(attributes.get('owned')),
    provides: readString(attributes.get('provides')),
    connections: [],
  };
}

function mapXmlConnectionAttributes(attributes: Map<string, string>): PlexApiConnection {
  return {
    uri: readString(attributes.get('uri')),
    protocol: readString(attributes.get('protocol')),
    address: readString(attributes.get('address')),
    port: normalizePort(attributes.get('port')),
    local: readBoolean(attributes.get('local')),
    relay: readBoolean(attributes.get('relay')),
  };
}

function decodeXmlAttribute(value: string, status: number): string {
  let decoded = '';
  let cursor = 0;
  while (cursor < value.length) {
    const ampersandIndex = value.indexOf('&', cursor);
    if (ampersandIndex === -1) {
      decoded += value.slice(cursor);
      break;
    }

    decoded += value.slice(cursor, ampersandIndex);
    const semicolonIndex = value.indexOf(';', ampersandIndex + 1);
    if (semicolonIndex === -1) {
      throwInvalidXml(status);
    }
    decoded += decodeXmlEntity(value.slice(ampersandIndex + 1, semicolonIndex), status);
    cursor = semicolonIndex + 1;
  }
  return decoded;
}

function decodeXmlEntity(entity: string, status: number): string {
  switch (entity) {
    case 'quot':
      return '"';
    case 'apos':
      return "'";
    case 'lt':
      return '<';
    case 'gt':
      return '>';
    case 'amp':
      return '&';
  }

  const hexMatch = /^#x([0-9a-f]+)$/iu.exec(entity);
  if (hexMatch) {
    return decodeXmlCodepoint(hexMatch[1] ?? '', 16, status);
  }
  const decimalMatch = /^#([0-9]+)$/u.exec(entity);
  if (decimalMatch) {
    return decodeXmlCodepoint(decimalMatch[1] ?? '', 10, status);
  }
  throwInvalidXml(status);
}

function decodeXmlCodepoint(value: string, radix: number, status: number): string {
  const codepoint = Number.parseInt(value, radix);
  if (!isXmlCharacterCodepoint(codepoint)) {
    throwInvalidXml(status);
  }
  try {
    return String.fromCodePoint(codepoint);
  } catch {
    throwInvalidXml(status);
  }
}

function isXmlCharacterCodepoint(codepoint: number): boolean {
  return (
    Number.isInteger(codepoint) &&
    (codepoint === 0x09 ||
      codepoint === 0x0a ||
      codepoint === 0x0d ||
      (codepoint >= 0x20 && codepoint <= 0xd7ff) ||
      (codepoint >= 0xe000 && codepoint <= 0xfffd) ||
      (codepoint >= 0x10000 && codepoint <= 0x10ffff))
  );
}

function readString(value: unknown): string {
  return typeof value === 'string' ? value.trim() : '';
}

function readBoolean(value: unknown): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true';
  }
  return false;
}

function normalizePort(value: unknown): number {
  const parsed =
    typeof value === 'number' ? value : typeof value === 'string' && value.trim().length > 0 ? Number(value.trim()) : 0;
  return Number.isInteger(parsed) && parsed >= MIN_PORT && parsed <= MAX_PORT ? parsed : 0;
}

function throwInvalidXml(status: number): never {
  throw new LivePlexTransportError('parse-error', 'Invalid Plex discovery XML response', status);
}
