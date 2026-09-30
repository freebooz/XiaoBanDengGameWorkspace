import { apiGet } from "./client";
import type {
  AICapability,
  AdminOverview,
  CollectionResult,
  GameDescriptor,
  HealthStatus,
  MatchDetail,
  MatchQuery,
  MatchSummary,
  PageResult,
  RoomQuery,
  RoomSummary,
  UserQuery,
  UserSummary,
} from "./types";

export interface AdminProvider {
  overview(): Promise<AdminOverview>;
  users(query?: UserQuery): Promise<PageResult<UserSummary>>;
  rooms(query?: RoomQuery): Promise<CollectionResult<RoomSummary>>;
  roomDetail(roomId: string): Promise<RoomSummary>;
  matches(query?: MatchQuery): Promise<PageResult<MatchSummary>>;
  matchDetail(matchId: string): Promise<MatchDetail>;
}

/** adminApi（管理API）默认只调用真实Go服务，不自动回退到假数据。 */
export const adminApi: AdminProvider = {
  overview: () => apiGet<AdminOverview>("/api/v1/admin/overview"),
  users: (query = {}) =>
    apiGet<PageResult<UserSummary>>(
      "/api/v1/admin/users",
      query as Record<string, string | number | undefined>,
    ),
  rooms: (query = {}) =>
    apiGet<CollectionResult<RoomSummary>>(
      "/api/v1/admin/rooms",
      query as Record<string, string | number | undefined>,
    ),
  roomDetail: (roomId) =>
    apiGet<RoomSummary>("/api/v1/admin/rooms/" + encodeURIComponent(roomId)),
  matches: (query = {}) =>
    apiGet<PageResult<MatchSummary>>(
      "/api/v1/admin/matches",
      query as Record<string, string | number | undefined>,
    ),
  matchDetail: (matchId) =>
    apiGet<MatchDetail>("/api/v1/admin/matches/" + encodeURIComponent(matchId)),
};

/** platformApi（平台公共API）供工作台与游戏中心复用。 */
export const platformApi = {
  health: () => apiGet<HealthStatus>("/health"),
  catalog: () => apiGet<{ games: GameDescriptor[] }>("/api/v1/catalog"),
  aiCapabilities: () =>
    apiGet<AICapability[]>("/api/v1/ai/capabilities"),
};

/**
 * createDevelopmentAdminProvider（开发数据提供者）
 * 只返回带development标识的空结构，用于后端功能尚未接入时验证空态；
 * 不生成随机用户、房间或交易数字。
 */
export function createDevelopmentAdminProvider(): AdminProvider {
  const now = new Date().toISOString();
  return {
    overview: async () => ({
      registered_users: 0,
      active_rooms: 0,
      total_matches: 0,
      service_time: now,
      data_source: "development",
    }),
    users: async (query = {}) => ({
      items: [],
      total: 0,
      page: query.page ?? 1,
      page_size: query.page_size ?? 20,
      data_source: "development",
    }),
    rooms: async () => ({ items: [], total: 0, data_source: "development" }),
    roomDetail: async (roomId) => ({
      room_id: roomId,
      product_id: "",
      game_id: "",
      rule_set_id: "",
      rule_version: "",
      state: "development",
      created_at: now,
      duration_seconds: 0,
      data_source: "development",
    }),
    matches: async (query = {}) => ({
      items: [],
      total: 0,
      page: query.page ?? 1,
      page_size: query.page_size ?? 20,
      data_source: "development",
    }),
    matchDetail: async (matchId) => ({
      summary: {
        match_id: matchId,
        product_id: "",
        game_id: "",
        rule_set_id: "",
        rule_version: "",
        status: "development",
        started_at: null,
        finished_at: null,
        created_at: now,
      },
      events: [],
      snapshots: [],
      data_source: "development",
    }),
  };
}
