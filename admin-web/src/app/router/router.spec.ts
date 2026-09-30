import { beforeEach, describe, expect, it } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { createAppRouter, routeRecords } from "./index";
import { useAuthStore } from "../store/auth";

describe("小板凳后台路由", () => {
  beforeEach(() => {
    localStorage.clear();
    setActivePinia(createPinia());
  });

  it("包含一期核心业务路由", () => {
    const paths = routeRecords.flatMap((route) => [
      route.path,
      ...(route.children ?? []).map((child) =>
        child.path.startsWith("/") ? child.path : "/" + child.path,
      ),
    ]);

    expect(paths).toContain("/login");
    expect(paths).toContain("/dashboard");
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

  it("开发管理员登录后刷新核心路由仍保持登录态", async () => {
    const auth = useAuthStore();
    auth.loginDevelopment();

    // 用新的 Pinia 模拟浏览器刷新后重新创建应用。
    setActivePinia(createPinia());
    const router = createAppRouter(true);
    await router.push("/users");
    await router.isReady();

    expect(router.currentRoute.value.path).toBe("/users");
    expect(useAuthStore().isAuthenticated).toBe(true);
  });
});
