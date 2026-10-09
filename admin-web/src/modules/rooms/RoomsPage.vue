<script setup lang="ts">
import { computed, onMounted, reactive, ref } from "vue";
import FilterBar from "../../components/FilterBar.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import QueryError from "../../components/QueryError.vue";
import RoomDetailDrawer from "./RoomDetailDrawer.vue";
import { adminApi } from "../../services/api/admin";
import type { CollectionResult, RoomSummary } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { formatDate, formatDuration } from "../common/display";
import "../common/readonly-centers.css";

// 房间目录来自当前服务进程，显示查询时点状态；不宣称全节点汇总或持续实时同步。
const { data, loading, errorMessage, run } = useReadOnlyQuery<CollectionResult<RoomSummary>>();
const filters = reactive({ product: "", game: "", rule: "", state: "" });
const selectedId = ref("");
const drawerVisible = ref(false);
const development = computed(() => data.value?.data_source === "development" || data.value?.items.some((item) => item.data_source === "development"));

/** loadRooms（房间查询）只提交后端已支持的四个条件，不补造分页或未知字段。 */
function loadRooms(): Promise<void> {
  const query = { product_id: filters.product.trim() || undefined, game_id: filters.game.trim() || undefined, rule_set_id: filters.rule.trim() || undefined, state: filters.state || undefined };
  return run(() => adminApi.rooms(query));
}
function resetFilters(): void { Object.assign(filters, { product: "", game: "", rule: "", state: "" }); void loadRooms(); }
function openRoom(room: RoomSummary): void { selectedId.value = room.room_id; drawerVisible.value = true; }
onMounted(loadRooms);
</script>

<template>
  <section class="readonly-center">
    <div class="readonly-heading">
      <div><h2>房间中心</h2><p>当前服务节点的房间目录与查询时点状态；时长按服务端返回值展示。</p></div>
      <DevelopmentBadge v-if="development" label="开发数据" />
    </div>
    <FilterBar>
      <el-input v-model="filters.product" data-testid="room-product" clearable placeholder="产品标识" aria-label="产品标识" @keyup.enter="loadRooms" />
      <el-input v-model="filters.game" data-testid="room-game" clearable placeholder="游戏标识" aria-label="游戏标识" @keyup.enter="loadRooms" />
      <el-input v-model="filters.rule" data-testid="room-rule" clearable placeholder="规则集标识" aria-label="规则集标识" @keyup.enter="loadRooms" />
      <el-select v-model="filters.state" clearable filterable allow-create placeholder="房间状态" aria-label="房间状态">
        <el-option label="等待中" value="waiting" /><el-option label="进行中" value="playing" /><el-option label="已结束" value="finished" /><el-option label="已关闭" value="closed" />
      </el-select>
      <template #actions>
        <el-button data-testid="room-search" type="primary" size="small" @click="loadRooms">查询</el-button>
        <el-button data-testid="room-reset" size="small" @click="resetFilters">重置</el-button>
        <el-button data-testid="room-refresh" size="small" :loading="loading" @click="loadRooms">刷新</el-button>
      </template>
    </FilterBar>
    <QueryError :message="errorMessage" @retry="loadRooms" />
    <el-card v-if="!errorMessage" v-loading="loading" class="xbd-section-card readonly-table">
      <el-table :data="data?.items ?? []" size="small" row-key="room_id" :empty-text="loading ? '加载中…' : '暂无房间数据'">
        <el-table-column label="房间标识" min-width="270"><template #default="{ row }"><el-button :data-testid="'open-room-' + row.room_id" class="readonly-link" link type="primary" @click="openRoom(row)">{{ row.room_id }}</el-button></template></el-table-column>
        <el-table-column prop="product_id" label="产品标识" min-width="185" />
        <el-table-column prop="game_id" label="游戏标识" min-width="135" />
        <el-table-column prop="rule_set_id" label="规则集标识" min-width="105" />
        <el-table-column prop="rule_version" label="规则版本" min-width="95" />
        <el-table-column label="房间状态" width="95"><template #default="{ row }"><StatusTag :value="row.state" /></template></el-table-column>
        <el-table-column label="创建时间" min-width="170"><template #default="{ row }">{{ formatDate(row.created_at) }}</template></el-table-column>
        <el-table-column label="已创建时长" min-width="110"><template #default="{ row }">{{ formatDuration(row.duration_seconds) }}</template></el-table-column>
        <el-table-column label="数据来源" width="105"><template #default="{ row }"><DevelopmentBadge v-if="data?.data_source === 'development' || row.data_source === 'development'" label="开发数据" /><span v-else>服务节点</span></template></el-table-column>
      </el-table>
      <div v-if="data" class="readonly-footer"><span>当前查询 {{ data.total }} 个房间</span><span>仅提供只读查询</span></div>
    </el-card>
    <RoomDetailDrawer v-model="drawerVisible" :room-id="selectedId" />
  </section>
</template>
