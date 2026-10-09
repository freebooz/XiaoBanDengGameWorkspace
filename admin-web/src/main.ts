import { createApp } from "vue";
import { createPinia } from "pinia";
import { ElLoading } from "element-plus/es/components/loading/index";
import "element-plus/es/components/loading/style/css";
import App from "./App.vue";
import { router } from "./app/router";
import "./styles.css";

// 入口只注册框架与必要的加载指令，Element Plus 组件和样式由构建插件按需引入。
const app = createApp(App);
app.use(createPinia());
app.directive("loading", ElLoading.directive);
app.use(router);
app.mount("#app");
