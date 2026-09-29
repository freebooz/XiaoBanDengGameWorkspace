<script setup lang="ts">
import { computed, onMounted, ref } from "vue";
import { ElMessage } from "element-plus";
import { api, type GameDescriptor, type HealthStatus } from "./api";

type MenuKey =
  | "dashboard"
  | "users"
  | "products"
  | "rooms"
  | "matches"
  | "commerce"
  | "ai"
  | "system";

const activeMenu = ref<MenuKey>("dashboard");
const health = ref<HealthStatus | null>(null);
const games = ref<GameDescriptor[]>([]);
const aiCapabilities = ref<Array<{ key: string; name: string; description: string; enabled: boolean }>>([]);
const loading = ref(false);

const menuItems: Array<{ key: MenuKey; label: string; description: string }> = [
  { key: "dashboard", label: "综合工作台", description: "平台运行状态与一期产品总览" },
  { key: "users", label: "用户中心", description: "统一账号、微信绑定与游戏档案" },
  { key: "products", label: "产品与游戏", description: "ProductId / GameId / RuleSetId / RuleVersion" },
  { key: "rooms", label: "房间中心", description: "实时房间、匹配与在线状态" },
  { key: "matches", label: "对局中心", description: "事件流、快照、战绩与回放" },
  { key: "commerce", label: "商业中心", description: "商品、支付订单、钱包账本与资产范围" },
  { key: "ai", label: "AI中心", description: "陪练、教学、提示、残局与复盘功能开关" },
  { key: "system", label: "系统管理", description: "配置、版本、渠道、日志与权限" },
];

const pageInfo = computed(
  () => menuItems.find((item) => item.key === activeMenu.value) ?? menuItems[0],
);

async function refresh(): Promise<void> {
  loading.value = true;
  try {
    const [healthResult, catalogResult, aiResult] = await Promise.all([
      api.health(),
      api.catalog(),
      api.aiCapabilities(),
    ]);
    health.value = healthResult;
    games.value = catalogResult.games;
    aiCapabilities.value = aiResult;
  } catch (error) {
    ElMessage.warning("后端尚未就绪：" + String(error));
  } finally {
    loading.value = false;
  }
}

function onMenuSelect(key: string): void {
  activeMenu.value = key as MenuKey;
}

onMounted(refresh);
</script>

<template>
  <el-container class="layout">
    <el-aside width="220px" class="sidebar">
      <div class="brand">
        <div class="brand-mark">凳</div>
        <div>
          <strong>小板凳</strong>
          <span>统一运营后台</span>
        </div>
      </div>
      <el-menu :default-active="activeMenu" @select="onMenuSelect">
        <el-menu-item v-for="item in menuItems" :key="item.key" :index="item.key">
          {{ item.label }}
        </el-menu-item>
      </el-menu>
    </el-aside>

    <el-container>
      <el-header class="header">
        <div>
          <h1>{{ pageInfo.label }}</h1>
          <p>{{ pageInfo.description }}</p>
        </div>
        <el-button :loading="loading" @click="refresh">刷新状态</el-button>
      </el-header>

      <el-main>
        <template v-if="activeMenu === 'dashboard'">
          <div class="grid">
            <el-card>
              <template #header>业务服务</template>
              <el-tag :type="health?.service === 'ok' ? 'success' : 'warning'">
                {{ health?.service ?? "未连接" }}
              </el-tag>
            </el-card>
            <el-card>
              <template #header>PostgreSQL</template>
              <el-tag :type="health?.postgres === 'ok' ? 'success' : 'warning'">
                {{ health?.postgres ?? "未连接" }}
              </el-tag>
            </el-card>
            <el-card>
              <template #header>Redis</template>
              <el-tag :type="health?.redis === 'ok' ? 'success' : 'warning'">
                {{ health?.redis ?? "未连接" }}
              </el-tag>
            </el-card>
          </div>
          <el-card class="section-card">
            <template #header>一期产品</template>
            <el-table :data="games" size="small">
              <el-table-column prop="name" label="产品" min-width="180" />
              <el-table-column prop="product_id" label="ProductId（产品标识）" min-width="180" />
              <el-table-column prop="game_id" label="GameId（游戏标识）" min-width="160" />
              <el-table-column prop="rule_set_id" label="RuleSetId（规则集）" min-width="140" />
              <el-table-column prop="rule_version" label="规则版本" width="110" />
            </el-table>
          </el-card>
        </template>

        <template v-else-if="activeMenu === 'products'">
          <el-card>
            <template #header>产品 / 游戏 / 规则集</template>
            <el-table :data="games" size="small">
              <el-table-column prop="name" label="名称" min-width="180" />
              <el-table-column prop="game_category" label="类别" width="100" />
              <el-table-column prop="game_id" label="GameId" min-width="150" />
              <el-table-column prop="rule_set_id" label="RuleSetId" min-width="130" />
              <el-table-column prop="rule_version" label="RuleVersion" width="130" />
            </el-table>
          </el-card>
        </template>

        <template v-else-if="activeMenu === 'ai'">
          <el-alert
            title="AI是旁路智能能力，不参与正式多人对局的权威规则判定。"
            type="info"
            :closable="false"
            show-icon
          />
          <el-card class="section-card">
            <template #header>AI能力预留</template>
            <el-table :data="aiCapabilities" size="small">
              <el-table-column prop="name" label="能力" width="140" />
              <el-table-column prop="key" label="Feature Flag（功能开关）" min-width="220" />
              <el-table-column prop="description" label="说明" min-width="260" />
            </el-table>
          </el-card>
        </template>

        <template v-else>
          <el-card>
            <template #header>{{ pageInfo.label }}</template>
            <el-empty description="一期已预留模块边界；后续在当前统一后台内增量实现，不另建后台。" />
          </el-card>
        </template>
      </el-main>
    </el-container>
  </el-container>
</template>