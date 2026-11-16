import { afterEach, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import { createPinia, setActivePinia } from "pinia";
import { WALLET_GRANT_EGGS, useAuthStore } from "../../app/store/auth";
import EggGrantPage from "./EggGrantPage.vue";

afterEach(() => vi.unstubAllGlobals());

it("连接中断后用同一个请求编号重试，并显示服务端鸡蛋余额", async () => {
  const pinia = createPinia();
  setActivePinia(pinia);
  const credential = "a".repeat(43);
  const fetch = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify({
    admin_name: "运营",
    capabilities: [WALLET_GRANT_EGGS],
  }))).mockRejectedValueOnce(new Error("connection lost")).mockImplementationOnce((_url, init) =>
    Promise.resolve(new Response(JSON.stringify({
      ...JSON.parse(String(init.body)), account_id: "test-player", asset_id: "xbd_egg", balance: 125,
    }))),
  );
  vi.stubGlobal("fetch", fetch);
  await useAuthStore().login(credential);
  const page = mount(EggGrantPage, { global: { plugins: [pinia, ElementPlus] } });
  await page.get("input[name=nickname]").setValue("  稻田阿福  ");
  await page.get("input[name=amount]").setValue("25");
  await page.get("form").trigger("submit");
  await flushPromises();
  expect(page.get("[role=alert]").text()).toContain("重试");

  await page.get("form").trigger("submit");
  await flushPromises();
  const [, firstGrant, retriedGrant] = fetch.mock.calls;
  expect(firstGrant[0]).toMatch(/\/api\/v1\/admin\/wallet\/eggs\/grant$/);
  expect(retriedGrant[1]).toMatchObject({
    method: "POST", headers: { Authorization: "Bearer " + credential }, body: firstGrant[1].body,
  });
  expect(JSON.parse(firstGrant[1].body)).toMatchObject({
    display_name: "稻田阿福", amount: 25,
    request_id: expect.stringMatching(/^[\da-f]{8}-(?:[\da-f]{4}-){3}[\da-f]{12}$/),
  });
  expect(page.get("[role=status]").text()).toContain("鸡蛋余额125 枚");
  expect(page.get<HTMLInputElement>("input[name=amount]").element.value).toBe("");
  page.unmount();
});
