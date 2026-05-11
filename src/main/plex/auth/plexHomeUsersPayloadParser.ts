import { PlexAuthError } from './plexAuthError.js';
import type { PlexHomeUser } from './types.js';

const HOME_USER_CONTAINER_KEYS = new Set([
  'user',
  'users',
  'homeuser',
  'homeusers',
  'manageduser',
  'managedusers',
  'account',
  'accounts',
]);

const HOME_USER_SIGNAL_KEYS = [
  'admin',
  'isAdmin',
  'protected',
  'hasPassword',
  'pinProtected',
  'restricted',
  'home',
] as const;

const HOME_USER_ID_KEYS = ['id', 'userid', 'key'] as const;
const HOME_USER_TITLE_KEYS = ['title', 'username', 'name'] as const;

export function parseHomeUsersPayloadData(payload: unknown): PlexHomeUser[] {
  if (!payload) {
    return [];
  }

  if (typeof payload === 'string') {
    return parseHomeUsersTextPayload(payload);
  }

  if (typeof payload === 'object') {
    return parseHomeUsersObjectPayload(payload);
  }

  return [];
}

function parseHomeUsersTextPayload(payload: string): PlexHomeUser[] {
  const text = payload.trim();
  if (!text) {
    return [];
  }

  if (text.startsWith('{') || text.startsWith('[')) {
    try {
      return parseHomeUsersPayloadData(JSON.parse(text));
    } catch {
      throw new PlexAuthError('parse-error', 'Unable to parse Plex Home users JSON payload');
    }
  }

  if (!text.startsWith('<')) {
    return [];
  }

  const xmlUsers = parseHomeUsersXml(text);
  if (xmlUsers.length > 0 || isStructurallyValidXml(text)) {
    return xmlUsers;
  }

  return parseHomeUsersXmlFallback(text);
}

function parseHomeUsersObjectPayload(payload: object): PlexHomeUser[] {
  return dedupeHomeUsersById(
    collectHomeUserCandidates(payload)
      .map(parseHomeUserAttributes)
      .filter((user): user is PlexHomeUser => user !== null),
  );
}

function parseHomeUsersXml(payload: string): PlexHomeUser[] {
  if (typeof DOMParser !== 'function') {
    return parseHomeUsersXmlFallback(payload);
  }

  try {
    const parser = new DOMParser();
    const doc = parser.parseFromString(payload, 'application/xml');
    if (doc.getElementsByTagName('parsererror').length > 0) {
      return parseHomeUsersXmlFallback(payload);
    }

    const users = dedupeHomeUsersById(
      Array.from(doc.getElementsByTagName('*'))
        .filter((node) => HOME_USER_CONTAINER_KEYS.has(node.tagName.trim().toLowerCase()))
        .map(readXmlNodeAttributes)
        .map(parseHomeUserAttributes)
        .filter((user): user is PlexHomeUser => user !== null),
    );

    return users.length > 0 ? users : parseHomeUsersXmlFallback(payload);
  } catch {
    return parseHomeUsersXmlFallback(payload);
  }
}

function isStructurallyValidXml(payload: string): boolean {
  if (typeof DOMParser !== 'function') {
    return false;
  }

  try {
    const parser = new DOMParser();
    const doc = parser.parseFromString(payload, 'application/xml');
    return doc.getElementsByTagName('parsererror').length === 0;
  } catch {
    return false;
  }
}

function parseHomeUsersXmlFallback(payload: string): PlexHomeUser[] {
  const matches: string[] = [];
  const tagRegex = /<([:\w-]+)\b[^>]*>/g;
  let match: RegExpExecArray | null;

  while ((match = tagRegex.exec(payload)) !== null) {
    const raw = match[0];
    const tagName = match[1];
    if (tagName && HOME_USER_CONTAINER_KEYS.has(tagName.trim().toLowerCase())) {
      matches.push(raw);
    }
  }

  return dedupeHomeUsersById(
    matches
      .map(parseXmlAttributeString)
      .map(parseHomeUserAttributes)
      .filter((user): user is PlexHomeUser => user !== null),
  );
}

function parseXmlAttributeString(raw: string): Record<string, unknown> {
  const attrs: Record<string, unknown> = {};
  const attrRegex = /([:\w-]+)=["']([^"']*)["']/g;
  let match: RegExpExecArray | null;

  while ((match = attrRegex.exec(raw)) !== null) {
    const key = match[1];
    if (key) {
      attrs[key] = match[2] ?? '';
    }
  }

  return attrs;
}

function collectHomeUserCandidates(payload: object): Record<string, unknown>[] {
  const out: Record<string, unknown>[] = [];
  const queue: object[] = [];
  const visited = new WeakSet<object>();
  enqueueCandidate(payload, queue, visited);

  while (queue.length > 0) {
    const current = queue.shift();
    if (!current) {
      continue;
    }

    const record = current as Record<string, unknown>;
    if (looksLikeHomeUserRecord(record)) {
      out.push(record);
    }

    for (const [key, value] of Object.entries(record)) {
      collectNestedCandidates(key, value, queue, out, visited);
    }
  }

  return out;
}

function collectNestedCandidates(
  key: string,
  value: unknown,
  queue: object[],
  out: Record<string, unknown>[],
  visited: WeakSet<object>,
): void {
  if (!value) {
    return;
  }

  if (Array.isArray(value)) {
    const isUserContainer = HOME_USER_CONTAINER_KEYS.has(key.toLowerCase());
    for (const entry of value) {
      if (!entry || typeof entry !== 'object') {
        continue;
      }
      const record = entry as Record<string, unknown>;
      if (isUserContainer) {
        out.push(record);
      } else {
        enqueueCandidate(record, queue, visited);
      }
    }
    return;
  }

  if (typeof value === 'object') {
    const record = value as Record<string, unknown>;
    if (HOME_USER_CONTAINER_KEYS.has(key.toLowerCase())) {
      out.push(record);
    }
    enqueueCandidate(record, queue, visited);
  }
}

function enqueueCandidate(value: object, queue: object[], visited: WeakSet<object>): void {
  if (visited.has(value)) {
    return;
  }

  visited.add(value);
  queue.push(value);
}

function looksLikeHomeUserRecord(record: Record<string, unknown>): boolean {
  const id = getRecordValue(record, HOME_USER_ID_KEYS);
  const title = getRecordValue(record, HOME_USER_TITLE_KEYS);

  if (id === undefined || id === null || String(id).trim().length === 0) {
    return false;
  }

  if (title === undefined || title === null || String(title).trim().length === 0) {
    return false;
  }

  return HOME_USER_SIGNAL_KEYS.some((key) => getRecordValue(record, [key]) !== undefined);
}

function parseHomeUserAttributes(attrs: Record<string, unknown>): PlexHomeUser | null {
  const id = String(getRecordValue(attrs, HOME_USER_ID_KEYS) ?? '').trim();
  const title = String(getRecordValue(attrs, HOME_USER_TITLE_KEYS) ?? '').trim();

  if (!id || !title) {
    return null;
  }

  const thumbValue = getRecordValue(attrs, ['thumb', 'avatar', 'avatarUrl']);
  const restrictedValue = getRecordValue(attrs, ['restricted']);
  const protectedValue = getRecordValue(attrs, ['protected', 'hasPassword', 'pinProtected']);
  const adminValue = getRecordValue(attrs, ['admin', 'isAdmin']);

  return {
    id,
    title,
    thumb: typeof thumbValue === 'string' && thumbValue.trim().length > 0 ? thumbValue : null,
    admin: coerceBoolean(adminValue),
    protected: coerceBoolean(protectedValue),
    ...(restrictedValue === undefined ? {} : { restricted: coerceBoolean(restrictedValue) }),
  };
}

function coerceBoolean(value: unknown): boolean {
  if (typeof value === 'boolean') {
    return value;
  }
  if (typeof value === 'number') {
    return value === 1;
  }
  if (typeof value === 'string') {
    const normalized = value.trim().toLowerCase();
    return normalized === '1' || normalized === 'true' || normalized === 'yes';
  }
  return false;
}

function getRecordValue(record: Record<string, unknown>, keys: readonly string[]): unknown {
  const normalized = new Set(keys.map((key) => key.toLowerCase()));

  for (const [key, value] of Object.entries(record)) {
    if (normalized.has(key.toLowerCase())) {
      return value;
    }
  }

  return undefined;
}

function readXmlNodeAttributes(node: Element): Record<string, unknown> {
  const out: Record<string, unknown> = {};

  for (let index = 0; index < node.attributes.length; index += 1) {
    const attr = node.attributes.item(index);
    if (attr) {
      out[attr.name] = attr.value;
    }
  }

  return out;
}

function dedupeHomeUsersById(users: PlexHomeUser[]): PlexHomeUser[] {
  const deduped = new Map<string, PlexHomeUser>();

  for (const user of users) {
    if (!deduped.has(user.id)) {
      deduped.set(user.id, user);
    }
  }

  return Array.from(deduped.values());
}
