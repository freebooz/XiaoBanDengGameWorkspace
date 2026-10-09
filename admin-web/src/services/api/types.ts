export interface HealthStatus {
  service: string;
  postgres: string;
  redis: string;
  time: string;
}

export interface GameDescriptor {
  product_id: string;
  game_category: string;
  game_id: string;
  rule_set_id: string;
  rule_version: string;
  name: string;
  enabled: boolean;
}

export interface AdminOverview {
  registered_users: number;
  active_rooms: number;
  total_matches: number;
  service_time: string;
  data_source: "partial" | "development";
}

export interface PageResult<T> {
  items: T[];
  total: number;
  page: number;
  page_size: number;
  data_source: "partial" | "development";
}

export interface CollectionResult<T> {
  items: T[];
  total: number;
  data_source: "partial" | "development";
}

export interface UserSummary {
  account_id: string;
  display_name: string;
  account_type: string;
  status: string;
  created_at: string;
}

export interface UserQuery {
  page?: number;
  page_size?: number;
  status?: string;
  keyword?: string;
}

/** 客户端标识是房间连接标识，不能作为认证账号使用。 */
export interface RoomPlayer {
  client_id: string;
  seat: string;
  connected: boolean;
}

/** 历史对局座位保留入座时间，不把当前在线状态套用到历史玩家。 */
export interface MatchPlayer {
  client_id: string;
  seat: string;
  joined_at: string;
}

export interface RoomSummary {
  room_id: string;
  product_id: string;
  game_id: string;
  rule_set_id: string;
  rule_version: string;
  state: string;
  created_at: string;
  duration_seconds: number;
  data_source: "partial" | "development";
  players?: RoomPlayer[];
  connected_count?: number;
  match_id?: string;
  source?: string;
}

export interface RoomQuery {
  product_id?: string;
  game_id?: string;
  rule_set_id?: string;
  state?: string;
}

export interface MatchSummary {
  match_id: string;
  product_id: string;
  game_id: string;
  rule_set_id: string;
  rule_version: string;
  status: string;
  started_at: string | null;
  finished_at: string | null;
  created_at: string;
  room_id?: string;
  winner?: string;
  result_reason?: string;
  source?: string;
}

export interface MatchQuery {
  page?: number;
  page_size?: number;
  game_id?: string;
  status?: string;
}

/** 事件与快照分别分页；服务端返回数组只包含各自当前页。 */
export interface MatchRecordQuery {
  event_page?: number;
  snapshot_page?: number;
  record_page_size?: number;
}

export interface GameEvent {
  sequence: number;
  event_type: string;
  payload: unknown;
  created_at: string;
}

export interface GameSnapshot {
  sequence: number;
  snapshot: unknown;
  created_at: string;
}

export interface MatchDetail {
  summary: MatchSummary;
  events: GameEvent[];
  snapshots: GameSnapshot[];
  data_source: "partial" | "development";
  players?: MatchPlayer[];
  event_total?: number;
  snapshot_total?: number;
  event_page?: number;
  snapshot_page?: number;
  record_page_size?: number;
}

export interface AICapability {
  key: string;
  name: string;
  description: string;
  enabled: boolean;
}
