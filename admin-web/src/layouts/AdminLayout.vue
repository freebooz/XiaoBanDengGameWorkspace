<script setup lang="ts">
import { RouterView } from "vue-router";
import Sidebar from "./Sidebar.vue";
import HeaderBar from "./HeaderBar.vue";
import { usePlatformStore } from "../app/store/platform";

const platform = usePlatformStore();
</script>

<template>
  <el-container class="admin-layout">
    <Sidebar />
    <!-- 页眉经过自定义组件封装，需显式指定纵向容器，保证内容位于页眉下方。 -->
    <el-container class="admin-main-shell" direction="vertical">
      <HeaderBar />
      <el-main class="admin-content">
        <RouterView />
      </el-main>
    </el-container>
  </el-container>
</template>

<style scoped>
.admin-layout { width: 100%; height: 100%; background: var(--xbd-page-bg); }
.admin-main-shell {
  min-width: 0;
  margin-left: v-bind("platform.sidebarCollapsed ? 'var(--xbd-sidebar-collapsed-width)' : 'var(--xbd-sidebar-width)'");
  transition: margin-left 0.22s ease;
}
.admin-content { padding: 18px 20px 22px; overflow: auto; background: var(--xbd-page-bg); }
</style>
