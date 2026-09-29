import { createApp } from "vue";
import ElementPlus from "element-plus";
import "element-plus/dist/index.css";
import App from "./App.vue";
import "./styles.css";

// main.ts（前端入口）只负责注册Vue和Element Plus，业务页面由App.vue统一承载。
createApp(App).use(ElementPlus).mount("#app");