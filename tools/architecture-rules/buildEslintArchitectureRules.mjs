import { builtinModules } from 'node:module';

const BOUNDARY_MESSAGES = Object.freeze({
  domainBoundary:
    'Domain code must stay deterministic and runtime-agnostic. Do not import Node, Electron, main, preload, renderer, native-helper, or browser/runtime globals.',
  rendererBoundary:
    'Renderer code must stay unprivileged. Use the typed preload API instead of Node, Electron, main, or native-helper imports.',
  preloadBoundary:
    'Preload code owns only the narrow bridge. Do not import renderer or native-helper implementation.',
  mainBoundary:
    'Electron main must not import renderer implementation.',
  nativeHelperBoundary:
    'Native helper code must not import renderer or preload implementation.',
  testOwner:
    'Tests must stay inside their declared architecture owner. Move cross-owner assertions to an approved integration seam.',
  integrationSeam:
    'Integration tests must use an approved named architecture seam and may import only that seam vocabulary.',
});

export const architectureRuleMessages = BOUNDARY_MESSAGES;

const nodeBuiltinImportPatterns = Array.from(new Set(
  [
    'node:*',
    ...builtinModules.flatMap((moduleName) => [
      moduleName,
      `node:${moduleName}`,
    ]),
  ],
)).sort();

/**
 * Transforms data-owned architecture rules into ESLint flat-config
 * restrictions, including owner fallbacks, denied imports/globals, dynamic
 * import checks, and named integration seam allowlists.
 */
export function buildEslintArchitectureRules(rules) {
  return [
    buildBoundaryRule(rules.domainBoundary, BOUNDARY_MESSAGES.domainBoundary),
    buildBoundaryRule(rules.rendererBoundary, BOUNDARY_MESSAGES.rendererBoundary),
    buildBoundaryRule(rules.preloadBoundary, BOUNDARY_MESSAGES.preloadBoundary),
    buildBoundaryRule(rules.mainBoundary, BOUNDARY_MESSAGES.mainBoundary),
    buildBoundaryRule(rules.nativeHelperBoundary, BOUNDARY_MESSAGES.nativeHelperBoundary),
    ...(rules.testOwners ?? []).map((owner) => buildTestOwnerRule(owner)),
    buildIntegrationTestRule(rules.integrationTests, rules.integrationSeams ?? []),
    ...(rules.integrationSeams ?? []).map((seam) => buildIntegrationSeamRule(seam)),
  ].filter(Boolean);
}

function buildBoundaryRule(boundary, message) {
  if (!boundary || boundary.files.length === 0) {
    return null;
  }
  const forbiddenImportPatterns = [
    ...boundary.forbiddenImportPatterns,
    ...(boundary.forbidNodeBuiltins ? nodeBuiltinImportPatterns : []),
  ];
  const rules = {};

  if (forbiddenImportPatterns.length > 0) {
    rules['no-restricted-imports'] = [
      'error',
      {
        patterns: [
          {
            group: forbiddenImportPatterns,
            message,
          },
        ],
      },
    ];
  }

  if (boundary.forbiddenGlobals?.length > 0) {
    rules['no-restricted-globals'] = [
      'error',
      ...boundary.forbiddenGlobals.map((name) => ({
        name,
        message,
      })),
    ];
  }

  const restrictedSyntax = [];
  if (boundary.forbidNonLiteralDynamicImports) {
    restrictedSyntax.push({
      selector: 'ImportExpression:not([source.type="Literal"])',
      message,
    });
  }
  if (boundary.forbidGlobalThisProperties) {
    restrictedSyntax.push({
      selector: 'MemberExpression[object.name="globalThis"]',
      message,
    });
  }

  const dynamicImportRegexes = buildDynamicImportRegexes(boundary);
  restrictedSyntax.push(
    ...dynamicImportRegexes.map((regex) => ({
        selector: `ImportExpression[source.value=/${regex}/]`,
        message,
      })),
  );

  if (restrictedSyntax.length > 0) {
    rules['no-restricted-syntax'] = ['error', ...restrictedSyntax];
  }

  return {
    files: boundary.files,
    rules,
  };
}

function buildTestOwnerRule(owner) {
  if (!owner || owner.files.length === 0) {
    return null;
  }

  const forbiddenImportPatterns = [
    ...(owner.forbiddenImportPatterns ?? []),
    ...('allowedNodeBuiltins' in owner ? nodeBuiltinImportPatternsExcept(owner.allowedNodeBuiltins) : []),
  ];
  const forbiddenExactImports =
    'allowedNodeBuiltins' in owner && !forbiddenImportPatterns.includes('**/domain') ? ['domain'] : [];
  const forbiddenDynamicImportPatterns = [
    ...forbiddenImportPatterns,
    ...(forbiddenImportPatterns.includes('**/domain') ? [] : forbiddenExactImports),
  ];

  return buildRestrictedImportEntry({
    files: owner.files,
    forbiddenImportPatterns,
    forbiddenExactImports,
    forbiddenDynamicImportPatterns,
    message: owner.message ?? BOUNDARY_MESSAGES.testOwner,
    restrictDynamicImports: true,
  });
}

function buildIntegrationSeamRule(seam) {
  if (!seam || seam.files.length === 0) {
    return null;
  }

  const allowedImportRegex = buildAllowedIntegrationImportRegex(seam);
  const rules = {
    'no-restricted-syntax': [
      'error',
      {
        selector: `ImportDeclaration:not([source.value=/${allowedImportRegex}/])`,
        message: seam.message ?? BOUNDARY_MESSAGES.integrationSeam,
      },
      {
        selector: 'ImportExpression',
        message: seam.message ?? BOUNDARY_MESSAGES.integrationSeam,
      },
    ],
  };

  return {
    files: seam.files,
    rules,
  };
}

function buildIntegrationTestRule(integrationTests, seams) {
  if (!integrationTests || integrationTests.files.length === 0) {
    return null;
  }

  const allowedImportRegex = buildAllowedImportRegex(integrationTests.allowedNodeBuiltins ?? []);
  return {
    files: integrationTests.files,
    ignores: seams.flatMap((seam) => seam.files ?? []),
    rules: {
      'no-restricted-syntax': [
        'error',
        {
          selector: `ImportDeclaration:not([source.value=/${allowedImportRegex}/])`,
          message: integrationTests.message ?? BOUNDARY_MESSAGES.integrationSeam,
        },
        {
          selector: 'ImportExpression',
          message: integrationTests.message ?? BOUNDARY_MESSAGES.integrationSeam,
        },
      ],
    },
  };
}

function buildRestrictedImportEntry({
  files,
  forbiddenImportPatterns,
  forbiddenExactImports = [],
  forbiddenDynamicImportPatterns = forbiddenImportPatterns,
  message,
  restrictDynamicImports = false,
}) {
  const rules = {};

  if (forbiddenImportPatterns.length > 0 || forbiddenExactImports.length > 0) {
    const restriction = {};
    if (forbiddenImportPatterns.length > 0) {
      restriction.patterns = [
        {
          group: Array.from(new Set(forbiddenImportPatterns)).sort(),
          message,
        },
      ];
    }
    if (forbiddenExactImports.length > 0) {
      restriction.paths = Array.from(new Set(forbiddenExactImports)).sort().map((name) => ({
        name,
        message,
      }));
    }
    rules['no-restricted-imports'] = [
      'error',
      restriction,
    ];
  }

  if (restrictDynamicImports) {
    const restrictedSyntax = [
      {
        selector: 'ImportExpression:not([source.type="Literal"])',
        message,
      },
      ...buildDynamicImportRegexes({ forbiddenImportPatterns: forbiddenDynamicImportPatterns }).map((regex) => ({
        selector: `ImportExpression[source.value=/${regex}/]`,
        message,
      })),
    ];

    if (restrictedSyntax.length > 0) {
      rules['no-restricted-syntax'] = [
        'error',
        ...restrictedSyntax,
      ];
    }
  }

  return {
    files,
    rules,
  };
}

function nodeBuiltinImportPatternsExcept(allowed = []) {
  const allowedSet = new Set(allowed);
  return nodeBuiltinImportPatterns.filter((pattern) =>
    pattern !== 'node:*' && pattern !== 'domain' && !allowedSet.has(pattern),
  );
}

function buildDynamicImportRegexes(boundary) {
  const regexes = [];

  if (boundary.forbidNodeBuiltins) {
    const builtins = nodeBuiltinImportPatterns
      .filter((pattern) => pattern !== 'node:*' && !pattern.startsWith('node:'))
      .map(escapeSelectorRegexLiteral);
    regexes.push(`^(?:node:.*|${builtins.join('|')})$`);
  }

  for (const pattern of boundary.forbiddenImportPatterns) {
    if (pattern === 'node:*') {
      regexes.push('^node:');
      continue;
    }
    if (pattern.startsWith('**/') && pattern.endsWith('/**')) {
      const segment = pattern.slice(3, -3);
      regexes.push(`(?:^|\\/)${escapeSelectorRegexLiteral(segment)}(?:\\/|$)`);
      continue;
    }
    if (pattern.startsWith('**/')) {
      const segment = pattern.slice(3);
      regexes.push(`(?:^|\\/)${escapeSelectorRegexLiteral(segment)}$`);
      continue;
    }
    if (pattern.endsWith('/**')) {
      const prefix = pattern.slice(0, -3);
      regexes.push(`^${escapeSelectorRegexLiteral(prefix)}(?:\\/|$)`);
      continue;
    }
    if (!pattern.includes('*')) {
      regexes.push(`^${escapeSelectorRegexLiteral(pattern)}$`);
    }
  }

  return Array.from(new Set(regexes));
}

function escapeSelectorRegexLiteral(text) {
  return text
    .replace(/[\\^$+?.()|[\]{}]/gu, '\\$&')
    .replace(/\//gu, '\\/');
}

function buildAllowedIntegrationImportRegex(seam) {
  const allowed = [
    ...(seam.allowedNodeBuiltins ?? []),
    ...(seam.allowedImportPatterns ?? []),
  ];
  return buildAllowedImportRegex(allowed);
}

function buildAllowedImportRegex(allowed) {
  const patterns = allowed.map((pattern) => {
    if (pattern.endsWith('/**')) {
      return `${escapeSelectorRegexLiteral(pattern.slice(0, -3))}(?:\\/.*)?`;
    }
    return escapeSelectorRegexLiteral(pattern);
  });

  return `^(?:${patterns.join('|')})$`;
}
