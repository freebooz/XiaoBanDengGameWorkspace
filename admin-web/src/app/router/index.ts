import { defineComponent, h } from "vue";
import {
  createMemoryHistory,
  createRouter,
  createWebHistory,
  type RouteRecordRaw,
  type Router,
} from "vue-router";
import { useAuthStore } from "../store/auth";

const TemporaryPage = defineComponent({
  name: "TemporaryPage",
  setup: () => () => h("div", { class: "route-placeholder" }, "模块初始化中"),
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
        path: "dashboard",
        name: "dashboard",
        component: () => import("../../modules/dashboard/DashboardPage.vue"),
        meta: { title: "综合工作台", description: "平台运行状态与一期产品总览", requiresAuth: true },
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
        component: TemporaryPage,
        meta: { title: "房间中心", description: "实时房间与生命周期状态", requiresAuth: true },
      },
      {
        path: "matches",
        name: "matches",
        component: TemporaryPage,
        meta: { title: "对局中心", description: "战绩、事件、快照与回放", requiresAuth: true },
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
      return "/dashboard";
    }
    return true;
  });

  return router;
}

export const router = createAppRouter();
