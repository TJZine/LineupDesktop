export interface SetupSmokeProjection {
  obsoleteSelectorsPresent: boolean;
  auth: {
    hostVisible: boolean;
    owner: string | null;
    ownerVisible: boolean;
    requestPinControlPresent: boolean;
  };
  library: {
    workspaceVisible: boolean;
    documentOwner: string | null;
    ownerVisible: boolean;
    ownerActive: boolean;
    status: 'idle' | 'loading' | 'ready' | 'empty' | 'error' | 'recovery';
    sectionsPresent: boolean;
    selectAllPresent: boolean;
    clearAllPresent: boolean;
    nextPresent: boolean;
    backPresent: boolean;
  };
}

export function evaluateSetupSmokeProjection(projection: SetupSmokeProjection): {
  accepted: boolean;
  failures: string[];
} {
  const failures: string[] = [];
  if (projection.obsoleteSelectorsPresent) failures.push('obsolete selectors');
  const authReady = projection.auth.hostVisible
    && projection.auth.owner === 'auth-link-code'
    && projection.auth.ownerVisible
    && projection.auth.requestPinControlPresent;
  const libraryReady = projection.library.workspaceVisible
    && projection.library.documentOwner === 'library'
    && projection.library.ownerVisible
    && projection.library.ownerActive
    && (projection.library.status === 'loading'
      || projection.library.status === 'ready'
      || projection.library.status === 'empty')
    && projection.library.sectionsPresent
    && projection.library.selectAllPresent
    && projection.library.clearAllPresent
    && projection.library.nextPresent
    && projection.library.backPresent;
  if (!authReady && !libraryReady) failures.push('no valid setup owner');
  return { accepted: failures.length === 0, failures };
}
