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

(globalThis as any).document = mockDocument as any;

import {
  guideCellPosition,
  guideVisibleWindow,
  guidePresentation,
  guideCellDom,
} from '../../../renderer/epg/guideDom.js';
import type { EpgProgramCellViewModel } from '../../../renderer/epg.js';

test('guideCellPosition calculates correct left and width within window', () => {
  const windowStart = 1000;
  const windowEnd = 4000; // 3000ms duration
  const trackWidth = 1200;

  // Fully inside
  const pos1 = guideCellPosition(1500, 2500, windowStart, windowEnd, trackWidth);
  assert.equal(pos1.isClippedStart, false);
  assert.equal(pos1.isClippedEnd, false);
  assert.equal(pos1.left, ((1500 - 1000) / 3000) * 1200); // 200px
  assert.equal(pos1.width, ((2500 - 1500) / 3000) * 1200 - 4); // 400px - 4px gap

  // Clipped start
  const pos2 = guideCellPosition(500, 2500, windowStart, windowEnd, trackWidth);
  assert.equal(pos2.isClippedStart, true);
  assert.equal(pos2.isClippedEnd, false);
  assert.equal(pos2.left, 0);
  assert.equal(pos2.width, ((2500 - 1000) / 3000) * 1200 - 4); // 600px - 4px gap

  // Clipped end
  const pos3 = guideCellPosition(2000, 5000, windowStart, windowEnd, trackWidth);
  assert.equal(pos3.isClippedStart, false);
  assert.equal(pos3.isClippedEnd, true);
  assert.equal(pos3.left, ((2000 - 1000) / 3000) * 1200); // 400px
  assert.equal(pos3.width, ((4000 - 2000) / 3000) * 1200 - 4); // 800px - 4px gap
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
    columnStart: 1,
    columnSpan: 1,
    isSelected: true,
    temporalState: 'current',
    progressPercent: 40,
    widthTier: 'medium',
    timeLabel: '1:30 PM - 2:30 PM',
  };

  const windowStart = 1000;
  const windowEnd = 4000;
  const trackWidth = 1200;

  const cell = guideCellDom(program, windowStart, windowEnd, trackWidth) as any;

  assert.equal(cell.tagName, 'ARTICLE');
  assert.equal(cell.classList.contains('epg-grid__program'), true);
  assert.equal(cell.dataset.selectedProgram, 'true');
  assert.equal(cell.dataset.temporalState, 'current');
  assert.equal(cell.style.position, 'absolute');
  assert.equal(cell.style.left, '200px');
  // 400px width minus 4px gap
  assert.equal(cell.style.width, '396px');
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
