<script setup lang="ts">
import { computed } from "vue";

const props = defineProps<{ value?: string | null }>();
// 共用状态标签补齐只读业务状态；未知状态保留原值，不错误映射为正常。
const isHealthy = computed(() => ["ok", "active", "enabled", "playing"].includes(props.value ?? ""));
const label = computed(() => {
  if (!props.value) return "未知";
  if (props.value === "ok") return "正常";
  if (props.value === "active") return "活跃";
  if (props.value === "waiting") return "等待中";
  if (props.value === "finished") return "已结束";
  const labels: Record<string, string> = { enabled: "已启用", disabled: "已停用", playing: "进行中", created: "待开始", closed: "已关闭", cancelled: "已取消", aborted: "已中止", development: "开发数据" };
  return labels[props.value] ?? `未知状态（${props.value}）`;
});
</script>

<template>
  <el-tag :type="isHealthy ? 'success' : value ? 'warning' : 'info'" size="small" effect="light">
    {{ label }}
  </el-tag>
</template>
