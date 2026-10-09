import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises } from "@vue/test-utils";
import MatchesPage from "./MatchesPage.vue";
import { deferredResponse, jsonResponse, mockHTTP, mountPage, testMatch, testMatchDetail } from "../common/test-support";

// 验证持久化查询、分页及事件快照展示，不调用写接口或构造假回放。
enableAutoUnmount(afterEach);
const matchList = (items = [testMatch], total = items.length) => ({ items, total, page: 1, page_size: 20, data_source: "development" });
describe("对局中心", () => {
  beforeEach(() => { mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-match") ? testMatchDetail : matchList())); });
  afterEach(() => { vi.unstubAllGlobals(); });
  it("展示独立规则版本、中文状态和已结束对局时长", async () => {
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    for (const text of ["test-match", "1.0.0", "已结束", "1分5秒", "开发数据"]) expect(wrapper.text()).toContain(text);
    expect(wrapper.text()).not.toMatch(/强制结算|删除|修改/);
  });
  it("游戏和状态查询走服务端，筛选及重置返回第一页", async () => {
    mockHTTP((url) => jsonResponse(matchList([{ ...testMatch, match_id: url.searchParams.get("game_id") === "test-game" && url.searchParams.get("status") === "finished" && url.searchParams.get("page") === "1" ? "test-filtered-match" : "test-match" }], 45)));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    wrapper.findComponent({ name: "ElPagination" }).vm.$emit("current-change", 2);
    await flushPromises();
    await wrapper.get('[data-testid="match-game"]').setValue(" test-game ");
    wrapper.findComponent({ name: "ElSelect" }).vm.$emit("update:modelValue", "finished");
    await wrapper.get('[data-testid="match-search"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-filtered-match");
    await wrapper.get('[data-testid="match-reset"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).not.toContain("test-filtered-match");
  });
  it("分页参数和刷新保持当前页", async () => {
    mockHTTP((url) => jsonResponse(matchList([{ ...testMatch, match_id: `test-page-${url.searchParams.get("page")}` }], 45)));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    wrapper.findComponent({ name: "ElPagination" }).vm.$emit("current-change", 2);
    await flushPromises();
    expect(wrapper.text()).toContain("test-page-2");
    await wrapper.get('[data-testid="match-refresh"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-page-2");
  });
  it("编辑中的筛选不在翻页或刷新时偷偷提交", async () => {
    mockHTTP((url) => jsonResponse(url.searchParams.get("game_id")
      ? matchList([], 1)
      : matchList([{ ...testMatch, match_id: `test-applied-page-${url.searchParams.get("page")}` }], 45)));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="match-game"]').setValue("test-unsubmitted-game");
    wrapper.findComponent({ name: "ElPagination" }).vm.$emit("current-change", 2);
    await flushPromises();
    expect(wrapper.text()).toContain("test-applied-page-2");
    await wrapper.get('[data-testid="match-refresh"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-applied-page-2");
  });
  it("空对局集合与开发数据标识正常显示", async () => {
    mockHTTP(() => jsonResponse(matchList([])));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    expect(wrapper.text()).toContain("暂无对局数据");
    expect(wrapper.text()).toContain("开发数据");
  });
  it("未结束或异常时间不虚构确定时长", async () => {
    mockHTTP(() => jsonResponse(matchList([{ ...testMatch, finished_at: null, status: "playing" }, { ...testMatch, match_id: "test-invalid-time", started_at: "invalid" }])));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    expect(wrapper.text()).toContain("进行中");
    expect(wrapper.text()).toContain("待结束");
    expect(wrapper.text()).toContain("时间异常");
    expect(wrapper.text()).not.toContain("NaN");
  });
  it("详情展示已有事件和快照，JSON 作为文本显示", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-match") ? { ...testMatchDetail, events: [{ ...testMatchDetail.events[0], payload: { test_note: "<img src=x onerror=alert(1)>" } }] } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger("click");
    await flushPromises();
    await wrapper.get('#tab-events').trigger("click");
    expect(wrapper.text()).toContain("test_move");
    expect(wrapper.text()).toContain("<img src=x onerror=alert(1)>");
    expect(wrapper.find('.event-payload img').exists()).toBe(false);
    await wrapper.get('#tab-snapshots').trigger("click");
    expect(wrapper.text()).toContain("测试快照");
    expect(wrapper.text()).toContain("开发数据");
  });
  it("详情无事件或快照显示暂无记录，不生成回放", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-match") ? { ...testMatchDetail, events: [], snapshots: [] } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger("click");
    await flushPromises();
    await wrapper.get('#tab-events').trigger("click");
    expect(wrapper.text()).toContain("暂无事件记录");
    await wrapper.get('#tab-snapshots').trigger("click");
    expect(wrapper.text()).toContain("暂无快照记录");
    await wrapper.get('#tab-replay').trigger("click");
    expect(wrapper.text()).toContain("回放服务待接入");
  });
  it.each([404, 500, 0])("详情失败 %s 显示错误并可重试", async (status) => {
    mockHTTP((url) => { if (url.pathname.endsWith("/test-match")) { if (!status) throw new TypeError("offline"); return jsonResponse({ error: status === 404 ? "对局不存在" : "详情查询失败" }, status); } return jsonResponse(matchList()); });
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain(status === 404 ? "对局不存在" : status ? "详情查询失败" : "服务离线");
    expect(wrapper.find('.match-detail-data').exists()).toBe(false);
    mockHTTP(() => jsonResponse(testMatchDetail));
    await wrapper.get('[data-testid="query-retry"]').trigger("click");
    await flushPromises();
    expect(wrapper.find('.match-detail-data').exists()).toBe(true);
  });
  it.each([0, 500])("列表错误 %s 不混同空数据，重试恢复", async (status) => {
    mockHTTP(() => { if (!status) throw new TypeError("offline"); return jsonResponse({ error: "对局查询失败" }, status); });
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    expect(wrapper.text()).toContain(status ? "对局查询失败" : "服务离线");
    expect(wrapper.text()).not.toContain("暂无对局数据");
    mockHTTP(() => jsonResponse(matchList()));
    await wrapper.get('[data-testid="query-retry"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-match");
  });
  it("切换详情时迟到的旧响应不能污染新对局", async () => {
    const first = deferredResponse();
    mockHTTP((url) => {
      if (url.pathname.endsWith("/test-match")) return first.promise;
      if (url.pathname.endsWith("/test-second-match")) return jsonResponse({ ...testMatchDetail, summary: { ...testMatch, match_id: "test-second-match" }, events: [], snapshots: [] });
      return jsonResponse(matchList([testMatch, { ...testMatch, match_id: "test-second-match" }]));
    });
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger("click");
    // 通过页面入口切换选中对局，验证抽屉内部监听与请求代次。
    await wrapper.get('[data-testid="open-match-test-second-match"]').trigger("click");
    await flushPromises();
    first.resolve(jsonResponse(testMatchDetail));
    await flushPromises();
    expect(wrapper.get('.match-detail-data').text()).toContain("test-second-match");
    expect(wrapper.get('.match-detail-data').text()).not.toContain("test_move");
  });
  it("超过20条事件和快照可分别分页，未同时创建全部记录节点", async () => {
    const records = Array.from({ length: 21 }, (_, index) => index + 1);
    mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-match") ? {
      ...testMatchDetail,
      events: records.map((sequence) => ({ ...testMatchDetail.events[0], sequence, payload: { test_record: `test-event-${sequence}` } })),
      snapshots: records.map((sequence) => ({ ...testMatchDetail.snapshots[0], sequence, snapshot: { test_record: `test-snapshot-${sequence}` } })),
    } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger("click");
    await flushPromises();
    await wrapper.get('#tab-events').trigger("click");
    expect(wrapper.findAll('.event-payload')).toHaveLength(20);
    await wrapper.get('#pane-events .btn-next').trigger("click");
    await flushPromises();
    expect(wrapper.findAll('.event-payload')).toHaveLength(1);
    expect(wrapper.get('.event-payload').text()).toContain("test-event-21");
    await wrapper.get('#tab-snapshots').trigger("click");
    await wrapper.get('#pane-snapshots .btn-next').trigger("click");
    await flushPromises();
    expect(wrapper.get('#pane-snapshots').text()).toContain("test-snapshot-21");
    expect(wrapper.findAll('#pane-snapshots .readonly-record')).toHaveLength(1);
  });
});
