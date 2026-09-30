<script setup lang="ts">
withDefaults(
  defineProps<{ modelValue: boolean; title: string; width?: string | number }>(),
  { width: "620px" },
);
defineEmits<{ "update:modelValue": [value: boolean] }>();
</script>

<template>
  <el-drawer
    :model-value="modelValue"
    :title="title"
    :size="width"
    destroy-on-close
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <slot />
  </el-drawer>
</template>
