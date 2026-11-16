import { afterEach, expect, it, vi } from "vitest";
import { flushPromises, mount } from "@vue/test-utils";
import { createPinia, setActivePinia } from "pinia";
import ElementPlus from "element-plus";
import { useAuthStore } from "../../app/store/auth";
import MahjongReportsPage from "./MahjongReportsPage.vue";

afterEach(() => vi.unstubAllGlobals());

it("审核员可筛选队列并确认举报结案", async () => {
  const pinia = createPinia();
  setActivePinia(pinia);
  const credential = "c".repeat(43);
  const report = {
    report_id: "r-1", match_id: "match-1", room_id: "0820", reporter_seat: 0, target_seat: 2,
    reason: "voice_abuse", created_at: "2026-11-14T10:00:00Z", status: "pending",
  };
  const fetch = vi.fn(async (url: string) => {
    if (url.endsWith("/session")) {
      return Response.json({ admin_name: "审核员", capabilities: ["mahjong:review"] });
    }
    if (url.endsWith("/resolve")) {
      return Response.json({ report: { ...report, status: "upheld" } });
    }
    const status = new URL(url).searchParams.get("status");
    return Response.json({ items: status === "pending" ? [report] : [], total: status === "pending" ? 1 : 0 });
  });
  vi.stubGlobal("fetch", fetch);
  await useAuthStore().login(credential);
  const wrapper = mount(MahjongReportsPage, {
    global: { plugins: [pinia, ElementPlus], stubs: { teleport: true } },
  });
  try {
    await flushPromises();
    expect(wrapper.text()).toContain("语音滥用");
    expect(wrapper.text()).toContain("1 → 3");
    expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("status=pending&limit=20&offset=0"), expect.anything());
    await wrapper.get('[data-testid="report-open-r-1"]').trigger("click");
    await wrapper.get("#report-disposition").setValue("upheld");
    await wrapper.get("#report-note").setValue("按队列处理");
    await wrapper.get("form").trigger("submit");
    await flushPromises();
    expect(fetch).toHaveBeenCalledWith(expect.stringContaining("/api/v1/admin/mahjong/reports/r-1/resolve"), expect.objectContaining({
      method: "POST", body: JSON.stringify({ status: "upheld", note: "按队列处理" }),
      headers: expect.objectContaining({ Authorization: "Bearer " + credential }),
    }));
    expect(wrapper.text()).toContain("处理结果已保存");
    await wrapper.get('[data-testid="report-status"]').setValue("dismissed");
    await flushPromises();
    expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("status=dismissed&limit=20&offset=0"), expect.anything());
    expect(wrapper.text()).toContain("没有符合条件的举报");
  } finally {
    wrapper.unmount();
  }
});
