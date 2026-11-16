<script setup lang="ts">
import { RouterView } from "vue-router";
import Sidebar from "./Sidebar.vue";
import HeaderBar from "./HeaderBar.vue";
import { usePlatformStore } from "../app/store/platform";

const platform = usePlatformStore();
</script>

<template>
  <div class="admin-layout" :class="{ 'sidebar-collapsed': platform.sidebarCollapsed }">
    <Sidebar />
    <div class="admin-main-shell">
      <HeaderBar />
      <el-main class="admin-content">
        <RouterView />
      </el-main>
    </div>
  </div>
</template>

<style scoped>
.admin-layout {
  --nav-width: var(--xbd-sidebar-width);
  display: flex; width: 100%; height: 100%; background: var(--xbd-page-bg);
}
.admin-layout.sidebar-collapsed { --nav-width: var(--xbd-sidebar-collapsed-width); }
.admin-main-shell {
  display: flex; flex: 1 1 0; flex-direction: column; min-width: 0; min-height: 0;
}
.admin-content { min-height: 0; padding: 18px 20px 22px; overflow: auto; background: var(--xbd-page-bg); }
@media (max-width: 760px) {
  .admin-layout { flex-direction: column; }
  .admin-content { padding: 12px; }
}
</style>
