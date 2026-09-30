<template>
  <span class="development-badge">开发环境</span>
</template>

<style scoped>
.development-badge {
  display: inline-flex;
  align-items: center;
  gap: 5px;
  padding: 5px 10px;
  border: 1px solid #efcfab;
  border-radius: 999px;
  color: #9c5b1f;
  background: #fff4e5;
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
