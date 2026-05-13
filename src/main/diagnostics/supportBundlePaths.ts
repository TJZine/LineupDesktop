import crypto from 'node:crypto';
import path from 'node:path';

export const SUPPORT_BUNDLE_DIRECTORY_PREFIX = 'lineup-desktop-support-';

export interface SupportBundleTarget {
  bundleId: string;
  bundleDirectoryName: string;
  bundleDirectoryPath: string;
}

export function createSupportBundleId(nowMs = Date.now(), randomSuffix = createRandomSuffix()): string {
  const timestamp = Number.isFinite(nowMs) && nowMs >= 0
    ? Math.floor(nowMs).toString(36)
    : '0';
  return sanitizeSupportBundleId(`${timestamp}-${randomSuffix}`);
}

export function createSupportBundleTarget(parentDirectory: string, bundleId: string): SupportBundleTarget {
  if (parentDirectory.trim().length === 0) {
    throw new Error('Support bundle parent directory is unavailable.');
  }

  const normalizedParent = path.resolve(parentDirectory);
  const safeBundleId = sanitizeSupportBundleId(bundleId);
  const bundleDirectoryName = `${SUPPORT_BUNDLE_DIRECTORY_PREFIX}${safeBundleId}`;
  const bundleDirectoryPath = path.join(normalizedParent, bundleDirectoryName);

  if (path.dirname(bundleDirectoryPath) !== normalizedParent) {
    throw new Error('Support bundle target escaped the selected parent directory.');
  }

  return {
    bundleId: safeBundleId,
    bundleDirectoryName,
    bundleDirectoryPath,
  };
}

export function sanitizeSupportBundleId(value: string): string {
  const safe = value
    .trim()
    .replace(/[^A-Za-z0-9-]/gu, '-')
    .replace(/-+/gu, '-')
    .replace(/^-|-$/gu, '')
    .slice(0, 80);
  return safe.length > 0 ? safe : 'bundle';
}

function createRandomSuffix(): string {
  return crypto.randomBytes(6).toString('hex');
}
