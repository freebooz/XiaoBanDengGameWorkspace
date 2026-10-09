<script setup lang="ts">
import { computed, ref } from "vue";
import { useRoute, useRouter } from "vue-router";
import { useAuthStore } from "../app/store/auth";

const route = useRoute();
const router = useRouter();
const auth = useAuthStore();
const title = computed(() => String(route.meta.title ?? "小板凳游戏运营平台"));
const description = computed(() => String(route.meta.description ?? "统一游戏运营与运行管理"));
const loggingOut = ref(false);
const logoutError = ref("");

/** 服务端注销成功后再离开页面，离线错误支持直接重试。 */
async function logout(): Promise<void> {
  if (loggingOut.value) return;
  loggingOut.value = true;
  logoutError.value = "";
  try {
    await auth.logout();
    await router.replace("/login");
  } catch (error) {
    logoutError.value = error instanceof Error ? error.message : "退出失败，请重试";
  } finally { loggingOut.value = false; }
}
</script>

<template>
  <el-header class="admin-header">
    <div class="header-copy">
      <h1>{{ title }}</h1>
      <p>{{ description }}</p>
    </div>
    <div class="header-actions">
      <span class="environment-pill">只读管理员</span>
      <div v-if="logoutError" class="logout-error" role="alert">
        <span>{{ logoutError }}</span>
        <button data-testid="retry-logout" type="button" :disabled="loggingOut" @click="logout">重试退出</button>
      </div>
      <el-dropdown>
        <button class="admin-user" type="button" :disabled="loggingOut">{{ auth.adminName || "管理员" }}⌄</button>
        <template #dropdown>
          <el-dropdown-menu>
            <el-dropdown-item :disabled="loggingOut" @click="logout">退出登录</el-dropdown-item>
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
.logout-error { display: flex; align-items: center; gap: 8px; color: #b42318; font-size: 11px; }
.logout-error button { border: 0; color: inherit; background: transparent; cursor: pointer; text-decoration: underline; }
</style>
