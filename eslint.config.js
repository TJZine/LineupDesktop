import js from '@eslint/js';
import tsPlugin from '@typescript-eslint/eslint-plugin';
import tsParser from '@typescript-eslint/parser';

import { buildEslintArchitectureRules } from './tools/architecture-rules/buildEslintArchitectureRules.mjs';
import { desktopArchitectureRules } from './tools/architecture-rules/desktopArchitectureRules.mjs';

export default [
  {
    ignores: [
      'node_modules/**',
      'dist/**',
      'out/**',
      'coverage/**',
      '.codanna/**',
      '.codex/cache/**',
      '.agent/**',
      '.fastembed_cache/**',
      '.mcp_sequential_thinking/**',
      'docs/runs/**',
    ],
  },
  js.configs.recommended,
  {
    files: ['src/**/*.ts', 'src/**/*.cts'],
    languageOptions: {
      parser: tsParser,
      parserOptions: {
        project: './tsconfig.json',
        tsconfigRootDir: import.meta.dirname,
        sourceType: 'module',
      },
    },
    plugins: {
      '@typescript-eslint': tsPlugin,
    },
    rules: {
      '@typescript-eslint/consistent-type-imports': ['error', { prefer: 'type-imports' }],
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-unused-vars': ['error', { argsIgnorePattern: '^_' }],
      'no-unused-vars': 'off',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
    },
  },
  {
    files: ['src/main/**/*.ts', 'src/preload/**/*.ts', 'src/preload/**/*.cts'],
    languageOptions: {
      globals: {
        console: 'readonly',
        process: 'readonly',
        require: 'readonly',
        Response: 'readonly',
        setTimeout: 'readonly',
        URL: 'readonly',
      },
    },
  },
  {
    files: ['src/renderer/**/*.ts'],
    languageOptions: {
      globals: {
        document: 'readonly',
        window: 'readonly',
      },
    },
  },
  {
    files: ['*.js', 'tools/**/*.mjs'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: {
        console: 'readonly',
        process: 'readonly',
        URL: 'readonly',
      },
    },
  },
  ...buildEslintArchitectureRules(desktopArchitectureRules),
];
