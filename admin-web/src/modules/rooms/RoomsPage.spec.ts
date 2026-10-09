import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises } from "@vue/test-utils";
import RoomsPage from "./RoomsPage.vue";
import { deferredResponse, jsonResponse, mockHTTP, mountPage, testRoom } from "../common/test-support";

// 网络边界之外使用真实组件，覆盖筛选、详情、失败重试和开发数据边界。
enableAutoUnmount(afterEach);
const roomList = (items = [testRoom]) => ({ items, total: items.length, data_source: "partial" });
describe("房间中心", () => {
  beforeEach(() => { mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-room") ? testRoom : roomList())); });
  afterEach(() => { vi.unstubAllGlobals(); });
  it("展示真实字段、中文状态、时长和行级开发标识", async () => {
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    for (const text of ["test-room", "standard", "1.0.0", "等待中", "1分5秒", "开发数据"]) expect(wrapper.text()).toContain(text);
    expect(wrapper.text()).not.toMatch(/踢人|关闭房间|删除/);
  });
  it("四个查询条件传给已有接口并显示筛选结果", async () => {
    mockHTTP((url) => jsonResponse(url.searchParams.get("product_id") === "test-product" && url.searchParams.get("game_id") === "test-game" && url.searchParams.get("rule_set_id") === "test-rule" && url.searchParams.get("state") === "waiting" ? roomList([{ ...testRoom, room_id: "test-filtered-room" }]) : roomList()));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    for (const [field, value] of [["product", " test-product "], ["game", "test-game"], ["rule", "test-rule"]]) await wrapper.get(`[data-testid="room-${field}"]`).setValue(value);
    wrapper.findComponent({ name: "ElSelect" }).vm.$emit("update:modelValue", "waiting");
    await wrapper.get('[data-testid="room-search"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-filtered-room");
    await wrapper.get('[data-testid="room-reset"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).not.toContain("test-filtered-room");
  });
  it("空集合显示房间空态", async () => {
    mockHTTP(() => jsonResponse(roomList([])));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    expect(wrapper.text()).toContain("暂无房间数据");
  });
  it("开发空集合仍显示来源标识", async () => {
    mockHTTP(() => jsonResponse({ ...roomList([]), data_source: "development" }));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    expect(wrapper.text()).toContain("开发数据");
  });
  it("混合列表按source标识开发行且详情兼容开发source", async () => {
    const rooms = [
      { ...testRoom, room_id: 'test-live-room', data_source: 'partial' as const, source: 'production' },
      { ...testRoom, room_id: 'test-source-dev-room', data_source: 'partial' as const, source: 'development' },
    ];
    mockHTTP((url) => jsonResponse(url.pathname.endsWith('/test-source-dev-room') ? rooms[1] : url.pathname.endsWith('/test-live-room') ? rooms[0] : roomList(rooms)));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    expect(wrapper.get('.readonly-heading').text()).toContain('含开发数据');
    const rows = wrapper.findAll('.el-table__body tr');
    expect(rows.find((row) => row.text().includes('test-live-room'))!.text()).toContain('服务节点');
    expect(rows.find((row) => row.text().includes('test-live-room'))!.find('.development-badge').exists()).toBe(false);
    expect(rows.find((row) => row.text().includes('test-source-dev-room'))!.find('.development-badge').exists()).toBe(true);
    await wrapper.get('[data-testid="open-room-test-live-room"]').trigger('click');
    await flushPromises();
    expect(wrapper.find('.room-detail-data .development-badge').exists()).toBe(false);
    await wrapper.get('[data-testid="open-room-test-source-dev-room"]').trigger('click');
    await flushPromises();
    expect(wrapper.get('.room-detail-data .development-badge').text()).toBe('开发数据');
  });
  it("详情重新查询已有接口，未接入信息不伪造", async () => {
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("房间详情");
    expect(wrapper.text()).toContain("玩家座位与连接状态待接入");
    expect(wrapper.text()).toContain("1分5秒");
    expect(wrapper.get('.room-detail-data').text()).toContain("关联对局待接入");
  });
  it("显示服务端玩家座位和连接人数，客户端标识不冒充认证账号", async () => {
    const room = { ...testRoom, connected_count: 1, match_id: "test-room-match", players: [
      { client_id: "test-client-red", seat: "red", connected: true },
      { client_id: "test-client-black", seat: "black", connected: false },
    ] };
    mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-room") ? room : roomList([room])));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    expect(wrapper.text()).toContain("1 人在线");
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    await flushPromises();
    const detail = wrapper.get('.room-detail-data');
    for (const text of ["test-client-red", "test-client-black", "红方", "黑方", "已连接", "已断开", "test-room-match", "客户端标识"]) expect(detail.text()).toContain(text);
    expect(detail.text()).not.toContain("玩家座位与连接状态待接入");
    expect(detail.text()).not.toContain("认证账号");
  });
  it("空玩家数组与尚未接入玩家字段分别展示", async () => {
    mockHTTP((url) => jsonResponse(url.pathname.endsWith("/test-room") ? { ...testRoom, players: [], connected_count: 0 } : roomList()));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("暂无玩家");
    expect(wrapper.get('.room-detail-data').text()).toContain("0 人在线");
    expect(wrapper.text()).not.toContain("玩家座位与连接状态待接入");
  });
  it.each([404, 500, 0])("详情失败 %s 不展示旧详情并可重试", async (status) => {
    mockHTTP((url) => { if (url.pathname.endsWith("/test-room")) { if (!status) throw new TypeError("offline"); return jsonResponse({ error: status === 404 ? "房间不存在" : "详情查询失败" }, status); } return jsonResponse(roomList()); });
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain(status === 404 ? "房间不存在" : status === 0 ? "服务离线" : "详情查询失败");
    expect(wrapper.find('.room-detail-data').exists()).toBe(false);
    mockHTTP(() => jsonResponse(testRoom));
    await wrapper.get('[data-testid="query-retry"]').trigger("click");
    await flushPromises();
    expect(wrapper.find('.room-detail-data').exists()).toBe(true);
  });
  it.each([0, 500])("列表失败 %s 与空数据区分，刷新后恢复", async (status) => {
    mockHTTP(() => { if (!status) throw new TypeError("offline"); return jsonResponse({ error: "房间查询失败" }, status); });
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    expect(wrapper.text()).toContain(status ? "房间查询失败" : "服务离线");
    expect(wrapper.text()).not.toContain("暂无房间数据");
    mockHTTP(() => jsonResponse(roomList()));
    await wrapper.get('[data-testid="room-refresh"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("test-room");
  });
  it("迟到的旧查询不能覆盖最新筛选结果", async () => {
    const first = deferredResponse();
    let count = 0;
    mockHTTP(() => ++count === 1 ? first.promise : jsonResponse(roomList([{ ...testRoom, room_id: "test-new-room" }])));
    const wrapper = mountPage(RoomsPage);
    await wrapper.get('[data-testid="room-search"]').trigger("click");
    await flushPromises();
    first.resolve(jsonResponse(roomList()));
    await flushPromises();
    expect(wrapper.text()).toContain("test-new-room");
    expect(wrapper.find('[data-testid="open-room-test-room"]').exists()).toBe(false);
  });
  it("关闭详情后迟到响应失效，重新打开同房间会重新查询", async () => {
    const pending = deferredResponse();
    let details = 0;
    mockHTTP((url) => url.pathname.endsWith("/test-room")
      ? ++details === 1 ? pending.promise : jsonResponse({ ...testRoom, duration_seconds: 130, state: "playing" })
      : jsonResponse(roomList()));
    const wrapper = mountPage(RoomsPage);
    await flushPromises();
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    wrapper.findComponent({ name: "ElDrawer" }).vm.$emit("update:modelValue", false);
    await flushPromises();
    pending.resolve(jsonResponse(testRoom));
    await flushPromises();
    expect(wrapper.find('.room-detail-data').exists()).toBe(false);
    await wrapper.get('[data-testid="open-room-test-room"]').trigger("click");
    await flushPromises();
    expect(wrapper.get('.room-detail-data').text()).toContain("2分10秒");
    expect(wrapper.get('.room-detail-data').text()).toContain("进行中");
  });
});
