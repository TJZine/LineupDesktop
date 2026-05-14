import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import {
  APP_PACKAGE_RELATIVE_PATH,
  CHECKSUMS_RELATIVE_PATH,
  MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
  NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
  NOTICES_RELATIVE_PATH,
  PACKAGE_RELATIVE_PATH,
  PROVENANCE_RELATIVE_PATH,
  computeArtifactChecksums,
  createStagedAppPackage,
  formatChecksumRows,
  isNormalizedRelativePackagePath,
  listFiles,
  parseChecksumRows,
} from './package-windows-internal.mjs';
import { scanFileContent } from './verify-redaction.mjs';

const executablePattern = /\.(exe|dll|node|so|dylib)$/iu;
const mpvNamePattern = /(?:^|[./\\-])lib?mpv|(?:^|[./\\-])mpv(?:[./\\-]|$)/iu;
const nativeMediaNamePattern = /(?:^|[./\\-])(?:native[-_]?helper|native[-_]?media|media[-_]?binary)(?:[./\\-]|$)/iu;
const forbiddenSigningEvidencePatterns = [
  {
    label: 'signing-password-field',
    pattern: /(?<![\w-])["']?(?:signingPassword|signing[-_ ]password|certificatePassword|certificate[-_ ]password|certPassword|cert[-_ ]password|pfxPassword|pfx[-_ ]password|p12Password|p12[-_ ]password|privateKeyPassword|private[-_ ]key[-_ ]password)["']?\s*[:=]/iu,
  },
  {
    label: 'certificate-field',
    pattern: /(?<![\w-])["']?(?:certificatePath|certificate[-_ ]path|certificateFile|certificate[-_ ]file|certificatePem|certificate[-_ ]pem|certPem|cert[-_ ]pem|signingCertificate|signing[-_ ]certificate|signingCertificatePem|signing[-_ ]certificate[-_ ]pem|codeSigningCertificate|code[-_ ]signing[-_ ]certificate|codeSigningCertificatePem|code[-_ ]signing[-_ ]certificate[-_ ]pem|codeSigningCert|code[-_ ]signing[-_ ]cert|codeSigningCertPem|code[-_ ]signing[-_ ]cert[-_ ]pem)["']?\s*[:=]/iu,
  },
  {
    label: 'certificate-pem-block',
    pattern: /-----BEGIN CERTIFICATE-----/iu,
  },
  {
    label: 'private-key-field',
    pattern: /(?<![\w-])["']?(?:privateKey|private[-_ ]key)(?:Path|File|[-_ ]path|[-_ ]file)?["']?\s*[:=]|-----BEGIN (?:(?:RSA|EC|DSA|OPENSSH|ENCRYPTED) )?PRIVATE KEY-----/iu,
  },
  {
    label: 'certificate-file-reference',
    pattern: /(?:^|[\\/"'\s:])(?:[^\\/"'\s]*\.(?:pfx|p12)|[^\\/"'\s]*(?:certificate|cert|signing|code[-_ ]?sign)[^\\/"'\s]*\.(?:pem|cer|crt|key))(?:[\\/"'\s,}\]]|$)/iu,
  },
  {
    label: 'certificate-file-reference',
    pattern: /(?<![\w-])["']?(?:pfx|p12)["']?\s*[:=]/iu,
  },
  {
    label: 'code-signing-material',
    pattern: /(?<![\w-])["']?code[-_ ]?signing(?:Certificate|Cert|Key|Password|Path|File|Material)?["']?\s*[:=]/iu,
  },
];
const expectedTopLevelFiles = new Set([
  'LineupDesktop.exe',
  APP_PACKAGE_RELATIVE_PATH,
  NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
  MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
  PROVENANCE_RELATIVE_PATH,
  CHECKSUMS_RELATIVE_PATH,
  NOTICES_RELATIVE_PATH,
]);

export function parseVerifyArgs(args) {
  const parsed = {
    packageRoot: undefined,
    manifestPath: undefined,
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (arg === '--package') {
      const value = args[index + 1];
      if (!value) {
        throw new Error('Usage: node tools/verify-windows-internal-package.mjs --package <package-root> --manifest <manifest-path>');
      }
      parsed.packageRoot = value;
      index += 1;
      continue;
    }
    if (arg === '--manifest') {
      const value = args[index + 1];
      if (!value) {
        throw new Error('Usage: node tools/verify-windows-internal-package.mjs --package <package-root> --manifest <manifest-path>');
      }
      parsed.manifestPath = value;
      index += 1;
      continue;
    }
    throw new Error(`Unknown argument: ${arg}`);
  }

  if (!parsed.packageRoot || !parsed.manifestPath) {
    throw new Error('Usage: node tools/verify-windows-internal-package.mjs --package <package-root> --manifest <manifest-path>');
  }

  return parsed;
}

export function verifyWindowsInternalPackage(options) {
  const root = path.resolve(options.root ?? path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..'));
  const packageRoot = resolveRepoRelativePath(root, options.packageRoot);
  const manifestPath = resolveRepoRelativePath(root, options.manifestPath);
  const expectedPackageRoot = path.join(root, PACKAGE_RELATIVE_PATH);
  const errors = [];

  if (!fs.statSync(packageRoot, { throwIfNoEntry: false })?.isDirectory()) {
    return [`Package root is missing: ${packageRoot}`];
  }
  if (packageRoot !== expectedPackageRoot) {
    errors.push(`Package root must be exactly ${PACKAGE_RELATIVE_PATH} relative to the repo root.`);
  }

  const expectedManifestPath = path.join(packageRoot, PROVENANCE_RELATIVE_PATH);
  if (manifestPath !== expectedManifestPath) {
    errors.push(`Manifest path must be ${PROVENANCE_RELATIVE_PATH} inside the package root.`);
  }

  const fileListErrorCount = errors.length;
  const files = safeListFiles(packageRoot, errors);
  if (errors.length > fileListErrorCount) {
    return errors;
  }
  const fileSet = new Set(files);
  for (const requiredFile of expectedTopLevelFiles) {
    if (!fileSet.has(requiredFile)) {
      errors.push(`Missing required package file: ${requiredFile}`);
    }
  }

  if (!files.some((relativePath) => relativePath.startsWith('resources/app/dist/'))) {
    errors.push('Missing resources/app/dist payload.');
  }
  if (files.some((relativePath) => relativePath.endsWith('.asar'))) {
    errors.push('Package must not contain .asar files.');
  }
  if (files.some((relativePath) => relativePath.startsWith('app/'))) {
    errors.push('Package must not contain an alternate top-level app layout.');
  }
  verifyNoForbiddenNativeMediaFiles(files, errors);

  verifyStagedAppPackage(root, packageRoot, errors);
  verifyBlockedDirectories(files, errors);
  const provenance = verifyJsonEvidence(packageRoot, errors);
  const artifactChecksumRows = safeComputeArtifactChecksums(packageRoot, errors, { exclude: new Set() });
  if (!artifactChecksumRows) {
    return errors;
  }
  verifyChecksumManifest(
    packageRoot,
    errors,
    artifactChecksumRows.filter((row) => row.path !== CHECKSUMS_RELATIVE_PATH),
  );
  verifyProvenanceArtifactChecksums(
    packageRoot,
    provenance,
    errors,
    artifactChecksumRows.filter((row) => (
      row.path !== PROVENANCE_RELATIVE_PATH && row.path !== CHECKSUMS_RELATIVE_PATH
    )),
  );
  verifyRedactionSafeEvidence(packageRoot, errors);
  verifyNoSigningMaterialEvidence(packageRoot, errors);

  return errors;
}

export function verifyStagedAppPackage(root, packageRoot, errors) {
  const appPackagePath = path.join(packageRoot, APP_PACKAGE_RELATIVE_PATH);
  const appPackage = readJson(appPackagePath, errors, 'app package manifest');
  const rootPackage = readJson(path.join(root, 'package.json'), errors, 'root package metadata');
  if (!appPackage || !rootPackage) {
    return;
  }

  const expected = createStagedAppPackage({
    app: {
      name: rootPackage.name,
      version: rootPackage.version,
      license: rootPackage.license,
      type: rootPackage.type,
    },
  });
  const expectedKeys = Object.keys(expected).sort();
  const actualKeys = Object.keys(appPackage).sort();
  if (JSON.stringify(actualKeys) !== JSON.stringify(expectedKeys)) {
    errors.push('resources/app/package.json must contain only name, version, license, type, and main.');
  }
  if (appPackage.main !== 'dist/main/index.js') {
    errors.push('resources/app/package.json main must be dist/main/index.js.');
  }
  for (const key of ['name', 'version', 'license', 'type']) {
    if (typeof appPackage[key] !== 'string' || appPackage[key].length === 0) {
      errors.push(`resources/app/package.json ${key} must be a non-empty string.`);
    }
    if (typeof rootPackage[key] === 'string' && appPackage[key] !== rootPackage[key]) {
      errors.push(`resources/app/package.json ${key} must match root package.json.`);
    }
  }
}

export function verifyBlockedDirectories(files, errors) {
  const nativeFiles = files.filter((relativePath) => relativePath.startsWith('resources/native-helper/'));
  const mediaFiles = files.filter((relativePath) => relativePath.startsWith('resources/media-binaries/'));

  if (nativeFiles.length !== 1 || nativeFiles[0] !== NATIVE_HELPER_BLOCKED_RELATIVE_PATH) {
    errors.push('resources/native-helper must contain only PRODUCTION_HELPER_BLOCKED.txt.');
  }
  if (mediaFiles.length !== 1 || mediaFiles[0] !== MEDIA_BINARIES_BLOCKED_RELATIVE_PATH) {
    errors.push('resources/media-binaries must contain only REDISTRIBUTION_BLOCKED.txt.');
  }

}

export function verifyNoForbiddenNativeMediaFiles(files, errors) {
  for (const relativePath of files) {
    if (
      executablePattern.test(relativePath) &&
      (mpvNamePattern.test(relativePath) || nativeMediaNamePattern.test(relativePath))
    ) {
      errors.push(`Package contains forbidden native/media binary-looking file: ${relativePath}`);
    }
  }
}

export function verifyJsonEvidence(packageRoot, errors) {
  const provenance = readJson(path.join(packageRoot, PROVENANCE_RELATIVE_PATH), errors, 'provenance manifest');
  const notices = readJson(path.join(packageRoot, NOTICES_RELATIVE_PATH), errors, 'internal notices');

  if (provenance) {
    if (provenance.manifestFormat !== 'rd-18-windows-internal-provenance-v1') {
      errors.push('Provenance manifest has an unexpected manifestFormat.');
    }
    if (provenance.packageLayout?.unpackedApp !== true || provenance.packageLayout?.asar !== false) {
      errors.push('Provenance manifest must record unpacked app layout and asar false.');
    }
    if (provenance.packageLayout?.entrypoint !== 'LineupDesktop.exe') {
      errors.push('Provenance manifest must record LineupDesktop.exe as entrypoint.');
    }
    for (const key of ['electron', 'node', 'chrome', 'v8', 'modules', 'napi']) {
      if (typeof provenance.runtime?.[key] !== 'string' || provenance.runtime[key].length === 0) {
        errors.push(`Provenance runtime.${key} must be recorded.`);
      }
    }
    if (!Number.isInteger(provenance.lockfile?.packageCount) || provenance.lockfile.packageCount <= 0) {
      errors.push('Provenance lockfile.packageCount must be a positive integer.');
    }
    assertChecksumArray(provenance.buildInputChecksums, 'buildInputChecksums', errors);
    assertChecksumArray(provenance.artifactFileChecksums, 'artifactFileChecksums', errors);
    if (provenance.nativeHelperStatus?.status !== 'blocked') {
      errors.push('Provenance nativeHelperStatus must be blocked.');
    }
    if (
      provenance.mediaBinariesStatus?.status !== 'blocked' ||
      provenance.mediaBinariesStatus?.rd06LocalPrerequisitesCopied !== false
    ) {
      errors.push('Provenance mediaBinariesStatus must block media redistribution and record no RD-06 copies.');
    }
    if (provenance.supportBundleRedactionProof?.status !== 'recorded') {
      errors.push('Provenance supportBundleRedactionProof status must be recorded.');
    }
    if (provenance.windowsProof?.status !== 'required-before-closeout') {
      errors.push('Provenance windowsProof status must be required-before-closeout.');
    }
  }

  if (notices) {
    if (notices.noticeFormat !== 'rd-18-internal-notices-v1') {
      errors.push('Internal notices have an unexpected noticeFormat.');
    }
    if (notices.auditStatus?.publicRelease !== 'blocked') {
      errors.push('Internal notices must keep publicRelease blocked.');
    }
    if (notices.nativeHelper?.status !== 'blocked' || notices.mediaBinaries?.status !== 'blocked') {
      errors.push('Internal notices must record blocked native helper and media binaries.');
    }
  }

  return provenance;
}

export function verifyChecksumManifest(packageRoot, errors, expectedRows = undefined) {
  const checksumPath = path.join(packageRoot, CHECKSUMS_RELATIVE_PATH);
  let actualRows;
  try {
    actualRows = parseChecksumRows(fs.readFileSync(checksumPath, 'utf8'));
  } catch (error) {
    errors.push(error instanceof Error ? error.message : 'Unable to parse checksums.sha256.');
    return;
  }

  const expectedChecksumRows = expectedRows ?? safeComputeArtifactChecksums(packageRoot, errors, {
    exclude: new Set([CHECKSUMS_RELATIVE_PATH]),
  });
  if (!expectedChecksumRows) {
    return;
  }
  if (formatChecksumRows(actualRows) !== formatChecksumRows(expectedChecksumRows)) {
    errors.push('checksums.sha256 must match staged package files in deterministic path order.');
  }
  for (const row of actualRows) {
    if (!isNormalizedRelativePackagePath(row.path)) {
      errors.push(`Checksum path must be normalized and relative: ${row.path}`);
    }
  }
}

export function verifyProvenanceArtifactChecksums(packageRoot, provenance, errors, expectedRows = undefined) {
  if (!provenance) {
    return;
  }

  const expectedProvenanceRows = expectedRows ?? safeComputeArtifactChecksums(packageRoot, errors, {
    exclude: new Set([PROVENANCE_RELATIVE_PATH, CHECKSUMS_RELATIVE_PATH]),
  });
  if (!expectedProvenanceRows) {
    return;
  }
  if (
    Array.isArray(provenance.artifactFileChecksums) &&
    formatChecksumRows(provenance.artifactFileChecksums) !== formatChecksumRows(expectedProvenanceRows)
  ) {
    errors.push(
      'Provenance artifactFileChecksums must match staged package files before provenance and checksums are written.',
    );
  }
}

export function verifyRedactionSafeEvidence(packageRoot, errors) {
  const evidenceFiles = [
    APP_PACKAGE_RELATIVE_PATH,
    NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
    MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
    PROVENANCE_RELATIVE_PATH,
    CHECKSUMS_RELATIVE_PATH,
    NOTICES_RELATIVE_PATH,
  ];

  for (const relativePath of evidenceFiles) {
    const filePath = path.join(packageRoot, relativePath);
    if (!fs.statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
      continue;
    }
    const findings = scanFileContent(fs.readFileSync(filePath, 'utf8'));
    if (findings.length > 0) {
      errors.push(`Generated package evidence must be redaction-safe: ${relativePath} ${findings.join(',')}`);
    }
  }
}

export function verifyNoSigningMaterialEvidence(packageRoot, errors) {
  const evidenceFiles = [
    APP_PACKAGE_RELATIVE_PATH,
    NATIVE_HELPER_BLOCKED_RELATIVE_PATH,
    MEDIA_BINARIES_BLOCKED_RELATIVE_PATH,
    PROVENANCE_RELATIVE_PATH,
    CHECKSUMS_RELATIVE_PATH,
    NOTICES_RELATIVE_PATH,
  ];

  for (const relativePath of evidenceFiles) {
    const filePath = path.join(packageRoot, relativePath);
    if (!fs.statSync(filePath, { throwIfNoEntry: false })?.isFile()) {
      continue;
    }
    const content = fs.readFileSync(filePath, 'utf8');
    const findings = [];
    for (const { label, pattern } of forbiddenSigningEvidencePatterns) {
      pattern.lastIndex = 0;
      if (pattern.test(content)) {
        findings.push(label);
      }
    }
    if (findings.length > 0) {
      errors.push(`Generated package evidence must not contain signing material: ${relativePath} ${findings.join(',')}`);
    }
  }
}

function safeListFiles(packageRoot, errors) {
  try {
    return listFiles(packageRoot);
  } catch (error) {
    errors.push(error instanceof Error ? error.message : 'Unable to inspect package files.');
    return [];
  }
}

function safeComputeArtifactChecksums(packageRoot, errors, options) {
  try {
    return computeArtifactChecksums(packageRoot, options);
  } catch (error) {
    errors.push(error instanceof Error ? error.message : 'Unable to inspect package files.');
    return undefined;
  }
}

function resolveRepoRelativePath(root, value) {
  if (path.isAbsolute(value)) {
    return path.resolve(value);
  }
  return path.resolve(root, value);
}

function assertChecksumArray(value, label, errors) {
  if (!Array.isArray(value) || value.length === 0) {
    errors.push(`Provenance ${label} must be a non-empty checksum array.`);
    return;
  }
  for (const row of value) {
    if (!isNormalizedRelativePackagePath(row?.path)) {
      errors.push(`Provenance ${label} paths must be normalized and relative.`);
    }
    if (typeof row?.sha256 !== 'string' || !/^[a-f0-9]{64}$/u.test(row.sha256)) {
      errors.push(`Provenance ${label} entries must include sha256.`);
    }
  }
}

function readJson(filePath, errors, label) {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8'));
  } catch {
    errors.push(`Unable to read ${label}.`);
    return undefined;
  }
}

if (process.argv[1] === fileURLToPath(import.meta.url)) {
  try {
    const { packageRoot, manifestPath } = parseVerifyArgs(process.argv.slice(2));
    const errors = verifyWindowsInternalPackage({ packageRoot, manifestPath });
    if (errors.length > 0) {
      for (const error of errors) {
        console.error(error);
      }
      process.exit(1);
    }
    console.log('RD-18 internal Windows package verification passed.');
  } catch (error) {
    console.error(error instanceof Error ? error.message : 'RD-18 internal package verification failed.');
    process.exit(1);
  }
}
