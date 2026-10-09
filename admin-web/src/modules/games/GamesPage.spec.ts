import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import { enableAutoUnmount, flushPromises } from "@vue/test-utils";
import GamesPage from "./GamesPage.vue";
import { jsonResponse, mockHTTP, mountPage, testGames } from "../common/test-support";

// 验证真实目录展示和本地筛选，不把夹具当成线上运营数据。
enableAutoUnmount(afterEach);
describe("游戏中心", () => {
  beforeEach(() => { mockHTTP(() => jsonResponse({ games: testGames })); });
  afterEach(() => { vi.unstubAllGlobals(); });
  it("产品、游戏、规则集和版本独立展示且只有只读入口", async () => {
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    for (const value of ["小板凳象棋", "xbd_chinese_chess", "chinese_chess", "standard", "guiyang", "1.0.0", "已启用", "已停用"]) {
      expect(wrapper.text()).toContain(value);
    }
    expect(wrapper.text()).not.toMatch(/删除|新增|编辑|上架|下架/);
  });
  it("产品和启用状态筛选生效，重置恢复全部目录", async () => {
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    await wrapper.get('[data-testid="game-product"]').setValue(" xbd_mahjong ");
    wrapper.findAllComponents({ name: "ElSelect" })[1].vm.$emit("update:modelValue", "disabled");
    await wrapper.get('[data-testid="game-search"]').trigger("click");
    expect(wrapper.text()).toContain("小板凳麻将·贵阳麻将");
    expect(wrapper.text()).not.toContain("小板凳象棋");
    await wrapper.get('[data-testid="game-reset"]').trigger("click");
    expect(wrapper.text()).toContain("小板凳象棋");
  });
  it("类别筛选和无匹配条件显示筛选空态", async () => {
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    wrapper.findAllComponents({ name: "ElSelect" })[0].vm.$emit("update:modelValue", "mahjong");
    await wrapper.get('[data-testid="game-search"]').trigger("click");
    expect(wrapper.text()).not.toContain("小板凳象棋");
    await wrapper.get('[data-testid="game-product"]').setValue("不存在");
    await wrapper.get('[data-testid="game-search"]').trigger("click");
    expect(wrapper.text()).toContain("暂无匹配游戏");
  });
  it("空目录不伪造产品", async () => {
    mockHTTP(() => jsonResponse({ games: [] }));
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    expect(wrapper.text()).toContain("暂无游戏目录");
    expect(wrapper.text()).not.toContain("小板凳象棋");
  });
  it("刷新重新读取目录", async () => {
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    mockHTTP(() => jsonResponse({ games: [] }));
    await wrapper.get('[data-testid="game-refresh"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("暂无游戏目录");
    expect(wrapper.text()).not.toContain("小板凳象棋");
  });
  it("同产品多规则连续筛选后不残留重复表格行", async () => {
    const a1 = { ...testGames[0], name: "测试规则A1", product_id: "test-a", rule_set_id: "test-rule-1", enabled: false };
    const a2 = { ...a1, name: "测试规则A2", rule_set_id: "test-rule-2", enabled: true };
    mockHTTP(() => jsonResponse({ games: [a1, { ...a2, product_id: "test-b", name: "测试规则B1" }, a2, { ...a2, product_id: "test-c", name: "测试规则C1" }] }));
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    await wrapper.get('[data-testid="game-product"]').setValue("test-a");
    await wrapper.get('[data-testid="game-search"]').trigger("click");
    expect(wrapper.findAll('.el-table__body tbody tr')).toHaveLength(2);
    await wrapper.get('[data-testid="game-product"]').setValue("");
    wrapper.findAllComponents({ name: "ElSelect" })[1].vm.$emit("update:modelValue", "enabled");
    await wrapper.get('[data-testid="game-search"]').trigger("click");
    expect(wrapper.findAll('.el-table__body tbody tr')).toHaveLength(3);
    expect(wrapper.text().match(/测试规则A2/g)).toHaveLength(1);
    expect(wrapper.text()).not.toContain("测试规则A1");
  });
  it.each(["offline", "http"])("%s 错误保留页面并支持重试", async (mode) => {
    mockHTTP(() => { if (mode === "offline") throw new TypeError("offline"); return jsonResponse({ error: "目录查询失败" }, 500); });
    const wrapper = mountPage(GamesPage);
    await flushPromises();
    expect(wrapper.text()).toContain(mode === "offline" ? "服务离线" : "目录查询失败");
    expect(wrapper.text()).not.toContain("暂无游戏目录");
    mockHTTP(() => jsonResponse({ games: testGames }));
    await wrapper.get('[data-testid="query-retry"]').trigger("click");
    await flushPromises();
    expect(wrapper.text()).toContain("小板凳象棋");
  });
});
