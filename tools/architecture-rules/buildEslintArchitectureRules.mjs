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

export function buildEslintArchitectureRules(rules) {
  return [
    buildBoundaryRule(rules.domainBoundary, BOUNDARY_MESSAGES.domainBoundary),
    buildBoundaryRule(rules.rendererBoundary, BOUNDARY_MESSAGES.rendererBoundary),
    buildBoundaryRule(rules.preloadBoundary, BOUNDARY_MESSAGES.preloadBoundary),
    buildBoundaryRule(rules.mainBoundary, BOUNDARY_MESSAGES.mainBoundary),
    buildBoundaryRule(rules.nativeHelperBoundary, BOUNDARY_MESSAGES.nativeHelperBoundary),
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
    ignores: ['src/**/__tests__/**'],
    rules,
  };
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
