<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { usePlatformStore } from "../app/store/platform";
import { MAHJONG_REVIEW, PLATFORM_READ, WALLET_GRANT_EGGS, useAuthStore } from "../app/store/auth";
import BrandLogo from "../components/BrandLogo.vue";

const route = useRoute();
const router = useRouter();
const platform = usePlatformStore();
const auth = useAuthStore();

const items = computed(() => [
  { path: "/dashboard", label: "综合工作台" },
  { path: "/monitor", label: "实时监视" },
  { path: "/users", label: "用户中心" },
  { path: "/games/products", label: "游戏中心" },
  { path: "/rooms", label: "房间中心" },
  { path: "/matches", label: "对局中心" },
  { path: "/mahjong/reports", label: "麻将举报", capability: MAHJONG_REVIEW },
  { path: "/wallet/eggs", label: "鸡蛋发放", capability: WALLET_GRANT_EGGS },
].filter((item) => auth.can(item.capability ?? PLATFORM_READ)));

const activePath = computed(() => route.path);
</script>

<template>
  <aside class="admin-sidebar" :class="{ collapsed: platform.sidebarCollapsed }">
    <div class="sidebar-brand">
      <BrandLogo
        :compact="platform.sidebarCollapsed"
        :show-subtitle="true"
        inverse
      />
    </div>
    <el-menu
      :default-active="activePath"
      :collapse="platform.sidebarCollapsed"
      class="sidebar-menu"
      @select="(path: string) => router.push(path)"
    >
      <el-menu-item v-for="item in items" :key="item.path" :index="item.path" :aria-current="activePath === item.path ? 'page' : undefined">
        <span>{{ item.label }}</span>
      </el-menu-item>
    </el-menu>
    <button class="collapse-button" type="button" @click="platform.toggleSidebar">
      {{ platform.sidebarCollapsed ? "›" : "‹ 收起导航" }}
    </button>
  </aside>
</template>

<style scoped>
.admin-sidebar {
  position: relative; flex: 0 0 auto; width: var(--nav-width); min-width: 0; z-index: 20;
  background: var(--xbd-sidebar-bg); color: var(--xbd-text-primary);
  transition: width 0.22s ease; border-right: 1px solid var(--xbd-border);
}
.sidebar-brand { height: var(--xbd-header-height); display: flex; align-items: center; padding: 0 12px; border-bottom: 1px solid var(--xbd-border); overflow: hidden; }
.sidebar-menu { border-right: 0; background: transparent; }
.sidebar-menu :deep(.el-menu-item) { height: 46px; margin: 3px 8px; border-radius: 9px; color: var(--xbd-text-secondary); }
.sidebar-menu :deep(.el-menu-item:hover) { background: var(--xbd-surface-raised); color: var(--xbd-text-primary); }
.sidebar-menu :deep(.el-menu-item.is-active) { background: linear-gradient(90deg, var(--xbd-brand-tint), var(--xbd-surface-inset)); color: var(--xbd-brand-highlight); }
.collapse-button { position: absolute; bottom: 16px; left: 10px; right: 10px; height: 34px; border: 1px solid var(--xbd-border-control); border-radius: 8px; background: var(--xbd-surface-inset); color: var(--xbd-text-secondary); cursor: pointer; }
@media (max-width: 760px) {
  .admin-sidebar { width: 100%; height: auto; transition: none; }
  .sidebar-brand { height: 54px; }
  .sidebar-menu { width: 100%; display: flex; overflow-x: auto; }
  .sidebar-menu :deep(.el-menu-item) { flex: 0 0 auto; height: 44px; margin: 2px 4px; padding: 0 9px; }
  .sidebar-menu :deep(.el-menu-item span) { width: auto; height: auto; visibility: visible; }
  .collapse-button { display: none; }
}
</style>

