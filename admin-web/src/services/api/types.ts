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

export interface EggGrantRequest {
  display_name: string;
  expected_account_id?: string;
  amount: number;
  request_id: string;
}

export interface EggWalletPlayer {
  account_id: string;
  display_name: string;
  asset_id: "xbd_egg";
  balance: number;
}

export interface EggGrantReceipt extends EggWalletPlayer {
  amount: number;
  request_id: string;
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
export type MahjongRoomAdmissionRequest = {
  room_generation: string;
  expected_revision: number;
  paused: boolean;
  reason: string;
  request_id: string;
};

export type MahjongRoomOperation = {
  request_id: string;
  room_id: string;
  room_generation: string;
  admission_revision: number;
  paused: boolean;
  reason: string;
  admin_name: string;
  created_at: string;
};

export type MahjongReportStatus = "pending" | "upheld" | "dismissed";

export interface MahjongReport {
  report_id: string;
  match_id: string;
  room_id: string;
  reporter_seat: number;
  target_seat: number;
  reason: string;
  created_at: string;
  status: MahjongReportStatus;
  analyst?: string;
  reviewed_at?: string;
  note?: string;
}
