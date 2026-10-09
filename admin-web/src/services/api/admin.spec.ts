import { afterEach, describe, expect, it, vi } from "vitest";
import {
  ApiError,
  apiGet,
} from "./client";
import {
  adminApi,
  createDevelopmentAdminProvider,
} from "./admin";

describe("运营后台API服务层", () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it("HTTP错误转换为结构化ApiError", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: "数据库暂不可用" }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }),
      ),
    );

    await expect(apiGet("/api/v1/admin/overview")).rejects.toMatchObject({
      name: "ApiError",
      status: 500,
      message: "数据库暂不可用",
    } satisfies Partial<ApiError>);
  });

  it("用户接口空数据保持空数组且不生成虚假用户", async () => {
    vi.stubGlobal(
      "fetch",
      vi.fn().mockResolvedValue(
        new Response(
          JSON.stringify({
            items: [],
            total: 0,
            page: 1,
            page_size: 20,
            data_source: "partial",
          }),
          { status: 200, headers: { "Content-Type": "application/json" } },
        ),
      ),
    );

    const result = await adminApi.users({ page: 1, page_size: 20 });
    expect(result.items).toEqual([]);
    expect(result.total).toBe(0);
    expect(result.data_source).toBe("partial");
  });

  it("显式开发数据提供者必须标记development", async () => {
    const provider = createDevelopmentAdminProvider();
    const result = await provider.users({ page: 1, page_size: 20 });
    expect(result.items).toEqual([]);
    expect(result.data_source).toBe("development");
  });

  it("对局记录查询保留原详情路径并发送独立分页参数", async () => {
    let requested: URL | undefined;
    vi.stubGlobal("fetch", vi.fn((input: string) => {
      requested = new URL(input);
      return Promise.resolve(new Response(JSON.stringify({ events: [], snapshots: [] }), { status: 200 }));
    }));
    await adminApi.matchDetail("test/match", { event_page: 2, snapshot_page: 3, record_page_size: 20 });
    expect(requested?.pathname).toBe("/api/v1/admin/matches/test%2Fmatch");
    expect(requested?.searchParams.get("event_page")).toBe("2");
    expect(requested?.searchParams.get("snapshot_page")).toBe("3");
    expect(requested?.searchParams.get("record_page_size")).toBe("20");
  });
});
