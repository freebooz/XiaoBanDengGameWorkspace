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
}

export interface MatchQuery {
  page?: number;
  page_size?: number;
  game_id?: string;
  status?: string;
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
}

export interface AICapability {
  key: string;
  name: string;
  description: string;
  enabled: boolean;
}
