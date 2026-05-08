export const desktopArchitectureRules = {
  version: '2026-05-07-desktop-foundation',
  rendererBoundary: {
    files: ['src/renderer/**/*.ts', 'src/renderer/**/*.tsx'],
    forbidNodeBuiltins: true,
    forbiddenGlobals: ['Buffer', 'process', 'require', '__dirname', '__filename', 'global'],
    forbiddenImportPatterns: [
      'electron',
      'src/main/**',
      'src/preload/**',
      'src/native-helper/**',
      '**/main/**',
      '**/preload/**',
      '**/native-helper/**',
      '../main/**',
      '../preload/**',
      '../native-helper/**',
    ],
  },
  preloadBoundary: {
    files: ['src/preload/**/*.ts', 'src/preload/**/*.cts'],
    forbiddenImportPatterns: [
      'src/renderer/**',
      'src/native-helper/**',
      '**/renderer/**',
      '**/native-helper/**',
      '../renderer/**',
      '../native-helper/**',
    ],
  },
  mainBoundary: {
    files: ['src/main/**/*.ts'],
    forbiddenImportPatterns: [
      'src/renderer/**',
      '**/renderer/**',
      '../renderer/**',
    ],
  },
  nativeHelperBoundary: {
    files: ['src/native-helper/**/*.ts'],
    forbiddenImportPatterns: [
      'src/renderer/**',
      'src/preload/**',
      '**/renderer/**',
      '**/preload/**',
      '../renderer/**',
      '../preload/**',
    ],
  },
};
