import { defineConfig } from "vite";
import vue from "@vitejs/plugin-vue";

// Vite（前端构建工具）配置：一期保持最小可运行设置。
export default defineConfig({
  plugins: [vue()],
  server: { port: 5173 },
});