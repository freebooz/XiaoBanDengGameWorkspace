<script setup lang="ts">
import { computed, onScopeDispose, ref, shallowRef, useId, watch } from "vue";
import { MAHJONG_MANAGE_ROOMS, PLATFORM_READ, useAuthStore } from "../../app/store/auth";
import { mahjongRoomsApi } from "../../services/api/admin";
import { ApiError } from "../../services/api/client";
import type { MahjongRoomAdmissionRequest, MahjongRoomOperation } from "../../services/api/types";
import { displayMonitorTime, type Connection, type Room } from "./monitor";

const props = defineProps<{ room: Room; connection: Connection }>();
const auth = useAuthStore();
const reason = ref("");
const reasonLimit = 160;
const reasonLength = computed(() => Array.from(reason.value.trim()).length);
const reasonHelpID = useId();
const history = shallowRef<MahjongRoomOperation[]>([]);
const revision = computed(() => props.room.mahjong?.admission_revision);
const shownHistory = computed(() => history.value.filter((item) => item.admission_revision <= (revision.value ?? -1)));
const loadingHistory = ref(false);
const historyError = ref("");
const errorMessage = ref("");
const message = ref("");
const permissionRejected = ref(false);
const conflicted = ref(false);
const sending = ref(false);
const retry = shallowRef<MahjongRoomAdmissionRequest>();
const awaiting = shallowRef<MahjongRoomOperation>();
let action: AbortController | undefined;

const hasManagementAccess = computed(() => auth.can(MAHJONG_MANAGE_ROOMS) && auth.can(PLATFORM_READ));
const canAct = computed(() => hasManagementAccess.value && !permissionRejected.value && props.connection === "live" &&
  !!props.room.room_generation && props.room.mahjong?.can_set_admission === true && !conflicted.value &&
  !sending.value && !awaiting.value);

watch([revision, () => props.connection, () => auth.sessionRevision], async (
  [roomRevision, connection], _old, onCleanup,
) => {
  const generation = props.room.room_generation;
  loadingHistory.value = false;
  if (!generation || roomRevision === undefined || connection !== "live" || !auth.can(PLATFORM_READ)) return;

  const controller = new AbortController();
  onCleanup(() => controller.abort());
  loadingHistory.value = true;
  historyError.value = "";
  try {
    const { items } = await mahjongRoomsApi.operations(props.room.room_id, generation, controller.signal);
    if (controller.signal.aborted) return;
    history.value = items.filter((item) => item?.room_id === props.room.room_id && item.room_generation === generation);
  } catch {
    if (!controller.signal.aborted) historyError.value = "暂时无法读取操作记录。";
  } finally {
    if (!controller.signal.aborted) loadingHistory.value = false;
  }
}, { immediate: true });

watch(() => props.room, () => {
  if (conflicted.value && props.connection === "live") {
    conflicted.value = false;
    errorMessage.value = "";
    message.value = "已收到最新房间状态，请确认后再提交。";
  }
});

watch([awaiting, retry, shownHistory, revision, () => props.connection], () => {
  const roomRevision = revision.value;
  if (roomRevision === undefined || props.connection !== "live" || sending.value) return;
  const unconfirmed = retry.value;
  const operation = awaiting.value ?? (unconfirmed && shownHistory.value.find((item) => item.request_id === unconfirmed.request_id));
  if (!operation || operation.admission_revision > roomRevision) return;
  awaiting.value = undefined;
  retry.value = undefined;
  reason.value = "";
  errorMessage.value = "";
  message.value = "操作已记录，房间状态已同步。";
});

function stopAction(): void {
  action?.abort();
  action = undefined;
}

watch(() => auth.sessionRevision, () => {
  stopAction();
  reason.value = "";
  history.value = [];
  historyError.value = "";
  errorMessage.value = "";
  message.value = "";
  permissionRejected.value = false;
  conflicted.value = false;
  sending.value = false;
  retry.value = undefined;
  awaiting.value = undefined;
}, { flush: "sync" });
onScopeDispose(stopAction);

function newRequest(): void {
  const { room_generation: generation, mahjong } = props.room;
  if (!canAct.value || retry.value || !generation || !mahjong || reasonLength.value < 1 || reasonLength.value > reasonLimit) return;
  if (typeof crypto.randomUUID !== "function") {
    errorMessage.value = "请通过 HTTPS 打开管理端后重试。";
    return;
  }
  void submit({ room_generation: generation, expected_revision: mahjong.admission_revision,
    paused: !mahjong.admission_paused, reason: reason.value.trim(), request_id: crypto.randomUUID() });
}

async function submit(request: MahjongRoomAdmissionRequest): Promise<void> {
  if (!canAct.value) return;
  const controller = new AbortController();
  action = controller;
  sending.value = true;
  retry.value = undefined;
  errorMessage.value = "";
  message.value = "";
  const roomID = props.room.room_id;
  try {
    const { operation } = await mahjongRoomsApi.setAdmission(roomID, request, controller.signal);
    if (controller.signal.aborted) return;
    if (!operation || operation.room_id !== roomID || operation.room_generation !== request.room_generation ||
      operation.request_id !== request.request_id || operation.admission_revision !== request.expected_revision + 1 ||
      operation.paused !== request.paused) {
      throw new ApiError("无法确认操作回执", 502, "");
    }
    awaiting.value = operation;
    message.value = "指令已受理，正在同步房间状态。";
  } catch (error) {
    if (controller.signal.aborted) return;
    if (error instanceof ApiError && (error.status === 409 || error.status === 404)) {
      conflicted.value = true;
      errorMessage.value = "房间当前无法应用该操作，正在等待实时状态更新。";
    } else if (error instanceof ApiError && error.status === 403) {
      permissionRejected.value = true;
      errorMessage.value = "当前账号没有麻将房间操作权限。";
    } else if (error instanceof ApiError && error.status > 0 && error.status < 500) {
      errorMessage.value = error.message;
    } else {
      retry.value = request;
      errorMessage.value = "暂时无法确认结果，可按原请求重试。";
    }
  } finally {
    if (action === controller) {
      action = undefined;
      sending.value = false;
    }
  }
}

function discardRetry(): void {
  retry.value = undefined;
  errorMessage.value = "";
}
</script>

<template>
  <section class="admission" aria-label="玩家入座">
    <div class="admission-heading">
      <h3>玩家入座</h3>
      <span class="admission-state" :data-paused="props.room.mahjong?.admission_paused" data-testid="mahjong-admission-state">
        {{ props.room.mahjong?.admission_paused ? "暂停入座" : "开放入座" }}
      </span>
    </div>
    <form v-if="hasManagementAccess && !permissionRejected" class="admission-form" :aria-busy="sending || !!awaiting" @submit.prevent="newRequest">
      <label class="admission-reason">
        <span>操作原因 <small :id="reasonHelpID">{{ reasonLength }} / {{ reasonLimit }} 字符 · 仅后台可见</small></span>
        <textarea v-model="reason" name="reason" rows="2" required :aria-describedby="reasonHelpID"
          :disabled="!canAct || !!retry" :aria-invalid="reasonLength > reasonLimit" />
      </label>
      <div v-if="retry" class="admission-buttons">
        <button type="button" class="primary" data-testid="mahjong-admission-retry" :disabled="!canAct" @click="submit(retry)">重试原操作</button>
        <button type="button" @click="discardRetry">放弃重试</button>
      </div>
      <button v-else type="submit" class="primary" data-testid="mahjong-admission-submit" :disabled="!canAct || !reasonLength || reasonLength > reasonLimit">
        {{ sending ? "正在提交…" : props.room.mahjong?.admission_paused ? "恢复入座" : "暂停入座" }}
      </button>
      <p v-if="props.connection === 'live' && !props.room.mahjong?.can_set_admission" class="admission-note">
        {{ props.room.status === 'waiting' && props.room.players < props.room.capacity && !props.room.phase ? '入座设置暂不可用。' : '好友房候场且有空座时可调整入座设置。' }}
      </p>
    </form>
    <p v-if="errorMessage" class="admission-error" role="alert">{{ errorMessage }}</p>
    <p v-if="message" class="admission-note" role="status">{{ message }}</p>

    <div class="operations" data-testid="mahjong-room-operations">
      <h3>最近操作</h3>
      <ul v-if="shownHistory.length" tabindex="0" :aria-busy="loadingHistory" aria-label="最近操作记录">
        <li v-for="item in shownHistory" :key="item.request_id">
          <div>
            <strong>{{ item.paused ? "暂停入座" : "恢复入座" }}</strong>
            <small>{{ item.admin_name }} · <time :datetime="item.created_at">{{ displayMonitorTime(item.created_at) }}</time></small>
          </div>
          <p>{{ item.reason }}</p>
        </li>
      </ul>
      <p v-if="historyError" class="admission-note" role="status">{{ historyError }}</p>
      <p v-else-if="!shownHistory.length" class="admission-note">{{ loadingHistory ? "正在读取操作记录…" : props.connection === "live" ? "暂无操作记录" : "连接恢复后读取操作记录。" }}</p>
    </div>
  </section>
</template>

<style scoped>
.admission { display: grid; gap: 12px; padding: 16px; min-width: 0; }
.admission h3 { margin: 0; font-size: 15px; }
.admission-heading { display: flex; align-items: center; flex-wrap: wrap; gap: 8px; }
.admission-state {
  padding: 3px 8px; border-radius: 20px; color: var(--xbd-success); background: var(--xbd-success-bg);
  font-size: 12px; font-weight: 650;
}
.admission-state[data-paused="true"] { color: var(--xbd-warning); background: var(--xbd-warning-bg); }
.admission-form { display: flex; align-items: end; flex-wrap: wrap; gap: 10px; }
.admission-reason { flex: 1 1 250px; display: grid; gap: 6px; }
.admission-reason > span { display: flex; align-items: baseline; flex-wrap: wrap; gap: 8px; font-weight: 600; }
.admission small { color: var(--xbd-text-secondary); font-size: 12px; font-weight: 400; overflow-wrap: anywhere; }
.admission textarea, .admission button {
  padding: 8px 12px; min-height: 44px; border: 1px solid var(--xbd-border-control); border-radius: var(--xbd-radius-sm);
  color: var(--xbd-text-primary); background: var(--xbd-surface-inset); font: inherit;
}
.admission textarea { resize: vertical; width: 100%; font-size: 16px; }
.admission textarea[aria-invalid="true"] { border-color: var(--xbd-danger); }
.admission button { font-weight: 650; cursor: pointer; }
.admission .primary { border-color: var(--xbd-brand-primary); color: var(--xbd-text-on-brand); background: var(--xbd-action-surface); }
.admission button:disabled { color: var(--xbd-text-secondary); background: var(--xbd-surface-raised); border-color: var(--xbd-border); cursor: default; }
.admission :is(button, textarea, ul):focus-visible { outline: 2px solid var(--xbd-brand-highlight); outline-offset: 2px; }
.admission-buttons { display: flex; flex-wrap: wrap; gap: 8px; }
.admission-form > .admission-note { width: 100%; }
.admission-note, .admission-error { margin: 0; color: var(--xbd-text-secondary); font-size: 12px; }
.admission-error { color: var(--xbd-danger); }
.operations { display: grid; gap: 8px; padding-top: 12px; border-top: 1px solid var(--xbd-border); }
.operations ul { list-style: none; margin: 0; padding: 0; max-height: 280px; overflow: auto; }
.operations li { padding: 9px 10px; border-bottom: 1px solid var(--xbd-border); overflow-wrap: anywhere; }
.operations li:last-child { border-bottom: 0; }
.operations li div { display: flex; align-items: baseline; flex-wrap: wrap; gap: 4px 10px; }
.operations li p { margin: 4px 0 0; }
@media (max-width: 560px) {
  .admission-form > button { width: 100%; }
}
</style>
