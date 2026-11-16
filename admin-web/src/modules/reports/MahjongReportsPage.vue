<script setup lang="ts">
import { onMounted, onUnmounted, ref } from "vue";
import FilterBar from "../../components/FilterBar.vue";
import { mahjongReportsApi } from "../../services/api/admin";
import { ApiError } from "../../services/api/client";
import type { MahjongReport, MahjongReportStatus } from "../../services/api/types";

const pageSize = 20;
const statuses = { pending: "待审核", upheld: "举报成立", dismissed: "已驳回" } as const;
const reasons: Record<string, string> = { abusive_chat: "不当聊天", spam: "刷屏", voice_abuse: "语音滥用", other: "其他" };
const status = ref<MahjongReportStatus | "">("pending");
const page = ref(1);
const total = ref(0);
const items = ref<MahjongReport[]>([]);
const loading = ref(false);
const queueError = ref("");
const selected = ref<MahjongReport | null>(null);
const dialogOpen = ref(false);
const note = ref("");
const disposition = ref<"upheld" | "dismissed" | "">("");
const resolving = ref(false);
const reviewError = ref("");
const success = ref("");
let listGeneration = 0;
let alive = true;

const formatDate = (date: string) => new Date(date).toLocaleString("zh-CN", { hour12: false });

function errorMessage(error: unknown, fallback: string): string {
  if (error instanceof ApiError && error.status === 403) return "当前账号没有麻将举报审核权限";
  return error instanceof Error ? error.message : fallback;
}

async function load(): Promise<void> {
  const generation = ++listGeneration;
  loading.value = true;
  queueError.value = "";
  try {
    const result = await mahjongReportsApi.list(status.value, pageSize, (page.value - 1) * pageSize);
    if (generation !== listGeneration) return;
    const lastPage = Math.max(1, Math.ceil(result.total / pageSize));
    if (page.value > lastPage) {
      page.value = lastPage;
      await load();
      return;
    }
    total.value = result.total;
    items.value = result.items;
  } catch (error) {
    if (generation !== listGeneration) return;
    queueError.value = errorMessage(error, "举报队列加载失败");
    items.value = [];
    total.value = 0;
  } finally {
    if (generation === listGeneration) loading.value = false;
  }
}

function filter(): void {
  page.value = 1;
  success.value = "";
  void load();
}

function openReport(report: MahjongReport): void {
  selected.value = report;
  note.value = "";
  disposition.value = "";
  reviewError.value = "";
  dialogOpen.value = true;
}

async function resolve(): Promise<void> {
  if (!selected.value || selected.value.status !== "pending" || !disposition.value || resolving.value) return;
  const reason = note.value.trim();
  if (Array.from(reason).length > 240 || !/^[\p{L}\p{M}\p{N} .,!?:;()\-。，！？：；、（）—]*$/u.test(reason)) {
    reviewError.value = "备注最多 240 字，可使用文字、数字和常用标点";
    return;
  }
  const reportId = selected.value.report_id;
  resolving.value = true;
  reviewError.value = "";
  success.value = "";
  try {
    const { report } = await mahjongReportsApi.resolve(reportId, disposition.value, reason);
    if (!alive) return;
    dialogOpen.value = false;
    success.value = "处理结果已保存 · " + statuses[report.status];
    await load();
  } catch (error) {
    if (!alive) return;
    if (error instanceof ApiError && error.status === 409) {
      dialogOpen.value = false;
      await load();
      if (alive) queueError.value = "这条举报已由其他审核员处理，队列已更新";
    } else {
      reviewError.value = errorMessage(error, "审核结果保存失败");
    }
  } finally {
    if (alive) resolving.value = false;
  }
}

onMounted(load);
onUnmounted(() => { alive = false; listGeneration++; });
</script>

<template>
  <section class="reports-page">
    <FilterBar>
      <label class="status-filter">
        处理状态
        <select v-model="status" data-testid="report-status" @change="filter">
          <option value="">全部状态</option>
          <option v-for="(label, value) in statuses" :key="value" :value="value">{{ label }}</option>
        </select>
      </label>
      <el-button plain :loading="loading" @click="load">刷新</el-button>
    </FilterBar>
    <el-alert v-if="queueError" :title="queueError" type="error" :closable="false" show-icon />
    <el-alert v-if="success" :title="success" type="success" @close="success = ''" show-icon />
    <el-card class="xbd-section-card" v-loading="loading">
      <el-table :data="items" row-key="report_id" :empty-text="queueError ? '举报列表暂不可用' : '没有符合条件的举报'">
        <el-table-column prop="room_id" label="房间" min-width="76" />
        <el-table-column prop="match_id" label="对局" min-width="130" show-overflow-tooltip />
        <el-table-column label="举报席 → 被举报席" min-width="135">
          <template #default="{ row }">{{ row.reporter_seat + 1 }} → {{ row.target_seat + 1 }}</template>
        </el-table-column>
        <el-table-column label="原因" min-width="100">
          <template #default="{ row }">{{ reasons[row.reason] ?? row.reason }}</template>
        </el-table-column>
        <el-table-column label="提交时间" min-width="170">
          <template #default="{ row }">{{ formatDate(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="状态" min-width="103">
          <template #default="{ row }">
            <el-tag :type="row.status === 'pending' ? 'warning' : row.status === 'upheld' ? 'danger' : 'info'">
              {{ statuses[row.status as MahjongReportStatus] }}
            </el-tag>
          </template>
        </el-table-column>
        <el-table-column label="操作" min-width="100">
          <template #default="{ row }">
            <el-button link type="primary" :data-testid="'report-open-' + row.report_id" @click="openReport(row)">
              {{ row.status === 'pending' ? '审核' : '查看' }}
            </el-button>
          </template>
        </el-table-column>
      </el-table>
      <el-pagination v-if="total > 0" class="queue-pagination" v-model:current-page="page"
        :page-size="pageSize" :total="total" :disabled="loading" layout="total, prev, pager, next"
        @current-change="load" />
    </el-card>

    <el-dialog v-model="dialogOpen" title="麻将举报" width="min(520px, 94vw)"
      :close-on-click-modal="!resolving" :close-on-press-escape="!resolving" :show-close="!resolving">
      <template v-if="selected">
        <dl class="report-summary">
          <dt>房间</dt><dd>{{ selected.room_id }} · {{ selected.match_id }}</dd>
          <dt>座位</dt><dd>{{ selected.reporter_seat + 1 }} 号位举报 {{ selected.target_seat + 1 }} 号位</dd>
          <dt>原因</dt><dd>{{ reasons[selected.reason] ?? selected.reason }}</dd>
          <dt>状态</dt><dd>{{ statuses[selected.status] }}</dd>
          <template v-if="selected.reviewed_at">
            <dt>审核员</dt><dd>{{ selected.analyst }}</dd>
            <dt>审核时间</dt><dd>{{ formatDate(selected.reviewed_at) }}</dd>
            <dt>审核备注</dt><dd>{{ selected.note || "无备注" }}</dd>
          </template>
        </dl>
        <form v-if="selected.status === 'pending'" class="review-form" @submit.prevent="resolve">
          <label for="report-disposition">处理结果</label>
          <select id="report-disposition" v-model="disposition" :disabled="resolving" required>
            <option value="" disabled>请选择</option>
            <option value="upheld">举报成立</option>
            <option value="dismissed">驳回举报</option>
          </select>
          <label for="report-note">审核备注（选填）</label>
          <el-input id="report-note" v-model="note" :disabled="resolving" :maxlength="240" show-word-limit
            placeholder="记录审核依据" />
          <p v-if="reviewError" role="alert" class="review-error">{{ reviewError }}</p>
          <el-button type="primary" native-type="submit" :disabled="!disposition" :loading="resolving">
            确认结案
          </el-button>
        </form>
      </template>
    </el-dialog>
  </section>
</template>

<style scoped>
.reports-page { display: grid; min-width: 0; gap: 14px; }
.status-filter { display: flex; align-items: center; gap: 10px; }
select {
  min-height: 36px;
  min-width: 136px;
  padding: 4px 10px;
  border: 1px solid var(--xbd-border);
  border-radius: 7px;
  color: var(--xbd-text-primary);
  background: var(--el-fill-color-blank);
  font: inherit;
}
.queue-pagination { justify-content: flex-end; margin-top: 14px; flex-wrap: wrap; }
.report-summary { display: grid; grid-template-columns: max-content minmax(0, 1fr); gap: 8px 12px; margin: 0 0 20px; }
.report-summary dt { color: var(--xbd-text-secondary); }
.report-summary dd { margin: 0; overflow-wrap: anywhere; }
.review-form { display: grid; gap: 10px; }
.review-error { color: var(--el-color-danger); margin: 0; }
</style>
