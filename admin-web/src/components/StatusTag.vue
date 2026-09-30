<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{ value?: string | null }>();
const isHealthy = computed(() => props.value === "ok" || props.value === "active" || props.value === "enabled");
const label = computed(() => {
  if (!props.value) return "未知";
  if (props.value === "ok") return "正常";
  if (props.value === "active") return "活跃";
  if (props.value === "waiting") return "等待中";
  if (props.value === "finished") return "已结束";
  return props.value;
});
</script>

<template>
  <el-tag :type="isHealthy ? 'success' : value ? 'warning' : 'info'" size="small" effect="light">
    {{ label }}
  </el-tag>
</template>
