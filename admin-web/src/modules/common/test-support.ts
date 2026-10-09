import { vi } from "vitest";
import { mount, type VueWrapper } from "@vue/test-utils";
import ElementPlus from "element-plus";
import type { Component } from "vue";
import type { GameDescriptor, MatchDetail, MatchSummary, RoomSummary } from "../../services/api/types";

/** 回归测试专用夹具：标识均含 test，不进入页面代码或真实接口。 */
export const testGames: GameDescriptor[] = [
  { product_id: "xbd_chinese_chess", game_category: "board", game_id: "chinese_chess", rule_set_id: "standard", rule_version: "1.0.0", name: "小板凳象棋", enabled: true },
  { product_id: "xbd_mahjong", game_category: "mahjong", game_id: "mahjong", rule_set_id: "guiyang", rule_version: "1.0.0", name: "小板凳麻将·贵阳麻将", enabled: false },
];
export const testRoom: RoomSummary = {
  room_id: "test-room", product_id: "xbd_chinese_chess", game_id: "chinese_chess", rule_set_id: "standard", rule_version: "1.0.0", state: "waiting", created_at: "2026-10-09T01:00:00Z", duration_seconds: 65, data_source: "development",
};
export const testMatch: MatchSummary = {
  match_id: "test-match", product_id: "xbd_chinese_chess", game_id: "chinese_chess", rule_set_id: "standard", rule_version: "1.0.0", status: "finished", created_at: "2026-10-09T01:00:00Z", started_at: "2026-10-09T01:00:00Z", finished_at: "2026-10-09T01:01:05Z",
};
export const testMatchDetail: MatchDetail = {
  summary: testMatch, data_source: "development",
  events: [{ sequence: 1, event_type: "test_move", payload: { test_note: "测试事件" }, created_at: "2026-10-09T01:00:10Z" }],
  snapshots: [{ sequence: 1, snapshot: { test_note: "测试快照" }, created_at: "2026-10-09T01:00:10Z" }],
};

/** 仅替代网络边界，页面仍使用真实接口客户端和 Element Plus 组件。 */
export function jsonResponse(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "Content-Type": "application/json" } });
}
export function mockHTTP(handler: (url: URL) => Response | Promise<Response>) {
  const fetchMock = vi.fn((input: string | URL | Request) => handler(new URL(String(input))));
  vi.stubGlobal("fetch", fetchMock);
  return fetchMock;
}
export function mountPage(component: Component): VueWrapper {
  return mount(component, { attachTo: document.body, global: { plugins: [ElementPlus] } });
}

/** 延迟响应用于验证查询并发与抽屉切换，避免依赖真实计时。 */
export function deferredResponse() {
  let resolve!: (response: Response) => void;
  const promise = new Promise<Response>((done) => { resolve = done; });
  return { promise, resolve };
}
