import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import UsersPage from "./UsersPage.vue";
import { adminApi } from "../../services/api/admin";

vi.mock("../../services/api/admin", () => ({
  adminApi: { users: vi.fn() },
}));

enableAutoUnmount(afterEach);

describe("用户中心", () => {
  beforeEach(() => {
    vi.mocked(adminApi.users).mockReset();
  });

  it("空数据库显示品牌化空状态", async () => {
    vi.mocked(adminApi.users).mockResolvedValue({
      items: [],
      total: 0,
      page: 1,
      page_size: 20,
      data_source: "partial",
    });
    const wrapper = mount(UsersPage, {
      attachTo: document.body,
      global: { plugins: [ElementPlus] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain("暂无用户数据");
  });

  it("关键词和账号状态会进入真实查询参数", async () => {
    vi.mocked(adminApi.users).mockResolvedValue({
      items: [],
      total: 0,
      page: 1,
      page_size: 20,
      data_source: "partial",
    });
    const wrapper = mount(UsersPage, {
      attachTo: document.body,
      global: { plugins: [ElementPlus] },
    });
    await flushPromises();

    await wrapper.get('[data-testid="user-keyword"]').setValue("acc-001");
    const select = wrapper.findComponent({ name: "ElSelect" });
    select.vm.$emit("update:modelValue", "active");
    await wrapper.get('[data-testid="user-search"]').trigger("click");
    await flushPromises();

    expect(adminApi.users).toHaveBeenLastCalledWith(
      expect.objectContaining({ keyword: "acc-001", status: "active", page: 1 }),
    );
  });

  it("点击用户打开详情抽屉且待接入域不伪造数据", async () => {
    vi.mocked(adminApi.users).mockResolvedValue({
      items: [{
        account_id: "acc-001",
        display_name: "测试用户",
        account_type: "guest",
        status: "active",
        created_at: "2026-09-30T00:00:00Z",
      }],
      total: 1,
      page: 1,
      page_size: 20,
      data_source: "partial",
    });
    const wrapper = mount(UsersPage, {
      attachTo: document.body,
      global: { plugins: [ElementPlus] },
    });
    await flushPromises();

    await wrapper.get('[data-testid="open-user-acc-001"]').trigger("click");
    await flushPromises();

    expect(wrapper.text()).toContain("基础资料");
    expect(wrapper.text()).toContain("身份绑定");
    expect(wrapper.text()).toContain("游戏档案");
    expect(wrapper.text()).toContain("登录记录");
    expect(wrapper.text()).toContain("数据待接入");
  });

  it("开发数据源必须显示开发数据标识", async () => {
    vi.mocked(adminApi.users).mockResolvedValue({
      items: [],
      total: 0,
      page: 1,
      page_size: 20,
      data_source: "development",
    });
    const wrapper = mount(UsersPage, {
      attachTo: document.body,
      global: { plugins: [ElementPlus] },
    });
    await flushPromises();
    expect(wrapper.text()).toContain("开发数据");
  });
});
