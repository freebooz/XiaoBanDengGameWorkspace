<script setup lang="ts">
import { computed } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "../app/store/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const title = computed(() => String(route.meta.title ?? "小板凳游戏运营平台"));
const description = computed(() => String(route.meta.description ?? "统一游戏运营与运行管理"));
function logout(): void {
  auth.logout();
  void router.push("/login");
}
</script>

<template>
  <el-header class="admin-header">
    <div class="header-copy">
      <h1>{{ title }}</h1>
      <p>{{ description }}</p>
    </div>
    <div class="header-actions">
      <span class="environment-pill">开发环境</span>
      <el-dropdown>
        <button class="admin-user" type="button">{{ auth.adminName || "管理员" }}⌄</button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item @click="logout">退出登录</el-dropdown-item>
          </el-dropdown-menu>
        </template>
      </el-dropdown>
    </div>
  </el-header>
</template>

<style scoped>
.admin-header { position: sticky; top: 0; z-index: 10; height: var(--xbd-header-height); display: flex; align-items: center; justify-content: space-between; padding: 0 20px; border-bottom: 1px solid var(--xbd-border); background: rgba(255,253,252,.94); backdrop-filter: blur(12px); }
.header-copy h1 { margin: 0; font-size: 18px; font-weight: 680; }
.header-copy p { margin: 3px 0 0; color: var(--xbd-text-secondary); font-size: 11px; }
.header-actions { display: flex; align-items: center; gap: 12px; }
.environment-pill { padding: 4px 9px; border: 1px solid #f0d5b7; border-radius: 999px; color: #a86625; background: #fff6e9; font-size: 10px; }
.admin-user { border: 0; background: transparent; color: var(--xbd-text-primary); cursor: pointer; font-size: 12px; }
</style>
