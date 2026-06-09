import '../../renderer/domBindings.js';

declare module '../../renderer/domBindings.js' {
  interface RendererDomBindings {
    /**
     * @deprecated Test-only compatibility for older helper object literals while
     * RD-23 completes the hard rename to channelSetupStatusElement. Production
     * code must not read this field or the fixture-named DOM selector.
     */
    channelSetupFixtureStatusElement?: HTMLElement | null;
  }
}
