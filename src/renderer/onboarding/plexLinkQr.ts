const SVG_NAMESPACE = 'http://www.w3.org/2000/svg';

// Static plex.tv/link payload adapted from upstream. It intentionally contains
// no account code, token, query parameter, or runtime value.
const PLEX_LINK_QR_PATH = 'M1 1.5h7m3 0h4m2 0h1m1 0h7M1 2.5h1m5 0h1m2 0h1m1 0h1m3 0h1m2 0h1m5 0h1M1 3.5h1m1 0h3m1 0h1m1 0h1m1 0h2m2 0h3m1 0h1m1 0h3m1 0h1M1 4.5h1m1 0h3m1 0h1m1 0h2m3 0h2m3 0h1m1 0h3m1 0h1M1 5.5h1m1 0h3m1 0h1m1 0h1m1 0h1m2 0h1m2 0h1m1 0h1m1 0h3m1 0h1M1 6.5h1m5 0h1m1 0h2m3 0h4m1 0h1m5 0h1M1 7.5h7m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m1 0h7M9 8.5h1m7 0h1M1 9.5h1m1 0h5m2 0h1m2 0h3m3 0h5M4 10.5h1m1 0h1m4 0h4m5 0h1m3 0h1M1 11.5h4m1 0h3m1 0h1m1 0h1m1 0h1m1 0h1m1 0h1m3 0h1m1 0h2M1 12.5h1m2 0h1m1 0h1m6 0h1m1 0h1m1 0h1m1 0h1m5 0h1M2 13.5h2m3 0h1m1 0h1m1 0h2m3 0h6m1 0h3M1 14.5h1m2 0h1m1 0h1m6 0h2m2 0h1m2 0h1m1 0h1m1 0h1M1 15.5h1m5 0h1m1 0h1m1 0h1m2 0h3m1 0h5m1 0h2M1 16.5h1m2 0h1m3 0h3m2 0h2m1 0h6m3 0h1M1 17.5h1m1 0h3m1 0h1m2 0h2m1 0h1m1 0h7m1 0h1M9 18.5h1m1 0h1m5 0h1m3 0h2M1 19.5h7m3 0h3m3 0h1m1 0h1m1 0h1m1 0h3M1 20.5h1m5 0h1m1 0h4m2 0h1m1 0h1m3 0h2m2 0h1M1 21.5h1m1 0h3m1 0h1m1 0h4m3 0h6m1 0h3M1 22.5h1m1 0h3m1 0h1m1 0h2m2 0h7m1 0h5M1 23.5h1m1 0h3m1 0h1m1 0h2m3 0h2m1 0h2m3 0h2m1 0h1M1 24.5h1m5 0h1m2 0h1m2 0h2m1 0h2m2 0h3m2 0h1M1 25.5h7m1 0h1m1 0h1m1 0h1m1 0h2m2 0h7';

export function createPlexLinkQr(documentRef: Document = document): SVGSVGElement {
  const svg = documentRef.createElementNS(SVG_NAMESPACE, 'svg');
  svg.setAttribute('viewBox', '0 0 27 27');
  svg.setAttribute('width', '160');
  svg.setAttribute('height', '160');
  svg.setAttribute('shape-rendering', 'crispEdges');
  svg.setAttribute('aria-label', 'QR code for plex.tv/link');
  svg.setAttribute('role', 'img');

  const background = documentRef.createElementNS(SVG_NAMESPACE, 'path');
  background.setAttribute('fill', '#ffffff');
  background.setAttribute('d', 'M0 0h27v27H0z');
  const pattern = documentRef.createElementNS(SVG_NAMESPACE, 'path');
  pattern.setAttribute('stroke', '#000000');
  pattern.setAttribute('d', PLEX_LINK_QR_PATH);
  svg.append(background, pattern);
  return svg;
}
