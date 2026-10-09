<script setup lang="ts">
import { watch } from "vue";
import DetailDrawer from "../../components/DetailDrawer.vue";
import StatusTag from "../../components/StatusTag.vue";
import DevelopmentBadge from "../../components/DevelopmentBadge.vue";
import QueryError from "../../components/QueryError.vue";
import { adminApi } from "../../services/api/admin";
import type { RoomSummary } from "../../services/api/types";
import { useReadOnlyQuery } from "../common/useReadOnlyQuery";
import { formatDate, formatDuration } from "../common/display";

// 详情必须重新查询服务端，不能把列表摘要冒充最新详情。
const props = defineProps<{ modelValue: boolean; roomId: string }>();
defineEmits<{ "update:modelValue": [value: boolean] }>();
const { data, loading, errorMessage, run, clear } = useReadOnlyQuery<RoomSummary>();
function loadDetail(): Promise<void> { const id = props.roomId; return run(() => adminApi.roomDetail(id)); }
watch(() => [props.modelValue, props.roomId], () => {
  if (props.modelValue && props.roomId) void loadDetail(); else clear();
}, { immediate: true });
</script>

<template>
  <DetailDrawer :model-value="modelValue" title="房间详情" width="min(680px, 90vw)" @update:model-value="$emit('update:modelValue', $event)">
    <div class="readonly-detail" v-loading="loading">
      <QueryError :message="errorMessage" @retry="loadDetail" />
      <p v-if="loading" class="readonly-loading" role="status">详情加载中…</p>
      <div v-if="data" class="room-detail-data">
        <DevelopmentBadge v-if="data.data_source === 'development'" label="开发数据" />
        <el-descriptions :column="1" border size="small">
          <el-descriptions-item label="房间标识">{{ data.room_id }}</el-descriptions-item>
          <el-descriptions-item label="产品标识">{{ data.product_id }}</el-descriptions-item>
          <el-descriptions-item label="游戏标识">{{ data.game_id }}</el-descriptions-item>
          <el-descriptions-item label="规则集标识">{{ data.rule_set_id }}</el-descriptions-item>
          <el-descriptions-item label="规则版本">{{ data.rule_version }}</el-descriptions-item>
          <el-descriptions-item label="房间状态"><StatusTag :value="data.state" /></el-descriptions-item>
          <el-descriptions-item label="创建时间">{{ formatDate(data.created_at) }}</el-descriptions-item>
          <el-descriptions-item label="已创建时长">{{ formatDuration(data.duration_seconds) }}</el-descriptions-item>
        </el-descriptions>
        <el-empty :image-size="54" description="玩家座位与连接状态待接入" />
      </div>
    </div>
  </DetailDrawer>
</template>
