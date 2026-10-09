// 真实浏览器烟测：要求隔离后端、development 房间开关及显式测试凭据。
import fs from "node:fs/promises";
import path from "node:path";
import { chromium, expect } from "@playwright/test";

const base = process.env.TEST_ADMIN_BASE_URL;
const username = process.env.TEST_ADMIN_USERNAME;
const password = process.env.TEST_ADMIN_PASSWORD;
if (!base || !username || !password) throw new Error("必须显式提供隔离测试地址及管理员凭据");
const results = [];
const browser = await chromium.launch({
  headless: true,
  ...(process.env.TEST_CHROMIUM_PATH ? { executablePath: process.env.TEST_CHROMIUM_PATH } : {}),
  ...(process.env.TEST_CHROMIUM_ARGS ? { args: JSON.parse(process.env.TEST_CHROMIUM_ARGS) } : {}),
});
const context = await browser.newContext();
const page = await context.newPage();
const pageErrors = [];
page.on("pageerror", (error) => pageErrors.push(error.message));
try {
  const denied = await context.request.get(`${base}/api/v1/admin/rooms`);
  expect(denied.status()).toBe(401);
  await page.goto(`${base}/rooms`);
  await expect(page).toHaveURL(/\/login\?redirect=/);
  await page.getByRole("textbox", { name: "管理员账号" }).fill(username);
  await page.locator("#admin-password").fill("wrong-test-only-password");
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page.getByRole("alert")).toContainText("无效");
  // 失败响应显示错误后 finally 才清空口令；等待表单完成避免再次输入被清理。
  await expect(page.locator("#admin-password")).toHaveValue("");
  await page.locator("#admin-password").fill(password);
  await page.getByRole("button", { name: "登录", exact: true }).click();
  await expect(page).toHaveURL(base + "/rooms");
  const cookie = (await context.cookies()).find((item) => item.name === "xbd_admin_session");
  expect(cookie, JSON.stringify((await context.cookies()).map(({name, domain, path, httpOnly, secure})=>({name, domain, path, httpOnly, secure})))).toBeDefined();
  expect(cookie?.httpOnly).toBe(true);
  expect(cookie?.sameSite).toBe("Lax");
  expect(await page.evaluate(() => localStorage.getItem("xbd_admin_dev_session"))).toBeNull();
  results.push("登录失败、真实Cookie登录、只读拒绝及站内恢复");

  // 游戏连接独立保活；测试房间明确命名且后端 source=development。
  const gamePage = await context.newPage();
  await gamePage.goto(`${base}/games/products`);
  const roomID = `regression-development-${Date.now()}`;
  const wsURL = process.env.TEST_GAME_WS_URL || base.replace(/^http/, "ws") + "/ws";
  const matchID = await gamePage.evaluate(async ({ roomID, wsURL }) => {
    const connect = () => new Promise((resolve, reject) => {
      const ws = new WebSocket(wsURL); const queued = []; const waiting = [];
      ws.onerror = () => reject(new Error("测试游戏连接失败"));
      ws.onmessage = (event) => { const message = JSON.parse(event.data); const index = waiting.findIndex((item) => item.type === message.type); if (index >= 0) waiting.splice(index, 1)[0].resolve(message); else queued.push(message); };
      ws.onopen = () => resolve({ ws, read: (type) => new Promise((done) => { const index = queued.findIndex((item) => item.type === type); if (index >= 0) done(queued.splice(index, 1)[0]); else waiting.push({type, resolve: done}); }) });
    });
    const red = await connect(); red.ws.send(JSON.stringify({type:"chess_join", room_id:roomID, client_id:"regression-only-red"})); await red.read("chess_joined"); await red.read("chess_state");
    const black = await connect(); black.ws.send(JSON.stringify({type:"chess_join", room_id:roomID, client_id:"regression-only-black"})); await black.read("chess_joined"); const ready = await black.read("chess_state"); await red.read("chess_state");
    const move = {type:"chess_move",piece_id:"red_soldier_0",from:{x:0,y:6},to:{x:0,y:5}};
    red.ws.send(JSON.stringify(move)); await red.read("chess_state"); await black.read("chess_state");
    red.ws.send(JSON.stringify(move)); await red.read("chess_error");
    window.regressionClients = [red.ws,black.ws]; return ready.match_id;
  }, {roomID,wsURL});
  await page.getByTestId("room-refresh").click();
  await expect(page.locator(".readonly-center")).toContainText(roomID);
  await page.getByTestId(`open-room-${roomID}`).click();
  await expect(page.locator(".room-detail-data")).toContainText("2 人在线");
  await expect(page.locator(".room-detail-data")).toContainText("regression-only-red");
  await expect(page.locator(".room-detail-data .development-badge")).toContainText("开发数据");
  results.push("真实双客户端、合法/非法走子、目录连接与开发来源");

  for (const [width,height] of [[1366,768],[1440,900],[1920,1080]]) {
    await page.setViewportSize({width,height});
    for (const route of ["/games/products","/rooms","/matches"]) {
      await page.goto(base + route); await expect(page.locator(".el-table").first()).toBeVisible();
      await page.reload(); await expect(page.locator(".el-table").first()).toBeVisible();
      const layout = await page.evaluate(() => ({
        overflow:document.documentElement.scrollWidth > window.innerWidth,
        bodyFont:getComputedStyle(document.querySelector(".el-table")).fontSize,
        headerFont:getComputedStyle(document.querySelector(".el-table__header")).fontSize,
        primaryColor:getComputedStyle(document.querySelector(".el-button--primary")).backgroundColor,
        brand:getComputedStyle(document.documentElement).getPropertyValue("--xbd-brand-primary").trim(),
      }));
      expect(layout.overflow).toBe(false); expect(layout.bodyFont).toBe("11px"); expect(layout.headerFont).toBe("12px");
      // 比较浏览器归一化颜色，避免十六进制与 RGB 表示差异。
      const brandColor=await page.evaluate((brand)=>{const node=document.createElement("i");node.style.color=brand;document.body.append(node);const color=getComputedStyle(node).color;node.remove();return color;},layout.brand);
      expect(layout.primaryColor).toBe(brandColor);
      results.push(`${width}×${height} ${route} 刷新、11px/12px字体、品牌色与视口`);
    }
  }
  await page.goto(`${base}/matches`);
  await page.getByTestId(`open-match-${matchID}`).click();
  await expect(page.locator(".match-detail-data")).toContainText("regression-only-red");
  await page.getByRole("tab",{name:"游戏事件"}).click();
  await expect(page.locator(".event-payload")).toContainText("red_soldier_0");
  await page.getByRole("tab",{name:"回放",exact:true}).click();
  await expect(page.getByTestId("replay-board")).toBeVisible();
  await expect(page.locator(".replay-controls")).toContainText("第 1 / 2 帧");
  await page.getByTestId("replay-next").click();
  await expect(page.locator(".replay-controls")).toContainText("第 2 / 2 帧");
  await expect(page.getByTestId("replay-next")).toBeDisabled();
  results.push("真实持久化玩家、事件、快照棋盘与逐帧回放");
  await gamePage.close();
  await page.goto(`${base}/matches`);
  await expect(page.locator(".readonly-center")).toContainText("已中止");
  await page.getByTestId("match-game").fill("nonexistent-regression-game");
  await page.getByTestId("match-search").click();
  await expect(page.locator(".el-table__empty-block")).toContainText("暂无对局数据");
  await page.getByTestId("match-reset").click();
  await expect(page.locator(".readonly-center")).toContainText(matchID);
  results.push("断线中止、查询空数据与筛选重置");

  // 故障由浏览器网络层显式注入；不把夹具当作实际服务故障或运营数据。
  await page.route("**/api/v1/admin/matches?**", (route) => route.fulfill({status:500,json:{error:"回归测试注入接口失败"}}));
  await page.getByTestId("match-refresh").click(); await expect(page.locator(".query-error")).toContainText("回归测试注入接口失败");
  await page.unroute("**/api/v1/admin/matches?**");
  await page.getByRole("button",{name:"重试",exact:true}).click(); await expect(page.locator(".readonly-center")).toContainText(matchID);
  await page.route("**/api/v1/admin/matches?**", (route) => route.abort("connectionrefused"));
  await page.getByTestId("match-refresh").click(); await expect(page.locator(".query-error")).toContainText("无法连接业务服务");
  await page.unroute("**/api/v1/admin/matches?**");
  await page.getByRole("button",{name:"重试",exact:true}).click(); await expect(page.locator(".readonly-center")).toContainText(matchID);
  results.push("注入HTTP500、离线与重试（网络测试夹具）");
  await page.locator(".admin-user").click(); await page.getByText("退出登录",{exact:true}).click();
  await expect(page).toHaveURL(/\/login$/);
  expect((await context.request.get(`${base}/api/v1/admin/auth/session`)).status()).toBe(401);
  expect(pageErrors).toEqual([]);
  results.push("真实注销、会话失效及浏览器无异常");
  if (process.env.TEST_REPORT_PATH) { await fs.mkdir(path.dirname(process.env.TEST_REPORT_PATH),{recursive:true});await fs.writeFile(process.env.TEST_REPORT_PATH,JSON.stringify({source:"隔离开发服务；故障项为显式网络注入",results},null,2)); }
  console.log(JSON.stringify({passed:results.length,results},null,2));
} finally { await context.close();await browser.close(); }
