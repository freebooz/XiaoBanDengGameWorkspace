const crypto = require('node:crypto');
const fs = require('node:fs');
const path = require('node:path');

async function main() {
  const input = JSON.parse(fs.readFileSync(0, 'utf8'));
  const endpoint = new URL(input.base);
  if (endpoint.protocol !== 'https:' || endpoint.hostname !== '127.0.0.1' || !endpoint.port) {
    throw new Error('Expected an isolated HTTPS fixture.');
  }
  if (!/^[\w-]{43}$/.test(input.token) || !/^[a-f0-9-]{36}$/.test(input.reportId)) {
    throw new Error('Invalid fixture credential or report metadata.');
  }
  const playwright = require(process.env.XBD_PLAYWRIGHT_PATH || 'playwright');
  const cert = new crypto.X509Certificate(fs.readFileSync(input.leaf));
  const acceptLeaf = crypto.createHash('sha256')
    .update(cert.publicKey.export({ format: 'der', type: 'spki' })).digest('base64');
  const browser = await playwright.chromium.launch({
    executablePath: process.env.XBD_CHROME_PATH || undefined,
    args: [`--ignore-certificate-errors-spki-list=${acceptLeaf}`],
  });
  try {
    const page = await browser.newPage({ viewport: { width: 1280, height: 900 } });
    page.setDefaultTimeout(10_000);
    const pageErrors = [];
    page.on('pageerror', error => pageErrors.push(error.name));
    await page.goto(`${endpoint.origin}/mahjong/reports`, { waitUntil: 'domcontentloaded' });
    await page.locator('#admin-credential').fill(input.token);
    await page.getByRole('button', { name: '登录', exact: true }).click();
    await page.getByTestId(`report-open-${input.reportId}`).click();
    await page.locator('#report-disposition').selectOption('upheld');
    await page.locator('#report-note').fill('自动验证审核流程');
    await page.getByRole('button', { name: '确认结案' }).click();
    await page.getByText('处理结果已保存 · 举报成立', { exact: true }).waitFor();
    await page.getByTestId('report-status').selectOption('upheld');
    await page.getByTestId(`report-open-${input.reportId}`).click();
    await page.getByText('自动验证审核流程', { exact: true }).waitFor();
    if (pageErrors.length > 0) throw new Error('The browser reported an application JavaScript error.');
    const stored = await page.evaluate(() => Object.values(localStorage).concat(Object.values(sessionStorage)));
    if (stored.some(value => value.includes(input.token))) throw new Error('The browser persisted the test credential.');
    const preview = process.env.XBD_ADMIN_PREVIEW_PATH;
    if (preview) await page.screenshot({ path: path.resolve(preview) });
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('#admin-credential').waitFor();
    console.log('MAHJONG_ADMIN_BROWSER_OK login=true queue=true resolution=true storage=memory');
  } finally {
    await browser.close();
  }
}

main().catch(() => {
  // Automation errors may contain the text entered in the password field.
  console.error('Mahjong admin browser fixture did not reach the expected state.');
  process.exitCode = 1;
});
