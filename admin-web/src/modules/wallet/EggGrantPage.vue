<script setup lang="ts">
import { computed, onScopeDispose, ref, shallowRef, watch } from "vue";
import { WALLET_GRANT_EGGS, useAuthStore } from "../../app/store/auth";
import { eggWalletApi } from "../../services/api/admin";
import { ApiError } from "../../services/api/client";
import type { EggGrantReceipt, EggGrantRequest, EggWalletPlayer } from "../../services/api/types";

const auth = useAuthStore();
const maxAmount = 1_000_000;
const nickname = ref("");
const amount = ref<number | string>("");
const player = shallowRef<EggWalletPlayer>();
const lookingUp = ref(false);
const submitting = ref(false);
const errorMessage = ref("");
const receipt = shallowRef<EggGrantReceipt>();
const attempt = shallowRef<EggGrantRequest>();
let lookupRequest: AbortController | undefined;
let grantRequest: AbortController | undefined;
const displayName = computed(() => nickname.value.trim());
const quantity = computed(() => Number(amount.value));
const permitted = computed(() => auth.isAuthenticated && auth.can(WALLET_GRANT_EGGS));
const canLookup = computed(() => permitted.value && !!displayName.value && !lookingUp.value && !submitting.value);
const canGrant = computed(() => permitted.value && !!player.value && player.value.display_name === displayName.value &&
  !lookingUp.value && !submitting.value && Number.isInteger(quantity.value) && quantity.value >= 1 && quantity.value <= maxAmount);
const sameAttempt = computed(() => !!attempt.value && attempt.value.display_name === displayName.value &&
  attempt.value.expected_account_id === player.value?.account_id && attempt.value.amount === quantity.value);
const formatEggs = (count: number) => `${count.toLocaleString("zh-CN")} 枚`;

function clearPlayer(): void {
  player.value = undefined;
  attempt.value = undefined;
  receipt.value = undefined;
  amount.value = "";
}

function cancelRequests(): void {
  lookupRequest?.abort();
  grantRequest?.abort();
  lookupRequest = undefined;
  grantRequest = undefined;
}

function resetPlayer(): void {
  cancelRequests();
  clearPlayer();
  lookingUp.value = false;
  submitting.value = false;
  errorMessage.value = "";
}

watch(displayName, resetPlayer, { flush: "sync" });
watch(() => auth.sessionRevision, () => {
  nickname.value = "";
  resetPlayer();
}, { flush: "sync" });
onScopeDispose(cancelRequests);

function isReviewedWallet(value: EggWalletPlayer, name: string): boolean {
  return !!value && value.display_name === name && typeof value.account_id === "string" && !!value.account_id &&
    value.asset_id === "xbd_egg" && Number.isSafeInteger(value.balance) && value.balance >= 0;
}

async function lookupPlayer(): Promise<void> {
  if (!canLookup.value) return;
  const name = displayName.value;
  const previousAccount = player.value?.account_id ?? attempt.value?.expected_account_id;
  const controller = new AbortController();
  lookupRequest = controller;
  lookingUp.value = true;
  player.value = undefined;
  receipt.value = undefined;
  errorMessage.value = "";
  try {
    const result = await eggWalletApi.player(name, controller.signal);
    if (controller.signal.aborted) return;
    if (!isReviewedWallet(result, name)) throw new Error("无效的玩家钱包数据");
    if (result.account_id !== previousAccount) clearPlayer();
    player.value = result;
  } catch (error) {
    if (controller.signal.aborted) return;
    if (error instanceof ApiError && error.status === 404) errorMessage.value = "未找到该昵称对应的有效玩家，请核对完整昵称。";
    else if (error instanceof ApiError && error.status === 409) errorMessage.value = "该昵称对应多个有效账号，请核对昵称。";
    else if (error instanceof ApiError && error.status === 403) errorMessage.value = "当前账号没有鸡蛋管理权限。";
    else errorMessage.value = "暂时无法读取玩家钱包，请重试。";
  } finally {
    if (lookupRequest === controller) {
      lookupRequest = undefined;
      lookingUp.value = false;
    }
  }
}

async function submit(): Promise<void> {
  const selected = player.value;
  if (!canGrant.value || !selected) return;
  if (typeof crypto.randomUUID !== "function") {
    errorMessage.value = "请通过 HTTPS 打开管理端后重试。";
    return;
  }

  // Keep the exact reviewed target and request ID if the previous response was lost.
  const request = (sameAttempt.value ? attempt.value : undefined) ?? {
    display_name: selected.display_name, expected_account_id: selected.account_id,
    amount: quantity.value, request_id: crypto.randomUUID(),
  };
  const controller = new AbortController();
  grantRequest = controller;
  attempt.value = request;
  submitting.value = true;
  errorMessage.value = "";
  receipt.value = undefined;
  try {
    const result = await eggWalletApi.grant(request, controller.signal);
    if (controller.signal.aborted) return;
    if (!isReviewedWallet(result, request.display_name) || result.account_id !== request.expected_account_id ||
      result.request_id !== request.request_id || result.amount !== request.amount) throw new Error("无效的鸡蛋发放回执");
    receipt.value = result;
    player.value = { ...selected, balance: result.balance };
    amount.value = "";
    attempt.value = undefined;
  } catch (error) {
    if (controller.signal.aborted) return;
    if (error instanceof ApiError && (error.status === 409 || error.status === 404)) {
      clearPlayer();
      errorMessage.value = "发放需要重新核对玩家账号，请再次查询。";
    } else if (error instanceof ApiError && error.status > 0 && error.status < 500) {
      attempt.value = undefined;
      errorMessage.value = error.status === 403 ? "当前账号没有鸡蛋管理权限。" : "发放信息无效，请核对玩家和数量。";
    } else {
      errorMessage.value = "暂时无法确认发放结果，请用相同数量重试。";
    }
  } finally {
    if (grantRequest === controller) {
      grantRequest = undefined;
      submitting.value = false;
    }
  }
}
</script>

<template>
  <section class="egg-grant-page" aria-label="鸡蛋管理">
    <el-card shadow="never">
      <div class="grant-workspace">
        <form class="grant-form" data-testid="egg-player-lookup" aria-label="核对玩家" :aria-busy="lookingUp" @submit.prevent="lookupPlayer">
          <label>
            玩家昵称
            <input v-model="nickname" name="nickname" placeholder="输入完整昵称" maxlength="64" autocomplete="off" required :disabled="submitting || !permitted" />
          </label>
          <el-button size="large" native-type="submit" data-testid="egg-player-lookup-submit" :loading="lookingUp" :disabled="!canLookup">
            核对玩家
          </el-button>
        </form>

        <div v-if="player" class="player-wallet" data-testid="egg-wallet-player" role="status">
          <dl>
            <div><dt>已核对玩家</dt><dd>{{ player.display_name }}</dd></div>
            <div class="player-balance"><dt>当前鸡蛋余额</dt><dd data-testid="egg-player-balance">{{ formatEggs(player.balance) }}</dd></div>
            <div class="player-account"><dt>账号 ID</dt><dd>{{ player.account_id }}</dd></div>
          </dl>
        </div>

        <form class="grant-form" data-testid="egg-grant-form" aria-label="发放鸡蛋" :aria-busy="submitting" @submit.prevent="submit">
          <label>
            鸡蛋数量
            <input v-model="amount" name="amount" type="number" inputmode="numeric" min="1" :max="maxAmount" step="1" placeholder="1–1,000,000" required :disabled="!player || submitting || !permitted" />
          </label>
          <el-button type="primary" size="large" native-type="submit" data-testid="egg-grant-submit" :loading="submitting" :disabled="!canGrant">
            {{ submitting ? '正在发放…' : sameAttempt ? '重试发放' : '发放鸡蛋' }}
          </el-button>
        </form>
        <p v-if="errorMessage" role="alert" class="grant-error">{{ errorMessage }}</p>
      </div>
    </el-card>
    <el-card v-if="receipt" shadow="never" class="grant-receipt" data-testid="egg-grant-receipt">
      <div role="status">
        <h2>鸡蛋已发放</h2>
        <dl>
          <div><dt>玩家昵称</dt><dd>{{ receipt.display_name }}</dd></div>
          <div><dt>发放数量</dt><dd>{{ formatEggs(receipt.amount) }}</dd></div>
          <div><dt>鸡蛋余额</dt><dd>{{ formatEggs(receipt.balance) }}</dd></div>
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
.grant-workspace { display: grid; gap: 18px; }
.grant-form {
  display: grid;
  grid-template-columns: minmax(0, 1fr) max-content;
  align-items: end;
  gap: 10px;
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
.grant-form input:disabled { opacity: .65; }
.grant-form :is(input, button):focus-visible { outline: 2px solid var(--xbd-brand-highlight); outline-offset: 2px; }
.grant-form button { min-height: 44px; margin: 0; }
.grant-error { margin: 0; color: var(--el-color-danger); }
.player-wallet {
  padding: 12px; border: 1px solid var(--xbd-border); border-radius: var(--xbd-radius-sm);
  background: var(--xbd-surface-inset);
}
.player-wallet dl { display: grid; grid-template-columns: repeat(2, minmax(0, 1fr)); gap: 8px; margin: 0; }
.player-wallet dt { color: var(--xbd-text-secondary); }
.player-wallet dd { margin: 4px 0 0; font-weight: 650; overflow-wrap: anywhere; }
.player-balance dd { color: var(--xbd-brand-highlight); font-variant-numeric: tabular-nums; }
.player-account { grid-column: 1 / -1; }
.player-account dd { font: 12px ui-monospace, Consolas, monospace; }
.grant-receipt h2 { margin: 0 0 12px; font-size: 17px; color: var(--xbd-success); }
.grant-receipt dl { display: grid; gap: 8px; margin: 0; }
.grant-receipt dl > div { display: grid; grid-template-columns: 5em minmax(0, 1fr); gap: 8px; }
.grant-receipt dt { color: var(--xbd-text-secondary); }
.grant-receipt dd { margin: 0; overflow-wrap: anywhere; }
@media (max-width: 560px) {
  .grant-form { grid-template-columns: minmax(0, 1fr); }
}
</style>
