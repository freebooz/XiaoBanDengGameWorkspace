import { flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAuthStore } from "../../app/store/auth";
import MonitorPage from "./MonitorPage.vue";

function eventStream() {
  let output!: ReadableStreamDefaultController<Uint8Array>;
  const body = new ReadableStream<Uint8Array>({ start(controller) { output = controller; } });
  const publishSnapshot = (snapshot: unknown) => {
    output.enqueue(new TextEncoder().encode(`event: snapshot\ndata: ${JSON.stringify(snapshot)}\n\n`));
  };
  return {
    response: new Response(body, { headers: { "Content-Type": "text/event-stream" } }),
    publishSnapshot,
    publish(status: string) {
      const at = "2026-11-14T03:00:00Z";
      const snapshot = {
        generated_at: at, services: [{ id: "api", status: "ok", checked_at: at }],
        lobbies: [{ game_id: "mahjong", product_id: "xbd_mahjong", online_players: 4, waiting_players: 0, rooms: 1 }],
        rooms: [{ game_id: "mahjong", product_id: "xbd_mahjong", room_id: "6382", status, kind: "friend", phase: "turn",
          rule_set_id: "guiyang", rule_version: "2.0.0", capacity: 4, players: 4, connected_players: 4, completed_rounds: 0, updated_at: at }],
        players: [{ game_id: "mahjong", room_id: "6382", room_status: status, account_id: "sample-account", status,
          connected: true, seat: 0, display_name: "小板凳" }],
      };
      publishSnapshot(snapshot);
    },
    end() { output.close(); },
  };
}

const generation = "2026-11-14T03:00:00.123456789Z";
const reusedGeneration = "2026-11-14T03:00:00.123456790Z";

function mahjongSnapshot({ revision = 0, paused = false, phase = "waiting", roomGeneration = generation } = {}) {
  const at = "2026-11-14T03:00:01Z";
  const playing = phase !== "waiting";
  return {
    generated_at: at, services: [], lobbies: [],
    rooms: [{ game_id: "mahjong", product_id: "xbd_mahjong", room_id: "6382", room_generation: roomGeneration,
      status: playing ? "playing" : "waiting", kind: "friend", phase, rule_set_id: "guiyang", rule_version: "2.0.0",
      capacity: 4, players: 2, ready_players: 1, connected_players: 1, completed_rounds: 1, updated_at: at,
      mahjong: { round_number: 2, round_limit: 4, admission_paused: paused, admission_revision: revision,
        can_set_admission: !playing, spectator_count: playing ? 2 : 0,
        ...(playing ? { match_id: "round-match-id", dealer: 0, turn: 1, remaining_tiles: 27,
          action_deadline_ms: 1794625224000, last_discard: { seat: 0, suit: "tong", rank: 5 } } : {}) },
    }],
    players: [
      { game_id: "mahjong", room_id: "6382", room_generation: roomGeneration, account_id: "account-a",
        status: playing ? "playing" : "ready", connected: true, seat: 0, display_name: "一号玩家" },
      { game_id: "mahjong", room_id: "6382", room_generation: roomGeneration, account_id: "account-b",
        status: playing ? "reconnecting" : "waiting", connected: false, seat: 1, display_name: "二号玩家" },
      { game_id: "mahjong", room_id: "6382", room_generation: "2026-11-14T02:59:00Z", account_id: "old-seat",
        status: "ready", connected: true, seat: 2, display_name: "上次房间玩家" },
    ],
  };
}

async function mountMahjongRoom(
  respondToRoom: (url: URL, options: RequestInit) => Response | Promise<Response>,
  capabilities = ["platform:read", "mahjong:manage_rooms"],
) {
  const pinia = createPinia();
  setActivePinia(pinia);
  const stream = eventStream();
  const fetch = vi.fn(async (url: string, options: RequestInit) => {
    const requestURL = new URL(url);
    if (requestURL.pathname === "/api/v1/admin/session") return Response.json({ admin_name: "运营", capabilities });
    if (requestURL.pathname === "/api/v1/admin/monitor/stream") return stream.response;
    return respondToRoom(requestURL, options);
  });
  vi.stubGlobal("fetch", fetch);
  await useAuthStore().login("s".repeat(43));
  const page = mount(MonitorPage, { global: { plugins: [pinia] } });
  stream.publishSnapshot(mahjongSnapshot());
  await flushPromises();
  return { page, stream, fetch };
}

function pauseReceipt(requestID: string) {
  return { request_id: requestID, room_id: "6382", room_generation: generation, admission_revision: 1,
    paused: true, reason: "处理用户反馈", admin_name: "运营", created_at: "2026-11-14T03:00:05Z" };
}

describe("实时监视", () => {
  afterEach(() => {
    vi.useRealTimers();
    vi.unstubAllGlobals();
  });

  it.each([false, true])("显示房间变化并自动重连（房间中心模式 %s）", async (roomsOnly) => {
    const pinia = createPinia();
    setActivePinia(pinia);
    const first = eventStream();
    const second = eventStream();
    const fetch = vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ admin_name: "运营", capabilities: ["platform:read"] })))
      .mockResolvedValueOnce(first.response)
      .mockResolvedValueOnce(second.response);
    vi.stubGlobal("fetch", fetch);
    await useAuthStore().login("s".repeat(43));
    vi.useFakeTimers({ toFake: ["setTimeout", "clearTimeout"] });
    const page = mount(MonitorPage, { props: { roomsOnly }, global: { plugins: [pinia] } });
    try {
      first.publish("waiting");
      await flushPromises();
      expect(page.get('[data-testid="monitor-connection"]').text()).toBe("实时连接");
      expect(page.find('[data-testid="monitor-server-section"]').exists()).toBe(!roomsOnly);
      expect(page.find('[data-testid="monitor-lobbies-section"]').exists()).toBe(!roomsOnly);
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("等待中");
      expect(page.get('[data-testid="monitor-player-sample-account"]').text()).toContain("小板凳");
      first.publish("playing");
      await flushPromises();
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("对局中");
      expect(fetch).toHaveBeenCalledTimes(2);

      first.end();
      await flushPromises();
      expect(page.get('[data-testid="monitor-connection"]').text()).toContain("连接中断");
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("对局中");
      await vi.advanceTimersByTimeAsync(1_000);
      second.publish("settled");
      await flushPromises();
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("已结算");
      expect(page.get('[data-testid="monitor-connection"]').text()).toBe("实时连接");
    } finally {
      page.unmount();
    }
    expect(fetch.mock.calls[2][1].signal.aborted).toBe(true);
    await vi.advanceTimersByTimeAsync(40_000);
    expect(fetch).toHaveBeenCalledTimes(3);
  });

  it("对局中心排除候场房，开局后显示对局及席位", async () => {
    const pinia = createPinia();
    setActivePinia(pinia);
    const stream = eventStream();
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(new Response(JSON.stringify({ admin_name: "运营", capabilities: ["platform:read"] })))
      .mockResolvedValueOnce(stream.response));
    await useAuthStore().login("s".repeat(43));
    const page = mount(MonitorPage, { props: { roomsOnly: true, matchesOnly: true }, global: { plugins: [pinia] } });
    try {
      stream.publish("waiting");
      await flushPromises();
      expect(page.find('[data-testid="monitor-room-6382"]').exists()).toBe(false);
      stream.publish("playing");
      await flushPromises();
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("对局中");
      expect(page.find('[data-testid="monitor-player-sample-account"]').exists()).toBe(true);
    } finally {
      page.unmount();
    }
  });

  it("收到无效玩家数据时保留最后一份有效快照并尝试重连", async () => {
    const pinia = createPinia();
    setActivePinia(pinia);
    const stream = eventStream();
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(Response.json({ admin_name: "运营", capabilities: ["platform:read"] }))
      .mockResolvedValueOnce(stream.response));
    await useAuthStore().login("s".repeat(43));
    const page = mount(MonitorPage, { global: { plugins: [pinia] } });
    try {
      stream.publish("playing");
      await flushPromises();
      stream.publishSnapshot({
        generated_at: "2026-11-14T03:00:01Z", services: [], lobbies: [], rooms: [], players: [null],
      });
      await flushPromises();
      expect(page.get('[data-testid="monitor-connection"]').attributes("data-state")).toBe("stale");
      expect(page.get('[data-testid="monitor-room-6382"]').text()).toContain("对局中");
      expect(page.get('[data-testid="monitor-player-sample-account"]').text()).toContain("小板凳");
    } finally {
      page.unmount();
    }
  });

  it("在筛选期间继续展示选中房间最新牌局，仅使用同一房间代次的玩家", async () => {
    const { page, stream, fetch } = await mountMahjongRoom(() => Response.json({ items: [] }), ["platform:read"]);
    try {
      await page.get('[data-testid="monitor-player-account-a"] button').trigger("click");
      await flushPromises();
      const inspector = () => page.get('[data-testid="mahjong-room-inspector"]');
      expect(inspector().text()).toContain("已准备");
      expect(inspector().text()).not.toContain("行动截止");
      expect(inspector().text()).not.toContain("最近出牌");
      expect(inspector().text()).not.toContain("轮转座位");
      expect(inspector().text()).not.toContain("上次房间玩家");
      expect(inspector().find('[data-testid="mahjong-admission-submit"]').exists()).toBe(false);

      await page.get('[data-testid="monitor-search"]').setValue("筛掉房间行");
      expect(page.find('[data-testid="monitor-room-6382"]').exists()).toBe(false);
      stream.publishSnapshot(mahjongSnapshot({ phase: "reaction" }));
      await flushPromises();
      expect(inspector().text()).toContain("接牌响应");
      expect(inspector().text()).toContain("2 / 4");
      expect(inspector().text()).toContain("五筒");
      expect(inspector().text()).toContain("等待重连");
      expect(inspector().get('[data-testid="mahjong-spectators"]').text()).toBe("2");
      expect(inspector().get('[data-testid="mahjong-action-deadline"]').attributes("datetime")).toBe(new Date(1794625224000).toISOString());
      expect(fetch.mock.calls.filter(([url]) => url.includes("/operations"))).toHaveLength(1);
    } finally {
      page.unmount();
    }
  });

  it("应用指令后等待 SSE 更新准入状态和操作记录，断线时禁用提交", async () => {
    let receipt: ReturnType<typeof pauseReceipt> | undefined;
    const { page, stream, fetch } = await mountMahjongRoom((url, options) => {
      if (url.pathname.endsWith("/operations")) return Response.json({ items: receipt ? [receipt] : [] });
      receipt = pauseReceipt(JSON.parse(options.body as string).request_id);
      return Response.json({ operation: receipt });
    });
    try {
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      const inspector = () => page.get('[data-testid="mahjong-room-inspector"]');
      const submit = () => inspector().get<HTMLButtonElement>('[data-testid="mahjong-admission-submit"]');
      expect(submit().element.disabled).toBe(true);
      await inspector().get("textarea").setValue("😀".repeat(161));
      expect(submit().element.disabled).toBe(true);
      await inspector().get("textarea").setValue("处理用户反馈");
      await inspector().get("form").trigger("submit");
      await flushPromises();

      const post = fetch.mock.calls.find(([url]) => url.endsWith("/6382/admission"));
      expect(post?.[1].method).toBe("POST");
      expect(JSON.parse(post![1].body as string)).toEqual({ room_generation: generation, expected_revision: 0,
        paused: true, reason: "处理用户反馈", request_id: expect.stringMatching(/^[\da-f-]{36}$/) });
      expect(submit().element.disabled).toBe(true);
      expect(inspector().get('[data-testid="mahjong-admission-state"]').text()).toBe("开放入座");
      expect(fetch.mock.calls.filter(([url]) => url.includes("/operations"))).toHaveLength(1);

      stream.publishSnapshot(mahjongSnapshot({ revision: 1, paused: true }));
      await flushPromises();
      expect(inspector().get('[data-testid="mahjong-admission-state"]').text()).toBe("暂停入座");
      expect(inspector().get('[data-testid="mahjong-room-operations"]').text()).toContain("处理用户反馈");
      const historyCalls = fetch.mock.calls.filter(([url]) => url.includes("/operations"));
      expect(historyCalls).toHaveLength(2);
      expect(new URL(historyCalls[1][0]).searchParams.get("room_generation")).toBe(generation);

      stream.end();
      await flushPromises();
      expect(inspector().get('[data-testid="mahjong-inspector-stale"]').text()).toContain("连接中断");
      expect(submit().element.disabled).toBe(true);
    } finally {
      page.unmount();
    }
  });

  it("传输失败时保留原请求，冲突后等待新快照，房号复用时清除选中状态", async () => {
    const requests: string[] = [];
    const { page, stream } = await mountMahjongRoom((url, options) => {
      if (url.pathname.endsWith("/operations")) return Response.json({ items: [] });
      requests.push(options.body as string);
      if (requests.length === 1) throw new TypeError("network lost");
      return Response.json({ error: "房间状态已更新" }, { status: 409 });
    });
    try {
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      const inspector = () => page.get('[data-testid="mahjong-room-inspector"]');
      await inspector().get("textarea").setValue("处理用户反馈");
      await inspector().get("form").trigger("submit");
      await flushPromises();
      await inspector().get('[data-testid="mahjong-admission-retry"]').trigger("click");
      await flushPromises();
      expect(requests).toHaveLength(2);
      expect(requests[1]).toBe(requests[0]);
      expect(inspector().get('[role="alert"]').text()).toContain("等待实时状态更新");
      expect(inspector().get<HTMLButtonElement>('[data-testid="mahjong-admission-submit"]').element.disabled).toBe(true);

      stream.publishSnapshot(mahjongSnapshot({ revision: 1, paused: true }));
      await flushPromises();
      expect(inspector().get<HTMLButtonElement>('[data-testid="mahjong-admission-submit"]').element.disabled).toBe(false);
      expect(inspector().get('[data-testid="mahjong-admission-submit"]').text()).toBe("恢复入座");

      stream.publishSnapshot(mahjongSnapshot({ roomGeneration: reusedGeneration }));
      await flushPromises();
      expect(page.find('[data-testid="mahjong-room-inspector"]').exists()).toBe(false);
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      expect(inspector().get<HTMLTextAreaElement>("textarea").element.value).toBe("");
    } finally {
      page.unmount();
    }
  });

  it("关闭被替换房间时取消在途操作和记录请求", async () => {
    const pending: ((response: Response) => void)[] = [];
    const { page, stream, fetch } = await mountMahjongRoom((url) => {
      if (url.searchParams.get("room_generation") === reusedGeneration) return Response.json({ items: [] });
      return new Promise<Response>((resolve) => { pending.push(resolve); });
    });
    try {
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      const inspector = () => page.get('[data-testid="mahjong-room-inspector"]');
      await inspector().get("textarea").setValue("处理用户反馈");
      await inspector().get("form").trigger("submit");
      expect(pending).toHaveLength(2);
      const historySignal = fetch.mock.calls[2][1].signal;
      const actionSignal = fetch.mock.calls[3][1].signal;

      stream.publishSnapshot(mahjongSnapshot({ roomGeneration: reusedGeneration }));
      await flushPromises();
      expect(historySignal?.aborted).toBe(true);
      expect(actionSignal?.aborted).toBe(true);
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      const oldReceipt = pauseReceipt(JSON.parse(fetch.mock.calls[3][1].body as string).request_id);
      pending[0](Response.json({ items: [oldReceipt] }));
      pending[1](Response.json({ operation: oldReceipt }));
      await flushPromises();
      expect(inspector().get('[data-testid="mahjong-admission-state"]').text()).toBe("开放入座");
      expect(inspector().get('[data-testid="mahjong-room-operations"]').text()).not.toContain("处理用户反馈");
    } finally {
      page.unmount();
    }
  });

  it("在实时快照同步同一修订前不显示提前返回的审计记录", async () => {
    const receipt = pauseReceipt("7417bb68-70d8-4d24-b316-22b15c34a379");
    const { page, stream } = await mountMahjongRoom(() => Response.json({ items: [receipt] }));
    try {
      await page.get('[data-testid="monitor-room-6382"] button').trigger("click");
      await flushPromises();
      const history = () => page.get('[data-testid="mahjong-room-operations"]').text();
      expect(history()).not.toContain("处理用户反馈");
      stream.publishSnapshot(mahjongSnapshot({ revision: 1, paused: true }));
      await flushPromises();
      expect(history()).toContain("处理用户反馈");
    } finally {
      page.unmount();
    }
  });
});
