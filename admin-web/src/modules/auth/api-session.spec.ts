import { afterEach, describe, expect, it, vi } from "vitest";
import { apiGet } from "../../services/api/client";

// 请求约定必须兼容同源部署，并允许明确配置接口根地址。
describe("管理员 cookie 请求约定", () => {
  afterEach(() => { vi.unstubAllGlobals(); vi.unstubAllEnvs(); });
  it("默认同源并携带 HttpOnly 会话 cookie", async () => {
    vi.stubEnv("VITE_API_BASE_URL", "");
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}"));
    vi.stubGlobal("fetch", fetchMock);
    await apiGet("/api/v1/admin/users", { page: 2 });
    const [input, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(new URL(input).origin).toBe(window.location.origin);
    expect(new URL(input).searchParams.get("page")).toBe("2");
    expect(options.credentials).toBe("include");
  });
  it("明确配置接口地址时保持路径和 cookie 请求", async () => {
    vi.stubEnv("VITE_API_BASE_URL", "https://api.test/");
    const fetchMock = vi.fn().mockResolvedValue(new Response("{}"));
    vi.stubGlobal("fetch", fetchMock);
    await apiGet("/api/v1/admin/users");
    const [input, options] = fetchMock.mock.calls[0] as unknown as [string, RequestInit];
    expect(input).toBe("https://api.test/api/v1/admin/users");
    expect(options.credentials).toBe("include");
  });
});
