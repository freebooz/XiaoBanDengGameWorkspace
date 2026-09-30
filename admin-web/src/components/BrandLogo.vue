<script setup lang="ts">
import markUrl from "../assets/brand/logo-mark.svg";

withDefaults(
  defineProps<{
    compact?: boolean;
    showSubtitle?: boolean;
    inverse?: boolean;
  }>(),
  { compact: false, showSubtitle: true, inverse: false },
);
</script>

<template>
  <div
    class="brand-logo"
    :class="{ compact, inverse }"
    aria-label="小板凳品牌标识"
  >
    <img :src="markUrl" alt="" class="brand-logo__mark" />
    <div v-if="!compact" class="brand-logo__copy">
      <strong>小板凳</strong>
      <span v-if="showSubtitle">游戏运营平台</span>
    </div>
  </div>
</template>

<style scoped>
.brand-logo { display: inline-flex; align-items: center; gap: 11px; min-width: 0; }
.brand-logo__mark { width: 42px; height: 42px; flex: 0 0 auto; filter: drop-shadow(0 5px 10px rgba(102, 55, 24, .18)); }
.brand-logo__copy { min-width: 0; white-space: nowrap; }
.brand-logo__copy strong, .brand-logo__copy span { display: block; }
.brand-logo__copy strong { color: var(--xbd-text-primary); font-size: 18px; font-weight: 760; letter-spacing: .08em; }
.brand-logo__copy span { margin-top: 2px; color: var(--xbd-text-secondary); font-size: 10px; letter-spacing: .08em; }
.brand-logo.inverse .brand-logo__copy strong { color: #fff7ee; }
.brand-logo.inverse .brand-logo__copy span { color: #a99a8d; }
.brand-logo.compact .brand-logo__mark { width: 38px; height: 38px; }
</style>
