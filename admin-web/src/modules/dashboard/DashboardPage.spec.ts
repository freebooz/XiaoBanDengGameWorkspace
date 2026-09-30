import { beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import DashboardPage from "./DashboardPage.vue";
import { adminApi, platformApi } from "../../services/api/admin";

vi.mock("../../services/api/admin", () => ({
  adminApi: { overview: vi.fn() },
  platformApi: { health: vi.fn(), catalog: vi.fn(), aiCapabilities: vi.fn() },
}));

describe("综合工作台", () => {
  beforeEach(() => {
    vi.mocked(adminApi.overview).mockReset();
    vi.mocked(platformApi.health).mockReset();
    vi.mocked(platformApi.catalog).mockReset();
  });

  it("展示真实概览指标和服务健康状态", async () => {
    vi.mocked(adminApi.overview).mockResolvedValue({
      registered_users: 3,
      active_rooms: 2,
      total_matches: 8,
      service_time: "2026-09-30T00:00:00Z",
      data_source: "partial",
    });
    vi.mocked(platformApi.health).mockResolvedValue({
      service: "ok",
      postgres: "ok",
      redis: "ok",
      time: "2026-09-30T00:00:00Z",
    });
    vi.mocked(platformApi.catalog).mockResolvedValue({
      games: [
        {
          product_id: "xbd_chinese_chess",
          game_category: "board",
          game_id: "chinese_chess",
          rule_set_id: "standard",
          rule_version: "1.0.0",
          name: "小板凳象棋",
          enabled: true,
        },
      ],
    });

    const wrapper = mount(DashboardPage, { global: { plugins: [ElementPlus] } });
    await flushPromises();

    expect(wrapper.text()).toContain("注册用户");
    expect(wrapper.text()).toContain("3");
    expect(wrapper.text()).toContain("实时房间");
    expect(wrapper.text()).toContain("2");
    expect(wrapper.text()).toContain("累计对局");
    expect(wrapper.text()).toContain("8");
    expect(wrapper.text()).toContain("PostgreSQL");
    expect(wrapper.text()).toContain("正常");
    expect(wrapper.text()).toContain("小板凳象棋");
  });

  it("尚无可靠统计的数据明确显示待接入", async () => {
    vi.mocked(adminApi.overview).mockResolvedValue({
      registered_users: 0,
      active_rooms: 0,
      total_matches: 0,
      service_time: "2026-09-30T00:00:00Z",
      data_source: "partial",
    });
    vi.mocked(platformApi.health).mockResolvedValue({
      service: "ok",
      postgres: "ok",
      redis: "ok",
      time: "2026-09-30T00:00:00Z",
    });
    vi.mocked(platformApi.catalog).mockResolvedValue({ games: [] });

    const wrapper = mount(DashboardPage, { global: { plugins: [ElementPlus] } });
    await flushPromises();

    expect(wrapper.text()).toContain("今日活跃");
    expect(wrapper.text()).toContain("当前在线");
    expect(wrapper.text().match(/待接入/g)?.length).toBeGreaterThanOrEqual(2);
  });

  it("后端离线时仍渲染工作台并显示服务离线", async () => {
    vi.mocked(adminApi.overview).mockRejectedValue(new Error("offline"));
    vi.mocked(platformApi.health).mockRejectedValue(new Error("offline"));
    vi.mocked(platformApi.catalog).mockRejectedValue(new Error("offline"));

    const wrapper = mount(DashboardPage, { global: { plugins: [ElementPlus] } });
    await flushPromises();

    expect(wrapper.text()).toContain("综合工作台");
    expect(wrapper.text()).toContain("服务离线");
  });
});
