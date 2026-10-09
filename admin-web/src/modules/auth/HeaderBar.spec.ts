import { afterEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import ElementPlus from "element-plus";
import HeaderBar from "../../layouts/HeaderBar.vue";
import { createAppRouter } from "../../app/router";
import { useAuthStore } from "../../app/store/auth";

// 真实下拉退出操作必须先注销服务端 cookie 会话。
async function mountHeader(logoutResponse: Response | Error) {
  const session = { username: "test-reader", role: "readonly", expires_at: "2099-01-01T00:00:00Z" };
  const fetchMock = vi.fn().mockResolvedValueOnce(new Response(JSON.stringify(session)))
    .mockImplementation(() => logoutResponse instanceof Error ? Promise.reject(logoutResponse) : Promise.resolve(logoutResponse));
  vi.stubGlobal("fetch", fetchMock);
  const pinia = createPinia();
  setActivePinia(pinia);
  const router = createAppRouter(true);
  await router.push("/users");
  const wrapper = mount(HeaderBar, { global: { plugins: [pinia, router, ElementPlus] } });
  return { wrapper, router, fetchMock };
}
enableAutoUnmount(afterEach);
describe("正式管理员页头", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
  it("生产只读身份展示和退出调用真实注销接口", async () => {
    vi.stubEnv("DEV", false);
    const { wrapper, router, fetchMock } = await mountHeader(new Response(null, { status: 204 }));
    expect(wrapper.text()).not.toContain("开发环境");
    expect(wrapper.text()).toContain("只读管理员");
    await wrapper.findComponent({ name: "ElDropdownItem" }).get("li[role=menuitem]").trigger("click");
    await vi.waitFor(() => { expect(router.currentRoute.value.path).toBe("/login"); });
    expect(useAuthStore().isAuthenticated).toBe(false);
    const [input, options] = fetchMock.mock.calls[1] as unknown as [string, RequestInit];
    expect(new URL(input).pathname).toBe("/api/v1/admin/auth/logout");
    expect(options).toMatchObject({ method: "POST", credentials: "include" });
  });
  it("注销服务离线时保留会话并显示可重试错误", async () => {
    const { wrapper, router } = await mountHeader(new TypeError("offline"));
    await wrapper.findComponent({ name: "ElDropdownItem" }).get("li[role=menuitem]").trigger("click");
    await vi.waitFor(() => { expect(wrapper.text()).toContain("无法连接业务服务"); });
    expect(useAuthStore().isAuthenticated).toBe(true);
    expect(router.currentRoute.value.path).toBe("/users");
    expect(wrapper.find('[data-testid="retry-logout"]').exists()).toBe(true);
  });
});
