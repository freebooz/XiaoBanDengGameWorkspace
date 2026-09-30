<script setup lang="ts">
withDefaults(
  defineProps<{
    label: string;
    value: string | number;
    caption?: string;
    tone?: "brand" | "success" | "neutral" | "warning";
  }>(),
  { caption: "", tone: "brand" },
);
</script>

<template>
  <article class="metric-card" :class="'tone-' + tone">
    <div class="metric-card__head">
      <span class="metric-card__label">{{ label }}</span>
      <span class="metric-card__dot" />
    </div>
    <div class="metric-card__value">{{ value }}</div>
    <div class="metric-card__caption">{{ caption || "实时数据" }}</div>
  </article>
</template>

<style scoped>
.metric-card {
  position: relative; overflow: hidden; min-height: 126px; padding: 18px 18px 16px;
  border: 1px solid var(--xbd-border); border-radius: 14px; background: var(--xbd-card-bg);
  box-shadow: var(--xbd-shadow-card);
}
.metric-card::after { position: absolute; right: -26px; bottom: -34px; width: 92px; height: 92px; border-radius: 50%; background: rgba(212,138,58,.055); content: ""; }
.metric-card__head { display: flex; align-items: center; justify-content: space-between; }
.metric-card__label { color: var(--xbd-text-secondary); font-size: 12px; }
.metric-card__dot { width: 8px; height: 8px; border-radius: 50%; background: var(--xbd-brand-primary); box-shadow: 0 0 0 4px rgba(212,138,58,.10); }
.metric-card__value { margin-top: 15px; color: var(--xbd-text-primary); font-size: 28px; font-weight: 720; letter-spacing: -.02em; }
.metric-card__caption { margin-top: 6px; color: #a09891; font-size: 10px; }
.tone-success .metric-card__dot { background: var(--xbd-success); box-shadow: 0 0 0 4px rgba(61,155,104,.10); }
.tone-neutral .metric-card__dot { background: #a89d92; box-shadow: 0 0 0 4px rgba(168,157,146,.10); }
.tone-warning .metric-card__dot { background: var(--xbd-warning); box-shadow: 0 0 0 4px rgba(217,155,53,.10); }
</style>
