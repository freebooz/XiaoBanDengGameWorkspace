<script setup lang="ts">
import type { RoomPlayer } from "../../services/api/types";

// 只展示真实客户端连接；未知座位原样保留，不补造认证账号。
defineProps<{ players: RoomPlayer[] }>();
function seatLabel(seat: string): string {
  return ({ red: "红方", black: "黑方", spectator: "观战" } as Record<string, string>)[seat] ?? seat;
}
</script>

<template>
  <el-table :data="players" size="small" empty-text="暂无玩家" class="room-players">
    <el-table-column prop="client_id" label="客户端标识" min-width="170" />
    <el-table-column label="座位" min-width="85"><template #default="{ row }">{{ seatLabel(row.seat) }}</template></el-table-column>
    <el-table-column label="连接状态" width="100"><template #default="{ row }"><el-tag :type="row.connected ? 'success' : 'info'" size="small">{{ row.connected ? '已连接' : '已断开' }}</el-tag></template></el-table-column>
  </el-table>
</template>

<style scoped>
.room-players { margin-top: 12px; font-size: 11px; }
</style>
