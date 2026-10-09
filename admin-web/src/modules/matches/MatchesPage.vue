<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import FilterBar from "../../components/FilterBar.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import QueryError from "../../components/QueryError.vue";
import MatchDetailDrawer from "./MatchDetailDrawer.vue";
import { seatLabel, resultReasonLabel } from "./record-display";
import { adminApi } from "../../services/api/admin";
import type { MatchSummary, PageResult } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { formatDate, matchDuration } from "../common/display";
import "../common/readonly-centers.css";

// 对局列表依赖既有持久化分页查询，禁止在当前页做过滤冒充全量查询。
const { data, loading, errorMessage, run } = useReadOnlyQuery<PageResult<MatchSummary>>();
// 混合列表逐行标识开发来源，标题徽章不把真实对局归类为开发数据。
const development = computed(() => data.value?.data_source === "development" || data.value?.items.some((item) => item.source === "development"));
const filters = reactive({ game: "", status: "" });
// 输入草稿与已提交条件分离，翻页、刷新和重试保持当前查询语义。
const applied = reactive({ game: "", status: "" });
const page = ref(1);
const pageSize = 20;
const selectedId = ref("");
const drawerVisible = ref(false);

/** loadMatches（对局查询）发送后端支持的页码、游戏及状态字段。 */
function loadMatches(): Promise<void> {
  const query = { page: page.value, page_size: pageSize, game_id: applied.game || undefined, status: applied.status || undefined };
  return run(() => adminApi.matches(query));
}
function applyFilters(): void { Object.assign(applied, { game: filters.game.trim(), status: filters.status }); page.value = 1; void loadMatches(); }
function resetFilters(): void { Object.assign(filters, { game: "", status: "" }); applyFilters(); }
function changePage(value: number): void { page.value = value; void loadMatches(); }
function openMatch(match: MatchSummary): void { selectedId.value = match.match_id; drawerVisible.value = true; }
onMounted(loadMatches);
</script>

<template>
  <section class="readonly-center">
    <div class="readonly-heading">
      <div><h2>对局中心</h2><p>查询已有对局索引、游戏事件与状态快照；未持久化的业务信息明确标记待接入。</p></div>
      <DevelopmentBadge v-if="development" :label="data?.data_source === 'development' ? '开发数据' : '含开发数据'" />
    </div>
    <FilterBar>
      <el-input v-model="filters.game" data-testid="match-game" clearable placeholder="游戏标识" aria-label="游戏标识" @keyup.enter="applyFilters" />
      <el-select v-model="filters.status" clearable filterable allow-create placeholder="对局状态" aria-label="对局状态">
        <el-option label="待开始" value="created" /><el-option label="等待中" value="waiting" /><el-option label="进行中" value="playing" /><el-option label="已结束" value="finished" /><el-option label="已取消" value="cancelled" /><el-option label="已中止" value="aborted" />
      </el-select>
      <template #actions>
        <el-button data-testid="match-search" type="primary" size="small" @click="applyFilters">查询</el-button>
        <el-button data-testid="match-reset" size="small" @click="resetFilters">重置</el-button>
        <el-button data-testid="match-refresh" size="small" :loading="loading" @click="loadMatches">刷新</el-button>
      </template>
    </FilterBar>
    <QueryError :message="errorMessage" @retry="loadMatches" />
    <el-card v-if="!errorMessage" v-loading="loading" class="xbd-section-card readonly-table">
      <el-table :data="data?.items ?? []" size="small" row-key="match_id" :empty-text="loading ? '加载中…' : '暂无对局数据'">
        <el-table-column label="对局标识" min-width="270"><template #default="{ row }"><el-button :data-testid="'open-match-' + row.match_id" class="readonly-link" link type="primary" @click="openMatch(row)">{{ row.match_id }}</el-button></template></el-table-column>
        <el-table-column prop="product_id" label="产品标识" min-width="185" />
        <el-table-column prop="game_id" label="游戏标识" min-width="135" />
        <el-table-column prop="rule_set_id" label="规则集标识" min-width="105" />
        <el-table-column prop="rule_version" label="规则版本" min-width="95" />
        <el-table-column label="对局状态" width="95"><template #default="{ row }"><StatusTag :value="row.status" /></template></el-table-column>
        <el-table-column label="胜方" min-width="90"><template #default="{ row }">{{ row.winner === undefined ? '待接入' : row.winner ? seatLabel(row.winner) : '暂无胜方' }}</template></el-table-column>
        <el-table-column label="结果原因" min-width="120"><template #default="{ row }">{{ row.result_reason === undefined ? '待接入' : row.result_reason ? resultReasonLabel(row.result_reason) : '暂无结果原因' }}</template></el-table-column>
        <el-table-column label="开始时间" min-width="170"><template #default="{ row }">{{ formatDate(row.started_at, '未开始') }}</template></el-table-column>
        <el-table-column label="结束时间" min-width="170"><template #default="{ row }">{{ formatDate(row.finished_at, '未结束') }}</template></el-table-column>
        <el-table-column label="确定时长" min-width="115"><template #default="{ row }">{{ matchDuration(row.started_at, row.finished_at) }}</template></el-table-column>
        <el-table-column label="数据来源" width="105"><template #default="{ row }"><DevelopmentBadge v-if="data?.data_source === 'development' || row.source === 'development'" label="开发数据" /><span v-else>持久化记录</span></template></el-table-column>
      </el-table>
      <div v-if="data" class="readonly-footer">
        <span>共 {{ data.total }} 个对局</span>
        <el-pagination v-if="data.total > pageSize" :current-page="page" :page-size="pageSize" :total="data.total" background size="small" layout="prev, pager, next" @current-change="changePage" />
      </div>
    </el-card>
    <MatchDetailDrawer v-model="drawerVisible" :match-id="selectedId" />
  </section>
</template>
