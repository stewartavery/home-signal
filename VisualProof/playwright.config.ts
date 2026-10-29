import { defineConfig } from '@playwright/test';

const updating = process.argv.some((arg) => {
  return arg === '-u' || arg === '--update-snapshots' || arg.startsWith('--update-snapshots=');
});

if (updating && process.env.HS_PROOF_CONTAINER !== '1') {
  throw new Error(
    'Regen display-proof goldens only inside the pinned Playwright container via scripts/display-proof.sh record. Do not record against a host browser or a real display.'
  );
}

export default defineConfig({
  testDir: './tests',
  outputDir: './test-results',
  fullyParallel: false,
  workers: 1,
  retries: 0,
  snapshotDir: '../Fixtures/DisplayProof/screenshots',
  snapshotPathTemplate: '{snapshotDir}/{platform}/{arg}{ext}',
  expect: {
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      scale: 'css',
      maxDiffPixels: 0,
    },
  },
  use: {
    browserName: 'chromium',
    viewport: { width: 1920, height: 1080 },
    deviceScaleFactor: 1,
    locale: 'en-US',
    timezoneId: 'UTC',
    reducedMotion: 'reduce',
    serviceWorkers: 'block',
  },
});
