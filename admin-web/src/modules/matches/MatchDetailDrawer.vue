<script setup lang="ts">
import { computed, ref, watch } from "vue";
import DetailDrawer from "../../components/DetailDrawer.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import QueryError from "../../components/QueryError.vue";
import { adminApi } from "../../services/api/admin";
import type { MatchDetail } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { formatDate, formatJSON, matchDuration } from "../common/display";

// 对局抽屉仅展示后端实际返回的摘要、事件、快照，缺失玩家和回放数据不推测补全。
const props = defineProps<{ modelValue: boolean; matchId: string }>();
defineEmits<{ "update:modelValue": [value: boolean] }>();
const { data, loading, errorMessage, run, clear } = useReadOnlyQuery<MatchDetail>();
const tab = ref("summary");
const eventPage = ref(1);
const snapshotPage = ref(1);
const recordPageSize = 20;
// 详情接口一次返回全部记录；客户端分页限制同时创建的 DOM（页面元素）数量。
const events = computed(() => data.value?.events.slice((eventPage.value - 1) * recordPageSize, eventPage.value * recordPageSize) ?? []);
const snapshots = computed(() => data.value?.snapshots.slice((snapshotPage.value - 1) * recordPageSize, snapshotPage.value * recordPageSize) ?? []);

function loadDetail(): Promise<void> { const id = props.matchId; return run(() => adminApi.matchDetail(id)); }
watch(() => [props.modelValue, props.matchId], () => {
  tab.value = "summary";
  eventPage.value = 1;
  snapshotPage.value = 1;
  if (props.modelValue && props.matchId) void loadDetail(); else clear();
}, { immediate: true });
</script>

<template>
  <DetailDrawer :model-value="modelValue" title="对局详情" width="min(760px, 90vw)" @update:model-value="$emit('update:modelValue', $event)">
    <div class="readonly-detail" v-loading="loading">
      <QueryError :message="errorMessage" @retry="loadDetail" />
      <p v-if="loading" class="readonly-loading" role="status">详情加载中…</p>
      <div v-if="data" class="match-detail-data">
        <DevelopmentBadge v-if="data.data_source === 'development'" label="开发数据" />
        <el-tabs v-model="tab">
          <el-tab-pane name="summary" label="对局摘要">
            <el-descriptions :column="1" border size="small">
              <el-descriptions-item label="对局标识">{{ data.summary.match_id }}</el-descriptions-item>
              <el-descriptions-item label="产品标识">{{ data.summary.product_id }}</el-descriptions-item>
              <el-descriptions-item label="游戏标识">{{ data.summary.game_id }}</el-descriptions-item>
              <el-descriptions-item label="规则集标识">{{ data.summary.rule_set_id }}</el-descriptions-item>
              <el-descriptions-item label="规则版本">{{ data.summary.rule_version }}</el-descriptions-item>
              <el-descriptions-item label="对局状态"><StatusTag :value="data.summary.status" /></el-descriptions-item>
              <el-descriptions-item label="创建时间">{{ formatDate(data.summary.created_at) }}</el-descriptions-item>
              <el-descriptions-item label="开始时间">{{ formatDate(data.summary.started_at, '未开始') }}</el-descriptions-item>
              <el-descriptions-item label="结束时间">{{ formatDate(data.summary.finished_at, '未结束') }}</el-descriptions-item>
              <el-descriptions-item label="确定时长">{{ matchDuration(data.summary.started_at, data.summary.finished_at) }}</el-descriptions-item>
            </el-descriptions>
            <p class="xbd-empty-note">玩家明细与结算信息待接入。</p>
          </el-tab-pane>
          <el-tab-pane name="events" label="游戏事件" lazy>
            <el-empty v-if="!data.events.length" :image-size="54" description="暂无事件记录" />
            <div v-else class="readonly-records">
              <article v-for="(event, index) in events" :key="event.sequence + ':' + index" class="readonly-record">
                <header><strong>序号 {{ event.sequence }} · 事件类型：{{ event.event_type }}</strong><span>{{ formatDate(event.created_at) }}</span></header>
                <pre class="readonly-json event-payload">{{ formatJSON(event.payload) }}</pre>
              </article>
            </div>
            <div v-if="data.events.length > recordPageSize" class="readonly-footer"><span>{{ data.events.length }} 条事件</span><el-pagination v-model:current-page="eventPage" :page-size="recordPageSize" :total="data.events.length" size="small" layout="prev, pager, next" /></div>
          </el-tab-pane>
          <el-tab-pane name="snapshots" label="状态快照" lazy>
            <el-empty v-if="!data.snapshots.length" :image-size="54" description="暂无快照记录" />
            <div v-else class="readonly-records">
              <article v-for="(snapshot, index) in snapshots" :key="snapshot.sequence + ':' + index" class="readonly-record">
                <header><strong>序号 {{ snapshot.sequence }}</strong><span>{{ formatDate(snapshot.created_at) }}</span></header>
                <pre class="readonly-json">{{ formatJSON(snapshot.snapshot) }}</pre>
              </article>
            </div>
            <div v-if="data.snapshots.length > recordPageSize" class="readonly-footer"><span>{{ data.snapshots.length }} 条快照</span><el-pagination v-model:current-page="snapshotPage" :page-size="recordPageSize" :total="data.snapshots.length" size="small" layout="prev, pager, next" /></div>
          </el-tab-pane>
          <el-tab-pane name="replay" label="回放" lazy><el-empty :image-size="54" description="回放服务待接入，当前仅支持事件与快照的只读查看" /></el-tab-pane>
        </el-tabs>
      </div>
    </div>
  </DetailDrawer>
</template>
