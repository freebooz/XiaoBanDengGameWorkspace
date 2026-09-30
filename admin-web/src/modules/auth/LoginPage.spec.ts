import { beforeEach, describe, expect, it, vi } from "vitest";
import { mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import ElementPlus from "element-plus";
import LoginPage from "./LoginPage.vue";
import { createAppRouter } from "../../app/router";
import { useAuthStore } from "../../app/store/auth";

describe("小板凳品牌登录页", () => {
  beforeEach(() => {
    localStorage.clear();
  });

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

  it("开发管理员登录后进入综合工作台", async () => {
    const pinia = createPinia();
    setActivePinia(pinia);
    const router = createAppRouter(true);
    await router.push("/login");
    await router.isReady();

    const wrapper = mount(LoginPage, {
      global: { plugins: [pinia, router, ElementPlus] },
    });

    await wrapper.get('[data-testid="development-login"]').trigger("click");
    expect(useAuthStore().isAuthenticated).toBe(true);
    await vi.waitFor(() => {
      expect(router.currentRoute.value.path).toBe("/dashboard");
    });
  });
});
