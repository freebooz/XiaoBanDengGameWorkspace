<script setup lang="ts">
import { computed, ref } from "vue";
import { connectionText, countConnectedAccounts, useMonitor } from "./monitor";

const props = withDefaults(defineProps<{ roomsOnly?: boolean; matchesOnly?: boolean }>(),
  { roomsOnly: false, matchesOnly: false });
const { snapshot, connection } = useMonitor();
const gameFilter = ref("");
const search = ref("");
const needle = computed(() => search.value.trim().toLowerCase());
const gameNames: Record<string, string> = {
  chinese_chess: "中国象棋", mahjong: "麻将", landlord: "斗地主", guandan: "掼蛋",
};
const serviceNames: Record<string, string> = { api: "游戏 API", postgres: "PostgreSQL", redis: "Redis" };
const stateNames: Record<string, string> = {
  ok: "正常", unavailable: "不可用", draining: "停止接入中",
  lobby: "大厅在线", waiting: "等待中", ready: "已准备", matched: "已匹配", playing: "对局中",
  reconnecting: "等待重连", settled: "已结算", finished: "已结束", closed: "已关闭",
  turn: "出牌", reaction: "接牌响应", settling: "结算中", entering: "正在入桌", saving: "正在保存",
};
const kindNames: Record<string, string> = { friend: "好友房", quick: "快速匹配", training: "训练房" };
const heat: Record<string, string> = {
  ok: "success", unavailable: "danger", draining: "warn",
  lobby: "success", waiting: "warn", playing: "success", reconnecting: "warn",
};
const dateFormatter = new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "medium" });
const matchesSearch = (...values: (string | undefined)[]) => !needle.value ||
  values.some((value) => value?.toLowerCase().includes(needle.value));
const matchesGame = (gameID: string) => !gameFilter.value || gameFilter.value === gameID;
const gameName = (id: string) => gameNames[id] ?? id;
const stateName = (id: string) => stateNames[id] ?? (id || "—");

const lobbies = computed(() => snapshot.value?.lobbies.filter((lobby) => matchesGame(lobby.game_id)) ?? []);
const matchStatuses = new Set(["playing", "finished", "settled"]);
const rooms = computed(() => snapshot.value?.rooms.filter((room) =>
  (!props.matchesOnly || matchStatuses.has(room.status)) && matchesGame(room.game_id) &&
  matchesSearch(room.room_id, room.rule_set_id, gameName(room.game_id))) ?? []);
const players = computed(() => snapshot.value?.players.filter((player) =>
  (!props.matchesOnly || matchStatuses.has(player.room_status ?? "")) && matchesGame(player.game_id) &&
  matchesSearch(player.account_id, player.display_name, player.room_id)) ?? []);
const gameOptions = computed(() => [...new Set([
  ...(snapshot.value?.lobbies ?? []).map((lobby) => lobby.game_id),
  ...(snapshot.value?.rooms ?? []).map((room) => room.game_id),
  ...(snapshot.value?.players ?? []).map((player) => player.game_id),
])]);
const connectedAccounts = computed(() => countConnectedAccounts(snapshot.value?.players ?? []));
const inLobby = computed(() => {
  const counts = new Map<string, number>();
  for (const player of snapshot.value?.players ?? []) {
    if (player.connected && player.status === "lobby") {
      counts.set(player.game_id, (counts.get(player.game_id) ?? 0) + 1);
    }
  }
  return counts;
});
const playingRooms = computed(() => snapshot.value?.rooms.filter((room) => room.status === "playing").length);
const metrics = computed(() => [
  { label: "正常服务", value: snapshot.value ? `${snapshot.value.services.filter((service) => service.status === "ok").length} / ${snapshot.value.services.length}` : "—" },
  { label: "已观测在线玩家", value: snapshot.value ? connectedAccounts.value : "—" },
  { label: "当前房间", value: snapshot.value?.rooms.length ?? "—" },
  { label: "对局中房间", value: playingRooms.value ?? "—" },
]);

function displayTime(raw?: string): string {
  const date = raw ? new Date(raw) : undefined;
  return date && Number.isFinite(date.getTime()) && date.getUTCFullYear() > 1 ? dateFormatter.format(date) : "—";
}
</script>

<template>
  <section class="monitor-page">
    <div class="monitor-overview">
      <div class="monitor-overview-header">
        <div>
          <div class="connection" :data-state="connection" data-testid="monitor-connection" role="status">
            <i aria-hidden="true" />{{ connectionText[connection] }}
          </div>
          <p class="snapshot-time">最后快照 <time :datetime="snapshot?.generated_at">{{ displayTime(snapshot?.generated_at) }}</time></p>
        </div>
        <nav class="monitor-links" aria-label="监视分类">
          <a v-if="!props.roomsOnly" href="#monitor-servers">服务器</a>
          <a v-if="!props.roomsOnly" href="#monitor-lobbies">游戏大厅</a>
          <a href="#monitor-rooms">{{ props.matchesOnly ? "实时对局" : "游戏房间" }}</a>
          <a href="#monitor-players">玩家</a>
        </nav>
      </div>
      <dl v-if="!props.roomsOnly" class="monitor-metrics">
        <div v-for="metric in metrics" :key="metric.label">
          <dt>{{ metric.label }}</dt><dd>{{ metric.value }}</dd>
        </div>
      </dl>
    </div>

    <p v-if="connection === 'stale'" class="monitor-notice" role="status">
      {{ snapshot ? "以下为断开前收到的数据，恢复连接后将自动更新。" : "暂未收到监视数据，正在等待服务恢复。" }}
    </p>
    <p v-if="connection === 'forbidden'" class="monitor-notice" role="alert">请使用有平台读取权限的管理员账号登录。</p>

    <div v-if="!props.roomsOnly" class="monitor-grid">
      <section id="monitor-servers" class="monitor-card" data-testid="monitor-server-section" aria-labelledby="monitor-servers-title">
        <header><h2 id="monitor-servers-title">服务器</h2><span>依赖健康</span></header>
        <ul v-if="snapshot?.services.length" class="services-list">
          <li v-for="service in snapshot.services" :key="service.id" :data-testid="'monitor-service-' + service.id">
            <div>
              <strong>{{ serviceNames[service.id] ?? service.id }}</strong>
              <time :datetime="service.checked_at">{{ displayTime(service.checked_at) }}</time>
            </div>
            <span class="monitor-tag" :data-tone="heat[service.status]">{{ stateName(service.status) }}</span>
          </li>
        </ul>
        <p v-else class="monitor-empty">{{ snapshot ? "暂无服务数据" : "等待服务状态" }}</p>
      </section>

      <section id="monitor-lobbies" class="monitor-card" data-testid="monitor-lobbies-section" aria-labelledby="monitor-lobbies-title">
        <header><h2 id="monitor-lobbies-title">游戏大厅</h2><span>{{ lobbies.length }} 项</span></header>
        <div v-if="lobbies.length" class="monitor-table-wrap" tabindex="0">
          <table>
            <thead><tr><th scope="col">游戏</th><th scope="col">在线玩家</th><th scope="col">大厅空闲</th><th scope="col">等待入局</th><th scope="col">房间</th></tr></thead>
            <tbody>
              <tr v-for="lobby in lobbies" :key="lobby.product_id" :data-testid="'monitor-lobby-' + lobby.game_id">
                <th scope="row">{{ gameName(lobby.game_id) }}</th>
                <td>{{ lobby.online_players }}</td>
                <td>{{ lobby.presence_tracked === false ? "—" : (inLobby.get(lobby.game_id) ?? 0) }}</td>
                <td>{{ lobby.presence_tracked === false ? "—" : lobby.waiting_players }}</td>
                <td>{{ lobby.rooms }}</td>
              </tr>
            </tbody>
          </table>
        </div>
        <p v-else class="monitor-empty">{{ snapshot ? "暂无符合条件的大厅" : "等待大厅状态" }}</p>
        <p v-if="lobbies.some((lobby) => lobby.presence_tracked === false)" class="monitor-note">标有“—”的游戏目前只统计房间内的在线玩家。</p>
      </section>
    </div>

    <div class="monitor-filters">
      <label for="monitor-game-filter">游戏
        <select id="monitor-game-filter" v-model="gameFilter" data-testid="monitor-game-filter">
          <option value="">全部游戏</option>
          <option v-for="id in gameOptions" :key="id" :value="id">{{ gameName(id) }}</option>
        </select>
      </label>
      <label for="monitor-search">搜索房间和玩家
        <input id="monitor-search" v-model="search" data-testid="monitor-search" type="search" placeholder="房号、昵称或账号 ID" />
      </label>
      <button v-if="gameFilter || search" type="button" @click="gameFilter = ''; search = ''">清除筛选</button>
    </div>

    <section id="monitor-rooms" class="monitor-card" data-testid="monitor-rooms-section" aria-labelledby="monitor-rooms-title">
      <header><h2 id="monitor-rooms-title">{{ props.matchesOnly ? "实时对局" : "游戏房间" }}</h2><span>{{ rooms.length }} 间</span></header>
      <div v-if="rooms.length" class="monitor-table-wrap" tabindex="0">
        <table>
          <thead>
            <tr><th scope="col">房号</th><th scope="col">游戏与规则</th><th scope="col">房间状态</th><th scope="col">入座 / 容量</th>
              <th scope="col">在线玩家</th><th scope="col">完局</th><th scope="col">更新时间</th></tr>
          </thead>
          <tbody>
            <tr v-for="room in rooms" :key="room.game_id + ':' + room.room_id" :data-testid="'monitor-room-' + room.room_id">
              <th scope="row"><span class="room-code">{{ room.room_id }}</span><small>{{ kindNames[room.kind] ?? stateName(room.kind) }}</small></th>
              <td>{{ gameName(room.game_id) }}<small>{{ [room.rule_set_id, room.rule_version].filter(Boolean).join(" · ") || "—" }}</small></td>
              <td><span class="monitor-tag" :data-tone="heat[room.status]">{{ stateName(room.status) }}</span>
                <small v-if="room.phase && room.phase !== room.status">{{ stateName(room.phase) }}</small></td>
              <td>{{ room.players }} / {{ room.capacity }}<small v-if="room.status === 'waiting' && room.ready_players !== undefined">已准备 {{ room.ready_players }}</small></td>
              <td>{{ room.connected_players ?? "—" }}</td><td>{{ room.completed_rounds ?? "—" }}</td>
              <td><time :datetime="room.updated_at">{{ displayTime(room.updated_at) }}</time></td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="monitor-empty">{{ snapshot ? (props.matchesOnly ? "暂无符合条件的对局" : "暂无符合条件的房间") : "等待最新状态" }}</p>
    </section>

    <section id="monitor-players" class="monitor-card" data-testid="monitor-players-section" aria-labelledby="monitor-players-title">
      <header><h2 id="monitor-players-title">玩家</h2><span>{{ players.length }} 项</span></header>
      <div v-if="players.length" class="monitor-table-wrap" tabindex="0">
        <table>
          <thead>
            <tr><th scope="col">玩家</th><th scope="col">所在游戏</th><th scope="col">房号</th><th scope="col">座位</th>
              <th scope="col">活动状态</th><th scope="col">连接</th></tr>
          </thead>
          <tbody>
            <tr v-for="player in players" :key="[player.game_id, player.room_id, player.account_id].join(':')" :data-testid="'monitor-player-' + player.account_id">
              <th scope="row">{{ player.display_name || "玩家" }}<small class="account-id">{{ player.account_id }}</small></th>
              <td>{{ gameName(player.game_id) }}</td><td>{{ player.room_id || "—" }}</td><td>{{ player.seat === undefined ? "—" : player.seat + 1 }}</td>
              <td><span class="monitor-tag" :data-tone="heat[player.status]">{{ stateName(player.status) }}</span></td>
              <td>{{ player.connected ? "已连接" : "已断开" }}</td>
            </tr>
          </tbody>
        </table>
      </div>
      <p v-else class="monitor-empty">{{ snapshot ? "暂无符合条件的玩家" : "等待玩家状态" }}</p>
    </section>
  </section>
</template>

<style scoped>
.monitor-page { width: 100%; max-width: 1560px; margin: 0 auto; display: grid; gap: 16px; }
.monitor-overview {
  padding: 20px 22px; border: 1px solid var(--xbd-border); border-radius: var(--xbd-radius-lg); color: var(--xbd-text-primary);
  background: linear-gradient(125deg, var(--xbd-sidebar-bg) 10%, var(--xbd-sidebar-bg-secondary) 70%, var(--xbd-brand-tint));
  box-shadow: var(--xbd-shadow-card);
}
.monitor-overview-header { display: flex; justify-content: space-between; align-items: center; flex-wrap: wrap; gap: 12px; }
.connection { display: flex; align-items: center; gap: 8px; color: var(--xbd-warning); font-size: 14px; font-weight: 680; }
.connection i { width: 8px; height: 8px; border-radius: 50%; background: currentColor; }
.connection[data-state="live"] { color: var(--xbd-success); }
.connection[data-state="forbidden"] { color: var(--xbd-danger); }
.snapshot-time { color: var(--xbd-text-secondary); margin: 5px 0 0; font-size: 12px; }
.monitor-links { display: flex; flex-wrap: wrap; gap: 7px; }
.monitor-links a {
  border: 1px solid var(--xbd-border-control); border-radius: var(--xbd-radius-sm); padding: 6px 10px;
  color: var(--xbd-text-primary); line-height: 1.4;
}
.monitor-links a:hover { border-color: var(--xbd-brand-highlight); }
.monitor-metrics { margin: 18px 0 0; display: grid; grid-template-columns: repeat(4, minmax(0, 1fr)); gap: 10px; }
.monitor-metrics div { padding: 12px 14px; border: 1px solid var(--xbd-border); border-radius: var(--xbd-radius-md); background: var(--xbd-card-bg); }
.monitor-metrics dt { color: var(--xbd-text-secondary); font-size: 12px; }
.monitor-metrics dd { margin: 4px 0 0; color: var(--xbd-text-primary); font-size: 24px; font-weight: 690; font-variant-numeric: tabular-nums; }
.monitor-notice { margin: 0; padding: 11px 14px; border: 1px solid var(--xbd-border-control); border-radius: var(--xbd-radius-sm); background: var(--xbd-warning-bg); color: var(--xbd-warning); }
.monitor-notice[role="alert"] { background: var(--xbd-danger-bg); color: var(--xbd-danger); }
.monitor-grid { display: grid; grid-template-columns: minmax(270px, .9fr) minmax(360px, 1.3fr); gap: 16px; }
.monitor-card { min-width: 0; border: 1px solid var(--xbd-border); background: var(--xbd-card-bg); border-radius: var(--xbd-radius-md); box-shadow: var(--xbd-shadow-card); scroll-margin: 10px; }
.monitor-card header { display: flex; justify-content: space-between; align-items: center; gap: 10px; padding: 14px 16px; }
.monitor-card header span { color: var(--xbd-text-secondary); font-size: 12px; }
.monitor-card h2 { margin: 0; font-size: 16px; }
.monitor-table-wrap { overflow-x: auto; }
.monitor-table-wrap:focus-visible { outline: 2px solid var(--xbd-brand-primary); outline-offset: -2px; }
.monitor-card table { width: 100%; border-collapse: collapse; text-align: left; font-variant-numeric: tabular-nums; }
.monitor-card th, .monitor-card td { padding: 10px 14px; white-space: nowrap; line-height: 1.4; border-top: 1px solid var(--xbd-border); }
.monitor-card thead { background: var(--xbd-surface-raised); color: var(--xbd-text-secondary); font-size: 12px; }
.monitor-card tbody tr:hover { background: var(--xbd-surface-hover); }
.monitor-card small, .services-list time { display: block; color: var(--xbd-text-secondary); font-size: 11px; margin-top: 4px; font-weight: 450; }
.room-code { font-size: 15px; font-weight: 700; letter-spacing: .025em; }
.account-id { font-family: ui-monospace, Consolas, monospace; }
.services-list { list-style: none; padding: 0; margin: 0; }
.services-list li {
  display: flex; align-items: center; justify-content: space-between; gap: 12px;
  padding: 11px 15px; border-top: 1px solid var(--xbd-border);
}
.monitor-tag { display: inline-block; padding: 3px 8px; border-radius: 20px; background: var(--xbd-surface-raised); color: var(--xbd-text-secondary); line-height: 1.3; font-size: 11px; font-weight: 650; white-space: nowrap; }
.monitor-tag[data-tone="success"] { background: var(--xbd-success-bg); color: var(--xbd-success); }
.monitor-tag[data-tone="warn"] { background: var(--xbd-warning-bg); color: var(--xbd-warning); }
.monitor-tag[data-tone="danger"] { background: var(--xbd-danger-bg); color: var(--xbd-danger); }
.monitor-note, .monitor-empty { margin: 0; padding: 12px 16px; color: var(--xbd-text-secondary); }
.monitor-note { font-size: 11px; border-top: 1px solid var(--xbd-border); }
.monitor-empty { border-top: 1px solid var(--xbd-border); }
.monitor-filters { display: flex; flex-wrap: wrap; align-items: center; gap: 12px; }
.monitor-filters label { display: flex; align-items: center; gap: 8px; font-weight: 600; }
.monitor-filters input, .monitor-filters select, .monitor-filters button {
  width: auto; max-width: 100%; border: 1px solid var(--xbd-border-control); background: var(--xbd-card-bg);
  color: var(--xbd-text-primary); min-height: 38px; padding: 6px 10px; border-radius: var(--xbd-radius-sm); font: inherit;
}
.monitor-filters button { cursor: pointer; }
.monitor-filters input { width: min(210px, 50vw); }
@media (max-width: 1020px) {
  .monitor-grid { grid-template-columns: minmax(0, 1fr); }
}
@media (max-width: 620px) {
  .monitor-overview { padding: 14px; }
  .monitor-metrics { grid-template-columns: repeat(2, minmax(0, 1fr)); }
  .monitor-filters label { flex-wrap: wrap; }
}
</style>
