import { afterEach, describe, expect, it, vi } from "vitest";
import { createPinia, setActivePinia } from "pinia";
import { useAuthStore } from "../../app/store/auth";
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
    vi.stubGlobal("fetch", vi.fn().mockResolvedValue(
        new Response(JSON.stringify({ error: "数据库暂不可用" }), {
          status: 500,
          headers: { "Content-Type": "application/json" },
        }),
    ));

    await expect(apiGet("/api/v1/admin/overview")).rejects.toMatchObject({
      name: "ApiError",
      status: 500,
      message: "数据库暂不可用",
    } satisfies Partial<ApiError>);
  });

  it("拒绝状态为 200 的 HTML 页面和空 JSON 响应", async () => {
    vi.stubGlobal("fetch", vi.fn()
      .mockResolvedValueOnce(new Response("<!doctype html><title>管理平台</title>"))
      .mockResolvedValueOnce(Response.json(null)));

    for (let attempt = 0; attempt < 2; attempt++) {
      await expect(apiGet("/api/v1/admin/overview")).rejects.toMatchObject({ status: 502 });
    }
  });

  it("用户接口空数据保持空数组且不生成虚假用户", async () => {
    setActivePinia(createPinia());
    const fetch = vi.fn().mockResolvedValueOnce(
      new Response(JSON.stringify({ admin_name: "运营", capabilities: ["platform:read"] })),
    ).mockResolvedValue(
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
      );
    vi.stubGlobal("fetch", fetch);

    const credential = "b".repeat(43);
    await useAuthStore().login(credential);
    const result = await adminApi.users({ page: 1, page_size: 20 });
    expect(result.items).toEqual([]);
    expect(result.total).toBe(0);
    expect(result.data_source).toBe("partial");
    expect(fetch).toHaveBeenLastCalledWith(expect.stringContaining("/api/v1/admin/users"), expect.objectContaining({
      headers: expect.objectContaining({ Authorization: "Bearer " + credential }), cache: "no-store", redirect: "error",
    }));
  });

  it("显式开发数据提供者必须标记development", async () => {
    const provider = createDevelopmentAdminProvider();
    const result = await provider.users({ page: 1, page_size: 20 });
    expect(result.items).toEqual([]);
    expect(result.data_source).toBe("development");
  });
});
