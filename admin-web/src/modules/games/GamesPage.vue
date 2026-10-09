<script setup lang="ts">
import { computed, onMounted, reactive } from "vue";
import FilterBar from "../../components/FilterBar.vue";
import StatusTag from "../../components/StatusTag.vue";
import QueryError from "../../components/QueryError.vue";
import { platformApi } from "../../services/api/admin";
import type { GameDescriptor } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { categoryLabel } from "../common/display";
import "../common/readonly-centers.css";

// 游戏中心仅消费已有公共目录，不提供产品或规则配置的写操作。
const { data, loading, errorMessage, run } = useReadOnlyQuery<{ games: GameDescriptor[] }>();
const filters = reactive({ product: "", category: "", enabled: "" });
const applied = reactive({ product: "", category: "", enabled: "" });
const games = computed(() => data.value?.games ?? []);
const categories = computed(() => [...new Set(games.value.map((item) => item.game_category))]);
const rows = computed(() => games.value.filter((item) =>
  (!applied.product || item.product_id.includes(applied.product) || item.name.includes(applied.product)) &&
  (!applied.category || item.game_category === applied.category) &&
  (!applied.enabled || item.enabled === (applied.enabled === "enabled")),
));
const productCount = computed(() => new Set(games.value.map((item) => item.product_id)).size);

/** catalogKey（目录行标识）按产品、游戏、规则集与版本组合，支持同产品多规则。 */
function catalogKey(item: GameDescriptor): string {
  return JSON.stringify([item.product_id, item.game_id, item.rule_set_id, item.rule_version]);
}

/** 查询条件显式应用；刷新仅重新加载真实目录并保留已应用条件。 */
function applyFilters(): void { Object.assign(applied, { ...filters, product: filters.product.trim() }); }
function resetFilters(): void { Object.assign(filters, { product: "", category: "", enabled: "" }); applyFilters(); }
function loadGames(): Promise<void> { return run(() => platformApi.catalog()); }
onMounted(loadGames);
</script>

<template>
  <section class="readonly-center">
    <div class="readonly-heading">
      <div><h2>游戏中心</h2><p>统一查看产品、游戏类别、规则集及版本；目录启用状态仅供查询。</p></div>
      <span v-if="data">{{ productCount }} 个产品 · {{ games.length }} 条规则目录</span>
    </div>
    <FilterBar>
      <el-input v-model="filters.product" data-testid="game-product" clearable placeholder="产品标识 / 名称" aria-label="产品标识或名称" @keyup.enter="applyFilters" />
      <el-select v-model="filters.category" clearable placeholder="游戏类别" aria-label="游戏类别">
        <el-option v-for="category in categories" :key="category" :label="categoryLabel(category)" :value="category" />
      </el-select>
      <el-select v-model="filters.enabled" clearable placeholder="启用状态" aria-label="启用状态">
        <el-option label="已启用" value="enabled" /><el-option label="已停用" value="disabled" />
      </el-select>
      <template #actions>
        <el-button data-testid="game-search" type="primary" size="small" @click="applyFilters">查询</el-button>
        <el-button data-testid="game-reset" size="small" @click="resetFilters">重置</el-button>
        <el-button data-testid="game-refresh" size="small" :loading="loading" @click="loadGames">刷新</el-button>
      </template>
    </FilterBar>
    <QueryError :message="errorMessage" @retry="loadGames" />
    <el-card v-if="!errorMessage" v-loading="loading" class="xbd-section-card readonly-table">
      <el-table :data="rows" size="small" :row-key="catalogKey" :empty-text="loading ? '加载中…' : games.length ? '暂无匹配游戏' : '暂无游戏目录'">
        <el-table-column prop="name" label="游戏名称" min-width="170" />
        <el-table-column prop="product_id" label="产品标识" min-width="190" />
        <el-table-column label="游戏类别" min-width="115"><template #default="{ row }">{{ categoryLabel(row.game_category) }}</template></el-table-column>
        <el-table-column prop="game_id" label="游戏标识" min-width="145" />
        <el-table-column prop="rule_set_id" label="规则集标识" min-width="120" />
        <el-table-column prop="rule_version" label="规则版本" min-width="95" />
        <el-table-column label="启用状态" width="95"><template #default="{ row }"><StatusTag :value="row.enabled ? 'enabled' : 'disabled'" /></template></el-table-column>
      </el-table>
      <div v-if="data" class="readonly-footer"><span>当前匹配 {{ rows.length }} 条规则目录</span><span>数据来源：平台产品目录</span></div>
    </el-card>
  </section>
</template>
