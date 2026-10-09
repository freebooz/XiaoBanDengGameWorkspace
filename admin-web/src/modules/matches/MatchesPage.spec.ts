import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises } from "@vue/test-utils";
import MatchesPage from "./MatchesPage.vue";
import { deferredResponse, jsonResponse, mockHTTP, mountPage, testMatch, testMatchDetail } from "../common/test-support";

// 验证持久化查询、分页及事件快照展示，不调用写接口或构造假回放。
enableAutoUnmount(afterEach);
const matchList = (items = [testMatch], total = items.length) => ({ items, total, page: 1, page_size: 20, data_source: "development" });
// 分页夹具仅返回本页，不用全量数组模拟服务端分页成功。
function pagedDetail(url: URL, total = 21) {
  const eventPage = Number(url.searchParams.get("event_page") ?? 1);
  const snapshotPage = Number(url.searchParams.get("snapshot_page") ?? 1);
  const pageSize = 20;
  const sequences = (page: number) => Array.from({ length: Math.max(0, Math.min(pageSize, total - (page - 1) * pageSize)) }, (_, index) => (page - 1) * pageSize + index + 1);
  return { ...testMatchDetail, event_page: eventPage, snapshot_page: snapshotPage, record_page_size: pageSize, event_total: total, snapshot_total: total,
    events: sequences(eventPage).map((sequence) => ({ ...testMatchDetail.events[0], sequence, payload: { test_record: `test-event-${sequence}` } })),
    snapshots: sequences(snapshotPage).map((sequence) => ({ ...testMatchDetail.snapshots[0], sequence, snapshot: { test_record: `test-snapshot-${sequence}` } })),
  };
}
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
  it("混合对局列表逐行标识开发source，详情不依赖整页来源标识", async () => {
    const matches = [
      { ...testMatch, match_id: 'test-live-match', source: 'production' },
      { ...testMatch, match_id: 'test-source-dev-match', source: 'development' },
    ];
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-source-dev-match')
      ? { ...testMatchDetail, data_source: 'partial', summary: matches[1] }
      : url.pathname.endsWith('/test-live-match') ? { ...testMatchDetail, data_source: 'partial', summary: matches[0] }
        : { ...matchList(matches), data_source: 'partial' }));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    expect(wrapper.get('.readonly-heading').text()).toContain('含开发数据');
    const rows = wrapper.findAll('.el-table__body tr');
    expect(rows.find((row) => row.text().includes('test-live-match'))!.text()).toContain('持久化记录');
    expect(rows.find((row) => row.text().includes('test-live-match'))!.find('.development-badge').exists()).toBe(false);
    expect(rows.find((row) => row.text().includes('test-source-dev-match'))!.find('.development-badge').exists()).toBe(true);
    await wrapper.get('[data-testid="open-match-test-live-match"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('.match-detail-data .development-badge').exists()).toBe(false);
    await wrapper.get('[data-testid="open-match-test-source-dev-match"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('.match-detail-data .development-badge').text()).toBe('开发数据');
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
    expect(wrapper.text()).toContain("暂无持久化快照，无法回放");
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
  it("事件和快照翻页请求各自页码，保留另一域页码和选中标签", async () => {
    const fetchMock = mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-match") ? pagedDetail(url) : matchList()));
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
    expect(wrapper.get('#tab-events').attributes('aria-selected')).toBe('true');
    await wrapper.get('#tab-snapshots').trigger("click");
    await wrapper.get('#pane-snapshots .btn-next').trigger("click");
    await flushPromises();
    expect(wrapper.get('#pane-snapshots').text()).toContain("test-snapshot-21");
    expect(wrapper.findAll('#pane-snapshots .readonly-record')).toHaveLength(1);
    const requests = fetchMock.mock.calls.map(([input]) => new URL(String(input))).filter((url) => url.pathname.endsWith('/test-match'));
    expect(requests.map((url) => [url.searchParams.get('event_page'), url.searchParams.get('snapshot_page'), url.searchParams.get('record_page_size')])).toEqual([['1', '1', '20'], ['2', '1', '20'], ['2', '2', '20']]);
  });

  it("展示持久化玩家、关联房间和结算结果，缺失字段保留待接入", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? { ...testMatchDetail, summary: { ...testMatch, room_id: 'test-origin-room', winner: 'red', result_reason: 'checkmate' }, players: [{ client_id: 'test-match-player', seat: 'red', joined_at: '2026-10-09T01:00:00Z' }] } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    const detail = wrapper.get('.match-detail-data');
    for (const text of ['test-origin-room', '红方', '将死', 'test-match-player', '入座时间', '客户端标识']) expect(detail.text()).toContain(text);
    expect(detail.text()).not.toContain('连接状态');
    expect(detail.text()).not.toContain('玩家明细与结算信息待接入');
    expect(detail.text()).not.toContain('认证账号');
  });

  it("旧详情缺少玩家和分页字段时不推测总量或结算", async () => {
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('.match-detail-data').text()).toContain('玩家明细待接入');
    expect(wrapper.get('.match-detail-data').text()).toContain('结算信息待接入');
    await wrapper.get('#tab-events').trigger('click');
    expect(wrapper.get('#pane-events').text()).toContain('分页信息待接入');
    expect(wrapper.find('#pane-events .el-pagination').exists()).toBe(false);
    await wrapper.get('#tab-replay').trigger('click');
    expect(wrapper.get('#pane-replay').text()).toContain('仅能查看本次返回的快照');
    expect(wrapper.get('#pane-replay').text()).toContain('测试快照');
  });

  it("部分结算字段缺失仍逐项标记待接入，未知结果编码原样显示", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? { ...testMatchDetail, summary: { ...testMatch, winner: 'test-unknown-seat' }, players: [] } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    const detail = wrapper.get('.match-detail-data');
    expect(detail.text()).toContain('test-unknown-seat');
    expect(detail.text()).toContain('结果原因待接入');
    expect(detail.text()).toContain('暂无持久化玩家');
    expect(detail.text()).not.toContain('玩家明细待接入');
  });

  it("分页元数据以服务端页码和大小为准，回放帧号不误当全量数组", async () => {
    const fetchMock = mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? { ...testMatchDetail, event_page: 2, snapshot_page: 2, record_page_size: 2, event_total: 5, snapshot_total: 3,
      snapshots: [{ ...testMatchDetail.snapshots[0], sequence: 99, snapshot: { test_record: 'test-authoritative-frame' } }],
    } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-replay').trigger('click');
    expect(wrapper.get('#pane-replay').text()).toContain('第 3 / 3 帧');
    expect(wrapper.get('#pane-replay').text()).toContain('序号 99');
    expect(wrapper.get('[data-testid="replay-next"]').attributes('disabled')).toBeDefined();
    await wrapper.get('#tab-events').trigger('click');
    await wrapper.get('#pane-events .btn-prev').trigger('click');
    await flushPromises();
    const request = new URL(String(fetchMock.mock.calls.at(-1)?.[0]));
    expect(request.searchParams.get('event_page')).toBe('1');
    expect(request.searchParams.get('snapshot_page')).toBe('2');
    expect(request.searchParams.get('record_page_size')).toBe('2');
  });

  it("非法分页元数据不生成全局计数或跨页回放", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? { ...testMatchDetail, event_page: 0, snapshot_page: 1, record_page_size: 0, event_total: -1, snapshot_total: 22 } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-events').trigger('click');
    expect(wrapper.get('#pane-events').text()).toContain('分页信息待接入');
    expect(wrapper.find('#pane-events .el-pagination').exists()).toBe(false);
    await wrapper.get('#tab-replay').trigger('click');
    expect(wrapper.get('#pane-replay').text()).toContain('仅能查看本次返回的快照');
    expect(wrapper.get('[data-testid="replay-next"]').attributes('disabled')).toBeDefined();
  });

  it("没有持久化快照的正式分页响应保持空态且不出现回放按钮", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? pagedDetail(url, 0) : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-replay').trigger('click');
    expect(wrapper.get('#pane-replay').text()).toContain('暂无持久化快照，无法回放');
    expect(wrapper.find('[data-testid="replay-next"]').exists()).toBe(false);
    expect(wrapper.get('#pane-replay').text()).not.toContain('分页信息待接入');
  });

  it("真实快照棋盘只读显示且未知结构仍可作为JSON查看", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? { ...pagedDetail(url, 2), snapshots: [
      { ...testMatchDetail.snapshots[0], sequence: 10, snapshot: { type: 'chess_state', turn: 'red', pieces: [{ id: 'test-red-general', type: 'general', color: 'red', x: 4, y: 9 }] } },
      { ...testMatchDetail.snapshots[0], sequence: 11, snapshot: { future_format: 'test-unknown-snapshot' } },
    ] } : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-replay').trigger('click');
    expect(wrapper.findAll('[data-testid="replay-board"] .snapshot-cell')).toHaveLength(90);
    expect(wrapper.get('[data-testid="replay-board"]').text()).toContain('帅');
    expect(wrapper.get('#pane-replay').text()).toContain('序号 10');
    await wrapper.get('[data-testid="replay-next"]').trigger('click');
    expect(wrapper.get('#pane-replay').text()).toContain('test-unknown-snapshot');
    expect(wrapper.find('[data-testid="replay-board"]').exists()).toBe(false);
    expect(wrapper.get('[data-testid="replay-next"]').attributes('disabled')).toBeDefined();
  });

  it("回放跨快照页向前向后请求真实数据并保持事件页码", async () => {
    const fetchMock = mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-match') ? pagedDetail(url) : matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-events').trigger('click');
    await wrapper.get('#pane-events .btn-next').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-replay').trigger('click');
    for (let index = 0; index < 20; index += 1) await wrapper.get('[data-testid="replay-next"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('#pane-replay').text()).toContain('test-snapshot-21');
    expect(wrapper.get('#pane-replay').text()).toContain('第 21 / 21 帧');
    await wrapper.get('[data-testid="replay-previous"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('#pane-replay').text()).toContain('test-snapshot-20');
    expect(wrapper.get('#tab-replay').attributes('aria-selected')).toBe('true');
    const request = new URL(String(fetchMock.mock.calls.at(-1)?.[0]));
    expect(request.searchParams.get('event_page')).toBe('2');
    expect(request.searchParams.get('snapshot_page')).toBe('1');
  });

  it("分页请求失败隐藏旧记录，重试保留请求页与标签", async () => {
    let fail = true;
    const fetchMock = mockHTTP((url) => url.pathname.endsWith('/test-match')
      ? url.searchParams.get('event_page') === '2' && fail ? jsonResponse({ error: 'test-record-page-error' }, 500) : jsonResponse(pagedDetail(url))
      : jsonResponse(matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-events').trigger('click');
    await wrapper.get('#pane-events .btn-next').trigger('click');
    await flushPromises();
    expect(wrapper.text()).toContain('test-record-page-error');
    expect(wrapper.find('.event-payload').exists()).toBe(false);
    fail = false;
    await wrapper.get('[data-testid="query-retry"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('.event-payload').text()).toContain('test-event-21');
    expect(wrapper.get('#tab-events').attributes('aria-selected')).toBe('true');
    expect(new URL(String(fetchMock.mock.calls.at(-1)?.[0])).searchParams.get('event_page')).toBe('2');
  });

  it("切换事件和快照页的迟到响应不能覆盖组合查询", async () => {
    const pending = deferredResponse();
    let delayedURL: URL | undefined;
    mockHTTP((url) => {
      if (!url.pathname.endsWith('/test-match')) return jsonResponse(matchList());
      if (url.searchParams.get('event_page') === '2' && url.searchParams.get('snapshot_page') === '1') { delayedURL = url; return pending.promise; }
      return jsonResponse(pagedDetail(url));
    });
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-events').trigger('click');
    wrapper.findAllComponents({ name: 'ElPagination' }).find((item) => item.attributes('data-testid') === 'event-pagination')!.vm.$emit('current-change', 2);
    await flushPromises();
    await wrapper.get('#tab-snapshots').trigger('click');
    wrapper.findAllComponents({ name: 'ElPagination' }).find((item) => item.attributes('data-testid') === 'snapshot-pagination')!.vm.$emit('current-change', 2);
    await flushPromises();
    pending.resolve(jsonResponse(pagedDetail(delayedURL!)));
    await flushPromises();
    expect(wrapper.get('#pane-snapshots').text()).toContain('test-snapshot-21');
    await wrapper.get('#tab-events').trigger('click');
    expect(wrapper.get('.event-payload').text()).toContain('test-event-21');
  });

  it("重新打开详情恢复第1页并发送默认20条，关闭后迟到记录失效", async () => {
    const pending = deferredResponse();
    const fetchMock = mockHTTP((url) => url.pathname.endsWith('/test-match')
      ? url.searchParams.get('event_page') === '2' ? pending.promise : jsonResponse(pagedDetail(url))
      : jsonResponse(matchList()));
    const wrapper = mountPage(MatchesPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    await wrapper.get('#tab-events').trigger('click');
    await wrapper.get('#pane-events .btn-next').trigger('click');
    wrapper.findComponent({ name: 'ElDrawer' }).vm.$emit('update:modelValue', false);
    await flushPromises();
    pending.resolve(jsonResponse({ ...testMatchDetail, events: [{ ...testMatchDetail.events[0], payload: { test_record: 'test-stale-closed' } }] }));
    await flushPromises();
    expect(wrapper.find('.match-detail-data').exists()).toBe(false);
    await wrapper.get('[data-testid="open-match-test-match"]').trigger('click');
    await flushPromises();
    const request = new URL(String(fetchMock.mock.calls.at(-1)?.[0]));
    expect(request.searchParams.get('event_page')).toBe('1');
    expect(request.searchParams.get('snapshot_page')).toBe('1');
    expect(request.searchParams.get('record_page_size')).toBe('20');
    expect(wrapper.get('#tab-summary').attributes('aria-selected')).toBe('true');
    expect(wrapper.text()).not.toContain('test-stale-closed');
  });
});
