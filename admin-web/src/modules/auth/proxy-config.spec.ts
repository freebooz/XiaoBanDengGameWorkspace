// @vitest-environment node
// 构建工具依赖 Node 原生类型，配置回归使用 Node 环境。
import { afterEach, describe, expect, it, vi } from "vitest";
import configuration from "../../../vite.config";
import { createServer as createHTTPServer } from "node:http";
import { createServer as createViteServer } from "vite";

// 后端以浏览器 Origin 和 Host 校验同源，开发代理必须保留原始 Host。
describe("管理员开发代理的同源认证", () => {
  afterEach(() => { vi.unstubAllEnvs(); });
  it("API 和健康检查使用默认服务地址且保留浏览器 Host", () => {
    vi.stubEnv("VITE_API_PROXY_TARGET", "");
    const config = configuration({ command: "serve", mode: "development" });
    expect(config.server?.proxy?.["/api"]).toMatchObject({ target: "http://127.0.0.1:8080", changeOrigin: false });
    expect(config.server?.proxy?.["/health"]).toMatchObject({ target: "http://127.0.0.1:8080", changeOrigin: false });
  });
  it("真实开发代理丢弃伪造的 X-Real-IP 并以连接地址覆盖", async () => {
    const backend = createHTTPServer((request, response) => {
      response.setHeader("Content-Type", "application/json");
      response.end(JSON.stringify({ realIP: request.headers["x-real-ip"], host: request.headers.host }));
    });
    await new Promise<void>((resolve) => { backend.listen(0, "127.0.0.1", resolve); });
    const backendAddress = backend.address();
    if (!backendAddress || typeof backendAddress === "string") throw new Error("测试服务未监听端口");
    const config = configuration({ command: "serve", mode: "development" });
    const apiProxy = config.server?.proxy?.["/api"];
    if (typeof apiProxy !== "object" || apiProxy === null) throw new Error("测试配置未提供 API 代理对象");
    const vite = await createViteServer({ configFile: false, logLevel: "silent", plugins: [], appType: "custom",
      server: { host: "127.0.0.1", port: 0, proxy: { "/api": { ...apiProxy, target: `http://127.0.0.1:${backendAddress.port}` } } } });
    try {
      await vite.listen();
      const viteAddress = vite.httpServer?.address();
      if (!viteAddress || typeof viteAddress === "string") throw new Error("测试代理未监听端口");
      const response = await fetch(`http://127.0.0.1:${viteAddress.port}/api/v1/admin/auth/session`, { headers: { "X-Real-IP": "203.0.113.5" } });
      const payload = await response.json() as { realIP: string; host: string };
      expect(payload.realIP).toBe("127.0.0.1");
      expect(payload.host).toBe(`127.0.0.1:${viteAddress.port}`);
    } finally {
      await vite.close();
      await new Promise<void>((resolve, reject) => { backend.close((error) => { if (error) reject(error); else resolve(); }); });
    }
  });

  it("显式代理目标同时应用到 API 和健康检查", () => {
    vi.stubEnv("VITE_API_PROXY_TARGET", "http://127.0.0.1:8099");
    const config = configuration({ command: "serve", mode: "development" });
    expect(config.server?.proxy?.["/api"]).toMatchObject({ target: "http://127.0.0.1:8099", changeOrigin: false });
    expect(config.server?.proxy?.["/health"]).toMatchObject({ target: "http://127.0.0.1:8099", changeOrigin: false });
  });
});
