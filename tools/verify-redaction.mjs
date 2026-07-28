import fs from 'node:fs';
import path from 'node:path';
import { Buffer } from 'node:buffer';
import { execFileSync } from 'node:child_process';
import { fileURLToPath } from 'node:url';

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');
const diagnosticRedactionVersion = 'rd17-redaction-v1';

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
const rawProcessDataKeyPattern = ['env', 'argv', 'pid', 'stderr', 'stdout', 'crashDump', 'minidump', 'rawLog']
  .map(caseInsensitiveLiteral)
  .join('|');
const nativeHandleKeyPattern = ['nativeHandle', 'libmpvObject', 'engineId']
  .map(caseInsensitiveLiteral)
  .join('|');
const rawIpcFrameKeyPattern = ['rawIpc'].map(caseInsensitiveLiteral).join('|');
const repositoryUnixFilesystemPathPattern = new RegExp(
  String.raw`(?<![\p{L}\p{N}._~+/\\-])/(?:Applications|Library|Users|Volumes|etc|home|opt|private|root|srv|tmp|usr|var|(?=[\p{L}\p{N}._()-]*[^\x00-\x7F])[\p{L}\p{N}._()-]+)/(?![/?#])[^"'<>{}\r\n]+`,
  'u',
);
const repositoryDriveFilesystemPathPattern = new RegExp(
  String.raw`(?<![\p{L}\p{N}._~+/\\-])[A-Za-z]:(?:/(?!/)|\\(?!\\))[^"'<>{}\r\n]+`,
  'u',
);
const repositoryUncFilesystemPathPattern = new RegExp(
  String.raw`(?<!\\)\\\\(?!\\)[A-Za-z0-9][A-Za-z0-9.-]*\\[A-Za-z0-9][A-Za-z0-9 ._()-]*\\[^"'<>{}\r\n]+`,
  'u',
);
const repositorySerializedFilesystemPathPattern = new RegExp(
  String.raw`"[^"\r\n]+"\s*:\s*"(?:[A-Za-z]:(?:/|\\\\)|\\\\\\\\|/(?!/))(?=[^"\r\n]*[\\/])(?:\\.|[^"\\])+"`,
  'u',
);
const repositoryFileUrlFilesystemPathPattern = new RegExp(
  String.raw`file:\/\/(?:\/(?!\/)[^/\s"'<>]+\/|[A-Za-z]:[\\/]|[A-Za-z0-9][A-Za-z0-9.-]*\/[^/\s"'<>]+\/)`,
  'u',
);
const repositoryContextualUnixFilesystemPathPattern = new RegExp(
  String.raw`\b(?:absolute|archive|cache|copied|directory|file|filesystem|folder|generated|local|mounted|output|path|saved|workspace)\b[^\r\n]{0,80}?(?<![\p{L}\p{N}._~+/\\-])/(?!/)[\p{L}\p{N}._()-]+(?:/[\p{L}\p{N} ._()-]+)+`,
  'iu',
);
const forbiddenPatterns = [
  {
    label: 'token-query-parameter',
    pattern: new RegExp(String.raw`[?&](?:${tokenQueryKeyPattern})\s*=\s*[^&\s"')]+`, 'u'),
  },
  {
    label: 'raw-auth-header',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${authHeaderKeyReferencePattern})\s*:\s*${authHeaderValuePattern}`,
      'u',
    ),
  },
  {
    label: 'credential-scheme',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${credentialSchemePattern})\s+${credentialValuePattern}`,
      'u',
    ),
  },
  {
    label: 'header-map-credential',
    pattern: new RegExp(
      String.raw`(?<![\w-])(?:${headerMapContainerKeyReferencePattern})\s*[:=]\s*\{[\s\S]{0,2000}?(?:${headerMapKeyPattern})\s*:\s*${headerMapValuePattern}`,
      'u',
    ),
  },
  {
    label: 'secret-field-value',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:${secretFieldKeyReferencePattern})\s*(?:=|:\s*)\s*${secretFieldValuePattern}`,
      'u',
    ),
  },
  {
    label: 'secret-field-value',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:${caseInsensitiveLiteral('credential')})\s+\d{2,}`,
      'u',
    ),
  },
  {
    label: 'native-handle',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:"(?:${nativeHandleKeyPattern})"|'(?:${nativeHandleKeyPattern})'|(?:${nativeHandleKeyPattern}))\s*(?:=|:\s*|\s+)\s*(?:"?0x[0-9a-fA-F]+"?|"?\d{4,}"?)`,
      'u',
    ),
  },
  {
    label: 'privileged-diagnostic-field-value',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:${privilegedDiagnosticFieldKeyReferencePattern})\s*(?:=|:\s*)\s*${privilegedDiagnosticFieldValuePattern}`,
      'u',
    ),
  },
  {
    label: 'oauth-token-path-segment',
    pattern: new RegExp(
      String.raw`/oauth2/${credentialValuePattern}(?:[/?#\s"')]|$)`,
      'u',
    ),
  },
  {
    label: 'raw-process-data',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:"(?:${rawProcessDataKeyPattern})"|'(?:${rawProcessDataKeyPattern})'|(?:${rawProcessDataKeyPattern}))\s*(?:=|:\s*|\s+)\s*(?:"(?:[^"\r\n]*(?:[A-Za-z]:\\|\/Users\/|\/home\/|token=|Authorization:)[^"\r\n]*)"|'(?:[^'\r\n]*(?:[A-Za-z]:\\|\/Users\/|\/home\/|token=|Authorization:)[^'\r\n]*)'|\d{2,})`,
      'u',
    ),
  },
  {
    label: 'raw-ipc-frame',
    pattern: new RegExp(
      String.raw`(?<![?&\w-])(?:"(?:${rawIpcFrameKeyPattern})"|'(?:${rawIpcFrameKeyPattern})'|(?:${rawIpcFrameKeyPattern}))\s*(?:=|:\s*|\s+)\s*(?:"[^"\r\n]{4,}"|'[^'\r\n]{4,}'|\{[^{}\r\n]{1,200}\}|channel\s+\S+)`,
      'u',
    ),
  },
];

const textFilePattern = /\.(md|ts|tsx|js|mjs|cjs|json|ndjson|toml|yaml|yml|txt)$/u;
const skippedDirectoryNames = new Set([
  'node_modules',
  '.git',
  '.codanna',
  'dist',
  'out',
  'coverage',
]);

/**
 * Repository redaction scans version-controlled, non-binary file content in
 * deterministic order. Support-bundle scanning retains its narrower text-file
 * contract because it validates a generated artifact rather than source input.
 */
export function collectFiles(root = repoRoot) {
  const files = [];
  walkFiles(root, root, files, (entry) =>
    entry.isFile() && textFilePattern.test(entry.name));
  return files.sort();
}

export function scanFileContent(content) {
  const findings = scanForbiddenContent(content);
  if (containsAbsoluteFilesystemPath(content)) {
    findings.push('raw-filesystem-path');
  }
  return findings;
}

function scanForbiddenContent(content) {
  const findings = [];
  for (const { label, pattern } of forbiddenPatterns) {
    pattern.lastIndex = 0;
    if (pattern.test(content)) {
      findings.push(label);
    }
  }
  return findings;
}

function containsAbsoluteFilesystemPath(content) {
  return findAbsoluteFilesystemPathStart(content, 0) !== -1;
}

function findAbsoluteFilesystemPathStart(content, fromIndex) {
  for (let index = fromIndex; index < content.length; index += 1) {
    if (!isAbsoluteFilesystemPathStartBoundary(content[index - 1])) {
      continue;
    }

    const current = content[index];
    const next = content[index + 1];
    const afterNext = content[index + 2];
    const isDrivePath = /^[A-Za-z]$/u.test(current)
      && next === ':'
      && (afterNext === '\\' || afterNext === '/');
    const isUncPath = current === '\\' && next === '\\';
    const isUnixPath = current === '/'
      && next !== undefined
      && next !== '/'
      && next !== '"'
      && !/\s/u.test(next);

    if (isDrivePath || isUncPath || isUnixPath) {
      return index;
    }
  }

  return -1;
}

function isAbsoluteFilesystemPathStartBoundary(value) {
  return value === undefined || !/[\p{L}\p{N}._~+/\\-]/u.test(value);
}

function containsRepositoryAbsoluteFilesystemPath(content) {
  for (const pattern of [
    repositoryUnixFilesystemPathPattern,
    repositoryDriveFilesystemPathPattern,
    repositoryUncFilesystemPathPattern,
    repositorySerializedFilesystemPathPattern,
    repositoryFileUrlFilesystemPathPattern,
    repositoryContextualUnixFilesystemPathPattern,
  ]) {
    pattern.lastIndex = 0;
    if (pattern.test(content)) {
      return true;
    }
  }
  return false;
}

export function scanRepo(root = repoRoot) {
  const findings = [];
  const resolvedRoot = path.resolve(root);
  const files = resolvedRoot === repoRoot
    ? collectGitVisibleFiles(resolvedRoot)
    : collectAllFiles(resolvedRoot);
  for (const relativePath of files) {
    const absolutePath = path.join(resolvedRoot, relativePath);
    let stat;
    try {
      stat = fs.lstatSync(absolutePath);
    } catch (error) {
      if (error?.code === 'ENOENT') {
        continue;
      }
      throw error;
    }
    if (!stat.isFile() && !stat.isSymbolicLink()) {
      continue;
    }
    const bytes = stat.isSymbolicLink()
      ? Buffer.from(fs.readlinkSync(absolutePath))
      : fs.readFileSync(absolutePath);
    if (isBinaryContent(bytes)) {
      continue;
    }
    const content = bytes.toString('utf8');
    const reasons = scanForbiddenContent(content);
    if (containsRepositoryAbsoluteFilesystemPath(content)) {
      reasons.push('raw-filesystem-path');
    }
    for (const reason of reasons) {
      findings.push({ file: relativePath, reason });
    }
  }
  return findings;
}

function collectGitVisibleFiles(root) {
  const output = execFileSync(
    'git',
    ['-C', root, 'ls-files', '--cached', '--others', '--exclude-standard', '-z'],
    {
      encoding: 'utf8',
      maxBuffer: 16 * 1024 * 1024,
      windowsHide: true,
    },
  );
  return output.split('\0').filter(Boolean).sort();
}

function collectAllFiles(root) {
  const files = [];
  walkFiles(root, root, files, (entry) =>
    entry.isFile() || entry.isSymbolicLink());
  return files.sort();
}

function isBinaryContent(content) {
  return content.includes(0);
}

export function scanSupportBundleDirectory(root, options = {}) {
  const files = collectFiles(root);
  const findingsByLabel = {};
  let scannedByteCount = 0;
  let findingCount = 0;

  for (const relativePath of files) {
    const absolutePath = path.join(root, relativePath);
    const stat = fs.statSync(absolutePath);
    if (!stat.isFile()) {
      continue;
    }
    scannedByteCount += stat.size;
    const content = fs.readFileSync(absolutePath, 'utf8');
    for (const label of scanFileContent(content)) {
      findingsByLabel[label] = (findingsByLabel[label] ?? 0) + 1;
      findingCount += 1;
    }
  }

  return {
    redactionVersion: diagnosticRedactionVersion,
    scannedFileCount: files.length,
    scannedByteCount,
    findingCount,
    findingsByLabel,
    truncatedRecordCount: Number.isInteger(options.truncatedRecordCount)
      ? Math.max(0, options.truncatedRecordCount)
      : 0,
    omittedFileCount: Number.isInteger(options.omittedFileCount)
      ? Math.max(0, options.omittedFileCount)
      : 0,
    status: findingCount === 0 ? 'passed' : 'failed',
    timestampMs: Number.isFinite(options.timestampMs) ? Math.max(0, Math.floor(options.timestampMs)) : Date.now(),
  };
}

function walkFiles(root, directory, files, includeFile) {
  for (const entry of fs.readdirSync(directory, { withFileTypes: true })) {
    const absolute = path.join(directory, entry.name);
    if (entry.isDirectory()) {
      if (skippedDirectoryNames.has(entry.name)) continue;
      walkFiles(root, absolute, files, includeFile);
      continue;
    }
    if (includeFile(entry)) {
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
