<script setup lang="ts">
// QueryError（查询错误提示）复用已有组件库，错误状态始终提供显式重试入口。
defineProps<{ message: string }>();
defineEmits<{ retry: [] }>();
</script>

<template>
  <div v-if="message" class="query-error" role="alert">
    <el-alert :title="message" type="error" :closable="false" show-icon />
    <el-button data-testid="query-retry" size="small" @click="$emit('retry')">重试</el-button>
  </div>
</template>

<style scoped>
/* 错误信息允许换行，重试按钮保留可点击区域。 */
.query-error { display: flex; align-items: center; gap: 10px; margin-bottom: 12px; }
.query-error :deep(.el-alert) { min-width: 0; }
.query-error :deep(.el-button) { flex-shrink: 0; }
</style>
