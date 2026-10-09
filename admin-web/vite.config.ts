import { defineConfig, loadEnv, type ProxyOptions } from "vite";
import vue from "@vitejs/plugin-vue";
import AutoImport from "unplugin-auto-import/vite";
import Components from "unplugin-vue-components/vite";
import { ElementPlusResolver } from "unplugin-vue-components/resolvers";

/** 组件与样式按页面装载；开发代理保持认证 cookie 的同源请求。 */
export default defineConfig(({ mode }) => {
  const env = loadEnv(mode, process.cwd(), "");
  const target = env.VITE_API_PROXY_TARGET || "http://127.0.0.1:8080";
  const proxy: ProxyOptions = {
    target,
    changeOrigin: false,
    // 覆盖用户提交的来源头，后端仅在明确可信代理场景读取真实连接地址。
    configure(proxyServer) {
      proxyServer.on("proxyReq", (proxyRequest, request) => {
        proxyRequest.removeHeader("X-Real-IP");
        if (request.socket.remoteAddress) proxyRequest.setHeader("X-Real-IP", request.socket.remoteAddress);
      });
    },
  };
  return {
    plugins: [
      vue(),
      AutoImport({ dts: false, resolvers: [ElementPlusResolver({ directives: false })] }),
      Components({ dirs: [], dts: false, resolvers: [ElementPlusResolver({ directives: false })] }),
    ],
    server: {
      port: 5173,
      // 保留浏览器 Host，使后端 Origin 同源校验与代理请求一致。
      proxy: {
        "/api": proxy,
        "/health": proxy,
      },
    },
  };
});
