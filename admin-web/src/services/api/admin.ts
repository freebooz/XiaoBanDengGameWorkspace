import { apiGet } from "./client";
import { useAuthStore } from "../../app/store/auth";
import type {
  AICapability,
  AdminOverview,
  CollectionResult,
  EggGrantReceipt,
  EggGrantRequest,
  EggWalletPlayer,
  GameDescriptor,
  HealthStatus,
  MatchDetail,
  MatchQuery,
  MatchSummary,
  MahjongReport,
  MahjongReportStatus,
  MahjongRoomAdmissionRequest,
  MahjongRoomOperation,
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
  overview: () => useAuthStore().request<AdminOverview>("/api/v1/admin/overview"),
  users: (query = {}) =>
    useAuthStore().request<PageResult<UserSummary>>(
      "/api/v1/admin/users",
      query as Record<string, string | number | undefined>,
    ),
  rooms: (query = {}) =>
    useAuthStore().request<CollectionResult<RoomSummary>>(
      "/api/v1/admin/rooms",
      query as Record<string, string | number | undefined>,
    ),
  roomDetail: (roomId) =>
    useAuthStore().request<RoomSummary>("/api/v1/admin/rooms/" + encodeURIComponent(roomId)),
  matches: (query = {}) =>
    useAuthStore().request<PageResult<MatchSummary>>(
      "/api/v1/admin/matches",
      query as Record<string, string | number | undefined>,
    ),
  matchDetail: (matchId) =>
    useAuthStore().request<MatchDetail>("/api/v1/admin/matches/" + encodeURIComponent(matchId)),
};

export const mahjongReportsApi = {
  list: (status: MahjongReportStatus | "", limit: number, offset: number) =>
    useAuthStore().request<{ items: MahjongReport[]; total: number }>(
      "/api/v1/admin/mahjong/reports", { status, limit, offset },
    ),
  resolve: (id: string, status: Exclude<MahjongReportStatus, "pending">, note: string) =>
    useAuthStore().request<{ report: MahjongReport }>(
      "/api/v1/admin/mahjong/reports/" + encodeURIComponent(id) + "/resolve", undefined, { status, note },
    ),
};

export const mahjongRoomsApi = {
  setAdmission: (roomID: string, request: MahjongRoomAdmissionRequest, signal: AbortSignal) =>
    useAuthStore().request<{ operation: MahjongRoomOperation }>(
      "/api/v1/admin/mahjong/rooms/" + encodeURIComponent(roomID) + "/admission", undefined, request, signal,
    ),
  operations: (roomID: string, roomGeneration: string, signal: AbortSignal) =>
    useAuthStore().request<{ items: MahjongRoomOperation[] }>(
      "/api/v1/admin/mahjong/rooms/" + encodeURIComponent(roomID) + "/operations",
      { room_generation: roomGeneration }, undefined, signal,
    ),
};

export const eggWalletApi = {
  player: (displayName: string, signal: AbortSignal) =>
    useAuthStore().request<EggWalletPlayer>("/api/v1/admin/wallet/eggs/player", { display_name: displayName }, undefined, signal),
  grant: (grant: EggGrantRequest, signal?: AbortSignal) =>
    useAuthStore().request<EggGrantReceipt>("/api/v1/admin/wallet/eggs/grant", undefined, grant, signal),
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
