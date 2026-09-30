<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { usePlatformStore } from "../app/store/platform";
import BrandLogo from "../components/BrandLogo.vue";

const route = useRoute();
const router = useRouter();
const platform = usePlatformStore();

const items = [
  { path: "/dashboard", label: "综合工作台" },
  { path: "/users", label: "用户中心" },
  { path: "/games/products", label: "游戏中心" },
  { path: "/rooms", label: "房间中心" },
  { path: "/matches", label: "对局中心" },
];

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
      <el-menu-item v-for="item in items" :key="item.path" :index="item.path">
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
  position: fixed; inset: 0 auto 0 0; z-index: 20;
  width: var(--xbd-sidebar-width); background: var(--xbd-sidebar-bg); color: #f7ecdf;
  transition: width 0.22s ease; box-shadow: 8px 0 30px rgba(36, 25, 17, 0.08);
}
.admin-sidebar.collapsed { width: var(--xbd-sidebar-collapsed-width); }
.sidebar-brand { height: var(--xbd-header-height); display: flex; align-items: center; padding: 0 12px; border-bottom: 1px solid rgba(255,255,255,.08); overflow: hidden; }
.sidebar-menu { border-right: 0; background: transparent; }
.sidebar-menu :deep(.el-menu-item) { height: 46px; margin: 3px 8px; border-radius: 9px; color: #c7baae; }
.sidebar-menu :deep(.el-menu-item:hover) { background: rgba(212,138,58,.12); color: #fff; }
.sidebar-menu :deep(.el-menu-item.is-active) { background: linear-gradient(90deg, rgba(212,138,58,.24), rgba(212,138,58,.08)); color: var(--xbd-brand-highlight); }
.collapse-button { position: absolute; bottom: 16px; left: 10px; right: 10px; height: 34px; border: 1px solid rgba(255,255,255,.08); border-radius: 8px; background: rgba(255,255,255,.035); color: #a99a8d; cursor: pointer; }
</style>

