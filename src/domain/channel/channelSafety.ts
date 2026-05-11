export const CHANNEL_DOMAIN_FORBIDDEN_KEYS = [
  'rawMediaUrl',
  'tokenizedUrl',
  'authHeaders',
  'rawAuthHeaders',
  'persistentToken',
  'credentialMaterial',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
  'localStorage',
  'storageKey',
  'currentChannelKey',
  'serverUri',
  'connectionUri',
] as const;

export type ChannelDomainForbiddenKey = (typeof CHANNEL_DOMAIN_FORBIDDEN_KEYS)[number];

export interface ChannelSafetyFinding {
  path: string;
  key: ChannelDomainForbiddenKey;
}

export function auditChannelDomainValueForForbiddenFields(
  value: unknown,
  rootPath = '$',
): ChannelSafetyFinding[] {
  const findings: ChannelSafetyFinding[] = [];
  auditValue(value, rootPath, findings, new WeakSet<object>());
  return findings;
}

export function assertChannelDomainValueIsSafe(value: unknown, rootPath = '$'): void {
  const findings = auditChannelDomainValueForForbiddenFields(value, rootPath);
  if (findings.length > 0) {
    throw new Error(
      `Channel domain value contains forbidden field(s): ${findings
        .map((finding) => `${finding.path}.${finding.key}`)
        .join(', ')}`,
    );
  }
}

function auditValue(
  value: unknown,
  path: string,
  findings: ChannelSafetyFinding[],
  seen: WeakSet<object>,
): void {
  if (!value || typeof value !== 'object') {
    return;
  }
  if (seen.has(value)) {
    return;
  }
  seen.add(value);

  if (Array.isArray(value)) {
    value.forEach((entry, index) => auditValue(entry, `${path}[${String(index)}]`, findings, seen));
    return;
  }

  for (const [key, entry] of Object.entries(value as Record<string, unknown>)) {
    if (isForbiddenKey(key)) {
      findings.push({ path, key });
    }
    auditValue(entry, `${path}.${key}`, findings, seen);
  }
}

function isForbiddenKey(value: string): value is ChannelDomainForbiddenKey {
  return (CHANNEL_DOMAIN_FORBIDDEN_KEYS as readonly string[]).includes(value);
}
