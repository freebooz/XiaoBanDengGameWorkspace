import { flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import { afterEach, describe, expect, it, vi } from "vitest";
import { useAuthStore } from "../../app/store/auth";
import MonitorPage from "./MonitorPage.vue";

function eventStream() {
  let output!: ReadableStreamDefaultController<Uint8Array>;
  const body = new ReadableStream<Uint8Array>({ start(controller) { output = controller; } });
  return {
    response: new Response(body, { headers: { "Content-Type": "text/event-stream" } }),
    publish(status: string) {
      const at = "2026-11-14T03:00:00Z";
      const snapshot = {
        generated_at: at, services: [{ id: "api", status: "ok", checked_at: at }],
        lobbies: [{ game_id: "mahjong", product_id: "xbd_mahjong", online_players: 4, waiting_players: 0, rooms: 1 }],
        rooms: [{ game_id: "mahjong", product_id: "xbd_mahjong", room_id: "6382", status, kind: "friend",
          rule_set_id: "guiyang", rule_version: "2.0.0", capacity: 4, players: 4, connected_players: 4, updated_at: at }],
        players: [{ game_id: "mahjong", room_id: "6382", room_status: status, account_id: "sample-account", status,
          connected: true, seat: 0, display_name: "小板凳" }],
      };
      output.enqueue(new TextEncoder().encode(`event: snapshot\ndata: ${JSON.stringify(snapshot)}\n\n`));
    },
    end() { output.close(); },
  };
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
});
