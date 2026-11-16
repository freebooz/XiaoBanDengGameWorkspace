import { onScopeDispose, ref, shallowRef, watch } from "vue";
import { PLATFORM_READ, useAuthStore } from "../../app/store/auth";
import { ApiError } from "../../services/api/client";

export type Service = { id: string; status: string; checked_at: string };
export type Lobby = {
  game_id: string; product_id: string; presence_tracked?: boolean;
  online_players: number; waiting_players: number; rooms: number;
};
export type Room = {
  room_id: string; game_id: string; product_id: string; rule_set_id: string; rule_version: string;
  kind: string; status: string; phase: string; capacity: number; players: number;
  connected_players: number; ready_players?: number; completed_rounds: number; updated_at: string;
};
export type Player = {
  account_id: string; display_name?: string; game_id: string; room_id?: string;
  room_status?: string;
  status: string; seat?: number; connected: boolean;
};
type Snapshot = {
  generated_at: string; services: Service[]; lobbies: Lobby[]; rooms: Room[]; players: Player[];
};
type Connection = "connecting" | "live" | "stale" | "forbidden";

export const connectionText: Record<Connection, string> = {
  connecting: "正在连接",
  live: "实时连接",
  stale: "连接中断，正在重连",
  forbidden: "监视权限不可用",
};

export function countConnectedAccounts(players: readonly Player[]): number {
  return new Set(players.filter((player) => player.connected).map((player) => player.account_id)).size;
}

function readSnapshot(data: string): Snapshot {
  const snapshot: Snapshot = JSON.parse(data);
  if (!snapshot || typeof snapshot.generated_at !== "string" || !Array.isArray(snapshot.services) ||
    !Array.isArray(snapshot.lobbies) || !Array.isArray(snapshot.rooms) || !Array.isArray(snapshot.players)) {
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
