import { createHash } from 'node:crypto';
import { readFileSync } from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';
import { expect, test, type Page } from '@playwright/test';

const root = path.resolve(__dirname, '../../Fixtures/DisplayProof');

type Fixture = {
  name: string;
  file: string;
  title: string;
  theme: string;
  modules: number;
  outline: boolean;
  overflow: boolean;
  contentHash: string;
};

type Contract = {
  stage: { width: number; height: number };
  viewport: { width: number; height: number };
  gap: number;
  columnGap: number;
  spaceL: number;
  spaceXL: number;
  pads: { top: number; right: number; bottom: number; left: number };
  pageWidth: number;
  pageHeight: number;
  blockWidths: number[];
  blockHeights: number[];
  between: number[];
  columnGaps: number[];
  overflow: boolean;
  font: string;
  ready: string | null;
  proof: string | null;
  theme: string | null;
  title: string;
  blocks: number;
  outline: string;
  stepped: boolean;
};

const manifest = JSON.parse(readFileSync(path.join(root, 'manifest.json'), 'utf8')) as {
  stage: { width: number; height: number };
  fixtures: Fixture[];
};

test.describe('display layout proof', () => {
  test.beforeEach(async ({ page }) => {
    await page.route('**/*', (route) => {
      const url = route.request().url();
      if (url.startsWith('file:') || url.startsWith('data:')) return route.continue();
      return route.abort();
    });
  });

  for (const fixture of manifest.fixtures) {
    test(fixture.name, async ({ page }) => {
      expect(manifest.stage).toEqual({ width: 1920, height: 1080 });
      const htmlPath = path.join(root, fixture.file);
      const bytes = readFileSync(htmlPath);
      const hash = createHash('sha256').update(bytes).digest('hex');
      expect(hash).toBe(fixture.contentHash);
      expect(fixture.modules).toBeGreaterThan(0);

      const blocked: string[] = [];
      page.on('requestfailed', (request) => {
        const url = request.url();
        if (!url.startsWith('file:') && !url.startsWith('data:')) blocked.push(url);
      });

      await page.goto(pathToFileURL(htmlPath).href, { waitUntil: 'load' });
      await page.waitForFunction(
        () => document.fonts.status === 'loaded' && document.documentElement.getAttribute('data-hs-ready') === '1'
      );
      expect(blocked).toEqual([]);

      const report = await contract(page);
      expect(report.viewport).toEqual({ width: 1920, height: 1080 });
      expect(report.stage).toEqual({ width: 1920, height: 1080 });
      expect(report.ready).toBe('1');
      expect(report.proof).toBe('1');
      expect(report.theme).toBe(fixture.theme);
      expect(report.title).toBe(fixture.title);
      expect(report.blocks).toBe(fixture.modules);
      expect(report.overflow).toBe(false);
      expect(report.gap).toBe(report.spaceL);
      expect(report.columnGap).toBe(report.spaceL);
      for (const edge of [report.pads.top, report.pads.right, report.pads.bottom, report.pads.left]) {
        expect(edge).toBe(report.spaceXL);
      }
      expect(report.pageWidth).toBeCloseTo(report.stage.width - report.pads.left - report.pads.right, 1);
      expect(report.pageHeight).toBeCloseTo(report.stage.height - report.pads.top - report.pads.bottom, 1);
      for (const width of report.blockWidths) {
        expect(width).toBeCloseTo(report.pageWidth, 1);
      }
      const span = Math.max(...report.blockHeights) - Math.min(...report.blockHeights);
      expect(span).toBeLessThan(1.5);
      const used = report.blockHeights.reduce((sum, height) => sum + height, 0) + report.between.reduce((sum, gap) => sum + gap, 0);
      expect(used).toBeCloseTo(report.pageHeight, 0);
      for (const gap of report.between) {
        expect(gap).toBeCloseTo(report.spaceL, 1);
      }
      for (const gap of report.columnGaps) {
        expect(gap).toBeCloseTo(report.spaceL, 1);
      }
      expect(report.font.includes('system-ui')).toBe(false);
      expect(report.font.includes('Helvetica')).toBe(false);
      expect(report.font.includes('Georgia')).toBe(false);
      const face = fixture.theme === 'moonlit-autumn' ? 'HS Serif' : 'HS Sans';
      expect(report.font.includes(face)).toBe(true);
      expect(report.outline).toBe(fixture.outline ? 'solid' : 'none');
      expect(report.stepped).toBe(fixture.overflow);

      await expect(page).toHaveScreenshot(`${fixture.name}.png`, {
        animations: 'disabled',
        caret: 'hide',
        scale: 'css',
      });
    });
  }
});

async function contract(page: Page): Promise<Contract> {
  return page.evaluate(() => {
    const stage = document.querySelector('.stage');
    const pageEl = document.querySelector('.page');
    if (!(stage instanceof HTMLElement) || !(pageEl instanceof HTMLElement)) {
      throw new Error('missing stage');
    }
    const stageBox = stage.getBoundingClientRect();
    const pageBox = pageEl.getBoundingClientRect();
    const blocks = Array.from(pageEl.querySelectorAll(':scope > .block'));
    const stageStyle = getComputedStyle(stage);
    const pageStyle = getComputedStyle(pageEl);
    const rootStyle = getComputedStyle(document.documentElement);
    const spaceL = parseFloat(rootStyle.getPropertyValue('--space-l'));
    const spaceXL = parseFloat(rootStyle.getPropertyValue('--space-xl'));
    const boxes = blocks.map((block) => block.getBoundingClientRect());
    const between: number[] = [];
    for (let index = 1; index < boxes.length; index += 1) {
      between.push(boxes[index].top - boxes[index - 1].bottom);
    }
    const doc = document.documentElement;
    const overflow =
      doc.scrollWidth > doc.clientWidth + 1 ||
      doc.scrollHeight > doc.clientHeight + 1 ||
      stage.scrollWidth > stage.clientWidth + 1 ||
      stage.scrollHeight > stage.clientHeight + 1 ||
      pageEl.scrollWidth > pageEl.clientWidth + 1 ||
      pageEl.scrollHeight > pageEl.clientHeight + 1 ||
      blocks.some((block) => block.scrollWidth > block.clientWidth + 1 || block.scrollHeight > block.clientHeight + 1);
    const stepped = Array.from(document.querySelectorAll('[data-fit]')).some((node) => {
      if (!(node instanceof HTMLElement)) return false;
      const tokenName = node.getAttribute('data-fit');
      const max = parseFloat(getComputedStyle(document.documentElement).getPropertyValue(`--type-${tokenName}`));
      const size = parseFloat(getComputedStyle(node).fontSize);
      return size < max - 0.5;
    });
    return {
      stage: { width: stageBox.width, height: stageBox.height },
      viewport: { width: window.innerWidth, height: window.innerHeight },
      gap: parseFloat(pageStyle.rowGap),
      columnGap: parseFloat(pageStyle.columnGap),
      spaceL,
      spaceXL,
      pads: {
        top: parseFloat(stageStyle.paddingTop),
        right: parseFloat(stageStyle.paddingRight),
        bottom: parseFloat(stageStyle.paddingBottom),
        left: parseFloat(stageStyle.paddingLeft),
      },
      pageWidth: pageBox.width,
      pageHeight: pageBox.height,
      blockWidths: boxes.map((box) => box.width),
      blockHeights: boxes.map((box) => box.height),
      between,
      columnGaps: Array.from(document.querySelectorAll('.cols')).map((node) => parseFloat(getComputedStyle(node).columnGap)),
      overflow,
      font: stageStyle.fontFamily,
      ready: doc.getAttribute('data-hs-ready'),
      proof: doc.getAttribute('data-hs-proof'),
      theme: stage.getAttribute('data-theme'),
      title: document.title,
      blocks: blocks.length,
      outline: blocks.length > 0 ? getComputedStyle(blocks[0]).outlineStyle : 'none',
      stepped,
    };
  });
}
