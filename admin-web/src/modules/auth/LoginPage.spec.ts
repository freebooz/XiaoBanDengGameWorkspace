import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import ElementPlus from "element-plus";
import LoginPage from "./LoginPage.vue";
import { createAppRouter } from "../../app/router";
import { useAuthStore } from "../../app/store/auth";

// 仅模拟 HTTP 边界，输入、提交、路由和 Element Plus 均运行真实实现。
const session = { username: "test-reader", role: "readonly", expires_at: "2099-01-01T00:00:00Z" };
function jsonResponse(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), { status, headers: { "Content-Type": "application/json" } });
}
async function mountLogin(path = "/login") {
  const pinia = createPinia();
  setActivePinia(pinia);
  const router = createAppRouter(true);
  await router.push(path);
  const wrapper = mount(LoginPage, { attachTo: document.body, global: { plugins: [pinia, router, ElementPlus] } });
  return { wrapper, router };
}
async function submitLogin(wrapper: ReturnType<typeof mount> ) {
  await wrapper.get('input[name="username"]').setValue("test-reader");
  await wrapper.get('input[name="password"]').setValue("test-password");
  await wrapper.get("form").trigger("submit");
  await flushPromises();
}
enableAutoUnmount(afterEach);
describe("小板凳品牌登录页", () => {
  beforeEach(() => {
    localStorage.clear();
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(jsonResponse({ error: "请登录" }, 401)));
  });
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });

  it("生产环境也展示品牌和真实账号密码登录表单", async () => {
    vi.stubEnv("DEV", false);
    const { wrapper } = await mountLogin();
    expect(wrapper.text()).toContain("小板凳游戏运营平台");
    expect(wrapper.find('[aria-label="小板凳品牌标识"]').exists()).toBe(true);
    expect(wrapper.find('input[name="username"]').exists()).toBe(true);
    expect(wrapper.find('input[name="password"][type="password"]').exists()).toBe(true);
    expect(wrapper.text()).not.toContain("开发环境");
  });

  it("登录成功通过 cookie 请求恢复站内目标地址且不持久保存凭据", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(jsonResponse({ error: "请登录" }, 401)).mockResolvedValue(jsonResponse(session));
    vi.stubGlobal("fetch", fetchMock);
    const { wrapper, router } = await mountLogin("/login?redirect=%2Frooms%3Fpage%3D2");
    await submitLogin(wrapper);
    await vi.waitFor(() => { expect(router.currentRoute.value.fullPath).toBe("/rooms?page=2"); });
    expect(useAuthStore().adminName).toBe("test-reader");
    const [input, options] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
    expect(new URL(input).pathname).toBe("/api/v1/admin/auth/login");
    expect(options).toMatchObject({ method: "POST", credentials: "include", body: JSON.stringify({ username: "test-reader", password: "test-password" }) });
    expect(localStorage.length).toBe(0);
    expect(sessionStorage.length).toBe(0);
    expect((wrapper.get('input[name="password"]').element as HTMLInputElement).value).toBe("");
  });

  it.each(["https://evil.test/rooms", "//evil.test/rooms", "/\\evil.test/rooms", "/login?redirect=%2Frooms"])("拒绝不安全或循环跳转目标 %s", async (redirect) => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(jsonResponse({ error: "请登录" }, 401)).mockResolvedValue(jsonResponse(session)));
    const { wrapper, router } = await mountLogin("/login?redirect=" + encodeURIComponent(redirect));
    await submitLogin(wrapper);
    await vi.waitFor(() => { expect(router.currentRoute.value.path).toBe("/dashboard"); });
  });

  it("错误密码401显示服务端错误且不会登录或再次触发会话导航", async () => {
    const fetchMock = vi.fn().mockResolvedValueOnce(jsonResponse({ error: "请登录" }, 401)).mockResolvedValue(jsonResponse({ error: "账号或密码错误" }, 401));
    vi.stubGlobal("fetch", fetchMock);
    const { wrapper, router } = await mountLogin("/login?redirect=%2Fusers");
    await submitLogin(wrapper);
    expect(wrapper.text()).toContain("账号或密码错误");
    expect(useAuthStore().isAuthenticated).toBe(false);
    expect(router.currentRoute.value.path).toBe("/login");
    expect(fetchMock).toHaveBeenCalledTimes(2);
  });

  it("登录服务离线后允许重试且成功前不会授权", async () => {
    vi.stubGlobal("fetch", vi.fn().mockResolvedValueOnce(jsonResponse({ error: "请登录" }, 401)).mockRejectedValueOnce(new TypeError("offline")).mockResolvedValue(jsonResponse(session)));
    const { wrapper, router } = await mountLogin();
    await submitLogin(wrapper);
    expect(wrapper.text()).toContain("无法连接业务服务");
    expect(useAuthStore().isAuthenticated).toBe(false);
    expect(router.currentRoute.value.path).toBe("/login");
    await submitLogin(wrapper);
    await vi.waitFor(() => { expect(router.currentRoute.value.path).toBe("/dashboard"); });
  });

  it("恢复会话进行中禁用登录入口，避免并发提交两种认证请求", async () => {
    let finishRestore!: (value: Response) => void;
    const restoring = new Promise<Response>((resolve) => { finishRestore = resolve; });
    const fetchMock = vi.fn().mockRejectedValueOnce(new TypeError("offline")).mockReturnValueOnce(restoring).mockResolvedValue(jsonResponse(session));
    vi.stubGlobal("fetch", fetchMock);
    const { wrapper } = await mountLogin();
    await wrapper.get('input[name="username"]').setValue("test-reader");
    await wrapper.get('input[name="password"]').setValue("test-password");
    await wrapper.get('[data-testid="retry-session"]').trigger("click");
    try {
      expect((wrapper.get('input[name="username"]').element as HTMLInputElement).disabled).toBe(true);
      expect((wrapper.get('button[type="submit"]').element as HTMLButtonElement).disabled).toBe(true);
      await wrapper.get("form").trigger("submit");
      expect(fetchMock).toHaveBeenCalledTimes(2);
    } finally {
      finishRestore(jsonResponse(session));
      await flushPromises();
    }
  });

  it("会话恢复离线时展示重试入口并可恢复原目标页面", async () => {
    vi.stubGlobal("fetch", vi.fn().mockRejectedValueOnce(new TypeError("offline")).mockResolvedValue(jsonResponse(session)));
    const { wrapper, router } = await mountLogin("/users?page=2");
    expect(wrapper.text()).toContain("无法连接业务服务");
    await wrapper.get('[data-testid="retry-session"]').trigger("click");
    await vi.waitFor(() => { expect(router.currentRoute.value.fullPath).toBe("/users?page=2"); });
  });
});
