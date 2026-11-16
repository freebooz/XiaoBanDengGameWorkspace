<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import MetricCard from "../../components/MetricCard.vue";
import StatusTag from "../../components/StatusTag.vue";
import { adminApi, platformApi } from "../../services/api/admin";
import type { AdminOverview, GameDescriptor, HealthStatus } from "../../services/api/types";
import { connectionText, countConnectedAccounts, useMonitor } from "../monitor/monitor";

const loading = ref(false);
const offline = ref(false);
const overview = ref<AdminOverview | null>(null);
const health = ref<HealthStatus | null>(null);
const games = ref<GameDescriptor[]>([]);
const { snapshot, connection } = useMonitor();
const onlinePlayers = computed(() => snapshot.value ? countConnectedAccounts(snapshot.value.players) : "--");
const currentRooms = computed(() => snapshot.value?.rooms.length ?? "--");
const playingRooms = computed(() => snapshot.value?.rooms.filter((room) => room.status === "playing").length ?? "--");
const monitorTone = computed(() => connection.value === "live" ? "success" : connection.value === "stale" ? "warning" : "neutral");
const serviceStatus = (name: "api" | "postgres" | "redis") => snapshot.value?.services
  .find((service) => service.id === name)?.status ?? (name === "api" ? health.value?.service : health.value?.[name]);

async function loadDashboard(): Promise<void> {
  if (loading.value) return;
  loading.value = true;
  const [overviewResult, healthResult, catalogResult] = await Promise.allSettled([
    adminApi.overview(),
    platformApi.health(),
    platformApi.catalog(),
  ]);

  overview.value = overviewResult.status === "fulfilled" ? overviewResult.value : null;
  health.value = healthResult.status === "fulfilled" ? healthResult.value : null;
  games.value = catalogResult.status === "fulfilled" ? catalogResult.value.games : [];
  offline.value = healthResult.status === "rejected";
  loading.value = false;
}

onMounted(loadDashboard);
</script>

<template>
  <section class="dashboard-page" v-loading="loading">
    <div class="dashboard-heading">
      <div>
        <div class="dashboard-eyebrow">XIAOBANDENG GAME OPERATIONS · 小板凳游戏运营</div>
        <h2>综合工作台</h2>
        <p>聚合平台运行健康、真实业务规模和一期产品状态。</p>
      </div>
      <el-button plain @click="loadDashboard">刷新数据</el-button>
    </div>

    <el-alert
      v-if="offline && connection !== 'live'"
      class="offline-alert"
      title="服务离线"
      description="业务后端当前不可连接，页面保留可用框架；恢复服务后可直接刷新。"
      type="error"
      :closable="false"
      show-icon
    />

    <div class="metric-grid">
      <MetricCard label="注册用户" :value="overview?.registered_users ?? '--'" caption="accounts 真实数据" tone="brand" />
      <MetricCard label="今日活跃" value="待接入" caption="等待登录行为统计口径" tone="neutral" />
      <MetricCard label="当前在线" :value="onlinePlayers" caption="监视范围内去重账号" :tone="monitorTone" />
      <MetricCard label="实时房间" :value="currentRooms" :caption="snapshot ? '对局中 ' + playingRooms + ' 间' : connectionText[connection]" :tone="monitorTone" />
      <MetricCard label="累计对局" :value="overview?.total_matches ?? '--'" caption="game_matches 真实记录" tone="brand" />
    </div>
    <p class="live-status" role="status" :data-state="connection" data-testid="dashboard-monitor-status">
      {{ connectionText[connection] }}<template v-if="connection === 'stale' && snapshot">，以下保留最后收到的快照</template>
    </p>

    <div class="dashboard-grid">
      <el-card class="xbd-section-card product-card">
        <template #header>
          <div class="card-header">
            <span>一期产品运行概览</span>
            <span class="card-caption">真实 Catalog（游戏目录）</span>
          </div>
        </template>
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
        <el-empty v-else :image-size="70" description="暂无产品目录数据" />
      </el-card>

      <el-card class="xbd-section-card health-card">
        <template #header>
          <div class="card-header">
            <span>服务健康</span>
            <span class="card-caption">{{ snapshot ? "监视快照" : "启动探测" }}</span>
          </div>
        </template>
        <div class="health-list">
          <div>
            <span>业务 API（应用接口）</span>
            <StatusTag :value="serviceStatus('api')" />
          </div>
          <div>
            <span>PostgreSQL（关系数据库）</span>
            <StatusTag :value="serviceStatus('postgres')" />
          </div>
          <div>
            <span>Redis（内存缓存）</span>
            <StatusTag :value="serviceStatus('redis')" />
          </div>
        </div>
      </el-card>
    </div>

    <el-card class="xbd-section-card trend-card">
      <template #header>
        <div class="card-header">
          <span>在线趋势</span>
          <span class="card-caption">一期数据能力预留</span>
        </div>
      </template>
      <div class="trend-placeholder">
        <div class="trend-placeholder__line" />
        <div>
          <strong>待接入</strong>
          <span>在线人数时序统计尚无可靠持久化口径，因此不生成演示曲线。</span>
        </div>
      </div>
    </el-card>
  </section>
</template>

<style scoped>
.dashboard-page { width: 100%; max-width: 1680px; margin: 0 auto; }
.dashboard-heading { display: flex; align-items: flex-end; justify-content: space-between; margin-bottom: 16px; padding: 4px 2px; }
.dashboard-eyebrow { color: var(--xbd-brand-highlight); font-size: 9px; font-weight: 700; letter-spacing: .13em; }
.dashboard-heading h2 { margin: 7px 0 0; font-size: 22px; font-weight: 720; }
.dashboard-heading p { margin: 5px 0 0; color: var(--xbd-text-secondary); font-size: 11px; }
.offline-alert { margin-bottom: 14px; }
.live-status { margin: 8px 2px 0; color: var(--xbd-text-secondary); font-size: 12px; }
.live-status[data-state="stale"] { color: var(--xbd-warning); }
.live-status[data-state="forbidden"] { color: var(--xbd-danger); }
.metric-grid { display: grid; grid-template-columns: repeat(5, minmax(0, 1fr)); gap: 12px; }
.dashboard-grid { display: grid; grid-template-columns: minmax(0, 1.8fr) minmax(280px, .8fr); gap: 14px; margin-top: 14px; }
.card-header { display: flex; align-items: center; justify-content: space-between; gap: 16px; }
.card-caption { color: var(--xbd-text-muted); font-size: 10px; font-weight: 400; }
.health-list { display: grid; gap: 8px; }
.health-list > div { display: flex; align-items: center; justify-content: space-between; padding: 10px 11px; border: 1px solid var(--xbd-border); border-radius: 9px; background: var(--xbd-surface-inset); font-size: 11px; }
.trend-card { margin-top: 14px; }
.trend-placeholder { min-height: 126px; display: flex; align-items: center; justify-content: center; gap: 22px; color: var(--xbd-text-secondary); }
.trend-placeholder__line { position: relative; width: 180px; height: 62px; border-bottom: 1px solid var(--xbd-border); background: linear-gradient(180deg, var(--xbd-brand-tint), transparent); clip-path: polygon(0 70%, 16% 54%, 32% 62%, 51% 28%, 69% 44%, 84% 18%, 100% 34%, 100% 100%, 0 100%); }
.trend-placeholder strong, .trend-placeholder span { display: block; }
.trend-placeholder strong { color: var(--xbd-text-primary); font-size: 15px; }
.trend-placeholder span { max-width: 420px; margin-top: 7px; font-size: 11px; line-height: 1.7; }
@media (max-width: 1366px) {
  .metric-grid { grid-template-columns: repeat(5, minmax(150px, 1fr)); overflow-x: auto; padding-bottom: 3px; }
  .dashboard-grid { grid-template-columns: minmax(0, 1.55fr) 280px; }
}
</style>
