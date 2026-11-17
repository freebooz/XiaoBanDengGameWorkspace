<script setup lang="ts">
import { computed, ref } from "vue";
import MahjongRoomAdmission from "./MahjongRoomAdmission.vue";
import { displayMonitorTime, kindNames, monitorStateName, type Connection, type Player, type Room } from "./monitor";

const props = defineProps<{ id: string; room: Room; players: Player[]; connection: Connection }>();
const emit = defineEmits<{ close: [] }>();
const heading = ref<HTMLHeadingElement>();
const board = computed(() => props.room.mahjong);
const seatName = (seat?: number) => seat === undefined || seat < 0 ? "—" : `${seat + 1} 号位`;
const seatCount = 4;
const seats = computed(() => Array.from({ length: seatCount }, (_, seat) => ({
  seat,
  player: props.players.find((player) => player.seat === seat),
  // Training reservations always include three bots, omitted from monitor.players.
  bot: props.room.kind === "training" && props.room.players === seatCount && seat > 0,
})));
const deadline = computed(() => {
  if (!board.value?.action_deadline_ms) return undefined;
  const date = new Date(board.value.action_deadline_ms);
  return Number.isFinite(date.getTime()) ? date : undefined;
});
const suits: Record<string, string> = { wan: "万", tong: "筒", tiao: "条" };
const lastDiscard = computed(() => {
  const discard = board.value?.last_discard;
  if (!discard) return "";
  const rank = "一二三四五六七八九"[discard.rank - 1] ?? discard.rank;
  return `${rank}${suits[discard.suit] ?? discard.suit} · ${seatName(discard.seat)}`;
});

defineExpose({ focusHeading: () => heading.value?.focus() });
</script>

<template>
  <section :id="props.id" class="room-inspector" data-testid="mahjong-room-inspector" :aria-labelledby="props.id + '-title'">
    <header class="inspector-heading">
      <div>
        <h2 :id="props.id + '-title'" ref="heading" tabindex="-1">麻将房间 {{ props.room.room_id }}</h2>
        <p>{{ kindNames[props.room.kind] ?? props.room.kind }}{{ props.room.rule_set_id ? ' · ' + props.room.rule_set_id : '' }}{{ props.room.rule_version ? ' · ' + props.room.rule_version : '' }}</p>
      </div>
      <button type="button" @click="emit('close')">关闭详情</button>
    </header>

    <p v-if="props.connection !== 'live'" class="room-stale" data-testid="mahjong-inspector-stale" role="status">
      实时连接中断，以下为最后收到的房间状态。
    </p>
    <dl class="room-facts">
      <div><dt>房间状态</dt><dd>{{ monitorStateName(props.room.status) }}</dd></div>
      <div v-if="props.room.phase && props.room.phase !== props.room.status"><dt>牌局阶段</dt><dd>{{ monitorStateName(props.room.phase) }}</dd></div>
      <div v-if="board?.round_number">
        <dt>{{ board.round_limit ? '当前局 / 总局' : '当前局' }}</dt>
        <dd>{{ board.round_number }}<template v-if="board.round_limit"> / {{ board.round_limit }}</template></dd>
      </div>
      <div v-if="board?.remaining_tiles !== undefined"><dt>剩余牌</dt><dd>{{ board.remaining_tiles }}</dd></div>
      <div v-if="board"><dt>观战人数</dt><dd data-testid="mahjong-spectators">{{ board.spectator_count }}</dd></div>
      <div v-if="(board?.dealer ?? -1) >= 0"><dt>庄家</dt><dd>{{ seatName(board?.dealer) }}</dd></div>
      <div v-if="(board?.turn ?? -1) >= 0"><dt>轮转座位</dt><dd>{{ seatName(board?.turn) }}</dd></div>
      <div v-if="lastDiscard"><dt>最近出牌</dt><dd>{{ lastDiscard }}</dd></div>
      <div v-if="deadline"><dt>行动截止</dt><dd>
        <time :datetime="deadline.toISOString()" data-testid="mahjong-action-deadline">{{ displayMonitorTime(board?.action_deadline_ms) }}</time>
      </dd></div>
    </dl>
    <div class="room-metadata">
      <p v-if="board?.match_id">对局 ID <span>{{ board.match_id }}</span></p>
      <p>更新时间 <time :datetime="props.room.updated_at">{{ displayMonitorTime(props.room.updated_at) }}</time></p>
      <p v-if="!board">当前服务未提供详细牌局数据。</p>
    </div>

    <section class="room-seats" :aria-labelledby="props.id + '-seats'">
      <div class="seats-heading">
        <h3 :id="props.id + '-seats'">席位</h3>
        <p>在线 {{ props.room.connected_players }}<template v-if="props.room.status === 'waiting' && props.room.ready_players !== undefined"> · 已准备 {{ props.room.ready_players }}</template></p>
      </div>
      <ul>
        <li v-for="{ seat, player, bot } in seats" :key="seat" :data-active="board?.turn === seat && props.room.phase === 'turn'">
          <div class="seat-heading">
            <strong>{{ seatName(seat) }}</strong>
            <small v-if="board?.dealer === seat" class="seat-dealer">庄家</small>
          </div>
          <template v-if="player">
            <span class="seat-player">{{ player.display_name || '玩家' }}</span>
            <small class="seat-account">{{ player.account_id }}</small>
            <span class="seat-status" :data-connected="player.connected">
              {{ monitorStateName(player.status) }} · {{ player.connected ? '已连接' : '已断开' }}
            </span>
          </template>
          <span v-else class="seat-status">{{ bot ? '电脑' : '空座' }}</span>
        </li>
      </ul>
    </section>

    <MahjongRoomAdmission v-if="props.room.kind === 'friend' && board && props.room.room_generation" :room="props.room" :connection="props.connection" />
  </section>
</template>

<style scoped>
.room-inspector {
  display: grid; gap: 0; min-width: 0; scroll-margin: 12px; border: 1px solid var(--xbd-border-control);
  border-radius: var(--xbd-radius-md); color: var(--xbd-text-primary); background: var(--xbd-card-bg); box-shadow: var(--xbd-shadow-card);
}
.inspector-heading {
  padding: 14px 16px; display: flex; justify-content: space-between; flex-wrap: wrap; align-items: center; gap: 10px;
  border-radius: var(--xbd-radius-md) var(--xbd-radius-md) 0 0; background: var(--xbd-walnut-surface);
}
.inspector-heading h2 { margin: 0; font-size: 18px; overflow-wrap: anywhere; }
.inspector-heading p, .room-metadata p { margin: 4px 0 0; color: var(--xbd-text-secondary); font-size: 12px; overflow-wrap: anywhere; }
.inspector-heading button {
  min-height: 44px; padding: 4px 12px; border: 1px solid var(--xbd-border-control); border-radius: var(--xbd-radius-sm);
  background: var(--xbd-card-bg); color: var(--xbd-text-primary); font: inherit; cursor: pointer;
}
.inspector-heading button:hover { background: var(--xbd-surface-hover); }
.inspector-heading :is(button, h2):focus-visible { outline: 2px solid var(--xbd-brand-highlight); outline-offset: 2px; }
.room-stale { margin: 0; padding: 9px 16px; background: var(--xbd-warning-bg); color: var(--xbd-warning); }
.room-facts {
  margin: 0; padding: 16px 16px 8px; display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 104px), 1fr)); gap: 8px;
}
.room-facts > div { padding: 8px 10px; background: var(--xbd-surface-inset); border-radius: var(--xbd-radius-sm); }
.room-facts dt { font-size: 12px; color: var(--xbd-text-secondary); }
.room-facts dd { margin: 3px 0 0; font-size: 14px; font-weight: 650; overflow-wrap: anywhere; font-variant-numeric: tabular-nums; }
.room-metadata { padding: 0 16px 14px; display: flex; flex-wrap: wrap; column-gap: 16px; }
.room-seats { padding: 14px 16px; border-top: 1px solid var(--xbd-border); border-bottom: 1px solid var(--xbd-border); }
.seats-heading { display: flex; align-items: center; flex-wrap: wrap; justify-content: space-between; gap: 8px; margin-bottom: 10px; }
.seats-heading h3 { margin: 0; font-size: 15px; }
.seats-heading p { margin: 0; font-size: 12px; color: var(--xbd-text-secondary); }
.room-seats ul {
  display: grid; grid-template-columns: repeat(auto-fit, minmax(min(100%, 135px), 1fr));
  gap: 8px; list-style: none; margin: 0; padding: 0;
}
.room-seats li {
  display: flex; flex-direction: column; gap: 5px; padding: 10px; overflow-wrap: anywhere;
  border: 1px solid var(--xbd-border); border-radius: var(--xbd-radius-sm); background: var(--xbd-surface-inset);
}
.room-seats li[data-active="true"] { border-color: var(--xbd-brand-highlight); }
.seat-heading { display: flex; align-items: center; flex-wrap: wrap; gap: 7px; }
.seat-dealer { color: var(--xbd-brand-highlight); }
.seat-player { margin-top: 3px; font-weight: 650; }
.seat-account, .seat-status { color: var(--xbd-text-secondary); font-size: 12px; }
.seat-account { font-family: ui-monospace, Consolas, monospace; }
.seat-status[data-connected="true"] { color: var(--xbd-success); }
</style>
