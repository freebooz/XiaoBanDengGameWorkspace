<script setup lang="ts">
import { onMounted, ref } from "vue";
import { platformApi } from "../../services/api/admin";
import type { GameDescriptor } from "../../services/api/types";
import GameCatalogTable from "./GameCatalogTable.vue";

const games = ref<GameDescriptor[]>([]);
const loading = ref(false);
const unavailable = ref(false);

async function loadCatalog(): Promise<void> {
  if (loading.value) return;
  loading.value = true;
  unavailable.value = false;
  try {
    games.value = (await platformApi.catalog()).games;
  } catch {
    unavailable.value = true;
  } finally {
    loading.value = false;
  }
}

onMounted(loadCatalog);
</script>

<template>
  <el-card class="xbd-section-card" :aria-busy="loading">
    <template #header>
      <header class="catalog-header">
        <h2>游戏目录</h2>
        <el-button plain :loading="loading" @click="loadCatalog">刷新目录</el-button>
      </header>
    </template>
    <p v-if="unavailable" class="catalog-error" role="alert">
      {{ games.length ? "游戏目录刷新失败，以下为上次收到的数据。" : "游戏目录暂不可用，请刷新重试。" }}
    </p>
    <GameCatalogTable v-if="games.length || !unavailable" :games="games"
      :empty-text="loading ? '正在读取游戏目录' : '暂无产品目录数据'" />
  </el-card>
</template>

<style scoped>
.catalog-header { display: flex; align-items: center; justify-content: space-between; gap: 12px; }
.catalog-header h2 { margin: 0; font-size: 16px; }
.catalog-error { color: var(--xbd-warning); }
</style>
