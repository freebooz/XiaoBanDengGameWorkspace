import { defineStore } from "pinia";

const DEV_SESSION_KEY = "xbd_admin_dev_session";

/** useAuthStore（管理员会话状态）仅为一期后台提供开发环境会话。 */
export const useAuthStore = defineStore("auth", {
  state: () => ({
    isAuthenticated:
      import.meta.env.DEV && localStorage.getItem(DEV_SESSION_KEY) === "1",
    adminName:
      import.meta.env.DEV && localStorage.getItem(DEV_SESSION_KEY) === "1"
        ? "开发管理员"
        : "",
  }),
  actions: {
    /** loginDevelopment（开发管理员登录）生产构建中禁止启用。 */
    loginDevelopment(): void {
      if (!import.meta.env.DEV) {
        return;
      }
      localStorage.setItem(DEV_SESSION_KEY, "1");
      this.isAuthenticated = true;
      this.adminName = "开发管理员";
    },
    /** logout（退出管理员会话）。 */
    logout(): void {
      localStorage.removeItem(DEV_SESSION_KEY);
      this.isAuthenticated = false;
      this.adminName = "";
    },
  },
});
