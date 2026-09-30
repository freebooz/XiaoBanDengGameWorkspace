import { defineStore } from "pinia";

/** usePlatformStore（平台界面状态）保存跨页面的轻量后台 UI 状态。 */
export const usePlatformStore = defineStore("platform", {
  state: () => ({
    sidebarCollapsed: false,
  }),
  actions: {
    toggleSidebar(): void {
      this.sidebarCollapsed = !this.sidebarCollapsed;
    },
  },
});
