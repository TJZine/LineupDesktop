import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

const tokenQueryKeys = [
  ['X-Plex', 'Token'].join('-'),
  'token',
];

const authHeaderKeys = [
  ['Authorization'].join(''),
  ['X-Plex', 'Token'].join('-'),
];

const credentialSchemes = [
  ['Bearer'].join(''),
  ['Basic'].join(''),
  ['Token'].join(''),
];

const secretFieldKeys = [
  'authToken',
  'authenticationToken',
  'accountToken',
  'activeToken',
  'plexToken',
  'clientSecret',
  'credential',
  'password',
];

const privilegedDiagnosticFieldKeys = [
  'tokenizedUrl',
  'rawMediaUrl',
  'nativeHandle',
  'libmpvObject',
  'engineId',
  'electronApi',
  'nodeApi',
  'rawPlexPayload',
  'streamKey',
  'partKey',
  'secretDiagnostics',
  'credentialMaterial',
];

const headerMapContainerKeys = [
  'headers',
  'authHeaders',
  'rawAuthHeaders',
];

const escapeRegExp = (value) => value.replace(/[.*+?^${}()|[\]\\]/gu, '\\$&');
const caseInsensitiveLiteral = (value) =>
  value
    .split('')
    .map((character) => {
      const lower = character.toLowerCase();
      const upper = character.toUpperCase();
      return lower === upper ? escapeRegExp(character) : `[${lower}${upper}]`;
    })
    .join('');

const tokenQueryKeyPattern = [
  escapeRegExp(tokenQueryKeys[0]),
  String.raw`[A-Za-z0-9_-]*${caseInsensitiveLiteral('token')}[A-Za-z0-9_-]*`,
].join('|');
const authHeaderKeyPattern = authHeaderKeys.map(caseInsensitiveLiteral).join('|');
const authHeaderKeyReferencePattern = String.raw`(?:"(?:${authHeaderKeyPattern})"|'(?:${authHeaderKeyPattern})'|(?:${authHeaderKeyPattern}))`;
const headerMapKeyPattern = authHeaderKeyReferencePattern;
const credentialSchemePattern = credentialSchemes.map(caseInsensitiveLiteral).join('|');
const secretFieldKeyPattern = secretFieldKeys.map(caseInsensitiveLiteral).join('|');
const secretFieldKeyReferencePattern = String.raw`(?:"(?:${secretFieldKeyPattern})"|'(?:${secretFieldKeyPattern})'|(?:${secretFieldKeyPattern}))`;
const privilegedDiagnosticFieldKeyPattern = privilegedDiagnosticFieldKeys.map(caseInsensitiveLiteral).join('|');
const privilegedDiagnosticFieldKeyReferencePattern = String.raw`(?:"(?:${privilegedDiagnosticFieldKeyPattern})"|'(?:${privilegedDiagnosticFieldKeyPattern})'|(?:${privilegedDiagnosticFieldKeyPattern}))`;
const headerMapContainerKeyPattern = headerMapContainerKeys.map(caseInsensitiveLiteral).join('|');
const headerMapContainerKeyReferencePattern = String.raw`(?:"(?:${headerMapContainerKeyPattern})"|'(?:${headerMapContainerKeyPattern})'|(?:${headerMapContainerKeyPattern}))`;
const bareAlphabeticSecretValuePattern = String.raw`(?:[a-z]{16,}|[A-Z]{16,}|(?=[A-Za-z]{16,})(?=(?:[a-z]*[A-Z]){3})(?=(?:[A-Z]*[a-z]){3})[A-Za-z]+)`;
const credentialValuePattern = String.raw`(?:[-A-Za-z0-9._~+/=]+:[-A-Za-z0-9._~+/=:]+|(?=[-A-Za-z0-9._~+/=:]{8,})(?=[-A-Za-z0-9._~+/=:]*[:0-9._~+/=-])[-A-Za-z0-9._~+/=:]+|${bareAlphabeticSecretValuePattern})`;
const authHeaderValuePattern = String.raw`(?:"(?:(?:${credentialSchemePattern})\s+)?[^"\r\n]+"|'(?:(?:${credentialSchemePattern})\s+)?[^'\r\n]+'|(?:(?:${credentialSchemePattern})\s+)?${credentialValuePattern})`;
const headerMapValuePattern = String.raw`(?:"[^"\r\n]*"|'[^'\r\n]*'|[^,}\r\n]+)`;
const quotedSecretFieldValuePattern = String.raw`(?:"(?:(?=[^"\r\n]{8,})(?=[^"\r\n]*[0-9._~+/=-])[^"\r\n]+|[A-Za-z]{16,})"|'(?:(?=[^'\r\n]{8,})(?=[^'\r\n]*[0-9._~+/=-])[^'\r\n]+|[A-Za-z]{16,})')`;
const bareSecretFieldValuePattern = String.raw`(?:(?=[-A-Za-z0-9._~+/=]{8,})(?=[-A-Za-z0-9._~+/=]*[0-9_~+/=-])[-A-Za-z0-9._~+/=]+|${bareAlphabeticSecretValuePattern})`;
const secretFieldValuePattern = String.raw`(?:${quotedSecretFieldValuePattern}|${bareSecretFieldValuePattern})`;
const privilegedCredentialValuePattern = String.raw`(?:(?=[-A-Za-z0-9._~+/=]{8,})(?=[-A-Za-z0-9._~+/=]*[0-9])[-A-Za-z0-9._~+/=]+|${bareAlphabeticSecretValuePattern})`;
const privilegedDiagnosticFieldValuePattern = String.raw`(?:https?:\/\/(?!(?:secret\.example|example\.invalid)(?:[/:?#"')\s,}\r\n]|$))[^\s,}\r\n]+|${privilegedCredentialValuePattern})`;

const forbiddenPatterns = [
  {
    label: 'token query parameter',
    pattern: new RegExp(String.raw`[?&](?:${tokenQueryKeyPattern})\s*=\s*[^&\s"')]+`, 'u'),
  },
  {
    label: 'raw Authorization header',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${authHeaderKeyReferencePattern})\s*:\s*${authHeaderValuePattern}`,
      'u',
    ),
  },
  {
    label: 'credential scheme',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${credentialSchemePattern})\s+${credentialValuePattern}`,
      'u',
    ),
  },
  {
    label: 'header map credential',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${headerMapContainerKeyReferencePattern})\s*[:=]\s*\{[\s\S]{0,2000}?(?:${headerMapKeyPattern})\s*:\s*${headerMapValuePattern}`,
      'u',
    ),
  },
  {
    label: 'secret field value',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:${secretFieldKeyReferencePattern})\s*(?:=|:\s*)\s*${secretFieldValuePattern}`,
      'u',
    ),
  },
  {
    label: 'privileged diagnostic field value',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:${privilegedDiagnosticFieldKeyReferencePattern})\s*(?:=|:\s*)\s*${privilegedDiagnosticFieldValuePattern}`,
      'u',
    ),
  },
  {
    label: 'oauth2 token path segment',
    pattern: new RegExp(
      String.raw`/oauth2/${credentialValuePattern}(?:[/?#\s"')]|$)`,
      'u',
    ),
  },
];

const textFilePattern = /\.(md|ts|tsx|js|mjs|cjs|json|toml|yaml|yml|txt)$/u;

export function collectFiles(root = repoRoot) {
  const files = [];
  walkDirectory(root, root, files);
  return files.sort();
}

export function scanFileContent(content) {
  const findings = [];
  for (const { label, pattern } of forbiddenPatterns) {
    pattern.lastIndex = 0;
    if (pattern.test(content)) {
      findings.push(label);
    }
  }
  return findings;
}

export function scanRepo(root = repoRoot) {
  const findings = [];
  for (const relativePath of collectFiles(root)) {
    const absolutePath = path.join(root, relativePath);
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile()) {
      continue;
    }
    const content = fs.readFileSync(absolutePath, 'utf8');
    for (const reason of scanFileContent(content)) {
      findings.push({ file: relativePath, reason });
    }
  }
  return findings;
}

function walkDirectory(root, directory, files) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (
        entry.name === 'node_modules' ||
        entry.name === '.git' ||
        entry.name === 'dist' ||
        entry.name === 'out' ||
        entry.name === 'coverage'
      ) {
        continue;
      }
      walkDirectory(root, absolute, files);
      continue;
    }
    if (entry.isFile() && textFilePattern.test(entry.name)) {
      files.push(path.relative(root, absolute));
    }
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  const findings = scanRepo();
  if (findings.length > 0) {
    for (const finding of findings) {
      console.error(`${finding.file}: ${finding.reason}`);
    }
    process.exit(1);
  }
  console.log('Redaction verification passed.');
}
