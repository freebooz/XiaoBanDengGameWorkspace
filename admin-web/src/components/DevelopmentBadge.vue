<script setup lang="ts">
withDefaults(defineProps<{ label?: string }>(), { label: "开发环境" });
</script>

<template>
  <span class="development-badge">{{ label }}</span>
</template>

<style scoped>
.development-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 10px;
  border: 1px solid var(--xbd-border-control);
  border-radius: 999px;
  color: var(--xbd-warning);
  background: var(--xbd-warning-bg);
  font-size: 11px;
  font-weight: 650;
}
.development-badge::before {
  width: 6px;
  height: 6px;
  border-radius: 50%;
  background: var(--xbd-brand-primary);
  content: "";
}
</style>
