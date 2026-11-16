import { defineComponent, h } from "vue";
import {
  createMemoryHistory,
  createRouter,
  createWebHistory,
  type RouteRecordRaw,
  type Router,
} from "vue-router";
import { MAHJONG_REVIEW, PLATFORM_READ, WALLET_GRANT_EGGS, useAuthStore } from "../store/auth";

const TemporaryPage = defineComponent({
  name: "TemporaryPage",
  setup: () => () => h("div", { class: "route-placeholder" }, "模块初始化中"),
});
const AccessPage = defineComponent({
  setup: () => () => h("section", { class: "route-placeholder", role: "status" }, "当前账号没有可用的后台权限"),
});

/** routeRecords（路由表）固定一期核心 URL，页面模块将在后续任务逐项替换。 */
export const routeRecords: RouteRecordRaw[] = [
  {
    path: "/login",
    name: "login",
    component: () => import("../../modules/auth/LoginPage.vue"),
    meta: { title: "管理员登录", public: true },
  },
  {
    path: "/",
    component: () => import("../../layouts/AdminLayout.vue"),
    meta: { requiresAuth: true },
    children: [
      { path: "", redirect: "/dashboard" },
      {
        path: "access",
        name: "access",
        component: AccessPage,
        meta: { title: "权限", requiresAuth: true },
      },
      {
        path: "dashboard",
        name: "dashboard",
        component: () => import("../../modules/dashboard/DashboardPage.vue"),
        meta: { title: "综合工作台", description: "平台运行状态与一期产品总览", requiresAuth: true },
      },
      {
        path: "monitor",
        name: "monitor",
        component: () => import("../../modules/monitor/MonitorPage.vue"),
        meta: { title: "实时监视", description: "服务器健康、游戏大厅、房间与玩家", requiresAuth: true, capability: PLATFORM_READ },
      },
      {
        path: "users",
        name: "users",
        component: () => import("../../modules/users/UsersPage.vue"),
        meta: { title: "用户中心", description: "统一账号、身份绑定与游戏档案", requiresAuth: true },
      },
      {
        path: "games/products",
        name: "games-products",
        component: TemporaryPage,
        meta: { title: "游戏中心", description: "产品、游戏、规则集与规则版本", requiresAuth: true },
      },
      {
        path: "rooms",
        name: "rooms",
        component: () => import("../../modules/monitor/MonitorPage.vue"),
        props: { roomsOnly: true },
        meta: { title: "房间中心", description: "实时房间、牌局阶段及玩家连接状态", requiresAuth: true, capability: PLATFORM_READ },
      },
      {
        path: "matches",
        name: "matches",
        component: () => import("../../modules/monitor/MonitorPage.vue"),
        props: { roomsOnly: true, matchesOnly: true },
        meta: { title: "对局中心", description: "实时对局阶段、在线席位及结算状态", requiresAuth: true, capability: PLATFORM_READ },
      },
      {
        path: "mahjong/reports",
        name: "mahjong-reports",
        component: () => import("../../modules/reports/MahjongReportsPage.vue"),
        meta: { title: "麻将举报", description: "核查牌桌举报与处理记录", requiresAuth: true, capability: MAHJONG_REVIEW },
      },
      {
        path: "wallet/eggs",
        name: "wallet-eggs",
        component: () => import("../../modules/wallet/EggGrantPage.vue"),
        meta: { title: "鸡蛋发放", description: "按玩家昵称发放鸡蛋", requiresAuth: true, capability: WALLET_GRANT_EGGS },
      },
    ],
  },
  { path: "/:pathMatch(.*)*", redirect: "/dashboard" },
];

/** createAppRouter（创建路由器）测试环境可选择内存历史。 */
export function createAppRouter(memoryHistory = false): Router {
  const router = createRouter({
    history: memoryHistory ? createMemoryHistory() : createWebHistory(),
    routes: routeRecords,
  });

  router.beforeEach((to) => {
    const auth = useAuthStore();
    if (to.meta.requiresAuth && !auth.isAuthenticated) {
      return { path: "/login", query: { redirect: to.fullPath } };
    }
    if (to.path === "/login" && auth.isAuthenticated) {
      return auth.landingPath;
    }
    if (to.meta.requiresAuth && to.name !== "access") {
      const capability = String(to.meta.capability ?? PLATFORM_READ);
      if (!auth.can(capability)) return auth.landingPath;
    }
    return true;
  });

  return router;
}

export const router = createAppRouter();
