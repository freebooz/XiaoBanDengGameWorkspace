import { afterEach, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import { createPinia, setActivePinia } from "pinia";
import { WALLET_GRANT_EGGS, useAuthStore } from "../../app/store/auth";
import EggGrantPage from "./EggGrantPage.vue";

afterEach(() => vi.unstubAllGlobals());

const credential = "a".repeat(43);
const player = (accountID: string, displayName: string, balance: number) =>
  ({ account_id: accountID, display_name: displayName, asset_id: "xbd_egg", balance });

async function openWallet(respond: (url: URL, init: RequestInit) => Response | Promise<Response>) {
  const pinia = createPinia();
  setActivePinia(pinia);
  const fetch = vi.fn(async (rawURL: string, init: RequestInit) => {
    const url = new URL(rawURL);
    if (url.pathname === "/api/v1/admin/session") return Response.json({ admin_name: "运营", capabilities: [WALLET_GRANT_EGGS] });
    return respond(url, init);
  });
  vi.stubGlobal("fetch", fetch);
  const auth = useAuthStore();
  await auth.login(credential);
  const page = mount(EggGrantPage, { global: { plugins: [pinia, ElementPlus] } });
  return { auth, fetch, page };
}

const lookupForm = '[data-testid="egg-player-lookup"]';
const grantForm = '[data-testid="egg-grant-form"]';
const reviewedPlayer = '[data-testid="egg-wallet-player"]';
const grantButton = '[data-testid="egg-grant-submit"]';

it("核对玩家和余额后按账号发放，连接中断用同一个请求重试", async () => {
  let grants = 0;
  const { fetch, page } = await openWallet((url, init) => {
    if (url.pathname.endsWith("/player")) return Response.json(player("test-player", "稻田阿福", 100));
    if (++grants === 1) throw new Error("connection lost");
    return Response.json({ ...JSON.parse(String(init.body)), ...player("test-player", "稻田阿福", 125) });
  });
  try {
    await page.get("input[name=nickname]").setValue("  稻田阿福  ");
    expect(page.get<HTMLButtonElement>(grantButton).element.disabled).toBe(true);
    await page.get(grantForm).trigger("submit");
    expect(grants).toBe(0);

    await page.get(lookupForm).trigger("submit");
    await flushPromises();
    const [lookupURL, lookup] = fetch.mock.calls[1];
    expect(new URL(lookupURL).pathname).toBe("/api/v1/admin/wallet/eggs/player");
    expect(new URL(lookupURL).searchParams.get("display_name")).toBe("稻田阿福");
    expect(lookup).toMatchObject({ method: "GET", headers: { Authorization: "Bearer " + credential } });
    expect(page.get(reviewedPlayer).text()).toContain("test-player");
    expect(page.get('[data-testid="egg-player-balance"]').text()).toBe("100 枚");

    await page.get("input[name=amount]").setValue("25");
    await page.get(grantForm).trigger("submit");
    await flushPromises();
    expect(page.get("[role=alert]").text()).toContain("重试");

    await page.get(grantForm).trigger("submit");
    await flushPromises();
    const [, , firstGrant, retriedGrant] = fetch.mock.calls;
    expect(firstGrant[0]).toMatch(/\/api\/v1\/admin\/wallet\/eggs\/grant$/);
    expect(retriedGrant[1]).toMatchObject({
      method: "POST", headers: { Authorization: "Bearer " + credential }, body: firstGrant[1].body,
    });
    expect(JSON.parse(String(firstGrant[1].body))).toMatchObject({
      display_name: "稻田阿福", expected_account_id: "test-player", amount: 25,
      request_id: expect.stringMatching(/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/),
    });
    expect(page.get('[data-testid="egg-grant-receipt"]').text()).toContain("鸡蛋余额125 枚");
    expect(page.get('[data-testid="egg-player-balance"]').text()).toBe("125 枚");
    expect(page.get<HTMLInputElement>("input[name=amount]").element.value).toBe("");
  } finally {
    page.unmount();
  }
});

it("较早的查询回包无法替换新玩家，改动昵称后必须再次核对", async () => {
  let respondToOldLookup!: (response: Response) => void;
  const { fetch, page } = await openWallet((url) => {
    if (url.searchParams.get("display_name") === "旧昵称") {
      return new Promise((resolve) => { respondToOldLookup = resolve; });
    }
    return Response.json(player("new-player", "新昵称", 3));
  });
  try {
    await page.get("input[name=nickname]").setValue("旧昵称");
    await page.get(lookupForm).trigger("submit");
    await page.get("input[name=nickname]").setValue("新昵称");
    await page.get(lookupForm).trigger("submit");
    await flushPromises();
    expect(fetch.mock.calls[1][1].signal?.aborted).toBe(true);
    respondToOldLookup(Response.json(player("old-player", "旧昵称", 123)));
    await flushPromises();
    expect(page.get(reviewedPlayer).text()).toContain("new-player");
    expect(page.get(reviewedPlayer).text()).not.toContain("old-player");

    await page.get("input[name=amount]").setValue("25");
    await page.get("input[name=nickname]").setValue("另一个昵称");
    expect(page.find(reviewedPlayer).exists()).toBe(false);
    expect(page.get<HTMLButtonElement>(grantButton).element.disabled).toBe(true);
    await page.get(grantForm).trigger("submit");
    expect(fetch.mock.calls).toHaveLength(3);
  } finally {
    page.unmount();
  }
});

it("已核对的昵称被重新占用时要求重新核对账号", async () => {
  let lookups = 0;
  const { page } = await openWallet((url) => {
    if (url.pathname.endsWith("/player")) return Response.json(player(++lookups === 1 ? "old-account" : "new-account", "同一昵称", 20));
    return Response.json({ error: "需要重新核对" }, { status: 409 });
  });
  try {
    await page.get("input[name=nickname]").setValue("同一昵称");
    await page.get(lookupForm).trigger("submit");
    await flushPromises();
    await page.get("input[name=amount]").setValue("25");
    await page.get(grantForm).trigger("submit");
    await flushPromises();
    expect(page.find(reviewedPlayer).exists()).toBe(false);
    expect(page.get("[role=alert]").text()).toContain("重新核对");
    await page.get(lookupForm).trigger("submit");
    await flushPromises();
    expect(page.get(reviewedPlayer).text()).toContain("new-account");
    expect(page.get<HTMLButtonElement>(grantButton).element.disabled).toBe(true);
  } finally {
    page.unmount();
  }
});

it("管理员会话变更时取消查询并清除输入，忽略旧会话回包", async () => {
  let completeLookup!: (response: Response) => void;
  const { auth, fetch, page } = await openWallet(() => new Promise((resolve) => { completeLookup = resolve; }));
  try {
    const nickname = page.get<HTMLInputElement>("input[name=nickname]");
    await nickname.setValue("上一会话玩家");
    await page.get(lookupForm).trigger("submit");
    await auth.login("b".repeat(43));
    expect(fetch.mock.calls[1][1].signal?.aborted).toBe(true);
    completeLookup(Response.json(player("former-player", "上一会话玩家", 100)));
    await flushPromises();
    expect(nickname.element.value).toBe("");
    expect(page.find(reviewedPlayer).exists()).toBe(false);
    expect(page.get<HTMLButtonElement>(grantButton).element.disabled).toBe(true);
  } finally {
    page.unmount();
  }
});
