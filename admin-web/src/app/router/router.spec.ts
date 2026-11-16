import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { createAppRouter, routeRecords } from "./index";
import { PLATFORM_READ, WALLET_GRANT_EGGS, useAuthStore } from "../store/auth";

describe("小板凳后台路由", () => {
  beforeEach(() => {
    localStorage.clear();
    setActivePinia(createPinia());
  });
  afterEach(() => vi.unstubAllGlobals());

  it("包含一期核心业务路由", () => {
    const paths = routeRecords.flatMap((route) => [
      route.path,
      ...(route.children ?? []).map((child) =>
        child.path.startsWith("/") ? child.path : "/" + child.path,
      ),
    ]);

    expect(paths).toContain("/login");
    expect(paths).toContain("/dashboard");
    expect(paths).toContain("/monitor");
    expect(paths).toContain("/users");
    expect(paths).toContain("/games/products");
    expect(paths).toContain("/rooms");
    expect(paths).toContain("/matches");
  });

  it("未登录访问受保护页面会重定向到登录页", async () => {
    const router = createAppRouter(true);
    await router.push("/users");
    await router.isReady();
    expect(router.currentRoute.value.path).toBe("/login");
  });

  it("鸡蛋发放路由只对有发放权限的管理员开放", async () => {
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ admin_name: "只读", capabilities: [PLATFORM_READ] })))
      .mockResolvedValueOnce(new Response(JSON.stringify({ admin_name: "运营", capabilities: [WALLET_GRANT_EGGS] }))));
    const router = createAppRouter(true);
    const auth = useAuthStore();
    await auth.login("a".repeat(43));
    await router.push("/wallet/eggs");
    expect(router.currentRoute.value.path).toBe("/dashboard");

    await auth.login("b".repeat(43));
    expect(auth.landingPath).toBe("/wallet/eggs");
    await router.push("/wallet/eggs");
    expect(router.currentRoute.value.path).toBe("/wallet/eggs");
  });

  it("页面刷新不使用旧的开发登录标记", async () => {
    localStorage.setItem("xbd_admin_dev_session", "1");

    // 用新的 Pinia 模拟浏览器刷新后重新创建应用。
    setActivePinia(createPinia());
    const router = createAppRouter(true);
    await router.push("/users");
    await router.isReady();

    expect(router.currentRoute.value.path).toBe("/login");
    expect(useAuthStore().isAuthenticated).toBe(false);
  });
});
