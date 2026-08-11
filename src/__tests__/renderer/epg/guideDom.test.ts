/* eslint-disable @typescript-eslint/no-explicit-any */
import test from 'node:test';
import assert from 'node:assert/strict';

class MockElement {
  tagName: string;
  className: string = '';
  id: string = '';
  dataset: Record<string, string> = {};
  style: any;
  children: MockElement[] = [];
  attributes = new Map<string, string>();
  textContent: string = '';

  constructor(tagName: string) {
    this.tagName = tagName.toUpperCase();
    const self = this;
    this.style = {
      position: '',
      left: '',
      width: '',
      setProperty(name: string, value: string) {
        self.style[name] = value;
      },
      getPropertyValue(name: string) {
        return self.style[name] || '';
      }
    };
  }

  setAttribute(name: string, value: string) {
    this.attributes.set(name, value);
  }

  getAttribute(name: string) {
    return this.attributes.get(name) || null;
  }

  append(...nodes: (any | string)[]) {
    for (const node of nodes) {
      if (typeof node === 'string') {
        const textNode = new MockElement('#text');
        textNode.textContent = node;
        this.children.push(textNode);
      } else {
        this.children.push(node);
      }
    }
  }

  querySelector(selector: string): MockElement | null {
    const search = (el: MockElement): MockElement | null => {
      if (selector.startsWith('.')) {
        const className = selector.slice(1);
        if (el.className.split(' ').includes(className)) {
          return el;
        }
      }
      for (const child of el.children) {
        const found = search(child);
        if (found) return found;
      }
      return null;
    };
    return search(this);
  }

  get classList() {
    const self = this;
    return {
      add(name: string) {
        const parts = self.className ? self.className.split(' ') : [];
        if (!parts.includes(name)) {
          parts.push(name);
          self.className = parts.join(' ');
        }
      },
      contains(name: string) {
        return self.className.split(' ').includes(name);
      }
    };
  }
}

const mockDocument = {
  createElement(tagName: string) {
    return new MockElement(tagName);
  }
};

const originalDocument = globalThis.document;
(globalThis as any).document = mockDocument as any;

function assertAlmostEqual(actual: number, expected: number): void {
  assert.ok(Math.abs(actual - expected) < 0.000001, `${String(actual)} !== ${String(expected)}`);
}

import {
  guideCellPosition,
  guideVisibleWindow,
  guidePresentation,
  guideCellDom,
  renderEpgGuideDom,
} from '../../../renderer/epg/guideDom.js';
import type { EpgProgramCellViewModel } from '../../../renderer/epg.js';

test.after(() => {
  if (originalDocument === undefined) {
    delete (globalThis as { document?: Document }).document;
    return;
  }
  (globalThis as { document: Document }).document = originalDocument;
});

test('guideCellPosition calculates correct left and width within window', () => {
  const windowStart = 1000;
  const windowEnd = 4000; // 3000ms duration
  const trackWidth = 1000;

  // Fully inside
  const pos1 = guideCellPosition(1500, 2500, windowStart, windowEnd, trackWidth);
  assert.equal(pos1.isClippedStart, false);
  assert.equal(pos1.isClippedEnd, false);
  assertAlmostEqual(pos1.left, ((1500 - 1000) / 3000) * trackWidth);
  assertAlmostEqual(pos1.width, ((2500 - 1500) / 3000) * trackWidth);

  // Clipped start
  const pos2 = guideCellPosition(500, 2500, windowStart, windowEnd, trackWidth);
  assert.equal(pos2.isClippedStart, true);
  assert.equal(pos2.isClippedEnd, false);
  assert.equal(pos2.left, 0);
  assertAlmostEqual(pos2.width, ((2500 - 1000) / 3000) * trackWidth);

  // Clipped end
  const pos3 = guideCellPosition(2000, 5000, windowStart, windowEnd, trackWidth);
  assert.equal(pos3.isClippedStart, false);
  assert.equal(pos3.isClippedEnd, true);
  assertAlmostEqual(pos3.left, ((2000 - 1000) / 3000) * trackWidth);
  assertAlmostEqual(pos3.width, ((4000 - 2000) / 3000) * trackWidth);
});

test('guideVisibleWindow clips times to window boundary', () => {
  const windowStart = 1000;
  const windowEnd = 4000;

  const w1 = guideVisibleWindow(1500, 2500, windowStart, windowEnd);
  assert.equal(w1.startsAtMs, 1500);
  assert.equal(w1.endsAtMs, 2500);
  assert.equal(w1.durationMs, 1000);

  const w2 = guideVisibleWindow(500, 2500, windowStart, windowEnd);
  assert.equal(w2.startsAtMs, 1000);
  assert.equal(w2.endsAtMs, 2500);
  assert.equal(w2.durationMs, 1500);
});

test('guidePresentation maps widths to correct tiers and identifies live status', () => {
  // Wide: >= 350
  const pres1 = guidePresentation(350, 'current', true);
  assert.equal(pres1.widthTier, 'wide');
  assert.equal(pres1.isLive, true);
  assert.equal(pres1.showTicker, true);

  // Medium: >= 180 and < 350
  const pres2 = guidePresentation(200, 'upcoming', false);
  assert.equal(pres2.widthTier, 'medium');
  assert.equal(pres2.isLive, false);
  assert.equal(pres2.showTicker, false);

  // Narrow: >= 80 and < 180
  const pres3 = guidePresentation(100, 'past', false);
  assert.equal(pres3.widthTier, 'narrow');

  // Sliver: < 80
  const pres4 = guidePresentation(50, 'upcoming', false);
  assert.equal(pres4.widthTier, 'sliver');
});

test('guideCellDom builds valid DOM elements', () => {
  const program: EpgProgramCellViewModel = {
    id: 'prog-1',
    title: 'Test Program',
    subtitle: 'Test Subtitle',
    description: 'A test program',
    showTitle: 'Test Program',
    episodeLabel: 'S1 E1',
    rating: 'PG',
    quality: ['HD'],
    genres: ['Drama'],
    startsAtMs: 1500,
    endsAtMs: 2500,
    channelId: 'channel-1',
    focusId: 'guide-program-channel-1--prog-1',
    presentationGeneration: 4,
    columnStart: 1,
    columnSpan: 1,
    isSelected: true,
    temporalState: 'current',
    progressPercent: 40,
    widthTier: 'medium',
    timeLabel: '1:30 PM - 2:30 PM',
    artwork: { poster: null, background: null, logo: null },
  };

  const windowStart = 1000;
  const windowEnd = 4000;
  const trackWidth = 1000;

  const cell = guideCellDom(program, windowStart, windowEnd, trackWidth) as any;

  assert.equal(cell.tagName, 'BUTTON');
  assert.equal(cell.classList.contains('epg-grid__program'), true);
  assert.equal(cell.dataset.focusId, 'guide-program-channel-1--prog-1');
  assert.equal(cell.dataset.guideChannelId, 'channel-1');
  assert.equal(cell.dataset.guideProgramId, 'prog-1');
  assert.equal(cell.dataset.guideGeneration, '4');
  assert.equal(cell.getAttribute('role'), 'gridcell');
  assert.equal(cell.dataset.selectedProgram, 'true');
  assert.equal(cell.dataset.temporalState, 'current');
  assert.equal(cell.style.position, 'absolute');
  assert.equal(cell.style.left, '16.666667%');
  assert.equal(cell.style.width, 'max(0px, calc(33.333333% - 4px))');
  assert.equal(cell.style.getPropertyValue('--epg-cell-progress'), '40%');

  const liveBadge = cell.querySelector('.epg-badge--live');
  assert.notEqual(liveBadge, null);
  assert.equal(liveBadge?.textContent, 'LIVE');

  const epBadge = cell.querySelector('.epg-badge--episode');
  assert.notEqual(epBadge, null);
  assert.equal(epBadge?.textContent, 'S1 E1');

  const titleEl = cell.querySelector('.epg-cell-title');
  assert.notEqual(titleEl, null);
  assert.equal(titleEl?.textContent, 'Test Program');

  const subtitleEl = cell.querySelector('.epg-cell-subtitle');
  assert.notEqual(subtitleEl, null);
  assert.equal(subtitleEl?.textContent, 'Test Subtitle');
});

test('Guide reconcile instrumentation cannot replace the original render error', (context) => {
  const original = new Error('render failed');
  context.mock.method(globalThis.performance, 'mark', () => { throw new Error('mark failed'); });
  context.mock.method(globalThis.performance, 'clearMarks', () => { throw new Error('clear failed'); });
  const guide = {
    presentationGeneration: 1,
    get selectedProgram(): never { throw original; },
  };
  assert.throws(
    () => renderEpgGuideDom({ guide } as never, {} as never),
    (error) => error === original,
  );
});
