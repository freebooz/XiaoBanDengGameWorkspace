<script setup lang="ts">
import { useRoute } from "vue-router";
const route = useRoute();
</script>

<template>
  <section class="page-container">
    <slot>
      <el-card class="xbd-section-card">
        <el-empty :description="String(route.meta.title ?? '模块') + '正在初始化'" />
      </el-card>
    </slot>
  </section>
</template>

<style scoped>
.page-container { width: 100%; max-width: 1680px; margin: 0 auto; }
</style>
