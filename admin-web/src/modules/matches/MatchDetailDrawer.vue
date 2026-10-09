<script setup lang="ts">
import { computed, ref, watch } from "vue";
import DetailDrawer from "../../components/DetailDrawer.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import QueryError from "../../components/QueryError.vue";
import SnapshotBoard from "./SnapshotBoard.vue";
import { seatLabel, resultReasonLabel } from "./record-display";
import { adminApi } from "../../services/api/admin";
import type { MatchDetail } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { formatDate, formatJSON, matchDuration } from "../common/display";

// 对局记录使用服务端独立分页，不把页内数组长度当作全局总量。
const props = defineProps<{ modelValue: boolean; matchId: string }>();
defineEmits<{ "update:modelValue": [value: boolean] }>();
const { data, loading, errorMessage, run, clear } = useReadOnlyQuery<MatchDetail>();
const tab = ref("summary");
const eventPage = ref(1);
const snapshotPage = ref(1);
const recordPageSize = ref(20);
const replayIndex = ref(0);
const recordsReady = ref(false);
const recordMetadata = ref<Pick<MatchDetail, "event_total" | "snapshot_total" | "event_page" | "snapshot_page" | "record_page_size"> | null>(null);
let requestGeneration = 0;
let pendingReplayTarget: "first" | "last" | null = null;

function validInteger(value: unknown, minimum: number): value is number {
  return typeof value === "number" && Number.isInteger(value) && value >= minimum;
}
const eventPagination = computed(() => validInteger(recordMetadata.value?.event_total, 0)
  && validInteger(recordMetadata.value?.event_page, 1) && validInteger(recordMetadata.value?.record_page_size, 1));
const snapshotPagination = computed(() => validInteger(recordMetadata.value?.snapshot_total, 0)
  && validInteger(recordMetadata.value?.snapshot_page, 1) && validInteger(recordMetadata.value?.record_page_size, 1));
const replaySnapshot = computed(() => data.value?.snapshots[replayIndex.value]);
const replayPosition = computed(() => snapshotPagination.value
  ? (snapshotPage.value - 1) * recordPageSize.value + replayIndex.value + 1
  : replayIndex.value + 1);
const canReplayPrevious = computed(() => Boolean(replaySnapshot.value) && !loading.value
  && (replayIndex.value > 0 || (snapshotPagination.value && snapshotPage.value > 1)));
const canReplayNext = computed(() => Boolean(replaySnapshot.value) && !loading.value
  && (replayIndex.value < (data.value?.snapshots.length ?? 0) - 1
    || (snapshotPagination.value && replayPosition.value < (recordMetadata.value?.snapshot_total ?? 0))));

/** 每次请求完整保留两个领域页码；查询代次同时保护数据、页码和回放游标。 */
async function loadDetail(): Promise<void> {
  const generation = ++requestGeneration;
  const id = props.matchId;
  const query = { event_page: eventPage.value, snapshot_page: snapshotPage.value, record_page_size: recordPageSize.value };
  const previousSnapshotPage = recordMetadata.value?.snapshot_page;
  await run(() => adminApi.matchDetail(id, query));
  if (generation !== requestGeneration || !data.value) return;
  const result = data.value;
  if (validInteger(result.event_page, 1)) eventPage.value = result.event_page;
  if (validInteger(result.snapshot_page, 1)) snapshotPage.value = result.snapshot_page;
  if (validInteger(result.record_page_size, 1)) recordPageSize.value = result.record_page_size;
  recordMetadata.value = {
    event_total: result.event_total, snapshot_total: result.snapshot_total,
    event_page: result.event_page, snapshot_page: result.snapshot_page, record_page_size: result.record_page_size,
  };
  recordsReady.value = true;
  if (pendingReplayTarget === "last") replayIndex.value = Math.max(0, result.snapshots.length - 1);
  else if (pendingReplayTarget === "first" || result.snapshot_page !== previousSnapshotPage) replayIndex.value = 0;
  else replayIndex.value = Math.min(replayIndex.value, Math.max(0, result.snapshots.length - 1));
  pendingReplayTarget = null;
}
function changeEventPage(value: number): void { eventPage.value = value; void loadDetail(); }
function changeSnapshotPage(value: number, target: "first" | "last" = "first"): void {
  snapshotPage.value = value;
  pendingReplayTarget = target;
  void loadDetail();
}
function replayPrevious(): void {
  if (!canReplayPrevious.value) return;
  if (replayIndex.value > 0) replayIndex.value -= 1;
  else changeSnapshotPage(snapshotPage.value - 1, "last");
}
function replayNext(): void {
  if (!canReplayNext.value) return;
  if (replayIndex.value < (data.value?.snapshots.length ?? 0) - 1) replayIndex.value += 1;
  else changeSnapshotPage(snapshotPage.value + 1);
}
watch(() => [props.modelValue, props.matchId], () => {
  requestGeneration += 1;
  clear();
  tab.value = "summary";
  eventPage.value = 1;
  snapshotPage.value = 1;
  recordPageSize.value = 20;
  replayIndex.value = 0;
  pendingReplayTarget = null;
  recordsReady.value = false;
  recordMetadata.value = null;
  if (props.modelValue && props.matchId) void loadDetail();
}, { immediate: true });
</script>

<template>
  <DetailDrawer :model-value="modelValue" title="对局详情" width="min(760px, 90vw)" @update:model-value="$emit('update:modelValue', $event)">
    <div class="readonly-detail" v-loading="loading">
      <QueryError :message="errorMessage" @retry="loadDetail" />
      <p v-if="loading" class="readonly-loading" role="status">详情加载中…</p>
      <div v-if="data || recordsReady" class="match-detail-data">
        <DevelopmentBadge v-if="data?.data_source === 'development' || data?.summary.source === 'development'" label="开发数据" />
        <el-tabs v-model="tab">
          <el-tab-pane name="summary" label="对局摘要">
            <template v-if="data">
              <el-descriptions :column="1" border size="small">
                <el-descriptions-item label="对局标识">{{ data.summary.match_id }}</el-descriptions-item>
                <el-descriptions-item label="关联房间">{{ data.summary.room_id === undefined ? '关联房间待接入' : data.summary.room_id || '暂无关联房间' }}</el-descriptions-item>
                <el-descriptions-item label="产品标识">{{ data.summary.product_id }}</el-descriptions-item>
                <el-descriptions-item label="游戏标识">{{ data.summary.game_id }}</el-descriptions-item>
                <el-descriptions-item label="规则集标识">{{ data.summary.rule_set_id }}</el-descriptions-item>
                <el-descriptions-item label="规则版本">{{ data.summary.rule_version }}</el-descriptions-item>
                <el-descriptions-item label="对局状态"><StatusTag :value="data.summary.status" /></el-descriptions-item>
                <el-descriptions-item label="创建时间">{{ formatDate(data.summary.created_at) }}</el-descriptions-item>
                <el-descriptions-item label="开始时间">{{ formatDate(data.summary.started_at, '未开始') }}</el-descriptions-item>
                <el-descriptions-item label="结束时间">{{ formatDate(data.summary.finished_at, '未结束') }}</el-descriptions-item>
                <el-descriptions-item label="确定时长">{{ matchDuration(data.summary.started_at, data.summary.finished_at) }}</el-descriptions-item>
                <el-descriptions-item label="胜方">{{ data.summary.winner === undefined ? '胜方待接入' : data.summary.winner ? seatLabel(data.summary.winner) : '暂无胜方' }}</el-descriptions-item>
                <el-descriptions-item label="结果原因">{{ data.summary.result_reason === undefined ? '结果原因待接入' : data.summary.result_reason ? resultReasonLabel(data.summary.result_reason) : '暂无结果原因' }}</el-descriptions-item>
              </el-descriptions>
              <p v-if="data.summary.winner === undefined && data.summary.result_reason === undefined" class="xbd-empty-note">结算信息待接入。</p>
              <el-table v-if="data.players !== undefined" :data="data.players" size="small" empty-text="暂无持久化玩家" class="match-players">
                <el-table-column prop="client_id" label="客户端标识" min-width="170" />
                <el-table-column label="座位" min-width="85"><template #default="{ row }">{{ seatLabel(row.seat) }}</template></el-table-column>
                <el-table-column label="入座时间" min-width="160"><template #default="{ row }">{{ formatDate(row.joined_at) }}</template></el-table-column>
              </el-table>
              <p v-else class="xbd-empty-note">玩家明细待接入。</p>
            </template>
          </el-tab-pane>
          <el-tab-pane name="events" label="游戏事件" lazy>
            <template v-if="data">
              <el-empty v-if="!data.events.length" :image-size="54" description="暂无事件记录" />
              <div v-else class="readonly-records">
                <article v-for="(event, index) in data.events" :key="event.sequence + ':' + index" class="readonly-record">
                  <header><strong>序号 {{ event.sequence }} · 事件类型：{{ event.event_type }}</strong><span>{{ formatDate(event.created_at) }}</span></header>
                  <pre class="readonly-json event-payload">{{ formatJSON(event.payload) }}</pre>
                </article>
              </div>
            </template>
            <div v-if="eventPagination" class="readonly-footer"><span>共 {{ recordMetadata?.event_total }} 条事件</span><el-pagination v-if="(recordMetadata?.event_total ?? 0) > recordPageSize" data-testid="event-pagination" :current-page="eventPage" :page-size="recordPageSize" :total="recordMetadata?.event_total" size="small" layout="prev, pager, next" @current-change="changeEventPage" /></div>
            <p v-else-if="data" class="xbd-empty-note">分页信息待接入；仅展示本次返回的事件。</p>
          </el-tab-pane>
          <el-tab-pane name="snapshots" label="状态快照" lazy>
            <template v-if="data">
              <el-empty v-if="!data.snapshots.length" :image-size="54" description="暂无快照记录" />
              <div v-else class="readonly-records">
                <article v-for="(snapshot, index) in data.snapshots" :key="snapshot.sequence + ':' + index" class="readonly-record">
                  <header><strong>序号 {{ snapshot.sequence }}</strong><span>{{ formatDate(snapshot.created_at) }}</span></header>
                  <pre class="readonly-json">{{ formatJSON(snapshot.snapshot) }}</pre>
                </article>
              </div>
            </template>
            <div v-if="snapshotPagination" class="readonly-footer"><span>共 {{ recordMetadata?.snapshot_total }} 条快照</span><el-pagination v-if="(recordMetadata?.snapshot_total ?? 0) > recordPageSize" data-testid="snapshot-pagination" :current-page="snapshotPage" :page-size="recordPageSize" :total="recordMetadata?.snapshot_total" size="small" layout="prev, pager, next" @current-change="changeSnapshotPage" /></div>
            <p v-else-if="data" class="xbd-empty-note">分页信息待接入；仅展示本次返回的快照。</p>
          </el-tab-pane>
          <el-tab-pane name="replay" label="回放" lazy>
            <p class="xbd-empty-note">持久化快照逐帧查看；帧间不推演走子，不代表完整游戏过程。</p>
            <p v-if="!snapshotPagination && data" class="xbd-empty-note">分页信息待接入，仅能查看本次返回的快照。</p>
            <template v-if="replaySnapshot">
              <div class="readonly-footer replay-controls">
                <span v-if="snapshotPagination">第 {{ replayPosition }} / {{ recordMetadata?.snapshot_total }} 帧</span>
                <span v-else>本次返回第 {{ replayIndex + 1 }} / {{ data?.snapshots.length }} 帧</span>
                <div><el-button data-testid="replay-previous" size="small" :disabled="!canReplayPrevious" @click="replayPrevious">上一步</el-button><el-button data-testid="replay-next" size="small" :disabled="!canReplayNext" @click="replayNext">下一步</el-button></div>
              </div>
              <article class="readonly-record">
                <header><strong>序号 {{ replaySnapshot.sequence }}</strong><span>{{ formatDate(replaySnapshot.created_at) }}</span></header>
                <SnapshotBoard :snapshot="replaySnapshot.snapshot" />
                <pre class="readonly-json replay-snapshot">{{ formatJSON(replaySnapshot.snapshot) }}</pre>
              </article>
            </template>
            <el-empty v-else-if="data" :image-size="54" :description="snapshotPagination && (recordMetadata?.snapshot_total ?? 0) > 0 ? '当前页暂无快照，请在状态快照中选择其他页' : '本次返回暂无持久化快照，无法回放'" />
          </el-tab-pane>
        </el-tabs>
      </div>
    </div>
  </DetailDrawer>
</template>

<style scoped>
.match-players { margin-top: 12px; font-size: 11px; }
.replay-controls { padding: 8px 0; margin-bottom: 8px; border-top: 0; }
.replay-controls .el-button { font-size: 11px; }
</style>
