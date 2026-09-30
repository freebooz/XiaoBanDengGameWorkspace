<template>
  <div class="filter-bar">
    <div class="filter-bar__fields"><slot /></div>
    <div class="filter-bar__actions"><slot name="actions" /></div>
  </div>
</template>

<style scoped>
.filter-bar {
  display: flex; align-items: center; justify-content: space-between; gap: 14px;
  min-height: 58px; margin-bottom: 12px; padding: 10px 12px;
  border: 1px solid var(--xbd-border); border-radius: 12px; background: var(--xbd-card-bg);
  box-shadow: 0 4px 14px rgba(71,48,29,.035);
}
.filter-bar__fields { display: flex; align-items: center; flex-wrap: wrap; gap: 9px; min-width: 0; }
.filter-bar__actions { display: flex; align-items: center; gap: 8px; flex: 0 0 auto; }
</style>
