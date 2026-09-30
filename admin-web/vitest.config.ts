import { defineConfig } from "vitest/config";
import vue from "@vitejs/plugin-vue";

// vitest.config.ts（前端测试配置）统一启用 Vue SFC 与 jsdom 浏览器环境。
export default defineConfig({
  plugins: [vue()],
  test: {
    environment: "jsdom",
    globals: true,
  },
});
