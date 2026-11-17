import { onScopeDispose, ref, shallowRef, watch } from "vue";
import { PLATFORM_READ, useAuthStore } from "../../app/store/auth";
import { ApiError } from "../../services/api/client";

export type Service = { id: string; status: string; checked_at: string };
export type Lobby = {
  game_id: string; product_id: string; presence_tracked?: boolean;
  online_players: number; waiting_players: number; rooms: number;
};
export type MahjongRoomState = {
  round_number: number; round_limit: number; spectator_count: number;
  admission_paused: boolean; admission_revision: number; can_set_admission: boolean;
  match_id?: string; dealer?: number; turn?: number; remaining_tiles?: number; action_deadline_ms?: number;
  last_discard?: { seat: number; suit: string; rank: number };
};
export type Room = {
  room_id: string; game_id: string; product_id: string; rule_set_id: string; rule_version: string;
  kind: string; status: string; phase: string; capacity: number; players: number;
  connected_players: number; ready_players?: number; completed_rounds: number; updated_at: string;
  room_generation?: string; mahjong?: MahjongRoomState;
};
export type Player = {
  account_id: string; display_name?: string; game_id: string; room_id?: string;
  room_status?: string; room_generation?: string;
  status: string; seat?: number; connected: boolean;
};
type Snapshot = {
  generated_at: string; services: Service[]; lobbies: Lobby[]; rooms: Room[]; players: Player[];
};
export type Connection = "connecting" | "live" | "stale" | "forbidden";

export const connectionText: Record<Connection, string> = {
  connecting: "正在连接",
  live: "实时连接",
  stale: "连接中断，正在重连",
  forbidden: "监视权限不可用",
};

const stateNames: Record<string, string> = {
  ok: "正常", unavailable: "不可用", draining: "停止接入中",
  lobby: "大厅在线", waiting: "等待中", ready: "已准备", matched: "已匹配", playing: "对局中",
  reconnecting: "等待重连", settled: "已结算", finished: "已结束", closed: "已关闭",
  dingque: "定缺", turn: "出牌", reaction: "接牌响应", settling: "结算中", entering: "正在入桌", saving: "正在保存",
};
export const kindNames: Record<string, string> = { friend: "好友房", quick: "快速匹配", training: "训练房" };
export const monitorStateName = (id: string) => stateNames[id] ?? (id || "—");

const dateFormatter = new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "medium" });
export function displayMonitorTime(raw?: string | number): string {
  const date = raw ? new Date(raw) : undefined;
  return date && Number.isFinite(date.getTime()) && date.getUTCFullYear() > 1 ? dateFormatter.format(date) : "—";
}

export function countConnectedAccounts(players: readonly Player[]): number {
  return new Set(players.filter((player) => player.connected).map((player) => player.account_id)).size;
}

const isText = (value: unknown): value is string => typeof value === "string";
const isCount = (value: unknown): value is number => typeof value === "number" && Number.isSafeInteger(value) && value >= 0;
const isOptionalText = (value: unknown): boolean => value === undefined || isText(value);
const isOptionalCount = (value: unknown): boolean => value === undefined || isCount(value);
const isSeat = (value: unknown): value is number => isCount(value) && value < 4;
const isOptionalSeat = (value: unknown): boolean => value === undefined || value === -1 || isSeat(value);

function isOptionalGeneration(value: unknown): boolean {
  return value === undefined || (isText(value) &&
    /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(\.\d{1,9})?Z$/.test(value) && Number.isFinite(Date.parse(value)));
}

function isOptionalMahjongState(state: MahjongRoomState | undefined): boolean {
  if (state === undefined) return true;
  return !!state && isCount(state.round_number) && isCount(state.round_limit) && isCount(state.spectator_count) &&
    typeof state.admission_paused === "boolean" && isCount(state.admission_revision) &&
    typeof state.can_set_admission === "boolean" && isOptionalText(state.match_id) &&
    isOptionalSeat(state.dealer) && isOptionalSeat(state.turn) && isOptionalCount(state.remaining_tiles) &&
    isOptionalCount(state.action_deadline_ms) && (state.last_discard === undefined || (!!state.last_discard &&
      isSeat(state.last_discard.seat) && isText(state.last_discard.suit) && isCount(state.last_discard.rank)));
}

function readSnapshot(data: string): Snapshot {
  const snapshot: Snapshot = JSON.parse(data);
  if (!snapshot || !isText(snapshot.generated_at) ||
      !Array.isArray(snapshot.services) || !snapshot.services.every((service) =>
        service && isText(service.id) && isText(service.status) && isText(service.checked_at)) ||
      !Array.isArray(snapshot.lobbies) || !snapshot.lobbies.every((lobby) =>
        lobby && isText(lobby.game_id) && isText(lobby.product_id) && isCount(lobby.online_players) &&
        isCount(lobby.waiting_players) && isCount(lobby.rooms)) ||
      !Array.isArray(snapshot.rooms) || !snapshot.rooms.every((room) =>
        room && isText(room.room_id) && isText(room.game_id) && isText(room.product_id) && isText(room.rule_set_id) &&
        isText(room.rule_version) && isText(room.kind) && isText(room.status) && isText(room.phase) &&
        isCount(room.capacity) && isCount(room.players) && isCount(room.connected_players) &&
        isCount(room.completed_rounds) && isText(room.updated_at) &&
        isOptionalCount(room.ready_players) && isOptionalGeneration(room.room_generation) &&
        isOptionalMahjongState(room.mahjong)) ||
      !Array.isArray(snapshot.players) || !snapshot.players.every((player) =>
        player && isText(player.account_id) && isText(player.game_id) && isText(player.status) &&
        isOptionalText(player.room_id) && isOptionalText(player.room_status) && isOptionalText(player.display_name) &&
        isOptionalGeneration(player.room_generation) && typeof player.connected === "boolean" && isOptionalCount(player.seat))) {
    throw new Error("监视快照格式无效");
  }
  return snapshot;
}

export function useMonitor() {
  const auth = useAuthStore();
  const snapshot = shallowRef<Snapshot>();
  const connection = ref<Connection>("connecting");
  let controller: AbortController | undefined;
  let retry: number | undefined;
  let heartbeat: number | undefined;
  let attempt = 0;
  let disposed = false;

  function stop(): void {
    window.clearTimeout(retry);
    window.clearTimeout(heartbeat);
    controller?.abort();
    controller = undefined;
  }

  async function connect(): Promise<void> {
    stop();
    if (disposed || !auth.isAuthenticated || !auth.can(PLATFORM_READ)) return;
    const current = new AbortController();
    controller = current;
    const expectHeartbeat = () => {
      window.clearTimeout(heartbeat);
      heartbeat = window.setTimeout(() => current.abort(), 35_000);
    };
    expectHeartbeat();
    try {
      await auth.stream("/api/v1/admin/monitor/stream", current.signal, (event, data) => {
        if (controller !== current || current.signal.aborted || event !== "snapshot") return;
        snapshot.value = readSnapshot(data);
        connection.value = "live";
        attempt = 0;
        expectHeartbeat();
      }, () => {
        if (controller === current && !current.signal.aborted && connection.value === "live") expectHeartbeat();
      });
    } catch (error) {
      if (controller !== current) return;
      if (error instanceof ApiError && (error.status === 401 || error.status === 403)) {
        snapshot.value = undefined;
        connection.value = "forbidden";
        stop();
        return;
      }
    }
    if (controller !== current || disposed) return;
    stop();
    connection.value = "stale";
    const delay = 1_000 * 2 ** Math.min(attempt++, 4);
    retry = window.setTimeout(() => void connect(), delay);
  }

  watch(() => auth.sessionRevision, () => {
    snapshot.value = undefined;
    if (auth.isAuthenticated && auth.can(PLATFORM_READ)) {
      attempt = 0;
      connection.value = "connecting";
      void connect();
    } else {
      connection.value = "forbidden";
      stop();
    }
  }, { immediate: true, flush: "sync" });
  onScopeDispose(() => {
    disposed = true;
    stop();
  });

  return { snapshot, connection };
}
