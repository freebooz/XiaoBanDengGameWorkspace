import {
  createMemoryHistory,
  createRouter,
  createWebHistory,
  type RouteRecordRaw,
  type Router,
} from "vue-router";
import { useAuthStore } from "../store/auth";
import { setUnauthorizedHandler } from "../../services/api/client";

/** routeRecords（路由表）固定一期核心 URL（页面地址），按领域延迟加载真实只读页面。 */
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
        component: () => import("../../modules/games/GamesPage.vue"),
        meta: { title: "游戏中心", description: "产品、游戏、规则集与规则版本", requiresAuth: true },
      },
      {
        path: "rooms",
        name: "rooms",
        component: () => import("../../modules/rooms/RoomsPage.vue"),
        meta: { title: "房间中心", description: "实时房间与生命周期状态", requiresAuth: true },
      },
      {
        path: "matches",
        name: "matches",
        component: () => import("../../modules/matches/MatchesPage.vue"),
        meta: { title: "对局中心", description: "战绩、事件、快照与回放", requiresAuth: true },
      },
    ],
  },
  { path: "/:pathMatch(.*)*", redirect: "/dashboard" },
];

/** 只允许已定义的站内业务地址，拒绝外部 URL、反斜线及登录循环。 */
export function getSafeRedirect(value: unknown): string {
  if (typeof value !== "string" || !value.startsWith("/") || value.startsWith("//") ||
    /[\\\s\u0000-\u001f]/.test(value)) return "/dashboard";
  try {
    const url = new URL(value, window.location.origin);
    const allowedPaths = ["/", "/dashboard", "/users", "/games/products", "/rooms", "/matches"];
    if (url.origin === window.location.origin && allowedPaths.includes(url.pathname)) {
      return url.pathname + url.search + url.hash;
    }
  } catch { /* 无法解析的地址统一回到工作台。 */ }
  return "/dashboard";
}

/** createAppRouter（创建路由器）测试环境可选择内存历史。 */
export function createAppRouter(memoryHistory = false): Router {
  const router = createRouter({
    history: memoryHistory ? createMemoryHistory() : createWebHistory(),
    routes: routeRecords,
  });

  // 业务接口收到 401 时清理状态，并保留当前页面供重新登录恢复。
  setUnauthorizedHandler(() => {
    const auth = useAuthStore();
    auth.clearSession();
    const current = router.currentRoute.value;
    if (current.path !== "/login") {
      void router.replace({ path: "/login", query: { redirect: current.fullPath } });
    }
  }, () => useAuthStore().getSessionRevision());

  router.beforeEach(async (to) => {
    const auth = useAuthStore();
    if (to.meta.requiresAuth || to.path === "/login") await auth.restoreSession();
    if (to.meta.requiresAuth && !auth.isAuthenticated) {
      return { path: "/login", query: { redirect: to.fullPath } };
    }
    if (to.path === "/login" && auth.isAuthenticated) {
      return getSafeRedirect(to.query.redirect);
    }
    return true;
  });

  return router;
}

export const router = createAppRouter();
