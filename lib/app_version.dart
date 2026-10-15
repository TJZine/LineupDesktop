const lineupVersion = String.fromEnvironment(
  'LINEUP_VERSION',
  defaultValue: '0.1.0',
);
const lineupVersionDefined = bool.hasEnvironment('LINEUP_VERSION');
