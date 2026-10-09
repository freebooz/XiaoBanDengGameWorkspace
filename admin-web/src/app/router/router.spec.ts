import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { createAppRouter, routeRecords } from "./index";
import { useAuthStore } from "../store/auth";
import { apiGet } from "../../services/api/client";

// 网络边界返回真实只读管理员结构，路由和状态仍使用生产实现。
const session = { username: "test-reader", role: "readonly", expires_at: "2099-01-01T00:00:00Z" };
function response(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}

describe("小板凳后台路由", () => {
  beforeEach(() => {
    localStorage.clear();
    setActivePinia(createPinia());
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response({ error: "请登录" }, 401)));
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

  it("包含一期核心业务路由", () => {
    const paths = routeRecords.flatMap((route) => [route.path, ...(route.children ?? []).map((child) =>
      child.path.startsWith("/") ? child.path : "/" + child.path)]);
    expect(paths).toEqual(expect.arrayContaining(["/login", "/dashboard", "/users", "/games/products", "/rooms", "/matches"]));
  });

  it("未登录访问受保护页面会保留目标地址", async () => {
    const router = createAppRouter(true);
    await router.push("/users?page=2");
    expect(router.currentRoute.value.path).toBe("/login");
    expect(router.currentRoute.value.query.redirect).toBe("/users?page=2");
  });

  it("浏览器刷新先向服务端恢复只读管理员会话", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response(session)));
    const router = createAppRouter(true);
    await router.push("/users");
    expect(router.currentRoute.value.path).toBe("/users");
    expect(useAuthStore().adminName).toBe("test-reader");
    expect(useAuthStore().isAuthenticated).toBe(true);
  });

  it("伪造旧开发 localStorage 会话不能绕过服务端认证", async () => {
    localStorage.setItem("xbd_admin_dev_session", "1");
    setActivePinia(createPinia());
    const router = createAppRouter(true);
    await router.push("/users");
    expect(router.currentRoute.value.path).toBe("/login");
    expect(useAuthStore().isAuthenticated).toBe(false);
  });

  it("恢复请求离线后保留可展示的错误且停留登录页", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValue(new TypeError("offline")));
    const router = createAppRouter(true);
    await router.push("/rooms");
    expect(router.currentRoute.value.path).toBe("/login");
    expect(useAuthStore()).toMatchObject({ isAuthenticated: false, sessionError: "无法连接业务服务" });
  });

  it("不把无效的管理员会话响应当作授权", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(response({ username: "test-reader", role: "admin" })));
    const router = createAppRouter(true);
    await router.push("/users");
    expect(router.currentRoute.value.path).toBe("/login");
    expect(useAuthStore()).toMatchObject({ isAuthenticated: false, sessionError: "管理员会话响应无效" });
  });

  it("旧业务请求迟到的401不能清掉更新的成功登录", async () => {
    let finishOldRequest!: (value: Response) => void;
    const oldRequest = new Promise<Response>((resolve) => { finishOldRequest = resolve; });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(response(session)).mockReturnValueOnce(oldRequest).mockResolvedValue(response(session)));
    const router = createAppRouter(true);
    await router.push("/users");
    const staleRequest = apiGet("/api/v1/admin/matches");
    await useAuthStore().login("test-reader", "test-password");
    finishOldRequest(response({ error: "旧会话已失效" }, 401));
    await expect(staleRequest).rejects.toMatchObject({ status: 401 });
    expect(useAuthStore().isAuthenticated).toBe(true);
    expect(router.currentRoute.value.path).toBe("/users");
  });

  it("登录进行中发起的业务401不能覆盖随后成功的身份", async () => {
    let finishLogin!: (value: Response) => void;
    let finishOldRequest!: (value: Response) => void;
    const loginResponse = new Promise<Response>((resolve) => { finishLogin = resolve; });
    const oldRequest = new Promise<Response>((resolve) => { finishOldRequest = resolve; });
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(response(session)).mockReturnValueOnce(loginResponse).mockReturnValueOnce(oldRequest));
    const router = createAppRouter(true);
    await router.push("/users");
    const loggingIn = useAuthStore().login("test-reader", "test-password");
    const staleRequest = apiGet("/api/v1/admin/matches");
    finishLogin(response(session));
    await loggingIn;
    finishOldRequest(response({ error: "登录完成前的请求未获授权" }, 401));
    await expect(staleRequest).rejects.toMatchObject({ status: 401 });
    expect(useAuthStore().isAuthenticated).toBe(true);
    expect(router.currentRoute.value.path).toBe("/users");
  });

  it("业务接口401立即清除会话并返回当前页面的登录入口", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(response(session)).mockResolvedValue(response({ error: "会话已过期" }, 401)));
    const router = createAppRouter(true);
    await router.push("/users?page=2");
    await expect(apiGet("/api/v1/admin/users")).rejects.toMatchObject({ status: 401 });
    await vi.waitFor(() => { expect(router.currentRoute.value.path).toBe("/login"); });
    expect(router.currentRoute.value.query.redirect).toBe("/users?page=2");
    expect(useAuthStore().isAuthenticated).toBe(false);
  });
});
