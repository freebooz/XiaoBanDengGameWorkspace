import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { RouterView } from "vue-router";
import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import { createAppRouter } from "./index";
import { jsonResponse, mockHTTP, testGames } from "../../modules/common/test-support";

// 使用真实路由、布局及接口客户端，模拟浏览器刷新后的会话恢复。
enableAutoUnmount(afterEach);
describe("一期业务路由刷新", () => {
  beforeEach(() => { localStorage.clear(); setActivePinia(createPinia()); });
  afterEach(() => { vi.unstubAllGlobals(); });
  it.each([
    ["/games/products", "小板凳象棋"],
    ["/rooms", "暂无房间数据"],
    ["/matches", "暂无对局数据"],
  ])("直接刷新 %s 恢复真实业务页", async (path, expected) => {
    const pinia = createPinia();
    setActivePinia(pinia);
    mockHTTP((url) => jsonResponse(url.pathname === "/api/v1/admin/auth/session"
      ? { username: "test-reader", role: "readonly", expires_at: "2099-01-01T00:00:00Z" }
      : url.pathname === "/api/v1/catalog"
      ? { games: testGames }
      : { items: [], total: 0, page: 1, page_size: 20, data_source: "partial" }));
    const router = createAppRouter(true);
    await router.push(path);
    await router.isReady();
    const wrapper = mount(RouterView, { attachTo: document.body, global: { plugins: [pinia, router, ElementPlus] } });
    await flushPromises();
    expect(router.currentRoute.value.path).toBe(path);
    expect(wrapper.text()).toContain(expected);
    expect(wrapper.text()).not.toContain("模块初始化中");
  });
  it.each(["/games/products", "/rooms", "/matches"])("未登录访问 %s 保持现有守卫", async (path) => {
    mockHTTP(() => jsonResponse({ error: "请登录" }, 401));
    const router = createAppRouter(true);
    await router.push(path);
    expect(router.currentRoute.value.path).toBe("/login");
    expect(router.currentRoute.value.query.redirect).toBe(path);
  });
});
