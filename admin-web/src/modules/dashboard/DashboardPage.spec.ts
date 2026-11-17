import { beforeEach, describe, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import ElementPlus from "element-plus";
import { ref, shallowRef } from "vue";
import DashboardPage from "./DashboardPage.vue";
import { adminApi, platformApi } from "../../services/api/admin";
import { useMonitor } from "../monitor/monitor";

vi.mock("../../services/api/admin", () => ({
  adminApi: { overview: vi.fn() },
  platformApi: { health: vi.fn(), catalog: vi.fn(), aiCapabilities: vi.fn() },
}));
vi.mock("../monitor/monitor", async (importOriginal) => ({
  ...await importOriginal<typeof import("../monitor/monitor")>(),
  useMonitor: vi.fn(),
}));

type MonitorRefs = ReturnType<typeof useMonitor>;
type Snapshot = NonNullable<MonitorRefs["snapshot"]["value"]>;
let monitor: MonitorRefs;

function liveSnapshot(roomID = "2864"): Snapshot {
  return {
    generated_at: "2026-11-14T08:00:00Z",
    services: [{ id: "api", status: "ok", checked_at: "2026-11-14T08:00:00Z" }],
    lobbies: [],
    rooms: [{ room_id: roomID, game_id: "mahjong", product_id: "xbd_mahjong", rule_set_id: "guiyang",
      rule_version: "2.0.0", kind: "friend", status: "playing", phase: "turn", capacity: 4, players: 4,
      connected_players: 4, completed_rounds: 0, updated_at: "2026-11-14T08:00:00Z" }],
    players: [
      { account_id: "account-a", game_id: "mahjong", status: "playing", connected: true },
      { account_id: "account-a", game_id: "landlord", status: "playing", connected: true },
      { account_id: "account-b", game_id: "mahjong", status: "reconnecting", connected: false },
    ],
  };
}

describe("综合工作台", () => {
  beforeEach(() => {
    vi.mocked(adminApi.overview).mockReset();
    vi.mocked(platformApi.health).mockReset();
    vi.mocked(platformApi.catalog).mockReset();
    monitor = { snapshot: shallowRef<Snapshot>(), connection: ref("connecting") };
    vi.mocked(useMonitor).mockReturnValue(monitor);
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
    expect(wrapper.text()).toContain("累计对局");
    expect(wrapper.text()).toContain("8");
    expect(wrapper.text()).toContain("PostgreSQL");
    expect(wrapper.text()).toContain("正常");
    expect(wrapper.text()).toContain("小板凳象棋");

    const metrics = () => Object.fromEntries(wrapper.findAll(".metric-card").map((card) => [
      card.get(".metric-card__label").text(), card.get(".metric-card__value").text(),
    ]));
    expect(metrics()).toMatchObject({ 当前在线: "--", 实时房间: "--" });
    monitor.snapshot.value = liveSnapshot();
    monitor.connection.value = "live";
    await flushPromises();
    expect(metrics()).toMatchObject({ 当前在线: "1", 实时房间: "1" });
    expect(wrapper.text()).toContain("对局中 1 间");
    expect(wrapper.get('[data-testid="monitor-room-2864"]').text()).toContain("出牌");
    expect(wrapper.get('[data-testid="monitor-player-account-b"]').text()).toContain("等待重连");
    expect(useMonitor).toHaveBeenCalledTimes(1);

    monitor.connection.value = "stale";
    await flushPromises();
    expect(metrics().实时房间).toBe("1");
    expect(wrapper.get('[data-testid="dashboard-monitor-status"]').text()).toContain("最后收到的快照");

    monitor.snapshot.value = { ...liveSnapshot(), players: [], rooms: [] };
    monitor.connection.value = "live";
    await flushPromises();
    expect(metrics()).toMatchObject({ 当前在线: "0", 实时房间: "0" });
    expect(wrapper.find('[data-testid="monitor-room-2864"]').exists()).toBe(false);
    expect(wrapper.find('[data-testid="monitor-player-account-b"]').exists()).toBe(false);
    expect(adminApi.overview).toHaveBeenCalledTimes(1);
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
