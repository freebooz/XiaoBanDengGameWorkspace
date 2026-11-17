<script setup lang="ts">
import StatusTag from "../../components/StatusTag.vue";
import type { GameDescriptor } from "../../services/api/types";

defineProps<{ games: GameDescriptor[]; emptyText: string }>();
</script>

<template>
  <el-table v-if="games.length" :data="games" size="small">
    <el-table-column prop="name" label="产品" min-width="150" />
    <el-table-column prop="game_id" label="GameId（游戏标识）" min-width="150" />
    <el-table-column prop="rule_set_id" label="RuleSetId（规则集）" min-width="130" />
    <el-table-column prop="rule_version" label="规则版本" width="96" />
    <el-table-column label="状态" width="82">
      <template #default="{ row }">
        <StatusTag :value="row.enabled ? 'enabled' : 'disabled'" />
      </template>
    </el-table-column>
  </el-table>
  <el-empty v-else :image-size="70" :description="emptyText" />
</template>
