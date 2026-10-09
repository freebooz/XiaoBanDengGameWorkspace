<script setup lang="ts">
import { onMounted, reactive, ref } from "vue";
import FilterBar from "../../components/FilterBar.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import UserDetailDrawer from "./UserDetailDrawer.vue";
import { adminApi } from "../../services/api/admin";
import type { PageResult, UserSummary } from "../../services/api/types";

const loading = ref(false);
const errorMessage = ref("");
const filters = reactive({ keyword: "", status: "" });
const page = ref(1);
const pageSize = ref(20);
const result = ref<PageResult<UserSummary>>({
  items: [], total: 0, page: 1, page_size: 20, data_source: "partial",
});
const selectedUser = ref<UserSummary | null>(null);
const drawerVisible = ref(false);

async function loadUsers(): Promise<void> {
  loading.value = true;
  errorMessage.value = "";
  try {
    result.value = await adminApi.users({
      page: page.value,
      page_size: pageSize.value,
      keyword: filters.keyword.trim() || undefined,
      status: filters.status || undefined,
    });
  } catch (error) {
    errorMessage.value = error instanceof Error ? error.message : "用户数据加载失败";
    result.value = { items: [], total: 0, page: page.value, page_size: pageSize.value, data_source: "partial" };
  } finally {
    loading.value = false;
  }
}

async function applyFilters(): Promise<void> {
  page.value = 1;
  await loadUsers();
}

function openUser(user: UserSummary): void {
  selectedUser.value = user;
  drawerVisible.value = true;
}

function accountTypeLabel(value: string): string {
  if (value === "guest") return "游客";
  if (value === "wechat") return "微信";
  if (value === "phone") return "手机号";
  return value;
}

function formatDate(value: string): string {
  return new Date(value).toLocaleString();
}

onMounted(loadUsers);
</script>

<template>
  <section class="users-page">
    <div class="page-heading">
      <div>
        <h2>用户中心</h2>
        <p>统一查看 AccountId（统一账号标识）、账号类型与基础状态；未持久化信息明确标记待接入。</p>
      </div>
      <DevelopmentBadge v-if="result.data_source === 'development'" label="开发数据" />
    </div>

    <FilterBar>
      <el-input
        v-model="filters.keyword"
        data-testid="user-keyword"
        clearable
        placeholder="AccountId（账号标识）/ 昵称"
        style="width: 250px"
        @keyup.enter="applyFilters"
      />
      <el-select
        v-model="filters.status"
        data-testid="user-status"
        clearable
        placeholder="账号状态"
        style="width: 140px"
      >
        <el-option label="正常" value="active" />
        <el-option label="冻结" value="frozen" />
        <el-option label="停用" value="disabled" />
      </el-select>
      <template #actions>
        <el-button data-testid="user-search" type="primary" @click="applyFilters">查询</el-button>
        <el-button @click="filters.keyword = ''; filters.status = ''; applyFilters()">重置</el-button>
      </template>
    </FilterBar>

    <el-alert
      v-if="errorMessage"
      class="error-alert"
      :title="errorMessage"
      type="error"
      :closable="false"
      show-icon
    />

    <el-card class="xbd-section-card table-card" v-loading="loading">
      <el-table
        :data="result.items"
        size="small"
        empty-text="暂无用户数据"
        table-layout="auto"
      >
        <el-table-column label="AccountId（统一账号标识）" min-width="220">
          <template #default="{ row }">
            <el-button
              :data-testid="'open-user-' + row.account_id"
              class="link-button"
              link
              type="primary"
              @click="openUser(row)"
            >
              {{ row.account_id }}
            </el-button>
          </template>
        </el-table-column>
        <el-table-column prop="display_name" label="昵称" min-width="130" />
        <el-table-column label="登录方式" width="96">
          <template #default="{ row }">{{ accountTypeLabel(row.account_type) }}</template>
        </el-table-column>
        <el-table-column label="微信绑定" width="92"><template #default>待接入</template></el-table-column>
        <el-table-column label="最近登录" width="130"><template #default>待接入</template></el-table-column>
        <el-table-column label="当前在线" width="90"><template #default>待接入</template></el-table-column>
        <el-table-column label="注册时间" min-width="160">
          <template #default="{ row }">{{ formatDate(row.created_at) }}</template>
        </el-table-column>
        <el-table-column label="账号状态" width="90">
          <template #default="{ row }"><StatusTag :value="row.status" /></template>
        </el-table-column>
      </el-table>

      <div class="table-footer">
        <span>共 {{ result.total }} 个账号</span>
        <el-pagination
          v-if="result.total > pageSize"
          v-model:current-page="page"
          v-model:page-size="pageSize"
          background
          layout="prev, pager, next"
          :total="result.total"
          @current-change="loadUsers"
        />
      </div>
    </el-card>

    <UserDetailDrawer
      v-model="drawerVisible"
      :user="selectedUser"
      :data-source="result.data_source"
    />
  </section>
</template>

<style scoped>
.users-page { width: 100%; max-width: 1680px; margin: 0 auto; }
.page-heading { display: flex; align-items: flex-end; justify-content: space-between; gap: 18px; margin-bottom: 14px; }
.page-heading h2 { margin: 0; font-size: 20px; font-weight: 700; }
.page-heading p { margin: 5px 0 0; color: var(--xbd-text-secondary); font-size: 11px; }
.error-alert { margin-bottom: 12px; }
.table-card :deep(.el-card__body) { padding: 0; }
.table-card :deep(.el-table) { width: 100%; }
.table-footer { min-height: 50px; display: flex; align-items: center; justify-content: space-between; padding: 9px 14px; border-top: 1px solid var(--xbd-border); color: var(--xbd-text-secondary); font-size: 10px; }
.link-button { padding: 0; font-size: 11px; }
</style>
