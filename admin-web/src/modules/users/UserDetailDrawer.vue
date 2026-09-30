<script setup lang="ts">
import DetailDrawer from "../../components/DetailDrawer.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import type { UserSummary } from "../../services/api/types";

defineProps<{
  modelValue: boolean;
  user: UserSummary | null;
  dataSource: "partial" | "development";
}>();
defineEmits<{ "update:modelValue": [value: boolean] }>();

function accountTypeLabel(value?: string): string {
  if (value === "guest") return "游客账号";
  if (value === "wechat") return "微信账号";
  if (value === "phone") return "手机号账号";
  return value || "未知";
}
</script>

<template>
  <DetailDrawer
    :model-value="modelValue"
    title="用户详情"
    width="680px"
    @update:model-value="$emit('update:modelValue', $event)"
  >
    <template v-if="user">
      <div class="drawer-summary">
        <div>
          <span>AccountId（统一账号标识）</span>
          <strong>{{ user.account_id }}</strong>
        </div>
        <DevelopmentBadge v-if="dataSource === 'development'" />
      </div>

      <el-tabs>
        <el-tab-pane label="基础资料">
          <el-descriptions :column="1" border size="small">
            <el-descriptions-item label="昵称">{{ user.display_name }}</el-descriptions-item>
            <el-descriptions-item label="账号类型">{{ accountTypeLabel(user.account_type) }}</el-descriptions-item>
            <el-descriptions-item label="账号状态">{{ user.status }}</el-descriptions-item>
            <el-descriptions-item label="注册时间">{{ new Date(user.created_at).toLocaleString() }}</el-descriptions-item>
          </el-descriptions>
        </el-tab-pane>
        <el-tab-pane label="身份绑定">
          <el-empty :image-size="62" description="数据待接入：微信 OpenID / UnionID 绑定明细" />
        </el-tab-pane>
        <el-tab-pane label="游戏档案">
          <el-empty :image-size="62" description="数据待接入：游戏等级、评分与战绩档案" />
        </el-tab-pane>
        <el-tab-pane label="登录记录">
          <el-empty :image-size="62" description="数据待接入：管理员只读查看登录记录" />
        </el-tab-pane>
        <el-tab-pane label="平台资产">
          <el-empty :image-size="62" description="数据待接入：平台资产仅提供只读视图" />
        </el-tab-pane>
      </el-tabs>
    </template>
  </DetailDrawer>
</template>

<style scoped>
.drawer-summary { display: flex; align-items: flex-start; justify-content: space-between; gap: 16px; margin-bottom: 14px; padding: 13px 14px; border: 1px solid var(--xbd-border); border-radius: 10px; background: #faf7f3; }
.drawer-summary span, .drawer-summary strong { display: block; }
.drawer-summary span { color: var(--xbd-text-secondary); font-size: 10px; }
.drawer-summary strong { margin-top: 5px; font-size: 12px; word-break: break-all; }
</style>
