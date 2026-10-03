import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { randomBytes } from 'node:crypto';
const { chromium } = createRequire('/opt/browser-tests/package.json')('playwright');
const base = process.env.TROJAN_TEST_URL || 'http://127.0.0.1:80';
const username = process.env.TROJAN_TEST_ADMIN_USER || 'smoke-admin';
const password = process.env.TROJAN_TEST_ADMIN_PASSWORD || 'test-admin-password-123';
const temporaryUser = 'ui-test-' + randomBytes(5).toString('hex');
const temporaryPass = randomBytes(16).toString('hex');
const browser = await chromium.launch({ args: ['--no-sandbox', '--disable-gpu'] });
const context = await browser.newContext({ locale: 'zh-CN', viewport: {width: 1440, height: 900} });
const page = await context.newPage();
const errors = [], external = [];
page.on('pageerror', error => {errors.push(error.message); console.error('PAGE_ERROR:', error.message);});
page.on('request', request => {
  if (/^https?:/.test(request.url()) && new URL(request.url()).origin !== new URL(base).origin) external.push(request.url());
});
async function login(target, user, pass) {
  await target.goto(base + '/#/login');
  await target.locator('input[name="username"]').fill(user);
  await target.locator('input[name="password"]').fill(pass);
  await target.getByRole('button', {name: '登录', exact: true}).click();
  await target.waitForURL('**/#/dashboard');
}
await page.route('**/common/version', async route => {
  await new Promise(resolve => setTimeout(resolve, 600));
  await route.continue();
});
let adminToken;
try {
  await login(page, username, password);
  adminToken = await page.evaluate(() => localStorage.getItem('token'));
  const checks = await Promise.all(Array.from({length: 12}, async () => {
    const response = await page.request.get(base + '/auth/loginUser', {headers: {'Authorization': 'Bearer ' + adminToken}});
    assert.equal((await response.json()).data.isAdmin, true);
  }));
  assert.equal((await page.request.get(base + '/common/serverInfo', {headers: {'Authorization': 'Bearer ' + adminToken}})).status(), 200);
  await page.goto(base + '/#/user');
  const add = page.getByRole('button', {name:'添加', exact:true});
  await add.waitFor({state:'visible'});
  await add.click();
  const dialog = page.locator('.el-dialog:visible');
  await dialog.getByPlaceholder('输入用户名', {exact:true}).fill(temporaryUser);
  await dialog.getByPlaceholder('输入密码', {exact:true}).fill(temporaryPass);
  const created = page.waitForResponse(response => response.url().endsWith('/trojan/user') && response.request().method() === 'POST');
  await dialog.getByRole('button', {name:'确定', exact:true}).click();
  assert.equal((await (await created).json()).Msg, 'success');
  const row = page.getByRole('row').filter({hasText:temporaryUser});
  await row.waitFor({state:'visible'});
  for (const label of ['trojan链接', 'clash链接']) {
    await row.getByRole('button', {name:'分享', exact:true}).hover();
    await page.getByRole('menuitem', {name:label, exact:true}).click();
    await page.locator('.el-dialog:visible canvas').waitFor({state:'visible'});
    await page.locator('.el-dialog:visible .el-dialog__headerbtn').click();
  }
  const ordinary = await browser.newContext({locale:'zh-CN'});
  const ordinaryPage = await ordinary.newPage();
  ordinaryPage.on('pageerror', error => errors.push(error.message));
  await login(ordinaryPage, temporaryUser, temporaryPass);
  await ordinaryPage.goto(base + '/#/user');
  await ordinaryPage.getByRole('row').filter({hasText:temporaryUser}).waitFor({state:'visible'});
  assert.equal(await ordinaryPage.getByRole('button', {name:'添加', exact:true}).count(), 0);
  assert.equal(await ordinaryPage.getByRole('button', {name:'删除', exact:true}).count(), 0);
  await ordinary.close();
  await row.getByRole('button', {name:'删除', exact:true}).click();
  const deleted = page.waitForResponse(response => response.url().includes('/trojan/user?id=') && response.request().method() === 'DELETE');
  await page.locator('.el-dialog:visible').getByRole('button', {name:'确定', exact:true}).click();
  assert.equal((await (await deleted).json()).Msg, 'success');
  await row.waitFor({state:'hidden'});
  assert.deepEqual(errors, [], 'Management page has JavaScript errors');
  assert.deepEqual(external, [], 'Management page depends on external resources');
  console.log('MANAGEMENT_UI_OK: custom administrator, add user, ordinary-user controls, delete user, share QR codes, local assets');
} finally {
  if (adminToken) {
    const headers = {'Authorization': 'Bearer ' + adminToken};
    const response = await fetch(base + '/trojan/user', {headers});
    const data = await response.json();
    for (const user of data.Data?.userList || []) {
      if (user.Username === temporaryUser) await fetch(base + '/trojan/user?id=' + user.ID, {method:'DELETE', headers});
    }
  }
  await browser.close();
}
