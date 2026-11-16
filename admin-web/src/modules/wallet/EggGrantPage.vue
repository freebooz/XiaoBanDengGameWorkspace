<script setup lang="ts">
import { onUnmounted, ref } from "vue";
import { WALLET_GRANT_EGGS, useAuthStore } from "../../app/store/auth";
import { eggWalletApi } from "../../services/api/admin";
import { ApiError } from "../../services/api/client";
import type { EggGrantReceipt, EggGrantRequest } from "../../services/api/types";

const auth = useAuthStore();
const maxAmount = 1_000_000;
const nickname = ref("");
const amount = ref<number | string>("");
const submitting = ref(false);
const errorMessage = ref("");
const receipt = ref<EggGrantReceipt | null>(null);
let attempt: EggGrantRequest | undefined;
let active = true;

onUnmounted(() => { active = false; });

async function submit(): Promise<void> {
  if (submitting.value || !auth.can(WALLET_GRANT_EGGS)) return;
  const displayName = nickname.value.trim();
  const quantity = Number(amount.value);
  if (!displayName || !Number.isInteger(quantity) || quantity < 1 || quantity > maxAmount) {
    errorMessage.value = "请输入玩家昵称及 1 至 1,000,000 之间的整数。";
    return;
  }

  const session = auth.sessionRevision;
  submitting.value = true;
  errorMessage.value = "";
  receipt.value = null;
  try {
    // The server may have applied a request whose response was lost.
    if (attempt?.display_name !== displayName || attempt.amount !== quantity) {
      attempt = { display_name: displayName, amount: quantity, request_id: crypto.randomUUID() };
    }
    const result = await eggWalletApi.grant(attempt);
    if (!active || auth.sessionRevision !== session) return;
    receipt.value = result;
    amount.value = "";
    attempt = undefined;
  } catch (error) {
    if (!active || auth.sessionRevision !== session) return;
    if (error instanceof ApiError) {
      if (error.status === 403) errorMessage.value = "当前账号没有鸡蛋发放权限。";
      else if (error.status === 404) errorMessage.value = "未找到该昵称对应的有效玩家，请核对昵称。";
      else if (error.status === 0 || error.status >= 500) errorMessage.value = "暂时无法确认发放结果。请保留昵称及数量并重试。";
      else errorMessage.value = error.message;
    } else {
      errorMessage.value = "无法生成发放请求，请通过 HTTPS 打开管理端后重试。";
    }
  } finally {
    if (active) submitting.value = false;
  }
}
</script>

<template>
  <section class="egg-grant-page" aria-label="鸡蛋发放">
    <el-card shadow="never">
      <form class="grant-form" :aria-busy="submitting" @submit.prevent="submit">
        <label>
          玩家昵称
          <input v-model="nickname" name="nickname" placeholder="输入完整昵称" maxlength="64" autocomplete="off" required :disabled="submitting" />
        </label>
        <label>
          鸡蛋数量
          <input v-model="amount" name="amount" type="number" inputmode="numeric" min="1" :max="maxAmount" step="1" placeholder="1–1,000,000" required :disabled="submitting" />
        </label>
        <el-button type="primary" size="large" native-type="submit" :loading="submitting" :disabled="submitting">
          发放鸡蛋
        </el-button>
        <p v-if="errorMessage" role="alert" class="grant-error">{{ errorMessage }}</p>
      </form>
    </el-card>
    <el-card v-if="receipt" shadow="never" class="grant-receipt">
      <div role="status">
        <h2>鸡蛋已发放</h2>
        <dl>
          <div><dt>玩家昵称</dt><dd>{{ receipt.display_name }}</dd></div>
          <div><dt>发放数量</dt><dd>{{ receipt.amount.toLocaleString("zh-CN") }} 枚</dd></div>
          <div><dt>鸡蛋余额</dt><dd>{{ receipt.balance.toLocaleString("zh-CN") }} 枚</dd></div>
          <div><dt>请求编号</dt><dd>{{ receipt.request_id }}</dd></div>
        </dl>
      </div>
    </el-card>
  </section>
</template>

<style scoped>
.egg-grant-page {
  display: grid;
  gap: 16px;
  max-width: 650px;
}
.grant-form {
  display: grid;
  gap: 16px;
}
.grant-form label {
  display: grid;
  gap: 8px;
  font-weight: 600;
}
.grant-form input {
  width: 100%;
  min-height: 44px;
  border: 1px solid var(--xbd-border-control);
  border-radius: var(--xbd-radius-sm);
  padding: 8px 12px;
  background: var(--xbd-page-bg);
  color: var(--xbd-text-primary);
  font: inherit;
  font-size: 16px;
  font-weight: 400;
}
.grant-form input::placeholder { color: var(--xbd-text-muted); }
.grant-form button { min-height: 44px; margin: 0; justify-self: start; }
.grant-error { margin: 0; color: var(--el-color-danger); }
.grant-receipt h2 { margin: 0 0 12px; font-size: 17px; color: var(--xbd-success); }
.grant-receipt dl { display: grid; gap: 8px; margin: 0; }
.grant-receipt dl > div { display: grid; grid-template-columns: 5em minmax(0, 1fr); gap: 8px; }
.grant-receipt dt { color: var(--xbd-text-secondary); }
.grant-receipt dd { margin: 0; overflow-wrap: anywhere; }
@media (max-width: 560px) {
  .grant-form button { width: 100%; }
}
</style>
