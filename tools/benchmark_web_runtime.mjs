// Run against a locally served release export, never a player browser profile.
// PLAYWRIGHT_MODULE may point to an existing Playwright index.mjs installation.
import fs from 'node:fs';
import path from 'node:path';
import { pathToFileURL } from 'node:url';

const modulePath = process.env.PLAYWRIGHT_MODULE;
const { chromium } = await import(modulePath ? pathToFileURL(path.resolve(modulePath)).href : 'playwright');
const outputPath = process.argv[2] || 'output/runtime-benchmark.json';
const url = process.argv[3] || 'http://127.0.0.1:8777/game/index.html';
const browser = await chromium.launch({ headless: true, args: ['--use-gl=angle', '--use-angle=swiftshader'] });
try {
  const page = await browser.newPage({ viewport: { width: 1280, height: 720 } });
  const errors = [];
  page.on('console', message => {
    if (message.type() === 'error') errors.push(message.text());
    console.log(message.text());
  });
  page.on('pageerror', error => errors.push(String(error)));
  await page.route(url, async route => {
    const response = await route.fetch();
    const body = await response.text();
    if (!body.includes('"args":[]')) throw new Error('Expected an unmodified Godot release configuration');
    await route.fulfill({ response, body: body.replace('"args":[]', '"args":["--","--runtime-benchmark"]') });
  });
  await page.goto(url, { waitUntil: 'domcontentloaded' });
  await page.waitForFunction(() => window.__runtimeBenchmark, {}, { timeout: 180000 });
  const result = await page.evaluate(() => window.__runtimeBenchmark);
  fs.mkdirSync(path.dirname(outputPath), { recursive: true });
  fs.writeFileSync(outputPath, JSON.stringify({ result, errors }, null, 2));
  if (errors.length || !result.release) process.exitCode = 1;
} finally {
  await browser.close();
}
