import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import ElementPlus from "element-plus";
import LoginPage from "./LoginPage.vue";
import { createAppRouter } from "../../app/router";
import { useAuthStore } from "../../app/store/auth";

describe("小板凳品牌登录页", () => {
  beforeEach(() => {
    localStorage.clear();
  });
  afterEach(() => vi.unstubAllGlobals());

  it("展示正式品牌名称、Logo 可访问文本和开发环境标识", async () => {
    const pinia = createPinia();
    setActivePinia(pinia);
    const router = createAppRouter(true);
    await router.push("/login");
    await router.isReady();

    const wrapper = mount(LoginPage, {
      global: { plugins: [pinia, router, ElementPlus] },
    });

    expect(wrapper.text()).toContain("小板凳游戏运营平台");
    expect(wrapper.text()).toContain("开发环境");
    expect(wrapper.find('[aria-label="小板凳品牌标识"]').exists()).toBe(true);
  });

  it("验证 Bearer 凭据后按权限进入举报队列", async () => {
    const fetchSession = vi.fn().mockResolvedValue(new Response(JSON.stringify({
      admin_name: "审核员", capabilities: ["mahjong:review"],
    })));
    vi.stubGlobal("fetch", fetchSession);
    const pinia = createPinia();
    setActivePinia(pinia);
    const router = createAppRouter(true);
    await router.push("/login");
    await router.isReady();

    const wrapper = mount(LoginPage, {
      global: { plugins: [pinia, router, ElementPlus] },
    });

    const input = wrapper.get('input[type="password"]');
    await input.setValue("a".repeat(43));
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(useAuthStore().isAuthenticated).toBe(true);
    expect(fetchSession).toHaveBeenCalledWith(expect.stringMatching(/\/api\/v1\/admin\/session$/), expect.objectContaining({
      headers: expect.objectContaining({ Authorization: "Bearer " + "a".repeat(43) }),
    }));
    expect(JSON.stringify(pinia.state.value)).not.toContain("a".repeat(43));
    expect(localStorage.length).toBe(0);
    await vi.waitFor(() => {
      expect(router.currentRoute.value.path).toBe("/mahjong/reports");
    });
  });
});
